#!/usr/bin/env bash
# Roll back the centered master layout at runtime.
YABAI="${YABAI_BIN:-/opt/homebrew/bin/yabai}"
CM="$HOME/.config/yabai/centered-master.sh"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/yabai-centered-master"

echo "Releasing managed spaces..."
for f in "$STATE"/*.state; do
    [ -e "$f" ] || continue
    uuid=$(basename "$f" .state)
    idx=$("$YABAI" -m query --spaces 2>/dev/null \
          | /usr/bin/jq -r --arg u "$uuid" '.[]|select(.uuid==$u)|.index')
    [ -n "$idx" ] || continue
    "$CM" uncenter "$idx" 2>/dev/null || true
done

echo "Removing cm_* signals..."
"$YABAI" -m signal --list 2>/dev/null \
  | /usr/bin/jq -r '.[]|select(.label|startswith("cm_"))|.label' \
  | while read -r l; do "$YABAI" -m signal --remove "$l" 2>/dev/null || true; done

rm -rf "$STATE"
echo "Done. Remove the 'Centered master' blocks from yabairc and skhdrc to make"
echo "it permanent, or restore from ~/dotfiles/.backups/<timestamp>/."
