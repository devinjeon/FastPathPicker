use std::io::{self, BufRead};

use crate::format::FormattedText;
use crate::line::{Line, LineMatch, SimpleLine};
use crate::parse;

/// Process stdin and return parsed line objects.
pub fn get_line_objs_from_stdin(
    validate_file_exists: bool,
    all_input: bool,
) -> io::Result<Vec<Line>> {
    let stdin = io::stdin();
    let lines: Vec<String> = stdin.lock().lines().collect::<io::Result<Vec<_>>>()?;
    Ok(get_line_objs_from_lines(
        &lines,
        validate_file_exists,
        all_input,
    ))
}

/// Process a list of lines and return parsed line objects.
pub fn get_line_objs_from_lines(
    lines: &[String],
    validate_file_exists: bool,
    all_input: bool,
) -> Vec<Line> {
    lines
        .iter()
        .enumerate()
        .map(|(index, line)| {
            let expanded = line.replace('\t', "    ");
            let formatted = FormattedText::new(&expanded);

            match parse::match_line(&expanded, validate_file_exists, all_input) {
                Some(result) => Line::Match(LineMatch::new(
                    formatted,
                    result.path,
                    result.line_num,
                    index,
                    expanded,
                )),
                None => Line::Simple(SimpleLine::new(formatted, index, expanded)),
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
mod tests {
    use super::*;

    #[test]
    fn test_empty_input() {
        let lines: Vec<String> = vec![];
        let result = get_line_objs_from_lines(&lines, false, false);
        assert!(result.is_empty());
    }

    #[test]
    fn test_simple_file_match() {
        let lines = vec!["src/main.rs:42: something".to_string()];
        let result = get_line_objs_from_lines(&lines, false, false);
        assert_eq!(result.len(), 1);
        assert!(result[0].as_match().is_some());
    }

    #[test]
    fn test_no_match_line() {
        let lines = vec!["just some text with no file".to_string()];
        let result = get_line_objs_from_lines(&lines, false, false);
        assert_eq!(result.len(), 1);
        assert!(result[0].as_match().is_none());
    }

    #[test]
    fn test_tab_expansion() {
        let lines = vec!["\tsrc/main.rs".to_string()];
        let result = get_line_objs_from_lines(&lines, false, false);
        assert_eq!(result.len(), 1);
        // Tab should be expanded to 4 spaces
        assert!(result[0].original_line().starts_with("    "));
    }

    #[test]
    fn test_all_input_mode() {
        let lines = vec!["  some branch  ".to_string(), "another branch".to_string()];
        let result = get_line_objs_from_lines(&lines, false, true);
        // All non-empty trimmed lines should match
        for line in &result {
            assert!(line.as_match().is_some());
        }
    }
}
