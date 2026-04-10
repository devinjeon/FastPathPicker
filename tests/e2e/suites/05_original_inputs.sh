# Suite: 05_original_inputs
# Sourced by run_e2e.sh — do not run directly.

# ------------------------------------------------------------------
echo -e "${CYAN}[10] Original Input Files${NC}"

if [ -d "$INPUTS_DIR" ]; then
    run_test_file "input_gitDiff" \
        "$INPUTS_DIR/gitDiff.txt" \
        --no-file-checks --all -c "echo"

    run_test_file "input_absoluteGitDiff" \
        "$INPUTS_DIR/absoluteGitDiff.txt" \
        --no-file-checks --all -c "echo"

    run_test_file "input_gitDiffColor" \
        "$INPUTS_DIR/gitDiffColor.txt" \
        --no-file-checks --all -c "echo"

    run_test_file "input_gitDiffNoStat" \
        "$INPUTS_DIR/gitDiffNoStat.txt" \
        --no-file-checks --all -c "echo"

    run_test_file "input_gitBranch_allInput" \
        "$INPUTS_DIR/gitBranch.txt" \
        --all-input --all -c "echo"

    run_test_file "input_longList" \
        "$INPUTS_DIR/longList.txt" \
        --no-file-checks --all -c "echo"

    run_test_file "input_tonsOfFiles" \
        "$INPUTS_DIR/tonsOfFiles.txt" \
        --no-file-checks --all -c "echo"

    run_test_file "input_longFileNames" \
        "$INPUTS_DIR/longFileNames.txt" \
        --no-file-checks --all -c "echo"

    run_test_file "input_superLongFileNames" \
        "$INPUTS_DIR/superLongFileNames.txt" \
        --no-file-checks --all -c "echo"

    run_test_file "input_gitAbbreviatedFiles" \
        "$INPUTS_DIR/gitAbbreviatedFiles.txt" \
        --no-file-checks --all -c "echo"

    run_test_file "input_longLineAbbreviated" \
        "$INPUTS_DIR/longLineAbbreviated.txt" \
        --no-file-checks --all -c "echo"

    run_test_file "input_gitLongDiff" \
        "$INPUTS_DIR/gitLongDiff.txt" \
        --no-file-checks --all -c "echo"

    run_test_file "input_gitLongDiffColor" \
        "$INPUTS_DIR/gitLongDiffColor.txt" \
        --no-file-checks --all -c "echo"
else
    echo -e "  ${YELLOW}SKIP${NC} Original input files not found at $INPUTS_DIR"
fi

# ------------------------------------------------------------------
# 11. Mixed real-world inputs

# ------------------------------------------------------------------
echo -e "${CYAN}[11] Real-World Mixed Input${NC}"

run_test "find_output" \
    "./src/main.rs
./src/parse.rs
./src/format.rs
./tests/parse_test.rs
./Cargo.toml" \
    --no-file-checks --all -c "echo"

run_test "rust_compiler_errors" \
    "error[E0308]: mismatched types
  --> src/main.rs:42:5
  |
