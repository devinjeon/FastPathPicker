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

#[allow(dead_code)]
pub fn get_log_path() -> PathBuf {
    get_state_dir().join(".fpp.log")
}

pub fn get_selection_path() -> PathBuf {
    get_state_dir().join(".selection.json")
}

pub fn get_keybindings_path() -> PathBuf {
    get_state_dir().join(".fpp.keys")
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

/// Clean all state files.
pub fn clean_state() -> Result<()> {
    let dir = get_state_dir();
    if dir.exists() {
        for entry in fs::read_dir(&dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_file() {
                fs::remove_file(path)?;
            }
        }
    }
    Ok(())
}

/// Write the output shell script.
pub fn write_script(content: &str) -> Result<()> {
    ensure_state_dir()?;
    fs::write(get_script_output_path(), content)?;
    Ok(())
}

/// Append to the output shell script.
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
#[allow(dead_code)]
pub fn delete_selection() -> Result<()> {
    let path = get_selection_path();
    if path.exists() {
        fs::remove_file(path)?;
    }
    Ok(())
}
