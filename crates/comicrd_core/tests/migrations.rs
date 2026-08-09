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
        pairs.get("arrow_navigation_enabled").map(String::as_str),
        Some("false")
    );
    assert_eq!(pairs.get("default_zoom").map(String::as_str), Some("1"));
    assert_eq!(pairs.get("page_gap").map(String::as_str), Some("10"));
    assert_eq!(
        pairs.get("unlimited_scroll").map(String::as_str),
        Some("false")
    );
    assert_eq!(
        pairs.get("unlimited_scroll_up").map(String::as_str),
        Some("true")
    );
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

#[test]
fn reopen_is_idempotent_and_preserves_size_bytes_columns() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    let library = temp.path().join("library");
    let comic = library.join("Comic A");
    let chapter = comic.join("Chapter 1");
    std::fs::create_dir_all(&chapter).expect("chapter");
    std::fs::write(chapter.join("001.png"), vec![0u8; 1024]).expect("page");

    let core = ComicRdCore::open(&app_data).expect("open core");
    core.set_setting(
        "library_source_input",
        &serde_json::to_string(&library).unwrap(),
    )
    .expect("set library source");
    core.add_library(&library.to_string_lossy())
        .expect("add library");
    core.scan_libraries().expect("scan libraries");
    drop(core);

    let core = ComicRdCore::open(&app_data).expect("reopen core");
    let stats = core.get_library_storage_stats().expect("stats");
    assert_eq!(stats.total_size_bytes, 1024);
    assert_eq!(stats.comic_count, 1);
}

#[test]
fn open_drops_legacy_history_key_columns_from_existing_database() {
    let temp = tempdir().expect("tempdir");
    let app_data = temp.path().join("app-data");
    std::fs::create_dir_all(&app_data).expect("app data dir");
    let db_path = app_data.join("comicrd.db");

    let legacy_conn = rusqlite::Connection::open(&db_path).expect("legacy db");
    legacy_conn
        .execute_batch(
            r#"
        CREATE TABLE libraries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          path TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
        CREATE TABLE comics (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          library_id INTEGER NOT NULL,
          title TEXT NOT NULL,
          history_key TEXT NOT NULL,
          source_path TEXT NOT NULL UNIQUE,
          source_type TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          date_modified INTEGER NOT NULL,
          size_bytes INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY(library_id) REFERENCES libraries(id) ON DELETE CASCADE
        );
        CREATE TABLE chapters (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          comic_id INTEGER NOT NULL,
          title TEXT NOT NULL,
          chapter_index INTEGER NOT NULL,
          history_key TEXT NOT NULL,
          source_path TEXT NOT NULL UNIQUE,
          source_type TEXT NOT NULL,
          page_count INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          date_modified INTEGER NOT NULL,
          size_bytes INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY(comic_id) REFERENCES comics(id) ON DELETE CASCADE
        );
        CREATE INDEX idx_comics_history_key ON comics(history_key);
        CREATE INDEX idx_chapters_history_key ON chapters(history_key);
        INSERT INTO libraries (id, path, created_at, updated_at) VALUES (1, '/tmp/lib', 1, 1);
        INSERT INTO comics (id, library_id, title, history_key, source_path, source_type, created_at, updated_at, date_modified)
          VALUES (1, 1, 'Comic A', 'comic/Comic A', '/tmp/lib/Comic A', 'folder', 1, 1, 1);
        INSERT INTO chapters (id, comic_id, title, chapter_index, history_key, source_path, source_type, page_count, created_at, updated_at, date_modified)
          VALUES (1, 1, 'Chapter 1', 1, 'chapter/Comic A/Chapter 1#1', '/tmp/lib/Comic A/Chapter 1', 'folder', 0, 1, 1, 1);
        "#,
        )
        .expect("create legacy schema");
    drop(legacy_conn);

    let core = ComicRdCore::open(&app_data).expect("open core with legacy db");
    drop(core);

    let migrated_conn = rusqlite::Connection::open(&db_path).expect("migrated db");
    let columns: Vec<String> = migrated_conn
        .prepare("PRAGMA table_info(comics)")
        .expect("prepare comics info")
        .query_map([], |row| row.get::<_, String>(1))
        .expect("query comics info")
        .collect::<Result<_, _>>()
        .expect("collect comics columns");
    assert!(!columns.contains(&"history_key".to_string()));
    let columns: Vec<String> = migrated_conn
        .prepare("PRAGMA table_info(chapters)")
        .expect("prepare chapters info")
        .query_map([], |row| row.get::<_, String>(1))
        .expect("query chapters info")
        .collect::<Result<_, _>>()
        .expect("collect chapters columns");
    assert!(!columns.contains(&"history_key".to_string()));

    let comic_count: i64 = migrated_conn
        .query_row("SELECT COUNT(*) FROM comics", [], |row| row.get(0))
        .expect("count comics");
    assert_eq!(comic_count, 1);
    let chapter_count: i64 = migrated_conn
        .query_row("SELECT COUNT(*) FROM chapters", [], |row| row.get(0))
        .expect("count chapters");
    assert_eq!(chapter_count, 1);
    let source_path: String = migrated_conn
        .query_row("SELECT source_path FROM comics WHERE id = 1", [], |row| {
            row.get(0)
        })
        .expect("read comic source_path");
    assert_eq!(source_path, "/tmp/lib/Comic A");
}
