use std::fs;

use crate::state;

/// A custom key binding mapping a key to a command.
#[derive(Debug, Clone)]
pub struct KeyBinding {
    pub key: String,
    pub command: String,
}

/// Read custom key bindings from the configuration file.
/// Returns an empty list if the file doesn't exist.
pub fn read_key_bindings() -> Vec<KeyBinding> {
    let path = state::get_keybindings_path();
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };

    parse_key_bindings(&content)
}

/// Parse key bindings from INI-style configuration content.
fn parse_key_bindings(content: &str) -> Vec<KeyBinding> {
    let mut bindings = Vec::new();
    let mut in_bindings_section = false;

    for line in content.lines() {
        let trimmed = line.trim();

        if trimmed == "[bindings]" {
            in_bindings_section = true;
            continue;
        }

        if trimmed.starts_with('[') {
            in_bindings_section = false;
            continue;
        }

        if in_bindings_section {
            if let Some((key, command)) = trimmed.split_once('=') {
                // Lowercase keys like Python's configparser
                bindings.push(KeyBinding {
                    key: key.trim().to_lowercase(),
                    command: command.trim().to_string(),
                });
            }
        }
    }

    bindings
}

#[cfg(test)]
#[path = "keybindings_tests.rs"]
mod tests;
