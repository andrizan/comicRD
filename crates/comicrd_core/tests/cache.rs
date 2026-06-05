use comicrd_core::{ComicRdCore, OpenChapterPayload, RenderPagePayload};
use image::{ImageBuffer, Rgba};
use std::fs;
use std::sync::{Arc, Barrier};
use std::thread;
use tempfile::tempdir;

#[test]
fn render_page_variant_reuses_page_source_and_page_bytes_cache() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter = comic.join("Chapter 1");
    fs::create_dir_all(&chapter).expect("chapter");
    create_png(chapter.join("001.png"), 800, 400);

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

    let payload = RenderPagePayload {
        chapter_id,
        page_index: 0,
    };

    let first = core
        .render_page_variant(payload.clone())
        .expect("first render");
    let first_stats = core.cache_stats_for_test();
    let second = core.render_page_variant(payload).expect("second render");
    let second_stats = core.cache_stats_for_test();

    assert_eq!(first.bytes, second.bytes);
    assert_eq!(first.mime, second.mime);
    assert_eq!(first.width, second.width);
    assert_eq!(first.height, second.height);

    assert_eq!(first_stats.page_source_loads, 1);
    assert_eq!(first_stats.page_bytes_loads, 1);
    assert_eq!(second_stats.page_source_loads, 1);
    assert_eq!(second_stats.page_bytes_loads, 1);
    assert_eq!(second_stats.page_bytes_cache_hits, 1);
}

#[test]
fn concurrent_render_page_variant_shares_cached_bytes() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter = comic.join("Chapter 1");
    fs::create_dir_all(&chapter).expect("chapter");
    create_png(chapter.join("001.png"), 1800, 1200);

    let core = Arc::new(ComicRdCore::open(&app_data).expect("open core"));
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

    let payload = RenderPagePayload {
        chapter_id,
        page_index: 0,
    };
    let worker_count = 8;
    let barrier = Arc::new(Barrier::new(worker_count));
    let mut workers = Vec::new();

    for _ in 0..worker_count {
        let core = Arc::clone(&core);
        let payload = payload.clone();
        let barrier = Arc::clone(&barrier);
        workers.push(thread::spawn(move || {
            barrier.wait();
            core.render_page_variant(payload)
                .expect("render page variant")
        }));
    }

    let pages: Vec<_> = workers
        .into_iter()
        .map(|worker| worker.join().expect("worker"))
        .collect();
    for page in &pages[1..] {
        assert_eq!(pages[0].bytes, page.bytes);
        assert_eq!(pages[0].mime, page.mime);
        assert_eq!(pages[0].width, page.width);
        assert_eq!(pages[0].height, page.height);
    }

    let stats = core.cache_stats_for_test();
    assert_eq!(stats.page_source_loads, 1);
    assert_eq!(stats.page_bytes_loads, 1);
}

fn create_png(path: impl AsRef<std::path::Path>, width: u32, height: u32) {
    let image = ImageBuffer::from_pixel(width, height, Rgba([10u8, 20, 30, 255]));
    image.save(path).expect("save png");
}
