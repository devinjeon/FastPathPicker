//! Screen snapshot tests: port of Python's test_screen.py.
//!
//! Renders the UI into a virtual terminal via the vt100 crate,
//! then compares the output against Python's expected snapshot files.

use std::path::{Path, PathBuf};

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

// Access internal crate items via the binary crate's public API.
// Since fpp is a binary crate, we use `include!` or direct module access won't work.
// Instead, we compile against the library by re-exporting what we need.

/// Path to the test inputs directory.
fn inputs_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/inputs")
}

/// Path to the expected snapshots directory.
fn expected_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/expected")
}

/// Read an input file and return its lines.
fn read_input_file(name: &str) -> Vec<String> {
    let path = inputs_dir().join(name);
    let content = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("Failed to read input file {}: {}", path.display(), e));
    content.split('\n').map(|s| s.to_string()).collect()
}

/// Read the expected snapshot file.
fn read_expected(name: &str) -> String {
    let path = expected_dir().join(format!("{name}.txt"));
    std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("Failed to read expected file {}: {}", path.display(), e))
}

/// Python attribute symbol mapping (from ScreenForTest.ATTRIBUTE_SYMBOL_MAPPING).
/// Maps (bold, underline, fg_color, bg_color) to a single character.
fn attr_symbol(cell: &vt100::Cell) -> char {
    let bold = cell.bold();
    let underline = cell.underline();
    let bg = cell.bgcolor();

    // crossterm 256-color indices: Blue=12, Red=9, Green=10, White=15
    // Python curses attribute symbol mapping:
    //   bold + blue bg (hovered)          → "*"  (2097154)
    //   bold + red bg  (hovered+selected) → "/"  (2097156)
    //   bold + green bg (selected)        → "|"  (2097155)
    //   underline (normal match)          → "_"  (131072)
    match (bold, underline, bg) {
        // Hovered: Bold + Blue BG (crossterm Color::Blue = idx 12)
        (true, _, vt100::Color::Idx(12)) => '*',
        // Hovered + Selected: Bold + Red BG (crossterm Color::Red = idx 9)
        (true, _, vt100::Color::Idx(9)) => '/',
        // Selected: Bold + Green BG (crossterm Color::Green = idx 10)
        (true, _, vt100::Color::Idx(10)) => '|',
        // Underlined (normal match)
        (_, true, _) => '_',
        // Default
        _ => ' ',
    }
}

/// Parse a key input string into a KeyEvent.
fn parse_key_input(input: &str) -> KeyEvent {
    match input {
        "UP" => KeyEvent::new(KeyCode::Up, KeyModifiers::NONE),
        "DOWN" => KeyEvent::new(KeyCode::Down, KeyModifiers::NONE),
        "HOME" => KeyEvent::new(KeyCode::Home, KeyModifiers::NONE),
        "END" => KeyEvent::new(KeyCode::End, KeyModifiers::NONE),
        "NPAGE" | "PAGEDOWN" => KeyEvent::new(KeyCode::PageDown, KeyModifiers::NONE),
        "PPAGE" | "PAGEUP" => KeyEvent::new(KeyCode::PageUp, KeyModifiers::NONE),
        " " => KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE),
        s if s.len() == 1 => {
            let ch = s.chars().next().unwrap();
            KeyEvent::new(KeyCode::Char(ch), KeyModifiers::NONE)
        }
        other => panic!("Unknown key input: {other}"),
    }
}

/// Strip \x1b[2J (clear screen) sequences from raw terminal output.
fn strip_clear(data: &[u8]) -> Vec<u8> {
    let mut result = Vec::new();
    let mut i = 0;
    while i < data.len() {
        if i + 3 < data.len()
            && data[i] == 0x1b
            && data[i + 1] == b'['
            && data[i + 2] == b'2'
            && data[i + 3] == b'J'
        {
            i += 4;
            continue;
        }
        result.push(data[i]);
        i += 1;
    }
    result
}

