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

#[test]
fn list_comic_chapters_raw_treats_cbr_comic_as_single_chapter() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    fs::create_dir_all(&library).expect("library");
    let comic = library.join("Rar Comic.cbr");
    fs::write(&comic, b"not opened during raw chapter listing").expect("cbr");

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
    assert_eq!(chapters[0].source_type, "cbr");
    assert_eq!(chapters[0].page_count, 0);
}

#[test]
fn list_comic_chapters_raw_orders_decimal_archives_after_whole_chapters() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    fs::create_dir_all(&comic).expect("comic");

    for name in [
        "Chapter 10.cbz",
        "Chapter 02.cbz",
        "Chapter 06.5.cbz",
        "Chapter 06.cbz",
        "Chapter 46.10.cbz",
        "Chapter 46.1.cbz",
        "Chapter 46.cbz",
        "Chapter 46.2.cbz",
        "Chapter 02-fix.cbz",
        "Chapter 07.cbz",
    ] {
        fs::write(comic.join(name), b"").expect("chapter archive");
    }

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
        vec![
            "Chapter 02",
            "Chapter 02-fix",
            "Chapter 06",
            "Chapter 06.5",
            "Chapter 07",
            "Chapter 10",
            "Chapter 46",
            "Chapter 46.1",
            "Chapter 46.2",
            "Chapter 46.10",
        ]
        .iter()
        .map(|v| v.to_string())
        .collect::<Vec<_>>()
        .iter()
        .map(|v| v.as_str())
        .collect::<Vec<_>>(),
        "decimal chapters (06.5, 46.1) must come after their whole chapter"
    );

    let indexes = chapters
        .iter()
        .map(|chapter| chapter.chapter_index)
        .collect::<Vec<_>>();
    assert_eq!(indexes, (1..=10).collect::<Vec<_>>());
}

#[test]
fn list_comic_chapters_raw_orders_decimal_folder_chapters_after_whole_chapters() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    for name in ["Chapter 06.5", "Chapter 06", "Chapter 07"] {
        fs::create_dir_all(comic.join(name)).expect("chapter dir");
    }
    fs::write(comic.join("Chapter 06").join("001.png"), b"").expect("page");
    fs::write(comic.join("Chapter 06.5").join("001.png"), b"").expect("page");
    fs::write(comic.join("Chapter 07").join("001.png"), b"").expect("page");

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
        vec!["Chapter 06", "Chapter 06.5", "Chapter 07"],
        "folder chapter 06.5 must come after 06"
    );
}
