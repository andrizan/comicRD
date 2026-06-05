use comicrd_core::{ComicRdCore, OpenChapterPayload, SaveProgressPayload, SortBy, SortDir};
use std::fs;
use tempfile::tempdir;

#[test]
fn list_library_comics_raw_reads_configured_source_folder_and_archive() {
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

    let status = core.check_library_source().expect("source status");
    assert!(status.configured);
    assert!(status.exists);
    assert!(status.is_dir);
    assert!(status.readable);
    assert_eq!(status.path, library.to_string_lossy());

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
fn check_library_source_reports_unconfigured_path() {
    let temp = tempdir().expect("tempdir");
    let core = ComicRdCore::open(temp.path()).expect("open core");

    let status = core.check_library_source().expect("source status");

    assert!(!status.configured);
    assert_eq!(status.path, "");
    assert!(!status.exists);
    assert!(!status.is_dir);
    assert!(!status.readable);
    assert_eq!(status.error, None);
}

#[test]
fn check_library_source_reports_missing_path_as_mount_hint() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let missing_library = temp.path().join("unmounted-library");
    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&missing_library).unwrap(),
    )
    .expect("set library source");

    let status = core.check_library_source().expect("source status");

    assert!(status.configured);
    assert_eq!(status.path, missing_library.to_string_lossy());
    assert!(!status.exists);
    assert!(!status.is_dir);
    assert!(!status.readable);
    assert_eq!(
        status.error,
        Some(format!(
            "path '{}' not found. On Linux, you may need to mount the partition first.",
            missing_library.display()
        ))
    );
}

#[test]
fn list_library_comics_raw_returns_error_when_library_not_configured() {
    let temp = tempdir().expect("tempdir");
    let core = ComicRdCore::open(temp.path()).expect("open core");

    let result = core.list_library_comics_raw(SortBy::Name, SortDir::Asc);

    assert!(result.is_err());
}

#[test]
fn list_library_comics_raw_returns_zero_counts_before_scan() {
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
}

#[test]
fn list_library_comics_raw_reads_counts_from_db_after_scan() {
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
fn list_library_comics_raw_reflects_progress_after_save() {
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
fn list_library_comics_raw_uses_cache_until_progress_save() {
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
