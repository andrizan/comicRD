# Audit Memory & Performa — 2026-06-06 (Final)

Audit mendalam terhadap seluruh codebase comicrd_flutter (Rust core, Flutter UI, Bridge layer) untuk optimasi memory dan performa.

---

## Status: Semua Fase Selesai ✅

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
| 12 | Image cache pakai `clear()` saat reader dispose | ✅ |
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

### Fase 3 — Selesai ✅

#### BUG

| # | Masalah | Lokasi | Solusi | Status |
|---|---------|--------|--------|--------|
| B1 | `start_scan_libraries` tidak panggil `clear_library_list_cache()` | `lib.rs:398-420` | Tambah `clear_library_list_cache()` setelah scan | ✅ |

#### HIGH Impact

| # | Masalah | Lokasi | Solusi | Status |
|---|---------|--------|--------|--------|
| H1 | `renderedPageProvider` tidak di-invalidate saat ganti chapter | `reader_state.dart` | Invalidate provider + clear imageCache | ✅ |
| H2 | `_ReferencePageIndicator` buat N widget+tooltip | `reader_page.dart:1140` | Ganti dengan `CustomPainter` | ✅ |
| H3 | `filteredComicChaptersProvider` async → loading flash | `comic_state.dart:20` | Ubah ke sync `Provider` | ✅ |
| H4 | `(*bytes).clone()` deep copy image setiap cache hit | `image_pipeline.rs:267` | `RenderedPage.bytes` pakai `Arc<Vec<u8>>` | ✅ |
| H5 | N query DB individual untuk listing | `library.rs:52-95` | Batch query `WHERE history_key IN (...)` | ✅ |
| H6 | Scan hold DB lock selama scan penuh | `lib.rs:390-396` | Pecah lock per-library | ✅ |
| H7 | `RenderedPage.bytes: Vec<u8>` paksa deep copy via bridge | `bridge/api.rs:165` | `Arc<Vec<u8>>` di core, clone saat crossing FFI | ✅ |

#### MEDIUM Impact

| # | Masalah | Lokasi | Solusi | Status |
|---|---------|--------|--------|--------|
| M1 | `_pageKeys` tidak di-clear di `dispose()` | `reader_page.dart:35` | Tambah `_pageKeys.clear()` di dispose | ✅ |
| M2 | Global `imageCache` mutation race condition | `reader_page.dart:52,60` | Guard dengan static instance counter | ✅ |
| M3 | `_pageAtViewportCenter` iterasi semua page keys | `reader_page.dart:353-381` | Early exit saat distance < 10% viewport | ✅ |
| M4 | `prefetch_pages` lock DB per page | `lib.rs:523-534` | Lock sekali, batch | ✅ |
| M5 | `list_comic_chapters_raw_conn` discover FS setiap kali | `chapter.rs:476` | Cache hasil discovery (60s TTL) | ✅ |
| M6 | Triple WalkDir di chapter discovery | `chapter.rs:368-456` | Merge walk per child dir | ✅ |
| M7 | Prepared statement per archive di listing | `library.rs:122-159` | Ter-cover oleh batch query | ✅ |
| M8 | Global mutex serializes semua bridge call | `bridge/api.rs:6` | `Mutex` → `RwLock` | ✅ |

#### LOW Impact

| # | Masalah | Lokasi | Solusi | Status |
|---|---------|--------|--------|--------|
| L1 | `readerDataProvider` tidak invalidasi saat ganti chapter | `reader_state.dart` | Invalidate saat switch/close | ✅ |
| L2 | Unbounded map growth di 3 notifier | `comic_state.dart`, `scroll_state.dart` | LRU cache max 200 | ✅ |
| L3 | `_refreshLibrary` refresh history+bookmarks tidak perlu | `library_page.dart:371` | Hapus dari refresh | ✅ |
| L4 | DB lock held during sort | `lib.rs:347` | Release lock sebelum sort | ✅ |
| L5 | Fire-and-forget DB writes di settings | `settings_state.dart:116` | Wrap di `unawaited()` | ✅ |
| L6 | History dedup di Dart, harusnya di SQL | `library_state.dart:111` | Pindah ke SQL `GROUP BY` | ✅ |

---

## Ringkasan

| Fase | Item | Status |
|------|------|--------|
| Fase 1 | 17 | ✅ |
| Fase 2 | 15 | ✅ |
| Fase 3 | 22 | ✅ |
| **Total** | **54** | ✅ |

---

## Detail Temuan Kritis

### Image Memory Leak (H1 + H4 + H7)

**Masalah:** `renderedPageProvider` tidak di-invalidate saat keluar reader. `RenderedPage.bytes` di-clone (deep copy) setiap cache hit. Flutter `imageCache` menyimpan decoded image setelah dispose.

**Fix:**
- `Arc<Vec<u8>>` untuk `RenderedPage.bytes` di core (eliminasi deep copy)
- Invalidate `renderedPageProvider` + `clear()` imageCache saat chapter switch/close
- `clear()` di `dispose()` (bukan `clearLiveImages()`)

### Scan DB Lock (H6)

**Masalah:** `scan_libraries_now` hold `Mutex<Connection>` selama scan penuh. Semua operasi DB lain (save_progress, render_page, listing) ter-block.

**Fix:** Pecah lock per-library. FS walk tanpa lock. Lock hanya saat DB transaction.

### Library Listing N+1 Query (H5)

**Masalah:** `comics_from_fs_entries` melakukan 1 SQL query per komik. 500 komik = 500 query.

**Fix:** Batch query `WHERE history_key IN (...)` untuk folder counts dan archive progress.

### Chapter Discovery Cache (M5)

**Masalah:** `list_comic_chapters_raw_conn` walk filesystem setiap kali dipanggil.

**Fix:** Cache hasil discovery di `ComicRdCore` dengan TTL 60 detik. Invalidate saat scan/bookmark/import.
