# Audit Memory & Performa — 2026-06-06

Audit mendalam terhadap seluruh codebase comicrd_flutter (Rust core, Flutter UI, Bridge layer) untuk optimasi memory dan performa.

---

## HIGH Impact (Prioritas Utama)

### Rust Core

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| 1 | Page cache clone full image bytes setiap cache hit | `image_pipeline.rs:222` | Wrap `Vec<u8>` di `Arc` supaya clone murah |
| 2 | Single `Mutex<Connection>` block semua operasi saat scan | `lib.rs:251` | Pakai connection pool atau connection terpisah untuk scan |
| 3 | Scan hold DB lock selama seluruh proses scan | `lib.rs:406` | Pecah lock per-library, bukan satu lock untuk semua |
| 4 | Archive dibuka 2x (list + read) | `chapter.rs:240,259` | Cache open archive handle di `PageSource` |

### Flutter UI

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| 5 | `IndexedStack` keep 3 tab alive sekaligus | `library_page.dart:283` | Ganti dengan conditional rendering (`switch`) |
| 6 | `.sublist()` copy full list setiap build | `library_page.dart:85` | Hapus `.sublist()`, pass `items` + `visibleCount` langsung |
| 7 | `toLowerCase()` di setiap filter per ketikan | `library_state.dart:60-70` | Debounce 300ms + pre-lowercase di bridge |
| 8 | Page indicator build N widget untuk N halaman | `reader_page.dart:1446` | Ganti dengan `CustomPainter` |
| 9 | Image cache di-clear total saat reader dispose | `reader_page.dart:60-61` | Pakai `clearLiveImages()` saja, jangan `clear()` |
| 10 | 4 provider di-invalidate setiap page turn | `reader_page.dart:428-439` | Pindah invalidation ke saat reader close |

### Bridge

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| 11 | Semua comic di-transfer sekaligus | `comicrd_api.dart:34` | Tambah server-side pagination (`limit`/`offset`) |
| 12 | `RenderedPage.bytes` copy 2x via FFI | `frb_generated.dart:2516` | Investigasi zero-copy FRB atau pre-decode di Rust |

---

## MEDIUM Impact

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| 13 | `PageSource.clone()` copy path list | `image_pipeline.rs:170` | Wrap di `Arc` |
| 14 | `LibraryListCache` clone full entries | `lib.rs:359` | Wrap di `Arc<Vec<PathBuf>>` |
| 15 | `to_string_lossy().to_string()` berlebihan | `library.rs:60`, `chapter.rs:371` | Pakai `to_str()` atau `Cow<str>` |
| 16 | Chapter entries tuple 3 String per chapter | `chapter.rs:370` | Pakai struct dengan `Cow<str>` |
| 17 | `list_comics()` / `Comic` dead code | `api.rs:545` | Hapus |
| 18 | `RawComic.key` == `source_path` redundan | `lib.rs:36` | Hapus field `key` |
| 19 | `RawComic.library_path` dikirim N kali | `api.rs:26` | Hapus, Flutter sudah punya dari `checkLibrarySource()` |
| 20 | History dedup di Dart, harusnya di SQL | `library_state.dart:111` | Pakai `GROUP BY` di Rust |
| 21 | N+1 query chapter progress | `chapter.rs:486` | Batch query dengan `WHERE comic_id = ?` |
| 22 | `prefetch_pages` lock DB per page | `lib.rs:559` | Lock sekali, iterate di dalam |
| 23 | Scroll offset save setiap tick | `library_page.dart:60` | Throttle 200ms |
| 24 | `clearLiveImages()` setiap 2 halaman | `reader_page.dart:349` | Hapus, biarkan LRU handle |
| 25 | `renderedPageProvider` tidak di-evict | `reader_page.dart:667` | Invalidate page yang jauh dari viewport |

---

## LOW Impact

| # | Masalah | Lokasi | Solusi |
|---|---------|--------|--------|
| 26 | `scrollOffsetsProvider` tumbuh tak terbatas | `scroll_state.dart:8` | LRU cache max 200 entry |
| 27 | `_pageKeys` tumbuh tak terbatas | `reader_page.dart:35` | Hapus key yang jauh dari viewport |
| 28 | `renderPagePreview` redundan | `api.rs:581` | Hapus |
| 29 | `RenderedPage.cache_key` bisa dihitung client-side | `api.rs:187` | Hapus |
| 30 | `SettingEntry.updated_at` tidak dipakai Flutter | `api.rs:204` | Hapus |
| 31 | `Vec::with_capacity` tidak dipakai | `lib.rs:367` | Tambah pre-allocation |
| 32 | RegExp compile setiap build | `comic_page.dart:80` | Pindah ke `initState` |

---

## Rekomendasi Eksekusi (urutan ROI tertinggi)

