# Research: WezTerm to Ghostty Configuration Migration

## Overview

This document analyzes the current WezTerm configuration at `~/.dotfiles/wezterm/` and maps every feature to its Ghostty equivalent for a full-parity migration.

Ghostty uses a flat key-value config file at `~/.config/ghostty/config` (no scripting language). Custom themes go in `~/.config/ghostty/themes/`. Keybinds use `keybind = trigger=action` syntax.

## Current WezTerm Configuration Structure

### Key Files

| File | Role |
|------|------|
| `config.lua` | Main configuration (219 lines) — fonts, colors, keybinds, hyperlinks, event handlers |
| `local.example.lua` | Template for machine-local overrides (font, hyperlink rules, URL transforms, config overrides) |
| `install.sh` | Symlinks config into `~/.config/wezterm/` |
| `colors/Tokyo Night Storm.toml` | Custom color scheme file |

### Architecture

The config uses a **local override pattern**: `config.lua` defines defaults, then `require("local")` loads an optional `local.lua` that can override `primary_font`, `decorations`, `url_transforms`, `hyperlink_rules`, and apply arbitrary config via `apply_to_config(config)`.

---

## Feature-by-Feature Mapping

### 1. Font Configuration

**WezTerm** (`config.lua:136-145`):
```lua
config.font = wezterm.font_with_fallback({
  primary_font,                                    -- "Maple Mono" (default)
  { family = "Noto Color Emoji", scale = 0.75 },
  { family = "Symbols Nerd Font Mono", scale = 0.75 },
  { family = "Powerline Extra Symbols", scale = 0.75 },
  { family = "codicon", scale = 0.75 },
  { family = "Noto Sans Symbols", scale = 0.75 },
  { family = "Noto Sans Symbols2", scale = 0.75 },
  { family = "Font Awesome 6 Free", scale = 0.75 },
})
config.font_size = 14
```

**Ghostty equivalent**:
```
font-family = "Maple Mono"
font-family = "Noto Color Emoji"
font-family = "Symbols Nerd Font Mono"
font-family = "Noto Sans Symbols"
font-family = "Noto Sans Symbols2"
font-family = "Font Awesome 6 Free"
font-size = 14
```

**Gap**: Ghostty does NOT support per-fallback font scaling (`scale = 0.75`). However, Ghostty has built-in Nerd Font support and automatically resizes Nerd Font symbols to match cell size, so `Symbols Nerd Font Mono` may not even be needed. The `Powerline Extra Symbols` and `codicon` fonts may render at native size rather than 0.75x.

### 2. Cursor

**WezTerm** (`config.lua:132-133`):
```lua
config.default_cursor_style = "BlinkingBlock"
config.hide_mouse_cursor_when_typing = false
```

**Ghostty equivalent**:
```
cursor-style = block
cursor-style-blink = true
mouse-hide-while-typing = false
```

**Parity**: Full.

### 3. Color Scheme

**WezTerm** (`config.lua:158`):
```lua
config.color_scheme = "Catppuccin Mocha"
```

**Ghostty equivalent**:
```
theme = "catppuccin-mocha"
```

Ghostty ships with hundreds of built-in themes sourced from iterm2-color-schemes, including Catppuccin variants. Verify with `ghostty +list-themes | grep -i catppuccin`.

**Parity**: Full (assuming the theme exists built-in; otherwise a custom theme file is trivial).

### 4. Window Decorations

**WezTerm** (`config.lua:12-20`):
- macOS: `"RESIZE"` (no title bar, just resize handles)
- Linux/Sway: `"NONE"`
- Linux/other: `"TITLE | RESIZE"`

**Ghostty equivalent**:
- macOS: `macos-titlebar-style = hidden` (hides titlebar, keeps resize/rounded corners)
- Linux/Sway: `window-decoration = none` or `gtk-titlebar = false`
- Linux/other: `window-decoration = auto` (default)

**Note**: Ghostty uses separate options for macOS (`macos-titlebar-style`) vs Linux (`window-decoration`, `gtk-titlebar`). The local override pattern will need to handle this differently since Ghostty can't run Lua logic — but the config file can be platform-specific or use separate config files.

### 5. Window Padding

**WezTerm** (`config.lua:152-157`):
```lua
config.window_padding = { left = "4px", right = "4px", top = "2px", bottom = "2px" }
```

**Ghostty equivalent**:
```
window-padding-x = 4
window-padding-y = 2
```

