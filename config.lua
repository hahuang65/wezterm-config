local wezterm = require 'wezterm'

return {
  font = wezterm.font("JetBrains Mono"),
  font_size = 12,
  enable_tab_bar = false,
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
