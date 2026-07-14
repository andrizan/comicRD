use comicrd_core::{ComicRdCore, OpenChapterPayload, SaveProgressPayload, SortBy, SortDir};
use std::fs;
use tempfile::tempdir;

#[test]
fn reads_configured_source_folder_and_archive() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    fs::create_dir_all(library.join("Comic Folder")).expect("comic folder");
    fs::write(
        library.join("Zed Comic.cbz"),
        b"not opened during raw listing",
    )
    .expect("cbz");
    fs::write(
        library.join("Rar Comic.cbr"),
        b"not opened during raw listing",
    )
    .expect("cbr");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");

    let comics = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("list raw comics");
    let titles = comics
        .iter()
        .map(|comic| comic.title.as_str())
        .collect::<Vec<_>>();
    assert_eq!(titles, vec!["Comic Folder", "Rar Comic", "Zed Comic"]);

    assert_eq!(comics[0].source_type, "folder");
    assert_eq!(comics[0].chapter_count, 0);
    assert_eq!(comics[1].source_type, "cbr");
    assert_eq!(comics[1].chapter_count, 1);
    assert_eq!(comics[2].source_type, "cbz");
    assert_eq!(comics[2].chapter_count, 1);
}

#[test]
fn returns_error_when_library_not_configured() {
    let temp = tempdir().expect("tempdir");
    let core = ComicRdCore::open(temp.path()).expect("open core");

    let result = core.list_library_comics_raw(SortBy::Name, SortDir::Asc);

    assert!(result.is_err());
}

#[test]
fn returns_zero_counts_before_scan() {
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

    let comics = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("list raw comics");
    assert_eq!(comics.len(), 1);
    assert_eq!(comics[0].title, "Comic A");
    assert_eq!(comics[0].chapter_count, 0);
    assert_eq!(comics[0].read_chapter_count, 0);
    assert_eq!(comics[0].in_progress_chapter_count, 0);
    assert_eq!(comics[0].size_bytes, 0);
}

#[test]
fn size_bytes_zero_before_scan_and_total_storage_empty() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter = comic.join("Chapter 1");
    fs::create_dir_all(&chapter).expect("chapter");
    fs::write(chapter.join("001.png"), vec![0u8; 4096]).expect("page");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");

    let stats = core.get_library_storage_stats().expect("storage stats");
    assert_eq!(stats.total_size_bytes, 0);
    assert_eq!(stats.comic_count, 0);
}

#[test]
fn reads_counts_from_db_after_scan() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter_1 = comic.join("Chapter 1");
    let chapter_2 = comic.join("Chapter 2");
    fs::create_dir_all(&chapter_1).expect("chapter 1");
    fs::create_dir_all(&chapter_2).expect("chapter 2");
    fs::write(chapter_1.join("001.png"), b"").expect("page 1");
    fs::write(chapter_2.join("001.png"), b"").expect("page 2");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    core.add_library(&library.to_string_lossy())
        .expect("add library");
    core.scan_libraries().expect("scan libraries");

    let comics = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("list raw comics");
    assert_eq!(comics.len(), 1);
    assert_eq!(comics[0].title, "Comic A");
    assert_eq!(comics[0].chapter_count, 2);
    assert_eq!(comics[0].read_chapter_count, 0);
    assert_eq!(comics[0].in_progress_chapter_count, 0);
}

#[test]
fn reflects_progress_after_save() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter_1 = comic.join("Chapter 1");
    let chapter_2 = comic.join("Chapter 2");
    fs::create_dir_all(&chapter_1).expect("chapter 1");
    fs::create_dir_all(&chapter_2).expect("chapter 2");
    fs::write(chapter_1.join("001.png"), b"").expect("page 1");
    fs::write(chapter_2.join("001.png"), b"").expect("page 2");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    core.add_library(&library.to_string_lossy())
        .expect("add library");
    core.scan_libraries().expect("scan libraries");

    let chapter_id = core
        .open_chapter_for_reading(OpenChapterPayload {
            comic_source_path: comic.to_string_lossy().to_string(),
            chapter_source_path: chapter_1.to_string_lossy().to_string(),
        })
        .expect("open chapter");
    core.save_progress(SaveProgressPayload {
        chapter_id,
        last_page: 1,
        total_pages: 3,
        is_read: false,
    })
    .expect("save progress");

    let comics = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("list raw comics after progress");
    assert_eq!(comics.len(), 1);
    assert_eq!(comics[0].title, "Comic A");
    assert_eq!(comics[0].chapter_count, 2);
    assert_eq!(comics[0].read_chapter_count, 0);
    assert_eq!(comics[0].in_progress_chapter_count, 1);
}

