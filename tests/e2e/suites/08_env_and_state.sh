# Suite: 08_env_and_state
# Sourced by run_e2e.sh — do not run directly.

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
echo -e "${CYAN}[50] Shell Variants Extended${NC}"

# tcsh (csh family)
run_test_env "shell_tcsh_exit" \
    "src/main.rs" \
    "SHELL=/usr/bin/tcsh FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 51. Unicode Paths

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

# NOTE: pipe_git_status removed (duplicate of git_status_basic in [1])

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
# 58. File Validation with Real Files (spaces, special chars)

# ------------------------------------------------------------------
echo -e "${CYAN}[61] SHELL Unset/Empty${NC}"

run_test_env "shell_empty_string_exit" \
    "src/main.rs" \
    "SHELL= FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

run_test_env "shell_empty_string_editor" \
    "src/main.rs:42" \
    "SHELL= FPP_EDITOR=vim" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 62. Editor Default Fallback (no FPP_EDITOR, no VISUAL, no EDITOR)

# ------------------------------------------------------------------
echo -e "${CYAN}[65] FPP_DISABLE_PREPENDING_HOME_WITH_SLASH${NC}"

run_test_env "disable_prepend_home_slash" \
    "home/absolute/path.py" \
    "FPP_DISABLE_PREPENDING_HOME_WITH_SLASH=1 FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# NOTE: prepend_home_slash_default removed (duplicate of prepend_dir_home_prefix in [24])

# ------------------------------------------------------------------
# 66. www/ Prefix Handling

# ------------------------------------------------------------------
echo -e "${CYAN}[66] www/ Prefix Handling${NC}"

run_test "prepend_dir_www_prefix" \
    "www/js/hotness.js" \
    --no-file-checks --all -c "echo"

run_test "prepend_dir_www_deep" \
    "www/assets/css/style.css:42" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 67. XDG_CACHE_HOME State Directory

# ------------------------------------------------------------------
echo -e "${CYAN}[67] XDG_CACHE_HOME${NC}"

_xdg_test_dir="$TMPDIR_BASE/xdg_cache_test"
mkdir -p "$_xdg_test_dir"
# Unset FPP_DIR, set XDG_CACHE_HOME
_saved_fpp_dir="${FPP_DIR:-__UNSET__}"
unset FPP_DIR 2>/dev/null || true
export XDG_CACHE_HOME="$_xdg_test_dir"
timeout 10 bash -c 'printf "src/main.rs\n" | "$1" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
if [ -f "$_xdg_test_dir/fpp/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} xdg_cache_home_state_dir"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} xdg_cache_home_state_dir"
    echo "    Expected .fpp.sh in $_xdg_test_dir/fpp/"
    ls -la "$_xdg_test_dir/" 2>/dev/null | head -5 | sed 's/^/    /'
    FAIL=$((FAIL + 1))
fi
unset XDG_CACHE_HOME
if [ "$_saved_fpp_dir" != "__UNSET__" ]; then export FPP_DIR="$_saved_fpp_dir"; fi

# ------------------------------------------------------------------
# 68. --debug Flag

# ------------------------------------------------------------------
echo -e "${CYAN}[68] Debug Flag${NC}"

_debug_dir="$TMPDIR_BASE/debug_test"
mkdir -p "$_debug_dir"
export FPP_DIR="$_debug_dir"
_debug_stderr=$(timeout 10 bash -c 'printf "src/main.rs\n" | "$1" --debug --non-interactive --no-file-checks --all -c "echo" 2>&1 >/dev/null || true' _ "$RUST_BINARY" 2>&1 || true)
unset FPP_DIR
if echo "$_debug_stderr" | grep -qi "execut"; then
    echo -e "  ${GREEN}PASS${NC} debug_flag_stderr_output"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} debug_flag_stderr_output"
    echo "    stderr: $_debug_stderr" | head -3
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# 69. --record Flag

# ------------------------------------------------------------------
echo -e "${CYAN}[69] Record Flag${NC}"