42 |     let x: u32 = \"hello\";
  |                  ^^^^^^^ expected \`u32\`, found \`&str\`

error[E0425]: cannot find value
  --> src/parse.rs:10:12
  |
10 |     return unknown_var;
  |            ^^^^^^^^^^^ not found" \
    --no-file-checks --all -c "echo"

run_test "python_traceback" \
    'Traceback (most recent call last):
  File "/usr/lib/python3/foo.py", line 42, in <module>
    raise ValueError()
  File "src/bar.py", line 10, in func
    return None' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 12. Line number extraction

# ------------------------------------------------------------------
echo -e "${CYAN}[44] Real-World Tool Output${NC}"

# ls -la style output
run_test "ls_la_output" \
    "-rw-r--r--  1 user group  1234 Jan  1 12:00 Cargo.toml
-rw-r--r--  1 user group   567 Jan  1 12:00 Makefile
drwxr-xr-x  4 user group   128 Jan  1 12:00 src
-rw-r--r--  1 user group   890 Jan  1 12:00 README.md" \
    --no-file-checks --all -c "echo"

# git log --oneline --name-only
run_test "git_log_name_only" \
    "abc1234 Fix parsing bug
src/main.rs
def5678 Add tests
tests/parse_test.rs
README.md" \
    --no-file-checks --all -c "echo"

# rg/ag with block separator (--)
run_test "rg_block_separator" \
    "src/main.rs:42:fn main() {
src/main.rs:43:    println!();
--
src/parse.rs:10:use regex;
src/parse.rs:11:pub fn match_line() {" \
    --no-file-checks --all -c "echo"

# git diff --name-only style
run_test "git_diff_name_only" \
    "src/main.rs
src/parse.rs
tests/parse_test.rs
Cargo.toml" \
    --no-file-checks --all -c "echo"

# docker ps style output (--all-input)
run_test "docker_ps_all_input" \
    "CONTAINER ID   IMAGE          STATUS
abc123def456   nginx:latest   Up 2 hours
def789ghi012   redis:7        Up 3 hours" \
    --all-input --all -c "echo"

# WSL-style paths
run_test "wsl_mnt_paths" \
    "/mnt/c/Users/dev/project/main.rs
/mnt/c/Users/dev/project/lib.rs:42" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 45. ANSI Mixed Stream

# ------------------------------------------------------------------
echo -e "${CYAN}[52] Additional Input Files${NC}"

if [ -d "$INPUTS_DIR" ]; then
    # Files with spaces (critical for MASTER_REGEX_WITH_SPACES)
    if [ -f "$INPUTS_DIR/../inputs/fileNamesWithSpaces.txt" ]; then
        run_test_file "input_fileNamesWithSpaces" \
            "$INPUTS_DIR/../inputs/fileNamesWithSpaces.txt" \
            --all -c "echo"
    fi

    # Some files exist, some don't
    if [ -f "$INPUTS_DIR/gitDiffSomeExist.txt" ]; then
        run_test_file "input_gitDiffSomeExist" \
            "$INPUTS_DIR/gitDiffSomeExist.txt" \
            --all -c "echo"
    fi

    # Long file names with prefix text
    if [ -f "$INPUTS_DIR/longFileNamesWithBeforeText.txt" ]; then
        run_test_file "input_longFileNamesWithBeforeText" \
            "$INPUTS_DIR/longFileNamesWithBeforeText.txt" \
            --no-file-checks --all -c "echo"
    fi
fi

# ------------------------------------------------------------------
# 53. Fuzz Patterns Extended (from test_parsing.py)

# ------------------------------------------------------------------
echo -e "${CYAN}[92] Real-World Tool Outputs${NC}"

# Java stack trace
run_test "java_stack_trace" \
    'Exception in thread "main" java.lang.NullPointerException
	at com.example.MyClass.method(MyClass.java:42)
	at com.example.Main.main(Main.java:10)' \
    --no-file-checks --all -c "echo"

# Go compile error
run_test "go_compile_error" \
    "./main.go:10:5: undefined: foo
./util.go:25:12: cannot use x" \
    --no-file-checks --all -c "echo"

# pytest output
run_test "pytest_output" \
    "FAILED tests/test_foo.py::test_bar - AssertionError
FAILED tests/test_baz.py::test_qux - ValueError" \
    --no-file-checks --all -c "echo"

# svn status
run_test "svn_status_output" \
    "M       trunk/src/main.rs
A       trunk/src/new_file.rs
D       trunk/src/old_file.rs" \
    --no-file-checks --all -c "echo"

# webpack error
run_test "webpack_error_output" \
    "ERROR in ./src/App.tsx:15:3
Module not found: Error: Can't resolve './Missing'
 @ ./src/index.tsx:1:0" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 1: Real-world tool outputs

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle1-1] Real-World Tool Outputs${NC}"

# npm error output with paths in quotes
run_test "npm_error_output" \
    "npm ERR! code ENOENT
npm ERR! syscall open
npm ERR! path /home/user/project/package.json
npm ERR! errno -2
npm ERR! enoent ENOENT: no such file or directory, open '/home/user/project/package.json'" \
    --no-file-checks --all -c "echo"

# ag/ack style output (filename alone on a line, matches below)
run_test "ag_style_output" \
    "src/parse.rs
42:    let regex = Regex::new(pattern);
85:    fn match_line(line: &str) -> Option<Match> {

src/main.rs
10:use crate::parse;" \
    --no-file-checks --all -c "echo"

# fd style output (no ./ prefix, plain relative paths)
run_test "fd_style_output" \
    "src/main.rs
src/parse.rs
tests/parsing_test.rs
docs/README.md" \
    --no-file-checks --all -c "echo"

# hg status output
run_test "hg_status_output" \
    "M src/main.rs
A src/new_file.rs
R src/old_file.rs
? untracked.txt
! missing_file.rs" \
    --no-file-checks --all -c "echo"

# bazel build error output (path:line:col format)
run_test "bazel_build_output" \
    "ERROR: /home/user/project/BUILD:10:1: no such target '//src:main'
WARNING: /home/user/project/WORKSPACE:5:1: deprecated" \
    --no-file-checks --all -c "echo"

# Ruby stack trace
run_test "ruby_stack_trace" \
    "/usr/lib/ruby/3.0/net/http.rb:987:in \`connect'
/home/user/app/lib/client.rb:42:in \`request'
app/controllers/main_controller.rb:15:in \`index'" \
    --no-file-checks --all -c "echo"

# Node.js stack trace (paths in parentheses)
run_test "node_stack_trace" \
    "Error: Something went wrong
    at Object.<anonymous> (/home/user/app/index.js:10:5)
    at Module._compile (node:internal/modules/cjs/loader:1105:14)" \
    --no-file-checks --all -c "echo"

# diff --git header line
run_test "diff_git_header" \
    "diff --git a/src/parse.rs b/src/parse.rs
index abc1234..def5678 100644
--- a/src/parse.rs
+++ b/src/parse.rs" \
    --no-file-checks --all -c "echo"

# locate command output (system paths, various extensions)
run_test "locate_style_output" \
    "/usr/lib/python3.10/json/__init__.py
/usr/lib/python3.10/json/decoder.py
/etc/nginx/nginx.conf
/usr/local/share/man/man1/git.1" \
    --no-file-checks --all -c "echo"

# perforce depot paths (double-slash prefix)
run_test "perforce_depot_paths" \
    "//depot/main/src/foo.py#3 - edit default change (text)
//depot/main/src/bar.py#1 - add default change (text)" \
    --no-file-checks --all -c "echo"

# cargo compiler output (warning + error mixed)
run_test "cargo_mixed_output" \
    "warning: unused variable: \`x\`
 --> src/lib.rs:5:9
  |
5 |     let x = 42;
  |         ^ help: if this is intentional, prefix it with an underscore

error[E0599]: no method named \`foo\` found
 --> src/bar.rs:12:10" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 1: Path parsing edge cases

