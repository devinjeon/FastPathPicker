# Suite: 04_all_input
# Sourced by run_e2e.sh — do not run directly.

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
echo -e "${CYAN}[COV-31] Non-Interactive Hovered${NC}"

run_test "cov_non_interactive_no_all" \
    "src/main.rs:42
src/lib.rs:10" \
    --no-file-checks

# ==================================================================
# [COV-32] Shell rc suffix (non-standard)

