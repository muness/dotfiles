#!/usr/bin/env sh

# Toggle sketchybar visibility and adjust yabai space reservation

HIDDEN=$(sketchybar --query bar | jq -r '.hidden')

if [ "$HIDDEN" = "off" ]; then
    # Bar is visible - hide it
    sketchybar --bar hidden=on
    yabai -m config external_bar all:0:0
else
    # Bar is hidden - show it
    sketchybar --bar hidden=off
    yabai -m config external_bar all:37:0
fi
