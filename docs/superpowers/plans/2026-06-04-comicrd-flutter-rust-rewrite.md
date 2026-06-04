# ComicRD Flutter + Rust Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite ComicRD from Tauri + React into a Flutter desktop app while preserving full current feature parity and reusing the Rust core logic through `flutter_rust_bridge`.

**Architecture:** Flutter becomes the desktop shell, renderer, routing, and UI runtime. Rust remains the owner of scanning, archive/page reading, SQLite metadata, progress/bookmarks/settings, backup/import, image resize, caching, and prefetch. Tauri, WebView, React, custom protocol image URLs, and Tauri commands are removed from the new app.

**Tech Stack:** Flutter 3.44.1, Dart 3.12.1, Rust 1.95.0, `flutter_rust_bridge` v2, `go_router`, `flutter_riverpod`, SQLite through Rust `rusqlite`, `zip`, `image`, `lru`, `file_selector`, `path_provider`, `window_manager`.

---

## Summary

- Target platform for v1 rewrite: Windows, Linux, macOS desktop only.
- Source app reference: `/home/andrizan/CODE/PRIVATE/comicRD`.
- Target workspace: `/home/andrizan/CODE/PRIVATE/comicrd_flutter`.
- Flutter app path: `/home/andrizan/CODE/PRIVATE/comicrd_flutter/app_flutter`.
- Target behavior: full parity with current ComicRD, not a small reader-only MVP.
- Data ownership: Rust owns SQLite, cache, business logic, and heavy IO; Flutter owns UI state and presentation.
- Migration safety: keep the existing Tauri app untouched until the Flutter version reaches parity.
- Git rule: do not commit automatically unless the user explicitly asks for a commit.

## Current Feature Inventory To Preserve

- Library:
  - library source path setting and source status warning
  - history/library/bookmarks tabs
  - search by title/path
  - read/unread filter based on reading progress
  - sort by name or folder date, asc/desc
  - grid/list display mode
  - comic bookmarks
  - context actions: open folder, add/remove bookmark, copy title, copy path
  - scroll restoration per tab
- Comic detail:
  - chapter discovery from comic folders, nested chapter folders, root images, ZIP, and CBZ
  - search chapters
  - chapter sort by name or folder date/chapter index, asc/desc
  - chapter favorites and favorites-only filter
  - read/reading/unread status display
  - remember last opened chapter per comic
  - warm prefetch before entering reader
- Reader:
  - webtoon vertical reader only
  - progress restore and debounced progress save
  - mark chapter read on last page
  - close reader back to comic page using comic source path
  - prev/next page and prev/next chapter controls
  - keyboard navigation: Esc, ArrowUp, ArrowDown, PageUp, PageDown, ArrowLeft, ArrowRight
  - zoom, page gap, fullscreen, top toolbar, bottom segmented page indicator
  - current page tracking while scrolling
  - direction-aware prefetch
  - active page window around current page to avoid loading every page at once
- Settings:
  - library source picker
  - app theme light/dark
  - app locale en/id
  - default zoom
  - page gap
  - image pipeline profile: performance, balanced, quality
  - database backup export/import

## Public API Boundary

Replace `src/api/tauri.ts` Tauri invoke calls with a Dart facade over generated FRB APIs. Keep names and payload semantics close to the existing app so UI migration stays mechanical.

Core lifecycle:

- `initApp(appDataDir: String) -> void`
- `shutdownApp() -> void`

Library APIs:

- `checkLibrarySource() -> LibrarySourceStatus`
- `addLibrary(path: String) -> int`
- `listLibraries() -> List<Library>`
- `scanLibraries() -> ScanSummary`
- `startScanLibraries() -> bool`
- `getLibraryScanStatus() -> LibraryScanStatus`
- `listLibraryComicsRaw(sortBy: SortBy, sortDir: SortDir) -> List<RawComic>`
- `listComicsWithProgress() -> List<String>`
- `listReadingHistory() -> List<ReadingHistoryEntry>`

Comic/chapter APIs:

