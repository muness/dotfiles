#!/bin/bash

sketchybar --add item yabai_layout left \
  --set yabai_layout script="$PLUGIN_DIR/yabai_layout.sh" \
  label.font="$LABEL_FONT" \
  icon.font="$ICON_FONT" \
  padding_left=10 \
  padding_right=12 \
  label.padding_left=6 \
  label.padding_right=8 \
  label.y_offset=-1 \
  background.corner_radius=8 \
  --subscribe yabai_layout space_change mouse.clicked

$PLUGIN_DIR/yabai_layout.sh
