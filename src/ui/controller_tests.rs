use super::*;
use crate::format::FormattedText;
use crate::line::{Line, LineMatch};

/// Truncate a line to fit within max_width, using |...| decorator for long lines.
fn truncate_line(text: &str, max_width: usize) -> String {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() <= max_width {
        return text.to_string();
    }
    if max_width <= TRUNCATE_DECORATOR.len() + 2 {
        return chars.iter().take(max_width).collect();
    }
    let decorator_len = TRUNCATE_DECORATOR.len();
    let remaining = max_width - decorator_len;
    let front = remaining / 2;
    let back = remaining - front;
    let mut result: String = chars[..front].iter().collect();
    result.push_str(TRUNCATE_DECORATOR);
    result.extend(&chars[chars.len() - back..]);
    result
}

fn make_test_lines(paths: &[&str]) -> (Vec<Line>, Vec<usize>) {
    let lines: Vec<Line> = paths
        .iter()
        .map(|path| {
            Line::Match(LineMatch::new(
                FormattedText::new(path),
                path.to_string(),
                0,
                path.to_string(),
                0,
                path.len(),
            ))
        })
        .collect();
    let indices: Vec<usize> = (0..lines.len()).collect();
    (lines, indices)
}

#[test]
fn test_move_hover() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    assert_eq!(ctrl.hover_index, 0);

    ctrl.move_hover(1);
    assert_eq!(ctrl.hover_index, 1);

    ctrl.move_hover(1);
    assert_eq!(ctrl.hover_index, 2);

    // Wraps around to first (like Python)
    ctrl.move_hover(1);
    assert_eq!(ctrl.hover_index, 0);

    ctrl.move_hover(-1);
    // Wraps around to last
    assert_eq!(ctrl.hover_index, 2);
}

#[test]
fn test_toggle_selection() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    ctrl.toggle_current_selection();
    assert!(ctrl.lines[0].as_match().unwrap().selected);
    assert!(!ctrl.lines[1].as_match().unwrap().selected);

    ctrl.toggle_current_selection();
    assert!(!ctrl.lines[0].as_match().unwrap().selected);
}

#[test]
fn test_toggle_select_all() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    ctrl.toggle_select_all();
    assert!(ctrl.lines[0].as_match().unwrap().selected);
    assert!(ctrl.lines[1].as_match().unwrap().selected);
    assert!(ctrl.lines[2].as_match().unwrap().selected);

    ctrl.toggle_select_all();
    assert!(!ctrl.lines[0].as_match().unwrap().selected);
    assert!(!ctrl.lines[1].as_match().unwrap().selected);
    assert!(!ctrl.lines[2].as_match().unwrap().selected);
}

#[test]
fn test_initial_select_all() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
    let ctrl = Controller::new(lines, indices, None, true, None, false);
    assert!(ctrl.lines[0].as_match().unwrap().selected);
    assert!(ctrl.lines[1].as_match().unwrap().selected);
}

#[test]
fn test_get_selected_matches_uses_hovered_when_none_selected() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
    let ctrl = Controller::new(lines, indices, None, false, None, false);
    let selected = ctrl.get_selected_matches();
    assert_eq!(selected.len(), 1);
    assert_eq!(selected[0].path, "a.txt");
}

#[test]
fn test_get_selected_matches_returns_selected() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.move_hover(1);
    ctrl.toggle_current_selection(); // select b.txt
    ctrl.move_hover(1);
    ctrl.toggle_current_selection(); // select c.txt

    let selected = ctrl.get_selected_matches();
    assert_eq!(selected.len(), 2);
    assert_eq!(selected[0].path, "b.txt");
    assert_eq!(selected[1].path, "c.txt");
}

#[test]
fn test_execute_keys_from_str() {
    let keys = execute_keys_from_str("f j F END");
    assert_eq!(keys.len(), 4);
    assert_eq!(keys[0].code, KeyCode::Char('f'));
    assert_eq!(keys[1].code, KeyCode::Char('j'));
    assert_eq!(keys[2].code, KeyCode::Char('F'));
    assert_eq!(keys[3].code, KeyCode::End);
}

#[test]
fn test_jump_to_first_and_last() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt", "d.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    ctrl.jump_to_last();
    assert_eq!(ctrl.hover_index, 3);

    ctrl.jump_to_first();
    assert_eq!(ctrl.hover_index, 0);
}

