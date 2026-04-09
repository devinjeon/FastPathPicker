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

run_test_env "alias_fish_no_shopt" \
    "src/main.rs" \
    "SHELL=/usr/bin/fish FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

run_test_env "alias_bash_has_shopt" \
    "src/main.rs" \
    "SHELL=/bin/bash FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

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

# Basic piped input should work (this was failing before the use-dev-tty fix)
run_test "pipe_git_status" \
    " M src/main.rs
 M src/parse.rs
?? new_file.txt" \
    --no-file-checks --all -c "echo"

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