#[test]
fn reflects_read_count_after_marking_chapter_read() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter_1 = comic.join("Chapter 1");
    let chapter_2 = comic.join("Chapter 2");
    fs::create_dir_all(&chapter_1).expect("chapter 1");
    fs::create_dir_all(&chapter_2).expect("chapter 2");
    fs::write(chapter_1.join("001.png"), b"").expect("page 1");
    fs::write(chapter_2.join("001.png"), b"").expect("page 2");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    core.add_library(&library.to_string_lossy())
        .expect("add library");
    core.scan_libraries().expect("scan libraries");

    let chapter_id = core
        .open_chapter_for_reading(OpenChapterPayload {
            comic_source_path: comic.to_string_lossy().to_string(),
            chapter_source_path: chapter_1.to_string_lossy().to_string(),
        })
        .expect("open chapter");
    core.save_progress(SaveProgressPayload {
        chapter_id,
        last_page: 2,
        total_pages: 3,
        is_read: true,
    })
    .expect("save progress");

    let comics = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("list raw comics after read");
    assert_eq!(comics.len(), 1);
    assert_eq!(comics[0].chapter_count, 2);
    assert_eq!(comics[0].read_chapter_count, 1);
    assert_eq!(comics[0].in_progress_chapter_count, 0);
}

#[test]
fn reflects_all_chapters_read() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter_1 = comic.join("Chapter 1");
    let chapter_2 = comic.join("Chapter 2");
    fs::create_dir_all(&chapter_1).expect("chapter 1");
    fs::create_dir_all(&chapter_2).expect("chapter 2");
    fs::write(chapter_1.join("001.png"), b"").expect("page 1");
    fs::write(chapter_2.join("001.png"), b"").expect("page 2");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    core.add_library(&library.to_string_lossy())
        .expect("add library");
    core.scan_libraries().expect("scan libraries");

    // Mark chapter 1 as read
    let ch1_id = core
        .open_chapter_for_reading(OpenChapterPayload {
            comic_source_path: comic.to_string_lossy().to_string(),
            chapter_source_path: chapter_1.to_string_lossy().to_string(),
        })
        .expect("open chapter 1");
    core.save_progress(SaveProgressPayload {
        chapter_id: ch1_id,
        last_page: 2,
        total_pages: 3,
        is_read: true,
    })
    .expect("save progress ch1");

    // Mark chapter 2 as read
    let ch2_id = core
        .open_chapter_for_reading(OpenChapterPayload {
            comic_source_path: comic.to_string_lossy().to_string(),
            chapter_source_path: chapter_2.to_string_lossy().to_string(),
        })
        .expect("open chapter 2");
    core.save_progress(SaveProgressPayload {
        chapter_id: ch2_id,
        last_page: 2,
        total_pages: 3,
        is_read: true,
    })
    .expect("save progress ch2");

    let comics = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("list raw comics after all read");
    assert_eq!(comics.len(), 1);
    assert_eq!(comics[0].chapter_count, 2);
    assert_eq!(comics[0].read_chapter_count, 2);
    assert_eq!(comics[0].in_progress_chapter_count, 0);
}

