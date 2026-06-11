# Audit Memory & Performa — 2026-06-07 (Final)

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
| 15 | Hapus field redundan dari bridge structs | ✅ |
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

| # | Optimasi | Status |
|---|----------|--------|
| B1 | Fix `clear_library_list_cache()` di async scan | ✅ |
| H1 | Invalidate `renderedPageProvider` saat chapter switch/close | ✅ |
| H2 | CustomPainter page indicator (N widget → 1 painter) | ✅ |
| H3 | `filteredComicChaptersProvider` → sync Provider | ✅ |
| H4 | `Arc<Vec<u8>>` untuk `RenderedPage.bytes` di core | ✅ |
| H5 | Batch query library listing | ✅ |
| H6 | DB lock dipecah per-library saat scan | ✅ |
| H7 | `Arc<Vec<u8>>` di core, clone saat crossing FFI | ✅ |
| M1 | `_pageKeys.clear()` di dispose | ✅ |
| M2 | Guard imageCache mutation (static counter) | ✅ |
| M3 | Early exit di `_pageAtViewportCenter` | ✅ |
| M4 | Batch prefetch lock | ✅ |
| M5 | Cache chapter discovery (60s TTL) | ✅ |
| M6 | Merge triple WalkDir | ✅ |
| M8 | `Mutex` → `RwLock` untuk bridge CORE | ✅ |
| L1 | Invalidate `readerDataProvider` saat switch/close | ✅ |
| L2 | LRU cache max 200 untuk unbounded maps | ✅ |
| L3 | Hapus history+bookmarks dari `_refreshLibrary` | ✅ |
| L4 | Release DB lock sebelum sort | ✅ |
| L5 | `unawaited()` untuk fire-and-forget DB writes | ✅ |
| L6 | History dedup pindah ke SQL | ✅ |

### Fase 4 — Selesai ✅ (Image Memory Deep Audit)

| # | Masalah | Lokasi | Solusi | Status |
|---|---------|--------|--------|--------|
| I1 | `renderedPageProvider` tidak `autoDispose` → Dart memory menumpuk | `reader_state.dart:31` | Tambah `.autoDispose` | ✅ |
| I2 | Bridge deep copy bytes setiap render | `api.rs:403` | FRB limitation — document only | ✅ |
| I3 | Tidak ada explicit cross-chapter eviction di Rust | `image_pipeline.rs:113` | Tambah `evictChapterPages` saat switch chapter | ✅ |
| I4 | `initialReaderPageForProgress` selalu return 0 | `reader_state.dart:78` | Implementasi resume dari `progress.lastPage` | ✅ |
| I5 | Prefetch + evict sequential | `reader_page.dart:461` | Pakai `Future.wait([...])` | ✅ |
| I6 | Reader terlalu bergantung pada `GlobalKey` dan cache Dart per-item | `reader_page.dart` | Semua `PageInfo` + width/height dimuat upfront dari Rust, folder page discovery max depth 3, image dirender lazy oleh `ListView.builder(scrollCacheExtent: 1500)`, `itemExtentBuilder` menjaga resume/jump tanpa build semua page, placeholder tidak menampilkan spinner permanen | ✅ |
| I7 | Prefetch lama bisa lanjut setelah ganti chapter dan mengisi cache lagi; evict kosong belum membuang `PageSource` | `reader_page.dart`, `image_pipeline.rs:113` | Tambah generation guard + chapterId capture, tunggu prefetch aktif sebelum evict final, dan `evictChapterPages(chapterId, [])` membuang raw bytes + page source | ✅ |

---

## Memory Flow Per Page Read

```
Step  Location                              Action
────  ────────────────────────────────────  ──────────────────────────
 1    chapter.rs (zip_image_bytes)          FS/ZIP read → Vec<u8>
 2    image_pipeline.rs:231                 Arc::new(bytes) [wrap]
 3    image_pipeline.rs:240-246             Stored in PageCache [Arc::clone]
 4    image_pipeline.rs:267                 Arc::clone into RenderedPage
 5    api.rs:403                            (*value.bytes).clone() [DEEP COPY]
 6    frb_generated.rs                      Vec<u8> → SSE buffer [COPY]
 7    FFI transfer                          SSE buffer Rust → Dart
 8    frb_generated.dart                    SSE buffer → Uint8List [COPY]
 9    reader_state.dart                     Uint8List held in provider state
10    reader_page.dart:705-710              Image.memory() [DECODE → ui.Image]
11    Flutter imageCache                    Decoded ui.Image cached (64MB cap)
```

### Persistent copies at steady state (page visible)

| Location | What | Size |
|----------|------|------|
| Rust `PageCache` | `Arc<Vec<u8>>` compressed | ~1MB JPEG |
| Dart provider container | `Uint8List` compressed | ~1MB JPEG |
| Flutter `imageCache` | `ui.Image` decoded RGBA | ~10MB (1920×1300×4) |

### Memory lifecycle after fix

```
Load chapter → ambil semua PageInfo
ListView.builder membuat item visible/cacheExtent → render page → Arc clone (cheap) → bridge deep copy → Dart Uint8List → Image.memory
Scroll keluar builder/cacheExtent → provider autoDispose → Dart heap freed
Ganti chapter → cancel queued prefetch + await prefetch aktif lama → invalidate Dart providers + evict raw bytes dan PageSource chapter lama + clear Flutter imageCache
Keluar reader → await prefetch aktif lama → evict raw bytes dan PageSource chapter lama + clear imageCache
```

---

## Ringkasan Total

| Fase | Item | Status |
|------|------|--------|
| Fase 1 | 17 | ✅ |
| Fase 2 | 15 | ✅ |
| Fase 3 | 21 | ✅ |
| Fase 4 | 7 | ✅ |
| **Total** | **60** | ✅ |

---

## Known Limitations (Tidak Bisa Di-Fix)

| Issue | Alasan |
|-------|--------|
| Bridge deep copy bytes (I2) | FRB codegen tidak support `Arc<Vec<u8>>` di bridge DTO. Butuh custom FFI di luar FRB. |
| `imageCache` decoded image ~10MB per halaman | Inherent dari Flutter `Image.memory()`. Tidak bisa dihindari tanpa custom image decoder. |
