# Suite: 09_path_resolution
# Sourced by run_e2e.sh — do not run directly.

# ------------------------------------------------------------------
echo -e "${CYAN}[24] Path Resolution${NC}"

# a/ and b/ git diff prefix stripping
run_test "prepend_dir_git_a_prefix" \
    "a/foo/bar/baz/asd.py" \
    --no-file-checks --all -c "echo"

run_test "prepend_dir_git_b_prefix" \
    "b/foo/bar/baz/asd.py" \
    --no-file-checks --all -c "echo"

# home/ -> /home/ conversion
run_test "prepend_dir_home_prefix" \
    "home/absolute/path.py" \
    --no-file-checks --all -c "echo"

# ./relative and ../relative paths
run_test "prepend_dir_relative_dot" \
    "./src/main.rs:42" \
    --no-file-checks --all -c "echo"

run_test "prepend_dir_relative_dotdot" \
    "../other/src/main.rs:10" \
    --no-file-checks --all -c "echo"

# Simple filename (no directory)
run_test "prepend_dir_no_dir" \
    "somefile.txt" \
    --no-file-checks --all -c "echo"

# Tilde path expansion
run_test "prepend_dir_tilde" \
    "~/src/project/main.rs:42" \
    --no-file-checks --all -c "echo"

# Git abbreviated path (unresolvable)
run_test "prepend_dir_git_abbreviated" \
    ".../deep/nested/foo.py" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 25. ANSI Color Extended

# ------------------------------------------------------------------
echo -e "${CYAN}[27] File Validation${NC}"

# Nonexistent file with --no-file-checks should match
run_test "file_validation_nfc_nonexistent" \
    "nonexistent/deep/fake_file.rs" \
    --no-file-checks --all -c "echo"

# Nonexistent file without --no-file-checks may not match
run_test "file_validation_default_nonexistent" \
    "nonexistent/deep/fake_file.rs" \
    --all -c "echo"

# --all-input disables file checks implicitly
run_test "file_validation_all_input_bypass" \
    "nonexistent/path/line.txt" \
    --all-input --all -c "echo"

# ------------------------------------------------------------------
# 28. Special File Patterns

# ------------------------------------------------------------------
echo -e "${CYAN}[30] Path Escaping${NC}"

# Single quote in filename
run_test "escape_single_quote" \
    "it's_a_file.txt" \
    --no-file-checks --all -c "echo"

# Dollar sign in filename
run_test "escape_dollar_sign" \
    'price$100.txt' \
    --no-file-checks --all -c "echo"

# Paths with @ and + signs
run_test "escape_at_plus" \
    "NSArray+Utils.h
assets/retina/victory@2x.png" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 31. CLI Flag Combinations

# ------------------------------------------------------------------
echo -e "${CYAN}[35] Unresolvable File Warnings${NC}"

# Git abbreviated with editor mode (should produce warning)
run_test_editor "warn_git_abbreviated_editor" "vim" \
    ".../something/foo.py
.../expected/selectFirst.txt" \
    --no-file-checks --all

# Git abbreviated with command mode
run_test "warn_git_abbreviated_command" \
    ".../expected/selectFirst.txt" \
    --no-file-checks --all -c "cat"

# ------------------------------------------------------------------
# 36. No Matches Output Verification

# ------------------------------------------------------------------
echo -e "${CYAN}[36] No Matches Output${NC}"

run_test "no_matches_command_mode" \
    "this is just plain text" \
    -c "echo"

run_test "no_matches_editor_mode" \
    "this is just plain text" \
    --no-file-checks

run_test "empty_input_editor" \
    "" \
    --no-file-checks

# ------------------------------------------------------------------
# 37. Whitespace Edge Cases

# ------------------------------------------------------------------
echo -e "${CYAN}[41] Duplicate Files${NC}"

# Same file mentioned multiple times: should appear once in output
run_test "duplicate_file_paths" \
    "src/main.rs:10
src/main.rs:20
src/main.rs:30" \
    --no-file-checks --all -c "echo"

# Different lines with same resolved path
run_test "duplicate_resolved_paths" \
    "./src/main.rs
