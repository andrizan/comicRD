# ComicRD

Desktop comic reader for local libraries. Flutter owns the desktop UI; Rust owns
filesystem discovery, archives, SQLite metadata, progress, bookmarks, history,
backup/import, and the reader image pipeline.

Technical details: `docs/technical.md`.

## Features

- Library source selection + fast top-level listing + explicit full scan
- Folder, ZIP/CBZ, and RAR/CBR support; nested folder pages to depth 3
- JPEG, PNG, WebP, GIF, BMP, and AVIF pages
- Library/history/bookmark tabs; grid/list modes; search, sort, unread/reading filters
- Chapters with progress, page counts, and natural ordering (`06.5` after `06`)
- Vertical reader: keyboard, fullscreen, zoom, page gap, stable scroll, auto-save progress, prev/next chapter
- On-demand page bytes with bounded prefetch/cache; on-demand thumbnails (200 MB LRU disk cache)
- Comic detail: selectable title/path, open-folder action, covers
- SQLite settings/progress/bookmarks/history; backup export/import; Optimize Data (purge stale + VACUUM + report)
- Auto-update via GitHub Releases; Linux packaging/AUR; Windows installer

## Status

Main app flows are done: library listing/scan, chapters, reader, progress, bookmarks, history, settings, backup/import, thumbnails, and Optimize Data. Reader loads page bytes on demand with 2048px tiling and a stable scrollbar. Smoke tested on Windows and Linux with Linux packaging available. macOS target exists but still needs a native smoke test.

## Install

### Arch Linux / CachyOS

```bash
paru -S comicrd-bin
# or: yay -S comicrd-bin
```

### Windows Installer

Download `*-setup.exe` from GitHub Releases. Per-user install, no admin needed.

### Linux Tarball

```bash
tar -xzf comicrd-2.8.1-linux-x86_64.tar.gz
./comicrd-2.8.1-linux-x86_64/opt/comicrd/ComicRD
```

### Local Pacman Package

```bash
./scripts/package-arch-local.sh 2.8.1
sudo pacman -U dist/arch/comicrd-bin-2.8.1-1-x86_64.pkg.tar.zst
```

## Build From Source

### Requirements

- Flutter desktop SDK (3.47+, Dart ^3.12.1)
- Rust toolchain (`rustc 1.98`)
- `flutter_rust_bridge_codegen` 2.13.0, `cargo-expand`
- Platform desktop build tools

Uses Flutter's default renderer (Impeller since 3.47), no extra config.
Material symbols come from `material_ui` / `cupertino_ui` (SDK copies deprecated Nov 2026).

Arch/CachyOS:

```bash
sudo pacman -S --needed base-devel clang cmake dav1d gtk3 ninja pkgconf
```

Ubuntu:

```bash
sudo apt-get install -y build-essential clang cmake libdav1d-dev libgtk-3-dev ninja-build pkg-config
```

macOS:

```bash
brew install dav1d pkg-config
export PKG_CONFIG_PATH="$(brew --prefix dav1d)/lib/pkgconfig:$(brew --prefix)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
```

Windows (Visual Studio build tools required):

```powershell
# Option A — vcpkg
scoop install vcpkg pkg-config
vcpkg install dav1d:x64-windows
setx PKG_CONFIG_PATH "$env:VCPKG_ROOT\installed\x64-windows\lib\pkgconfig"
```

```powershell
# Option B — meson, or run scripts/setup-dav1d.ps1 (installs to %LOCALAPPDATA%\dav1d)
scoop install meson nasm
git clone --depth 1 --branch 1.5.4 https://code.videolan.org/videolan/dav1d.git C:\Users\<you>\dav1d-build
meson setup build --prefix=C:/Users/<you>/dav1d-install --default-library=static -Denable_tools=false -Denable_tests=false -Denable_docs=false
meson compile -C build
meson install -C build
setx PKG_CONFIG_PATH "C:\Users\<you>\dav1d-install\lib\pkgconfig"
```

After `setx`, open a new terminal. Alternative (Windows-only, do not commit):
local `.cargo/config.toml` (already gitignored):

```toml
[env]
PKG_CONFIG_PATH = { value = "C:/Users/<you>/dav1d-install/lib/pkgconfig", force = true }
```

Install tooling:

```bash
cargo install flutter_rust_bridge_codegen --version 2.13.0
cargo install cargo-expand
```

### Development Commands

```bash
cargo test
flutter analyze
flutter test
flutter run -d linux
flutter pub get
cargo build -p comicrd_bridge --release
```

