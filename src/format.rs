/// Wraps a line of text that may contain ANSI escape sequences,
/// providing both plain-text access and raw ANSI-preserved access.
#[derive(Debug, Clone)]
pub struct FormattedText {
    plain: String,
    raw: String,
}

impl FormattedText {
    /// Parse a string potentially containing ANSI escape sequences.
    /// Stores both the raw text (with ANSI codes) and plain text (stripped).
    pub fn new(raw: &str) -> Self {
        let mut plain = String::new();
        let chars: Vec<char> = raw.chars().collect();
        let mut i = 0;

        while i < chars.len() {
            if chars[i] == '\x1b' && i + 1 < chars.len() && chars[i + 1] == '[' {
                // Skip ANSI sequence: ESC[ ... (terminator)
                i += 2;
                while i < chars.len() && !is_ansi_terminator(chars[i]) {
                    i += 1;
                }
                if i < chars.len() {
                    i += 1; // skip terminator
                }
            } else {
                plain.push(chars[i]);
                i += 1;
            }
        }

        Self {
            plain,
            raw: raw.to_string(),
        }
    }

    /// Get the plain text without any ANSI formatting.
    pub fn plain_text(&self) -> &str {
        &self.plain
    }

    /// Get the raw text with ANSI escape sequences preserved.
    #[cfg(test)]
    pub fn raw_text(&self) -> &str {
        &self.raw
    }

    /// Split the raw text at a visible character position, preserving ANSI codes.
    /// Like Python's FormattedText.breakat(). Returns (before, after) with ANSI intact.
    pub fn breakat(&self, visible_pos: usize) -> (String, String) {
        let chars: Vec<char> = self.raw.chars().collect();
        let mut visible = 0;
        let mut i = 0;

        while i < chars.len() && visible < visible_pos {
            if chars[i] == '\x1b' && i + 1 < chars.len() && chars[i + 1] == '[' {
                // Skip ANSI sequence entirely (counts as 0 visible chars)
                i += 2;
                while i < chars.len() && !is_ansi_terminator(chars[i]) {
                    i += 1;
                }
                if i < chars.len() {
                    i += 1; // skip terminator
                }
            } else {
                visible += 1;
                i += 1;
            }
        }

        let before: String = chars[..i].iter().collect();
        let after: String = chars[i..].iter().collect();
        (before, after)
    }

    /// Check if the raw text contains any ANSI escape sequences.
    pub fn has_ansi(&self) -> bool {
        self.raw.len() != self.plain.len()
    }

    /// Get raw text truncated to max_visible visible characters,
    /// preserving ANSI escape sequences within that range.
    /// Returns the raw text slice with ANSI codes intact, plus a reset sequence at the end.
    pub fn raw_truncated(&self, max_visible: usize) -> String {
        if self.plain.chars().count() <= max_visible {
            return self.raw.clone();
        }

        let mut result = String::new();
        let chars: Vec<char> = self.raw.chars().collect();
        let mut visible_count = 0;
        let mut i = 0;

        while i < chars.len() && visible_count < max_visible {
            if chars[i] == '\x1b' && i + 1 < chars.len() && chars[i + 1] == '[' {
                // Copy entire ANSI sequence
                result.push(chars[i]);
                i += 1;
                while i < chars.len() {
                    result.push(chars[i]);
                    if is_ansi_terminator(chars[i]) {
                        i += 1;
                        break;
                    }
                    i += 1;
                }
            } else {
                result.push(chars[i]);
                visible_count += 1;
                i += 1;
            }
        }

        // Append reset to avoid color bleeding
        result.push_str("\x1b[0m");
        result
    }

    /// Get raw text with |...| truncation decorator applied,
    /// preserving ANSI codes in the front and back portions.
    pub fn raw_truncated_with_decorator(&self, max_visible: usize) -> String {
        let plain_len = self.plain.chars().count();
        if plain_len <= max_visible {
            return self.raw.clone();
        }

        let decorator = "|...|";
        let decorator_len = decorator.len();
        if max_visible <= decorator_len + 2 {
            return self.raw_truncated(max_visible);
        }

        let remaining = max_visible - decorator_len;
        let front_visible = remaining / 2;
        let back_visible = remaining - front_visible;

        // Get front portion with ANSI
        let front = self.raw_take_front(front_visible);
        // Get back portion with ANSI
        let back = self.raw_take_back(back_visible);

        format!("{front}\x1b[0m{decorator}{back}\x1b[0m")
    }

    /// Take the first N visible characters from raw text, preserving ANSI codes.
    fn raw_take_front(&self, n: usize) -> String {
        let mut result = String::new();
        let chars: Vec<char> = self.raw.chars().collect();
        let mut visible = 0;
        let mut i = 0;

        while i < chars.len() && visible < n {
            if chars[i] == '\x1b' && i + 1 < chars.len() && chars[i + 1] == '[' {
                result.push(chars[i]);
                i += 1;
                while i < chars.len() {
                    result.push(chars[i]);
                    if is_ansi_terminator(chars[i]) {
                        i += 1;
                        break;
                    }
                    i += 1;
                }
            } else {
                result.push(chars[i]);
                visible += 1;
                i += 1;
            }
        }

        result
    }

    /// Take the last N visible characters from raw text, preserving ANSI codes.
    fn raw_take_back(&self, n: usize) -> String {
        let chars: Vec<char> = self.raw.chars().collect();
        let plain_chars: Vec<char> = self.plain.chars().collect();
        let total_visible = plain_chars.len();
        if n >= total_visible {
            return self.raw.clone();
        }

        let skip_visible = total_visible - n;
        let mut result = String::new();
        let mut visible = 0;
        let mut i = 0;
        let mut collecting = false;

        while i < chars.len() {
            if chars[i] == '\x1b' && i + 1 < chars.len() && chars[i + 1] == '[' {
                let start = i;
                i += 2;
                while i < chars.len() && !is_ansi_terminator(chars[i]) {
                    i += 1;
                }
                if i < chars.len() {
                    i += 1;
                }
                if collecting {
                    for &ch in &chars[start..i] {
                        result.push(ch);
                    }
                }
            } else {
                visible += 1;
                if visible > skip_visible {
                    collecting = true;
                }
                if collecting {
                    result.push(chars[i]);
                }
                i += 1;
            }
        }

        result
    }
}

/// Check if a character is an ANSI CSI sequence terminator.
/// Only recognize 'm' and 'K' to match Python PathPicker's behavior.
/// Other CSI terminators (H, J, A, B, C, D) are left as literal text,
/// matching how the original Python formatted_text.py handles them.
fn is_ansi_terminator(ch: char) -> bool {
    matches!(ch, 'm' | 'K')
}

#[cfg(test)]
mod tests {
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
}
