# ComicRD

A lightweight, high-performance desktop comic reader built with **Tauri 2 + React**, designed for reading local comics from folders, ZIP, and CBZ archives.

The reader is locked to **webtoon mode** (vertical scroll) to keep the rendering pipeline simple and efficient.

## Features

- **Library Management** — Set a library folder with automatic comic detection (similar to HakuNeko)
- **Library Source Status** — Live check of the configured library path with a warning banner and refresh button when the folder is missing, not a directory, or unmounted (e.g., an external drive on Linux)
- **Reading Progress** — Continue reading, bookmarks, and read/unread status tracking
- **Navigation** — Previous/next page and chapter navigation, plus vertical keyboard scrolling with Arrow Up/Down and Page Up/Down
- **Reader Controls** — Smooth animated zoom, page gap/margin, and fullscreen with globally persisted settings
- **Sorting** — Comics sortable by `name` or `folder_date` (ascending/descending); chapters sortable by name
- **Image Formats** — Current Rust decoder pipeline supports PNG, JPEG, WebP, GIF, and BMP. AVIF is not enabled yet.
- **Chapter Status** — Unread, reading, and read indicators per chapter
- **Internationalization** — English and Indonesian UI via Lingui, with English as the default locale
- **Page Indicator** — Segmented bottom progress bar with clickable segments for quick page jumping
- **Responsive Toolbar** — Top toolbar with close, title, navigation, zoom, gap, fullscreen, and bookmark controls
- **Base UI Tooltips** — Icon-only controls use the local shadcn/Base UI tooltip component instead of browser-native `title` tooltips
- **`Esc` Navigation** — Returns to the chapter page based on `comic_source_path`
- **Scroll Restoration** — Scroll position is maintained per page and per library tab when navigating away and back

## Performance

- **Incremental Library Scan** — Titles scanned first; chapters scanned only when a title is opened
- **Lazy Database Writes** — Comic, chapter, and progress records created only when a chapter is read
- **Relative History Paths** — Progress keys are relative to the library source, so history survives folder moves
- **Virtual List Rendering** — Library and chapter lists use `@tanstack/react-virtual` to render only visible rows, keeping memory usage constant regardless of list size
- **Stable Webtoon Rendering** — Pages are rendered as a normal vertical document with stable sizing, eager loading near the current page, and lightweight placeholders for distant pages
- **Native-Assisted Image Pipeline** — Rust reads page files, serves resized viewport-aware variants through the custom protocol, generates low-resolution previews, and deduplicates in-flight resize work
- **Reader Page Windowing** — The reader keeps the current page and nearby pages active while distant pages use stable aspect-ratio placeholders, reducing WebView image memory pressure during long chapters
- **Direction-Aware Prefetch** — The frontend asks Rust to prefetch resized variants ahead of the current scroll direction instead of pushing base64 image data through IPC
- **Image Pipeline Profiles** — `performance`, `balanced`, and `quality` profiles tune target image width and prefetch distance from Settings
- **i18n Code-Splitting** — English and Indonesian catalogs are dynamic-import chunks; the main bundle excludes both. The active locale is switched via an in-flight-deduped async loader
- **Aggressive Query gcTime** — `pagesQuery`, `chapterContextQuery`, and `progressQuery` use a 60s gcTime so cached responses are released as soon as the user leaves the reader
- **Backend Page Cache (Rust)** — `ahash` for path hashing, `RwLock<PageCache>` for concurrent reads, `lru::LruCache` for original page bytes, preview bytes, and resized image variants
- **Custom Page Protocol** — Comic page bytes are served directly to `<img>` tags through Tauri's registered `comicrd` protocol. Linux/macOS use `comicrd://localhost/...`; Windows/Android use Wry's `http://comicrd.localhost/...` custom-protocol workaround.
- **Persistent Settings** — Reader, library, theme, and locale preferences are stored in SQLite `app_settings`

## Tech Stack

