# Reader Backlog — Satu-satunya Plan Aktif

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Complete tasks in phase order. Do NOT commit unless the user explicitly asks.

**Goal:** Sisa pekerjaan reader yang masih terbuka dan terverifikasi masih berlaku di tree saat ini (2026-09-04). Aturan desain (tiling, pipeline, cache, prefetch) tinggal di `AGENTS.md` — tidak diduplikasi di sini. Riwayat plan yang sudah selesai/diganti ada di git (lihat `git log -- docs/superpowers/plans/`).

Asal tiap seksi: (A)Concurrency Phase 5 yang belum tersentuh; (B) rekomendasi audit RAM 2026-09-03 yang belum diimplementasi, diverifikasi ulang masih ada di kode pada 2026-09-04; (C) gate QA manual yang belum dicentang dari plan tiling/rewrite/decoupled-UI.

---

## Phase A — CBR session temp-extract (belum tersentuh)

Masalah: `rar_image_bytes` (`crates/comicrd_core/src/chapter.rs`) header-scan dari awal arsip per request, dan `get_chapter_pages` full-extract per halaman (trik probe 64KB tidak berlaku — API unrar tidak punya partial read). CBR 200 halaman ≈ 200 decompress penuh saat open + scan O(n) per render. Tidak ada fixture RAR-writer, jadi phase ini test-light.

- [ ] Implement session temp-extract: pada akses halaman pertama chapter rar/cbr, extract image entries SEKALI ke session dir terbatas di bawah app-data temp (pakai urutan `image_entries`), baca probe/read berikutnya dari disk, hapus session saat `evictChapterPages(chapter_id, [])` (sudah dipanggil di close/switch) + sapu orphaned session best-effort saat startup.
- [ ] Batasan: disk-bounded (satu chapter per open reader + cap total session, LRU-hapus tertua); jangan tahan mutex DB selama extraction (aturan AGENTS.md); semantik `PageSource::Archive` untuk zip tidak tersentuh.
- [ ] Uji: test fixture `VERSION_RAR` tetap hijau; tambah unit test lifecycle session (create/reuse/cleanup/evict-all-clears) dengan fake extractor bila perlu; QA manual dengan CBR multi-entry asli (waktu open + scroll + close membersihkan temp).
- [ ] AGENTS.md: perbarui bullet CBR (temp extraction kini ada) dengan lokasi session-dir dan kontrak cleanup.

## Phase B — Tindak lanjut audit RAM (terverifikasi masih berlaku)

### B0 — Serialisasi render tile per chapter (GATED)

- [ ] Kriteria masuk: ukur dulu (release, scratch saja): peak RSS saat 8 thread render tile strip berbeda konkuren vs sekuensial. Lanjut hanya jika puncak bermasalah (>500MB atau dekat OOM di mesin target). Prefetch tetap sekuensial by design; yang belum dibatasi adalah render on-demand konkuren dari `renderedTileProvider` saat scroll cepat (`decode_and_fit` menahan 1 full RGBA strip per miss, mis. 1600×20000 = 128MB transient).
- [ ] Jika masuk: serialkan render tile per chapter di core (pola sequential-prefetch yang sudah ada — mis. mutex per-chapter di sekitar seksi decode/encode, jangan di sekitar cache hit; buktikan tanpa deadlock via liveness test `reader_flow.rs`). JANGAN serialkan cache hit atau DB read.
- [ ] Jika tidak masuk: coret sebagai "measured, no action" dengan angkanya.

### B1 — Overlap 2 chapter saat pindah + evict eksplisit

Masalah (`app_flutter/lib/pages/reader_page.dart`): `dispose` mengandalkan `autoDispose` tanpa invalidate eksplisit; `didUpdateWidget` (jalur `go('/reader/$id')` reuse state) menunda invalidate tile lama ke post-frame sementara chapter baru sudah loading; `_releaseChapterMemory` memegang cache lama selama drain prefetch — jendela lama+baru hidup bareng tiap next/prev.

- [ ] Invalidate eksplisit tile chapter lama di `dispose` (jangan hanya andalkan `autoDispose`) + double-evict (sebelum dan sesudah drain prefetch) di dispose/switch.
- [ ] Uji: `flutter test` hijau; gate manual Impeller di Phase C.

### B2 — Cap `chapter_discovery_cache`