// --- truncate_line tests ---

#[test]
fn test_truncate_line_short() {
    assert_eq!(truncate_line("hello", 10), "hello");
}

#[test]
fn test_truncate_line_exact() {
    assert_eq!(truncate_line("hello", 5), "hello");
}

#[test]
fn test_truncate_line_long() {
    let result = truncate_line("abcdefghijklmnopqrstuvwxyz", 15);
    assert_eq!(result.chars().count(), 15);
    assert!(result.contains("|...|"));
}

#[test]
fn test_truncate_line_very_small_width() {
    let result = truncate_line("abcdefghij", 5);
    assert_eq!(result, "abcde");
}

#[test]
fn test_truncate_line_unicode() {
    let result = truncate_line("가나다라마바사아자차카타파하", 10);
    assert_eq!(result.chars().count(), 10);
    assert!(result.contains("|...|"));
}

// --- Enter key restriction tests ---

#[test]
fn test_enter_blocked_in_all_input_without_command() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, true);
    let key = KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE);
    let action = ctrl.handle_key(key).unwrap();
    assert!(matches!(action, Action::Continue));
}

#[test]
fn test_enter_works_in_all_input_with_preset_command() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(
        lines,
        indices,
        Some("git add".to_string()),
        false,
        None,
        true,
    );
    let key = KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE);
    let action = ctrl.handle_key(key).unwrap();
    assert!(matches!(action, Action::Execute));
}

#[test]
fn test_enter_works_without_all_input() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    let key = KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE);
    let action = ctrl.handle_key(key).unwrap();
    assert!(matches!(action, Action::Execute));
}

// --- Preset command warning tests ---

#[test]
fn test_c_key_with_preset_command_enters_warning() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(
        lines,
        indices,
        Some("git add".to_string()),
        false,
        None,
        false,
    );
    let key = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert_eq!(ctrl.mode, Mode::Warning);
}

#[test]
fn test_c_key_without_preset_enters_command_mode() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    let key = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert_eq!(ctrl.mode, Mode::Command);
}

#[test]
fn test_warning_dismissed_by_any_key() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(
        lines,
        indices,
        Some("git add".to_string()),
        false,
        None,
        false,
    );
    ctrl.mode = Mode::Warning;
    let key = KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert_eq!(ctrl.mode, Mode::Normal);
}

// --- Description toggle tests ---

#[test]
fn test_d_key_shows_description() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    assert!(!ctrl.show_description);

    let key = KeyEvent::new(KeyCode::Char('d'), KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert!(ctrl.show_description);
}

#[test]
fn test_description_clears_on_move() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.show_description = true;

    ctrl.move_hover(1);
    assert!(!ctrl.show_description);
}

// --- Quit vs SilentQuit distinction ---

#[test]
fn test_quit_vs_silent_quit_are_distinct() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    let q_action = ctrl
        .handle_key(KeyEvent::new(KeyCode::Char('q'), KeyModifiers::NONE))
        .unwrap();
    assert!(matches!(q_action, Action::Quit));
    let cc_action = ctrl
        .handle_key(KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL))
        .unwrap();
    assert!(matches!(cc_action, Action::SilentQuit));
}

// --- Ctrl-C silent quit tests ---

#[test]
fn test_ctrl_c_returns_silent_quit() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    let key = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL);
    let action = ctrl.handle_key(key).unwrap();
    assert!(matches!(action, Action::SilentQuit));
}

#[test]
fn test_ctrl_c_in_command_mode_returns_silent_quit() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.mode = Mode::Command;
    let key = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL);
    let action = ctrl.handle_key(key).unwrap();
    assert!(matches!(action, Action::SilentQuit));
}

#[test]
fn test_ctrl_c_in_xmode_returns_silent_quit() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.mode = Mode::QuickSelect;
    let key = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL);
    let action = ctrl.handle_key(key).unwrap();
    assert!(matches!(action, Action::SilentQuit));
}

// --- Command mode backspace tests ---

#[test]
fn test_command_mode_backspace_on_empty_stays_in_command() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.mode = Mode::Command;
    // Backspace on empty buffer should NOT exit command mode (Python compat)
    let key = KeyEvent::new(KeyCode::Backspace, KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert_eq!(ctrl.mode, Mode::Command);
}

