@RTK.md

# ComicRD Agent Notes

## Rules

- **JANGAN melakukan commit secara otomatis.** Hanya lakukan commit ketika user secara eksplisit meminta (misalnya: "commit", "buat commit", "ya commit"). Jangan pernah mengasumsikan user ingin commit setelah selesai perubahan.

## Roles

- Product Role: Desktop comic reader lokal dengan fokus performa dan UX baca.
- Frontend Role: React + TanStack Router/Query untuk Library, Comic, Reader, Settings.
- Backend Role: Tauri 2 + Rust command layer untuk scan source, rendering page, progress, bookmark, settings.
- Data Role: SQLite (`rusqlite`) untuk metadata komik, chapter, progress, bookmark, dan `app_settings`.
- Performance Role: scan library bertahap, virtual list, lazy image, stable webtoon rendering, dan custom protocol untuk melayani byte gambar tanpa base64 IPC.

## Tech Stack

- Runtime: Tauri 2
- Frontend: React 19, Vite, TypeScript
- Styling/UI: TailwindCSS, shadcn-style components lokal berbasis Base UI, Lucide Icons
- Routing: TanStack Router
- Data Fetching: TanStack Query
- State Management: Zustand
- List Virtualization: `@tanstack/react-virtual`
- i18n: Lingui (`@lingui/core`, `@lingui/react`) dengan locale `en` dan `id`
- Database: SQLite via `rusqlite`
- Archive Support: `zip`, `cbz`, folder images
- Formatting/Linting: `oxfmt`, `oxlint`
- Test: Vitest (unit), Playwright (E2E), Rust tests (`cargo test`)

## Build Scripts

- `scripts/build-linux.sh` mirrors `.github/workflows/desktop-build.yml` for local Linux builds.
- `pnpm build:linux` builds `.deb` and `.rpm`.
- `pnpm build:linux:appimage` builds AppImage separately.
- `pnpm build:linux:arch` follows the Arch/CachyOS CI path: `pnpm tauri build --target x86_64-unknown-linux-gnu --no-bundle`, then generate tarball, `PKGBUILD`, `.SRCINFO`, and local pacman package when `makepkg` exists.
- Linux outputs are copied to `release/linux`.

## Architecture: State Management (Zustand)

- Store: `src/stores/libraryStore.ts` — `usePreferencesStore` dengan `useShallow` selectors.
- Separated hooks: `useLibraryPreferences()` untuk LibraryPage, `useChapterSort()` untuk ComicPage.
- Actions dipisah dari values via selector constants agar referensi stabil.
- Persistensi: `sortBy`, `sortDir`, `viewMode`, `inputPath`, `chapterSortDir` disimpan ke SQLite `app_settings` via `setSetting()`.
- Scroll position disimpan in-memory di Layout (`scrollPositions` Map), bukan di SQLite.

## Architecture: List Virtualization

- Component: `src/components/ui/virtual-list.tsx` — reusable `VirtualList<T>` wrapper.
- Menggunakan `.content-scroll` (Layout `<main>`) sebagai scroll element, bukan div sendiri.
- `estimateSize: 88` untuk library rows (`.library-row` CSS `contain-intrinsic-size: 88px`).
- `estimateSize: 72` untuk chapter rows di ComicPage.
- `overscan: 5` default.
- Expose `VirtualListHandle.scrollToIndex()` via ref untuk scroll-to-chapter.
- JANGAN pakai `measureElement` — menyebabkan `getTotalSize()` berubah → scroll reset.

## Architecture: Scroll Restoration

- Layout (`src/routes/Layout.tsx`) export: `scrollPositions` Map, `saveScroll(key)`, `restoreScroll(key)`, `setScrollKey(key)`.
- Scroll listener di Layout save posisi per `activeScrollKey` setiap scroll event.
- `isRestoring` flag mencegah listener overwrite posisi saat restore berjalan.
- `restoreScroll()` retry 8x selama 2 detik untuk survive virtualizer recalculation.
- Per-page keys: `library:history`, `library:library`, `library:bookmarks`, `comic:{comicSourcePath}`, `settings`.
- Tab switch di LibraryPage: `switchViewMode()` save scroll SEBELUM `setViewMode()` (sebelum React re-render).
- Layout `useLayoutEffect` handle save/restore saat pathname berbeda (navigasi antar page).

## Architecture: CSS Layout

- `.app-shell` pakai `height: 100%` (BUKAN `min-height: 100%`) supaya `.content-scroll` terconstraint ke viewport.
- `.content-scroll` punya `overflow: auto` + `scroll-behavior: smooth` + `scrollbar-gutter: stable`.
- `scrollTo({ behavior: "instant" })` dipakai untuk bypass `scroll-behavior: smooth` saat restore.

## Current Global Reader Settings

- `default_mode`
- `arrow_navigation_enabled`
- `default_zoom`
- `page_gap`
- `image_pipeline_profile` (`performance`, `balanced`, `quality`; default `balanced`)
- `library_source_input`
- `app_theme`
- `app_locale` (default `en`, pilihan hanya `en` dan `id`; tidak ada opsi system)
- `library_sort_by`, `library_sort_dir`, `library_view_mode`, `chapter_sort_dir`

## Current Reader UX

