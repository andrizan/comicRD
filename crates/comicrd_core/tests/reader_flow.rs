use comicrd_core::{ComicRdCore, OpenChapterPayload, RenderPageTilePayload, SaveProgressPayload};
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
        is_read: true,
    })
    .expect("save progress");

    let progress = core
        .get_progress(chapter_id)
        .expect("get progress")
        .expect("progress exists");
    assert_eq!(progress.last_page, 1);
    assert_eq!(progress.total_pages, 2);
    assert!(progress.is_read);
}

#[test]
fn tile_render_does_not_block_progress_writes() {
    // Liveness only (no timing asserts): tile rendering must not hold the
    // DB mutex, so concurrent progress/history calls always complete.
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter_1 = comic.join("Chapter 1");
    fs::create_dir_all(&chapter_1).expect("chapter 1");
    let strip = image::ImageBuffer::from_pixel(
        1600,
        4100,
        image::Rgba([10u8, 20, 30, 255]),
    );
    strip.save(chapter_1.join("strip.png")).expect("strip");

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

    std::thread::scope(|s| {
        s.spawn(|| {
            // 1600x4100 -> tiles [2048, 2048, 4].
            for tile_index in 0..3usize {
                core.render_page_tile(RenderPageTilePayload {
                    chapter_id,
                    page_index: 0,
                    tile_index,
                })
                .expect("render tile");
            }
        });
        core.save_progress(SaveProgressPayload {
            chapter_id,
            last_page: 2,
            total_pages: 10,
            is_read: false,
        })
        .expect("save progress");
        core.list_reading_history().expect("history");
    });

    let progress = core
        .get_progress(chapter_id)
        .expect("get progress")
        .expect("progress exists");
    assert_eq!(progress.last_page, 2);
}

#[test]
fn open_chapter_reuses_stored_sizes_until_the_chapter_changes() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter_1 = comic.join("Chapter 1");
    let chapter_2 = comic.join("Chapter 2");
    fs::create_dir_all(&chapter_1).expect("chapter 1");
    fs::create_dir_all(&chapter_2).expect("chapter 2");
    fs::write(chapter_1.join("001.png"), vec![0u8; 1000]).expect("c1 p1");
    fs::write(chapter_1.join("002.png"), vec![0u8; 2000]).expect("c1 p2");
    fs::write(chapter_2.join("001.png"), vec![0u8; 500]).expect("c2 p1");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    let open = |core: &ComicRdCore| {
        core.open_chapter_for_reading(OpenChapterPayload {
            comic_source_path: comic.to_string_lossy().to_string(),
            chapter_source_path: chapter_1.to_string_lossy().to_string(),
        })
        .expect("open chapter")
    };
    let sizes = |core: &ComicRdCore| -> Vec<i64> {
        core.list_comic_chapters_raw(&comic.to_string_lossy())
            .expect("chapters")
            .into_iter()
            .map(|chapter| chapter.size_bytes)
            .collect()
    };

    open(&core);
    assert_eq!(sizes(&core), vec![3000, 500]);

    // Overwriting a page in place leaves the folder's modified time alone, so
    // the stored size is kept: opening must not re-walk every chapter.
    fs::write(chapter_1.join("002.png"), vec![0u8; 9000]).expect("grow page");
    open(&core);
    assert_eq!(sizes(&core), vec![3000, 500]);

    // Once the chapter counts as changed (its stored time no longer matches),
    // the size is measured again.
    let conn = rusqlite::Connection::open(app_data.join("comicrd.db")).expect("db");
    conn.execute(
        "UPDATE chapters SET date_modified = 0 WHERE source_path = ?1",
        [chapter_1.to_string_lossy().to_string()],
    )
    .expect("age chapter");
    drop(conn);
    open(&core);
    assert_eq!(sizes(&core), vec![10000, 500]);
}
