# Suite: 01_basic_parsing
# Sourced by run_e2e.sh — do not run directly.

# ------------------------------------------------------------------
echo -e "${CYAN}[1] Basic Parsing${NC}"

run_test "git_status_basic" \
    " M src/main.rs
 M src/parse.rs
?? new_file.txt" \
    --no-file-checks --all -c "echo"

run_test "git_status_modified_only" \
    " M README.md
 M Cargo.toml" \
    --no-file-checks --all -c "echo"

run_test "git_status_renamed" \
    "R  old_name.rs -> new_name.rs
M  src/lib.rs" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 2. grep/rg style input with line numbers

# ------------------------------------------------------------------
echo -e "${CYAN}[2] Grep Style Input${NC}"

run_test "grep_basic" \
    "src/main.rs:42: fn main()
src/parse.rs:10: use regex" \
    --no-file-checks --all -c "echo"

run_test "grep_with_column" \
    "src/main.rs:42:10: fn main()
src/parse.rs:10:5: use regex" \
    --no-file-checks --all -c "echo"

run_test "grep_recursive" \
    "./src/main.rs:1:mod format;
./src/parse.rs:1:use regex::Regex;
./tests/parse_test.rs:5:use fpp::parse;" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 3. Absolute paths

# ------------------------------------------------------------------
echo -e "${CYAN}[3] Absolute Paths${NC}"

run_test "absolute_paths" \
    "/usr/local/bin/test.sh
/home/user/project/main.rs
/var/log/syslog" \
    --no-file-checks --all -c "echo"

run_test "absolute_with_linenum" \
    "/usr/local/bin/test.sh:42
/home/user/project/main.rs:100" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 4. Home directory paths

# ------------------------------------------------------------------
echo -e "${CYAN}[4] Home Directory Paths${NC}"

run_test "home_dir_paths" \
    "~/foo/bar/something.py
~/foo/bar/inHomeDir.py:22" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 5. Paths with extensions and special names

# ------------------------------------------------------------------
echo -e "${CYAN}[5] Extensions and Special Names${NC}"

run_test "dotfiles" \
    ".gitignore
.env.local
tmp/.gitignore
.ssh/.gitignore" \
    --no-file-checks --all -c "echo"

run_test "multiple_periods" \
    "So.many.periods.txt
SO.MANY.PERIODS.TXT" \
    --no-file-checks --all -c "echo"

run_test "no_extension_files" \
    "Makefile
Gemfile
Dockerfile
TARGETS" \
    --no-file-checks --all -c "echo"

run_test "special_extensions" \
    "NSArray+Utils.h
src/categories/NSDate+Category.h
assets/retina/victory@2x.png" \
    --no-file-checks --all -c "echo"

run_test "temp_files" \
    "So.many.periods.txt~
#So.many.periods.txt#" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 6. Paths with context (before/after text)

# ------------------------------------------------------------------
echo -e "${CYAN}[12] Line Number Extraction${NC}"

run_test "linenum_colon" \
    "src/main.rs:42
./asd.txt:83
foo/bar/TARGETS:23" \
    --no-file-checks --all -c "echo"

run_test "linenum_dash" \
    "flib/asd/ent/berkeley/two.py-22
foo/bar/TARGETS-24" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 13. Git abbreviated paths (unresolvable)

# ------------------------------------------------------------------
echo -e "${CYAN}[13] Git Abbreviated Paths${NC}"

run_test "git_abbreviated" \
    ".../something/foo.py
.../expected/selectFirst.txt" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 14. Editor integration (script content verification)

# ------------------------------------------------------------------
echo -e "${CYAN}[28] Special File Patterns${NC}"

# Vim temp file standalone (no directory)
run_test "vim_temp_standalone" \
    "#main.rs#" \
    --no-file-checks --all -c "echo"

# Emacs temp file standalone
run_test "emacs_temp_standalone" \
    "main.rs~" \
    --no-file-checks --all -c "echo"

# Path in parentheses (from Python test_parsing.py)
run_test "path_in_parens" \
    '(fbcode/search/places/scorer/PageScorer.cpp:27:46):#include "header.h"' \
    --no-file-checks --all -c "echo"

# Reject non-file patterns
run_test "reject_special_chars" \
    'SO.MANY&&PERIODSTXT' \
    --no-file-checks -c "echo"

# .ssh/known_hosts (dotdir, no extension)
run_test "dotdir_no_extension" \
    ".ssh/known_hosts" \
    --no-file-checks --all -c "echo"

# Short path component
run_test "short_path_component" \
    "foo/b " \
    --no-file-checks --all -c "echo"

# First path wins on a line with multiple paths
run_test "first_path_wins" \
    "flib/asd/asd.py two/three/four.py" \
    --no-file-checks --all -c "echo"

