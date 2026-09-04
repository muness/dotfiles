#!/usr/bin/env bash
#
# centered-master.sh - Hyprland/dwm-style centered master layout for yabai.
#
# One designated "master" window is centered at a configurable fraction of the
# usable display width and runs full height. Every other managed window is
# distributed between a left and a right column, vertically tiled.
#
#     +--------+------------------+--------+
#     | left 0 |                  | right0 |
#     +--------+      MASTER      +--------+
#     | left 1 |                  | right1 |
#     +--------+------------------+--------+
#
# The layout is expressed entirely in yabai's *native* BSP tree:
#
#     root (vertical split)
#     |-- left column   (chain of horizontal splits)
#     `-- node (vertical split)
#         |-- MASTER
#         `-- right column (chain of horizontal splits)
#
# so native focus/swap/warp/mouse-resize keep working. When a side column is
# empty the tree cannot express the centering on its own, so the corresponding
# per-space padding is inflated instead. Nothing here needs the yabai
# scripting addition, and it works with SIP enabled.
#
# Enabled per Space, keyed by the Space's stable UUID.
#
# Attribution: the overall approach (yabai signals -> idempotent layout pass,
# a lock to serialise handlers, per-space state, and geometry-based inference
# of which windows are "master") is adapted from Leon Silicon's
# yabai-master-stack-plugin (MIT):
#   https://github.com/leonsilicon/yabai-master-stack-plugin
# That project implements a two-column (left|right) master-stack via a single
# "dividing line" x-coordinate and infers master membership from geometry. The
# centered three-column layout, the BSP tree construction, the ratio/padding
# math and the stable master identity here are new.

set -uo pipefail

YABAI="${YABAI_BIN:-/opt/homebrew/bin/yabai}"
JQ="${JQ_BIN:-/usr/bin/jq}"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/yabai-centered-master"
LOCK_DIR="$STATE_DIR/.lock"
LOG_FILE="$STATE_DIR/log"

DEFAULT_MASTER_WIDTH="${CM_DEFAULT_MASTER_WIDTH:-0.50}"
MIN_MASTER_WIDTH="${CM_MIN_MASTER_WIDTH:-0.20}"
MAX_MASTER_WIDTH="${CM_MAX_MASTER_WIDTH:-0.85}"
WIDTH_STEP="${CM_WIDTH_STEP:-0.05}"
# Pixel tolerance when deciding whether the on-screen layout already matches.
TOL="${CM_TOLERANCE:-6}"
DEBUG="${CM_DEBUG:-0}"

mkdir -p "$STATE_DIR"

log() { [ "$DEBUG" = "1" ] && printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG_FILE"; return 0; }
die() { printf 'centered-master: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Locking (macOS has no flock(1); mkdir is atomic on APFS)
# ---------------------------------------------------------------------------

LOCK_HELD=0
lock_acquire() { # $1 = max seconds to wait (0 = don't wait)
    local waited=0 limit="${1:-0}"
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        # Reap a lock whose owner died.
        local owner
        owner=$(cat "$LOCK_DIR/pid" 2>/dev/null)
        if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
            log "reaping stale lock from pid $owner"
            rm -rf "$LOCK_DIR"
            continue
        fi
        # Belt and braces: a lock older than 15s is stale regardless.
        if [ -d "$LOCK_DIR" ] && [ -z "$(find "$LOCK_DIR" -maxdepth 0 -mtime -15s 2>/dev/null)" ]; then
            log "reaping expired lock"
            rm -rf "$LOCK_DIR"
            continue
        fi
        awk "BEGIN{exit !($waited >= $limit)}" && return 1
        sleep 0.05
        waited=$(awk "BEGIN{print $waited + 0.05}")
    done
    echo $$ >"$LOCK_DIR/pid"
    LOCK_HELD=1
    trap lock_release EXIT INT TERM
    return 0
}
lock_release() { [ "$LOCK_HELD" = "1" ] && rm -rf "$LOCK_DIR"; LOCK_HELD=0; }

# ---------------------------------------------------------------------------
# Per-space state
# ---------------------------------------------------------------------------
# One file per Space UUID:
#     enabled=1
#     master=<window id>
#     mwidth=0.50
#     left=id,id,...
#     right=id,id,...
#     applied_w=<master width in px at last successful apply>

sp_uuid=""; sp_index=""; sp_display=""
st_enabled=0; st_master=""; st_mwidth=""; st_left=""; st_right=""; st_applied_w=""; st_built=""

state_file() { printf '%s/%s.state' "$STATE_DIR" "$1"; }

state_load() {
    local f; f=$(state_file "$sp_uuid")
    st_enabled=0; st_master=""; st_mwidth="$DEFAULT_MASTER_WIDTH"; st_left=""; st_right=""; st_applied_w=""; st_built=""
    [ -f "$f" ] || return 0
    local k v
    while IFS='=' read -r k v; do
        case "$k" in
            enabled)   st_enabled="$v" ;;
            master)    st_master="$v" ;;
            mwidth)    st_mwidth="$v" ;;
            left)      st_left="$v" ;;
            right)     st_right="$v" ;;
            applied_w) st_applied_w="$v" ;;
            built)     st_built="$v" ;;
        esac
    done <"$f"
    return 0
}

