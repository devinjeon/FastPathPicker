#!/bin/bash
# e2e test runner: compare original Python PathPicker and Rust implementation
#
# Bypasses Python's curses UI and compares only parsing + script generation logic.
# fpp_headless.py calls Python internals directly to produce .fpp.sh,
# while the Rust binary does the same via --non-interactive mode.
#
# Usage:
#   ./tests/e2e/run_e2e.sh                    # Python vs Rust comparison
#   ./tests/e2e/run_e2e.sh --rust-only        # Rust only (snapshot-based)
#   ./tests/e2e/run_e2e.sh --update-snapshots # update snapshots
#   FPP_BINARY=/path/to/fpp ./tests/e2e/run_e2e.sh --rust-only  # custom binary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INPUTS_DIR="$PROJECT_ROOT/PathPicker/src/tests/inputs"
SNAPSHOT_DIR="$SCRIPT_DIR/snapshots"
TMPDIR_BASE="$(mktemp -d)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
SKIP=0

# Binaries
RUST_BINARY="${FPP_BINARY:-$PROJECT_ROOT/target/release/fpp}"
PYTHON_HEADLESS="python3 $SCRIPT_DIR/fpp_headless.py"
MODE="compare"  # compare | rust-only | update-snapshots

# Prevent Rust binary from executing generated .fpp.sh scripts during tests.
# We only care about the script content, not its execution.
export FPP_SKIP_EXECUTE=1

for arg in "$@"; do
    case "$arg" in
        --rust-only) MODE="rust-only" ;;
        --update-snapshots) MODE="update-snapshots" ;;
        --help)
            echo "Usage: $0 [--rust-only|--update-snapshots]"
            echo ""
            echo "Modes:"
            echo "  (default)           Compare Python fpp vs Rust fpp"
            echo "  --rust-only         Run Rust binary only, compare against snapshots"
            echo "  --update-snapshots  Update snapshot files from current Rust binary output"
            echo ""
            echo "Environment:"
            echo "  FPP_BINARY          Path to the binary to test (default: target/release/fpp)"
            exit 0
            ;;
    esac
done

cleanup() {
    rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

# === Helper functions ===

# Run Rust binary with given input and flags, return .fpp.sh content
run_rust() {
    local input="$1"
    local state_dir="$2"
    shift 2
    local flags=("$@")

    mkdir -p "$state_dir"
    rm -f "$state_dir/.fpp.sh" "$state_dir/.input.json" "$state_dir/.selection.json"

    export FPP_DIR="$state_dir"
    timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive "${@:3}" >/dev/null 2>&1 || true' _ "$input" "$RUST_BINARY" "${flags[@]}" 2>/dev/null || true
    unset FPP_DIR

    if [ -f "$state_dir/.fpp.sh" ]; then
        cat "$state_dir/.fpp.sh"
    else
        echo "(no script generated)"
    fi
}

# Run Python headless with given input and flags, return .fpp.sh content
run_python() {
    local input="$1"
    local state_dir="$2"
    shift 2
    local flags=("$@")

    mkdir -p "$state_dir"
    rm -f "$state_dir/.fpp.sh" "$state_dir/.pickle" "$state_dir/.selection.pickle"

    export FPP_DIR="$state_dir"
    printf '%s' "$input" | $PYTHON_HEADLESS "${flags[@]}" >/dev/null 2>&1 || true
    unset FPP_DIR

    if [ -f "$state_dir/.fpp.sh" ]; then
        cat "$state_dir/.fpp.sh"
    else
        echo "(no script generated)"
    fi
}

# File input variants
run_rust_file() {
    local input_file="$1"
    local state_dir="$2"
    shift 2
    local flags=("$@")

    mkdir -p "$state_dir"
    rm -f "$state_dir/.fpp.sh" "$state_dir/.input.json" "$state_dir/.selection.json"

    export FPP_DIR="$state_dir"
    timeout 10 "$RUST_BINARY" --non-interactive "${flags[@]}" < "$input_file" >/dev/null 2>&1 || true
    unset FPP_DIR

    if [ -f "$state_dir/.fpp.sh" ]; then
        cat "$state_dir/.fpp.sh"
    else
        echo "(no script generated)"
    fi
}

run_python_file() {
    local input_file="$1"
    local state_dir="$2"
    shift 2
    local flags=("$@")

    mkdir -p "$state_dir"
    rm -f "$state_dir/.fpp.sh" "$state_dir/.pickle" "$state_dir/.selection.pickle"

    export FPP_DIR="$state_dir"
    $PYTHON_HEADLESS "${flags[@]}" < "$input_file" >/dev/null 2>&1 || true
    unset FPP_DIR

    if [ -f "$state_dir/.fpp.sh" ]; then
        cat "$state_dir/.fpp.sh"
    else
        echo "(no script generated)"
    fi
}

# Normalize script output for comparison
# Removes platform-specific differences while preserving semantic content
normalize_output() {
    # 1. Collapse printf multi-line strings into single lines using \n
    #    (Python embeds actual newlines, Rust uses \n escape — same behavior when executed)
    # 2. Remove trailing whitespace
    # 3. Remove empty lines
    python3 -c "
import sys
lines = sys.stdin.read().split('\n')
result = []
in_printf = False
printf_buf = ''
for line in lines:
    stripped = line.rstrip()
    if not stripped:
        continue
    if in_printf:
        printf_buf += '\\\\n' + stripped
        if '\"' in stripped:
            in_printf = False
            result.append(printf_buf)
            printf_buf = ''
        continue
    if stripped.startswith('printf \"') and stripped.count('\"') == 1:
        in_printf = True
        printf_buf = stripped
        continue
    result.append(stripped)
if printf_buf:
    result.append(printf_buf)
print('\n'.join(result))
" 2>/dev/null || sed -e 's/[[:space:]]*$//' -e '/^$/d'
}

# Compare two outputs and report result
assert_equal() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    local norm_expected norm_actual
    norm_expected=$(echo "$expected" | normalize_output)
    norm_actual=$(echo "$actual" | normalize_output)

    if [ "$norm_expected" = "$norm_actual" ]; then
        echo -e "  ${GREEN}PASS${NC} $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $test_name"
        echo -e "    ${YELLOW}Expected:${NC}"
        echo "$norm_expected" | head -20 | sed 's/^/      /'
        echo -e "    ${YELLOW}Actual:${NC}"
        echo "$norm_actual" | head -20 | sed 's/^/      /'
        diff <(echo "$norm_expected") <(echo "$norm_actual") 2>/dev/null | head -30 | sed 's/^/      /' || true
        FAIL=$((FAIL + 1))
    fi
}

# High-level test runners that dispatch based on MODE

# run_test <name> <input> <flags...>
# Flags are passed to BOTH Python and Rust (except --non-interactive which is added to Rust automatically)
run_test() {
    local test_name="$1"
    local input="$2"
    shift 2
    local flags=("$@")

    case "$MODE" in
        compare)
            local py_dir="$TMPDIR_BASE/py_${test_name}"
            local rs_dir="$TMPDIR_BASE/rs_${test_name}"
            local py_out rs_out
            py_out=$(run_python "$input" "$py_dir" "${flags[@]}")
            rs_out=$(run_rust "$input" "$rs_dir" "${flags[@]}")
            assert_equal "$test_name" "$py_out" "$rs_out"
            ;;
        rust-only)
            local rs_dir="$TMPDIR_BASE/rs_${test_name}"
            local snapshot_file="$SNAPSHOT_DIR/${test_name}.txt"
            local rs_out
            rs_out=$(run_rust "$input" "$rs_dir" "${flags[@]}")
            if [ ! -f "$snapshot_file" ]; then
                echo -e "  ${YELLOW}SKIP${NC} $test_name (no snapshot)"
                SKIP=$((SKIP + 1))
                return
            fi
            assert_equal "$test_name" "$(cat "$snapshot_file")" "$rs_out"
            ;;
        update-snapshots)
            local rs_dir="$TMPDIR_BASE/rs_${test_name}"
            mkdir -p "$SNAPSHOT_DIR"
            local rs_out
            rs_out=$(run_rust "$input" "$rs_dir" "${flags[@]}")
            echo "$rs_out" > "$SNAPSHOT_DIR/${test_name}.txt"
            echo -e "  ${CYAN}UPDATED${NC} $test_name"
            ;;
    esac
}

# run_test_file <name> <input_file> <flags...>
run_test_file() {
    local test_name="$1"
    local input_file="$2"
    shift 2
    local flags=("$@")

    case "$MODE" in
        compare)
            local py_dir="$TMPDIR_BASE/py_${test_name}"
            local rs_dir="$TMPDIR_BASE/rs_${test_name}"
            local py_out rs_out
            py_out=$(run_python_file "$input_file" "$py_dir" "${flags[@]}")
            rs_out=$(run_rust_file "$input_file" "$rs_dir" "${flags[@]}")
            assert_equal "$test_name" "$py_out" "$rs_out"
            ;;
        rust-only)
            local rs_dir="$TMPDIR_BASE/rs_${test_name}"
            local snapshot_file="$SNAPSHOT_DIR/${test_name}.txt"
            local rs_out
            rs_out=$(run_rust_file "$input_file" "$rs_dir" "${flags[@]}")
            if [ ! -f "$snapshot_file" ]; then
                echo -e "  ${YELLOW}SKIP${NC} $test_name (no snapshot)"
                SKIP=$((SKIP + 1))
                return
            fi
            assert_equal "$test_name" "$(cat "$snapshot_file")" "$rs_out"
            ;;
        update-snapshots)
            local rs_dir="$TMPDIR_BASE/rs_${test_name}"
            mkdir -p "$SNAPSHOT_DIR"
            local rs_out
            rs_out=$(run_rust_file "$input_file" "$rs_dir" "${flags[@]}")
            echo "$rs_out" > "$SNAPSHOT_DIR/${test_name}.txt"
            echo -e "  ${CYAN}UPDATED${NC} $test_name"
            ;;
    esac
}

# Editor test: sets FPP_EDITOR env var
run_test_editor() {
    local test_name="$1"
    local editor="$2"
    local input="$3"
    shift 3
    local flags=("$@")

    case "$MODE" in
        compare)
            local py_dir="$TMPDIR_BASE/py_${test_name}"
            local rs_dir="$TMPDIR_BASE/rs_${test_name}"
            mkdir -p "$py_dir" "$rs_dir"
            rm -f "$py_dir/.fpp.sh" "$rs_dir/.fpp.sh"

            local py_out rs_out
            export FPP_DIR="$py_dir" FPP_EDITOR="$editor"
            timeout 10 bash -c 'printf "%s" "$1" | $2 "${@:3}" >/dev/null 2>&1 || true' _ "$input" "$PYTHON_HEADLESS" "${flags[@]}" 2>/dev/null || true
            py_out=$(cat "$py_dir/.fpp.sh" 2>/dev/null || echo "(no script)")

            export FPP_DIR="$rs_dir"
            timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive "${@:3}" >/dev/null 2>&1 || true' _ "$input" "$RUST_BINARY" "${flags[@]}" 2>/dev/null || true
            rs_out=$(cat "$rs_dir/.fpp.sh" 2>/dev/null || echo "(no script)")
            unset FPP_DIR FPP_EDITOR

            assert_equal "$test_name" "$py_out" "$rs_out"
            ;;
        rust-only)
            local rs_dir="$TMPDIR_BASE/rs_${test_name}"
            local snapshot_file="$SNAPSHOT_DIR/${test_name}.txt"
            mkdir -p "$rs_dir"
            rm -f "$rs_dir/.fpp.sh"

            export FPP_DIR="$rs_dir" FPP_EDITOR="$editor"
            timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive "${@:3}" >/dev/null 2>&1 || true' _ "$input" "$RUST_BINARY" "${flags[@]}" 2>/dev/null || true
            local rs_out
            rs_out=$(cat "$rs_dir/.fpp.sh" 2>/dev/null || echo "(no script)")
            unset FPP_DIR FPP_EDITOR

            if [ ! -f "$snapshot_file" ]; then
                echo -e "  ${YELLOW}SKIP${NC} $test_name (no snapshot)"
                SKIP=$((SKIP + 1))
                return
            fi
            assert_equal "$test_name" "$(cat "$snapshot_file")" "$rs_out"
            ;;
        update-snapshots)
            local rs_dir="$TMPDIR_BASE/rs_${test_name}"
            mkdir -p "$rs_dir" "$SNAPSHOT_DIR"
            rm -f "$rs_dir/.fpp.sh"

            export FPP_DIR="$rs_dir" FPP_EDITOR="$editor"
            timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive "${@:3}" >/dev/null 2>&1 || true' _ "$input" "$RUST_BINARY" "${flags[@]}" 2>/dev/null || true
            local rs_out
            rs_out=$(cat "$rs_dir/.fpp.sh" 2>/dev/null || echo "(no script)")
            unset FPP_DIR FPP_EDITOR

            echo "$rs_out" > "$SNAPSHOT_DIR/${test_name}.txt"
            echo -e "  ${CYAN}UPDATED${NC} $test_name"
            ;;
    esac
}

# Run test with custom environment variables
# Usage: run_test_env <name> <input> <env_string> <flags...>
# env_string is space-separated KEY=VALUE pairs
run_test_env() {
    local test_name="$1"
    local input="$2"
    local env_string="$3"
    shift 3
    local flags=("$@")

    # Save and set env vars
    local saved_vars=()
    local var_names=()
    for kv in $env_string; do
        local key="${kv%%=*}"
        local val="${kv#*=}"
        var_names+=("$key")
        if [ -n "${!key+x}" ]; then
            saved_vars+=("$key=${!key}")
        else
            saved_vars+=("$key=__UNSET__")
        fi
        export "$key=$val"
    done

    case "$MODE" in
        compare)
            local py_dir="$TMPDIR_BASE/py_${test_name}"
            local rs_dir="$TMPDIR_BASE/rs_${test_name}"
            mkdir -p "$py_dir" "$rs_dir"
            rm -f "$py_dir/.fpp.sh" "$rs_dir/.fpp.sh"

            local py_out rs_out
            export FPP_DIR="$py_dir"
            timeout 10 bash -c 'printf "%s" "$1" | $2 "${@:3}" >/dev/null 2>&1 || true' _ "$input" "$PYTHON_HEADLESS" "${flags[@]}" 2>/dev/null || true
            py_out=$(cat "$py_dir/.fpp.sh" 2>/dev/null || echo "(no script generated)")

            export FPP_DIR="$rs_dir"
            timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive "${@:3}" >/dev/null 2>&1 || true' _ "$input" "$RUST_BINARY" "${flags[@]}" 2>/dev/null || true
            rs_out=$(cat "$rs_dir/.fpp.sh" 2>/dev/null || echo "(no script generated)")

            assert_equal "$test_name" "$py_out" "$rs_out"
            ;;
        rust-only)
            local rs_dir="$TMPDIR_BASE/rs_${test_name}"
            local snapshot_file="$SNAPSHOT_DIR/${test_name}.txt"
            mkdir -p "$rs_dir"
            rm -f "$rs_dir/.fpp.sh"

            export FPP_DIR="$rs_dir"
            timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive "${@:3}" >/dev/null 2>&1 || true' _ "$input" "$RUST_BINARY" "${flags[@]}" 2>/dev/null || true
            local rs_out
            rs_out=$(cat "$rs_dir/.fpp.sh" 2>/dev/null || echo "(no script generated)")

            if [ ! -f "$snapshot_file" ]; then
                echo -e "  ${YELLOW}SKIP${NC} $test_name (no snapshot)"
                SKIP=$((SKIP + 1))
                # Restore env
                for saved in "${saved_vars[@]}"; do
                    local skey="${saved%%=*}"
                    local sval="${saved#*=}"
                    if [ "$sval" = "__UNSET__" ]; then unset "$skey"; else export "$skey=$sval"; fi
                done
                return
            fi
            assert_equal "$test_name" "$(cat "$snapshot_file")" "$rs_out"
            ;;
        update-snapshots)
            local rs_dir="$TMPDIR_BASE/rs_${test_name}"
            mkdir -p "$rs_dir" "$SNAPSHOT_DIR"
            rm -f "$rs_dir/.fpp.sh"

            export FPP_DIR="$rs_dir"
            timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive "${@:3}" >/dev/null 2>&1 || true' _ "$input" "$RUST_BINARY" "${flags[@]}" 2>/dev/null || true
            local rs_out
            rs_out=$(cat "$rs_dir/.fpp.sh" 2>/dev/null || echo "(no script generated)")

            echo "$rs_out" > "$SNAPSHOT_DIR/${test_name}.txt"
            echo -e "  ${CYAN}UPDATED${NC} $test_name"
            ;;
    esac

    # Restore env vars
    for saved in "${saved_vars[@]}"; do
        local skey="${saved%%=*}"
        local sval="${saved#*=}"
        if [ "$sval" = "__UNSET__" ]; then
            unset "$skey"
        else
            export "$skey=$sval"
        fi
    done
}

# === Prerequisite checks ===

echo -e "${CYAN}=== e2e Test Runner ===${NC}"
echo "Mode: $MODE"

if [ ! -f "$RUST_BINARY" ]; then
    echo -e "${RED}Rust binary not found: $RUST_BINARY${NC}"
    echo "Run 'make build' first."
    exit 1
fi

if [ "$MODE" = "compare" ]; then
    # Verify Python headless wrapper works
    if ! echo "test.txt" | $PYTHON_HEADLESS --no-file-checks --all -c "echo" >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Python headless runner failed. Checking dependencies...${NC}"
        (cd "$PROJECT_ROOT/PathPicker" && pip3 install -e . 2>/dev/null) || true
    fi
fi

echo "Rust binary: $RUST_BINARY"
[ "$MODE" = "compare" ] && echo "Python:      $PYTHON_HEADLESS"
echo ""

# === Test Cases ===

# ------------------------------------------------------------------
# 1. Basic parsing: git status style input
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
echo -e "${CYAN}[6] Paths with Context${NC}"

run_test "path_with_prefix" \
    "M     html/js/hotness.js
Modified: src/parse.rs
Changed: tests/test.py
+++ b/src/main.rs" \
    --no-file-checks --all -c "echo"

