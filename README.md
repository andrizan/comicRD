# ComicRD

ComicRD adalah aplikasi komik reader desktop berbasis **Tauri 2 + React** untuk membaca komik lokal dari:

- Folder gambar
- ZIP
- CBZ

Mode baca dikunci ke **Webtoon mode** (vertical scroll) supaya pipeline render tetap sederhana dan ringan.

## Fitur Utama

- Set folder library + **auto-detect komik otomatis** (gaya Hakuneko)
- Continue reading, bookmark, read/unread status
- Prev/next page + prev/next chapter
- Keyboard navigation (Arrow) dengan toggle
- `Esc` / close reader kembali ke halaman chapter
- Zoom dan page margin/gap yang disimpan global
- Sorting komik: `name`, `folder_date`, asc/desc
- Sorting chapter: nama asc/desc
- Status chapter: unread, reading, read
- Bottom page indicator segmented seperti reader desktop

## Performa

- Scan library bertahap: title dulu, chapter hanya saat title diklik
- Database write hanya saat chapter dibuka/dibaca
- History path relatif terhadap library source supaya tetap cocok ketika folder library dipindah
- Lazy loading image dan virtualized reader
- Prefetch beberapa page berikutnya
- Tauri custom protocol (`comicrd://...`) untuk melayani byte gambar langsung ke `<img>` tanpa base64 IPC

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
