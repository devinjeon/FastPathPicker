/// Scrollbar state for the file list display.
/// Matches Python PathPicker's ScrollBar class rendering style.
#[derive(Debug)]
pub struct ScrollBar {
    /// Total number of items
    total: usize,
    /// Number of visible items
    viewport_height: usize,
    /// Whether the scrollbar is needed
    active: bool,
}

/// Result of scrollbar calculation: which rows should show the scrollbar indicator.
pub struct ScrollBarRange {
    /// Row where the box starts (/-\ top)
    pub box_start: usize,
    /// Row where the box ends (\-/ bottom)
    pub box_end: usize,
    /// Total viewport height for cap rendering
    pub viewport: usize,
}

impl ScrollBar {
    pub fn new(total: usize, viewport_height: usize) -> Self {
        Self {
            total,
            viewport_height,
            active: total > viewport_height,
        }
    }

    pub fn is_active(&self) -> bool {
        self.active
    }

    /// Calculate the scrollbar position for a given scroll offset.
    /// Returns box start/end rows within the viewport, matching Python's
    /// fraction-based calculation.
    pub fn calculate(&self, scroll_offset: usize) -> Option<ScrollBarRange> {
        if !self.active || self.total == 0 {
            return None;
        }

        // Python: frac_displayed = min(1.0, max_y / float(num_lines))
        // box_start_fraction = -scroll_offset / float(num_lines)
        // box_stop_fraction = box_start_fraction + frac_displayed
        let frac_displayed = (self.viewport_height as f64 / self.total as f64).min(1.0);
        let box_start_fraction = scroll_offset as f64 / self.total as f64;
        let box_stop_fraction = box_start_fraction + frac_displayed;

        // Python uses diff = top_y - min_y where top_y = max_y - 2
        // We simplify: the usable range is viewport_height - 2 (caps at top/bottom)
        let usable = self.viewport_height.saturating_sub(2);
        let box_start = (usable as f64 * box_start_fraction) as usize + 1; // +1 for top cap
        let box_end = (usable as f64 * box_stop_fraction) as usize + 1;

        Some(ScrollBarRange {
            box_start,
            box_end: box_end.min(self.viewport_height.saturating_sub(1)),
            viewport: self.viewport_height,
        })
    }
}

/// Render a scrollbar row. Returns the 4-5 character string for this row.
/// Matches Python's ASCII art style:
/// - Row 0 and last row: "=== " (caps)
/// - Box top: "/-\\ "
/// - Box body: "|-| "
/// - Box bottom: "\\-/ "
/// - Track: " .  "
/// - Column 4: " " (border)
pub fn render_scrollbar_row(row: usize, range: &ScrollBarRange) -> &'static str {
    let last_row = range.viewport.saturating_sub(1);

    // Caps at top and bottom
    if row == 0 || row == last_row {
        return "=== ";
    }

    // Box rendering
    if row == range.box_start {
        return "/-\\ ";
    }
    if row == range.box_end {
        return "\\-/ ";
    }
    if row > range.box_start && row < range.box_end {
        return "|-| ";
    }

    // Track
    " .  "
}

#[cfg(test)]
mod tests {
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
            viewport: 20,
        };
        assert_eq!(render_scrollbar_row(0, &range), "=== ");
        assert_eq!(render_scrollbar_row(19, &range), "=== ");
    }

    #[test]
    fn test_render_box() {
        let range = ScrollBarRange {
            box_start: 3,
            box_end: 6,
            viewport: 20,
        };
        assert_eq!(render_scrollbar_row(3, &range), "/-\\ ");
        assert_eq!(render_scrollbar_row(4, &range), "|-| ");
        assert_eq!(render_scrollbar_row(5, &range), "|-| ");
        assert_eq!(render_scrollbar_row(6, &range), "\\-/ ");
    }

    #[test]
    fn test_render_track() {
        let range = ScrollBarRange {
            box_start: 3,
            box_end: 6,
            viewport: 20,
        };
        assert_eq!(render_scrollbar_row(2, &range), " .  ");
        assert_eq!(render_scrollbar_row(7, &range), " .  ");
    }
}
