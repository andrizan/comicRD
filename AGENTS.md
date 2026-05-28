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
- Styling/UI: TailwindCSS, shadcn-style components lokal, Lucide Icons
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
- `library_source_input`
- `app_theme`
- `app_locale` (default `en`, pilihan hanya `en` dan `id`; tidak ada opsi system)
- `library_sort_by`, `library_sort_dir`, `library_view_mode`, `chapter_sort_dir`

## Current Reader UX

- Reader route full-screen (main app navbar disembunyikan saat `/reader/*`).
- Reader mode dikunci ke webtoon vertical scroll.
- Toolbar atas ala OpenComic/HakuNeko: close, judul komik/chapter, navigasi, zoom, gap, fullscreen, bookmark.
- Progress indicator segmented fixed di bagian bawah; segment bisa diklik untuk lompat page.
- `Esc` dan tombol close kembali ke chapter page berdasarkan `comic_source_path`, bukan id database.
- `ArrowUp`/`ArrowDown` dan `PageUp`/`PageDown` dipakai sebagai alternatif scroll saat mouse wheel bermasalah.

## Current Render Pipeline

- Library page hanya scan title komik dari folder source.
- Comic/chapter page baru scan chapter saat title diklik.
- Database write untuk comic/chapter/progress baru dilakukan saat chapter dibuka/dibaca.
- Chapter status boleh melakukan lookup read-only ke database berdasarkan relative `history_key`.
- Gambar dilayani langsung ke `<img>` lewat `comicPageSrc`.
- Linux/macOS harus memakai `comicrd://localhost/page/{chapterId}/{pageIndex}`.
- Windows/Android harus memakai Wry/Tauri custom-protocol workaround `http://comicrd.localhost/page/{chapterId}/{pageIndex}`.
- `http://comicrd.localhost/...` bukan HTTP server biasa; hanya valid sebagai custom protocol workaround pada platform yang didukung. Jika Linux menerima URL ini, release build bisa menampilkan `Connection refused`.
- React menampilkan halaman sebagai dokumen webtoon normal dengan lazy loading dan prefetch beberapa halaman ke depan; jangan memakai dynamic-height virtualizer untuk reader karena pernah menyebabkan overlap dan scroll jump.

## Current i18n UX

- UI memakai Lingui runtime catalog lokal di `src/i18n.ts`.
- Locale aktif dibaca dari `app_settings.app_locale` via `listSettings`.
- Settings page menyimpan bahasa ke database lewat `setSetting("app_locale", localePreference)`.
- Default locale adalah English (`en`), bukan OS/system language.

## Testing

- Unit: `pnpm test` — Vitest, 7 test files, test pure functions.
- E2E: `npx playwright test` — Playwright dengan Chromium, mock Tauri IPC via `window.__TAURI_INTERNALS__`.
- E2E config: `playwright.config.ts`, test dir `e2e/`.
- E2E mock: 200 fake comics, mock settings, mock semua Tauri IPC commands yang dipakai frontend.
- Rust: `cargo test` di `src-tauri/`.