state_save() {
    local f; f=$(state_file "$sp_uuid")
    { printf 'enabled=%s\n'   "$st_enabled"
      printf 'master=%s\n'    "$st_master"
      printf 'mwidth=%s\n'    "$st_mwidth"
      printf 'left=%s\n'      "$st_left"
      printf 'right=%s\n'     "$st_right"
      printf 'applied_w=%s\n' "$st_applied_w"
      printf 'built=%s\n'     "$st_built"
    } >"$f.tmp" && mv "$f.tmp" "$f"
}

# ---------------------------------------------------------------------------
# yabai queries
# ---------------------------------------------------------------------------

# Resolve the space to operate on. With no argument, the focused space.
space_resolve() {
    local sel="${1:-}" j
    if [ -n "$sel" ]; then j=$("$YABAI" -m query --spaces --space "$sel" 2>/dev/null)
    else                   j=$("$YABAI" -m query --spaces --space 2>/dev/null); fi
    [ -n "$j" ] || return 1
    sp_uuid=$(printf '%s' "$j" | "$JQ" -r '.uuid')
    sp_index=$(printf '%s' "$j" | "$JQ" -r '.index')
    sp_display=$(printf '%s' "$j" | "$JQ" -r '.display')
    sp_visible=$(printf '%s' "$j" | "$JQ" -r '."is-visible"')
    sp_fullscreen=$(printf '%s' "$j" | "$JQ" -r '."is-native-fullscreen"')
    [ "$sp_uuid" != "null" ] && [ -n "$sp_uuid" ]
}

# Windows yabai is actually tiling on this space, as "id x y w h" lines.
# A window yabai has not placed in the tree reports is-visible=false even on a
# visible space, so that flag is the reliable "is in the BSP tree" test.
tiled_windows() {
    "$YABAI" -m query --windows --space "$sp_index" 2>/dev/null | "$JQ" -r '
        .[] | select(
            (."is-floating" | not) and (."is-minimized" | not) and
            (."is-hidden"   | not) and ."is-visible" and
            (."is-native-fullscreen" | not)
        ) | "\(.id) \(.frame.x) \(.frame.y) \(.frame.w) \(.frame.h)"'
}

win_field() { printf '%s\n' "$2" | awk -v id="$1" -v f="$3" '$1==id{print $f}'; }

display_geom() { # -> "x w"
    "$YABAI" -m query --displays --display "$sp_display" 2>/dev/null \
        | "$JQ" -r '"\(.frame.x) \(.frame.w)"'
}

# Base (un-inflated) padding for this space. We store the user's values the
# first time we touch a space so `disable` can put them back exactly.
base_pad() { # -> "left right"
    local f="$STATE_DIR/$sp_uuid.pad"
    if [ ! -f "$f" ]; then
        printf '%s %s\n' \
            "$("$YABAI" -m config --space "$sp_index" left_padding)" \
            "$("$YABAI" -m config --space "$sp_index" right_padding)" >"$f"
    fi
    cat "$f"
}

space_gap() { "$YABAI" -m config --space "$sp_index" window_gap; }

# ---------------------------------------------------------------------------
# List helpers (comma separated id lists)
# ---------------------------------------------------------------------------

