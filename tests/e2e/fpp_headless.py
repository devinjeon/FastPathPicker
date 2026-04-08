#!/usr/bin/env python3
"""Headless PathPicker runner for e2e testing.

Mirrors the original process_input.main() flow as closely as possible,
calling the actual Python functions rather than reimplementing them.
Replaces the curses UI with automatic "select all + enter".

Usage:
    echo "src/main.rs" | python3 fpp_headless.py --all --no-file-checks -c "echo"
    echo "src/main.rs" | FPP_DIR=/tmp/test python3 fpp_headless.py --all -c "git add"

Environment:
    FPP_DIR       State directory (default: ~/.cache/fpp)
    FPP_EDITOR    Editor override
    SHELL         Shell for exit status variable
"""
import os
import pickle
import sys

# Add PathPicker src to path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
PATHPICKER_SRC = os.path.join(PROJECT_ROOT, "PathPicker", "src")
sys.path.insert(0, PATHPICKER_SRC)

from pathpicker import output, state_files
from pathpicker.line_format import LineMatch
from pathpicker.screen_flags import ScreenFlags
import process_input


def main():
    argv = sys.argv[1:]
    flags = ScreenFlags.init_from_args(argv)

    # --clean: call the actual process_input.main() clean path
    # (matches process_input.main lines 72-78)
    if flags.get_is_clean_mode():
        for file_path in state_files.get_all_state_files():
            if os.path.isfile(file_path):
                os.remove(file_path)
        return

    if sys.stdin.isatty():
        # TTY mode: reuse previous input
        # (matches process_input.main lines 79-92)
        if flags.get_keep_open():
            selection_path = state_files.get_selection_file_path()
            if os.path.isfile(selection_path):
                os.remove(selection_path)
        pickle_path = state_files.get_pickle_file_path()
        if os.path.isfile(pickle_path):
            with open(pickle_path, "rb") as f:
                line_objs = pickle.load(f)
        else:
            process_input.usage()
            return
    else:
        # Pipe mode: delete old selection, then call do_program()
        # (matches process_input.main lines 93-98)
        selection_path = state_files.get_selection_file_path()
        if os.path.isfile(selection_path):
            os.remove(selection_path)

        # Call the actual do_program to save pickle
        # (matches process_input.do_program lines 60-63)
        process_input.do_program(flags)

        # Load back the parsed results from pickle
        pickle_path = state_files.get_pickle_file_path()
        with open(pickle_path, "rb") as f:
            line_objs = pickle.load(f)

    # --- Output phase (mirrors screen_control after user selects all) ---
    matches = [obj for obj in line_objs.values() if isinstance(obj, LineMatch)]

    if not matches:
        output.clear_file()
        output.append_to_file('echo "No lines matched!";')
        output.append_exit()
        return

    preset_command = flags.get_preset_command()
    output.clear_file()
    output.exec_composed_command(preset_command, matches)


if __name__ == "__main__":
    main()
