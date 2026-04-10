# helpers.sh — Shared variables, helper functions, and prerequisite checks
# for the e2e test runner. Sourced by run_e2e.sh before suite files.
#
# Shared variables exported:
#   SCRIPT_DIR, PROJECT_ROOT, INPUTS_DIR, SNAPSHOT_DIR, TMPDIR_BASE
#   RED, GREEN, YELLOW, CYAN, NC (color codes)
#   PASS, FAIL, SKIP (counters)
#   RUST_BINARY, PYTHON_HEADLESS, MODE
#
# Helper functions:
#   run_rust, run_python, run_rust_file, run_python_file
#   normalize_output, assert_equal
#   run_test, run_test_file, run_test_editor, run_test_env

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
        --suite=*) E2E_SUITE="${arg#--suite=}" ;;
        --help)
            echo "Usage: $0 [--rust-only|--update-snapshots|--suite=NAME]"
            echo ""
            echo "Modes:"
            echo "  (default)           Compare Python fpp vs Rust fpp"
            echo "  --rust-only         Run Rust binary only, compare against snapshots"
            echo "  --update-snapshots  Update snapshot files from current Rust binary output"
            echo ""
            echo "Options:"
            echo "  --suite=NAME        Run only the named suite (e.g. --suite=01_basic_parsing)"
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
