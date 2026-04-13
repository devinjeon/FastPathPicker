use std::borrow::Cow;

/// Classification of a segment in ANSI-containing text.
enum AnsiSegment {
    /// A visible character at the given char index.
    Visible(usize),
    /// An ANSI escape sequence spanning chars[start..end].
    Escape(usize, usize),
}

/// Iterate over raw_chars, yielding each segment as either a visible character
/// or an ANSI escape sequence span. Centralizes the ANSI-skipping logic that
/// was previously duplicated across new, breakat, raw_truncated, raw_take_front,
/// raw_take_back, and visible_char_count.
fn iter_ansi_segments(chars: &[char]) -> impl Iterator<Item = AnsiSegment> + '_ {
    let mut i = 0;
    std::iter::from_fn(move || {
        if i >= chars.len() {
            return None;
        }
        if chars[i] == '\x1b' && i + 1 < chars.len() && chars[i + 1] == '[' {
            let start = i;
            i += 2;
            while i < chars.len() && !is_ansi_terminator(chars[i]) {
                i += 1;
            }
            if i < chars.len() {
                i += 1; // skip terminator
            }
            Some(AnsiSegment::Escape(start, i))
        } else {
            let idx = i;
            i += 1;
            Some(AnsiSegment::Visible(idx))
        }
    })
}

/// Find the raw char index corresponding to the given visible character position.
/// ANSI sequences before that position are included (i.e., the returned index
/// points to the first visible char at or beyond `visible_pos`).
fn find_raw_offset_for_visible(chars: &[char], visible_pos: usize) -> usize {
    let mut visible = 0;
    for segment in iter_ansi_segments(chars) {
        if let AnsiSegment::Visible(idx) = segment {
            if visible >= visible_pos {
                return idx;
            }
            visible += 1;
        }
    }
    chars.len()
}

/// Wraps a line of text that may contain ANSI escape sequences,
/// providing both plain-text access and raw ANSI-preserved access.
#[derive(Debug, Clone)]
pub struct FormattedText {
    plain: String,
    raw: String,
    /// Pre-computed char vector from `raw` to avoid repeated `chars().collect()` allocations
    /// in methods that need character-level indexing (breakat, truncation, etc.).
    raw_chars: Vec<char>,
}

impl FormattedText {
    /// Parse a string potentially containing ANSI escape sequences.
    /// Stores both the raw text (with ANSI codes) and plain text (stripped).
    pub fn new(raw: &str) -> Self {
        let chars: Vec<char> = raw.chars().collect();
        let mut plain = String::new();
        for segment in iter_ansi_segments(&chars) {
            if let AnsiSegment::Visible(idx) = segment {
                plain.push(chars[idx]);
            }
        }

        let raw_owned = raw.to_string();
        Self {
            plain,
            raw: raw_owned,
            raw_chars: chars,
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
        let split_at = find_raw_offset_for_visible(&self.raw_chars, visible_pos);
        let before: String = self.raw_chars[..split_at].iter().collect();
        let after: String = self.raw_chars[split_at..].iter().collect();
        (before, after)
    }

    /// Check if the raw text contains any ANSI escape sequences.
    pub fn has_ansi(&self) -> bool {
        self.raw.len() != self.plain.len()
    }

    /// Get raw text truncated to max_visible visible characters,
    /// preserving ANSI escape sequences within that range.
    /// Returns the raw text slice with ANSI codes intact, plus a reset sequence at the end.
    pub fn raw_truncated(&self, max_visible: usize) -> Cow<'_, str> {
        if self.plain.chars().count() <= max_visible {
            return Cow::Borrowed(&self.raw);
        }

        let mut result = String::new();
        let chars = &self.raw_chars;
        let mut visible_count = 0;

        for segment in iter_ansi_segments(chars) {
            match segment {
                AnsiSegment::Escape(start, end) => {
                    for &ch in &chars[start..end] {
                        result.push(ch);
                    }
                }
                AnsiSegment::Visible(idx) => {
                    if visible_count >= max_visible {
                        break;
                    }
                    result.push(chars[idx]);
                    visible_count += 1;
                }
            }
        }

        // Append reset to avoid color bleeding
        result.push_str("\x1b[0m");
        Cow::Owned(result)
    }

    /// Get raw text with |...| truncation decorator applied,
    /// preserving ANSI codes in the front and back portions.
    pub fn raw_truncated_with_decorator(&self, max_visible: usize) -> Cow<'_, str> {
        let plain_len = self.plain.chars().count();
        if plain_len <= max_visible {
            return Cow::Borrowed(&self.raw);
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

        Cow::Owned(format!("{front}\x1b[0m{decorator}{back}\x1b[0m"))
    }

