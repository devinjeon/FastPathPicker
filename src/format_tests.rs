use super::*;

#[test]
fn test_plain_text() {
    let ft = FormattedText::new("hello world");
    assert_eq!(ft.plain_text(), "hello world");
}

#[test]
fn test_ansi_stripping() {
    let ft = FormattedText::new("\x1b[31mred text\x1b[0m normal");
    assert_eq!(ft.plain_text(), "red text normal");
}

#[test]
fn test_raw_preserved() {
    let raw = "\x1b[31mred text\x1b[0m normal";
    let ft = FormattedText::new(raw);
    assert_eq!(ft.raw_text(), raw);
}

#[test]
fn test_has_ansi() {
    assert!(FormattedText::new("\x1b[31mred\x1b[0m").has_ansi());
    assert!(!FormattedText::new("plain text").has_ansi());
}

#[test]
fn test_empty() {
    let ft = FormattedText::new("");
    assert_eq!(ft.plain_text(), "");
    assert_eq!(ft.raw_text(), "");
}

#[test]
fn test_256_color_stripping() {
    let ft = FormattedText::new("\x1b[38;5;196mcolored\x1b[0m plain");
    assert_eq!(ft.plain_text(), "colored plain");
}

#[test]
fn test_truecolor_stripping() {
    let ft = FormattedText::new("\x1b[38;2;255;128;0mrgb text\x1b[0m");
    assert_eq!(ft.plain_text(), "rgb text");
}

#[test]
fn test_256_color_background() {
    let ft = FormattedText::new("\x1b[48;5;21mblue bg\x1b[0m");
    assert_eq!(ft.plain_text(), "blue bg");
}

#[test]
fn test_mixed_ansi_codes() {
    let ft = FormattedText::new("\x1b[1;38;5;82mgreen bold\x1b[0m normal");
    assert_eq!(ft.plain_text(), "green bold normal");
}

#[test]
fn test_raw_truncated_short() {
    let ft = FormattedText::new("hello");
    assert_eq!(ft.raw_truncated(10), "hello");
}

#[test]
fn test_raw_truncated_with_ansi() {
    let ft = FormattedText::new("\x1b[31mhello world\x1b[0m");
    let result = ft.raw_truncated(5);
    // Should contain "hello" visible chars with ANSI prefix and reset
    assert!(result.starts_with("\x1b[31m"));
    assert!(result.ends_with("\x1b[0m"));
    // Extract visible text
    let plain = FormattedText::new(&result);
    assert_eq!(plain.plain_text(), "hello");
}

#[test]
fn test_raw_truncated_with_decorator() {
    let ft = FormattedText::new("\x1b[31mabcdefghijklmnopqrstuvwxyz\x1b[0m");
    let result = ft.raw_truncated_with_decorator(15);
    let plain = FormattedText::new(&result);
    assert_eq!(plain.plain_text().chars().count(), 15);
    assert!(plain.plain_text().contains("|...|"));
}

#[test]
fn test_raw_truncated_decorator_no_ansi() {
    let ft = FormattedText::new("abcdefghijklmnopqrstuvwxyz");
    let result = ft.raw_truncated_with_decorator(15);
    let plain = FormattedText::new(&result);
    assert_eq!(plain.plain_text().chars().count(), 15);
    assert!(plain.plain_text().contains("|...|"));
}

#[test]
fn test_raw_truncated_with_decorator_short_text() {
    // Line 126: text fits within max_visible, returns raw unchanged
    let ft = FormattedText::new("short");
    let result = ft.raw_truncated_with_decorator(20);
    assert_eq!(result, "short");
}

#[test]
fn test_raw_truncated_with_decorator_tiny_max() {
    // Line 132: max_visible too small for decorator, falls back to raw_truncated
    let ft = FormattedText::new("abcdefghijklmnopqrstuvwxyz");
    let result = ft.raw_truncated_with_decorator(5);
    let plain = FormattedText::new(&result);
    assert_eq!(plain.plain_text().chars().count(), 5);
    assert!(!plain.plain_text().contains("|...|"));
}

#[test]
fn test_raw_take_back_large_n() {
    // Line 182: n >= total_visible, returns raw unchanged
    let ft = FormattedText::new("\x1b[31mhello\x1b[0m");
    let result = ft.raw_take_back(100);
    assert_eq!(result, "\x1b[31mhello\x1b[0m");
}
