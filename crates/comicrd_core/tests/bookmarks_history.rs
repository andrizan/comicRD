use comicrd_core::{ComicRdCore, OpenChapterPayload, SaveBookmarkPayload, SaveProgressPayload};
use std::fs;
use tempfile::tempdir;

#[test]
fn bookmark_favorite_and_history_apis_round_trip_reader_state() {
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

    let favorite_id = core
        .add_chapter_favorite(&chapter.to_string_lossy(), &comic.to_string_lossy())
        .expect("add favorite");
    assert!(favorite_id >= 0);
    assert_eq!(
        core.list_chapter_favorites(&comic.to_string_lossy())
            .expect("list favorites"),
        vec![chapter.to_string_lossy().to_string()]
    );

    core.save_progress(SaveProgressPayload {
        chapter_id,
        last_page: 0,
        total_pages: 1,
        is_read: true,
    })
    .expect("save progress");

    let history = core.list_reading_history().expect("history");
    assert_eq!(history.len(), 1);
    assert_eq!(history[0].comic_source_path, comic.to_string_lossy());
    assert_eq!(history[0].comic_title, "Comic A");
    assert_eq!(history[0].chapter_title, "Chapter 1");
    assert!(history[0].is_read);

    assert_eq!(
        core.list_comics_with_progress()
            .expect("comics with progress"),
        vec![comic.to_string_lossy().to_string()]
    );

    core.remove_bookmark(bookmark_id).expect("remove bookmark");
    assert!(core
        .list_bookmarks(chapter_id)
        .expect("list bookmarks after remove")
        .is_empty());

    core.remove_comic_bookmark(&comic.to_string_lossy())
        .expect("remove comic bookmark");
    assert!(!core
        .is_comic_bookmarked(&comic.to_string_lossy())
        .expect("is bookmarked after remove"));

    core.remove_chapter_favorite(&chapter.to_string_lossy())
        .expect("remove favorite");
    assert!(core
        .list_chapter_favorites(&comic.to_string_lossy())
        .expect("favorites after remove")
        .is_empty());
}
