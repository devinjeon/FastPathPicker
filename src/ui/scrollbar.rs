/// Scrollbar state for the file list display.
/// Matches Python PathPicker's ScrollBar class rendering style.
#[derive(Debug)]
pub struct ScrollBar {
    /// Total number of items
    total: usize,
    /// Full screen height (not viewport)
    screen_height: usize,
    /// Whether the scrollbar is needed
    active: bool,
}

/// Result of scrollbar calculation: which rows should show the scrollbar indicator.
pub struct ScrollBarRange {
    /// Row where the box starts (/-\ top), screen-relative
    pub box_start: usize,
    /// Row where the box ends (\-/ bottom), screen-relative
    pub box_end: usize,
    /// Screen height for cap rendering
    pub screen_height: usize,
}

impl ScrollBar {
    pub fn new(total: usize, screen_height: usize) -> Self {
        Self {
            total,
            screen_height,
            active: total > screen_height,
        }
    }

    pub fn is_active(&self) -> bool {
        self.active
    }

    /// Calculate the scrollbar position for a given scroll offset.
    /// Matches Python's calc_box_fractions + output_box exactly:
    /// - frac_displayed = min(1.0, max_y / num_lines)  (full screen height)
    /// - box_start_fraction = scroll_offset / num_lines
    /// - top_y = max_y - 2, min_y = CHROME_MIN_Y + 1 = 1
    /// - diff = top_y - min_y
    /// - box_start_y = int(diff * box_start_fraction) + min_y
    pub fn calculate(&self, scroll_offset: usize) -> Option<ScrollBarRange> {
        if !self.active || self.total == 0 {
            return None;
        }

        let max_y = self.screen_height;
        let frac_displayed = (max_y as f64 / self.total as f64).min(1.0);
        let box_start_fraction = scroll_offset as f64 / self.total as f64;
        let box_stop_fraction = box_start_fraction + frac_displayed;

        // Python: top_y = max_y - 2, min_y = CHROME_MIN_Y + 1 = 1
        let min_y: usize = 1;
        let top_y = max_y.saturating_sub(2);
        let diff = top_y.saturating_sub(min_y);

        let box_start = (diff as f64 * box_start_fraction) as usize + min_y;
        let box_end = (diff as f64 * box_stop_fraction) as usize + min_y;

        Some(ScrollBarRange {
            box_start,
            box_end: box_end.min(top_y),
            screen_height: max_y,
        })
    }
}

/// Render a scrollbar row at a screen position. Returns a 3-character string.
/// Matches Python's ASCII art style:
/// - Caps at row 0 and row screen_height-1: "==="
/// - Box top: "/-\"
/// - Box body: "|-|"
/// - Box bottom: "\-/"
/// - Track: " . "
pub fn render_scrollbar_row(screen_row: usize, range: &ScrollBarRange) -> &'static str {
    // Caps at first and last screen row
    if screen_row == 0 || screen_row == range.screen_height - 1 {
        return "===";
    }

    // Box rendering (when start == end, bottom wins — Python draws /-\ first, then \-/ overwrites)
    if screen_row == range.box_end && screen_row >= range.box_start {
        return "\\-/";
    }
    if screen_row == range.box_start {
        return "/-\\";
    }
    if screen_row > range.box_start && screen_row < range.box_end {
        return "|-|";
    }

    // Track
    " . "
}

#[cfg(test)]
#[path = "scrollbar_tests.rs"]
mod tests;
