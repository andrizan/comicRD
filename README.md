# ComicRD

ComicRD adalah aplikasi komik reader desktop berbasis **Tauri 2 + React** untuk membaca komik lokal dari:

- Folder gambar
- ZIP
- CBZ

Mode baca:

- Manga mode (paging)
- Webtoon mode (vertical scroll)

## Fitur Utama

- Set folder library + **auto-detect komik otomatis** (gaya Hakuneko)
- Continue reading, bookmark, read/unread status
- Prev/next page + prev/next chapter
- Keyboard navigation (Arrow) dengan toggle
- Zoom, interpolation, dan page margin/gap yang disimpan global
- Interpolation methods: `lanczos3`, `lanczos2`, `spline36`, `mitchell`, `cubic`, `linear`, `nearest`
- Sorting komik: `name`, `date`, `date_modified`
- Bottom page/chapter indicator

## Performa

- Lazy loading image
- Virtualized comic list
- Prefetch page tetangga (prev/next)
- Cache render terpisah dengan budget memori eksplisit:
  - Thumbnail cache
  - Preview cache

## Tech Stack

- Tauri 2
- Rust + `rusqlite` (SQLite)
- React 19 + Vite + TypeScript
- TailwindCSS
- TanStack Router + TanStack Query
- Lucide Icons
- Lint/Format: `oxlint`, `oxfmt`

## Development

```bash
pnpm install
pnpm tauri:dev
```

Command quality checks:

```bash
pnpm format
pnpm lint
pnpm typecheck
pnpm test
```

## Build Desktop

Build target per platform:

```bash
pnpm tauri:build:linux
pnpm tauri:build:windows
pnpm tauri:build:macos
```

Build current machine default target:

```bash
pnpm tauri:build
```

CI workflow untuk build Windows/Linux/macOS ada di:

- `.github/workflows/desktop-build.yml`

## Catatan Cross-Platform Build

- Build native per OS tetap membutuhkan toolchain/SDK OS target.
- Untuk build multi-platform otomatis, gunakan CI matrix (sudah disiapkan).

Referensi resmi:

- https://v2.tauri.app/
- https://v2.tauri.app/distribute/windows-installer/
- https://v2.tauri.app/start/prerequisites/
