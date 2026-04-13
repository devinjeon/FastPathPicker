//! Event logger matching Python PathPicker's logger.py.
//! Accumulates events and writes JSON to .fpp.log on output().

use std::sync::Mutex;

use anyhow::Result;
use serde::Serialize;

use crate::state;

#[derive(Serialize)]
struct LogEntry {
    unixname: String,
    num: Option<usize>,
    eventname: String,
}

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
        Ok(mut e) => std::mem::take(&mut *e),
        Err(e) => {
            eprintln!("fpp: logger EVENTS mutex poisoned in output: {e}");
            return Ok(());
        }
    };

    let username = std::env::var("USER")
        .or_else(|_| std::env::var("LOGNAME"))
        .unwrap_or_else(|_| "unknown".to_string());

    let entries: Vec<LogEntry> = events
        .into_iter()
        .map(|(eventname, num)| LogEntry {
            unixname: username.clone(),
            num,
            eventname,
        })
        .collect();

    let json_output = serde_json::to_string(&entries)?;
    let log_path = state::get_state_dir().join(".fpp.log");
    state::ensure_state_dir()?;
    std::fs::write(log_path, json_output)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_serde_json_escaping() {
        // Verify serde_json handles special characters correctly
        let entry = LogEntry {
            unixname: "user\"with\\special\nchars".to_string(),
            num: Some(42),
            eventname: "test\tevent".to_string(),
        };
        let json = serde_json::to_string(&entry).unwrap();
        assert!(json.contains(r#"\"#));
        assert!(json.contains("42"));
        // Verify it's valid JSON by round-tripping
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed["num"], 42);
    }

    #[test]
    fn test_serde_json_null_num() {
        let entry = LogEntry {
            unixname: "user".to_string(),
            num: None,
            eventname: "event".to_string(),
        };
        let json = serde_json::to_string(&entry).unwrap();
        assert!(json.contains("null"));
    }

    #[test]
    fn test_add_event_and_output() {
        let _guard = crate::test_env::ENV_LOCK.lock().unwrap();
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

        // Verify the output is valid JSON
        let parsed: Vec<serde_json::Value> = serde_json::from_str(&content).unwrap();
        assert_eq!(parsed.len(), 2);

        // Clean up
        if let Ok(mut events) = EVENTS.lock() {
            events.clear();
        }
        std::env::remove_var("FPP_DIR");
    }
}
