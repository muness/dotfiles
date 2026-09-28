#!/usr/bin/env bash
#
# centered-master.sh - a centered-master layout facade over yabai.
#
#   +--------+------------------+--------+
#   | left 0 |                  | right0 |
#   +--------+      MASTER      +--------+
#   | left 1 |                  | right1 |
#   +--------+------------------+--------+
#
# This does NOT negotiate with yabai's BSP tree. It owns the layout model
# (a master window plus two ordered columns) and renders it by setting
# absolute frames, the way dwm/Hyprland compute layout as a pure function of
# the window list. yabai is demoted to two roles: event source, and the thing
# that tells us which windows are worth managing.
#
# An earlier version of this script tried to drive yabai's tree with `--warp`
# and failed: `window --warp <id>` reorders at the target's level rather than
# splitting the target leaf, and the insertion point set by `window --insert`
# is a toggle that `query` does not expose, so neither can be driven
# deterministically from outside the process.
#
# A Space is managed iff it has a master. `center` sets one, `uncenter`
# clears it and hands the windows back to yabai. There is no enable flag.
#
# Requires: yabai, jq, bash, osascript. No scripting addition; SIP can stay on.

set -uo pipefail

YABAI="${YABAI_BIN:-/opt/homebrew/bin/yabai}"
JQ="${JQ_BIN:-/usr/bin/jq}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/yabai-centered-master"
LOCK_DIR="$STATE_DIR/.lock"
LOG_FILE="$STATE_DIR/log"

DEFAULT_RATIO="${CM_RATIO:-0.50}"
MIN_RATIO="${CM_MIN_RATIO:-0.20}"
MAX_RATIO="${CM_MAX_RATIO:-0.85}"
RATIO_STEP="${CM_RATIO_STEP:-0.05}"
DEBUG="${CM_DEBUG:-0}"

mkdir -p "$STATE_DIR"
log(){ [ "$DEBUG" = 1 ] && printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG_FILE"; return 0; }
die(){ printf 'centered-master: %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
# Lock (macOS has no flock(1); mkdir is atomic)
# --------------------------------------------------------------------------
LOCK_HELD=0
lock(){ local waited=0 limit="${1:-0}" owner
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        owner=$(cat "$LOCK_DIR/pid" 2>/dev/null)
        if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then rm -rf "$LOCK_DIR"; continue; fi
        if [ -d "$LOCK_DIR" ] && [ -z "$(find "$LOCK_DIR" -maxdepth 0 -mtime -10s 2>/dev/null)" ]; then
            rm -rf "$LOCK_DIR"; continue; fi
        awk "BEGIN{exit !($waited>=$limit)}" && return 1
        sleep 0.05; waited=$(awk "BEGIN{print $waited+0.05}")
    done
    echo $$ >"$LOCK_DIR/pid"; LOCK_HELD=1; trap unlock EXIT INT TERM; return 0; }
unlock(){ [ "$LOCK_HELD" = 1 ] && rm -rf "$LOCK_DIR"; LOCK_HELD=0; }

# --------------------------------------------------------------------------
# Space + state
# --------------------------------------------------------------------------
sp_uuid=""; sp_index=""; sp_display=""; sp_visible=""; sp_fullscreen=""
st_master=""; st_ratio=""; st_left=""; st_right=""; st_owned=""

space_resolve(){ local j
    if [ -n "${1:-}" ]; then j=$("$YABAI" -m query --spaces --space "$1" 2>/dev/null)
    else j=$("$YABAI" -m query --spaces --space 2>/dev/null); fi
    [ -n "$j" ] || return 1
    sp_uuid=$(printf '%s' "$j"|"$JQ" -r '.uuid'); [ -n "$sp_uuid" ] && [ "$sp_uuid" != null ] || return 1
    sp_index=$(printf '%s' "$j"|"$JQ" -r '.index')
    sp_display=$(printf '%s' "$j"|"$JQ" -r '.display')
    sp_visible=$(printf '%s' "$j"|"$JQ" -r '."is-visible"')
    sp_fullscreen=$(printf '%s' "$j"|"$JQ" -r '."is-native-fullscreen"'); }

sfile(){ printf '%s/%s.state' "$STATE_DIR" "${1:-$sp_uuid}"; }
state_load(){ local f k v; f=$(sfile)
    st_master=""; st_ratio="$DEFAULT_RATIO"; st_left=""; st_right=""; st_owned=""
    [ -f "$f" ] || return 0
    while IFS='=' read -r k v; do case "$k" in
        master) st_master="$v";; ratio) st_ratio="$v";;
        left) st_left="$v";; right) st_right="$v";; owned) st_owned="$v";; esac
    done <"$f"; return 0; }
