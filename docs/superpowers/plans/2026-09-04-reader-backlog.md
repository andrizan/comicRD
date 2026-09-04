# Reader Backlog — Satu-satunya Plan Aktif

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Complete tasks in phase order. Do NOT commit unless the user explicitly asks.

**Goal:** Sisa pekerjaan reader yang masih terbuka, dengan standar ketat: hanya percepatan murni, correctness fix tanpa biaya kecepatan, dan gate QA. Item yang berbau trade-off kecepatan-demi-memori sengaja TIDAK dikerjakan (daftar + alasan di bawah). Aturan desain (tiling, pipeline, cache, prefetch) tinggal di `AGENTS.md` — tidak diduplikasi di sini. Riwayat plan yang sudah selesai/diganti ada di git (lihat `git log -- docs/superpowers/plans/`).

Asal tiap seksi: (A) Concurrency Phase 5 yang belum tersentuh; (B) bug correctness dari audit RAM 2026-09-03; (C) gate QA manual dari plan lama. Keputusan ruang lingkup 2026-09-04: B0/B1/B2 dan 3 bullet B3 non-correctness dicoret (lihat "Sengaja tidak dikerjakan").

---

## Phase A — CBR session temp-extract (belum tersentuh)

Masalah: `rar_image_bytes` (`crates/comicrd_core/src/chapter.rs`) header-scan dari awal arsip per request, dan `get_chapter_pages` full-extract per halaman (trik probe 64KB tidak berlaku — API unrar tidak punya partial read). CBR 200 halaman ≈ 200 decompress penuh saat open + scan O(n) per render. Tidak ada fixture RAR-writer, jadi phase ini test-light.

- [x] Implement session temp-extract: pada akses halaman pertama chapter rar/cbr, extract image entries SEKALI ke session dir terbatas di bawah app-data temp (pakai urutan `image_entries`), baca probe/read berikutnya dari disk, hapus session saat `evictChapterPages(chapter_id, [])` (sudah dipanggil di close/switch) + sapu orphaned session best-effort saat startup. — DONE 2026-09-04: `ensure_rar_session` (`image_pipeline.rs`) + `build_rar_session_page_list` (`chapter.rs`); session `<app-data>/rar-sessions/chapter-<id>`; `PageSource::RarSession`; zip/cbz/folder tidak tersentuh; thumbnail cover tetap on-demand (di luar ruang lingkup).
- [x] Batasan: disk-bounded (satu chapter per open reader + cap total session, LRU-hapus tertua); jangan tahan mutex DB selama extraction (aturan AGENTS.md); semantik `PageSource::Archive` untuk zip tidak tersentuh. — DONE: session mengikuti LRU page-source yang sudah ada (cap 2 → maks 2 session hidup); semua IO ekstraksi di luar lock cache maupun DB; zip tetap varian `Archive`.
- [x] Uji: test fixture `VERSION_RAR` tetap hijau; tambah unit test lifecycle session (create/reuse/cleanup/evict-all-clears) dengan fake extractor bila perlu; QA manual dengan CBR multi-entry asli (waktu open + scroll + close membersihkan temp). — DONE tanpa QA manual CBR asli (headless): unit test `session_file_name` + `extract_rar_session` fake-extractor (order/isi/error-cleanup) + integration `tests/rar_session.rs` (create → evict-all → re-extract, partial-evict bertahan). QA CBR multi-entry pindah ke Phase C.
- [x] AGENTS.md: perbarui bullet CBR (temp extraction kini ada) dengan lokasi session-dir dan kontrak cleanup. — DONE.

## Phase B — Correctness fix tanpa biaya kecepatan

- [x] Clear `_pageBookmarkedPages` saat chapter switch (`didUpdateWidget` di `app_flutter/lib/pages/reader_page.dart` me-reset `_currentPage`/`_renderStart` tapi tidak Set ini — chapter baru gagal load bookmark karena guard `isEmpty` + Set campur antar chapter). Murni correctness: tanpa decode/encode/IO tambahan. — DONE 2026-09-04: satu baris `clear()` di blok reset `didUpdateWidget`.
- [x] Uji: `flutter analyze` + `flutter test` hijau. — DONE (analyze bersih, `reader_page_test.dart` 13/13 hijau).

## Sengaja tidak dikerjakan (keputusan 2026-09-04)

Item di bawah terverifikasi masih ada di kode, tetapi dicoret karena menukar kecepatan dengan batas memori (premi steady-state kecil, kecuali B0 yang riil). Tidak dikerjakan kecuali keluhan "RAM monoton naik" kembali dengan data pengukuran.

- B0 serialisasi render per chapter: satu-satunya trade-off kecepatan yang riil (tile konkuren jadi antre). Coret penuh, bukan gated.
- B1 double-evict + invalidate eksplisit: HashMap-remove/invalidate murah, tetapi manfaatnya hanya jendela transient switch — tidak mempercepat apa pun.
- B2 cap `chapter_discovery_cache`: re-walk saat revisit entry ter-evict adalah pelambatan (kecil) demi batas memori.
- B3 `autoDispose.family` 7 provider: kunjungan ulang membayar re-fetch DB demi melepas state.
- B3 `imageCache.maximumSize`: skenario terburuk memaksa re-decode `Image.memory`.
- B3 hapus satu sisi double prefetch: penghematan hanya hit-check murah; risiko menyentuh jalur warm-start yang sudah benar tidak sepadan.

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
