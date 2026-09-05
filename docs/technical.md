# Technical Notes

The user-facing summary lives in `README.md`. Agent design rules (source of truth)
live in `AGENTS.md`. This file keeps the technical details trimmed from the README
so they are not lost.

## Rendering & UI Framework

- Use Flutter's default renderer as-is. Since Flutter 3.47, Impeller is the
  default on macOS, Windows, and Linux (Metal on macOS, Vulkan on Windows/Linux).
  Do not force Skia or disable Impeller without a written reason.
- Material symbols are imported from the standalone `material_ui` /
  `cupertino_ui` packages, not from the copies bundled in the Flutter SDK
  (deprecated in the November 2026 stable). No compatibility bridge remains in
  `app_flutter/lib` — first-party code has zero legacy SDK Material imports.

## Windows dav1d & PKG_CONFIG_PATH

From a Windows host with Visual Studio desktop build tools.

Option A — vcpkg:

```powershell
scoop install vcpkg pkg-config
vcpkg install dav1d:x64-windows
$env:PKG_CONFIG_PATH = "$env:VCPKG_ROOT\installed\x64-windows\lib\pkgconfig"
setx PKG_CONFIG_PATH "$env:VCPKG_ROOT\installed\x64-windows\lib\pkgconfig"
```

On GitHub Actions, vcpkg is already available via
`$env:VCPKG_INSTALLATION_ROOT`.

Option B — meson (build from source):

```powershell
scoop install meson nasm
git clone --depth 1 --branch 1.5.4 https://code.videolan.org/videolan/dav1d.git C:\Users\<you>\dav1d-build
meson setup build --prefix=C:/Users/<you>/dav1d-install --default-library=static -Denable_tools=false -Denable_tests=false -Denable_docs=false
meson compile -C build
meson install -C build
setx PKG_CONFIG_PATH "C:\Users\<you>\dav1d-install\lib\pkgconfig"
```

After `setx`, open a new terminal so the variable takes effect. In the current
terminal, use `$env:PKG_CONFIG_PATH = "..."` instead.

Scripted equivalent: `scripts/setup-dav1d.ps1` (builds + installs dav1d 1.5.4 to
`%LOCALAPPDATA%\dav1d`, sets `PKG_CONFIG_PATH` in the user environment).

Persistent alternative via local `.cargo/config.toml` (Windows-only):

```toml
# .cargo/config.toml  (local, not committed — see .gitignore)
[env]
PKG_CONFIG_PATH = { value = "C:/Users/<you>/dav1d-install/lib/pkgconfig", force = true }
```

- `setx` and session env vars only take effect in new terminals, and tools like
  Git for Windows can overwrite `PKG_CONFIG_PATH` on launch. `.cargo/config.toml`
  always applies to `cargo` (including via `flutter_rust_bridge_codegen generate`).
- This file is Windows-only and must not be committed. Cargo's `[env]` section has
  no per-target/cfg support, so `force = true` would override `PKG_CONFIG_PATH` on
  Linux/macOS too and break the build (the path does not exist there; dav1d comes
  from the system package manager). The file is already in `.gitignore`; each
  Windows developer creates it locally with their own path.

## Native Bridge Build

- `flutter run -d linux` drives the Flutter desktop build. The Linux CMake file
  calls `scripts/build-native-bridge.sh`, which builds `comicrd_bridge` and copies
  `libcomicrd_bridge.so` into the Flutter bundle.
- Hot reload/restart is Dart-only. If you changed Rust code but the app still
  behaves like the old binary, stop the app completely and run it again — an
  already-loaded Rust dynamic library is not reliably reloaded in the same desktop
  process.
- Manual rebuild (missing bridge at startup / force a fresh copy):

```bash
./scripts/build-native-bridge.sh --platform linux --configuration Debug --destination app_flutter/build/linux/x64/debug/bundle/lib
./scripts/build-native-bridge.sh --platform linux --configuration Release --destination app_flutter/build/linux/x64/release/bundle/lib
```

