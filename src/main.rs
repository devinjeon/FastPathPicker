mod format;
mod input;
mod keybindings;
mod line;
mod output;
mod parse;
mod state;
mod ui;

use std::io::IsTerminal;

use anyhow::Result;
use clap::Parser;

/// A fast file path picker - Rust rewrite of Facebook's PathPicker (fpp).
/// Parses file paths from stdin and presents an interactive selection UI.
#[derive(Parser, Debug)]
#[command(
    name = "fpp",
    version = "0.9.5",
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
    #[arg(short = 'e', long = "execute-keys")]
    execute_keys: Option<String>,

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

fn run_once(args: &Args, lines: Vec<line::Line>, match_indices: Vec<usize>) -> Result<()> {
    if match_indices.is_empty() {
        output::output_nothing()?;
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
    let mut controller = ui::controller::Controller::new(
        lines,
        match_indices,
        preset_command,
        args.all,
        args.execute_keys.clone(),
    );

    controller.run()?;

    Ok(())
}

fn main() -> Result<()> {
    let args = Args::parse();

    if args.debug {
        eprintln!("fpp executing in: {}", std::env::current_dir()?.display());
    }

    if args.record {
        eprintln!("Recording input and output...");
    }

    if args.clean {
        state::clean_state()?;
        if !std::io::stdin().is_terminal() {
            // Continue processing after clean
        } else {
            return Ok(());
        }
    }

    // Check if stdin is a terminal (no piped input)
    if std::io::stdin().is_terminal() {
        eprintln!("No input provided. Pipe command output to fpp:");
        eprintln!("  git status | fpp");
        eprintln!("  grep -rn pattern . | fpp");
        return Ok(());
    }

    let validate_files = !args.no_file_checks;
    let all_input = args.all_input;

    // Read and parse input (only once from stdin)
    let lines = input::get_line_objs_from_stdin(validate_files, all_input)?;
    let match_indices = input::get_matches(&lines);

    if args.keep_open {
        // Loop mode: re-run the UI after each selection until Ctrl-C
        loop {
            // Clear previous selection
            let _ = state::delete_selection();
            run_once(&args, lines.clone(), match_indices.clone())?;
        }
    } else {
        run_once(&args, lines, match_indices)?;
    }

    Ok(())
}
