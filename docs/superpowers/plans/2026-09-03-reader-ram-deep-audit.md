# Deep Audit RAM Reader Era Tiling + Impeller — 2026-09-03

Follow-up dari `2026-06-06-memory-performance-audit.md` (final, era pra-tiling/Skia)
dan temuan `2026-09-04-reader-concurrency-pipeline.md`.
Pertanyaan pemicu: "semakin banyak chapter yang dibaca semakin besar RAM".
Stack saat ini: Flutter 3.47 (Impeller default, bukan Skia) + strip tiling
(`TILE_MAX_HEIGHT = 2048`).

## Kesimpulan

Tidak ada satu leak tak terbatas. Ada 5 penumpuk yang membuat RSS terlihat
monoton naik: transient decode strip, overlap 2 chapter saat pindah, cache
tanpa cap, provider non-`autoDispose`, dan triple-copy di bridge.
RSS OS di high-water mark bukan bukti leak — yang dinilai heap Dart +
`ImageCache`, bukan RSS saja.

## Aliran memori per tile (saat ini)

```
ZIP/folder read (1-3MB compressed)
-> decode full strip RGBA (1600x20000 = 128MB transient)
-> crop per tile + encode JPEG/PNG (10 tile x ~1MB)
-> PageCache Arc<Vec<u8>> (cap 16 tile, ~16-48MB)
-> bridge From<RenderedPage>: (*bytes).clone() [copy #1]
-> FRB SSE buffer [copy #2]
-> Dart Uint8List di renderedTileProvider [copy #3]
-> Image.memory decode -> ui.Image 1600x2048x4 = ~13MB/tile di engine
   imageCache (cap 128MB reader / 100MB luar)
```

Satu strip `1600x20000`: transient Rust `~130MB`, menetap `~10MB` Rust +
`~10MB` Dart + `~65MB` engine (5 tile visible). Puncak 1 chapter `~200MB`,
overlap 2 chapter saat pindah `~400MB`.

## Temuan

### P0-1: Decode konkuren strip dari Dart

`crates/comicrd_core/src/image_pipeline.rs::decode_and_fit` menahan 1 full
`DynamicImage` RGBA per miss (`1600x20000` = 128MB). Prefetch Rust sekuensial
(by design), tapi `renderedTileProvider` on-demand dipicu `ListView` membangun
banyak tile sekaligus saat scroll cepat (`_ReaderPageItem`). N render konkuren
= N x transient. Phase 4 plan konkurensi masih DEFERRED.

### P0-2: Overlap 2 chapter saat pindah

`app_flutter/lib/pages/reader_page.dart`:

- `dispose()` (`:249`): `_releaseChapterMemory(invalidateRenderedPages:false)`
  mengandalkan `autoDispose`, tanpa invalidate eksplisit.
- `didUpdateWidget()` (`:277`, jalur `go('/reader/$id')` yang reuse state):
  invalidate tile lama ditunda `postFrameCallback`, chapter baru sudah loading.
- `_releaseChapterMemory` (`:1275`): `generation++` → `await pendingPrefetch`
  → `evict(keep=[])`. Benar anti-repopulate, tapi cache lama dipegang selama
  drain — jendela lama+baru hidup bareng tiap next/prev.

### P0-3: `chapter_discovery_cache` unbounded

`crates/comicrd_core/src/lib.rs:296,877,894`: `HashMap` tanpa cap, entry
expired (>60s) hanya dianggap miss tanpa `remove`. `clear` hanya saat
open/scan/optimize/import. Browse banyak komik tanpa open = tumbuh terus.
Provider Dart lain sudah `_maxSize=200`, yang ini belum.

### P1-1: Family provider non-`autoDispose`

`app_flutter/lib/state/comic_state.dart:7,11,21,117`,
`app_flutter/lib/state/library_state.dart:14,20,116,188,235`:
`comicChaptersProvider`, `chapterBookmarksProvider`,
`comicReadingHistoryProvider`, `comicFavoritedProvider`,
`rawLibraryComicsProvider`, `readingHistoryProvider`, `allFavoritesProvider`.
Tiap komik yang dibuka nempel sampai invalidate manual. Per item kecil, tapi
monoton naik saat gonta-ganti komik. (`readerDataProvider` dan
`renderedTileProvider` sudah `autoDispose` — dijadikan contoh.)

### P1-2: `imageCache` hanya batasi bytes

`reader_page.dart:241,264`: `maximumSizeBytes` 128MB/100MB, tapi
`maximumSize` (count) default 1000 tidak pernah diset. Thumbnail library
(`comicThumbnailProvider`, sudah `autoDispose`) berbagi `imageCache` global
dengan tile reader.

### P1-3: Double prefetch

`comic_page.dart:397` warm 4 tile → navigasi → `_restoreProgress` +
`_prefetchWindow` (`reader_page.dart:1139`) prefetch ulang window yang sama.

### P2: `_pageBookmarkedPages` tidak di-clear

`reader_page.dart:231`: `didUpdateWidget`/`_switchChapter` reset
`_currentPage`/`_renderStart` tapi tidak `_pageBookmarkedPages`. Chapter baru
gagal load bookmark (`if (isEmpty)`) + Set campur antar chapter. Kecil, tapi bug.

## Koreksi Impeller (Flutter 3.47)

`imageCache` Dart tetap ada (cache `ui.Image`, independen renderer). Yang beda:
pool texture + staging buffer Impeller (Vulkan/Metal/D3D), bukan Skia Ganesh.
Dealokasi GPU ditunda sampai batas frame/`ImpellerContext` cleanup — RSS turun
telat 1-2 frame/GC setelah `clear()`. `RepaintBoundary` per tile tetap
dipertahankan (isolasi repaint; tiap boundary = layer sendiri di Impeller,
jangan dibungkus lagi). Estimasi `2048x2048x4 = 16MB`/tile tetap valid.

## Gate pengukuran (ditambahkan ke plan tiling + konkurensi)

Switch chapter 5x cepat di Impeller: DevTools Memory `ImageCache` count/bytes
tidak monoton naik, kolom GPU turun kembali setelah 1-2 frame/GC. RSS OS boleh
di high-water mark.

## Rekomendasi (belum diimplementasi)

P0: serialisasi render tile per chapter di Rust; invalidate eksplisit +
double-evict di dispose/switch; cap LRU 200 + prune expired untuk
`chapter_discovery_cache`. P1: `autoDispose.family` untuk provider di §P1-1;
set `imageCache.maximumSize`; hapus satu sisi double prefetch; clear
`_pageBookmarkedPages` saat switch. Observability: ekspos `cache_stats_for_test`
+ RSS ke settings debug.
