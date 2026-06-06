# Audit Memory & Performa — 2026-06-06 (Updated)

Audit mendalam terhadap seluruh codebase comicrd_flutter (Rust core, Flutter UI, Bridge layer) untuk optimasi memory dan performa.

---

## Status: Fase 1 Selesai, Fase 2 Pending

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

---

### Fase 2 — Pending

#### HIGH Impact (baru ditemukan)

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| H1 | `save_progress()` clear library_list_cache padahal progress tidak mengubah FS | `lib.rs:528` | Hapus `clear_library_list_cache()` dari `save_progress()` |
| H2 | Double `setQuery()` di comic_page — listener + onChanged keduanya fire | `comic_page.dart:41-45,129` | Hapus listener, pakai onChanged + debounce |

#### NEW Issues (dari perubahan fase 1)

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| N1 | `RenderedPage.cache_key` masih di-compute di core (wasted alloc) | `image_pipeline.rs:266` | Hapus field dari core struct |
| N2 | `SettingEntry.updated_at` masih di-query dari DB | `database.rs:249` | Hapus dari SELECT |
| N3 | `ReadingProgress.updated_at` masih di-query dari DB | `reader.rs:42` | Hapus dari SELECT |
| N4 | Library cache clone `Vec<PathBuf>` di setiap access | `lib.rs:359` | Pakai `Arc<Vec<PathBuf>>` |

#### MEDIUM Impact (sisa)

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| M1 | Dead code: `_ReaderToolbar` + 3 helper widget (~460 baris) | `reader_page.dart:1082-1542` | Hapus |
| M2 | `Comic` struct + `list_comics()` + `list_comics_conn()` masih di core | `lib.rs:58-69`, `library.rs:350-407` | Hapus atau mark `#[cfg(test)]` |
| M4 | `pub use comicrd_core::*` leak internal types | `bridge/lib.rs:4` | Hapus |
| R1 | DB Mutex contention setiap bridge call | `lib.rs:252` | Pertimbangkan `RwLock` |
| R2 | `prefetch_pages` hold lock across loop | `lib.rs:559-570` | Batch source lookup sekali |
| R3 | `zip_image_bytes` buka archive ulang per page | `chapter.rs:259` | Cache `ZipArchive` handle |

#### LOW Impact

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| M3 | `render_page_preview()` dead di core | `lib.rs:548` | Hapus |
| M5 | `image_pipeline_profile` setting dead | `database.rs:232` | Hapus dari defaults |
| M6 | Chapter search tanpa debounce | `comic_page.dart:129` | Tambah debounce 300ms |
| M7 | History dedup di Dart, harusnya di SQL | `library_state.dart:113` | Pakai `GROUP BY` di Rust |
| M8 | Scroll offset save tanpa throttle di comic_page | `comic_page.dart:37` | Tambah throttle 200ms |
| F1 | Double `ref.watch(readerSettingsProvider)` | `reader_page.dart:95,263` | Hapus watch kedua |
| F2 | `libraryPaginationProvider.reset()` tidak pernah dipanggil | `library_state.dart:46` | Panggil saat filter berubah |
| F3 | `_decodeString` dan helper duplicated across files | `comic_state.dart`, `library_state.dart` | Extract ke utility |
| T2 | Test scan.rs pakai dead `list_comics()` API | `scan.rs:44,71` | Migrate ke `list_library_comics_raw` |

---

## Ringkasan

| Fase | HIGH | MEDIUM | LOW | Total | Status |
|------|------|--------|-----|-------|--------|
| Fase 1 | 12 | 5 | 0 | 17 | ✅ Selesai |
| Fase 2 | 2 | 6 | 9 | 17 | ⏳ Pending |
| **Total** | **14** | **11** | **9** | **34** | |

---

## Detail Temuan Fase 1 (Selesai)

### 1. Page Cache Clone (HIGH) ✅

`image_pipeline.rs:222` — setiap cache hit, `state.bytes.get(&key).cloned()` clone seluruh `CachedPageBytes` yang berisi `Vec<u8>` (full image 500KB-5MB).

**Fix:** Ubah `CachedPageBytes.bytes` ke `Arc<Vec<u8>>`. Cache hit return `Arc` clone (murah).

### 2. IndexedStack (HIGH) ✅