src/main.rs" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 42. Input from original PathPicker test patterns (Python test_parsing.py)

# ------------------------------------------------------------------
echo -e "${CYAN}[55] Path Escaping Extended${NC}"

# Backslash in path
run_test "escape_backslash" \
    'path/with\\backslash/file.txt' \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 56. Cache File Creation

# ------------------------------------------------------------------
echo -e "${CYAN}[58] File Validation with Real Files${NC}"

# These tests use actual files from PathPicker/src/tests/inputs/
# to verify MASTER_REGEX_WITH_SPACES and similar file-inspection regexes
TESTS_INPUTS_DIR="$PROJECT_ROOT/tests/inputs"

if [ -d "$TESTS_INPUTS_DIR" ]; then
    # Evil file with space (MASTER_REGEX_WITH_SPACES)
    run_test "validate_evil_file_with_space" \
        "M     $TESTS_INPUTS_DIR/evilFile With Space.txt" \
        --all -c "echo"

    # Evil file no prepend (JUST_FILE_WITH_SPACES)
    (cd "$TESTS_INPUTS_DIR" && \
    run_test "validate_evil_file_no_prepend" \
        "evilFile No Prepend.txt" \
        --all -c "echo")

    # Annoying spaces folder
    run_test "validate_annoying_spaces_folder" \
        "$TESTS_INPUTS_DIR/annoying Spaces Folder" \
        --all -c "echo"

    # NSArray+Utils.h (+ in filename)
    run_test "validate_nsarray_plus_file" \
        "$TESTS_INPUTS_DIR/NSArray+Utils.h" \
        --all -c "echo"

    # sublime-workspace extension (MASTER_REGEX_MORE_EXTENSIONS)
    run_test "validate_sublime_workspace" \
        "$TESTS_INPUTS_DIR/blogredesign.sublime-workspace" \
        --all -c "echo"

    # Yocto percent file
    (cd "$TESTS_INPUTS_DIR" && \
    run_test "validate_yocto_percent_file" \
        "file-from-yocto_%.bbappend" \
        --all -c "echo")

    # Tilde extension file
    run_test "validate_tilde_extension" \
        "$TESTS_INPUTS_DIR/annoyingTildeExtension.txt~" \
        --all -c "echo"

    # svo with parens and comma
    run_test "validate_svo_parens_comma" \
        "$TESTS_INPUTS_DIR/svo (install the zip, not me).xml" \
        --all -c "echo"

    # svo with parens no comma
    run_test "validate_svo_parens_no_comma" \
        "$TESTS_INPUTS_DIR/svo (install the zip not me).xml" \
        --all -c "echo"

    # Hyphen dir with system-bundle extension
    if [ -d "$TESTS_INPUTS_DIR/annoying-hyphen-dir" ]; then
        run_test "validate_hyphen_dir_bundle" \
            "$TESTS_INPUTS_DIR/annoying-hyphen-dir" \
            --all -c "echo"
    fi
else
    echo -e "  ${YELLOW}SKIP${NC} tests/inputs/ directory not found"
fi

# ------------------------------------------------------------------
# 59. Editor with Args in Name

# ------------------------------------------------------------------
echo -e "${CYAN}[91] Space Files + Linenum Validation${NC}"

if [ -d "$TESTS_INPUTS_DIR" ]; then
    # Evil file with space + line number
    run_test "validate_evil_file_space_linenum" \
        "$TESTS_INPUTS_DIR/evilFile With Space.txt:22" \
        --all -c "echo"

    # svo without parens, with comma
    run_test "validate_svo_no_parens_comma" \
        "$TESTS_INPUTS_DIR/svo install the zip, not me.xml" \
        --all -c "echo"

    # svo without parens, without comma
    run_test "validate_svo_no_parens_no_comma" \
        "$TESTS_INPUTS_DIR/svo install the zip not me.xml" \
        --all -c "echo"
else
    echo -e "  ${YELLOW}SKIP${NC} tests/inputs/ directory not found"
fi

# ------------------------------------------------------------------
# 92. Real-World Tool Outputs (Cycle 3)

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle1-7] Dedup & Path Resolution${NC}"

