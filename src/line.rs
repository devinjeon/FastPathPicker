use std::fmt;
use std::fs::File;
use std::io::{BufRead, BufReader};
#[cfg(unix)]
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::time::SystemTime;

use crate::format::FormattedText;
use crate::parse;

/// Represents a line that matched a file path.
#[derive(Debug, Clone)]
pub struct LineMatch {
    pub formatted_text: FormattedText,
    pub path: String,
    pub line_num: u64,
    pub selected: bool,
    original_line: String,
    /// Start position of the match within the plain text (character index)
    pub match_start: usize,
    /// End position of the match within the plain text (character index)
    pub match_end: usize,
}

/// Represents a line that did not match any file path.
#[derive(Debug, Clone)]
pub struct SimpleLine {
    pub formatted_text: FormattedText,
    original_line: String,
}

/// Either a matched or unmatched line.
#[derive(Debug, Clone)]
pub enum Line {
    Match(LineMatch),
    Simple(SimpleLine),
}

impl LineMatch {
    pub fn new(
        formatted_text: FormattedText,
        path: String,
        line_num: u64,
        original_line: String,
        match_start: usize,
        match_end: usize,
    ) -> Self {
        Self {
            formatted_text,
            path,
            line_num,
            selected: false,
            original_line,
            match_start,
            match_end,
        }
    }

    pub fn get_path(&self) -> &str {
        &self.path
    }

    pub fn get_line_num(&self) -> u64 {
        self.line_num
    }

    pub fn get_dir(&self) -> String {
        // path is already resolved at construction time (prepend_dir called in input.rs)
        // Python: os.path.dirname(self.path)
        Path::new(&self.path)
            .parent()
            .map_or(self.path.clone(), |p| p.to_string_lossy().to_string())
    }

    pub fn is_resolvable(&self) -> bool {
        parse::is_resolvable(&self.path)
    }

    pub fn is_git_abbreviated_path(&self) -> bool {
        parse::is_git_abbreviated_path(&self.path)
    }

    pub fn toggle_select(&mut self) {
        self.selected = !self.selected;
    }

    pub fn set_select(&mut self, val: bool) {
        self.selected = val;
    }

    /// Get file description metadata for the sidebar display.
    /// Matches Python's format: local time mm/dd/YYYY, user/group names, wc -l style.
    pub fn get_file_description(&self) -> Vec<String> {
        // path is already resolved (prepend_dir called at construction time)
        let path = Path::new(&self.path);

        let metadata = match path.metadata() {
            Ok(m) => m,
            Err(_) => {
                return vec![
                    format!("File: {}", self.path),
                    "Unable to read metadata".to_string(),
                ]
            }
        };

        let mut desc = Vec::new();

        // Python: last accessed: mm/dd/YYYY HH:MM:SS (local time)
        if let Ok(accessed) = metadata.accessed() {
            desc.push(format!(
                "last accessed: {}",
                format_system_time_local(accessed)
            ));
        }

        // Python: last modified: mm/dd/YYYY HH:MM:SS (local time)
        if let Ok(modified) = metadata.modified() {
            desc.push(format!(
                "last modified: {}",
                format_system_time_local(modified)
            ));
        }

        // Python: owned by user: username, uid / owned by group: groupname, gid
        #[cfg(unix)]
        {
            let uid = metadata.uid();
            let username = get_username(uid).unwrap_or_else(|| uid.to_string());
            desc.push(format!("owned by user: {username}, {uid}"));

            let gid = metadata.gid();
            let groupname = get_groupname(gid).unwrap_or_else(|| gid.to_string());
            desc.push(format!("owned by group: {groupname}, {gid}"));
        }

        // Python: size: 42K (integer division, single-letter suffix)
        let size = metadata.len();
        desc.push(format!("size: {}", format_size_python(size)));

        // Python: length: N lines (or line)
        if size < 10 * 1024 * 1024 {
            if let Ok(file) = File::open(&self.path) {
                let line_count = BufReader::new(file).lines().count();
                let caption = if line_count == 1 { "line" } else { "lines" };
                desc.push(format!("length: {line_count} {caption}"));
            }
        } else {
            desc.push("length: (file too large)".to_string());
        }

        desc
    }
}

