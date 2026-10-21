Upstream: https://github.com/ChaseC-130/amphetamine
Pinned commit: 3760f0e7bebfef8df7680f88d43f6d1881a1c527

Local compatibility patches: UPower lid presence and logind lid state for Apple Silicon; Hyprland Lua DPMS enable/disable values; ThemeColor singleton for this Qt 6.12 shell build. Upstream license retained. No global lid policy changes.

The widget starts inactive. A user service stops Amphetamine when graphical-session.target stops. Timed expiration and explicit off are tested without physically closing the lid. Actual closed-lid panel-off and resume remain hardware checks.

Reproduce installation with `./install-local.sh` from this directory (requires Omarchy session PATH). Existing installations are refused to preserve local edits. CLI is linked at ~/.local/bin/amphetamine.

Verified live: hardware capability detection, QML popup rendering, six-second timer expiration removing the sleep/idle/lid inhibitor, and stopping the cleanup service ending a 30-second session. Left inactive. No physical suspend or lid-close test was performed.
