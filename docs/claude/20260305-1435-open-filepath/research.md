# Research: Open Filepath Feature for WezTerm

## Overview

The wezterm config at `config.lua` is a ~209-line Lua configuration that manages fonts, keybindings, hyperlink rules, and URL opening. It supports a `local.lua` override system for machine-specific settings. The goal is to add a feature that lets the user quick-select filepaths visible in the terminal and open them with a configurable command.

## Architecture

### File Structure

- **`config.lua`** — Main config. Defines keybindings, hyperlink rules, URL transforms, and event handlers.
- **`local.example.lua`** — Template for machine-specific overrides (font, hyperlink rules, url_transforms, `apply_to_config()`).
- **`local.lua`** (gitignored) — Actual local overrides.

### Config Flow

1. Default variables set (font, decorations, url_transforms)
2. `local.lua` loaded via `pcall(require("local"))` — overrides defaults
3. Hyperlink rules assembled: wezterm defaults → custom rules → local rules
4. Hyperlink regexes extracted into a parallel array for QuickSelect
5. Config builder populated with all settings
6. `local_config.apply_to_config(config)` called last for final overrides

### Existing URL Opening System (Ctrl-Shift-O) — `config.lua:159-183`

This is the closest existing feature to what we're building:

```lua
key = "O", mods = "SHIFT|CTRL",
action = wezterm.action({
  QuickSelectArgs = {
    patterns = hyperlink_regexes,
    action = wezterm.action_callback(function(window, pane)
      local url = window:get_selection_text_for_pane(pane)
      -- Apply URL transforms
      for _, transform in ipairs(url_transforms) do
        for _, prefix in ipairs(transform.prefixes) do
          if starts_with(url, prefix) then
            url = transform.format(url)
            break
          end
        end
      end
      wezterm.log_info("Opening: " .. url)
      wezterm.open_with(url)
    end),
  },
})
```

**Key patterns:**

- Uses `QuickSelectArgs` to highlight matching text in the terminal
- Uses `action_callback` to run Lua when user selects an item
- `window:get_selection_text_for_pane(pane)` gets the selected text
- `wezterm.open_with(url)` opens with system default handler
- URL transforms allow pre-processing before opening

### Existing Scrollback Handler — `config.lua:95-114`

Opens scrollback in nvim using `SpawnCommandInNewWindow`. Shows the pattern for spawning external commands.

## Relevant WezTerm APIs

### `wezterm.open_with(path_or_url [, application])`

- Opens a path or URL with the system default handler, or a specified application
- `wezterm.open_with("file.txt")` — default handler
- `wezterm.open_with("file.txt", "nvim")` — won't work directly (nvim needs a terminal)
- For terminal apps, need `SpawnCommandInNewWindow` or `SpawnCommandInNewTab` instead

### `QuickSelectArgs`

- **`patterns`** — Array of regex patterns to highlight in terminal output
- **`action`** — Callback via `wezterm.action_callback()` when item selected
- **`label`** — Text shown at bottom of overlay (default: "copy")
- **`alphabet`** — Characters used for selection labels
- **`scope_lines`** — How many lines above/below viewport to search (default: 1000)

### `PromptInputLine`

- Displays a text input prompt overlay
- **`description`** — Prompt text displayed (supports `wezterm.format()`)
- **`action`** — Callback `(window, pane, line)` where `line` is user input or `nil` if cancelled
- **`prompt`** — Input prompt text (nightly only, defaults to `"> "`)
- **`initial_value`** — Pre-fill value (nightly only)

### `InputSelector`

- Displays a list of choices for user selection
- **`title`** — Overlay title
- **`choices`** — Table of `{label, id}` entries
- **`action`** — Callback `(window, pane, id, label)`
- **`fuzzy`** — Enable fuzzy finding (boolean)
- Supports keyboard navigation and fuzzy search

### `pane:get_current_working_dir()`

- Returns a `Url` object (or nil) representing the pane's current working directory
- `Url.file_path` — Decoded file path string (e.g., `/home/user/project`)
- Works via OSC 7 escape sequences, with OS-specific fallbacks
- Critical for resolving relative paths

### `SpawnCommandInNewWindow` / `SpawnCommandInNewTab`

- Spawns a command in a new window/tab
- Takes `{args = {"cmd", "arg1", ...}, cwd = "..."}`
- Needed for opening files in terminal applications (nvim, less, etc.)

## Design Considerations

### Filepath Regex Patterns

Need regex patterns that match filepaths in terminal output. Common forms:

- Absolute: `/home/user/file.txt`, `/Users/hhhuang/.dotfiles/wezterm/config.lua`
- Relative: `./src/main.rs`, `../config.lua`, `src/lib.rs`
- With line numbers: `src/main.rs:42`, `src/main.rs:42:10` (common in compiler output, grep, etc.)
- Home-relative: `~/Documents/file.txt`
// Also handle `$HOME`, `$XDG_CONFIG_DIR`, etc.
- Quoted: `"path/to/file"`, `'path/to/file'`

### Path Resolution

Relative paths need to be resolved against the pane's current working directory via `pane:get_current_working_dir()`. The `Url` object's `file_path` property gives the decoded path.

### Opening Command

The user wants to specify the command used to open the file. Options:

1. **Default**: Use `wezterm.open_with(path)` for system default
2. **Terminal app (nvim, vim, less)**: Use `SpawnCommandInNewWindow` with `{args = {cmd, path}}`
3. **GUI app**: Use `wezterm.open_with(path, app_name)`

For terminal apps, `wezterm.open_with` won't work — need to spawn in a new window/tab.

### Interaction Flow Options

**Option A: QuickSelect only** — Select filepath, open with pre-configured default command
**Option B: QuickSelect → PromptInputLine** — Select filepath, then prompt for command
**Option C: QuickSelect → InputSelector** — Select filepath, then pick from a list of commands

Option B or C is most aligned with the user's request ("type the command"). Option B gives the most flexibility. Option C is more discoverable but less flexible.

A hybrid approach could work: QuickSelect the filepath, then show an InputSelector with common commands plus a "custom..." option that chains to PromptInputLine.

### Line Number Handling

If the regex captures `file.txt:42:10`, the path and line number should be parsed separately. For nvim/vim, line numbers can be passed as `+42` argument.

### Local Config Integration

Following existing patterns, the open command configuration should be overridable via `local.lua`:

- Default open command (e.g., `"nvim"`, or the system default)
- Command presets for InputSelector
- Whether to open in new window vs new tab

## Edge Cases & Gotchas

1. **`pane:get_current_working_dir()` may return nil** — Need fallback (e.g., `$HOME`)
2. **Relative paths without `./` prefix** — Hard to distinguish from regular words. `src/main.rs` looks like a path but `hello/world` might not be. File extension helps.
3. **Paths with spaces** — Need careful regex. Quoted paths help but unquoted paths with spaces are ambiguous.
4. **`wezterm.open_with` vs `SpawnCommand`** — Terminal apps (nvim, vim, less, bat) need `SpawnCommandInNewWindow`; GUI apps and system-default can use `open_with`.
5. **Line numbers in path** — `file.txt:42:10` needs parsing to extract path and line/column.
6. **Symlinks and non-existent files** — Selected text might not be a valid file; graceful error handling needed.
7. **The existing Ctrl-Shift-O binding** — New feature should use a different keybinding to avoid conflict.

## Current State

- The codebase is clean and well-organized (~209 lines)
- Local override pattern is well-established
- No existing filepath opening feature
- Hyperlink/URL opening (Ctrl-Shift-O) provides a solid template to build from
