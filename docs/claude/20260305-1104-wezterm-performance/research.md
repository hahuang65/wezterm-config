# Research: WezTerm Configuration Performance Analysis

**Date:** 2026-03-05  
**WezTerm Version:** 20250622-064717-2b656cb5  
**Configuration Location:** `/Users/hhhuang/.dotfiles/wezterm/`  
**Scope:** Analyze current WezTerm configuration to identify performance improvement opportunities

---

## Overview

This is a **well-architected, performance-conscious WezTerm configuration** with minimal overhead. The configuration is compact (219 lines), self-contained, and follows best practices with defensive programming patterns. The primary finding is that **startup and runtime performance are already excellent**, with only one significant performance issue identified: a 2-second blocking sleep in the nvim scrollback handler.

### Key Characteristics
- **Startup overhead:** Minimal (<50ms estimated)
- **Runtime efficiency:** Very good (only issue is user-triggered blocking sleep)
- **Code quality:** Clean, well-commented (38 comment lines), clear structure
- **Configuration complexity:** Simple, no complex abstractions
- **Dependencies:** Minimal (core WezTerm API + Lua stdlib only)

---

## Architecture

### File Structure

```
/Users/hhhuang/.dotfiles/wezterm/
├── config.lua                  (219 lines) - Main configuration
├── local.example.lua           (26 lines)  - Template for local overrides
├── install.sh                  (16 lines)  - Symlink installer script
├── README.md                   (8 lines)   - Basic documentation
├── LICENSE
├── colors/
│   └── Tokyo Night Storm.toml  (11 lines)  - Custom color scheme (currently unused)
├── .builds/
│   └── mirror.yml              (58 lines)  - CI mirror config for sr.ht→GitHub
└── docs/
    └── claude/
        └── 20260305-0141-wezterm-to-ghostty/
            ├── research.md     - Previous migration research to Ghostty
            └── plan.md         - Previous migration plan

Installed configuration (symlinked):
~/.config/wezterm/
├── wezterm.lua                 → symlink to config.lua
├── local.lua                   (26 lines)  - Active local overrides
└── colors/
    └── Tokyo Night Storm.toml  → symlink
```

### Module Dependencies

```
config.lua
├─→ wezterm (builtin WezTerm API)
├─→ io (Lua stdlib - used only in nvim scrollback handler)
├─→ os (Lua stdlib - used for tmpname, remove, getenv)
└─→ local.lua (optional, loaded via pcall)
    └─ No further dependencies
```

**Assessment:** Minimal, self-contained dependencies. No external Lua modules or plugins.

---

## Configuration Loading Flow

WezTerm executes `config.lua` in this sequence:

```
1. Lines 1-3:   Require core modules (wezterm, io, os)
2. Lines 6-8:   Define helper function (starts_with)
3. Lines 10-20: Set default variables (primary_font, decorations, url_transforms)
                └─ Platform detection: checks XDG_CURRENT_DESKTOP for Linux/Sway
4. Lines 23-46: Load optional local.lua via pcall (non-blocking if missing)
                └─ Override primary_font, decorations, url_transforms if provided
5. Lines 48-78: Build hyperlink_rules and hyperlink_regexes arrays
                ├─ Copy wezterm.default_hyperlink_rules()
                ├─ Add custom rules (IP addresses, localhost)
                └─ Append local_config.hyperlink_rules if available
6. Lines 92-125: Register event handler "trigger-nvim-with-scrollback"
7. Lines 130-212: Build config object
                ├─ Set all terminal options (font, colors, keybinds, etc.)
                └─ Lines 161-209: Register 9 keybindings
8. Lines 215-217: Apply local_config.apply_to_config() if available
9. Return config object to WezTerm
```

**Pattern:** Defensive programming with `pcall()` for optional local config - no errors if file missing.

---

## Key Files

### `config.lua` (Primary configuration - 219 lines)

**Role:** Main WezTerm configuration defining all terminal behavior

**Sections:**
- **Lines 1-8:** Module imports and helper functions
- **Lines 10-20:** Default variable declarations with platform detection
- **Lines 23-46:** Local config loading and override mechanism
- **Lines 48-78:** Hyperlink rules construction
- **Lines 92-125:** Event handler for nvim scrollback functionality
- **Lines 130-212:** Core configuration (fonts, colors, keybinds, window settings)
- **Lines 215-217:** Final local config application hook

