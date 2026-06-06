use comicrd_core::{ComicRdCore, OpenChapterPayload, SaveProgressPayload, SortBy, SortDir};
use std::fs;
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use tempfile::tempdir;

#[test]
fn scan_libraries_upserts_comics_chapters_and_progress_counts() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic_a = library.join("Comic A");
    let chapter_1 = comic_a.join("Chapter 1");
    let chapter_2 = comic_a.join("Chapter 2");
    let archive_comic = library.join("Comic B.cbz");
    fs::create_dir_all(&chapter_1).expect("chapter 1");
    fs::create_dir_all(&chapter_2).expect("chapter 2");
    fs::write(chapter_1.join("001.png"), b"").expect("page 1");
    fs::write(chapter_2.join("001.png"), b"").expect("page 2");
    fs::write(&archive_comic, b"placeholder").expect("archive");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    let library_id = core
        .add_library(&library.to_string_lossy())
        .expect("add library");

    let summary = core.scan_libraries().expect("scan libraries");
    assert_eq!(summary.comics, 2);
    assert_eq!(summary.chapters, 3);
    let scan_status = core.get_library_scan_status();
    assert!(!scan_status.running);
    assert!(scan_status.started_at.is_some());
    assert!(scan_status.finished_at.is_some());
    assert_eq!(scan_status.last_summary, Some(summary));
    assert_eq!(scan_status.error, None);

    let raw_comics = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("list raw comics");
    assert_eq!(raw_comics.len(), 2);
    assert_eq!(raw_comics[0].title, "Comic A");
    assert_eq!(raw_comics[0].chapter_count, 2);
    assert_eq!(raw_comics[0].read_chapter_count, 0);
    assert_eq!(raw_comics[0].in_progress_chapter_count, 0);
    assert_eq!(raw_comics[1].title, "Comic B");
    assert_eq!(raw_comics[1].source_type, "cbz");
    assert_eq!(raw_comics[1].chapter_count, 1);

    let chapter_id = core
        .open_chapter_for_reading(OpenChapterPayload {
            comic_source_path: comic_a.to_string_lossy().to_string(),
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

    let raw_comics = core
        .list_library_comics_raw(SortBy::Name, SortDir::Asc)
        .expect("list raw comics after progress");
    assert_eq!(raw_comics[0].title, "Comic A");
    assert_eq!(raw_comics[0].chapter_count, 2);
    assert_eq!(raw_comics[0].read_chapter_count, 0);
    assert_eq!(raw_comics[0].in_progress_chapter_count, 1);
}

#[test]
fn start_scan_libraries_updates_core_owned_scan_status() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    fs::create_dir_all(comic.join("Chapter 1")).expect("chapter");
    fs::write(comic.join("Chapter 1").join("001.png"), b"").expect("page");

    let core = Arc::new(ComicRdCore::open(&app_data).expect("open core"));
    core.add_library(&library.to_string_lossy())
        .expect("add library");

    assert!(core.start_scan_libraries().expect("start scan"));

    let mut scan_status = core.get_library_scan_status();
    for _ in 0..100 {
        if !scan_status.running && scan_status.finished_at.is_some() {
            break;
        }
        thread::sleep(Duration::from_millis(10));
        scan_status = core.get_library_scan_status();
    }

    assert!(!scan_status.running);
    assert!(scan_status.started_at.is_some());
    assert!(scan_status.finished_at.is_some());
    assert_eq!(scan_status.error, None);
    assert_eq!(scan_status.last_summary.expect("summary").comics, 1);
}
