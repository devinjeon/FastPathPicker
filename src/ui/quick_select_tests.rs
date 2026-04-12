use super::*;

#[test]
fn test_get_label() {
    assert_eq!(get_label(0), Some('B'));
    assert_eq!(get_label(1), Some('C'));
}

#[test]
fn test_get_label_last_index() {
    // The last valid label index
    let last_idx = QUICK_SELECT_LABELS.len() - 1;
    let last_char = QUICK_SELECT_LABELS.chars().last().unwrap();
    assert_eq!(get_label(last_idx), Some(last_char));
}

#[test]
fn test_get_label_out_of_range() {
    // One past the end should return None
    assert_eq!(get_label(QUICK_SELECT_LABELS.len()), None);
    // Far out of range
    assert_eq!(get_label(9999), None);
}

#[test]
fn test_find_index_exact() {
    assert_eq!(find_index_for_label_exact('B'), Some(0));
    assert_eq!(find_index_for_label_exact('C'), Some(1));
    assert_eq!(find_index_for_label_exact('A'), None); // excluded
    assert_eq!(find_index_for_label_exact('F'), None); // excluded
}

#[test]
fn test_find_index_exact_special_chars() {
    // Test exact matching for special characters in the label string
    assert!(find_index_for_label_exact('~').is_some());
    assert!(find_index_for_label_exact('!').is_some());
    assert!(find_index_for_label_exact('\'').is_some());
}

#[test]
fn test_find_index_exact_not_found() {
    // Characters not in the label string
    assert_eq!(find_index_for_label_exact('a'), None); // lowercase not in labels
    assert_eq!(find_index_for_label_exact('A'), None); // excluded
    assert_eq!(find_index_for_label_exact('F'), None); // excluded
    assert_eq!(find_index_for_label_exact('\n'), None);
}

#[test]
fn test_labels_count() {
    // Verify the expected number of labels
    assert_eq!(
        QUICK_SELECT_LABELS.len(),
        QUICK_SELECT_LABELS.chars().count(),
        "All labels should be ASCII (single byte)"
    );
}
