# ComicRD Technical Notes

Developer documentation for the Flutter + Rust rewrite. The user-facing summary
lives in `README.md`; the design rules agents must follow (reader pipeline,
cache policy, bridge minimization, provider architecture) are the source of
truth in `AGENTS.md`.

Contents:

- [Requirements](#requirements)
- [Run Locally](#run-locally)
- [Bridge Workflow](#bridge-workflow)
- [Desktop Builds And Packaging](#desktop-builds-and-packaging)
- [Continuous Integration](#continuous-integration)
- [Repository Layout](#repository-layout)
- [Architecture](#architecture)
- [Rendering, UI Framework And Design System](#rendering-ui-framework-and-design-system)
- [Data Model And Listing](#data-model-and-listing)
- [Database Maintenance](#database-maintenance)
- [Flutter State](#flutter-state)
- [Reader Image Pipeline](#reader-image-pipeline)
- [Tests](#tests)

## Requirements

- Flutter desktop SDK (3.47+, Dart ^3.12.1)
- Rust toolchain (`rustc 1.98`)
- `flutter_rust_bridge_codegen` 2.13.0, `cargo-expand`
- Platform desktop build tools (below)

### Linux (Arch/CachyOS)

```bash
sudo pacman -S --needed base-devel clang cmake ninja pkgconf gtk3 dav1d
```

Debian/Ubuntu: `build-essential clang cmake ninja-build pkg-config libgtk-3-dev libdav1d-dev`.

### Windows

Visual Studio 2022 with the "Desktop development with C++" workload, plus dav1d
for AVIF decoding (the Rust `image` AVIF decoder links against it through
`pkg-config`).

Option A — vcpkg:

```powershell
scoop install vcpkg pkg-config
vcpkg install dav1d:x64-windows
$env:PKG_CONFIG_PATH = "$env:VCPKG_ROOT\installed\x64-windows\lib\pkgconfig"
setx PKG_CONFIG_PATH "$env:VCPKG_ROOT\installed\x64-windows\lib\pkgconfig"
```

On GitHub Actions, vcpkg is already available via `$env:VCPKG_INSTALLATION_ROOT`.

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

Persistent alternative via a local `.cargo/config.toml` (Windows-only):

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

### macOS

```bash
brew install dav1d pkg-config
```

## Run Locally

```bash
cd app_flutter
flutter pub get
flutter run -d linux
```

Everyday commands:

```bash
cargo test
flutter analyze
flutter test
cargo build -p comicrd_bridge --release
```

### Native Bridge Build

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

- Windows: `scripts/build-native-bridge.ps1` from the Windows CMake build; it uses
  `VCPKG_INSTALLATION_ROOT` / `VCPKG_ROOT` to populate `PKG_CONFIG_PATH` when
  vcpkg is available.
- macOS: the Xcode project calls `scripts/build-native-bridge.sh` and copies
  `libcomicrd_bridge.dylib` into the app framework directory.

## Bridge Workflow

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

No codegen is needed for `comicrd_core`-only changes, but still restart the app.
The bridge must stay minimal: do not send fields that duplicate other fields, are
constant for every item in a response, or are unused by Flutter.

## Desktop Builds And Packaging

```bash
flutter build linux --release
flutter build windows --release
flutter build macos --release
ISCC.exe /D"AppVersion=2.8.3" app_flutter\windows\installer\comicrd-setup.iss
./scripts/package-linux.sh 2.8.3
```

- The Windows installer requires [Inno Setup](https://jrsoftware.org/isinfo.php).
  Output: `dist/comicrd-{version}-windows-x86_64-setup.exe`. Windows AVIF support
  is native and requires the dav1d setup above.
- The Linux tarball is used by GitHub Releases and AUR. Output:
  `dist/comicrd-2.8.3-linux-x86_64.tar.gz`.
- Local pacman package for testing the AUR layout:

```bash
./scripts/package-arch-local.sh 2.8.3
sudo pacman -U dist/arch/comicrd-bin-2.8.3-1-x86_64.pkg.tar.zst
```

## Continuous Integration

`.github/workflows/desktop-build.yml`:

- `quality` runs `cargo test`, `flutter analyze` and `flutter test` on every push
  and pull request.
- `build-linux`, `build-windows` and `build-macos` run on tags (`v*`) or manual
  dispatch, bump `app_flutter/pubspec.yaml` to the tag version, and upload the
  tarball, zip, installer and macOS bundle as artifacts.
- `release` collects the artifacts into a GitHub Release (prerelease when the
  tag carries a suffix) and commits the version bump to `master`; `publish-aur`
  updates the `comicrd-bin` AUR package from the published tarball checksum.
- `cache-dav1d` warms the Windows dav1d cache on pushes to `master` so tag builds
  skip the meson build; the Windows job also builds it itself on a cold cache.

The repeated steps live in composite actions under `.github/actions/`:

| Action | Purpose |
| --- | --- |
| `setup-toolchain` | Flutter + Rust toolchains with caches and the native dependencies of the runner OS (`flutter: "false"` for Rust-only jobs) |
| `dav1d-windows` | Restore-or-build a static dav1d 1.5.4 and export `PKG_CONFIG_PATH` |
| `release-version` | Tag validation, `version`/`prerelease` outputs and the pubspec bump, in one bash implementation for all platforms |

Workflow permissions are read-only by default; only the release job has
`contents: write`. `codeql.yml` scans the Rust workspace (CodeQL has no Dart
support).

## Repository Layout

```text
comicrd_flutter/
├── app_flutter/              # Flutter desktop UI
│   ├── lib/
│   │   ├── api/              # Dart facade over generated bridge APIs
│   │   ├── pages/            # library, comic, reader, settings
│   │   ├── routes/           # Route/path helpers
│   │   ├── state/            # Riverpod providers, settings, strings
│   │   ├── utils/            # theme tokens, formatting, update checker
│   │   ├── widgets/          # soft_ui building blocks, thumbnails
│   │   ├── app.dart          # router, shell, sidebar
│   │   ├── main.dart
│   │   ├── bridge_generated.dart
│   │   ├── api.dart
│   │   ├── frb_generated.dart
│   │   └── frb_generated.io.dart
│   ├── assets/               # Plus Jakarta Sans, app icon source
│   ├── linux/
│   ├── windows/
│   │   └── installer/        # Inno Setup script
│   ├── test/                 # widget/unit tests, support/ helpers, screenshot tool
│   └── pubspec.yaml
│
├── crates/
│   ├── comicrd_core/         # Reusable Rust core
│   └── comicrd_bridge/       # flutter_rust_bridge API crate
│
├── docs/                     # this file and the README screenshots
├── scripts/                  # bridge build, packaging, icon generation
├── .github/                  # workflows and composite actions
├── Cargo.toml
└── flutter_rust_bridge.yaml
```

Do not reintroduce the old Tauri/React/WebView stack. The target architecture is
Flutter desktop plus Rust core/bridge crates.

## Architecture

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

## Rendering, UI Framework And Design System

- Use Flutter's default renderer as-is. Since Flutter 3.47, Impeller is the
  default on macOS, Windows, and Linux (Metal on macOS, Vulkan on Windows/Linux).
  Do not force Skia or disable Impeller without a written reason.
- Material symbols are imported from the standalone `material_ui` /
  `cupertino_ui` packages, not from the copies bundled in the Flutter SDK
  (deprecated in the November 2026 stable). No compatibility bridge remains in
  `app_flutter/lib` — first-party code has zero legacy SDK Material imports.
- Controls come from `forui` (`FTheme`, popover menus, tooltips, toaster) with
  Lucide icons from `forui_lucide`.

The UI follows a soft, modern system: a lavender-cream ground with white cards
and tinted shadows, radii 12–28, one 44 px control height, accent reserved for
the active state and amber for bookmark/"new" markers, set in Plus Jakarta Sans
(bundled under `app_flutter/assets/fonts`, OFL).

- Tokens: `app_flutter/lib/utils/forui_theme.dart` — `ComicReaderFTheme`
  (light/dark `FThemeData`), `ComicReaderColors` (theme extension: canvas,
  progress, badge, star, success, line, shadow, scrim), `AppShape` (radii,
  control height, shadows) and `AppIcons`.
- Shared widgets: `app_flutter/lib/widgets/soft_ui.dart` — `SoftCard`,
  `HoverCard`, `SoftButton`, `SoftIconButton`, `SoftChip`, `SoftSegmented`,
  `SoftSortMenu`, `SoftPill`, `SoftSwitch`, `SoftSlider`, `SoftSearchField`,
  `SoftProgressBar`, `SoftBadge`, `CoverThumbnail`, `PageHeading`,
  `SectionHeading`, `SoftEmptyState`. Pages compose these instead of styling
  raw containers.
- The reader chrome (`_ReaderTopBar`, Display/Mark panels, `_ReaderPageBar`)
  uses its own fixed dark palette so pages keep the same surround in both
  themes; it deliberately draws no `BackdropFilter` (a fullscreen blur is
  recomputed every scrolled frame).
- Contrast was verified by calculation: every text pairing is at least 4.5:1
  and every UI pairing at least 3:1 in both themes. Keyboard focus rings,
  `Semantics` labels/toggle states and tooltips are part of the shared widgets.

## Data Model And Listing

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
Opening a comic also discovers chapters on demand. Picking a folder on the
first-run screen stores it, registers the library and starts a background scan.

Chapters are natural-sorted by display title: archive files are compared by file
stem (not the full file name), so the `.cbz`/`.cbr` extension never affects
ordering and decimal chapters such as `Chapter 06.5` sort after `Chapter 06` and
before `Chapter 07`.

The `comics` and `chapters` tables keep only fields that are actually read
(`source_path`, `source_type`, `date_modified`, `size_bytes`, `page_count`,
foreign keys). Unused columns such as `created_at`/`updated_at` are not created
on fresh DBs and are dropped via migration on existing DBs.

## Database Maintenance

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

## Flutter State

Library state is split so filtering does not trigger loading-state churn:

- `rawLibraryComicsProvider` fetches raw comics from Rust; watches source status +
  sort preferences.
- `filteredLibraryComicsProvider` applies query and view-mode filters
  synchronously.
- `libraryComicsProvider` combines the filtered list with pagination.
- `libraryPaginationProvider` tracks the visible count independently.

Search input is debounced in the UI before updating preferences. Scroll offsets
are throttled and restored via local state providers.

The shell (`ComicRdShell`) hydrates the stored settings once into the app,
library and reader notifiers; the sidebar selection derives from the current
route and `libraryPreferencesProvider.selectedTab`, so a tab change made inside
a page ("View History") is reflected without a second source of truth.
`library_source_actions.dart` holds the shared "set library folder" and
"invalidate library data" steps used by the first-run screen and Settings.

## Reader Image Pipeline

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

With unlimited scroll the reader is a continuous strip rather than one chapter
per page. `ReaderStrip` chains the opened chapter with its neighbours; the next
and the previous chapter's page list is fetched once the viewport is within
three screens of that end, so crossing into it never waits on
a load and never reloads the page. A separator at each boundary shows the chapter
that was finished and the one that follows (title, position in the comic, page
count). The chapter at the viewport centre drives the top bar, page bar, marks
and progress; moving into the next chapter marks the previous one read and
records the new one immediately. Prepending a chapter above the viewport shifts
the scroll offset by exactly its height so the page being read does not move.
Tile prefetch, eviction and the exact-total sliver work unchanged over the whole
strip, split per chapter.

The reader chrome (toolbar, Display/Mark panels, segmented page bar) is an
overlay rebuilt on its own version counter (`_overlayVersion`), so opening a
panel or moving the current page never relayouts the page strip. Keyboard:
`Esc` closes an open panel, then fullscreen, then the reader; `↑ ↓` / `PgUp
PgDn` scroll; `← →` switch chapter; `0` / `Home` jump to the first page.

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

## Tests

```bash
cargo test
flutter analyze
flutter test
flutter test --coverage   # writes app_flutter/coverage/lcov.info (gitignored)
```

Rust tests for core/bridge changes; Flutter analyzer/tests for Dart, UI,
generated bridge, routing, state, or pubspec changes.

### Rust

Integration tests per concern in `crates/comicrd_core/tests/`: library source
checks, library listing, scan, chapters, reader flow, image pipeline, cache
behavior, bookmarks, history, migrations, backup/import, rar/cbr session lifecycle,
and database optimization (stale-row purge, thumbnail cleanup, VACUUM consistency,
unavailable-library guard). Unit tests are inline (`chapter.rs`,
`image_pipeline.rs`, `library.rs`).

### Flutter

Widget and unit tests in `app_flutter/test/`:

| File | Covers |
| --- | --- |
| `app_shell_test.dart` | sidebar tabs and persistence, badges, status card states, collapse/expand, `Ctrl+T`/`Ctrl+L` |
| `library_page_test.dart` | first-run screen, source error banner, continue-reading shelf, filter chips, sort, list mode, search, history, favorites, card menus |
| `comic_page_ui_test.dart`, `comic_page_test.dart`, `comic_bookmark_test.dart` | header/progress card, chapter rows and resume, bookmark tab, sort, menus, auto-scroll, favorite toggle |
| `reader_page_test.dart`, `reader_chrome_test.dart`, `reader_state_test.dart`, `reader_tiles_test.dart` | pipeline (lazy render, prefetch/evict, tiles, unlimited scroll) and chrome (panels, `0` key, page bar, track taps, back) |
| `settings_page_test.dart` | sections, theme/locale, switches, sliders, scan progress/cancel, optimize, path save, update flow, section navigation |
| `soft_ui_test.dart` | every shared widget |
| `strings_test.dart`, `update_test.dart`, `library_source_actions_test.dart`, `comic_thumbnail_*_test.dart`, `back_to_top_button_test.dart` | strings tables, update parsing/notifier, source actions, thumbnails |

Shared helpers under `test/support/`: `fake_api.dart` (`FakeComicRdApi`, an
in-memory `ComicRdApi` with a small library that records every call — extend it
rather than adding fakes) and `router_host.dart` (`pumpRoutedPage`, one page
under a private GoRouter whose other routes render their location as text, with
settings hydration like the shell). Environment traps worth knowing are listed
in `AGENTS.md` → "Flutter Tests" (double-tap arena in the shell, test font
widths, tooltip timers, lazy lists).

### Screenshots

The README images are produced headlessly, with the bundled fonts and sample
data, by a gated test:

```bash
cd app_flutter
COMICRD_SCREENSHOTS=1 flutter test test/screenshots_test.dart   # → build/screenshots/*.png
```

`COMICRD_SCREENSHOT_DIR` overrides the output folder. Copy the ones you want
into `docs/screenshots/`.