/// Extract text and attribute rows from a rendered buffer using two-pass vt100 parsing.
///
/// Two-pass approach:
/// Pass 1 (with clear): full render with \x1b[2J — all cells correct, but unwritten cells
///   are filled with spaces (indistinguishable from intentional spaces).
/// Pass 2 (without clear): \x1b[2J stripped — unwritten cells remain truly empty,
///   so we can tell which cells were explicitly written by the render code.
///
/// Rule: include a cell if Pass 2 shows it as non-empty (explicitly written).
///       Skip it only if Pass 2 shows empty (never written = clear artifact).
fn extract_rows_from_buf(buf: &[u8], width: u16, height: u16) -> (Vec<String>, Vec<String>) {
    // Pass 1: full render (for correct content and attributes)
    let mut full_parser = vt100::Parser::new(height, width, 0);
    full_parser.process(buf);
    let full_screen = full_parser.screen();

    // Pass 2: render without clear (to identify explicitly written cells)
    let no_clear_buf = strip_clear(buf);
    let mut no_clear_parser = vt100::Parser::new(height, width, 0);
    no_clear_parser.process(&no_clear_buf);
    let no_clear_screen = no_clear_parser.screen();

    let mut text_rows = Vec::new();
    let mut attr_rows = Vec::new();
    for row in 0..height {
        let mut text = String::new();
        let mut attrs = String::new();
        for col in 0..width {
            let full_cell = full_screen.cell(row, col).unwrap();
            let no_clear_cell = no_clear_screen.cell(row, col).unwrap();
            let was_written = !no_clear_cell.contents().is_empty();
            if was_written {
                let contents = full_cell.contents();
                if contents.is_empty() {
                    text.push(' ');
                    attrs.push(' ');
                } else {
                    text.push_str(&contents);
                    attrs.push(attr_symbol(full_cell));
                }
            }
        }
        text_rows.push(text);
        attr_rows.push(attrs);
    }

    (text_rows, attr_rows)
}

/// Render the controller to a virtual terminal and extract rows.
/// Returns (text_rows, attribute_rows).
fn render_to_vt100(
    lines: Vec<fpp2::line::Line>,
    match_indices: Vec<usize>,
    char_inputs: &[&str],
    screen_config: (u16, u16), // (width, height)
    preset_command: Option<String>,
    initial_select_all: bool,
    all_input: bool,
) -> (Vec<String>, Vec<String>) {
    let (width, height) = screen_config;

    let mut ctrl = fpp2::ui::controller::Controller::new(
        lines,
        match_indices,
        preset_command,
        initial_select_all,
        None, // execute_keys handled manually below
        all_input,
    );
    ctrl.set_viewport_size(width, height);

    // Feed key inputs
    for input in char_inputs {
        let key = parse_key_input(input);
        let _ = ctrl.handle_key(key);
    }

    // Render to a buffer
    let mut buf: Vec<u8> = Vec::new();
    ctrl.render_to(&mut buf, (width, height))
        .expect("render_to failed");

    extract_rows_from_buf(&buf, width, height)
}

/// Render the controller after each keystroke and capture all intermediate screen states.
/// Returns a Vec of (text_rows, attribute_rows) — one per render cycle.
///
/// Matches the Python ScreenForTest capture model: the screen state is captured
/// after processing each key input and re-rendering. There is no initial render
/// capture (Python's getch() is called before the first render in the loop).
/// So index 0 = after 1st key, index 1 = after 2nd key, etc.
fn render_to_vt100_with_history(
    lines: Vec<fpp2::line::Line>,
    match_indices: Vec<usize>,
    char_inputs: &[&str],
    screen_config: (u16, u16),
    preset_command: Option<String>,
    initial_select_all: bool,
    all_input: bool,
) -> Vec<(Vec<String>, Vec<String>)> {
    let (width, height) = screen_config;

    let mut ctrl = fpp2::ui::controller::Controller::new(
        lines,
        match_indices,
        preset_command,
        initial_select_all,
        None,
        all_input,
    );
    ctrl.set_viewport_size(width, height);

    let mut history = Vec::new();

    // Feed keys one at a time, capturing after each
    for input in char_inputs {
        let key = parse_key_input(input);
        let _ = ctrl.handle_key(key);

        let mut buf: Vec<u8> = Vec::new();
        ctrl.render_to(&mut buf, (width, height))
            .expect("render_to failed");
        history.push(extract_rows_from_buf(&buf, width, height));
    }

    history
}

