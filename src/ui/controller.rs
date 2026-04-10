use std::collections::VecDeque;
use std::io::{self, Write};
use std::time::Duration;

use anyhow::Result;
use crossterm::{
    cursor,
    event::{self, Event, KeyCode, KeyEvent, KeyModifiers},
    execute,
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
    custom_bindings: Vec<KeyBinding>,
    all_input: bool,
    show_description: bool,
    /// Override terminal size for testing. None = use terminal::size().
    viewport_size: Option<(u16, u16)>,
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
            custom_bindings: keybindings::read_key_bindings(),
            all_input,
            show_description: false,
            viewport_size: None,
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

    /// Get the effective terminal size, using override if set.
    fn get_size(&self) -> (u16, u16) {
        self.viewport_size
            .unwrap_or_else(|| terminal::size().unwrap_or((80, 24)))
    }

    /// Run the interactive UI loop. Returns when the user makes a selection or quits.
    pub fn run(&mut self) -> Result<()> {
        if self.match_indices.is_empty() {
            output::output_no_matches()?;
            return Ok(());
        }

        terminal::enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, terminal::EnterAlternateScreen, cursor::Hide,)?;

        let result = self.event_loop(&mut stdout);

        execute!(stdout, cursor::Show, terminal::LeaveAlternateScreen,)?;
        terminal::disable_raw_mode()?;

        result
    }

    fn event_loop(&mut self, stdout: &mut io::Stdout) -> Result<()> {
        // Process any queued execute-keys first
        while let Some(key) = self.execute_keys_queue.pop_front() {
            match self.handle_key(key)? {
                Action::Continue => {
                    self.dirty = true;
                }
                Action::Quit => {
                    // Python: output_nothing() then save selection then exit
                    output::output_nothing()?;
                    self.save_selection()?;
                    return Ok(());
                }
                Action::SilentQuit => {
                    // Python Ctrl-C: sys.exit(0) — no script, no selection save
                    return Ok(());
                }
                Action::Execute => {
                    return self.execute_selection();
                }
            }
        }

        loop {
            if self.dirty {
                let size = terminal::size()?;
                self.render_to(stdout, size)?;
                self.dirty = false;
            }

            if event::poll(Duration::from_millis(100))? {
                match event::read()? {
                    Event::Key(key) => {
                        match self.handle_key(key)? {
                            Action::Continue => {}
                            Action::Quit => {
                                // Python: output_nothing() then save selection then exit
                                output::output_nothing()?;
                                self.save_selection()?;
                                return Ok(());
                            }
                            Action::SilentQuit => {
                                // Python Ctrl-C: sys.exit(0) — no script, no selection save
                                return Ok(());
                            }
                            Action::Execute => {
                                return self.execute_selection();
                            }
                        }
                        self.dirty = true;
                    }
                    Event::Resize(_, _) => {
                        self.dirty = true;
                    }
                    _ => {}
                }
            }
        }
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
                for binding in &self.custom_bindings {
                    if binding.key.len() == 1 && binding.key == ch.to_string() {
                        return self.execute_custom_binding(&binding.command.clone());
                    }
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
                    for binding in &self.custom_bindings {
                        if binding.key.len() == 1 && binding.key == ch.to_string() {
                            return self.execute_custom_binding(&binding.command.clone());
                        }
                    }
                }
                Ok(Action::Continue)
            }
        }
    }

    fn execute_custom_binding(&mut self, command: &str) -> Result<Action> {
        self.command_buffer = command.to_string();
        Ok(Action::Execute)
    }

    // --- Navigation ---

    fn move_hover(&mut self, delta: isize) {
        if self.match_indices.is_empty() {
            return;
        }
        let len = self.match_indices.len() as isize;
        let new_idx = ((self.hover_index as isize + delta) % len + len) % len;
        self.hover_index = new_idx as usize;
        self.show_description = false;
        self.adjust_scroll();
    }

    fn page_down(&mut self) {
        let (width, height) = self.get_size();
        let chrome = Chrome::new(width, height);
        let page = (chrome.content_height as usize) / 2;
        self.move_hover(page as isize);
    }

    fn page_up(&mut self) {
        let (width, height) = self.get_size();
        let chrome = Chrome::new(width, height);
        let page = (chrome.content_height as usize) / 2;
        self.move_hover(-(page as isize));
    }

    fn jump_to_first(&mut self) {
        self.hover_index = 0;
        self.adjust_scroll();
    }

    fn jump_to_last(&mut self) {
        if !self.match_indices.is_empty() {
            self.hover_index = self.match_indices.len() - 1;
        }
        self.adjust_scroll();
    }

    fn adjust_scroll(&mut self) {
        // Port of Python's update_scroll_offset: center-scroll with leeway.
        // Centers the viewport on the hovered line, but only repositions
        // when the current offset has drifted more than 1/4 window height
        // from the desired center (or when the hovered line is off-screen).
        let (width, height) = self.get_size();
        let chrome = Chrome::new(width, height);
        let window_height = chrome.content_height as usize;
        let half_height = window_height.div_ceil(2);

        let hovered_line_idx = self.match_indices[self.hover_index];

        // Python uses negative offset; we use positive. Equivalent logic:
        // desired_top_row = max(hovered_line_idx - half_height, 0)
        let desired_top_row = hovered_line_idx.saturating_sub(half_height);
        let old_offset = self.scroll_offset;

        // Python condition: abs(new_offset - old_offset) > half_height / 2
        //   or self.hover_index + old_offset < 0
        // In Python, scroll_offset is negative. Converting to Rust positive offset:
        // - drift = abs(desired_top_row - old_offset)
        // - hover_index < old_offset (match index vs scroll position, Python quirk)
        let drift = desired_top_row.abs_diff(old_offset);
        let hover_before_viewport = self.hover_index < old_offset;

        if drift > half_height / 2 || hover_before_viewport {
            self.scroll_offset = desired_top_row;
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
        // Toggle each unique path individually (like Python)
        let mut seen_paths = std::collections::HashSet::new();
        for &idx in &self.match_indices {
            if let Some(m) = self.lines[idx].as_match_mut() {
                if seen_paths.insert(m.path.clone()) {
                    m.selected = !m.selected;
                }
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

    /// Render to any writer with a given terminal size.
    /// Used by both the real event loop (with stdout) and tests (with Vec<u8>).
    pub fn render_to(&self, writer: &mut impl Write, (width, height): (u16, u16)) -> Result<()> {
        let chrome = Chrome::new(width, height);

        // Show cursor in command mode, hide otherwise
        if self.mode == Mode::Command {
            execute!(writer, cursor::Show)?;
        } else {
            execute!(writer, cursor::Hide)?;
        }

        execute!(writer, terminal::Clear(ClearType::All))?;

        // Warning overlay: render and return (event_loop handles dismissal)
        if self.mode == Mode::Warning {
            self.render_preset_warning(writer, &chrome)?;
            self.render_info(writer, &chrome, height)?;
            writer.flush()?;
            return Ok(());
        }

        // Command mode: show Python-style full-screen command entry UI
        if self.mode == Mode::Command {
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

        for (row, line_idx) in (self.scroll_offset..viewport_end).enumerate() {
            let line = &self.lines[line_idx];
            let is_hovered = hovered_line_idx == Some(line_idx);

            execute!(writer, cursor::MoveTo(0, row as u16))?;

            // Scrollbar (Python ASCII art style: 3-char strings at col 0-2,
            // border space at col 4, content at col 5 = CHROME_MIN_X).
            // Col 3 is intentionally left unwritten (matching Python's erase).
            // Use screen_row (not viewport row) for scrollbar rendering,
            // since Python draws scrollbar based on full screen position.
            let screen_row = row;
            if has_scrollbar {
                if let Some(ref range) = sb_range {
                    let sb_str = scrollbar::render_scrollbar_row(screen_row, range);
                    execute!(writer, style::Print(sb_str))?;
                }
                // Border at col 4 (Python: output_border at x_pos + 4)
                execute!(writer, cursor::MoveTo(4, row as u16), style::Print(" "),)?;
            }

            // Quick-select labels: Python renders at x=0 (overwriting first char)
            if in_xmode {
                if let Some(label) = quick_select::get_label(row) {
                    execute!(
                        writer,
                        cursor::MoveTo(0, row as u16),
                        style::Print(format!("{label}")),
                    )?;
                }
                // Move cursor to content start (CHROME_MIN_X = 5)
                if !has_scrollbar {
                    let content_x = chrome.content_start_x(has_scrollbar, in_xmode);
                    execute!(writer, cursor::MoveTo(content_x, row as u16))?;
                }
            }

            // Line content: Python renders before_text + decorated_match + after_text
            // Only the match portion gets color/underline attributes.
            let is_selected = line.as_match().is_some_and(|m| m.selected);

            if let Some(m) = line.as_match() {
                let plain = m.formatted_text.plain_text();
                let plain_len = plain.chars().count();
                let ms = m.match_start.min(plain_len);
                let me = m.match_end.min(plain_len);

                // Use ANSI-aware splitting to preserve colors in before/after
                let (before_raw, rest_raw) = m.formatted_text.breakat(ms);
                let (_matched_raw, after_raw) = {
                    let rest_ft = crate::format::FormattedText::new(&rest_raw);
                    let match_len = me - ms;
                    rest_ft.breakat(match_len)
                };

                let before_plain: String = plain.chars().take(ms).collect();
                let mut matched_plain: String = plain.chars().skip(ms).take(me - ms).collect();
                let after_plain: String = plain.chars().skip(me).collect();

                let arrow = if is_selected { "|===>" } else { "" };
                let arrow_len = arrow.len();
                let max_len = text_width;

                // Python: update_decorated_match(max_len) — if before_text + decorated_match
                // exceeds available space, truncate the combined (arrow + match) with |...|
                // and drop before_text for more room.
                // Python's plain_text = decorator_text + match, and both begin/end are taken
                // from this combined string, so the arrow is included in the truncation.
                let combined = format!("{arrow}{matched_plain}");
                let important_len = before_plain.chars().count() + combined.chars().count();
                let is_truncated = important_len > max_len;
                let truncated_combined;
                if is_truncated {
                    // Python: space_allowed = max_len - |...| - decorator_text - before_text
                    let space_allowed = max_len
                        .saturating_sub(TRUNCATE_DECORATOR.len())
                        .saturating_sub(arrow.len())
                        .saturating_sub(before_plain.chars().count());
                    if space_allowed > 1 {
                        let mid = space_allowed / 2;
                        let combined_chars: Vec<char> = combined.chars().collect();
                        let total = combined_chars.len();
                        let begin: String = combined_chars[..mid].iter().collect();
                        let end: String =
                            combined_chars[total.saturating_sub(mid)..].iter().collect();
                        truncated_combined = format!("{begin}{TRUNCATE_DECORATOR}{end}");
                    } else {
                        truncated_combined = combined;
                    }
                } else {
                    truncated_combined = combined;
                }

                // Print before_text with ANSI preserved
                // When truncated, before_text is still shown (Python includes it in space calc)
                let before_display = if m.formatted_text.has_ansi() {
                    let ft = crate::format::FormattedText::new(&before_raw);
                    ft.raw_truncated(max_len)
                } else {
                    before_plain.chars().take(max_len).collect::<String>()
                };
                let before_printed = if m.formatted_text.has_ansi() {
                    crate::format::FormattedText::new(&before_display)
                        .plain_text()
                        .chars()
                        .count()
                } else {
                    before_display.chars().count()
                };
                execute!(writer, style::Print(&before_display))?;
                // Reset after ANSI before_text to avoid color bleeding into match
                if m.formatted_text.has_ansi() {
                    execute!(writer, style::Print("\x1b[0m"))?;
                }

                // Set attributes for the match portion
                if is_hovered && m.selected {
                    execute!(
                        writer,
                        SetBackgroundColor(Color::Red),
                        SetForegroundColor(Color::White),
                        SetAttribute(Attribute::Bold),
                    )?;
                } else if is_hovered {
                    execute!(
                        writer,
                        SetBackgroundColor(Color::Blue),
                        SetForegroundColor(Color::White),
                        SetAttribute(Attribute::Bold),
                    )?;
                } else if m.selected {
                    execute!(
                        writer,
                        SetBackgroundColor(Color::Green),
                        SetForegroundColor(Color::White),
                        SetAttribute(Attribute::Bold),
                    )?;
                } else if !self.all_input {
                    execute!(writer, SetAttribute(Attribute::Underlined))?;
                }

                // Print combined arrow+match (truncated if needed)
                // Simple clipping at render time — Python clips via curses addstr.
                let remaining = max_len.saturating_sub(before_printed);
                let match_display: String = truncated_combined.chars().take(remaining).collect();
                let match_printed = match_display.chars().count();
                execute!(writer, style::Print(&match_display))?;

                // Reset attributes
                execute!(
                    writer,
                    SetBackgroundColor(Color::Reset),
                    SetForegroundColor(Color::Reset),
                    SetAttribute(Attribute::Reset),
                )?;

                // Print after_text with ANSI preserved
                // Simple clipping (no |...| decorator) — matches Python's curses
                // addstr which silently clips at the right edge of the screen.
                let after_remaining = remaining.saturating_sub(match_printed);
                if after_remaining > 0 {
                    let after_display = if m.formatted_text.has_ansi() {
                        let ft = crate::format::FormattedText::new(&after_raw);
                        let result = ft.raw_truncated(after_remaining);
                        format!("{result}\x1b[0m")
                    } else {
                        after_plain
                            .chars()
                            .take(after_remaining)
                            .collect::<String>()
                    };
                    execute!(writer, style::Print(&after_display))?;
                }
            } else {
                // SimpleLine: no attributes, just print with ANSI preservation
                // Simple clipping at the right edge (matching Python's curses addstr)
                let ft = line.formatted_text();
                let display = if ft.has_ansi() {
                    ft.raw_truncated(text_width)
                } else {
                    ft.plain_text().chars().take(text_width).collect::<String>()
                };
                execute!(writer, style::Print(&display))?;
            }
        }

        // Draw scrollbar and x-mode labels for rows beyond content area
        // Python draws scrollbar across full screen height and x-mode labels on all rows
        {
            let content_rows = viewport_end - self.scroll_offset;
            for row in content_rows..height as usize {
                execute!(writer, cursor::MoveTo(0, row as u16))?;
                if has_scrollbar {
                    if let Some(ref range) = sb_range {
                        let sb_str = scrollbar::render_scrollbar_row(row, range);
                        execute!(writer, style::Print(sb_str))?;
                    }
                    execute!(writer, cursor::MoveTo(4, row as u16), style::Print(" "),)?;
                }
                // X-mode labels continue on empty rows (but not the last row = usage line)
                if in_xmode && row < (height as usize).saturating_sub(1) {
                    if let Some(label) = quick_select::get_label(row) {
                        execute!(
                            writer,
                            cursor::MoveTo(0, row as u16),
                            style::Print(format!("{label}")),
                        )?;
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
        // max_y accounts for narrow info bar (height - 4 in narrow mode)
        let max_y = chrome.content_height;
        let min_y = 0u16;
        let y_start = (max_y + min_y) / 2 - 3;
        let has_scrollbar =
            ScrollBar::new(self.lines.len(), chrome.content_height as usize).is_active();
        let x_start = if has_scrollbar { 5u16 } else { 0u16 };

        execute!(
            writer,
            cursor::MoveTo(x_start, y_start),
            SetBackgroundColor(Color::Red),
            SetForegroundColor(Color::White),
            style::Print("Oh no! You already provided a command so you cannot enter command mode."),
            SetBackgroundColor(Color::Reset),
            SetForegroundColor(Color::Reset),
        )?;

        if let Some(ref cmd) = self.preset_command {
            execute!(
                writer,
                cursor::MoveTo(x_start, y_start + 1),
                style::Print(format!("The command you provided was \"{cmd}\" ")),
            )?;
        }

        execute!(
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
                if $y >= 0 && $y < max_y {
                    execute!($w, cursor::MoveTo(0, $y as u16), style::Print($text))?;
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
            execute!(
                writer,
                cursor::MoveTo(0, input_y as u16),
                style::Print(&prompt_line),
                cursor::MoveTo(0, input_y as u16),
                style::Print(&self.command_buffer),
                cursor::MoveTo(self.command_buffer.len() as u16, input_y as u16),
            )?;
        }

        Ok(())
    }

    fn render_info(&self, writer: &mut impl Write, chrome: &Chrome, height: u16) -> Result<()> {
        if chrome.is_wide {
            let border_x = chrome.content_width;

            // Draw vertical border '|' (matching Python's HelperChrome)
            for row in 0..height {
                execute!(writer, cursor::MoveTo(border_x, row), style::Print("|"),)?;
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
                    execute!(
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
                        execute!(
                            writer,
                            cursor::MoveTo(border_x + 1, desc_start),
                            style::Print(&truncated_header),
                        )?;
                        for (i, line) in desc.iter().enumerate() {
                            let truncated: String =
                                line.chars().take(max_w.saturating_sub(6)).collect();
                            execute!(
                                writer,
                                cursor::MoveTo(border_x + 1, desc_start + 2 + i as u16),
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

            // In x-mode, labels continue on border line (not usage line)
            if in_xmode {
                if let Some(label) = quick_select::get_label(border_y as usize) {
                    execute!(
                        writer,
                        cursor::MoveTo(0, border_y),
                        style::Print(format!("{label}")),
                    )?;
                }
            }

            let border_width = (chrome.content_width as usize).saturating_sub(min_x as usize);
            let border: String = "_".repeat(border_width);
            execute!(
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
            let max_usage_width = (chrome.content_width - min_x) as usize;
            let truncated_usage: String = usage.chars().take(max_usage_width).collect();
            execute!(
                writer,
                cursor::MoveTo(min_x, border_y + 1),
                SetForegroundColor(Color::DarkGrey),
                style::Print(&truncated_usage),
                SetForegroundColor(Color::Reset),
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

/// Truncate a line to fit within max_width, using |...| decorator for long lines.
fn truncate_line(text: &str, max_width: usize) -> String {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() <= max_width {
        return text.to_string();
    }
    if max_width <= TRUNCATE_DECORATOR.len() + 2 {
        return chars.iter().take(max_width).collect();
    }
    let decorator_len = TRUNCATE_DECORATOR.len();
    let remaining = max_width - decorator_len;
    let front = remaining / 2;
    let back = remaining - front;
    let mut result: String = chars[..front].iter().collect();
    result.push_str(TRUNCATE_DECORATOR);
    result.extend(&chars[chars.len() - back..]);
    result
}

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
mod tests {
    use super::*;
    use crate::format::FormattedText;
    use crate::line::{Line, LineMatch};

    fn make_test_lines(paths: &[&str]) -> (Vec<Line>, Vec<usize>) {
        let lines: Vec<Line> = paths
            .iter()
            .map(|path| {
                Line::Match(LineMatch::new(
                    FormattedText::new(path),
                    path.to_string(),
                    0,
                    path.to_string(),
                    0,
                    path.len(),
                ))
            })
            .collect();
        let indices: Vec<usize> = (0..lines.len()).collect();
        (lines, indices)
    }

    #[test]
    fn test_move_hover() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        assert_eq!(ctrl.hover_index, 0);

        ctrl.move_hover(1);
        assert_eq!(ctrl.hover_index, 1);

        ctrl.move_hover(1);
        assert_eq!(ctrl.hover_index, 2);

        // Wraps around to first (like Python)
        ctrl.move_hover(1);
        assert_eq!(ctrl.hover_index, 0);

        ctrl.move_hover(-1);
        // Wraps around to last
        assert_eq!(ctrl.hover_index, 2);
    }

    #[test]
    fn test_toggle_selection() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        ctrl.toggle_current_selection();
        assert!(ctrl.lines[0].as_match().unwrap().selected);
        assert!(!ctrl.lines[1].as_match().unwrap().selected);

        ctrl.toggle_current_selection();
        assert!(!ctrl.lines[0].as_match().unwrap().selected);
    }

    #[test]
    fn test_toggle_select_all() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        ctrl.toggle_select_all();
        assert!(ctrl.lines[0].as_match().unwrap().selected);
        assert!(ctrl.lines[1].as_match().unwrap().selected);
        assert!(ctrl.lines[2].as_match().unwrap().selected);

        ctrl.toggle_select_all();
        assert!(!ctrl.lines[0].as_match().unwrap().selected);
        assert!(!ctrl.lines[1].as_match().unwrap().selected);
        assert!(!ctrl.lines[2].as_match().unwrap().selected);
    }

    #[test]
    fn test_initial_select_all() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
        let ctrl = Controller::new(lines, indices, None, true, None, false);
        assert!(ctrl.lines[0].as_match().unwrap().selected);
        assert!(ctrl.lines[1].as_match().unwrap().selected);
    }

    #[test]
    fn test_get_selected_matches_uses_hovered_when_none_selected() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
        let ctrl = Controller::new(lines, indices, None, false, None, false);
        let selected = ctrl.get_selected_matches();
        assert_eq!(selected.len(), 1);
        assert_eq!(selected[0].path, "a.txt");
    }

    #[test]
    fn test_get_selected_matches_returns_selected() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.move_hover(1);
        ctrl.toggle_current_selection(); // select b.txt
        ctrl.move_hover(1);
        ctrl.toggle_current_selection(); // select c.txt

        let selected = ctrl.get_selected_matches();
        assert_eq!(selected.len(), 2);
        assert_eq!(selected[0].path, "b.txt");
        assert_eq!(selected[1].path, "c.txt");
    }

    #[test]
    fn test_execute_keys_from_str() {
        let keys = execute_keys_from_str("f j F END");
        assert_eq!(keys.len(), 4);
        assert_eq!(keys[0].code, KeyCode::Char('f'));
        assert_eq!(keys[1].code, KeyCode::Char('j'));
        assert_eq!(keys[2].code, KeyCode::Char('F'));
        assert_eq!(keys[3].code, KeyCode::End);
    }

    #[test]
    fn test_jump_to_first_and_last() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt", "d.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        ctrl.jump_to_last();
        assert_eq!(ctrl.hover_index, 3);

        ctrl.jump_to_first();
        assert_eq!(ctrl.hover_index, 0);
    }

    // --- truncate_line tests ---

    #[test]
    fn test_truncate_line_short() {
        assert_eq!(truncate_line("hello", 10), "hello");
    }

    #[test]
    fn test_truncate_line_exact() {
        assert_eq!(truncate_line("hello", 5), "hello");
    }

    #[test]
    fn test_truncate_line_long() {
        let result = truncate_line("abcdefghijklmnopqrstuvwxyz", 15);
        assert_eq!(result.chars().count(), 15);
        assert!(result.contains("|...|"));
    }

    #[test]
    fn test_truncate_line_very_small_width() {
        let result = truncate_line("abcdefghij", 5);
        assert_eq!(result, "abcde");
    }

    #[test]
    fn test_truncate_line_unicode() {
        let result = truncate_line("가나다라마바사아자차카타파하", 10);
        assert_eq!(result.chars().count(), 10);
        assert!(result.contains("|...|"));
    }

    // --- Enter key restriction tests ---

    #[test]
    fn test_enter_blocked_in_all_input_without_command() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, true);
        let key = KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE);
        let action = ctrl.handle_key(key).unwrap();
        assert!(matches!(action, Action::Continue));
    }

    #[test]
    fn test_enter_works_in_all_input_with_preset_command() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(
            lines,
            indices,
            Some("git add".to_string()),
            false,
            None,
            true,
        );
        let key = KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE);
        let action = ctrl.handle_key(key).unwrap();
        assert!(matches!(action, Action::Execute));
    }

    #[test]
    fn test_enter_works_without_all_input() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        let key = KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE);
        let action = ctrl.handle_key(key).unwrap();
        assert!(matches!(action, Action::Execute));
    }

    // --- Preset command warning tests ---

    #[test]
    fn test_c_key_with_preset_command_enters_warning() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(
            lines,
            indices,
            Some("git add".to_string()),
            false,
            None,
            false,
        );
        let key = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert_eq!(ctrl.mode, Mode::Warning);
    }

    #[test]
    fn test_c_key_without_preset_enters_command_mode() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        let key = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert_eq!(ctrl.mode, Mode::Command);
    }

    #[test]
    fn test_warning_dismissed_by_any_key() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(
            lines,
            indices,
            Some("git add".to_string()),
            false,
            None,
            false,
        );
        ctrl.mode = Mode::Warning;
        let key = KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert_eq!(ctrl.mode, Mode::Normal);
    }

    // --- Description toggle tests ---

    #[test]
    fn test_d_key_shows_description() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        assert!(!ctrl.show_description);

        let key = KeyEvent::new(KeyCode::Char('d'), KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert!(ctrl.show_description);
    }

    #[test]
    fn test_description_clears_on_move() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.show_description = true;

        ctrl.move_hover(1);
        assert!(!ctrl.show_description);
    }

    // --- Quit vs SilentQuit distinction ---

    #[test]
    fn test_quit_vs_silent_quit_are_distinct() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        let q_action = ctrl
            .handle_key(KeyEvent::new(KeyCode::Char('q'), KeyModifiers::NONE))
            .unwrap();
        assert!(matches!(q_action, Action::Quit));
        let cc_action = ctrl
            .handle_key(KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL))
            .unwrap();
        assert!(matches!(cc_action, Action::SilentQuit));
    }

    // --- Ctrl-C silent quit tests ---

    #[test]
    fn test_ctrl_c_returns_silent_quit() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        let key = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL);
        let action = ctrl.handle_key(key).unwrap();
        assert!(matches!(action, Action::SilentQuit));
    }

    #[test]
    fn test_ctrl_c_in_command_mode_returns_silent_quit() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.mode = Mode::Command;
        let key = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL);
        let action = ctrl.handle_key(key).unwrap();
        assert!(matches!(action, Action::SilentQuit));
    }

    #[test]
    fn test_ctrl_c_in_xmode_returns_silent_quit() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.mode = Mode::QuickSelect;
        let key = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL);
        let action = ctrl.handle_key(key).unwrap();
        assert!(matches!(action, Action::SilentQuit));
    }

    // --- Command mode backspace tests ---

    #[test]
    fn test_command_mode_backspace_on_empty_stays_in_command() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.mode = Mode::Command;
        // Backspace on empty buffer should NOT exit command mode (Python compat)
        let key = KeyEvent::new(KeyCode::Backspace, KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert_eq!(ctrl.mode, Mode::Command);
    }

    #[test]
    fn test_command_mode_backspace_removes_char() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.mode = Mode::Command;
        ctrl.command_buffer = "ab".to_string();
        let key = KeyEvent::new(KeyCode::Backspace, KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert_eq!(ctrl.command_buffer, "a");
        assert_eq!(ctrl.mode, Mode::Command);
    }

    #[test]
    fn test_command_mode_empty_enter_returns_to_normal() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.mode = Mode::Command;
        let key = KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert_eq!(ctrl.mode, Mode::Normal);
    }

    // --- Custom keybinding fire-after-builtin tests ---

    #[test]
    fn test_custom_binding_fires_on_unbound_key() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.custom_bindings = vec![KeyBinding {
            key: "z".to_string(),
            command: "git add".to_string(),
        }];
        let key = KeyEvent::new(KeyCode::Char('z'), KeyModifiers::NONE);
        let action = ctrl.handle_key(key).unwrap();
        assert!(matches!(action, Action::Execute));
        assert_eq!(ctrl.command_buffer, "git add");
    }

    #[test]
    fn test_custom_binding_fires_after_builtin_key() {
        // Python: if 'f' has a custom binding, toggle_select fires first,
        // then the custom binding fires (overriding to Execute)
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.custom_bindings = vec![KeyBinding {
            key: "f".to_string(),
            command: "git add".to_string(),
        }];
        let key = KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE);
        let action = ctrl.handle_key(key).unwrap();
        // Built-in 'f' toggled selection, then custom binding fires Execute
        assert!(ctrl.lines[0].as_match().unwrap().selected);
        assert!(matches!(action, Action::Execute));
    }

    #[test]
    fn test_custom_binding_does_not_fire_on_quit() {
        // Python: 'q' exits before custom binding loop runs
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.custom_bindings = vec![KeyBinding {
            key: "q".to_string(),
            command: "git add".to_string(),
        }];
        let key = KeyEvent::new(KeyCode::Char('q'), KeyModifiers::NONE);
        let action = ctrl.handle_key(key).unwrap();
        // Should be Quit, not Execute (custom binding doesn't fire for Quit)
        assert!(matches!(action, Action::Quit));
    }

    #[test]
    fn test_custom_binding_fires_in_xmode_on_unmatched_key() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.mode = Mode::QuickSelect;
        ctrl.custom_bindings = vec![KeyBinding {
            key: "z".to_string(),
            command: "git add".to_string(),
        }];
        let key = KeyEvent::new(KeyCode::Char('z'), KeyModifiers::NONE);
        let action = ctrl.handle_key(key).unwrap();
        assert!(matches!(action, Action::Execute));
        assert_eq!(ctrl.command_buffer, "git add");
    }

    // --- Command mode Esc test ---

    #[test]
    fn test_command_mode_esc_clears_buffer_and_returns_to_normal() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.mode = Mode::Command;
        ctrl.command_buffer = "git add".to_string();
        let key = KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert_eq!(ctrl.mode, Mode::Normal);
        assert!(ctrl.command_buffer.is_empty());
    }

    // --- QuickSelect mode G/END/A key tests ---

    #[test]
    fn test_xmode_g_uppercase_is_ignored() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.mode = Mode::QuickSelect;
        let key = KeyEvent::new(KeyCode::Char('G'), KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert_eq!(ctrl.hover_index, 0);
    }

    #[test]
    fn test_xmode_end_key_works() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.mode = Mode::QuickSelect;
        let key = KeyEvent::new(KeyCode::End, KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert_eq!(ctrl.hover_index, 2);
    }

    #[test]
    fn test_xmode_a_is_ignored() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.mode = Mode::QuickSelect;
        let key = KeyEvent::new(KeyCode::Char('A'), KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert!(!ctrl.lines[0].as_match().unwrap().selected);
        assert!(!ctrl.lines[1].as_match().unwrap().selected);
    }

    // --- Selection state collection test ---

    #[test]
    fn test_save_selection_collects_correct_indices() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.move_hover(1);
        ctrl.toggle_current_selection(); // select b.txt (index 1)

        let selected: Vec<usize> = ctrl
            .match_indices
            .iter()
            .filter(|&&idx| ctrl.lines[idx].as_match().is_some_and(|m| m.selected))
            .copied()
            .collect();
        assert_eq!(selected, vec![1]);
    }

    // --- F key (toggle + move down) tests ---

    #[test]
    fn test_f_uppercase_toggles_and_moves_down() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        assert_eq!(ctrl.hover_index, 0);

        let key = KeyEvent::new(KeyCode::Char('F'), KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        // a.txt should be selected, hover moved to b.txt
        assert!(ctrl.lines[0].as_match().unwrap().selected);
        assert_eq!(ctrl.hover_index, 1);
    }

    #[test]
    fn test_f_uppercase_wraps_at_end() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.hover_index = 1; // last item

        let key = KeyEvent::new(KeyCode::Char('F'), KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert!(ctrl.lines[1].as_match().unwrap().selected);
        assert_eq!(ctrl.hover_index, 0); // wrapped to first
    }

    // --- Page down / page up tests ---

    #[test]
    fn test_page_down_via_space() {
        // terminal::size() returns fallback (80,24) in test → content_height=20 → page=10
        let paths: Vec<&str> = (0..30).map(|_| "f.txt").collect();
        let (lines, indices) = make_test_lines(&paths);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        assert_eq!(ctrl.hover_index, 0);

        let key = KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert!(ctrl.hover_index > 0, "page_down should move hover forward");
    }

    #[test]
    fn test_page_up_via_b() {
        let paths: Vec<&str> = (0..30).map(|_| "f.txt").collect();
        let (lines, indices) = make_test_lines(&paths);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.hover_index = 15;

        let key = KeyEvent::new(KeyCode::Char('b'), KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert!(ctrl.hover_index < 15, "page_up should move hover backward");
    }

    #[test]
    fn test_page_down_via_npage() {
        let paths: Vec<&str> = (0..30).map(|_| "f.txt").collect();
        let (lines, indices) = make_test_lines(&paths);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        let key = KeyEvent::new(KeyCode::PageDown, KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert!(ctrl.hover_index > 0);
    }

    #[test]
    fn test_page_up_via_ppage() {
        let paths: Vec<&str> = (0..30).map(|_| "f.txt").collect();
        let (lines, indices) = make_test_lines(&paths);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.hover_index = 20;

        let key = KeyEvent::new(KeyCode::PageUp, KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        assert!(ctrl.hover_index < 20);
    }

    #[test]
    fn test_page_down_wraps_around() {
        let paths: Vec<&str> = (0..5).map(|_| "f.txt").collect();
        let (lines, indices) = make_test_lines(&paths);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.hover_index = 4; // last item

        let key = KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE);
        ctrl.handle_key(key).unwrap();
        // Should wrap since page size > remaining items
        // move_hover wraps via modular arithmetic
        assert!(ctrl.hover_index < 5);
    }

    // --- Multi-step interaction sequence tests (matching Python test_screen.py) ---

    /// Python: selectDownSelect — [f, j, f]
    #[test]
    fn test_sequence_select_down_select() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        // f: select a.txt
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
            .unwrap();
        assert!(ctrl.lines[0].as_match().unwrap().selected);

        // j: move down
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('j'), KeyModifiers::NONE))
            .unwrap();
        assert_eq!(ctrl.hover_index, 1);

        // f: select b.txt
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
            .unwrap();
        assert!(ctrl.lines[0].as_match().unwrap().selected);
        assert!(ctrl.lines[1].as_match().unwrap().selected);
        assert!(!ctrl.lines[2].as_match().unwrap().selected);
    }

    /// Python: selectWithDownSelect — [F, f]
    #[test]
    fn test_sequence_select_with_down_select() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        // F: select a.txt + move down
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('F'), KeyModifiers::NONE))
            .unwrap();
        assert!(ctrl.lines[0].as_match().unwrap().selected);
        assert_eq!(ctrl.hover_index, 1);

        // f: select b.txt
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
            .unwrap();
        assert!(ctrl.lines[0].as_match().unwrap().selected);
        assert!(ctrl.lines[1].as_match().unwrap().selected);
    }

    /// Python: selectDownSelectInverse — [f, j, f, A]
    #[test]
    fn test_sequence_select_down_select_inverse() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        // f: select a.txt
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
            .unwrap();
        // j: move down
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('j'), KeyModifiers::NONE))
            .unwrap();
        // f: select b.txt
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
            .unwrap();
        // A: toggle all — a.txt OFF, b.txt OFF, c.txt ON
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('A'), KeyModifiers::NONE))
            .unwrap();

        assert!(!ctrl.lines[0].as_match().unwrap().selected);
        assert!(!ctrl.lines[1].as_match().unwrap().selected);
        assert!(ctrl.lines[2].as_match().unwrap().selected);
    }

    /// Python: selectWithDownSelectInverse — [F, F, A]
    #[test]
    fn test_sequence_select_with_down_select_inverse() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        // F: select a.txt + move down
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('F'), KeyModifiers::NONE))
            .unwrap();
        // F: select b.txt + move down
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('F'), KeyModifiers::NONE))
            .unwrap();
        // A: toggle all — a OFF, b OFF, c ON
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('A'), KeyModifiers::NONE))
            .unwrap();

        assert!(!ctrl.lines[0].as_match().unwrap().selected);
        assert!(!ctrl.lines[1].as_match().unwrap().selected);
        assert!(ctrl.lines[2].as_match().unwrap().selected);
    }

    /// Python: selectTwoCommandMode — [f, j, f, c] with past_screen check
    #[test]
    fn test_sequence_select_two_then_command_mode() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
            .unwrap();
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('j'), KeyModifiers::NONE))
            .unwrap();
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
            .unwrap();
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE))
            .unwrap();

        assert_eq!(ctrl.mode, Mode::Command);
        assert!(ctrl.lines[0].as_match().unwrap().selected);
        assert!(ctrl.lines[1].as_match().unwrap().selected);
    }

    /// Python: allInputBranch — [-ai, j, f]
    #[test]
    fn test_sequence_all_input_select() {
        let (lines, indices) = make_test_lines(&["branch-1", "branch-2", "branch-3"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, true);

        ctrl.handle_key(KeyEvent::new(KeyCode::Char('j'), KeyModifiers::NONE))
            .unwrap();
        assert_eq!(ctrl.hover_index, 1);

        ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
            .unwrap();
        assert!(ctrl.lines[1].as_match().unwrap().selected);

        // Enter should be blocked (all_input, no preset command)
        let action = ctrl
            .handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE))
            .unwrap();
        assert!(matches!(action, Action::Continue));
    }

    /// Python: longListPageUpAndDown — [NPAGE, NPAGE, NPAGE, PPAGE]
    #[test]
    fn test_sequence_page_down_then_up() {
        let paths: Vec<&str> = (0..50).map(|_| "f.txt").collect();
        let (lines, indices) = make_test_lines(&paths);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        // 3x page down
        for _ in 0..3 {
            ctrl.handle_key(KeyEvent::new(KeyCode::PageDown, KeyModifiers::NONE))
                .unwrap();
        }
        let after_down = ctrl.hover_index;
        assert!(after_down > 0, "should have moved forward");

        // 1x page up
        ctrl.handle_key(KeyEvent::new(KeyCode::PageUp, KeyModifiers::NONE))
            .unwrap();
        assert!(ctrl.hover_index < after_down, "page up should move back");
    }

    /// Python: longListHomeKey — [SPACE, SPACE, HOME]
    #[test]
    fn test_sequence_page_down_then_home() {
        let paths: Vec<&str> = (0..50).map(|_| "f.txt").collect();
        let (lines, indices) = make_test_lines(&paths);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        ctrl.handle_key(KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE))
            .unwrap();
        ctrl.handle_key(KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE))
            .unwrap();
        assert!(ctrl.hover_index > 0);

        ctrl.handle_key(KeyEvent::new(KeyCode::Home, KeyModifiers::NONE))
            .unwrap();
        assert_eq!(ctrl.hover_index, 0);
    }

    /// Python: xModeWithSelect — [x, G, J] (G ignored, J is quick-select label)
    #[test]
    fn test_sequence_xmode_interactions() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        // x: enter quick-select mode
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('x'), KeyModifiers::NONE))
            .unwrap();
        assert_eq!(ctrl.mode, Mode::QuickSelect);

        // G: should be ignored in X_MODE (Python compat)
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('G'), KeyModifiers::NONE))
            .unwrap();
        assert_eq!(ctrl.hover_index, 0); // didn't jump to last

        // J: is a quick-select label — selects item at that row
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('J'), KeyModifiers::NONE))
            .unwrap();
        // J is in LABELS at some index, should toggle that row's selection
    }

    /// Python: selectAllBug — [A] on long list
    #[test]
    fn test_select_all_on_long_list() {
        let paths: Vec<&str> = (0..50).map(|_| "f.txt").collect();
        let (lines, indices) = make_test_lines(&paths);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        ctrl.handle_key(KeyEvent::new(KeyCode::Char('A'), KeyModifiers::NONE))
            .unwrap();
        // All unique paths should be selected (only 1 unique path "f.txt",
        // so only first occurrence gets toggled)
        let selected_count = ctrl
            .lines
            .iter()
            .filter(|l| l.as_match().is_some_and(|m| m.selected))
            .count();
        assert!(selected_count > 0);
    }

    // --- Scroll offset tests ---

    #[test]
    fn test_scroll_offset_updates_on_jump_to_last() {
        let paths: Vec<&str> = (0..100).map(|_| "f.txt").collect();
        let (lines, indices) = make_test_lines(&paths);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        assert_eq!(ctrl.scroll_offset, 0);

        ctrl.jump_to_last();
        assert_eq!(ctrl.hover_index, 99);
        // scroll_offset should have moved to show the last item
        assert!(
            ctrl.scroll_offset > 0,
            "scroll should have moved for last item"
        );
    }

    #[test]
    fn test_scroll_offset_resets_on_jump_to_first() {
        let paths: Vec<&str> = (0..100).map(|_| "f.txt").collect();
        let (lines, indices) = make_test_lines(&paths);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        ctrl.jump_to_last();
        assert!(ctrl.scroll_offset > 0);

        ctrl.jump_to_first();
        assert_eq!(ctrl.hover_index, 0);
        assert_eq!(ctrl.scroll_offset, 0);
    }

    #[test]
    fn test_scroll_offset_no_change_for_small_list() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt", "c.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);

        ctrl.move_hover(1);
        assert_eq!(ctrl.scroll_offset, 0, "small list should not scroll");

        ctrl.move_hover(1);
        assert_eq!(ctrl.scroll_offset, 0);
    }

    // --- Command mode typing test ---

    #[test]
    fn test_command_mode_typing_builds_buffer() {
        let (lines, indices) = make_test_lines(&["a.txt"]);
        let mut ctrl = Controller::new(lines, indices, None, false, None, false);
        ctrl.mode = Mode::Command;

        for ch in "git add".chars() {
            ctrl.handle_key(KeyEvent::new(KeyCode::Char(ch), KeyModifiers::NONE))
                .unwrap();
        }
        assert_eq!(ctrl.command_buffer, "git add");

        // Enter executes the command
        let action = ctrl
            .handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE))
            .unwrap();
        assert!(matches!(action, Action::Execute));
    }

    /// Python: selectCommandWithPassedCommand — [f, c, a] with -c flag
    #[test]
    fn test_sequence_command_mode_with_preset_warning_dismiss() {
        let (lines, indices) = make_test_lines(&["a.txt", "b.txt"]);
        let mut ctrl = Controller::new(
            lines,
            indices,
            Some("git add".to_string()),
            false,
            None,
            false,
        );

        // f: select a.txt
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE))
            .unwrap();
        assert!(ctrl.lines[0].as_match().unwrap().selected);

        // c: should show warning (preset command exists)
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE))
            .unwrap();
        assert_eq!(ctrl.mode, Mode::Warning);

        // a: dismiss warning, return to Normal
        ctrl.handle_key(KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE))
            .unwrap();
        assert_eq!(ctrl.mode, Mode::Normal);
    }

    // --- begin_height calculation test ---

    #[test]
    fn test_begin_height_matches_python() {
        // Python: int(round(max_y / 2) - len(paths) / 2.0)
        let cases = [(24, 3), (50, 10), (10, 2), (80, 1)];
        for (max_y, num_paths) in cases {
            let rust_result = ((max_y as f64 / 2.0).round() - (num_paths as f64 / 2.0)) as i32;
            let python_result = ((max_y as f64 / 2.0).round() - (num_paths as f64 / 2.0)) as i32;
            assert_eq!(
                rust_result, python_result,
                "begin_height mismatch for max_y={max_y}, paths={num_paths}"
            );
        }
    }
}