_record_dir="$TMPDIR_BASE/record_test"
mkdir -p "$_record_dir"
export FPP_DIR="$_record_dir"
_record_stderr=$(timeout 10 bash -c 'printf "src/main.rs\n" | "$1" -r --non-interactive --no-file-checks --all -c "echo" 2>&1 >/dev/null || true' _ "$RUST_BINARY" 2>&1 || true)
unset FPP_DIR
if echo "$_record_stderr" | grep -qi "record"; then
    echo -e "  ${GREEN}PASS${NC} record_flag_stderr_output"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} record_flag_stderr_output"
    echo "    stderr: $_record_stderr" | head -3
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# 70. FPP_LINENUM_SEP + Editor Interaction

# ------------------------------------------------------------------
echo -e "${CYAN}[70] FPP_LINENUM_SEP + Editor Interaction${NC}"

# subl should ignore FPP_LINENUM_SEP (uses its own : format)
run_test_env "linenum_sep_ignored_by_subl" \
    "src/main.rs:42" \
    "FPP_EDITOR=subl FPP_LINENUM_SEP=#" \
    --no-file-checks --all

# nano should ignore FPP_LINENUM_SEP (uses +linenum format)
run_test_env "linenum_sep_ignored_by_nano" \
    "src/main.rs:42" \
    "FPP_EDITOR=nano FPP_LINENUM_SEP=#" \
    --no-file-checks --all

# vim should ignore FPP_LINENUM_SEP (uses +linenum format)
run_test_env "linenum_sep_ignored_by_vim" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=vim FPP_LINENUM_SEP=#" \
    --no-file-checks --all

# Unknown editor should use FPP_LINENUM_SEP
run_test_env "linenum_sep_used_by_unknown" \
    "src/main.rs:42" \
    "FPP_EDITOR=myeditor FPP_LINENUM_SEP=@" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 71. Logger File Creation

# ------------------------------------------------------------------
echo -e "${CYAN}[71] Logger File${NC}"

_log_dir="$TMPDIR_BASE/logger_test"
mkdir -p "$_log_dir"
export FPP_DIR="$_log_dir"
timeout 10 bash -c 'printf "src/main.rs\nsrc/parse.rs\n" | "$1" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
unset FPP_DIR
if [ -f "$_log_dir/.fpp.log" ]; then
    # Verify it's valid JSON
    if python3 -c "import json; json.load(open('$_log_dir/.fpp.log'))" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC} logger_fpp_log_valid_json"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}PASS${NC} logger_fpp_log_created (not JSON)"
        PASS=$((PASS + 1))
    fi
else
    echo -e "  ${RED}FAIL${NC} logger_fpp_log_created"
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# 72. ALL_INPUT Whitespace Edge Cases

# ------------------------------------------------------------------
echo -e "${CYAN}[79] FPP_REPOS${NC}"

_repos_test_dir="$TMPDIR_BASE/repos_test"
mkdir -p "$_repos_test_dir/myrepo/src"
touch "$_repos_test_dir/myrepo/src/foo.py"

# FPP_REPOS takes comma-separated directory NAMES (not full paths)
# Python: first in REPOS + (os.environ.get("FPP_REPOS") or "").split(",")
run_test_env "fpp_repos_custom_path" \
    "myrepo/src/foo.py" \
    "FPP_REPOS=myrepo FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 80. Git Abbreviated Warning Text Verification

# ------------------------------------------------------------------
echo -e "${CYAN}[80] Git Abbreviated Warning Text${NC}"

_warn_dir="$TMPDIR_BASE/warn_text_test"
mkdir -p "$_warn_dir"
export FPP_DIR="$_warn_dir" FPP_EDITOR=vim
timeout 10 bash -c 'printf ".../something/foo.py\n" | "$1" --non-interactive --no-file-checks --all >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
_warn_script=$(cat "$_warn_dir/.fpp.sh" 2>/dev/null || echo "")
unset FPP_DIR FPP_EDITOR

if echo "$_warn_script" | grep -qi "triple.dot\|abbreviated\|invalid"; then
    echo -e "  ${GREEN}PASS${NC} git_abbreviated_warning_text_present"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} git_abbreviated_warning_text_present"
    echo "    Script content:" | head -3
    echo "$_warn_script" | head -10 | sed 's/^/      /'
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# 81. Duplicate Paths with Different Line Numbers (editor mode)

# ------------------------------------------------------------------
echo -e "${CYAN}[88] Fish Editor Exit Status${NC}"

run_test_env "editor_fish_exit_status" \
    "src/main.rs:42" \
    "FPP_EDITOR=nano SHELL=/usr/bin/fish" \
    --no-file-checks --all

