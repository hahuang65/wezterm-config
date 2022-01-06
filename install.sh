#!/bin/sh

mkdir -p "${HOME}/.config/wezterm"

ln -sf "${PWD}/config.lua" "${HOME}/.config/wezterm/wezterm.lua"
ln -sf "${PWD}/colors" "${HOME}/.config/wezterm/colors"