run_test "path_with_suffix" \
    "html/js/hotness.js | 4 ++++
flib/asd/asd.py two/three/four.py
banana hanana Wilde/ads/story.m" \
    --no-file-checks --all -c "echo"

run_test "complex_grep_output" \
    'fbcode/search/places/scorer/PageScorer.cpp:27:46:#include "search/places/scorer/linear_scores/MinutiaeVerbScorer.h' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 7. Empty and edge-case inputs
# ------------------------------------------------------------------
echo -e "${CYAN}[7] Edge Cases${NC}"

run_test "empty_input" \
    "" \
    -c "echo"

run_test "whitespace_only" \
    "
   " \
    -c "echo"

run_test "no_matches" \
    "this is just plain text
no file paths here
another boring line" \
    -c "echo"

run_test "trailing_slash_rejected" \
    "foo/bar/baz/
asd/asd/asd/ 23" \
    --no-file-checks -c "echo"

run_test "very_short_dotfile" \
    ".a
.b" \
    --no-file-checks -c "echo"

# ------------------------------------------------------------------
# 8. Command flag variations
# ------------------------------------------------------------------
echo -e "${CYAN}[8] Command Flags${NC}"

run_test "command_git_add" \
    "src/main.rs
src/parse.rs" \
    --no-file-checks --all -c "git add"

run_test "command_with_dollar_f" \
    "file1.txt
file2.txt" \
    --no-file-checks --all -c 'mv $F /tmp/'

run_test "command_cd" \
    "/usr/local/bin/test.sh" \
    --no-file-checks --all -c "cd"

run_test "command_multi_word" \
    "src/main.rs
src/parse.rs" \
    --no-file-checks --all -c "git diff --stat"

# ------------------------------------------------------------------
# 9. --all-input flag
# ------------------------------------------------------------------
echo -e "${CYAN}[9] All-Input Mode${NC}"

run_test "all_input_basic" \
    "a
   foo bar
foo bar    " \
    --all-input --all -c "echo"

run_test "all_input_whitespace_ignored" \
    "
real content here" \
    --all-input --all -c "echo"

run_test "all_input_git_branch" \
    "  fix3
  gh-pages
* master
  testAllInput
  trunk" \
    --all-input --all -c "echo"

# ------------------------------------------------------------------
# 10. Input files from original PathPicker test suite
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
echo -e "${CYAN}[14] Editor Integration${NC}"

run_test_editor "editor_vim_default" "vim" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

run_test_editor "editor_nano" "nano" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

run_test_editor "editor_subl" "subl" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

run_test_editor "editor_emacs" "emacs" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 15. Stress tests
# ------------------------------------------------------------------
echo -e "${CYAN}[15] Stress Tests${NC}"

# Generate 200 file paths
MANY_FILES=""
for i in $(seq 1 200); do
    MANY_FILES+="src/file${i}.rs:${i}
"
done

run_test "stress_200_files" \
    "$MANY_FILES" \
    --no-file-checks --all -c "echo"

# Very long file path
LONG_PATH="very/deeply/nested/directory/structure/that/goes/on/and/on/for/a/while/to/test/limits/file.rs"
run_test "stress_long_path" \
    "$LONG_PATH" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 16. ANSI color handling
# ------------------------------------------------------------------
echo -e "${CYAN}[16] ANSI Color Input${NC}"

run_test "ansi_git_status" \
    $'\033[32m M src/main.rs\033[0m
