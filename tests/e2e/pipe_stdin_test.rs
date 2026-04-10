//! Integration tests for piped stdin handling.
//!
//! Verifies that the fpp binary correctly handles piped input
//! and produces expected output scripts. This was broken before
//! enabling crossterm's `use-dev-tty` feature and adding dup2
//! stdin redirect to /dev/tty.

use std::io::Write;
use std::process::{Command, Stdio};

fn fpp_binary() -> std::path::PathBuf {
    // cargo test builds to target/debug
    let mut path = std::env::current_exe()
        .unwrap()
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf();
    path.push("fpp");
    path
}

fn run_fpp_piped(input: &str, extra_args: &[&str]) -> (i32, String, String) {
    let tmp_dir = tempfile::tempdir().unwrap();
    let state_dir = tmp_dir.path().to_str().unwrap();

    let mut cmd = Command::new(fpp_binary());
    cmd.args(["--non-interactive", "--no-file-checks", "--all"])
        .args(extra_args)
        .env("FPP_DIR", state_dir)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    let mut child = cmd.spawn().expect("failed to spawn fpp");
    if let Some(ref mut stdin) = child.stdin {
        stdin.write_all(input.as_bytes()).unwrap();
    }
    drop(child.stdin.take());

    let output = child.wait_with_output().expect("failed to wait on fpp");
    let exit_code = output.status.code().unwrap_or(-1);
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    // Also read the generated script if it exists
    let script_path = tmp_dir.path().join(".fpp.sh");
    let script = std::fs::read_to_string(&script_path).unwrap_or_default();

    // Return exit code, script content, stderr
    let _ = stdout; // suppress unused warning
    (exit_code, script, stderr)
}

#[test]
fn test_piped_stdin_basic() {
    let (exit, script, stderr) = run_fpp_piped("src/main.rs\nsrc/parse.rs\n", &["-c", "echo"]);
    assert_eq!(exit, 0, "fpp should exit cleanly, stderr: {stderr}");
    assert!(
        script.contains("src/main.rs"),
        "script should contain src/main.rs, got: {script}"
    );
    assert!(
        script.contains("src/parse.rs"),
        "script should contain src/parse.rs, got: {script}"
    );
}

#[test]
fn test_piped_stdin_empty_input() {
    let (exit, _script, stderr) = run_fpp_piped("", &["-c", "echo"]);
    assert_eq!(
        exit, 0,
        "fpp should handle empty input gracefully, stderr: {stderr}"
    );
}

#[test]
fn test_piped_stdin_git_status_format() {
    let input = " M src/main.rs\n M src/parse.rs\n?? new_file.txt\n";
    let (exit, script, stderr) = run_fpp_piped(input, &["-c", "echo"]);
    assert_eq!(exit, 0, "fpp should parse git status, stderr: {stderr}");
    assert!(
        script.contains("src/main.rs"),
        "script should contain matched file, got: {script}"
    );
}

#[test]
fn test_piped_stdin_grep_format() {
    let input = "src/main.rs:42: fn main()\nsrc/parse.rs:10: use regex\n";
    let (exit, script, stderr) = run_fpp_piped(input, &["-c", "echo"]);
    assert_eq!(exit, 0, "fpp should parse grep output, stderr: {stderr}");
    assert!(
        script.contains("src/main.rs"),
        "script should contain matched file, got: {script}"
    );
}

#[test]
fn test_piped_stdin_large_input() {
    let mut input = String::new();
    for i in 1..=200 {
        input.push_str(&format!("src/file{i}.rs:{i}: content\n"));
    }
    let (exit, script, stderr) = run_fpp_piped(&input, &["-c", "echo"]);
    assert_eq!(exit, 0, "fpp should handle large input, stderr: {stderr}");
    assert!(
        script.contains("src/file1.rs"),
        "script should contain first file, got first 200 chars: {}",
        &script[..script.len().min(200)]
    );
    assert!(
        script.contains("src/file200.rs"),
        "script should contain last file"
    );
}

#[test]
fn test_piped_stdin_with_command_substitution() {
    let input = "src/main.rs\nsrc/parse.rs\n";
    let (exit, script, stderr) = run_fpp_piped(input, &["-c", "git add"]);
    assert_eq!(exit, 0, "fpp with -c should work, stderr: {stderr}");
    assert!(
        script.contains("git add"),
        "script should contain the command, got: {script}"
    );
}

#[test]
fn test_piped_stdin_no_matches() {
    // Input with no recognizable file paths
    let (exit, _script, stderr) =
        run_fpp_piped("just some random text\nno files here\n", &["-c", "echo"]);
    assert_eq!(
        exit, 0,
        "fpp should exit cleanly with no matches, stderr: {stderr}"
    );
}

#[test]
fn test_piped_stdin_creates_input_cache() {
    let tmp_dir = tempfile::tempdir().unwrap();
    let state_dir = tmp_dir.path().to_str().unwrap();

    let mut cmd = Command::new(fpp_binary());
    cmd.args([
        "--non-interactive",
        "--no-file-checks",
        "--all",
        "-c",
        "echo",
    ])
    .env("FPP_DIR", state_dir)
    .stdin(Stdio::piped())
    .stdout(Stdio::piped())
    .stderr(Stdio::piped());

    let mut child = cmd.spawn().expect("failed to spawn fpp");
    if let Some(ref mut stdin) = child.stdin {
        stdin.write_all(b"src/main.rs\nsrc/parse.rs\n").unwrap();
    }
    drop(child.stdin.take());
    let _ = child.wait_with_output().unwrap();

    let cache_path = tmp_dir.path().join(".input.json");
    assert!(
        cache_path.exists(),
        "input cache should be created at {cache_path:?}"
    );
}
