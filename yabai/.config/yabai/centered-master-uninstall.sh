#!/usr/bin/env sh
# Roll back the centered master layout at runtime.
set -e
YABAI="${YABAI_BIN:-/opt/homebrew/bin/yabai}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/yabai-centered-master"

echo "Removing cm_* signals..."
"$YABAI" -m signal --list | /usr/bin/jq -r '.[]|select(.label|startswith("cm_"))|.label' \
  | while read -r l; do "$YABAI" -m signal --remove "$l" 2>/dev/null || true; done

echo "Restoring per-space padding, auto_balance and layout..."
GLOBAL_AB=$("$YABAI" -m config auto_balance)
for f in "$STATE"/*.pad; do
    [ -e "$f" ] || continue
    uuid=$(basename "$f" .pad)
    idx=$("$YABAI" -m query --spaces | /usr/bin/jq -r --arg u "$uuid" '.[]|select(.uuid==$u)|.index')
    [ -n "$idx" ] || continue
    read -r pl pr <"$f"
    "$YABAI" -m config --space "$idx" left_padding  "$pl"        >/dev/null 2>&1 || true
    "$YABAI" -m config --space "$idx" right_padding "$pr"        >/dev/null 2>&1 || true
    "$YABAI" -m config --space "$idx" auto_balance  "$GLOBAL_AB" >/dev/null 2>&1 || true
    "$YABAI" -m space "$idx" --balance                           >/dev/null 2>&1 || true
    echo "  space $idx restored (padding $pl/$pr)"
done

rm -rf "$STATE"
echo "Done. Remove the 'Centered master' blocks from yabairc and skhdrc to"
echo "make it permanent, or restore from ~/dotfiles/.backups/<timestamp>/."
