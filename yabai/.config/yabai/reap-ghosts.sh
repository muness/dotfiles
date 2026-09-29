#!/usr/bin/env bash
#
# reap-ghosts.sh - drop dead windows from yabai's BSP tree.
#
# Some apps (Ghostty here) close a window without yabai ever seeing it go:
# window_destroyed never fires, `query` still knows the id, and the window keeps
# its leaf in the tree. Its tile then stays reserved, so neighbours never grow
# into the gap and the next window lands in the wrong slot.
#
# A ghost is a tiled standard window on an on-screen space that is not visible,
# not hidden, not minimised and not native-fullscreen. Floating it removes its
# leaf and lets yabai rebalance. Idempotent, and cheap when there are no ghosts.
# Debounced, because the ghost is only recognisable once the close has settled.

YABAI="${YABAI_BIN:-/opt/homebrew/bin/yabai}"
JQ="${JQ_BIN:-/usr/bin/jq}"
TOK="${XDG_STATE_HOME:-$HOME/.local/state}/yabai-centered-master/.reap"
mkdir -p "$(dirname "$TOK")"

me="$$-$(date +%s%N)"; echo "$me" >"$TOK"; sleep 0.4
[ "$(cat "$TOK" 2>/dev/null)" = "$me" ] || exit 0

# The ghosts are missing from every list query and only answer `--window <id>`,
# so remember every tiled window id while it is alive and re-probe them by id.
SEEN="$(dirname "$TOK")/reap.seen"; touch "$SEEN"
live=$("$YABAI" -m query --windows 2>/dev/null | "$JQ" -r '.[]|select(.subrole=="AXStandardWindow")|.id')
[ -n "$live" ] || exit 0
vis=$("$YABAI" -m query --spaces 2>/dev/null | "$JQ" -r '.[]|select(."is-visible")|.index')
ends=$(for s in $vis; do "$YABAI" -m query --spaces --space "$s" 2>/dev/null \
       | "$JQ" -r '."first-window",."last-window"'; done)
ids=$(printf '%s\n%s\n%s\n' "$live" "$ends" "$(cat "$SEEN")" | grep -E '^[0-9]+$' | sort -un)
: >"$SEEN.new"
for id in $ids; do
    w=$("$YABAI" -m query --windows --window "$id" 2>/dev/null) || continue   # truly gone: forget it
    [ -n "$w" ] || continue
    if printf '%s' "$w" | "$JQ" -e --argjson v "$(printf '%s\n' $vis | "$JQ" -Rs '[split("\n")[]|select(length>0)|tonumber]')" '
        .subrole=="AXStandardWindow" and (."is-floating"|not) and (."is-visible"|not)
        and (."is-hidden"|not) and (."is-minimized"|not) and (."is-native-fullscreen"|not)
        and (.space as $sp | $v | index($sp) != null)' >/dev/null; then
        "$YABAI" -m window "$id" --toggle float >/dev/null 2>&1      # ghost: drop its leaf
    fi
    echo "$id" >>"$SEEN.new"
done
mv "$SEEN.new" "$SEEN"
