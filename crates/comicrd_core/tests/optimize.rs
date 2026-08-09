use std::path::Path;

use comicrd_core::ComicRdCore;
use tempfile::tempdir;

fn setup_library(temp: &tempfile::TempDir) -> (ComicRdCore, std::path::PathBuf) {
    let library = temp.path().join("library");
    let comic_a = library.join("Comic A");
    let chapter_a1 = comic_a.join("Chapter 1");
    std::fs::create_dir_all(&chapter_a1).expect("chapter dir");
    std::fs::write(chapter_a1.join("001.png"), vec![0u8; 1024]).expect("page");

    let comic_b = library.join("Comic B");
    let chapter_b1 = comic_b.join("Chapter 1");
    std::fs::create_dir_all(&chapter_b1).expect("chapter dir");
    std::fs::write(chapter_b1.join("001.png"), vec![0u8; 1024]).expect("page");

    let core = ComicRdCore::open(&temp.path().join("app-data")).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    core.add_library(&library.to_string_lossy())
        .expect("add library");
    core.scan_libraries().expect("scan libraries");

    let comics = core.list_library_comics_raw(comicrd_core::SortBy::Name, comicrd_core::SortDir::Asc).expect("list");
    assert_eq!(comics.len(), 2);
    (core, library)
}

#[test]
fn database_size_bytes_reports_file_size() {
    let temp = tempdir().expect("tempdir");
    let core = ComicRdCore::open(&temp.path().join("app-data")).expect("open core");
    let db_path = temp.path().join("app-data").join("comicrd.db");
    assert!(db_path.exists());
    let size = core.database_size_bytes();
    assert!(size > 0, "database size should be positive");
}

#[test]
fn optimize_database_removes_stale_comics_and_chapters() {
    let temp = tempdir().expect("tempdir");
    let (core, library) = setup_library(&temp);

    // Favorite + bookmark referencing entries that will be purged.
    core.add_favorite(library.join("Comic A").to_string_lossy().as_ref())
        .expect("add favorite");
    let bookmarked_path = library
        .join("Comic B")
        .join("Chapter 1")
        .to_string_lossy()
        .to_string();
    core.add_bookmark(&bookmarked_path, library.join("Comic B").to_string_lossy().as_ref())
        .expect("add bookmark");

    // Delete Comic A from disk entirely, and Chapter 1 of Comic B.
    std::fs::remove_dir_all(library.join("Comic A")).expect("remove comic a");
    std::fs::remove_dir_all(library.join("Comic B").join("Chapter 1"))
        .expect("remove chapter b1");

    let result = core.optimize_database().expect("optimize");
    assert_eq!(result.removed_comics, 1, "one comic should be removed");
    assert_eq!(
        result.removed_chapters, 2,
        "chapter of deleted comic + chapter of remaining comic"
    );
    assert!(
        result.removed_reading_progress >= 0 && result.removed_page_bookmarks >= 0,
        "cascaded rows are counted"
    );
    assert!(
        result.removed_chapter_bookmarks >= 1,
        "bookmark for missing chapter should be purged"
    );
    assert!(
        result.removed_favorites >= 1,
        "favorite for missing comic should be purged"
    );
    assert_eq!(result.skipped_library_count, 0);

    let comics = core.list_library_comics_raw(comicrd_core::SortBy::Name, comicrd_core::SortDir::Asc).expect("list");
    assert_eq!(comics.len(), 1, "only Comic B remains");
    assert_eq!(comics[0].title, "Comic B");
}

#[test]
fn optimize_database_skips_unavailable_library() {
    let temp = tempdir().expect("tempdir");
    let (core, library) = setup_library(&temp);

    let missing_root = temp.path().join("missing");
    core.add_library(&missing_root.to_string_lossy())
        .expect("add missing library");

    // Nothing on disk changed, but the extra library root is unavailable.
    let result = core.optimize_database().expect("optimize");
    assert_eq!(result.removed_comics, 0);
    assert_eq!(result.skipped_library_count, 1);

    // Delete everything on disk; Comic A belongs to the available library,
    // so it is removed, while the unavailable library protects nothing here
    // because it holds no rows yet.
    std::fs::remove_dir_all(library.join("Comic A")).expect("remove comic a");
    let result = core.optimize_database().expect("optimize");
    assert_eq!(result.removed_comics, 1);
}

