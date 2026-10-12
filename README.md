# ComicRD

Desktop comic reader for local libraries — no account, no internet. Point it at
one folder; it reads folders, ZIP/CBZ and RAR/CBR straight from disk, remembers
where you stopped, and keeps the whole library offline.

![ComicRD library view: continue-reading shelf, filter chips and a cover grid](docs/screenshots/library.png)

| Comic detail | Reader with the Display panel |
| --- | --- |
| ![Comic detail: cover, progress card and chapter list](docs/screenshots/comic.png) | ![Reader: floating glass toolbar, segmented page bar and the Display panel](docs/screenshots/reader.png) |

| Dark theme | First run |
| --- | --- |
| ![Library in the dark theme](docs/screenshots/dark.png) | ![First-run screen with the folder picker and an example folder structure](docs/screenshots/welcome.png) |

## Features

- Pick one library folder; the listing is instant, a full scan runs in the background
- Folder, ZIP/CBZ, and RAR/CBR support; nested folder pages to depth 3
- JPEG, PNG, WebP, GIF, BMP, and AVIF pages
- Library with a continue-reading shelf, grid and list cards, unread/reading filters, search and sort
- History (continue or read again), favorites, chapter bookmarks and page bookmarks
- Comic detail: progress card, last read, chapter list with natural ordering (`06.5` after `06`)
- Vertical reader: floating toolbar, Display panel (zoom, page gap, unlimited scroll, portrait mode),
  Mark panel (page/chapter bookmark, favorite), segmented page bar with bookmark markers,
  fullscreen, auto-saved progress, prev/next chapter
- Keyboard: `Esc` close, `↑ ↓` / `PgUp PgDn` scroll, `← →` switch chapter, `0` / `Home` first page,
  `Ctrl+T` theme, `Ctrl+L` language
- Light and dark themes, English and Indonesian
- Backup export/import, Optimize Data (purge stale entries + VACUUM), auto-update via GitHub Releases

## Install

### Arch Linux / CachyOS

```bash
paru -S comicrd-bin
# or: yay -S comicrd-bin
```

### Windows

Download `*-setup.exe` from GitHub Releases. Per-user install, no admin needed.

### Linux Tarball

```bash
tar -xzf comicrd-2.8.3-linux-x86_64.tar.gz
./comicrd-2.8.3-linux-x86_64/opt/comicrd/ComicRD
```

macOS builds exist but have not had a native smoke test yet.

## Build From Source

```bash
cd app_flutter
flutter pub get
flutter run -d linux
```

Requirements, platform dependencies (dav1d on Windows), packaging, the bridge
workflow and CI are described in [`docs/technical.md`](docs/technical.md).

## Documentation

- [`docs/technical.md`](docs/technical.md) — requirements, build/run, CI,
  repository layout, architecture, data model, reader pipeline, tests, screenshots
- [`AGENTS.md`](AGENTS.md) — design rules for contributors and coding agents

## License

MIT. See [LICENSE](LICENSE).
