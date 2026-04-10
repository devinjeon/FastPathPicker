# Suite: 10_stress_and_fuzz
# Sourced by run_e2e.sh — do not run directly.

# ------------------------------------------------------------------
echo -e "${CYAN}[15] Stress Tests${NC}"

# Generate 200 file paths
MANY_FILES=""
for i in $(seq 1 200); do
    MANY_FILES+="src/file${i}.rs:${i}
"
done

run_test "stress_200_files" \
    "$MANY_FILES" \
    --no-file-checks --all -c "echo"

# Very long file path
LONG_PATH="very/deeply/nested/directory/structure/that/goes/on/and/on/for/a/while/to/test/limits/file.rs"
run_test "stress_long_path" \
    "$LONG_PATH" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 16. ANSI color handling

# ------------------------------------------------------------------
echo -e "${CYAN}[39] Stress Tests Extended${NC}"

# 500 files
STRESS_500=""
for i in $(seq 1 500); do
    STRESS_500+="src/module${i}/file${i}.rs:${i}
"
done
run_test "stress_500_files" \
    "$STRESS_500" \
    --no-file-checks --all -c "echo"

# Mixed input: many non-file lines with occasional file paths
STRESS_MIXED=""
for i in $(seq 1 100); do
    STRESS_MIXED+="This is just plain text line ${i}
"
    if (( i % 20 == 0 )); then
        STRESS_MIXED+="src/file${i}.rs:${i}
"
    fi
done
run_test "stress_mixed_input" \
    "$STRESS_MIXED" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 40. State Directory Priority

# ------------------------------------------------------------------
echo -e "${CYAN}[53] Fuzz Patterns Extended${NC}"

# +++ prefix (git diff style) + normal path
run_test "fuzz_plus_prefix" \
    "+++ html/js/hotness.js" \
    --no-file-checks --all -c "echo"

# Path with suffix containing colon+numbers (line number interference)
run_test "fuzz_colon_suffix" \
    "html/js/hotness.js:0:7: var AdsErrorCodeStore" \
    --no-file-checks --all -c "echo"

# Home dir path with fuzz prefix
run_test "fuzz_home_with_prefix" \
    "Modified: ~/foo/bar/something.py * Adapts to something" \
    --no-file-checks --all -c "echo"

# Multiple periods file with prefix
run_test "fuzz_periods_with_prefix" \
    "blarg blah So.MANY.PERIODS.TXT:22 jkk asdad" \
    --no-file-checks --all -c "echo"

# @ in path with prefix word
run_test "fuzz_at_sign_prefix" \
    "blarge assets/retina/victory@2x.png" \
    --no-file-checks --all -c "echo"

# + in path with prefix word
run_test "fuzz_plus_sign_prefix" \
    "test src/categories/NSDate+Category.h" \
    --no-file-checks --all -c "echo"

# Home dir + @ character
run_test "fuzz_home_at_sign" \
    "~/assets/retina/victory@2x.png" \
    --no-file-checks --all -c "echo"

# Home dir + + character
run_test "fuzz_home_plus_sign" \
    "~/src/categories/NSDate+Category.h" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 54. Stress: Very Long Single Line

# ------------------------------------------------------------------
echo -e "${CYAN}[54] Long Line Stress${NC}"

LONG_LINE="$(python3 -c "print('x' * 5000 + ' src/main.rs:42 ' + 'y' * 5000)")"
run_test "stress_very_long_line" \
    "$LONG_LINE" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 55. Path Escaping Extended

# ------------------------------------------------------------------
echo -e "${CYAN}[73] Additional Fuzz Patterns${NC}"

# Banana prefix + absolute path + suffix
run_test "fuzz_banana_absolute_path" \
    "Banana asdasdoj pjo /absolute/path/to/something.txt jkk asdad" \
    --no-file-checks --all -c "echo"

# M prefix + dotfile
run_test "fuzz_m_prefix_dotfile" \
    "M .env.local * Adapts AdsErrorCodestore to something" \
    --no-file-checks --all -c "echo"

# +++ prefix + @ file + suffix
run_test "fuzz_plus_prefix_at_file" \
    "+++ assets/retina/victory@2x.png jkk asdad" \
    --no-file-checks --all -c "echo"

# Changed prefix + dotdir
run_test "fuzz_changed_prefix_dotdir" \
    "Changed: .ssh/known_hosts:0:7: var AdsErrorCodeStore" \
    --no-file-checks --all -c "echo"

# M prefix + TARGETS-dash + suffix
run_test "fuzz_m_prefix_targets_dash" \
    "M foo/bar/TARGETS-24 jkk asdad" \
    --no-file-checks --all -c "echo"

# M prefix + dotfile path + colon suffix
run_test "fuzz_m_prefix_gitignore" \
    "M tmp/.gitignore:0:7: var AdsErrorCodeStore" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# 74. vi/vim Mixed Linenum (some files with linenum, some without)

# ------------------------------------------------------------------
echo -e "${CYAN}[Cycle2-8] Fuzz Combinations${NC}"

# +++ prefix with dotfile
run_test "fuzz_plus_prefix_dotfile" \
    "+++ .env.local * Adapts AdsErrorCodestore to something" \
    --no-file-checks --all -c "echo"

# Changed: prefix with gitignore in subdir
run_test "fuzz_changed_prefix_gitignore" \
    "Changed: tmp/.gitignore jkk asdad" \
    --no-file-checks --all -c "echo"

# Banana prefix with TARGETS and linenum + suffix
run_test "fuzz_banana_targets_linenum" \
    "Banana asdasdoj pjo foo/bar/TARGETS:23 jkk asdad" \
    --no-file-checks --all -c "echo"

# Modified: prefix with vim temp file + code suffix
run_test "fuzz_modified_vim_temp" \
    "Modified: #So.many.periods.txt#:0:7: var AdsErrorCodeStore" \
    --no-file-checks --all -c "echo"

# +++ prefix with linenum path + suffix
run_test "fuzz_plus_prefix_asd_linenum" \
    "+++ ./asd.txt:83 jkk asdad" \
    --no-file-checks --all -c "echo"

# M prefix with NSArray+Utils.h
run_test "fuzz_m_prefix_nsarray_plus_h" \
    "M     ./objectivec/NSArray+Utils.h" \
    --no-file-checks --all -c "echo"

# ------------------------------------------------------------------
# Cycle 2: all_input edge cases

# ==================================================================
echo -e "${CYAN}[C1-25] Long Lines${NC}"

# Path at the end of a very long line
_long_prefix=$(python3 -c "print('x' * 500)")
run_test "long_line_path_at_end" \
    "${_long_prefix} src/main.rs:42" \
    --no-file-checks --all -c "echo"

# Path at the beginning of a very long line
_long_suffix=$(python3 -c "print('x' * 500)")
run_test "long_line_path_at_start" \
    "src/main.rs:42 ${_long_suffix}" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-26] Multiple matches on same line

# ==================================================================
echo -e "${CYAN}[C1-10] Shell Exit Code Edge Cases${NC}"

# Shell with full path to fish (different path from shell_fish_exit)
run_test_env "shell_fish_localbin" \
    "src/main.rs" \
    "SHELL=/usr/local/bin/fish FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# Shell containing "fish" as substring (e.g. goldfish) - should suppress shopt
run_test_env "shell_goldfish_no_shopt" \
    "src/main.rs" \
    "SHELL=/usr/bin/goldfish FPP_EDITOR=vim" \
    --no-file-checks --all -c "echo"

# ==================================================================
# [C1-11] NOTE: editor_full_path_nano removed (duplicate of [49])

