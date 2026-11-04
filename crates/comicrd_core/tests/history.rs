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

#[test]
fn history_has_one_entry_per_comic_even_when_chapters_share_a_timestamp() {
    // Scrolling out of one chapter into the next writes both rows within the
    // same second, and `updated_at` has second resolution. The comic must
    // still appear once, as the later chapter, in a fixed order.
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let mut chapter_ids = Vec::new();
    for number in 1..=3 {
        let chapter = comic.join(format!("Chapter {number}"));
        fs::create_dir_all(&chapter).expect("chapter");
        fs::write(chapter.join("001.png"), b"").expect("page");
    }

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    for number in 1..=3 {
        chapter_ids.push(
            core.open_chapter_for_reading(OpenChapterPayload {
                comic_source_path: comic.to_string_lossy().to_string(),
                chapter_source_path: comic
                    .join(format!("Chapter {number}"))
                    .to_string_lossy()
                    .to_string(),
            })
            .expect("open chapter"),
        );
    }

    // Write the later chapter first so insertion order cannot decide it.
    for (chapter_id, is_read) in [(chapter_ids[1], false), (chapter_ids[0], true)] {
        core.save_progress(SaveProgressPayload {
            chapter_id,
            last_page: 0,
            total_pages: 1,
            is_read,
        })
        .expect("save progress");
    }
    // Pin both rows to one second whatever the clock did in between.
    let conn = rusqlite::Connection::open(app_data.join("comicrd.db")).expect("db");
    conn.execute("UPDATE reading_progress SET updated_at = 1700000000", [])
        .expect("pin timestamps");
    drop(conn);

    let history = core.list_reading_history().expect("history");
    assert_eq!(history.len(), 1, "one entry per comic: {history:?}");
    assert_eq!(history[0].chapter_title, "Chapter 2");
    assert!(!history[0].is_read);
}
