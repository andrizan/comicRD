# ComicRD

ComicRD is a desktop comic reader for local libraries. This repository contains
the Flutter + Rust rewrite: Flutter owns the desktop UI, while Rust owns
filesystem discovery, archive handling, SQLite metadata, progress, bookmarks,
history, backup/import, and the reader image pipeline.

## Features

- Local library source selection and validation
- Fast library listing from the top-level filesystem entries
- Explicit full library scan with foreground and background scan APIs
- Folder comics plus ZIP/CBZ and RAR/CBR archive support
- Folder chapter pages can be discovered in nested image directories up to depth 3
- JPEG, PNG, WebP, GIF, BMP, and AVIF page image support
- Library, history, and bookmark tabs
- Grid and list library display modes
- Search, sort by name/date, and unread/reading filters
- Comic bookmarks and chapter favorites
- Chapter listing with progress and page counts
- Vertical/webtoon reader with keyboard navigation, fullscreen, zoom, and page gap controls
- Stable reader scroll/progress from Rust-provided page width/height metadata
- Automatic progress save
- Previous/next chapter navigation
- On-demand page byte loading with bounded prefetch/cache around the current viewport
- SQLite-backed settings, metadata, reading progress, bookmarks, and history
- Database backup export/import
- Linux packaging scripts, GitHub release assets, and AUR publishing support

## Status

ComicRD is under active development. The main Flutter/Rust application flows are
implemented, including library listing, scan, chapter discovery, reader flow,
progress, bookmarks, history, settings, and backup/import. Linux packaging is
available. Windows and macOS build targets are present, but should be smoke
tested on their native platforms before release claims.

## Install

### Arch Linux / CachyOS

```bash
paru -S comicrd-bin
```

or:

```bash
yay -S comicrd-bin
```

### Linux Tarball

Download the Linux tarball from GitHub Releases, extract it, and run the bundled
executable:

```bash
tar -xzf comicrd-1.0.0-linux-x86_64.tar.gz
./comicrd-1.0.0-linux-x86_64/opt/comicrd/ComicRD
```

### Local Pacman Package

On Arch-based systems, a local install package can be created from source:

```bash
./scripts/package-arch-local.sh 1.0.0
sudo pacman -U dist/arch/comicrd-bin-1.0.0-1-x86_64.pkg.tar.zst
```

## Build From Source

### Requirements

- Flutter desktop SDK
- Rust toolchain, currently `rust-version = "1.95"` in the workspace
- `flutter_rust_bridge_codegen` 2.12.0
- `cargo-expand`
- Platform desktop build tools

Linux build dependencies on Arch/CachyOS:

```bash
sudo pacman -S --needed base-devel clang cmake gtk3 ninja pkgconf
```

Linux build dependencies on Ubuntu:

```bash
sudo apt-get install -y build-essential clang cmake libgtk-3-dev ninja-build pkg-config
```

Install the bridge generator and helper tooling:

```bash
cargo install flutter_rust_bridge_codegen --version 2.12.0
cargo install cargo-expand
```

### Development Commands

Run development commands from the repository root unless noted otherwise.

```bash
cargo test
flutter analyze
flutter test
flutter run -d linux
```

To fetch Flutter dependencies directly:

```bash
flutter pub get
```

To build the Rust bridge crate:

```bash
cargo build -p comicrd_bridge --release
```

## Run Locally

For normal Linux desktop development, run from the repository root:

```bash
flutter pub get
flutter run -d linux
```

`flutter run -d linux` drives the Flutter desktop build. During that build,
the Linux CMake file calls `scripts/build-native-bridge.sh`, which builds
`comicrd_bridge` and copies `libcomicrd_bridge.so` into the Flutter bundle.

If you changed Rust code and the running app still behaves like the old binary,
stop the app completely and run it again. Flutter hot reload/hot restart is for
Dart code; it does not reliably reload an already-loaded Rust dynamic library
inside the same desktop process.

### Rebuild The Native Bridge Manually

Use this when the app fails at startup because the native bridge is missing, or
when you want to force-copy a fresh Rust debug library into the Linux Flutter
bundle:

```bash
./scripts/build-native-bridge.sh --platform linux --configuration Debug --destination app_flutter/build/linux/x64/debug/bundle/lib
flutter run -d linux
```

For a release Linux bundle:

```bash
./scripts/build-native-bridge.sh --platform linux --configuration Release --destination app_flutter/build/linux/x64/release/bundle/lib
flutter build linux --release
```

The script builds this Rust artifact:

```text
target/debug/libcomicrd_bridge.so
target/release/libcomicrd_bridge.so
```

and copies it into the Flutter bundle's `lib/` directory.

On Windows, the same job is handled by `scripts/build-native-bridge.ps1` from
the Windows CMake build. On macOS, the Xcode project calls
`scripts/build-native-bridge.sh` and copies `libcomicrd_bridge.dylib` into the
app framework directory.

### When Bridge APIs Change

If you change public bridge functions or DTOs in
`crates/comicrd_bridge/src/api.rs`, regenerate Dart/Rust bindings before
running:

```bash
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
flutter run -d linux
```

If only `comicrd_core` implementation logic changed and the public bridge API is
the same, code generation is not needed. A full app restart is still needed so
the desktop process loads the rebuilt native library.

### Desktop Builds

Linux:

```bash
flutter build linux --release
```

Windows, from a Windows host with Visual Studio desktop build tools:

```bash
flutter build windows --release
```

macOS, from a macOS host with Xcode:

```bash
flutter build macos --release
```

Create the Linux release tarball used by GitHub Releases and AUR:

```bash
./scripts/package-linux.sh 1.0.0
./scripts/package-linux.sh 1.0.0a1
```

The output is written to:

```text
dist/comicrd-1.0.0-linux-x86_64.tar.gz
dist/comicrd-1.0.0a1-linux-x86_64.tar.gz
```

## Repository Layout

```text
comicrd_flutter/
├── app_flutter/              # Flutter desktop UI
│   ├── lib/
│   │   ├── api/              # Dart facade over generated bridge APIs
│   │   ├── pages/            # Library, comic, and reader pages
│   │   ├── routes/           # Route/path helpers
│   │   ├── state/            # Riverpod providers and notifiers
│   │   ├── widgets/          # Shared UI widgets
│   │   ├── app.dart
│   │   ├── main.dart
│   │   ├── bridge_generated.dart
│   │   ├── api.dart
│   │   ├── frb_generated.dart
│   │   └── frb_generated.io.dart
│   ├── linux/
│   ├── windows/
│   ├── test/
│   └── pubspec.yaml
│
├── crates/
│   ├── comicrd_core/         # Reusable Rust core
│   └── comicrd_bridge/       # flutter_rust_bridge API crate
│
├── docs/                     # Migration plans and audits
├── scripts/                  # Packaging helpers
├── Cargo.toml
└── flutter_rust_bridge.yaml
```

Do not reintroduce the old Tauri/React/WebView stack in this repository. The
target architecture is Flutter desktop plus Rust core/bridge crates.

## Architecture

Flutter owns routes, Riverpod state, theme, localization, desktop behavior, and
rendering. Rust owns reusable application data and heavy work:

- filesystem source checks and scanning
- folder and archive chapter discovery
- SQLite migrations and persistence
- reader progress, bookmarks, favorites, and history
- backup export/import
- page source and raw image-byte caching
- image MIME detection and dimension probing

The API boundary is exposed through `flutter_rust_bridge`:

```text
Flutter UI
↓
ComicRdApi Dart facade
↓
Generated flutter_rust_bridge bindings
↓
comicrd_bridge
↓
comicrd_core
```

Flutter UI, page, widget, and state code should call the facade in
`app_flutter/lib/api/comicrd_api.dart` instead of calling generated bridge
functions directly.

## Data Model And Listing

The library tab treats the filesystem as the source of truth for which comics
exist. `list_library_comics_raw` performs a shallow walk of the configured
library root:

- only depth-1 entries are listed
- each top-level folder or archive is one comic
- subfolders are not traversed while listing
- top-level filesystem entries are cached for 30 seconds
- sorting is done by name or folder/archive modified date

The database stores metadata and reader state after a scan or after opening a
comic/chapter. It is not used to enumerate the library listing. Folder comic
chapter counts and read progress come from the database only after they are
known; otherwise the listing returns zero counts. Archive comics are represented
as a single chapter.