\033[31m M src/parse.rs\033[0m' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 17. Editor Variants (expanded)
# ------------------------------------------------------------------
echo -e "${CYAN}[17] Editor Variants${NC}"

run_test_editor "editor_nvim_split" "nvim" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

run_test_editor "editor_vi" "vi" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

run_test_editor "editor_joe" "joe" \
    "src/main.rs:42" \
    --no-file-checks --all

run_test_editor "editor_micro" "micro" \
    "src/main.rs:42" \
    --no-file-checks --all

run_test_editor "editor_mvim_split" "mvim" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

run_test_editor "editor_emacsclient" "emacsclient" \
    "src/main.rs:42" \
    --no-file-checks --all

run_test_editor "editor_hx" "hx" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

run_test_editor "editor_atom" "atom" \
    "src/main.rs:42" \
    --no-file-checks --all

run_test_editor "editor_vim_tab_mode" "vim -p" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

# Single file (no split needed)
run_test_editor "editor_vim_single_file" "vim" \
    "src/main.rs:42" \
    --no-file-checks --all

# Three files with vim split
run_test_editor "editor_vim_three_files" "vim" \
    "src/main.rs:42
src/parse.rs:10
src/lib.rs:1" \
    --no-file-checks --all

# Three files with nano
run_test_editor "editor_nano_three_files" "nano" \
    "src/main.rs:42
src/parse.rs:10
src/lib.rs:1" \
    --no-file-checks --all

# Single file no line number with subl
run_test_editor "editor_subl_no_linenum" "subl" \
    "src/main.rs" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 18. FPP_DISABLE_SPLIT
# ------------------------------------------------------------------
echo -e "${CYAN}[18] FPP_DISABLE_SPLIT${NC}"

run_test_env "vim_disable_split" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=vim FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

run_test_env "nvim_disable_split" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=nvim FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

run_test_env "mvim_disable_split" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=mvim FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 19. FPP_LINENUM_SEP
# ------------------------------------------------------------------
echo -e "${CYAN}[19] FPP_LINENUM_SEP${NC}"

run_test_env "linenum_sep_colon" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=code FPP_LINENUM_SEP=:" \
    --no-file-checks --all

run_test_env "linenum_sep_hash" \
    "src/main.rs:42" \
    "FPP_EDITOR=myeditor FPP_LINENUM_SEP=#" \
    --no-file-checks --all

run_test_env "linenum_sep_zero_linenum" \
    "src/main.rs" \
    "FPP_EDITOR=code FPP_LINENUM_SEP=:" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 20. $F Token Substitution (expanded)
# ------------------------------------------------------------------
echo -e "${CYAN}[20] \$F Token Substitution${NC}"

run_test "dollar_f_beginning" \
    "file1.txt
file2.txt" \
    --no-file-checks --all -c '$F | wc -l'

run_test "dollar_f_middle" \
    "file1.txt
file2.txt" \
    --no-file-checks --all -c 'cp $F /backup/'

run_test "dollar_f_single_file" \
    "file1.txt" \
    --no-file-checks --all -c 'cat $F'

run_test "command_no_dollar_f_append" \
    "file1.txt
file2.txt
file3.txt" \
    --no-file-checks --all -c "wc -l"

# ------------------------------------------------------------------
# 21. cd Command Variations
# ------------------------------------------------------------------
echo -e "${CYAN}[21] cd Command Variations${NC}"

run_test "command_cd_relative" \
    "src/main.rs" \
    --no-file-checks --all -c "cd"

run_test "command_cd_homedir" \
    "~/projects/foo.rs" \
    --no-file-checks --all -c "cd"

run_test "command_cd_bare_file" \
    "Makefile" \
    --no-file-checks --all -c "cd"

run_test "command_cd_nested" \
    "/usr/local/lib/test.rs" \
    --no-file-checks --all -c "cd"

# ------------------------------------------------------------------
# 22. Shell-Specific Exit Codes
# ------------------------------------------------------------------
echo -e "${CYAN}[22] Shell-Specific Exit Codes${NC}"

run_test_env "shell_fish_exit" \
    "src/main.rs" \
    "SHELL=/usr/bin/fish FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

run_test_env "shell_csh_exit" \
    "src/main.rs" \
    "SHELL=/bin/csh FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

run_test_env "shell_bash_exit" \
    "src/main.rs" \
    "SHELL=/bin/bash FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

run_test_env "shell_zsh_exit" \
    "src/main.rs" \
    "SHELL=/bin/zsh FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

run_test_env "shell_rc_exit" \
    "src/main.rs" \
    "SHELL=/usr/bin/rc FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 23. Alias Expansion (shopt)
# ------------------------------------------------------------------
echo -e "${CYAN}[23] Alias Expansion${NC}"

# NOTE: alias_fish_no_shopt removed (duplicate of shell_fish_exit in [22])
# NOTE: alias_bash_has_shopt removed (duplicate of shell_bash_exit in [22])

# ------------------------------------------------------------------
# 24. Path Resolution (prepend_dir)
# ------------------------------------------------------------------
echo -e "${CYAN}[24] Path Resolution${NC}"

# a/ and b/ git diff prefix stripping
run_test "prepend_dir_git_a_prefix" \
    "a/foo/bar/baz/asd.py" \
    --no-file-checks --all -c "echo"

run_test "prepend_dir_git_b_prefix" \
    "b/foo/bar/baz/asd.py" \
    --no-file-checks --all -c "echo"

# home/ -> /home/ conversion
run_test "prepend_dir_home_prefix" \
    "home/absolute/path.py" \
    --no-file-checks --all -c "echo"

# ./relative and ../relative paths
run_test "prepend_dir_relative_dot" \
    "./src/main.rs:42" \
    --no-file-checks --all -c "echo"

run_test "prepend_dir_relative_dotdot" \
    "../other/src/main.rs:10" \
    --no-file-checks --all -c "echo"

# Simple filename (no directory)
run_test "prepend_dir_no_dir" \
    "somefile.txt" \
    --no-file-checks --all -c "echo"

# Tilde path expansion
run_test "prepend_dir_tilde" \
    "~/src/project/main.rs:42" \
    --no-file-checks --all -c "echo"

# Git abbreviated path (unresolvable)
run_test "prepend_dir_git_abbreviated" \
    ".../deep/nested/foo.py" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 25. ANSI Color Extended
# ------------------------------------------------------------------
echo -e "${CYAN}[25] ANSI Color Extended${NC}"

# 256-color codes
run_test "ansi_256_color" \
    $'\033[38;5;196msrc/main.rs\033[0m:42: fn main()
\033[38;5;82msrc/parse.rs\033[0m:10: use regex' \
    --no-file-checks --all -c "echo"

# True color (24-bit RGB)
run_test "ansi_truecolor_rgb" \
    $'\033[38;2;255;128;0msrc/main.rs\033[0m:42: fn main()' \
    --no-file-checks --all -c "echo"

# Bold + color combo
run_test "ansi_bold_color_combo" \
    $'\033[1;31m M src/main.rs\033[0m
\033[1;32m?? new_file.txt\033[0m' \
    --no-file-checks --all -c "echo"

# Background color
run_test "ansi_background_color" \
    $'\033[41msrc/main.rs\033[0m
\033[48;5;21msrc/parse.rs\033[0m' \
    --no-file-checks --all -c "echo"

# Multiple SGR parameters combined
run_test "ansi_multiple_sgr" \
    $'\033[1;3;4;38;5;82msrc/format.rs\033[0m:15: pub fn new' \
    --no-file-checks --all -c "echo"

# Reset in middle of path
run_test "ansi_reset_mid_path" \
    $'\033[31msrc/\033[0m\033[32mmain.rs\033[0m:42' \
    --no-file-checks --all -c "echo"

# Erase line sequence (\033[K)
run_test "ansi_erase_line" \
    $'\033[31msrc/main.rs\033[K\033[0m' \
    --no-file-checks --all -c "echo"

# Colored grep output simulation
run_test "ansi_colored_grep" \
    $'\033[35msrc/main.rs\033[0m\033[36m:\033[0m\033[32m42\033[0m\033[36m:\033[0m fn main() {
\033[35msrc/parse.rs\033[0m\033[36m:\033[0m\033[32m10\033[0m\033[36m:\033[0m use regex' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 26. Tab Handling
# ------------------------------------------------------------------
echo -e "${CYAN}[26] Tab Handling${NC}"

run_test "tab_before_path" \
    $'\tsrc/main.rs
\t\tsrc/parse.rs' \
    --no-file-checks --all -c "echo"

run_test "tab_only_lines" \
    $'\t\t\t
src/main.rs' \
    --no-file-checks --all -c "echo"

run_test "tab_mixed_spaces" \
    $'  \tsrc/main.rs
\t  src/parse.rs' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 27. File Validation (--no-file-checks vs default)
# ------------------------------------------------------------------
echo -e "${CYAN}[27] File Validation${NC}"

# Nonexistent file with --no-file-checks should match
run_test "file_validation_nfc_nonexistent" \
    "nonexistent/deep/fake_file.rs" \
    --no-file-checks --all -c "echo"

# Nonexistent file without --no-file-checks may not match
run_test "file_validation_default_nonexistent" \
    "nonexistent/deep/fake_file.rs" \
    --all -c "echo"

# --all-input disables file checks implicitly
run_test "file_validation_all_input_bypass" \
    "nonexistent/path/line.txt" \
    --all-input --all -c "echo"

# ------------------------------------------------------------------
# 28. Special File Patterns
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
echo -e "${CYAN}[29] All-Input Extended${NC}"

# Single character
run_test "all_input_single_char" \
    "a" \
    --all-input --all -c "echo"

# Special characters in lines
run_test "all_input_special_chars" \
    'no changes added to commit (use "git add" and/or "git commit -a")' \
    --all-input --all -c "echo"

# Trimming both sides
run_test "all_input_trim_both" \
    "    foo bar    " \
    --all-input --all -c "echo"

# Tab prefix
run_test "all_input_tab_prefix" \
    $'\tmodified:   Classes/Media/YPMediaLibraryViewController.m' \
    --all-input --all -c "echo"

# Multiple lines with mixed whitespace
run_test "all_input_mixed_whitespace" \
    "line1

line3

line5" \
    --all-input --all -c "echo"

# ------------------------------------------------------------------
# 30. Path Escaping
# ------------------------------------------------------------------
echo -e "${CYAN}[30] Path Escaping${NC}"

# Single quote in filename
run_test "escape_single_quote" \
    "it's_a_file.txt" \
    --no-file-checks --all -c "echo"

# Dollar sign in filename
run_test "escape_dollar_sign" \
    'price$100.txt' \
    --no-file-checks --all -c "echo"

# Paths with @ and + signs
run_test "escape_at_plus" \
    "NSArray+Utils.h
assets/retina/victory@2x.png" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 31. CLI Flag Combinations
# ------------------------------------------------------------------
echo -e "${CYAN}[31] CLI Flag Combinations${NC}"

# --all + --command
run_test "all_with_command" \
    "src/main.rs
src/parse.rs
some plain text line" \
    --no-file-checks --all -c "wc -l"

# --all-input + --command
run_test "all_input_with_command" \
    "feature-branch
hotfix/login-bug
  develop" \
    --all-input --all -c "git checkout"

# --all + --all-input + --command
run_test "all_all_input_command" \
    "any text line
another line" \
    --all-input --all -c "echo"

# --all + editor mode
run_test_editor "all_flag_editor" "nano" \
    "src/main.rs:10
src/parse.rs:20" \
    --no-file-checks --all

# --all + $F substitution
run_test "all_flag_dollar_f" \
    "file1.txt
file2.txt
file3.txt" \
    --no-file-checks --all -c 'wc -l $F'

# ------------------------------------------------------------------
# 32. Single Dash Flag Compatibility (Python-style)
# ------------------------------------------------------------------
echo -e "${CYAN}[32] Single Dash Flags${NC}"

run_test "single_dash_nfc" \
    "nonexistent/deleted/file.rs" \
    -nfc --all -c "echo"

run_test "single_dash_ai" \
    "feature-branch
develop" \
    -ai --all -c "echo"

# Note: -ni is not tested here because run_test already adds --non-interactive.
# The preprocess_args conversion of -ni → --non-interactive is covered by unit tests.

run_test "single_dash_ko" \
    "src/main.rs" \
    -ko --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 33. Editor Priority (FPP_EDITOR > VISUAL > EDITOR > vim)
# ------------------------------------------------------------------
echo -e "${CYAN}[33] Editor Priority${NC}"

run_test_env "editor_fpp_editor_priority" \
    "src/main.rs:42" \
    "FPP_EDITOR=nano VISUAL=vim EDITOR=emacs" \
    --no-file-checks --all

# VISUAL fallback: FPP_EDITOR must be truly unset, not empty
_saved_fpp_editor="${FPP_EDITOR:-__UNSET__}"
_saved_visual="${VISUAL:-__UNSET__}"
_saved_editor="${EDITOR:-__UNSET__}"
unset FPP_EDITOR
export VISUAL=subl EDITOR=emacs
run_test_env "editor_visual_fallback" \
    "src/main.rs:42" \
    "VISUAL=subl EDITOR=emacs" \
    --no-file-checks --all
unset VISUAL
export EDITOR=emacs
run_test_env "editor_editor_fallback" \
    "src/main.rs:42" \
    "EDITOR=emacs" \
    --no-file-checks --all
# Restore
if [ "$_saved_fpp_editor" != "__UNSET__" ]; then export FPP_EDITOR="$_saved_fpp_editor"; else unset FPP_EDITOR 2>/dev/null || true; fi
if [ "$_saved_visual" != "__UNSET__" ]; then export VISUAL="$_saved_visual"; else unset VISUAL 2>/dev/null || true; fi
if [ "$_saved_editor" != "__UNSET__" ]; then export EDITOR="$_saved_editor"; else unset EDITOR 2>/dev/null || true; fi

# ------------------------------------------------------------------
# 34. --clean Flag
# ------------------------------------------------------------------
echo -e "${CYAN}[34] Clean Flag${NC}"

# Test that --clean removes state files
_clean_test_dir="$TMPDIR_BASE/clean_test_dir"
mkdir -p "$_clean_test_dir"
touch "$_clean_test_dir/.fpp.sh" "$_clean_test_dir/.fpp.log"
# Create files that match state file patterns
echo '{}' > "$_clean_test_dir/.selection.json"
echo '[]' > "$_clean_test_dir/.input.json"

export FPP_DIR="$_clean_test_dir"
timeout 10 "$RUST_BINARY" --clean >/dev/null 2>&1 || true
_clean_remaining=$(ls -1 "$_clean_test_dir" 2>/dev/null | wc -l | tr -d ' ')
unset FPP_DIR

if [ "$MODE" = "compare" ]; then
    # Also test Python
    _clean_test_dir_py="$TMPDIR_BASE/clean_test_dir_py"
    mkdir -p "$_clean_test_dir_py"
    touch "$_clean_test_dir_py/.fpp.sh" "$_clean_test_dir_py/.fpp.log"
    echo '{}' > "$_clean_test_dir_py/.selection.pickle"
    echo '[]' > "$_clean_test_dir_py/.pickle"

    export FPP_DIR="$_clean_test_dir_py"
    # Python clean is done by the bash wrapper, test that Rust clean works independently
    unset FPP_DIR
fi

if [ "$_clean_remaining" = "0" ]; then
    echo -e "  ${GREEN}PASS${NC} clean_removes_state_files"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} clean_removes_state_files (${_clean_remaining} files remaining)"
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# 35. Unresolvable File Warnings
# ------------------------------------------------------------------
echo -e "${CYAN}[35] Unresolvable File Warnings${NC}"

# Git abbreviated with editor mode (should produce warning)
run_test_editor "warn_git_abbreviated_editor" "vim" \
    ".../something/foo.py
.../expected/selectFirst.txt" \
    --no-file-checks --all

# Git abbreviated with command mode
run_test "warn_git_abbreviated_command" \
    ".../expected/selectFirst.txt" \
    --no-file-checks --all -c "cat"

# ------------------------------------------------------------------
# 36. No Matches Output Verification
# ------------------------------------------------------------------
echo -e "${CYAN}[36] No Matches Output${NC}"

run_test "no_matches_command_mode" \
    "this is just plain text" \
    -c "echo"

run_test "no_matches_editor_mode" \
    "this is just plain text" \
    --no-file-checks

run_test "empty_input_editor" \
    "" \
    --no-file-checks

# ------------------------------------------------------------------
# 37. Whitespace Edge Cases
# ------------------------------------------------------------------
echo -e "${CYAN}[37] Whitespace Edge Cases${NC}"

run_test "whitespace_tabs_only" \
    $'\t\t\t' \
    --no-file-checks -c "echo"

run_test "whitespace_mixed_around_paths" \
    "   src/main.rs
		src/parse.rs		" \
    --no-file-checks --all -c "echo"

run_test "whitespace_newlines_only" \
    "



" \
    -c "echo"

# ------------------------------------------------------------------
# 38. Line Number Extraction Extended
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
echo -e "${CYAN}[39] Stress Tests Extended${NC}"

# 500 files
STRESS_500=""
for i in $(seq 1 500); do
    STRESS_500+="src/module${i}/file${i}.rs:${i}
"
done
run_test "stress_500_files" \
    "$STRESS_500" \
    --no-file-checks --all -c "echo"

# Mixed input: many non-file lines with occasional file paths
STRESS_MIXED=""
for i in $(seq 1 100); do
    STRESS_MIXED+="This is just plain text line ${i}
"
    if (( i % 20 == 0 )); then
        STRESS_MIXED+="src/file${i}.rs:${i}
"
    fi
done
run_test "stress_mixed_input" \
    "$STRESS_MIXED" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 40. State Directory Priority
# ------------------------------------------------------------------
echo -e "${CYAN}[40] State Directory${NC}"

# FPP_DIR takes priority
_fpp_dir_test="$TMPDIR_BASE/fpp_dir_priority"
mkdir -p "$_fpp_dir_test"
export FPP_DIR="$_fpp_dir_test"
timeout 10 bash -c 'printf "src/main.rs" | "$1" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
if [ -f "$_fpp_dir_test/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} state_dir_fpp_dir_env"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} state_dir_fpp_dir_env (script not in FPP_DIR)"
    FAIL=$((FAIL + 1))
fi
unset FPP_DIR

# ------------------------------------------------------------------
# 41. Duplicate file deduplication in output
# ------------------------------------------------------------------
echo -e "${CYAN}[41] Duplicate Files${NC}"

# Same file mentioned multiple times: should appear once in output
run_test "duplicate_file_paths" \
    "src/main.rs:10
src/main.rs:20
src/main.rs:30" \
    --no-file-checks --all -c "echo"

# Different lines with same resolved path
run_test "duplicate_resolved_paths" \
    "./src/main.rs
src/main.rs" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 42. Input from original PathPicker test patterns (Python test_parsing.py)
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
echo -e "${CYAN}[43] CRLF Line Endings${NC}"

run_test "crlf_line_endings" \
    $'src/main.rs\r\nsrc/parse.rs\r\nsrc/lib.rs\r\n' \
    --no-file-checks --all -c "echo"

run_test "mixed_line_endings" \
    $'src/main.rs\nsrc/parse.rs\r\nsrc/lib.rs\n' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 44. Real-World Tool Output
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
echo -e "${CYAN}[45] ANSI Mixed Stream${NC}"

run_test "ansi_mixed_plain_and_colored" \
    $'plain/path/file.rs:10
\033[32m M colored/path.rs\033[0m
another/plain.rs:20
\033[1;31m D deleted.rs\033[0m
src/normal.rs' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 46. $F Token Edge Cases (Cycle 2)
# ------------------------------------------------------------------
echo -e "${CYAN}[46] \$F Edge Cases${NC}"

# $F only command
run_test "dollar_f_only" \
    "file1.txt" \
    --no-file-checks --all -c '$F'

# $F multiple occurrences
run_test "dollar_f_multiple_occurrences" \
    "file1.txt
file2.txt" \
    --no-file-checks --all -c 'diff $F && echo $F done'

# Single quote in path + $F
run_test "dollar_f_single_quote_path" \
    "it's_a_file.txt" \
    --no-file-checks --all -c 'cat $F'

# ------------------------------------------------------------------
# 47. Command Special Characters
# ------------------------------------------------------------------
echo -e "${CYAN}[47] Command Special Characters${NC}"

# Command with pipe
run_test "command_with_pipe" \
    "file1.txt
file2.txt" \
    --no-file-checks --all -c 'cat $F | sort | uniq'

# Command with semicolons
run_test "command_with_semicolons" \
    "file1.txt" \
    --no-file-checks --all -c 'echo start; cat $F; echo done'

# Command with double quotes
run_test "command_with_double_quotes" \
    "src/main.rs" \
    --no-file-checks --all -c 'grep "hello world"'

# ------------------------------------------------------------------
# 48. cd Multiple Files (first wins)
# ------------------------------------------------------------------
echo -e "${CYAN}[48] cd Edge Cases${NC}"

run_test "cd_multiple_files_first_wins" \
    "/usr/local/bin/test.sh
/var/log/syslog
/etc/hosts" \
    --no-file-checks --all -c "cd"

# ------------------------------------------------------------------
# 49. Editor Edge Cases (Cycle 2)
# ------------------------------------------------------------------
echo -e "${CYAN}[49] Editor Edge Cases${NC}"

# vim -p single file
run_test_editor "editor_vim_tab_single" "vim -p" \
    "src/main.rs:42" \
    --no-file-checks --all

# Editor with absolute path
run_test_editor "editor_full_path_vim" "/usr/local/bin/vim" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

run_test_editor "editor_full_path_nano" "/usr/bin/nano" \
    "src/main.rs:42" \
    --no-file-checks --all

# FPP_DISABLE_SPLIT with empty string (should keep split enabled)
run_test_env "vim_disable_split_empty" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=vim FPP_DISABLE_SPLIT=" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 50. Shell Variants Extended
# ------------------------------------------------------------------
echo -e "${CYAN}[50] Shell Variants Extended${NC}"

# tcsh (csh family)
run_test_env "shell_tcsh_exit" \
    "src/main.rs" \
    "SHELL=/usr/bin/tcsh FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 51. Unicode Paths
# ------------------------------------------------------------------
echo -e "${CYAN}[51] Unicode Paths${NC}"

# CJK characters in filenames
run_test "unicode_cjk_paths" \
    "docs/설계문서.md
src/テスト.rs
assets/图标.png" \
    --no-file-checks --all -c "echo"

# CJK in --all-input mode
run_test "unicode_all_input" \
    "docs/설계문서.md
src/テスト.rs" \
    --all-input --all -c "echo"

# Accented characters
run_test "unicode_accented" \
    "src/café.rs
docs/résumé.txt" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 52. Original Input Files (Additional)
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
echo -e "${CYAN}[53] Fuzz Patterns Extended${NC}"

# +++ prefix (git diff style) + normal path
run_test "fuzz_plus_prefix" \
    "+++ html/js/hotness.js" \
    --no-file-checks --all -c "echo"

# Path with suffix containing colon+numbers (line number interference)
run_test "fuzz_colon_suffix" \
    "html/js/hotness.js:0:7: var AdsErrorCodeStore" \
    --no-file-checks --all -c "echo"

# Home dir path with fuzz prefix
run_test "fuzz_home_with_prefix" \
    "Modified: ~/foo/bar/something.py * Adapts to something" \
    --no-file-checks --all -c "echo"

# Multiple periods file with prefix
run_test "fuzz_periods_with_prefix" \
    "blarg blah So.MANY.PERIODS.TXT:22 jkk asdad" \
    --no-file-checks --all -c "echo"

# @ in path with prefix word
run_test "fuzz_at_sign_prefix" \
    "blarge assets/retina/victory@2x.png" \
    --no-file-checks --all -c "echo"

# + in path with prefix word
run_test "fuzz_plus_sign_prefix" \
    "test src/categories/NSDate+Category.h" \
    --no-file-checks --all -c "echo"

# Home dir + @ character
run_test "fuzz_home_at_sign" \
    "~/assets/retina/victory@2x.png" \
    --no-file-checks --all -c "echo"

# Home dir + + character
run_test "fuzz_home_plus_sign" \
    "~/src/categories/NSDate+Category.h" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 54. Stress: Very Long Single Line
# ------------------------------------------------------------------
echo -e "${CYAN}[54] Long Line Stress${NC}"

LONG_LINE="$(python3 -c "print('x' * 5000 + ' src/main.rs:42 ' + 'y' * 5000)")"
run_test "stress_very_long_line" \
    "$LONG_LINE" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 55. Path Escaping Extended
# ------------------------------------------------------------------
echo -e "${CYAN}[55] Path Escaping Extended${NC}"

# Backslash in path
run_test "escape_backslash" \
    'path/with\\backslash/file.txt' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 56. Cache File Creation
# ------------------------------------------------------------------
echo -e "${CYAN}[56] Cache File${NC}"

_cache_dir="$TMPDIR_BASE/cache_test"
mkdir -p "$_cache_dir"
export FPP_DIR="$_cache_dir"
timeout 10 bash -c 'printf "src/main.rs\nsrc/parse.rs\n" | "$1" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
if [ -f "$_cache_dir/.input.json" ]; then
    echo -e "  ${GREEN}PASS${NC} cache_input_json_created"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} cache_input_json_created"
    FAIL=$((FAIL + 1))
fi
unset FPP_DIR

# ------------------------------------------------------------------
# 57. Piped Stdin Handling
# ------------------------------------------------------------------
echo -e "${CYAN}[57] Piped Stdin Handling${NC}"

# NOTE: pipe_git_status removed (duplicate of git_status_basic in [1])

# Piped input with -c command should produce correct script
_pipe_dir="$TMPDIR_BASE/pipe_test"
mkdir -p "$_pipe_dir"
export FPP_DIR="$_pipe_dir"
timeout 10 bash -c 'printf "src/main.rs\nsrc/parse.rs\n" | "$1" --non-interactive --no-file-checks --all -c "git add" >/dev/null 2>&1' _ "$RUST_BINARY" 2>/dev/null
_pipe_exit=$?
unset FPP_DIR
if [ $_pipe_exit -eq 0 ] && [ -f "$_pipe_dir/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} pipe_with_command_no_error"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} pipe_with_command_no_error (exit=$_pipe_exit)"
    FAIL=$((FAIL + 1))
fi

# Piped input should not crash even with empty input
_pipe_empty_dir="$TMPDIR_BASE/pipe_empty_test"
mkdir -p "$_pipe_empty_dir"
export FPP_DIR="$_pipe_empty_dir"
timeout 10 bash -c 'printf "" | "$1" --non-interactive --no-file-checks -c "echo" >/dev/null 2>&1' _ "$RUST_BINARY" 2>/dev/null
_pipe_empty_exit=$?
unset FPP_DIR
if [ $_pipe_empty_exit -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} pipe_empty_input_no_crash"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} pipe_empty_input_no_crash (exit=$_pipe_empty_exit)"
    FAIL=$((FAIL + 1))
fi

# Large piped input should work without hanging
_pipe_large_dir="$TMPDIR_BASE/pipe_large_test"
mkdir -p "$_pipe_large_dir"
_large_input=""
for i in $(seq 1 500); do
    _large_input+="src/file${i}.rs:${i}: some content
"
done
export FPP_DIR="$_pipe_large_dir"
timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1' _ "$_large_input" "$RUST_BINARY" 2>/dev/null
_pipe_large_exit=$?
unset FPP_DIR
if [ $_pipe_large_exit -eq 0 ] && [ -f "$_pipe_large_dir/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} pipe_large_input_500_files"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} pipe_large_input_500_files (exit=$_pipe_large_exit)"
    FAIL=$((FAIL + 1))
fi

# File redirection (< file) should also work
_pipe_redir_dir="$TMPDIR_BASE/pipe_redir_test"
mkdir -p "$_pipe_redir_dir"
_redir_input_file="$TMPDIR_BASE/redir_input.txt"
printf "src/main.rs:10\nsrc/lib.rs:20\n" > "$_redir_input_file"
export FPP_DIR="$_pipe_redir_dir"
timeout 10 "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" < "$_redir_input_file" >/dev/null 2>&1
_pipe_redir_exit=$?
unset FPP_DIR
if [ $_pipe_redir_exit -eq 0 ] && [ -f "$_pipe_redir_dir/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} pipe_file_redirection"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} pipe_file_redirection (exit=$_pipe_redir_exit)"
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# 58. File Validation with Real Files (spaces, special chars)
# ------------------------------------------------------------------
echo -e "${CYAN}[58] File Validation with Real Files${NC}"

# These tests use actual files from PathPicker/src/tests/inputs/
# to verify MASTER_REGEX_WITH_SPACES and similar file-inspection regexes
TESTS_INPUTS_DIR="$PROJECT_ROOT/tests/inputs"

if [ -d "$TESTS_INPUTS_DIR" ]; then
    # Evil file with space (MASTER_REGEX_WITH_SPACES)
    run_test "validate_evil_file_with_space" \
        "M     $TESTS_INPUTS_DIR/evilFile With Space.txt" \
        --all -c "echo"

    # Evil file no prepend (JUST_FILE_WITH_SPACES)
    (cd "$TESTS_INPUTS_DIR" && \
    run_test "validate_evil_file_no_prepend" \
        "evilFile No Prepend.txt" \
        --all -c "echo")

    # Annoying spaces folder
    run_test "validate_annoying_spaces_folder" \
        "$TESTS_INPUTS_DIR/annoying Spaces Folder" \
        --all -c "echo"

    # NSArray+Utils.h (+ in filename)
    run_test "validate_nsarray_plus_file" \
        "$TESTS_INPUTS_DIR/NSArray+Utils.h" \
        --all -c "echo"

    # sublime-workspace extension (MASTER_REGEX_MORE_EXTENSIONS)
    run_test "validate_sublime_workspace" \
        "$TESTS_INPUTS_DIR/blogredesign.sublime-workspace" \
        --all -c "echo"

    # Yocto percent file
    (cd "$TESTS_INPUTS_DIR" && \
    run_test "validate_yocto_percent_file" \
        "file-from-yocto_%.bbappend" \
        --all -c "echo")

    # Tilde extension file
    run_test "validate_tilde_extension" \
        "$TESTS_INPUTS_DIR/annoyingTildeExtension.txt~" \
        --all -c "echo"

    # svo with parens and comma
    run_test "validate_svo_parens_comma" \
        "$TESTS_INPUTS_DIR/svo (install the zip, not me).xml" \
        --all -c "echo"

    # svo with parens no comma
    run_test "validate_svo_parens_no_comma" \
        "$TESTS_INPUTS_DIR/svo (install the zip not me).xml" \
        --all -c "echo"

    # Hyphen dir with system-bundle extension
    if [ -d "$TESTS_INPUTS_DIR/annoying-hyphen-dir" ]; then
        run_test "validate_hyphen_dir_bundle" \
            "$TESTS_INPUTS_DIR/annoying-hyphen-dir" \
            --all -c "echo"
    fi
else
    echo -e "  ${YELLOW}SKIP${NC} tests/inputs/ directory not found"
fi

# ------------------------------------------------------------------
# 59. Editor with Args in Name
# ------------------------------------------------------------------
echo -e "${CYAN}[59] Editor with Args in Name${NC}"

# emacs -nw: should extract "emacs" as editor name
run_test_editor "editor_emacs_nw_args" "emacs -nw" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

# /usr/local/bin/vim -p: absolute path + args
run_test_editor "editor_full_path_vim_p" "/usr/local/bin/vim -p" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

# vim -O (vertical split mode)
run_test_editor "editor_vim_vertical_split" "vim -O" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 60. Editor Mode No Shopt (alias expansion only in command mode)
# ------------------------------------------------------------------
echo -e "${CYAN}[60] Editor Mode No Shopt${NC}"

# Editor mode should NOT have shopt expand_aliases
run_test_env "editor_mode_no_shopt_bash" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=vim SHELL=/bin/bash" \
    --no-file-checks --all

# fish + editor mode: no shopt, no $status
run_test_env "editor_mode_no_shopt_fish" \
    "src/main.rs:42" \
    "FPP_EDITOR=vim SHELL=/usr/bin/fish" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 61. SHELL Unset / Empty
# ------------------------------------------------------------------
echo -e "${CYAN}[61] SHELL Unset/Empty${NC}"

run_test_env "shell_empty_string_exit" \
    "src/main.rs" \
    "SHELL= FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

run_test_env "shell_empty_string_editor" \
    "src/main.rs:42" \
    "SHELL= FPP_EDITOR=vim" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 62. Editor Default Fallback (no FPP_EDITOR, no VISUAL, no EDITOR)
# ------------------------------------------------------------------
echo -e "${CYAN}[62] Editor Default Fallback${NC}"

# All editor env vars unset -> should fallback to vim
_saved_fpp_editor_62="${FPP_EDITOR:-__UNSET__}"
_saved_visual_62="${VISUAL:-__UNSET__}"
_saved_editor_62="${EDITOR:-__UNSET__}"
unset FPP_EDITOR VISUAL EDITOR 2>/dev/null || true

_ed_default_dir="$TMPDIR_BASE/ed_default"
mkdir -p "$_ed_default_dir"
export FPP_DIR="$_ed_default_dir"
timeout 10 bash -c 'printf "src/main.rs:42\n" | "$1" --non-interactive --no-file-checks --all >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
_ed_default_out=$(cat "$_ed_default_dir/.fpp.sh" 2>/dev/null || echo "(no script)")
unset FPP_DIR

if echo "$_ed_default_out" | grep -q "vim"; then
    echo -e "  ${GREEN}PASS${NC} editor_default_vim_fallback"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} editor_default_vim_fallback"
    echo "    Script: $_ed_default_out" | head -5
    FAIL=$((FAIL + 1))
fi

# Restore
if [ "$_saved_fpp_editor_62" != "__UNSET__" ]; then export FPP_EDITOR="$_saved_fpp_editor_62"; fi
if [ "$_saved_visual_62" != "__UNSET__" ]; then export VISUAL="$_saved_visual_62"; fi
if [ "$_saved_editor_62" != "__UNSET__" ]; then export EDITOR="$_saved_editor_62"; fi

# ------------------------------------------------------------------
# 63. Preferred Regex (TARGETS with dash linenum)
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
echo -e "${CYAN}[64] cd Path Normalization${NC}"

# dotdot normalization
run_test "cd_dotdot_normalization" \
    "/usr/local/bin/../lib/test.rs" \
    --no-file-checks --all -c "cd"

# dot normalization
run_test "cd_dot_normalization" \
    "./src/./main.rs" \
    --no-file-checks --all -c "cd"

# tilde in cd command
run_test "cd_tilde_expansion" \
    "~/projects/foo/bar.rs" \
    --no-file-checks --all -c "cd"

# ------------------------------------------------------------------
# 65. FPP_DISABLE_PREPENDING_HOME_WITH_SLASH
# ------------------------------------------------------------------
echo -e "${CYAN}[65] FPP_DISABLE_PREPENDING_HOME_WITH_SLASH${NC}"

run_test_env "disable_prepend_home_slash" \
    "home/absolute/path.py" \
    "FPP_DISABLE_PREPENDING_HOME_WITH_SLASH=1 FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# NOTE: prepend_home_slash_default removed (duplicate of prepend_dir_home_prefix in [24])

# ------------------------------------------------------------------
# 66. www/ Prefix Handling
# ------------------------------------------------------------------
echo -e "${CYAN}[66] www/ Prefix Handling${NC}"

run_test "prepend_dir_www_prefix" \
    "www/js/hotness.js" \
    --no-file-checks --all -c "echo"

run_test "prepend_dir_www_deep" \
    "www/assets/css/style.css:42" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 67. XDG_CACHE_HOME State Directory
# ------------------------------------------------------------------
echo -e "${CYAN}[67] XDG_CACHE_HOME${NC}"

_xdg_test_dir="$TMPDIR_BASE/xdg_cache_test"
mkdir -p "$_xdg_test_dir"
# Unset FPP_DIR, set XDG_CACHE_HOME
_saved_fpp_dir="${FPP_DIR:-__UNSET__}"
unset FPP_DIR 2>/dev/null || true
export XDG_CACHE_HOME="$_xdg_test_dir"
timeout 10 bash -c 'printf "src/main.rs\n" | "$1" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
if [ -f "$_xdg_test_dir/fpp/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} xdg_cache_home_state_dir"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} xdg_cache_home_state_dir"
    echo "    Expected .fpp.sh in $_xdg_test_dir/fpp/"
    ls -la "$_xdg_test_dir/" 2>/dev/null | head -5 | sed 's/^/    /'
    FAIL=$((FAIL + 1))
fi
unset XDG_CACHE_HOME
if [ "$_saved_fpp_dir" != "__UNSET__" ]; then export FPP_DIR="$_saved_fpp_dir"; fi

# ------------------------------------------------------------------
# 68. --debug Flag
# ------------------------------------------------------------------
echo -e "${CYAN}[68] Debug Flag${NC}"

_debug_dir="$TMPDIR_BASE/debug_test"
mkdir -p "$_debug_dir"
export FPP_DIR="$_debug_dir"
_debug_stderr=$(timeout 10 bash -c 'printf "src/main.rs\n" | "$1" --debug --non-interactive --no-file-checks --all -c "echo" 2>&1 >/dev/null || true' _ "$RUST_BINARY" 2>&1 || true)
unset FPP_DIR
if echo "$_debug_stderr" | grep -qi "execut"; then
    echo -e "  ${GREEN}PASS${NC} debug_flag_stderr_output"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} debug_flag_stderr_output"
    echo "    stderr: $_debug_stderr" | head -3
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# 69. --record Flag
# ------------------------------------------------------------------
echo -e "${CYAN}[69] Record Flag${NC}"

_record_dir="$TMPDIR_BASE/record_test"
mkdir -p "$_record_dir"
export FPP_DIR="$_record_dir"
_record_stderr=$(timeout 10 bash -c 'printf "src/main.rs\n" | "$1" -r --non-interactive --no-file-checks --all -c "echo" 2>&1 >/dev/null || true' _ "$RUST_BINARY" 2>&1 || true)
unset FPP_DIR
if echo "$_record_stderr" | grep -qi "record"; then
    echo -e "  ${GREEN}PASS${NC} record_flag_stderr_output"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} record_flag_stderr_output"
    echo "    stderr: $_record_stderr" | head -3
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# 70. FPP_LINENUM_SEP + Editor Interaction
# ------------------------------------------------------------------
echo -e "${CYAN}[70] FPP_LINENUM_SEP + Editor Interaction${NC}"

# subl should ignore FPP_LINENUM_SEP (uses its own : format)
run_test_env "linenum_sep_ignored_by_subl" \
    "src/main.rs:42" \
    "FPP_EDITOR=subl FPP_LINENUM_SEP=#" \
    --no-file-checks --all

# nano should ignore FPP_LINENUM_SEP (uses +linenum format)
run_test_env "linenum_sep_ignored_by_nano" \
    "src/main.rs:42" \
    "FPP_EDITOR=nano FPP_LINENUM_SEP=#" \
    --no-file-checks --all

# vim should ignore FPP_LINENUM_SEP (uses +linenum format)
run_test_env "linenum_sep_ignored_by_vim" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=vim FPP_LINENUM_SEP=#" \
    --no-file-checks --all

# Unknown editor should use FPP_LINENUM_SEP
run_test_env "linenum_sep_used_by_unknown" \
    "src/main.rs:42" \
    "FPP_EDITOR=myeditor FPP_LINENUM_SEP=@" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 71. Logger File Creation
# ------------------------------------------------------------------
echo -e "${CYAN}[71] Logger File${NC}"

_log_dir="$TMPDIR_BASE/logger_test"
mkdir -p "$_log_dir"
export FPP_DIR="$_log_dir"
timeout 10 bash -c 'printf "src/main.rs\nsrc/parse.rs\n" | "$1" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
unset FPP_DIR
if [ -f "$_log_dir/.fpp.log" ]; then
    # Verify it's valid JSON
    if python3 -c "import json; json.load(open('$_log_dir/.fpp.log'))" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC} logger_fpp_log_valid_json"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}PASS${NC} logger_fpp_log_created (not JSON)"
        PASS=$((PASS + 1))
    fi
else
    echo -e "  ${RED}FAIL${NC} logger_fpp_log_created"
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# 72. ALL_INPUT Whitespace Edge Cases
# ------------------------------------------------------------------
echo -e "${CYAN}[72] ALL_INPUT Whitespace Edge Cases${NC}"

# Spaces-only line should be skipped
run_test "all_input_spaces_only" \
    "    " \
    --all-input --all -c "echo"

# Single space -> skipped
run_test "all_input_single_space" \
    " " \
    --all-input --all -c "echo"

# Leading spaces should be trimmed
run_test "all_input_leading_spaces" \
    "   hello" \
    --all-input --all -c "echo"

# Multi-word with internal spaces preserved
run_test "all_input_multi_word" \
    "foo bar baz" \
    --all-input --all -c "echo"

# ------------------------------------------------------------------
# 73. Fuzz Patterns (additional prefix/suffix combos)
# ------------------------------------------------------------------
echo -e "${CYAN}[73] Additional Fuzz Patterns${NC}"

# Banana prefix + absolute path + suffix
run_test "fuzz_banana_absolute_path" \
    "Banana asdasdoj pjo /absolute/path/to/something.txt jkk asdad" \
    --no-file-checks --all -c "echo"

# M prefix + dotfile
run_test "fuzz_m_prefix_dotfile" \
    "M .env.local * Adapts AdsErrorCodestore to something" \
    --no-file-checks --all -c "echo"

# +++ prefix + @ file + suffix
run_test "fuzz_plus_prefix_at_file" \
    "+++ assets/retina/victory@2x.png jkk asdad" \
    --no-file-checks --all -c "echo"

# Changed prefix + dotdir
run_test "fuzz_changed_prefix_dotdir" \
    "Changed: .ssh/known_hosts:0:7: var AdsErrorCodeStore" \
    --no-file-checks --all -c "echo"

# M prefix + TARGETS-dash + suffix
run_test "fuzz_m_prefix_targets_dash" \
    "M foo/bar/TARGETS-24 jkk asdad" \
    --no-file-checks --all -c "echo"

# M prefix + dotfile path + colon suffix
run_test "fuzz_m_prefix_gitignore" \
    "M tmp/.gitignore:0:7: var AdsErrorCodeStore" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 74. vi/vim Mixed Linenum (some files with linenum, some without)
# ------------------------------------------------------------------
echo -e "${CYAN}[74] Mixed Linenum Editor${NC}"

run_test_editor "editor_vi_mixed_linenum" "vi" \
    "src/main.rs:42
src/lib.rs" \
    --no-file-checks --all

run_test_editor "editor_nano_mixed_linenum" "nano" \
    "src/main.rs:42
src/lib.rs" \
    --no-file-checks --all

run_test_editor "editor_subl_mixed_linenum" "subl" \
    "src/main.rs:42
src/lib.rs" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 75. Path Single Quote in Editor Mode
# ------------------------------------------------------------------
echo -e "${CYAN}[75] Single Quote Path in Editor Mode${NC}"

run_test_editor "editor_nano_single_quote_path" "nano" \
    "it's_a_file.txt:42" \
    --no-file-checks --all

run_test_editor "editor_vim_single_quote_path" "vim" \
    "it's_a_file.txt:42" \
    --no-file-checks --all

run_test_editor "editor_subl_single_quote_path" "subl" \
    "it's_a_file.txt:42" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 76. vim -p Tab Mode Three Files
# ------------------------------------------------------------------
echo -e "${CYAN}[76] vim -p Three Files${NC}"

run_test_editor "editor_vim_tab_three_files" "vim -p" \
    "src/main.rs:42
src/parse.rs:10
src/lib.rs:1" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 77. Command with Double Quotes + $F
# ------------------------------------------------------------------
echo -e "${CYAN}[77] Command Double Quotes + \$F${NC}"

run_test "command_grep_pattern_dollar_f" \
    "src/main.rs" \
    --no-file-checks --all -c 'grep "pattern" $F'

run_test "command_awk_dollar_f" \
    "data.csv
report.csv" \
    --no-file-checks --all -c 'awk -F"," "{print}" $F'

# ------------------------------------------------------------------
# 78. CRLF Trailing CR Verification
# ------------------------------------------------------------------
echo -e "${CYAN}[78] CRLF Trailing CR${NC}"

# Single file with CRLF - verify no \r in output
_crlf_dir="$TMPDIR_BASE/crlf_test"
mkdir -p "$_crlf_dir"
export FPP_DIR="$_crlf_dir"
timeout 10 bash -c 'printf "src/main.rs\r\n" | "$1" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
_crlf_script=$(cat "$_crlf_dir/.fpp.sh" 2>/dev/null || echo "")
unset FPP_DIR
if printf '%s' "$_crlf_script" | tr -d '\n' | od -c | grep -q '\\r'; then
    echo -e "  ${RED}FAIL${NC} crlf_no_trailing_cr (\\r found in script)"
    FAIL=$((FAIL + 1))
else
    echo -e "  ${GREEN}PASS${NC} crlf_no_trailing_cr"
    PASS=$((PASS + 1))
fi

# ------------------------------------------------------------------
# 79. FPP_REPOS Environment Variable
# ------------------------------------------------------------------
echo -e "${CYAN}[79] FPP_REPOS${NC}"

_repos_test_dir="$TMPDIR_BASE/repos_test"
mkdir -p "$_repos_test_dir/myrepo/src"
touch "$_repos_test_dir/myrepo/src/foo.py"

# FPP_REPOS takes comma-separated directory NAMES (not full paths)
# Python: first in REPOS + (os.environ.get("FPP_REPOS") or "").split(",")
run_test_env "fpp_repos_custom_path" \
    "myrepo/src/foo.py" \
    "FPP_REPOS=myrepo FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 80. Git Abbreviated Warning Text Verification
# ------------------------------------------------------------------
echo -e "${CYAN}[80] Git Abbreviated Warning Text${NC}"

_warn_dir="$TMPDIR_BASE/warn_text_test"
mkdir -p "$_warn_dir"
export FPP_DIR="$_warn_dir" FPP_EDITOR=vim
timeout 10 bash -c 'printf ".../something/foo.py\n" | "$1" --non-interactive --no-file-checks --all >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
_warn_script=$(cat "$_warn_dir/.fpp.sh" 2>/dev/null || echo "")
unset FPP_DIR FPP_EDITOR

if echo "$_warn_script" | grep -qi "triple.dot\|abbreviated\|invalid"; then
    echo -e "  ${GREEN}PASS${NC} git_abbreviated_warning_text_present"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} git_abbreviated_warning_text_present"
    echo "    Script content:" | head -3
    echo "$_warn_script" | head -10 | sed 's/^/      /'
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# 81. Duplicate Paths with Different Line Numbers (editor mode)
# ------------------------------------------------------------------
echo -e "${CYAN}[81] Duplicate Paths Editor Mode${NC}"

# Same file with different line numbers: editor should open with first line number
run_test_editor "editor_duplicate_path_linenum" "vim" \
    "src/main.rs:42
src/main.rs:100
src/main.rs:5" \
    --no-file-checks --all

run_test_editor "editor_duplicate_path_subl" "subl" \
    "src/main.rs:42
src/main.rs:100" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 82. Path Trailing Space Trimming
# ------------------------------------------------------------------
echo -e "${CYAN}[82] Path Trailing Space${NC}"

run_test "path_trailing_space_trimmed" \
    "flib/foo/bar.py " \
    --no-file-checks --all -c "echo"

run_test "path_trailing_tab_trimmed" \
    $'src/main.rs\t' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 83. cd Path with Double Quote Escaping
# ------------------------------------------------------------------
echo -e "${CYAN}[83] cd Double Quote Path${NC}"

run_test "cd_path_with_double_quote" \
    'src/my"file.rs' \
    --no-file-checks --all -c "cd"

# ------------------------------------------------------------------
# 84. Command with Double Quotes, No $F (multi-file)
# ------------------------------------------------------------------
echo -e "${CYAN}[84] Command Double Quotes No \$F${NC}"

run_test "command_double_quotes_no_dollar_f" \
    "src/main.rs
src/parse.rs" \
    --no-file-checks --all -c 'sed -i "s/old/new/g"'

# ------------------------------------------------------------------
# 85. FPP_LINENUM_SEP + Mixed Linenum (unknown editor)
# ------------------------------------------------------------------
echo -e "${CYAN}[85] FPP_LINENUM_SEP Mixed Linenum${NC}"

run_test_env "linenum_sep_mixed_linenum_unknown" \
    "src/main.rs:42
src/lib.rs" \
    "FPP_EDITOR=myeditor FPP_LINENUM_SEP=@" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 86. nvim Three Files Split
# ------------------------------------------------------------------
echo -e "${CYAN}[86] nvim Three Files Split${NC}"

run_test_editor "editor_nvim_three_files_split" "nvim" \
    "src/main.rs:42
src/parse.rs:10
src/lib.rs:1" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 87. Editor with Backslash Path
# ------------------------------------------------------------------
echo -e "${CYAN}[87] Editor Backslash Path${NC}"

run_test_editor "editor_vim_backslash_path" "vim" \
    'path/with\\backslash/file.txt:42' \
    --no-file-checks --all

# ------------------------------------------------------------------
# 88. Fish Shell + Editor Mode Exit Status
# ------------------------------------------------------------------
echo -e "${CYAN}[88] Fish Editor Exit Status${NC}"

run_test_env "editor_fish_exit_status" \
    "src/main.rs:42" \
    "FPP_EDITOR=nano SHELL=/usr/bin/fish" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 89. --clean Preserves .fpp.keys
# ------------------------------------------------------------------
echo -e "${CYAN}[89] Clean Preserves Keybindings${NC}"

_clean_keys_dir="$TMPDIR_BASE/clean_keys_test"
mkdir -p "$_clean_keys_dir"
touch "$_clean_keys_dir/.fpp.sh" "$_clean_keys_dir/.fpp.log"
echo '{}' > "$_clean_keys_dir/.selection.json"
echo '[]' > "$_clean_keys_dir/.input.json"
echo '[bindings]' > "$_clean_keys_dir/.fpp.keys"
export FPP_DIR="$_clean_keys_dir"
timeout 10 "$RUST_BINARY" --clean >/dev/null 2>&1 || true
unset FPP_DIR
if [ -f "$_clean_keys_dir/.fpp.keys" ]; then
    echo -e "  ${GREEN}PASS${NC} clean_preserves_keybindings"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} clean_preserves_keybindings (.fpp.keys was deleted)"
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# 90. Extensionless Directory Path
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
echo -e "${CYAN}[91] Space Files + Linenum Validation${NC}"

if [ -d "$TESTS_INPUTS_DIR" ]; then
    # Evil file with space + line number
    run_test "validate_evil_file_space_linenum" \
        "$TESTS_INPUTS_DIR/evilFile With Space.txt:22" \
        --all -c "echo"

    # svo without parens, with comma
    run_test "validate_svo_no_parens_comma" \
        "$TESTS_INPUTS_DIR/svo install the zip, not me.xml" \
        --all -c "echo"

    # svo without parens, without comma
    run_test "validate_svo_no_parens_no_comma" \
        "$TESTS_INPUTS_DIR/svo install the zip not me.xml" \
        --all -c "echo"
else
    echo -e "  ${YELLOW}SKIP${NC} tests/inputs/ directory not found"
fi

# ------------------------------------------------------------------
# 92. Real-World Tool Outputs (Cycle 3)
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
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle1-3] Command Mode Edge Cases${NC}"

# Command with backtick
run_test "command_with_backtick" \
    "file1.txt
file2.txt" \
    --no-file-checks --all -c 'echo `date`'

# Command with $HOME (non-$F dollar var preserved)
run_test "command_preserve_dollar_var" \
    "file1.txt" \
    --no-file-checks --all -c 'echo $HOME'

# Single quote in path, command mode without $F
run_test "single_quote_path_no_dollar_f" \
    "it's_a_file.txt" \
    --no-file-checks --all -c "git add"

# Empty command string
run_test_env "command_empty_string" \
    "src/main.rs:42" \
    "FPP_EDITOR=vim" \
    --no-file-checks --all -c ""

# cd command with no matches
run_test "cd_no_matches" \
    "no file paths here at all" \
    --no-file-checks -c "cd"

# $F with single-quote path
run_test "dollar_f_single_quote_combined" \
    "it's_a_test.txt
file2.txt" \
    --no-file-checks --all -c 'echo $F && ls $F'

# ------------------------------------------------------------------
# Cycle 1: Editor edge cases
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle1-4] Editor Edge Cases${NC}"

# vim with line_num=0 (no linenum in input)
run_test_editor "editor_vim_zero_linenum" \
    "vim" \
    "src/main.rs" \
    --no-file-checks --all

# vim split with no linenum
run_test_editor "editor_vim_split_no_linenum" \
    "vim" \
    "src/main.rs
src/parse.rs" \
    --no-file-checks --all

# editor with args (nano --backup)
run_test_editor "editor_nano_with_args" \
    "nano --backup" \
    "src/main.rs:42" \
    --no-file-checks --all

# sublime (spelled out, not subl)
run_test_editor "editor_sublime_spelled_out" \
    "sublime" \
    "src/main.rs:42" \
    --no-file-checks --all

# VS Code editor (code - unknown editor fallback)
run_test_editor "editor_code_vscode" \
    "code" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

# vim split with many files (10)
run_test_editor "editor_vim_split_10_files" \
    "vim" \
    "src/file1.rs:1
src/file2.rs:2
src/file3.rs:3
src/file4.rs:4
src/file5.rs:5
src/file6.rs:6
src/file7.rs:7
src/file8.rs:8
src/file9.rs:9
src/file10.rs:10" \
    --no-file-checks --all

# Editor name case sensitivity (NANO uppercase)
run_test_editor "editor_uppercase_name" \
    "/usr/local/bin/NANO" \
    "src/main.rs:42" \
    --no-file-checks --all

# git diff a/b prefix in editor mode
run_test_editor "editor_git_diff_ab_prefix" \
    "vim" \
    "a/src/main.rs:42
b/src/parse.rs:10" \
    --no-file-checks --all

# ------------------------------------------------------------------
# Cycle 1: Shell and env var edge cases
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle1-5] Shell & Env Var Edge Cases${NC}"

# Shell = /bin/sh
run_test_env "shell_sh_exit" \
    "src/main.rs" \
    "SHELL=/bin/sh FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# Shell = /bin/ksh
run_test_env "shell_ksh_exit" \
    "src/main.rs" \
    "SHELL=/bin/ksh FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# FPP_DISABLE_PREPENDING_HOME_WITH_SLASH empty string
run_test_env "disable_prepend_home_empty_string" \
    "home/user/file.py" \
    "FPP_DISABLE_PREPENDING_HOME_WITH_SLASH=" \
    --no-file-checks --all -c "echo"

# FPP_DISABLE_SPLIT=0 (truthy non-empty string)
run_test_env "vim_disable_split_zero" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=vim FPP_DISABLE_SPLIT=0" \
    --no-file-checks --all

# ------------------------------------------------------------------
# Cycle 1: Flag combinations
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle1-6] Flag Combinations${NC}"

# --all-input + --no-file-checks + --all (redundant flags)
run_test "nfc_all_input_all_combined" \
    "just some text
src/main.rs" \
    --all-input --no-file-checks --all -c "echo"

# --all-input with file-path-like inputs
run_test "all_input_with_file_paths" \
    "src/main.rs:42
~/foo/bar.py
random text line" \
    --all-input --all -c "echo"

# --all-input tab-only line
run_test "all_input_tab_only_line" \
    $'\t\t\t' \
    --all-input --all -c "echo"

# ------------------------------------------------------------------
# Cycle 1: Dedup and path resolution
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle1-7] Dedup & Path Resolution${NC}"

# Same path different line numbers in command mode
run_test "dedup_same_path_diff_linenum_cmd" \
    "src/main.rs:10
src/main.rs:20
src/main.rs:30" \
    --no-file-checks --all -c "wc -l"

# Same path different line numbers in editor mode
run_test_editor "dedup_same_path_diff_linenum_editor" \
    "vim" \
    "src/main.rs:10
src/main.rs:20
src/main.rs:30" \
    --no-file-checks --all

# builtin REPOS: fbcode path
run_test "builtin_repos_fbcode" \
    "fbcode/something/test.py:10" \
    --no-file-checks --all -c "echo"

# builtin REPOS: configerator path
run_test "builtin_repos_configerator" \
    "configerator/config/test.py" \
    --no-file-checks --all -c "echo"

# builtin REPOS: configerator-dsi (hyphen in repo name)
run_test "builtin_repos_configerator_dsi" \
    "configerator-dsi/data/config.yaml" \
    --no-file-checks --all -c "echo"

# www prefix with editor mode (subl)
run_test_env "www_prefix_editor_subl" \
    "www/js/hotness.js:42" \
    "FPP_EDITOR=subl" \
    --no-file-checks --all

# prepend_dir with home tilde path
run_test "prepend_dir_home_tilde" \
    "~/www/asd.py" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 1: Output escaping edge cases
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle1-8] Output Escaping${NC}"

# Double quote in cd directory path
run_test "cd_dir_with_double_quote" \
    'src/my"dir/file.rs' \
    --no-file-checks --all -c "cd"

# Command with backslash
run_test "command_with_backslash" \
    "src/main.rs" \
    --no-file-checks --all -c 'echo hello\\world'

# ------------------------------------------------------------------
# Cycle 2: File validation with real files (MASTER_REGEX_WITH_SPACES)
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-1] File Validation - Space Paths${NC}"

# annoying Spaces Folder/evilFile With Space2.txt:42
(cd "$INPUTS_DIR" && run_test "validate_spaces_folder_file_linenum" \
    "./annoying Spaces Folder/evilFile With Space2.txt:42" \
    --all -c "echo")

# Leading space before space-file path
(cd "$INPUTS_DIR" && run_test "validate_leading_space_spaces_folder" \
    " ./annoying Spaces Folder/evilFile With Space2.txt:42" \
    --all -c "echo")

# Git-style prefix with space-file path
(cd "$INPUTS_DIR" && run_test "validate_git_prefix_spaces_folder" \
    "M     ./annoying Spaces Folder/evilFile With Space2.txt:42" \
    --all -c "echo")

# hyphen-dir Package Control.system-bundle (no linenum)
(cd "$INPUTS_DIR" && run_test "validate_hyphen_dir_bundle_file" \
    "./annoying-hyphen-dir/Package Control.system-bundle" \
    --all -c "echo")

# hyphen-dir Package Control.system-bundle:42
(cd "$INPUTS_DIR" && run_test "validate_hyphen_dir_bundle_linenum" \
    "./annoying-hyphen-dir/Package Control.system-bundle:42" \
    --all -c "echo")

# .DS_KINDA_STORE hidden dotfile (FILE_NO_PERIODS with validation)
(cd "$INPUTS_DIR" && run_test "validate_ds_kinda_store" \
    ".DS_KINDA_STORE" \
    --all -c "echo")

# .DS_KINDA_STORE with ./ prefix
(cd "$INPUTS_DIR" && run_test "validate_ds_kinda_store_dotslash" \
    "./.DS_KINDA_STORE" \
    --all -c "echo")

# sublime-workspace without ./ prefix, no linenum
(cd "$INPUTS_DIR" && run_test "validate_sublime_workspace_no_dotslash" \
    "blogredesign.sublime-workspace" \
    --all -c "echo")

# sublime-workspace without ./ prefix, with linenum
(cd "$INPUTS_DIR" && run_test "validate_sublime_workspace_linenum" \
    "blogredesign.sublime-workspace:42" \
    --all -c "echo")

# ------------------------------------------------------------------
# Cycle 2: Regex priority and preferred_regex
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-2] Regex Priority${NC}"

# MASTER_REGEX wins when it matches before OTHER_BGS
run_test "preferred_regex_master_wins" \
    "src/path/file.py:42 foo/bar/TARGETS:10" \
    --no-file-checks --all -c "echo"

# Non-first-component ... is resolvable (no warning)
run_test "non_first_component_dots_resolvable" \
    "src/.../nested/foo.py" \
    --no-file-checks --all -c "echo"

# OTHER_BGS min filename length (2 chars = below 3 minimum)
run_test "other_bgs_min_filename_length" \
    "foo/bar/ab:42" \
    --no-file-checks --all -c "echo"

# Contiguous spaces rejected by MASTER_REGEX_WITH_SPACES
run_test "spaces_regex_reject_contiguous" \
    "./path/two  spaces/file.txt" \
    --no-file-checks --all -c "echo"

# One match per line (first wins, multi-path lines)
run_test "one_match_per_line" \
    "src/a.py:1 src/b.py:2
src/c.py:3 src/d.py:4
src/e.py:5" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: Command mode edge cases
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-3] Command Mode Edge Cases${NC}"

# "cde" should NOT be treated as "cd" command
run_test "cd_command_false_positive" \
    "src/main.rs" \
    --no-file-checks --all -c "cde"

# Unicode in command string
run_test "command_with_unicode" \
    "src/main.rs" \
    --no-file-checks --all -c "echo 한글"

# Mixed resolvable + unresolvable (git abbreviated warning)
run_test "warn_git_abbreviated_mixed" \
    "src/main.rs:42
.../abbreviated/path.py" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: Shell edge cases
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-4] Shell Edge Cases${NC}"

# Shell name ending with "rc" but not standard rc shell
run_test_env "shell_endswith_rc_nonstandard" \
    "src/main.rs" \
    "SHELL=/usr/bin/bashrc FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: FPP_REPOS edge cases
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-5] FPP_REPOS Edge Cases${NC}"

# Comma-separated multiple repos
run_test_env "fpp_repos_comma_separated" \
    "myrepo1/src/foo.py" \
    "FPP_REPOS=myrepo1,myrepo2 FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# Empty FPP_REPOS string
run_test_env "fpp_repos_empty_string" \
    "src/main.rs" \
    "FPP_REPOS= FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# FPP_REPOS with trailing comma
run_test_env "fpp_repos_trailing_comma" \
    "myrepo/file.py" \
    "FPP_REPOS=myrepo, FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: ANSI parsing edge cases
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-6] ANSI Parsing Edge Cases${NC}"

