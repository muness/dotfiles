# Centered master layout for yabai

```
+--------+------------------+--------+
| left 0 |                  | right0 |
+--------+      MASTER      +--------+
| left 1 |                  | right1 |
+--------+------------------+--------+
```

One master window centred on screen at a configurable fraction of the usable
width, full height. Everything else is distributed between a left and a right
column. The side columns keep their width even when empty, so the master stays
centred at one and two windows.

## It is a facade, not a BSP plugin

This does **not** manipulate yabai's BSP tree. It owns the layout model — a
master plus two ordered columns — and renders it by setting absolute frames, the
way dwm and Hyprland compute layout as a pure function of the window list.
yabai is demoted to two roles: event source, and the thing that decides which
windows are worth managing.

An earlier version did try to drive the tree, and could not be made reliable:

* `window --warp <id>` is documented as "re-insert the selected window,
  splitting the given window", but in practice reorders at the target's level
  rather than splitting the target leaf. Results depend on the tree you started
  from.
* `window --insert <dir>` is a toggle, and its state is not exposed by
  `query`, so it cannot be set deterministically from outside the process.

Owning the model removes both problems, at the cost described under
*Trade-offs*.

## Keys

| Key | Action |
| --- | --- |
| `⌥ ↩` | centre this Space, or release it if already centred |
| `⌥ ⇧ ↩` | promote the focused window to master |
| `⌥ ⌘ l` / `⌥ ⌘ h` | widen / narrow the master by 5% |
| `⌥ ⌘ 0` | reset master to 50% |
| `⌥ ⇧ r` | re-render, if something has drifted |
| `⌥ h/j/k/l` | focus — resolved against the layout on a managed Space |
| `⌥ ⇧ h/j/k/l` | swap the focused window with that neighbour |

Focusing never promotes. Only `⌥ ⇧ ↩` changes the master.

`toggle` deliberately ignores which window is focused: if the Space is centred
it is released, full stop. That way a mis-aimed toggle can never silently
reshuffle the layout when you meant to switch it off.

Note that `yabai -m space --layout bsp` will **not** get you out. Managed
windows are floating, so they are not in the tree and no layout setting
reaches them; `toggle` / `uncenter` is the only way back, because it is the
only thing that knows which windows it floated.

The `⌥ hjkl` cluster routes through this script and falls through to plain
yabai (including the display hop) on any Space that is not managed, so
unmanaged Spaces behave exactly as they always did.

## CLI

```
~/.config/yabai/centered-master.sh status
~/.config/yabai/centered-master.sh toggle   [space]
~/.config/yabai/centered-master.sh center   [space]
~/.config/yabai/centered-master.sh uncenter [space]
~/.config/yabai/centered-master.sh width 0.6
~/.config/yabai/centered-master.sh focus west
~/.config/yabai/centered-master.sh apply    [space]
```

`CM_DEBUG=1` writes a trace to `~/.local/state/yabai-centered-master/log`.

## Trade-offs

Managed windows are floating, so yabai's own tree operations no longer apply to
them. What that costs, and what replaces it:

| Lost | Replacement |
| --- | --- |
| tree-based directional focus | resolved against the model (`focus <dir>`) |
| `--swap` / `--warp` | `swap <dir>`, which exchanges slots in the model |
| mouse drag-to-swap | none — the window is snapped back on the next render |
| divider drag-resize | none — use `width` for the master; column heights are fixed equal |

## Known limits

* **Off-screen Spaces cannot be rendered.** macOS will not let yabai move a
  window on a Space that is not on screen without the scripting addition; the
  calls return success and do nothing. Rendering is therefore deferred, and the
  `space_changed` signal re-renders a Space when it comes forward.
* **Apps with a large minimum window size overflow their column.** On a 2087px
  display at 50% master the side columns are ~506px, and e.g. Claude refuses to
  go below 600px wide. Lower the master width, or keep such apps out.
* **A window that is already floating when you run `center` is left alone**, on
  the assumption you floated it deliberately or a `manage=off` rule did. That
  is how `yabairc` rules keep working without this script knowing about them.
* **Minimise and restore loses the slot.** A restored window is re-adopted into
  whichever column is shorter, not the one it left.
* Requires `yabai`, `jq`, `bash`, `osascript`. No scripting addition; SIP can
  stay enabled.

## State

`~/.local/state/yabai-centered-master/<space-uuid>.state`, keyed by the Space's
stable UUID. A Space is managed iff that file gives it a master; there is no
separate enable flag.

The usable screen rect (menubar and Dock aware) comes from AppKit's
`NSScreen.visibleFrame` via `osascript`, since yabai only reports the raw
display frame. It is cached per display and dropped on any display event.

## Rollback

```sh
~/dotfiles/yabai/.config/yabai/centered-master-uninstall.sh
```

Releases every managed Space, removes the `cm_*` signals, and deletes the state
directory. To remove the config lines too, restore from
`~/dotfiles/.backups/<timestamp>/`.
