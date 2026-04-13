use std::collections::VecDeque;
use std::io::{self, BufWriter, Write};
use std::time::Duration;

use anyhow::Result;
use crossterm::{
    cursor,
    event::{self, Event, KeyCode, KeyEvent, KeyModifiers},
    execute, queue,
    style::{self, Attribute, Color, SetAttribute, SetBackgroundColor, SetForegroundColor},
    terminal::{self, ClearType},
};

use crate::keybindings::{self, KeyBinding};
use crate::line::{Line, LineMatch};
use crate::output;
use crate::state;
use crate::ui::chrome::Chrome;
use crate::ui::quick_select;
use crate::ui::scrollbar::{self, ScrollBar};

/// Modes the controller can be in.
#[derive(Debug, PartialEq)]
enum Mode {
    /// Normal navigation and selection mode
    Normal,
    /// Command input mode
    Command,
    /// Quick-select mode with labels
    QuickSelect,
    /// Showing preset command warning overlay
    Warning,
}

/// Result of processing a single event in the event loop.
///
/// Transport errors (e.g., `event::read` failure) propagate via the outer `Result`
/// of `process_event()`. Application-level exit results (e.g., from `execute_selection`)
/// are wrapped in `Exit`.
#[must_use]
enum LoopAction {
    /// Continue the event loop.
    Continue,
    /// Exit the event loop with the given result.
    /// The bool indicates whether a script should be executed (false = silent quit).
    Exit(Result<bool>),
}

/// Bundles the per-render parameters shared across content line rendering calls,
/// replacing multiple individual arguments with a single context struct.
struct RenderContext<'a> {
    chrome: &'a Chrome,
    has_scrollbar: bool,
    in_xmode: bool,
    text_width: usize,
    sb_range: &'a Option<scrollbar::ScrollBarRange>,
    hovered_line_idx: Option<usize>,
    use_space_padding: bool,
    padding_cache: &'a str,
}

/// Main UI controller. Manages the interactive selection interface.
pub struct Controller {
    lines: Vec<Line>,
    match_indices: Vec<usize>,
    hover_index: usize,
    scroll_offset: usize,
    mode: Mode,
    command_buffer: String,
    preset_command: Option<String>,
    execute_keys_queue: VecDeque<KeyEvent>,
    dirty: bool,
    /// Line indices that need re-rendering (dirty line tracking).
    /// Accumulated across coalesced events. Only used for partial redraw when
    /// `partial_redraw_ok` is true.
    dirty_lines: Vec<usize>,
    /// True when all pending changes are pure hover moves (safe for partial redraw).
    /// Set to false by any action requiring full redraw (selection, mode, scroll, resize).
    partial_redraw_ok: bool,
    custom_bindings: Vec<KeyBinding>,
    all_input: bool,
    show_description: bool,
    /// Override terminal size for testing. None = use terminal::size().
    viewport_size: Option<(u16, u16)>,
    /// Cached terminal size. Updated on resize events to avoid repeated ioctl calls.
    cached_size: (u16, u16),
}

impl Controller {
    pub fn new(
        lines: Vec<Line>,
        match_indices: Vec<usize>,
        preset_command: Option<String>,
        initial_select_all: bool,
        execute_keys: Option<String>,
        all_input: bool,
    ) -> Self {
        let keys_queue = execute_keys
            .as_deref()
            .map(execute_keys_from_str)
            .unwrap_or_default();

        let mut ctrl = Self {
            lines,
            match_indices,
            hover_index: 0,
            scroll_offset: 0,
            mode: Mode::Normal,
            command_buffer: String::new(),
            preset_command,
            execute_keys_queue: VecDeque::from(keys_queue),
            dirty: true,
            dirty_lines: Vec::new(),
            partial_redraw_ok: false,
            custom_bindings: keybindings::read_key_bindings(),
            all_input,
            show_description: false,
            viewport_size: None,
            cached_size: terminal::size().unwrap_or((80, 24)),
        };

        if initial_select_all {
            ctrl.toggle_select_all();
        }

        // Python loads previous selection on startup from .selection.pickle
        // (choose.py get_line_objs -> set_selections_from_pickle).
        ctrl.load_previous_selection();

        ctrl
    }

    /// Set viewport size override (for testing).
    pub fn set_viewport_size(&mut self, width: u16, height: u16) {
        self.viewport_size = Some((width, height));
    }

    /// Get the effective terminal size, using override or cache.
    fn get_size(&self) -> (u16, u16) {
        self.viewport_size.unwrap_or(self.cached_size)
    }

    /// Refresh cached terminal size (called on resize events).
    fn refresh_size(&mut self) {
        self.cached_size = terminal::size().unwrap_or((80, 24));
    }

    /// Run the interactive UI loop. Returns when the user makes a selection or quits.
    /// Returns `Ok(true)` if the user performed an action (quit/execute/no-matches),
    /// `Ok(false)` if the user pressed Ctrl-C (silent quit, no script should run).
    pub fn run(&mut self) -> Result<bool> {
        if self.match_indices.is_empty() {
            output::output_no_matches()?;
            return Ok(true);
        }

        let mut stdout = io::stdout();
        terminal::enable_raw_mode()?;
        execute!(stdout, terminal::EnterAlternateScreen, cursor::Hide,)?;

        // Wrap stdout in BufWriter to batch terminal writes, reducing syscalls.
        // 16KB buffer is large enough to hold a full screen render in most cases.
        // We explicitly flush and drop the BufWriter before cleanup to ensure no
        // stale data is written after terminal restoration.
        let result = {
            let mut buf_stdout = BufWriter::with_capacity(16 * 1024, &mut stdout);
            let r = self.event_loop(&mut buf_stdout);
            // Flush any remaining buffered data before we leave the alternate screen.
            let _ = buf_stdout.flush();
            // Drop the BufWriter so `stdout` is no longer borrowed.
            drop(buf_stdout);
            r
        };

        execute!(stdout, cursor::Show, terminal::LeaveAlternateScreen,)?;
        terminal::disable_raw_mode()?;

        result
    }

