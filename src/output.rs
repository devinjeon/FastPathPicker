use std::env;

use anyhow::Result;

use crate::line::LineMatch;
use crate::logger;
use crate::state;

const RED_COLOR: &str = "\x1b[0;31m";
const NO_COLOR: &str = "\x1b[0m";

const INVALID_FILE_WARNING: &str = r#"
Warning! Some invalid or unresolvable files were detected.
"#;

const GIT_ABBREVIATION_WARNING: &str = r#"
It looks like one of these is a git abbreviated file with
a triple dot path (.../). Try to turn off git's abbreviation
with --numstat so we get actual paths (not abbreviated
versions which cannot be resolved.
"#;

const CONTINUE_WARNING: &str = "Are you sure you want to continue? Ctrl-C to quit";

/// Execute a composed command with the given line objects.
/// Writes the appropriate shell script to the state directory.
pub fn exec_composed_command(command: &str, line_objs: &[LineMatch]) -> Result<()> {
    state::write_script("")?;

    if command.is_empty() {
        return edit_files(line_objs);
    }

    logger::add_event("command_on_num_files", Some(line_objs.len()));
    let composed = compose_command(command, line_objs);
    append_alias_expansion()?;
    append_if_invalid(line_objs)?;
    append_friendly_command(&composed)?;
    append_exit()
}

/// Open selected files in the user's editor.
fn edit_files(line_objs: &[LineMatch]) -> Result<()> {
    logger::add_event("editing_num_files", Some(line_objs.len()));
    let files_and_nums: Vec<(&str, u64)> = line_objs
        .iter()
        .map(|obj| (obj.get_path(), obj.get_line_num()))
        .collect();
    let command = join_files_into_command(&files_and_nums);
    append_if_invalid(line_objs)?;
    state::append_script(&command)?;
    append_exit()
}

/// Build the editor command with file paths and line numbers.
fn join_files_into_command(files_and_nums: &[(&str, u64)]) -> String {
    let (editor, editor_path) = get_editor_and_path();
    let mut cmd = format!("{editor_path} ");

    if editor == "vim -p" {
        // vim -p mode: no quoting on paths (like Python)
        if let Some((first_path, first_num)) = files_and_nums.first() {
            cmd.push_str(&format!(" +{first_num} {first_path}"));
            for (path, num) in &files_and_nums[1..] {
                cmd.push_str(&format!(" +\"tabnew +{num} {path}\""));
            }
        }
    } else if matches!(editor.as_str(), "vim" | "mvim" | "nvim")
        && env::var("FPP_DISABLE_SPLIT")
            .ok()
            .filter(|v| !v.is_empty())
            .is_none()
    {
        // vim split mode: no quoting on paths (like Python)
        if let Some((first_path, first_num)) = files_and_nums.first() {
            cmd.push_str(&format!(" +{first_num} {first_path}"));
            for (path, num) in &files_and_nums[1..] {
                cmd.push_str(&format!(" +\"vsp +{num} {path}\""));
            }
        }
    } else {
        let editor_base = editor.split_whitespace().next().unwrap_or(&editor);
        for (path, num) in files_and_nums {
            let escaped = shell_escape(path);
            match editor_base {
                "vi" | "nvim" | "nano" | "joe" | "emacs" | "emacsclient" | "micro" if *num != 0 => {
                    cmd.push_str(&format!(" +{num} {escaped}"));
                }
                "subl" | "sublime" | "atom" | "hx" if *num != 0 => {
                    cmd.push_str(&format!(" {}", shell_escape(&format!("{path}:{num}"))));
                }
                _ => {
                    if *num != 0 {
                        if let Ok(sep) = env::var("FPP_LINENUM_SEP") {
                            cmd.push_str(&format!(
                                " {}",
                                shell_escape(&format!("{path}{sep}{num}"))
                            ));
                        } else {
                            cmd.push_str(&format!(" {escaped}"));
                        }
                    } else {
                        cmd.push_str(&format!(" {escaped}"));
                    }
                }
            }
        }
    }

    cmd
}

fn get_editor_and_path() -> (String, String) {
    // Python uses `os.environ.get("FPP_EDITOR") or ...` where empty string is falsy,
    // so we must filter out empty strings to match Python behavior.
    if let Some(editor_path) = env::var("FPP_EDITOR")
        .ok()
        .filter(|s| !s.is_empty())
        .or_else(|| env::var("VISUAL").ok().filter(|s| !s.is_empty()))
        .or_else(|| env::var("EDITOR").ok().filter(|s| !s.is_empty()))
    {
        let editor = std::path::Path::new(&editor_path)
            .file_name()
            .map_or(editor_path.clone(), |n| n.to_string_lossy().to_string());
        (editor, editor_path)
    } else {
        ("vim".to_string(), "vim".to_string())
    }
}

fn compose_command(command: &str, line_objs: &[LineMatch]) -> String {
    if is_cd_command(command) {
        return compose_cd_command(line_objs);
    }
    compose_file_command(command, line_objs)
}

fn is_cd_command(command: &str) -> bool {
    command.starts_with("cd ") || command == "cd"
}

fn compose_cd_command(line_objs: &[LineMatch]) -> String {
    if let Some(first) = line_objs.first() {
        let dir = first.get_dir();
        let expanded = if dir.starts_with("~/") {
            if let Some(home) = dirs::home_dir() {
                dir.replacen("~", &home.to_string_lossy(), 1)
            } else {
                dir
            }
        } else {
            dir
        };
        // Python uses os.path.abspath which normalizes `.`/`..` but does NOT
        // resolve symlinks (unlike Rust's canonicalize).
        let abs_path = if std::path::Path::new(&expanded).is_absolute() {
            std::path::PathBuf::from(&expanded)
        } else {
            std::env::current_dir()
                .map(|cwd| cwd.join(&expanded))
                .unwrap_or_else(|_| std::path::PathBuf::from(&expanded))
        };
        // Normalize `.`/`..` components without resolving symlinks
        let mut components = Vec::new();
        for comp in abs_path.components() {
            match comp {
                std::path::Component::ParentDir => {
                    components.pop();
                }
                std::path::Component::CurDir => {}
                _ => components.push(comp),
            }
        }
        let abs: String = components
            .iter()
            .collect::<std::path::PathBuf>()
            .to_string_lossy()
            .to_string();
        // Python uses double quotes: echo "{path}" > ~/.dircopy
        format!("echo \"{}\" > ~/.dircopy", abs.replace('"', "\\\""))
    } else {
        String::new()
    }
}

fn compose_file_command(command: &str, line_objs: &[LineMatch]) -> String {
    let paths: Vec<String> = line_objs
        .iter()
        .map(|obj| shell_escape(obj.get_path()))
        .collect();
    let path_str = paths.join(" ");

    if command.contains("$F") {
        command.replace("$F", &path_str)
    } else {
        format!("{command} {path_str}")
    }
}

fn append_if_invalid(line_objs: &[LineMatch]) -> Result<()> {
    let invalid: Vec<&LineMatch> = line_objs
        .iter()
        .filter(|obj| !obj.is_resolvable())
        .collect();

    if invalid.is_empty() {
        return Ok(());
    }

    append_error(INVALID_FILE_WARNING)?;
    if invalid.iter().any(|obj| obj.is_git_abbreviated_path()) {
        append_error(GIT_ABBREVIATION_WARNING)?;
    }
    state::append_script(&format!("read -p \"{CONTINUE_WARNING}\" -r"))
}

fn append_alias_expansion() -> Result<()> {
    // Python: `shell is None or "fish" not in shell` — when SHELL is unset,
    // alias expansion IS written (because `None is None` is True).
    let shell = env::var("SHELL").unwrap_or_default();
    if !shell.contains("fish") {
        state::append_script(
            r#"
if type shopt > /dev/null; then
  shopt -s expand_aliases
fi
"#,
        )?;
    }
    Ok(())
}

fn append_friendly_command(command: &str) -> Result<()> {
    // Python only escapes " to \" in the echo command (matching original behavior)
    let escaped = command.replace('"', "\\\"");
    state::append_script(&format!("echo \"executing command:\"\necho \"{escaped}\""))?;
    state::append_script(command)
}

fn append_error(text: &str) -> Result<()> {
    state::append_script(&format!("printf \"{RED_COLOR}{text}{NO_COLOR}\\n\""))
}

fn append_exit() -> Result<()> {
    // Python: os.environ["SHELL"] raises KeyError when SHELL is unset,
    // so append_exit() silently fails and no exit line is written.
    let shell = match env::var("SHELL") {
        Ok(s) => s,
        Err(_) => return Ok(()),
    };
    let exit_status = if shell.ends_with("csh") || shell.ends_with("fish") || shell.ends_with("rc")
    {
        "$status"
    } else {
        "$?"
    };
    state::append_script(&format!("exit {exit_status};"))
}

/// Escape a string for safe use in shell single quotes.
/// Handles embedded single quotes by ending the quote, adding an escaped quote, and reopening.
fn shell_escape(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

/// Output "nothing to do" and exit (used when user presses 'q').
pub fn output_nothing() -> Result<()> {
    state::write_script("")?;
    state::append_script("echo \"nothing to do!\"; exit 1")
}

/// Output "No lines matched!" (used when no matches found, like Python's choose.py).
pub fn output_no_matches() -> Result<()> {
    state::write_script("")?;
    state::append_script("echo \"No lines matched!\";")?;
    append_exit()
}

#[cfg(test)]
mod tests {
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
}
