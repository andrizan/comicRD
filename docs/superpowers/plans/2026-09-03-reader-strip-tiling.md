# Reader Strip Tiling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Complete tasks in phase order; do not skip Phase 0.

**Goal:** Render tall webtoon strips (e.g. 1600×20000) as stacked tiles (max 2048px tall each) instead of one giant GPU texture, without seams, without changing reading progress semantics, and without regressing normal pages.

**Why:** A 1600×30000 strip decodes to ~192MB RGBA in a single texture. That thrashes the 128MB Dart image cache, risks exceeding GPU max texture size (~16384px, 8192px on older GPUs → blank pages), and was the original driver of GPU 99% in reader mode. Width capping (commit `422d832`) fixed wide monsters but deliberately leaves tall strips untouched — tiling is the second half.

**Non-goals:** Horizontal/paged reading mode, RTL layout (reader is vertical-only, direction-independent), PDF/EPUB/CB7 support, changing the progress/bookmark DB schema.

---

## Key Design Decisions (do not deviate without updating this plan)

1. **Rust is the single source of truth for tile layout.** `PageInfo` gains `tile_heights: Vec<u32>` (fitted pixel heights per tile, top-to-bottom). Flutter never computes tile splits itself. Rationale: Rust computes fitted height with `f32` (`(h * 2048.0 / w).round()`); Dart uses `double` and could round boundary values differently → off-by-one rows → visible seams or gaps. A `u32` list has zero parity risk.
2. **Fitted width stays computable on both sides, so it is NOT sent** (bridge minimization rule): `fitted_w = min(original_w, 2048)`. Pure integer op, exact parity. GIF rule also stays Rust-only: Rust emits a single tile for GIFs (animation preserved); Flutter just trusts `tile_heights`.
3. **Tiles split on exact pixel boundaries, zero overlap, zero inter-tile gap.** `pageGap` applies ONLY after the last tile of a page. Any gap/padding between tiles of one page = visible seam = bug.
4. **Tile pixel grid is fixed at list time; zoom never re-tiles.** Zoom only changes Dart-side display scale (`displayWidth / fitted_w` applied to tile heights), exactly like today. If zoom ever triggers re-tiling, the plan is violated.
5. **Progress/bookmarks/indicator stay PAGE-based.** Backend schema unchanged. Every tile maps to exactly one page (`tile → page` is O(1) via stored index, never a search). `lastPage`, `initialPage`, bookmarks, indicator text all keep page semantics.
6. **One tile = one `ListView` item** (flattened), NOT a `Column` of tiles per page item. A `Column` would eagerly build/decode every tile of any visible page and defeat the memory goal. Flattening keeps `ListView.builder` laziness per tile.
7. **Old whole-page path is fully replaced, not kept alongside.** After migration, `render_page_variant` / `RenderPagePayload` / `prefetch_pages` / `PrefetchPagesPayload` become dead and MUST be removed (repo rule: remove dead bridge functions promptly). Tile 0 of a single-tile page renders byte-comparable output to the old path (lock with a compat test).
8. **Tile size cap `TILE_MAX_HEIGHT = 2048`.** Safe on 8192-limited GPUs (max tile texture 2048×2048×4 = 16MB), matches `MAX_VARIANT_WIDTH`, keeps prefetch granularity small.

---

## Phase 0 — Toolchain (MUST be first; incident-driven)

Context: on 2026-09-03 the tree was silently downgraded FRB 2.13.0 → 2.12.0 because the locally installed codegen (2.12.0, from June) was run against a 2.13.0 project. Regenerating with the wrong codegen re-stamps every generated file and re-downgrades the project.

- [x] Run `flutter_rust_bridge_codegen --version` and compare against `flutter_rust_bridge` in `app_flutter/pubspec.yaml` + `crates/comicrd_bridge/Cargo.toml`. They must match EXACTLY before any regen in Phase 2.
- [x] If mismatched, upgrade the tool (not the project): `cargo install flutter_rust_bridge_codegen --version =<project-version> --locked`.
- [x] Verify: `git status --short` shows NO version-file changes after regen (stamps in `frb_generated.*` must read the project version).

---

## Phase 1 — Rust core: tile layout + tile rendering

Files: `crates/comicrd_core/src/image_pipeline.rs`, `crates/comicrd_core/src/chapter.rs`, `crates/comicrd_core/src/lib.rs`.

