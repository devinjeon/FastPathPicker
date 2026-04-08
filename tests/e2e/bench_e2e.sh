#!/bin/bash
# e2e performance comparison: Python fpp vs Rust fpp
#
# Measures and compares execution time of both binaries on identical inputs.
# Each test is repeated N times and compared by median.
#
# Usage:
#   ./tests/e2e/bench_e2e.sh              # default (5 iterations)
#   ./tests/e2e/bench_e2e.sh -n 20        # 20 iterations
#   ./tests/e2e/bench_e2e.sh --rust-only  # measure Rust only
#   FPP_BINARY=/path/to/fpp ./tests/e2e/bench_e2e.sh --rust-only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INPUTS_DIR="$PROJECT_ROOT/PathPicker/src/tests/inputs"
TMPDIR_BASE="$(mktemp -d)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Defaults
RUST_BINARY="${FPP_BINARY:-$PROJECT_ROOT/target/release/fpp}"
PYTHON_HEADLESS="python3 $SCRIPT_DIR/fpp_headless.py"
ITERATIONS=5
MODE="compare"  # compare | rust-only

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) ITERATIONS="$2"; shift 2 ;;
        --rust-only) MODE="rust-only"; shift ;;
        --help)
            echo "Usage: $0 [-n ITERATIONS] [--rust-only]"
            echo ""
            echo "Options:"
            echo "  -n N          Number of iterations per test (default: 5)"
            echo "  --rust-only   Only measure Rust binary"
            echo ""
            echo "Environment:"
            echo "  FPP_BINARY    Path to Rust binary (default: target/release/fpp)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

# === Timing helpers ===

# Returns elapsed time in milliseconds
# Usage: time_cmd <output_var> <cmd...>
# Stores ms in $REPLY
time_ms() {
    local start end
    start=$(python3 -c "import time; print(int(time.monotonic_ns()))")
    "$@" >/dev/null 2>&1 || true
    end=$(python3 -c "import time; print(int(time.monotonic_ns()))")
    REPLY=$(( (end - start) / 1000000 ))
}

# Compute median from a list of numbers
# Usage: median <n1> <n2> ...
median() {
    printf '%s\n' "$@" | sort -n | awk '{a[NR]=$1} END{if(NR%2==1)print a[(NR+1)/2]; else print (a[NR/2]+a[NR/2+1])/2}'
}

# Compute min from a list of numbers
min_of() {
    printf '%s\n' "$@" | sort -n | head -1
}

# Run benchmark for a single test case
# Usage: bench <name> <input> <flags...>
bench() {
    local name="$1"
    local input="$2"
    shift 2
    local flags=("$@")

    local rs_times=()
    local py_times=()

    # Rust
    for i in $(seq 1 "$ITERATIONS"); do
        local state_dir="$TMPDIR_BASE/rs_${name}_${i}"
        mkdir -p "$state_dir"
        rm -f "$state_dir/.fpp.sh" "$state_dir/.input.json" "$state_dir/.selection.json"
        export FPP_DIR="$state_dir"
        time_ms bash -c "printf '%s' '$input' | '$RUST_BINARY' --non-interactive ${flags[*]}"
        rs_times+=("$REPLY")
        unset FPP_DIR
    done

    # Python (if compare mode)
    if [ "$MODE" = "compare" ]; then
        for i in $(seq 1 "$ITERATIONS"); do
            local state_dir="$TMPDIR_BASE/py_${name}_${i}"
            mkdir -p "$state_dir"
            rm -f "$state_dir/.fpp.sh" "$state_dir/.pickle" "$state_dir/.selection.pickle"
            export FPP_DIR="$state_dir"
            time_ms bash -c "printf '%s' '$input' | $PYTHON_HEADLESS ${flags[*]}"
            py_times+=("$REPLY")
            unset FPP_DIR
        done
    fi

    # Compute stats
    local rs_med rs_min
    rs_med=$(median "${rs_times[@]}")
    rs_min=$(min_of "${rs_times[@]}")

    if [ "$MODE" = "compare" ]; then
        local py_med py_min speedup
        py_med=$(median "${py_times[@]}")
        py_min=$(min_of "${py_times[@]}")
        if [ "$rs_med" -gt 0 ]; then
            speedup=$(python3 -c "print(f'{$py_med/$rs_med:.1f}')")
        else
            speedup="inf"
        fi

        local color="$GREEN"
        if python3 -c "exit(0 if $py_med/$rs_med < 1.5 else 1)" 2>/dev/null; then
            color="$YELLOW"
        fi

        printf "  %-35s %s%6sms%s  %s%6sms%s  ${BOLD}${color}%5sx${NC}\n" \
            "$name" \
            "$DIM" "$rs_med" "$NC" \
            "$DIM" "$py_med" "$NC" \
            "$speedup"
    else
        printf "  %-35s %s%6sms%s  (min: %sms)\n" \
            "$name" \
            "$DIM" "$rs_med" "$NC" \
            "$rs_min"
    fi
}

