#!/bin/sh
# karabiner.edn -> karabiner.json (macOS only).
# Task: `mise run apply-karabiner-goku` (sources: dotfiles/.config/karabiner.edn).
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Not macOS; skipping Karabiner generation."
  exit 0
fi

echo "Updating Karabiner config..."

edn_file="$HOME/.config/karabiner.edn"
karabiner_dir="$HOME/.config/karabiner"
karabiner_json="$karabiner_dir/karabiner.json"
karabiner_cli="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"

if [ ! -f "$edn_file" ]; then
  echo "$edn_file does not exist; skipping Karabiner JSON generation."
  exit 0
fi

mkdir -p "$karabiner_dir"

if [ ! -f "$karabiner_json" ]; then
  cat >"$karabiner_json" <<'JSON'
{
  "profiles": [
    {
      "complex_modifications": {
        "parameters": {
          "basic.to_delayed_action_delay_milliseconds": 300
        },
        "rules": []
      },
      "devices": [
        {
          "identifiers": {
            "is_keyboard": true,
            "is_pointing_device": true,
            "product_id": 24926,
            "vendor_id": 7504
          },
          "ignore": false,
          "manipulate_caps_lock_led": false
        }
      ],
      "name": "US",
      "selected": true,
      "virtual_hid_keyboard": {
        "keyboard_type_v2": "ansi"
      }
    }
  ]
}
JSON
fi

GOKU_EDN_CONFIG_FILE="$edn_file" nix run nixpkgs#goku --

if [ -x "$karabiner_cli" ]; then
  "$karabiner_cli" --select-profile US
fi
