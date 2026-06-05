use comicrd_core::{ComicRdCore, OpenChapterPayload, RenderPagePayload};
use image::{ImageBuffer, Rgba};
use std::fs;
use std::io::Write;
use tempfile::tempdir;

#[test]
fn get_chapter_pages_lists_sorted_archive_images() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    fs::create_dir_all(&library).expect("library");
    let comic = library.join("Archive Comic.cbz");
    create_zip_with_entries(&comic, &["002.png", "001.png"]);

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

    let pages = core.get_chapter_pages(chapter_id).expect("pages");

    assert_eq!(pages.len(), 2);
    assert_eq!(pages[0].name, "001.png");
    assert_eq!(pages[1].name, "002.png");
}

#[test]
fn render_page_variant_returns_raw_image_bytes() {
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

    let rendered = core
        .render_page_variant(RenderPagePayload {
            chapter_id,
            page_index: 0,
        })
        .expect("render page");

    assert_eq!(rendered.mime, "image/png");
    assert_eq!(rendered.width, 800);
    assert_eq!(rendered.height, 400);
    assert!(!rendered.bytes.is_empty());
}

fn create_png(path: impl AsRef<std::path::Path>, width: u32, height: u32) {
    let image = ImageBuffer::from_pixel(width, height, Rgba([10u8, 20, 30, 255]));
    image.save(path).expect("save png");
}

fn create_zip_with_entries(path: impl AsRef<std::path::Path>, names: &[&str]) {
    let file = fs::File::create(path).expect("create zip");
    let mut zip = zip::ZipWriter::new(file);
    let options = zip::write::SimpleFileOptions::default();
    for name in names {
        zip.start_file(name, options).expect("start file");
        zip.write_all(b"placeholder").expect("write entry");
    }
    zip.finish().expect("finish zip");
}
