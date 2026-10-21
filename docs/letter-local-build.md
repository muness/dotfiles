# Letter local trial — 2026-10-21

Built Letter 1.7.0 from https://github.com/stalvatero/letter at commit `4198c07fe22587d4c6f0dc394821fc6f6d8b0c83` on aarch64. Source: `~/.local/src/letter`; installation prefix: `~/.local`. No upstream source modifications were needed.

Added official repository dependencies: meson, vala, webkitgtk-6.0, gsound, libedataserverui4, blueprint-compiler (and their dependencies). Existing Evolution/GOA libraries were retained.

Rebuild/update deliberately from the source checkout:

```sh
/usr/bin/meson setup _build --prefix="$HOME/.local" -Dprofile=default
/usr/bin/meson compile -C _build -j 4
/usr/bin/meson test -C _build --print-errorlogs
/usr/bin/meson install -C _build
```

All 11 upstream tests passed, with the remote-content test rerun using `GTK_A11Y=none` because the current session advertises an inaccessible AT-SPI bus. This workaround was limited to that test; the installed app launches normally (with accessibility warnings in this session).

Launched using `systemd-run --user --unit=letter-trial --collect ~/.local/bin/letter`. Desktop entry is `~/.local/share/applications/io.github.stalvatero.Letter.desktop`. App visibly discovered four existing accounts (two Google, two Microsoft 365) and populated Microsoft 365 folders/messages without account reconfiguration. Initial cache population continues in the background. No send/archive/delete actions were tested or performed.

For the trial, `mark-as-read` is `never` in both `io.github.stalvatero.Letter` and legacy `io.github.stalvatero.Mail` GSettings schemas. Adjust this in Letter preferences if desired. Default mailto handler remains Evolution; calendar reminder service and account configuration were not changed. Letter stores its own mail data/cache under `~/.local/share/letter` and `~/.cache/letter`.

To remove installed files, use the build's `meson-logs/install-log.txt` as the manifest; preserve shared schema caches/icons directories and personal mail data. Do not run an unreviewed purge script. Source and install manifest remain available for rollback.
