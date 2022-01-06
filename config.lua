local wezterm = require 'wezterm'

function os.capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

local font_size = 12
local os_name = os.capture 'uname'

if os_name == "Darwin" then
  font_size = 16
end

return {
  default_cursor_style = "BlinkingBlock",
  font = wezterm.font("JetBrainsMono Nerd Font"),
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
  color_scheme = "Tokyo Night Storm"
}
