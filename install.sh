#!/usr/bin/env bash
# install.sh — Claude Code StatusLine (Catppuccin Mocha) installer
# Usage: bash install.sh

set -euo pipefail

DEST="$HOME/.claude"
SETTINGS="$DEST/settings.json"

# ── Dependency check ──
MISSING=()
for cmd in jq bc git; do
  command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd")
done
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Error: missing required tools: ${MISSING[*]}"
  echo "Install with: brew install ${MISSING[*]}"
  exit 1
fi

# ── Backup existing statusline ──
if [ -f "$DEST/statusline.sh" ]; then
  cp "$DEST/statusline.sh" "$DEST/statusline.sh.bak"
  echo "Backed up existing statusline to statusline.sh.bak"
fi

# ── Install scripts ──
install -m 755 statusline.sh    "$DEST/statusline.sh"
install -m 755 gemini-banner.sh "$DEST/gemini-banner.sh"
install -m 755 codex-banner.sh  "$DEST/codex-banner.sh"
echo "Installed scripts to $DEST/"

# ── Merge settings.json (preserves existing config) ──
if [ -f "$SETTINGS" ]; then
  jq '. + {
    "statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 2},
    "refreshInterval": 60
  }' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "Updated $SETTINGS"
else
  echo "Warning: $SETTINGS not found. Create it manually with:"
  echo '  {"statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 2}, "refreshInterval": 60}'
fi

echo ""
echo "✓ Installation complete. Restart Claude Code to activate the status bar."
echo ""
echo "Optional: add to ~/.zshrc for Gemini/Codex banners:"
echo '  g() { ~/.claude/gemini-banner.sh; gemini "$@"; }'
echo '  cx() { ~/.claude/codex-banner.sh; codex "$@"; }'
