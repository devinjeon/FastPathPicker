#!/usr/bin/env bash
# =============================================================================
# Comprehensive e2e performance benchmark: Rust fpp2 vs Python fpp
#
# Uses hyperfine for statistical rigor (warmup, multiple runs, mean +/- sigma).
# Generates its own test inputs across multiple categories and sizes.
# Outputs human-readable tables and machine-readable JSON.
#
# Usage:
#   ./tests/e2e/bench_e2e.sh                    # full comparison
#   ./tests/e2e/bench_e2e.sh --rust-only        # Rust only
#   ./tests/e2e/bench_e2e.sh --runs 20          # 20 runs per benchmark
#   ./tests/e2e/bench_e2e.sh --json results.json # custom JSON output path
#   ./tests/e2e/bench_e2e.sh --quick             # fast iteration (warmup=1, runs=3)
#   FPP_BINARY=/path/to/fpp2 ./tests/e2e/bench_e2e.sh --rust-only
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_HEADLESS="$SCRIPT_DIR/fpp_headless.py"

# --- Colors ---------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Defaults --------------------------------------------------------------
RUST_BINARY="${FPP_BINARY:-$PROJECT_ROOT/target/release/fpp2}"
RUNS=10
WARMUP=3
MODE="compare"   # compare | rust-only
JSON_OUT=""
TMPDIR_BASE=""

# --- Parse arguments -------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rust-only)  MODE="rust-only"; shift ;;
        --runs|-n)    RUNS="$2"; shift 2 ;;
        --warmup)     WARMUP="$2"; shift 2 ;;
        --json)       JSON_OUT="$2"; shift 2 ;;
        --quick)      WARMUP=1; RUNS=3; shift ;;
        --help|-h)
            cat <<'USAGE'
Usage: bench_e2e.sh [OPTIONS]

Options:
  --rust-only       Only benchmark the Rust binary (skip Python)
  --runs, -n N      Number of measured runs per benchmark (default: 10)
  --warmup N        Number of warmup runs (default: 3)
  --quick           Quick mode: warmup=1, runs=3 for fast iteration
  --json PATH       Path for combined JSON output (default: auto in temp dir)
  --help, -h        Show this help

Environment:
  FPP_BINARY        Path to Rust binary (default: target/release/fpp2)
USAGE
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Prerequisite checks ---------------------------------------------------
if ! command -v hyperfine &>/dev/null; then
    echo -e "${RED}ERROR: hyperfine is required but not found.${NC}"
    echo "Install it with:"
    echo "  brew install hyperfine        # macOS"
    echo "  cargo install hyperfine       # any platform"
    echo "  apt install hyperfine         # Debian/Ubuntu"
    exit 1
fi

if [[ ! -x "$RUST_BINARY" ]]; then
    echo -e "${RED}ERROR: Rust binary not found at $RUST_BINARY${NC}"
    echo "Run 'make build' first."
    exit 1
fi

if [[ "$MODE" == "compare" ]] && ! python3 -c "import sys; sys.path.insert(0,'$PROJECT_ROOT/PathPicker/src'); import process_input" 2>/dev/null; then
    echo -e "${YELLOW}WARNING: Python PathPicker not available. Switching to --rust-only mode.${NC}"
    MODE="rust-only"
fi

# --- Temp directory ---------------------------------------------------------
TMPDIR_BASE="$(mktemp -d)"
JSON_DIR="$TMPDIR_BASE/json"
INPUT_DIR="$TMPDIR_BASE/inputs"
REAL_FILES_DIR="$TMPDIR_BASE/real_files"
mkdir -p "$JSON_DIR" "$INPUT_DIR" "$REAL_FILES_DIR"

if [[ -z "$JSON_OUT" ]]; then
    JSON_OUT="$TMPDIR_BASE/bench_results.json"
fi

