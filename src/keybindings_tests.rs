use super::*;

use crate::test_env::ENV_LOCK;

#[test]
fn test_empty_config() {
    let bindings = parse_key_bindings("");
    assert!(bindings.is_empty());
}

#[test]
fn test_standard_parsing() {
    let config = "[bindings]\nr = rspec\ns = subl";
    let bindings = parse_key_bindings(config);
    assert_eq!(bindings.len(), 2);
    assert_eq!(bindings[0].key, "r");
    assert_eq!(bindings[0].command, "rspec");
    assert_eq!(bindings[1].key, "s");
    assert_eq!(bindings[1].command, "subl");
}

#[test]
fn test_no_bindings_section() {
    let config = "[other]\nkey = value";
    let bindings = parse_key_bindings(config);
    assert!(bindings.is_empty());
}

/// Ported from Python's test_ignore_non_existing_configuration_file.
/// read_key_bindings() should return an empty list for a non-existent file.
#[test]
fn test_ignore_non_existing_configuration_file() {
    let _guard = ENV_LOCK.lock().unwrap();
    // Temporarily set FPP_DIR to a temp directory with no .fpp.keys file.
    let tmp = std::env::temp_dir().join("fpp_test_no_keybindings");
    let _ = std::fs::create_dir_all(&tmp);
    // Make sure the keys file does NOT exist.
    let keys_file = tmp.join(".fpp.keys");
    let _ = std::fs::remove_file(&keys_file);

    // SAFETY: test runs serially under ENV_LOCK
    unsafe { std::env::set_var("FPP_DIR", &tmp) };
    let bindings = read_key_bindings();
    // Clean up
    unsafe { std::env::remove_var("FPP_DIR") };
    let _ = std::fs::remove_dir_all(&tmp);

    assert!(
        bindings.is_empty(),
        "read_key_bindings should return empty for non-existent file, got: {:?}",
        bindings.len(),
    );
}
