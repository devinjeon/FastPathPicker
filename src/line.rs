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
/// Uses `localtime_r` to convert Unix timestamps to local calendar components,
/// avoiding error-prone manual calendar arithmetic.
fn format_system_time_local(time: SystemTime) -> String {
    let duration = time
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default();
    let total_secs = i64::try_from(duration.as_secs()).unwrap_or(0);

    let (year, month, day, hours, mins, secs) = get_local_time_components(total_secs);

    // Python format: %m/%d/%Y %H:%M:%S
    format!("{month:02}/{day:02}/{year} {hours:02}:{mins:02}:{secs:02}")
}

/// Convert a Unix timestamp to local time components (year, month, day, hour, min, sec).
#[cfg(unix)]
fn get_local_time_components(unix_time: i64) -> (i32, u32, u32, u32, u32, u32) {
    use std::mem::MaybeUninit;
    unsafe {
        let mut tm = MaybeUninit::zeroed();
        let result = libc::localtime_r(&unix_time, tm.as_mut_ptr());
        if result.is_null() {
            // localtime_r failed; fall back to epoch display.
            return (1970, 1, 1, 0, 0, 0);
        }
        // SAFETY: localtime_r returned non-NULL, so the tm struct is fully initialized.
        let tm = tm.assume_init();
        (
            tm.tm_year + 1900,      // tm_year is years since 1900
            (tm.tm_mon + 1) as u32, // tm_mon is 0-based
            tm.tm_mday as u32,
            tm.tm_hour as u32,
            tm.tm_min as u32,
            tm.tm_sec as u32,
        )
    }
}

#[cfg(not(unix))]
fn get_local_time_components(unix_time: i64) -> (i32, u32, u32, u32, u32, u32) {
    // Non-Unix: fall back to UTC calculation.
    if unix_time < 0 {
        return (1970, 1, 1, 0, 0, 0);
    }
    let time_of_day = unix_time.rem_euclid(86400);
    let hours = (time_of_day / 3600) as u32;
    let mins = ((time_of_day % 3600) / 60) as u32;
    let secs = (time_of_day % 60) as u32;
    let mut days = unix_time / 86400;
    let mut year = 1970i32;
    loop {
        let dy = if is_leap_year(year) { 366 } else { 365 };
        if days < dy {
            break;
        }
        days -= dy;
        year += 1;
    }
    let month_days = if is_leap_year(year) {
        [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    } else {
        [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    };
    let mut month = 1u32;
    for &md in &month_days {
        if days < md {
            break;
        }
        days -= md;
        month += 1;
    }
    (year, month, (days + 1) as u32, hours, mins, secs)
}

#[cfg(any(not(unix), test))]
fn is_leap_year(year: i32) -> bool {
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
#[path = "line_tests.rs"]
mod tests;

/// Maximum buffer size for getpwuid_r/getgrgid_r to prevent unbounded growth.
#[cfg(unix)]
const LOOKUP_BUF_MAX: usize = 1 << 20; // 1 MB

/// Get username from uid (Unix only) using the reentrant `getpwuid_r`.
#[cfg(unix)]
fn get_username(uid: u32) -> Option<String> {
    let mut buf = vec![0u8; 1024];
    let mut pwd: libc::passwd = unsafe { std::mem::zeroed() };
    let mut result: *mut libc::passwd = std::ptr::null_mut();

    loop {
        // SAFETY: getpwuid_r is thread-safe (reentrant). We provide a buffer for
        // the function to write into, avoiding the static storage issue of getpwuid.
        let ret = unsafe {
            libc::getpwuid_r(
                uid,
                &mut pwd,
                buf.as_mut_ptr() as *mut libc::c_char,
                buf.len(),
                &mut result,
            )
        };
        if ret == libc::ERANGE {
            if buf.len() >= LOOKUP_BUF_MAX {
                return None;
            }
            buf.resize(buf.len() * 2, 0);
            result = std::ptr::null_mut();
            continue;
        }
        break;
    }

    if result.is_null() {
        return None;
    }
    // SAFETY: result is non-null and points to pwd which is backed by buf.
    let name = unsafe { std::ffi::CStr::from_ptr(pwd.pw_name) };
    Some(name.to_string_lossy().into_owned())
}

/// Get group name from gid (Unix only) using the reentrant `getgrgid_r`.
#[cfg(unix)]
fn get_groupname(gid: u32) -> Option<String> {
    let mut buf = vec![0u8; 1024];
    let mut grp: libc::group = unsafe { std::mem::zeroed() };
    let mut result: *mut libc::group = std::ptr::null_mut();

    loop {
        // SAFETY: getgrgid_r is thread-safe (reentrant). We provide a buffer for
        // the function to write into, avoiding the static storage issue of getgrgid.
        let ret = unsafe {
            libc::getgrgid_r(
                gid,
                &mut grp,
                buf.as_mut_ptr() as *mut libc::c_char,
                buf.len(),
                &mut result,
            )
        };
        if ret == libc::ERANGE {
            if buf.len() >= LOOKUP_BUF_MAX {
                return None;
            }
            buf.resize(buf.len() * 2, 0);
            result = std::ptr::null_mut();
            continue;
        }
        break;
    }

    if result.is_null() {
        return None;
    }
    // SAFETY: result is non-null and points to grp which is backed by buf.
    let name = unsafe { std::ffi::CStr::from_ptr(grp.gr_name) };
    Some(name.to_string_lossy().into_owned())
}