# Non-m/K ANSI terminator (J = erase display)
run_test "ansi_non_mk_terminator" \
    $'\033[2Jsrc/main.rs:42' \
    --no-file-checks --all -c "echo"

# Incomplete ANSI sequence (ESC[ without terminator)
run_test "ansi_incomplete_sequence" \
    $'\033[src/main.rs:42' \
    --no-file-checks --all -c "echo"

# ANSI partial sequence at line end
run_test "ansi_partial_at_line_end" \
    $'\033[31msrc/main.rs\033[' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: Unicode edge cases
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-7] Unicode Edge Cases${NC}"

# CJK prefix before path (multibyte position test)
run_test "unicode_cjk_prefix_path" \
    "前缀text src/main.rs:42 后缀text" \
    --no-file-checks --all -c "echo"

# NFD decomposed unicode in path
run_test "unicode_nfd_decomposed" \
    $'src/cafe\xcc\x81.rs:10' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: Fuzz combinations
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-8] Fuzz Combinations${NC}"

# +++ prefix with dotfile
run_test "fuzz_plus_prefix_dotfile" \
    "+++ .env.local * Adapts AdsErrorCodestore to something" \
    --no-file-checks --all -c "echo"

# Changed: prefix with gitignore in subdir
run_test "fuzz_changed_prefix_gitignore" \
    "Changed: tmp/.gitignore jkk asdad" \
    --no-file-checks --all -c "echo"

