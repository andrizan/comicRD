@RTK.md

# ComicRD Agent Notes

## Roles

- Product Role: Desktop comic reader lokal dengan fokus performa dan UX baca.
- Frontend Role: React + TanStack Router/Query untuk Library, Comic, Reader, Settings.
- Backend Role: Tauri 2 + Rust command layer untuk scan source, rendering page, progress, bookmark, settings.
- Data Role: SQLite (`rusqlite`) untuk metadata komik, chapter, progress, bookmark, dan `app_settings`.
- Performance Role: scan library bertahap, lazy list, lazy image, virtualized reader, dan custom protocol untuk melayani byte gambar tanpa base64 IPC.

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

## Current Render Pipeline

- Library page hanya scan title komik dari folder source.
- Comic/chapter page baru scan chapter saat title diklik.
- Database write untuk comic/chapter/progress baru dilakukan saat chapter dibuka/dibaca.
- Chapter status boleh melakukan lookup read-only ke database berdasarkan relative `history_key`.
- Gambar dilayani langsung ke `<img>` lewat `comicPageSrc`; platform yang mendukung memakai `comicrd://localhost/page/{chapterId}/{pageIndex}`, sedangkan Windows/Android memakai fallback `http://comicrd.localhost/page/{chapterId}/{pageIndex}`.
- React menampilkan `<img>` langsung dari protocol URL dengan lazy loading dan prefetch beberapa halaman ke depan.

## Current i18n UX

- UI memakai Lingui runtime catalog lokal di `src/i18n.ts`.
- Locale aktif dibaca dari `app_settings.app_locale` via `listSettings`.
- Settings page menyimpan bahasa ke database lewat `setSetting("app_locale", localePreference)`.
- Default locale adalah English (`en`), bukan OS/system language.