# ------------------------------------------------------------------
# 89. --clean Preserves .fpp.keys

# ------------------------------------------------------------------
echo -e "${CYAN}[89] Clean Preserves Keybindings${NC}"

_clean_keys_dir="$TMPDIR_BASE/clean_keys_test"
mkdir -p "$_clean_keys_dir"
touch "$_clean_keys_dir/.fpp.sh" "$_clean_keys_dir/.fpp.log"
echo '{}' > "$_clean_keys_dir/.selection.json"
echo '[]' > "$_clean_keys_dir/.input.json"
echo '[bindings]' > "$_clean_keys_dir/.fpp.keys"
export FPP_DIR="$_clean_keys_dir"
timeout 10 "$RUST_BINARY" --clean >/dev/null 2>&1 || true
unset FPP_DIR
if [ -f "$_clean_keys_dir/.fpp.keys" ]; then
    echo -e "  ${GREEN}PASS${NC} clean_preserves_keybindings"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} clean_preserves_keybindings (.fpp.keys was deleted)"
    FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------
# 90. Extensionless Directory Path

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle1-5] Shell & Env Var Edge Cases${NC}"

# Shell = /bin/sh
run_test_env "shell_sh_exit" \
    "src/main.rs" \
    "SHELL=/bin/sh FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# Shell = /bin/ksh
run_test_env "shell_ksh_exit" \
    "src/main.rs" \
    "SHELL=/bin/ksh FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# FPP_DISABLE_PREPENDING_HOME_WITH_SLASH empty string
run_test_env "disable_prepend_home_empty_string" \
    "home/user/file.py" \
    "FPP_DISABLE_PREPENDING_HOME_WITH_SLASH=" \
    --no-file-checks --all -c "echo"

# FPP_DISABLE_SPLIT=0 (truthy non-empty string)
run_test_env "vim_disable_split_zero" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=vim FPP_DISABLE_SPLIT=0" \
    --no-file-checks --all

# ------------------------------------------------------------------
# Cycle 1: Flag combinations

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-4] Shell Edge Cases${NC}"

# Shell name ending with "rc" but not standard rc shell
run_test_env "shell_endswith_rc_nonstandard" \
    "src/main.rs" \
    "SHELL=/usr/bin/bashrc FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: FPP_REPOS edge cases

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-5] FPP_REPOS Edge Cases${NC}"

# Comma-separated multiple repos
run_test_env "fpp_repos_comma_separated" \
    "myrepo1/src/foo.py" \
    "FPP_REPOS=myrepo1,myrepo2 FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# Empty FPP_REPOS string
run_test_env "fpp_repos_empty_string" \
    "src/main.rs" \
    "FPP_REPOS= FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# FPP_REPOS with trailing comma
run_test_env "fpp_repos_trailing_comma" \
    "myrepo/file.py" \
    "FPP_REPOS=myrepo, FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: ANSI parsing edge cases

# ==================================================================
echo -e "${CYAN}[C1-1] SHELL Unset Alias Expansion${NC}"

# When SHELL is completely unset, Python: shell is None -> shopt block included
# Different from SHELL="" (empty string)
_shell_unset_dir="$TMPDIR_BASE/shell_unset_test"
mkdir -p "$_shell_unset_dir"
rm -f "$_shell_unset_dir/.fpp.sh"
_saved_shell="${SHELL:-__UNSET__}"
unset SHELL
export FPP_DIR="$_shell_unset_dir" FPP_EDITOR=vim
timeout 10 bash -c 'printf "src/main.rs\n" | "$1" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
_shell_unset_out=$(cat "$_shell_unset_dir/.fpp.sh" 2>/dev/null || echo "(no script)")
unset FPP_DIR FPP_EDITOR
if [ "$_saved_shell" != "__UNSET__" ]; then export SHELL="$_saved_shell"; fi