Rust artifacts built:

```text
target/debug/libcomicrd_bridge.so
target/release/libcomicrd_bridge.so
```

Copied into the Flutter bundle's `lib/` directory.

- Windows: `scripts/build-native-bridge.ps1` from the Windows CMake build.
- macOS: the Xcode project calls `scripts/build-native-bridge.sh` and copies
  `libcomicrd_bridge.dylib` into the app framework directory.

## Desktop Builds & Packaging

```bash
flutter build linux --release
flutter build windows --release
flutter build macos --release
ISCC.exe /D"AppVersion=2.8.1" app_flutter\windows\installer\comicrd-setup.iss
./scripts/package-linux.sh 2.8.1
```

- The Windows installer requires [Inno Setup](https://jrsoftware.org/isinfo.php).
  Output: `dist/comicrd-{version}-windows-x86_64-setup.exe`.
- Windows AVIF support is native and requires the `dav1d` vcpkg package above. The
  Windows Flutter build calls `scripts/build-native-bridge.ps1`, which uses
  `VCPKG_INSTALLATION_ROOT` / `VCPKG_ROOT` to populate `PKG_CONFIG_PATH` when
  vcpkg is available.
- The Linux tarball is used by GitHub Releases and AUR. Output:
  `dist/comicrd-2.8.1-linux-x86_64.tar.gz`.

## Repository Layout (Full)

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

Do not reintroduce the old Tauri/React/WebView stack. The target architecture is
Flutter desktop plus Rust core/bridge crates.

## Architecture (Full)

Flutter: routes, Riverpod state, theme, localization, desktop behavior, rendering.
Rust: reusable application data and heavy work:

- filesystem source checks and scanning
- folder and archive chapter discovery
- SQLite migrations and persistence
- reader progress, bookmarks, favorites, and history
- backup export/import
- page source and raw image-byte caching
- image MIME detection and dimension probing

API boundary via `flutter_rust_bridge`:

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

UI/page/widget/state code calls the facade in
`app_flutter/lib/api/comicrd_api.dart`, not generated bridge functions directly.

## Data Model And Listing (Full)

The library tab treats the filesystem as the source of truth.
`list_library_comics_raw` shallow-walks the library root:

- only depth-1 entries are listed
- each top-level folder/archive is one comic
- subfolders are not traversed while listing
- top-level filesystem entries are cached for 30 seconds
- sorting by name or folder/archive modified date

The database stores metadata and reader state after a scan or after opening a
comic/chapter. The DB is not used to enumerate the listing. Folder comic chapter
counts and read progress come from the DB only when already known; otherwise the
listing returns zero counts. Archive comics are represented as a single chapter.

An explicit scan walks depth-1 entries then upserts comics/chapters into SQLite.
Opening a comic also discovers chapters on demand.

Chapters are natural-sorted by display title: archive files are compared by file
stem (not the full file name), so the `.cbz`/`.cbr` extension never affects
ordering and decimal chapters such as `Chapter 06.5` sort after `Chapter 06` and
before `Chapter 07`.

The `comics` and `chapters` tables keep only fields that are actually read
(`source_path`, `source_type`, `date_modified`, `size_bytes`, `page_count`,
foreign keys). Unused columns such as `created_at`/`updated_at` are not created
on fresh DBs and are dropped via migration on existing DBs.

## Database Maintenance (Full)

Settings → Optimize Data runs maintenance on the SQLite database and thumbnail
cache:

- deletes comics whose source path no longer exists on disk (cascading to
  chapters, reading progress, and page bookmarks)
- deletes chapters whose source path no longer exists on disk
- purges orphaned reading-progress rows, page bookmarks, chapter bookmarks, and
  favorites pointing at missing comics/chapters
- deletes cached cover thumbnails for comics that no longer exist
- runs `VACUUM` and a WAL checkpoint so the DB file physically shrinks
- skips libraries whose root path is unavailable (for example an unmounted
  drive), so a temporary mount failure never wipes library data
- reports DB size before/after plus how many comics, chapters, bookmarks,
  favorites, and covers were removed, and how much space was freed

The thumbnail cache (`app_data_dir/thumbnails`, named `{width}x{height}-{hash}.jpg`)
is a normal LRU, but its size is only trimmed when new covers are written.
Optimize Data is the explicit cleanup that removes orphan covers immediately.

## Flutter State (Full)

Library state is split so filtering does not trigger loading-state churn:

- `rawLibraryComicsProvider` fetches raw comics from Rust; watches source status +
  sort preferences.
- `filteredLibraryComicsProvider` applies query and view-mode filters
  synchronously.
- `libraryComicsProvider` combines the filtered list with pagination.
- `libraryPaginationProvider` tracks the visible count independently.

Search input is debounced in the UI before updating preferences. Scroll offsets
are throttled and restored via local state providers.

## Reader Image Pipeline (Full)

Metadata-first, bytes-on-demand pipeline:

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

The reader never loads all image bytes of a chapter into Dart memory. Flutter uses
a custom sliver with an exact-total child delegate (so `maxScrollExtent` never
wobbles and the scrollbar thumb stays stable), `scrollCacheExtent`, and per-tile
extents; Rust-provided dimensions keep scrollbar, resume, current-page tracking,
and progress stable even before image bytes finish loading. Progress, bookmarks,
and the page indicator stay page-based; tiles are a rendering detail unknown to
the DB.

Format handling:

- folder chapters are scanned up to depth 3, ignoring hidden/system files such as
  `__MACOSX`, `thumbs.db`, and `desktop.ini`
- ZIP/CBZ chapters are listed from archive entries; page bytes are read by entry
  name on demand
- RAR/CBR chapters extract image entries once into a session dir under the
  app-data folder on first access; reads and dimension probes are served from disk
  afterwards. Sessions are deleted on reader close/chapter switch, follow the
  page-source LRU while open, and are swept on startup
- image names are natural-sorted (`2.png` before `10.png`)

Memory is bounded around the viewport:

- Flutter/Riverpod only keeps rendered tile providers while tile widgets are built
  or inside the scroll cache extent
- Flutter prefetches a small window around the visible tiles (`visibleFirst - 2`
  through `visibleLast + 2`)
- Flutter asks Rust to evict tiles outside that window
- Rust caches up to 2 page sources (RAR session dirs follow the same bound)
- Rust caches up to 16 raw tile byte entries (each tile decodes to at most
  2048x2048x4 = 16MB; GIFs and fitting pages pass through byte-identical)
- cached page bytes use `Arc<Vec<u8>>` so cache hits inside Rust avoid deep copies

## Bridge Workflow (Full)

API boundary: `crates/comicrd_bridge/src/api.rs`. Generated files are committed:

```text
crates/comicrd_bridge/src/frb_generated.rs
app_flutter/lib/api.dart
app_flutter/lib/frb_generated.dart
app_flutter/lib/frb_generated.io.dart
```

Regenerate after changing public bridge structs/functions:

```bash
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

The bridge must stay minimal. Do not send fields that duplicate other fields, are
constant for every item in a response, or are unused by Flutter.

## Tests (Full)

Rust integration tests per concern in `crates/comicrd_core/tests/`: library source
checks, library listing, scan, chapters, reader flow, image pipeline, cache
behavior, bookmarks, history, migrations, backup/import, rar/cbr session lifecycle,
and database optimization (stale-row purge, thumbnail cleanup, VACUUM consistency,
unavailable-library guard).

```bash
cargo test
flutter analyze
flutter test
```

Rust tests for core/bridge changes. Flutter analyzer/tests for Dart, UI, generated
bridge, routing, state, or pubspec changes.