Masalah (`crates/comicrd_core/src/lib.rs:296`): `Mutex<HashMap<...>>` tanpa cap; entry expired (>60s) hanya dianggap miss tanpa `remove`. Browse banyak komik tanpa open = tumbuh terus.

- [ ] Cap LRU 200 (samakan provider Dart lain yang sudah `_maxSize=200`) + prune expired saat akses.
- [ ] Uji: `cargo test -p comicrd_core` hijau + unit test cap/evict.

### B3 — Provider `autoDispose` + `imageCache.maximumSize` + prefetch ganda + bookmark set

- [ ] `FutureProvider.family` berikut masih non-`autoDispose` (terverifikasi 2026-09-04) — jadikan `autoDispose.family`: `comicChaptersProvider`, `chapterBookmarksProvider`, `comicReadingHistoryProvider`, `comicFavoritedProvider` (`comic_state.dart`), `rawLibraryComicsProvider`, `readingHistoryProvider`, `allFavoritesProvider` (`library_state.dart`). (`readerDataProvider`, `renderedTileProvider`, `comicThumbnailProvider` sudah jadi contoh yang benar.)
- [ ] Set `imageCache.maximumSize` (count) di reader — saat ini hanya `maximumSizeBytes` (128MB reader / 100MB luar, `reader_page.dart:241,264`), count default 1000 tidak pernah diset.
- [ ] Hapus satu sisi double prefetch: warm 4 tile di `comic_page.dart:397` vs `_restoreProgress` + `_prefetchWindow` yang prefetch ulang window yang sama setelah navigasi.
- [ ] Clear `_pageBookmarkedPages` saat chapter switch (`didUpdateWidget` me-reset `_currentPage`/`_renderStart` tapi tidak Set ini — chapter baru gagal load bookmark + Set campur antar chapter).
- [ ] Uji: `flutter analyze` + `flutter test` hijau.

## Phase C — Gate QA manual (satu-satunya yang tersisa dari plan lama)

- [ ] Tiling real-app (rebuild `.so` — verifikasi timestamp!): strip 20000px top→bottom (tanpa seam/blank); zoom 0.2/1.0/1.5 mid-strip; resume mid-strip setelah close; bookmark halaman strip; switch chapter mid-strip (tanpa stale tile); prev/next di boundary; scroll sampai END (total exact tidak boleh menghalangi tile bawah).
- [ ] Impeller fast-switch: next/prev chapter 5× cepat → DevTools Memory `ImageCache` count/bytes tidak monoton naik, kolom GPU turun kembali setelah 1–2 frame/GC. RSS OS boleh high-water mark — yang dinilai heap Dart + `ImageCache`, bukan RSS.
- [ ] Desktop smoke: Linux run (folder + CBZ); Windows tanpa proses WebView2 + memori bounded saat scroll chapter panjang; macOS bundle name/icon/support-dir + backup/import.
- [ ] CI: workflow desktop-build hijau di toolchain saat ini.

---

## Verification & close-out

- [ ] Perubahan Rust: `cargo test -p comicrd_core` hijau, zero warnings, `git diff --check` bersih; tidak ada `cargo fmt` borongan.
- [ ] Perubahan Dart: `flutter analyze` + `flutter test` hijau.
- [ ] Scratch pengukuran dihapus; `git status` hanya file yang dimaksud. Timing assert DILARANG di committed tests (flaky) — angka hanya di scratch/manual gate.
- [ ] Checklist plan ini dimutakhirkan seiring pekerjaan mendarat. Commit hanya bila diminta eksplisit.
- [ ] Non-goals: perubahan signature bridge (tanpa regen FRB) kecuali dibutuhkan Phase A (tidak direncanakan); connection pooling; perubahan skema progress/bookmark; pelebaran window prefetch/retensi; JPEG-untuk-PNG.

## Pitfall list (ringkas; detail di AGENTS.md)

1. Tile grid dari Rust saja; gap hanya antar-halaman; zoom tidak pernah re-tile.
2. `Connection: !Sync` — resolve DB row → drop guard → kerja lambat lock-free; jangan pernah tahan mutex DB melintasi IO/decode/encode.
3. LRU cap 16 dihormati di semua jalur baru; evict tetap page-based.
4. Byte-identical pass-through + pixel-exact reassembly adalah guard yang tidak boleh dilonggarkan.
5. RAR session bocor = failure mode Phase A; cleanup di semua path close + startup sweep sebagai backstop.
