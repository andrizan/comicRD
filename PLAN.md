# ComicRD Plan

## Goal

Build a lightweight local desktop comic reader with a stable webtoon reading experience, fast library browsing, and persistent reading history.

## Current Status

- Implemented: Tauri 2 desktop shell with React 19, Vite, TypeScript, TailwindCSS, TanStack Router, TanStack Query, Lucide icons, and SQLite through `rusqlite`.
- Implemented: Local library source stored in `app_settings.library_source_input`.
- Implemented: Raw library scan lists comic titles from the configured library folder only.
- Implemented: Chapter scan happens only after opening a comic title.
- Implemented: Database writes for comic/chapter/progress happen only when a chapter is opened or read.
- Implemented: Relative history keys based on library source, so progress can survive moving the root folder when the same relative structure is kept.
- Implemented: ZIP/CBZ and folder-image chapter support.
- Implemented: Webtoon-only reader mode.
- Implemented: Reader zoom and page gap stored globally.
- Implemented: Reader close and `Esc` return to the chapter page.
- Implemented: `ArrowUp`/`ArrowDown` and `PageUp`/`PageDown` scroll the reader.
- Implemented: Chapter read/reading/unread status from read-only database lookup.
- Implemented: Database backup export/import.
- Implemented: Light/dark theme stored in `app_settings.app_theme`.
- Implemented: English/Indonesian i18n with English default.
- Implemented: Linux build script produces `.deb` and `.rpm`; AppImage is a separate script because it depends on `linuxdeploy`.
- Implemented: Local `scripts/build-linux.sh` mirrors GitHub Actions for `.deb`/`.rpm`, AppImage, and Arch/CachyOS package generation.

## Performance Rules

- Do not scan chapters on the Library page.
- Do not write comic/chapter metadata during library title scan.
- Do not use Base64 IPC for page images.
- Use `comicrd://localhost/page/{chapterId}/{pageIndex}` for Linux/macOS page image URLs.
- Use `http://comicrd.localhost/page/{chapterId}/{pageIndex}` for Windows/Android only, because Wry maps this form to the registered custom protocol there.
- Never let Linux receive `http://comicrd.localhost/...`; it will try a real localhost connection and fail with `Connection refused`.
- If the Linux front page shows `Could not connect to localhost: Connection refused`, stop and verify the Tauri/WebKitGTK production asset protocol before changing code.
- Keep the reader as a normal vertical document with lazy images; avoid dynamic-height virtualizers in reader mode because they caused page overlap and scroll jumps.
- Keep library list simple and rely on `content-visibility: auto` for large lists.

## Remaining Work

- Add full unit/integration tests after feature stabilization.
- Improve keyboard shortcuts discoverability in reader UI.
- Add more complete empty/error states for broken archives or unreadable image files.
- Add optional thumbnail generation only if it can be done without slowing the first library scan.
- Validate Windows and macOS build outputs in CI or on native machines.

## Build Commands

```bash
pnpm tauri:build:linux
pnpm tauri:build:linux:appimage
pnpm tauri:build:windows
pnpm tauri:build:macos
pnpm build:linux
pnpm build:linux:appimage
pnpm build:linux:arch
pnpm build:linux:all
```

Linux default build creates `.deb` and `.rpm`. AppImage is intentionally separate. Local CI-mirror Linux outputs are copied to `release/linux`.
