use std::env;
use std::path::Path;
use std::process::Command;

use std::sync::LazyLock;

use regex::Regex;

/// Result of matching a line: (file_path, line_number, match_start, match_end)
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MatchResult {
    pub path: String,
    pub line_num: u64,
    /// Start position of the match within the line (character index)
    pub match_start: usize,
    /// End position of the match within the line (character index)
    pub match_end: usize,
}

/// Configuration for each regex in the waterfall.
struct RegexConfig {
    regex: &'static LazyLock<Regex>,
    preferred_regex: Option<&'static LazyLock<Regex>>,
    num_index: usize,
    no_num: bool,
    only_with_file_inspection: bool,
    with_all_lines_matched: bool,
}

// --- Regex Definitions ---
// These match the original Python patterns exactly.

static MASTER_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(/?([a-z.A-Z0-9\-_]+/)+[@a-zA-Z0-9\-_+.]+\.[a-zA-Z0-9]{1,10})[:\-]?(\d+)?")
        .unwrap()
});

static MASTER_REGEX_MORE_EXTENSIONS: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(/?([a-z.A-Z0-9\-_]+/)+[@a-zA-Z0-9\-_+.]+\.[a-zA-Z0-9\-~]{1,30})[:\-]?(\d+)?")
        .unwrap()
});

static HOMEDIR_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(~/([a-z.A-Z0-9\-_]+/)+[@a-zA-Z0-9\-_+.]+\.[a-zA-Z0-9]{1,10})[:\-]?(\d+)?")
        .unwrap()
});

static OTHER_BGS_RESULT_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(/?([a-z.A-Z0-9\-_]+/)+[a-zA-Z0-9_.]{3,})[:\-]?(\d+)").unwrap());

static ENTIRE_TRIMMED_LINE_IF_NOT_WHITESPACE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(\S.*\S|\S)").unwrap());

static JUST_FILE_WITH_NUMBER: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"([@%+a-z.A-Z0-9\-_]+\.[a-zA-Z]{1,10})[:\-](\d+)(\s|$|:)+").unwrap()
});

static JUST_FILE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"([@%+a-z.A-Z0-9\-_]+\.[a-zA-Z]{1,10})(\s|$|:)+").unwrap());

static JUST_EMACS_TEMP_FILE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"([@%+a-z.A-Z0-9\-_]+\.[a-zA-Z]{1,10}~)(\s|$|:)+").unwrap());

static JUST_VIM_TEMP_FILE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(#[@%+a-z.A-Z0-9\-_]+\.[a-zA-Z]{1,10}#)(\s|$|:)+").unwrap());

static JUST_FILE_WITH_SPACES: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"([a-zA-Z][@+a-z. A-Z0-9\-_]+\.[a-zA-Z]{1,10})(\s|$|:)+").unwrap()
});

static FILE_NO_PERIODS: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(((/?([a-z.A-Z0-9\-_]+/))?\.[a-zA-Z0-9\-_]{3,}[a-zA-Z0-9\-_/]*)|([a-z.A-Z0-9\-_/]+/[a-zA-Z0-9\-_]+)|([A-Z][a-zA-Z]{2,}file))(\s|$|:)+",
    )
    .unwrap()
});

static MASTER_REGEX_WITH_SPACES: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"((?:\.?/)?(([a-z.A-Z0-9\-_]|\s[a-zA-Z0-9\-_])+/)+(([(),%@a-zA-Z0-9\-_+.]|\s[,()@%a-zA-Z0-9\-_+.])+)\.[a-zA-Z0-9\-]{1,30})[:\-]?(\d+)?",
    )
    .unwrap()
});

static MASTER_REGEX_WITH_SPACES_AND_WEIRD_FILES: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"((?:\.?/)?(([a-z.A-Z0-9\-_]|\s[a-zA-Z0-9\-_])+/)+((/?([a-z.A-Z0-9\-_]+/))?\.[a-zA-Z0-9\-_]{3,}[a-zA-Z0-9\-_/]*)|([a-z.A-Z0-9\-_/]+/[a-zA-Z0-9\-_]+)|([A-Z][a-zA-Z]{2,}file))",
    )
    .unwrap()
});

// --- Regex Waterfall ---

