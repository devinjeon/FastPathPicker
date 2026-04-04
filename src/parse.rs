use std::env;
use std::path::Path;
use std::process::Command;

use std::sync::LazyLock;

use regex::Regex;

/// Result of matching a line: (file_path, line_number)
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MatchResult {
    pub path: String,
    pub line_num: u64,
}

/// Configuration for each regex in the waterfall.
struct RegexConfig {
    #[allow(dead_code)]
    name: &'static str,
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
            name: "HOMEDIR_REGEX",
            regex: &HOMEDIR_REGEX,
            preferred_regex: None,
            num_index: 2,
            no_num: false,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            name: "MASTER_REGEX",
            regex: &MASTER_REGEX,
            preferred_regex: Some(&OTHER_BGS_RESULT_REGEX),
            num_index: 2,
            no_num: false,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            name: "OTHER_BGS_RESULT_REGEX",
            regex: &OTHER_BGS_RESULT_REGEX,
            preferred_regex: None,
            num_index: 2,
            no_num: false,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            name: "MASTER_REGEX_MORE_EXTENSIONS",
            regex: &MASTER_REGEX_MORE_EXTENSIONS,
            preferred_regex: None,
            num_index: 2,
            no_num: false,
            only_with_file_inspection: true,
            with_all_lines_matched: false,
        },
        RegexConfig {
            name: "MASTER_REGEX_WITH_SPACES",
            regex: &MASTER_REGEX_WITH_SPACES,
            preferred_regex: None,
            num_index: 5, // adjusted for Rust regex capture group numbering
            no_num: false,
            only_with_file_inspection: true,
            with_all_lines_matched: false,
        },
        RegexConfig {
            name: "MASTER_REGEX_WITH_SPACES_AND_WEIRD_FILES",
            regex: &MASTER_REGEX_WITH_SPACES_AND_WEIRD_FILES,
            preferred_regex: None,
            num_index: 5, // adjusted for Rust regex capture group numbering
            no_num: true,
            only_with_file_inspection: true,
            with_all_lines_matched: false,
        },
        RegexConfig {
            name: "JUST_VIM_TEMP_FILE",
            regex: &JUST_VIM_TEMP_FILE,
            preferred_regex: None,
            num_index: 2,
            no_num: true,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            name: "JUST_EMACS_TEMP_FILE",
            regex: &JUST_EMACS_TEMP_FILE,
            preferred_regex: None,
            num_index: 2,
            no_num: true,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            name: "JUST_FILE_WITH_NUMBER",
            regex: &JUST_FILE_WITH_NUMBER,
            preferred_regex: None,
            num_index: 1,
            no_num: false,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            name: "JUST_FILE",
            regex: &JUST_FILE,
            preferred_regex: None,
            num_index: 2,
            no_num: true,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            name: "JUST_FILE_WITH_SPACES",
            regex: &JUST_FILE_WITH_SPACES,
            preferred_regex: None,
            num_index: 2,
            no_num: true,
            only_with_file_inspection: true,
            with_all_lines_matched: false,
        },
        RegexConfig {
            name: "FILE_NO_PERIODS",
            regex: &FILE_NO_PERIODS,
            preferred_regex: None,
            num_index: 2,
            no_num: true,
            only_with_file_inspection: false,
            with_all_lines_matched: false,
        },
        RegexConfig {
            name: "ENTIRE_TRIMMED_LINE_IF_NOT_WHITESPACE",
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
    MatchResult { path, line_num }
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

    if first == "home" && env::var("FPP_DISABLE_PREPENDING_HOME_WITH_SLASH").is_err() {
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

fn get_repos() -> Vec<String> {
    let mut repos = vec![
        "www".to_string(),
        "fbcode".to_string(),
        "configerator".to_string(),
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
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── Existing basic tests ──────────────────────────────────────────

    #[test]
    fn test_basic_path_match() {
        let result = match_line("html/js/hotness.js", false, false);
        assert!(result.is_some());
        assert_eq!(result.unwrap().path, "html/js/hotness.js");
    }

    #[test]
    fn test_path_with_line_number() {
        let result = match_line("html/js/hotness.js:22", false, false);
        assert!(result.is_some());
        let r = result.unwrap();
        assert_eq!(r.path, "html/js/hotness.js");
        assert_eq!(r.line_num, 22);
    }

    #[test]
    fn test_homedir_path() {
        let result = match_line("~/foo/bar/something.py", false, false);
        assert!(result.is_some());
        assert_eq!(result.unwrap().path, "~/foo/bar/something.py");
    }

    #[test]
    fn test_no_match_plain_text() {
        let result = match_line("just some random text", false, false);
        assert!(result.is_none());
    }

    #[test]
    fn test_all_input_mode() {
        let result = match_line("any random text here", false, true);
        assert!(result.is_some());
        assert_eq!(result.unwrap().path, "any random text here");
    }

    #[test]
    fn test_prepend_dir_absolute() {
        assert_eq!(prepend_dir("/absolute/path", false), "/absolute/path");
    }

    #[test]
    fn test_prepend_dir_relative() {
        assert_eq!(prepend_dir("./relative/path", false), "./relative/path");
    }

    #[test]
    fn test_prepend_dir_git_abbreviated() {
        assert_eq!(prepend_dir(".../some/path", false), ".../some/path");
    }

    #[test]
    fn test_is_resolvable() {
        assert!(is_resolvable("some/path.txt"));
        assert!(!is_resolvable(".../abbreviated/path"));
    }

    // ── Data-driven test infrastructure ───────────────────────────────

    struct TestCase {
        input: &'static str,
        should_match: bool,
        expected_file: Option<&'static str>,
        expected_num: u64,
        disable_fuzz_test: bool,
    }

    impl TestCase {
        const fn new(input: &'static str, should_match: bool) -> Self {
            Self {
                input,
                should_match,
                expected_file: None,
                expected_num: 0,
                disable_fuzz_test: false,
            }
        }

        const fn file(mut self, f: &'static str) -> Self {
            self.expected_file = Some(f);
            self
        }

        const fn num(mut self, n: u64) -> Self {
            self.expected_num = n;
            self
        }

        const fn no_fuzz(mut self) -> Self {
            self.disable_fuzz_test = true;
            self
        }
    }

    // ── FILE_TEST_CASES with validate_file_exists=False ───────────────
    // (skipping cases that need actual filesystem files)

    fn file_test_cases() -> Vec<TestCase> {
        vec![
            TestCase::new("html/js/hotness.js", true).file("html/js/hotness.js"),
            TestCase::new("/absolute/path/to/something.txt", true)
                .file("/absolute/path/to/something.txt"),
            TestCase::new("/html/js/hotness.js42", true).file("/html/js/hotness.js42"),
            TestCase::new("/html/js/hotness.js", true).file("/html/js/hotness.js"),
            TestCase::new("./asd.txt:83", true)
                .file("./asd.txt")
                .num(83),
            TestCase::new(".env.local", true).file(".env.local"),
            TestCase::new(".gitignore", true).file(".gitignore"),
            TestCase::new("tmp/.gitignore", true).file("tmp/.gitignore"),
            TestCase::new(".ssh/.gitignore", true).file(".ssh/.gitignore"),
            TestCase::new(".ssh/known_hosts", true).file(".ssh/known_hosts"),
            TestCase::new(".a", false),
            TestCase::new("flib/asd/ent/berkeley/two.py-22", true)
                .file("flib/asd/ent/berkeley/two.py")
                .num(22),
            TestCase::new("flib/foo/bar", true).file("flib/foo/bar"),
            TestCase::new("flib/foo/bar ", true).file("flib/foo/bar"),
            TestCase::new("foo/b ", true).file("foo/b"),
            TestCase::new("foo/bar/baz/", false),
            TestCase::new("flib/ads/ads.thrift", true).file("flib/ads/ads.thrift"),
            TestCase::new("banana hanana Wilde/ads/story.m", true).file("Wilde/ads/story.m"),
            TestCase::new("flib/asd/asd.py two/three/four.py", true).file("flib/asd/asd.py"),
            TestCase::new("asd/asd/asd/ 23", false),
            TestCase::new("foo/bar/TARGETS:23", true)
                .file("foo/bar/TARGETS")
                .num(23),
            TestCase::new("foo/bar/TARGETS-24", true)
                .file("foo/bar/TARGETS")
                .num(24),
            TestCase::new(
                "fbcode/search/places/scorer/PageScorer.cpp:27:46:\
                 #include \"search/places/scorer/linear_scores/MinutiaeVerbScorer.h",
                true,
            )
            .file("fbcode/search/places/scorer/PageScorer.cpp")
            .num(27),
            TestCase::new(
                "(fbcode/search/places/scorer/PageScorer.cpp:27:46):\
                 #include \"search/places/scorer/linear_scores/MinutiaeVerbScorer.h",
                true,
            )
            .file("fbcode/search/places/scorer/PageScorer.cpp")
            .num(27),
            TestCase::new(
                "fbcode/search/places/scorer/TARGETS:590:28:\
                     srcs = [\"linear_scores/MinutiaeVerbScorer.cpp\"]",
                true,
            )
            .file("fbcode/search/places/scorer/TARGETS")
            .num(590),
            TestCase::new(
                "fbcode/search/places/scorer/TARGETS:1083:27:\
                       \"linear_scores/test/MinutiaeVerbScorerTest.cpp\"",
                true,
            )
            .file("fbcode/search/places/scorer/TARGETS")
            .num(1083),
            TestCase::new("~/foo/bar/something.py", true).file("~/foo/bar/something.py"),
            TestCase::new("~/foo/bar/inHomeDir.py:22", true)
                .file("~/foo/bar/inHomeDir.py")
                .num(22),
            TestCase::new("blarge assets/retina/victory@2x.png", true)
                .file("assets/retina/victory@2x.png"),
            TestCase::new("~/assets/retina/victory@2x.png", true)
                .file("~/assets/retina/victory@2x.png"),
            TestCase::new("So.many.periods.txt", true).file("So.many.periods.txt"),
            TestCase::new("So.many.periods.txt~", true).file("So.many.periods.txt~"),
            TestCase::new("#So.many.periods.txt#", true).file("#So.many.periods.txt#"),
            TestCase::new("SO.MANY.PERIODS.TXT", true).file("SO.MANY.PERIODS.TXT"),
            TestCase::new("blarg blah So.MANY.PERIODS.TXT:22", true)
                .file("So.MANY.PERIODS.TXT")
                .num(22),
            TestCase::new("SO.MANY&&PERIODSTXT", false),
            TestCase::new("test src/categories/NSDate+Category.h", true)
                .file("src/categories/NSDate+Category.h"),
            TestCase::new("~/src/categories/NSDate+Category.h", true)
                .file("~/src/categories/NSDate+Category.h"),
            // files with + in them
            TestCase::new("M     ./objectivec/NSArray+Utils.h", true)
                .file("./objectivec/NSArray+Utils.h"),
            TestCase::new("NSArray+Utils.h", true).file("NSArray+Utils.h"),
            TestCase::new("Gemfile", true).file("Gemfile").no_fuzz(),
            TestCase::new("Gemfilenope", false).no_fuzz(),
        ]
    }

    // ── test_file_match ───────────────────────────────────────────────

    #[test]
    fn test_file_match() {
        let cases = file_test_cases();
        for tc in &cases {
            let result = match_line(tc.input, false, false);
            if !tc.should_match {
                assert!(
                    result.is_none(),
                    "Line {:?} should NOT match but did: {:?}",
                    tc.input,
                    result,
                );
                continue;
            }
            let r = result.unwrap_or_else(|| {
                panic!("Line {:?} did not match any regex", tc.input);
            });
            if let Some(expected_file) = tc.expected_file {
                assert_eq!(
                    r.path, expected_file,
                    "files not equal for {:?}: got {:?}",
                    tc.input, r.path,
                );
            }
            assert_eq!(
                r.line_num, tc.expected_num,
                "num not equal for {:?}: expected {} got {}",
                tc.input, tc.expected_num, r.line_num,
            );
        }
    }

    // ── test_file_fuzz ────────────────────────────────────────────────

    #[test]
    fn test_file_fuzz() {
        let cases = file_test_cases();
        let befores = [
            "M ",
            "Modified: ",
            "Changed: ",
            "+++ ",
            "Banana asdasdoj pjo ",
        ];
        let afters = [
            " * Adapts AdsErrorCodestore to something",
            ":0:7: var AdsErrorCodeStore",
            " jkk asdad",
        ];

        for tc in &cases {
            if tc.disable_fuzz_test {
                continue;
            }
            for before in &befores {
                for after in &afters {
                    let fuzzed = format!("{}{}{}", before, tc.input, after);
                    let result = match_line(&fuzzed, false, false);
                    if tc.should_match {
                        let r = result.unwrap_or_else(|| {
                            panic!("Fuzzed line {:?} did not match any regex", fuzzed);
                        });
                        if let Some(expected_file) = tc.expected_file {
                            assert_eq!(
                                r.path, expected_file,
                                "fuzz file mismatch for {:?}: got {:?}",
                                fuzzed, r.path,
                            );
                        }
                    }
                    // non-matching cases may match with fuzz context, that is fine
                }
            }
        }
    }

    // ── test_prepend_dir (ported from PREPEND_DIR_TEST_CASES) ─────────

    #[test]
    fn test_prepend_dir_cases() {
        // "home/absolute/path.py" -> "/home/absolute/path.py"
        assert_eq!(
            prepend_dir("home/absolute/path.py", false),
            "/home/absolute/path.py",
        );

        // "~/www/asd.py" -> expands ~ to home dir
        let home = dirs::home_dir().unwrap();
        let home_str = home.to_string_lossy();
        assert_eq!(
            prepend_dir("~/www/asd.py", false),
            format!("{}/www/asd.py", home_str),
        );

        // empty string
        assert_eq!(prepend_dir("", false), "");
    }

    // ── test_all_input (ported from ALL_INPUT_TEST_CASES) ─────────────

    struct AllInputTestCase {
        input: &'static str,
        expected: Option<&'static str>,
    }

    #[test]
    fn test_all_input_cases() {
        let cases = vec![
            AllInputTestCase {
                input: "    ",
                expected: None,
            },
            AllInputTestCase {
                input: " ",
                expected: None,
            },
            AllInputTestCase {
                input: "a",
                expected: Some("a"),
            },
            AllInputTestCase {
                input: "   a",
                expected: Some("a"),
            },
            AllInputTestCase {
                input: "a    ",
                expected: Some("a"),
            },
            AllInputTestCase {
                input: "    foo bar",
                expected: Some("foo bar"),
            },
            AllInputTestCase {
                input: "foo bar    ",
                expected: Some("foo bar"),
            },
            AllInputTestCase {
                input: "    foo bar    ",
                expected: Some("foo bar"),
            },
            AllInputTestCase {
                input: "foo bar baz",
                expected: Some("foo bar baz"),
            },
            AllInputTestCase {
                input: "\tmodified:   Classes/Media/YPMediaLibraryViewController.m",
                expected: Some("modified:   Classes/Media/YPMediaLibraryViewController.m"),
            },
            AllInputTestCase {
                input: "no changes added to commit (use \"git add\" and/or \"git commit -a\")",
                expected: Some(
                    "no changes added to commit (use \"git add\" and/or \"git commit -a\")",
                ),
            },
        ];

        for tc in &cases {
            let result = match_line(tc.input, false, true);
            match tc.expected {
                None => {
                    assert!(
                        result.is_none(),
                        "Expected no match for {:?}, got {:?}",
                        tc.input,
                        result,
                    );
                }
                Some(expected) => {
                    let r = result.unwrap_or_else(|| {
                        panic!("Expected match {:?} for {:?}, got None", expected, tc.input,);
                    });
                    assert_eq!(
                        r.path, expected,
                        "all_input mismatch for {:?}: got {:?}",
                        tc.input, r.path,
                    );
                }
            }
        }
    }

    // ── test_unresolvable ─────────────────────────────────────────────

    #[test]
    fn test_unresolvable() {
        let line = ".../something/foo.py";
        let result = match_line(line, false, false);
        assert!(result.is_some(), "{:?} should match", line);
        assert!(!is_resolvable(&result.unwrap().path));
    }

    // ── test_resolvable ───────────────────────────────────────────────

    #[test]
    fn test_resolvable() {
        let cases = file_test_cases();
        for tc in &cases {
            if !tc.should_match {
                continue;
            }
            let result = match_line(tc.input, false, false);
            let r = result.unwrap_or_else(|| {
                panic!("Line {:?} should be resolvable but did not match", tc.input);
            });
            assert!(
                is_resolvable(&r.path),
                "Line {:?} was not resolvable",
                tc.input,
            );
        }
    }

    // ── validate_file_exists tests ───────────────────────────────────

    struct FileExistsTestCase {
        input: &'static str,
        should_match: bool,
        expected_file: Option<&'static str>,
        expected_num: u64,
    }

    #[test]
    fn test_validate_file_exists() {
        // These tests require the fixture files in tests/inputs/
        let test_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/inputs");
        if !test_dir.exists() {
            eprintln!("Skipping validate_file_exists tests: tests/inputs/ not found");
            return;
        }

        // Change to tests/ directory so relative paths resolve
        let original_dir = std::env::current_dir().unwrap();
        std::env::set_current_dir(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests"))
            .unwrap();

        let cases = vec![
            FileExistsTestCase {
                input: "M    ./inputs/evilFile With Space.txt",
                should_match: true,
                expected_file: Some("./inputs/evilFile With Space.txt"),
                expected_num: 0,
            },
            FileExistsTestCase {
                input: "./inputs/evilFile With Space.txt:22",
                should_match: true,
                expected_file: Some("./inputs/evilFile With Space.txt"),
                expected_num: 22,
            },
            FileExistsTestCase {
                input: "./inputs/annoying Spaces Folder/evilFile With Space2.txt",
                should_match: true,
                expected_file: Some("./inputs/annoying Spaces Folder/evilFile With Space2.txt"),
                expected_num: 0,
            },
            FileExistsTestCase {
                input: "./inputs/annoying Spaces Folder/evilFile With Space2.txt:42",
                should_match: true,
                expected_file: Some("./inputs/annoying Spaces Folder/evilFile With Space2.txt"),
                expected_num: 42,
            },
            FileExistsTestCase {
                input: " ./inputs/annoying Spaces Folder/evilFile With Space2.txt:42",
                should_match: true,
                expected_file: Some("./inputs/annoying Spaces Folder/evilFile With Space2.txt"),
                expected_num: 42,
            },
            FileExistsTestCase {
                input: "M     ./inputs/annoying Spaces Folder/evilFile With Space2.txt:42",
                should_match: true,
                expected_file: Some("./inputs/annoying Spaces Folder/evilFile With Space2.txt"),
                expected_num: 42,
            },
            FileExistsTestCase {
                input: "./inputs/NSArray+Utils.h:42",
                should_match: true,
                expected_file: Some("./inputs/NSArray+Utils.h"),
                expected_num: 42,
            },
            FileExistsTestCase {
                input: "./inputs/blogredesign.sublime-workspace:42",
                should_match: true,
                expected_file: Some("./inputs/blogredesign.sublime-workspace"),
                expected_num: 42,
            },
            FileExistsTestCase {
                input: "inputs/blogredesign.sublime-workspace:42",
                should_match: true,
                expected_file: Some("inputs/blogredesign.sublime-workspace"),
                expected_num: 42,
            },
            FileExistsTestCase {
                input: "inputs/blogredesign.sublime-workspace",
                should_match: true,
                expected_file: Some("inputs/blogredesign.sublime-workspace"),
                expected_num: 0,
            },
            FileExistsTestCase {
                input: "./inputs/annoying-hyphen-dir/Package Control.system-bundle",
                should_match: true,
                expected_file: Some("./inputs/annoying-hyphen-dir/Package Control.system-bundle"),
                expected_num: 0,
            },
            FileExistsTestCase {
                input: "./inputs/annoying-hyphen-dir/Package Control.system-bundle:42",
                should_match: true,
                expected_file: Some("./inputs/annoying-hyphen-dir/Package Control.system-bundle"),
                expected_num: 42,
            },
            FileExistsTestCase {
                input: "./inputs/svo (install the zip, not me).xml",
                should_match: true,
                expected_file: Some("./inputs/svo (install the zip, not me).xml"),
                expected_num: 0,
            },
            FileExistsTestCase {
                input: "./inputs/svo (install the zip not me).xml",
                should_match: true,
                expected_file: Some("./inputs/svo (install the zip not me).xml"),
                expected_num: 0,
            },
            FileExistsTestCase {
                input: "./inputs/svo install the zip, not me.xml",
                should_match: true,
                expected_file: Some("./inputs/svo install the zip, not me.xml"),
                expected_num: 0,
            },
            FileExistsTestCase {
                input: "./inputs/svo install the zip not me.xml",
                should_match: true,
                expected_file: Some("./inputs/svo install the zip not me.xml"),
                expected_num: 0,
            },
            FileExistsTestCase {
                input: "./inputs/annoyingTildeExtension.txt~:42",
                should_match: true,
                expected_file: Some("./inputs/annoyingTildeExtension.txt~"),
                expected_num: 42,
            },
            FileExistsTestCase {
                input: "inputs/.DS_KINDA_STORE",
                should_match: true,
                expected_file: Some("inputs/.DS_KINDA_STORE"),
                expected_num: 0,
            },
            FileExistsTestCase {
                input: "./inputs/.DS_KINDA_STORE",
                should_match: true,
                expected_file: Some("./inputs/.DS_KINDA_STORE"),
                expected_num: 0,
            },
        ];

        for tc in &cases {
            let result = match_line(tc.input, true, false);
            if tc.should_match {
                let r = result.unwrap_or_else(|| {
                    panic!(
                        "Expected match for {:?} with validate_file_exists=true",
                        tc.input
                    );
                });
                assert_eq!(
                    r.path,
                    tc.expected_file.unwrap(),
                    "Wrong file for {:?}",
                    tc.input,
                );
                assert_eq!(
                    r.line_num, tc.expected_num,
                    "Wrong line num for {:?}",
                    tc.input,
                );
            } else {
                assert!(
                    result.is_none(),
                    "Expected no match for {:?} with validate_file_exists=true",
                    tc.input,
                );
            }
        }

        // Restore original directory
        std::env::set_current_dir(original_dir).unwrap();
    }

    // ── prepend_dir additional cases ─────────────────────────────────

    #[test]
    fn test_prepend_dir_git_diff_prefix() {
        let result_a = prepend_dir("a/foo/bar.py", false);
        assert!(
            result_a.ends_with("foo/bar.py"),
            "a/ prefix not stripped: {}",
            result_a
        );
        assert!(
            !result_a.contains("a/foo"),
            "a/ should be removed: {}",
            result_a
        );

        let result_b = prepend_dir("b/foo/bar.py", false);
        assert!(
            result_b.ends_with("foo/bar.py"),
            "b/ prefix not stripped: {}",
            result_b
        );
        assert!(
            !result_b.contains("b/foo"),
            "b/ should be removed: {}",
            result_b
        );
    }

    #[test]
    fn test_prepend_dir_no_slash() {
        // File without slash should get ./ prepended
        let result = prepend_dir("somefile.txt", false);
        assert_eq!(result, "./somefile.txt");
    }
}