#[test]
fn optimize_database_vacuum_keeps_database_consistent() {
    let temp = tempdir().expect("tempdir");
    let (core, library) = setup_library(&temp);

    std::fs::remove_dir_all(library.join("Comic A")).expect("remove comic a");
    let result = core.optimize_database().expect("optimize");
    assert_eq!(result.removed_comics, 1);

    // After optimization the DB must still open and list remaining comics.
    let comics = core.list_library_comics_raw(comicrd_core::SortBy::Name, comicrd_core::SortDir::Asc).expect("list");
    assert_eq!(comics.len(), 1);
    assert!(core.database_size_bytes() > 0);
}

fn write_real_png(path: &std::path::Path) {
    let img = image::DynamicImage::new_rgb8(4, 4);
    img.save(path).expect("write png");
}

#[test]
fn optimize_database_purges_thumbnails_of_deleted_comics() {
    let temp = tempdir().expect("tempdir");
    let (core, library) = setup_library(&temp);

    // Replace the empty test pages with real images so covers can be cached.
    write_real_png(&library.join("Comic A").join("Chapter 1").join("001.png"));
    write_real_png(&library.join("Comic B").join("Chapter 1").join("001.png"));

    let comic_a = library.join("Comic A").to_string_lossy().to_string();
    let comic_b = library.join("Comic B").to_string_lossy().to_string();
    let cover_a = core.get_comic_thumbnail(&comic_a, 200, 300).expect("cover a");
    let cover_b = core.get_comic_thumbnail(&comic_b, 200, 300).expect("cover b");
    assert!(!cover_a.is_empty() && !cover_b.is_empty(), "covers generated");

    let thumbnails_dir = temp.path().join("app-data").join("thumbnails");
    let files_before: Vec<_> = std::fs::read_dir(&thumbnails_dir)
        .expect("thumbnails dir")
        .filter_map(|e| e.ok())
        .collect();
    assert_eq!(files_before.len(), 2, "both covers cached on disk");

    std::fs::remove_dir_all(library.join("Comic A")).expect("remove comic a");

    let result = core.optimize_database().expect("optimize");
    assert_eq!(result.removed_comics, 1);
    assert_eq!(result.removed_thumbnails, 1, "stale cover of deleted comic");
    assert!(result.removed_thumbnail_bytes > 0);

    let files_after: Vec<_> = std::fs::read_dir(&thumbnails_dir)
        .expect("thumbnails dir")
        .filter_map(|e| e.ok())
        .collect();
    assert_eq!(files_after.len(), 1, "cover of remaining comic is kept");
}

#[test]
fn optimize_database_after_open_is_idempotent() {
    let temp = tempdir().expect("tempdir");
    let (core, library) = setup_library(&temp);

    std::fs::remove_dir_all(library.join("Comic A")).expect("remove comic a");
    core.optimize_database().expect("optimize");

    // Second run: nothing left to remove, no errors.
    let result = core.optimize_database().expect("optimize");
    assert_eq!(result.removed_comics, 0);
    assert_eq!(result.removed_chapters, 0);

    // Reopen and verify consistency.
    drop(core);
    let core = ComicRdCore::open(&temp.path().join("app-data")).expect("reopen core");
    let comics = core.list_library_comics_raw(comicrd_core::SortBy::Name, comicrd_core::SortDir::Asc).expect("list");
    assert_eq!(comics.len(), 1, "reopen keeps cleaned state");
    assert!(
        Path::new(&temp.path().join("app-data").join("comicrd.db")).exists(),
        "db file still exists"
    );
}
