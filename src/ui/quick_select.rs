/// Labels used for quick-select mode.
/// Excludes 'A' (select all) and 'F' (toggle+move).
pub const QUICK_SELECT_LABELS: &str = "BCDEGHIJKLMNOPQRSTUVWXYZ1234567890~!@#$%^&*()_+<>?{}|;'";

/// Get the label character for a given visible line index in quick-select mode.
pub fn get_label(index: usize) -> Option<char> {
    QUICK_SELECT_LABELS.chars().nth(index)
}

/// Find the line index for a given quick-select label character.
/// Accepts both upper and lowercase input.
pub fn find_index_for_label(ch: char) -> Option<usize> {
    let upper = ch.to_ascii_uppercase();
    QUICK_SELECT_LABELS.chars().position(|c| c == upper)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_label() {
        assert_eq!(get_label(0), Some('B'));
        assert_eq!(get_label(1), Some('C'));
    }

    #[test]
    fn test_find_index() {
        assert_eq!(find_index_for_label('B'), Some(0));
        assert_eq!(find_index_for_label('C'), Some(1));
        assert_eq!(find_index_for_label('A'), None); // excluded
        assert_eq!(find_index_for_label('F'), None); // excluded
    }
}
