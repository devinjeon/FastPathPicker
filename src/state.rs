use std::env;
use std::fs;
use std::path::PathBuf;

use anyhow::Result;
use serde::{Deserialize, Serialize};

/// Selection state persisted between sessions.
#[derive(Debug, Serialize, Deserialize, Default)]
pub struct SelectionState {
    pub selected_indices: Vec<usize>,
}

/// Get the state directory path (FPP_DIR, XDG_CACHE_HOME/fpp, or ~/.cache/fpp).
pub fn get_state_dir() -> PathBuf {
    if let Ok(fpp_dir) = env::var("FPP_DIR") {
        return PathBuf::from(fpp_dir);
    }
    if let Ok(xdg) = env::var("XDG_CACHE_HOME") {
        return PathBuf::from(xdg).join("fpp");
    }
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".cache")
        .join("fpp")
}

/// Ensure the state directory exists.
pub fn ensure_state_dir() -> Result<PathBuf> {
    let dir = get_state_dir();
    fs::create_dir_all(&dir)?;
    Ok(dir)
}

pub fn get_script_output_path() -> PathBuf {
    get_state_dir().join(".fpp.sh")
}

pub fn get_selection_path() -> PathBuf {
    get_state_dir().join(".selection.json")
}

pub fn get_keybindings_path() -> PathBuf {
    get_state_dir().join(".fpp.keys")
}

pub fn get_input_cache_path() -> PathBuf {
    get_state_dir().join(".input.json")
}

/// Save selection state to disk.
pub fn save_selection(state: &SelectionState) -> Result<()> {
    ensure_state_dir()?;
    let json = serde_json::to_string(state)?;
    fs::write(get_selection_path(), json)?;
    Ok(())
}

/// Load selection state from disk.
pub fn load_selection() -> Result<SelectionState> {
    let path = get_selection_path();
    if !path.exists() {
        return Ok(SelectionState::default());
    }
    let data = fs::read_to_string(path)?;
    let state: SelectionState = serde_json::from_str(&data)?;
    Ok(state)
}

/// Save raw input lines to cache for stdin re-use (replaces Python's pickle).
pub fn save_input_cache(lines: &[String]) -> Result<()> {
    ensure_state_dir()?;
    let json = serde_json::to_string(lines)?;
    fs::write(get_input_cache_path(), json)?;
    Ok(())
}

/// Load cached input lines for stdin re-use.
pub fn load_input_cache() -> Result<Vec<String>> {
    let path = get_input_cache_path();
    if !path.exists() {
        anyhow::bail!("No cached input found");
    }
    let data = fs::read_to_string(path)?;
    let lines: Vec<String> = serde_json::from_str(&data)?;
    Ok(lines)
}

/// Clean specific state files (like Python: pickle, selection, log, script).
/// Python cleans: .pickle, .selection.pickle, .fpp.log, .fpp.sh
/// (does NOT clean keybindings)
pub fn clean_state() -> Result<usize> {
    let state_files = [
        get_script_output_path(),
        get_selection_path(),
        get_input_cache_path(),
        get_state_dir().join(".fpp.log"),
    ];
    let mut count = 0;
    for path in &state_files {
        if path.exists() {
            fs::remove_file(path)?;
            count += 1;
        }
    }
    Ok(count)
}

/// Write the output shell script (truncate + write).
/// Callers should call `logger::output()` once after all script writes are complete,
/// rather than on every individual write, to avoid repeated I/O.
pub fn write_script(content: &str) -> Result<()> {
    ensure_state_dir()?;
    fs::write(get_script_output_path(), format!("{content}\n"))?;
    Ok(())
}

/// Append to the output shell script.
/// Callers should call `logger::output()` once after all script writes are complete.
pub fn append_script(content: &str) -> Result<()> {
    use std::io::Write;
    ensure_state_dir()?;
    let path = get_script_output_path();
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)?;
    writeln!(file, "{content}")?;
    Ok(())
}

/// Delete selection state file.
pub fn delete_selection() -> Result<()> {
    let path = get_selection_path();
    if path.exists() {
        fs::remove_file(path)?;
    }
    Ok(())
}

#[cfg(test)]
#[path = "state_tests.rs"]
mod tests;
