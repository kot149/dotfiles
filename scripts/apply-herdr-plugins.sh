#!/bin/sh
# Link herdr Python plugins and reload config (non-Windows).
#
# Task: `mise run apply-herdr-plugins`.
set -eu

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "Windows detected; skipping herdr plugin link."; exit 0 ;;
esac

link_plugin() {
  plugin_id="$1"
  plugin_dir="$2"

  if [ ! -f "$plugin_dir/herdr-plugin.toml" ]; then
    echo "$plugin_dir is missing a manifest; skipping $plugin_id link."
    return 0
  fi

  if herdr plugin list 2>/dev/null | grep -q "^- $plugin_id "; then
    echo "$plugin_id already linked."
  else
    echo "Linking $plugin_id..."
    herdr plugin link "$plugin_dir"
  fi
}

if ! command -v herdr >/dev/null 2>&1; then
  echo "herdr not found; skipping plugin link."
  exit 0
fi

link_plugin "local.copy-output" "$HOME/.local/share/herdr-plugins/copy-output-py"
link_plugin "local.next-agent" "$HOME/.local/share/herdr-plugins/next-agent-py"

herdr server reload-config >/dev/null 2>&1 || true