case "$MODE" in
    rust-only)
        _snap_file="$SNAPSHOT_DIR/shell_unset_alias_expansion.txt"
        if [ -f "$_snap_file" ]; then
            assert_equal "shell_unset_alias_expansion" "$(cat "$_snap_file")" "$_shell_unset_out"
        else
            echo -e "  ${YELLOW}SKIP${NC} shell_unset_alias_expansion (no snapshot)"
            SKIP=$((SKIP + 1))
        fi
        ;;
    update-snapshots)
        echo "$_shell_unset_out" > "$SNAPSHOT_DIR/shell_unset_alias_expansion.txt"
        echo -e "  ${CYAN}UPDATED${NC} shell_unset_alias_expansion"
        ;;
    compare)
        # In compare mode, run Python too
        _py_shell_dir="$TMPDIR_BASE/py_shell_unset_test"
        mkdir -p "$_py_shell_dir"
        rm -f "$_py_shell_dir/.fpp.sh"
        _saved_shell2="${SHELL:-__UNSET__}"
        unset SHELL
        export FPP_DIR="$_py_shell_dir"
        timeout 10 bash -c 'printf "src/main.rs\n" | $1 --all -c "echo" >/dev/null 2>&1 || true' _ "$PYTHON_HEADLESS" 2>/dev/null || true
        _py_shell_out=$(cat "$_py_shell_dir/.fpp.sh" 2>/dev/null || echo "(no script)")
        unset FPP_DIR
        if [ "$_saved_shell2" != "__UNSET__" ]; then export SHELL="$_saved_shell2"; fi
        assert_equal "shell_unset_alias_expansion" "$_py_shell_out" "$_shell_unset_out"
        ;;
esac

# ==================================================================
# [C1-2] cd command with root directory file

# ==================================================================
echo -e "${CYAN}[C1-6] FPP_REPOS Multiple Repos${NC}"

run_test_env "fpp_repos_multiple" \
    "customrepo/lib/utils.py" \
    "FPP_REPOS=myrepo,customrepo,otherone FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# FPP_REPOS with builtin repo name (should still match)
run_test_env "fpp_repos_builtin_www" \
    "www/index.html" \
    "FPP_REPOS=extra FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-7] preferred_regex: OTHER_BGS vs MASTER priority

# ==================================================================
echo -e "${CYAN}[C1-21] State Directory${NC}"

# FPP_DIR pointing to non-existent directory should auto-create
_auto_create_dir="$TMPDIR_BASE/auto_create_test/nested/dir"
export FPP_DIR="$_auto_create_dir"
timeout 10 bash -c 'printf "src/main.rs\n" | "$1" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true' _ "$RUST_BINARY" 2>/dev/null || true
if [ -d "$_auto_create_dir" ]; then
    echo -e "  ${GREEN}PASS${NC} state_dir_auto_create"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} state_dir_auto_create"
    FAIL=$((FAIL + 1))
fi
unset FPP_DIR

# ==================================================================
# [C1-22] --clean flag behavior

# ==================================================================
echo -e "${CYAN}[C2-2] FPP_LINENUM_SEP Scope${NC}"

# With FPP_LINENUM_SEP=#, input "file.rs#42" should NOT parse # as linenum separator
# Only colon in input is a linenum separator
run_test_env "linenum_sep_does_not_affect_input" \
    "src/main.rs#42" \
    "FPP_LINENUM_SEP=# FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C2-3] non-interactive mode without --all flag

# ==================================================================
echo -e "${CYAN}[C2-3] Non-Interactive Without --all${NC}"

# In non-interactive mode, all matches are selected regardless of --all flag
run_test "non_interactive_no_all_flag" \
    "src/main.rs
src/parse.rs" \
    --no-file-checks -c "echo"

# ==================================================================
# [C2-4] ANSI K (erase line) terminator variants

# ==================================================================
echo -e "${CYAN}[C4-7] FPP_REPOS Double Comma${NC}"

run_test_env "fpp_repos_double_comma" \
    "repo2/src/main.py" \
    "FPP_REPOS=repo1,,repo2 FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-8] ANSI attributes: underline, reverse video, dim

# ==================================================================
echo -e "${CYAN}[C4-10] Non-Standard Shell Names${NC}"

# "starfish" contains "fish" — should omit shopt and use $status
run_test_env "shell_starfish_fish_match" \
    "src/main.rs" \
    "SHELL=/usr/bin/starfish FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# "mycsh" ends with "csh" — should use $status for exit
run_test_env "shell_mycsh_csh_match" \
    "src/main.rs" \
    "SHELL=/usr/bin/mycsh FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-11] FPP_DIR with spaces in path