**Note**: Ghostty uses separate X/Y padding. Supports `left,right` and `top,bottom` syntax for asymmetric padding (e.g., `window-padding-x = 4,4`).

**Parity**: Full.

### 6. Tab Bar

**WezTerm** (`config.lua:147-148`):
```lua
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
```

**Ghostty equivalent** (macOS):
```
macos-titlebar-style = tabs
```
On macOS the tab bar is integrated into the titlebar by default. If `macos-titlebar-style = hidden`, no tab bar is shown.

**Ghostty equivalent** (Linux):
```
window-show-tab-bar = auto
```
`auto` hides the tab bar when only one tab exists (matching WezTerm behavior).

**Gap**: If we use `macos-titlebar-style = hidden` for decoration purposes, we lose the integrated tab bar on macOS. Trade-off to evaluate.

### 7. Scrollback

**WezTerm** (`config.lua:159`):
```lua
config.scrollback_lines = 10000
```

**Ghostty equivalent**:
```
scrollback-limit = 10000000
```

**Note**: Ghostty measures scrollback in **bytes**, not lines. Default is 10MB. 10,000 lines at ~80 chars is ~800KB, so 10MB default already exceeds the WezTerm setting. The default is likely fine, or set explicitly to `10000000` (10MB).

**Parity**: Approximate (byte-based vs line-based).

### 8. Window Close Confirmation

**WezTerm** (`config.lua:160`):
```lua
config.window_close_confirmation = "NeverPrompt"
```

**Ghostty equivalent**:
```
confirm-close-surface = false
```

**Parity**: Full.

### 9. Initial Window Size

**WezTerm** (`config.lua:211-212`):
```lua
config.initial_cols = 160
config.initial_rows = 48
```

**Ghostty equivalent**:
```
window-width = 160
window-height = 48
```

**Note**: Both must be set together in Ghostty. Values are in grid cells (same as WezTerm).

**Parity**: Full.

### 10. Keybindings

#### Scroll by half page — Ctrl+Shift+D / Ctrl+Shift+U (`config.lua:167-168`)

**WezTerm**:
```lua
{ key = "D", mods = "SHIFT|CTRL", action = wezterm.action({ ScrollByPage = 0.5 }) },
{ key = "U", mods = "SHIFT|CTRL", action = wezterm.action({ ScrollByPage = -0.5 }) },
```

**Ghostty**:
```
keybind = ctrl+shift+d=scroll_page_fractional:0.5
keybind = ctrl+shift+u=scroll_page_fractional:-0.5
```

**Parity**: Full.

#### PageUp/PageDown 1/3 page (`config.lua:205-206`)

**WezTerm**:
```lua
{ key = "PageUp", action = wezterm.action.ScrollByPage(-0.33) },
{ key = "PageDown", action = wezterm.action.ScrollByPage(0.33) },
```

**Ghostty**:
```
keybind = page_up=scroll_page_fractional:-0.33
keybind = page_down=scroll_page_fractional:0.33
```

**Parity**: Full.

#### Search for git hashes — Ctrl+Shift+H (`config.lua:165`)

**WezTerm**:
```lua
{ key = "H", mods = "SHIFT|CTRL", action = wezterm.action({ Search = { Regex = "[a-f0-9]{6,}" } }) }
```

**Ghostty**: No direct equivalent. Ghostty does not have a built-in regex search mode that can be invoked with a pre-filled pattern via keybind.

**Gap**: No parity. This feature would need an external tool or script workaround.

#### Open scrollback in nvim — Ctrl+Shift+E (`config.lua:92-125, 163`)

**WezTerm**: Custom event handler that dumps 2000 lines of scrollback to a temp file and opens nvim in a new window.

**Ghostty**: No direct equivalent. Ghostty doesn't support arbitrary event handlers or scripting. This would need to be implemented via an external script/wrapper, possibly using `keybind = ctrl+shift+e=text:...` to invoke a shell command, but there's no direct "run command" keybind action.

**Gap**: No parity. Significant feature loss — requires external tooling.

#### Open URL via QuickSelect — Ctrl+Shift+O (`config.lua:170-194`)

**WezTerm**: Opens QuickSelect with hyperlink regex patterns, applies URL transforms, then opens in browser.

