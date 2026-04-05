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
        };

        if initial_select_all {
            ctrl.toggle_select_all();
        }

        // Python does NOT load previous selection on startup - only saves on exit.
        // Removed selection loading to match Python behavior.

        ctrl
    }

    /// Run the interactive UI loop. Returns when the user makes a selection or quits.
    pub fn run(&mut self) -> Result<()> {
        if self.match_indices.is_empty() {
            output::output_nothing()?;
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
                Action::Execute => {
                    return self.execute_selection();
                }
            }
        }

        loop {
            if self.dirty {
                self.render(stdout)?;
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

    fn handle_key(&mut self, key: KeyEvent) -> Result<Action> {
        // Ctrl-C always quits
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            return Ok(Action::Quit);
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
        match key.code {
            KeyCode::Char('q') => Ok(Action::Quit),
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
            KeyCode::Char('G') | KeyCode::End => {
                self.jump_to_last();
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
            KeyCode::Char('A') => {
                self.toggle_select_all();
                Ok(Action::Continue)
            }
            KeyCode::Char('c') => {
                if self.preset_command.is_some() {
                    self.mode = Mode::Warning;
                } else {
                    self.mode = Mode::Command;
                }
                Ok(Action::Continue)
            }
            KeyCode::Char('x') => {
                self.mode = Mode::QuickSelect;
                Ok(Action::Continue)
            }
            KeyCode::Char('d') => {
                self.show_description = true;
                Ok(Action::Continue)
            }
            KeyCode::Enter => {
                // In all_input mode, Enter only works if a preset command is set
                if self.all_input && self.preset_command.is_none() {
                    Ok(Action::Continue)
                } else {
                    Ok(Action::Execute)
                }
            }
            _ => {
                // Check custom bindings after all built-in keys (like Python)
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

    fn handle_command_key(&mut self, key: KeyEvent) -> Result<Action> {
        match key.code {
            KeyCode::Enter => {
                if self.command_buffer.is_empty() {
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
                self.command_buffer.pop();
                if self.command_buffer.is_empty() {
                    self.mode = Mode::Normal;
                }
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
            // Python: G is ignored in X_MODE, but END still works
            KeyCode::Char('G') => Ok(Action::Continue),
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
            _ => Ok(Action::Continue),
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
        let (width, height) = terminal::size().unwrap_or((80, 24));
        let chrome = Chrome::new(width, height);
        let page = (chrome.content_height as usize) / 2;
        self.move_hover(page as isize);
    }

    fn page_up(&mut self) {
        let (width, height) = terminal::size().unwrap_or((80, 24));
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
        let (width, height) = terminal::size().unwrap_or((80, 24));
        let chrome = Chrome::new(width, height);
        let window_height = chrome.content_height as usize;
        let half_height = window_height.div_ceil(2);

        let hovered_line_idx = self.match_indices[self.hover_index];

        // Python uses negative offset; we use positive. Equivalent logic:
        // desired_top_row = max(hovered_line_idx - half_height, 0)
        let desired_top_row = hovered_line_idx.saturating_sub(half_height);
        let old_offset = self.scroll_offset;

        // Leeway: don't reposition if within half_height/2 of desired
        // unless the hovered line is currently off-screen
        let hovered_off_screen =
            hovered_line_idx < old_offset || hovered_line_idx >= old_offset + window_height;
        let drift = desired_top_row.abs_diff(old_offset);

        if drift > half_height / 2 || hovered_off_screen {
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

    // --- Rendering ---

    fn render(&self, stdout: &mut io::Stdout) -> Result<()> {
        let (width, height) = terminal::size()?;
        let chrome = Chrome::new(width, height);

        // Show cursor in command mode, hide otherwise
        if self.mode == Mode::Command {
            execute!(stdout, cursor::Show)?;
        } else {
            execute!(stdout, cursor::Hide)?;
        }

        execute!(stdout, terminal::Clear(ClearType::All))?;

        // Warning overlay: render and return (event_loop handles dismissal)
        if self.mode == Mode::Warning {
            self.render_preset_warning(stdout, &chrome)?;
            stdout.flush()?;
            return Ok(());
        }

        // Scrollbar based on total lines (not just matches)
        let scrollbar = ScrollBar::new(self.lines.len(), chrome.content_height as usize);
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

            execute!(stdout, cursor::MoveTo(0, row as u16))?;

            // Scrollbar (Python ASCII art style: ===, /-\, |-|, \-/, " . ")
            if has_scrollbar {
                if let Some(ref range) = sb_range {
                    let sb_str = scrollbar::render_scrollbar_row(row, range);
                    execute!(stdout, style::Print(sb_str))?;
                } else {
                    execute!(stdout, style::Print("    "))?;
                }
                // Column 4 border (Python draws " " at x=4)
                execute!(stdout, style::Print(" "))?;
            }

            // Quick-select label
            if in_xmode {
                if let Some(label) = quick_select::get_label(row) {
                    execute!(
                        stdout,
                        SetForegroundColor(Color::Yellow),
                        style::Print(format!("{label} ")),
                        SetForegroundColor(Color::Reset),
                    )?;
                } else {
                    execute!(stdout, style::Print("  "))?;
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

                let before: String = plain.chars().take(ms).collect();
                let matched: String = plain.chars().skip(ms).take(me - ms).collect();
                let after: String = plain.chars().skip(me).collect();

                let arrow_len = if is_selected { 5 } else { 0 };
                let max_len = text_width.saturating_sub(arrow_len);

                // Print before_text (plain, no attributes)
                let before_display = truncate_line(&before, max_len);
                let before_printed = before_display.chars().count();
                execute!(stdout, style::Print(&before_display))?;

                // Set attributes for the match portion
                if is_hovered && m.selected {
                    execute!(
                        stdout,
                        SetBackgroundColor(Color::Red),
                        SetForegroundColor(Color::White),
                        SetAttribute(Attribute::Bold),
                    )?;
                } else if is_hovered {
                    execute!(
                        stdout,
                        SetBackgroundColor(Color::Blue),
                        SetForegroundColor(Color::White),
                        SetAttribute(Attribute::Bold),
                    )?;
                } else if m.selected {
                    execute!(
                        stdout,
                        SetBackgroundColor(Color::Green),
                        SetForegroundColor(Color::White),
                        SetAttribute(Attribute::Bold),
                    )?;
                } else if !self.all_input {
                    execute!(stdout, SetAttribute(Attribute::Underlined))?;
                }

                // Arrow decorator (part of decorated_match)
                if m.selected {
                    execute!(stdout, style::Print("|===>"))?;
                }

                // Print match portion with attributes
                let remaining = max_len.saturating_sub(before_printed);
                let match_display = truncate_line(&matched, remaining);
                let match_printed = match_display.chars().count();
                execute!(stdout, style::Print(&match_display))?;

                // Reset attributes
                execute!(
                    stdout,
                    SetBackgroundColor(Color::Reset),
                    SetForegroundColor(Color::Reset),
                    SetAttribute(Attribute::Reset),
                )?;

                // Print after_text (plain, no attributes)
                let after_remaining = remaining.saturating_sub(match_printed);
                if after_remaining > 0 {
                    let after_display = truncate_line(&after, after_remaining);
                    execute!(stdout, style::Print(&after_display))?;
                }
            } else {
                // SimpleLine: no attributes, just print with ANSI preservation
                let ft = line.formatted_text();
                let display = if ft.has_ansi() {
                    ft.raw_truncated_with_decorator(text_width)
                } else {
                    truncate_line(ft.plain_text(), text_width)
                };
                execute!(stdout, style::Print(&display))?;
            }
        }

        // Bottom info bar (narrow mode) or sidebar (wide mode)
        self.render_info(stdout, &chrome)?;

        stdout.flush()?;
        Ok(())
    }

    fn render_preset_warning(&self, stdout: &mut io::Stdout, _chrome: &Chrome) -> Result<()> {
        let (_, height) = terminal::size()?;
        let y_start = height.saturating_sub(4) / 2;
        let x_start = 2u16;

        execute!(
            stdout,
            cursor::MoveTo(x_start, y_start),
            SetBackgroundColor(Color::Red),
            SetForegroundColor(Color::White),
            style::Print("Oh no! You already provided a command so you cannot enter command mode."),
            SetBackgroundColor(Color::Reset),
            SetForegroundColor(Color::Reset),
        )?;

        if let Some(ref cmd) = self.preset_command {
            execute!(
                stdout,
                cursor::MoveTo(x_start, y_start + 1),
                style::Print(format!("The command you provided was \"{cmd}\" ")),
            )?;
        }

        execute!(
            stdout,
            cursor::MoveTo(x_start, y_start + 2),
            style::Print("Press any key to go back to selecting paths."),
        )?;

        Ok(())
    }

    fn render_info(&self, stdout: &mut io::Stdout, chrome: &Chrome) -> Result<()> {
        let total = self.match_indices.len();
        let selected_count = self
            .match_indices
            .iter()
            .filter(|&&idx| self.lines[idx].as_match().is_some_and(|m| m.selected))
            .count();

        let info = format!(
            " {}/{} files | {} selected",
            self.hover_index + 1,
            total,
            selected_count,
        );

        let mode_str = match self.mode {
            Mode::Normal => "NORMAL",
            Mode::Command => "COMMAND",
            Mode::QuickSelect => "X-MODE",
            Mode::Warning => "NORMAL",
        };

        if chrome.is_wide {
            // Sidebar rendering
            let sidebar_x = chrome.content_width;
            execute!(
                stdout,
                cursor::MoveTo(sidebar_x, 0),
                SetForegroundColor(Color::Cyan),
                style::Print(format!(" [{mode_str}]")),
                SetForegroundColor(Color::Reset),
            )?;
            execute!(stdout, cursor::MoveTo(sidebar_x, 1), style::Print(&info),)?;

            // Show file description when toggled with 'd'
            if self.show_description {
                if let Some(&idx) = self.match_indices.get(self.hover_index) {
                    if let Some(m) = self.lines[idx].as_match() {
                        let desc = m.get_file_description();
                        let header = format!("Description for {}:", m.path);
                        let max_w = chrome.sidebar_width as usize - 2;
                        let truncated_header: String = header.chars().take(max_w).collect();
                        execute!(
                            stdout,
                            cursor::MoveTo(sidebar_x, 3),
                            style::Print(format!(" {truncated_header}")),
                        )?;
                        for (i, line) in desc.iter().enumerate() {
                            let truncated: String =
                                line.chars().take(max_w.saturating_sub(6)).collect();
                            execute!(
                                stdout,
                                cursor::MoveTo(sidebar_x, (i + 5) as u16),
                                style::Print(format!("     * {truncated}")),
                            )?;
                        }
                    }
                }
            }
        } else {
            // Bottom info bar
            let info_y = chrome.content_height;
            execute!(
                stdout,
                cursor::MoveTo(0, info_y),
                SetForegroundColor(Color::Cyan),
                style::Print(format!(" [{mode_str}]{info}")),
                SetForegroundColor(Color::Reset),
            )?;

            if self.mode == Mode::Command {
                execute!(
                    stdout,
                    cursor::MoveTo(0, info_y + 1),
                    style::Print(format!(" > {}", self.command_buffer)),
                )?;
                execute!(
                    stdout,
                    cursor::MoveTo(0, info_y + 2),
                    SetForegroundColor(Color::DarkGrey),
                    style::Print(super::chrome::USAGE_COMMAND),
                    SetForegroundColor(Color::Reset),
                )?;
            } else {
                let usage = match self.mode {
                    Mode::QuickSelect => super::chrome::USAGE_XMODE,
                    _ => {
                        if self.all_input {
                            super::chrome::USAGE_HEADER_ALL_INPUT
                        } else {
                            super::chrome::USAGE_HEADER
                        }
                    }
                };
                execute!(
                    stdout,
                    cursor::MoveTo(0, info_y + 1),
                    SetForegroundColor(Color::DarkGrey),
                    style::Print(usage),
                    SetForegroundColor(Color::Reset),
                )?;
            }
        }

        Ok(())
    }
}

enum Action {
    Continue,
    Quit,
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
}
