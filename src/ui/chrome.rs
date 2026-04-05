/// UI chrome dimensions and layout.
pub struct Chrome {
    pub is_wide: bool,
    pub sidebar_width: u16,
    pub content_width: u16,
    pub content_height: u16,
}

const WIDE_MODE_THRESHOLD: u16 = 200;
const SIDEBAR_WIDTH: u16 = 50;
const NARROW_INFO_LINES: u16 = 4;

impl Chrome {
    pub fn new(width: u16, height: u16) -> Self {
        let is_wide = width > WIDE_MODE_THRESHOLD;
        let sidebar_width = if is_wide { SIDEBAR_WIDTH } else { 0 };
        let info_lines = if is_wide { 0 } else { NARROW_INFO_LINES };
        let content_width = width.saturating_sub(sidebar_width);
        let content_height = height.saturating_sub(info_lines);

        Self {
            is_wide,
            sidebar_width,
            content_width,
            content_height,
        }
    }

    /// Get the x-offset where content starts (after scrollbar area).
    pub fn content_start_x(&self, has_scrollbar: bool, x_mode: bool) -> u16 {
        if has_scrollbar || x_mode {
            5
        } else {
            0
        }
    }

    /// Get the usable content width for text display.
    pub fn text_width(&self, has_scrollbar: bool, x_mode: bool) -> u16 {
        self.content_width
            .saturating_sub(self.content_start_x(has_scrollbar, x_mode))
    }
}

/// Usage strings shown in the UI.
pub const USAGE_HEADER: &str =
    "  [fpp] j/k:navigate  f:select  A:select-all  c:command  x:quick-select  ENTER:open  q:quit";
pub const USAGE_HEADER_ALL_INPUT: &str =
    "  [fpp] j/k:navigate  f:select  A:select-all  c:command  x:quick-select  q:quit";
pub const USAGE_COMMAND: &str =
    "  [fpp] Type a command, press ENTER to execute (use $F for filenames)";
pub const USAGE_XMODE: &str = "  [fpp] Quick select mode: press a label to toggle selection";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_narrow_mode() {
        let chrome = Chrome::new(80, 24);
        assert!(!chrome.is_wide);
        assert_eq!(chrome.sidebar_width, 0);
        assert_eq!(chrome.content_width, 80);
    }

    #[test]
    fn test_wide_mode() {
        let chrome = Chrome::new(220, 50);
        assert!(chrome.is_wide);
        assert_eq!(chrome.sidebar_width, SIDEBAR_WIDTH);
        assert_eq!(chrome.content_width, 170);
    }
}
