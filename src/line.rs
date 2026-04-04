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
    #[allow(dead_code)]
    pub index: usize,
    pub selected: bool,
    #[allow(dead_code)]
    pub hovered: bool,
    original_line: String,
}

/// Represents a line that did not match any file path.
#[derive(Debug, Clone)]
pub struct SimpleLine {
    pub formatted_text: FormattedText,
    #[allow(dead_code)]
    pub index: usize,
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
        index: usize,
        original_line: String,
    ) -> Self {
        Self {
            formatted_text,
            path,
            line_num,
            index,
            selected: false,
            hovered: false,
            original_line,
        }
    }

    pub fn get_path(&self) -> &str {
        &self.path
    }

    pub fn get_line_num(&self) -> u64 {
        self.line_num
    }

    pub fn get_dir(&self) -> String {
        let resolved = parse::prepend_dir(&self.path, false);
        Path::new(&resolved)
            .parent()
            .map_or(resolved.clone(), |p| p.to_string_lossy().to_string())
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

    /// Get file description metadata for the sidebar display.
    pub fn get_file_description(&self) -> Vec<String> {
        let resolved = parse::prepend_dir(&self.path, true);
        let path = Path::new(&resolved);

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

        // Last accessed time
        if let Ok(accessed) = metadata.accessed() {
            desc.push(format!("Last accessed: {}", format_system_time(accessed)));
        }

        // Last modified time
        if let Ok(modified) = metadata.modified() {
            desc.push(format!("Last modified: {}", format_system_time(modified)));
        }

        // Owner user/group (Unix only)
        #[cfg(unix)]
        {
            let uid = metadata.uid();
            desc.push(format!("Owner: {uid}"));
            let gid = metadata.gid();
            desc.push(format!("Group: {gid}"));
        }

        // File size
        let size = metadata.len();
        desc.push(format!("Size: {}", format_size(size)));

        // Line count (read directly instead of spawning wc)
        if let Ok(file) = File::open(&resolved) {
            let line_count = BufReader::new(file).lines().count();
            desc.push(format!("Lines: {line_count}"));
        }

        desc
    }
}

impl SimpleLine {
    pub fn new(formatted_text: FormattedText, index: usize, original_line: String) -> Self {
        Self {
            formatted_text,
            index,
            original_line,
        }
    }
}

impl Line {
    #[allow(dead_code)]
    pub fn index(&self) -> usize {
        match self {
            Line::Match(m) => m.index,
            Line::Simple(s) => s.index,
        }
    }

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

fn format_system_time(time: SystemTime) -> String {
    let duration = time
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default();
    let total_secs = duration.as_secs() as i64;

    // Calculate date/time components from Unix timestamp
    let days_since_epoch = total_secs / 86400;
    let time_of_day = total_secs % 86400;
    let hours = time_of_day / 3600;
    let mins = (time_of_day % 3600) / 60;
    let secs = time_of_day % 60;

    // Simple date calculation (good enough for display purposes)
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

    format!("{year}-{month:02}-{day:02} {hours:02}:{mins:02}:{secs:02} UTC")
}

fn is_leap_year(year: i64) -> bool {
    (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
}

fn format_size(bytes: u64) -> String {
    if bytes < 1024 {
        format!("{bytes} B")
    } else if bytes < 1024 * 1024 {
        format!("{:.1} KB", bytes as f64 / 1024.0)
    } else if bytes < 1024 * 1024 * 1024 {
        format!("{:.1} MB", bytes as f64 / (1024.0 * 1024.0))
    } else {
        format!("{:.1} GB", bytes as f64 / (1024.0 * 1024.0 * 1024.0))
    }
}