list_has()    { case ",$1," in *",$2,"*) return 0 ;; *) return 1 ;; esac; }
list_add()    { if [ -z "$1" ]; then printf '%s' "$2"; else printf '%s,%s' "$1" "$2"; fi; }
list_prep()   { if [ -z "$1" ]; then printf '%s' "$2"; else printf '%s,%s' "$2" "$1"; fi; }
list_del()    { printf '%s' "$1" | tr ',' '\n' | grep -vx "$2" | paste -sd, -; }
list_count()  { [ -z "$1" ] && { echo 0; return; }; printf '%s' "$1" | tr ',' '\n' | grep -c . ; }

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

# Decide the master and the left/right membership, reconciling stored state
# with what is actually on screen. Sets st_master / st_left / st_right.
reconcile() {
    local wins="$1" ids
    ids=$(printf '%s\n' "$wins" | awk '{print $1}')

    # Drop remembered windows that are gone.
    local nl="" nr="" id
    for id in $(printf '%s' "$st_left" | tr ',' ' '); do
        printf '%s\n' "$ids" | grep -qx "$id" && nl=$(list_add "$nl" "$id")
    done
    for id in $(printf '%s' "$st_right" | tr ',' ' '); do
        printf '%s\n' "$ids" | grep -qx "$id" && nr=$(list_add "$nr" "$id")
    done
    st_left="$nl"; st_right="$nr"

    # Master gone (closed, minimised, moved away)? Promote deterministically:
    # the top of the left column, else the top of the right column, else any.
    if [ -z "$st_master" ] || ! printf '%s\n' "$ids" | grep -qx "$st_master"; then
        local cand=""
        [ -n "$st_left" ]  && cand=$(printf '%s' "$st_left"  | cut -d, -f1)
        [ -z "$cand" ] && [ -n "$st_right" ] && cand=$(printf '%s' "$st_right" | cut -d, -f1)
        [ -z "$cand" ] && cand=$(printf '%s\n' "$ids" | head -1)
        st_master="$cand"
        st_left=$(list_del "$st_left" "$st_master")
        st_right=$(list_del "$st_right" "$st_master")
        log "master reassigned to $st_master"
    fi
    st_left=$(list_del "$st_left" "$st_master")
    st_right=$(list_del "$st_right" "$st_master")

    # If the layout is already settled, believe the screen over our records:
    # a window the user dragged across to the other column keeps its new side.
    # Only trusted while the master itself is where we put it, so that
    # mid-rebuild geometry (or a window pinned by its own minimum size) cannot
    # start a ping-pong.
    if [ -n "$st_applied_w" ]; then
        local mx mw cw
        mx=$(win_field "$st_master" "$1" 2); mw=$(win_field "$st_master" "$1" 4)
        cw="$mw"
        if [ -n "$mx" ] && awk "BEGIN{exit !(($cw-$st_applied_w)^2 <= $TOL^2)}"; then
            local wx ww
            for id in $(printf '%s\n' "$ids"); do
                [ "$id" = "$st_master" ] && continue
                wx=$(win_field "$id" "$1" 2); ww=$(win_field "$id" "$1" 4)
                [ -n "$wx" ] || continue
                if awk "BEGIN{exit !($wx + $ww <= $mx + $TOL)}"; then
                    if list_has "$st_right" "$id"; then
                        st_right=$(list_del "$st_right" "$id"); st_left=$(list_add "$st_left" "$id")
                        log "adopted $id: dragged right -> left"
                    fi
                elif awk "BEGIN{exit !($wx >= $mx + $mw - $TOL)}"; then
                    if list_has "$st_left" "$id"; then
                        st_left=$(list_del "$st_left" "$id"); st_right=$(list_add "$st_right" "$id")
                        log "adopted $id: dragged left -> right"
                    fi
                fi
            done
        fi
    fi

    # Place windows we have never seen on the shorter side (ties go left), in
    # ascending id order so a burst of new windows lands deterministically.
    for id in $(printf '%s\n' "$ids" | sort -n); do
        [ "$id" = "$st_master" ] && continue
        list_has "$st_left" "$id"  && continue
        list_has "$st_right" "$id" && continue
        if [ "$(list_count "$st_left")" -le "$(list_count "$st_right")" ]; then
            st_left=$(list_add "$st_left" "$id")
        else
            st_right=$(list_add "$st_right" "$id")
        fi
    done

    # Rebalance only when the sides differ by 2 or more, so ordinary
    # open/close churn does not shuffle windows the user has placed.
    # Move the bottom-most window across and put it on top of the other column,
    # which keeps both columns' relative order intact.
    while [ $(( $(list_count "$st_left") - $(list_count "$st_right") )) -ge 2 ]; do
        local mv; mv=$(printf '%s' "$st_left" | tr ',' '\n' | tail -1)
        st_left=$(list_del "$st_left" "$mv"); st_right=$(list_prep "$st_right" "$mv")
    done
    while [ $(( $(list_count "$st_right") - $(list_count "$st_left") )) -ge 2 ]; do
        local mv; mv=$(printf '%s' "$st_right" | tr ',' '\n' | tail -1)
        st_right=$(list_del "$st_right" "$mv"); st_left=$(list_prep "$st_left" "$mv")
    done
}

