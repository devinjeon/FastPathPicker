/// Scrollbar state for the file list display.
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
    pub start_row: usize,
    pub end_row: usize,
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
    pub fn calculate(&self, scroll_offset: usize) -> Option<ScrollBarRange> {
        if !self.active || self.total == 0 {
            return None;
        }

        let bar_height = (self.viewport_height * self.viewport_height)
            .checked_div(self.total)
            .unwrap_or(1)
            .max(1);

        let scrollable = self.total.saturating_sub(self.viewport_height);
        let bar_start = if scrollable > 0 {
            (scroll_offset * (self.viewport_height - bar_height)) / scrollable
        } else {
            0
        };

        Some(ScrollBarRange {
            start_row: bar_start,
            end_row: (bar_start + bar_height).min(self.viewport_height),
        })
    }
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
        assert_eq!(range.start_row, 0);
    }
}
