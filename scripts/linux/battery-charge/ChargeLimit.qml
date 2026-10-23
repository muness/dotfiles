import QtQuick
import Quickshell.Io
import qs.Ui

WidgetButton {
  id: root
  property string moduleName: "muness.battery-charge"
  property var settings: ({})
  property string limit: ""

  text: limit ? (vertical ? limit : limit + "% cap") : "Cap ?"
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
