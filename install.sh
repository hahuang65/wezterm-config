#!/bin/sh

mkdir -p "${HOME}/.config/wezterm"
mkdir -p "${HOME}/.config/wezterm/colors"

ln -sf "${PWD}/config.lua" "${HOME}/.config/wezterm/wezterm.lua"

for color in colors/*.toml
do
    ln -sf "${PWD}/${color}" "${HOME}/.config/wezterm/colors/"
done

for color in colors/*.lua
do
    ln -sf "${PWD}/${color}" "${HOME}/.config/wezterm/colors/"
done
