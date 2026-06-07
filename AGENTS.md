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

## Data Source Rules

### Listing Pustaka: Raw Filesystem is Primary

The library listing (`list_library_comics_raw`) uses **raw filesystem** as the primary source, NOT the database.

- Listing walks the library root directory at **depth 1 only** (shallow walk).
- **Never traverse subfolders** (chapter directories) during listing. This would cause O(N*M) filesystem operations.
- Each top-level entry (folder or archive) = one comic in the listing.
- Chapter counts and read progress are read from the DB **only if already scanned**. If not scanned, return `0/0/0`.

### DB is for Progress, Not Listing

The SQLite database stores:
- Chapter metadata (after scan)
- Reading progress (after opening chapters)
- Bookmarks, favorites, history

The DB is **NOT** used to enumerate comics for the library listing. The filesystem is the source of truth for "what comics exist."

### Scan vs Listing

- **Listing** (tab Pustaka): shallow FS walk + DB progress lookup. Fast, no subfolder traversal.
- **Scan** (explicit user action): deep FS walk, upserts comics/chapters into DB. Slow, runs in background thread.
- **Opening a comic**: discovers chapters on-demand, upserts into DB. One-time cost per comic.

### Cache FS Entries

Cache the top-level FS entries in `LibraryListCache` with a 30-second TTL.

**IMPORTANT:** The cache stores BOTH filesystem entries AND database counts (chapter_count, read_chapter_count, in_progress_chapter_count). Any operation that changes DB data that affects counts MUST clear the cache.

Invalidate cache on:
- `scan_libraries()` — FS structure changes
- `add_library()` — FS structure changes
- `import_database_backup()` — DB changes
- `save_progress()` — DB read/in_progress counts change

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

### Bridge Data Minimization

- Don't send redundant fields across the bridge (e.g., `key` that duplicates `source_path`).
- Don't send per-item fields that are constant across all items (e.g., `library_path`).
- Don't send fields that Flutter never reads (e.g., `updated_at` on settings).
- Remove dead bridge functions and structs promptly.

## Reader Image Pipeline

The vertical/webtoon reader must use a metadata-first, bytes-on-demand pipeline.

### Reader Contract

- Rust must provide the full page list for an opened chapter up front: `index`, `name`, and best-effort `width`/`height`.
- Rust must natural-sort page entries (`2.png` before `10.png`).
- Folder chapter page discovery may recurse to max depth 3, but library listing must remain depth 1.
- Ignore hidden/system entries such as dotfiles, `__MACOSX`, `thumbs.db`, and `desktop.ini`.
- Flutter must build the reader with `ListView.builder`, not `Column`, `ListView(children: [...])`, or any eager all-page widget tree.
- Flutter must use Rust-provided width/height for stable placeholders and item extents (`itemExtentBuilder`) so scrollbar, resume, progress, and current-page tracking do not depend on image decode timing.
- Flutter must request image bytes only when a page item is built or prefetched. Do not load all image bytes for a chapter into Dart memory.
- `renderPageVariant(chapterId, pageIndex)` is the current on-demand page-byte API. It should read only the requested page bytes and return dimensions/mime/bytes for that page.
- Keep `renderedPageProvider` auto-disposed so Dart page bytes are released when page widgets leave the builder/cache extent.

### Format Rules

- Folder pages: read metadata up front, then read only the requested page file on demand.
- ZIP/CBZ pages: list archive entries up front, then read only the requested entry on demand.
- RAR/CBR pages: current implementation uses the Rust `unrar` backend and reads matching entries on demand. Do not switch to loading all RAR entries into memory.
- If CBR is changed to temp extraction later, use a bounded temp session folder and delete it on reader close.

### Cache And Prefetch Policy

The reader image pipeline must keep raw image/page data bounded around the current viewport:

- Prefetch/keep only a small range around the current page. The current policy is `current - 2` through `current + 2`.
- Flutter must ask Rust to evict other raw pages for the chapter as the active range changes and on reader close/chapter switch.
- Rust caches up to 2 page sources and 6 raw page byte entries.
- Use `Arc<Vec<u8>>` for cached image bytes to avoid deep copies on Rust cache hits.

Do not expand reader raw-image cache, Flutter provider retention, or prefetch windows beyond this policy unless the user explicitly changes the memory policy.

## Flutter State Rules

### Provider Architecture

- `rawLibraryComicsProvider` (FutureProvider): fetches raw comics from Rust. Only watches sort preferences and source status.
- `filteredLibraryComicsProvider` (sync Provider): filters by query + viewMode. Sync, no async cascade.
- `libraryComicsProvider` (sync Provider): combines filtered list + pagination state.
- `libraryPaginationProvider` (Notifier<int>): tracks visible count, independent of filtering.

**Do not** make the filtering provider watch the raw provider's `.future` — this causes async cascade where every query change triggers a loading state.

### Search Debounce

Always debounce search input with a 300ms timer. Do not call `setQuery()` on every keystroke.

### Scroll Offset Management

- Throttle scroll offset saves to 200ms.
- Clamp initial scroll offset to non-negative.
- Validate scroll position after layout (post-frame callback) — if offset > maxExtent, jump to maxExtent.

### Tab Rendering

Use conditional rendering (`switch`) instead of `IndexedStack` for tabs. `IndexedStack` keeps all tabs alive in memory simultaneously.

## Testing

### Test Organization

Integration tests are split by concern:

```text
crates/comicrd_core/tests/
  library_source.rs     — check_library_source edge cases
  library_listing.rs    — list_library_comics_raw + caching
  scan.rs               — scan sync + async
  chapters.rs           — chapter discovery
  reader_flow.rs        — open chapter, pages, context, progress
  image_pipeline.rs     — render page variant, page dimensions
  cache.rs              — page cache hits, concurrency, eviction
  bookmarks.rs          — page/comic bookmarks, chapter favorites
  history.rs            — reading history, comics-with-progress
  migrations.rs         — DB creation, default settings, legacy migration
  backup.rs             — export/import database backup
```

Unit tests are inline in source files:

```text
src/chapter.rs::tests      — ext_eq, is_archive, natural_compare, etc.
src/image_pipeline.rs::tests — mime_for_path, page_dimensions
src/library.rs::tests      — library_source_status_for edge cases
```

### Test Rules

- Tests that use `list_library_comics_raw` must first call `scan_libraries()` if they expect non-zero counts.
- Tests that use `list_library_comics_raw` without scanning should expect `0/0/0` counts (shallow FS, no DB data).
- Don't use dead APIs (e.g., `list_comics()`) in tests — use the production path.

## Planning

The active migration plan is:

```text
docs/superpowers/plans/2026-06-04-comicrd-flutter-rust-rewrite.md
```

The active audit is:

```text
docs/superpowers/plans/2026-06-06-memory-performance-audit.md
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
