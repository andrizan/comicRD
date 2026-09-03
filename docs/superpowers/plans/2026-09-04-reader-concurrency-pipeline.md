# Reader Concurrency & Pipeline Plan (Audit Jilid 2 Follow-up)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Complete tasks in phase order. Do NOT commit unless the user explicitly asks.

**Goal:** Remove the measured stalls in the reader pipeline: DB-mutex contention, repeated full-strip decodes, and (conditionally) slow encoding and RAR overhead — without changing rendered output, cache semantics, or the bridge contract (no FRB regen needed unless structs change; none planned).

**Measured baselines (debug profile, strip JPEG 1600×12000, 8 cores):** single tile render 15–19s (≈2 full decodes at 6.5s each + 1 tile encode at 1.4s; crop 0.24s negligible); `save_progress` 19,339ms during a render vs 0ms idle; 4 concurrent renders 65s wall (≈4× serial, zero parallelism); CBZ 100-entry `get_chapter_pages` 191ms; tile JPEG 1.2–2.1MB. Release shrinks absolutes ~5–20×; ratios, serialization, and stalls persist. Do NOT add timing asserts to committed tests (flaky) — timings below are manual release-profile gates.

---

## Phase 0 — Reproduce measurements (mandatory first)

Context: numbers above came from a deleted scratch test. Re-establish them before changing code so improvements are provable.

- [x] Re-create scratch `crates/comicrd_core/tests/audit_measure.rs` (do NOT commit it): patterned 1600×12000 JPEG strip chapter; cases: single-tile render timing, 4-concurrent vs 4-sequential wall time, `save_progress` latency during a big render vs idle baseline.
- [x] Run `cargo test -p comicrd_core --test audit_measure -- --nocapture`, record numbers as the new baseline in this file (edit the table above).
- [ ] Delete the scratch file before any commit (`git status` must not show it).

---

## Phase 1 — Scope the DB mutex (critical, do first)

Problem: `ComicRdCore::render_page_tile` / `prefetch_tiles` / `get_chapter_pages` hold `self.conn` (DB mutex) across filesystem IO, full image decode, resize, and encode. Everything needing the DB (`save_progress`, history, chapter lists) queues behind image CPU work.

- [x] In `crates/comicrd_core/src/lib.rs`, restructure so the mutex guard never spans slow work:
  - `render_page_tile`: lock → read `chapter_source` (chapter_id → path/type) → **drop guard** → `render_page_tile_conn` takes `&ComicRdCore` (or the needed pieces) instead of `&Connection`. `PageCache` has its own mutex and needs no DB lock.
  - `prefetch_tiles`: same per-iteration (lock → resolve source once per chapter outside the loop if trivially refactorable, else per tile; never hold across `render_page_tile_conn`).
  - `get_chapter_pages`: lock → `chapter_source` → drop → probe dims + tile layout lock-free → re-lock ONLY for the `UPDATE chapters SET page_count` write.
  - Leave fast single-statement writers (`save_progress`, progress/bookmark/favorite/history reads-writes) as-is; they are victims, not culprits.
- [x] Constraints (violating any fails review): `rusqlite::Connection` is `!Sync` — never share it across threads, only shorten guard lifetimes on the calling thread. No connection pool (out of scope). Preserve poison-error mapping (`"db lock poisoned"`). The `UPDATE chapters` write must still run exactly once per `get_chapter_pages`.
- [x] Existing suite green: `cargo test -p comicrd_core` (14 suites), zero warnings, `git diff --check`. No `cargo fmt` (repo not fmt-clean; hand-match style).
- [x] Add a deterministic liveness test (no timing asserts): big-strip tile render on a scoped thread while the main thread runs `save_progress` + `list_reading_history`; assert both succeed (no deadlock, no poison). Generous timeouts only.
- [ ] Manual release gate: `save_progress` p99 < 50ms while a strip prefetch runs (measure via scratch timing, do not commit it).
- [ ] AGENTS.md: append to Cache/Pipeline rules — "never hold the DB (`conn`) mutex across filesystem IO, image decode/resize/encode, or archive scans; resolve DB rows first, drop the guard, then do slow work."

## Phase 2 — Decode once per page-miss (after Phase 1)

Problem: every tile miss decodes the ENTIRE strip; `fit_page_variant` decodes once for the width check and the tile path decodes the fitted bytes again (≈2 decodes + 1 encode per tile; a 10-tile strip pays ~20 decodes).

- [x] In `image_pipeline.rs`, split `fit_page_variant` internals into shared `decode_and_fit` (single decode per page-miss; `fit_page_variant` deleted afterwards as dead, unit tests migrated to `decode_and_fit`). Tile path on miss: decode once → single tile encodes whole (byte-identical to old `fit` output, pinned by unchanged compat tests) → multi tile crops each from the one image and remembers every tile under triple keys (respect cap 16 LRU).
- [ ] Rewrite `get_or_load_tile_bytes` miss path: decode once via the shared helper → single tile: encode whole (must stay byte-identical to `fit_page_variant` output — existing compat test `render_page_tile_returns_raw_image_bytes` + AVIF test lock this) → multi tile: crop each tile from the ONE decoded image, encode, and `remember_bytes` EVERY tile of the page under its triple key (respect the LRU cap of 16; eviction order unchanged).
- [x] Stats semantics (document in code comment + update `tests/cache.rs` expectations if they shift): `page_bytes_loads` +1 per page-miss (not per tile-encoded); `page_bytes_cache_hits` per tile-hit as today. Existing single-tile assertions (`loads==1`, `hits==1`) stay green untouched.
- [x] Unit/integration: one-miss test (`page_bytes_loads` delta == 1 after N tile renders) + wide-page layout unit (`tile_layout_for_dimensions(3000,4000)`); strip reassembly stays the pixel-exact guard (wide stacking shares that proven loop; resize pinned by `decode_and_fit` unit + downscales dims test). Full `cargo test` green.
- [x] Note the accepted trade: first touch of a strip encodes all its tiles up front (one-time transient spike ~10 encodes debug / ~2s release for 20000px); cached after. Prefetch was already sequential, so no new concurrency is introduced.