## Run Locally

```bash
flutter pub get
flutter run -d linux
```

CMake calls `scripts/build-native-bridge.sh` automatically. Hot reload is
Dart-only — restart the app fully for Rust changes.

Manual bridge rebuild (missing bridge at startup / force fresh copy):

```bash
./scripts/build-native-bridge.sh --platform linux --configuration Debug --destination app_flutter/build/linux/x64/debug/bundle/lib
./scripts/build-native-bridge.sh --platform linux --configuration Release --destination app_flutter/build/linux/x64/release/bundle/lib
```

Windows uses `scripts/build-native-bridge.ps1`; macOS copies
`libcomicrd_bridge.dylib` via Xcode.

When `crates/comicrd_bridge/src/api.rs` changes:

```bash
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

No codegen needed for `comicrd_core`-only changes, but still restart the app.

### Desktop Builds

```bash
flutter build linux --release
flutter build windows --release
flutter build macos --release
ISCC.exe /D"AppVersion=2.8.1" app_flutter\windows\installer\comicrd-setup.iss
./scripts/package-linux.sh 2.8.1
```

## Repository Layout

```text
comicrd_flutter/
├── app_flutter/              # Flutter desktop UI
│   ├── lib/
│   │   ├── api/              # Dart facade over generated bridge APIs
│   │   ├── pages/
│   │   ├── routes/
│   │   ├── state/
│   │   ├── widgets/
│   │   └── bridge_generated.dart
│   └── pubspec.yaml
├── crates/
│   ├── comicrd_core/         # Reusable Rust core
│   └── comicrd_bridge/       # flutter_rust_bridge API crate
├── docs/
├── scripts/
└── flutter_rust_bridge.yaml
```

No Tauri/React/WebView — Flutter desktop + Rust core/bridge only.

## Architecture

Flutter: routes, Riverpod state, theme, localization, desktop behavior, rendering.
Rust: source checks/scanning, chapter discovery, SQLite, progress/bookmarks/history,
backup, page/image caching, MIME + dimension probing.

```text
Flutter UI → ComicRdApi facade → FRB bindings → comicrd_bridge → comicrd_core
```

UI code calls `app_flutter/lib/api/comicrd_api.dart`, not generated functions directly.

## Data Model And Listing

Filesystem is the source of truth (`list_library_comics_raw`: depth-1 walk, one
top-level folder/archive = one comic, 30s entry cache, sort by name/date).
DB stores scan results and reader state only — unlisted/unscanned comics report
`0/0/0` counts. Explicit scan upserts to SQLite; opening a comic discovers
chapters on demand. Chapters are natural-sorted by stem (`06.5` after `06`).

## Database Maintenance

Settings → Optimize Data: deletes missing comics/chapters + orphaned
progress/bookmarks/favorites/covers, skips unavailable library roots, runs
`VACUUM` + WAL checkpoint, reports size before/after and freed space.
Thumbnail cache (`app_data_dir/thumbnails`) trims on write; Optimize Data purges
orphans immediately.

## Flutter State

`rawLibraryComicsProvider` fetches from Rust; `filteredLibraryComicsProvider`
applies query/view-mode sync; `libraryComicsProvider` + `libraryPaginationProvider`
handle pagination. Search is debounced, scroll offsets throttled.

## Reader Image Pipeline

Metadata-first, bytes-on-demand: Rust lists pages, probes width/height, splits
tall pages into ≤2048px tiles; Flutter renders flattened tiles with stable
extents and an exact-total sliver (no scrollbar jumps); tile bytes load only on
build/prefetch. Progress/bookmarks stay page-based.

- Folder: depth 3, ignores dotfiles/`__MACOSX`/`thumbs.db`/`desktop.ini`
- ZIP/CBZ: read entry bytes on demand
- RAR/CBR: extract-once session dir under app-data, served from disk, LRU (max 2), swept on startup
- Natural sort (`2.png` before `10.png`); bounded memory (prefetch ±2 tiles, 2 page sources, 16 raw tiles)

## Bridge Workflow

Boundary: `crates/comicrd_bridge/src/api.rs`. Generated files are committed
(`frb_generated.rs`, `api.dart`, `frb_generated.dart`, `frb_generated.io.dart`).
Keep the bridge minimal: no duplicate/constant/unused fields.

## Tests

```bash
cargo test
flutter analyze
flutter test
```

Rust tests live in `crates/comicrd_core/tests/` (per concern); Dart tests in `app_flutter/test/`.

## License

MIT. See [LICENSE](LICENSE).
