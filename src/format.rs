use crossterm::style::{Attribute, Color, ContentStyle};

/// Represents a segment of text with optional ANSI styling.
#[derive(Debug, Clone)]
pub struct StyledSegment {
    pub text: String,
    pub style: ContentStyle,
}

/// Wraps a line of text that may contain ANSI escape sequences,
/// providing both styled and plain-text access.
#[derive(Debug, Clone)]
pub struct FormattedText {
    segments: Vec<StyledSegment>,
    plain: String,
}

impl FormattedText {
    /// Parse a string potentially containing ANSI escape sequences.
    pub fn new(raw: &str) -> Self {
        let mut segments = Vec::new();
        let mut plain = String::new();
        let mut current_style = ContentStyle::new();
        let mut current_text = String::new();
        let chars: Vec<char> = raw.chars().collect();
        let mut i = 0;

        while i < chars.len() {
            if chars[i] == '\x1b' && i + 1 < chars.len() && chars[i + 1] == '[' {
                // Flush current text
                if !current_text.is_empty() {
                    segments.push(StyledSegment {
                        text: current_text.clone(),
                        style: current_style,
                    });
                    current_text.clear();
                }

                // Parse ANSI sequence
                i += 2; // skip ESC[
                let mut code_str = String::new();
                while i < chars.len() && chars[i] != 'm' {
                    code_str.push(chars[i]);
                    i += 1;
                }
                if i < chars.len() {
                    i += 1; // skip 'm'
                }

                // Apply codes
                for code in code_str.split(';') {
                    let code: u8 = code.parse().unwrap_or(0);
                    current_style = apply_ansi_code(current_style, code);
                }
            } else {
                current_text.push(chars[i]);
                plain.push(chars[i]);
                i += 1;
            }
        }

        // Flush remaining text
        if !current_text.is_empty() {
            segments.push(StyledSegment {
                text: current_text,
                style: current_style,
            });
        }

        Self { segments, plain }
    }

    /// Get the plain text without any ANSI formatting.
    pub fn plain_text(&self) -> &str {
        &self.plain
    }

    /// Get the styled segments for rendering.
    pub fn segments(&self) -> &[StyledSegment] {
        &self.segments
    }

    /// Get a substring of the formatted text, breaking at a character position.
    pub fn break_at(&self, pos: usize) -> FormattedText {
        let mut new_segments = Vec::new();
        let mut remaining = pos;

        for seg in &self.segments {
            if remaining == 0 {
                break;
            }
            let chars: Vec<char> = seg.text.chars().collect();
            let take = remaining.min(chars.len());
            let text: String = chars[..take].iter().collect();
            new_segments.push(StyledSegment {
                text,
                style: seg.style,
            });
            remaining -= take;
        }

        let plain: String = self.plain.chars().take(pos).collect();
        FormattedText {
            segments: new_segments,
            plain,
        }
    }

    /// Length of the plain text in characters (not bytes).
    pub fn len(&self) -> usize {
        self.plain.chars().count()
    }

    pub fn is_empty(&self) -> bool {
        self.plain.is_empty()
    }
}

fn apply_ansi_code(mut style: ContentStyle, code: u8) -> ContentStyle {
    match code {
        0 => ContentStyle::new(), // reset
        1 => {
            style.attributes.set(Attribute::Bold);
            style
        }
        4 => {
            style.attributes.set(Attribute::Underlined);
            style
        }
        30 => {
            style.foreground_color = Some(Color::Black);
            style
        }
        31 => {
            style.foreground_color = Some(Color::DarkRed);
            style
        }
        32 => {
            style.foreground_color = Some(Color::DarkGreen);
            style
        }
        33 => {
            style.foreground_color = Some(Color::DarkYellow);
            style
        }
        34 => {
            style.foreground_color = Some(Color::DarkBlue);
            style
        }
        35 => {
            style.foreground_color = Some(Color::DarkMagenta);
            style
        }
        36 => {
            style.foreground_color = Some(Color::DarkCyan);
            style
        }
        37 => {
            style.foreground_color = Some(Color::Grey);
            style
        }
        39 => {
            style.foreground_color = None;
            style
        }
        40 => {
            style.background_color = Some(Color::Black);
            style
        }
        41 => {
            style.background_color = Some(Color::DarkRed);
            style
        }
        42 => {
            style.background_color = Some(Color::DarkGreen);
            style
        }
        43 => {
            style.background_color = Some(Color::DarkYellow);
            style
        }
        44 => {
            style.background_color = Some(Color::DarkBlue);
            style
        }
        45 => {
            style.background_color = Some(Color::DarkMagenta);
            style
        }
        46 => {
            style.background_color = Some(Color::DarkCyan);
            style
        }
        47 => {
            style.background_color = Some(Color::Grey);
            style
        }
        49 => {
            style.background_color = None;
            style
        }
        _ => style,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_plain_text() {
        let ft = FormattedText::new("hello world");
        assert_eq!(ft.plain_text(), "hello world");
        assert_eq!(ft.len(), 11);
    }

    #[test]
    fn test_ansi_stripping() {
        let ft = FormattedText::new("\x1b[31mred text\x1b[0m normal");
        assert_eq!(ft.plain_text(), "red text normal");
    }

    #[test]
    fn test_break_at() {
        let ft = FormattedText::new("hello world");
        let broken = ft.break_at(5);
        assert_eq!(broken.plain_text(), "hello");
    }

    #[test]
    fn test_empty() {
        let ft = FormattedText::new("");
        assert!(ft.is_empty());
        assert_eq!(ft.len(), 0);
    }
}