# Same path different line numbers in command mode
run_test "dedup_same_path_diff_linenum_cmd" \
    "src/main.rs:10
src/main.rs:20
src/main.rs:30" \
    --no-file-checks --all -c "wc -l"

# Same path different line numbers in editor mode
run_test_editor "dedup_same_path_diff_linenum_editor" \
    "vim" \
    "src/main.rs:10
src/main.rs:20
src/main.rs:30" \
    --no-file-checks --all

# builtin REPOS: fbcode path
run_test "builtin_repos_fbcode" \
    "fbcode/something/test.py:10" \
    --no-file-checks --all -c "echo"

# builtin REPOS: configerator path
run_test "builtin_repos_configerator" \
    "configerator/config/test.py" \
    --no-file-checks --all -c "echo"

# builtin REPOS: configerator-dsi (hyphen in repo name)
run_test "builtin_repos_configerator_dsi" \
    "configerator-dsi/data/config.yaml" \
    --no-file-checks --all -c "echo"

# www prefix with editor mode (subl)
run_test_env "www_prefix_editor_subl" \
    "www/js/hotness.js:42" \
    "FPP_EDITOR=subl" \
    --no-file-checks --all

# prepend_dir with home tilde path
run_test "prepend_dir_home_tilde" \
    "~/www/asd.py" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 1: Output escaping edge cases

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-1] File Validation - Space Paths${NC}"

# annoying Spaces Folder/evilFile With Space2.txt:42
(cd "$INPUTS_DIR" && run_test "validate_spaces_folder_file_linenum" \
    "./annoying Spaces Folder/evilFile With Space2.txt:42" \
    --all -c "echo")

# Leading space before space-file path
(cd "$INPUTS_DIR" && run_test "validate_leading_space_spaces_folder" \
    " ./annoying Spaces Folder/evilFile With Space2.txt:42" \
    --all -c "echo")

# Git-style prefix with space-file path
(cd "$INPUTS_DIR" && run_test "validate_git_prefix_spaces_folder" \
    "M     ./annoying Spaces Folder/evilFile With Space2.txt:42" \
    --all -c "echo")

# hyphen-dir Package Control.system-bundle (no linenum)
(cd "$INPUTS_DIR" && run_test "validate_hyphen_dir_bundle_file" \
    "./annoying-hyphen-dir/Package Control.system-bundle" \
    --all -c "echo")

# hyphen-dir Package Control.system-bundle:42
(cd "$INPUTS_DIR" && run_test "validate_hyphen_dir_bundle_linenum" \
    "./annoying-hyphen-dir/Package Control.system-bundle:42" \
    --all -c "echo")

# .DS_KINDA_STORE hidden dotfile (FILE_NO_PERIODS with validation)
(cd "$INPUTS_DIR" && run_test "validate_ds_kinda_store" \
    ".DS_KINDA_STORE" \
    --all -c "echo")

# .DS_KINDA_STORE with ./ prefix
(cd "$INPUTS_DIR" && run_test "validate_ds_kinda_store_dotslash" \
    "./.DS_KINDA_STORE" \
    --all -c "echo")

# sublime-workspace without ./ prefix, no linenum
(cd "$INPUTS_DIR" && run_test "validate_sublime_workspace_no_dotslash" \
    "blogredesign.sublime-workspace" \
    --all -c "echo")

# sublime-workspace without ./ prefix, with linenum
(cd "$INPUTS_DIR" && run_test "validate_sublime_workspace_linenum" \
    "blogredesign.sublime-workspace:42" \
    --all -c "echo")

# ------------------------------------------------------------------
# Cycle 2: Regex priority and preferred_regex

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-2] Regex Priority${NC}"

# MASTER_REGEX wins when it matches before OTHER_BGS
run_test "preferred_regex_master_wins" \
    "src/path/file.py:42 foo/bar/TARGETS:10" \
    --no-file-checks --all -c "echo"

# Non-first-component ... is resolvable (no warning)
run_test "non_first_component_dots_resolvable" \
    "src/.../nested/foo.py" \
    --no-file-checks --all -c "echo"