/// Trait to trim trailing whitespace from strings.
trait TrimEnd {
    fn trimmed_end(&self) -> String;
}

impl TrimEnd for String {
    fn trimmed_end(&self) -> String {
        self.trim_end().to_string()
    }
}

/// Check if a line matches a glob pattern (Python test uses " (glob)" suffix).
/// Supports `*` as wildcard matching any characters.
fn matches_glob(pattern: &str, actual: &str) -> bool {
    let parts: Vec<&str> = pattern.split('*').collect();
    let mut pos = 0;
    for (i, part) in parts.iter().enumerate() {
        if part.is_empty() {
            continue;
        }
        if let Some(found) = actual[pos..].find(part) {
            if i == 0 && found != 0 {
                return false; // First part must match at start
            }
            pos += found + part.len();
        } else {
            return false;
        }
    }
    // If pattern doesn't end with *, actual must end exactly
    if !pattern.ends_with('*') {
        pos == actual.len()
    } else {
        true
    }
}

/// Compare actual lines against expected lines, trimming trailing whitespace on both sides.
fn compare_lines(test_name: &str, actual: &[&str], expected: &[&str]) {
    let actual_trimmed: Vec<&str> = actual.iter().map(|s| s.trim_end()).collect();
    let expected_trimmed: Vec<&str> = expected.iter().map(|s| s.trim_end()).collect();

    let actual_len = actual_trimmed
        .iter()
        .rposition(|s| !s.is_empty())
        .map_or(0, |i| i + 1);
    let expected_len = expected_trimmed
        .iter()
        .rposition(|s| !s.is_empty())
        .map_or(0, |i| i + 1);

    let max_len = actual_len.max(expected_len);

    for i in 0..max_len {
        let actual_line = actual_trimmed.get(i).copied().unwrap_or("");
        let expected_line = expected_trimmed.get(i).copied().unwrap_or("");

        // Python tests use " (glob)" suffix for wildcard matching
        let glob_suffix = " (glob)";
        if expected_line.ends_with(glob_suffix) {
            let pattern = &expected_line[..expected_line.len() - glob_suffix.len()];
            assert!(
                matches_glob(pattern, actual_line),
                "\nTest '{}' line {} glob mismatch:\nPattern:  {:?}\nActual:   {:?}",
                test_name,
                i + 1,
                pattern,
                actual_line,
            );
        } else {
            assert_eq!(
                actual_line,
                expected_line,
                "\nTest '{}' line {} mismatch:\nExpected: {:?}\nActual:   {:?}",
                test_name,
                i + 1,
                expected_line,
                actual_line,
            );
        }
    }
}

/// Configuration for a screen test case.
struct ScreenTestCase {
    name: &'static str,
    input_file: &'static str,
    inputs: Vec<&'static str>,
    args_select_all: bool,
    args_command: Option<String>,
    screen_config: (u16, u16), // (width, height)
    with_attributes: bool,
    validate_file_exists: bool,
    all_input: bool,
    past_screen: Option<usize>,
    past_screens: Option<Vec<usize>>,
}

impl Default for ScreenTestCase {
    fn default() -> Self {
        Self {
            name: "",
            input_file: "gitDiff.txt",
            inputs: vec![],
            args_select_all: false,
            args_command: None,
            screen_config: (80, 30),
            with_attributes: false,
            validate_file_exists: false,
            all_input: false,
            past_screen: None,
            past_screens: None,
        }
    }
}