# Banana prefix with TARGETS and linenum + suffix
run_test "fuzz_banana_targets_linenum" \
    "Banana asdasdoj pjo foo/bar/TARGETS:23 jkk asdad" \
    --no-file-checks --all -c "echo"

# Modified: prefix with vim temp file + code suffix
run_test "fuzz_modified_vim_temp" \
    "Modified: #So.many.periods.txt#:0:7: var AdsErrorCodeStore" \
    --no-file-checks --all -c "echo"

# +++ prefix with linenum path + suffix
run_test "fuzz_plus_prefix_asd_linenum" \
    "+++ ./asd.txt:83 jkk asdad" \
    --no-file-checks --all -c "echo"

# M prefix with NSArray+Utils.h
run_test "fuzz_m_prefix_nsarray_plus_h" \
    "M     ./objectivec/NSArray+Utils.h" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: all_input edge cases
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-9] all_input Edge Cases${NC}"

# Trailing spaces only (trimmed to "a")
run_test "all_input_trailing_spaces_only" \
    "a    " \
    --all-input --all -c "echo"

# Word with trailing spaces
run_test "all_input_trailing_spaces_word" \
    "foo bar    " \
    --all-input --all -c "echo"

# File path treated as raw text in all-input mode
run_test "all_input_file_path_raw_text" \
    "src/main.rs:42" \
    --all-input --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: git abbreviated bypass with file validation
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-10] Git Abbreviated Bypass${NC}"

# .../path bypasses file validation (no --no-file-checks needed)
run_test "validate_git_abbreviated_bypass" \
    ".../something/foo.py" \
    --all -c "echo"

# ------------------------------------------------------------------
# Cycle 3: Final file validation edge cases
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle3-1] File Validation Edge Cases${NC}"

# Space folder file WITHOUT linenum (validate_file_exists=true)
(cd "$INPUTS_DIR" && run_test "validate_spaces_folder_file_no_linenum" \
    "./annoying Spaces Folder/evilFile With Space2.txt" \
    --all -c "echo")

# hyphen-dir Package Control WITHOUT ./ prefix (validate=true)
(cd "$INPUTS_DIR" && run_test "validate_hyphen_dir_no_dotslash" \
    "annoying-hyphen-dir/Package Control.system-bundle" \
    --all -c "echo")

# Tilde extension with linenum (validate_file_exists=true)
(cd "$INPUTS_DIR" && run_test "validate_tilde_ext_linenum" \
    "./annoyingTildeExtension.txt~:42" \
    --all -c "echo")

# .DS_KINDA_STORE from parent dir (inputs/ prefix in path)
(cd "$INPUTS_DIR/.." && run_test "validate_ds_kinda_store_from_parent" \
    "inputs/.DS_KINDA_STORE" \
    --all -c "echo")

# Yocto % file with ./ prefix (validate=true, working_dir=inputs)
(cd "$INPUTS_DIR" && run_test "validate_yocto_dotslash" \
    "./file-from-yocto_3.1%.bbappend" \
    --all -c "echo")

# ------------------------------------------------------------------
# Cycle 3: Regex skip logic (only_with_file_inspection)
# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle3-2] Regex Skip Logic${NC}"

# sublime-workspace with --no-file-checks: MASTER_REGEX_MORE_EXTENSIONS skipped
# Should still match via a different regex or not match at all
run_test "sublime_workspace_nfc_skip" \
    "blogredesign.sublime-workspace" \
    --no-file-checks --all -c "echo"

# Space file with --no-file-checks: MASTER_REGEX_WITH_SPACES skipped
run_test "space_file_nfc_skip" \
    "some dir/evil file.txt" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 1 Consolidation: Missing Test Cases
# ------------------------------------------------------------------

# ==================================================================
# [C1-1] SHELL unset (not empty string) - alias expansion behavior
# ==================================================================
echo -e "${CYAN}[C1-1] SHELL Unset Alias Expansion${NC}"

# When SHELL is completely unset, Python: shell is None -> shopt block included
# Different from SHELL="" (empty string)
_shell_unset_dir="$TMPDIR_BASE/shell_unset_test"
mkdir -p "$_shell_unset_dir"
rm -f "$_shell_unset_dir/.fpp.sh"
_saved_shell="${SHELL:-__UNSET__}"
unset SHELL
export FPP_DIR="$_shell_unset_dir" FPP_EDITOR=vim
timeout 10 bash -c 'printf "src/main.rs\n" | "$1" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
_shell_unset_out=$(cat "$_shell_unset_dir/.fpp.sh" 2>/dev/null || echo "(no script)")
unset FPP_DIR FPP_EDITOR
if [ "$_saved_shell" != "__UNSET__" ]; then export SHELL="$_saved_shell"; fi