An explicit scan walks the depth-1 library entries and upserts comics/chapters
into SQLite. Opening a comic also discovers its chapters on demand.

## Flutter State

The library state is split to avoid loading-state churn while filtering:

- `rawLibraryComicsProvider` fetches raw comics from Rust and watches source
  status plus sort preferences.
- `filteredLibraryComicsProvider` synchronously applies query and view-mode
  filters.
- `libraryComicsProvider` combines the filtered list with pagination.
- `libraryPaginationProvider` tracks the visible count independently.

Search input is debounced in the UI before updating preferences. Scroll offsets
are throttled and restored through local state providers.

## Reader Image Pipeline

The vertical reader uses a metadata-first, bytes-on-demand pipeline:

```text
Open chapter
↓
Rust lists every page entry and probes width/height metadata
↓
Flutter builds a ListView.builder from the full page count
↓
Each page reserves stable space using the Rust width/height metadata
↓
When Flutter builds a page item, it requests only that page's bytes from Rust
↓
Rust reads folder/ZIP/RAR page bytes on demand and returns them through the bridge
```

The reader does not load every image byte in a chapter into Dart memory. Flutter
uses `ListView.builder` with `scrollCacheExtent` and `itemExtentBuilder`; Rust
provides page dimensions so scrollbar, resume, current-page tracking, and
progress remain stable even before the image bytes finish loading.

Format handling:

- folder chapters are scanned for image pages up to depth 3, ignoring hidden and
  system files such as `__MACOSX`, `thumbs.db`, and `desktop.ini`
- ZIP/CBZ chapters are listed from archive entries and page bytes are read by
  entry name on demand
- RAR/CBR chapters use the Rust `unrar` backend and read matching entries on
  demand
- image names are natural-sorted, so `2.png` comes before `10.png`

Memory is bounded around the current viewport:

- Flutter/Riverpod only keeps rendered page providers alive while page widgets
  are built or inside the scroll cache extent
- Flutter prefetches pages from `current - 2` through `current + 2`
- Flutter asks Rust to evict other raw pages for that chapter
- Rust caches up to 2 page sources
- Rust caches up to 6 raw page byte entries
- cached page bytes use `Arc<Vec<u8>>` to avoid deep copies on cache hits inside
  Rust

## Bridge Workflow

The bridge API boundary lives in:

```text
crates/comicrd_bridge/src/api.rs
```

Generated files are committed:

```text
crates/comicrd_bridge/src/frb_generated.rs
app_flutter/lib/api.dart
app_flutter/lib/frb_generated.dart
app_flutter/lib/frb_generated.io.dart
```

Regenerate bindings after changing public bridge structs or functions:

```bash
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

The bridge should stay minimal. Do not send fields that duplicate other fields,
are constant for every item in a response, or are unused by Flutter.

## Tests

Rust integration tests are organized by concern in
`crates/comicrd_core/tests/`, including library source checks, library listing,
scan, chapters, reader flow, image pipeline, cache behavior, bookmarks, history,
migrations, and backup/import.

Focused checks:

```bash
cargo test
flutter analyze
flutter test
```

Run Rust tests for core or bridge changes. Run Flutter analyzer/tests for Dart,
Flutter UI, generated bridge, routing, state, or pubspec changes.

## Release

GitHub Actions builds release assets from version tags:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Use `vX.Y.Zsuffix` for Arch-compatible prerelease tags that should also publish
to AUR, for example `v1.0.0a1`. Tags with underscore or hyphen prerelease
suffixes, such as `v1.0.0_a1` or `v1.0.0-a1`, create GitHub prereleases but are
not published to AUR. Arch accepts underscores in `pkgver`, but `1.0.0_a1`
sorts newer than `1.0.0`, so it is not safe for prereleases in the stable
`comicrd-bin` package.

The `Desktop Build` workflow:

- runs Rust and Flutter checks
- builds Linux, Windows, and macOS bundles
- uploads release assets to GitHub Releases
- publishes `comicrd-bin` to AUR from the Linux tarball

## License

ComicRD is licensed under the MIT License. See [LICENSE](LICENSE).
