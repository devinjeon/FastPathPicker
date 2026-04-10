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
#   ./tests/e2e/run_e2e.sh --suite=NAME       # run specific suite only
#   FPP_BINARY=/path/to/fpp ./tests/e2e/run_e2e.sh --rust-only  # custom binary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source helpers (shared variables, helper functions, prerequisite checks)
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

# === Run Test Suites ===

SUITES_DIR="$SCRIPT_DIR/suites"

if [ -n "${E2E_SUITE:-}" ]; then
    # Run a single suite (supports prefix matching: --suite=01 finds 01_basic_parsing.sh)
    suite_file="$SUITES_DIR/${E2E_SUITE}.sh"
    if [ ! -f "$suite_file" ]; then
        # Try prefix match
        matched=()
        for f in "$SUITES_DIR"/${E2E_SUITE}*.sh; do
            [ -f "$f" ] && matched+=("$f")
        done
        if [ ${#matched[@]} -eq 1 ]; then
            suite_file="${matched[0]}"
        elif [ ${#matched[@]} -gt 1 ]; then
            echo -e "${RED}Ambiguous suite prefix '${E2E_SUITE}', matches:${NC}"
            printf '  %s\n' "${matched[@]##*/}"
            exit 1
        else
            echo -e "${RED}Suite not found: ${E2E_SUITE}${NC}"
            echo "Available suites:"
            ls "$SUITES_DIR"/*.sh 2>/dev/null | xargs -I{} basename {} .sh | sed 's/^/  /'
            exit 1
        fi
    fi
    suite_name=$(basename "$suite_file" .sh)
    echo -e "${CYAN}Running suite: ${suite_name}${NC}"
    # shellcheck source=/dev/null
    source "$suite_file"
else
    # Run all suites in order
    for suite_file in "$SUITES_DIR"/*.sh; do
        suite_name=$(basename "$suite_file" .sh)
        echo -e "${CYAN}--- Suite: ${suite_name} ---${NC}"
        # shellcheck source=/dev/null
        source "$suite_file"
        echo ""
    done
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
