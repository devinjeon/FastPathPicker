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

// --- vim/nvim split mode tests ---

#[test]
fn test_join_files_vim_split_mode() {
    let _guard = ENV_LOCK.lock().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_EDITOR", "vim") };
    unsafe { env::remove_var("FPP_DISABLE_SPLIT") };

    let result = join_files_into_command(&[("src/main.rs", 10), ("src/lib.rs", 20)]);
    assert_eq!(
        result, "vim  +10 src/main.rs +\"vsp +20 src/lib.rs\"",
        "Full vim split command mismatch"
    );

    unsafe { env::remove_var("FPP_EDITOR") };
}

#[test]
fn test_join_files_nvim_split_mode() {
    let _guard = ENV_LOCK.lock().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_EDITOR", "nvim") };
    unsafe { env::remove_var("FPP_DISABLE_SPLIT") };

    let result = join_files_into_command(&[("a.rs", 1), ("b.rs", 2), ("c.rs", 3)]);
    assert_eq!(
        result, "nvim  +1 a.rs +\"vsp +2 b.rs\" +\"vsp +3 c.rs\"",
        "Full nvim split command mismatch"
    );

    unsafe { env::remove_var("FPP_EDITOR") };
}

#[test]
fn test_join_files_vim_split_disabled() {
    let _guard = ENV_LOCK.lock().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_EDITOR", "vim") };
    unsafe { env::set_var("FPP_DISABLE_SPLIT", "1") };
    unsafe { env::remove_var("FPP_LINENUM_SEP") };

    let result = join_files_into_command(&[("a.rs", 1), ("b.rs", 2)]);
    // With split disabled, vim falls through to the general editor path.
    // "vim" is not in the special-case editor list, so paths are shell-escaped
    // and line numbers are omitted (no FPP_LINENUM_SEP set).
    assert_eq!(
        result, "vim  'a.rs' 'b.rs'",
        "Full vim split-disabled command mismatch"
    );

    unsafe { env::remove_var("FPP_EDITOR") };
    unsafe { env::remove_var("FPP_DISABLE_SPLIT") };
}

#[test]
fn test_join_files_vim_p_mode() {
    let _guard = ENV_LOCK.lock().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_EDITOR", "vim -p") };
    unsafe { env::remove_var("FPP_DISABLE_SPLIT") };

    let result = join_files_into_command(&[("a.rs", 1), ("b.rs", 2)]);
    assert_eq!(
        result, "vim -p  +1 a.rs +\"tabnew +2 b.rs\"",
        "Full vim -p command mismatch"
    );

    unsafe { env::remove_var("FPP_EDITOR") };
}

// --- append_exit shell branch tests ---

#[test]
fn test_append_exit_csh() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };
    unsafe { env::set_var("SHELL", "/bin/tcsh") };
    state::write_script("").unwrap();

    append_exit().unwrap();
    let script = std::fs::read_to_string(tmp.path().join(".fpp.sh")).unwrap();
    assert!(
        script.contains("$status"),
        "csh should use $status: {script}"
    );

    unsafe { env::remove_var("FPP_DIR") };
    unsafe { env::remove_var("SHELL") };
}

#[test]
fn test_append_exit_fish() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };
    unsafe { env::set_var("SHELL", "/usr/bin/fish") };
    state::write_script("").unwrap();

    append_exit().unwrap();
    let script = std::fs::read_to_string(tmp.path().join(".fpp.sh")).unwrap();
    assert!(
        script.contains("$status"),
        "fish should use $status: {script}"
    );

    unsafe { env::remove_var("FPP_DIR") };
    unsafe { env::remove_var("SHELL") };
}

#[test]
fn test_append_exit_rc() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };
    unsafe { env::set_var("SHELL", "/usr/bin/rc") };
    state::write_script("").unwrap();

    append_exit().unwrap();
    let script = std::fs::read_to_string(tmp.path().join(".fpp.sh")).unwrap();
    assert!(
        script.contains("$status"),
        "rc should use $status: {script}"
    );

    unsafe { env::remove_var("FPP_DIR") };
    unsafe { env::remove_var("SHELL") };
}

#[test]
fn test_append_exit_bash() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };
    unsafe { env::set_var("SHELL", "/bin/bash") };
    state::write_script("").unwrap();

    append_exit().unwrap();
    let script = std::fs::read_to_string(tmp.path().join(".fpp.sh")).unwrap();
    assert!(script.contains("$?"), "bash should use $?: {script}");

    unsafe { env::remove_var("FPP_DIR") };
    unsafe { env::remove_var("SHELL") };
}

#[test]
fn test_append_exit_no_shell() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };
    unsafe { env::remove_var("SHELL") };
    state::write_script("").unwrap();

    append_exit().unwrap();
    let script = std::fs::read_to_string(tmp.path().join(".fpp.sh")).unwrap();
    // When SHELL is unset, no exit line should be written
    assert!(
        !script.contains("exit"),
        "No SHELL should not write exit: {script}"
    );

    unsafe { env::remove_var("FPP_DIR") };
}

// --- compose_cd_command with ~/ home directory path ---