state_save(){ local f; f=$(sfile)
    { printf 'master=%s\nratio=%s\nleft=%s\nright=%s\nowned=%s\n' \
        "$st_master" "$st_ratio" "$st_left" "$st_right" "$st_owned"; } >"$f.tmp" && mv "$f.tmp" "$f"; }
state_clear(){ rm -f "$(sfile)"; st_master=""; st_left=""; st_right=""; st_owned=""; }
managed(){ [ -n "$st_master" ]; }

# --------------------------------------------------------------------------
# Usable screen rect, menubar/dock aware.
# yabai only reports the raw display frame, so ask AppKit for visibleFrame and
# flip it from AppKit's bottom-left origin into yabai's top-left coordinates.
# Cached per display: the osascript round-trip costs ~150ms.
# --------------------------------------------------------------------------
usable_rect(){ # -> "x y w h"
    local cache="$STATE_DIR/display-$sp_display.rect"
    if [ -f "$cache" ]; then cat "$cache"; return 0; fi
    local dframe dx dw out
    dframe=$("$YABAI" -m query --displays --display "$sp_display" 2>/dev/null)
    dx=$(printf '%s' "$dframe"|"$JQ" -r '.frame.x'); dw=$(printf '%s' "$dframe"|"$JQ" -r '.frame.w')
    out=$(osascript -l JavaScript <<'JXA' 2>/dev/null
ObjC.import("AppKit");
var o=[], ss=$.NSScreen.screens;
for (var i=0;i<ss.count;i++){ var s=ss.objectAtIndex(i), f=s.frame, v=s.visibleFrame;
  o.push([v.origin.x, f.size.height-(v.origin.y+v.size.height), v.size.width, v.size.height].join(" ")); }
o.join("\n");
JXA
)
    # Match the AppKit screen to this yabai display by x-origin and width.
    local line best=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        set -- $line
        if awk "BEGIN{exit !(($1-$dx)^2<=4 && ($3-$dw)^2<=4)}"; then best="$line"; break; fi
    done <<<"$out"
    [ -n "$best" ] && { printf '%s\n' "$best" | tee "$cache"; return 0; }
    # Fallback: raw display frame inset by the standard menubar height.
    printf '%s %s %s %s\n' "$dx" 25 "$dw" \
        "$(awk "BEGIN{print $(printf '%s' "$dframe"|"$JQ" -r '.frame.h')-25}")"
}
rect_cache_clear(){ rm -f "$STATE_DIR"/display-*.rect; }

gap(){ "$YABAI" -m config --space "$sp_index" window_gap 2>/dev/null || echo 10; }
pad(){ "$YABAI" -m config --space "$sp_index" "$1" 2>/dev/null || echo 10; }

