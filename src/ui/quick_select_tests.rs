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