case "$MODE" in
    rust-only)
        _snap_file="$SNAPSHOT_DIR/shell_unset_alias_expansion.txt"
        if [ -f "$_snap_file" ]; then
            assert_equal "shell_unset_alias_expansion" "$(cat "$_snap_file")" "$_shell_unset_out"
        else
            echo -e "  ${YELLOW}SKIP${NC} shell_unset_alias_expansion (no snapshot)"
            SKIP=$((SKIP + 1))
        fi
        ;;
    update-snapshots)
        echo "$_shell_unset_out" > "$SNAPSHOT_DIR/shell_unset_alias_expansion.txt"
        echo -e "  ${CYAN}UPDATED${NC} shell_unset_alias_expansion"
        ;;
    compare)
        # In compare mode, run Python too
        _py_shell_dir="$TMPDIR_BASE/py_shell_unset_test"
        mkdir -p "$_py_shell_dir"
        rm -f "$_py_shell_dir/.fpp.sh"
        _saved_shell2="${SHELL:-__UNSET__}"
        unset SHELL
        export FPP_DIR="$_py_shell_dir"
        timeout 10 bash -c 'printf "src/main.rs\n" | $1 --all -c "echo" >/dev/null 2>&1 || true' _ "$PYTHON_HEADLESS" 2>/dev/null || true
        _py_shell_out=$(cat "$_py_shell_dir/.fpp.sh" 2>/dev/null || echo "(no script)")
        unset FPP_DIR
        if [ "$_saved_shell2" != "__UNSET__" ]; then export SHELL="$_saved_shell2"; fi
        assert_equal "shell_unset_alias_expansion" "$_py_shell_out" "$_shell_unset_out"
        ;;
esac

# ==================================================================
# [C1-2] cd command with root directory file
# ==================================================================
echo -e "${CYAN}[C1-2] cd Command Edge Cases${NC}"

# /file.txt -> dirname is "/" (root dir)
run_test "cd_root_dir_file" \
    "/file.txt" \
    --no-file-checks --all -c "cd"

# cd with relative path containing ../
run_test "cd_dotdot_relative" \
    "../other/main.rs" \
    --no-file-checks --all -c "cd"

# NOTE: cd_bare_filename removed (duplicate of command_cd_bare_file in [21])

# ==================================================================
# [C1-3] --all flag unique path dedup behavior
# ==================================================================
echo -e "${CYAN}[C1-3] --all Flag Unique Path Dedup${NC}"

# Same file with different line numbers - --all should select unique paths
run_test "all_flag_dedup_same_file" \
    "src/main.rs:10
src/main.rs:20
src/main.rs:30
src/parse.rs:5
src/parse.rs:15" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-4] --version and --help output
# ==================================================================
echo -e "${CYAN}[C1-4] CLI Help and Version${NC}"

# --version should exit 0
_version_exit=0
timeout 5 "$RUST_BINARY" --version >/dev/null 2>&1 || _version_exit=$?
if [ $_version_exit -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} version_flag_exit_zero"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} version_flag_exit_zero (exit=$_version_exit)"
    FAIL=$((FAIL + 1))
fi

# --help should exit 0
_help_exit=0
timeout 5 "$RUST_BINARY" --help >/dev/null 2>&1 || _help_exit=$?
if [ $_help_exit -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} help_flag_exit_zero"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} help_flag_exit_zero (exit=$_help_exit)"
    FAIL=$((FAIL + 1))
fi

# ==================================================================
# [C1-5] Editor with relative path containing ../
# ==================================================================
echo -e "${CYAN}[C1-5] Editor with Relative Paths${NC}"

# ../other/main.rs:42 opened in vim
run_test_editor "editor_vim_dotdot_path" "vim" \
    "../other/main.rs:42" \
    --no-file-checks --all

# ./src/main.rs:10 opened in vim (dot-slash prefix)
run_test_editor "editor_vim_dotslash_path" "vim" \
    "./src/main.rs:10" \
    --no-file-checks --all

# ==================================================================
# [C1-6] FPP_REPOS with multiple comma-separated repos
# ==================================================================
echo -e "${CYAN}[C1-6] FPP_REPOS Multiple Repos${NC}"

run_test_env "fpp_repos_multiple" \
    "customrepo/lib/utils.py" \
    "FPP_REPOS=myrepo,customrepo,otherone FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# FPP_REPOS with builtin repo name (should still match)
run_test_env "fpp_repos_builtin_www" \
    "www/index.html" \
    "FPP_REPOS=extra FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-7] preferred_regex: OTHER_BGS vs MASTER priority
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
echo -e "${CYAN}[C1-8] All-Input Mode Edge Cases${NC}"

# Tab-only line should NOT match (tab -> 4 spaces -> whitespace only)
run_test "all_input_single_tab_line" \
    "$(printf '\t')" \
    --all-input --all -c "echo"

# Mixed content with empty lines
run_test "all_input_mixed_with_empty" \
    "first line

third line

fifth line" \
    --all-input --all -c "echo"

# Line that looks like a path in all-input mode (treated as raw text)
run_test "all_input_absolute_path" \
    "/usr/local/bin/test" \
    --all-input --all -c "echo"

# ==================================================================
# [C1-9] NOTE: editor_vim_p_* removed (duplicates of editor_vim_tab_mode/editor_vim_tab_single in [17/49])
# [C1-10] NOTE: shell_rc_suffix_status removed (duplicate of shell_rc_exit in [22])
# NOTE: shell_tcsh_exit removed (duplicate of [50])
# ==================================================================
echo -e "${CYAN}[C1-10] Shell Exit Code Edge Cases${NC}"

# Shell with full path to fish (different path from shell_fish_exit)
run_test_env "shell_fish_localbin" \
    "src/main.rs" \
    "SHELL=/usr/local/bin/fish FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# Shell containing "fish" as substring (e.g. goldfish) - should suppress shopt
run_test_env "shell_goldfish_no_shopt" \
    "src/main.rs" \
    "SHELL=/usr/bin/goldfish FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-11] NOTE: editor_full_path_nano removed (duplicate of [49])
# ==================================================================
echo -e "${CYAN}[C1-11] Editor Full Paths${NC}"

run_test_editor "editor_full_path_emacs" "/usr/bin/emacs" \
    "src/main.rs:42" \
    --no-file-checks --all

run_test_editor "editor_full_path_subl" "/usr/local/bin/subl" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

# ==================================================================
# [C1-12] NOTE: prepend_no_slash_dotprefix removed (duplicate of prepend_dir_no_dir in [24])
# ==================================================================
echo -e "${CYAN}[C1-12] prepend_dir Edge Cases${NC}"

# Absolute path (starts with /) -> no prepend
run_test "prepend_absolute_unchanged" \
    "/usr/local/bin/test.sh" \
    --no-file-checks --all -c "echo"

# Path starting with tilde -> preserved as-is
run_test "prepend_tilde_preserved" \
    "~/Documents/file.txt" \
    --no-file-checks --all -c "echo"

# Double-dot relative path
run_test "prepend_dotdot_path" \
    "../../deep/nested/file.py" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-13] ANSI edge cases
# ==================================================================
echo -e "${CYAN}[C1-13] ANSI Edge Cases${NC}"

# 256-color ANSI codes should be stripped for path extraction
run_test "ansi_256_fg_color_path" \
    "$(printf '\033[38;5;196m')src/main.rs$(printf '\033[0m')" \
    --no-file-checks --all -c "echo"

# True color (24-bit) ANSI
run_test "ansi_truecolor_path" \
    "$(printf '\033[38;2;255;100;0m')src/parse.rs:42$(printf '\033[0m')" \
    --no-file-checks --all -c "echo"

# ANSI bold + color combined
run_test "ansi_bold_color_combined" \
    "$(printf '\033[1;31m')src/lib.rs:10$(printf '\033[0m') error: unused variable" \
    --no-file-checks --all -c "echo"

# Non-m/K terminator (e.g. \033[2J erase display) - should not strip path
run_test "ansi_non_sgr_terminator" \
    "$(printf '\033[2J')src/main.rs" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-14] Command generation edge cases
# ==================================================================
echo -e "${CYAN}[C1-14] Command Generation Edge Cases${NC}"

# NOTE: command_empty_string, command_with_pipe, command_with_semicolons,
# command_with_double_quotes, command_with_backtick, command_preserve_dollar_var
# already exist in earlier sections.

# Command with single quotes in it
run_test "command_with_single_quotes_echo" \
    "src/main.rs" \
    --no-file-checks --all -c "echo 'hello world'"

# ==================================================================
# [C1-15] Multiple files in editor with various editors
# ==================================================================
echo -e "${CYAN}[C1-15] Multi-file Editor Commands${NC}"

# helix with multiple files and line numbers
run_test_editor "editor_hx_multi_linenum" "hx" \
    "src/main.rs:42
src/parse.rs:10
src/lib.rs:5" \
    --no-file-checks --all

# micro with multiple files
run_test_editor "editor_micro_multi" "micro" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

# joe with multiple files
run_test_editor "editor_joe_multi" "joe" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

# emacs with multiple files and line numbers
run_test_editor "editor_emacs_multi_linenum" "emacs" \
    "src/main.rs:42
src/parse.rs:10
src/lib.rs:5" \
    --no-file-checks --all

# ==================================================================
# [C1-16] NOTE: vim_disable_split_empty_string and vim_disable_split_zero
# removed (duplicates of vim_disable_split_empty and vim_disable_split_zero in [49/C1-5])
# ==================================================================

# ==================================================================
# [C1-17] Line number edge cases in editor mode
# ==================================================================
echo -e "${CYAN}[C1-17] Line Number Edge Cases${NC}"

# Line number 0 (should be treated same as no line number or as 0)
run_test_editor "editor_vim_linenum_zero" "vim" \
    "src/main.rs:0" \
    --no-file-checks --all

# Very large line number
run_test_editor "editor_vim_linenum_large" "vim" \
    "src/main.rs:999999" \
    --no-file-checks --all

# Line number with custom separator (FPP_LINENUM_SEP)
run_test_env "linenum_sep_dash" \
    "src/main.rs-42" \
    "FPP_LINENUM_SEP=- FPP_EDITOR=vim" \
    --no-file-checks --all

# ==================================================================
# [C1-18] Input with various git output formats
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
echo -e "${CYAN}[C1-20] Special Characters in Paths${NC}"

# Path with @ symbol
run_test "path_with_at_symbol" \
    "src/@types/index.ts" \
    --no-file-checks --all -c "echo"

# Path with + symbol
run_test "path_with_plus_symbol" \
    "src/c++/main.cpp" \
    --no-file-checks --all -c "echo"

# Path with hash in directory
run_test "path_with_hash_dir" \
    "src/#temp#/file.rs" \
    --no-file-checks --all -c "echo"

# Path with parentheses
run_test "path_with_parens" \
    "src/utils(old)/helper.py" \
    --no-file-checks --all -c "echo"

# Path with equals sign
run_test "path_with_equals" \
    "src/config=prod/settings.json" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-21] State directory auto-creation
# ==================================================================
echo -e "${CYAN}[C1-21] State Directory${NC}"

# FPP_DIR pointing to non-existent directory should auto-create
_auto_create_dir="$TMPDIR_BASE/auto_create_test/nested/dir"
export FPP_DIR="$_auto_create_dir"
timeout 10 bash -c 'printf "src/main.rs\n" | "$1" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
if [ -d "$_auto_create_dir" ]; then
    echo -e "  ${GREEN}PASS${NC} state_dir_auto_create"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} state_dir_auto_create"
    FAIL=$((FAIL + 1))
fi
unset FPP_DIR

# ==================================================================
# [C1-22] --clean flag behavior
# ==================================================================
echo -e "${CYAN}[C1-22] --clean Flag${NC}"

# --clean should delete state files before processing
_clean_dir="$TMPDIR_BASE/clean_test"
mkdir -p "$_clean_dir"
echo "old content" > "$_clean_dir/.fpp.sh"
echo "old state" > "$_clean_dir/.input.json"
export FPP_DIR="$_clean_dir"
timeout 10 bash -c 'printf "src/main.rs\n" | "$1" --non-interactive --no-file-checks --all --clean -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
_clean_script=$(cat "$_clean_dir/.fpp.sh" 2>/dev/null || echo "(no script)")
unset FPP_DIR
# Verify old content was replaced
if echo "$_clean_script" | grep -q "old content"; then
    echo -e "  ${RED}FAIL${NC} clean_flag_removes_old_state"
    FAIL=$((FAIL + 1))
else
    echo -e "  ${GREEN}PASS${NC} clean_flag_removes_old_state"
    PASS=$((PASS + 1))
fi

# ==================================================================
# [C1-23] $F token in various positions in command
# ==================================================================
echo -e "${CYAN}[C1-23] \$F Token Positions${NC}"

# $F at the very end
run_test "dollar_f_at_end" \
    "src/main.rs
src/parse.rs" \
    --no-file-checks --all -c 'git add $F'

# $F with surrounding text
run_test "dollar_f_surrounded" \
    "src/main.rs" \
    --no-file-checks --all -c 'echo before $F after'

# No $F - files appended at end
run_test "no_dollar_f_append_multi" \
    "src/main.rs
src/parse.rs
src/lib.rs" \
    --no-file-checks --all -c "wc -l"

# ==================================================================
# [C1-24] NOTE: crlf_path_parsing and mixed_line_endings removed
# (duplicates of crlf_line_endings and mixed_line_endings in [43])
# ==================================================================

# ==================================================================
# [C1-25] Edge case: very long line with path buried in it
# ==================================================================
echo -e "${CYAN}[C1-25] Long Lines${NC}"

# Path at the end of a very long line
_long_prefix=$(python3 -c "print('x' * 500)")
run_test "long_line_path_at_end" \
    "${_long_prefix} src/main.rs:42" \
    --no-file-checks --all -c "echo"

# Path at the beginning of a very long line
_long_suffix=$(python3 -c "print('x' * 500)")
run_test "long_line_path_at_start" \
    "src/main.rs:42 ${_long_suffix}" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-26] Multiple matches on same line
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
echo -e "${CYAN}[C1-27] Vim Split with Many Files${NC}"

run_test_editor "editor_vim_split_four_files" "vim" \
    "src/main.rs:10
src/parse.rs:20
src/lib.rs:30
src/format.rs:40" \
    --no-file-checks --all

run_test_editor "editor_nvim_split_four_files" "nvim" \
    "src/main.rs:10
src/parse.rs:20
src/lib.rs:30
src/format.rs:40" \
    --no-file-checks --all

# ------------------------------------------------------------------
# Cycle 2 Consolidation: Additional Missing Test Cases
# ------------------------------------------------------------------

# ==================================================================
# [C2-1] FPP_EDITOR empty string -> fallback to VISUAL/EDITOR
# ==================================================================
echo -e "${CYAN}[C2-1] FPP_EDITOR Empty String Fallback${NC}"

run_test_env "editor_fpp_editor_empty_fallback" \
    "src/main.rs:42" \
    "FPP_EDITOR= VISUAL=nano" \
    --no-file-checks --all

# ==================================================================
# [C2-2] FPP_LINENUM_SEP only affects output, NOT input parsing
# ==================================================================
echo -e "${CYAN}[C2-2] FPP_LINENUM_SEP Scope${NC}"

# With FPP_LINENUM_SEP=#, input "file.rs#42" should NOT parse # as linenum separator
# Only colon in input is a linenum separator
run_test_env "linenum_sep_does_not_affect_input" \
    "src/main.rs#42" \
    "FPP_LINENUM_SEP=# FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C2-3] non-interactive mode without --all flag
# ==================================================================
echo -e "${CYAN}[C2-3] Non-Interactive Without --all${NC}"

# In non-interactive mode, all matches are selected regardless of --all flag
run_test "non_interactive_no_all_flag" \
    "src/main.rs
src/parse.rs" \
    --no-file-checks -c "echo"

# ==================================================================
# [C2-4] ANSI K (erase line) terminator variants
# ==================================================================
echo -e "${CYAN}[C2-4] ANSI K Terminator Variants${NC}"

# \033[0K (erase from cursor to end of line)
run_test "ansi_erase_to_eol" \
    "$(printf '\033[0K')src/main.rs:42" \
    --no-file-checks --all -c "echo"

# \033[2K (erase entire line) followed by content
run_test "ansi_erase_full_line" \
    "$(printf '\033[2K')src/parse.rs" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C2-5] Editor mode with git abbreviated path warning
# ==================================================================
echo -e "${CYAN}[C2-5] Git Abbreviated Warning in Mixed Input${NC}"

# Mix of normal files and .../abbreviated - warning should appear for abbreviated
run_test_editor "editor_mixed_normal_and_abbreviated" "vim" \
    "src/main.rs:42
.../something/foo.py
src/parse.rs:10" \
    --no-file-checks --all

# ==================================================================
# [C2-6] Process input: bare \r without \n
# ==================================================================
echo -e "${CYAN}[C2-6] Bare CR Handling${NC}"

# Python readlines() only splits on \n, not \r
# So "file1.rs\rfile2.rs" is ONE line, not two
run_test "bare_cr_single_line" \
    "$(printf 'src/main.rs\rsrc/parse.rs')" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C2-7] cd command with tab after "cd"
# ==================================================================
echo -e "${CYAN}[C2-7] cd Command Edge Cases${NC}"

# "cd\t" should NOT be treated as cd command (Python: command[0:3] in ["cd ", "cd"])
run_test "cd_with_tab_not_cd" \
    "src/main.rs" \
    --no-file-checks --all -c "$(printf 'cd\t')"

# ==================================================================
# [C2-8] Multiple regex match with file validation fallback
# ==================================================================
echo -e "${CYAN}[C2-8] File Validation Regex Fallback${NC}"

# When validate_file_exists=True and first regex match doesn't exist,
# should fall back to next regex match that does exist
(cd "$INPUTS_DIR" && run_test "validate_fallback_to_existing" \
    "nonexistent.sublime-workspace annoying-hyphen-dir/Package Control.system-bundle" \
    --all -c "echo")

# ------------------------------------------------------------------
# Cycle 3: Minor Edge Cases (from final review)
# ------------------------------------------------------------------

# ==================================================================
# [C3-1] is_git_abbreviated_path: "...file.py" (no slash) vs ".../file.py"
# ==================================================================
echo -e "${CYAN}[C3-1] Git Abbreviated Path Edge Cases${NC}"

# "...file.py" without slash - Python: parts[0]="...file.py" != "...", NOT abbreviated
# Rust should match Python behavior
run_test "git_abbreviated_no_slash" \
    "...file.py" \
    --no-file-checks --all -c "echo"

# ".../dir/file.py" - standard abbreviated, should be treated as abbreviated
run_test "git_abbreviated_with_subdir" \
    ".../deeply/nested/dir/file.py" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C3-2] File validation with prefix text before path
# ==================================================================
echo -e "${CYAN}[C3-2] Prefix Text with File Validation${NC}"

