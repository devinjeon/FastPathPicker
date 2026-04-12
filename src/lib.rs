// Library re-exports for integration tests.
// The actual application logic lives in each module;
// main.rs also declares these as `mod` for the binary target.

pub mod format;
pub mod input;
pub mod keybindings;
pub mod line;
pub mod logger;
pub mod output;
pub mod parse;
pub mod state;
pub mod ui;

/// Shared test utilities. This module is only compiled during testing.
#[cfg(test)]
pub(crate) mod test_env {
    use std::sync::Mutex;

    /// Global lock for all tests that mutate environment variables (FPP_DIR, SHELL, etc.).
    /// All env-mutating tests across all modules MUST acquire this lock to prevent
    /// cross-module races when tests run in parallel.
    pub static ENV_LOCK: Mutex<()> = Mutex::new(());
}
