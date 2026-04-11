use super::*;
use std::sync::Mutex;

// Prevent parallel tests from interfering with FPP_DIR env var within this module.
// NOTE: This lock only serializes tests within state_tests. Tests in output_tests
// and keybindings_tests have their own independent ENV_LOCK instances. To prevent
// cross-module races on FPP_DIR, run with `--test-threads=1`.
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

#[test]
fn test_clean_state_all_files_exist() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    env::set_var("FPP_DIR", tmp.path().to_str().unwrap());

    // Create all state files
    ensure_state_dir().unwrap();
    fs::write(get_script_output_path(), "#!/bin/bash").unwrap();
    fs::write(get_selection_path(), "{}").unwrap();
    fs::write(get_input_cache_path(), "[]").unwrap();
    fs::write(get_state_dir().join(".fpp.log"), "[]").unwrap();

    let count = clean_state().unwrap();
    assert_eq!(count, 4);

    // Verify all files are gone
    assert!(!get_script_output_path().exists());
    assert!(!get_selection_path().exists());
    assert!(!get_input_cache_path().exists());
    assert!(!get_state_dir().join(".fpp.log").exists());

    env::remove_var("FPP_DIR");
}

#[test]
fn test_clean_state_no_files_exist() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    env::set_var("FPP_DIR", tmp.path().to_str().unwrap());

    ensure_state_dir().unwrap();
    let count = clean_state().unwrap();
    assert_eq!(count, 0);

    env::remove_var("FPP_DIR");
}

#[test]
fn test_clean_state_partial_files() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    env::set_var("FPP_DIR", tmp.path().to_str().unwrap());

    ensure_state_dir().unwrap();
    fs::write(get_script_output_path(), "#!/bin/bash").unwrap();
    fs::write(get_state_dir().join(".fpp.log"), "[]").unwrap();
    // selection and input_cache do not exist

    let count = clean_state().unwrap();
    assert_eq!(count, 2);

    assert!(!get_script_output_path().exists());
    assert!(!get_state_dir().join(".fpp.log").exists());

    env::remove_var("FPP_DIR");
}

#[test]
fn test_delete_selection_exists() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    env::set_var("FPP_DIR", tmp.path().to_str().unwrap());

    let state = SelectionState {
        selected_indices: vec![1, 2, 3],
    };
    save_selection(&state).unwrap();
    assert!(get_selection_path().exists());

    delete_selection().unwrap();
    assert!(!get_selection_path().exists());

    env::remove_var("FPP_DIR");
}

#[test]
fn test_delete_selection_not_exists() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    env::set_var("FPP_DIR", tmp.path().to_str().unwrap());

    ensure_state_dir().unwrap();
    assert!(!get_selection_path().exists());

    // Should not error when file doesn't exist
    delete_selection().unwrap();

    env::remove_var("FPP_DIR");
}
