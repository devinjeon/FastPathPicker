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
    let home = dirs::home_dir().unwrap();
    let home_str = home.to_string_lossy();
    let prepend = &*PREPEND_PATH;

    // 1. "home/absolute/path.py" -> "/home/absolute/path.py"
    assert_eq!(
        prepend_dir("home/absolute/path.py", false),
        "/home/absolute/path.py",
    );

    // 2. "~/www/asd.py" -> expands ~ to home dir
    assert_eq!(
        prepend_dir("~/www/asd.py", false),
        format!("{}/www/asd.py", home_str),
    );

    // 3. "www/asd.py" -> expands to ~/www/asd.py (repos match)
    assert_eq!(
        prepend_dir("www/asd.py", false),
        format!("{}/www/asd.py", home_str),
    );

    // 4. "foo/bar/baz/asd.py" -> PREPEND_PATH + "foo/bar/baz/asd.py"
    assert_eq!(
        prepend_dir("foo/bar/baz/asd.py", false),
        format!("{}foo/bar/baz/asd.py", prepend),
    );

    // 5. "a/foo/bar/baz/asd.py" -> PREPEND_PATH + "foo/bar/baz/asd.py"
    assert_eq!(
        prepend_dir("a/foo/bar/baz/asd.py", false),
        format!("{}foo/bar/baz/asd.py", prepend),
    );

    // 6. "b/foo/bar/baz/asd.py" -> PREPEND_PATH + "foo/bar/baz/asd.py"
    assert_eq!(
        prepend_dir("b/foo/bar/baz/asd.py", false),
        format!("{}foo/bar/baz/asd.py", prepend),
    );

    // 7. empty string
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
            expected: Some("no changes added to commit (use \"git add\" and/or \"git commit -a\")"),
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

// Use the shared DIR_LOCK from test_env to prevent parallel test interference
// with set_current_dir across all unit test modules in this binary.
use crate::test_env::DIR_LOCK;

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

    // Change to tests/ directory so relative ./inputs/ paths resolve.
    let _guard = DIR_LOCK.lock().unwrap();
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

/// Tests that require working_dir="inputs" (chdir into inputs/ before matching).
/// Ported from Python's FILE_TEST_CASES with working_dir parameter.
#[test]
fn test_validate_file_exists_with_working_dir() {
    let inputs_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/inputs");
    if !inputs_dir.exists() {
        eprintln!("Skipping working_dir tests: tests/inputs/ not found");
        return;
    }

    let _guard = DIR_LOCK.lock().unwrap();
    let original_dir = std::env::current_dir().unwrap();
    std::env::set_current_dir(&inputs_dir).unwrap();

    // Python: evilFile No Prepend.txt, working_dir="inputs", validate=True, no_fuzz
    let result = match_line("evilFile No Prepend.txt", true, false);
    let r = result.expect("'evilFile No Prepend.txt' should match with validate_file_exists");
    assert_eq!(r.path, "evilFile No Prepend.txt");
    assert_eq!(r.line_num, 0);

    // Python: file-from-yocto_%.bbappend, working_dir="inputs", validate=True
    let result = match_line("file-from-yocto_%.bbappend", true, false);
    let r = result.expect("'file-from-yocto_%.bbappend' should match with validate_file_exists");
    assert_eq!(r.path, "file-from-yocto_%.bbappend");
    assert_eq!(r.line_num, 0);

    // Python: "other thing ./foo/file-from-yocto_3.1%.bbappend", working_dir="inputs", validate=True
    // The expected match is "file-from-yocto_3.1%.bbappend" (just the basename)
    let result = match_line(
        "other thing ./foo/file-from-yocto_3.1%.bbappend",
        true,
        false,
    );
    let r = result.expect("'other thing ./foo/file-from-yocto_3.1%.bbappend' should match");
    assert_eq!(r.path, "file-from-yocto_3.1%.bbappend");
    assert_eq!(r.line_num, 0);

    // Python: "./file-from-yocto_3.1%.bbappend", working_dir="inputs", validate=True
    let result = match_line("./file-from-yocto_3.1%.bbappend", true, false);
    let r = result.expect("'./file-from-yocto_3.1%.bbappend' should match");
    assert_eq!(r.path, "./file-from-yocto_3.1%.bbappend");
    assert_eq!(r.line_num, 0);

    std::env::set_current_dir(original_dir).unwrap();
}

/// Python: "inputs/annoying-hyphen-dir/Package Control.system-bundle"
/// with validate_file_exists=True, disable_fuzz_test=True, no prepend.
#[test]
fn test_validate_file_exists_no_prepend() {
    let test_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests");
    if !test_dir.exists() {
        eprintln!("Skipping no-prepend test: tests/ not found");
        return;
    }

    let _guard = DIR_LOCK.lock().unwrap();
    let original_dir = std::env::current_dir().unwrap();
    std::env::set_current_dir(&test_dir).unwrap();

    let result = match_line(
        "inputs/annoying-hyphen-dir/Package Control.system-bundle",
        true,
        false,
    );
    let r =
        result.expect("'inputs/annoying-hyphen-dir/Package Control.system-bundle' should match");
    assert_eq!(
        r.path,
        "inputs/annoying-hyphen-dir/Package Control.system-bundle"
    );
    assert_eq!(r.line_num, 0);

    std::env::set_current_dir(original_dir).unwrap();
}

// ── validate_file_exists negative cases ──────────────────────────

#[test]
fn test_validate_nonexistent_path_with_spaces() {
    let result = match_line("this path does not exist.txt", true, false);
    assert!(
        result.is_none(),
        "Non-existent path with spaces should not match when validate_file_exists=true"
    );
}

#[test]
fn test_validate_nonexistent_absolute_path() {
    let result = match_line("/tmp/absolutely_nonexistent_fpp_test_file.rs", true, false);
    assert!(
        result.is_none(),
        "Non-existent absolute path should not match when validate_file_exists=true"
    );
}

#[test]
fn test_validate_nonexistent_relative_path() {
    let result = match_line("nonexistent_dir/fake_file.txt", true, false);
    assert!(
        result.is_none(),
        "Non-existent relative path should not match when validate_file_exists=true"
    );
}

// ── prepend_dir additional cases ─────────────────────────────────

#[test]
fn test_prepend_dir_no_slash() {
    // File without slash should get ./ prepended
    let result = prepend_dir("somefile.txt", false);
    assert_eq!(result, "./somefile.txt");
}