- [x] Add `const TILE_MAX_HEIGHT: u32 = 2048` in `image_pipeline.rs`.
- [x] Add `pub(crate) fn tile_layout_for_dimensions(width: u32, height: u32, is_gif: bool) -> (u32, Vec<u32>)` returning `(fitted_width, tile_heights)`:
  - `fitted_w = min(width, 2048)`; `fitted_h = width > 2048 ? (height as f32 * 2048.0 / width as f32).round() as u32 : height`.
  - `is_gif || fitted_h == 0` → `(fitted_w, vec![fitted_h])` (single tile; `fitted_h == 0` guards corrupt headers, tile 0 renders the error path as today).
  - Else split `fitted_h` into chunks of `TILE_MAX_HEIGHT` (last chunk = remainder, never zero-length; exact `TILE_MAX_HEIGHT` multiple → no empty trailing tile).
  - `is_gif` comes from the same extension check used for mime (`ext_eq(name, "gif")`, case-insensitive).
- [x] Use the helper in `get_chapter_pages_conn` (`chapter.rs`, BOTH folder and archive branches): fill new `PageInfo.tile_heights`. Core `PageInfo` struct gains `tile_heights: Vec<u32>`. Folder branch: `is_gif` from file extension. Archive branch: `is_gif` from entry name extension.
- [x] Add `get_or_load_tile_bytes(conn, cache, chapter_id, page_index, tile_index) -> Result<(Arc<Vec<u8>>, &'static str), String>:
  - Load source + read page bytes (existing helpers, unchanged).
  - `fit` width exactly as today (CatmullRom, PNG→PNG lossless, else JPEG q92, GIF passthrough).
  - Compute layout with `tile_layout_for_dimensions(decoded_w, decoded_h, mime == "image/gif")`. If `tile_index >= layout.len()` → `Err("tile index out of range")`.
  - If single tile → return fitted bytes as-is (MUST equal old `render_page_variant` output for the same page — compat test locks this).
  - Else decode fitted bytes, crop rows `[tile_index*2048, min(start+2048, fitted_h))`, encode with the same PNG/JPEG rule, return.
  - Defensive fallback: if decoded dims differ from header dims used at list time (corrupt/odd files), tile 0 returns the whole fitted image and other indices error (never panic, never return wrong rows).
- [x] Change `PageCache` bytes key `(i64, usize)` → `(i64, usize, usize)` = (chapter, page, tile). Update `touch_bytes`, `remember_bytes`, `evict_except` (evict by PAGE: drop all triples whose page ∉ `keep_pages`; `keep_pages.is_empty()` still drops the page source too). Raise `PAGE_BYTES_CACHE_CAP` 6 → 16 (a tile is ≤16MB decoded / ~0.1–3MB encoded; document the bound in a comment).
- [x] Replace `prefetch_pages` body in `lib.rs` with `prefetch_tiles(payload: PrefetchTilesPayload { chapter_id, tiles: Vec<PageTile{page_index: usize, tile_index: usize}> })`, same sequential loop pattern (sequential bounds transient decode memory — do NOT parallelize).
- [x] Keep `render_page_variant` / `evict_chapter_pages` signatures working until Phase 3 migrates Flutter; mark with `// TODO(phase-3): remove after tile migration`.
- [x] Unit tests (`image_pipeline.rs::tests`): exact-2048 → 1 tile; 2049 → `[2048, 1]`; 20000-wide-1600 → 10 tiles `[2048×9, 1568]`... (compute: 20000 = 9×2048+1568 ✓); wide 3000×4000 → fitted 2048 wide, tiles of scaled height; GIF any-size → single tile; `(0,0)` → single tile, no panic; tile heights sum == fitted_h (property test over several sizes).
- [x] Unit tests (`chapter.rs::tests`): `tile_layout_for_dimensions` parity cases incl. GIF-by-extension, zero dims.
- [x] Verify: `cargo test -p comicrd_core` all green, zero warnings, `git diff --check` clean. Do NOT run `cargo fmt` (repo is not fmt-clean; hand-match surrounding style).

## Phase 2 — Bridge + facade

Files: `crates/comicrd_bridge/src/api.rs`, `crates/comicrd_core/src/lib.rs` (public types), `app_flutter/lib/api/comicrd_api.dart`, regen outputs.