| Layer               | Technology                                                              |
| ------------------- | ----------------------------------------------------------------------- |
| Runtime             | [Tauri 2](https://v2.tauri.app/)                                        |
| Backend             | Rust + [`rusqlite`](https://github.com/rusqlite/rusqlite) (SQLite)      |
| Frontend            | [React 19](https://react.dev/) + [Vite](https://vite.dev/) + TypeScript |
| Styling             | [TailwindCSS v4](https://tailwindcss.com/)                              |
| Routing             | [TanStack Router](https://tanstack.com/router)                          |
| Data Fetching       | [TanStack Query](https://tanstack.com/query)                            |
| State Management    | [Zustand](https://zustand-demo.pmnd.rs/)                                |
| List Virtualization | [TanStack Virtual](https://tanstack.com/virtual)                        |
| i18n                | [Lingui](https://lingui.dev/)                                           |
| Icons               | [Lucide React](https://lucide.dev/)                                     |
| Linting             | [oxlint](https://oxc-project.github.io/)                                |
| Formatting          | [oxfmt](https://oxc-project.github.io/)                                 |
| Unit Testing        | [Vitest](https://vitest.dev/)                                           |
| E2E Testing         | [Playwright](https://playwright.dev/)                                   |
| Rust Testing        | `cargo test`                                                            |
| Package Manager     | [pnpm](https://pnpm.io/)                                                |

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

The Vite dev server is configured for `http://127.0.0.1:1520`. If Windows blocks that port with `EACCES`, check the excluded TCP port ranges before changing Tauri/Vite config.

### Quality Checks

```bash
pnpm format        # Format code with oxfmt
pnpm lint          # Lint with oxlint
pnpm typecheck     # TypeScript type checking
pnpm test          # Run Vitest tests
npx playwright test # Run Playwright E2E tests
cargo test --manifest-path src-tauri/Cargo.toml # Run Rust tests
```

## Building

Build for a specific platform:

```bash
pnpm tauri:build:linux       # Linux (.deb + .rpm)
pnpm tauri:build:windows     # Windows
pnpm tauri:build:macos       # macOS (universal)
```

Linux builds can also be run through the local CI-mirror script:

```bash
pnpm build:linux             # .deb + .rpm, copied to release/linux
pnpm build:linux:appimage    # AppImage, copied to release/linux
pnpm build:linux:arch        # Arch/CachyOS tarball + PKGBUILD + pacman package
pnpm build:linux:all
```

Linux AppImage requires `linuxdeploy` and is built separately:

```bash
pnpm tauri:build:linux:appimage
```

If Linux shows `Could not connect to localhost: Connection refused` on the app front page, do not assume it is a frontend bug. First verify the Tauri/WebKitGTK production asset protocol path and confirm which URL the webview is loading.

For reader image URLs, Linux/macOS must use `comicrd://localhost/...`. Windows/Android use Wry's `http://comicrd.localhost/...` custom-protocol workaround.

Build for the current machine's default target:

```bash
pnpm tauri:build
```

CI workflows for multi-platform builds are defined in `.github/workflows/desktop-build.yml`.

## Project Structure

```
comicrd/
├── .github/workflows/   # CI/CD workflows
├── e2e/                 # Playwright E2E tests
├── public/              # Static assets
├── src/                 # React frontend (TypeScript)
│   ├── api/             # Tauri IPC wrappers
│   ├── components/      # UI components (virtual-list, card, button, feedback)
│   ├── i18n/            # Lingui bootstrap and lazy-loaded catalogs
│   │   └── messages/    # en / id catalogs as dynamic chunks
│   ├── lib/             # Utilities and pure functions
│   ├── routes/          # Page components (Layout, Library, Comic, Reader, Settings)
│   └── stores/          # Zustand state stores
├── src-tauri/           # Tauri backend (Rust)
├── AGENTS.md            # Agent coding guidelines
├── package.json
├── playwright.config.ts
├── vitest.config.ts
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
