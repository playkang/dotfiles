#!/usr/bin/env bash
# dotfiles install script
# Usage: bash install.sh
# Or one-liner: curl -s https://raw.githubusercontent.com/playkang/dotfiles/main/install.sh | bash

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "==> Installing dotfiles from $DOTFILES_DIR"

# ── Claude statusline ───────────────────────────────────────────────────────
install_claude_statusline() {
  echo ""
  echo "==> Installing Claude Code statusline..."

  mkdir -p "$CLAUDE_DIR"

  # Copy statusline script
  cp "$DOTFILES_DIR/claude/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
  chmod +x "$CLAUDE_DIR/statusline-command.sh"
  echo "    ✓ statusline-command.sh installed"

  # Merge statusLine config into existing settings.json
  SETTINGS="$CLAUDE_DIR/settings.json"
  STATUSLINE_CONFIG='{
  "statusLine": {
    "type": "command",
    "command": "bash '"$CLAUDE_DIR"'/statusline-command.sh"
  }
}'

  if [ -f "$SETTINGS" ]; then
    # Merge: keep existing settings, add/overwrite statusLine key
    if command -v jq &>/dev/null; then
      tmp=$(mktemp)
      jq --argjson sl "$(echo "$STATUSLINE_CONFIG" | jq '.statusLine')" \
        '.statusLine = $sl' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
      echo "    ✓ statusLine merged into existing settings.json"
    else
      echo "    ⚠ jq not found — please manually add to $SETTINGS:"
      echo "$STATUSLINE_CONFIG"
    fi
  else
    echo "$STATUSLINE_CONFIG" > "$SETTINGS"
    echo "    ✓ settings.json created"
  fi
}

install_claude_statusline

echo ""
echo "✅ Done! Restart Claude Code to apply changes."