# --------------------------------------------------------------------------
# Window sets
# --------------------------------------------------------------------------
# Candidates: real, non-minimised, non-hidden standard windows on this space.
candidates(){ "$YABAI" -m query --windows --space "$sp_index" 2>/dev/null | "$JQ" -r '
    .[] | select((."is-minimized"|not) and (."is-hidden"|not)
                 and (."is-native-fullscreen"|not) and .subrole=="AXStandardWindow")
    | .id'; }
# Windows yabai is currently TILING. Membership is seeded from this, so every
# `manage=off` rule in yabairc is honoured without us knowing about it.
tiled(){ "$YABAI" -m query --windows --space "$sp_index" 2>/dev/null | "$JQ" -r '
    .[] | select((."is-floating"|not) and (."is-minimized"|not) and (."is-hidden"|not)
                 and ."is-visible" and (."is-native-fullscreen"|not)) | .id'; }
focused(){ "$YABAI" -m query --windows --window 2>/dev/null | "$JQ" -r '.id // empty'; }
# Every window id on the space, with no filtering at all. `owned` is pruned
# against this rather than against candidates(), because a minimised window
# still exists and must stay owned so it can be re-adopted when it returns.
extant(){ "$YABAI" -m query --windows --space "$sp_index" 2>/dev/null | "$JQ" -r '.[].id'; }

has(){ case ",$1," in *",$2,"*) return 0;; *) return 1;; esac; }
add(){ if [ -z "$1" ]; then printf '%s' "$2"; else printf '%s,%s' "$1" "$2"; fi; }
del(){ printf '%s' "$1"|tr ',' '\n'|grep -vx "$2"|paste -sd, -; }
cnt(){ [ -z "$1" ] && { echo 0; return; }; printf '%s' "$1"|tr ',' '\n'|grep -c .; }
nth(){ printf '%s' "$1"|cut -d, -f"$2"; }
idx(){ printf '%s' "$1"|tr ',' '\n'|grep -nx "$2"|cut -d: -f1; }

# --------------------------------------------------------------------------
# Model reconciliation
# --------------------------------------------------------------------------
reconcile(){ local live nl="" nr="" id
    live=$(candidates)
    for id in $(printf '%s' "$st_left" |tr ',' ' '); do printf '%s\n' "$live"|grep -qx "$id" && nl=$(add "$nl" "$id"); done
    for id in $(printf '%s' "$st_right"|tr ',' ' '); do printf '%s\n' "$live"|grep -qx "$id" && nr=$(add "$nr" "$id"); done
    st_left="$nl"; st_right="$nr"
    local no="" alive; alive=$(extant)
    for id in $(printf '%s' "$st_owned"|tr ',' ' '); do
        printf '%s\n' "$alive"|grep -qx "$id" && no=$(add "$no" "$id"); done
    st_owned="$no"

    # Master gone: take the head of the longer column, deterministically.
    if [ -z "$st_master" ] || ! printf '%s\n' "$live"|grep -qx "$st_master"; then
        local c=""
        if [ "$(cnt "$st_left")" -ge "$(cnt "$st_right")" ]; then c=$(nth "$st_left" 1); fi
        [ -z "$c" ] && c=$(nth "$st_right" 1)
        [ -z "$c" ] && c=$(nth "$st_left" 1)
        [ -z "$c" ] && c=$(printf '%s\n' "$live"|head -1)
        st_master="$c"; log "master -> $st_master"
    fi
    st_left=$(del "$st_left" "$st_master"); st_right=$(del "$st_right" "$st_master")

    # Adopt new windows, but only ones yabai would have tiled, so `manage=off`
    # rules keep working. Shorter column wins; ties go left.
    local t; t=$(tiled)
    for id in $(printf '%s\n' "$live"|sort -n); do
        [ "$id" = "$st_master" ] && continue
        has "$st_left" "$id" && continue
        has "$st_right" "$id" && continue
        printf '%s\n' "$t"|grep -qx "$id" || has "$st_owned" "$id" || continue
        if [ "$(cnt "$st_left")" -le "$(cnt "$st_right")" ]
        then st_left=$(add "$st_left" "$id"); else st_right=$(add "$st_right" "$id"); fi
    done

    # Rebalance only at a difference of 2+, so ordinary churn does not shuffle
    # windows the user has deliberately placed.
    local mv
    while [ $(( $(cnt "$st_left") - $(cnt "$st_right") )) -ge 2 ]; do
        mv=$(printf '%s' "$st_left"|tr ',' '\n'|tail -1)
        st_left=$(del "$st_left" "$mv"); st_right=$(add "$st_right" "$mv"); done
    while [ $(( $(cnt "$st_right") - $(cnt "$st_left") )) -ge 2 ]; do
        mv=$(printf '%s' "$st_right"|tr ',' '\n'|tail -1)
        st_right=$(del "$st_right" "$mv"); st_left=$(add "$st_left" "$mv"); done
}