static REGEX_WATERFALL: LazyLock<Vec<RegexConfig>> = LazyLock::new(|| {
    vec![
        RegexConfig {
            regex: &HOMEDIR_REGEX,
            preferred_regex: None,
            num_index: 2,
            no_num: false,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            regex: &MASTER_REGEX,
            preferred_regex: Some(&OTHER_BGS_RESULT_REGEX),
            num_index: 2,
            no_num: false,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            regex: &OTHER_BGS_RESULT_REGEX,
            preferred_regex: None,
            num_index: 2,
            no_num: false,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            regex: &MASTER_REGEX_MORE_EXTENSIONS,
            preferred_regex: None,
            num_index: 2,
            no_num: false,
            only_with_file_inspection: true,
            with_all_lines_matched: false,
        },
        RegexConfig {
            regex: &MASTER_REGEX_WITH_SPACES,
            preferred_regex: None,
            num_index: 5, // adjusted for Rust regex capture group numbering
            no_num: false,
            only_with_file_inspection: true,
            with_all_lines_matched: false,
        },
        RegexConfig {
            regex: &MASTER_REGEX_WITH_SPACES_AND_WEIRD_FILES,
            preferred_regex: None,
            num_index: 5, // adjusted for Rust regex capture group numbering
            no_num: false,
            only_with_file_inspection: true,
            with_all_lines_matched: false,
        },
        RegexConfig {
            regex: &JUST_VIM_TEMP_FILE,
            preferred_regex: None,
            num_index: 2,
            no_num: true,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            regex: &JUST_EMACS_TEMP_FILE,
            preferred_regex: None,
            num_index: 2,
            no_num: true,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            regex: &JUST_FILE_WITH_NUMBER,
            preferred_regex: None,
            num_index: 1,
            no_num: false,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            regex: &JUST_FILE,
            preferred_regex: None,
            num_index: 2,
            no_num: true,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            regex: &JUST_FILE_WITH_SPACES,
            preferred_regex: None,
            num_index: 2,
            no_num: true,
            only_with_file_inspection: true,
            with_all_lines_matched: false,
        },
        RegexConfig {
            regex: &FILE_NO_PERIODS,
            preferred_regex: None,
            num_index: 2,
            no_num: true,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            regex: &ENTIRE_TRIMMED_LINE_IF_NOT_WHITESPACE,
            preferred_regex: None,
            num_index: 2,
            no_num: true,
            only_with_file_inspection: false,
            with_all_lines_matched: true,
        },
    ]
});

// --- Repository Path Detection ---

/// Detect the repository root via git or hg, falling back to "./"
pub fn get_repo_path() -> String {
    if let Ok(output) = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        if output.status.success() {
            let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !path.is_empty() {
                return path;
            }
        }
    }

    if let Ok(output) = Command::new("hg").arg("root").output() {
        if output.status.success() {
            let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !path.is_empty() {
                return path;
            }
        }
    }

    ".".to_string()
}

static PREPEND_PATH: LazyLock<String> = LazyLock::new(|| {
    let repo = get_repo_path();
    format!("{}/", repo.trim_end_matches('/'))
});

// --- Matching ---

fn unpack_match(captures: &regex::Captures, num_index: usize, no_num: bool) -> MatchResult {
    let path = captures.get(1).map_or("", |m| m.as_str()).to_string();
    let line_num = if no_num {
        0
    } else {
        captures
            .get(num_index + 1) // +1 because Python's groups()[idx] maps to captures.get(idx+1)
            .and_then(|m| m.as_str().parse::<u64>().ok())
            .unwrap_or(0)
    };
    // Store match position (from group 0 = full match)
    let full_match = captures.get(0).unwrap();
    let match_start = full_match.start();
    let mut match_end = full_match.end();
    // Python strips trailing whitespace from the match group
    let matched_str = &full_match.as_str();
    let stripped = matched_str.trim_end();
    match_end -= matched_str.len() - stripped.len();
    MatchResult {
        path,
        line_num,
        match_start,
        match_end,
    }
}

