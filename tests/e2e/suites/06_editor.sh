# Suite: 06_editor
# Sourced by run_e2e.sh — do not run directly.

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
echo -e "${CYAN}[COV-26] --all Flag Editor Mode${NC}"

run_test_editor "all_flag_editor_vim" "vim" \
    "src/a.rs:10
src/b.rs:20
src/c.rs" \
    --no-file-checks --all

# ==================================================================
# [COV-27] Multiple $F occurrences in different positions

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