# Order a column top-to-bottom by the windows' current y, so the stored order
# tracks what the user sees (and what they get by dragging windows around).
order_by_y() { # $1 = id list, $2 = window table
    local out id
    out=$(for id in $(printf '%s' "$1" | tr ',' ' '); do
              printf '%s %s\n' "$(win_field "$id" "$2" 3)" "$id"
          done | sort -n -k1,1 -k2,2 | awk '{print $2}' | paste -sd, -)
    printf '%s' "$out"
}

# Is the on-screen geometry already the layout we want?
# Structural only: which column each window is in, master centred and correct
# width, master full height. Heights *within* a column are deliberately not
# checked so the user's own vertical resizing survives.
structure_ok() { # $1 = window table, $2 = target master x, $3 = target master w
    local wins="$1" tx="$2" tw="$3" id mx mw
    mx=$(win_field "$st_master" "$wins" 2); mw=$(win_field "$st_master" "$wins" 4)
    [ -n "$mx" ] || return 1
    awk "BEGIN{exit !(($mx-$tx)^2 <= $TOL^2 && ($mw-$tw)^2 <= $TOL^2)}" || return 1
    for id in $(printf '%s' "$st_left" | tr ',' ' '); do
        local x w; x=$(win_field "$id" "$wins" 2); w=$(win_field "$id" "$wins" 4)
        awk "BEGIN{exit !($x + $w <= $tx + $TOL)}" || return 1
    done
    for id in $(printf '%s' "$st_right" | tr ',' ' '); do
        local x; x=$(win_field "$id" "$wins" 2)
        awk "BEGIN{exit !($x >= $tx + $tw - $TOL)}" || return 1
    done
    return 0
}

