# Linux application installation and updates

`vendor-apps.sh` is the public entry point for manually managed desktop apps.
Add new apps to its default selection, installation backend and read-only check;
route bootstrap and scheduled updates through that entry point. Keep root
installation interactive through polkit; scheduled runs check root-managed apps
and update only installed user-managed apps via `--user-only`.

Resolve current upstream releases on each run. Do not hardcode application
versions or source revisions. Document any required hardware/source pin and its
update path in `docs/linux-app-updates.md`. System package managers, Flatpak,
mise and the shared cross-platform CLI bootstrap retain their own package lists.
