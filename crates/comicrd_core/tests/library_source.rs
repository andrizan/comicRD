use comicrd_core::ComicRdCore;
use std::fs;
use tempfile::tempdir;

#[test]
fn reports_unconfigured_path() {
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
fn reports_missing_path_as_mount_hint() {
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
fn reports_configured_readable_path() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    fs::create_dir_all(&library).expect("library");

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
}