# Rebuild the BSP tree into the target shape using native warps.
#
#   root (vertical)
#   |-- left0 ... (horizontal chain)
#   `-- (vertical)
#       |-- MASTER
#       `-- right0 ... (horizontal chain)
#
# `yabai -m window A --warp B` re-inserts A by splitting B. The axis comes from
# the *space's* split_type and the side from the global window_placement, so we
# drive both explicitly. (`window --insert` would be the obvious tool, but it is
# a toggle whose state is not exposed by `query`, so it cannot be set reliably.)
build_tree() {
    local L R first prev id side placement
    L=$(printf '%s' "$st_left"  | tr ',' ' ')
    R=$(printf '%s' "$st_right" | tr ',' ' ')

    placement=$("$YABAI" -m config window_placement)
    [ "$placement" = "second_child" ] || \
        "$YABAI" -m config window_placement second_child >/dev/null 2>&1

    # 1. Left/right skeleton around the master.
    "$YABAI" -m config --space "$sp_index" split_type vertical >/dev/null 2>&1
    set -- $L
    [ $# -gt 0 ] && "$YABAI" -m window "$st_master" --warp "$1" >/dev/null 2>&1
    set -- $R
    [ $# -gt 0 ] && "$YABAI" -m window "$1" --warp "$st_master" >/dev/null 2>&1

    # 2. Grow each column downwards.
    "$YABAI" -m config --space "$sp_index" split_type horizontal >/dev/null 2>&1
    for side in "$L" "$R"; do
        prev=""; first=1
        for id in $side; do
            if [ "$first" = 1 ]; then prev="$id"; first=0; continue; fi
            "$YABAI" -m window "$id" --warp "$prev" >/dev/null 2>&1
            prev="$id"
        done
    done

    [ "$placement" = "second_child" ] || \
        "$YABAI" -m config window_placement "$placement" >/dev/null 2>&1
}

# The one real layout pass. Idempotent.
apply_layout() { # $1 = "adopt" to learn a new master width from a mouse resize
    local adopt="${1:-}"
    local wins n
    wins=$(tiled_windows)
    n=$(printf '%s\n' "$wins" | grep -c .)

    local bp pl pr gap dx dw
    bp=$(base_pad); pl=${bp% *}; pr=${bp#* }
    gap=$(space_gap)
    read -r dx dw <<<"$(display_geom)"

    if [ "$n" -eq 0 ]; then
        "$YABAI" -m config --space "$sp_index" left_padding  "$pl" >/dev/null 2>&1
        "$YABAI" -m config --space "$sp_index" right_padding "$pr" >/dev/null 2>&1
        st_master=""; st_left=""; st_right=""; st_built=""; state_save
        return 0
    fi

    reconcile "$wins"
    st_left=$(order_by_y "$st_left" "$wins")
    st_right=$(order_by_y "$st_right" "$wins")

    # A deliberate mouse resize of the master changes its width away from the
    # width we last applied; adopt that as the new master fraction. Our own
    # operations leave the width exactly where we put it, so the events they
    # generate never trigger this.
    local uw cur_mw
    uw=$(awk "BEGIN{print $dw - $pl - $pr}")
    if [ "$adopt" = "adopt" ] && [ -n "$st_applied_w" ]; then
        cur_mw=$(win_field "$st_master" "$wins" 4)
        if [ -n "$cur_mw" ] && awk "BEGIN{exit !(($cur_mw-$st_applied_w)^2 > $TOL^2)}"; then
            st_mwidth=$(awk "BEGIN{v=$cur_mw/$uw;
                if(v<$MIN_MASTER_WIDTH)v=$MIN_MASTER_WIDTH;
                if(v>$MAX_MASTER_WIDTH)v=$MAX_MASTER_WIDTH; printf \"%.4f\", v}")
            log "adopted master width $st_mwidth from resize (${cur_mw}px)"
        fi
    fi

    local nl nr master_w master_x npl npr
    nl=$(list_count "$st_left"); nr=$(list_count "$st_right")

    # Target geometry: master centred on the display, master_w of the usable
    # width. A column with no windows is replaced by inflated padding.
    master_w=$(awk "BEGIN{printf \"%d\", $st_mwidth * $uw + 0.5}")
    master_x=$(awk "BEGIN{printf \"%d\", $dx + $dw/2 - $master_w/2 + 0.5}")
    if [ "$nl" -gt 0 ]; then npl="$pl"; else npl=$(awk "BEGIN{printf \"%d\", $master_x - $dx}"); fi
    if [ "$nr" -gt 0 ]; then npr="$pr"; else npr=$(awk "BEGIN{printf \"%d\", $dx + $dw - $master_x - $master_w}"); fi

    "$YABAI" -m config --space "$sp_index" left_padding  "$npl" >/dev/null 2>&1
    "$YABAI" -m config --space "$sp_index" right_padding "$npr" >/dev/null 2>&1
    # auto_balance would immediately undo our ratios; it is a *space* setting,
    # so other spaces keep the user's global value.
    "$YABAI" -m config --space "$sp_index" auto_balance off      >/dev/null 2>&1

    # Only touch the tree when the structure is actually wrong; otherwise the
    # user's own vertical resizing inside a column is preserved.
    # Rebuild only when the structure is wrong *and* the membership actually
    # changed since the last rebuild. Without that second test, a window whose
    # own minimum size stops it fitting its column would make every single
    # event rebuild the whole space.
    wins=$(tiled_windows)
    local fp="$st_master|$st_left|$st_right"
    if ! structure_ok "$wins" "$master_x" "$master_w" && [ "$fp" != "$st_built" ]; then
        log "rebuilding tree on space $sp_index (L=$st_left M=$st_master R=$st_right)"
        build_tree
        st_built="$fp"
        # Equal heights within each column. yabai's "x-axis" balance is the one
        # that equalises top/bottom divisions; it also resets the left/right
        # ratios, which is why the horizontal fix-up comes after.
        "$YABAI" -m space "$sp_index" --balance x-axis >/dev/null 2>&1
        wins=$(tiled_windows)
    fi

    # Horizontal placement: nudge the master's own edges. --resize walks up to
    # whichever divider owns that edge, so this works at any tree depth, and is
    # a no-op on an outer edge (where the inflated padding is doing the work).
    local cx cw i
    for i in 1 2 3 4; do
        cx=$(win_field "$st_master" "$wins" 2); cw=$(win_field "$st_master" "$wins" 4)
        [ -n "$cx" ] || break
        local dl dr
        dl=$(awk "BEGIN{printf \"%d\", $master_x - $cx}")
        dr=$(awk "BEGIN{printf \"%d\", ($master_x + $master_w) - ($cx + $cw)}")
        [ "$dl" -eq 0 ] && [ "$dr" -eq 0 ] && break
        [ "$dl" -ne 0 ] && "$YABAI" -m window "$st_master" --resize "left:$dl:0"  >/dev/null 2>&1
        [ "$dr" -ne 0 ] && "$YABAI" -m window "$st_master" --resize "right:$dr:0" >/dev/null 2>&1
        wins=$(tiled_windows)
    done

    st_applied_w=$(win_field "$st_master" "$wins" 4)
    state_save
}

# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

run_layout() { # $1 = space selector or "", $2 = "adopt"|""
    space_resolve "${1:-}" || return 0
    state_load
    [ "$st_enabled" = "1" ] || return 0
    # yabai silently ignores frame changes on a Space that is not on screen,
    # so defer; the space_changed signal reflows it when it comes forward.
    [ "$sp_visible" = "true" ] || { log "space $sp_index not visible, deferring"; return 0; }
    [ "$sp_fullscreen" = "true" ] && return 0
    apply_layout "${2:-}"
}

cmd_reflow() { lock_acquire 3 || { log "reflow: busy"; return 0; }; run_layout "${1:-}" ""; lock_release; }

# Debounced path for the noisy window_moved / window_resized signals. A burst
# collapses to one pass, and events generated by our own operations are
# dropped because we still hold the lock.
cmd_nudge() {
    local token="$STATE_DIR/.nudge"
    local me; me=$(date +%s%N)
    echo "$me" >"$token"
    sleep 0.25
    [ "$(cat "$token" 2>/dev/null)" = "$me" ] || return 0
    lock_acquire 0 || { log "nudge: busy"; return 0; }
    run_layout "" "adopt"
    lock_release
}

cmd_reflow_visible() {
    lock_acquire 3 || return 0
    local idx
    for idx in $("$YABAI" -m query --spaces | "$JQ" -r '.[]|select(."is-visible")|.index'); do
        run_layout "$idx" ""
    done
    lock_release
}

cmd_enable() {
    space_resolve "${1:-}" || die "no such space"
    state_load
    base_pad >/dev/null            # remember the user's padding before we touch it
    st_enabled=1
    [ -n "$st_mwidth" ] || st_mwidth="$DEFAULT_MASTER_WIDTH"
    # Seed the master from the focused window if we have no opinion yet.
    if [ -z "$st_master" ]; then
        st_master=$("$YABAI" -m query --windows --window 2>/dev/null | "$JQ" -r '.id // empty')
    fi
    "$YABAI" -m space "$sp_index" --layout bsp >/dev/null 2>&1
    state_save
    cmd_reflow "$sp_index"
    printf 'centered-master: enabled on space %s\n' "$sp_index"
}

cmd_disable() {
    space_resolve "${1:-}" || die "no such space"
    state_load
    st_enabled=0; state_save
    local bp pl pr
    bp=$(base_pad); pl=${bp% *}; pr=${bp#* }
    "$YABAI" -m config --space "$sp_index" left_padding  "$pl" >/dev/null 2>&1
    "$YABAI" -m config --space "$sp_index" right_padding "$pr" >/dev/null 2>&1
    "$YABAI" -m config --space "$sp_index" auto_balance \
        "$("$YABAI" -m config auto_balance)" >/dev/null 2>&1
    "$YABAI" -m config --space "$sp_index" split_type \
        "$("$YABAI" -m config split_type)" >/dev/null 2>&1
    "$YABAI" -m space "$sp_index" --balance >/dev/null 2>&1
    printf 'centered-master: disabled on space %s (padding restored, layout balanced)\n' "$sp_index"
}

cmd_toggle() {
    space_resolve "${1:-}" || die "no such space"
    state_load
    if [ "$st_enabled" = "1" ]; then cmd_disable "$sp_index"; else cmd_enable "$sp_index"; fi
}

cmd_promote() {
    space_resolve "" || die "no space"
    state_load
    [ "$st_enabled" = "1" ] || die "centered-master is not enabled on space $sp_index"
    local w; w=$("$YABAI" -m query --windows --window 2>/dev/null | "$JQ" -r '.id // empty')
    [ -n "$w" ] || die "no focused window"
    [ "$w" = "$st_master" ] && return 0
    lock_acquire 3 || return 0
    # The outgoing master takes the promoted window's place in its column, so
    # the columns keep their shape.
    local side="" pos=""
    if list_has "$st_left" "$w"; then side=left
    elif list_has "$st_right" "$w"; then side=right; fi
    case "$side" in
        left)  st_left=$(printf '%s' "$st_left" | sed "s/\b$w\b/$st_master/") ;;
        right) st_right=$(printf '%s' "$st_right" | sed "s/\b$w\b/$st_master/") ;;
        *)     if [ "$(list_count "$st_left")" -le "$(list_count "$st_right")" ]
               then st_left=$(list_add "$st_left" "$st_master")
               else st_right=$(list_add "$st_right" "$st_master"); fi ;;
    esac
    st_master="$w"; state_save
    run_layout "$sp_index" ""
    lock_release
}

cmd_width() { # +0.05 | -0.05 | 0.5
    space_resolve "" || die "no space"
    state_load
    [ "$st_enabled" = "1" ] || die "centered-master is not enabled on space $sp_index"
    local arg="${1:?usage: width +0.05|-0.05|<fraction>}"
    case "$arg" in
        +*|-*) st_mwidth=$(awk "BEGIN{printf \"%.4f\", $st_mwidth + ($arg)}") ;;
        *)     st_mwidth=$(awk "BEGIN{printf \"%.4f\", $arg}") ;;
    esac
    st_mwidth=$(awk "BEGIN{v=$st_mwidth;
        if(v<$MIN_MASTER_WIDTH)v=$MIN_MASTER_WIDTH;
        if(v>$MAX_MASTER_WIDTH)v=$MAX_MASTER_WIDTH; printf \"%.4f\", v}")
    state_save
    cmd_reflow "$sp_index"
}