    fn event_loop(&mut self, stdout: &mut impl Write) -> Result<bool> {
        // Process any queued execute-keys first
        while let Some(key) = self.execute_keys_queue.pop_front() {
            match self.handle_key(key)? {
                Action::Continue => {
                    self.dirty = true;
                }
                Action::Quit => {
                    output::output_nothing()?;
                    self.save_selection()?;
                    return Ok(true);
                }
                Action::SilentQuit => {
                    return Ok(false);
                }
                Action::Execute => {
                    self.execute_selection()?;
                    return Ok(true);
                }
            }
        }

        loop {
            if self.dirty {
                let size = self.get_size();
                if self.partial_redraw_ok && !self.dirty_lines.is_empty() {
                    // Partial redraw: only re-render dirty lines (no flicker).
                    // Dedup here at the caller so render_dirty_lines receives a
                    // clean list and doesn't render the same line twice.
                    let mut dirty = std::mem::take(&mut self.dirty_lines);
                    dirty.sort_unstable();
                    dirty.dedup();
                    self.render_dirty_lines(stdout, size, &dirty)?;
                } else {
                    self.render_to(stdout, size)?;
                }
                self.dirty = false;
                self.partial_redraw_ok = true; // reset for next event batch
                self.dirty_lines.clear();
            }

            // Block until the first event arrives (no busy-spin, no artificial delay).
            // Once we have one event, immediately drain any queued events below.
            if event::poll(Duration::from_secs(1))? {
                if let LoopAction::Exit(result) = self.process_event()? {
                    return result;
                }

                // Drain pending events to coalesce rapid key presses into a single
                // render. poll(ZERO) is non-blocking so this adds negligible latency.
                // Capped at 64 to guard against runaway event streams.
                for _ in 0..64 {
                    if !event::poll(Duration::ZERO)? {
                        break;
                    }
                    if let LoopAction::Exit(result) = self.process_event()? {
                        return result;
                    }
                }
            }
        }
    }

    /// Process a single event from the crossterm event queue.
    fn process_event(&mut self) -> Result<LoopAction> {
        match event::read()? {
            Event::Key(key) => {
                // Remember dirty_lines count before handling key.
                // If move_hover adds entries, this was a pure hover move.
                // Otherwise, it was a different action needing full redraw.
                let dirty_before = self.dirty_lines.len();
                match self.handle_key(key)? {
                    Action::Continue => {}
                    Action::Quit => {
                        output::output_nothing()?;
                        self.save_selection()?;
                        return Ok(LoopAction::Exit(Ok(true)));
                    }
                    Action::SilentQuit => {
                        return Ok(LoopAction::Exit(Ok(false)));
                    }
                    Action::Execute => {
                        self.execute_selection()?;
                        return Ok(LoopAction::Exit(Ok(true)));
                    }
                }
                self.dirty = true;
                // If handle_key didn't add dirty_lines, it wasn't a pure hover
                // move — force full redraw by invalidating partial_redraw_ok.
                if self.dirty_lines.len() == dirty_before {
                    self.partial_redraw_ok = false;
                }
            }
            Event::Resize(_, _) => {
                self.refresh_size();
                self.dirty = true;
                self.partial_redraw_ok = false;
            }
            _ => {}
        }
        Ok(LoopAction::Continue)
    }

    pub fn handle_key(&mut self, key: KeyEvent) -> Result<Action> {
        // Ctrl-C: silent exit matching Python's signal handler (sys.exit(0))
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            return Ok(Action::SilentQuit);
        }