cleanup() {
    # Copy JSON out before removing temp dir if it was inside temp
    if [[ "$JSON_OUT" == "$TMPDIR_BASE/"* ]]; then
        local final_json="$PROJECT_ROOT/bench_results.json"
        cp "$JSON_OUT" "$final_json" 2>/dev/null || true
        echo -e "\n${CYAN}JSON results:${NC} $final_json"
    fi
    rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

# --- Input generation helpers -----------------------------------------------

# Generate N lines of synthetic file paths (matches regex patterns)
gen_synthetic_match() {
    local n="$1"
    local outfile="$INPUT_DIR/synthetic_match_${n}.txt"
    if [[ -f "$outfile" ]]; then echo "$outfile"; return; fi
    python3 -c "
import random, os
exts = ['rs', 'py', 'js', 'ts', 'go', 'c', 'h', 'cpp', 'java', 'rb', 'sh', 'md', 'toml', 'yaml', 'json']
dirs = ['src', 'lib', 'pkg', 'internal', 'cmd', 'tests', 'bench', 'util', 'core', 'api']
subdirs = ['auth', 'db', 'cache', 'config', 'handler', 'model', 'service', 'worker', 'parser', 'format']
no_period_files = ['Makefile', '.gitignore', 'Dockerfile', 'Rakefile', 'Gemfile', 'LICENSE', 'CHANGELOG', '.dockerignore', '.editorconfig']
for i in range($n):
    d = random.choice(dirs)
    sd = random.choice(subdirs)
    ext = random.choice(exts)
    line_num = random.randint(1, 500)
    kind = i % 9
    if kind == 0:
        # grep-style: path:line: content
        print(f'{d}/{sd}/file_{i}.{ext}:{line_num}: fn func_{i}()')
    elif kind == 1:
        # git diff style
        print(f'a/{d}/{sd}/module_{i}.{ext}')
    elif kind == 2:
        # simple path with extension
        print(f'{d}/{sd}/component_{i}.{ext}')
    elif kind == 3:
        # path:line (no trailing content)
        print(f'{d}/{sd}/item_{i}.{ext}:{line_num}')
    elif kind == 4:
        # HOMEDIR_REGEX: ~/path/to/file.ext
        print(f'~/{d}/{sd}/home_file_{i}.{ext}')
    elif kind == 5:
        # MASTER_REGEX_WITH_SPACES: path with spaces/file.ext
        print(f'{d}/{sd}/dir with spaces/spaced_file_{i}.{ext}')
    elif kind == 6:
        # FILE_NO_PERIODS: Makefile, .gitignore, etc.
        print(f'{d}/{sd}/{random.choice(no_period_files)}')
    elif kind == 7:
        # ANSI colored line: colored path with line number
        print(f'\033[31m{d}/{sd}/colored_{i}.{ext}\033[0m:{line_num}: some content')
    else:
        # ANSI colored simple path
        print(f'\033[32m{d}/{sd}/green_{i}.{ext}\033[0m')
" > "$outfile"
    echo "$outfile"
}

# Generate N lines of plain text that do NOT match path regex patterns
gen_no_match() {
    local n="$1"
    local outfile="$INPUT_DIR/no_match_${n}.txt"
    if [[ -f "$outfile" ]]; then echo "$outfile"; return; fi
    python3 -c "
import random
words = ['the', 'quick', 'brown', 'fox', 'jumps', 'over', 'lazy', 'dog',
         'lorem', 'ipsum', 'dolor', 'sit', 'amet', 'consectetur',
         'performance', 'benchmark', 'results', 'indicate', 'that',
         'memory', 'allocation', 'pattern', 'should', 'be', 'optimized',
         'processing', 'pipeline', 'handles', 'concurrent', 'requests']
for i in range($n):
    length = random.randint(5, 15)
    line = ' '.join(random.choice(words) for _ in range(length))
    # Ensure no periods preceded by filename-like tokens
    print(f'{line} (line {i+1})')
" > "$outfile"
    echo "$outfile"
}

# Generate N lines of real file paths from this project (no -nfc needed)
gen_real_files() {
    local n="$1"
    local outfile="$REAL_FILES_DIR/real_${n}.txt"
    if [[ -f "$outfile" ]]; then echo "$outfile"; return; fi
    # Collect actual files from the project
    find "$PROJECT_ROOT" \
        -not -path '*/target/*' \
        -not -path '*/.git/*' \
        -not -path '*/node_modules/*' \
        -type f \
        2>/dev/null | head -"$((n * 2))" | python3 -c "import sys, random; lines=sys.stdin.read().splitlines(); random.shuffle(lines); print('\n'.join(lines))" | head -"$n" > "$outfile"
    # Guard: if no files were found, skip with warning
    local count
    count=$(wc -l < "$outfile")
    if (( count == 0 )); then
        echo -e "  ${YELLOW}WARNING: No real files found in project. Skipping real-files-${n} benchmark.${NC}" >&2
        rm -f "$outfile"
        echo ""
        return
    fi
    # If we don't have enough files, pad by repeating (use temp file to avoid self-append)
    while (( count < n )); do
        local remaining=$((n - count))
        local pad_file="${outfile}.pad"
        head -"$remaining" "$outfile" > "$pad_file"
        cat "$pad_file" >> "$outfile"
        rm -f "$pad_file"
        count=$(wc -l < "$outfile")
    done
    # Truncate to exact size
    head -"$n" "$outfile" > "${outfile}.tmp" && mv "${outfile}.tmp" "$outfile"
    echo "$outfile"
}

# --- Benchmark runner -------------------------------------------------------

# Counter for JSON fragments
BENCH_INDEX=0

# Wrapper around hyperfine that handles rust-only vs compare modes.
# Usage: run_bench <label> <category> <input_file> <rust_flags> <python_flags>
#   rust_flags:   flags for the Rust binary
#   python_flags: flags for the Python headless script
run_bench() {
    local label="$1"
    local category="$2"
    local input_file="$3"
    local rust_flags="$4"
    local python_flags="$5"

    local json_file="$JSON_DIR/bench_${BENCH_INDEX}.json"
    BENCH_INDEX=$((BENCH_INDEX + 1))

    # Each run gets a fresh state dir via --prepare (runs before every timing)
    local rust_state_dir="$TMPDIR_BASE/state_rs_${BENCH_INDEX}"
    local py_state_dir="$TMPDIR_BASE/state_py_${BENCH_INDEX}"

    local rust_cmd="FPP_DIR='$rust_state_dir' '$RUST_BINARY' --non-interactive $rust_flags < '$input_file'"
    local rust_prepare="rm -rf '$rust_state_dir' && mkdir -p '$rust_state_dir'"

    if [[ "$MODE" == "compare" ]]; then
        local py_cmd="FPP_DIR='$py_state_dir' python3 '$PYTHON_HEADLESS' $python_flags < '$input_file'"
        local py_prepare="rm -rf '$py_state_dir' && mkdir -p '$py_state_dir'"

        echo -e "  ${DIM}Running: $label${NC}"
        hyperfine \
            --warmup "$WARMUP" \
            --runs "$RUNS" \
            --export-json "$json_file" \
            --command-name "rust: $label" \
            --prepare "$rust_prepare" \
            "$rust_cmd" \
            --command-name "python: $label" \
            --prepare "$py_prepare" \
            "$py_cmd" \
            2>&1 | sed 's/^/    /'
    else
        echo -e "  ${DIM}Running: $label${NC}"
        hyperfine \
            --warmup "$WARMUP" \
            --runs "$RUNS" \
            --export-json "$json_file" \
            --command-name "rust: $label" \
            --prepare "$rust_prepare" \
            "$rust_cmd" \
            2>&1 | sed 's/^/    /'
    fi

    # Annotate JSON with metadata
    if [[ -f "$json_file" ]]; then
        python3 -c "
import json, sys
with open('$json_file') as f:
    data = json.load(f)
data['_meta'] = {'label': '$label', 'category': '$category', 'input_file': '$input_file'}
with open('$json_file', 'w') as f:
    json.dump(data, f, indent=2)
"
    fi
}

# --- Memory measurement (RSS) -----------------------------------------------
# Measures peak RSS in KB using /usr/bin/time on macOS or GNU time on Linux.
# Runs 5 times and reports the median for reliability.
measure_rss() {
    local label="$1"
    local input_file="$2"
    local flags="$3"
    local binary="$4"  # "rust" or "python"

    local samples=()
    local num_samples=5

    for (( s=0; s<num_samples; s++ )); do
        local state_dir="$TMPDIR_BASE/mem_${label}_${s}_$$"
        mkdir -p "$state_dir"

        local rss_kb=0
        local time_file
        time_file=$(mktemp)

        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS: /usr/bin/time -l reports "maximum resident set size" in bytes
            if [[ "$binary" == "rust" ]]; then
                /usr/bin/time -l env FPP_DIR="$state_dir" "$RUST_BINARY" --non-interactive $flags < "$input_file" > /dev/null 2> "$time_file" || true
            else
                /usr/bin/time -l env FPP_DIR="$state_dir" python3 "$PYTHON_HEADLESS" $flags < "$input_file" > /dev/null 2> "$time_file" || true
            fi
            rss_kb=$(grep -i "maximum resident" "$time_file" | awk '{print int($1/1024)}')
        else
            # Linux: /usr/bin/time -v reports in KB
            if [[ "$binary" == "rust" ]]; then
                /usr/bin/time -v env FPP_DIR="$state_dir" "$RUST_BINARY" --non-interactive $flags < "$input_file" > /dev/null 2> "$time_file" || true
            else
                /usr/bin/time -v env FPP_DIR="$state_dir" python3 "$PYTHON_HEADLESS" $flags < "$input_file" > /dev/null 2> "$time_file" || true
            fi
            rss_kb=$(grep -i "maximum resident" "$time_file" | awk '{print $NF}')
        fi

        rm -f "$time_file"
        # Ensure rss_kb is a valid number (default to 0 if measurement failed)
        if ! [[ "$rss_kb" =~ ^[0-9]+$ ]]; then
            rss_kb=0
        fi
        samples+=("$rss_kb")
        rm -rf "$state_dir"
    done

    # Return the median of collected samples
    printf '%s\n' "${samples[@]}" | sort -n | awk "NR==$(( (num_samples+1)/2 )){print}"
}

# =============================================================================
# MAIN
# =============================================================================

echo -e "${BOLD}${CYAN}=================================================================${NC}"
echo -e "${BOLD}${CYAN}  Fast PathPicker -- e2e Performance Benchmark${NC}"
echo -e "${BOLD}${CYAN}=================================================================${NC}"
echo ""
echo "  Mode:     $MODE"
echo "  Runs:     $RUNS (warmup: $WARMUP)"
echo "  Rust:     $RUST_BINARY"
[[ "$MODE" == "compare" ]] && echo "  Python:   python3 $PYTHON_HEADLESS"
echo "  Temp:     $TMPDIR_BASE"
echo "  hyperfine: $(hyperfine --version)"
echo ""

# ===== CATEGORY 1: Startup ==================================================
echo -e "${BOLD}${CYAN}=== Category 1: Startup ===${NC}"
echo ""

# --help (no stdin needed)
help_json="$JSON_DIR/bench_${BENCH_INDEX}.json"
BENCH_INDEX=$((BENCH_INDEX + 1))

if [[ "$MODE" == "compare" ]]; then
    echo -e "  ${DIM}Running: --help${NC}"
    hyperfine \
        --warmup "$WARMUP" \
        --runs "$RUNS" \
        --export-json "$help_json" \
        --command-name "rust: --help" \
        "'$RUST_BINARY' --help" \
        --command-name "python: --help" \
        "python3 -c \"import sys; sys.path.insert(0,'$PROJECT_ROOT/PathPicker/src'); from pathpicker.screen_flags import ScreenFlags; ScreenFlags.init_from_args(['--help'])\" 2>/dev/null || true" \
        2>&1 | sed 's/^/    /'
else
    echo -e "  ${DIM}Running: --help${NC}"
    hyperfine \
        --warmup "$WARMUP" \
        --runs "$RUNS" \
        --export-json "$help_json" \
        --command-name "rust: --help" \
        "'$RUST_BINARY' --help" \
        2>&1 | sed 's/^/    /'
fi

# Annotate help JSON
if [[ -f "$help_json" ]]; then
    python3 -c "
import json
with open('$help_json') as f:
    data = json.load(f)
data['_meta'] = {'label': '--help', 'category': 'startup', 'input_file': ''}
with open('$help_json', 'w') as f:
    json.dump(data, f, indent=2)
"
fi

# Empty input (no matches)
echo "" > "$INPUT_DIR/empty.txt"
run_bench "empty-input" "startup" "$INPUT_DIR/empty.txt" \
    "-c echo" \
    "--all --no-file-checks -c echo"
echo ""

# ===== CATEGORY 2: Synthetic match (with -nfc) ==============================
echo -e "${BOLD}${CYAN}=== Category 2: Synthetic Match (-nfc) ===${NC}"
echo ""

for size in 100 500 1000 5000 10000 20000 50000; do
    input_file=$(gen_synthetic_match "$size")
    run_bench "synth-match-${size}" "synthetic_match" "$input_file" \
        "--no-file-checks --all -c echo" \
        "--all --no-file-checks -c echo"
done
echo ""

# ===== CATEGORY 3: No-match ==================================================
echo -e "${BOLD}${CYAN}=== Category 3: No-match (plain text) ===${NC}"
echo ""

for size in 100 500 1000 5000 10000 20000 50000; do
    input_file=$(gen_no_match "$size")
    run_bench "no-match-${size}" "no_match" "$input_file" \
        "--all --no-file-checks -c echo" \
        "--all --no-file-checks -c echo"
done
echo ""

# ===== CATEGORY 4: Real files (file validation enabled) =====================
echo -e "${BOLD}${CYAN}=== Category 4: Real Files (with validation) ===${NC}"
echo ""

for size in 100 500 1000 5000; do
    input_file=$(gen_real_files "$size")
    if [[ -z "$input_file" || ! -f "$input_file" ]]; then
        continue
    fi
    run_bench "real-files-${size}" "real_files" "$input_file" \
        "--all -c echo" \
        "--all -c echo"
done
echo ""

# ===== CATEGORY 5: Real-world Inputs from tests/inputs/ ====================
echo -e "${BOLD}${CYAN}=== Category 5: Real-world Inputs (tests/inputs/) ===${NC}"
echo ""

REAL_INPUT_DIR="$PROJECT_ROOT/tests/inputs"
for input_name in gitDiff.txt gitDiffColor.txt tonsOfFiles.txt gitLongDiff.txt gitLongDiffColor.txt; do
    input_path="$REAL_INPUT_DIR/$input_name"
    if [[ -f "$input_path" ]]; then
        bench_label="real-input-${input_name%.txt}"
        run_bench "$bench_label" "real_world_inputs" "$input_path" \
            "--no-file-checks --all -c echo" \
            "--all --no-file-checks -c echo"
    else
        echo -e "  ${YELLOW}SKIP: $input_name not found${NC}"
    fi
done
echo ""

# ===== MEMORY MEASUREMENT ===================================================
echo -e "${BOLD}${CYAN}=== Memory Measurement (Peak RSS) ===${NC}"
echo ""

MEM_SIZES_SYNTH=(100 1000 10000 50000)
MEM_SIZES_REAL=(100 1000 5000)

# File to collect memory results for JSON output
MEM_JSON_FILE="$TMPDIR_BASE/memory_results.jsonl"
: > "$MEM_JSON_FILE"

printf "  ${BOLD}%-30s %12s" "Test" "Rust (KB)"
[[ "$MODE" == "compare" ]] && printf " %12s %8s" "Python (KB)" "Ratio"
printf "${NC}\n"
printf "  %-30s %12s" "------------------------------" "------------"
[[ "$MODE" == "compare" ]] && printf " %12s %8s" "------------" "--------"
printf "\n"

# Synthetic match memory
for size in "${MEM_SIZES_SYNTH[@]}"; do
    input_file=$(gen_synthetic_match "$size")
    rs_rss=$(measure_rss "synth_${size}" "$input_file" "--no-file-checks --all -c echo" "rust")

    if [[ "$MODE" == "compare" ]]; then
        py_rss=$(measure_rss "synth_${size}" "$input_file" "--all --no-file-checks -c echo" "python")
        if (( rs_rss > 0 )); then
            ratio=$(python3 -c "print(f'{$py_rss/$rs_rss:.1f}x')")
        else
            ratio="N/A"
        fi
        printf "  %-30s %12s %12s %8s\n" "synth-match-${size}" "$rs_rss" "$py_rss" "$ratio"
        echo "{\"label\":\"synth-match-${size}\",\"category\":\"synthetic_match\",\"rust_rss_kb\":${rs_rss},\"python_rss_kb\":${py_rss}}" >> "$MEM_JSON_FILE"
    else
        printf "  %-30s %12s\n" "synth-match-${size}" "$rs_rss"
        echo "{\"label\":\"synth-match-${size}\",\"category\":\"synthetic_match\",\"rust_rss_kb\":${rs_rss}}" >> "$MEM_JSON_FILE"
    fi
done

# No-match memory
for size in "${MEM_SIZES_SYNTH[@]}"; do
    input_file=$(gen_no_match "$size")
    rs_rss=$(measure_rss "nomatch_${size}" "$input_file" "--all --no-file-checks -c echo" "rust")

    if [[ "$MODE" == "compare" ]]; then
        py_rss=$(measure_rss "nomatch_${size}" "$input_file" "--all --no-file-checks -c echo" "python")
        if (( rs_rss > 0 )); then
            ratio=$(python3 -c "print(f'{$py_rss/$rs_rss:.1f}x')")
        else
            ratio="N/A"
        fi
        printf "  %-30s %12s %12s %8s\n" "no-match-${size}" "$rs_rss" "$py_rss" "$ratio"
        echo "{\"label\":\"no-match-${size}\",\"category\":\"no_match\",\"rust_rss_kb\":${rs_rss},\"python_rss_kb\":${py_rss}}" >> "$MEM_JSON_FILE"
    else
        printf "  %-30s %12s\n" "no-match-${size}" "$rs_rss"
        echo "{\"label\":\"no-match-${size}\",\"category\":\"no_match\",\"rust_rss_kb\":${rs_rss}}" >> "$MEM_JSON_FILE"
    fi
done

# Real files memory
for size in "${MEM_SIZES_REAL[@]}"; do
    input_file=$(gen_real_files "$size")
    if [[ -z "$input_file" || ! -f "$input_file" ]]; then
        continue
    fi
    rs_rss=$(measure_rss "real_${size}" "$input_file" "--all -c echo" "rust")

    if [[ "$MODE" == "compare" ]]; then
        py_rss=$(measure_rss "real_${size}" "$input_file" "--all -c echo" "python")
        if (( rs_rss > 0 )); then
            ratio=$(python3 -c "print(f'{$py_rss/$rs_rss:.1f}x')")
        else
            ratio="N/A"
        fi
        printf "  %-30s %12s %12s %8s\n" "real-files-${size}" "$rs_rss" "$py_rss" "$ratio"
        echo "{\"label\":\"real-files-${size}\",\"category\":\"real_files\",\"rust_rss_kb\":${rs_rss},\"python_rss_kb\":${py_rss}}" >> "$MEM_JSON_FILE"
    else
        printf "  %-30s %12s\n" "real-files-${size}" "$rs_rss"
        echo "{\"label\":\"real-files-${size}\",\"category\":\"real_files\",\"rust_rss_kb\":${rs_rss}}" >> "$MEM_JSON_FILE"
    fi
done

echo ""

# ===== Combine JSON results ==================================================
echo -e "${DIM}Combining JSON results...${NC}"

python3 -c "
import json, glob, os, platform, subprocess

results = {'benchmarks': [], 'memory': [], 'environment': {}}
json_dir = '$JSON_DIR'

# Collect environment info
try:
    cpu_model = subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], stderr=subprocess.DEVNULL).decode().strip()