# OTHER_BGS min filename length (2 chars = below 3 minimum)
run_test "other_bgs_min_filename_length" \
    "foo/bar/ab:42" \
    --no-file-checks --all -c "echo"

# Contiguous spaces rejected by MASTER_REGEX_WITH_SPACES
run_test "spaces_regex_reject_contiguous" \
    "./path/two  spaces/file.txt" \
    --no-file-checks --all -c "echo"

# One match per line (first wins, multi-path lines)
run_test "one_match_per_line" \
    "src/a.py:1 src/b.py:2
src/c.py:3 src/d.py:4
src/e.py:5" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: Command mode edge cases

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-10] Git Abbreviated Bypass${NC}"

# .../path bypasses file validation (no --no-file-checks needed)
run_test "validate_git_abbreviated_bypass" \
    ".../something/foo.py" \
    --all -c "echo"

# ------------------------------------------------------------------
# Cycle 3: Final file validation edge cases

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle3-1] File Validation Edge Cases${NC}"

# Space folder file WITHOUT linenum (validate_file_exists=true)
(cd "$INPUTS_DIR" && run_test "validate_spaces_folder_file_no_linenum" \
    "./annoying Spaces Folder/evilFile With Space2.txt" \
    --all -c "echo")

# hyphen-dir Package Control WITHOUT ./ prefix (validate=true)
(cd "$INPUTS_DIR" && run_test "validate_hyphen_dir_no_dotslash" \
    "annoying-hyphen-dir/Package Control.system-bundle" \
    --all -c "echo")

# Tilde extension with linenum (validate_file_exists=true)
(cd "$INPUTS_DIR" && run_test "validate_tilde_ext_linenum" \
    "./annoyingTildeExtension.txt~:42" \
    --all -c "echo")

# .DS_KINDA_STORE from parent dir (inputs/ prefix in path)
(cd "$INPUTS_DIR/.." && run_test "validate_ds_kinda_store_from_parent" \
    "inputs/.DS_KINDA_STORE" \
    --all -c "echo")

# Yocto % file with ./ prefix (validate=true, working_dir=inputs)
(cd "$INPUTS_DIR" && run_test "validate_yocto_dotslash" \
    "./file-from-yocto_3.1%.bbappend" \
    --all -c "echo")

# ------------------------------------------------------------------
# Cycle 3: Regex skip logic (only_with_file_inspection)

# ==================================================================
echo -e "${CYAN}[C1-3] --all Flag Unique Path Dedup${NC}"

# Same file with different line numbers - --all should select unique paths
run_test "all_flag_dedup_same_file" \
    "src/main.rs:10
src/main.rs:20
src/main.rs:30
src/parse.rs:5
src/parse.rs:15" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-4] --version and --help output

# ==================================================================
echo -e "${CYAN}[C1-12] prepend_dir Edge Cases${NC}"

# Absolute path (starts with /) -> no prepend
run_test "prepend_absolute_unchanged" \
    "/usr/local/bin/test.sh" \
    --no-file-checks --all -c "echo"

# Path starting with tilde -> preserved as-is
run_test "prepend_tilde_preserved" \
    "~/Documents/file.txt" \
    --no-file-checks --all -c "echo"

# Double-dot relative path
run_test "prepend_dotdot_path" \
    "../../deep/nested/file.py" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-13] ANSI edge cases

# ==================================================================
echo -e "${CYAN}[C1-20] Special Characters in Paths${NC}"

# Path with @ symbol
run_test "path_with_at_symbol" \
    "src/@types/index.ts" \
    --no-file-checks --all -c "echo"

# Path with + symbol
run_test "path_with_plus_symbol" \
    "src/c++/main.cpp" \
    --no-file-checks --all -c "echo"

# Path with hash in directory
run_test "path_with_hash_dir" \
    "src/#temp#/file.rs" \
    --no-file-checks --all -c "echo"

# Path with parentheses
run_test "path_with_parens" \
    "src/utils(old)/helper.py" \
    --no-file-checks --all -c "echo"

# Path with equals sign
run_test "path_with_equals" \
    "src/config=prod/settings.json" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-21] State directory auto-creation

