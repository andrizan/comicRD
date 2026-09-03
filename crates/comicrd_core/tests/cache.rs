use comicrd_core::{ComicRdCore, OpenChapterPayload, RenderPageTilePayload};
use image::{ImageBuffer, ImageFormat, Rgba};
use std::fs;
use std::sync::{Arc, Barrier};
use std::thread;
use tempfile::tempdir;

#[test]
fn render_page_tile_reuses_page_source_and_page_bytes_cache() {
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

    let payload = RenderPageTilePayload {
        chapter_id,
        page_index: 0,
        tile_index: 0,
    };

    let first = core
        .render_page_tile(payload.clone())
        .expect("first render");
    let first_stats = core.cache_stats_for_test();
    let second = core.render_page_tile(payload).expect("second render");
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
fn concurrent_render_page_tile_shares_cached_bytes() {
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

    let payload = RenderPageTilePayload {
        chapter_id,
        page_index: 0,
        tile_index: 0,
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
            core.render_page_tile(payload)
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

#[test]
fn render_page_tile_reads_avif_dimensions_and_mime() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter = comic.join("Chapter 1");
    fs::create_dir_all(&chapter).expect("chapter");
    create_avif(chapter.join("001.avif"), 32, 24);

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

    let page = core
        .render_page_tile(RenderPageTilePayload {
            chapter_id,
            page_index: 0,
            tile_index: 0,
        })
        .expect("render avif page");

    assert_eq!(page.mime, "image/avif");
    assert_eq!(page.width, 32);
    assert_eq!(page.height, 24);
}

#[test]
fn evict_chapter_pages_without_keep_pages_drops_source_and_bytes_cache() {
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

    let payload = RenderPageTilePayload {
        chapter_id,
        page_index: 0,
        tile_index: 0,
    };

    core.render_page_tile(payload.clone())
        .expect("first render");
    core.evict_chapter_pages(chapter_id, Vec::new());
    core.render_page_tile(payload).expect("second render");

    let stats = core.cache_stats_for_test();
    assert_eq!(stats.page_source_loads, 2);
    assert_eq!(stats.page_bytes_loads, 2);
}

#[test]
fn evict_chapter_pages_drops_sibling_tiles_but_keeps_window() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter = comic.join("Chapter 1");
    fs::create_dir_all(&chapter).expect("chapter");
    // Page 0 is a strip (tiles [2048, 952]); page 1 is short (1 tile).
    create_png(chapter.join("001-strip.png"), 1600, 3000);
    create_png(chapter.join("002.png"), 800, 400);

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

    let tile = |page_index: usize, tile_index: usize| RenderPageTilePayload {
        chapter_id,
        page_index,
        tile_index,
    };
    core.render_page_tile(tile(0, 0)).expect("strip tile 0");
    core.render_page_tile(tile(0, 1)).expect("strip tile 1");
    core.render_page_tile(tile(1, 0)).expect("page 1");
    // One miss serves both strip tiles (decode-once), so 3 renders = 2 loads.
    assert_eq!(core.cache_stats_for_test().page_bytes_loads, 2);

    // Keep only page 1: both sibling tiles of page 0 must go. Rendering
    // tile (0,0) re-decodes once and re-caches both strip tiles.
    core.evict_chapter_pages(chapter_id, vec![1]);
    core.render_page_tile(tile(0, 0)).expect("strip tile 0 again");
    assert_eq!(core.cache_stats_for_test().page_bytes_loads, 3);
    core.render_page_tile(tile(1, 0)).expect("page 1 again");
    let stats = core.cache_stats_for_test();
    assert_eq!(stats.page_bytes_loads, 3);
    assert_eq!(stats.page_bytes_cache_hits, 2);
}

#[test]
fn rendering_all_strip_tiles_counts_single_page_miss() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter = comic.join("Chapter 1");
    fs::create_dir_all(&chapter).expect("chapter");
    // 1600x4100 -> tiles [2048, 2048, 4].
    create_png(chapter.join("strip.png"), 1600, 4100);

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

    let before = core.cache_stats_for_test();
    for tile_index in 0..3usize {
        core.render_page_tile(RenderPageTilePayload {
            chapter_id,
            page_index: 0,
            tile_index,
        })
        .expect("render tile");
    }
    let after = core.cache_stats_for_test();
    // One decode serves every tile of the page: a single page-miss.
    assert_eq!(after.page_bytes_loads - before.page_bytes_loads, 1);
    for tile_index in 0..3usize {
        core.render_page_tile(RenderPageTilePayload {
            chapter_id,
            page_index: 0,
            tile_index,
        })
        .expect("render tile again");
    }
    let again = core.cache_stats_for_test();
    assert_eq!(again.page_bytes_loads - after.page_bytes_loads, 0);
    assert_eq!(again.page_bytes_cache_hits - after.page_bytes_cache_hits, 3);
}

fn create_png(path: impl AsRef<std::path::Path>, width: u32, height: u32) {
    let image = ImageBuffer::from_pixel(width, height, Rgba([10u8, 20, 30, 255]));
    image.save(path).expect("save png");
}

fn create_avif(path: impl AsRef<std::path::Path>, width: u32, height: u32) {
    let image = ImageBuffer::from_pixel(width, height, Rgba([10u8, 20, 30, 255]));
    image
        .save_with_format(path, ImageFormat::Avif)
        .expect("save avif");
}
