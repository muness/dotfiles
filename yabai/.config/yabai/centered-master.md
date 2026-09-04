# Centered master layout for yabai

Hyprland/dwm-style centered master, opt-in per Space, implemented on top of
yabai's native BSP tree.

```
+--------+------------------+--------+
| left 0 |                  | right0 |
+--------+      MASTER      +--------+
| left 1 |                  | right1 |
+--------+------------------+--------+
```

One designated master window is centred on the display at a configurable
fraction of the usable width (default 50%) and runs full height. Every other
managed window goes into a left or a right column, vertically tiled.

## Keys

| Key | Action |
| --- | --- |
| `alt + shift - c` | toggle the layout on/off for the current Space |
| `alt - return` | promote the focused window to master |
| `alt + cmd - l` / `alt + cmd - h` | widen / narrow the master by 5% |
| `alt + cmd - 0` | reset the master to 50% |
| `alt + shift - r` | repair: forget the remembered columns, rebuild |

Focusing a window never promotes it. Only `alt - return` does.

## CLI

```
~/.config/yabai/centered-master.sh status          # per-space state
~/.config/yabai/centered-master.sh enable  [space]
~/.config/yabai/centered-master.sh disable [space]
~/.config/yabai/centered-master.sh width 0.6
~/.config/yabai/centered-master.sh reflow  [space] # idempotent re-apply
~/.config/yabai/centered-master.sh repair  [space]
```

`CM_DEBUG=1` writes a trace to
`~/.local/state/yabai-centered-master/log`.

## How it works

The layout is a plain BSP tree, so native focus, `--swap`, `--warp` and mouse
resizing keep working:

```
root (vertical split)
|-- left column   (chain of horizontal splits)
`-- node (vertical split)
    |-- MASTER
    `-- right column (chain of horizontal splits)
```

Two things cannot be expressed by the tree alone:

* **An empty side column.** With only one or two windows there is no node to
  hold the empty side, so the per-Space `left_padding` / `right_padding` is
  inflated instead. The master stays centred and the unused side is blank.
* **`auto_balance`.** It would immediately flatten the ratios, so it is turned
  off *for opted-in Spaces only* (it is a Space setting, not a global one).
  Your other Spaces keep the global `auto_balance on` from `yabairc`.

Horizontal placement is applied with `yabai -m window <master> --resize
left:dx:0` / `right:dx:0`, which walks up to whichever divider owns that edge
and therefore works at any depth in the tree.

State lives in `~/.local/state/yabai-centered-master/<space-uuid>.state`, keyed
by the Space's stable UUID, so it survives Spaces being reordered.

## Requirements

`yabai`, `jq`, and `bash`. **No scripting addition and no SIP change** — every
command used (`--warp`, `--insert`, `--resize`, `--ratio`, `space --padding`,
`config --space`, `signal`) works with SIP enabled.

## Rollback

```sh
~/dotfiles/yabai/.config/yabai/centered-master-uninstall.sh
```

That removes the `cm_*` signals, restores padding and `auto_balance` on every
opted-in Space, and deletes the state directory. To also remove the config
lines, restore from `~/dotfiles/.backups/<timestamp>/`.