**Ghostty**: Has built-in URL detection (Cmd+click / Ctrl+click to open). Does NOT have a QuickSelect-equivalent that labels matches for keyboard-driven selection. There's a `quick_select` discussion on GitHub but it's not a fully shipped feature with the same flexibility.

**Gap**: Partial parity. Ghostty can open clicked URLs, but lacks keyboard-driven URL quick-selection and custom URL transforms.

#### Disable Ctrl+Shift+N and Ctrl+Shift+P (`config.lua:196-204`)

**WezTerm**: Disables default assignments for these keys.

**Ghostty**:
```
keybind = ctrl+shift+n=unbind
keybind = ctrl+shift+p=unbind
```

**Parity**: Full.

#### Shift+Enter sends CSI u sequence (`config.lua:208`)

**WezTerm**:
```lua
{ key = "Enter", mods = "SHIFT", action = wezterm.action({ SendString = "\x1b[13;2u" }) }
```

**Ghostty**: By default, Ghostty already sends `\x1b[13;2u` for Shift+Enter when the application supports CSI u / kitty keyboard protocol. If the app doesn't request it, Ghostty sends a different sequence (`[27;2;13~`). To force the CSI u sequence:
```
keybind = shift+enter=csi:13;2u
```

**Note**: This may already work out of the box depending on the app. Test before adding the keybind.

### 11. Hyperlink Rules

**WezTerm** (`config.lua:48-78`): Custom hyperlink rules for numeric IP addresses and localhost URLs, plus local config can add more.

**Ghostty**: Has built-in URL detection enabled by default (`link-url = true`). Supports standard URL patterns. Does NOT support adding custom regex hyperlink rules in the same way.

**Gap**: Partial parity. Standard URLs work. Custom patterns (like the numeric IP regex) may or may not be matched by Ghostty's built-in detector.

### 12. Wayland / OpenGL

**WezTerm** (`config.lua:149-150`):
```lua
config.enable_wayland = true
config.front_end = "OpenGL"
```

**Ghostty**: Native Wayland support is automatic (no config needed). Uses its own GPU-accelerated renderer.

**Parity**: Full (implicit).

### 13. Local Config Override Pattern

**WezTerm**: Lua `require("local")` loads `local.lua` for machine-specific overrides.

**Ghostty**: Supports `config-file = /path/to/file` directive to include additional config files. A `local.conf` can be included conditionally, but Ghostty will error if the file doesn't exist unless you use a convention like always having the file (even if empty).

**Approach**: Create a `local` config file that's always present (possibly empty) and include it via `config-file`.

---

## Features with No Ghostty Equivalent

| WezTerm Feature | Status in Ghostty |
|----------------|-------------------|
| Open scrollback in nvim (Ctrl+Shift+E) | No scripting/event system. Needs external tool. |
| Search with pre-filled regex (Ctrl+Shift+H) | No parameterized search action. |
| QuickSelect with custom patterns + URL transforms (Ctrl+Shift+O) | No equivalent. Cmd/Ctrl+click opens URLs but no keyboard-driven selection. |
| Per-fallback font scaling | Not supported. Ghostty auto-scales Nerd Fonts. |
| Custom hyperlink regex rules | Built-in detection only. |
| URL transforms (rewriting URLs before opening) | Not supported. |

## Custom Color File

**WezTerm** ships a `colors/Tokyo Night Storm.toml` custom theme file.

**Ghostty** equivalent would be `~/.config/ghostty/themes/Tokyo Night Storm` (no extension) with:
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

However, the current WezTerm config uses `Catppuccin Mocha`, not Tokyo Night Storm. The Tokyo Night Storm file appears to be a leftover or alternative.

## Install Script

The current `install.sh` symlinks `config.lua` to `~/.config/wezterm/wezterm.lua` and color files. A Ghostty equivalent would symlink `config` to `~/.config/ghostty/config` and theme files to `~/.config/ghostty/themes/`.

---

## Summary of Parity Assessment

- **Full parity (12 features)**: Font, cursor, color scheme, padding, scrollback, close confirmation, window size, scroll keybinds, PageUp/PageDown, unbind keys, Shift+Enter, Wayland/GPU
- **Partial parity (3 features)**: Window decorations (different API per platform), tab bar (tied to titlebar style on macOS), hyperlink detection (built-in only)
- **No parity (4 features)**: Scrollback-in-nvim, regex search keybind, QuickSelect+URL transforms, per-font scaling
- **Different approach (1 feature)**: Local config overrides (config-file include vs Lua require)
