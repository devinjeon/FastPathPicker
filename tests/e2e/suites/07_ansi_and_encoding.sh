# Suite: 07_ansi_and_encoding
# Sourced by run_e2e.sh — do not run directly.

# ------------------------------------------------------------------
echo -e "${CYAN}[16] ANSI Color Input${NC}"

run_test "ansi_git_status" \
    $'\033[32m M src/main.rs\033[0m
\033[31m M src/parse.rs\033[0m' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 17. Editor Variants (expanded)

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
echo -e "${CYAN}[C4-15] ANSI Multi-Attribute${NC}"

# Bold + underline + color combined
run_test "ansi_bold_underline_color" \
    "$(printf '\033[1;4;33msrc/main.rs\033[0m:42')" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-16] FPP_LINENUM_SEP with dash separator

# ==================================================================
echo -e "${CYAN}[C4-29] ANSI Incomplete at EOL${NC}"

run_test "ansi_incomplete_no_terminator" \
    "$(printf '\033[31msrc/main.rs')" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-30] Editor: vi (not vim) multi-file

