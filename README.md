# ComicRD

ComicRD is a desktop comic reader for local comic libraries. It is built with
Flutter for the desktop UI and Rust for filesystem scanning, archive handling,
SQLite metadata, image rendering, and reader state.

## Features

- Local comic library scanner
- Folder comics, ZIP, and CBZ support
- Library, reading history, and bookmarks views
- Comic and chapter search
- Read, reading, and unread status
- Comic bookmarks and chapter favorites
- Vertical webtoon reader
- Progress restore and automatic progress save
- Previous/next page and chapter navigation
- Keyboard navigation
- Reader zoom, page gap, fullscreen, and image profile controls
- Image resize, cache, and prefetch pipeline in Rust
- SQLite-backed settings, metadata, progress, bookmarks, and history
- Database backup export/import
- Desktop builds for Linux, Windows, and macOS

## Status

ComicRD is under active development. The main Flutter and Rust application
flows are implemented, and Linux release packaging is available. Windows and
macOS builds are configured in CI but still need regular manual smoke testing
on their native platforms.

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

Download the Linux tarball from GitHub Releases, extract it, and run the
bundled executable:

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
- Rust toolchain
- `flutter_rust_bridge_codegen` `2.12.0`
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

Install the bridge generator:

```bash
cargo install flutter_rust_bridge_codegen --version 2.12.0
cargo install cargo-expand
```

### Development Checks

From the repository root:

```bash
cargo test
```

From `app_flutter/`:

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

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
```

The output is written to:

```text
dist/comicrd-1.0.0-linux-x86_64.tar.gz
```

## Release

GitHub Actions builds release assets from version tags:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The `Desktop Build` workflow:

- runs Rust and Flutter checks
- builds Linux, Windows, and macOS bundles
- uploads release assets to GitHub Releases
- publishes `comicrd-bin` to AUR from the Linux tarball

## Repository Layout

```text
comicrd_flutter/
├── app_flutter/              # Flutter desktop UI
│   ├── lib/
│   │   ├── api/              # Dart facade over generated bridge APIs
│   │   ├── pages/            # Route pages
│   │   ├── routes/           # Route helpers
│   │   ├── state/            # Riverpod state
│   │   ├── widgets/          # Shared widgets
│   │   ├── bridge_generated.dart
│   │   ├── api.dart
│   │   ├── frb_generated.dart
│   │   └── frb_generated.io.dart
│   └── pubspec.yaml
│
├── crates/
│   ├── comicrd_core/         # Reusable Rust core
│   └── comicrd_bridge/       # flutter_rust_bridge API crate
│
├── scripts/                  # Packaging helpers
├── docs/
├── Cargo.toml
└── flutter_rust_bridge.yaml
```

## Architecture

Flutter owns the UI, routing, theme, localization, desktop presentation, and
short-lived UI state. Rust owns long-lived application data and heavy work:
SQLite, filesystem discovery, archive page reading, image decoding/resizing,
caches, progress, bookmarks, history, settings, and backup/import.

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

UI code should call `app_flutter/lib/api/comicrd_api.dart` instead of generated
bridge functions directly.

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

## Contributing

1. Run `cargo test` for Rust changes.
2. Run `flutter analyze` and `flutter test` for Flutter or bridge changes.
3. Regenerate and commit bridge files when the public bridge API changes.
4. Keep generated release artifacts out of git.
5. Open an issue or pull request with clear reproduction steps for bugs.

## License

ComicRD is licensed under the MIT License. See [LICENSE](LICENSE).
