use super::*;

#[test]
fn test_narrow_mode() {
    let chrome = Chrome::new(80, 24);
    assert!(!chrome.is_wide);
    assert_eq!(chrome.sidebar_width, 0);
    assert_eq!(chrome.content_width, 80);
}

#[test]
fn test_wide_mode() {
    let chrome = Chrome::new(220, 50);
    assert!(chrome.is_wide);
    assert_eq!(chrome.sidebar_width, SIDEBAR_WIDTH);
    assert_eq!(chrome.content_width, 170);
}

#[test]
fn test_content_start_x_with_scrollbar() {
    let chrome = Chrome::new(80, 24);
    assert_eq!(chrome.content_start_x(true, false), 5);
    assert_eq!(chrome.content_start_x(false, false), 0);
    assert_eq!(chrome.content_start_x(false, true), 5);
}

#[test]
fn test_command_prompt_strings_match_python() {
    assert_eq!(
        SHORT_COMMAND_PROMPT,
        "Type a command below! Paths will be appended or replace $F"
    );
    assert_eq!(
        SHORT_COMMAND_PROMPT2,
        "Enter a blank line to go back to the selection process"
    );
    assert_eq!(SHORT_PATHS_HEADER, "Paths you have selected:");
}

#[test]
fn test_usage_page_contains_python_keys() {
    assert!(USAGE_PAGE.contains("[f] toggle the selection of a file"));
    assert!(USAGE_PAGE.contains("[F] toggle and move downward by 1"));
    assert!(USAGE_PAGE.contains("[A] toggle selection of all (unique) files"));
    assert!(USAGE_PAGE.contains("[x] quick select mode"));
    assert!(USAGE_PAGE.contains("[d] describe file"));
    assert!(USAGE_PAGE.contains("[<Enter>] open all selected files"));
    assert!(USAGE_PAGE.contains("[c] enter command mode"));
}

#[test]
fn test_usage_command_page_contains_python_examples() {
    assert!(USAGE_COMMAND_PAGE.contains("git add"));
    assert!(USAGE_COMMAND_PAGE.contains("git checkout HEAD~1 --"));
    assert!(USAGE_COMMAND_PAGE.contains("rm -rf"));
    assert!(USAGE_COMMAND_PAGE.contains("$F"));
    assert!(USAGE_COMMAND_PAGE.contains("scp $F dev:~/backup"));
}
