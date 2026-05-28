@RTK.md

# ComicRD Agent Notes

## Roles

- Product Role: Desktop comic reader lokal dengan fokus performa dan UX baca.
- Frontend Role: React + TanStack Router/Query untuk Library, Comic, Reader, Settings.
- Backend Role: Tauri 2 + Rust command layer untuk scan source, rendering page, progress, bookmark, settings.
- Data Role: SQLite (`rusqlite`) untuk metadata komik, chapter, progress, bookmark, dan `app_settings`.
- Performance Role: scan library bertahap, lazy list, lazy image, stable webtoon rendering, dan custom protocol untuk melayani byte gambar tanpa base64 IPC.

## Tech Stack

- Runtime: Tauri 2
- Frontend: React 19, Vite, TypeScript
- Styling/UI: TailwindCSS, shadcn-style components lokal, Lucide Icons
- Routing: TanStack Router
- Data Fetching: TanStack Query
- i18n: Lingui (`@lingui/core`, `@lingui/react`) dengan locale `en` dan `id`
- Database: SQLite via `rusqlite`
- Archive Support: `zip`, `cbz`, folder images
- Formatting/Linting: `oxfmt`, `oxlint`
- Test: Vitest (frontend), Rust tests (`cargo test`)

## Build Scripts

- `scripts/build-linux.sh` mirrors `.github/workflows/desktop-build.yml` for local Linux builds.
- `pnpm build:linux` builds `.deb` and `.rpm`.
- `pnpm build:linux:appimage` builds AppImage separately.
- `pnpm build:linux:arch` follows the Arch/CachyOS CI path: `pnpm tauri build --target x86_64-unknown-linux-gnu --no-bundle`, then generate tarball, `PKGBUILD`, `.SRCINFO`, and local pacman package when `makepkg` exists.
- Linux outputs are copied to `release/linux`.

## Current Global Reader Settings

- `default_mode`
- `arrow_navigation_enabled`
- `default_zoom`
- `page_gap`
- `library_source_input`
- `app_theme`
- `app_locale` (default `en`, pilihan hanya `en` dan `id`; tidak ada opsi system)

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