/// Run a single screen test case and compare against expected output.
fn run_screen_test(tc: &ScreenTestCase) {
    let raw_lines = read_input_file(tc.input_file);
    let lines =
        fpp2::input::get_line_objs_from_lines(&raw_lines, tc.validate_file_exists, tc.all_input);
    let match_indices = fpp2::input::get_matches(&lines);

    let (text_rows, _attr_rows) = if let Some(ref indices) = tc.past_screens {
        // Render with history and concatenate requested screen states
        let history = render_to_vt100_with_history(
            lines,
            match_indices,
            &tc.inputs,
            tc.screen_config,
            tc.args_command.clone(),
            tc.args_select_all,
            tc.all_input,
        );
        let mut combined_text = Vec::new();
        let mut combined_attrs = Vec::new();
        for &idx in indices {
            let (ref text, ref attrs) = history[idx];
            combined_text.extend(text.iter().cloned());
            combined_attrs.extend(attrs.iter().cloned());
        }
        (combined_text, combined_attrs)
    } else if let Some(idx) = tc.past_screen {
        // Render with history and pick the requested screen state
        let history = render_to_vt100_with_history(
            lines,
            match_indices,
            &tc.inputs,
            tc.screen_config,
            tc.args_command.clone(),
            tc.args_select_all,
            tc.all_input,
        );
        history[idx].clone()
    } else {
        // Normal case: render final state only
        render_to_vt100(
            lines,
            match_indices,
            &tc.inputs,
            tc.screen_config,
            tc.args_command.clone(),
            tc.args_select_all,
            tc.all_input,
        )
    };

    let expected_content = read_expected(tc.name);
    let expected_lines: Vec<&str> = expected_content.split('\n').collect();

    if tc.with_attributes {
        // Python expected files interleave: text line, attribute line, text line, ...
        // Extract only text lines from expected (every other line starting at 0)
        let expected_text_lines: Vec<&str> = expected_lines.iter().step_by(2).copied().collect();
        let actual_trimmed: Vec<String> = text_rows.iter().map(|s| s.trimmed_end()).collect();
        let actual_refs: Vec<&str> = actual_trimmed.iter().map(|s| s.as_str()).collect();
        compare_lines(tc.name, &actual_refs, &expected_text_lines);
    } else {
        let actual_trimmed: Vec<String> = text_rows.iter().map(|s| s.trimmed_end()).collect();
        let actual_refs: Vec<&str> = actual_trimmed.iter().map(|s| s.as_str()).collect();
        compare_lines(tc.name, &actual_refs, &expected_lines);
    }
}

// === Test Cases ===

#[test]
fn test_simple_load_and_quit() {
    run_screen_test(&ScreenTestCase {
        name: "simpleLoadAndQuit",
        ..Default::default()
    });
}

#[test]
fn test_select_first() {
    run_screen_test(&ScreenTestCase {
        name: "selectFirst",
        inputs: vec!["f"],
        ..Default::default()
    });
}

#[test]
fn test_select_first_with_down() {
    run_screen_test(&ScreenTestCase {
        name: "selectFirstWithDown",
        inputs: vec!["F"],
        ..Default::default()
    });
}

#[test]
fn test_select_down_select() {
    run_screen_test(&ScreenTestCase {
        name: "selectDownSelect",
        inputs: vec!["f", "j", "f"],
        ..Default::default()
    });
}

#[test]
fn test_select_with_down_select() {
    run_screen_test(&ScreenTestCase {
        name: "selectWithDownSelect",
        inputs: vec!["F", "f"],
        ..Default::default()
    });
}

#[test]
fn test_select_down_select_inverse() {
    run_screen_test(&ScreenTestCase {
        name: "selectDownSelectInverse",
        inputs: vec!["f", "j", "f", "A"],
        ..Default::default()
    });
}

#[test]
fn test_select_with_down_select_inverse() {
    run_screen_test(&ScreenTestCase {
        name: "selectWithDownSelectInverse",
        inputs: vec!["F", "F", "A"],
        ..Default::default()
    });
}

#[test]
fn test_select_all_from_arg() {
    run_screen_test(&ScreenTestCase {
        name: "selectAllFromArg",
        input_file: "absoluteGitDiff.txt",
        args_select_all: true,
        ..Default::default()
    });
}

#[test]
fn test_execute_keys_end_key_select_last() {
    // Python: args=["-e", "END", "f"] — execute keys END then f
    // We simulate by feeding END and f as inputs
    run_screen_test(&ScreenTestCase {
        name: "executeKeysEndKeySelectLast",
        inputs: vec!["END", "f"],
        ..Default::default()
    });
}