- `listComicChaptersRaw(comicSourcePath: String) -> List<RawChapter>`
- `openChapterForReading(OpenChapterPayload) -> int`
- `getChapterContext(chapterId: int) -> ChapterContext?`
- `getChapterPages(chapterId: int) -> List<PageInfo>`

Reader image APIs:

- `renderPageVariant(RenderPagePayload) -> RenderedPage`
- `renderPagePreview(chapterId: int, pageIndex: int) -> RenderedPage`
- `prefetchPageVariants(PrefetchPageVariantsPayload) -> void`

Reading state APIs:

- `saveProgress(SaveProgressPayload) -> void`
- `getProgress(chapterId: int) -> ReadingProgress?`
- `listBookmarks(chapterId: int) -> List<Bookmark>`
- `addBookmark(SaveBookmarkPayload) -> int`
- `removeBookmark(bookmarkId: int) -> void`
- `listAllBookmarks() -> List<ComicBookmark>`
- `addComicBookmark(comicSourcePath: String) -> int`
- `removeComicBookmark(comicSourcePath: String) -> void`
- `isComicBookmarked(comicSourcePath: String) -> bool`
- `addChapterFavorite(chapterSourcePath: String, comicSourcePath: String) -> int`
- `removeChapterFavorite(chapterSourcePath: String) -> void`
- `listChapterFavorites(comicSourcePath: String) -> List<String>`

Settings/backup/OS APIs:

- `listSettings() -> List<SettingEntry>`
- `getSetting(key: String) -> String?`
- `setSetting(key: String, valueJson: String) -> void`
- `exportDatabaseBackup(outputPath: String) -> void`
- `importDatabaseBackup(inputPath: String) -> void`
- `openContainingFolder(path: String) -> void`

Important data types:

- `RenderedPage`: `bytes`, `mime`, `width`, `height`, `cacheKey`
- `PageInfo`: `index`, `name`, optional `width`, optional `height`
- `ImagePipelineProfile`: `performance`, `balanced`, `quality`
- `ReaderMode`: `webtoon`
- `SortBy`: `name`, `folder_date`
- `SortDir`: `asc`, `desc`

## Implementation Tasks

### Task 1: Rust Workspace And Core Extraction

- [x] Create a Cargo workspace at repo root with `app_flutter`, `crates/comicrd_core`, and `crates/comicrd_bridge`.
- [ ] Move reusable Rust logic from `/home/andrizan/CODE/PRIVATE/comicRD/src-tauri/src/lib.rs` into `comicrd_core`.
- [x] Remove all Tauri dependencies from the core crate.
- [x] Replace `AppHandle`-based database path resolution with `ComicRdCore::open(app_data_dir: PathBuf)`.
- [x] Convert global singleton state into a core-owned state object:
  - SQLite connection mutex
  - page list/source cache
  - page byte LRU cache
  - page variant LRU cache
  - in-flight variant dedupe set and condvar
  - scan state mutex
- [x] Preserve migrations and existing SQLite schema exactly, including default settings.
- [x] Preserve current discovery behavior for folders, nested folders, ZIP, and CBZ.
- [x] Preserve current image variant policy:
  - min width 320
  - max width 4096
  - width rounded to 64
  - JPEG output for resized variants
  - no GIF resize
  - performance/balanced/quality profile quality and filter behavior
- [x] Add Rust tests for migrations, scan, progress, bookmarks, chapter context, image variants, and backup/import.
  - Covered: migrations/defaults, raw library listing, scan upsert/status, chapter discovery, reader progress/context, page variants, bookmarks/favorites/history, backup/import, page cache reuse, and concurrent in-flight variant dedupe.

### Task 2: Flutter Rust Bridge Integration

- [x] Add `flutter_rust_bridge` and generated bridge structure.
- [x] Expose a small bridge API that wraps `comicrd_core`.
- [x] Store the initialized core instance behind a bridge-level global after `initApp`.
- [x] Add typed request/response structs for every API listed in the Public API Boundary.
- [x] Use `path_provider` in Dart to resolve the app support directory and call `initApp` before rendering the main routes.
- [x] Add a thin Dart `ComicRdApi` facade so UI code does not call generated FRB symbols directly.
- [x] Verify `cargo test` passes for the Rust workspace.
- [x] Verify `flutter analyze` can see generated Dart code without analyzer errors.

