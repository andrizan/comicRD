use comicrd_core::{ComicRdCore, OpenChapterPayload, SaveProgressPayload};
use std::fs;
use tempfile::tempdir;

#[test]
fn open_chapter_lists_pages_context_and_persists_progress() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter_1 = comic.join("Chapter 1");
    let chapter_2 = comic.join("Chapter 2");
    fs::create_dir_all(&chapter_1).expect("chapter 1");
    fs::create_dir_all(&chapter_2).expect("chapter 2");
    fs::write(chapter_1.join("002.png"), b"").expect("page 2");
    fs::write(chapter_1.join("001.png"), b"").expect("page 1");
    fs::write(chapter_2.join("001.png"), b"").expect("next chapter page");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");

    let chapter_id = core
        .open_chapter_for_reading(OpenChapterPayload {
            comic_source_path: comic.to_string_lossy().to_string(),
            chapter_source_path: chapter_1.to_string_lossy().to_string(),
        })
        .expect("open chapter");

    let pages = core.get_chapter_pages(chapter_id).expect("pages");
    assert_eq!(pages.len(), 2);
    assert_eq!(pages[0].index, 0);
    assert_eq!(pages[0].name, "001.png");
    assert_eq!(pages[1].name, "002.png");

    let context = core
        .get_chapter_context(chapter_id)
        .expect("context")
        .expect("context exists");
    assert_eq!(context.comic_title, "Comic A");
    assert_eq!(context.title, "Chapter 1");
    assert_eq!(context.chapter_position, 1);
    assert_eq!(context.chapter_total, 2);
    assert_eq!(context.prev_chapter_id, None);
    assert!(context.next_chapter_id.is_some());
    assert_eq!(context.next_chapter_title.as_deref(), Some("Chapter 2"));

    core.save_progress(SaveProgressPayload {
        chapter_id,
        last_page: 1,
        total_pages: 2,
        mode: "webtoon".to_string(),
        is_read: true,
    })
    .expect("save progress");

    let progress = core
        .get_progress(chapter_id)
        .expect("get progress")
        .expect("progress exists");
    assert_eq!(progress.last_page, 1);
    assert_eq!(progress.total_pages, 2);
    assert_eq!(progress.mode, "webtoon");
    assert!(progress.is_read);
}
