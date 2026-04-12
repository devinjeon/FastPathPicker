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

// --- visible_char_count tests ---

#[test]
fn test_visible_char_count_plain() {
    assert_eq!(visible_char_count("hello world"), 11);
}

#[test]
fn test_visible_char_count_empty() {
    assert_eq!(visible_char_count(""), 0);
}

#[test]
fn test_visible_char_count_ansi_color() {
    assert_eq!(visible_char_count("\x1b[31mred text\x1b[0m"), 8);
}

#[test]
fn test_visible_char_count_256_color() {
    assert_eq!(visible_char_count("\x1b[38;5;196mcolored\x1b[0m"), 7);
}

#[test]
fn test_visible_char_count_truecolor() {
    assert_eq!(visible_char_count("\x1b[38;2;255;128;0mrgb\x1b[0m"), 3);
}

#[test]
fn test_visible_char_count_ansi_only() {
    assert_eq!(visible_char_count("\x1b[0m\x1b[31m\x1b[0m"), 0);
}

#[test]
fn test_visible_char_count_matches_formatted_text() {
    // Ensure visible_char_count produces the same result as FormattedText
    let test_cases = [
        "plain text",
        "\x1b[31mred\x1b[0m normal",
        "\x1b[1;38;5;82mgreen bold\x1b[0m",
        "",
        "\x1b[48;5;21mblue bg\x1b[0m mixed \x1b[33myellow\x1b[0m",
        "no ansi at all",
        "\x1b[Kline clear followed by text",
    ];
    for input in &test_cases {
        let ft_count = FormattedText::new(input).plain_text().chars().count();
        let util_count = visible_char_count(input);
        assert_eq!(ft_count, util_count, "Mismatch for input: {:?}", input);
    }
}

// --- raw_take_back ANSI preservation tests ---

#[test]
fn test_raw_take_back_preserves_ansi_color() {
    // Critical: raw_take_back must preserve ANSI codes preceding the visible portion.
    // "\x1b[31mabcdefghij\x1b[0m" with n=5 should yield "\x1b[31mfghij\x1b[0m"
    // (the red color code must NOT be dropped).
    let ft = FormattedText::new("\x1b[31mabcdefghij\x1b[0m");
    let result = ft.raw_take_back(5);
    assert!(
        result.contains("\x1b[31m"),
        "Should preserve red color code, got: {:?}",
        result
    );
    let plain = FormattedText::new(&result);
    assert_eq!(plain.plain_text(), "fghij");
}

#[test]
fn test_raw_take_back_multiple_ansi_codes() {
    // Multiple ANSI codes: all should be preserved
    let ft = FormattedText::new("\x1b[1m\x1b[31mabcde\x1b[0m");
    let result = ft.raw_take_back(3);
    assert!(result.contains("\x1b[1m"), "Should preserve bold code");
    assert!(result.contains("\x1b[31m"), "Should preserve red code");
    let plain = FormattedText::new(&result);
    assert_eq!(plain.plain_text(), "cde");
}

#[test]
fn test_raw_truncated_with_decorator_preserves_back_ansi() {
    // Decorator mode: the back portion should have ANSI colors preserved
    let ft = FormattedText::new("\x1b[31mabcdefghijklmnopqrstuvwxyz\x1b[0m");
    let result = ft.raw_truncated_with_decorator(15);
    let plain = FormattedText::new(&result);
    assert_eq!(plain.plain_text().chars().count(), 15);
    // The back portion should still have the red ANSI code
    // (there should be at least 2 occurrences of \x1b[31m or the code before the back part)
    assert!(
        result.contains("\x1b[31m"),
        "Back portion should preserve ANSI color, got: {:?}",
        result
    );
}

// --- breakat tests ---

#[test]
fn test_breakat_plain() {
    let ft = FormattedText::new("hello world");
    let (before, after) = ft.breakat(5);
    assert_eq!(before, "hello");
    assert_eq!(after, " world");
}

#[test]
fn test_breakat_with_ansi() {
    let ft = FormattedText::new("\x1b[31mhello world\x1b[0m");
    let (before, after) = ft.breakat(5);
    // before should include the ANSI prefix and "hello"
    assert_eq!(FormattedText::new(&before).plain_text(), "hello");
    assert_eq!(FormattedText::new(&after).plain_text(), " world");
}

#[test]
fn test_breakat_at_zero() {
    let ft = FormattedText::new("hello");
    let (before, after) = ft.breakat(0);
    assert_eq!(before, "");
    assert_eq!(after, "hello");
}

#[test]
fn test_breakat_beyond_length() {
    let ft = FormattedText::new("hi");
    let (before, after) = ft.breakat(100);
    assert_eq!(before, "hi");
    assert_eq!(after, "");
}