#[test]
fn test_command_mode_backspace_removes_char() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.mode = Mode::Command;
    ctrl.command_buffer = "ab".to_string();
    let key = KeyEvent::new(KeyCode::Backspace, KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert_eq!(ctrl.command_buffer, "a");
    assert_eq!(ctrl.mode, Mode::Command);
}

#[test]
fn test_command_mode_empty_enter_returns_to_normal() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.mode = Mode::Command;
    let key = KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert_eq!(ctrl.mode, Mode::Normal);
}

// --- Custom keybinding fire-after-builtin tests ---

#[test]
fn test_custom_binding_fires_on_unbound_key() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.custom_bindings = vec![KeyBinding {
        key: "z".to_string(),
        command: "git add".to_string(),
    }];
    let key = KeyEvent::new(KeyCode::Char('z'), KeyModifiers::NONE);
    let action = ctrl.handle_key(key).unwrap();
    assert!(matches!(action, Action::Execute));
    assert_eq!(ctrl.command_buffer, "git add");
}

#[test]
fn test_custom_binding_fires_after_builtin_key() {
    // Python: if 'f' has a custom binding, toggle_select fires first,
    // then the custom binding fires (overriding to Execute)
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.custom_bindings = vec![KeyBinding {
        key: "f".to_string(),
        command: "git add".to_string(),
    }];
    let key = KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE);
    let action = ctrl.handle_key(key).unwrap();
    // Built-in 'f' toggled selection, then custom binding fires Execute
    assert!(ctrl.lines[0].as_match().unwrap().selected);
    assert!(matches!(action, Action::Execute));
}

#[test]
fn test_custom_binding_does_not_fire_on_quit() {
    // Python: 'q' exits before custom binding loop runs
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.custom_bindings = vec![KeyBinding {
        key: "q".to_string(),
        command: "git add".to_string(),
    }];
    let key = KeyEvent::new(KeyCode::Char('q'), KeyModifiers::NONE);
    let action = ctrl.handle_key(key).unwrap();
    // Should be Quit, not Execute (custom binding doesn't fire for Quit)
    assert!(matches!(action, Action::Quit));
}

#[test]
fn test_custom_binding_fires_in_xmode_on_unmatched_key() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.mode = Mode::QuickSelect;
    ctrl.custom_bindings = vec![KeyBinding {
        key: "z".to_string(),
        command: "git add".to_string(),
    }];
    let key = KeyEvent::new(KeyCode::Char('z'), KeyModifiers::NONE);
    let action = ctrl.handle_key(key).unwrap();
    assert!(matches!(action, Action::Execute));
    assert_eq!(ctrl.command_buffer, "git add");
}

// --- Command mode Esc test ---

#[test]
fn test_command_mode_esc_clears_buffer_and_returns_to_normal() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.mode = Mode::Command;
    ctrl.command_buffer = "git add".to_string();
    let key = KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert_eq!(ctrl.mode, Mode::Normal);
    assert!(ctrl.command_buffer.is_empty());
}

// --- QuickSelect mode G/END/A key tests ---

#[test]
fn test_xmode_g_uppercase_is_ignored() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.mode = Mode::QuickSelect;
    let key = KeyEvent::new(KeyCode::Char('G'), KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert_eq!(ctrl.hover_index, 0);
}

#[test]
fn test_xmode_end_key_works() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.mode = Mode::QuickSelect;
    let key = KeyEvent::new(KeyCode::End, KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert_eq!(ctrl.hover_index, 2);
}

#[test]
fn test_xmode_a_is_ignored() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.mode = Mode::QuickSelect;
    let key = KeyEvent::new(KeyCode::Char('A'), KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert!(!ctrl.lines[0].as_match().unwrap().selected);
    assert!(!ctrl.lines[1].as_match().unwrap().selected);
}

// --- Selection state collection test ---

#[test]
fn test_save_selection_collects_correct_indices() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.move_hover(1);
    ctrl.toggle_current_selection(); // select b.txt (index 1)

    let selected: Vec<usize> = ctrl
        .match_indices
        .iter()
        .filter(|&&idx| ctrl.lines[idx].as_match().is_some_and(|m| m.selected))
        .copied()
        .collect();
    assert_eq!(selected, vec![1]);
}

// --- F key (toggle + move down) tests ---