# File input variant
bench_file() {
    local name="$1"
    local input_file="$2"
    shift 2
    local flags=("$@")

    local rs_times=()
    local py_times=()

    # Rust
    for i in $(seq 1 "$ITERATIONS"); do
        local state_dir="$TMPDIR_BASE/rs_${name}_${i}"
        mkdir -p "$state_dir"
        rm -f "$state_dir/.fpp.sh" "$state_dir/.input.json" "$state_dir/.selection.json"
        export FPP_DIR="$state_dir"
        time_ms bash -c "'$RUST_BINARY' --non-interactive ${flags[*]} < '$input_file'"
        rs_times+=("$REPLY")
        unset FPP_DIR
    done

    if [ "$MODE" = "compare" ]; then
        for i in $(seq 1 "$ITERATIONS"); do
            local state_dir="$TMPDIR_BASE/py_${name}_${i}"
            mkdir -p "$state_dir"
            rm -f "$state_dir/.fpp.sh" "$state_dir/.pickle" "$state_dir/.selection.pickle"
            export FPP_DIR="$state_dir"
            time_ms bash -c "$PYTHON_HEADLESS ${flags[*]} < '$input_file'"
            py_times+=("$REPLY")
            unset FPP_DIR
        done
    fi

    local rs_med rs_min
    rs_med=$(median "${rs_times[@]}")
    rs_min=$(min_of "${rs_times[@]}")

    if [ "$MODE" = "compare" ]; then
        local py_med py_min speedup
        py_med=$(median "${py_times[@]}")
        py_min=$(min_of "${py_times[@]}")
        if [ "$rs_med" -gt 0 ]; then
            speedup=$(python3 -c "print(f'{$py_med/$rs_med:.1f}')")
        else
            speedup="inf"
        fi

        local color="$GREEN"
        if python3 -c "exit(0 if $py_med/$rs_med < 1.5 else 1)" 2>/dev/null; then
            color="$YELLOW"
        fi

        printf "  %-35s %s%6sms%s  %s%6sms%s  ${BOLD}${color}%5sx${NC}\n" \
            "$name" \
            "$DIM" "$rs_med" "$NC" \
            "$DIM" "$py_med" "$NC" \
            "$speedup"
    else
        printf "  %-35s %s%6sms%s  (min: %sms)\n" \
            "$name" \
            "$DIM" "$rs_med" "$NC" \
            "$rs_min"
    fi
}

# === Prerequisite checks ===

echo -e "${CYAN}=== e2e Performance Benchmark ===${NC}"
echo "Mode: $MODE | Iterations: $ITERATIONS"
echo "Rust: $RUST_BINARY"
[ "$MODE" = "compare" ] && echo "Python: $PYTHON_HEADLESS"
echo ""

if [ ! -f "$RUST_BINARY" ]; then
    echo -e "${RED}Rust binary not found. Run 'make build' first.${NC}"
    exit 1
fi

# Warmup
echo -e "${DIM}Warming up...${NC}"
echo "warmup.txt" | FPP_DIR="$TMPDIR_BASE/warmup" "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
if [ "$MODE" = "compare" ]; then
    echo "warmup.txt" | FPP_DIR="$TMPDIR_BASE/warmup_py" $PYTHON_HEADLESS --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
