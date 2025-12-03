#!/bin/bash

source "$CONFIG_DIR/colors.sh"

ITEM_NAME="yabai_layout"

current_layout() {
  yabai -m query --spaces --space | jq -r '.type'
}

cycle_layout() {
  case "$(current_layout)" in
    bsp)
      yabai -m space --layout float
      ;;
    float)
      yabai -m space --layout bsp
      ;;
    stack)
      yabai -m space --layout bsp
      ;;
    *)
      yabai -m space --layout bsp
      ;;
  esac
}

set_view() {
  layout=$(current_layout)

  case "$layout" in
    bsp)
      icon="􀯹"
      label="BSP"
      ;;
    stack)
      icon="􀧍"
      label="STACK"
      ;;
    float)
      icon="􀢙"
      label="FLOAT"
      ;;
    *)
      icon="??"
      label="UNKNOWN"
      ;;
  esac

  sketchybar --set "$ITEM_NAME" icon="$icon" label="$label" \
    icon.color=$ITEM_COLOR \
    label.color=$ITEM_COLOR \
    background.color=$ACCENT_COLOR \
    background.drawing=on
}

if [ "$SENDER" = "mouse.clicked" ]; then
  cycle_layout
fi

set_view