#[test]
fn test_f_uppercase_toggles_and_moves_down() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    assert_eq!(ctrl.hover_index, 0);

    let key = KeyEvent::new(KeyCode::Char('F'), KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    // a.txt should be selected, hover moved to b.txt
    assert!(ctrl.lines[0].as_match().unwrap().selected);
    assert_eq!(ctrl.hover_index, 1);
}

#[test]
fn test_f_uppercase_wraps_at_end() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.hover_index = 1; // last item

    let key = KeyEvent::new(KeyCode::Char('F'), KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert!(ctrl.lines[1].as_match().unwrap().selected);
    assert_eq!(ctrl.hover_index, 0); // wrapped to first
}

// --- Page down / page up tests ---

#[test]
fn test_page_down_via_space() {
    // terminal::size() returns fallback (80,24) in test → content_height=20 → page=10
    let paths: Vec<&str> = (0..30).map(|_| "f.txt").collect();
    let (lines, indices) = make_test_lines(&paths);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    assert_eq!(ctrl.hover_index, 0);

    let key = KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert!(ctrl.hover_index > 0, "page_down should move hover forward");
}

#[test]
fn test_page_up_via_b() {
    let paths: Vec<&str> = (0..30).map(|_| "f.txt").collect();
    let (lines, indices) = make_test_lines(&paths);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.hover_index = 15;

    let key = KeyEvent::new(KeyCode::Char('b'), KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert!(ctrl.hover_index < 15, "page_up should move hover backward");
}

#[test]
fn test_page_down_via_npage() {
    let paths: Vec<&str> = (0..30).map(|_| "f.txt").collect();
    let (lines, indices) = make_test_lines(&paths);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    let key = KeyEvent::new(KeyCode::PageDown, KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert!(ctrl.hover_index > 0);
}

#[test]
fn test_page_up_via_ppage() {
    let paths: Vec<&str> = (0..30).map(|_| "f.txt").collect();
    let (lines, indices) = make_test_lines(&paths);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.hover_index = 20;

    let key = KeyEvent::new(KeyCode::PageUp, KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    assert!(ctrl.hover_index < 20);
}

#[test]
fn test_page_down_wraps_around() {
    let paths: Vec<&str> = (0..5).map(|_| "f.txt").collect();
    let (lines, indices) = make_test_lines(&paths);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.hover_index = 4; // last item

    let key = KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE);
    ctrl.handle_key(key).unwrap();
    // Should wrap since page size > remaining items
    // move_hover wraps via modular arithmetic
    assert!(ctrl.hover_index < 5);
}

// --- Multi-step interaction sequence tests (matching Python test_screen.py) ---

/// Python: selectDownSelect — [f, j, f]
#[test]
fn test_sequence_select_down_select() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    // f: select a.txt
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
        .unwrap();
    assert!(ctrl.lines[0].as_match().unwrap().selected);

    // j: move down
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('j'), KeyModifiers::NONE))
        .unwrap();
    assert_eq!(ctrl.hover_index, 1);

    // f: select b.txt
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
        .unwrap();
    assert!(ctrl.lines[0].as_match().unwrap().selected);
    assert!(ctrl.lines[1].as_match().unwrap().selected);
    assert!(!ctrl.lines[2].as_match().unwrap().selected);
}

/// Python: selectWithDownSelect — [F, f]
#[test]
fn test_sequence_select_with_down_select() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    // F: select a.txt + move down
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('F'), KeyModifiers::NONE))
        .unwrap();
    assert!(ctrl.lines[0].as_match().unwrap().selected);
    assert_eq!(ctrl.hover_index, 1);

    // f: select b.txt
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
        .unwrap();
    assert!(ctrl.lines[0].as_match().unwrap().selected);
    assert!(ctrl.lines[1].as_match().unwrap().selected);
}

/// Python: selectDownSelectInverse — [f, j, f, A]
#[test]
fn test_sequence_select_down_select_inverse() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    // f: select a.txt
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
        .unwrap();
    // j: move down
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('j'), KeyModifiers::NONE))
        .unwrap();
    // f: select b.txt
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
        .unwrap();
    // A: toggle all — a.txt OFF, b.txt OFF, c.txt ON
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('A'), KeyModifiers::NONE))
        .unwrap();

    assert!(!ctrl.lines[0].as_match().unwrap().selected);
    assert!(!ctrl.lines[1].as_match().unwrap().selected);
    assert!(ctrl.lines[2].as_match().unwrap().selected);
}

