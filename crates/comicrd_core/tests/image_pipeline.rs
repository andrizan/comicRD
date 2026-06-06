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
    create_zip_with_png_entries(&comic, &[("10.png", 100, 50), ("2.png", 200, 80)]);

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
    assert_eq!(pages[0].name, "2.png");
    assert_eq!(pages[0].width, Some(200));
    assert_eq!(pages[0].height, Some(80));
    assert_eq!(pages[1].name, "10.png");
    assert_eq!(pages[1].width, Some(100));
    assert_eq!(pages[1].height, Some(50));
}

#[test]
fn get_chapter_pages_returns_folder_image_dimensions() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter = comic.join("Chapter 1");
    fs::create_dir_all(&chapter).expect("chapter");
    create_png(chapter.join("10.png"), 100, 50);
    create_png(chapter.join("2.png"), 200, 80);

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

    let pages = core.get_chapter_pages(chapter_id).expect("pages");

    assert_eq!(pages.len(), 2);
    assert_eq!(pages[0].name, "2.png");
    assert_eq!(pages[0].width, Some(200));
    assert_eq!(pages[0].height, Some(80));
    assert_eq!(pages[1].name, "10.png");
    assert_eq!(pages[1].width, Some(100));
    assert_eq!(pages[1].height, Some(50));
}

#[test]
fn get_chapter_pages_lists_nested_folder_images_to_depth_three() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter = comic.join("Chapter 1");
    let nested = chapter.join("images").join("inner");
    fs::create_dir_all(&nested).expect("nested images");
    create_png(nested.join("10.png"), 100, 50);
    create_png(nested.join("2.png"), 200, 80);
    create_png(chapter.join(".hidden.png"), 1, 1);
    fs::write(chapter.join("thumbs.db"), b"ignored").expect("ignored file");

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

    let pages = core.get_chapter_pages(chapter_id).expect("pages");

    assert_eq!(pages.len(), 2);
    assert_eq!(pages[0].name, "2.png");
    assert_eq!(pages[0].width, Some(200));
    assert_eq!(pages[0].height, Some(80));
    assert_eq!(pages[1].name, "10.png");
    assert_eq!(pages[1].width, Some(100));
    assert_eq!(pages[1].height, Some(50));
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

fn create_png_bytes(width: u32, height: u32) -> Vec<u8> {
    let image = ImageBuffer::from_pixel(width, height, Rgba([10u8, 20, 30, 255]));
    let mut cursor = std::io::Cursor::new(Vec::new());
    image
        .write_to(&mut cursor, image::ImageFormat::Png)
        .expect("encode png");
    cursor.into_inner()
}

fn create_zip_with_png_entries(path: impl AsRef<std::path::Path>, entries: &[(&str, u32, u32)]) {
    let file = fs::File::create(path).expect("create zip");
    let mut zip = zip::ZipWriter::new(file);
    let options = zip::write::SimpleFileOptions::default();
    for (name, width, height) in entries {
        zip.start_file(name, options).expect("start file");
        zip.write_all(&create_png_bytes(*width, *height))
            .expect("write entry");
    }
    zip.finish().expect("finish zip");
}