impl SimpleLine {
    pub fn new(formatted_text: FormattedText, original_line: String) -> Self {
        Self {
            formatted_text,
            original_line,
        }
    }
}

impl Line {
    pub fn formatted_text(&self) -> &FormattedText {
        match self {
            Line::Match(m) => &m.formatted_text,
            Line::Simple(s) => &s.formatted_text,
        }
    }

    pub fn original_line(&self) -> &str {
        match self {
            Line::Match(m) => &m.original_line,
            Line::Simple(s) => &s.original_line,
        }
    }

    pub fn as_match(&self) -> Option<&LineMatch> {
        match self {
            Line::Match(m) => Some(m),
            _ => None,
        }
    }

    pub fn as_match_mut(&mut self) -> Option<&mut LineMatch> {
        match self {
            Line::Match(m) => Some(m),
            _ => None,
        }
    }
}

impl fmt::Display for Line {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.original_line())
    }
}

/// Format SystemTime as local time in Python's mm/dd/YYYY HH:MM:SS format.
fn format_system_time_local(time: SystemTime) -> String {
    let duration = time
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default();
    let total_secs = duration.as_secs() as i64;

    // Get local timezone offset (approximate: use libc on Unix)
    let local_secs = total_secs + get_utc_offset(total_secs);

    let days_since_epoch = local_secs / 86400;
    let time_of_day = local_secs.rem_euclid(86400);
    let hours = time_of_day / 3600;
    let mins = (time_of_day % 3600) / 60;
    let secs = time_of_day % 60;

    let mut year = 1970i64;
    let mut remaining_days = days_since_epoch;
    loop {
        let days_in_year = if is_leap_year(year) { 366 } else { 365 };
        if remaining_days < days_in_year {
            break;
        }
        remaining_days -= days_in_year;
        year += 1;
    }
    let month_days = if is_leap_year(year) {
        [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    } else {
        [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    };
    let mut month = 1u32;
    for &md in &month_days {
        if remaining_days < md {
            break;
        }
        remaining_days -= md;
        month += 1;
    }
    let day = remaining_days + 1;

    // Python format: %m/%d/%Y %H:%M:%S
    format!("{month:02}/{day:02}/{year} {hours:02}:{mins:02}:{secs:02}")
}

/// Get UTC offset in seconds for a given Unix timestamp.
#[cfg(unix)]
fn get_utc_offset(unix_time: i64) -> i64 {
    use std::mem::MaybeUninit;
    unsafe {
        let mut tm = MaybeUninit::zeroed().assume_init();
        libc::localtime_r(&unix_time, &mut tm);
        tm.tm_gmtoff
    }
}

#[cfg(not(unix))]
fn get_utc_offset(_unix_time: i64) -> i64 {
    0
}

fn is_leap_year(year: i64) -> bool {
    (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
}

/// Format size like Python: "size: 42K" (integer division, single-letter suffix)
fn format_size_python(bytes: u64) -> String {
    let mut size = bytes;
    for unit in ["B", "K", "M", "G", "T", "P", "E", "Z"] {
        if size < 1024 {
            return format!("{size}{unit}");
        }
        size /= 1024;
    }
    format!("{size}Y")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_line_match(path: &str) -> LineMatch {
        LineMatch::new(FormattedText::new(path), path.to_string(), 0, path.to_string(), 0, path.len())
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
        assert!(result.contains('/'), "Should contain date separator: {result}");
        assert!(result.contains(':'), "Should contain time separator: {result}");
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
}

/// Get username from uid (Unix only)
#[cfg(unix)]
fn get_username(uid: u32) -> Option<String> {
    unsafe {
        let pw = libc::getpwuid(uid);
        if pw.is_null() {
            return None;
        }
        let name = std::ffi::CStr::from_ptr((*pw).pw_name);
        Some(name.to_string_lossy().into_owned())
    }
}

/// Get group name from gid (Unix only)
#[cfg(unix)]
fn get_groupname(gid: u32) -> Option<String> {
    unsafe {
        let gr = libc::getgrgid(gid);
        if gr.is_null() {
            return None;
        }
        let name = std::ffi::CStr::from_ptr((*gr).gr_name);
        Some(name.to_string_lossy().into_owned())
    }
}