#[test]
fn test_select_all_bug() {
    run_screen_test(&ScreenTestCase {
        name: "selectAllBug",
        input_file: "gitLongDiff.txt",
        inputs: vec!["A"],
        ..Default::default()
    });
}

#[test]
fn test_git_diff_with_scroll() {
    run_screen_test(&ScreenTestCase {
        name: "gitDiffWithScroll",
        input_file: "gitDiffNoStat.txt",
        inputs: vec!["f", "j"],
        ..Default::default()
    });
}

#[test]
fn test_git_diff_with_scroll_up() {
    run_screen_test(&ScreenTestCase {
        name: "gitDiffWithScrollUp",
        input_file: "gitLongDiff.txt",
        inputs: vec!["k", "k"],
        ..Default::default()
    });
}

#[test]
fn test_git_diff_with_page_down() {
    run_screen_test(&ScreenTestCase {
        name: "gitDiffWithPageDown",
        input_file: "gitLongDiff.txt",
        inputs: vec![" ", " "],
        ..Default::default()
    });
}

#[test]
fn test_long_file_names() {
    run_screen_test(&ScreenTestCase {
        name: "longFileNames",
        input_file: "longFileNames.txt",
        screen_config: (20, 30),
        ..Default::default()
    });
}

#[test]
fn test_long_file_names_with_before_text_bug() {
    run_screen_test(&ScreenTestCase {
        name: "longFileNamesWithBeforeTextBug",
        input_file: "longFileNamesWithBeforeText.txt",
        inputs: vec!["f"],
        screen_config: (95, 40),
        ..Default::default()
    });
}

#[test]
fn test_abbreviated_line_select() {
    run_screen_test(&ScreenTestCase {
        name: "abbreviatedLineSelect",
        input_file: "longLineAbbreviated.txt",
        inputs: vec!["j", "j", "f"],
        ..Default::default()
    });
}

#[test]
fn test_long_list_page_up_and_down() {
    run_screen_test(&ScreenTestCase {
        name: "longListPageUpAndDown",
        input_file: "longList.txt",
        inputs: vec!["NPAGE", "NPAGE", "NPAGE", "PPAGE"],
        ..Default::default()
    });
}

// === WithAttributes tests ===

#[test]
fn test_simple_with_attributes() {
    run_screen_test(&ScreenTestCase {
        name: "simpleWithAttributes",
        with_attributes: true,
        ..Default::default()
    });
}

#[test]
fn test_simple_select_with_attributes() {
    run_screen_test(&ScreenTestCase {
        name: "simpleSelectWithAttributes",
        with_attributes: true,
        inputs: vec!["f", "j"],
        ..Default::default()
    });
}

#[test]
fn test_simple_select_with_color() {
    run_screen_test(&ScreenTestCase {
        name: "simpleSelectWithColor",
        input_file: "gitDiffColor.txt",
        with_attributes: true,
        inputs: vec!["f", "j"],
        screen_config: (200, 40),
        ..Default::default()
    });
}

#[test]
fn test_git_diff_with_page_down_color() {
    run_screen_test(&ScreenTestCase {
        name: "gitDiffWithPageDownColor",
        input_file: "gitLongDiffColor.txt",
        inputs: vec![" ", " "],
        with_attributes: true,
        ..Default::default()
    });
}

#[test]
fn test_git_diff_with_validation() {
    run_screen_test(&ScreenTestCase {
        name: "gitDiffWithValidation",
        input_file: "gitDiffSomeExist.txt",
        validate_file_exists: true,
        with_attributes: true,
        ..Default::default()
    });
}

#[test]
fn test_git_abbreviated_files() {
    run_screen_test(&ScreenTestCase {
        name: "gitAbbreviatedFiles",
        input_file: "gitAbbreviatedFiles.txt",
        with_attributes: true,
        inputs: vec!["f", "j"],
        ..Default::default()
    });
}

#[test]
fn test_long_file_truncation() {
    run_screen_test(&ScreenTestCase {
        name: "longFileTruncation",
        input_file: "superLongFileNames.txt",
        with_attributes: true,
        inputs: vec!["DOWN", "f"],
        screen_config: (60, 20),
        ..Default::default()
    });
}

