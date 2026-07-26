use comicrd_core::{ComicRdCore, OpenChapterPayload, SavePageBookmarkPayload};
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
        .add_page_bookmark(SavePageBookmarkPayload {
            chapter_id,
            page: 0,
            note: Some("cover".to_string()),
        })
        .expect("add page bookmark");
    let page_bookmarks = core.list_page_bookmarks(chapter_id).expect("list page bookmarks");
    assert_eq!(page_bookmarks.len(), 1);
    assert_eq!(page_bookmarks[0].id, bookmark_id);
    assert_eq!(page_bookmarks[0].note, "cover");

    core.remove_page_bookmark(bookmark_id).expect("remove page bookmark");
    assert!(core
        .list_page_bookmarks(chapter_id)
        .expect("list page bookmarks after remove")
        .is_empty());
}

#[test]
fn favorites_round_trip() {
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
        .add_favorite(&comic.to_string_lossy())
        .expect("add favorite");
    assert!(favorite_id >= 0);
    assert!(core
        .is_favorited(&comic.to_string_lossy())
        .expect("is favorited"));
    let favorites = core.list_favorites().expect("list favorites");
    assert_eq!(favorites.len(), 1);
    assert_eq!(
        favorites[0].comic_source_path,
        comic.to_string_lossy()
    );
    assert_eq!(favorites[0].comic_title, "Comic A");

    core.remove_favorite(&comic.to_string_lossy())
        .expect("remove favorite");
    assert!(!core
        .is_favorited(&comic.to_string_lossy())
        .expect("is favorited after remove"));
}

#[test]
fn favorite_title_falls_back_to_path_when_not_scanned() {
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
    core.add_favorite(&comic.to_string_lossy())
        .expect("add favorite");
    let favorites = core.list_favorites().expect("list favorites");
    assert_eq!(favorites.len(), 1);
    assert_eq!(favorites[0].comic_title, "Comic A");
}

#[test]
fn chapter_bookmarks_round_trip() {
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

    let bookmark_id = core
        .add_bookmark(&chapter.to_string_lossy(), &comic.to_string_lossy())
        .expect("add bookmark");
    assert!(bookmark_id >= 0);
    assert_eq!(
        core.list_bookmarks(&comic.to_string_lossy())
            .expect("list bookmarks"),
        vec![chapter.to_string_lossy().to_string()]
    );

    core.remove_bookmark(&chapter.to_string_lossy())
        .expect("remove bookmark");
    assert!(core
        .list_bookmarks(&comic.to_string_lossy())
        .expect("bookmarks after remove")
        .is_empty());
}