## Phase 3 — Faster JPEG encode (OPTIONAL, gated)

Entry criteria (do NOT start otherwise): after Phases 1–2, release-profile tile render still encode-bound (encode > 40% of measured tile time on a real strip).

- [x] Swap ONLY the JPEG encode call inside `encode_variant_image` to a faster backend (e.g. SIMD encoder crate), keeping signature, q92-equivalent quality, and PNG path untouched. — DEFERRED: entry criteria need release-profile measurement (manual QA); encode is ~15–20% of tile cost, Amdahl caps gains. Revisit only with profiling data.
- [ ] Gates: existing dims/mime/reassembly tests green; new test asserting encoded tile decodes to within-tolerance pixels of the pre-encode crop (no exact-bytes assert — encoders differ); manual visual spot-check on manga text/lines before/after.
- [ ] If entry criteria are not met, check this phase off as "skipped with reason" and do not add the dependency.

## Phase 4 — Bound transient RAM (measurement-gated)

Problem (structural, unmeasured in release): ~90MB transient per concurrent strip render (77MB RGBA decode + encode buffers); Flutter fires multiple tile providers at once on fast scroll.

- [x] Measure first (release profile, scratch only): peak RSS while 8 threads render distinct strip tiles concurrently vs sequentially. Record numbers here. — DEFERRED: cannot measure release RSS headless; revisit with app profiling. Prefetch path stays sequential by design. Note (Impeller, Flutter 3.47 default): GPU texture dealloc is deferred to frame boundary, so judge fast-switch peaks via DevTools Memory `ImageCache` + GPU column after 1-2 frames/GC, not instant RSS.
- [ ] Only if peak is problematic (>500MB or OOM-adjacent on target machines): serialize tile renders per chapter in core (extend the existing sequential-prefetch pattern — e.g. a per-chapter mutex around the decode/encode section, never around cache hits; prove no deadlock with the Phase 1 liveness test extended to mixed render+prefetch concurrency). Do NOT serialize cache hits or DB reads.
- [ ] If measurement is fine, check off as "measured, no action" with the numbers.

## Phase 5 — RAR path (code-evident, needs real CBR for QA)

Problem: `rar_image_bytes` header-scans from the archive start per request, and `get_chapter_pages` full-extracts per page (the 64KB probe trick cannot apply — unrar API has no partial reads). 200-page CBR ≈ 200 full decompressions at open + O(n) scan per render. No RAR-writer fixture exists, so this phase is test-light by necessity.

- [ ] Implement session temp-extract: on first page access of a rar/cbr chapter, extract image entries ONCE into a bounded session dir under app-data temp (reuse `image_entries` order), serve subsequent reads/probes from disk, delete the session on `evictChapterPages(chapter_id, [])` (already called on close/switch) + best-effort startup sweep of orphaned sessions.
- [ ] Constraints: disk-bounded (one chapter at a time per open reader + cap total sessions, LRU-delete oldest); never block the DB mutex during extraction (Phase 1 rule); keep `PageSource::Archive` semantics for zip untouched.
- [ ] Tests: existing `VERSION_RAR` fixture tests keep passing; add unit tests for session lifecycle (create/reuse/cleanup/evict-all-clears) with a fake extractor if needed; manual QA with a real multi-entry CBR (open time + scroll + close cleans temp).
- [ ] AGENTS.md: update the CBR bullet (temp extraction now exists) with the session-dir location and cleanup contract.

---

## Verification & close-out (all phases)

- [ ] `cargo test -p comicrd_core` 14 suites green, zero warnings; `flutter analyze` + `flutter test` green (Dart untouched, but run once at the end); `git diff --check` clean; no `cargo fmt` wholesale.
- [ ] Scratch measurement files deleted; `git status` shows only intended files.
- [ ] Plan checklist updated as work lands (this file). Commit only when explicitly asked.
- [ ] Known non-goals (do not sneak in): bridge signature changes (no FRB regen), connection pooling, FIR-style SIMD unless Phase 3 gates pass, progress/bookmark schema changes, `fast_image_resize` (measured 0% effect on this pipeline — tiling path performs no resize; revisit only with profiling data showing resize as hotspot).

## Pitfall list (read before coding)

1. `Connection: !Sync` — shortening guard lifetimes is the entire Phase 1; sharing `&Connection` across threads won't compile, working around it with `unsafe` or a pool is forbidden here.
2. Re-locking for the `UPDATE chapters` write: forgetting it silently breaks `page_count`; double-locking in one call path deadlocks (Mutex, not reentrant) — draw the lock scopes before coding.
3. Flaky timing asserts in committed tests — timings live in scratch/manual gates only.
4. Caching all tiles on miss must respect the 16-entry LRU cap; a 20000px strip (10 tiles) must not evict the neighboring pages' window — verify with the evict test pattern from the tiling plan.
5. Byte-identical single-tile output is load-bearing (compat tests) — any refactor of `fit_page_variant`/`encode_variant_image` must keep those tests green without touching their expectations.
6. RAR session cleanup on every close path (close, switch, evict-all, failed open) — leaked temp dirs are the failure mode; startup sweep is the backstop, not the plan.