# Absolute path with numeric extension
run_test "absolute_numeric_ext" \
    "/html/js/hotness.js42" \
    --no-file-checks --all -c "echo"

# FILE_NO_PERIODS: Gemfile matches but Gemfilenope does not
run_test "file_no_periods_valid" \
    "Gemfile
Rakefile
Cakefile" \
    --no-file-checks --all -c "echo"

run_test "file_no_periods_reject" \
    "Gemfilenope" \
    --no-file-checks -c "echo"

# ------------------------------------------------------------------
# 29. All-Input Mode Extended

# ------------------------------------------------------------------
echo -e "${CYAN}[38] Line Number Extended${NC}"

# Line number with no line number
run_test "linenum_none" \
    "src/main.rs" \
    --no-file-checks --all -c "echo"

# Multiple colon format (grep -n with column)
run_test "linenum_multi_colon" \
    "fbcode/search/places/scorer/TARGETS:590:28: some content" \
    --no-file-checks --all -c "echo"

# Just file with number (no directory)
run_test "linenum_just_file" \
    "So.MANY.PERIODS.TXT:22" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 39. Stress Tests Extended

# ------------------------------------------------------------------
echo -e "${CYAN}[42] Python Test Patterns${NC}"

# Fuzz-like: path with prefix and suffix text
run_test "fuzz_prefix_modified" \
    "Modified: html/js/hotness.js * Adapts to something" \
    --no-file-checks --all -c "echo"

run_test "fuzz_prefix_changed" \
    "Changed: ~/foo/bar/something.py:0:7: var AdsErrorCodeStore" \
    --no-file-checks --all -c "echo"

run_test "fuzz_middle_path" \
    "Banana asdasdoj pjo flib/foo/bar.py jkk asdad" \
    --no-file-checks --all -c "echo"

# Yocto-style paths with percent
run_test "yocto_percent_file" \
    "file-from-yocto_3.1%.bbappend" \
    --no-file-checks --all -c "echo"

# Git diff +++ and --- lines
run_test "git_diff_plus_minus" \
    "+++ b/src/main.rs
--- a/src/parse.rs
diff --git a/src/lib.rs b/src/lib.rs" \
    --no-file-checks --all -c "echo"

# TARGETS file with line number (OTHER_BGS_RESULT_REGEX)
run_test "targets_with_linenum" \
    "foo/bar/TARGETS:590" \
    --no-file-checks --all -c "echo"

# Multiple git status indicators
run_test "git_status_variety" \
    " M src/main.rs
 D deleted_file.rs
AM newly_added.rs
MM both_modified.rs
?? untracked.rs
!! ignored.rs
UU conflict.rs" \
    --no-file-checks --all -c "echo"

# Compiler error format (arrow -->)
run_test "compiler_error_arrow" \
    "  --> src/main.rs:42:5
  --> src/parse.rs:10:12" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 43. CRLF Line Endings

# ------------------------------------------------------------------
echo -e "${CYAN}[63] Preferred Regex / TARGETS${NC}"

# TARGETS-24 (dash separator line number, OTHER_BGS_RESULT_REGEX)
run_test "targets_dash_linenum" \
    "foo/bar/TARGETS-24" \
    --no-file-checks --all -c "echo"

# TARGETS:590 with extra content on same line
run_test "targets_multicolon_content" \
    'fbcode/search/places/scorer/TARGETS:590:28:    srcs = ["linear_scores/MinutiaeVerbScorer.cpp"]' \
    --no-file-checks --all -c "echo"

# preferred_regex wins: TARGETS:590 when MASTER_REGEX also matches
run_test "preferred_regex_targets" \
    "foo/bar/TARGETS:590 some/other/path.js" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 64. cd Command Path Normalization

# ------------------------------------------------------------------
echo -e "${CYAN}[90] Extensionless Directory Path${NC}"

# flib/foo/bar (no extension, has directory components)
run_test "extensionless_dir_path" \
    "flib/foo/bar" \
    --no-file-checks --all -c "echo"

# .thrift extension (from Python test suite)
run_test "thrift_extension" \
    "flib/ads/ads.thrift" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 91. File Validation: Space Files + Linenum

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle1-2] Path Parsing Edge Cases${NC}"

# Path with equals sign
run_test "path_with_equals_sign" \
    "CONFIG_FILE=/etc/app/config.yaml
src/config=test.rs" \
    --no-file-checks --all -c "echo"

# Path with consecutive dots
run_test "path_consecutive_dots" \
    "src/foo..bar.rs
path/to/file...ext" \
    --no-file-checks --all -c "echo"

# Path starting with number
run_test "path_starting_with_number" \
    "123/src/main.rs
42file.txt" \
    --no-file-checks --all -c "echo"