        match self.mode {
            Mode::Command => self.handle_command_key(key),
            Mode::QuickSelect => self.handle_xmode_key(key),
            Mode::Warning => {
                // Any key dismisses the warning
                self.mode = Mode::Normal;
                Ok(Action::Continue)
            }
            Mode::Normal => self.handle_normal_key(key),
        }
    }

    fn handle_normal_key(&mut self, key: KeyEvent) -> Result<Action> {
        // Python's process_input: built-in if/elif chain runs first, then custom
        // binding loop runs unconditionally. Custom bindings only matter if the
        // program hasn't already exited (Quit/Execute exit before the loop).
        let action = match key.code {
            KeyCode::Char('q') => Action::Quit,
            KeyCode::Char('j') | KeyCode::Down => {
                self.move_hover(1);
                Action::Continue
            }
            KeyCode::Char('k') | KeyCode::Up => {
                self.move_hover(-1);
                Action::Continue
            }
            KeyCode::Char(' ') | KeyCode::PageDown => {
                self.page_down();
                Action::Continue
            }
            KeyCode::Char('b') | KeyCode::PageUp => {
                self.page_up();
                Action::Continue
            }
            KeyCode::Char('g') | KeyCode::Home => {
                self.jump_to_first();
                Action::Continue
            }
            KeyCode::Char('G') | KeyCode::End => {
                self.jump_to_last();
                Action::Continue
            }
            KeyCode::Char('f') => {
                self.toggle_current_selection();
                Action::Continue
            }
            KeyCode::Char('F') => {
                self.toggle_current_selection();
                self.move_hover(1);
                Action::Continue
            }
            KeyCode::Char('A') => {
                self.toggle_select_all();
                Action::Continue
            }
            KeyCode::Char('c') => {
                if self.preset_command.is_some() {
                    self.mode = Mode::Warning;
                } else {
                    self.mode = Mode::Command;
                }
                Action::Continue
            }
            KeyCode::Char('x') => {
                self.mode = Mode::QuickSelect;
                Action::Continue
            }
            KeyCode::Char('d') => {
                self.show_description = true;
                Action::Continue
            }
            KeyCode::Enter => {
                if self.all_input && self.preset_command.is_none() {
                    Action::Continue
                } else {
                    Action::Execute
                }
            }
            _ => Action::Continue,
        };

        // Python: custom bindings fire AFTER built-in keys unconditionally.
        // In Python, Quit/Execute exit the process before the loop runs,
        // so custom bindings only effectively fire on Continue actions.
        if matches!(action, Action::Continue) {
            if let KeyCode::Char(ch) = key.code {
                if let Some(cmd) = self
                    .custom_bindings
                    .iter()
                    .find(|b| b.key.len() == 1 && b.key.starts_with(ch))
                    .map(|b| b.command.clone())
                {
                    return self.execute_custom_binding(&cmd);
                }
            }
        }

        Ok(action)
    }

    fn handle_command_key(&mut self, key: KeyEvent) -> Result<Action> {
        // Python: curses getstr() handles input as a complete line.
        // Empty Enter returns to selection mode. Esc is an improvement
        // (not in Python) but harmless for backward compat since Python
        // doesn't handle Esc in command mode at all.
        match key.code {
            KeyCode::Enter => {
                if self.command_buffer.is_empty() {
                    // Python: empty input returns to SELECT_MODE
                    self.mode = Mode::Normal;
                    Ok(Action::Continue)
                } else {
                    Ok(Action::Execute)
                }
            }
            KeyCode::Esc => {
                self.command_buffer.clear();
                self.mode = Mode::Normal;
                Ok(Action::Continue)
            }
            KeyCode::Backspace => {
                // Python: backspace is handled by curses natively within getstr().
                // It does NOT exit command mode when buffer becomes empty.
                self.command_buffer.pop();
                Ok(Action::Continue)
            }
            KeyCode::Char(ch) => {
                self.command_buffer.push(ch);
                Ok(Action::Continue)
            }
            _ => Ok(Action::Continue),
        }
    }

    fn handle_xmode_key(&mut self, key: KeyEvent) -> Result<Action> {
        // Python processes keys in a flat if-elif chain where navigation keys
        // are checked BEFORE the X_MODE label check. So in X_MODE, navigation
        // keys (j/k/SPACE/b/g/d/f/F/c/ENTER/q) all work normally.
        // Only keys that don't match any built-in AND are in LABELS trigger
        // quick-select. 'G' and 'A' are special: G is skipped in X_MODE
        // (but END still works), A is not in LABELS so it's ignored.
        match key.code {
            KeyCode::Char('x') | KeyCode::Esc => {
                self.mode = Mode::Normal;
                Ok(Action::Continue)
            }
            // Navigation keys work in X_MODE (same as Python)
            KeyCode::Char('j') | KeyCode::Down => {
                self.move_hover(1);
                Ok(Action::Continue)
            }
            KeyCode::Char('k') | KeyCode::Up => {
                self.move_hover(-1);
                Ok(Action::Continue)
            }
            KeyCode::Char(' ') | KeyCode::PageDown => {
                self.page_down();
                Ok(Action::Continue)
            }
            KeyCode::Char('b') | KeyCode::PageUp => {
                self.page_up();
                Ok(Action::Continue)
            }
            KeyCode::Char('g') | KeyCode::Home => {
                self.jump_to_first();
                Ok(Action::Continue)
            }
            // Python: G in X_MODE is a label key (not jump-to-last).
            // END still works as jump-to-last in all modes.
            KeyCode::End => {
                self.jump_to_last();
                Ok(Action::Continue)
            }
            KeyCode::Char('d') => {
                self.show_description = true;
                Ok(Action::Continue)
            }
            KeyCode::Char('f') => {
                self.toggle_current_selection();
                Ok(Action::Continue)
            }
            KeyCode::Char('F') => {
                self.toggle_current_selection();
                self.move_hover(1);
                Ok(Action::Continue)
            }
            // Python: A is not in LABELS, and `elif key == "A" and not self.mode == X_MODE`
            // means A is ignored in X_MODE
            KeyCode::Char('A') => Ok(Action::Continue),
            KeyCode::Char('c') => {
                if self.preset_command.is_some() {
                    self.mode = Mode::Warning;
                } else {
                    self.mode = Mode::Command;
                }
                Ok(Action::Continue)
            }
            KeyCode::Enter => {
                if self.all_input && self.preset_command.is_none() {
                    Ok(Action::Continue)
                } else {
                    Ok(Action::Execute)
                }
            }
            KeyCode::Char('q') => Ok(Action::Quit),
            // Only after all built-in keys: try quick-select label
            // Python only matches exact uppercase LABELS (no case conversion)
            KeyCode::Char(ch) if quick_select::QUICK_SELECT_LABELS.contains(ch) => {
                if let Some(row_idx) = quick_select::find_index_for_label_exact(ch) {
                    let line_idx = self.scroll_offset + row_idx;
                    if line_idx < self.lines.len() {
                        if let Some(m) = self.lines[line_idx].as_match_mut() {
                            m.toggle_select();
                            if let Some(match_idx) =
                                self.match_indices.iter().position(|&i| i == line_idx)
                            {
                                self.hover_index = match_idx;
                            }
                        }
                    }
                }
                Ok(Action::Continue)
            }
            _ => {
                // Custom bindings fire in all modes including X_MODE (like Python)
                if let KeyCode::Char(ch) = key.code {
                    if let Some(cmd) = self
                        .custom_bindings
                        .iter()
                        .find(|b| b.key.len() == 1 && b.key.starts_with(ch))
                        .map(|b| b.command.clone())
                    {
                        return self.execute_custom_binding(&cmd);
                    }
                }
                Ok(Action::Continue)
            }
        }
    }

    fn execute_custom_binding(&mut self, command: &str) -> Result<Action> {
        self.command_buffer.clear();
        self.command_buffer.push_str(command);
        Ok(Action::Execute)
    }

    // --- Navigation ---

    fn move_hover(&mut self, delta: isize) {
        if self.match_indices.is_empty() {
            return;
        }
        let old_hover = self.hover_index;
        let old_scroll = self.scroll_offset;

        let len = self.match_indices.len() as isize;
        let new_idx = ((self.hover_index as isize + delta) % len + len) % len;
        self.hover_index = new_idx as usize;
        self.show_description = false;
        self.update_scroll_offset();

        if self.scroll_offset == old_scroll {
            // No scroll: only redraw the old and new hover lines.
            self.dirty_lines.push(self.match_indices[old_hover]);
            self.dirty_lines.push(self.match_indices[self.hover_index]);
        } else {
            // Scroll changed: mark ALL visible lines as dirty for partial redraw.
            // This uses space-padding (no ClearType) so we avoid flicker, while
            // still updating every line that shifted. Much smoother than a full
            // clear-then-redraw cycle.
            let (width, height) = self.get_size();
            let chrome = Chrome::new(width, height);
            let viewport_end =
                (self.scroll_offset + chrome.content_height as usize).min(self.lines.len());
            for line_idx in self.scroll_offset..viewport_end {
                self.dirty_lines.push(line_idx);
            }
        }
    }

    /// Page down by half the viewport height.
    /// Does NOT add dirty_lines — `process_event` detects this and triggers full redraw.
    fn page_down(&mut self) {
        if self.match_indices.is_empty() {
            return;
        }
        let (width, height) = self.get_size();
        let chrome = Chrome::new(width, height);
        let page = (chrome.content_height as usize) / 2;
        let len = self.match_indices.len() as isize;
        let new_idx = ((self.hover_index as isize + page as isize) % len + len) % len;
        self.hover_index = new_idx as usize;
        self.show_description = false;
        self.update_scroll_offset();
    }

    /// Page up by half the viewport height.
    /// Does NOT add dirty_lines — `process_event` detects this and triggers full redraw.
    fn page_up(&mut self) {
        if self.match_indices.is_empty() {
            return;
        }
        let (width, height) = self.get_size();
        let chrome = Chrome::new(width, height);
        let page = (chrome.content_height as usize) / 2;
        let len = self.match_indices.len() as isize;
        let new_idx = ((self.hover_index as isize - page as isize) % len + len) % len;
        self.hover_index = new_idx as usize;
        self.show_description = false;
        self.update_scroll_offset();
    }

    /// Jump to the first match. Intentionally does NOT add dirty_lines — this
    /// causes `process_event` to detect no new dirty entries and set
    /// `partial_redraw_ok = false`, triggering a full redraw via `render_to`.
    fn jump_to_first(&mut self) {
        if self.match_indices.is_empty() {
            return;
        }
        self.hover_index = 0;
        self.show_description = false;
        self.update_scroll_offset();
    }

    /// Jump to the last match. See `jump_to_first` for why dirty_lines is not modified.
    fn jump_to_last(&mut self) {
        if self.match_indices.is_empty() {
            return;
        }
        self.hover_index = self.match_indices.len() - 1;
        self.show_description = false;
        self.update_scroll_offset();
    }

    /// Scroll offset update matching Python's `update_scroll_offset` exactly.
    /// Centers the viewport on the hovered line, but only repositions when
    /// the current offset differs from the desired position by more than
    /// half_height/2 (the "leeway" check), or when the hovered line would
    /// be off-screen.
    fn update_scroll_offset(&mut self) {
        let (width, height) = self.get_size();
        let chrome = Chrome::new(width, height);
        let window_height = chrome.content_height as usize;
        if window_height == 0 {
            return;
        }

        // Python 3's round() uses banker's rounding (round half to even).
        // Rust's f64::round() always rounds half away from zero.
        // Use round_ties_even() to match Python's behavior exactly.
        let half_height = (window_height as f64 / 2.0).round_ties_even() as usize;
        let hovered_line_idx = self.match_indices[self.hover_index];

        // Python: desired_top_row = hovered.get_screen_index() - half_height
        // Python uses negative scroll_offset; we use positive scroll_offset
        // (which equals the desired top row).
        let desired_top = hovered_line_idx.saturating_sub(half_height);

        let old_offset = self.scroll_offset;

        // Python leeway: only reposition if the difference exceeds half_height/2
        // or if the hovered line would be above the viewport.
        let diff = desired_top.abs_diff(old_offset);

        // Python: `self.hover_index + old_offset < 0` where old_offset is negative.
        // In Rust terms: hover_index (match index) < scroll_offset (positive).
        // This is a heuristic that detects when the viewport has scrolled far
        // past the current match position.
        let python_guard = (self.hover_index as isize) < (old_offset as isize);
        // Also ensure the hovered line is actually visible in the viewport.
        let hovered_offscreen =
            hovered_line_idx < old_offset || hovered_line_idx >= old_offset + window_height;

        if diff > half_height / 2 || python_guard || hovered_offscreen {
            self.scroll_offset = desired_top;
        }
    }

    // --- Selection ---

    fn toggle_current_selection(&mut self) {
        if let Some(&line_idx) = self.match_indices.get(self.hover_index) {
            if let Some(m) = self.lines[line_idx].as_match_mut() {
                m.toggle_select();
            }
        }
    }

    fn toggle_select_all(&mut self) {
        // Two-pass approach to work around the borrow checker:
        // First pass (immutable): collect indices of the first occurrence of each unique path.
        // Uses a set of line indices (usize) instead of cloning path strings.
        let mut seen_paths: std::collections::HashSet<&str> = std::collections::HashSet::new();
        let toggle_indices: Vec<usize> = self
            .match_indices
            .iter()
            .filter(|&&idx| {
                self.lines[idx]
                    .as_match()
                    .is_some_and(|m| seen_paths.insert(&m.path))
            })
            .copied()
            .collect();
        // Second pass (mutable): toggle the first occurrence of each unique path.
        for idx in toggle_indices {
            if let Some(m) = self.lines[idx].as_match_mut() {
                m.selected = !m.selected;
            }
        }
    }

    // --- Execution ---

    fn get_selected_matches(&self) -> Vec<LineMatch> {
        let selected: Vec<LineMatch> = self
            .match_indices
            .iter()
            .filter_map(|&idx| self.lines[idx].as_match().filter(|m| m.selected).cloned())
            .collect();

        if selected.is_empty() {
            // Use the hovered item
            if let Some(&idx) = self.match_indices.get(self.hover_index) {
                if let Some(m) = self.lines[idx].as_match() {
                    return vec![m.clone()];
                }
            }
            Vec::new()
        } else {
            selected
        }
    }

    fn execute_selection(&self) -> Result<()> {
        let matches = self.get_selected_matches();
        if matches.is_empty() {
            output::output_nothing()?;
            return Ok(());
        }

        // Python saves selection on Enter (get_paths_to_use → output_selection)
        self.save_selection()?;

        let command = self
            .preset_command
            .as_deref()
            .unwrap_or(&self.command_buffer);

        output::exec_composed_command(command, &matches)
    }

    fn save_selection(&self) -> Result<()> {
        let indices: Vec<usize> = self
            .match_indices
            .iter()
            .filter_map(|&idx| {
                self.lines[idx]
                    .as_match()
                    .filter(|m| m.selected)
                    .map(|_| idx)
            })
            .collect();
        state::save_selection(&state::SelectionState {
            selected_indices: indices,
        })
    }

    /// Load previous selection from disk (like Python's set_selections_from_pickle).
    fn load_previous_selection(&mut self) {
        if let Ok(sel) = state::load_selection() {
            for idx in sel.selected_indices {
                if idx < self.lines.len() {
                    if let Some(m) = self.lines[idx].as_match_mut() {
                        m.set_select(true);
                    }
                }
            }
        }
    }

    // --- Rendering ---

    /// Partial redraw: re-render only the specified dirty lines.
    /// Like Python's process_dirty() with dirty_indexes — only redraws lines whose
    /// hover/selection state changed, avoiding full-screen redraw on j/k navigation.
    /// When many lines are dirty (e.g., after scrolling), this still avoids the
    /// flicker of ClearType::All by using space-padding on each line.
    fn render_dirty_lines(
        &self,
        writer: &mut impl Write,
        (width, height): (u16, u16),
        dirty_line_indices: &[usize],
    ) -> Result<()> {
        if height < 5 || width < 10 {
            return Ok(());
        }
        let chrome = Chrome::new(width, height);
        let scrollbar = ScrollBar::new(self.lines.len(), height as usize);
        let has_scrollbar = scrollbar.is_active();
        let in_xmode = self.mode == Mode::QuickSelect;
        let text_width = chrome.text_width(has_scrollbar, in_xmode) as usize;
        let sb_range = scrollbar.calculate(self.scroll_offset);
        let hovered_line_idx = self.match_indices.get(self.hover_index).copied();
        let viewport_end =
            (self.scroll_offset + chrome.content_height as usize).min(self.lines.len());

        // Track whether we redrew a significant portion (scroll happened).
        // If so, also update the scrollbar on empty rows.
        let content_rows = viewport_end - self.scroll_offset;
        // dirty_line_indices is already deduped by the caller (event_loop).
        let is_full_viewport_dirty = dirty_line_indices.len() >= content_rows.max(1);

        // Pre-allocate padding buffer once for all lines in this render pass.
        let padding_cache = " ".repeat(text_width);

        let ctx = RenderContext {
            chrome: &chrome,
            has_scrollbar,
            in_xmode,
            text_width,
            sb_range: &sb_range,
            hovered_line_idx,
            use_space_padding: true, // space-padding for partial redraws (no flicker)
            padding_cache: &padding_cache,
        };

        for &line_idx in dirty_line_indices {
            // Skip lines outside the visible viewport
            if line_idx < self.scroll_offset || line_idx >= viewport_end {
                continue;
            }
            let row = line_idx - self.scroll_offset;
            self.render_content_line(writer, row, line_idx, &ctx)?;
        }

        // When the whole viewport scrolled, update scrollbar + empty rows.
        if is_full_viewport_dirty {
            for row in content_rows..height as usize {
                queue!(
                    writer,
                    cursor::MoveTo(0, row as u16),
                    terminal::Clear(ClearType::UntilNewLine)
                )?;
                if has_scrollbar {
                    if let Some(ref range) = sb_range {
                        let sb_str = scrollbar::render_scrollbar_row(row, range);
                        queue!(writer, style::Print(sb_str))?;
                    }
                    queue!(writer, cursor::MoveTo(4, row as u16), style::Print(" "))?;
                }
                if in_xmode && row < (height as usize).saturating_sub(1) {
                    if let Some(label) = quick_select::get_label(row) {
                        queue!(writer, cursor::MoveTo(1, row as u16), style::Print(label),)?;
                    }
                }
            }
        }

        // Only update the info area when something actually changed:
        // - Full viewport dirty (scroll happened, scrollbar position changed)
        // - Wide mode: always update because the sidebar border must be maintained
        //   and descriptions need to be cleared when show_description transitions
        //   from true to false. The BufWriter makes these extra writes negligible.
        // In narrow mode during simple hover, the usage text is static so
        // re-rendering it just causes unnecessary writes (and potential flicker
        // in SSH/tmux).
        if is_full_viewport_dirty || chrome.is_wide {
            self.render_info(writer, &chrome, height)?;
        }

        writer.flush()?;
        Ok(())
    }

    /// Render a single content line at the given row.
    /// Extracted to share rendering logic between full render and partial dirty-line render.
    /// When `use_space_padding` is true, stale content is overwritten with spaces instead
    /// of ClearType::UntilNewLine, preventing flicker during partial redraws.
    /// `padding_cache` is a pre-allocated spaces buffer (at least `text_width` long) to
    /// avoid per-line allocation when space-padding.
    fn render_content_line(
        &self,
        writer: &mut impl Write,
        row: usize,
        line_idx: usize,
        ctx: &RenderContext<'_>,
    ) -> Result<()> {
        let line = &self.lines[line_idx];
        let is_hovered = ctx.hovered_line_idx == Some(line_idx);
        let has_scrollbar = ctx.has_scrollbar;
        let in_xmode = ctx.in_xmode;
        let text_width = ctx.text_width;
        let chrome = ctx.chrome;
        let sb_range = ctx.sb_range;
        let use_space_padding = ctx.use_space_padding;
        let padding_cache = ctx.padding_cache;

        queue!(writer, cursor::MoveTo(0, row as u16))?;

        // Scrollbar
        let screen_row = row;
        if has_scrollbar {
            if let Some(ref range) = sb_range {
                let sb_str = scrollbar::render_scrollbar_row(screen_row, range);
                queue!(writer, style::Print(sb_str))?;
            }
            queue!(writer, cursor::MoveTo(4, row as u16), style::Print(" "))?;
        }

        // Quick-select labels — rendered at column 1 (matching Python) to leave a gap
        // between the label and any scrollbar at column 0.
        if in_xmode {
            if let Some(label) = quick_select::get_label(row) {
                queue!(writer, cursor::MoveTo(1, row as u16), style::Print(label),)?;
            }
            if !has_scrollbar {
                let content_x = chrome.content_start_x(has_scrollbar, in_xmode);
                queue!(writer, cursor::MoveTo(content_x, row as u16))?;
            }
        }

        // Line content — track printed columns for space-padding (no ClearType needed).
        let printed_cols = if let Some(m) = line.as_match() {
            self.render_match_line(writer, m, is_hovered, text_width)?
        } else {
            Self::render_simple_line(writer, line, text_width)?
        };

        if use_space_padding {
            // Pad remaining content area with spaces instead of ClearType::UntilNewLine.
            // This prevents flicker because the terminal never shows a cleared gap.
            let pad_count = text_width.saturating_sub(printed_cols);
            debug_assert!(
                pad_count <= padding_cache.len(),
                "pad_count ({pad_count}) exceeds padding_cache length ({})",
                padding_cache.len()
            );
            if pad_count > 0 {
                // Slice from pre-allocated padding buffer (no allocation per line).
                let end = pad_count.min(padding_cache.len());
                queue!(writer, style::Print(&padding_cache[..end]))?;
            }
            // In wide mode, re-draw the sidebar border on this row.
            if chrome.is_wide {
                queue!(
                    writer,
                    cursor::MoveTo(chrome.content_width, row as u16),
                    style::Print("|"),
                )?;
            }
        } else {
            // Full render: use ClearType::UntilNewLine for clean output.
            queue!(writer, terminal::Clear(ClearType::UntilNewLine))?;
        }
        Ok(())
    }

    /// Truncate the combined arrow+match text when the line exceeds `max_len`.
    ///
    /// Returns the (possibly truncated) combined string. Truncation uses the
    /// `|...|` decorator, splitting the text into front and back halves.
    fn truncate_match_text(
        combined: &str,
        arrow_len: usize,
        match_start: usize,
        max_len: usize,
    ) -> String {
        let combined_char_count = combined.chars().count();
        let important_len = match_start + combined_char_count;
        if important_len <= max_len {
            return combined.to_string();
        }

        let space_allowed = max_len
            .saturating_sub(TRUNCATE_DECORATOR.len())
            .saturating_sub(arrow_len)
            .saturating_sub(match_start);
        if space_allowed > 1 && combined_char_count > space_allowed {
            let mid = space_allowed / 2;
            let combined_chars: Vec<char> = combined.chars().collect();
            let total = combined_chars.len();
            let front = mid.min(total);
            let back = mid.min(total);
            let begin: String = combined_chars[..front].iter().collect();
            let end: String = combined_chars[total.saturating_sub(back)..]
                .iter()
                .collect();
            format!("{begin}{TRUNCATE_DECORATOR}{end}")
        } else {
            combined.to_string()
        }
    }

    /// Render a match line (before-segment, highlighted match, after-segment).
    ///
    /// Returns the number of visible columns printed.
    fn render_match_line(
        &self,
        writer: &mut impl Write,
        m: &LineMatch,
        is_hovered: bool,
        max_len: usize,
    ) -> Result<usize> {
        let plain = m.formatted_text.plain_text();
        let plain_len = plain.chars().count();
        let ms = m.match_start.min(plain_len);
        let me = m.match_end.min(plain_len);

        let (before_raw, rest_raw) = m.formatted_text.breakat(ms);
        // Split rest_raw at the match boundary without re-parsing into FormattedText.
        // breakat_raw operates directly on the raw string, avoiding a redundant ANSI parse.
        let match_len = me - ms;
        let (_matched_raw, after_raw) = crate::format::breakat_raw(&rest_raw, match_len);

        let before_plain: String = plain.chars().take(ms).collect();
        let matched_plain: String = plain.chars().skip(ms).take(me - ms).collect();
        let after_plain: String = plain.chars().skip(me).collect();

        let arrow = if m.selected { "|===>" } else { "" };

        // NOTE: We perform truncation on plain text here rather than using
        // FormattedText::raw_truncated_with_decorator because the matched
        // portion is rendered with crossterm's SetForegroundColor (not ANSI
        // codes embedded in the string). The three segments (before, match,
        // after) are styled and printed independently, so truncation must
        // operate on the decomposed plain-text pieces to correctly account
        // for the selection arrow prefix and per-segment column budgets.
        // raw_truncated_with_decorator works on a single contiguous
        // ANSI-bearing string and cannot handle this multi-segment layout.
        let combined = format!("{arrow}{matched_plain}");
        let truncated_combined = Self::truncate_match_text(&combined, arrow.len(), ms, max_len);

        let mut printed_cols: usize = 0;

        // Before-segment — use raw_truncate_str directly to avoid re-parsing ANSI
        let before_display = if m.formatted_text.has_ansi() {
            crate::format::raw_truncate_str(&before_raw, max_len)
        } else {
            before_plain.chars().take(max_len).collect::<String>()
        };
        let before_printed = if m.formatted_text.has_ansi() {
            crate::format::visible_char_count(&before_display)
        } else {
            before_display.chars().count()
        };
        queue!(writer, style::Print(&before_display))?;
        printed_cols += before_printed;
        if m.formatted_text.has_ansi() {
            queue!(writer, style::Print("\x1b[0m"))?;
        }

        // Match highlight style
        if is_hovered && m.selected {
            queue!(
                writer,
                SetBackgroundColor(Color::Red),
                SetForegroundColor(Color::White),
                SetAttribute(Attribute::Bold),
            )?;
        } else if is_hovered {
            queue!(
                writer,
                SetBackgroundColor(Color::Blue),
                SetForegroundColor(Color::White),
                SetAttribute(Attribute::Bold),
            )?;
        } else if m.selected {
            queue!(
                writer,
                SetBackgroundColor(Color::Green),
                SetForegroundColor(Color::White),
                SetAttribute(Attribute::Bold),
            )?;
        } else if !self.all_input {
            queue!(writer, SetAttribute(Attribute::Underlined))?;
        }

        // Match segment
        let remaining = max_len.saturating_sub(before_printed);
        let match_display: String = truncated_combined.chars().take(remaining).collect();
        let match_printed = match_display.chars().count();
        queue!(writer, style::Print(&match_display))?;
        printed_cols += match_printed;

        queue!(
            writer,
            SetBackgroundColor(Color::Reset),
            SetForegroundColor(Color::Reset),
            SetAttribute(Attribute::Reset),
        )?;

        // After-segment
        let after_remaining = remaining.saturating_sub(match_printed);
        if after_remaining > 0 {
            let after_display = if m.formatted_text.has_ansi() {
                // raw_truncate_str already appends \x1b[0m when truncating
                crate::format::raw_truncate_str(&after_raw, after_remaining)
            } else {
                after_plain
                    .chars()
                    .take(after_remaining)
                    .collect::<String>()
            };
            let after_printed = if m.formatted_text.has_ansi() {
                crate::format::visible_char_count(&after_display)
            } else {
                after_display.chars().count()
            };
            queue!(writer, style::Print(&after_display))?;
            printed_cols += after_printed;
        }
        // Reset any ANSI attributes from the original line content before padding,
        // preventing color bleed into space-padding or subsequent content.
        if m.formatted_text.has_ansi() {
            queue!(writer, style::Print("\x1b[0m"))?;
        }

        Ok(printed_cols)
    }

    /// Render a simple (non-match) line, preserving any ANSI formatting.
    ///
    /// Returns the number of visible columns printed.
    fn render_simple_line(
        writer: &mut impl Write,
        line: &Line,
        text_width: usize,
    ) -> Result<usize> {
        let ft = line.formatted_text();
        let display = if ft.has_ansi() {
            ft.raw_truncated(text_width)
        } else {
            ft.plain_text().chars().take(text_width).collect::<String>()
        };
        let display_len = if ft.has_ansi() {
            crate::format::visible_char_count(&display)
        } else {
            display.chars().count()
        };
        queue!(writer, style::Print(&display))?;
        // Reset ANSI after simple line content to prevent color bleed.
        if ft.has_ansi() {
            queue!(writer, style::Print("\x1b[0m"))?;
        }
        Ok(display_len)
    }

    /// Render to any writer with a given terminal size.
    /// Used by both the real event loop (with stdout) and tests (with Vec<u8>).
    pub fn render_to(&self, writer: &mut impl Write, (width, height): (u16, u16)) -> Result<()> {
        // Guard against extremely small terminals where layout calculations break down.
        if height < 5 || width < 10 {
            queue!(
                writer,
                cursor::MoveTo(0, 0),
                terminal::Clear(ClearType::All),
                style::Print("Terminal too small"),
            )?;
            writer.flush()?;
            return Ok(());
        }

        let chrome = Chrome::new(width, height);

        // Show cursor in command mode, hide otherwise
        if self.mode == Mode::Command {
            queue!(writer, cursor::Show)?;
        } else {
            queue!(writer, cursor::Hide)?;
        }

        // Overlay modes (Warning/Command) use full-screen clear because they replace
        // the entire screen content. Normal/QuickSelect modes use per-line clear
        // (ClearType::UntilNewLine) to avoid flicker on j/k navigation.
        if self.mode == Mode::Warning {
            queue!(writer, terminal::Clear(ClearType::All))?;
            self.render_preset_warning(writer, &chrome)?;
            self.render_info(writer, &chrome, height)?;
            writer.flush()?;
            return Ok(());
        }

        // Command mode: show Python-style full-screen command entry UI
        if self.mode == Mode::Command {
            queue!(writer, terminal::Clear(ClearType::All))?;
            self.render_command_mode(writer, width, height)?;
            self.render_info(writer, &chrome, height)?;
            writer.flush()?;
            return Ok(());
        }

        // Scrollbar based on total lines, using full screen height for calculations
        // (matching Python's ScrollBar which uses max_y from getmaxyx)
        let scrollbar = ScrollBar::new(self.lines.len(), height as usize);
        let has_scrollbar = scrollbar.is_active();
        let in_xmode = self.mode == Mode::QuickSelect;
        let text_width = chrome.text_width(has_scrollbar, in_xmode) as usize;

        // Render all visible lines (matches and non-matches, like Python)
        let viewport_end =
            (self.scroll_offset + chrome.content_height as usize).min(self.lines.len());

        let sb_range = scrollbar.calculate(self.scroll_offset);

        let hovered_line_idx = self.match_indices.get(self.hover_index).copied();

        // Empty padding cache — full redraws use ClearType::UntilNewLine, not space-padding.
        let ctx = RenderContext {
            chrome: &chrome,
            has_scrollbar,
            in_xmode,
            text_width,
            sb_range: &sb_range,
            hovered_line_idx,
            use_space_padding: false, // ClearType::UntilNewLine for full redraws
            padding_cache: "",
        };

        for (row, line_idx) in (self.scroll_offset..viewport_end).enumerate() {
            self.render_content_line(writer, row, line_idx, &ctx)?;
        }

        // Draw scrollbar and x-mode labels for rows beyond content area
        // Python draws scrollbar across full screen height and x-mode labels on all rows
        {
            let content_rows = viewport_end - self.scroll_offset;
            for row in content_rows..height as usize {
                queue!(
                    writer,
                    cursor::MoveTo(0, row as u16),
                    terminal::Clear(ClearType::UntilNewLine)
                )?;
                if has_scrollbar {
                    if let Some(ref range) = sb_range {
                        let sb_str = scrollbar::render_scrollbar_row(row, range);
                        queue!(writer, style::Print(sb_str))?;
                    }
                    queue!(writer, cursor::MoveTo(4, row as u16), style::Print(" "),)?;
                }
                // X-mode labels continue on empty rows (but not the last row = usage line)
                if in_xmode && row < (height as usize).saturating_sub(1) {
                    if let Some(label) = quick_select::get_label(row) {
                        queue!(writer, cursor::MoveTo(1, row as u16), style::Print(label),)?;
                    }
                }
            }
        }

        // Bottom info bar (narrow mode) or sidebar (wide mode)
        self.render_info(writer, &chrome, height)?;

        writer.flush()?;
        Ok(())
    }

    fn render_preset_warning(&self, writer: &mut impl Write, chrome: &Chrome) -> Result<()> {
        // Python: (min_x, min_y, _, max_y) = get_chrome_boundaries()
        // max_y accounts for narrow info bar (height - 4 in narrow mode) for centering.
        let max_y = chrome.content_height;
        let min_y = 0u16;
        let y_start = ((max_y + min_y) / 2).saturating_sub(3);
        // Python uses the full screen height for scrollbar calculation (ScrollBar uses
        // max_y from getmaxyx, which is the raw terminal height).
        let has_scrollbar = ScrollBar::new(self.lines.len(), chrome.height as usize).is_active();
        let x_start = if has_scrollbar { 5u16 } else { 0u16 };

        queue!(
            writer,
            cursor::MoveTo(x_start, y_start),
            SetBackgroundColor(Color::Red),
            SetForegroundColor(Color::White),
            style::Print("Oh no! You already provided a command so you cannot enter command mode."),
            SetBackgroundColor(Color::Reset),
            SetForegroundColor(Color::Reset),
        )?;

        if let Some(ref cmd) = self.preset_command {
            queue!(
                writer,
                cursor::MoveTo(x_start, y_start + 1),
                style::Print(format!("The command you provided was \"{cmd}\" ")),
            )?;
        }

        queue!(
            writer,
            cursor::MoveTo(x_start, y_start + 2),
            style::Print("Press any key to go back to selecting paths."),
        )?;

        Ok(())
    }

    /// Render command mode UI matching Python's show_and_get_command().
    /// Shows selected paths, prompt text, and command input.
    fn render_command_mode(&self, writer: &mut impl Write, width: u16, height: u16) -> Result<()> {
        use super::chrome::{SHORT_COMMAND_PROMPT, SHORT_COMMAND_PROMPT2, SHORT_PATHS_HEADER};

        let paths: Vec<String> = self
            .get_selected_matches()
            .iter()
            .map(|m| m.path.clone())
            .collect();
        let max_y = height as i32;

        // Python: begin_height = int(round(max_y / 2) - len(paths) / 2.0)
        // Use float subtraction before converting to int (matching Python exactly)
        let mut begin_height = ((max_y as f64 / 2.0).round() - (paths.len() as f64 / 2.0)) as i32;
        if begin_height <= 1 {
            begin_height = max_y - 6;
        }

        let border_line: String = "=".repeat(SHORT_COMMAND_PROMPT.len());
        let prompt_line: String = ".".repeat(SHORT_COMMAND_PROMPT.len());
        let max_path_length = if width > 200 {
            SHORT_COMMAND_PROMPT.len() + 18
        } else {
            (width as usize).saturating_sub(5)
        };

        // Print paths header
        let start_height = begin_height - 1 - paths.len() as i32;

        macro_rules! print_at {
            ($w:expr, $y:expr, $text:expr) => {
                // Clippy suggests `$y > 0` but callers pass `$y - N` expressions
                // where $y is i32, so `$y >= 0` is a meaningful negative-guard.
                #[allow(clippy::int_plus_one)]
                if $y >= 0 && $y < max_y {
                    queue!($w, cursor::MoveTo(0, $y as u16), style::Print($text))?;
                }
            };
        }

        print_at!(writer, start_height - 3, &border_line);
        print_at!(writer, start_height - 2, SHORT_PATHS_HEADER);
        print_at!(writer, start_height - 1, &border_line);

        for (i, path) in paths.iter().enumerate() {
            let truncated: String = path.chars().take(max_path_length).collect();
            print_at!(writer, start_height + i as i32, &truncated);
        }

        // Print prompt
        print_at!(writer, begin_height - 1, &border_line);
        print_at!(writer, begin_height, SHORT_COMMAND_PROMPT);
        print_at!(writer, begin_height + 1, SHORT_COMMAND_PROMPT2);
        print_at!(writer, begin_height + 2, &border_line);

        // Print command input line
        let input_y = begin_height + 3;
        if input_y >= 0 && input_y < max_y {
            queue!(
                writer,
                cursor::MoveTo(0, input_y as u16),
                style::Print(&prompt_line),
                cursor::MoveTo(0, input_y as u16),
                style::Print(&self.command_buffer),
                cursor::MoveTo(self.command_buffer.chars().count() as u16, input_y as u16),
            )?;
        }

        Ok(())
    }

    fn render_info(&self, writer: &mut impl Write, chrome: &Chrome, height: u16) -> Result<()> {
        if chrome.is_wide {
            let border_x = chrome.content_width;

            // Clear sidebar area and draw vertical border '|' (matching Python's HelperChrome).
            // Clearing from border_x prevents stale content when sidebar text shrinks
            // (e.g., toggling description off).
            // Clear(UntilNewLine) does not move the cursor, so we can print
            // the border character immediately after clearing.
            for row in 0..height {
                queue!(
                    writer,
                    cursor::MoveTo(border_x, row),
                    terminal::Clear(ClearType::UntilNewLine),
                    style::Print("|"),
                )?;
            }

            // Sidebar: show USAGE_PAGE or USAGE_COMMAND_PAGE (matching Python)
            let sidebar_text = if self.mode == Mode::Command {
                super::chrome::USAGE_COMMAND_PAGE
            } else {
                super::chrome::USAGE_PAGE
            };

            // Python: HelperChrome.get_min_y() = CHROME_MIN_Y = 0
            let sidebar_start_y = 0u16;
            let max_w = chrome.sidebar_width as usize - 2;
            for (i, line) in sidebar_text.split('\n').enumerate() {
                let row = sidebar_start_y + i as u16;
                if row < height {
                    let truncated: String = line.chars().take(max_w).collect();
                    // Python: addstr(min_y + index, border_x + 2, usage_line)
                    queue!(
                        writer,
                        cursor::MoveTo(border_x + 2, row),
                        style::Print(&truncated),
                    )?;
                }
            }

            // Show file description when toggled with 'd'
            if self.show_description {
                if let Some(&idx) = self.match_indices.get(self.hover_index) {
                    if let Some(m) = self.lines[idx].as_match() {
                        let desc = m.get_file_description();
                        let header = format!("Description for {}:", m.path);
                        let truncated_header: String = header.chars().take(max_w).collect();
                        // Python: start_y = sidebar_y + 1 = (min_y + count - 1) + 1 = min_y + count
                        let desc_start = sidebar_start_y + sidebar_text.split('\n').count() as u16;
                        // Python: addstr(start_y, border_x + 2, header) — offset by 2
                        // to leave a gap after the '|' border character.
                        queue!(
                            writer,
                            cursor::MoveTo(border_x + 2, desc_start),
                            style::Print(&truncated_header),
                        )?;
                        for (i, line) in desc.iter().enumerate() {
                            let row = desc_start + 2 + i as u16;
                            if row >= height {
                                break;
                            }
                            let truncated: String =
                                line.chars().take(max_w.saturating_sub(6)).collect();
                            queue!(
                                writer,
                                cursor::MoveTo(border_x + 2, row),
                                style::Print(format!("    * {truncated}")),
                            )?;
                        }
                    }
                }
            }
        } else {
            // Narrow mode bottom info bar
            // Python: border and usage start at get_min_x() which is CHROME_MIN_X (5) when scrollbar active
            // In command/warning mode, the scrollbar isn't visible so min_x is 0
            let in_overlay = matches!(self.mode, Mode::Command | Mode::Warning);
            let has_scrollbar =
                !in_overlay && ScrollBar::new(self.lines.len(), height as usize).is_active();
            let in_xmode = matches!(self.mode, Mode::QuickSelect);
            let min_x = if has_scrollbar || in_xmode {
                5u16
            } else {
                0u16
            };

            // Python: border at max_y - 2 (using original screen height, not reduced viewport)
            let border_y = height.saturating_sub(2);

            // Clear info bar rows from min_x to prevent stale content from previous frames.
            queue!(
                writer,
                cursor::MoveTo(min_x, border_y),
                terminal::Clear(ClearType::UntilNewLine),
                cursor::MoveTo(min_x, border_y + 1),
                terminal::Clear(ClearType::UntilNewLine),
            )?;

            // In x-mode, labels continue on border line (not usage line)
            if in_xmode {
                if let Some(label) = quick_select::get_label(border_y as usize) {
                    queue!(writer, cursor::MoveTo(1, border_y), style::Print(label),)?;
                }
            }

            let border_width = (chrome.content_width as usize).saturating_sub(min_x as usize);
            let border: String = "_".repeat(border_width);
            queue!(
                writer,
                cursor::MoveTo(min_x, border_y),
                style::Print(&border),
            )?;

            let usage = match self.mode {
                Mode::Command => super::chrome::USAGE_COMMAND,
                Mode::QuickSelect => super::chrome::USAGE_XMODE,
                _ => {
                    if self.all_input {
                        super::chrome::USAGE_HEADER_ALL_INPUT
                    } else {
                        super::chrome::USAGE_HEADER
                    }
                }
            };
            // Truncate usage text to available width to prevent line wrapping
            // (curses addstr truncates at screen edge; crossterm Print wraps)
            let max_usage_width = chrome.content_width.saturating_sub(min_x) as usize;
            let truncated_usage: String = usage.chars().take(max_usage_width).collect();
            queue!(
                writer,
                cursor::MoveTo(min_x, border_y + 1),
                style::Print(&truncated_usage),
            )?;
        }

        Ok(())
    }
}

