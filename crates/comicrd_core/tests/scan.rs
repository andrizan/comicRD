use comicrd_core::{ComicRdCore, OpenChapterPayload, SaveProgressPayload, SortBy, SortDir};
use std::fs;
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

    let comics = core
        .list_comics(SortBy::Name, SortDir::Asc)
        .expect("list comics");
    assert_eq!(comics.len(), 2);
    assert_eq!(comics[0].library_id, library_id);
    assert_eq!(comics[0].title, "Comic A");
    assert_eq!(comics[0].chapter_count, 2);
    assert_eq!(comics[0].read_chapter_count, 0);
    assert_eq!(comics[0].in_progress_chapter_count, 0);
    assert_eq!(comics[1].title, "Comic B");
    assert_eq!(comics[1].source_type, "cbz");
    assert_eq!(comics[1].chapter_count, 1);

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
        mode: "webtoon".to_string(),
        is_read: false,
    })
    .expect("save progress");

    let comics = core
        .list_comics(SortBy::Name, SortDir::Asc)
        .expect("list comics after progress");
    assert_eq!(comics[0].read_chapter_count, 0);
    assert_eq!(comics[0].in_progress_chapter_count, 1);
}
