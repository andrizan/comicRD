# ComicRD

A lightweight, high-performance desktop comic reader built with **Tauri 2 + React**, designed for reading local comics from folders, ZIP, and CBZ archives.

The reader is locked to **webtoon mode** (vertical scroll) to keep the rendering pipeline simple and efficient.

## Features

- **Library Management** — Set a library folder with automatic comic detection (similar to HakuNeko)
- **Reading Progress** — Continue reading, bookmarks, and read/unread status tracking
- **Navigation** — Previous/next page and chapter navigation with keyboard arrow support (toggleable)
- **Reader Controls** — Zoom, page gap/margin, and fullscreen with globally persisted settings
- **Sorting** — Comics sortable by `name` or `folder_date` (ascending/descending); chapters sortable by name
- **Chapter Status** — Unread, reading, and read indicators per chapter
- **Internationalization** — English and Indonesian UI via Lingui, with English as the default locale
- **Page Indicator** — Segmented bottom progress bar with clickable segments for quick page jumping
- **Responsive Toolbar** — Top toolbar with close, title, navigation, zoom, gap, fullscreen, and bookmark controls
- **`Esc` Navigation** — Returns to the chapter page based on `comic_source_path`

## Performance

- **Incremental Library Scan** — Titles scanned first; chapters scanned only when a title is opened
- **Lazy Database Writes** — Comic, chapter, and progress records created only when a chapter is read
- **Relative History Paths** — Progress keys are relative to the library source, so history survives folder moves
- **Virtualized Reader** — Lazy image loading with virtualized rendering and prefetching of upcoming pages
- **Custom Protocol** — Page bytes are served directly to `<img>` tags, using `comicrd://` where supported and an HTTP protocol fallback on Windows/Android
- **Persistent Settings** — Reader, library, theme, and locale preferences are stored in SQLite `app_settings`

## Tech Stack

| Layer           | Technology                                                              |
| --------------- | ----------------------------------------------------------------------- |
| Runtime         | [Tauri 2](https://v2.tauri.app/)                                        |
| Backend         | Rust + [`rusqlite`](https://github.com/rusqlite/rusqlite) (SQLite)      |
| Frontend        | [React 19](https://react.dev/) + [Vite](https://vite.dev/) + TypeScript |
| Styling         | [TailwindCSS v4](https://tailwindcss.com/)                              |
| Routing         | [TanStack Router](https://tanstack.com/router)                          |
| Data Fetching   | [TanStack Query](https://tanstack.com/query)                            |
| i18n            | [Lingui](https://lingui.dev/)                                           |
| Virtualization  | [TanStack Virtual](https://tanstack.com/virtual)                        |
| Icons           | [Lucide React](https://lucide.dev/)                                     |
| Linting         | [oxlint](https://oxc-project.github.io/)                                |
| Formatting      | [oxfmt](https://oxc-project.github.io/)                                 |
| Testing         | [Vitest](https://vitest.dev/) (frontend), `cargo test` (Rust)           |
| Package Manager | [pnpm](https://pnpm.io/)                                                |

## Getting Started

### Prerequisites

Ensure you have the [Tauri 2 prerequisites](https://v2.tauri.app/start/prerequisites/) installed for your platform.

### Installation

```bash
pnpm install
```

### Development

```bash
pnpm tauri:dev
```

### Quality Checks

```bash
pnpm format        # Format code with oxfmt
pnpm lint          # Lint with oxlint
pnpm typecheck     # TypeScript type checking
pnpm test          # Run Vitest tests
```

## Building

Build for a specific platform:

```bash
pnpm tauri:build:linux       # Linux (.deb + .rpm)
pnpm tauri:build:windows     # Windows
pnpm tauri:build:macos       # macOS (universal)
```

Linux AppImage requires `linuxdeploy` and is built separately:

```bash
pnpm tauri:build:linux:appimage
```

Build for the current machine's default target:

```bash
pnpm tauri:build
```

CI workflows for multi-platform builds are defined in `.github/workflows/desktop-build.yml`.

## Project Structure

```
comicrd/
├── .github/workflows/   # CI/CD workflows
├── public/              # Static assets
├── src/                 # React frontend (TypeScript)
├── src-tauri/           # Tauri backend (Rust)
├── AGENTS.md            # Agent coding guidelines
├── package.json
├── vite.config.ts
├── tsconfig.json
└── README.md
```

## Cross-Platform Notes

- Native builds require the target OS toolchain and SDK.
- For automated multi-platform builds, use the CI matrix workflow (already configured).

## License

See [LICENSE](./LICENSE) for details.

## Resources

- [Tauri 2 Documentation](https://v2.tauri.app/)
- [Tauri Windows Installer](https://v2.tauri.app/distribute/windows-installer/)
- [Tauri Prerequisites](https://v2.tauri.app/start/prerequisites/)