pub enum Action {
    Continue,
    Quit,
    /// Ctrl-C: silent exit (no script written, no selection saved, like Python's sys.exit(0))
    SilentQuit,
    Execute,
}

const TRUNCATE_DECORATOR: &str = "|...|";

/// Parse a key sequence string into KeyEvents (for --execute-keys flag).
fn execute_keys_from_str(keys: &str) -> Vec<KeyEvent> {
    keys.split_whitespace()
        .filter_map(|k| {
            // Match named keys case-insensitively, but preserve original case for single chars
            match k.to_uppercase().as_str() {
                "UP" => Some(KeyEvent::new(KeyCode::Up, KeyModifiers::NONE)),
                "DOWN" => Some(KeyEvent::new(KeyCode::Down, KeyModifiers::NONE)),
                "LEFT" => Some(KeyEvent::new(KeyCode::Left, KeyModifiers::NONE)),
                "RIGHT" => Some(KeyEvent::new(KeyCode::Right, KeyModifiers::NONE)),
                "HOME" => Some(KeyEvent::new(KeyCode::Home, KeyModifiers::NONE)),
                "END" => Some(KeyEvent::new(KeyCode::End, KeyModifiers::NONE)),
                "PAGEUP" | "PPAGE" => Some(KeyEvent::new(KeyCode::PageUp, KeyModifiers::NONE)),
                "PAGEDOWN" | "NPAGE" => Some(KeyEvent::new(KeyCode::PageDown, KeyModifiers::NONE)),
                "ENTER" => Some(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE)),
                "SPACE" => Some(KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE)),
                "CTRL_C" => Some(KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL)),
                _ if k.len() == 1 => {
                    // Use original char to preserve case: 'f' != 'F'
                    let ch = k.chars().next().unwrap();
                    Some(KeyEvent::new(KeyCode::Char(ch), KeyModifiers::NONE))
                }
                _ => None,
            }
        })
        .collect()
}

#[cfg(test)]
#[path = "controller_tests.rs"]
mod tests;