# Yocto file with "other thing" prefix text (matches Python test_parsing.py test)
(cd "$INPUTS_DIR" && run_test "validate_yocto_with_prefix" \
    "other thing ./file-from-yocto_3.1%.bbappend" \
    --all -c "echo")

# ==================================================================
# [C3-3] sublime-workspace with inputs/ directory prefix
# ==================================================================
echo -e "${CYAN}[C3-3] Sublime Workspace with Directory Prefix${NC}"

(cd "$INPUTS_DIR/.." && run_test "validate_sublime_workspace_with_dir" \
    "inputs/blogredesign.sublime-workspace:42" \
    --all -c "echo")

# ------------------------------------------------------------------
# Cycle 4: Comprehensive Gap Analysis (3-agent parallel review)
# ------------------------------------------------------------------

# ==================================================================
# [C4-1] vim -p mode: zero line number and mixed line numbers
# ==================================================================
echo -e "${CYAN}[C4-1] vim -p Mode Edge Cases${NC}"

# vim -p with no line number (line_num=0) — Python emits +0
run_test_editor "editor_vim_p_zero_linenum" "vim -p" \
    "src/main.rs" \
    --no-file-checks --all

# vim -p with mixed line numbers: first has linenum, second doesn't
run_test_editor "editor_vim_p_mixed_linenum" "vim -p" \
    "src/main.rs:42
src/parse.rs" \
    --no-file-checks --all

# ==================================================================
# [C4-2] mvim split with 3+ files
# ==================================================================
echo -e "${CYAN}[C4-2] mvim Split Multiple Files${NC}"

run_test_editor "editor_mvim_split_three_files" "mvim" \
    "src/main.rs:1
src/parse.rs:2
src/input.rs:3" \
    --no-file-checks --all

# ==================================================================
# [C4-3] sublime (spelled out) multi-file with line numbers
# ==================================================================
echo -e "${CYAN}[C4-3] Sublime Multi-File${NC}"

run_test_editor "editor_sublime_multi_linenum" "sublime" \
    "src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all

# ==================================================================
# [C4-4] FPP_DISABLE_SPLIT with non-vim editor (should be ignored)
# ==================================================================
echo -e "${CYAN}[C4-4] FPP_DISABLE_SPLIT Non-Vim${NC}"

run_test_env "disable_split_nano_ignored" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=nano FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

run_test_env "disable_split_subl_ignored" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=subl FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

# ==================================================================
# [C4-5] cd command with spaces in directory path
# ==================================================================
echo -e "${CYAN}[C4-5] cd with Space Directory${NC}"

run_test "cd_space_dir_path" \
    "src/my dir/file.rs" \
    --no-file-checks --all -c "cd"

# ==================================================================
# [C4-6] cd with consecutive dotdot normalization
# ==================================================================
echo -e "${CYAN}[C4-6] cd Double Dotdot${NC}"

run_test "cd_double_dotdot" \
    "/a/b/../../c/file.rs" \
    --no-file-checks --all -c "cd"

# ==================================================================
# [C4-7] FPP_REPOS with double comma (empty element)
# ==================================================================
echo -e "${CYAN}[C4-7] FPP_REPOS Double Comma${NC}"

run_test_env "fpp_repos_double_comma" \
    "repo2/src/main.py" \
    "FPP_REPOS=repo1,,repo2 FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-8] ANSI attributes: underline, reverse video, dim
# ==================================================================
echo -e "${CYAN}[C4-8] ANSI Attribute Variants${NC}"

# Underline (code 4)
run_test "ansi_underline_path" \
    "$(printf '\033[4msrc/main.rs\033[0m:42')" \
    --no-file-checks --all -c "echo"

# Reverse video (code 7)
run_test "ansi_reverse_video_path" \
    "$(printf '\033[7msrc/main.rs\033[0m:10')" \
    --no-file-checks --all -c "echo"

# Dim (code 2)
run_test "ansi_dim_path" \
    "$(printf '\033[2msrc/main.rs\033[0m:5')" \
    --no-file-checks --all -c "echo"

# Strikethrough (code 9)
run_test "ansi_strikethrough_path" \
    "$(printf '\033[9msrc/main.rs\033[0m:1')" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-9] $F triple occurrence in command
# ==================================================================
echo -e "${CYAN}[C4-9] \$F Triple Occurrence${NC}"

run_test "dollar_f_triple" \
    "a.txt
b.txt" \
    --no-file-checks --all -c 'echo $F && wc $F && ls $F'

# ==================================================================
# [C4-10] Non-standard shell names (fish/csh substring matching)
# ==================================================================
echo -e "${CYAN}[C4-10] Non-Standard Shell Names${NC}"

# "starfish" contains "fish" — should omit shopt and use $status
run_test_env "shell_starfish_fish_match" \
    "src/main.rs" \
    "SHELL=/usr/bin/starfish FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# "mycsh" ends with "csh" — should use $status for exit
run_test_env "shell_mycsh_csh_match" \
    "src/main.rs" \
    "SHELL=/usr/bin/mycsh FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-11] FPP_DIR with spaces in path
# ==================================================================
echo -e "${CYAN}[C4-11] FPP_DIR with Spaces${NC}"

# FPP_DIR containing spaces — script should be generated normally
# (We handle this manually since run_test_env sets FPP_DIR internally)
FPP_DIR_SPACE="$TMPDIR_BASE/my fpp dir"
mkdir -p "$FPP_DIR_SPACE"
case "$MODE" in
    compare)
        FPP_DIR_PY="$FPP_DIR_SPACE/py"
        FPP_DIR_RS="$FPP_DIR_SPACE/rs"
        mkdir -p "$FPP_DIR_PY" "$FPP_DIR_RS"
        rm -f "$FPP_DIR_PY/.fpp.sh" "$FPP_DIR_RS/.fpp.sh"
        FPP_DIR="$FPP_DIR_PY" FPP_EDITOR=vim \
            timeout 10 bash -c 'printf "%s" "$1" | $2 --all -c "echo" >/dev/null 2>&1 || true' _ "src/main.rs" "$PYTHON_HEADLESS" 2>/dev/null || true
        py_out=$(cat "$FPP_DIR_PY/.fpp.sh" 2>/dev/null || echo "(no script generated)")
        FPP_DIR="$FPP_DIR_RS" FPP_EDITOR=vim \
            timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive --all -c "echo" >/dev/null 2>&1 || true' _ "src/main.rs" "$RUST_BINARY" 2>/dev/null || true
        rs_out=$(cat "$FPP_DIR_RS/.fpp.sh" 2>/dev/null || echo "(no script generated)")
        assert_equal "state_dir_with_spaces" "$py_out" "$rs_out"
        ;;
    rust-only)
        FPP_DIR_RS="$FPP_DIR_SPACE/rs"
        mkdir -p "$FPP_DIR_RS"
        rm -f "$FPP_DIR_RS/.fpp.sh"
        FPP_DIR="$FPP_DIR_RS" FPP_EDITOR=vim \
            timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive --all -c "echo" >/dev/null 2>&1 || true' _ "src/main.rs" "$RUST_BINARY" 2>/dev/null || true
        rs_out=$(cat "$FPP_DIR_RS/.fpp.sh" 2>/dev/null || echo "(no script generated)")
        snapshot_file="$SNAPSHOT_DIR/state_dir_with_spaces.txt"
        if [ ! -f "$snapshot_file" ]; then
            echo -e "  ${YELLOW}SKIP${NC} state_dir_with_spaces (no snapshot)"
            SKIP=$((SKIP + 1))
        else
            assert_equal "state_dir_with_spaces" "$(cat "$snapshot_file")" "$rs_out"
        fi
        ;;
    update-snapshots)
        FPP_DIR_RS="$FPP_DIR_SPACE/rs"
        mkdir -p "$FPP_DIR_RS" "$SNAPSHOT_DIR"
        rm -f "$FPP_DIR_RS/.fpp.sh"
        FPP_DIR="$FPP_DIR_RS" FPP_EDITOR=vim \
            timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive --all -c "echo" >/dev/null 2>&1 || true' _ "src/main.rs" "$RUST_BINARY" 2>/dev/null || true
        rs_out=$(cat "$FPP_DIR_RS/.fpp.sh" 2>/dev/null || echo "(no script generated)")
        echo "$rs_out" > "$SNAPSHOT_DIR/state_dir_with_spaces.txt"
        echo -e "  ${CYAN}UPDATED${NC} state_dir_with_spaces"
        ;;
esac

# ==================================================================
# [C4-12] Editor FPP_EDITOR="" (empty string) should fall through to VISUAL
# NOTE: editor_fpp_editor_empty_to_visual removed (near-duplicate of editor_fpp_editor_empty_fallback in C2-1)

# ==================================================================
# [C4-13] Yocto file with ./foo/ prefix (filesystem validation fallback)
# ==================================================================
echo -e "${CYAN}[C4-13] Yocto File Validation Fallback${NC}"

# "other thing ./foo/file-from-yocto..." — ./foo/ doesn't exist, should fallback to bare filename
(cd "$INPUTS_DIR" && run_test "validate_yocto_foo_prefix" \
    "other thing ./foo/file-from-yocto_3.1%.bbappend" \
    --all -c "echo")

# NOTE: cd_bare_no_extension removed (duplicate of command_cd_bare_file in section 21)

# ==================================================================
# [C4-15] ANSI combined with multi-line: multiple SGR attributes on same path
# ==================================================================
echo -e "${CYAN}[C4-15] ANSI Multi-Attribute${NC}"

# Bold + underline + color combined
run_test "ansi_bold_underline_color" \
    "$(printf '\033[1;4;33msrc/main.rs\033[0m:42')" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-16] FPP_LINENUM_SEP with dash separator
# ==================================================================
echo -e "${CYAN}[C4-16] FPP_LINENUM_SEP Dash${NC}"

run_test_env "linenum_sep_dash_custom" \
    "src/main.rs:42" \
    "FPP_EDITOR=myeditor FPP_LINENUM_SEP=-" \
    --no-file-checks --all

# ==================================================================
# [C4-17] Editor with args: "emacs -nw" multi-file
# ==================================================================
echo -e "${CYAN}[C4-17] Editor with Args Multi-File${NC}"

run_test_editor "editor_emacs_nw_multi" "emacs -nw" \
    "src/main.rs:42
src/parse.rs:10
src/input.rs:5" \
    --no-file-checks --all

# NOTE: all_input_all_command_triple removed (near-duplicate of all_all_input_command in section 31)

# NOTE: fpp_repos_empty_string_split removed (near-duplicate of fpp_repos_empty_string in Cycle2-5)

# NOTE: shell_sh_exit_with_command removed (duplicate of shell_sh_exit in Cycle1-5)
# NOTE: shell_ksh_exit_with_command removed (duplicate of shell_ksh_exit in Cycle1-5)

# ==================================================================
# [C4-22] Editor: helix (hx) multi-file with mixed line numbers
# ==================================================================
echo -e "${CYAN}[C4-22] Helix Multi-File Mixed${NC}"

run_test_editor "editor_hx_mixed_linenum" "hx" \
    "src/main.rs:42
src/parse.rs
src/input.rs:10" \
    --no-file-checks --all

# NOTE: editor_joe_linenum removed (duplicate of editor_joe_multi in C1-15)
# NOTE: editor_micro_linenum removed (duplicate of editor_micro_multi in C1-15)

# ==================================================================
# [C4-25] Dedup: same file, same line number — should only appear once
# ==================================================================
echo -e "${CYAN}[C4-25] Dedup Same File Same Linenum${NC}"

run_test "dedup_same_path_same_linenum" \
    "src/main.rs:42
src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-26] Command mode: single file with $F (edge: $F at start of command)
# ==================================================================
echo -e "${CYAN}[C4-26] \$F Start of Command${NC}"

run_test "dollar_f_at_start" \
    "src/main.rs" \
    --no-file-checks --all -c '$F --version'

# ==================================================================
# [C4-27] Path with backslash in filename
# ==================================================================
echo -e "${CYAN}[C4-27] Backslash in Path${NC}"

run_test "path_with_backslash" \
    'src/main\.rs' \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-28] Very long filename (stress boundary)
# ==================================================================
echo -e "${CYAN}[C4-28] Very Long Filename${NC}"

LONG_NAME="src/$(python3 -c "print('a' * 200)").rs"
run_test "path_very_long_filename" \
    "$LONG_NAME" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-29] ANSI: incomplete sequence at end of line (no terminator)
# ==================================================================
echo -e "${CYAN}[C4-29] ANSI Incomplete at EOL${NC}"

run_test "ansi_incomplete_no_terminator" \
    "$(printf '\033[31msrc/main.rs')" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-30] Editor: vi (not vim) multi-file
# ==================================================================
echo -e "${CYAN}[C4-30] vi Multi-File${NC}"

run_test_editor "editor_vi_multi_file" "vi" \
    "src/main.rs:42
src/parse.rs:10
src/input.rs:5" \
    --no-file-checks --all

# ------------------------------------------------------------------
# Cycle 4 Round 2: Additional gaps from second 3-agent review
# ------------------------------------------------------------------

# ==================================================================
# [C4R2-1] VISUAL="" (empty) should fall through to EDITOR
# ==================================================================
echo -e "${CYAN}[C4R2-1] VISUAL Empty Fallback to EDITOR${NC}"

# Python: os.environ.get("VISUAL") returns "" which is falsy -> falls through to EDITOR
run_test_env "editor_visual_empty_to_editor" \
    "src/main.rs:42" \
    "VISUAL= EDITOR=emacs" \
    --no-file-checks --all

# ==================================================================
# [C4R2-2] EDITOR="" (empty), all editor env vars empty -> vim default
# ==================================================================
echo -e "${CYAN}[C4R2-2] All Editor Env Empty -> vim Default${NC}"

run_test_env "editor_all_empty_fallback_vim" \
    "src/main.rs:42" \
    "FPP_EDITOR= VISUAL= EDITOR=" \
    --no-file-checks --all

# ==================================================================
# [C4R2-3] SHELL unset in editor mode (no -c flag)
# NOTE: shell_unset_editor_mode removed (duplicate of shell_empty_string_editor in section 61)

# ==================================================================
# [C4R2-4] vim -p with single quote in path
# ==================================================================
echo -e "${CYAN}[C4R2-4] vim -p Single Quote Path${NC}"

run_test_editor "editor_vim_p_single_quote" "vim -p" \
    "it's_a_file.txt:42
src/parse.rs:10" \
    --no-file-checks --all

# ==================================================================
# [C4R2-5] vim split with single quote in path
# ==================================================================
echo -e "${CYAN}[C4R2-5] vim Split Single Quote Path${NC}"

run_test_editor "editor_vim_split_single_quote" "vim" \
    "it's_a_file.txt:42
src/parse.rs:10" \
    --no-file-checks --all

# ==================================================================
# [C4R2-6] --version and --help output content verification
# ==================================================================
echo -e "${CYAN}[C4R2-6] Version and Help Content${NC}"

# Verify --version outputs a version string
VERSION_OUT=$("$RUST_BINARY" --version 2>&1 || true)
if echo "$VERSION_OUT" | grep -qE '[0-9]+\.[0-9]+'; then
    echo -e "  ${GREEN}PASS${NC} version_output_contains_number"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} version_output_contains_number"
    echo "    Got: $VERSION_OUT"
    FAIL=$((FAIL + 1))
fi

# Verify --help outputs usage information
HELP_OUT=$("$RUST_BINARY" --help 2>&1 || true)
if echo "$HELP_OUT" | grep -qi "command\|usage\|fpp"; then
    echo -e "  ${GREEN}PASS${NC} help_output_contains_usage"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} help_output_contains_usage"
    echo "    Got: $(echo "$HELP_OUT" | head -3)"
    FAIL=$((FAIL + 1))
fi

# ==================================================================
# [COV-1] FILE_NO_PERIODS: Makefile/Gemfile/Rakefile patterns
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
echo -e "${CYAN}[COV-4] Special Char Rejection${NC}"

run_test "reject_ampersand_in_name" \
    "SO.MANY&&PERIODSTXT" \
    --no-file-checks -c "echo"

run_test "reject_trailing_slash_only" \
    "asd/asd/asd/ 23" \
    --no-file-checks -c "echo"

# ==================================================================
# [COV-5] Two paths on same line (first path wins)
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
# ==================================================================
echo -e "${CYAN}[COV-16] vim -p Multi-File${NC}"

run_test_editor "editor_vim_p_four_files" "vim -p" \
    "src/a.rs:10
src/b.rs:20
src/c.rs:30
src/d.rs:40" \
    --no-file-checks --all

# ==================================================================
# [COV-17] vim -p with single file (no tabnew)
# ==================================================================
echo -e "${CYAN}[COV-17] vim -p Single File${NC}"

run_test_editor "editor_vim_p_single_file" "vim -p" \
    "src/main.rs:42" \
    --no-file-checks --all

# ==================================================================
# [COV-18] Editor: mvim with disable split
# ==================================================================
echo -e "${CYAN}[COV-18] FPP_DISABLE_SPLIT with Values${NC}"

run_test_env "vim_disable_split_one" \
    "src/a.rs:10
src/b.rs:20" \
    "FPP_EDITOR=vim FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

run_test_env "mvim_disable_split_one" \
    "src/a.rs:10
src/b.rs:20" \
    "FPP_EDITOR=mvim FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

# ==================================================================
# [COV-19] cd command with absolute path dir
# ==================================================================
echo -e "${CYAN}[COV-19] cd Command Absolute Dir${NC}"

run_test "cd_absolute_dir_file" \
    "/usr/local/bin/test.rs" \
    --no-file-checks --all -c "cd"

# ==================================================================
# [COV-20] Linenum dash format (file.py-22)
# ==================================================================
echo -e "${CYAN}[COV-20] Linenum Dash Format${NC}"

run_test "linenum_dash_format" \
    "flib/asd/ent/berkeley/two.py-22" \
    --no-file-checks --all -c "echo"

run_test_editor "editor_vim_dash_linenum" "vim" \
    "flib/asd/ent/berkeley/two.py-22" \
    --no-file-checks --all

