local wezterm = require 'wezterm'
local io = require 'io';
local os = require 'os';

-- Boolean function that returns true of a string starts with the passed in argument.
local function starts_with(str, start)
   return str:sub(1, #start) == start
end

local a5_regex = "\\b([aA]5-\\d+)\\b"
local a5_base_url = "https://alpha5sp.atlassian.net/browse/"
local font_size = 12

if wezterm.target_triple == "x86_64-apple-darwin" then
  font_size = 16
elseif wezterm.hostname() == "bespin" then
  font_size = 14
elseif wezterm.hostname() == "jedha" then
  font_size = 13
end

-- Useful keybinds:
-- Scrollback: https://wezfurlong.org/wezterm/scrollback.html
-- Ctrl-Shift-E to open scrollback in nvim
-- Ctrl-Shift-F to search scrollback
-- Ctrl-Shift-H to search for git hashes (implemented below)
-- Ctrl-Shift-U to scroll back 1 page (implemented in keybinds)
-- Ctrl-Shift-D to scroll forward 1 page (implemented in keybinds)
-- Ctrl-N/Ctrl-P to cycle thru search results
-- Ctrl-E to open the scrollback in a nvim buffer (configured below)
-- Ctrl-Shift-Space to open Quick Select https://wezfurlong.org/wezterm/quickselect.html
-- Ctrl-Shift-X to open Copy Mode https://wezfurlong.org/wezterm/copymode.html

-- https://wezfurlong.org/wezterm/config/lua/wezterm/on.html
wezterm.on("trigger-nvim-with-scrollback", function(window, pane)
  -- Retrieve the current viewport's text.
  -- Pass an optional number of lines (eg: 2000) to retrieve
  -- that number of lines starting from the bottom of the viewport.
  local scrollback = pane:get_lines_as_text();

  -- Create a temporary file to pass to vim
  local name = os.tmpname();
  local f = io.open(name, "w+");
  f:write(scrollback);
  f:flush();
  f:close();

  -- Open a new window running vim and tell it to open the file
  window:perform_action(wezterm.action{SpawnCommandInNewWindow={
    args={"nvim", name}}
  }, pane)

  -- wait "enough" time for vim to read the file before we remove it.
  -- The window creation and process spawn are asynchronous
  -- wrt. running this script and are not awaitable, so we just pick
  -- a number.  We don't strictly need to remove this file, but it
  -- is nice to avoid cluttering up the temporary file directory
  -- location.
  wezterm.sleep_ms(1000);
  os.remove(name);
end)

-- Ran into an issue in nightly build where Alt-` stopped working.
-- It should be fixed now, but if it ever doesn't work, then
-- `use_dead_keys = true` should fix it.
return {
  default_cursor_style = "BlinkingBlock",
  -- Troubleshoot fonts with `wezterm ls-fonts`
  -- e.g. `wezterm ls-fonts --text "$(echo -e "\U0001f5d8")"` to find what font contains that glyph
  font = wezterm.font_with_fallback({
    "Iosevka",
    "Noto Color Emoji",
    "Symbols Nerd Font Mono",
    "Powerline Extra Symbols",
    "codicon",
    "Noto Sans Symbols",
    "Noto Sans Symbols2",
    "Font Awesome 6 Free"
  }),
  font_size = font_size,
  enable_tab_bar = false,
  enable_wayland = true,
  window_decorations = "RESIZE",
  window_padding = {
    left = "4px",
    right = "4px",
    top = "2px",
    bottom = "2px"
  },
  use_resize_increments = true,
  color_scheme = "Catppuccin",
  scrollback_lines = 10000,
  keys = {
    -- Open scrollback in nvim
    {key="E", mods="SHIFT|CTRL", action=wezterm.action{EmitEvent="trigger-nvim-with-scrollback"}},
    -- search for things that look like git hashes
    {key="H", mods="SHIFT|CTRL", action=wezterm.action{Search={Regex="[a-f0-9]{6,}"}}},
    -- Scroll the scrollback
    {key="D", mods="SHIFT|CTRL", action=wezterm.action{ScrollByPage=0.5}},
    {key="U", mods="SHIFT|CTRL", action=wezterm.action{ScrollByPage=-0.5}},
    -- Open browser with quickselect https://github.com/wez/wezterm/issues/1362#issuecomment-1000457693
    {key="O", mods="SHIFT|CTRL",
      action=wezterm.action{QuickSelectArgs={
        patterns={
          "https?://\\S+",
          a5_regex
        },
        action = wezterm.action_callback(function(window, pane)
          local url = window:get_selection_text_for_pane(pane)
          if starts_with(url, "A5-") or starts_with(url, "a5-") then
            url = a5_base_url .. url
          end

          wezterm.log_info("Opening: " .. url)
          wezterm.open_with(url)
        end)
      }
    }
   },
  },
  hyperlink_rules = {
    { -- Make A5 Jira links clickable
      regex = a5_regex,
      format = a5_base_url .. "$1"
    }
  }
}
