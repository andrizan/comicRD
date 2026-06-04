use comicrd_core::{ComicRdCore, SortBy, SortDir};
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
    assert_eq!(titles, vec!["Comic Folder", "Zed Comic"]);

    assert_eq!(comics[0].source_type, "folder");
    assert_eq!(comics[0].chapter_count, 0);
    assert_eq!(comics[1].source_type, "cbz");
    assert_eq!(comics[1].chapter_count, 1);
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