    /// Take the first N visible characters from raw text, preserving ANSI codes
    /// that appear *before or between* those characters. Does NOT append a trailing
    /// ANSI reset — callers must add `\x1b[0m` themselves if color bleed is a concern
    /// (e.g., `raw_truncated_with_decorator` does this explicitly).
    fn raw_take_front(&self, n: usize) -> String {
        let mut result = String::new();
        let chars = &self.raw_chars;
        let mut visible = 0;

        for segment in iter_ansi_segments(chars) {
            match segment {
                AnsiSegment::Escape(start, end) => {
                    for &ch in &chars[start..end] {
                        result.push(ch);
                    }
                }
                AnsiSegment::Visible(idx) => {
                    if visible >= n {
                        break;
                    }
                    result.push(chars[idx]);
                    visible += 1;
                }
            }
        }

        result
    }

    /// Take the last N visible characters from raw text, preserving ALL ANSI
    /// escape sequences — including those preceding the visible portion — so that
    /// colors/styles set earlier in the string are still active. This is
    /// asymmetric with `raw_take_front`, which stops collecting as soon as it
    /// reaches the visible-character limit and therefore drops trailing ANSI codes.
    fn raw_take_back(&self, n: usize) -> String {
        let chars = &self.raw_chars;
        let total_visible = self.plain.chars().count();
        if n >= total_visible {
            return self.raw.clone();
        }

        let skip_visible = total_visible - n;
        let mut result = String::new();
        let mut visible = 0;

        for segment in iter_ansi_segments(chars) {
            match segment {
                AnsiSegment::Escape(start, end) => {
                    // Always collect ANSI sequences so preceding colors are preserved
                    for &ch in &chars[start..end] {
                        result.push(ch);
                    }
                }
                AnsiSegment::Visible(idx) => {
                    visible += 1;
                    if visible > skip_visible {
                        result.push(chars[idx]);
                    }
                }
            }
        }

        result
    }
}

/// Truncate a raw ANSI-containing string to `max_visible` visible characters,
/// preserving ANSI codes. Appends a reset sequence when truncation occurs.
/// Like `FormattedText::raw_truncated` but operates on a plain `&str` without
/// requiring a full `FormattedText` construction.
pub fn raw_truncate_str(raw: &str, max_visible: usize) -> String {
    let mut result = String::new();
    let mut visible_count = 0;
    let mut truncated = false;
    let mut chars = raw.chars().peekable();

    while let Some(ch) = chars.next() {
        if ch == '\x1b' && chars.peek() == Some(&'[') {
            result.push(ch);
            result.push(chars.next().unwrap()); // '['
            for ch in chars.by_ref() {
                result.push(ch);
                if is_ansi_terminator(ch) {
                    break;
                }
            }
        } else {
            if visible_count >= max_visible {
                truncated = true;
                break;
            }
            result.push(ch);
            visible_count += 1;
        }
    }

    if truncated {
        result.push_str("\x1b[0m");
    }
    result
}

/// Split a raw ANSI-containing string at a visible character position without
/// constructing a full `FormattedText`. Used when the caller already has a raw
/// substring and only needs to split it (e.g., splitting rest_raw at match boundary).
pub fn breakat_raw(raw: &str, visible_pos: usize) -> (String, String) {
    let chars: Vec<char> = raw.chars().collect();
    let split_at = find_raw_offset_for_visible(&chars, visible_pos);
    let before: String = chars[..split_at].iter().collect();
    let after: String = chars[split_at..].iter().collect();
    (before, after)
}

/// Count visible (non-ANSI) characters in a string without constructing a FormattedText.
/// Operates directly on bytes/chars without allocating a Vec<char>, since this is called
/// per-line during rendering.
pub fn visible_char_count(s: &str) -> usize {
    let mut count = 0;
    let mut chars = s.chars();
    while let Some(ch) = chars.next() {
        if ch == '\x1b' {
            if chars.clone().next() == Some('[') {
                chars.next(); // skip '['
                for ch in chars.by_ref() {
                    if is_ansi_terminator(ch) {
                        break;
                    }
                }
            } else {
                count += 1;
            }
        } else {
            count += 1;
        }
    }
    count
}

/// Check if a character is an ANSI CSI sequence terminator.
/// Only recognize 'm' and 'K' to match Python PathPicker's behavior.
/// Other CSI terminators (H, J, A, B, C, D) are left as literal text,
/// matching how the original Python formatted_text.py handles them.
fn is_ansi_terminator(ch: char) -> bool {
    matches!(ch, 'm' | 'K')
}

#[cfg(test)]
#[path = "format_tests.rs"]
mod tests;
