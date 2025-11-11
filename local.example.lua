local base_url = "https://foobar.com/"

local module = {
  primary_font = "Menlo",
  hyperlink_rules = {
    {
      regex = "\\b([fF][bB]-\\d+)\\b",
      format = base_url .. "$1",
    },
  },
  url_transforms = {
    {
      prefixes = { "FB-", "fb-" },
      format = function(text)
        return base_url .. text
      end,
    },
  },
}

function module.apply_to_config(config)
  config.font_size = 18
  config.color_scheme = "Batman"
end

return module
