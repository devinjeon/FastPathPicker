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

    /// Get the x-offset where content starts (after scrollbar/x-mode area).
    /// Python's CHROME_MIN_X = 5 for both scrollbar and x-mode.
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

/// Usage strings shown in the UI (matching Python's screen_control.py).
pub const USAGE_HEADER: &str =
    "[f|A] selection, [down|j|up|k|space|b] navigation, [enter] open, [x] quick select mode, [c] command mode";
pub const USAGE_HEADER_ALL_INPUT: &str =
    "[f|A] selection, [down|j|up|k|space|b] navigation, [x] quick select mode, [c] command mode";
pub const USAGE_COMMAND: &str =
    "command examples: | git add | git checkout HEAD~1 -- | mv $F ../here/ |";
pub const USAGE_XMODE: &str =
    "[f|A] selection, [down|j|up|k|space|b] navigation, [enter] open, [x] quick select mode, [c] command mode";

/// Sidebar usage text (matching Python's usage_strings.py USAGE_PAGE).
pub const USAGE_PAGE: &str = "
    * [f] toggle the selection of a file
    * [F] toggle and move downward by 1
    * [A] toggle selection of all (unique) files
    * [down arrow|j] move downward by 1
    * [up arrow|k] move upward by 1
    * [<space>] page down
    * [b] page up
    * [x] quick select mode
    * [d] describe file


Once you have your files selected, you can
either open them in your favorite
text editor or execute commands with
them via command mode:

    * [<Enter>] open all selected files
        (or file under cursor if none selected)
        in $EDITOR
    * [c] enter command mode
";

pub const USAGE_COMMAND_PAGE: &str = "Command mode is helpful when you want to
execute bash commands with the filenames
you have selected. By default the filenames
are appended automatically to command you
enter before it is executed, so all you have
to do is type the prefix. Some examples:

    * git add
    * git checkout HEAD~1 --
    * rm -rf

These commands get formatted into:
    * git add file1 file2 # etc
    * git checkout HEAD~1 -- file1 file2
    * rm -rf file1 file2 # etc

If your command needs filenames in the middle,
the token \"$F\" will be replaced with your
selected filenames if it is found in the command
string. Examples include:

    * scp $F dev:~/backup
    * mv $F ../over/here

Which format to:
    * scp file1 file2 dev:~/backup
    * mv file1 file2 ../over/here";

/// Command mode prompt strings (matching Python's screen_control.py).
pub const SHORT_COMMAND_PROMPT: &str = "Type a command below! Paths will be appended or replace $F";
pub const SHORT_COMMAND_PROMPT2: &str = "Enter a blank line to go back to the selection process";
pub const SHORT_PATHS_HEADER: &str = "Paths you have selected:";

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

    #[test]
    fn test_content_start_x_with_scrollbar() {
        let chrome = Chrome::new(80, 24);
        assert_eq!(chrome.content_start_x(true, false), 5);
        assert_eq!(chrome.content_start_x(false, false), 0);
        assert_eq!(chrome.content_start_x(false, true), 5);
    }

    #[test]
    fn test_command_prompt_strings_match_python() {
        assert_eq!(
            SHORT_COMMAND_PROMPT,
            "Type a command below! Paths will be appended or replace $F"
        );
        assert_eq!(
            SHORT_COMMAND_PROMPT2,
            "Enter a blank line to go back to the selection process"
        );
        assert_eq!(SHORT_PATHS_HEADER, "Paths you have selected:");
    }

    #[test]
    fn test_usage_page_contains_python_keys() {
        assert!(USAGE_PAGE.contains("[f] toggle the selection of a file"));
        assert!(USAGE_PAGE.contains("[F] toggle and move downward by 1"));
        assert!(USAGE_PAGE.contains("[A] toggle selection of all (unique) files"));
        assert!(USAGE_PAGE.contains("[x] quick select mode"));
        assert!(USAGE_PAGE.contains("[d] describe file"));
        assert!(USAGE_PAGE.contains("[<Enter>] open all selected files"));
        assert!(USAGE_PAGE.contains("[c] enter command mode"));
    }

    #[test]
    fn test_usage_command_page_contains_python_examples() {
        assert!(USAGE_COMMAND_PAGE.contains("git add"));
        assert!(USAGE_COMMAND_PAGE.contains("git checkout HEAD~1 --"));
        assert!(USAGE_COMMAND_PAGE.contains("rm -rf"));
        assert!(USAGE_COMMAND_PAGE.contains("$F"));
        assert!(USAGE_COMMAND_PAGE.contains("scp $F dev:~/backup"));
    }
}