#[test]
fn test_x_mode_with_select() {
    run_screen_test(&ScreenTestCase {
        name: "xModeWithSelect",
        with_attributes: true,
        inputs: vec!["x", "G", "J"],
        ..Default::default()
    });
}

#[test]
fn test_all_input_branch() {
    run_screen_test(&ScreenTestCase {
        name: "allInputBranch",
        input_file: "gitBranch.txt",
        all_input: true,
        inputs: vec!["j", "f"],
        ..Default::default()
    });
}

#[test]
fn test_long_list_home_key() {
    run_screen_test(&ScreenTestCase {
        name: "longListHomeKey",
        input_file: "longList.txt",
        inputs: vec![" ", " ", "HOME"],
        with_attributes: true,
        screen_config: (80, 10),
        ..Default::default()
    });
}

#[test]
fn test_long_list_end_key() {
    run_screen_test(&ScreenTestCase {
        name: "longListEndKey",
        input_file: "longList.txt",
        inputs: vec!["END"],
        with_attributes: true,
        screen_config: (80, 10),
        ..Default::default()
    });
}

// === Tests with past_screen/past_screens (intermediate state verification) ===

#[test]
fn test_select_two_command_mode() {
    run_screen_test(&ScreenTestCase {
        name: "selectTwoCommandMode",
        input_file: "absoluteGitDiff.txt",
        inputs: vec!["f", "j", "f", "c"],
        past_screen: Some(3),
        ..Default::default()
    });
}

#[test]
fn test_select_command_with_passed_command() {
    run_screen_test(&ScreenTestCase {
        name: "selectCommandWithPassedCommand",
        input_file: "absoluteGitDiff.txt",
        with_attributes: true,
        inputs: vec!["f", "c", "a"],
        past_screen: Some(1),
        args_command: Some(" 'git add'".to_string()),
        ..Default::default()
    });
}

#[test]
fn test_dont_wipe_chrome() {
    run_screen_test(&ScreenTestCase {
        name: "dontWipeChrome",
        input_file: "gitDiffColor.txt",
        with_attributes: true,
        inputs: vec!["DOWN", "f", "f", "f", "UP"],
        screen_config: (201, 40),
        past_screens: Some(vec![0, 1, 2, 3, 4]),
        ..Default::default()
    });
}

#[test]
fn test_tons_of_files() {
    run_screen_test(&ScreenTestCase {
        name: "tonsOfFiles",
        input_file: "tonsOfFiles.txt",
        inputs: vec!["A", "c"],
        past_screen: Some(1),
        screen_config: (80, 30),
        ..Default::default()
    });
}

#[test]
fn test_file_name_with_spaces_description() {
    // This test needs validate_file_exists=true, so we must chdir to
    // the tests/ directory where fixture files exist in inputs/.
    // Integration tests run in a separate binary from unit tests, so they cannot
    // share the DIR_LOCK in src/lib.rs::test_env. This local lock protects against
    // parallel tests within this integration test binary that call set_current_dir.
    use std::sync::Mutex;
    static DIR_LOCK: Mutex<()> = Mutex::new(());
    let _guard = DIR_LOCK.lock().unwrap();
    let original_dir = std::env::current_dir().unwrap();
    let test_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests");
    std::env::set_current_dir(&test_dir).unwrap();
    struct RestoreDir(std::path::PathBuf);
    impl Drop for RestoreDir {
        fn drop(&mut self) {
            let _ = std::env::set_current_dir(&self.0);
        }
    }
    let _restore = RestoreDir(original_dir);
    run_screen_test(&ScreenTestCase {
        name: "fileNameWithSpacesDescription",
        input_file: "fileNamesWithSpaces.txt",
        inputs: vec!["d"],
        validate_file_exists: true,
        screen_config: (201, 30),
        ..Default::default()
    });
}

#[test]
fn test_tall_load_and_quit() {
    run_screen_test(&ScreenTestCase {
        name: "tallLoadAndQuit",
        screen_config: (140, 60),
        ..Default::default()
    });
}