# --------------------------------------------------------------------------
# The layout function: model -> frames. Pure; prints "id x y w h" per line.
# The side columns are always allotted their width even when empty, which is
# what keeps the master centred at one and two windows.
# --------------------------------------------------------------------------
layout(){
    local ux uy uw uh g pl pr pt pb
    read -r ux uy uw uh <<<"$(usable_rect)"
    g=$(gap); pl=$(pad left_padding); pr=$(pad right_padding)
    pt=$(pad top_padding); pb=$(pad bottom_padding)
    ux=$((ux+pl)); uw=$((uw-pl-pr)); uy=$((uy+pt)); uh=$((uh-pt-pb))

    awk -v ux="$ux" -v uy="$uy" -v uw="$uw" -v uh="$uh" -v g="$g" \
        -v r="$st_ratio" -v m="$st_master" -v L="$st_left" -v R="$st_right" '
    function col(list, x, w,   n,i,a,hh,yy) {
        if (list == "") return
        n = split(list, a, ",")
        hh = int((uh - (n-1)*g) / n)
        for (i = 1; i <= n; i++) {
            yy = uy + (i-1)*(hh+g)
            if (i == n) hh = uy + uh - yy          # absorb rounding in the last row
            printf "%s %d %d %d %d\n", a[i], x, yy, w, hh
        }
    }
    BEGIN {
        mw = int(r*uw + 0.5)
        sw = int((uw - mw - 2*g) / 2)
        if (sw < 0) { sw = 0; mw = uw }
        mx = ux + sw + g
        printf "%s %d %d %d %d\n", m, mx, uy, mw, uh
        col(L, ux, sw)
        col(R, mx + mw + g, sw)
    }'
}

apply_frames(){ local id x y w h cur
    while read -r id x y w h; do
        [ -n "$id" ] || continue
        cur=$("$YABAI" -m query --windows --window "$id" 2>/dev/null \
              | "$JQ" -r '"\(.frame.x|floor) \(.frame.y|floor) \(.frame.w|floor) \(.frame.h|floor) \(."is-floating")"')
        set -- $cur
        [ "${5:-}" = "true" ] || "$YABAI" -m window "$id" --toggle float >/dev/null 2>&1
        has "$st_owned" "$id" || st_owned=$(add "$st_owned" "$id")
        # Skip windows already in place; apps with a minimum size would
        # otherwise be re-poked on every single event.
        if [ "${1:-}" != "$x" ] || [ "${2:-}" != "$y" ]; then
            "$YABAI" -m window "$id" --move abs:"$x":"$y" >/dev/null 2>&1; fi
        if [ "${3:-}" != "$w" ] || [ "${4:-}" != "$h" ]; then
            "$YABAI" -m window "$id" --resize abs:"$w":"$h" >/dev/null 2>&1; fi
    done
}

render(){
    managed || return 0
    reconcile
    managed || { state_clear; return 0; }
    # NB: not `layout | apply_frames` -- the right-hand side of a pipe runs in
    # a subshell, and apply_frames has to mutate st_owned in this one.
    local plan; plan=$(layout)
    apply_frames <<<"$plan"
    state_save
}

# yabai cannot set frames on a Space that is not on screen; the call succeeds
# and does nothing. So defer, and let space_changed pick it up.
renderable(){ [ "$sp_visible" = true ] && [ "$sp_fullscreen" != true ]; }

# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------
cmd_center(){ space_resolve "${1:-}" || die "no space"
    state_load; lock 3 || return 0
    local f; f=$(focused)
    if [ -n "$f" ] && printf '%s\n' "$(candidates)"|grep -qx "$f"; then
        st_left=$(del "$st_left" "$f"); st_right=$(del "$st_right" "$f")
        [ -n "$st_master" ] && [ "$st_master" != "$f" ] && {
            if [ "$(cnt "$st_left")" -le "$(cnt "$st_right")" ]
            then st_left=$(add "$st_left" "$st_master"); else st_right=$(add "$st_right" "$st_master"); fi; }
        st_master="$f"
    fi
    [ -n "$st_master" ] || st_master=$(tiled|head -1)
    [ -n "$st_master" ] || { unlock; die "no window to make master on space $sp_index"; }
    render; unlock
    printf 'centered-master: space %s, master %s\n' "$sp_index" "$st_master"; }

