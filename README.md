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
- Natural chapter ordering (decimal chapters like `06.5` sort after their whole chapter `06`, with or without archive extensions)
- Vertical/webtoon reader with keyboard navigation, fullscreen, zoom, and page gap controls
- Stable reader scroll/progress from Rust-provided page width/height metadata
- Automatic progress save
- Previous/next chapter navigation
- On-demand page byte loading with bounded prefetch/cache around the current viewport
- On-demand comic thumbnail generation with persistent disk cache (200 MB LRU) and cover display in library, history, and comic detail pages
- Selectable title/path and open-folder action on comic detail page
- SQLite-backed settings, metadata, reading progress, bookmarks, and history
- Database backup export/import
- Optimize Data maintenance: removes comics/chapters no longer on disk, purges orphaned progress/bookmarks/favorites, deletes junk cover thumbnails, vacuums the database, and reports database size before/after
- Auto-update check via GitHub Releases
- Linux packaging scripts, GitHub release assets, and AUR publishing support
- Windows Inno Setup installer

## Status

The main Flutter/Rust application flows are implemented, including library
listing, scan, chapter discovery, reader flow, progress, bookmarks, history,
settings, backup/import, comic thumbnails, and database maintenance
(Optimize Data). Recent work focused on reader performance and quality: blur-free toolbar overlays, per-page `RepaintBoundary` isolation, overlay state decoupled from the page list, width-capped page variants (2048px, SIMD CatmullRom via `fast_image_resize`, lossless PNG for PNG inputs) so tall webtoon strips pass through untouched, strip tiling (2048px tiles, pixel-exact reassembly, page-based progress preserved), and an exact-total scrollbar delegate so the thumb never jumps on variable-height lists. Also UI polish (library/history/detail
covers, selectable metadata, open-folder action, stable sidebar hover state),
performance (persistent thumbnail cache, bounded reader memory), schema cleanup
(dropping unused columns), framework migration to the standalone
`material_ui` package ahead of the November 2026 SDK Material deprecation, and
dependency updates (flutter_rust_bridge 2.13, forui 0.26, go_router 18.0.1, material_ui 1.1.1, fast_image_resize 6.1). Most recent work cut chapter-open image latency (header-probe short-circuit without decoding, lazy per-tile encode with batched prefetch, parallel provider fetch) and gave RAR/CBR chapters extract-once session dirs served from disk. Current versions: app 2.8.1, Rust core/bridge 1.6.1. Linux
packaging is available and the application has been smoke tested directly on
Windows and Linux. The macOS build target is present, but still needs a native
macOS smoke test before release claims for that platform.

## Install

### Arch Linux / CachyOS

```bash
paru -S comicrd-bin
```

or:

```bash
yay -S comicrd-bin
```

### Windows Installer

Download the Windows installer (`*-setup.exe`) from GitHub Releases and run it.
The installer supports per-user installation without admin privileges and creates
an optional desktop shortcut.

### Linux Tarball

Download the Linux tarball from GitHub Releases, extract it, and run the bundled
executable:

```bash
tar -xzf comicrd-2.8.1-linux-x86_64.tar.gz
./comicrd-2.8.1-linux-x86_64/opt/comicrd/ComicRD
```

### Local Pacman Package

On Arch-based systems, a local install package can be created from source:

```bash
./scripts/package-arch-local.sh 2.8.1
sudo pacman -U dist/arch/comicrd-bin-2.8.1-1-x86_64.pkg.tar.zst
```

## Build From Source

### Requirements

- Flutter desktop SDK (3.47 or newer, Dart SDK ^3.12.1)
- Rust toolchain, currently `rustc 1.98`
- `flutter_rust_bridge_codegen` 2.13.0
- `cargo-expand`
- Platform desktop build tools

The app uses Flutter's default rendering engine. Since Flutter 3.47, Impeller is
the default renderer on macOS, Windows, and Linux (Metal on macOS, Vulkan on
Windows/Linux), so no explicit renderer configuration is needed. Do not force
Skia or disable Impeller without a documented reason.

The UI imports Material symbols from the standalone `material_ui` /
`cupertino_ui` packages instead of the copies bundled in the Flutter SDK
(deprecated in the November 2026 stable). No compatibility bridge remains in
`app_flutter/lib` — first-party code has zero legacy SDK Material imports.

Linux build dependencies on Arch/CachyOS:

```bash
sudo pacman -S --needed base-devel clang cmake dav1d gtk3 ninja pkgconf
```

Linux build dependencies on Ubuntu:

```bash
sudo apt-get install -y build-essential clang cmake libdav1d-dev libgtk-3-dev ninja-build pkg-config
```

macOS build dependencies:

```bash
brew install dav1d pkg-config
export PKG_CONFIG_PATH="$(brew --prefix dav1d)/lib/pkgconfig:$(brew --prefix)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
```

Windows build dependencies, from a Windows host with Visual Studio desktop
build tools:

**Option A — vcpkg:**

```powershell
scoop install vcpkg pkg-config
vcpkg install dav1d:x64-windows
$env:PKG_CONFIG_PATH = "$env:VCPKG_ROOT\installed\x64-windows\lib\pkgconfig"
setx PKG_CONFIG_PATH "$env:VCPKG_ROOT\installed\x64-windows\lib\pkgconfig"
```

Di GitHub Actions, vcpkg sudah tersedia otomatis via `$env:VCPKG_INSTALLATION_ROOT`.

**Option B — meson (build from source):**

```powershell
scoop install meson nasm
git clone --depth 1 --branch 1.5.4 https://code.videolan.org/videolan/dav1d.git C:\Users\<you>\dav1d-build
meson setup build --prefix=C:/Users/<you>/dav1d-install --default-library=static -Denable_tools=false -Denable_tests=false -Denable_docs=false
meson compile -C build
meson install -C build
setx PKG_CONFIG_PATH "C:\Users\<you>\dav1d-install\lib\pkgconfig"
```

After `setx`, open a **new terminal** so the variable takes effect. In the
current terminal, run `$env:PKG_CONFIG_PATH = "C:\Users\<you>\dav1d-install\lib\pkgconfig"` instead.

A scripted equivalent of the above is available at
`scripts/setup-dav1d.ps1`; it builds and installs dav1d 1.5.4 to
`%LOCALAPPDATA%\dav1d` and sets `PKG_CONFIG_PATH` to the user environment.

**Persistent `PKG_CONFIG_PATH` via `.cargo/config.toml` (alternative to `setx`, Windows only)**

`setx` and shell session env vars only take effect in new terminals, and tools
like Git for Windows can overwrite `PKG_CONFIG_PATH` on launch. For a
shell-independent fix that always works for `cargo` (including invocations
triggered by `flutter_rust_bridge_codegen generate`), create a local
`.cargo/config.toml` at the repository root:

```toml
# .cargo/config.toml  (local, not committed — see .gitignore)
[env]
PKG_CONFIG_PATH = { value = "C:/Users/<you>/dav1d-install/lib/pkgconfig", force = true }
```

Replace the path with wherever dav1d was installed (for example
`C:/Users/<you>/AppData/Local/dav1d/lib/pkgconfig` when using the meson script
in `scripts/setup-dav1d.ps1`).

**This file is Windows-only and must not be committed.** Cargo's `[env]`
section has no per-target/cfg support, so `force = true` would override
`PKG_CONFIG_PATH` on Linux/macOS too and break the build (the path does not
exist on those platforms, where dav1d is provided by the system package
manager). `.cargo/config.toml` is already in `.gitignore` to prevent
accidental commits; if your install path differs from other Windows
developers, each Windows developer should create the file locally.

Install the bridge generator and helper tooling:

```bash
cargo install flutter_rust_bridge_codegen --version 2.13.0
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

To build the Inno Setup installer (requires
[Inno Setup](https://jrsoftware.org/isinfo.php) installed):

```bash
ISCC.exe /D"AppVersion=2.8.1" app_flutter\windows\installer\comicrd-setup.iss
```

The output is written to `dist/comicrd-{version}-windows-x86_64-setup.exe`.

Windows AVIF support is native and requires the `dav1d` vcpkg package above.
The Windows Flutter build calls `scripts/build-native-bridge.ps1`, which also
uses `VCPKG_INSTALLATION_ROOT` or `VCPKG_ROOT` to populate `PKG_CONFIG_PATH`
when vcpkg is available.

macOS, from a macOS host with Xcode:

```bash
flutter build macos --release
```

Create the Linux release tarball used by GitHub Releases and AUR:

```bash
./scripts/package-linux.sh 2.8.1
```

The output is written to:

```text
dist/comicrd-2.8.1-linux-x86_64.tar.gz
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
│   │   └── installer/       # Inno Setup script
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