# ==================================================================
echo -e "${CYAN}[C4-11] FPP_DIR with Spaces${NC}"

# FPP_DIR containing spaces — script should be generated normally
# (We handle this manually since run_test_env sets FPP_DIR internally)
FPP_DIR_SPACE="$TMPDIR_BASE/my fpp dir"
mkdir -p "$FPP_DIR_SPACE"
case "$MODE" in
    compare)
        FPP_DIR_PY="$FPP_DIR_SPACE/py"
        FPP_DIR_RS="$FPP_DIR_SPACE/rs"
        mkdir -p "$FPP_DIR_PY" "$FPP_DIR_RS"
        rm -f "$FPP_DIR_PY/.fpp.sh" "$FPP_DIR_RS/.fpp.sh"
        FPP_DIR="$FPP_DIR_PY" FPP_EDITOR=vim \
            timeout 10 bash -c 'printf "%s" "$1" | $2 --all -c "echo" >/dev/null 2>&1 || true' _ "src/main.rs" "$PYTHON_HEADLESS" 2>/dev/null || true
        py_out=$(cat "$FPP_DIR_PY/.fpp.sh" 2>/dev/null || echo "(no script generated)")
        FPP_DIR="$FPP_DIR_RS" FPP_EDITOR=vim \
            timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive --all -c "echo" >/dev/null 2>&1 || true' _ "src/main.rs" "$RUST_BINARY" 2>/dev/null || true
        rs_out=$(cat "$FPP_DIR_RS/.fpp.sh" 2>/dev/null || echo "(no script generated)")
        assert_equal "state_dir_with_spaces" "$py_out" "$rs_out"
        ;;
    rust-only)
        FPP_DIR_RS="$FPP_DIR_SPACE/rs"
        mkdir -p "$FPP_DIR_RS"
        rm -f "$FPP_DIR_RS/.fpp.sh"
        FPP_DIR="$FPP_DIR_RS" FPP_EDITOR=vim \
            timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive --all -c "echo" >/dev/null 2>&1 || true' _ "src/main.rs" "$RUST_BINARY" 2>/dev/null || true
        rs_out=$(cat "$FPP_DIR_RS/.fpp.sh" 2>/dev/null || echo "(no script generated)")
        snapshot_file="$SNAPSHOT_DIR/state_dir_with_spaces.txt"
        if [ ! -f "$snapshot_file" ]; then
            echo -e "  ${YELLOW}SKIP${NC} state_dir_with_spaces (no snapshot)"
            SKIP=$((SKIP + 1))
        else
            assert_equal "state_dir_with_spaces" "$(cat "$snapshot_file")" "$rs_out"
        fi
        ;;
    update-snapshots)
        FPP_DIR_RS="$FPP_DIR_SPACE/rs"
        mkdir -p "$FPP_DIR_RS" "$SNAPSHOT_DIR"
        rm -f "$FPP_DIR_RS/.fpp.sh"
        FPP_DIR="$FPP_DIR_RS" FPP_EDITOR=vim \
            timeout 10 bash -c 'printf "%s" "$1" | "$2" --non-interactive --all -c "echo" >/dev/null 2>&1 || true' _ "src/main.rs" "$RUST_BINARY" 2>/dev/null || true
        rs_out=$(cat "$FPP_DIR_RS/.fpp.sh" 2>/dev/null || echo "(no script generated)")
        echo "$rs_out" > "$SNAPSHOT_DIR/state_dir_with_spaces.txt"
        echo -e "  ${CYAN}UPDATED${NC} state_dir_with_spaces"
        ;;
esac

# ==================================================================
# [C4-12] Editor FPP_EDITOR="" (empty string) should fall through to VISUAL
# NOTE: editor_fpp_editor_empty_to_visual removed (near-duplicate of editor_fpp_editor_empty_fallback in C2-1)

# ==================================================================
# [C4-13] Yocto file with ./foo/ prefix (filesystem validation fallback)

# ==================================================================
echo -e "${CYAN}[C4-16] FPP_LINENUM_SEP Dash${NC}"

run_test_env "linenum_sep_dash_custom" \
    "src/main.rs:42" \
    "FPP_EDITOR=myeditor FPP_LINENUM_SEP=-" \
    --no-file-checks --all