# Multiple files same basename different dirs
run_test "same_basename_diff_dirs" \
    "src/main.rs:10
lib/main.rs:20
tests/main.rs:30" \
    --no-file-checks --all -c "echo"

# Very deep nesting (13 levels)
run_test "very_deep_nesting" \
    "a/b/c/d/e/f/g/h/i/j/k/l/m/file.rs:42" \
    --no-file-checks --all -c "echo"

# Single line no trailing newline
run_test "single_line_no_newline" \
    "src/main.rs:42" \
    --no-file-checks --all -c "echo"

# Carriage return only (no LF)
run_test "carriage_return_only" \
    $'src/main.rs\rsrc/parse.rs' \
    --no-file-checks --all -c "echo"

# ANSI codes split across path components
run_test "ansi_split_across_components" \
    $'\033[31msrc/\033[32mdeep/\033[33mnested/\033[34mfile.rs\033[0m:42' \
    --no-file-checks --all -c "echo"

# Tab in middle of git status style line
run_test "tab_in_git_status" \
    $'\tmodified:\tsrc/main.rs' \
    --no-file-checks --all -c "echo"

# Homedir path with @ char and linenum
run_test "homedir_at_linenum" \
    "~/assets/retina/victory@2x.png:42" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 1: Command mode edge cases

# ==================================================================
echo -e "${CYAN}[C1-7] Regex Priority Edge Cases${NC}"

# Line number without extension - OTHER_BGS_RESULT_REGEX should match
run_test "regex_other_bgs_linenum_only" \
    "Makefile:42" \
    --no-file-checks --all -c "echo"

# Both MASTER and OTHER_BGS could match, but position decides
run_test "regex_priority_position" \
    "  src/main.rs:10: some error text" \
    --no-file-checks --all -c "echo"

# HOMEDIR_REGEX takes precedence (highest priority)
run_test "regex_homedir_precedence" \
    "~/Documents/file.txt:10" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-8] all-input mode edge cases

# ==================================================================
echo -e "${CYAN}[C1-18] Git Output Formats${NC}"

# git log --name-only with bare filenames (no commit hash prefix)
run_test "git_log_bare_filenames" \
    "pkg/server.go
pkg/handler.go
pkg/router.go" \
    --no-file-checks --all -c "echo"

# git diff --name-status format
run_test "git_diff_name_status" \
    "$(printf 'M\tpkg/server.go\nA\tpkg/new_handler.go\nD\tpkg/old_handler.go')" \
    --no-file-checks --all -c "echo"

# git stash show format
run_test "git_stash_show" \
    " pkg/server.go | 10 ++++------
 pkg/handler.go | 3 +--
 2 files changed, 5 insertions(+), 8 deletions(-)" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-19] Rust compiler error output format

# ==================================================================
echo -e "${CYAN}[C1-19] Compiler Error Formats${NC}"

# TypeScript/JavaScript error format
run_test "typescript_error_format" \
    "src/app.tsx(15,3): error TS2322: Type 'string' is not assignable" \
    --no-file-checks --all -c "echo"

# Python traceback with file and line
run_test "python_traceback_format" \
    '  File "src/main.py", line 42, in <module>' \
    --no-file-checks --all -c "echo"

# gcc/clang error format
run_test "gcc_error_format" \
    "src/main.c:42:10: error: expected ';' after expression" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-20] Path with special characters

# ==================================================================
echo -e "${CYAN}[C1-26] Multiple Matches Per Line${NC}"

# Two paths on the same line (first should win)
run_test "two_paths_same_line" \
    "src/main.rs src/parse.rs" \
    --no-file-checks --all -c "echo"

# Path followed by path with linenum
run_test "path_then_path_linenum_same_line" \
    "src/main.rs src/parse.rs:42" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-27] Vim/Nvim split with many files

# ==================================================================
echo -e "${CYAN}[COV-1] FILE_NO_PERIODS Standalone Patterns${NC}"

run_test "file_no_periods_makefile" \
    "Makefile" \
    --no-file-checks --all -c "echo"

run_test "file_no_periods_gemfile" \
    "Gemfile" \
    --no-file-checks --all -c "echo"

run_test "file_no_periods_rakefile" \
    "Rakefile" \
    --no-file-checks --all -c "echo"

# Gemfilenope should NOT match (doesn't end in "file")
run_test "file_no_periods_gemfilenope_reject" \
    "Gemfilenope" \
    --no-file-checks -c "echo"

# Short dotfile .a should NOT match
run_test "dotfile_too_short_reject" \
    ".a" \
    --no-file-checks -c "echo"

# ==================================================================
# [COV-2] Dotfile with multiple dots / .env.local pattern

# ==================================================================
echo -e "${CYAN}[COV-2] Dotfile Multi-Dot Extensions${NC}"

