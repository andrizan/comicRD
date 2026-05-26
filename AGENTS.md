@RTK.md

# ComicRD Agent Notes

## Roles

- Product Role: Desktop comic reader lokal dengan fokus performa dan UX baca.
- Frontend Role: React + TanStack Router/Query untuk Library, Comic, Reader, Settings.
- Backend Role: Tauri 2 + Rust command layer untuk scan source, rendering page, progress, bookmark, settings.
- Data Role: SQLite (`rusqlite`) untuk metadata komik, chapter, progress, bookmark, dan `app_settings`.
- Performance Role: lazy list, lazy image, prefetch tetangga page, cache render (`thumbnail` + `preview`) berbasis budget memori.

## Tech Stack

- Runtime: Tauri 2
- Frontend: React 19, Vite, TypeScript
- Styling/UI: TailwindCSS, shadcn-style components lokal, Lucide Icons
- Routing: TanStack Router
- Data Fetching: TanStack Query
- Database: SQLite via `rusqlite`
- Archive Support: `zip`, `cbz`, folder images
- Formatting/Linting: `oxfmt`, `oxlint`
- Test: Vitest (frontend), Rust tests (`cargo test`)

## Current Global Reader Settings

- `default_mode`
- `arrow_navigation_enabled`
- `smooth_scroll_speed`
- `interpolation_method`
- `default_zoom`
- `page_gap`
- `library_source_input`

## Current Reader UX

- Reader route full-screen (main app navbar disembunyikan saat `/reader/*`).
- Toolbar atas ala OpenComic/HakuNeko: close, judul komik/chapter, mode baca, navigasi, zoom, gap, interpolation.
- Progress bar tipis fixed di bagian bawah.
- Fokus baca: area konten lebih lebar, panel floating kanan dihapus.

## Current Render Pipeline

- Backend render image berjalan via `spawn_blocking` agar UI thread tidak freeze.
- Resized output dikirim sebagai JPEG base64 (lebih cepat dari PNG untuk throughput render).
- Prefetch manga: ±2 halaman; prefetch webtoon: beberapa halaman ke depan.