fi
echo ""

# === Header ===

if [ "$MODE" = "compare" ]; then
    printf "  ${BOLD}%-35s %8s  %8s  %6s${NC}\n" "Test" "Rust" "Python" "Speed"
    printf "  %-35s %8s  %8s  %6s\n" "-----------------------------------" "--------" "--------" "------"
else
    printf "  ${BOLD}%-35s %8s  %8s${NC}\n" "Test" "Median" "Min"
    printf "  %-35s %8s  %8s\n" "-----------------------------------" "--------" "--------"
fi

# === Benchmarks ===

echo -e "\n${CYAN}[Small inputs]${NC}"

bench "single_file" \
    "src/main.rs" \
    --no-file-checks --all -c "echo"

bench "3_files_git_status" \
    " M src/main.rs
 M src/parse.rs
?? new_file.txt" \
    --no-file-checks --all -c "echo"

bench "5_files_grep" \
    "src/main.rs:42: fn main()
src/parse.rs:10: use regex
src/format.rs:1: mod tests
src/line.rs:5: struct Line
src/output.rs:20: fn compose" \
    --no-file-checks --all -c "echo"

echo -e "\n${CYAN}[Medium inputs]${NC}"

bench_file "gitDiff_14files" \
    "$INPUTS_DIR/gitDiff.txt" \
    --no-file-checks --all -c "echo"

bench_file "gitDiffColor_19files" \
    "$INPUTS_DIR/gitDiffColor.txt" \
    --no-file-checks --all -c "echo"

bench_file "longList_100files" \
    "$INPUTS_DIR/longList.txt" \
    --no-file-checks --all -c "echo"

echo -e "\n${CYAN}[Large inputs]${NC}"

bench_file "tonsOfFiles_44files" \
    "$INPUTS_DIR/tonsOfFiles.txt" \
    --no-file-checks --all -c "echo"

bench_file "gitLongDiff" \
    "$INPUTS_DIR/gitLongDiff.txt" \
    --no-file-checks --all -c "echo"

bench_file "gitLongDiffColor" \
    "$INPUTS_DIR/gitLongDiffColor.txt" \
    --no-file-checks --all -c "echo"

# Generate 500-line input
LARGE_INPUT=""
for i in $(seq 1 500); do
    LARGE_INPUT+="src/module${i}/file${i}.rs:${i}: fn func_${i}()
"
done
echo "$LARGE_INPUT" > "$TMPDIR_BASE/large_input.txt"

bench_file "generated_500_lines" \
    "$TMPDIR_BASE/large_input.txt" \
    --no-file-checks --all -c "echo"

# Generate 2000-line input
HUGE_INPUT=""
for i in $(seq 1 2000); do
    HUGE_INPUT+="src/deep/nested/path/module${i}/file${i}.rs:${i}: fn function_name_${i}()
"
done
echo "$HUGE_INPUT" > "$TMPDIR_BASE/huge_input.txt"

bench_file "generated_2000_lines" \
    "$TMPDIR_BASE/huge_input.txt" \
    --no-file-checks --all -c "echo"

echo -e "\n${CYAN}[Special modes]${NC}"

bench "all_input_mode" \
    "  fix3
  gh-pages
* master
  testAllInput
  trunk
  feature/long-branch-name
  release/v2.0
  hotfix/critical-bug" \
    --all-input --all -c "echo"

bench "command_gen_5files" \
    "src/main.rs:42
src/parse.rs:10
src/format.rs:1
src/line.rs:5
src/output.rs:20" \
    --no-file-checks --all -c "git add"

bench "no_matches_input" \
    "this is just plain text with no file paths
another line of irrelevant content
yet another boring line here
no files to be found anywhere
just regular english text" \
    -c "echo"

# === Summary ===

echo ""
echo -e "${CYAN}=== Benchmark Complete ===${NC}"
echo "Iterations per test: $ITERATIONS"
echo "Times shown are median values in milliseconds."
if [ "$MODE" = "compare" ]; then
    echo "Speed column = Python time / Rust time (higher = Rust is faster)."
fi
