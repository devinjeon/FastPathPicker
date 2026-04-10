/// Labels used for quick-select mode.
/// Excludes 'A' (select all) and 'F' (toggle+move).
pub const QUICK_SELECT_LABELS: &str = "BCDEGHIJKLMNOPQRSTUVWXYZ1234567890~!@#$%^&*()_+<>?{}|;'";

/// Get the label character for a given visible line index in quick-select mode.
pub fn get_label(index: usize) -> Option<char> {
    QUICK_SELECT_LABELS.chars().nth(index)
}

/// Find the line index for a given quick-select label character.
/// Accepts both upper and lowercase input (for non-X_MODE contexts).
#[allow(dead_code)]
pub fn find_index_for_label(ch: char) -> Option<usize> {
    let upper = ch.to_ascii_uppercase();
    QUICK_SELECT_LABELS.chars().position(|c| c == upper)
}

/// Find the line index for a given quick-select label character (exact match).
/// Python only matches exact characters in LABELS (no case conversion).
pub fn find_index_for_label_exact(ch: char) -> Option<usize> {
    QUICK_SELECT_LABELS.chars().position(|c| c == ch)
}

#[cfg(test)]
#[path = "quick_select_tests.rs"]
mod tests;
