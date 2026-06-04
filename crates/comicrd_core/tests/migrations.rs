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
        pairs.get("app_theme").map(String::as_str),
        Some("\"light\"")
    );
    assert_eq!(pairs.get("app_locale").map(String::as_str), Some("\"en\""));
}
