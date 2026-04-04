# fpp (fast-path-picker)

A fast Rust rewrite of Facebook's [PathPicker](https://github.com/facebook/PathPicker).

Parses file paths from stdin and presents an interactive terminal UI for selecting files to open in your editor or run commands on.

## Installation

```bash
# From source
make build
make install  # installs to ~/.cargo/bin/fpp

# Or directly
cargo install --path .
```

## Usage

Pipe any command output to `fpp`:

```bash
git status | fpp
grep -rn "TODO" src/ | fpp
find . -name "*.rs" | fpp
git diff --name-only HEAD~5 | fpp
```

### CLI Arguments

| Argument | Description |
|----------|-------------|
| `-c`, `--command <CMD>` | Command to run on selected files (e.g., `-c git add`) |
| `-e`, `--execute-keys <KEYS>` | Auto-execute keys on startup (e.g., `-e END`) |
| `-n`, `--no-file-checks` | Disable filesystem validation |
| `--all-input` | Treat all input lines as matches |
| `--non-interactive` | Run in non-interactive subshell |
| `-a`, `--all` | Auto-select all files on startup |
| `--clean` | Remove all state files |
| `-r`, `--record` | Record input/output for testing |
| `--keep-open` | Keep open after selection (loop until Ctrl-C) |
| `--debug` | Print execution directory |

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `j` / `Down` | Move down |
| `k` / `Up` | Move up |
| `Space` / `PageDown` | Page down |
| `b` / `PageUp` | Page up |
| `g` / `Home` | Jump to first |
| `G` / `End` | Jump to last |
| `f` | Toggle selection |
| `F` | Toggle selection + move down |
| `A` | Toggle select all |
| `x` | Quick-select mode |
| `c` | Command mode |
| `d` | File description |
| `Enter` | Open selected files |
| `q` | Quit |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `FPP_DIR` | State directory (default: `~/.cache/fpp`) |
| `FPP_EDITOR` | Editor (highest priority) |
| `VISUAL` | Editor fallback |
| `EDITOR` | Editor fallback |
| `FPP_DISABLE_SPLIT` | Disable vim split panes |
| `FPP_LINENUM_SEP` | Custom line number separator |

## Development

```bash
make dev        # debug build
make build      # release build
make test       # all tests
make test-unit  # unit tests only
make lint       # clippy + fmt check
make fmt        # auto-format
make qa         # compare with original PathPicker
make all        # lint + test + build
```

## Testing

Unit tests include:
- 40+ parsing test cases ported from the original Python implementation
- Fuzz tests with prefix/suffix combinations
- File existence validation tests with fixture files in `tests/inputs/`
- All-input mode tests
- Path resolution tests (prepend_dir)

## Compatibility

Drop-in replacement for the original Python PathPicker. All CLI arguments, keyboard shortcuts, environment variables, and state file locations are compatible.

Note: Short aliases use double-dash format (`--nfc`, `--ai`, `--ni`, `--ko`) instead of the Python original's single-dash format (`-nfc`, `-ai`, `-ni`, `-ko`).

## License

MIT