# ==================================================================
echo -e "${CYAN}[C2-7] cd Command Edge Cases${NC}"

# "cd\t" should NOT be treated as cd command (Python: command[0:3] in ["cd ", "cd"])
run_test "cd_with_tab_not_cd" \
    "src/main.rs" \
    --no-file-checks --all -c "$(printf 'cd\t')"

# ==================================================================
# [C2-8] Multiple regex match with file validation fallback

# ==================================================================
echo -e "${CYAN}[C2-8] File Validation Regex Fallback${NC}"

# When validate_file_exists=True and first regex match doesn't exist,
# should fall back to next regex match that does exist
(cd "$INPUTS_DIR" && run_test "validate_fallback_to_existing" \
    "nonexistent.sublime-workspace annoying-hyphen-dir/Package Control.system-bundle" \
    --all -c "echo")

# ------------------------------------------------------------------
# Cycle 3: Minor Edge Cases (from final review)
# ------------------------------------------------------------------

# ==================================================================
# [C3-1] is_git_abbreviated_path: "...file.py" (no slash) vs ".../file.py"

# ==================================================================
echo -e "${CYAN}[C3-1] Git Abbreviated Path Edge Cases${NC}"

# "...file.py" without slash - Python: parts[0]="...file.py" != "...", NOT abbreviated
# Rust should match Python behavior
run_test "git_abbreviated_no_slash" \
    "...file.py" \
    --no-file-checks --all -c "echo"

# ".../dir/file.py" - standard abbreviated, should be treated as abbreviated
run_test "git_abbreviated_with_subdir" \
    ".../deeply/nested/dir/file.py" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C3-2] File validation with prefix text before path

# ==================================================================
echo -e "${CYAN}[C3-2] Prefix Text with File Validation${NC}"

# Yocto file with "other thing" prefix text (matches Python test_parsing.py test)
(cd "$INPUTS_DIR" && run_test "validate_yocto_with_prefix" \
    "other thing ./file-from-yocto_3.1%.bbappend" \
    --all -c "echo")

# ==================================================================
# [C3-3] sublime-workspace with inputs/ directory prefix

# ==================================================================
echo -e "${CYAN}[C3-3] Sublime Workspace with Directory Prefix${NC}"

(cd "$INPUTS_DIR/.." && run_test "validate_sublime_workspace_with_dir" \
    "inputs/blogredesign.sublime-workspace:42" \
    --all -c "echo")

# ------------------------------------------------------------------
# Cycle 4: Comprehensive Gap Analysis (3-agent parallel review)
# ------------------------------------------------------------------

# ==================================================================
# [C4-1] vim -p mode: zero line number and mixed line numbers

# ==================================================================
echo -e "${CYAN}[C4-4] FPP_DISABLE_SPLIT Non-Vim${NC}"

run_test_env "disable_split_nano_ignored" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=nano FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

run_test_env "disable_split_subl_ignored" \
    "src/main.rs:42
src/parse.rs:10" \
    "FPP_EDITOR=subl FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

# ==================================================================
# [C4-5] cd command with spaces in directory path

# ==================================================================
echo -e "${CYAN}[C4-13] Yocto File Validation Fallback${NC}"

# "other thing ./foo/file-from-yocto..." — ./foo/ doesn't exist, should fallback to bare filename
(cd "$INPUTS_DIR" && run_test "validate_yocto_foo_prefix" \
    "other thing ./foo/file-from-yocto_3.1%.bbappend" \
    --all -c "echo")

# NOTE: cd_bare_no_extension removed (duplicate of command_cd_bare_file in section 21)

# ==================================================================
# [C4-15] ANSI combined with multi-line: multiple SGR attributes on same path

# ==================================================================
echo -e "${CYAN}[C4-25] Dedup Same File Same Linenum${NC}"

run_test "dedup_same_path_same_linenum" \
    "src/main.rs:42
src/main.rs:42
src/parse.rs:10" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-26] Command mode: single file with $F (edge: $F at start of command)

# ==================================================================
echo -e "${CYAN}[C4-27] Backslash in Path${NC}"

