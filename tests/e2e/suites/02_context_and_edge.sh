# Suite: 02_context_and_edge
# Sourced by run_e2e.sh — do not run directly.

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

# ==================================================================
echo -e "${CYAN}[C2-6] Bare CR Handling${NC}"

# Python readlines() only splits on \n, not \r
# So "file1.rs\rfile2.rs" is ONE line, not two
run_test "bare_cr_single_line" \
    "$(printf 'src/main.rs\rsrc/parse.rs')" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C2-7] cd command with tab after "cd"

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