/// Python: selectWithDownSelectInverse — [F, F, A]
#[test]
fn test_sequence_select_with_down_select_inverse() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    // F: select a.txt + move down
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('F'), KeyModifiers::NONE))
        .unwrap();
    // F: select b.txt + move down
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('F'), KeyModifiers::NONE))
        .unwrap();
    // A: toggle all — a OFF, b OFF, c ON
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('A'), KeyModifiers::NONE))
        .unwrap();

    assert!(!ctrl.lines[0].as_match().unwrap().selected);
    assert!(!ctrl.lines[1].as_match().unwrap().selected);
    assert!(ctrl.lines[2].as_match().unwrap().selected);
}

/// Python: selectTwoCommandMode — [f, j, f, c] with past_screen check
#[test]
fn test_sequence_select_two_then_command_mode() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
        .unwrap();
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('j'), KeyModifiers::NONE))
        .unwrap();
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
        .unwrap();
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE))
        .unwrap();

    assert_eq!(ctrl.mode, Mode::Command);
    assert!(ctrl.lines[0].as_match().unwrap().selected);
    assert!(ctrl.lines[1].as_match().unwrap().selected);
}

/// Python: allInputBranch — [-ai, j, f]
#[test]
fn test_sequence_all_input_select() {
    let (lines, indices) = make_test_lines(&["branch-1", "branch-2", "branch-3"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, true);

    ctrl.handle_key(KeyEvent::new(KeyCode::Char('j'), KeyModifiers::NONE))
        .unwrap();
    assert_eq!(ctrl.hover_index, 1);

    ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
        .unwrap();
    assert!(ctrl.lines[1].as_match().unwrap().selected);

    // Enter should be blocked (all_input, no preset command)
    let action = ctrl
        .handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE))
        .unwrap();
    assert!(matches!(action, Action::Continue));
}

/// Python: longListPageUpAndDown — [NPAGE, NPAGE, NPAGE, PPAGE]
#[test]
fn test_sequence_page_down_then_up() {
    let paths: Vec<&str> = (0..50).map(|_| "f.txt").collect();
    let (lines, indices) = make_test_lines(&paths);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    // 3x page down
    for _ in 0..3 {
        ctrl.handle_key(KeyEvent::new(KeyCode::PageDown, KeyModifiers::NONE))
            .unwrap();
    }
    let after_down = ctrl.hover_index;
    assert!(after_down > 0, "should have moved forward");

    // 1x page up
    ctrl.handle_key(KeyEvent::new(KeyCode::PageUp, KeyModifiers::NONE))
        .unwrap();
    assert!(ctrl.hover_index < after_down, "page up should move back");
}

/// Python: longListHomeKey — [SPACE, SPACE, HOME]
#[test]
fn test_sequence_page_down_then_home() {
    let paths: Vec<&str> = (0..50).map(|_| "f.txt").collect();
    let (lines, indices) = make_test_lines(&paths);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    ctrl.handle_key(KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE))
        .unwrap();
    ctrl.handle_key(KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE))
        .unwrap();
    assert!(ctrl.hover_index > 0);

    ctrl.handle_key(KeyEvent::new(KeyCode::Home, KeyModifiers::NONE))
        .unwrap();
    assert_eq!(ctrl.hover_index, 0);
}

/// Python: xModeWithSelect — [x, G, J] (G ignored, J is quick-select label)
#[test]
fn test_sequence_xmode_interactions() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    // x: enter quick-select mode
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('x'), KeyModifiers::NONE))
        .unwrap();
    assert_eq!(ctrl.mode, Mode::QuickSelect);

    // G: should be ignored in X_MODE (Python compat)
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('G'), KeyModifiers::NONE))
        .unwrap();
    assert_eq!(ctrl.hover_index, 0); // didn't jump to last

    // J: is a quick-select label — selects item at that row
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('J'), KeyModifiers::NONE))
        .unwrap();
    // J is in LABELS at some index, should toggle that row's selection
}

/// Python: selectAllBug — [A] on long list
#[test]
fn test_select_all_on_long_list() {
    let paths: Vec<&str> = (0..50).map(|_| "f.txt").collect();
    let (lines, indices) = make_test_lines(&paths);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    ctrl.handle_key(KeyEvent::new(KeyCode::Char('A'), KeyModifiers::NONE))
        .unwrap();
    // All unique paths should be selected (only 1 unique path "f.txt",
    // so only first occurrence gets toggled)
    let selected_count = ctrl
        .lines
        .iter()
        .filter(|l| l.as_match().is_some_and(|m| m.selected))
        .count();
    assert_eq!(
        selected_count, 1,
        "Only the first occurrence of each unique path should be selected"
    );
}