1. **`Arc` untuk cache bytes** → Eliminasi clone image 5MB per cache hit
2. **Ganti `IndexedStack`** → Hemat 2/3 widget tree memory
3. **Hapus `.sublist()`** → Eliminasi copy full list per build
4. **Debounce search** → Eliminasi O(N) string alloc per ketikan
5. **Server-side pagination** → Kurangi transfer data dari Rust
6. **Pecah scan DB lock** → Unblock UI saat scan
7. **CustomPainter page indicator** → O(N) → O(1) widget

---

## Detail Temuan

### 1. Page Cache Clone (HIGH)

`image_pipeline.rs:222` — setiap cache hit, `state.bytes.get(&key).cloned()` clone seluruh `CachedPageBytes` yang berisi `Vec<u8>` (full image 500KB-5MB). Ini deep copy di bawah mutex lock.

**Fix:** Ubah `CachedPageBytes.bytes` ke `Arc<Vec<u8>>`. Cache hit return `Arc` clone (murah). `RenderedPage.bytes` juga jadi `Arc<Vec<u8>>` atau `.to_vec()` hanya saat crossing FFI boundary.

### 2. Single Mutex Connection (HIGH)

`lib.rs:251` — semua operasi DB contend di satu `Mutex<Connection>`. Scan thread hold lock untuk durasi scan penuh, block semua query UI.

**Fix:** Pakai `r2d2` connection pool atau buat connection terpisah untuk scan. SQLite WAL support concurrent readers + single writer.

### 3. IndexedStack (HIGH)

`library_page.dart:283` — `IndexedStack` keep semua 3 tab (history, library, bookmarks) alive sekaligus. 2/3 widget tree tidak terlihat tapi tetap di memory.

**Fix:** Ganti dengan `switch` conditional rendering. Scroll offset sudah di-save/restore via `scrollOffsetsProvider`, jadi tab switch tetap restore posisi.

### 4. Archive Dibuka 2x (HIGH)

`chapter.rs:240,259` — ZIP archive dibuka untuk listing entry, lalu dibuka lagi untuk read image. Untuk CBZ 200 halaman, ini berarti 199 archive open redundan per chapter read.

**Fix:** Cache `ZipArchive` handle (atau central directory) di `PageSource::Archive` variant.

### 5. Search Filter (HIGH)

`library_state.dart:60-70` — `toLowerCase()` dipanggil untuk setiap comic pada setiap ketikan user. Untuk library 5000 komik, ini O(N) string allocation per keystroke.

**Fix:** Debounce 300ms di `onChanged`. Pre-lowercase title di bridge boundary.

### 6. RenderedPage Bytes Copy (HIGH)

`frb_generated.dart:2516` — setiap page render transfer full image bytes (200KB-2MB) dari Rust ke Flutter via FRB SSE serialization (copy). Total: 2+ full copy per page.

**Fix:** Investigasi zero-copy FRB atau pre-decode pixels di Rust side.

### 7. Server-Side Pagination (HIGH)

`comicrd_api.dart:34` — `listLibraryComicsRaw` transfer semua comic sekaligus. Untuk library 5000 comic, ini ~150KB-520KB string data.

**Fix:** Tambah `limit`/`offset` parameter di bridge. Transfer hanya yang terlihat + buffer.

### 8. Chapter N+1 Query (MEDIUM)

`chapter.rs:486` — `list_comic_chapters_raw_conn` query DB satu per satu per chapter. 50 chapter = 50 SQL queries.

**Fix:** Batch query: `SELECT ... FROM chapters ch LEFT JOIN reading_progress r WHERE ch.comic_id = ?`

### 9. History Dedup di Dart (MEDIUM)

`library_state.dart:111` — semua history entry di-fetch dari Rust, lalu dedup di Dart. Data redundan ditransfer via bridge.

**Fix:** Pakai `GROUP BY comic_source_path` atau `SELECT DISTINCT` di Rust SQL.

### 10. Provider Invalidation Berlebihan (MEDIUM)

`reader_page.dart:428-439` — setiap page turn (debounced 450ms) invalidate 4 providers, masing-masing trigger bridge call.

**Fix:** Pindah invalidation ke saat reader close (`_close()`), bukan setiap page turn.

---

## Ringkasan

| Kategori | HIGH | MEDIUM | LOW | Total |
|----------|------|--------|-----|-------|
| Rust Core | 4 | 5 | 3 | 12 |
| Flutter UI | 6 | 4 | 4 | 14 |
| Bridge | 2 | 4 | 4 | 10 |
| **Total** | **12** | **13** | **11** | **36** |

Estimasi dampak jika semua HIGH fix diterapkan:
- Memory reader: **-50-80%** peak memory (Arc cache + IndexedStack + sublist)
- Library listing: **-70%** data transfer (pagination + field removal)
- Search responsiveness: **-90%** string allocation (debounce)
- Scan blocking: **UI tetap responsive** saat scan (connection pool)