Chapter entries are natural-sorted by their display title: archive files are
compared by file stem (not the full file name), so the `.cbz`/`.cbr` extension
never influences ordering and decimal chapters such as `Chapter 06.5` sort
after their whole chapter (`Chapter 06`) and before the next one
(`Chapter 07`).

The `comics` and `chapters` tables keep only fields that are actually read
(`source_path`, `source_type`, `date_modified`, `size_bytes`, `page_count`,
foreign keys). Unused columns such as `created_at`/`updated_at` on those two
tables are not created on fresh databases and are dropped by a migration on
existing databases.

## Database Maintenance

The **Optimize Data** section in Settings runs maintenance on the SQLite
database and thumbnail cache:

- deletes comics whose source path no longer exists on disk, cascading to
  their chapters, reading progress, and page bookmarks
- deletes chapters whose source path no longer exists on disk
- purges orphaned reading-progress rows, page bookmarks, chapter bookmarks, and
  favorites that point at missing comics/chapters
- deletes cached cover thumbnails for comics that no longer exist, so deleted
  comics do not leave junk covers behind
- runs `VACUUM` and a WAL checkpoint so the database file physically shrinks
- skips libraries whose root path is unavailable (for example an unmounted
  drive), so a temporary mount failure can never wipe library data
- reports database size before/after plus how many comics, chapters,
  bookmarks, favorites, and cover images were removed, and how much space was
  freed

The thumbnail cache (`app_data_dir/thumbnails`, named `{width}x{height}-{hash}.jpg`)
is a normal LRU cache, but its size is only trimmed as new covers are written.
Optimize Data is the explicit cleanup that removes orphaned covers immediately.

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
Rust lists every page entry, probes width/height metadata, and computes tile
layout (tile_heights per page; tall pages split into ≤2048px tiles)
↓
Flutter builds a CustomScrollView from the flattened tile list
↓
Each tile reserves stable space using the Rust width/height metadata
↓
When Flutter builds a tile item, it requests only that tile's bytes from Rust
↓
Rust skips decoding entirely for fitting single-tile pages (header probe),
width-caps over-wide pages (2048px, SIMD CatmullRom), encodes only the
requested tile (prefetch batches one decode per page), and returns the tile
on demand
```

The reader does not load every image byte in a chapter into Dart memory. Flutter
uses a custom sliver with an exact-total child delegate (so `maxScrollExtent`
never wobbles and the scrollbar thumb stays put), `scrollCacheExtent`, and
per-tile extents; Rust provides page dimensions so scrollbar, resume,
current-page tracking, and progress remain stable even before the image bytes
finish loading. Progress, bookmarks, and the page indicator stay page-based;
tiles are a rendering detail the database never sees.

Format handling:

- folder chapters are scanned for image pages up to depth 3, ignoring hidden and
  system files such as `__MACOSX`, `thumbs.db`, and `desktop.ini`
- ZIP/CBZ chapters are listed from archive entries and page bytes are read by
  entry name on demand
- RAR/CBR chapters extract image entries once into a session dir under the
  app-data folder on first access; reads and dimension probes are served from
  disk afterwards. Sessions are deleted on reader close/chapter switch,
  follow the page-source LRU while open, and are swept on startup
- image names are natural-sorted, so `2.png` comes before `10.png`

Memory is bounded around the current viewport:

- Flutter/Riverpod only keeps rendered tile providers alive while tile widgets
  are built or inside the scroll cache extent
- Flutter prefetches a small window around the visible tiles, from
  `visibleFirst - 2` through `visibleLast + 2`
- Flutter asks Rust to evict tiles of pages outside that window
- Rust caches up to 2 page sources (RAR session dirs follow the same bound)
- Rust caches up to 16 raw tile byte entries (each tile decodes to at most
  2048x2048x4 = 16MB; GIFs and fitting pages pass through byte-identical)
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
migrations, backup/import, rar/cbr session lifecycle, and database optimization (stale-row purge,
thumbnail cleanup, VACUUM consistency, unavailable-library guard).

Focused checks:

```bash
cargo test
flutter analyze
flutter test
```

Run Rust tests for core or bridge changes. Run Flutter analyzer/tests for Dart,
Flutter UI, generated bridge, routing, state, or pubspec changes.

## License

ComicRD is licensed under the MIT License. See [LICENSE](LICENSE).
