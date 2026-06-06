use comicrd_core::{ComicRdCore, OpenChapterPayload, SaveProgressPayload};
use std::fs;
use tempfile::tempdir;

#[test]
fn reading_history_and_comics_with_progress() {
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
}
