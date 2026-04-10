use std::io::IsTerminal;
use std::os::unix::io::AsRawFd;
use std::process;

use anyhow::Result;
use clap::Parser;

use fpp::{input, line, output, state, ui};

/// A fast file path picker - Rust rewrite of Facebook's PathPicker (fpp).
/// Parses file paths from stdin and presents an interactive selection UI.
#[derive(Parser, Debug)]
#[command(
    name = "fpp",
    version = "version 0.9.5",
    about = "
fpp - fast PathPicker

Pipe any command output to fpp to select files interactively:
  git status | fpp
  grep -rn pattern . | fpp
  find . -name '*.rs' | fpp

Navigate with j/k or arrows, f to select, ENTER to open in editor.
Press c to enter command mode, or use -c to specify a command.
Use $F in commands to place filenames mid-command: -c 'mv $F /tmp/'
"
)]
struct Args {
    /// Specify command to run on selected files
    #[arg(short = 'c', long = "command", num_args = 1..)]
    command: Option<Vec<String>>,

    /// Automatically execute given keys when file list shows up
    #[arg(short = 'e', long = "execute-keys", num_args = 1..)]
    execute_keys: Option<Vec<String>>,

    /// Disable filesystem validation
    #[arg(long = "no-file-checks", visible_alias = "nfc")]
    no_file_checks: bool,

    /// Force all input lines to be recognized
    #[arg(long = "all-input", visible_alias = "ai")]
    all_input: bool,

    /// Run commands in non-interactive subshell
    #[arg(long = "non-interactive", visible_alias = "ni")]
    non_interactive: bool,

    /// Automatically select all available lines
    #[arg(short = 'a', long = "all")]
    all: bool,

    /// Remove all state files on startup
    #[arg(long = "clean")]
    clean: bool,

    /// Record input and output for testing
    #[arg(short = 'r', long = "record")]
    record: bool,

    /// Keep PathPicker open after file selection
    #[arg(long = "keep-open", visible_alias = "ko")]
    keep_open: bool,

    /// Print execution directory (debug mode)
    #[arg(long = "debug")]
    debug: bool,
}

/// Convert Python-style single-dash multi-char flags to double-dash.
/// e.g., -nfc → --nfc, -ai → --ai, -ni → --ni, -ko → --ko
fn preprocess_args() -> Vec<String> {
    const MULTI_CHAR_SHORTS: &[&str] = &["-nfc", "-ai", "-ni", "-ko"];
    std::env::args()
        .map(|arg| {
            if MULTI_CHAR_SHORTS.contains(&arg.as_str()) {
                format!("-{arg}")
            } else {
                arg
            }
        })
        .collect()
}

fn run_once(args: &Args, lines: Vec<line::Line>, match_indices: Vec<usize>) -> Result<()> {
    if match_indices.is_empty() {
        output::output_no_matches()?;
        return Ok(());
    }

    let preset_command = args.command.as_ref().map(|parts| parts.join(" "));

    // Non-interactive mode: select all matches and execute immediately
    if args.non_interactive {
        let matches: Vec<line::LineMatch> = match_indices
            .iter()
            .filter_map(|&idx| lines[idx].as_match().cloned())
            .collect();
        let command = preset_command.as_deref().unwrap_or("");
        output::exec_composed_command(command, &matches)?;
        return Ok(());
    }

    // Create and run interactive controller
    let execute_keys_str = args.execute_keys.as_ref().map(|v| v.join(" "));
    let mut controller = ui::controller::Controller::new(
        lines,
        match_indices,
        preset_command,
        args.all,
        execute_keys_str,
        args.all_input,
    );

    controller.run()?;

    Ok(())
}

/// Execute the generated .fpp.sh script using the user's shell.
/// Mirrors Python's fpp bash wrapper behavior.
fn execute_script(non_interactive: bool) -> Result<()> {
    // Allow skipping script execution for testing (e2e tests only need .fpp.sh content)
    if std::env::var("FPP_SKIP_EXECUTE").is_ok() {
        return Ok(());
    }

    let script_path = state::get_script_output_path();
    if !script_path.exists() {
        return Ok(());
    }

    let content = std::fs::read_to_string(&script_path)?;
    if content.trim().is_empty() {
        return Ok(());
    }

    // Determine shell: $SHELL, $BASH, or fallback to /bin/bash
    let shell = std::env::var("SHELL")
        .or_else(|_| std::env::var("BASH"))
        .unwrap_or_else(|_| "/bin/bash".to_string());

    // Add -i flag for interactive shell unless:
    // - non-interactive mode is set
    // - running inside vim (VIMRUNTIME is set)
    let use_interactive = !non_interactive && std::env::var("VIMRUNTIME").is_err();

    let mut cmd = process::Command::new(&shell);
    if use_interactive {
        cmd.arg("-i");
    }
    cmd.arg(&script_path);

    // Connect stdin to /dev/tty for interactive programs (vim, etc.)
    if let Ok(tty) = std::fs::File::open("/dev/tty") {
        cmd.stdin(tty);
    }

    let status = cmd.status()?;

    // Propagate exit code from the script
    if !status.success() {
        process::exit(status.code().unwrap_or(1));
    }

    Ok(())
}

fn main() -> Result<()> {
    let args = Args::parse_from(preprocess_args());

    if args.debug {
        eprintln!("fpp executing in: {}", std::env::current_dir()?.display());
    }

    if args.record {
        eprintln!("Recording input and output...");
    }

    if args.clean {
        println!("Cleaning out state files...");
        let count = state::clean_state()?;
        println!("Done! Removed {count} files ");
        return Ok(());
    }

    let validate_files = !args.no_file_checks && !args.all_input;
    let all_input = args.all_input;

    // Get input lines: from stdin (piped) or from cache (TTY re-use)
    let raw_lines = if std::io::stdin().is_terminal() {
        // stdin is a TTY — try to reuse previous input (like Python's pickle re-use)
        if args.keep_open {
            let _ = state::delete_selection();
        }

        match state::load_input_cache() {
            Ok(cached) => {
                eprintln!("Using previous input piped to fpp...");
                cached
            }
            Err(_) => {
                eprintln!("No input provided. Pipe command output to fpp:");
                eprintln!("  git status | fpp");
                eprintln!("  grep -rn pattern . | fpp");
                return Ok(());
            }
        }
    } else {
        // stdin is piped — read fresh input, save cache, delete old selection
        let _ = state::delete_selection();
        let lines = input::read_stdin_lines()?;
        state::save_input_cache(&lines)?;
        lines
    };

    // After reading piped stdin, redirect fd 0 to /dev/tty so crossterm
    // can read keyboard input for the interactive UI.
    // Only needed (and possible) when we'll run an interactive session.
    if !args.non_interactive {
        if let Ok(tty) = std::fs::File::open("/dev/tty") {
            // SAFETY: dup2 atomically replaces fd 0 with the tty fd.
            // This is standard practice for TUI programs that read piped stdin.
            unsafe {
                libc::dup2(tty.as_raw_fd(), libc::STDIN_FILENO);
            }
        }
    }

    let lines = input::get_line_objs_from_lines(&raw_lines, validate_files, all_input);
    let match_indices = input::get_matches(&lines);

    if args.keep_open && std::env::var("FPP_SKIP_EXECUTE").is_err() {
        loop {
            let _ = state::delete_selection();
            run_once(&args, lines.clone(), match_indices.clone())?;
            execute_script(args.non_interactive)?;
        }
    } else {
        run_once(&args, lines, match_indices)?;
        execute_script(args.non_interactive)?;
    }

    Ok(())
}
