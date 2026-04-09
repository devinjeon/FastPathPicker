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
mod tests {
    use super::*;

    #[test]
    fn test_empty_config() {
        let bindings = parse_key_bindings("");
        assert!(bindings.is_empty());
    }

    #[test]
    fn test_standard_parsing() {
        let config = "[bindings]\nr = rspec\ns = subl";
        let bindings = parse_key_bindings(config);
        assert_eq!(bindings.len(), 2);
        assert_eq!(bindings[0].key, "r");
        assert_eq!(bindings[0].command, "rspec");
        assert_eq!(bindings[1].key, "s");
        assert_eq!(bindings[1].command, "subl");
    }

    #[test]
    fn test_no_bindings_section() {
        let config = "[other]\nkey = value";
        let bindings = parse_key_bindings(config);
        assert!(bindings.is_empty());
    }

    /// Ported from Python's test_ignore_non_existing_configuration_file.
    /// read_key_bindings() should return an empty list for a non-existent file.
    #[test]
    fn test_ignore_non_existing_configuration_file() {
        // Temporarily set FPP_DIR to a temp directory with no .fpp.keys file.
        let tmp = std::env::temp_dir().join("fpp_test_no_keybindings");
        let _ = std::fs::create_dir_all(&tmp);
        // Make sure the keys file does NOT exist.
        let keys_file = tmp.join(".fpp.keys");
        let _ = std::fs::remove_file(&keys_file);

        std::env::set_var("FPP_DIR", &tmp);
        let bindings = read_key_bindings();
        // Clean up
        std::env::remove_var("FPP_DIR");
        let _ = std::fs::remove_dir_all(&tmp);

        assert!(
            bindings.is_empty(),
            "read_key_bindings should return empty for non-existent file, got: {:?}",
            bindings.len(),
        );
    }
}
