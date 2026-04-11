//! Event logger matching Python PathPicker's logger.py.
//! Accumulates events and writes JSON to .fpp.log on output().

#![allow(dead_code)]

use std::sync::Mutex;

use anyhow::Result;

use crate::state;

static EVENTS: Mutex<Vec<(String, Option<usize>)>> = Mutex::new(Vec::new());

/// Add an event to the log.
pub fn add_event(event: &str, number: Option<usize>) {
    match EVENTS.lock() {
        Ok(mut events) => events.push((event.to_string(), number)),
        Err(e) => eprintln!("fpp: logger EVENTS mutex poisoned in add_event: {e}"),
    }
}

/// Write accumulated events to .fpp.log as JSON.
pub fn output() -> Result<()> {
    let events = match EVENTS.lock() {
        Ok(e) => e.clone(),
        Err(e) => {
            eprintln!("fpp: logger EVENTS mutex poisoned in output: {e}");
            return Ok(());
        }
    };

    let username = std::env::var("USER")
        .or_else(|_| std::env::var("LOGNAME"))
        .unwrap_or_else(|_| "unknown".to_string());

    let json_entries: Vec<String> = events
        .iter()
        .map(|(eventname, num)| {
            let num_str = match num {
                Some(n) => n.to_string(),
                None => "null".to_string(),
            };
            // Escape all special JSON characters to prevent malformed JSON from
            // env vars or event names containing quotes, backslashes, or control chars.
            let escaped_user = json_escape(&username);
            let escaped_event = json_escape(eventname);
            format!(
                r#"{{"unixname": "{}", "num": {}, "eventname": "{}"}}"#,
                escaped_user, num_str, escaped_event
            )
        })
        .collect();

    let json_output = format!("[{}]", json_entries.join(", "));
    let log_path = state::get_state_dir().join(".fpp.log");
    state::ensure_state_dir()?;
    std::fs::write(log_path, json_output)?;
    Ok(())
}

/// Escape a string for safe inclusion in a JSON string value.
/// Handles backslash, double-quote, and control characters (newline, tab, carriage return,
/// null byte, and other C0 controls).
fn json_escape(s: &str) -> String {
    use std::fmt::Write;
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c if c.is_control() => {
                // Encode other control characters as \uXXXX
                for unit in c.encode_utf16(&mut [0; 2]) {
                    // write! to String is infallible, unwrap is safe
                    write!(out, "\\u{unit:04x}").unwrap();
                }
            }
            c => out.push(c),
        }
    }
    out
}

/// Clear the log file.
pub fn clear() -> Result<()> {
    let log_path = state::get_state_dir().join(".fpp.log");
    if log_path.exists() {
        std::fs::write(log_path, "")?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_json_escape_backslash() {
        assert_eq!(json_escape(r"a\b"), r"a\\b");
    }

    #[test]
    fn test_json_escape_double_quote() {
        assert_eq!(json_escape(r#"say "hello""#), r#"say \"hello\""#);
    }

    #[test]
    fn test_json_escape_newline_tab_cr() {
        assert_eq!(json_escape("a\nb\tc\rd"), r"a\nb\tc\rd");
    }

    #[test]
    fn test_json_escape_control_chars() {
        // Null byte
        assert_eq!(json_escape("\x00"), r"\u0000");
        // Bell
        assert_eq!(json_escape("\x07"), r"\u0007");
        // Form feed
        assert_eq!(json_escape("\x0c"), r"\u000c");
        // Escape char (0x1b)
        assert_eq!(json_escape("\x1b"), r"\u001b");
    }

    #[test]
    fn test_json_escape_plain_text() {
        assert_eq!(json_escape("hello world"), "hello world");
    }

    #[test]
    fn test_json_escape_mixed() {
        assert_eq!(
            json_escape("line1\nline2\t\"quoted\"\\\x00end"),
            r#"line1\nline2\t\"quoted\"\\\u0000end"#
        );
    }

    // NOTE: This test sets/removes FPP_DIR without an ENV_LOCK mutex.
    // Unlike state_tests and output_tests which have their own ENV_LOCK,
    // this module only has a single env-mutating test so a lock is not
    // strictly necessary. However, to avoid cross-module races on FPP_DIR,
    // run with `--test-threads=1`.
    #[test]
    fn test_add_event_and_output() {
        let tmp = tempfile::tempdir().unwrap();
        std::env::set_var("FPP_DIR", tmp.path().to_str().unwrap());

        // Clear any previous events from other tests
        if let Ok(mut events) = EVENTS.lock() {
            events.clear();
        }

        add_event("test_event", Some(42));
        add_event("another_event", None);

        output().unwrap();

        let log_path = tmp.path().join(".fpp.log");
        let content = std::fs::read_to_string(log_path).unwrap();
        assert!(content.starts_with('['));
        assert!(content.ends_with(']'));
        assert!(content.contains("test_event"));
        assert!(content.contains("42"));
        assert!(content.contains("another_event"));
        assert!(content.contains("null"));

        // Clean up
        if let Ok(mut events) = EVENTS.lock() {
            events.clear();
        }
        std::env::remove_var("FPP_DIR");
    }
}