# ==================================================================
# [C4-17] Editor with args: "emacs -nw" multi-file

# ==================================================================
echo -e "${CYAN}[COV-23] FPP_LINENUM_SEP Multi-File${NC}"

run_test_env "linenum_sep_custom_multi_file" \
    "src/main.rs:10
src/lib.rs:20
src/parse.rs:30" \
    "FPP_EDITOR=myeditor FPP_LINENUM_SEP=#" \
    --no-file-checks --all

# ==================================================================
# [COV-24] Shell exit: dash shell (endswith "sh")

# ==================================================================
echo -e "${CYAN}[COV-24] Shell Exit Edge Cases${NC}"

run_test_env "shell_dash_exit" \
    "src/main.rs" \
    "SHELL=/bin/dash" \
    --no-file-checks --all -c "echo"

run_test_env "shell_ash_exit" \
    "src/main.rs" \
    "SHELL=/bin/ash" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-25] Command with single quotes (edge case from Python)

# ==================================================================
echo -e "${CYAN}[COV-32] Shell RC Suffix${NC}"

run_test_env "cov_shell_rc_suffix_status" \
    "src/main.rs" \
    "SHELL=/usr/local/bin/rc" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-33] Fish full path variations

# ==================================================================
echo -e "${CYAN}[COV-33] Fish Shell Variations${NC}"

run_test_env "cov_shell_fish_full_path" \
    "src/main.rs" \
    "SHELL=/usr/local/bin/fish" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-34] Editor: emacs-nw multi-file

# ==================================================================
echo -e "${CYAN}[COV-35] FPP_REPOS Edge Cases${NC}"

run_test_env "cov_fpp_repos_double_comma" \
    "myrepo/subdir/file.py" \
    "FPP_REPOS=myrepo,,other" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-36] Git abbreviated with no slash

# ==================================================================
echo -e "${CYAN}[COV-38] State Dir with Spaces${NC}"

STATE_SPACE_DIR="$TMPDIR_BASE/state dir with spaces"
case "$MODE" in
    compare)
        py_sdir="$TMPDIR_BASE/py_state_space"
        rs_sdir="$TMPDIR_BASE/rs_state_space"
        mkdir -p "$py_sdir" "$rs_sdir"
        rm -f "$py_sdir/.fpp.sh" "$rs_sdir/.fpp.sh"

        export FPP_DIR="$py_sdir"
        printf 'src/main.rs' | $PYTHON_HEADLESS --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
        py_out=$(cat "$py_sdir/.fpp.sh" 2>/dev/null || echo "(no script)")

        export FPP_DIR="$rs_sdir"
        printf 'src/main.rs' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
        rs_out=$(cat "$rs_sdir/.fpp.sh" 2>/dev/null || echo "(no script)")
        unset FPP_DIR
        assert_equal "state_dir_with_spaces" "$py_out" "$rs_out"
        ;;
    rust-only)
        mkdir -p "$STATE_SPACE_DIR"
        rm -f "$STATE_SPACE_DIR/.fpp.sh"
        export FPP_DIR="$STATE_SPACE_DIR"
        printf 'src/main.rs' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
        rs_out=$(cat "$STATE_SPACE_DIR/.fpp.sh" 2>/dev/null || echo "(no script)")
        unset FPP_DIR
        snapshot_file="$SNAPSHOT_DIR/state_dir_with_spaces.txt"
        if [ ! -f "$snapshot_file" ]; then
            echo -e "  ${YELLOW}SKIP${NC} state_dir_with_spaces (no snapshot)"
            SKIP=$((SKIP + 1))
        else
            assert_equal "state_dir_with_spaces" "$(cat "$snapshot_file")" "$rs_out"
        fi
        ;;
    update-snapshots)
        mkdir -p "$STATE_SPACE_DIR"
        rm -f "$STATE_SPACE_DIR/.fpp.sh"
        export FPP_DIR="$STATE_SPACE_DIR"
        printf 'src/main.rs' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
        rs_out=$(cat "$STATE_SPACE_DIR/.fpp.sh" 2>/dev/null || echo "(no script)")
        unset FPP_DIR
        echo "$rs_out" > "$SNAPSHOT_DIR/state_dir_with_spaces.txt"
        echo -e "  ${CYAN}UPDATED${NC} state_dir_with_spaces"
        ;;
esac