- [x] Core: `PageInfo` += `tile_heights: Vec<u32>`; add `PageTile { page_index, tile_index }` (usize, Serialize/Deserialize like siblings); add `PrefetchTilesPayload { chapter_id: i64, tiles: Vec<PageTile> }`; add `RenderPageTilePayload { chapter_id: i64, page_index: usize, tile_index: usize }`.
- [x] Bridge (`api.rs`): mirror structs (`tileHeights: List<int>` — `Vec<u32>` precedent exists via `PageInfo.index`); add `render_page_tile`, `prefetch_tiles`; add `From` impls following existing ones.
- [x] Facade (`comicrd_api.dart`): add `renderPageTile` + `prefetchTiles`; keep old methods until Phase 3 (mark `// TODO(phase-3)`).
- [x] Regen from repo root: `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` (ONLY after Phase 0 passes). Sanity: generated stamps read the project FRB version; `git diff --stat` shows no version-file churn.
- [x] Verify: `cargo test -p comicrd_core` + `flutter analyze` clean.

## Phase 3 — Flutter: flattened tile list

Files: `app_flutter/lib/state/reader_state.dart`, `app_flutter/lib/pages/reader_page.dart`, `app_flutter/test/reader_tiles_test.dart` (new), extend `app_flutter/test/reader_page_test.dart`.

- [x] `reader_state.dart`: add `TileRef { pageIndex, tileIndex }` + `renderedTileProvider = FutureProvider.autoDispose.family<RenderedPage, TileRequest(chapterId, pageIndex, tileIndex)>` (equality/hash like `RenderedPageRequest`). Keep old provider until cutover, then remove.
- [x] Build memoized tile list per `ReaderData`: `List<TileItem(pageIndex, tileIndex, isLastTileOfPage)>` by expanding each page's `tile_heights`. Pure helper `flattenTiles(pages)`, unit-tested (counts, order, flags, `tile→page` identity).
- [x] `ListView.builder`: `itemCount = tiles.length`. `itemExtentBuilder` returns display height of tile `i` = `tilePixelHeight * displayWidth(fitted_w) / fitted_w` (+ `pageGap` ONLY if `isLastTileOfPage`). `itemBuilder` wraps `_ReaderPageItem` (+ new `tileIndex` param, `ValueKey('p{page}t{tile}')`) with `Padding(bottom: isLast ? pageGap : 0)`.
- [x] Rewrite scroll math to tile space, keeping page wrappers for backend calls:
  - `_tileForOffset`, `_visibleTileRange`, `_scrollOffsetForTile` (mirror existing offset-walk logic; tile heights replace page heights; gap only after last tile of page).
  - `_currentPage` (int, page-based, saved to backend) derives from center tile's `pageIndex`. `_updateViewportWindow` notifies overlay only when PAGE changes (as today); prefetch window = visible tiles ±2 tiles.
  - `_jumpToPage` → offset of first tile of page. `_restoreProgress` → same via page→tile. Prev/next page buttons + keyboard: first tile of adjacent page. Auto-advance/unlimited-scroll checks map center/first/last tile → page.
- [x] `_prefetchWindow(tiles)`: build `PageTile` list for window, `evictChapterPages(keep_pages: unique pages in window)` (unchanged bridge call ✓), `prefetchTiles(...)`. Keep generation guard + queue pattern as-is.
- [x] `_invalidateRenderedPages`: iterate all tiles via `tile_heights` (not pages). Confirm invalidation covers chapter switch/close/dispose paths (generation guard already exists — tile providers must be inside its protection; verify by reading `_releaseChapterMemory`).
- [x] `_ReaderPageItem`: watch `renderedTileProvider`; keep `RepaintBoundary` (now per tile — even better isolation); placeholder `AspectRatio` uses tile aspect `fitted_w / tile_h` (stable extents preserved).
- [x] Cutover + delete: remove `renderedPageProvider`/`RenderedPageRequest`, old `renderPageVariant`/`prefetchPages` facade methods, core `render_page_variant`/`RenderPagePayload`/`prefetch_pages`/`PrefetchPagesPayload` + bridge mirrors; regen; `flutter analyze` clean.
- [x] Dart unit tests (`reader_tiles_test.dart`): flatten mapping incl. multi-tile pages; gap-on-last-tile-only; `tile→page` for progress mapping; **zoom-invariance**. (Offset math is covered via widget navigation tests rather than a standalone brute-force unit, since it needs a live `ScrollController` + `MediaQuery`.)
- [x] Widget tests: strip chapter renders N tile items with zero inter-tile gap; progress save still sends page indices; next/prev page jump lands on first tile; mid-strip resume restores offset.
- [x] Verify: `flutter analyze`, `flutter test` all green, `dart format` clean on touched files.

