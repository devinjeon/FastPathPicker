//! Event logger matching Python PathPicker's logger.py.
//! Accumulates events and writes JSON to .fpp.log on output().

#![allow(dead_code)]

use std::sync::Mutex;

use anyhow::Result;

use crate::state;

static EVENTS: Mutex<Vec<(String, Option<usize>)>> = Mutex::new(Vec::new());

/// Add an event to the log.
pub fn add_event(event: &str, number: Option<usize>) {
    if let Ok(mut events) = EVENTS.lock() {
        events.push((event.to_string(), number));
    }
}

/// Write accumulated events to .fpp.log as JSON.
pub fn output() -> Result<()> {
    let events = match EVENTS.lock() {
        Ok(e) => e.clone(),
        Err(_) => return Ok(()),
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
            format!(
                r#"{{"unixname": "{}", "num": {}, "eventname": "{}"}}"#,
                username, num_str, eventname
            )
        })
        .collect();

    let json_output = format!("[{}]", json_entries.join(", "));
    let log_path = state::get_state_dir().join(".fpp.log");
    state::ensure_state_dir()?;
    std::fs::write(log_path, json_output)?;
    Ok(())
}

/// Clear the log file.
pub fn clear() -> Result<()> {
    let log_path = state::get_state_dir().join(".fpp.log");
    if log_path.exists() {
        std::fs::write(log_path, "")?;
    }
    Ok(())
}
