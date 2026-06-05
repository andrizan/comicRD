# Agent Instructions

This repository is the Flutter + Rust rewrite of ComicRD. Follow these project-specific instructions in addition to the system and developer instructions.

## Command Wrapper

All shell commands in this workspace must be prefixed with `rtk`.

Examples:

```bash
rtk cargo test
rtk flutter analyze
rtk flutter test
rtk git status --short
```

The local wrapper policy comes from:

```text
@/home/andrizan/.codex/RTK.md
```

## Architecture

Keep the target layout intact:

```text
comicrd_flutter/
├── app_flutter/              # Flutter desktop UI
│   ├── lib/
│   │   ├── api/
│   │   ├── pages/
│   │   ├── routes/
│   │   ├── state/
│   │   ├── widgets/
│   │   └── bridge_generated.dart
│   └── pubspec.yaml
│
├── crates/
│   ├── comicrd_core/         # Reusable Rust core
│   └── comicrd_bridge/       # flutter_rust_bridge wrapper
└── flutter_rust_bridge.yaml
```

Do not reintroduce Tauri, React, WebView, TanStack, Zustand, Tailwind, or Tauri command APIs into this rewrite.

## Ownership Boundaries

- `comicrd_core` owns filesystem scanning, ZIP/CBZ reading, SQLite, metadata, reader progress, bookmarks, history, backup/import, image decoding/resizing, cache, prefetch, and business rules.
- `comicrd_bridge` owns the Flutter Rust Bridge API surface and conversion DTOs.
- `app_flutter` owns routes, Riverpod state, theme, localization, widgets, keyboard/desktop UI behavior, and rendering through Flutter.

`comicrd_core` must stay reusable and must not depend on Flutter, Tauri, or generated bridge code.

## Bridge Rules

When public bridge structs or bridge functions change, regenerate FRB output from the repository root:

```bash
rtk flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

Generated files are expected to be committed:

```text
crates/comicrd_bridge/src/frb_generated.rs
app_flutter/lib/api.dart
app_flutter/lib/frb_generated.dart
app_flutter/lib/frb_generated.io.dart
```

Flutter UI code should call `ComicRdApi` in:

```text
app_flutter/lib/api/comicrd_api.dart
```

Avoid calling generated bridge functions directly from page/widgets/state code.

## Reader Image Pipeline

The reader image pipeline must keep memory bounded around the current viewport. Cache raw image/page data only for:

- 2 images before the viewport
- the image currently in the viewport
- 2 images after the viewport

Do not expand reader raw-image cache or prefetch windows beyond this `2 + viewport + 2` policy unless the user explicitly changes the memory policy.

## Planning

The active migration plan is:

```text
docs/superpowers/plans/2026-06-04-comicrd-flutter-rust-rewrite.md
```

Update the plan checklist when a task is actually implemented and verified. Do not mark work complete only because files were edited.

## Verification

Use the smallest reliable verification for the change, but do not claim success without fresh evidence.

Common checks:

```bash
rtk cargo test
rtk flutter analyze
rtk flutter test
```

Run Rust tests for core/bridge changes. Run Flutter analyzer and tests for Dart, Flutter UI, pubspec, generated bridge, or routing/state changes.

## Git

Do not commit automatically. Commit only when the user explicitly asks for it.

Before committing:

```bash
rtk git status --short
rtk cargo test
```

Also run Flutter checks when sandbox permissions allow them and the change touches Flutter/Dart.