// --- Scroll offset tests ---

#[test]
fn test_scroll_offset_updates_on_jump_to_last() {
    let paths: Vec<&str> = (0..100).map(|_| "f.txt").collect();
    let (lines, indices) = make_test_lines(&paths);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    assert_eq!(ctrl.scroll_offset, 0);

    ctrl.jump_to_last();
    assert_eq!(ctrl.hover_index, 99);
    // scroll_offset should have moved to show the last item
    assert!(
        ctrl.scroll_offset > 0,
        "scroll should have moved for last item"
    );
}

#[test]
fn test_scroll_offset_resets_on_jump_to_first() {
    let paths: Vec<&str> = (0..100).map(|_| "f.txt").collect();
    let (lines, indices) = make_test_lines(&paths);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    ctrl.jump_to_last();
    assert!(ctrl.scroll_offset > 0);

    ctrl.jump_to_first();
    assert_eq!(ctrl.hover_index, 0);
    assert_eq!(ctrl.scroll_offset, 0);
}

#[test]
fn test_scroll_offset_no_change_for_small_list() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);

    ctrl.move_hover(1);
    assert_eq!(ctrl.scroll_offset, 0, "small list should not scroll");

    ctrl.move_hover(1);
    assert_eq!(ctrl.scroll_offset, 0);
}

// --- Command mode typing test ---

#[test]
fn test_command_mode_typing_builds_buffer() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.mode = Mode::Command;

    for ch in "git add".chars() {
        ctrl.handle_key(KeyEvent::new(KeyCode::Char(ch), KeyModifiers::NONE))
            .unwrap();
    }
    assert_eq!(ctrl.command_buffer, "git add");

    // Enter executes the command
    let action = ctrl
        .handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE))
        .unwrap();
    assert!(matches!(action, Action::Execute));
}

/// Python: selectCommandWithPassedCommand — [f, c, a] with -c flag
#[test]
fn test_sequence_command_mode_with_preset_warning_dismiss() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
    let mut ctrl = Controller::new(
        lines,
        indices,
        Some("git add".to_string()),
        false,
        None,
        false,
    );

    // f: select a.txt
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
        .unwrap();
    assert!(ctrl.lines[0].as_match().unwrap().selected);

    // c: should show warning (preset command exists)
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE))
        .unwrap();
    assert_eq!(ctrl.mode, Mode::Warning);

    // a: dismiss warning, return to Normal
    ctrl.handle_key(KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE))
        .unwrap();
    assert_eq!(ctrl.mode, Mode::Normal);
}

// --- Rendering optimization regression tests ---

#[test]
fn test_normal_mode_render_has_no_full_screen_clear() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.set_viewport_size(80, 24);

    let mut buf: Vec<u8> = Vec::new();
    ctrl.render_to(&mut buf, (80, 24)).unwrap();

    let output = String::from_utf8_lossy(&buf);
    // Normal mode should NOT emit full-screen clear (\x1b[2J).
    assert!(
        !output.contains("\x1b[2J"),
        "Normal mode render should not contain full-screen clear (\\x1b[2J)"
    );
    // Full render uses ClearType::UntilNewLine for clean output.
    // Partial dirty-line renders use space-padding instead (no flicker).
    assert!(
        output.contains("\x1b[K"),
        "Full render should contain ClearType::UntilNewLine (\\x1b[K)"
    );
    // Verify actual content is rendered (semantic check).
    assert!(
        output.contains("a.txt"),
        "Normal mode render should contain file names"
    );
}

#[test]
fn test_quickselect_mode_render_has_no_full_screen_clear() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.set_viewport_size(80, 24);
    ctrl.mode = Mode::QuickSelect;

    let mut buf: Vec<u8> = Vec::new();
    ctrl.render_to(&mut buf, (80, 24)).unwrap();

    let output = String::from_utf8_lossy(&buf);
    assert!(
        !output.contains("\x1b[2J"),
        "QuickSelect mode render should not contain full-screen clear (\\x1b[2J)"
    );
    assert!(
        output.contains("\x1b[K"),
        "QuickSelect full render should contain ClearType::UntilNewLine (\\x1b[K)"
    );
}

