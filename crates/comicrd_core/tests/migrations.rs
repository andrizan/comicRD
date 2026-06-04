use comicrd_core::ComicRdCore;
use tempfile::tempdir;

#[test]
fn open_creates_database_and_seeds_compatible_default_settings() {
    let temp = tempdir().expect("tempdir");
    let core = ComicRdCore::open(temp.path()).expect("open core");

    let db_path = temp.path().join("comicrd.db");
    assert!(db_path.exists(), "core should create comicrd.db");

    let settings = core.list_settings().expect("list settings");
    let pairs = settings
        .into_iter()
        .map(|entry| (entry.key, entry.value_json))
        .collect::<std::collections::BTreeMap<_, _>>();

    assert_eq!(
        pairs.get("default_mode").map(String::as_str),
        Some("\"webtoon\"")
    );
    assert_eq!(
        pairs.get("arrow_navigation_enabled").map(String::as_str),
        Some("false")
    );
    assert_eq!(pairs.get("default_zoom").map(String::as_str), Some("1"));
    assert_eq!(pairs.get("page_gap").map(String::as_str), Some("10"));
    assert_eq!(
        pairs.get("library_sort_by").map(String::as_str),
        Some("\"name\"")
    );
    assert_eq!(
        pairs.get("library_sort_dir").map(String::as_str),
        Some("\"asc\"")
    );
    assert_eq!(
        pairs.get("library_view_mode").map(String::as_str),
        Some("\"library\"")
    );
    assert_eq!(
        pairs.get("library_display_mode").map(String::as_str),
        Some("\"grid\"")
    );
    assert_eq!(
        pairs.get("image_pipeline_profile").map(String::as_str),
        Some("\"balanced\"")
    );
    assert_eq!(
        pairs.get("chapter_sort_by").map(String::as_str),
        Some("\"chapter_index\"")
    );
    assert_eq!(
        pairs.get("chapter_sort_dir").map(String::as_str),
        Some("\"asc\"")
    );
    assert_eq!(
        pairs.get("library_source_input").map(String::as_str),
        Some("\"\"")
    );
    assert_eq!(
        pairs.get("app_theme").map(String::as_str),
        Some("\"light\"")
    );
    assert_eq!(pairs.get("app_locale").map(String::as_str), Some("\"en\""));
}

#[test]
fn open_copies_legacy_tauri_database_once_when_new_database_is_absent() {
    let temp = tempdir().expect("tempdir");
    let legacy_app_data = temp.path().join("com.andrizan.comicrd");
    let new_app_data = temp.path().join("comicrd_flutter");
    let legacy = ComicRdCore::open(&legacy_app_data).expect("open legacy");
    legacy
        .set_setting("app_locale", "\"id\"")
        .expect("set legacy locale");
    legacy
        .export_database_backup(legacy_app_data.join("comicrd.db.copy"))
        .expect("checkpoint legacy");
    drop(legacy);

    let migrated = ComicRdCore::open(&new_app_data).expect("open migrated");
    assert_eq!(
        migrated.get_setting("app_locale").expect("migrated locale"),
        Some("\"id\"".to_string())
    );
    migrated
        .set_setting("app_locale", "\"en\"")
        .expect("set migrated locale");
    drop(migrated);

    let reopened = ComicRdCore::open(&new_app_data).expect("reopen migrated");
    assert_eq!(
        reopened.get_setting("app_locale").expect("reopened locale"),
        Some("\"en\"".to_string())
    );
}