## Phase 4 — Correctness + perf lockdown (bug-proofing)

- [x] Rust integration test (new in `tests/image_pipeline.rs`): build a 1600×5000 PNG strip chapter → render ALL tiles → decode + vertically stack → assert **pixel-exact** equality with the fitted whole image (no seam / overlap / missing row). This is the single most important test of the plan.
- [x] Compat test: tile 0 of a single-tile page renders bytes identical to pre-tiling behavior (small PNG passthrough).
- [x] Cache tests: extend `tests/cache.rs` pattern — render tile twice → bytes equal + `page_bytes_cache_hits` increments; evict with `keep_pages` drops sibling tiles of evicted pages, keeps window tiles.
- [x] Bound test: assert every emitted tile's decoded size ≤ 2048×2048×4 (16MB) for a mixed chapter (strip + spread + normal).
- [ ] Manual QA checklist (real app, rebuilt `.so` — verify timestamp!): 20000px strip top→bottom (no seams, no blanks); zoom 0.2/1.0/1.5 mid-strip; resume mid-strip after close; bookmark a strip page; chapter switch mid-strip (no stale tiles); prev/next chapter at boundaries; observe RAM/GPU vs pre-tiling build.

## Follow-up: Scrollbar Exact Total (post-plan fix)

Symptom: scrollbar thumb teleported ±10–40k px while content scrolled smoothly (also on single-tile chapters). Proven via scroll telemetry: all delegate inputs constant (zoom/gap/width/pages/tiles) while `maxScrollExtent` flip-flopped.

Root cause: `SliverVariedExtentList` only lays out children near the viewport; `SliverChildBuilderDelegate.estimateMaxScrollOffset` returns null, so the total falls back to `_extrapolateMaxScrollOffset` (average of laid-out children × remaining). The average changes every frame → eternal wobble. Verified in framework source (`rendering/sliver_fixed_extent_list.dart`, `widgets/sliver.dart`, `widgets/scroll_delegate.dart`).

Fix: `_ExactTotalChildDelegate` (overrides `estimateMaxScrollOffset` with the precomputed exact total, same single-source-of-truth extent fn) + `_ExactTotalSliverList` (`SliverMultiBoxAdaptorWidget` twin creating `RenderSliverVariedExtentList`), hosted in a `CustomScrollView` + `SliverPadding` with identical defaults to the old `ListView.builder` (laziness, keep-alives, repaint boundaries, semantics, cache extent). Locked by widget test `scroll extent stays stable while scrolling` + `AGENTS.md` rule above. Manual QA must include scrolling to the very END (an underestimated total would block reaching bottom tiles).
- [x] Docs: update `AGENTS.md` Reader Image Pipeline section (tile policy, `TILE_MAX_HEIGHT`, gap rule, zoom rule) + check off this plan file. Commit only when explicitly asked (repo rule).

---

## Pitfall List (read before coding)

1. Inter-tile gap/padding (even 1px) = visible seam. Audit every `EdgeInsets`/`SizedBox` in the tile item path.
2. Float math for tile boundaries anywhere in Dart = off-by-one rows eventually. Tile splits come from Rust `u32`s only.
3. Re-tiling on zoom, or keying tile cache by zoom = cache explosion + reload flashes. Tile grid is zoom-independent.
4. Changing progress/bookmark schema to tiles = backend churn + migration risk. Pages stay the unit of progress. (A 20000px strip is one "page" of progress — accepted, matches today.)
5. Tiling GIFs = breaking animation. Rust single-tiles them; Flutter must not second-guess.
6. Forgetting a tile in `_invalidateRenderedPages` = stale tiles after chapter switch (the exact bug class fixed in audit item H1).
7. Regen with wrong codegen version = silent project-wide downgrade (Phase 0 exists because this happened on 2026-09-03).
8. Parallel tile decodes of one giant strip = transient RAM spikes (full-strip RGBA per concurrent decode). Prefetch stays sequential; do not "optimize" with concurrent tile renders.
9. `itemExtentBuilder` returning null/wrong for tile indices = jump/resume breakage (same bug class as audit item I6 — keep extents stable and deterministic).
10. Removing bridge functions without regen + facade cleanup = compile break across three crates. Cutover is atomic within Phase 3.
