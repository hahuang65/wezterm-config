# Plan: WezTerm → Ghostty Configuration Migration

## Goal

Create a Ghostty configuration with full feature parity to the existing WezTerm setup, maintaining the same dotfiles repo structure, local override pattern, and install script convention.

## Research Reference

`docs/claude/20260305-0141-wezterm-to-ghostty/research.md`

## Approach

Create a sibling `ghostty/` directory alongside the existing `wezterm/` config in `~/.dotfiles/`. The Ghostty config uses flat key-value files (no Lua), so the structure is simpler. We preserve the local-override pattern using Ghostty's `config-file` include directive.

Since Ghostty and WezTerm will coexist (user can switch between them), we keep the WezTerm config untouched.

## Directory Structure

```
~/.dotfiles/ghostty/
├── config              # Main ghostty config (equivalent to config.lua)
├── local.example       # Template for machine-local overrides
├── themes/
│   └── Tokyo Night Storm   # Converted custom theme (no extension)
├── install.sh          # Symlinks into ~/.config/ghostty/
├── LICENSE
└── README.md
```

## Detailed Changes

### 1. New File: `ghostty/config`

The main configuration file. Every setting maps from a WezTerm equivalent (see research).

```
# Ghostty Configuration
# Migrated from WezTerm config.lua

# --- Fonts ---
font-family = "Maple Mono"
font-family = "Noto Color Emoji"
# Ghostty has built-in Nerd Font support and auto-scales symbols,
# so Symbols Nerd Font Mono, Powerline Extra Symbols, codicon are
# likely unnecessary. Include only if glyphs are missing.
font-family = "Noto Sans Symbols"
font-family = "Noto Sans Symbols2"
font-family = "Font Awesome 6 Free"
font-size = 14

# --- Cursor ---
cursor-style = block
cursor-style-blink = true
mouse-hide-while-typing = false

# --- Theme ---
theme = "catppuccin-mocha"

# --- Window ---
# macOS: hidden removes titlebar but keeps resize handles and rounded corners
macos-titlebar-style = hidden
window-padding-x = 4
window-padding-y = 2
confirm-close-surface = false
window-width = 160
window-height = 48

# --- Scrollback ---
# Default 10MB (~125k lines at 80 chars) exceeds WezTerm's 10k lines.
# Omit to use default, or set explicitly:
# scrollback-limit = 10000000

# --- Keybindings ---

# Scroll half-page (matches WezTerm Ctrl+Shift+D/U)
keybind = ctrl+shift+d=scroll_page_fractional:0.5
keybind = ctrl+shift+u=scroll_page_fractional:-0.5

# PageUp/PageDown scroll 1/3 page
keybind = page_up=scroll_page_fractional:-0.33
keybind = page_down=scroll_page_fractional:0.33

# Shift+Enter sends CSI u sequence for Claude Code compatibility
# Ghostty may already send this via kitty protocol — test first,
# remove if unnecessary
keybind = shift+enter=csi:13;2u

# Unbind Ctrl+Shift+N and Ctrl+Shift+P (reserved for other tools)
keybind = ctrl+shift+n=unbind
keybind = ctrl+shift+p=unbind

# --- Local overrides ---
# Include machine-local config. This file must exist (even if empty).
# Copy local.example to ~/.config/ghostty/local and customize.
config-file = local
```

### 2. New File: `ghostty/local.example`

Template for machine-specific overrides, mirroring `local.example.lua`.

```
# Machine-local Ghostty overrides
# Copy this file to ~/.config/ghostty/local and customize.

# Override font
# font-family = ""
# font-family = "Menlo"

# Override font size
# font-size = 18

# Override theme
# theme = "Batman"
```

### 3. New File: `ghostty/themes/Tokyo Night Storm`

Convert the existing WezTerm TOML color file to Ghostty theme format (no file extension).

```
background = #24283b
foreground = #c0caf5
selection-background = #364A82
selection-foreground = #c0caf5
cursor-color = #c0caf5
cursor-text = #24283b
palette = 0=#1D202F
palette = 1=#f7768e
palette = 2=#9ece6a
palette = 3=#e0af68
palette = 4=#7aa2f7
palette = 5=#bb9af7
palette = 6=#7dcfff
palette = 7=#a9b1d6
palette = 8=#414868
palette = 9=#f7768e
palette = 10=#9ece6a
palette = 11=#e0af68
palette = 12=#7aa2f7
palette = 13=#bb9af7
palette = 14=#7dcfff
palette = 15=#c0caf5
```

