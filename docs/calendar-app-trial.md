# Calendar frontend trial — 2026-10-21

Installed native GNOME Calendar 51.0-1 (aarch64) and user Flatpak Era 0.2.0 (`org.gnome.gitlab.TitouanReal.Era`, GNOME Platform 51). Both opened in Omarchy. GNOME Calendar displayed existing events; Era discovered the existing shared EDS calendar list. No event edits, account reconfiguration, or calendar selection changes were performed. Live EDS selection was checked before/after: 19 calendars, six selected, unchanged. Default text/calendar handler remains Evolution. The reminder overlay keeps its existing backend and configuration.

Launch `gnome-calendar` or `flatpak run --user org.gnome.gitlab.TitouanReal.Era`, or use Calendar / Era in the app menu. Era emits a large volume of debug/performance logging in this build. The session also has a stale accessibility-bus address affecting GTK apps; this was observed before either calendar was installed. These do not establish support for all event-editing, invitation, or recurring-event flows; those have not been exercised.

Letter is now the default for mailto, message/rfc822, and application/eml. Omarchy user bindings SUPER+SHIFT+E open Letter; SUPER+SHIFT+ALT+E opens a new mailto compose request. The prior MIME and bindings files were backed up in ~/.config before changes.