/// Internal implementation: collect all regex matches for a line.
fn match_line_impl(
    line: &str,
    with_file_inspection: bool,
    with_all_lines_matched: bool,
) -> Vec<MatchResult> {
    let mut results = Vec::new();

    for config in REGEX_WATERFALL.iter() {
        if config.with_all_lines_matched != with_all_lines_matched {
            continue;
        }
        if config.only_with_file_inspection && !with_file_inspection {
            continue;
        }

        let Some(captures) = config.regex.captures(line) else {
            continue;
        };

        if let Some(preferred) = config.preferred_regex {
            let preferred_regex: &Regex = preferred;
            if let Some(preferred_captures) = preferred_regex.captures(line) {
                let main_start = captures.get(0).map_or(0, |m| m.start());
                let pref_start = preferred_captures.get(0).map_or(0, |m| m.start());
                if pref_start < main_start {
                    results.push(unpack_match(
                        &preferred_captures,
                        config.num_index,
                        config.no_num,
                    ));
                    continue;
                }
            }
        }

        results.push(unpack_match(&captures, config.num_index, config.no_num));
    }

    results
}

/// Match a line against the regex waterfall, optionally validating file existence.
pub fn match_line(line: &str, validate_file_exists: bool, all_input: bool) -> Option<MatchResult> {
    if !validate_file_exists {
        let results = match_line_impl(line, false, all_input);
        return results.into_iter().next();
    }

    let results = match_line_impl(line, true, all_input);
    for result in results {
        let resolved = prepend_dir(&result.path, true);
        if Path::new(&resolved).is_file() || result.path.starts_with(".../") {
            return Some(result);
        }
    }
    None
}

/// Resolve a file path to an absolute or resolvable form.
pub fn prepend_dir(file: &str, with_file_inspection: bool) -> String {
    if file.is_empty() || file.len() < 2 {
        return file.to_string();
    }

    if file.starts_with('/') {
        return file.to_string();
    }

    if file.starts_with(".../") {
        return file.to_string();
    }

    if file.starts_with("~/") {
        return expand_home(file);
    }

    if file.starts_with("./") || file.starts_with("../") {
        return file.to_string();
    }

    let first = file.split('/').next().unwrap_or("");

    if first == "home"
        && env::var("FPP_DISABLE_PREPENDING_HOME_WITH_SLASH")
            .ok()
            .filter(|v| !v.is_empty())
            .is_none()
    {
        return format!("/{file}");
    }

    let repos = get_repos();
    if repos.contains(&first.to_string()) {
        return expand_home(&format!("~/{file}"));
    }

    if !file.contains('/') {
        return format!("./{file}");
    }

    // Handle git diff a/ and b/ prefixes
    if file.starts_with("a/") || file.starts_with("b/") {
        return format!("{}{}", *PREPEND_PATH, &file[2..]);
    }

    let parts: Vec<&str> = file.split('/').collect();
    if parts[0] == "www" {
        return format!("{}{}", *PREPEND_PATH, parts[1..].join("/"));
    }

    if !with_file_inspection {
        return format!("{}{}", *PREPEND_PATH, file);
    }

    let top_level = format!("{}{}", *PREPEND_PATH, file);
    let relative = format!("./{file}");
    if !Path::new(&top_level).is_file() && Path::new(&relative).is_file() {
        return relative;
    }
    top_level
}

/// Check if a path is resolvable (not a git abbreviated path).
pub fn is_resolvable(path: &str) -> bool {
    !path.starts_with(".../")
}

/// Check if a path is a git abbreviated path.
pub fn is_git_abbreviated_path(path: &str) -> bool {
    path.starts_with("...")
}

// --- Helpers ---

fn expand_home(path: &str) -> String {
    if let Some(home) = dirs::home_dir() {
        path.replacen("~", &home.to_string_lossy(), 1)
    } else {
        path.to_string()
    }
}

fn get_repos() -> &'static Vec<String> {
    static REPOS: LazyLock<Vec<String>> = LazyLock::new(|| {
        let mut repos = vec![
            "www".to_string(),
            "configerator".to_string(),
            "fbcode".to_string(),
            "configerator-dsi".to_string(),
        ];
        if let Ok(extra) = env::var("FPP_REPOS") {
            for r in extra.split(',') {
                let trimmed = r.trim().to_string();
                if !trimmed.is_empty() {
                    repos.push(trimmed);
                }
            }
        }
        repos
    });
    &REPOS
}

#[cfg(test)]
#[path = "parse_tests.rs"]
mod tests;
