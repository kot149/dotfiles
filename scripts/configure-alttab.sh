#!/bin/sh
# AltTab "previous window" = Shift+Tab (macOS only).
# Task: `mise run configure-alttab`.
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Not macOS; skipping AltTab configuration."
  exit 0
fi

# https://github.com/lwouis/alt-tab-macos/blob/master/src/logic/Preferences.swift

previous_window_shortcut="$(printf '%b' '\342\207\247\342\207\245')"
/usr/bin/defaults write com.lwouis.alt-tab-macos previousWindowShortcut "$previous_window_shortcut"
echo "Set com.lwouis.alt-tab-macos previousWindowShortcut to Shift+Tab (⇧⇥)."
