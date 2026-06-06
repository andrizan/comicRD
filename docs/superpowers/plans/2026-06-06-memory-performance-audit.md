# Audit Memory & Performa — 2026-06-06 (Final)

Audit mendalam terhadap seluruh codebase comicrd_flutter (Rust core, Flutter UI, Bridge layer) untuk optimasi memory dan performa.

---

## Status: Fase 1-2 Selesai, Fase 3 Pending

### Fase 1 — Selesai ✅

| # | Optimasi | Status |
|---|----------|--------|
| 1 | Arc untuk cache bytes (`image_pipeline.rs`) | ✅ |
| 2 | IndexedStack → switch conditional rendering | ✅ |
| 3 | Hapus `.sublist()` — pass items + visibleCount | ✅ |
| 4 | Debounce search 300ms (library_page) | ✅ |
| 5 | Hapus `RawComic.key` redundan | ✅ |
| 6 | Hapus `RawComic.library_path` per-item | ✅ |
| 7 | Hapus dead code `list_comics()` / `Comic` dari bridge | ✅ |
| 8 | Pre-allocation `Vec::with_capacity` | ✅ |
| 9 | Batch chapter query (N+1 → 1 query) | ✅ |
| 10 | Provider invalidation pindah ke reader close | ✅ |
| 11 | Hapus `clearLiveImages()` setiap 2 halaman | ✅ |
| 12 | Image cache pakai `clearLiveImages()` bukan `clear()` | ✅ |
| 13 | Scroll offset throttle 200ms (library_page) | ✅ |
| 14 | Hapus `renderPagePreview` dari bridge | ✅ |
| 15 | Hapus `SettingEntry.updated_at`, `RenderedPage.cache_key`, `ReadingProgress.updated_at` dari bridge | ✅ |
| 16 | Arc untuk `PageSource` | ✅ |
| 17 | Label count sesuai tab aktif | ✅ |

### Fase 2 — Selesai ✅

| # | Optimasi | Status |
|---|----------|--------|
| 18 | Hapus `clear_library_list_cache()` dari `save_progress()` | ✅ |
| 19 | Fix double `setQuery()` + debounce 300ms di comic_page | ✅ |
| 20 | Hapus `RenderedPage.cache_key` dari core | ✅ |
| 21 | Hapus `SettingEntry.updated_at` dari core + DB | ✅ |
| 22 | Hapus `ReadingProgress.updated_at` dari core + DB | ✅ |
| 23 | `Arc<Vec<PathBuf>>` untuk library cache entries | ✅ |
| 24 | Hapus dead code `_ReaderToolbar` + 3 helpers (~345 baris) | ✅ |
| 25 | Hapus `Comic` struct + `list_comics()` + `list_comics_conn()` dari core | ✅ |
| 26 | Hapus `render_page_preview()` dari core | ✅ |
| 27 | Test reorganization (24 → 40 test) | ✅ |
| 28 | Update AGENTS.md dengan rules | ✅ |
| 29 | Fix scroll position validation (clamp + post-frame) | ✅ |
| 30 | Fix reader scroll performance (`_pageAtViewportCenter`) | ✅ |
| 31 | Chapter count label di chapter page + reader page | ✅ |
| 32 | i18n untuk chapter count label | ✅ |

---

### Fase 3 — Pending

#### BUG

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| B1 | `start_scan_libraries` tidak panggil `clear_library_list_cache()` → stale listing setelah async scan | `lib.rs:398-420` | Tambah `clear_library_list_cache()` setelah scan selesai |

#### HIGH Impact

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| H1 | `renderedPageProvider` tidak di-invalidate saat ganti chapter → image bytes menumpuk | `reader_state.dart` | Invalidate provider chapter lama saat switch/close |
| H2 | `_ReferencePageIndicator` buat N widget+tooltip (500 page = 500 tooltip) | `reader_page.dart:1140` | Ganti dengan `CustomPainter` atau `Slider` |
| H3 | `filteredComicChaptersProvider` async → loading flash setiap filter berubah | `comic_state.dart:20` | Ubah ke sync `Provider` seperti library |
| H4 | `(*bytes).clone()` deep copy image setiap cache hit | `image_pipeline.rs:267` | `RenderedPage.bytes` harus `Arc<Vec<u8>>` |
| H5 | N query DB individual untuk listing (1 per komik) | `library.rs:52-95` | Batch query `WHERE history_key IN (...)` |
| H6 | Scan hold DB lock selama scan penuh, block semua operasi | `lib.rs:390-396` | Pecah lock per-library atau pakai connection terpisah |
| H7 | `RenderedPage.bytes: Vec<u8>` paksa deep copy via bridge | `bridge/api.rs:165` | Ubah ke `Arc<Vec<u8>>` di core, clone saat crossing FFI |

#### MEDIUM Impact

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| M1 | `_pageKeys` tidak di-clear di `dispose()` | `reader_page.dart:35` | Tambah `_pageKeys.clear()` di dispose |
| M2 | Global `imageCache` mutation race condition saat route transition | `reader_page.dart:52,60` | Pakai refcount atau guard |
| M3 | `_pageAtViewportCenter` iterasi semua page keys | `reader_page.dart:353-381` | Binary search atau check page dekat viewport saja |
| M4 | `prefetch_pages` lock DB per page | `lib.rs:523-534` | Lock sekali, batch |
| M5 | `list_comic_chapters_raw_conn` discover FS setiap kali | `chapter.rs:476` | Cache hasil discovery |
| M6 | Triple WalkDir di chapter discovery | `chapter.rs:368-456` | Merge walk |
| M7 | Prepared statement per archive di listing | `library.rs:122-159` | Prepare sekali, reuse |
| M8 | Global mutex serializes semua bridge call | `bridge/api.rs:6` | Pakai `RwLock` |

#### LOW Impact

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| L1 | `readerDataProvider` tidak invalidasi saat ganti chapter | `reader_state.dart` | Invalidate saat switch |
| L2 | Unbounded map growth di `comicPreferencesProvider`, `lastOpenedChapterProvider`, `scrollOffsetsProvider` | `comic_state.dart`, `scroll_state.dart` | LRU cache max 200 |
| L3 | `_refreshLibrary` refresh history+bookmarks padahal tidak perlu | `library_page.dart:371` | Hapus dari refresh |
| L4 | DB lock held during sort | `lib.rs:347` | Release lock sebelum sort |
| L5 | Fire-and-forget DB writes di settings | `settings_state.dart:116` | Wrap di `unawaited()` |
| L6 | History dedup di Dart, harusnya di SQL | `library_state.dart:111` | Pakai `GROUP BY` di Rust |

---

## Ringkasan

| Fase | Item | Status |
|------|------|--------|
| Fase 1 | 17 | ✅ |
| Fase 2 | 15 | ✅ |
| Fase 3 | 17 | ⏳ Pending |
| **Total** | **49** | |

---

## Rekomendasi Eksekusi Fase 3 (urutan ROI)

1. **B1** — Fix bug async scan cache (1 baris, immediate fix)
2. **H1** — Invalidate renderedPageProvider saat chapter switch (memory leak)
3. **H3** — Sync filteredComicChaptersProvider (UX fix, loading flash)
4. **M1** — Clear _pageKeys di dispose (defensive cleanup)
5. **H5** — Batch query library listing (performance)
6. **H4+H7** — Arc untuk RenderedPage.bytes (memory + performance)
7. **H2** — CustomPainter page indicator (widget count)
8. **M4** — Batch prefetch lock (lock contention)
9. **M5** — Cache chapter discovery (FS walk)