### 4. New File: `ghostty/install.sh`

Symlinks config and themes into `~/.config/ghostty/`.

```bash
#!/bin/sh

mkdir -p "${HOME}/.config/ghostty"
mkdir -p "${HOME}/.config/ghostty/themes"

ln -sf "${PWD}/config" "${HOME}/.config/ghostty/config"

# Create empty local config if it doesn't exist (required by config-file include)
touch "${HOME}/.config/ghostty/local"

for theme in themes/*
do
    ln -sf "${PWD}/${theme}" "${HOME}/.config/ghostty/themes/"
done
```

### 5. New File: `ghostty/README.md`

Brief README explaining the config, the local override pattern, and the features that don't have Ghostty equivalents.

### 6. Copy `LICENSE` from wezterm directory

Same license as the WezTerm config.

## Considerations & Trade-offs

### Window Decorations + Tab Bar (macOS)

**Trade-off**: `macos-titlebar-style = hidden` removes the titlebar (matching WezTerm's `"RESIZE"`), but also removes the integrated tab bar on macOS. The WezTerm config shows tabs when there are 2+.

**Decision**: Use `macos-titlebar-style = hidden` to match the existing minimal decoration style. Tabs can still be navigated via keybinds (Cmd+T, Cmd+Shift+], etc.) even without a visible tab bar. If the user wants the tab bar, they can override to `macos-titlebar-style = tabs` in their local config.

### Linux Window Decorations

**Trade-off**: WezTerm uses Lua runtime detection of `XDG_CURRENT_DESKTOP` to choose decorations. Ghostty can't do runtime checks.

**Decision**: The main config targets macOS (the primary platform based on the dotfiles structure). Linux users can set `window-decoration = none` or `window-decoration = auto` in their local config. Document this in `local.example`.

### Features Dropped (No Ghostty Equivalent)

These WezTerm features cannot be replicated in Ghostty's config-only model:

1. **Scrollback in nvim** (Ctrl+Shift+E) — Would need an external tool like `tmux capture-pane` or a custom script. Out of scope for this config migration.
2. **Search with regex** (Ctrl+Shift+H) — Ghostty has no parameterized search. Drop this binding.
3. **QuickSelect URLs** (Ctrl+Shift+O) — Ghostty has Cmd/Ctrl+click for URLs. No keyboard-driven alternative. Drop this binding.
4. **URL transforms** — Not possible without scripting. Drop.
5. **Custom hyperlink regex** — Ghostty's built-in URL detection handles standard URLs. Drop custom regex for numeric IPs and localhost.

### Font Fallback Scaling

WezTerm scales fallback fonts to 0.75x. Ghostty doesn't support per-font scaling but auto-scales Nerd Font symbols. We drop `Powerline Extra Symbols` and `codicon` (Ghostty's built-in Nerd Fonts cover these glyphs) and keep the remaining fallbacks without scaling. If symbols appear too large, the user can file a Ghostty issue or adjust.

### `config-file = local` Path Resolution

Ghostty resolves relative `config-file` paths relative to the config directory (`~/.config/ghostty/`). So `config-file = local` looks for `~/.config/ghostty/local`. The install script creates this file with `touch` if it doesn't already exist, preventing load errors.

## Dependencies

None. Ghostty must be installed separately by the user.

## Testing Strategy

Since this is a configuration-only migration (no application code), testing is manual verification:

1. **Font rendering**: Open Ghostty after install. Verify Maple Mono renders as primary font. Check Nerd Font icons render correctly (e.g., in a starship prompt or `echo -e "\ue0b0\uf09b"`).
2. **Color scheme**: Verify Catppuccin Mocha colors match WezTerm. Compare side-by-side with `neofetch` or a color test script.
3. **Keybindings**: Test each keybind:
   - Ctrl+Shift+D scrolls down half page
   - Ctrl+Shift+U scrolls up half page
   - PageUp/PageDown scrolls 1/3 page
   - Shift+Enter sends correct CSI sequence in Claude Code
   - Ctrl+Shift+N and Ctrl+Shift+P are unbound (no default action)
4. **Window**: Verify no titlebar on macOS, correct initial size (160x48), no close confirmation prompt.
5. **Local overrides**: Copy `local.example` to `~/.config/ghostty/local`, uncomment font-size override, reload Ghostty, verify font size changes.
6. **Install script**: Run `install.sh` from `ghostty/` directory, verify symlinks are created correctly.
7. **Theme file**: Change `theme = "Tokyo Night Storm"` in local config, verify colors load correctly.
