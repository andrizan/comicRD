use comicrd_core::ComicRdCore;
use std::fs;
use tempfile::tempdir;

#[test]
fn list_comic_chapters_raw_discovers_folder_root_images_child_folders_and_archives() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter_2 = comic.join("Chapter 2");
    let chapter_10 = comic.join("Chapter 10");
    let nested = comic.join("Extras");

    fs::create_dir_all(&chapter_10).expect("chapter 10");
    fs::create_dir_all(&chapter_2).expect("chapter 2");
    fs::create_dir_all(&nested).expect("nested");
    fs::write(comic.join("001.png"), b"").expect("root image");
    fs::write(chapter_10.join("001.jpg"), b"").expect("chapter 10 image");
    fs::write(chapter_2.join("001.jpg"), b"").expect("chapter 2 image");
    fs::write(nested.join("Bonus.cbz"), b"").expect("nested archive");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");

    let chapters = core
        .list_comic_chapters_raw(&comic.to_string_lossy())
        .expect("list chapters");
    let titles = chapters
        .iter()
        .map(|chapter| chapter.title.as_str())
        .collect::<Vec<_>>();

    assert_eq!(
        titles,
        vec!["Chapter 1", "Chapter 2", "Chapter 10", "Bonus"]
    );
    assert_eq!(chapters[0].chapter_index, 1);
    assert_eq!(chapters[1].chapter_index, 2);
    assert_eq!(chapters[2].chapter_index, 3);
    assert_eq!(chapters[3].chapter_index, 4);
    assert_eq!(chapters[3].source_type, "cbz");
}

#[test]
fn list_comic_chapters_raw_treats_archive_comic_as_single_chapter() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    fs::create_dir_all(&library).expect("library");
    let comic = library.join("Archive Comic.cbz");
    fs::write(&comic, b"").expect("archive comic");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");

    let chapters = core
        .list_comic_chapters_raw(&comic.to_string_lossy())
        .expect("list chapters");

    assert_eq!(chapters.len(), 1);
    assert_eq!(chapters[0].title, "Chapter 1");
    assert_eq!(chapters[0].chapter_index, 1);
    assert_eq!(chapters[0].source_type, "cbz");
    assert_eq!(chapters[0].page_count, 0);
}
