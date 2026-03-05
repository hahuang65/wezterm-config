# Plan: Open Filepath Feature

## Goal

Extend the existing Ctrl-Shift-O keybinding to handle both URLs and filepaths. URLs open in the browser as before. Filepaths are resolved (relative, absolute, `~/`, `$ENV_VAR`) and the user is prompted for a command to open them with.

## Research Reference

`docs/claude/20260305-1435-open-filepath/research.md`

## Approach

Merge filepath patterns into the existing Ctrl-Shift-O `QuickSelectArgs`. The `action_callback` detects whether the selection is a URL or a filepath:

- **URL** → apply url_transforms → `wezterm.open_with(url)` (existing behavior, unchanged)
- **Filepath** → resolve path → `PromptInputLine` for command → spawn

**Keybinding:** Ctrl-Shift-O (existing, enhanced)

**Flow:**
1. Ctrl-Shift-O → QuickSelect highlights URLs **and** filepaths
2. User selects one
3. If it looks like a URL → open in browser (existing behavior)
4. If it looks like a filepath → resolve it → prompt for command → spawn

## Detailed Changes

### `config.lua`

#### 1. Add filepath regex patterns (after line 82, before the keybinds comment)

```lua
-- Filepath patterns for QuickSelect (combined with hyperlink_regexes in Ctrl-Shift-O)
local filepath_patterns = {
  -- Absolute paths (Unix), optionally with :line or :line:col
  [[\b/[\w.\-]+(?:/[\w.\-]+)+(?::\d+)?(?::\d+)?\b]],
  -- Relative paths starting with ./ or ../
  [[\b\.\.?/[\w.\-]+(?:/[\w.\-]+)*(?::\d+)?(?::\d+)?\b]],
  -- Home-relative paths ~/...
  [[\b~/[\w.\-]+(?:/[\w.\-]+)*(?::\d+)?(?::\d+)?\b]],
  -- Environment variable paths $VAR/...
  [[\b\$\w+/[\w.\-]+(?:/[\w.\-]+)*(?::\d+)?(?::\d+)?\b]],
  -- Bare relative paths with file extension (to avoid matching random words)
  -- Matches: src/main.rs, lib/foo/bar.lua, config.lua (but not "hello/world")
  [[\b[\w.\-]+(?:/[\w.\-]+)*\.[\w]+(?::\d+)?(?::\d+)?\b]],
}
```

**Note:** QuickSelect patterns are Rust-flavored regex. Capture groups don't influence what gets selected — the entire match is the selection. The `:line:col` suffix is included in the selection and parsed in Lua.

#### 2. Add local config override for filepath patterns (in the local_config section, ~line 41-46)

```lua
  if local_config.filepath_patterns then
    for _, pattern in ipairs(local_config.filepath_patterns) do
      table.insert(filepath_patterns, pattern)
    end
  end
```

#### 3. Build a combined patterns array (after the filepath_patterns block)

```lua
-- Combine hyperlink regexes and filepath patterns for unified QuickSelect
local open_patterns = {}
for _, regex in ipairs(hyperlink_regexes) do
  table.insert(open_patterns, regex)
end
for _, pattern in ipairs(filepath_patterns) do
  table.insert(open_patterns, pattern)
end
```

#### 4. Add helper functions (after `starts_with`, ~line 8)

```lua
-- Check if a string looks like a URL
local function is_url(str)
  return str:match("^%w+://") ~= nil
end

-- Parse a filepath that may include :line and :line:col suffixes
local function parse_filepath(raw)
  local path, line, col = raw:match("^(.+):(%d+):(%d+)$")
  if path then
    return path, tonumber(line), tonumber(col)
  end
  path, line = raw:match("^(.+):(%d+)$")
  if path then
    return path, tonumber(line), nil
  end
  return raw, nil, nil
end

-- Resolve a filepath to an absolute path
local function resolve_filepath(path, cwd)
  -- Expand ~ to HOME
  if path:sub(1, 1) == "~" then
    local home = os.getenv("HOME") or ""
    return home .. path:sub(2)
  end
  -- Expand $ENV_VAR at the start
  local env_var = path:match("^%$(%w+)")
  if env_var then
    local val = os.getenv(env_var)
    if val then
      return val .. path:sub(#env_var + 2)  -- +2 for $ and the var name
    end
  end
  -- Already absolute
  if path:sub(1, 1) == "/" then
    return path
  end
  -- Relative path — prepend CWD
  if cwd then
    return cwd .. "/" .. path
  end
  return path
end
```