run_test "dotfile_env_local" \
    ".env.local" \
    --no-file-checks --all -c "echo"

run_test "dotfile_env_local_in_dir" \
    "config/.env.local" \
    --no-file-checks --all -c "echo"

run_test "dotfile_ssh_known_hosts" \
    ".ssh/known_hosts" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-3] Numeric extension (hotness.js42)

# ==================================================================
echo -e "${CYAN}[COV-3] Numeric Extension Paths${NC}"

run_test "path_numeric_extension" \
    "/html/js/hotness.js42" \
    --no-file-checks --all -c "echo"

run_test "path_long_numeric_ext" \
    "src/module/widget.py3" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-4] Special chars in filename that should NOT match

# ==================================================================
echo -e "${CYAN}[COV-5] Two Paths Same Line (First Wins)${NC}"

run_test "two_paths_first_wins" \
    "flib/asd/asd.py two/three/four.py" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-6] Dot-slash relative path with linenum

# ==================================================================
echo -e "${CYAN}[COV-6] Dot-Slash Relative Path${NC}"

run_test "dotslash_with_linenum" \
    "./asd.txt:83" \
    --no-file-checks --all -c "echo"

run_test "dotdotslash_with_linenum" \
    "../parent/file.rs:42" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-7] TARGETS multi-colon complex (fbcode patterns)

# ==================================================================
echo -e "${CYAN}[COV-7] TARGETS Complex Patterns${NC}"

run_test "targets_complex_colon_content" \
    'fbcode/search/places/scorer/PageScorer.cpp:27:46:#include "header.h"' \
    --no-file-checks --all -c "echo"

run_test "targets_in_parens" \
    '(fbcode/search/places/scorer/PageScorer.cpp:27:46): error' \
    --no-file-checks --all -c "echo"

run_test "targets_deep_linenum" \
    'fbcode/search/places/scorer/TARGETS:590:28:    srcs = ["file.cpp"]' \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-8] Plus symbol in filename (NSArray+Utils.h)

# ==================================================================
echo -e "${CYAN}[COV-8] Plus Symbol Filenames${NC}"

run_test "plus_in_filename_standalone" \
    "NSArray+Utils.h" \
    --no-file-checks --all -c "echo"

run_test "plus_in_filename_with_dir" \
    "M     ./objectivec/NSArray+Utils.h" \
    --no-file-checks --all -c "echo"

run_test "plus_in_filename_homedir" \
    "~/src/categories/NSDate+Category.h" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-9] Emacs/Vim temp with many periods

# ==================================================================
echo -e "${CYAN}[COV-9] Temp Files with Many Periods${NC}"

run_test "vim_temp_many_periods" \
    "#So.many.periods.txt#" \
    --no-file-checks --all -c "echo"

run_test "emacs_temp_many_periods" \
    "So.many.periods.txt~" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-10] Short path component (foo/b)

# ==================================================================
echo -e "${CYAN}[COV-10] Short Path Components${NC}"

run_test "short_path_component_foob" \
    "foo/b " \
    --no-file-checks --all -c "echo"

run_test "path_with_trailing_space" \
    "flib/foo/bar " \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-11] home/ prefix prepend to /home/

# ==================================================================
echo -e "${CYAN}[COV-11] home/ Prefix Prepending${NC}"

run_test "prepend_home_absolute" \
    "home/absolute/path.py" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-12] @ retina files with prefix text

# ==================================================================
echo -e "${CYAN}[COV-12] Retina @ Files${NC}"

run_test "retina_at_file_with_prefix" \
    "blarge assets/retina/victory@2x.png" \
    --no-file-checks --all -c "echo"

run_test "retina_at_homedir" \
    "~/assets/retina/victory@2x.png" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-13] Many periods in filename

# ==================================================================
echo -e "${CYAN}[COV-13] Many Periods Filenames${NC}"

run_test "many_periods_lower" \
    "So.many.periods.txt" \
    --no-file-checks --all -c "echo"

run_test "many_periods_upper" \
    "SO.MANY.PERIODS.TXT" \
    --no-file-checks --all -c "echo"

run_test "many_periods_with_linenum" \
    "blarg blah So.MANY.PERIODS.TXT:22" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-14] thrift/proto extensions

# ==================================================================
echo -e "${CYAN}[COV-14] Domain-Specific Extensions${NC}"

run_test "thrift_extension_with_dir" \
    "flib/ads/ads.thrift" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-15] banana prefix fuzz pattern from Python tests

# ==================================================================
echo -e "${CYAN}[COV-15] Fuzz: Prefix Text Before Path${NC}"

run_test "fuzz_banana_story_m" \
    "banana hanana Wilde/ads/story.m" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-16] vim -p with 4+ files

