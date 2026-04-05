/// Wraps a line of text that may contain ANSI escape sequences,
/// providing plain-text access with ANSI codes stripped.
#[derive(Debug, Clone)]
pub struct FormattedText {
    plain: String,
}

impl FormattedText {
    /// Parse a string potentially containing ANSI escape sequences.
    /// Strips all ANSI codes and stores only the plain text.
    pub fn new(raw: &str) -> Self {
        let mut plain = String::new();
        let chars: Vec<char> = raw.chars().collect();
        let mut i = 0;

        while i < chars.len() {
            if chars[i] == '\x1b' && i + 1 < chars.len() && chars[i + 1] == '[' {
                // Skip ANSI sequence: ESC[ ... m
                i += 2;
                while i < chars.len() && chars[i] != 'm' {
                    i += 1;
                }
                if i < chars.len() {
                    i += 1; // skip 'm'
                }
            } else {
                plain.push(chars[i]);
                i += 1;
            }
        }

        Self { plain }
    }

    /// Get the plain text without any ANSI formatting.
    pub fn plain_text(&self) -> &str {
        &self.plain
    }
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
    fn test_empty() {
        let ft = FormattedText::new("");
        assert_eq!(ft.plain_text(), "");
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
}
