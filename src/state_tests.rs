use super::*;

use crate::test_env::ENV_LOCK;

#[test]
fn test_save_and_load_selection() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };

    let state = SelectionState {
        selected_indices: vec![0, 3, 7],
    };
    save_selection(&state).unwrap();
    let loaded = load_selection().unwrap();
    assert_eq!(loaded.selected_indices, vec![0, 3, 7]);

    unsafe { env::remove_var("FPP_DIR") };
}

#[test]
fn test_load_selection_missing_file() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };

    let loaded = load_selection().unwrap();
    assert!(loaded.selected_indices.is_empty());

    unsafe { env::remove_var("FPP_DIR") };
}

#[test]
fn test_save_and_load_input_cache() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };

    let lines = vec!["src/main.rs".to_string(), "src/lib.rs".to_string()];
    save_input_cache(&lines).unwrap();
    let loaded = load_input_cache().unwrap();
    assert_eq!(loaded, lines);

    unsafe { env::remove_var("FPP_DIR") };
}

#[test]
fn test_load_input_cache_missing() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };

    let result = load_input_cache();
    assert!(result.is_err());

    unsafe { env::remove_var("FPP_DIR") };
}

#[test]
fn test_clean_state_all_files_exist() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };

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

    unsafe { env::remove_var("FPP_DIR") };
}

#[test]
fn test_clean_state_no_files_exist() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };

    ensure_state_dir().unwrap();
    let count = clean_state().unwrap();
    assert_eq!(count, 0);

    unsafe { env::remove_var("FPP_DIR") };
}

#[test]
fn test_clean_state_partial_files() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };

    ensure_state_dir().unwrap();
    fs::write(get_script_output_path(), "#!/bin/bash").unwrap();
    fs::write(get_state_dir().join(".fpp.log"), "[]").unwrap();
    // selection and input_cache do not exist

    let count = clean_state().unwrap();
    assert_eq!(count, 2);

    assert!(!get_script_output_path().exists());
    assert!(!get_state_dir().join(".fpp.log").exists());

    unsafe { env::remove_var("FPP_DIR") };
}

#[test]
fn test_delete_selection_exists() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };

    let state = SelectionState {
        selected_indices: vec![1, 2, 3],
    };
    save_selection(&state).unwrap();
    assert!(get_selection_path().exists());

    delete_selection().unwrap();
    assert!(!get_selection_path().exists());

    unsafe { env::remove_var("FPP_DIR") };
}

#[test]
fn test_delete_selection_not_exists() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };

    ensure_state_dir().unwrap();
    assert!(!get_selection_path().exists());

    // Should not error when file doesn't exist
    delete_selection().unwrap();

    unsafe { env::remove_var("FPP_DIR") };
}

#[test]
fn test_write_script_truncates() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };

    write_script("first content").unwrap();
    let content = fs::read_to_string(get_script_output_path()).unwrap();
    assert_eq!(content, "first content\n");

    // write_script should truncate previous content
    write_script("second").unwrap();
    let content = fs::read_to_string(get_script_output_path()).unwrap();
    assert_eq!(content, "second\n");

    unsafe { env::remove_var("FPP_DIR") };
}

#[test]
fn test_append_script() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };

    write_script("#!/bin/bash").unwrap();
    append_script("echo hello").unwrap();
    append_script("echo world").unwrap();

    let content = fs::read_to_string(get_script_output_path()).unwrap();
    assert!(content.contains("#!/bin/bash"));
    assert!(content.contains("echo hello"));
    assert!(content.contains("echo world"));

    unsafe { env::remove_var("FPP_DIR") };
}