#### 5. Replace the Ctrl-Shift-O keybinding (lines 159-183)

Replace the entire existing block with:

```lua
  -- Open URLs in browser, filepaths with user-specified command
  {
    key = "O",
    mods = "SHIFT|CTRL",
    action = wezterm.action({
      QuickSelectArgs = {
        label = "open",
        patterns = open_patterns,
        action = wezterm.action_callback(function(window, pane)
          local raw = window:get_selection_text_for_pane(pane)

          -- 1. Direct URL: open in browser
          if is_url(raw) then
            wezterm.log_info("Opening URL: " .. raw)
            wezterm.open_with(raw)
            return
          end

          -- 2. URL transform match: transform and open in browser
          for _, transform in ipairs(url_transforms) do
            for _, prefix in ipairs(transform.prefixes) do
              if starts_with(raw, prefix) then
                local url = transform.format(raw)
                wezterm.log_info("Opening URL: " .. url)
                wezterm.open_with(url)
                return
              end
            end
          end

          -- 3. Filepath: resolve and prompt for command
          local path, line, col = parse_filepath(raw)

          local cwd = nil
          local cwd_url = pane:get_current_working_dir()
          if cwd_url then
            cwd = cwd_url.file_path
          end

          local resolved = resolve_filepath(path, cwd)
          wezterm.log_info("Selected filepath: " .. resolved
            .. (line and (":" .. line) or "")
            .. (col and (":" .. col) or ""))

          -- Prompt user for the command to open the file with
          window:perform_action(
            wezterm.action({
              PromptInputLine = {
                description = "Open " .. resolved .. " with command (empty for system default):",
                action = wezterm.action_callback(function(inner_window, inner_pane, cmd)
                  if cmd == nil then
                    return -- user cancelled
                  end

                  if cmd == "" then
                    wezterm.log_info("Opening with system default: " .. resolved)
                    wezterm.open_with(resolved)
                    return
                  end

                  -- Build args: split cmd on spaces for the command name
                  local args = {}
                  for word in cmd:gmatch("%S+") do
                    table.insert(args, word)
                  end

                  -- Line number handling per command type:
                  -- "+line" style: editors that take +N before the filepath
                  -- ":line" style: test runners that take filepath:N
                  local line_arg_cmds = { nvim = true, vim = true, vi = true, nano = true, code = true, emacs = true }
                  local line_suffix_cmds = { rspec = true, pytest = true }
                  if line and line_arg_cmds[args[1]] then
                    table.insert(args, "+" .. line)
                    table.insert(args, resolved)
                  elseif line and line_suffix_cmds[args[1]] then
                    table.insert(args, resolved .. ":" .. line)
                  else
                    table.insert(args, resolved)
                  end

                  wezterm.log_info("Opening: " .. table.concat(args, " "))
                  inner_window:perform_action(
                    wezterm.action({ SpawnCommandInNewWindow = { args = args } }),
                    inner_pane
                  )
                end),
              },
            }),
            pane
          )
        end),
      },
    }),
  },
```

#### 6. Update the keybinds comment block (line 84-93)

Change the existing Ctrl-Shift-O comment to reflect the dual purpose:

```lua
-- Ctrl-Shift-O to open URLs (browser) or filepaths (prompted command)
```

### `local.example.lua`

Add documentation for the new `filepath_patterns` override:

```lua
  -- filepath_patterns = {
  --   -- Add custom filepath patterns for QuickSelect
  --   [[\b(custom/path/pattern)\b]],
  -- },
```

## Considerations & Trade-offs

### Unified vs separate keybinding

**Chosen: Unified Ctrl-Shift-O.** One keybinding for "open thing under cursor" is more intuitive. The detection is simple — URLs start with `scheme://`, everything else is treated as a filepath.

### URL detection

**Chosen: `str:match("^%w+://")`.** This catches `http://`, `https://`, `ftp://`, etc. The existing url_transforms handle non-URL prefixes (like `FB-123`) that get transformed into URLs — but those are already URLs by the time they reach the callback (they matched hyperlink regexes). The only edge case is url_transforms with non-URL prefixes, but those still won't match `^%w+://` so they'd fall through to filepath handling. We need to also apply url_transforms first and re-check, OR treat url_transform matches as URLs.

**Refinement:** We check url_transforms first. If a transform matches, the result is a URL — open in browser. If no transform matches and it's not a `scheme://` URL, treat as filepath.

Wait — actually the url_transforms work on the already-selected text. Looking at the existing code, `FB-123` is selected text that gets transformed to a full URL. So after transforms, we'd need to check if the *transformed* result is a URL. But the simpler approach: check `is_url` first (handles `http://...` selections), then check url_transforms (handles `FB-123` type selections), then fall through to filepath. Let me revise the callback logic:

