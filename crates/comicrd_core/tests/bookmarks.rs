use comicrd_core::{ComicRdCore, OpenChapterPayload, SaveBookmarkPayload};
use std::fs;
use tempfile::tempdir;

#[test]
fn page_bookmarks_round_trip() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter = comic.join("Chapter 1");
    fs::create_dir_all(&chapter).expect("chapter");
    fs::write(chapter.join("001.png"), b"").expect("page");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    let chapter_id = core
        .open_chapter_for_reading(OpenChapterPayload {
            comic_source_path: comic.to_string_lossy().to_string(),
            chapter_source_path: chapter.to_string_lossy().to_string(),
        })
        .expect("open chapter");

    let bookmark_id = core
        .add_bookmark(SaveBookmarkPayload {
            chapter_id,
            page: 0,
            note: Some("cover".to_string()),
        })
        .expect("add bookmark");
    let page_bookmarks = core.list_bookmarks(chapter_id).expect("list bookmarks");
    assert_eq!(page_bookmarks.len(), 1);
    assert_eq!(page_bookmarks[0].id, bookmark_id);
    assert_eq!(page_bookmarks[0].note, "cover");

    core.remove_bookmark(bookmark_id).expect("remove bookmark");
    assert!(core
        .list_bookmarks(chapter_id)
        .expect("list bookmarks after remove")
        .is_empty());
}

#[test]
fn comic_bookmarks_round_trip() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter = comic.join("Chapter 1");
    fs::create_dir_all(&chapter).expect("chapter");
    fs::write(chapter.join("001.png"), b"").expect("page");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    core.open_chapter_for_reading(OpenChapterPayload {
        comic_source_path: comic.to_string_lossy().to_string(),
        chapter_source_path: chapter.to_string_lossy().to_string(),
    })
    .expect("open chapter");

    let comic_bookmark_id = core
        .add_comic_bookmark(&comic.to_string_lossy())
        .expect("add comic bookmark");
    assert!(comic_bookmark_id >= 0);
    assert!(core
        .is_comic_bookmarked(&comic.to_string_lossy())
        .expect("is bookmarked"));
    let comic_bookmarks = core.list_all_bookmarks().expect("list comic bookmarks");
    assert_eq!(comic_bookmarks.len(), 1);
    assert_eq!(
        comic_bookmarks[0].comic_source_path,
        comic.to_string_lossy()
    );
    assert_eq!(comic_bookmarks[0].comic_title, "Comic A");

    core.remove_comic_bookmark(&comic.to_string_lossy())
        .expect("remove comic bookmark");
    assert!(!core
        .is_comic_bookmarked(&comic.to_string_lossy())
        .expect("is bookmarked after remove"));
}

#[test]
fn comic_bookmark_title_falls_back_to_path_when_not_scanned() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    fs::create_dir_all(&comic).expect("comic");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");

    // Bookmark a comic without opening any chapter (so it is not in the comics table).
    core.add_comic_bookmark(&comic.to_string_lossy())
        .expect("add comic bookmark");
    let comic_bookmarks = core.list_all_bookmarks().expect("list comic bookmarks");
    assert_eq!(comic_bookmarks.len(), 1);
    assert_eq!(comic_bookmarks[0].comic_title, "Comic A");
}

#[test]
fn chapter_favorites_round_trip() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter = comic.join("Chapter 1");
    fs::create_dir_all(&chapter).expect("chapter");
    fs::write(chapter.join("001.png"), b"").expect("page");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    core.open_chapter_for_reading(OpenChapterPayload {
        comic_source_path: comic.to_string_lossy().to_string(),
        chapter_source_path: chapter.to_string_lossy().to_string(),
    })
    .expect("open chapter");

    let favorite_id = core
        .add_chapter_favorite(&chapter.to_string_lossy(), &comic.to_string_lossy())
        .expect("add favorite");
    assert!(favorite_id >= 0);
    assert_eq!(
        core.list_chapter_favorites(&comic.to_string_lossy())
            .expect("list favorites"),
        vec![chapter.to_string_lossy().to_string()]
    );

    core.remove_chapter_favorite(&chapter.to_string_lossy())
        .expect("remove favorite");
    assert!(core
        .list_chapter_favorites(&comic.to_string_lossy())
        .expect("favorites after remove")
        .is_empty());
}