cmd_uncenter(){ space_resolve "${1:-}" || die "no space"
    state_load; managed || { printf 'centered-master: space %s not managed\n' "$sp_index"; return 0; }
    lock 3 || return 0
    local id
    for id in $(printf '%s,%s,%s' "$st_master" "$st_left,$st_right" "$st_owned"|tr ',' ' '|sort -u); do
        [ -n "$id" ] || continue
        "$YABAI" -m query --windows --window "$id" 2>/dev/null|"$JQ" -e '."is-floating"' >/dev/null 2>&1 \
            && "$YABAI" -m window "$id" --toggle float >/dev/null 2>&1
    done
    state_clear; "$YABAI" -m space "$sp_index" --balance >/dev/null 2>&1
    unlock; printf 'centered-master: space %s released back to bsp\n' "$sp_index"; }

cmd_promote(){ cmd_center "${1:-}"; }

# One key for on/off. Deliberately ignores which window is focused: if the
# space is centred it is released, full stop. Promoting a different window to
# master is `center`/`promote`, so that a mis-aimed toggle can never silently
# reshuffle the layout when you meant to switch it off.
cmd_toggle(){ space_resolve "${1:-}" || die "no space"; state_load
    if managed; then cmd_uncenter "$sp_index"; else cmd_center "$sp_index"; fi; }

cmd_width(){ space_resolve "" || die "no space"; state_load
    managed || die "space $sp_index is not centered"
    local a="${1:?usage: width +0.05|-0.05|<fraction>}"
    case "$a" in +*|-*) st_ratio=$(awk "BEGIN{printf \"%.4f\", $st_ratio+($a)}");;
                 *)     st_ratio=$(awk "BEGIN{printf \"%.4f\", $a}");; esac
    st_ratio=$(awk "BEGIN{v=$st_ratio; if(v<$MIN_RATIO)v=$MIN_RATIO; if(v>$MAX_RATIO)v=$MAX_RATIO; printf \"%.4f\",v}")
    lock 3 || return 0; render; unlock; }

# Directional focus/swap resolved against the model, because yabai's own
# directional commands operate on the BSP tree, which no longer describes
# anything once these windows are floating.
slot_of(){ local w="$1"
    [ "$w" = "$st_master" ] && { echo "m 0"; return; }
    has "$st_left"  "$w" && { echo "l $(idx "$st_left" "$w")"; return; }
    has "$st_right" "$w" && { echo "r $(idx "$st_right" "$w")"; return; }
    echo "? 0"; }

neighbour(){ # $1 = direction -> window id or empty
    local w col i; w=$(focused); [ -n "$w" ] || return 1
    read -r col i <<<"$(slot_of "$w")"
    case "$col:$1" in
        m:west)  nth "$st_left"  1 ;;
        m:east)  nth "$st_right" 1 ;;
        l:east)  echo "$st_master" ;;
        r:west)  echo "$st_master" ;;
        l:north) [ "$i" -gt 1 ] && nth "$st_left" $((i-1)) ;;
        l:south) [ "$i" -lt "$(cnt "$st_left")" ] && nth "$st_left" $((i+1)) ;;
        r:north) [ "$i" -gt 1 ] && nth "$st_right" $((i-1)) ;;
        r:south) [ "$i" -lt "$(cnt "$st_right")" ] && nth "$st_right" $((i+1)) ;;
        *) return 1 ;;
    esac; }

cmd_focus(){ space_resolve "" || die "no space"; state_load
    managed || { "$YABAI" -m window --focus "${1:?direction}" >/dev/null 2>&1 \
                 || "$YABAI" -m display --focus "$1" >/dev/null 2>&1; return 0; }
    local t; t=$(neighbour "${1:?direction}")
    [ -n "$t" ] && "$YABAI" -m window --focus "$t" >/dev/null 2>&1; }