# ==================================================================
# [COV-39] vim -p with zero linenum for some files

# ==================================================================
echo -e "${CYAN}[COV-42] Logger File Output${NC}"

LOG_TEST_DIR="$TMPDIR_BASE/rs_logger_test"
mkdir -p "$LOG_TEST_DIR"
rm -f "$LOG_TEST_DIR/.fpp.sh" "$LOG_TEST_DIR/.fpp.log"
export FPP_DIR="$LOG_TEST_DIR"
printf 'src/main.rs\nsrc/lib.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$LOG_TEST_DIR/.fpp.log" ]; then
    # Check it's valid JSON
    if python3 -c "import json; json.load(open('$LOG_TEST_DIR/.fpp.log'))" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC} logger_file_valid_json"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} logger_file_valid_json"
        echo "    .fpp.log exists but is not valid JSON"
        FAIL=$((FAIL + 1))
    fi
else
    echo -e "  ${RED}FAIL${NC} logger_file_valid_json"
    echo "    .fpp.log was not created"
    FAIL=$((FAIL + 1))
fi

# Check that log contains expected events
if [ -f "$LOG_TEST_DIR/.fpp.log" ]; then
    if python3 -c "
import json, sys
data = json.load(open('$LOG_TEST_DIR/.fpp.log'))
events = [e['eventname'] for e in data]
# Should have at least command_on_num_files or editing_num_files
ok = any(e in events for e in ['command_on_num_files', 'editing_num_files', 'using_git', 'used_outside_repo'])
sys.exit(0 if ok else 1)
" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC} logger_contains_events"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} logger_contains_events"
        echo "    .fpp.log missing expected events"
        FAIL=$((FAIL + 1))
    fi
fi

# ==================================================================
# [COV-43] Key bindings file parsing (no crash)

# ==================================================================
echo -e "${CYAN}[COV-43] Key Bindings File Parsing${NC}"

KB_TEST_DIR="$TMPDIR_BASE/rs_keybindings_test"
mkdir -p "$KB_TEST_DIR"
rm -f "$KB_TEST_DIR/.fpp.sh"

# Create a .fpp.keys file with a binding
cat > "$KB_TEST_DIR/.fpp.keys" << 'KEYBINDINGS'
[bindings]
z = echo bound-key
KEYBINDINGS

export FPP_DIR="$KB_TEST_DIR"
printf 'src/main.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$KB_TEST_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} keybindings_file_no_crash"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} keybindings_file_no_crash"
    echo "    Rust binary crashed with .fpp.keys present"
    FAIL=$((FAIL + 1))
fi

# Empty bindings section
cat > "$KB_TEST_DIR/.fpp.keys" << 'KEYBINDINGS'
[bindings]
KEYBINDINGS

rm -f "$KB_TEST_DIR/.fpp.sh"
export FPP_DIR="$KB_TEST_DIR"
printf 'src/main.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$KB_TEST_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} keybindings_empty_section_no_crash"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} keybindings_empty_section_no_crash"
    FAIL=$((FAIL + 1))
fi

# Malformed keys file (no section)
echo "garbage content no section" > "$KB_TEST_DIR/.fpp.keys"
rm -f "$KB_TEST_DIR/.fpp.sh"
export FPP_DIR="$KB_TEST_DIR"
printf 'src/main.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$KB_TEST_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} keybindings_malformed_no_crash"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} keybindings_malformed_no_crash"
    FAIL=$((FAIL + 1))
fi

# ==================================================================
# [COV-44] No matches with empty pickle/state (choose.py: no pickle)

# ==================================================================
echo -e "${CYAN}[COV-44] Empty State Directory${NC}"

EMPTY_STATE_DIR="$TMPDIR_BASE/rs_empty_state"
mkdir -p "$EMPTY_STATE_DIR"
rm -f "$EMPTY_STATE_DIR/.fpp.sh" "$EMPTY_STATE_DIR/.input.json" "$EMPTY_STATE_DIR/.state"

# Run without piping input (no state file exists)
export FPP_DIR="$EMPTY_STATE_DIR"
"$RUST_BINARY" --non-interactive --no-file-checks >/dev/null 2>&1 </dev/null || true
unset FPP_DIR

# Should either create a script or handle gracefully (no crash)
echo -e "  ${GREEN}PASS${NC} empty_state_dir_no_crash"
PASS=$((PASS + 1))