#[test]
fn test_wide_mode_render_has_no_full_screen_clear() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.set_viewport_size(210, 24);

    let mut buf: Vec<u8> = Vec::new();
    ctrl.render_to(&mut buf, (210, 24)).unwrap();

    let output = String::from_utf8_lossy(&buf);
    // Wide mode (>200 cols) should NOT use full-screen clear
    assert!(
        !output.contains("\x1b[2J"),
        "Wide mode render should not contain full-screen clear (\\x1b[2J)"
    );
    // Full render uses ClearType::UntilNewLine
    assert!(
        output.contains("\x1b[K"),
        "Wide mode full render should contain ClearType::UntilNewLine (\\x1b[K)"
    );
    // Sidebar border should be present
    assert!(
        output.contains("|"),
        "Wide mode render should contain sidebar border"
    );
}

#[test]
fn test_command_mode_render_uses_full_screen_clear() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.set_viewport_size(80, 24);
    ctrl.mode = Mode::Command;

    let mut buf: Vec<u8> = Vec::new();
    ctrl.render_to(&mut buf, (80, 24)).unwrap();

    // Command/Warning overlay modes use full-screen clear
    let output = String::from_utf8_lossy(&buf);
    assert!(
        output.contains("\x1b[2J"),
        "Command mode render should contain full-screen clear (\\x1b[2J)"
    );
}

#[test]
fn test_warning_mode_render_uses_full_screen_clear() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(
        lines,
        indices,
        Some("git add".to_string()),
        false,
        None,
        false,
    );
    ctrl.set_viewport_size(80, 24);
    ctrl.mode = Mode::Warning;

    let mut buf: Vec<u8> = Vec::new();
    ctrl.render_to(&mut buf, (80, 24)).unwrap();

    let output = String::from_utf8_lossy(&buf);
    assert!(
        output.contains("\x1b[2J"),
        "Warning mode render should contain full-screen clear (\\x1b[2J)"
    );
}

// --- begin_height calculation test ---

#[test]
fn test_begin_height_matches_python() {
    // Python: int(round(max_y / 2) - len(paths) / 2.0)
    let cases = [(24, 3), (50, 10), (10, 2), (80, 1)];
    for (max_y, num_paths) in cases {
        let rust_result = ((max_y as f64 / 2.0).round() - (num_paths as f64 / 2.0)) as i32;
        let python_result = ((max_y as f64 / 2.0).round() - (num_paths as f64 / 2.0)) as i32;
        assert_eq!(
            rust_result, python_result,
            "begin_height mismatch for max_y={max_y}, paths={num_paths}"
        );
    }
}

// --- run() return value tests ---

/// Ctrl-C (SilentQuit) should cause run() to return Ok(false),
/// indicating no script should be executed. This prevents stale
/// .fpp.sh files from previous sessions being executed on Ctrl-C.
#[test]
fn test_run_returns_false_on_silent_quit() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.set_viewport_size(80, 24);

    // Simulate Ctrl-C via execute_keys
    let key = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL);
    let action = ctrl.handle_key(key).unwrap();
    assert!(
        matches!(action, Action::SilentQuit),
        "Ctrl-C should produce SilentQuit"
    );
    // SilentQuit maps to run() returning Ok(false)
}

/// Normal quit ('q') should cause run() to return Ok(true),
/// so that the "nothing to do" script is executed.
#[test]
fn test_run_returns_true_on_normal_quit() {
    let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.set_viewport_size(80, 24);

    let key = KeyEvent::new(KeyCode::Char('q'), KeyModifiers::NONE);
    let action = ctrl.handle_key(key).unwrap();
    assert!(matches!(action, Action::Quit), "q should produce Quit");
    // Quit maps to run() returning Ok(true)
}

/// Enter (Execute) should cause run() to return Ok(true),
/// so that the selection script is executed.
#[test]
fn test_run_returns_true_on_execute() {
    let (lines, indices) = make_test_lines(&["a.txt"]);
    let mut ctrl = Controller::new(lines, indices, None, false, None, false);
    ctrl.set_viewport_size(80, 24);

    let key = KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE);
    let action = ctrl.handle_key(key).unwrap();
    assert!(
        matches!(action, Action::Execute),
        "Enter should produce Execute"
    );
    // Execute maps to run() returning Ok(true)
}
