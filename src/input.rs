use std::io::{self, BufRead};

use crate::format::FormattedText;
use crate::line::{Line, LineMatch, SimpleLine};
use crate::parse;

/// Read raw lines from stdin.
pub fn read_stdin_lines() -> io::Result<Vec<String>> {
    let stdin = io::stdin();
    stdin.lock().lines().collect()
}

/// Process a list of lines and return parsed line objects.
pub fn get_line_objs_from_lines(
    lines: &[String],
    validate_file_exists: bool,
    all_input: bool,
) -> Vec<Line> {
    lines
        .iter()
        .map(|line| {
            let expanded = line.replace('\t', "    ");
            let formatted = FormattedText::new(&expanded);

            // Match regex on ANSI-stripped plain text (like Python's str(formatted_line))
            match parse::match_line(formatted.plain_text(), validate_file_exists, all_input) {
                Some(result) => {
                    // Python resolves path at construction time:
                    // self.path = path if all_input else parse.prepend_dir(path, ...)
                    let resolved_path = if all_input {
                        result.path.clone()
                    } else {
                        parse::prepend_dir(&result.path, validate_file_exists)
                    };
                    Line::Match(LineMatch::new(
                        formatted,
                        resolved_path,
                        result.line_num,
                        expanded,
                        result.match_start,
                        result.match_end,
                    ))
                }
                None => Line::Simple(SimpleLine::new(formatted, expanded)),
            }
        })
        .collect()
}

/// Extract only the LineMatch entries from a list of lines.
pub fn get_matches(lines: &[Line]) -> Vec<usize> {
    lines
        .iter()
        .enumerate()
        .filter_map(|(i, line)| line.as_match().map(|_| i))
        .collect()
}

#[cfg(test)]
#[path = "input_tests.rs"]
mod tests;