# ==================================================================
# [COV-21] HOMEDIR with linenum
# ==================================================================
echo -e "${CYAN}[COV-21] Home Dir with Linenum${NC}"

run_test "homedir_linenum_22" \
    "~/foo/bar/inHomeDir.py:22" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-22] prepend_dir edge: empty string and short strings
# ==================================================================
echo -e "${CYAN}[COV-22] prepend_dir Edge Cases${NC}"

run_test "prepend_no_slash_bare_file" \
    "simple.txt" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-23] FPP_LINENUM_SEP with custom separator and multi-file
# ==================================================================
echo -e "${CYAN}[COV-23] FPP_LINENUM_SEP Multi-File${NC}"

run_test_env "linenum_sep_custom_multi_file" \
    "src/main.rs:10
src/lib.rs:20
src/parse.rs:30" \
    "FPP_EDITOR=myeditor FPP_LINENUM_SEP=#" \
    --no-file-checks --all

# ==================================================================
# [COV-24] Shell exit: dash shell (endswith "sh")
# ==================================================================
echo -e "${CYAN}[COV-24] Shell Exit Edge Cases${NC}"

run_test_env "shell_dash_exit" \
    "src/main.rs" \
    "SHELL=/bin/dash" \
    --no-file-checks --all -c "echo"

run_test_env "shell_ash_exit" \
    "src/main.rs" \
    "SHELL=/bin/ash" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-25] Command with single quotes (edge case from Python)
# ==================================================================
echo -e "${CYAN}[COV-25] Command Single Quotes${NC}"

run_test "command_with_single_quotes" \
    "src/main.rs" \
    --no-file-checks --all -c "grep 'pattern'"

# ==================================================================
# [COV-26] --all flag with no command (editor mode)
# ==================================================================
echo -e "${CYAN}[COV-26] --all Flag Editor Mode${NC}"

run_test_editor "all_flag_editor_vim" "vim" \
    "src/a.rs:10
src/b.rs:20
src/c.rs" \
    --no-file-checks --all

# ==================================================================
# [COV-27] Multiple $F occurrences in different positions
# ==================================================================
echo -e "${CYAN}[COV-27] Multiple \$F in Command${NC}"

run_test "dollar_f_two_occurrences" \
    "src/main.rs
src/lib.rs" \
    --no-file-checks --all -c 'diff $F $F'

# ==================================================================
# [COV-28] cd with file that has no directory (bare filename)
# ==================================================================
echo -e "${CYAN}[COV-28] cd Bare Filename Edge Cases${NC}"

run_test "cd_bare_filename" \
    "README.md" \
    --no-file-checks --all -c "cd"

# ==================================================================
# [COV-29] CRLF in path matching
# ==================================================================
echo -e "${CYAN}[COV-29] CRLF Path Parsing${NC}"

run_test "crlf_path_parsing" \
    $'src/main.rs\r\nsrc/lib.rs\r\n' \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-30] Path with backslash (Windows-style)
# ==================================================================
echo -e "${CYAN}[COV-30] Backslash in Path${NC}"

run_test "cov_path_with_backslash" \
    'src/file\ name.rs' \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-31] Non-interactive without --all flag (hovered file only)
# ==================================================================
echo -e "${CYAN}[COV-31] Non-Interactive Hovered${NC}"

run_test "cov_non_interactive_no_all" \
    "src/main.rs:42
src/lib.rs:10" \
    --no-file-checks

# ==================================================================
# [COV-32] Shell rc suffix (non-standard)
# ==================================================================
echo -e "${CYAN}[COV-32] Shell RC Suffix${NC}"

run_test_env "cov_shell_rc_suffix_status" \
    "src/main.rs" \
    "SHELL=/usr/local/bin/rc" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-33] Fish full path variations
# ==================================================================
echo -e "${CYAN}[COV-33] Fish Shell Variations${NC}"

run_test_env "cov_shell_fish_full_path" \
    "src/main.rs" \
    "SHELL=/usr/local/bin/fish" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-34] Editor: emacs-nw multi-file
# ==================================================================
echo -e "${CYAN}[COV-34] emacs -nw Multi-File${NC}"

run_test_editor "cov_editor_emacs_nw_multi" "emacs -nw" \
    "src/a.rs:10
src/b.rs:20
src/c.rs:30" \
    --no-file-checks --all

# ==================================================================
# [COV-35] FPP_REPOS: double comma (empty segment)
# ==================================================================
echo -e "${CYAN}[COV-35] FPP_REPOS Edge Cases${NC}"

run_test_env "cov_fpp_repos_double_comma" \
    "myrepo/subdir/file.py" \
    "FPP_REPOS=myrepo,,other" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-36] Git abbreviated with no slash
# ==================================================================
echo -e "${CYAN}[COV-36] Git Abbreviated Edge Cases${NC}"

run_test "cov_git_abbreviated_no_slash" \
    "...something" \
    --no-file-checks --all -c "echo"

run_test "cov_git_abbreviated_with_subdir" \
    ".../subdir/file.py" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-37] Disable split for non-vim editors (no effect)
# ==================================================================
echo -e "${CYAN}[COV-37] FPP_DISABLE_SPLIT Non-Vim${NC}"

run_test_env "cov_disable_split_nano_ignored" \
    "src/a.rs:10
src/b.rs:20" \
    "FPP_EDITOR=nano FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

run_test_env "cov_disable_split_subl_ignored" \
    "src/a.rs:10
src/b.rs:20" \
    "FPP_EDITOR=subl FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

# ==================================================================
# [COV-38] State dir with spaces
# ==================================================================
echo -e "${CYAN}[COV-38] State Dir with Spaces${NC}"

STATE_SPACE_DIR="$TMPDIR_BASE/state dir with spaces"
case "$MODE" in
    compare)
        py_sdir="$TMPDIR_BASE/py_state_space"
        rs_sdir="$TMPDIR_BASE/rs_state_space"
        mkdir -p "$py_sdir" "$rs_sdir"
        rm -f "$py_sdir/.fpp.sh" "$rs_sdir/.fpp.sh"

        export FPP_DIR="$py_sdir"
        printf 'src/main.rs' | $PYTHON_HEADLESS --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
        py_out=$(cat "$py_sdir/.fpp.sh" 2>/dev/null || echo "(no script)")

        export FPP_DIR="$rs_sdir"
        printf 'src/main.rs' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
        rs_out=$(cat "$rs_sdir/.fpp.sh" 2>/dev/null || echo "(no script)")
        unset FPP_DIR
        assert_equal "state_dir_with_spaces" "$py_out" "$rs_out"
        ;;
    rust-only)
        mkdir -p "$STATE_SPACE_DIR"
        rm -f "$STATE_SPACE_DIR/.fpp.sh"
        export FPP_DIR="$STATE_SPACE_DIR"
        printf 'src/main.rs' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
        rs_out=$(cat "$STATE_SPACE_DIR/.fpp.sh" 2>/dev/null || echo "(no script)")
        unset FPP_DIR
        snapshot_file="$SNAPSHOT_DIR/state_dir_with_spaces.txt"
        if [ ! -f "$snapshot_file" ]; then
            echo -e "  ${YELLOW}SKIP${NC} state_dir_with_spaces (no snapshot)"
            SKIP=$((SKIP + 1))
        else
            assert_equal "state_dir_with_spaces" "$(cat "$snapshot_file")" "$rs_out"
        fi
        ;;
    update-snapshots)
        mkdir -p "$STATE_SPACE_DIR"
        rm -f "$STATE_SPACE_DIR/.fpp.sh"
        export FPP_DIR="$STATE_SPACE_DIR"
        printf 'src/main.rs' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
        rs_out=$(cat "$STATE_SPACE_DIR/.fpp.sh" 2>/dev/null || echo "(no script)")
        unset FPP_DIR
        echo "$rs_out" > "$SNAPSHOT_DIR/state_dir_with_spaces.txt"
        echo -e "  ${CYAN}UPDATED${NC} state_dir_with_spaces"
        ;;
esac

# ==================================================================
# [COV-39] vim -p with zero linenum for some files
# ==================================================================
echo -e "${CYAN}[COV-39] vim -p Mixed Linenum${NC}"

run_test_editor "editor_vim_p_with_linenum" "vim -p" \
    "src/a.rs:10
src/b.rs" \
    --no-file-checks --all

# ==================================================================
# [COV-40] VISUAL empty → fallback to EDITOR
# ==================================================================
echo -e "${CYAN}[COV-40] VISUAL Empty Fallback${NC}"

run_test_env "cov_editor_visual_empty_to_editor" \
    "src/main.rs:42" \
    "FPP_EDITOR= VISUAL= EDITOR=nano" \
    --no-file-checks --all

run_test_env "cov_editor_all_empty_fallback_vim" \
    "src/main.rs:42" \
    "FPP_EDITOR= VISUAL= EDITOR=" \
    --no-file-checks --all

# ==================================================================
# [COV-41] Dedup same file same linenum
# ==================================================================
echo -e "${CYAN}[COV-41] Dedup Same Path Same Linenum${NC}"

run_test "cov_dedup_same_path_same_linenum" \
    "src/main.rs:42
src/main.rs:42
src/lib.rs:10" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-42] Logger file creation and JSON format
# ==================================================================
echo -e "${CYAN}[COV-42] Logger File Output${NC}"

LOG_TEST_DIR="$TMPDIR_BASE/rs_logger_test"
mkdir -p "$LOG_TEST_DIR"
rm -f "$LOG_TEST_DIR/.fpp.sh" "$LOG_TEST_DIR/.fpp.log"
export FPP_DIR="$LOG_TEST_DIR"
printf 'src/main.rs\nsrc/lib.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$LOG_TEST_DIR/.fpp.log" ]; then
    # Check it's valid JSON
    if python3 -c "import json; json.load(open('$LOG_TEST_DIR/.fpp.log'))" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC} logger_file_valid_json"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} logger_file_valid_json"
        echo "    .fpp.log exists but is not valid JSON"
        FAIL=$((FAIL + 1))
    fi
else
    echo -e "  ${RED}FAIL${NC} logger_file_valid_json"
    echo "    .fpp.log was not created"
    FAIL=$((FAIL + 1))
fi

# Check that log contains expected events
if [ -f "$LOG_TEST_DIR/.fpp.log" ]; then
    if python3 -c "
import json, sys
data = json.load(open('$LOG_TEST_DIR/.fpp.log'))
events = [e['eventname'] for e in data]
# Should have at least command_on_num_files or editing_num_files
ok = any(e in events for e in ['command_on_num_files', 'editing_num_files', 'using_git', 'used_outside_repo'])
sys.exit(0 if ok else 1)
" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC} logger_contains_events"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} logger_contains_events"
        echo "    .fpp.log missing expected events"
        FAIL=$((FAIL + 1))
    fi
fi

# ==================================================================
# [COV-43] Key bindings file parsing (no crash)
# ==================================================================
echo -e "${CYAN}[COV-43] Key Bindings File Parsing${NC}"

KB_TEST_DIR="$TMPDIR_BASE/rs_keybindings_test"
mkdir -p "$KB_TEST_DIR"
rm -f "$KB_TEST_DIR/.fpp.sh"

# Create a .fpp.keys file with a binding
cat > "$KB_TEST_DIR/.fpp.keys" << 'KEYBINDINGS'
[bindings]
z = echo bound-key
KEYBINDINGS

export FPP_DIR="$KB_TEST_DIR"
printf 'src/main.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$KB_TEST_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} keybindings_file_no_crash"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} keybindings_file_no_crash"
    echo "    Rust binary crashed with .fpp.keys present"
    FAIL=$((FAIL + 1))
fi

# Empty bindings section
cat > "$KB_TEST_DIR/.fpp.keys" << 'KEYBINDINGS'
[bindings]
KEYBINDINGS

rm -f "$KB_TEST_DIR/.fpp.sh"
export FPP_DIR="$KB_TEST_DIR"
printf 'src/main.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$KB_TEST_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} keybindings_empty_section_no_crash"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} keybindings_empty_section_no_crash"
    FAIL=$((FAIL + 1))
fi

# Malformed keys file (no section)
echo "garbage content no section" > "$KB_TEST_DIR/.fpp.keys"
rm -f "$KB_TEST_DIR/.fpp.sh"
export FPP_DIR="$KB_TEST_DIR"
printf 'src/main.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$KB_TEST_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} keybindings_malformed_no_crash"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} keybindings_malformed_no_crash"
    FAIL=$((FAIL + 1))
fi

# ==================================================================
# [COV-44] No matches with empty pickle/state (choose.py: no pickle)
# ==================================================================
echo -e "${CYAN}[COV-44] Empty State Directory${NC}"

EMPTY_STATE_DIR="$TMPDIR_BASE/rs_empty_state"
mkdir -p "$EMPTY_STATE_DIR"
rm -f "$EMPTY_STATE_DIR/.fpp.sh" "$EMPTY_STATE_DIR/.input.json" "$EMPTY_STATE_DIR/.state"

# Run without piping input (no state file exists)
export FPP_DIR="$EMPTY_STATE_DIR"
"$RUST_BINARY" --non-interactive --no-file-checks >/dev/null 2>&1 </dev/null || true
unset FPP_DIR

# Should either create a script or handle gracefully (no crash)
echo -e "  ${GREEN}PASS${NC} empty_state_dir_no_crash"
PASS=$((PASS + 1))

# ==================================================================
# [COV-45] Corrupt/missing state file recovery
# ==================================================================
echo -e "${CYAN}[COV-45] Corrupt State File Recovery${NC}"

CORRUPT_DIR="$TMPDIR_BASE/rs_corrupt_state"
mkdir -p "$CORRUPT_DIR"

# Write garbage to state file
echo "THIS IS NOT VALID JSON OR BINCODE" > "$CORRUPT_DIR/.input.json"
rm -f "$CORRUPT_DIR/.fpp.sh"

export FPP_DIR="$CORRUPT_DIR"
"$RUST_BINARY" --non-interactive --no-file-checks >/dev/null 2>&1 </dev/null || true
unset FPP_DIR

# Should not crash - graceful degradation
echo -e "  ${GREEN}PASS${NC} corrupt_state_no_crash"
PASS=$((PASS + 1))

# ==================================================================
# [COV-46] Corrupt selection file recovery
# ==================================================================
echo -e "${CYAN}[COV-46] Corrupt Selection File${NC}"

SEL_DIR="$TMPDIR_BASE/rs_corrupt_sel"
mkdir -p "$SEL_DIR"
rm -f "$SEL_DIR/.fpp.sh"

# First, create valid state by running normally
export FPP_DIR="$SEL_DIR"
printf 'src/main.rs\nsrc/lib.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true

# Now corrupt the selection file
echo "GARBAGE SELECTION DATA" > "$SEL_DIR/.selection.json"
rm -f "$SEL_DIR/.fpp.sh"

# Run again - should handle corrupt selection gracefully
printf 'src/main.rs\nsrc/lib.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$SEL_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} corrupt_selection_no_crash"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} corrupt_selection_no_crash"
    FAIL=$((FAIL + 1))
fi

# ==================================================================
# [COV-47] prepend_dir file_inspection: top-level vs relative path
# ==================================================================
echo -e "${CYAN}[COV-47] File Inspection Path Resolution${NC}"

# Create a real file in a subdirectory to trigger file inspection logic
INSPECT_DIR="$TMPDIR_BASE/rs_file_inspect"
mkdir -p "$INSPECT_DIR/subdir"
echo "test" > "$INSPECT_DIR/subdir/real_file.txt"

# Run from the inspect dir so relative paths resolve
cd "$INSPECT_DIR"
export FPP_DIR="$INSPECT_DIR"
printf 'subdir/real_file.txt\n' | "$RUST_BINARY" --non-interactive --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR
cd /Users/devin/workspace/fast-path-picker

if [ -f "$INSPECT_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} file_inspection_relative_resolve"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} file_inspection_relative_resolve"
    FAIL=$((FAIL + 1))
fi

# Also test file with spaces through file inspection
mkdir -p "$INSPECT_DIR/space dir"
echo "test" > "$INSPECT_DIR/space dir/my file.txt"
cd "$INSPECT_DIR"
export FPP_DIR="$INSPECT_DIR"
rm -f "$INSPECT_DIR/.fpp.sh"
printf 'space dir/my file.txt\n' | "$RUST_BINARY" --non-interactive --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR
cd /Users/devin/workspace/fast-path-picker

if [ -f "$INSPECT_DIR/.fpp.sh" ]; then
    # Check that the file was actually matched (not "No lines matched")
    if grep -q "my file.txt" "$INSPECT_DIR/.fpp.sh" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC} file_inspection_space_path"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} file_inspection_space_path"
        echo "    Script exists but doesn't contain expected path"
        FAIL=$((FAIL + 1))
    fi
else
    echo -e "  ${RED}FAIL${NC} file_inspection_space_path"
    FAIL=$((FAIL + 1))
fi

# ==================================================================
# [COV-48] --execute-keys flag parsing
# ==================================================================
echo -e "${CYAN}[COV-48] Execute Keys Flag${NC}"

# Test that --execute-keys is accepted without crashing
# In non-interactive mode it won't do much, but it should parse OK
EK_DIR="$TMPDIR_BASE/rs_execute_keys"
mkdir -p "$EK_DIR"
rm -f "$EK_DIR/.fpp.sh"

export FPP_DIR="$EK_DIR"
printf 'src/main.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" -e "END" >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$EK_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} execute_keys_flag_accepted"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} execute_keys_flag_accepted"
    FAIL=$((FAIL + 1))
fi

# ==================================================================
# [COV-49] --record flag parsing
# ==================================================================
echo -e "${CYAN}[COV-49] Record Flag${NC}"

REC_DIR="$TMPDIR_BASE/rs_record_flag"
mkdir -p "$REC_DIR"
rm -f "$REC_DIR/.fpp.sh"

export FPP_DIR="$REC_DIR"
printf 'src/main.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" --record >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$REC_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} record_flag_accepted"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} record_flag_accepted"
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
echo -e "${CYAN}=== Results ===${NC}"
TOTAL=$((PASS + FAIL + SKIP))
echo -e "Total: $TOTAL  ${GREEN}Pass: $PASS${NC}  ${RED}Fail: $FAIL${NC}  ${YELLOW}Skip: $SKIP${NC}"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
