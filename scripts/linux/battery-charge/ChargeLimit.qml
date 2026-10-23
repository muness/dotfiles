import QtQuick
import Quickshell.Io
import qs.Ui

BarIconButton {
  id: root
  property string moduleName: "muness.battery-charge"
  property var settings: ({})
  property string limit: ""

  // Follow the native indicator drawer's peek, including its hold while the
  // pointer moves across the bar. Travel stays visible like other active toggles.
  readonly property bool indicatorPeek: {
    if (!bar) return false
    var groups = bar.moduleWidgets("omarchy.indicators")
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].revealInactiveIndicators) return true
    }
    return bar.centerSectionRevealHeld === true
  }
  readonly property bool revealed: settings.alwaysShow === true || limit !== "80" || indicatorPeek

  text: "󱈏"
  implicitWidth: revealed ? (vertical ? barSize : slotSize) : 0
  implicitHeight: vertical ? (revealed ? slotSize : 0) : barSize
  clip: true
  concealed: !revealed
  interactive: revealed
  dimmed: limit === "80"

  tooltipText: limit
    ? (limit === "80" ? "Home" : "Travel") + ": charge limit " + limit + "%\nClick to change Home / Travel"
    : "Battery charge limit unavailable"
  onPressed: if (bar) bar.run("omarchy-menu summon battery-charge")

  FileView {
    id: threshold
    path: "/sys/class/power_supply/macsmc-battery/charge_control_end_threshold"
    printErrors: false
    onLoaded: {
      var value = text().trim()
      root.limit = value === "80" || value === "100" ? value : ""
    }
    onLoadFailed: root.limit = ""
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: threshold.reload()
  }
}