# Throw away the remembered columns and lay the space out from scratch.
cmd_repair() {
    space_resolve "${1:-}" || die "no space"
    state_load
    [ "$st_enabled" = "1" ] || die "centered-master is not enabled on space $sp_index"
    lock_acquire 3 || return 0
    st_left=""; st_right=""; st_applied_w=""; st_built=""; state_save
    "$YABAI" -m space "$sp_index" --layout bsp >/dev/null 2>&1
    run_layout "$sp_index" ""
    lock_release
    printf 'centered-master: repaired space %s\n' "$sp_index"
}

cmd_status() {
    local idx
    printf '%-6s %-38s %-8s %-8s %-8s %s\n' SPACE UUID ENABLED MASTER WIDTH 'LEFT | RIGHT'
    for idx in $("$YABAI" -m query --spaces | "$JQ" -r '.[].index'); do
        space_resolve "$idx" >/dev/null || continue
        state_load
        printf '%-6s %-38s %-8s %-8s %-8s %s | %s\n' \
            "$idx" "$sp_uuid" "${st_enabled:-0}" "${st_master:--}" "${st_mwidth:--}" \
            "${st_left:--}" "${st_right:--}"
    done
}

usage() {
    cat <<'EOF'
centered-master.sh -- centered master layout for yabai

  enable  [space]   turn the layout on for a space (default: focused)
  disable [space]   turn it off, restore padding, re-balance the space
  toggle  [space]   flip it
  promote           make the focused window the master
  width  +0.05      change master width (also: -0.05, or an absolute 0.6)
  repair  [space]   forget remembered columns and rebuild from scratch
  reflow  [space]   re-apply the layout (idempotent)
  nudge             debounced reflow; also learns a mouse-resized master width
  reflow-visible    reflow every on-screen space (used by signals)
  status            show per-space state
EOF
}

case "${1:-}" in
    enable)         shift; cmd_enable "$@" ;;
    disable)        shift; cmd_disable "$@" ;;
    toggle)         shift; cmd_toggle "$@" ;;
    promote)        shift; cmd_promote "$@" ;;
    width)          shift; cmd_width "$@" ;;
    repair)         shift; cmd_repair "$@" ;;
    reflow)         shift; cmd_reflow "$@" ;;
    nudge)          shift; cmd_nudge "$@" ;;
    reflow-visible) shift; cmd_reflow_visible "$@" ;;
    status)         shift; cmd_status "$@" ;;
    ''|-h|--help)   usage ;;
    *)              usage; exit 1 ;;
esac