#[test]
fn uses_cache_until_progress_save() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter_1 = comic.join("Chapter 1");
    let chapter_2 = comic.join("Chapter 2");
    fs::create_dir_all(&chapter_1).expect("chapter 1");
    fs::create_dir_all(&chapter_2).expect("chapter 2");
    fs::write(chapter_1.join("001.png"), b"").expect("page 1");
    fs::write(chapter_2.join("001.png"), b"").expect("page 2");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    core.add_library(&library.to_string_lossy())
        .expect("add library");
    core.scan_libraries().expect("scan libraries");

    let first = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("first listing");
    let second = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("second listing");
    assert_eq!(first, second);

    let chapter_id = core
        .open_chapter_for_reading(OpenChapterPayload {
            comic_source_path: comic.to_string_lossy().to_string(),
            chapter_source_path: chapter_1.to_string_lossy().to_string(),
        })
        .expect("open chapter");
    core.save_progress(SaveProgressPayload {
        chapter_id,
        last_page: 1,
        total_pages: 3,
        is_read: false,
    })
    .expect("save progress");

    let after_progress = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("listing after progress");
    assert_eq!(after_progress[0].in_progress_chapter_count, 1);
    assert_ne!(first, after_progress);
}

#[test]
fn size_bytes_populated_after_scan() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter_1 = comic.join("Chapter 1");
    let chapter_2 = comic.join("Chapter 2");
    fs::create_dir_all(&chapter_1).expect("chapter 1");
    fs::create_dir_all(&chapter_2).expect("chapter 2");
    fs::write(chapter_1.join("001.png"), vec![0u8; 2048]).expect("page 1");
    fs::write(chapter_1.join("002.png"), vec![0u8; 1024]).expect("page 2");
    fs::write(chapter_2.join("001.png"), vec![0u8; 4096]).expect("page 2-1");
    fs::write(chapter_1.join("Thumbs.db"), b"junk").expect("thumbs");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    core.add_library(&library.to_string_lossy())
        .expect("add library");
    core.scan_libraries().expect("scan libraries");

    let comics = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("list raw comics");
    assert_eq!(comics.len(), 1);
    assert_eq!(comics[0].chapter_count, 2);
    assert_eq!(comics[0].size_bytes, 2048 + 1024 + 4096);

    let stats = core.get_library_storage_stats().expect("storage stats");
    assert_eq!(stats.total_size_bytes, 2048 + 1024 + 4096);
    assert_eq!(stats.comic_count, 1);
}

#[test]
fn size_bytes_uses_archive_file_size_for_top_level_archive() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    fs::create_dir_all(&library).expect("library");
    let archive_path = library.join("Top Comic.cbz");
    let payload = vec![0u8; 8192];
    fs::write(&archive_path, &payload).expect("write cbz");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    core.add_library(&library.to_string_lossy())
        .expect("add library");
    core.scan_libraries().expect("scan libraries");

    let stats = core.get_library_storage_stats().expect("storage stats");
    assert_eq!(stats.total_size_bytes, payload.len() as i64);
    assert_eq!(stats.comic_count, 1);
}

#[test]
fn size_bytes_uses_archive_file_size_before_scan() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    fs::create_dir_all(&library).expect("library");
    let archive_path = library.join("Top Comic.cbz");
    let payload = vec![0u8; 4096];
    fs::write(&archive_path, &payload).expect("write cbz");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");

    let comics = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("list raw comics");
    assert_eq!(comics.len(), 1);
    assert_eq!(comics[0].size_bytes, payload.len() as i64);

    let stats = core.get_library_storage_stats().expect("storage stats");
    assert_eq!(stats.total_size_bytes, payload.len() as i64);
    assert_eq!(stats.comic_count, 1);
}

#[test]
fn size_bytes_preserved_after_rescan() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter_1 = comic.join("Chapter 1");
    let chapter_2 = comic.join("Chapter 2");
    fs::create_dir_all(&chapter_1).expect("chapter 1");
    fs::create_dir_all(&chapter_2).expect("chapter 2");
    fs::write(chapter_1.join("001.png"), vec![0u8; 2048]).expect("page 1");
    fs::write(chapter_2.join("001.png"), vec![0u8; 4096]).expect("page 2");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    core.add_library(&library.to_string_lossy())
        .expect("add library");

    core.scan_libraries().expect("first scan");
    let after_first = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("list after first scan");
    assert_eq!(after_first[0].size_bytes, 2048 + 4096);

    core.scan_libraries().expect("second scan");
    let after_second = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("list after second scan");
    assert_eq!(after_second[0].size_bytes, 2048 + 4096);
}