cmd_swap(){ space_resolve "" || die "no space"; state_load
    managed || { "$YABAI" -m window --swap "${1:?direction}" >/dev/null 2>&1 \
                 || { "$YABAI" -m window --display "$1" >/dev/null 2>&1 \
                      && "$YABAI" -m display --focus "$1" >/dev/null 2>&1; }; return 0; }
    local w t; w=$(focused); t=$(neighbour "${1:?direction}")
    [ -n "$t" ] || return 0
    lock 3 || return 0
    # Exchange the two ids wherever they sit in the model.
    local swap_one
    swap_one(){ printf '%s' "$1"|tr ',' '\n'|awk -v a="$2" -v b="$3" \
        '{ if($0==a) print b; else if($0==b) print a; else print }'|paste -sd, -; }
    [ "$st_master" = "$w" ] && st_master="$t" || { [ "$st_master" = "$t" ] && st_master="$w"; }
    st_left=$(swap_one "$st_left" "$w" "$t"); st_right=$(swap_one "$st_right" "$w" "$t")
    render; unlock; "$YABAI" -m window --focus "$w" >/dev/null 2>&1; }

cmd_apply(){ space_resolve "${1:-}" || return 0; state_load
    managed || return 0; renderable || { log "space $sp_index offscreen, deferring"; return 0; }
    lock 2 || return 0; render; unlock; }

# Debounced apply for the noisy window_moved / window_resized signals.
# A drag burst collapses to a single render, and the renders we trigger
# ourselves are dropped because we still hold the lock. apply_frames skips
# windows already in place, so a self-triggered render issues no moves and the
# cascade terminates instead of oscillating.
cmd_nudge(){ local tok="$STATE_DIR/.nudge" me; me="$$-$(date +%s%N)"
    echo "$me" >"$tok"; sleep 0.25
    [ "$(cat "$tok" 2>/dev/null)" = "$me" ] || return 0
    cmd_apply_visible; }

cmd_apply_visible(){ local i
    for i in $("$YABAI" -m query --spaces 2>/dev/null|"$JQ" -r '.[]|select(."is-visible")|.index'); do
        cmd_apply "$i"; done; }

cmd_displays_changed(){ rect_cache_clear; cmd_apply_visible; }

cmd_status(){ local i
    printf '%-6s %-8s %-8s %-7s %s\n' SPACE MANAGED MASTER WIDTH 'LEFT | RIGHT'
    for i in $("$YABAI" -m query --spaces 2>/dev/null|"$JQ" -r '.[].index'); do
        space_resolve "$i" || continue; state_load
        printf '%-6s %-8s %-8s %-7s %s | %s\n' "$i" \
            "$(managed && echo yes || echo no)" "${st_master:--}" "$st_ratio" \
            "${st_left:--}" "${st_right:--}"
    done; }

usage(){ cat <<'EOF'
centered-master.sh -- centered master layout facade over yabai

  center [space]    focused window becomes master; centre the space
  uncenter [space]  release the space back to yabai's bsp
  promote           alias for center
  toggle [space]    centre if released, release if centred
  width +0.05       master width (also -0.05, or an absolute 0.6)
  focus <dir>       west|east|north|south, resolved against the layout
  swap  <dir>       swap the focused window with its neighbour
  apply [space]     re-render (idempotent; used by signals)
  nudge             debounced re-render, for mouse drag/resize signals
  apply-visible     re-render every on-screen space
  displays-changed  drop the cached screen rect, then re-render
  status            per-space model
EOF
}

case "${1:-}" in
    center)           shift; cmd_center "$@" ;;
    uncenter)         shift; cmd_uncenter "$@" ;;
    promote)          shift; cmd_promote "$@" ;;
    toggle)           shift; cmd_toggle "$@" ;;
    width)            shift; cmd_width "$@" ;;
    focus)            shift; cmd_focus "$@" ;;
    swap)             shift; cmd_swap "$@" ;;
    apply)            shift; cmd_apply "$@" ;;
    nudge)            shift; cmd_nudge "$@" ;;
    apply-visible)    shift; cmd_apply_visible "$@" ;;
    displays-changed) shift; cmd_displays_changed "$@" ;;
    status)           shift; cmd_status "$@" ;;
    ''|-h|--help)     usage ;;
    *)                usage; exit 1 ;;
esac
