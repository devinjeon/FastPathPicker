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