except Exception:
    try:
        with open('/proc/cpuinfo') as f:
            for line in f:
                if 'model name' in line:
                    cpu_model = line.split(':',1)[1].strip()
                    break
            else:
                cpu_model = 'unknown'
    except Exception:
        cpu_model = 'unknown'

try:
    rust_version = subprocess.check_output(['rustc', '--version'], stderr=subprocess.DEVNULL).decode().strip()
except Exception:
    rust_version = 'unknown'

try:
    python_version = subprocess.check_output(['python3', '--version'], stderr=subprocess.DEVNULL).decode().strip()
except Exception:
    python_version = 'unknown'

results['environment'] = {
    'os': f'{platform.system()} {platform.release()}',
    'cpu': cpu_model,
    'rust_version': rust_version,
    'python_version': python_version,
}

# Collect hyperfine results
for jf in sorted(glob.glob(os.path.join(json_dir, 'bench_*.json')),
                  key=lambda p: int(os.path.basename(p).split('_')[1].split('.')[0])):
    with open(jf) as f:
        data = json.load(f)
    meta = data.get('_meta', {})
    for r in data.get('results', []):
        entry = {
            'label': meta.get('label', r.get('command', '')),
            'category': meta.get('category', 'unknown'),
            'command': r.get('command', ''),
            'mean_s': r.get('mean', 0),
            'stddev_s': r.get('stddev', 0),
            'median_s': r.get('median', 0),
            'min_s': r.get('min', 0),
            'max_s': r.get('max', 0),
            'times_s': r.get('times', []),
        }
        results['benchmarks'].append(entry)

