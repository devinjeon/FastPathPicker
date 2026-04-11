use super::*;

#[test]
fn test_is_cd_command() {
    assert!(is_cd_command("cd "));
    assert!(is_cd_command("cd"));
    assert!(is_cd_command("cd /some/path"));
    assert!(!is_cd_command("echo cd"));
}

#[test]
fn test_compose_file_command_append() {
    let objs = vec![
        make_test_line_match("file1.txt"),
        make_test_line_match("file2.txt"),
    ];
    let result = compose_file_command("git add", &objs);
    assert_eq!(result, "git add 'file1.txt' 'file2.txt'");
}

#[test]
fn test_compose_file_command_replace() {
    let objs = vec![
        make_test_line_match("file1.txt"),
        make_test_line_match("file2.txt"),
    ];
    let result = compose_file_command("mv $F ../here/", &objs);
    assert_eq!(result, "mv 'file1.txt' 'file2.txt' ../here/");
}

fn make_test_line_match(path: &str) -> LineMatch {
    use crate::format::FormattedText;
    LineMatch::new(
        FormattedText::new(path),
        path.to_string(),
        0,
        path.to_string(),
        0,
        path.len(),
    )
}

#[test]
fn test_compose_cd_command_absolute_path() {
    let obj = make_test_line_match("/usr/local/bin/test.rs");
    let result = compose_cd_command(&[obj]);
    assert!(result.contains("/usr/local/bin"));
    assert!(result.ends_with("\" > ~/.dircopy"));
}

#[test]
fn test_compose_cd_command_relative_path() {
    let obj = make_test_line_match("src/main.rs");
    let result = compose_cd_command(&[obj]);
    assert!(result.starts_with("echo \""));
    assert!(result.ends_with("\" > ~/.dircopy"));
    // Path should be absolute after normalization
    let path = result
        .strip_prefix("echo \"")
        .unwrap()
        .strip_suffix("\" > ~/.dircopy")
        .unwrap();
    assert!(path.starts_with('/'), "Path should be absolute: {path}");
}

#[test]
fn test_compose_cd_command_normalizes_dotdot() {
    let obj = make_test_line_match("/usr/local/bin/../lib/test.rs");
    let result = compose_cd_command(&[obj]);
    // .. should be normalized: /usr/local/bin/../lib -> /usr/local/lib
    assert!(
        result.contains("/usr/local/lib"),
        "Should normalize ..: {result}"
    );
    assert!(!result.contains(".."), "Should not contain ..: {result}");
}

#[test]
fn test_compose_cd_command_empty() {
    // Line 182: empty line_objs returns empty string
    let result = compose_cd_command(&[]);
    assert_eq!(result, "");
}

#[test]
fn test_shell_escape_single_quote() {
    // Line 263: single quote in path
    let result = shell_escape("can't stop");
    assert_eq!(result, "'can'\\''t stop'");
}

// Mutex to prevent parallel test interference with env vars within this module.
// NOTE: This lock only serializes tests within output_tests. Tests in state_tests
// and keybindings_tests have their own independent ENV_LOCK instances. To prevent
// cross-module races on FPP_DIR/SHELL/FPP_EDITOR, run with `--test-threads=1`
// or use `cargo test -- --test-threads=1`.
use std::sync::Mutex;
static ENV_LOCK: Mutex<()> = Mutex::new(());

#[test]
fn test_output_nothing() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    env::set_var("FPP_DIR", tmp.path().to_str().unwrap());

    output_nothing().unwrap();
    let script = std::fs::read_to_string(tmp.path().join(".fpp.sh")).unwrap();
    assert!(script.contains("nothing to do!"));

    env::remove_var("FPP_DIR");
}

#[test]
fn test_output_no_matches() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    env::set_var("FPP_DIR", tmp.path().to_str().unwrap());
    env::set_var("SHELL", "/bin/bash");

    output_no_matches().unwrap();
    let script = std::fs::read_to_string(tmp.path().join(".fpp.sh")).unwrap();
    assert!(script.contains("No lines matched!"));

    env::remove_var("FPP_DIR");
    env::remove_var("SHELL");
}

#[test]
fn test_join_files_editor_with_linenum_sep() {
    let _guard = ENV_LOCK.lock().unwrap();
    env::set_var("FPP_EDITOR", "code");
    env::set_var("FPP_LINENUM_SEP", ":");
    let result = join_files_into_command(&[("src/main.rs", 42)]);
    assert!(result.contains("'src/main.rs:42'"), "Got: {result}");
    env::remove_var("FPP_EDITOR");
    env::remove_var("FPP_LINENUM_SEP");
}

#[test]
fn test_join_files_editor_base_name_extraction() {
    let _guard = ENV_LOCK.lock().unwrap();
    env::set_var("FPP_EDITOR", "emacs -nw");
    let result = join_files_into_command(&[("src/main.rs", 10)]);
    assert!(result.contains("+10"), "Got: {result}");
    env::remove_var("FPP_EDITOR");
}

#[test]
fn test_join_files_zero_linenum() {
    let _guard = ENV_LOCK.lock().unwrap();
    env::set_var("FPP_EDITOR", "nano");
    let result = join_files_into_command(&[("src/main.rs", 0)]);
    assert!(!result.contains("+0"), "Should not have +0: {result}");
    env::remove_var("FPP_EDITOR");
}