- Reader route full-screen (main app navbar disembunyikan saat `/reader/*`).
- Reader mode dikunci ke webtoon vertical scroll.
- Toolbar atas ala OpenComic/HakuNeko: close, judul komik/chapter, navigasi, zoom, gap, fullscreen, bookmark.
- Tooltip untuk kontrol icon-only harus memakai `src/components/ui/tooltip.tsx` (`WithTooltip` / `TooltipProvider`) yang mengikuti shadcn Base UI Tooltip, bukan atribut HTML `title`.
- Progress indicator segmented fixed di bagian bawah; segment bisa diklik untuk lompat page.
- `Esc` dan tombol close kembali ke chapter page berdasarkan `comic_source_path`, bukan id database.
- `ArrowUp`/`ArrowDown` dan `PageUp`/`PageDown` dipakai sebagai alternatif scroll saat mouse wheel bermasalah.

## Current Render Pipeline

- Library page hanya scan title komik dari folder source.
- Comic/chapter page baru scan chapter saat title diklik.
- Database write untuk comic/chapter/progress baru dilakukan saat chapter dibuka/dibaca.
- Chapter status boleh melakukan lookup read-only ke database berdasarkan relative `history_key`.
- Gambar dilayani ke `<img>` lewat `comicPageSrc` dengan query variant (`w`, `profile`) agar Rust bisa mengirim versi resize sesuai viewport.
- Preview kecil dilayani lewat `comicPagePreviewSrc` untuk background placeholder saat variant utama belum selesai.
- Linux/macOS harus memakai `comicrd://localhost/page/{chapterId}/{pageIndex}`.
- Windows/Android harus memakai Wry/Tauri custom-protocol workaround `http://comicrd.localhost/page/{chapterId}/{pageIndex}`.
- `http://comicrd.localhost/...` bukan HTTP server biasa; hanya valid sebagai custom protocol workaround pada platform yang didukung. Jika Linux menerima URL ini, release build bisa menampilkan `Connection refused`.
- Rust image pipeline bertanggung jawab membaca file, cache byte asli, generate preview, resize variant viewport-aware, dedupe in-flight resize, dan prefetch variant secara async.
- Jangan kirim gambar besar via base64/IPC. Frontend hanya mengirim request URL/protocol atau command prefetch variant ke Rust.
- React menampilkan halaman sebagai dokumen webtoon normal dengan window aktif sekitar current page (`current ± 1` saat ini). Page dekat memuat `<img>` asli, page jauh boleh placeholder-only dengan aspect ratio stabil untuk menurunkan memory WebView.
- Prefetch harus direction-aware memakai `computePrefetchRange()` dan command `prefetchPageVariants()`, bukan prefetch semua page sekaligus.
- Jangan memakai dynamic-height virtualizer untuk reader karena pernah menyebabkan overlap dan scroll jump.
- Placeholder/loading wrapper boleh dipakai untuk menjaga tinggi sementara dan menampilkan preview kecil; pastikan page dekat tetap menuju `comicPageSrc`.
- Zoom reader dianimasikan lewat transisi `max-width` pada frame page (`transition-[max-width]`) supaya smooth tanpa transform yang mengganggu scroll/progress.
- AVIF belum didokumentasikan sebagai format yang disupport pipeline saat ini; jangan klaim support AVIF kecuali fitur `image`/decoder dan test sudah ditambahkan.

## Architecture: Tooltips

- Component: `src/components/ui/tooltip.tsx` — wrapper lokal untuk `@base-ui/react/tooltip` mengikuti pola shadcn Base Tooltip.
- Root app (`src/main.tsx`) harus tetap dibungkus `TooltipProvider`.
- Gunakan `WithTooltip` untuk tombol/icon/link existing supaya tidak membuat struktur button bersarang.
- Untuk disabled button, bungkus button dengan `span` di dalam `WithTooltip`, sesuai pola shadcn disabled tooltip.
- Hindari atribut DOM `title` sebagai tooltip. `title` sebagai prop komponen internal seperti `ErrorState title` atau `SpineThumb title` tetap boleh.

## Development Server

- Vite dev server memakai `127.0.0.1:1520`.
- `src-tauri/tauri.conf.json` `devUrl` harus tetap sinkron dengan `vite.config.ts`.
- Jika Windows memberi `EACCES` pada port dev, cek excluded TCP port ranges sebelum mengganti port lagi.

## Current i18n UX

- UI memakai Lingui runtime catalog lokal di `src/i18n.ts`.
- Locale aktif dibaca dari `app_settings.app_locale` via `listSettings`.
- Settings page menyimpan bahasa ke database lewat `setSetting("app_locale", localePreference)`.
- Default locale adalah English (`en`), bukan OS/system language.

## Testing

- Unit: `pnpm test` — Vitest, 8 test files.
- E2E: `npx playwright test` — Playwright dengan Chromium, mock Tauri IPC via `window.__TAURI_INTERNALS__`.
- E2E config: `playwright.config.ts`, test dir `e2e/`.
- E2E mock: 200 fake comics, mock settings, mock semua Tauri IPC commands yang dipakai frontend.
- Reader image loading E2E: `e2e/reader-image-loading.spec.ts` memastikan gambar page berikutnya tetap dimount dan ter-load saat scroll turun.
- Rust: `cargo test` di `src-tauri/`.