# Collect memory results
mem_file = '$MEM_JSON_FILE'
if os.path.exists(mem_file):
    with open(mem_file) as f:
        for line in f:
            line = line.strip()
            if line:
                results['memory'].append(json.loads(line))

with open('$JSON_OUT', 'w') as f:
    json.dump(results, f, indent=2)

print(f'  Wrote {len(results[\"benchmarks\"])} benchmark + {len(results[\"memory\"])} memory entries to $JSON_OUT')
"

# ===== Summary table ========================================================
echo ""
echo -e "${BOLD}${CYAN}=== Summary ===${NC}"
echo ""

python3 -c "
import json
from collections import OrderedDict

with open('$JSON_OUT') as f:
    data = json.load(f)

benchmarks = data['benchmarks']

# Group by category, then by label, preserving insertion order
categories = OrderedDict()
for b in benchmarks:
    cat = b.get('category', 'unknown')
    # Identify rust/python from command field (has 'rust: label' / 'python: label' format)
    cmd = b.get('command', '')
    if cmd.startswith('rust: '):
        key = cmd[len('rust: '):]
        side = 'rust'
    elif cmd.startswith('python: '):
        key = cmd[len('python: '):]
        side = 'python'
    else:
        key = b['label']
        side = 'rust'

    categories.setdefault(cat, OrderedDict())
    categories[cat].setdefault(key, {})[side] = b