**Performance impact:** Medium - runs once at startup, minimal overhead

### `local.lua` (Machine-specific overrides - 26 lines)

**Role:** Per-machine customizations without modifying main config

**Content:**
- Custom font size override (line 23: `config.font_size = 15`)
- Jira ticket hyperlink rules (lines 5-11: A5-#### → Atlassian URL)
- URL transforms for QuickSelect (lines 12-19: A5- prefix → full Jira URL)

**Performance impact:** Low - simple table definitions, no complex logic

### `local.example.lua` (Template - 26 lines)

**Role:** Documentation/template for creating local.lua

**Performance impact:** None - not loaded by WezTerm

### `colors/Tokyo Night Storm.toml` (Color scheme - 11 lines)

**Role:** Custom color scheme definition

**Performance impact:** None - currently unused (config uses built-in "Catppuccin Mocha")

---

## Data Flow

### Startup Sequence

```
WezTerm Launch
    ↓
Load ~/.config/wezterm/wezterm.lua (symlink → config.lua)
    ↓
Execute config.lua sequentially
    ├─ Require modules (cached by Lua)
    ├─ Platform detection (single os.getenv call)
    ├─ Load local.lua via pcall (fails fast if missing)
    ├─ Build hyperlink rules (array concatenation, ~10-20 rules)
    ├─ Register event handlers (stores callbacks, doesn't execute)
    └─ Build config object (direct property assignment)
    ↓
Return config to WezTerm
    ↓
WezTerm applies configuration (font resolution, window creation)
```

**Estimated overhead:** <50ms total

### Runtime Event Flow

#### Nvim Scrollback Handler (Ctrl+Shift+E)

```
User presses Ctrl+Shift+E
    ↓
WezTerm triggers "trigger-nvim-with-scrollback" event (config.lua:163)
    ↓
Event handler executes (config.lua:92-125):
    ├─ 1. Get 2000 lines of scrollback text (pane:get_lines_as_text)
    ├─ 2. Create temp file (os.tmpname)
    ├─ 3. Write scrollback to temp file (io.open, f:write)
    ├─ 4. Spawn nvim in new window (SpawnCommandInNewWindow) [async]
    ├─ 5. **BLOCK FOR 2 SECONDS** (wezterm.sleep_ms(2000)) ⚠️
    └─ 6. Delete temp file (os.remove)
    ↓
User regains control (after 2+ seconds)
```

**Performance bottleneck:** 2-second blocking sleep freezes WezTerm UI thread

#### QuickSelect URL Transform (Ctrl+Shift+O)

```
User presses Ctrl+Shift+O
    ↓
QuickSelect activates with hyperlink_regexes patterns (config.lua:174-175)
    ↓
User selects a URL
    ↓
Action callback executes (config.lua:176-191):
    ├─ 1. Get selected text (window:get_selection_text_for_pane)
    ├─ 2. Iterate url_transforms (typically 1-2 items)
    │   └─ Check each prefix (2-3 prefixes per transform)
    ├─ 3. Apply matching transform (if any)
    └─ 4. Open URL in browser (wezterm.open_with)
```

**Performance:** Efficient - minimal iteration, fast string operations

---

## Patterns & Conventions

### 1. Local Override Pattern ✅ **EFFICIENT**

```lua
-- config.lua:23-46
local local_config
local ok, result = pcall(function()
  return require("local")
end)

if ok then
  local_config = result
  if local_config.primary_font then
    primary_font = local_config.primary_font
  end
  -- ... more conditional overrides
end
```

**Benefits:**
- Safe fallback with `pcall()` - no errors if local.lua is missing
- Clear separation of machine-specific config
- Non-blocking failure mode

**Pattern used in:**
- Lines 23-46: Variable overrides (font, decorations, url_transforms)
- Lines 73-78: Hyperlink rules augmentation
- Lines 215-217: Final config object modification hook

### 2. Hyperlink Rules Composition ⚠️ **MINOR INEFFICIENCY**

```lua
-- config.lua:48-78
local hyperlink_rules = wezterm.default_hyperlink_rules()
local hyperlink_regexes = {}

-- Add custom rules (lines 50-66)
for _, rule in ipairs({...}) do
  table.insert(hyperlink_rules, rule)
end

-- Extract regexes (lines 68-70) - FIRST ITERATION
for _, v in ipairs(hyperlink_rules) do
  table.insert(hyperlink_regexes, v["regex"])
end

-- Add local rules (lines 73-78) - SECOND ITERATION
if local_config and local_config.hyperlink_rules then
  for _, rule in ipairs(local_config.hyperlink_rules) do
    table.insert(hyperlink_rules, rule)
    table.insert(hyperlink_regexes, rule.regex)  -- Correctly builds both here
  end
end
```

**Issue:** Lines 68-70 iterate `hyperlink_rules` to extract regexes, but this misses the custom rules added in lines 50-66 (they don't have regex extracted until local rules are added).

**Impact:** Negligible (10-20 rules total), but not optimal.

**Optimization opportunity:** Single-pass construction - build both arrays together when adding custom rules.

### 3. Config Builder Pattern ✅ **EFFICIENT**

```lua
-- config.lua:130
local config = wezterm.config_builder()
config.font = ...
config.color_scheme = ...
-- ... direct property assignment
return config
```

**Benefits:**
- Uses official WezTerm `config_builder()` API
- Type-safe with WezTerm validation
- Clear, readable assignments
- No unnecessary abstractions

---

## Dependencies

### Internal Dependencies

| Module | Purpose | Usage Location | Performance Impact |
|--------|---------|----------------|-------------------|
| `wezterm` | Core WezTerm API | Throughout config.lua | Low - builtin, cached |
| `io` | File I/O | Lines 100-105 (nvim handler only) | Medium - writes temp file |
| `os` | System operations | Lines 14, 99, 124 | Low - tmpname, getenv, remove |

### External Dependencies

| Dependency | Optional? | Failure Mode | Performance Impact |
|------------|-----------|--------------|-------------------|
| `local.lua` | ✅ Yes | Silent fallback via pcall | Low - simple table definitions |
| Font families | ⚠️ Required | WezTerm falls back to system fonts | Low - system font resolution |

### Font Fallback Chain

```lua
-- config.lua:136-145
config.font = wezterm.font_with_fallback({
  primary_font,                              -- "Maple Mono" (from local.lua)
  { family = "Noto Color Emoji", scale = 0.75 },
  { family = "Symbols Nerd Font Mono", scale = 0.75 },
  { family = "Powerline Extra Symbols", scale = 0.75 },
  { family = "codicon", scale = 0.75 },
  { family = "Noto Sans Symbols", scale = 0.75 },
  { family = "Noto Sans Symbols2", scale = 0.75 },
  { family = "Font Awesome 6 Free", scale = 0.75 },
})
```

**Analysis:**
- **8 font fallbacks** - above average but not excessive
- **Scaled fallbacks** (0.75x) - requires additional rendering calculations
- **Runtime impact:** Low - font selection happens per glyph, cached by system
- **Rendering overhead:** Each fallback requires font lookup, but WezTerm caches aggressively

**Optimization potential:** Remove unused fallback fonts if certain glyphs aren't needed (requires audit of actual glyph usage).

---

## Edge Cases & Gotchas

### 1. Blocking Sleep in Nvim Handler ⚠️ **CRITICAL**

**Location:** `config.lua:123`

```lua
wezterm.sleep_ms(2000)
```

**Issue:** Blocks WezTerm UI thread for 2 full seconds when user presses Ctrl+Shift+E.

**Context from comments (lines 117-122):**
> "wait 'enough' time for vim to read the file before we remove it. The window creation and process spawn are asynchronous wrt. running this script and are not awaitable, so we just pick a number."

**Why it exists:**
- `window:perform_action(SpawnCommandInNewWindow)` is asynchronous
- Need to ensure nvim opens the temp file before deleting it
- No way to await the spawn completion

**Impact:**
- UI completely frozen for 2 seconds
- User cannot interact with WezTerm during this time
- Triggered only when user manually presses Ctrl+Shift+E (not automatic)

**Mitigation strategies:**
1. **Reduce sleep duration** - 100-200ms may be sufficient (nvim opens files very quickly)
2. **Use persistent temp file** - Don't delete immediately, clean up on next invocation
3. **Background cleanup** - If WezTerm API supports background tasks (needs investigation)
4. **Alternative approach** - Pipe scrollback directly to nvim stdin (avoids temp file entirely)

### 2. Hyperlink Regex Array Construction ⚠️ **MINOR**

**Location:** `config.lua:68-70`

```lua
for _, v in ipairs(hyperlink_rules) do
  table.insert(hyperlink_regexes, v["regex"])
end
```

**Issue:** This loop extracts regexes from `hyperlink_rules` *before* custom rules (lines 50-66) have their regexes extracted. However, local config rules (lines 73-78) correctly build both arrays together.

**Result:** Custom rules in lines 50-66 may not have their regexes in `hyperlink_regexes` unless they're also in `wezterm.default_hyperlink_rules()`.

**Impact:** Likely none - custom rules appear to still work via `hyperlink_rules` (used in config.hyperlink_rules), and `hyperlink_regexes` is used for QuickSelect which may include them anyway.

**Verification needed:** Test if QuickSelect (Ctrl+Shift+O) correctly highlights custom patterns like `http://127.0.0.1:8000`.

### 3. Platform-Specific Decorations

**Location:** `config.lua:13-20`

```lua
if wezterm.target_triple == "x86_64-unknown-linux-gnu" then
  local desktop = os.getenv("XDG_CURRENT_DESKTOP") or ""
  if desktop:lower() == "sway" then
    decorations = "NONE"
  else
    decorations = "TITLE | RESIZE"
  end
end
```

**Gotcha:** Only detects Sway on Linux. On macOS/Windows, uses default `decorations = "RESIZE"`.

**Edge case:** If running on ARM Linux (`aarch64-unknown-linux-gnu`), platform detection is skipped and defaults to "RESIZE".

**Impact:** Low - decorations are cosmetic, doesn't affect functionality.

### 4. Unused Color Scheme File

**Location:** `colors/Tokyo Night Storm.toml`

**Issue:** File is symlinked to `~/.config/wezterm/colors/` but never used. Config uses built-in scheme:

```lua
-- config.lua:158
config.color_scheme = "Catppuccin Mocha"
```

**Impact:** None - just wasted disk space (~1 KB).

**Cleanup opportunity:** Remove unused color scheme or document why it's kept.

### 5. CSI u Sequence for Shift+Enter

**Location:** `config.lua:208`

```lua
{ key = "Enter", mods = "SHIFT", action = wezterm.action({ SendString = "\x1b[13;2u" }) },
```

**Context (from comment line 207):**
> "Send CSI u sequence for Shift+Enter so apps like Claude Code can distinguish it"

**Gotcha:** This overrides default Shift+Enter behavior. Applications must handle CSI u sequences to benefit.

**Impact:** Positive - improves compatibility with modern terminal applications, but older apps may not recognize the sequence.

---

## Current State

### Performance Metrics (Estimated)

| Metric | Value | Assessment |
|--------|-------|------------|
| **Startup time** | <50ms | ⭐⭐⭐⭐⭐ Excellent |
| **Config file size** | 219 lines | ⭐⭐⭐⭐⭐ Compact |
| **Runtime overhead** | Negligible | ⭐⭐⭐⭐☆ Very good (except nvim sleep) |
| **Memory footprint** | Minimal | ⭐⭐⭐⭐⭐ Excellent |
| **Code complexity** | Low | ⭐⭐⭐⭐⭐ Very readable |

### Known Issues

1. **2-second blocking sleep** (config.lua:123)
   - **Severity:** High (user-facing freeze)
   - **Frequency:** Only when manually triggered (Ctrl+Shift+E)
   - **Impact:** Major UX issue for 2 seconds per invocation

2. **Hyperlink regex array construction** (config.lua:68-70)
   - **Severity:** Low (may not affect functionality)
   - **Frequency:** Once at startup
   - **Impact:** Minor inefficiency, needs verification

3. **Unused color scheme file** (colors/Tokyo Night Storm.toml)
   - **Severity:** Negligible
   - **Impact:** None - just wasted disk space

### Technical Debt

- **Font fallback audit needed:** 8 fallback fonts may include unused ones - requires glyph usage analysis
- **Temp file cleanup:** Nvim handler relies on sleep timer instead of proper async cleanup
- **Code duplication:** Hyperlink array building could be DRYer

### Areas of Concern

**None identified beyond the blocking sleep issue.** The configuration is well-maintained, follows best practices, and has minimal complexity.

---

## Performance-Sensitive Operations

### Startup Operations (Lines 1-217)

| Operation | Location | Frequency | Impact | Optimization Potential |
|-----------|----------|-----------|--------|----------------------|
| **Module loading** | Lines 1-3 | Once at startup | Negligible | ✅ Already optimal (builtin modules) |
| **Platform detection** | Lines 13-20 | Once at startup | Low | ✅ Single `os.getenv()`, acceptable |
| **Local config loading** | Lines 23-46 | Once at startup | Low | ✅ `pcall()` fails fast, efficient |
| **Hyperlink rules building** | Lines 48-78 | Once at startup | Low | ⚠️ Minor - double iteration (see Patterns section) |
| **Font fallback resolution** | Lines 136-145 | Per glyph (cached) | Low | ⚠️ Medium - could audit for unused fonts |

**Overall startup assessment:** ⭐⭐⭐⭐⭐ Excellent - minimal overhead, no blocking operations

### Runtime Operations (User-triggered)

| Operation | Location | Trigger | Impact | Optimization Potential |
|-----------|----------|---------|--------|----------------------|
| **Nvim scrollback handler** | Lines 92-125 | Ctrl+Shift+E | **HIGH** ⚠️ | ⚠️ **Critical - 2-second blocking sleep** |
| **QuickSelect URL transform** | Lines 176-191 | Ctrl+Shift+O | Low | ✅ Already efficient |
| **Git hash search** | Line 165 | Ctrl+Shift+H | Low | ✅ WezTerm internal optimization |
| **Scrollback navigation** | Lines 167-168 | Ctrl+Shift+D/U | Low | ✅ WezTerm internal optimization |

**Overall runtime assessment:** ⭐⭐⭐⭐☆ Very good - only issue is user-triggered blocking sleep

### Background Operations

**None.** Configuration has:
- ✅ No timers or periodic updates
- ✅ No background file watchers
- ✅ No shell integration scripts polling environment
- ✅ No autocmds

**Assessment:** ⭐⭐⭐⭐⭐ Excellent - zero background overhead

---

## Feature Breakdown

### Core Features (Lines 130-212)

| Feature | Configuration Line(s) | Performance Impact |
|---------|----------------------|-------------------|
| **Cursor style** | 132 | Negligible |
| **Mouse cursor hiding** | 133 | Negligible |
| **Font configuration** | 136-146 | Low (8 fallbacks) |
| **Tab bar** | 147-148 | Low (auto-hide) |
| **Wayland support** | 149 | Negligible |
| **OpenGL rendering** | 150 | Low (GPU-accelerated) |
| **Window decorations** | 151 | Negligible |
| **Window padding** | 152-157 | Negligible |
| **Color scheme** | 158 | Negligible |
| **Scrollback buffer** | 159 | Medium (10,000 lines) |
| **Close confirmation** | 160 | Negligible |
| **Custom keybindings** | 161-209 | Low (9 bindings) |
| **Hyperlink rules** | 210 | Low (~15-20 rules) |
| **Initial window size** | 211-212 | Negligible |

### Advanced Features

| Feature | Location | Purpose | Performance Impact |
|---------|----------|---------|-------------------|
| **Nvim scrollback** | Lines 92-125 | Open scrollback in nvim (Ctrl+Shift+E) | High (2-second sleep) ⚠️ |
| **QuickSelect URL transform** | Lines 170-194 | Transform URLs before opening (Ctrl+Shift+O) | Low |
| **Custom hyperlink patterns** | Lines 50-66 | Detect IP addresses and localhost URLs | Low |
| **Local config overrides** | Lines 23-46, 215-217 | Machine-specific customizations | Low |
| **CSI u sequence** | Line 208 | Enhanced Shift+Enter support | Negligible |

### Unused Assets

- `colors/Tokyo Night Storm.toml` - Custom color scheme (defined but not active)
- `.builds/mirror.yml` - CI configuration for sr.ht → GitHub mirroring

---

## Optimization Opportunities

### High Priority: Fix Blocking Sleep

**Problem:** 2-second UI freeze when opening scrollback in nvim (config.lua:123)

**Current code:**
```lua
wezterm.sleep_ms(2000)  -- Blocks UI thread
os.remove(name)
```

**Option 1: Reduce sleep duration (Quick fix)**
```lua
wezterm.sleep_ms(100)  -- 100ms is likely sufficient for nvim to open file
os.remove(name)
```

**Option 2: Persistent temp file (Eliminate sleep)**
```lua
-- Don't delete immediately - clean up on next invocation
local last_scrollback_file = "/tmp/wezterm-scrollback-last.txt"
if io.exists(last_scrollback_file) then
  os.remove(last_scrollback_file)
end
local name = last_scrollback_file
-- ... write and spawn nvim
-- No sleep needed - file persists
```

**Option 3: Direct pipe (Best, if WezTerm supports)**
```lua
-- Pipe scrollback directly to nvim stdin (avoids temp file entirely)
window:perform_action(
  wezterm.action.SpawnCommandInNewWindow({
    args = { "nvim", "-c", "setlocal buftype=nofile", "-" },
    set_environment_variables = {
      SCROLLBACK = scrollback
    },
  }),
  pane
)
```

**Recommendation:** Start with Option 1 (reduce to 100ms) as it's safest, then investigate Option 3 if WezTerm API supports it.

---

### Medium Priority: Optimize Hyperlink Array Construction

**Problem:** Double iteration of hyperlink rules (config.lua:68-70 then 73-78)

**Current code:**
```lua
-- Lines 50-66: Add custom rules
for _, rule in ipairs({...}) do
  table.insert(hyperlink_rules, rule)
end

-- Lines 68-70: Extract regexes (FIRST iteration)
for _, v in ipairs(hyperlink_rules) do
  table.insert(hyperlink_regexes, v["regex"])
end

-- Lines 73-78: Add local rules (SECOND iteration)
if local_config and local_config.hyperlink_rules then
  for _, rule in ipairs(local_config.hyperlink_rules) do
    table.insert(hyperlink_rules, rule)
    table.insert(hyperlink_regexes, rule.regex)
  end
end
```

**Optimized code (single pass):**
```lua
-- Build both arrays together when adding custom rules
local hyperlink_rules = wezterm.default_hyperlink_rules()
local hyperlink_regexes = {}

-- Extract regexes from default rules
for _, rule in ipairs(hyperlink_rules) do
  table.insert(hyperlink_regexes, rule.regex)
end

-- Add custom rules (build both arrays together)
for _, rule in ipairs({
  {
    regex = [[\b\w+://(?:[\d]{1,3}\.){3}[\d]{1,3}\S*\b]],
    format = "$0",
  },
  {
    regex = "\\bhttp://localhost:[0-9]+(?:/\\S*)?\\b",
    format = "$0",
  },
}) do
  table.insert(hyperlink_rules, rule)
  table.insert(hyperlink_regexes, rule.regex)  -- Add this line
end

-- Add local config rules (already optimal)
if local_config and local_config.hyperlink_rules then
  for _, rule in ipairs(local_config.hyperlink_rules) do
    table.insert(hyperlink_rules, rule)
    table.insert(hyperlink_regexes, rule.regex)
  end
end
```

**Impact:** Negligible performance gain (~1-2ms at startup), but improves code correctness and readability.

---

### Low Priority: Font Fallback Audit

**Problem:** 8 font fallbacks may include unused fonts, slowing glyph resolution

**Current fonts:**
```lua
config.font = wezterm.font_with_fallback({
  primary_font,                              -- Maple Mono
  { family = "Noto Color Emoji", scale = 0.75 },
  { family = "Symbols Nerd Font Mono", scale = 0.75 },
  { family = "Powerline Extra Symbols", scale = 0.75 },
  { family = "codicon", scale = 0.75 },
  { family = "Noto Sans Symbols", scale = 0.75 },
  { family = "Noto Sans Symbols2", scale = 0.75 },
  { family = "Font Awesome 6 Free", scale = 0.75 },
})
```

**Audit process:**
1. **Identify glyph usage:** Run `wezterm ls-fonts --list-system` to see available fonts
2. **Test common glyphs:** Check which fonts are actually used for icons in terminal (nvim, tmux, etc.)
3. **Remove unused fonts:** Keep only fonts that provide glyphs not in primary font

**Example glyphs to test:**
```bash
# Test which font provides each glyph
wezterm ls-fonts --text "$(echo -e "\U0001f5d8")"  # Trash icon
wezterm ls-fonts --text "$(echo -e "\ue0b0")"      # Powerline triangle
wezterm ls-fonts --text "$(echo -e "\uf015")"      # Font Awesome home
```

**Potential reduction:** May be able to remove 2-3 fonts if glyphs overlap

**Impact:** Minor - maybe 5-10ms improvement in glyph rendering for uncommon symbols

---

### Low Priority: Cleanup Unused Files

**Files to consider removing:**
- `colors/Tokyo Night Storm.toml` - Not used (uses built-in Catppuccin Mocha)
- `.builds/mirror.yml` - Only needed if using sr.ht CI mirroring

**Impact:** None on performance, just cleaner repository

---

## Efficient Patterns Already in Use ✅

These patterns are **already optimal** and should be preserved:

1. **Defensive loading with pcall**
   ```lua
   local ok, result = pcall(function() return require("local") end)
   if ok then local_config = result end
   ```
   - Fails fast if local.lua is missing
   - No error spam in terminal

2. **Minimal startup operations**
   - No expensive computations
   - No blocking I/O during initialization
   - No network requests

3. **User-triggered actions only**
   - No background polling or timers
   - No automatic file watchers
   - All expensive operations are manual (Ctrl+Shift+E)

4. **Static configuration**
   - WezTerm caches config after initial load
   - No dynamic reloads during runtime
   - No conditional logic during execution

5. **Clear separation of concerns**
   - Main config in `config.lua`
   - Machine-specific overrides in `local.lua`
   - No mixing of concerns

6. **Official WezTerm patterns**
   - Uses `wezterm.config_builder()` (recommended API)
   - Uses `wezterm.font_with_fallback()` (official pattern)
   - Uses `wezterm.on()` for event handlers (official pattern)

---

## Summary

### Performance Assessment

| Category | Rating | Notes |
|----------|--------|-------|
| **Startup Performance** | ⭐⭐⭐⭐⭐ | Excellent - minimal overhead |
| **Runtime Performance** | ⭐⭐⭐⭐☆ | Very good - only issue is blocking sleep |
| **Code Quality** | ⭐⭐⭐⭐☆ | Well-structured, clear, documented |
| **Maintainability** | ⭐⭐⭐⭐⭐ | Simple, no complex abstractions |
| **Resource Usage** | ⭐⭐⭐⭐⭐ | Minimal memory/CPU footprint |

### Key Findings

**Strengths:**
- ✅ Minimal startup overhead (<50ms)
- ✅ No background operations (zero CPU when idle)
- ✅ Defensive programming (pcall, safe fallbacks)
- ✅ Clean code structure with good comments
- ✅ Self-contained (no external dependencies)

**Issues:**
- ⚠️ **Critical:** 2-second blocking sleep in nvim handler (config.lua:123)
- ⚠️ **Minor:** Hyperlink array double iteration (config.lua:68-70)
- ⚠️ **Low:** Font fallback audit needed (8 fonts may be excessive)

### Recommended Optimizations (Priority Order)

1. **Reduce nvim handler sleep** - 2000ms → 100ms (high impact, low risk)
2. **Optimize hyperlink array construction** - single-pass building (low impact, improves correctness)
3. **Audit font fallbacks** - remove unused fonts (low impact, requires testing)
4. **Clean up unused files** - remove Tokyo Night Storm color scheme (no impact, cosmetic)

### Overall Verdict

This WezTerm configuration is **already highly optimized** and follows performance best practices. The only significant issue is the 2-second blocking sleep in the nvim scrollback handler, which can be easily fixed by reducing the sleep duration. All other optimizations are minor and provide marginal improvements.

**The configuration demonstrates:**
- Excellent understanding of WezTerm APIs
- Strong software engineering practices (defensive programming, separation of concerns)
- Performance-conscious design (minimal startup, no background overhead)
- Clean, maintainable code structure

**Next steps:** Proceed to planning phase to design specific performance improvements.
