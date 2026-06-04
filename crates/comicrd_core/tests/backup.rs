use comicrd_core::ComicRdCore;
use tempfile::tempdir;

#[test]
fn export_and_import_database_backup_replaces_active_database() {
    let temp = tempdir().expect("tempdir");
    let source_app_data = temp.path().join("source-app-data");
    let target_app_data = temp.path().join("target-app-data");
    let backup_path = temp.path().join("backup").join("comicrd-backup.db");

    let source = ComicRdCore::open(&source_app_data).expect("open source");
    source
        .set_setting("app_locale", "\"id\"")
        .expect("set locale");
    source
        .export_database_backup(&backup_path)
        .expect("export backup");
    assert!(backup_path.exists());

    let target = ComicRdCore::open(&target_app_data).expect("open target");
    assert_eq!(
        target.get_setting("app_locale").expect("target locale"),
        Some("\"en\"".to_string())
    );

    target
        .import_database_backup(&backup_path)
        .expect("import backup");

    assert_eq!(
        target.get_setting("app_locale").expect("imported locale"),
        Some("\"id\"".to_string())
    );
    assert!(target_app_data
        .read_dir()
        .expect("target app data entries")
        .any(|entry| entry
            .expect("target app data entry")
            .file_name()
            .to_string_lossy()
            .starts_with("comicrd.db.pre-import-")));
}
