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
use crate::ui::scrollbar::ScrollBar;

/// Modes the controller can be in.
#[derive(Debug, PartialEq)]
enum Mode {
    /// Normal navigation and selection mode
    Normal,
    /// Command input mode
    Command,
    /// Quick-select mode with labels
    QuickSelect,
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
    select_all_state: bool,
}

impl Controller {
    pub fn new(
        lines: Vec<Line>,
        match_indices: Vec<usize>,
        preset_command: Option<String>,
        initial_select_all: bool,
        execute_keys: Option<String>,
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
            select_all_state: false,
        };

        if initial_select_all {
            ctrl.toggle_select_all();
        }

        // Load previous selection if available
        if let Ok(selection) = state::load_selection() {
            for &idx in &selection.selected_indices {
                if let Some(line) = ctrl.lines.get_mut(idx) {
                    if let Some(m) = line.as_match_mut() {
                        m.selected = true;
                    }
                }
            }
        }

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
                    self.save_selection()?;
                    state::write_script("")?;
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
                                self.save_selection()?;
                                state::write_script("")?;
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
            Mode::Normal => self.handle_normal_key(key),
        }
    }

    fn handle_normal_key(&mut self, key: KeyEvent) -> Result<Action> {
        // Check custom bindings first
        if let KeyCode::Char(ch) = key.code {
            for binding in &self.custom_bindings {
                if binding.key.len() == 1 && binding.key == ch.to_string() {
                    return self.execute_custom_binding(&binding.command.clone());
                }
            }
        }

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
                    // Warn: preset command already set
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
                // Description toggle - handled in render
                Ok(Action::Continue)
            }
            KeyCode::Enter => Ok(Action::Execute),
            _ => Ok(Action::Continue),
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
        match key.code {
            KeyCode::Char('x') | KeyCode::Esc => {
                self.mode = Mode::Normal;
                Ok(Action::Continue)
            }
            KeyCode::Char(ch) => {
                if let Some(relative_idx) = quick_select::find_index_for_label(ch) {
                    let viewport_start = self.scroll_offset;
                    let absolute_match_idx = viewport_start + relative_idx;
                    if absolute_match_idx < self.match_indices.len() {
                        let line_idx = self.match_indices[absolute_match_idx];
                        if let Some(m) = self.lines[line_idx].as_match_mut() {
                            m.toggle_select();
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
        let new_idx = if delta > 0 {
            (self.hover_index + delta as usize).min(self.match_indices.len() - 1)
        } else {
            self.hover_index.saturating_sub((-delta) as usize)
        };
        self.hover_index = new_idx;
        self.adjust_scroll();
    }

    fn page_down(&mut self) {
        let (_, height) = terminal::size().unwrap_or((80, 24));
        let page = (height as usize) / 2;
        self.move_hover(page as isize);
    }

    fn page_up(&mut self) {
        let (_, height) = terminal::size().unwrap_or((80, 24));
        let page = (height as usize) / 2;
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
        let (_, height) = terminal::size().unwrap_or((80, 24));
        let chrome = Chrome::new(terminal::size().unwrap_or((80, 24)).0, height);
        let viewport = chrome.content_height as usize;

        if self.hover_index < self.scroll_offset {
            self.scroll_offset = self.hover_index;
        } else if self.hover_index >= self.scroll_offset + viewport {
            self.scroll_offset = self.hover_index.saturating_sub(viewport - 1);
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
        self.select_all_state = !self.select_all_state;
        let state = self.select_all_state;

        // Collect unique paths and their line indices
        let mut seen_paths = std::collections::HashSet::new();
        for &idx in &self.match_indices {
            if let Some(m) = self.lines[idx].as_match_mut() {
                if seen_paths.insert(m.path.clone()) {
                    m.selected = state;
                } else {
                    m.selected = false;
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
        let scrollbar = ScrollBar::new(self.match_indices.len(), chrome.content_height as usize);
        let has_scrollbar = scrollbar.is_active();
        let in_xmode = self.mode == Mode::QuickSelect;
        // content_start_x is used implicitly via text_width calculation
        let _ = chrome.content_start_x(has_scrollbar, in_xmode);
        let text_width = chrome.text_width(has_scrollbar, in_xmode) as usize;

        execute!(stdout, terminal::Clear(ClearType::All))?;

        // Render visible lines
        let viewport_end =
            (self.scroll_offset + chrome.content_height as usize).min(self.match_indices.len());

        let sb_range = scrollbar.calculate(self.scroll_offset);

        for (row, match_idx) in (self.scroll_offset..viewport_end).enumerate() {
            let line_idx = self.match_indices[match_idx];
            let line = &self.lines[line_idx];
            let is_hovered = match_idx == self.hover_index;

            execute!(stdout, cursor::MoveTo(0, row as u16))?;

            // Scrollbar
            if has_scrollbar {
                let in_bar = sb_range
                    .as_ref()
                    .is_some_and(|r| row >= r.start_row && row < r.end_row);
                if in_bar {
                    execute!(stdout, style::Print("  > "))?;
                } else {
                    execute!(stdout, style::Print("    "))?;
                }
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

            // Line content
            let plain = line.formatted_text().plain_text();
            let display: String = if plain.len() > text_width {
                plain.chars().take(text_width).collect()
            } else {
                plain.to_string()
            };

            if let Some(m) = line.as_match() {
                if is_hovered && m.selected {
                    execute!(
                        stdout,
                        SetBackgroundColor(Color::DarkBlue),
                        SetForegroundColor(Color::White),
                        SetAttribute(Attribute::Bold),
                    )?;
                } else if is_hovered {
                    execute!(
                        stdout,
                        SetBackgroundColor(Color::DarkGrey),
                        SetForegroundColor(Color::White),
                    )?;
                } else if m.selected {
                    execute!(
                        stdout,
                        SetForegroundColor(Color::DarkGreen),
                        SetAttribute(Attribute::Bold),
                    )?;
                }
            }

            execute!(stdout, style::Print(&display))?;
            execute!(
                stdout,
                SetBackgroundColor(Color::Reset),
                SetForegroundColor(Color::Reset),
                SetAttribute(Attribute::Reset),
            )?;
        }

        // Bottom info bar (narrow mode) or sidebar (wide mode)
        self.render_info(stdout, &chrome)?;

        stdout.flush()?;
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

            // Show file description if hovered
            if let Some(&idx) = self.match_indices.get(self.hover_index) {
                if let Some(m) = self.lines[idx].as_match() {
                    let desc = m.get_file_description();
                    for (i, line) in desc.iter().enumerate() {
                        let truncated: String = line
                            .chars()
                            .take(chrome.sidebar_width as usize - 2)
                            .collect();
                        execute!(
                            stdout,
                            cursor::MoveTo(sidebar_x, (i + 3) as u16),
                            style::Print(format!(" {truncated}")),
                        )?;
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
            } else {
                let usage = match self.mode {
                    Mode::QuickSelect => super::chrome::USAGE_XMODE,
                    _ => super::chrome::USAGE_HEADER,
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
                "PAGEUP" | "NPAGE" => Some(KeyEvent::new(KeyCode::PageUp, KeyModifiers::NONE)),
                "PAGEDOWN" | "PPAGE" => Some(KeyEvent::new(KeyCode::PageDown, KeyModifiers::NONE)),
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