#[test]
fn test_compose_cd_command_home_path() {
    let obj = make_test_line_match("~/projects/test/file.rs");
    let result = compose_cd_command(&[obj]);
    // The path inside echo "..." should be expanded (no ~/ prefix),
    // but the > ~/.dircopy part is a literal redirect and stays as-is.
    let path = result
        .strip_prefix("echo \"")
        .unwrap()
        .strip_suffix("\" > ~/.dircopy")
        .unwrap();
    assert!(
        !path.starts_with("~/"),
        "Home dir in path should be expanded: {path}"
    );
    assert!(
        path.starts_with('/'),
        "Path should be absolute after expansion: {path}"
    );
    assert!(
        path.contains("projects/test"),
        "Path should contain original subpath: {path}"
    );
}

// Mutex to prevent parallel test interference with env vars within this module.
use crate::test_env::ENV_LOCK;

#[test]
fn test_output_nothing() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };

    output_nothing().unwrap();
    let script = std::fs::read_to_string(tmp.path().join(".fpp.sh")).unwrap();
    assert!(script.contains("nothing to do!"));

    unsafe { env::remove_var("FPP_DIR") };
}

#[test]
fn test_output_no_matches() {
    let _guard = ENV_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_DIR", tmp.path().to_str().unwrap()) };
    unsafe { env::set_var("SHELL", "/bin/bash") };

    output_no_matches().unwrap();
    let script = std::fs::read_to_string(tmp.path().join(".fpp.sh")).unwrap();
    assert!(script.contains("No lines matched!"));

    unsafe { env::remove_var("FPP_DIR") };
    unsafe { env::remove_var("SHELL") };
}

#[test]
fn test_join_files_editor_with_linenum_sep() {
    let _guard = ENV_LOCK.lock().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_EDITOR", "code") };
    unsafe { env::set_var("FPP_LINENUM_SEP", ":") };
    let result = join_files_into_command(&[("src/main.rs", 42)]);
    assert!(result.contains("'src/main.rs:42'"), "Got: {result}");
    unsafe { env::remove_var("FPP_EDITOR") };
    unsafe { env::remove_var("FPP_LINENUM_SEP") };
}

#[test]
fn test_join_files_editor_base_name_extraction() {
    let _guard = ENV_LOCK.lock().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_EDITOR", "emacs -nw") };
    let result = join_files_into_command(&[("src/main.rs", 10)]);
    assert!(result.contains("+10"), "Got: {result}");
    unsafe { env::remove_var("FPP_EDITOR") };
}

#[test]
fn test_join_files_zero_linenum() {
    let _guard = ENV_LOCK.lock().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_EDITOR", "nano") };
    let result = join_files_into_command(&[("src/main.rs", 0)]);
    assert!(!result.contains("+0"), "Should not have +0: {result}");
    unsafe { env::remove_var("FPP_EDITOR") };
}

#[test]
fn test_join_files_subl_linenum_format() {
    let _guard = ENV_LOCK.lock().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_EDITOR", "subl") };
    unsafe { env::remove_var("FPP_LINENUM_SEP") };
    let result = join_files_into_command(&[("src/main.rs", 42), ("lib.rs", 7)]);
    assert!(
        result.contains("'src/main.rs:42'"),
        "subl should use filename:linenum format: {result}"
    );
    assert!(result.contains("'lib.rs:7'"), "subl second file: {result}");
    unsafe { env::remove_var("FPP_EDITOR") };
}

#[test]
fn test_join_files_sublime_linenum_format() {
    let _guard = ENV_LOCK.lock().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_EDITOR", "sublime") };
    unsafe { env::remove_var("FPP_LINENUM_SEP") };
    let result = join_files_into_command(&[("a.rs", 10)]);
    assert!(
        result.contains("'a.rs:10'"),
        "sublime should use filename:linenum format: {result}"
    );
    unsafe { env::remove_var("FPP_EDITOR") };
}

#[test]
fn test_join_files_vi_linenum_format() {
    let _guard = ENV_LOCK.lock().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_EDITOR", "vi") };
    unsafe { env::remove_var("FPP_DISABLE_SPLIT") };
    let result = join_files_into_command(&[("src/main.rs", 5), ("lib.rs", 12)]);
    assert!(
        result.contains("+5 'src/main.rs'"),
        "vi should use +linenum filename format: {result}"
    );
    assert!(result.contains("+12 'lib.rs'"), "vi second file: {result}");
    unsafe { env::remove_var("FPP_EDITOR") };
}

#[test]
fn test_join_files_joe_linenum_format() {
    let _guard = ENV_LOCK.lock().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_EDITOR", "joe") };
    unsafe { env::remove_var("FPP_LINENUM_SEP") };
    let result = join_files_into_command(&[("a.rs", 3)]);
    assert!(
        result.contains("+3 'a.rs'"),
        "joe should use +linenum filename format: {result}"
    );
    unsafe { env::remove_var("FPP_EDITOR") };
}

#[test]
fn test_join_files_mvim_split_mode() {
    let _guard = ENV_LOCK.lock().unwrap();
    // SAFETY: test runs serially under ENV_LOCK
    unsafe { env::set_var("FPP_EDITOR", "mvim") };
    unsafe { env::remove_var("FPP_DISABLE_SPLIT") };
    let result = join_files_into_command(&[("a.rs", 1), ("b.rs", 2), ("c.rs", 3)]);
    assert_eq!(
        result, "mvim  +1 a.rs +\"vsp +2 b.rs\" +\"vsp +3 c.rs\"",
        "mvim split command mismatch"
    );
    unsafe { env::remove_var("FPP_EDITOR") };
}
