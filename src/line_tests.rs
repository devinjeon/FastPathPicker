use super::*;

fn make_line_match(path: &str) -> LineMatch {
    LineMatch::new(
        FormattedText::new(path),
        path.to_string(),
        0,
        path.to_string(),
        0,
        path.len(),
    )
}

fn make_simple_line(text: &str) -> SimpleLine {
    SimpleLine::new(FormattedText::new(text), text.to_string())
}

#[test]
fn test_set_select() {
    let mut m = make_line_match("src/main.rs");
    assert!(!m.selected);
    m.set_select(true);
    assert!(m.selected);
    m.set_select(false);
    assert!(!m.selected);
}

#[test]
fn test_as_match_mut_on_simple() {
    let mut line = Line::Simple(make_simple_line("not a file"));
    assert!(line.as_match_mut().is_none());
}

#[test]
fn test_as_match_mut_on_match() {
    let mut line = Line::Match(make_line_match("src/main.rs"));
    assert!(line.as_match_mut().is_some());
}

#[test]
fn test_line_display() {
    let line = Line::Match(make_line_match("src/main.rs"));
    assert_eq!(format!("{line}"), "src/main.rs");

    let line2 = Line::Simple(make_simple_line("just text"));
    assert_eq!(format!("{line2}"), "just text");
}

#[test]
fn test_formatted_text_on_simple() {
    let line = Line::Simple(make_simple_line("hello"));
    assert_eq!(line.formatted_text().plain_text(), "hello");
}

#[test]
fn test_original_line_on_simple() {
    let line = Line::Simple(make_simple_line("original text"));
    assert_eq!(line.original_line(), "original text");
}

#[test]
fn test_format_size_python() {
    assert_eq!(format_size_python(0), "0B");
    assert_eq!(format_size_python(512), "512B");
    assert_eq!(format_size_python(1024), "1K");
    assert_eq!(format_size_python(1048576), "1M");
    assert_eq!(format_size_python(1073741824), "1G");
}

#[test]
fn test_format_system_time_local() {
    // Epoch time 0 should give 1970-01-01 in UTC (offset may vary)
    let time = SystemTime::UNIX_EPOCH;
    let result = format_system_time_local(time);
    // Just verify format: mm/dd/yyyy hh:mm:ss
    assert!(
        result.contains('/'),
        "Should contain date separator: {result}"
    );
    assert!(
        result.contains(':'),
        "Should contain time separator: {result}"
    );
}

#[test]
fn test_is_leap_year() {
    assert!(is_leap_year(2000)); // divisible by 400
    assert!(!is_leap_year(1900)); // divisible by 100 but not 400
    assert!(is_leap_year(2024)); // divisible by 4
    assert!(!is_leap_year(2023)); // not divisible by 4
}

#[test]
fn test_get_file_description_nonexistent() {
    let m = make_line_match("/nonexistent/path/to/file.txt");
    let desc = m.get_file_description();
    assert!(desc.iter().any(|s| s.contains("Unable to read metadata")));
}