### Task 3: App Shell, Routing, Theme, And Localization

- [x] Replace the template counter app in `lib/main.dart`.
- [x] Add `go_router` routes:
  - `/`
  - `/comic/:comicPath`
  - `/reader/:chapterId`
- [x] Add Riverpod providers for settings, library preferences, library data, comic data, reader data, bookmarks, and history.
- [x] Implement light/dark theme matching the quiet desktop utility feel of the current app.
- [x] Implement en/id localization and keep `app_locale` default as `en`.
  - Current Flutter shell uses internal app strings for en/id. Material/Cupertino framework localizations remain English until `flutter_localizations` is added.
- [x] Implement top app chrome with home, app title, theme toggle, and settings button.
- [x] Hide main app chrome on reader route.
- [x] Implement in-memory scroll restoration for library tabs and comic pages.
- [x] Add route path encode/decode helpers for comic source paths.

### Task 4: Settings And Data Migration

- [x] Implement settings drawer/panel with:
  - library source text field
  - browse directory button using `file_selector`
  - source status refresh
  - default zoom
  - page gap
  - image pipeline profile
  - theme
  - locale
  - backup export/import
- [x] Persist settings through Rust `setSetting`.
- [x] Keep setting keys compatible with the Tauri app:
  - `default_mode`
  - `arrow_navigation_enabled`
  - `default_zoom`
  - `page_gap`
  - `image_pipeline_profile`
  - `library_source_input`
  - `app_theme`
  - `app_locale`
  - `library_sort_by`
  - `library_sort_dir`
  - `library_view_mode`
  - `library_display_mode`
  - `chapter_sort_by`
  - `chapter_sort_dir`
- [x] Implement first-run legacy database copy:
  - use Flutter support dir for the new database
  - if `comicrd.db` is absent, search likely legacy Tauri app data locations for `com.andrizan.comicrd/comicrd.db`
  - copy the DB once, remove stale WAL/SHM from the target, then run migrations
- [x] Keep manual import/export as fallback for any failed automatic migration.

### Task 5: Library Page

- [ ] Build the library page with three tabs: history, library, bookmarks.
- [ ] Load preferences from Rust settings on startup.
- [ ] Implement search, read/unread filter, sort, and grid/list display mode.
- [ ] Use raw filesystem comic listing from `listLibraryComicsRaw`, not full eager DB scan.
- [ ] Show source status warning when the library path is unconfigured, missing, not a directory, or unreadable.
- [ ] Implement comic bookmarks and context actions.
- [ ] Implement history tab using `listReadingHistory`, deduped by comic source path.
- [ ] Implement bookmarks tab using `listAllBookmarks`.
- [ ] Preserve scroll position per tab.

### Task 6: Comic Page

- [ ] Decode comic path from route param and derive fallback title from path.
- [ ] Load chapters via `listComicChaptersRaw`.
- [ ] Implement search, sort, grid/list display, favorites-only filter, and chapter favorites.
- [ ] Display read/reading/unread status from chapter progress data.
- [ ] Persist last opened chapter in session memory.
- [ ] On chapter open:
  - call `openChapterForReading`
  - prefetch from last read page through the next few pages
  - navigate to `/reader/:chapterId`
- [ ] Preserve Escape behavior back to the library route.
- [ ] Preserve scroll restoration and scroll-to-last-chapter behavior.

### Task 7: Reader Page And Image Rendering

- [ ] Implement full-screen black reader surface with its own vertical scroll controller.
- [ ] Load settings, chapter pages, chapter context, and progress before marking reader ready.
- [ ] Restore last progress page once page metadata is available.
- [ ] Track current page from scroll position without jitter.
- [ ] Save progress debounced and save immediately before closing or switching chapter.
- [ ] Implement top toolbar:
  - close
  - comic/chapter title
  - chapter position
  - gap controls
  - prev/next page
  - prev/next chapter
  - zoom controls
  - fullscreen
