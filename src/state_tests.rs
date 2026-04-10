use super::*;
use std::sync::Mutex;

// Prevent parallel tests from interfering with FPP_DIR env var.
static ENV_LOCK: Mutex<()> = Mutex::new(());

#[test]
fn test_save_and_load_selection() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    env::set_var("FPP_DIR", tmp.path().to_str().unwrap());

    let state = SelectionState {
        selected_indices: vec![0, 3, 7],
    };
    save_selection(&state).unwrap();
    let loaded = load_selection().unwrap();
    assert_eq!(loaded.selected_indices, vec![0, 3, 7]);

    env::remove_var("FPP_DIR");
}

#[test]
fn test_load_selection_missing_file() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    env::set_var("FPP_DIR", tmp.path().to_str().unwrap());

    let loaded = load_selection().unwrap();
    assert!(loaded.selected_indices.is_empty());

    env::remove_var("FPP_DIR");
}

#[test]
fn test_save_and_load_input_cache() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    env::set_var("FPP_DIR", tmp.path().to_str().unwrap());

    let lines = vec!["src/main.rs".to_string(), "src/lib.rs".to_string()];
    save_input_cache(&lines).unwrap();
    let loaded = load_input_cache().unwrap();
    assert_eq!(loaded, lines);

    env::remove_var("FPP_DIR");
}

#[test]
fn test_load_input_cache_missing() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    env::set_var("FPP_DIR", tmp.path().to_str().unwrap());

    let result = load_input_cache();
    assert!(result.is_err());

    env::remove_var("FPP_DIR");
}
