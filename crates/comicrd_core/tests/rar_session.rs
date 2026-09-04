//! Rar/cbr session lifecycle (extract-once, serve from disk, cleanup).
use comicrd_core::{ComicRdCore, OpenChapterPayload, RenderPageTilePayload};
use std::fs;
use std::path::{Path, PathBuf};
use tempfile::tempdir;

// Minimal single-entry RAR (stored "VERSION" file, no image entries).
// Mirrors the VERSION_RAR fixture in chapter.rs unit tests.
const VERSION_RAR: &[u8] = &[
    0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x00, 0xcf, 0x90, 0x73, 0x00, 0x00, 0x0d, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x0f, 0x0c, 0x74, 0x20, 0x80, 0x27, 0x00, 0x15, 0x00, 0x00,
    0x00, 0x0b, 0x00, 0x00, 0x00, 0x03, 0x45, 0xf3, 0x7d, 0xc6, 0xa4, 0x8a, 0x07, 0x47, 0x1d,
    0x33, 0x07, 0x00, 0xa4, 0x81, 0x00, 0x00, 0x56, 0x45, 0x52, 0x53, 0x49, 0x4f, 0x4e, 0x0c,
    0x00, 0x8f, 0xec, 0x8a, 0x45, 0xcc, 0x23, 0xc8, 0x48, 0x08, 0x83, 0x62, 0xfe, 0x5f, 0xdd,
    0x5c, 0x53, 0x88, 0xf0, 0x72, 0xc4, 0x3d, 0x7b, 0x00, 0x40, 0x07, 0x00,
];

fn open_cbr_chapter() -> (tempfile::TempDir, ComicRdCore, i64, PathBuf) {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    fs::create_dir_all(&library).expect("library");
    let comic = library.join("Archive Comic.cbr");
    fs::write(&comic, VERSION_RAR).expect("write cbr");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    let chapter_id = core
        .open_chapter_for_reading(OpenChapterPayload {
            comic_source_path: comic.to_string_lossy().to_string(),
            chapter_source_path: comic.to_string_lossy().to_string(),
        })
        .expect("open chapter");
    (temp, core, chapter_id, app_data)
}

fn session_dirs(app_data: &Path) -> Vec<PathBuf> {
    let base = app_data.join("rar-sessions");
    if !base.exists() {
        return Vec::new();
    }
    fs::read_dir(&base)
        .expect("read sessions")
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| path.is_dir())
        .collect()
}

#[test]
fn cbr_listing_uses_session_and_cleans_up_on_evict() {
    let (_temp, core, chapter_id, app_data) = open_cbr_chapter();

    // Fixture has no image entries: empty page list, but the session dir
    // is still established on first access.
    let pages = core.get_chapter_pages(chapter_id).expect("pages");
    assert!(pages.is_empty());
    assert_eq!(session_dirs(&app_data).len(), 1);

    // Empty chapter: tile 0 is out of range (no pages to serve).
    assert!(
        core.render_page_tile(RenderPageTilePayload {
            chapter_id,
            page_index: 0,
            tile_index: 0,
        })
        .is_err()
    );

    // Reader close path drops the session dir...
    core.evict_chapter_pages(chapter_id, Vec::new());
    assert!(session_dirs(&app_data).is_empty());

    // ...and the next access re-extracts on demand.
    let pages = core.get_chapter_pages(chapter_id).expect("pages again");
    assert!(pages.is_empty());
    assert_eq!(session_dirs(&app_data).len(), 1);
}

#[test]
fn cbr_session_survives_partial_evict() {
    let (_temp, core, chapter_id, app_data) = open_cbr_chapter();

    core.get_chapter_pages(chapter_id).expect("pages");
    assert_eq!(session_dirs(&app_data).len(), 1);

    // Non-empty keep list drops no source: the session stays.
    core.evict_chapter_pages(chapter_id, vec![0]);
    assert_eq!(session_dirs(&app_data).len(), 1);
}
