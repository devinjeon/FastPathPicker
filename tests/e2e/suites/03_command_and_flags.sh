# Suite: 03_command_and_flags
# Sourced by run_e2e.sh — do not run directly.

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

# NOTE: alias_fish_no_shopt removed (duplicate of shell_fish_exit in [22])
# NOTE: alias_bash_has_shopt removed (duplicate of shell_bash_exit in [22])

# ------------------------------------------------------------------
# 24. Path Resolution (prepend_dir)

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
echo -e "${CYAN}[64] cd Path Normalization${NC}"

# dotdot normalization
run_test "cd_dotdot_normalization" \
    "/usr/local/bin/../lib/test.rs" \
    --no-file-checks --all -c "cd"

# dot normalization
run_test "cd_dot_normalization" \
    "./src/./main.rs" \
    --no-file-checks --all -c "cd"

# tilde in cd command
run_test "cd_tilde_expansion" \
    "~/projects/foo/bar.rs" \
    --no-file-checks --all -c "cd"

# ------------------------------------------------------------------
# 65. FPP_DISABLE_PREPENDING_HOME_WITH_SLASH

# ------------------------------------------------------------------
echo -e "${CYAN}[77] Command Double Quotes + \$F${NC}"

run_test "command_grep_pattern_dollar_f" \
    "src/main.rs" \
    --no-file-checks --all -c 'grep "pattern" $F'

run_test "command_awk_dollar_f" \
    "data.csv
report.csv" \
    --no-file-checks --all -c 'awk -F"," "{print}" $F'

# ------------------------------------------------------------------
# 78. CRLF Trailing CR Verification

# ------------------------------------------------------------------
echo -e "${CYAN}[83] cd Double Quote Path${NC}"

run_test "cd_path_with_double_quote" \
    'src/my"file.rs' \
    --no-file-checks --all -c "cd"

# ------------------------------------------------------------------
# 84. Command with Double Quotes, No $F (multi-file)

# ------------------------------------------------------------------
echo -e "${CYAN}[84] Command Double Quotes No \$F${NC}"

run_test "command_double_quotes_no_dollar_f" \
    "src/main.rs
src/parse.rs" \
    --no-file-checks --all -c 'sed -i "s/old/new/g"'

# ------------------------------------------------------------------
# 85. FPP_LINENUM_SEP + Mixed Linenum (unknown editor)

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle1-3] Command Mode Edge Cases${NC}"

# Command with backtick
run_test "command_with_backtick" \
    "file1.txt
file2.txt" \
    --no-file-checks --all -c 'echo `date`'

# Command with $HOME (non-$F dollar var preserved)
run_test "command_preserve_dollar_var" \
    "file1.txt" \
    --no-file-checks --all -c 'echo $HOME'

# Single quote in path, command mode without $F
run_test "single_quote_path_no_dollar_f" \
    "it's_a_file.txt" \
    --no-file-checks --all -c "git add"

# Empty command string
run_test_env "command_empty_string" \
    "src/main.rs:42" \
    "FPP_EDITOR=vim" \
    --no-file-checks --all -c ""

# cd command with no matches
run_test "cd_no_matches" \
    "no file paths here at all" \
    --no-file-checks -c "cd"

# $F with single-quote path
run_test "dollar_f_single_quote_combined" \
    "it's_a_test.txt
file2.txt" \
    --no-file-checks --all -c 'echo $F && ls $F'

# ------------------------------------------------------------------
# Cycle 1: Editor edge cases

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle1-8] Output Escaping${NC}"

# Double quote in cd directory path
run_test "cd_dir_with_double_quote" \
    'src/my"dir/file.rs' \
    --no-file-checks --all -c "cd"

# Command with backslash
run_test "command_with_backslash" \
    "src/main.rs" \
    --no-file-checks --all -c 'echo hello\\world'

# ------------------------------------------------------------------
# Cycle 2: File validation with real files (MASTER_REGEX_WITH_SPACES)

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-3] Command Mode Edge Cases${NC}"

# "cde" should NOT be treated as "cd" command
run_test "cd_command_false_positive" \
    "src/main.rs" \
    --no-file-checks --all -c "cde"

# Unicode in command string
run_test "command_with_unicode" \
    "src/main.rs" \
    --no-file-checks --all -c "echo 한글"

# Mixed resolvable + unresolvable (git abbreviated warning)
run_test "warn_git_abbreviated_mixed" \
    "src/main.rs:42
.../abbreviated/path.py" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: Shell edge cases

# ==================================================================
echo -e "${CYAN}[C1-2] cd Command Edge Cases${NC}"

# /file.txt -> dirname is "/" (root dir)
run_test "cd_root_dir_file" \
    "/file.txt" \
    --no-file-checks --all -c "cd"

# cd with relative path containing ../
run_test "cd_dotdot_relative" \
    "../other/main.rs" \
    --no-file-checks --all -c "cd"

# NOTE: cd_bare_filename removed (duplicate of command_cd_bare_file in [21])

# ==================================================================
# [C1-3] --all flag unique path dedup behavior

# ==================================================================
echo -e "${CYAN}[C1-4] CLI Help and Version${NC}"

# --version should exit 0
_version_exit=0
timeout 5 "$RUST_BINARY" --version >/dev/null 2>&1 || _version_exit=$?
if [ $_version_exit -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} version_flag_exit_zero"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} version_flag_exit_zero (exit=$_version_exit)"
    FAIL=$((FAIL + 1))
