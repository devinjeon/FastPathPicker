use super::*;

#[test]
fn test_empty_input() {
    let lines: Vec<String> = vec![];
    let result = get_line_objs_from_lines(&lines, false, false);
    assert!(result.is_empty());
}

#[test]
fn test_simple_file_match() {
    let lines = vec!["src/main.rs:42: something".to_string()];
    let result = get_line_objs_from_lines(&lines, false, false);
    assert_eq!(result.len(), 1);
    assert!(result[0].as_match().is_some());
}

#[test]
fn test_no_match_line() {
    let lines = vec!["just some text with no file".to_string()];
    let result = get_line_objs_from_lines(&lines, false, false);
    assert_eq!(result.len(), 1);
    assert!(result[0].as_match().is_none());
}

#[test]
fn test_tab_expansion() {
    let lines = vec!["\tsrc/main.rs".to_string()];
    let result = get_line_objs_from_lines(&lines, false, false);
    assert_eq!(result.len(), 1);
    // Tab should be expanded to 4 spaces
    assert!(result[0].original_line().starts_with("    "));
}

#[test]
fn test_all_input_mode() {
    let lines = vec!["  some branch  ".to_string(), "another branch".to_string()];
    let result = get_line_objs_from_lines(&lines, false, true);
    // All non-empty trimmed lines should match
    for line in &result {
        assert!(line.as_match().is_some());
    }
}

// --- get_matches tests ---

#[test]
fn test_get_matches_mixed() {
    let lines = vec![
        "src/main.rs:10: fn main()".to_string(),
        "just some text".to_string(),
        "src/lib.rs:20: pub mod foo".to_string(),
    ];
    let result = get_line_objs_from_lines(&lines, false, false);
    let matches = get_matches(&result);
    // Lines 0 and 2 are matches, line 1 is simple
    assert_eq!(matches, vec![0, 2]);
}

#[test]
fn test_get_matches_all_match() {
    let lines = vec![
        "src/main.rs".to_string(),
        "src/lib.rs".to_string(),
        "Cargo.toml".to_string(),
    ];
    let result = get_line_objs_from_lines(&lines, false, false);
    let matches = get_matches(&result);
    assert_eq!(matches, vec![0, 1, 2]);
}

#[test]
fn test_get_matches_all_simple() {
    let lines = vec!["no files here".to_string(), "or here either".to_string()];
    let result = get_line_objs_from_lines(&lines, false, false);
    let matches = get_matches(&result);
    assert!(matches.is_empty());
}

#[test]
fn test_get_matches_empty() {
    let lines: Vec<String> = vec![];
    let result = get_line_objs_from_lines(&lines, false, false);
    let matches = get_matches(&result);
    assert!(matches.is_empty());
}
