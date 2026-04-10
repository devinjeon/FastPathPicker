use super::*;

#[test]
fn test_inactive_when_small() {
    let sb = ScrollBar::new(10, 20);
    assert!(!sb.is_active());
}

#[test]
fn test_active_when_large() {
    let sb = ScrollBar::new(100, 20);
    assert!(sb.is_active());
}

#[test]
fn test_calculate_at_top() {
    let sb = ScrollBar::new(100, 20);
    let range = sb.calculate(0).unwrap();
    assert!(range.box_start >= 1); // after top cap
}

#[test]
fn test_render_caps() {
    let range = ScrollBarRange {
        box_start: 3,
        box_end: 6,
        screen_height: 30,
    };
    assert_eq!(render_scrollbar_row(0, &range), "===");
    assert_eq!(render_scrollbar_row(29, &range), "===");
}

#[test]
fn test_render_box() {
    let range = ScrollBarRange {
        box_start: 3,
        box_end: 6,
        screen_height: 30,
    };
    assert_eq!(render_scrollbar_row(3, &range), "/-\\");
    assert_eq!(render_scrollbar_row(4, &range), "|-|");
    assert_eq!(render_scrollbar_row(5, &range), "|-|");
    assert_eq!(render_scrollbar_row(6, &range), "\\-/");
}

#[test]
fn test_render_track() {
    let range = ScrollBarRange {
        box_start: 3,
        box_end: 6,
        screen_height: 30,
    };
    assert_eq!(render_scrollbar_row(2, &range), " . ");
    assert_eq!(render_scrollbar_row(7, &range), " . ");
}