fi

# --help should exit 0
_help_exit=0
timeout 5 "$RUST_BINARY" --help >/dev/null 2>&1 || _help_exit=$?
if [ $_help_exit -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} help_flag_exit_zero"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} help_flag_exit_zero (exit=$_help_exit)"
    FAIL=$((FAIL + 1))
fi

# ==================================================================
# [C1-5] Editor with relative path containing ../

# ==================================================================
echo -e "${CYAN}[C1-14] Command Generation Edge Cases${NC}"

# NOTE: command_empty_string, command_with_pipe, command_with_semicolons,
# command_with_double_quotes, command_with_backtick, command_preserve_dollar_var
# already exist in earlier sections.

# Command with single quotes in it
run_test "command_with_single_quotes_echo" \
    "src/main.rs" \
    --no-file-checks --all -c "echo 'hello world'"

# ==================================================================
# [C1-15] Multiple files in editor with various editors

# ==================================================================
echo -e "${CYAN}[C1-22] --clean Flag${NC}"

# --clean should delete state files before processing
_clean_dir="$TMPDIR_BASE/clean_test"
mkdir -p "$_clean_dir"
echo "old content" > "$_clean_dir/.fpp.sh"
echo "old state" > "$_clean_dir/.input.json"
export FPP_DIR="$_clean_dir"
timeout 10 bash -c 'printf "src/main.rs\n" | "$1" --non-interactive --no-file-checks --all --clean -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
_clean_script=$(cat "$_clean_dir/.fpp.sh" 2>/dev/null || echo "(no script)")
unset FPP_DIR
# Verify old content was replaced
if echo "$_clean_script" | grep -q "old content"; then
    echo -e "  ${RED}FAIL${NC} clean_flag_removes_old_state"
    FAIL=$((FAIL + 1))
else
    echo -e "  ${GREEN}PASS${NC} clean_flag_removes_old_state"
    PASS=$((PASS + 1))
fi

# ==================================================================
# [C1-23] $F token in various positions in command

# ==================================================================
echo -e "${CYAN}[C1-23] \$F Token Positions${NC}"

# $F at the very end
run_test "dollar_f_at_end" \
    "src/main.rs
src/parse.rs" \
    --no-file-checks --all -c 'git add $F'

# $F with surrounding text
run_test "dollar_f_surrounded" \
    "src/main.rs" \
    --no-file-checks --all -c 'echo before $F after'

# No $F - files appended at end
run_test "no_dollar_f_append_multi" \
    "src/main.rs
src/parse.rs
src/lib.rs" \
    --no-file-checks --all -c "wc -l"

# ==================================================================
# [C1-24] NOTE: crlf_path_parsing and mixed_line_endings removed
# (duplicates of crlf_line_endings and mixed_line_endings in [43])
# ==================================================================

# ==================================================================
# [C1-25] Edge case: very long line with path buried in it

# ==================================================================
echo -e "${CYAN}[C4-5] cd with Space Directory${NC}"

run_test "cd_space_dir_path" \
    "src/my dir/file.rs" \
    --no-file-checks --all -c "cd"

# ==================================================================
# [C4-6] cd with consecutive dotdot normalization

# ==================================================================
echo -e "${CYAN}[C4-6] cd Double Dotdot${NC}"

run_test "cd_double_dotdot" \
    "/a/b/../../c/file.rs" \
    --no-file-checks --all -c "cd"

# ==================================================================
# [C4-7] FPP_REPOS with double comma (empty element)

# ==================================================================
echo -e "${CYAN}[C4-9] \$F Triple Occurrence${NC}"

run_test "dollar_f_triple" \
    "a.txt
b.txt" \
    --no-file-checks --all -c 'echo $F && wc $F && ls $F'

# ==================================================================
# [C4-10] Non-standard shell names (fish/csh substring matching)

# ==================================================================
echo -e "${CYAN}[C4-26] \$F Start of Command${NC}"

run_test "dollar_f_at_start" \
    "src/main.rs" \
    --no-file-checks --all -c '$F --version'

# ==================================================================
# [C4-27] Path with backslash in filename

# ==================================================================
echo -e "${CYAN}[COV-19] cd Command Absolute Dir${NC}"

run_test "cd_absolute_dir_file" \
    "/usr/local/bin/test.rs" \
    --no-file-checks --all -c "cd"

# ==================================================================
# [COV-20] Linenum dash format (file.py-22)

# ==================================================================
echo -e "${CYAN}[COV-25] Command Single Quotes${NC}"

run_test "command_with_single_quotes" \
    "src/main.rs" \
    --no-file-checks --all -c "grep 'pattern'"

# ==================================================================
# [COV-26] --all flag with no command (editor mode)

# ==================================================================
echo -e "${CYAN}[COV-27] Multiple \$F in Command${NC}"

run_test "dollar_f_two_occurrences" \
    "src/main.rs
src/lib.rs" \
    --no-file-checks --all -c 'diff $F $F'

# ==================================================================
# [COV-28] cd with file that has no directory (bare filename)

# ==================================================================
echo -e "${CYAN}[COV-28] cd Bare Filename Edge Cases${NC}"

run_test "cd_bare_filename" \
    "README.md" \
    --no-file-checks --all -c "cd"

# ==================================================================
# [COV-29] CRLF in path matching