```lua
-- 1. Direct URL
if is_url(raw) then ... open_with(raw) ... return end

-- 2. URL transform match
for _, transform in ipairs(url_transforms) do
  for _, prefix in ipairs(transform.prefixes) do
    if starts_with(raw, prefix) then
      local url = transform.format(raw)
      wezterm.log_info("Opening URL: " .. url)
      wezterm.open_with(url)
      return
    end
  end
end

-- 3. Filepath
...
```

This preserves exact existing behavior for URLs and url_transforms, and only filepaths fall through to the new prompt logic.

### PromptInputLine vs InputSelector

**Chosen: PromptInputLine.** The user specifically asked to "type the command". Empty input falls through to `wezterm.open_with` for system default.

### SpawnCommandInNewWindow vs open_with for typed commands

**Chosen: Always use SpawnCommandInNewWindow for typed commands.** When the user types `nvim` or `bat`, they expect a terminal. System default (GUI) is the empty-input case.

### Line number handling

**Chosen: Command-aware line number injection.** Two styles supported via table lookup:
- **`+line` style** (editors): nvim, vim, vi, nano, code, emacs — get `+N` as a separate arg before the filepath
- **`:line` style** (test runners): rspec, pytest — get `filepath:N` as a single arg

Unknown commands get just the filepath without line number injection.

## Testing Strategy

Manual testing (wezterm config, no test framework):

1. **URL still works**: `echo https://example.com`, Ctrl-Shift-O, select it → opens in browser
2. **URL transform still works**: Select a transformed pattern (e.g. FB-123) → opens transformed URL
3. **Absolute path**: `echo /tmp/test.txt`, select → prompt appears, type `cat` → opens in new window
4. **Relative path + line number**: `echo ./config.lua:42`, select → resolves to CWD, type `nvim` → `nvim +42 /full/path/config.lua`
5. **Home-relative path**: `echo ~/Documents`, select → resolves to `/Users/hhhuang/Documents`
6. **Env var path**: `echo '$HOME/.bashrc'`, select → `$HOME` expands
7. **Empty command**: Select filepath, press Enter → `wezterm.open_with` (system default)
8. **Cancel prompt**: Select filepath, press Escape → nothing happens
9. **Bare path with extension**: `echo src/main.rs:10:5`, select → resolves, line number parsed

## Todo List

### Phase 1: Helper Functions
- [x] Add `is_url()` function after `starts_with`
- [x] Add `parse_filepath()` function
- [x] Add `resolve_filepath()` function

### Phase 2: Filepath Patterns
- [x] Add `filepath_patterns` array (after hyperlink rules assembly)
- [x] Add local config override for `filepath_patterns` in the local_config section

### Phase 3: Combined Patterns & Keybinding
- [x] Build `open_patterns` array combining `hyperlink_regexes` + `filepath_patterns`
- [x] Replace Ctrl-Shift-O keybinding with unified URL/filepath handler
- [x] Update keybinds comment block

### Phase 4: Local Config Documentation
- [x] Add `filepath_patterns` example to `local.example.lua`

### Phase 5: Manual Testing
- [ ] Test URL opening still works (http/https)
- [ ] Test URL transform still works
- [ ] Test absolute filepath
- [ ] Test relative path with line number
- [ ] Test home-relative path (~/)
- [ ] Test env var path ($HOME/...)
- [ ] Test empty command (system default)
- [ ] Test cancel prompt (Escape)
- [ ] Test bare path with extension and line:col

## Verification Summary

Checked 18 verifiable claims against `config.lua` (350 lines) and `local.example.lua` (31 lines).

- **Confirmed: 14** — helper function signatures, local config override pattern, open_patterns assembly, keybinding structure, PromptInputLine flow, comment block update, local.example.lua changes
- **Corrected: 4**
  - Regex patterns in plan had capture groups `(...)` — actual code removed them during simplify review (non-capturing `(?:...)` only)
  - Keybinding code snippet: plan had url_transforms inside `is_url` branch — actual code checks `is_url` first (no transforms), then checks url_transforms separately, then falls through to filepath
  - Editor list: plan showed chained `if editor == "nvim" or ...` conditionals — actual code uses `line_arg_cmds` table lookup
  - Line number handling: plan only described `+line` editors — actual code also has `line_suffix_cmds` for test runners (rspec, pytest) using `:line` suffix style
- **Unverifiable: 0**