`library_page.dart:283` — `IndexedStack` keep semua 3 tab alive sekaligus.

**Fix:** Ganti dengan `switch` conditional rendering.

### 3. Search Filter (HIGH) ✅

`library_state.dart:60-70` — `toLowerCase()` dipanggil untuk setiap comic pada setiap ketikan user.

**Fix:** Debounce 300ms di `onChanged`.

### 4. Batch Chapter Query (MEDIUM) ✅

`chapter.rs:486` — `list_comic_chapters_raw_conn` query DB satu per satu per chapter.

**Fix:** Batch query dengan `WHERE history_key IN (...)`.

### 5. Provider Invalidation (MEDIUM) ✅

`reader_page.dart:428-439` — setiap page turn invalidate 4 providers.

**Fix:** Pindah invalidation ke saat reader close.

---

## Detail Temuan Fase 2 (Pending)

### H1. save_progress() Unnecessary Cache Clear

`lib.rs:528` — setiap `save_progress()` memanggil `clear_library_list_cache()`. Padahal progress tidak mengubah struktur filesystem. Ini menyebabkan unnecessary FS re-scan jika user kembali ke library page dalam 30 detik.

**Fix:** Hapus `self.clear_library_list_cache()` dari `save_progress()`.

### H2. Double setQuery() di comic_page

`comic_page.dart:41-45` — `_search.addListener()` memanggil `setQuery()`.
`comic_page.dart:129` — `onChanged` juga memanggil `setQuery()`.

Setiap keystroke fire 2 state update, 2 rebuild.

**Fix:** Hapus `.addListener()`. Tambah debounce 300ms seperti library_page.

### N1. RenderedPage.cache_key Still Computed

`image_pipeline.rs:266` — `format!("{}:{}", payload.chapter_id, payload.page_index)` di-compute setiap page render, padahal field sudah dihapus dari bridge struct.

**Fix:** Hapus `cache_key` dari core `RenderedPage` struct dan stop computing it.

### N2. SettingEntry.updated_at Still Queried

`database.rs:249` — `SELECT key, value_json, updated_at FROM app_settings`. `updated_at` tidak dipakai Flutter.

**Fix:** Hapus `updated_at` dari SELECT dan dari core struct.

### N3. ReadingProgress.updated_at Still Queried

`reader.rs:42` — query masih select `updated_at`. Bridge sudah tidak kirim field ini.

**Fix:** Hapus `updated_at` dari SELECT dan dari core struct.

### N4. Library Cache Vec Clone

`lib.rs:359` — `cache_guard.as_ref().unwrap().entries.clone()` clone seluruh `Vec<PathBuf>` setiap access. Untuk library 500+ komik, ini 500+ heap allocation.

**Fix:** Wrap entries di `Arc<Vec<PathBuf>>`, clone Arc saja (murah).

### M1. Dead Code ~460 Lines

`reader_page.dart:1082-1542` — 4 widget class tidak pernah di-instantiate:
- `_ReaderToolbar` (212 lines)
- `_ValueButton` (46 lines)
- `_SheetValueControl` (45 lines)
- `_PageIndicator` (35 lines)

**Fix:** Hapus.

### M2. Comic/list_comics Dead in Core

`lib.rs:58-69` — `Comic` struct masih ada.
`lib.rs:479-485` — `list_comics()` method masih ada.
`library.rs:350-407` — `list_comics_conn()` masih ada.

Hanya dipakai oleh test `scan.rs`.

**Fix:** Hapus dari production code, update test pakai `list_library_comics_raw`.

### M4. pub use comicrd_core::* Leaks

`bridge/lib.rs:4` — `pub use comicrd_core::*` expose semua internal core types.

**Fix:** Hapus. Bridge punya tipe sendiri di `api.rs`.

---

## Estimasi Dampak Fase 2

| Fix | Dampak |
|-----|--------|
| H1 | Eliminasi unnecessary FS re-scan setelah reading |
| H2 | Eliminasi 2x rebuild per keystroke di chapter search |
| N1-N3 | Eliminasi wasted alloc per page render dan per settings read |
| N4 | Eliminasi 500+ heap alloc per library view |
| M1 | -460 baris dead code |
| M2 | -60 baris dead code + cleaner API surface |