cat_titles = {
    'startup': 'Startup',
    'synthetic_match': 'Synthetic Match (-nfc)',
    'no_match': 'No-match (plain text)',
    'real_files': 'Real Files (with validation)',
    'real_world_inputs': 'Real-world Inputs (tests/inputs/)',
    'unknown': 'Other',
}

mode = '$MODE'
if mode == 'compare':
    print(f'  {\"Test\":<30s} {\"Rust mean\":>12s} {\"Python mean\":>12s} {\"Speedup\":>10s}')
    print(f'  {\"-\"*30} {\"-\"*12} {\"-\"*12} {\"-\"*10}')
    for cat, entries in categories.items():
        title = cat_titles.get(cat, cat)
        print(f'  [{title}]')
        for label, runs in entries.items():
            rs = runs.get('rust', {})
            py = runs.get('python', {})
            rs_ms = rs.get('mean_s', 0) * 1000
            py_ms = py.get('mean_s', 0) * 1000
            if rs_ms > 0 and py_ms > 0:
                speedup = f'{py_ms/rs_ms:.1f}x'
            else:
                speedup = 'N/A'
            print(f'    {label:<28s} {rs_ms:>9.1f}ms  {py_ms:>9.1f}ms  {speedup:>10s}')
        print()
else:
    print(f'  {\"Test\":<30s} {\"Mean\":>10s} {\"StdDev\":>10s} {\"Min ~ Max\":>22s}')
    print(f'  {\"-\"*30} {\"-\"*10} {\"-\"*10} {\"-\"*22}')
    for cat, entries in categories.items():
        title = cat_titles.get(cat, cat)
        print(f'  [{title}]')
        for label, runs in entries.items():
            rs = runs.get('rust', {})
            mean_ms = rs.get('mean_s', 0) * 1000
            std_ms = rs.get('stddev_s', 0) * 1000
            min_ms = rs.get('min_s', 0) * 1000
            max_ms = rs.get('max_s', 0) * 1000
            print(f'    {label:<28s} {mean_ms:>7.1f}ms  +/-{std_ms:>6.1f}ms  {min_ms:>7.1f} ~ {max_ms:>7.1f}ms')
        print()
"

echo ""
echo -e "${BOLD}${CYAN}=== Benchmark Complete ===${NC}"
echo "  Runs per test: $RUNS (warmup: $WARMUP)"
echo "  JSON output:   $JSON_OUT"
echo ""