- [ ] Implement bottom segmented page indicator with clickable page jumps.
- [ ] Implement keyboard controls matching current behavior.
- [ ] Replace protocol URLs with `renderPageVariant` and `Image.memory`.
- [ ] Use stable aspect-ratio placeholders from `PageInfo` or `RenderedPage` dimensions.
- [ ] Keep only nearby pages active around current page.
- [ ] Prefetch direction-aware ranges with the existing profile policies:
  - performance: max width 1280, max DPR 1, forward 6, backward 1
  - balanced: max width 1600, max DPR 1.25, forward 5, backward 1
  - quality: max width 2400, max DPR 1.75, forward 4, backward 2
- [ ] Cap Flutter image cache bytes and evict far-page images as the active window moves.

### Task 8: Packaging And Desktop Integration

- [ ] Set app name to `ComicRD`.
- [ ] Set desktop bundle/application identifier to `com.andrizan.comicrd`.
- [ ] Replace default Flutter icons with existing ComicRD icons where format permits.
- [ ] Wire platform-specific `openContainingFolder` implementation from Rust.
- [ ] Verify Linux desktop run.
- [ ] Verify Windows build no longer starts WebView2 or `msedgewebview2.exe`.
- [ ] Verify macOS bundle uses the correct name, icon, and support directory.
- [ ] Document build commands for Windows, Linux, and macOS in the README.

## Test Plan

- Rust:
  - [ ] `cargo test` from the Rust workspace root.
  - [ ] Migration test confirms default settings and all required tables/indexes.
  - [ ] Scan tests cover folder comic, root-image chapter, nested folder chapters, ZIP, and CBZ.
  - [ ] Sort tests cover numeric natural ordering for chapters/pages.
  - [ ] Reader flow test covers open chapter, page list, context prev/next, progress save/read, and history.
  - [ ] Bookmark/favorite tests cover chapter bookmarks, comic bookmarks, and chapter favorites.
  - [ ] Image tests cover width normalization, resize/no-resize thresholds, GIF no-resize, preview, cache byte budget, and in-flight dedupe.
  - [ ] Backup tests cover export, import, pre-import backup, and migration after import.
- Dart:
  - [ ] `flutter analyze`
  - [ ] `flutter test`
  - [ ] Unit tests for settings parsing/defaults.
  - [ ] Unit tests for route path encode/decode.
  - [ ] Unit tests for reader progress payload.
  - [ ] Unit tests for target image width and prefetch range policy.
- Flutter widget tests with fake API:
  - [ ] Library tabs, search, filter, sort, bookmark toggles, and source warning.
  - [ ] Comic page chapter filtering, favorites-only, open chapter, and warm prefetch.
  - [ ] Settings save flow, directory picker result handling, backup export/import status.
  - [ ] Reader progress restore, current page tracking, keyboard navigation, toolbar controls, active page window, and image eviction calls.
- Manual desktop smoke tests:
  - [ ] Linux: run with a folder comic and a CBZ comic.
  - [ ] Windows: confirm no WebView2 process and memory remains bounded during long chapter scroll.
  - [ ] macOS: confirm app support dir and backup/import behavior.

## Acceptance Criteria

- Flutter app can read the same local comic library as current ComicRD.
- Existing `comicrd.db` data can be reused or imported without losing progress/bookmarks/settings.
- Folder comics, ZIP, and CBZ render correctly.
- Reader memory stays bounded while scrolling large chapters.
- All current user-visible features listed in this plan exist in Flutter.
- Tauri, WebView, React, custom protocol URLs, TanStack, Zustand, Tailwind, and Tauri bundling are not required by the new app.
- Rust core has no Tauri dependency.
- Tests pass for Rust and Flutter before calling the rewrite complete.

## Assumptions

- First rewrite release is desktop-only: Windows, Linux, macOS.
- Rust remains source of truth for database and business logic.
- Flutter UI is rewritten as native Flutter widgets, not translated line-by-line from React.
- Current Tauri source remains available as the behavior reference until parity is reached.
- Network/package installation may be needed during implementation for Flutter/Rust dependencies.