run_test "path_with_backslash" \
    'src/main\.rs' \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-28] Very long filename (stress boundary)

# ==================================================================
echo -e "${CYAN}[C4-28] Very Long Filename${NC}"

LONG_NAME="src/$(python3 -c "print('a' * 200)").rs"
run_test "path_very_long_filename" \
    "$LONG_NAME" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C4-29] ANSI: incomplete sequence at end of line (no terminator)

# ==================================================================
echo -e "${CYAN}[COV-21] Home Dir with Linenum${NC}"

run_test "homedir_linenum_22" \
    "~/foo/bar/inHomeDir.py:22" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-22] prepend_dir edge: empty string and short strings

# ==================================================================
echo -e "${CYAN}[COV-22] prepend_dir Edge Cases${NC}"

run_test "prepend_no_slash_bare_file" \
    "simple.txt" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-23] FPP_LINENUM_SEP with custom separator and multi-file

# ==================================================================
echo -e "${CYAN}[COV-36] Git Abbreviated Edge Cases${NC}"

run_test "cov_git_abbreviated_no_slash" \
    "...something" \
    --no-file-checks --all -c "echo"

run_test "cov_git_abbreviated_with_subdir" \
    ".../subdir/file.py" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-37] Disable split for non-vim editors (no effect)

# ==================================================================
echo -e "${CYAN}[COV-37] FPP_DISABLE_SPLIT Non-Vim${NC}"

run_test_env "cov_disable_split_nano_ignored" \
    "src/a.rs:10
src/b.rs:20" \
    "FPP_EDITOR=nano FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

run_test_env "cov_disable_split_subl_ignored" \
    "src/a.rs:10
src/b.rs:20" \
    "FPP_EDITOR=subl FPP_DISABLE_SPLIT=1" \
    --no-file-checks --all

# ==================================================================
# [COV-38] State dir with spaces

# ==================================================================
echo -e "${CYAN}[COV-41] Dedup Same Path Same Linenum${NC}"

run_test "cov_dedup_same_path_same_linenum" \
    "src/main.rs:42
src/main.rs:42
src/lib.rs:10" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [COV-42] Logger file creation and JSON format

# ==================================================================
echo -e "${CYAN}[COV-47] File Inspection Path Resolution${NC}"

# Create a real file in a subdirectory to trigger file inspection logic
INSPECT_DIR="$TMPDIR_BASE/rs_file_inspect"
mkdir -p "$INSPECT_DIR/subdir"
echo "test" > "$INSPECT_DIR/subdir/real_file.txt"

# Run from the inspect dir so relative paths resolve
cd "$INSPECT_DIR"
export FPP_DIR="$INSPECT_DIR"
printf 'subdir/real_file.txt\n' | "$RUST_BINARY" --non-interactive --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR
cd /Users/devin/workspace/fast-path-picker

if [ -f "$INSPECT_DIR/.fpp.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} file_inspection_relative_resolve"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} file_inspection_relative_resolve"
    FAIL=$((FAIL + 1))
fi

# Also test file with spaces through file inspection
mkdir -p "$INSPECT_DIR/space dir"
echo "test" > "$INSPECT_DIR/space dir/my file.txt"
cd "$INSPECT_DIR"
export FPP_DIR="$INSPECT_DIR"
rm -f "$INSPECT_DIR/.fpp.sh"
printf 'space dir/my file.txt\n' | "$RUST_BINARY" --non-interactive --all -c "echo" >/dev/null 2>&1 || true
unset FPP_DIR
cd /Users/devin/workspace/fast-path-picker

if [ -f "$INSPECT_DIR/.fpp.sh" ]; then
    # Check that the file was actually matched (not "No lines matched")
    if grep -q "my file.txt" "$INSPECT_DIR/.fpp.sh" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC} file_inspection_space_path"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} file_inspection_space_path"
        echo "    Script exists but doesn't contain expected path"
        FAIL=$((FAIL + 1))
    fi
else
    echo -e "  ${RED}FAIL${NC} file_inspection_space_path"
    FAIL=$((FAIL + 1))
fi

# ==================================================================
# [COV-48] --execute-keys flag parsing