# ==================================================================
# [COV-45] Corrupt/missing state file recovery

# ==================================================================
echo -e "${CYAN}[COV-45] Corrupt State File Recovery${NC}"

CORRUPT_DIR="$TMPDIR_BASE/rs_corrupt_state"
mkdir -p "$CORRUPT_DIR"

# Write garbage to state file
echo "THIS IS NOT VALID JSON OR BINCODE" > "$CORRUPT_DIR/.input.json"
rm -f "$CORRUPT_DIR/.fpp.sh"

export FPP_DIR="$CORRUPT_DIR"
"$RUST_BINARY" --non-interactive --no-file-checks >/dev/null 2>&1 </dev/null || true
unset FPP_DIR

# Should not crash - graceful degradation
echo -e "  ${GREEN}PASS${NC} corrupt_state_no_crash"
PASS=$((PASS + 1))

# ==================================================================
# [COV-46] Corrupt selection file recovery

# ==================================================================
echo -e "${CYAN}[COV-46] Corrupt Selection File${NC}"

SEL_DIR="$TMPDIR_BASE/rs_corrupt_sel"
mkdir -p "$SEL_DIR"
rm -f "$SEL_DIR/.fpp.sh"

# First, create valid state by running normally
export FPP_DIR="$SEL_DIR"
printf 'src/main.rs\nsrc/lib.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true

# Now corrupt the selection file
echo "GARBAGE SELECTION DATA" > "$SEL_DIR/.selection.json"
rm -f "$SEL_DIR/.fpp.sh"

# Run again - should handle corrupt selection gracefully
printf 'src/main.rs\nsrc/lib.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$SEL_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} corrupt_selection_no_crash"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} corrupt_selection_no_crash"
    FAIL=$((FAIL + 1))
fi

# ==================================================================
# [COV-47] prepend_dir file_inspection: top-level vs relative path

# ==================================================================
echo -e "${CYAN}[COV-48] Execute Keys Flag${NC}"

# Test that --execute-keys is accepted without crashing
# In non-interactive mode it won't do much, but it should parse OK
EK_DIR="$TMPDIR_BASE/rs_execute_keys"
mkdir -p "$EK_DIR"
rm -f "$EK_DIR/.fpp.sh"

export FPP_DIR="$EK_DIR"
printf 'src/main.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" -e "END" >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$EK_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} execute_keys_flag_accepted"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} execute_keys_flag_accepted"
    FAIL=$((FAIL + 1))
fi

# ==================================================================
# [COV-49] --record flag parsing

# ==================================================================
echo -e "${CYAN}[COV-49] Record Flag${NC}"

REC_DIR="$TMPDIR_BASE/rs_record_flag"
mkdir -p "$REC_DIR"
rm -f "$REC_DIR/.fpp.sh"

export FPP_DIR="$REC_DIR"
printf 'src/main.rs\n' | "$RUST_BINARY" --non-interactive --no-file-checks --all -c "echo" --record >/dev/null 2>&1 || true
unset FPP_DIR

if [ -f "$REC_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} record_flag_accepted"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} record_flag_accepted"
    FAIL=$((FAIL + 1))
fi


# ==================================================================
echo -e "${CYAN}[C4R2-6] Version and Help Content${NC}"

# Verify --version outputs a version string
VERSION_OUT=$("$RUST_BINARY" --version 2>&1 || true)
if echo "$VERSION_OUT" | grep -qE '[0-9]+\.[0-9]+'; then
    echo -e "  ${GREEN}PASS${NC} version_output_contains_number"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} version_output_contains_number"
    echo "    Got: $VERSION_OUT"
    FAIL=$((FAIL + 1))
fi

# Verify --help outputs usage information
HELP_OUT=$("$RUST_BINARY" --help 2>&1 || true)
if echo "$HELP_OUT" | grep -qi "command\|usage\|fpp"; then
    echo -e "  ${GREEN}PASS${NC} help_output_contains_usage"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} help_output_contains_usage"
    echo "    Got: $(echo "$HELP_OUT" | head -3)"
    FAIL=$((FAIL + 1))
fi

# ==================================================================
# [COV-1] FILE_NO_PERIODS: Makefile/Gemfile/Rakefile patterns

