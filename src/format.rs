use crossterm::style::{Attribute, Color, ContentStyle};

/// Represents a segment of text with optional ANSI styling.
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct StyledSegment {
    pub text: String,
    pub style: ContentStyle,
}

/// Wraps a line of text that may contain ANSI escape sequences,
/// providing both styled and plain-text access.
#[derive(Debug, Clone)]
#[allow(dead_code)]
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

                // Apply codes, handling 256-color (38;5;N) and truecolor (38;2;R;G;B)
                let codes: Vec<&str> = code_str.split(';').collect();
                let mut ci = 0;
                while ci < codes.len() {
                    let code: u16 = codes[ci].parse().unwrap_or(0);
                    match code {
                        38 if ci + 2 < codes.len() && codes[ci + 1] == "5" => {
                            // 256-color foreground: 38;5;N
                            let n: u8 = codes[ci + 2].parse().unwrap_or(0);
                            current_style.foreground_color = Some(Color::AnsiValue(n));
                            ci += 3;
                        }
                        38 if ci + 4 < codes.len() && codes[ci + 1] == "2" => {
                            // Truecolor foreground: 38;2;R;G;B
                            let r: u8 = codes[ci + 2].parse().unwrap_or(0);
                            let g: u8 = codes[ci + 3].parse().unwrap_or(0);
                            let b: u8 = codes[ci + 4].parse().unwrap_or(0);
                            current_style.foreground_color = Some(Color::Rgb { r, g, b });
                            ci += 5;
                        }
                        48 if ci + 2 < codes.len() && codes[ci + 1] == "5" => {
                            // 256-color background: 48;5;N
                            let n: u8 = codes[ci + 2].parse().unwrap_or(0);
                            current_style.background_color = Some(Color::AnsiValue(n));
                            ci += 3;
                        }
                        48 if ci + 4 < codes.len() && codes[ci + 1] == "2" => {
                            // Truecolor background: 48;2;R;G;B
                            let r: u8 = codes[ci + 2].parse().unwrap_or(0);
                            let g: u8 = codes[ci + 3].parse().unwrap_or(0);
                            let b: u8 = codes[ci + 4].parse().unwrap_or(0);
                            current_style.background_color = Some(Color::Rgb { r, g, b });
                            ci += 5;
                        }
                        _ => {
                            current_style = apply_ansi_code(current_style, code as u8);
                            ci += 1;
                        }
                    }
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
    #[allow(dead_code)]
    pub fn segments(&self) -> &[StyledSegment] {
        &self.segments
    }

    /// Get a substring of the formatted text, breaking at a character position.
    #[allow(dead_code)]
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
    #[allow(dead_code)]
    pub fn len(&self) -> usize {
        self.plain.chars().count()
    }

    #[allow(dead_code)]
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

    #[test]
    fn test_256_color_stripping() {
        // 256-color foreground: ESC[38;5;196m (red)
        let ft = FormattedText::new("\x1b[38;5;196mcolored\x1b[0m plain");
        assert_eq!(ft.plain_text(), "colored plain");
    }

    #[test]
    fn test_truecolor_stripping() {
        // Truecolor foreground: ESC[38;2;255;128;0m (orange)
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
        // Bold + 256-color + text
        let ft = FormattedText::new("\x1b[1;38;5;82mgreen bold\x1b[0m normal");
        assert_eq!(ft.plain_text(), "green bold normal");
    }
}
