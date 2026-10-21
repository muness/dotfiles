import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon plus the dropdown behind it: a macOS-Amphetamine-shaped menu that
// starts a session at any of the durations this machine offers, and exposes
// the two lid preferences that actually change what happens when you shut the
// laptop. Everything it shows comes from the CLI — `capabilities` describes
// the hardware, `state.json` describes the running session — so the panel
// never guesses at what the machine can do.
Panel {
  id: root
  moduleName: "chase.amphetamine"
  ipcTarget: "amphetamine"

  readonly property string binPath: Qt.resolvedUrl("bin/amphetamine").toString().replace(/^file:\/\//, "")
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/amphetamine/state.json"
  readonly property string configPath: Quickshell.env("HOME") + "/.local/state/amphetamine/config.json"

  // Panel content is drawn in the bar's content color, not the bar-strip color
  // the icon uses, so a transparent bar does not wash out the popup.
  readonly property color fg: bar ? bar.foreground : ThemeColor.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showRemaining: setting("showRemaining", false) === true

  // ---- session state, tailed from the file the CLI owns --------------------
  property bool sessionActive: false
  property string sessionMode: "off"
  property string sessionLabel: "Off"
  property string sessionTitle: "Off"
  property double expiresAt: 0
  property int remainingSec: 0

  // ---- machine capabilities, refreshed whenever the panel opens -----------
  property var caps: ({})
  property var presets: []
  readonly property bool lidPresent: caps.lidPresent === true
  readonly property bool canPowerOffDisplay: caps.canPowerOffDisplay === true
  readonly property bool lidControlAvailable: lidPresent && canPowerOffDisplay
  readonly property string internalDisplay: caps.internalDisplay || ""
  readonly property var externalDisplays: caps.externalDisplays || []
  readonly property string lidState: caps.lidState || "absent"

  // ---- preferences, tailed from config.json ------------------------------
  property bool displayOffOnLidClose: true
  property bool keepDisplayAwake: true

  // ---- keyboard cursor ---------------------------------------------------
  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property int presetColumns: 3
  readonly property int presetStart: 1
  readonly property int presetCount: presets.length
  readonly property int toggleStart: presetStart + presetCount
  readonly property int toggleCount: (lidControlAvailable ? 1 : 0) + 1
  readonly property int cursorCount: presetStart + presetCount + toggleCount

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ------------------------------------------------------------------ text

  function formatRemaining(seconds) {
    if (seconds <= 0) return "0m"
    var mins = Math.ceil(seconds / 60)
    if (mins < 60) return mins + "m"
    var h = Math.floor(mins / 60)
    var m = mins % 60
    return m > 0 ? h + "h " + m + "m" : h + "h"
  }

  function statusLine() {
    if (!sessionActive) return "Sleeping normally"
    if (sessionMode === "timer") return formatRemaining(remainingSec) + " remaining"
    return "Awake indefinitely"
  }

  function tooltip() {
    if (!sessionActive) return "Amphetamine — off\nClick for durations · right-click to keep awake"
    var head = sessionMode === "timer"
      ? "Amphetamine — " + sessionTitle + " session, " + formatRemaining(remainingSec) + " remaining"
      : "Amphetamine — awake indefinitely"
    if (lidControlAvailable && displayOffOnLidClose)
      head += "\nScreen powers down when you close the lid"
    return head + "\nClick for durations · right-click to stop"
  }

  // ---------------------------------------------------------------- reading

  function loadState(raw) {
    try {
      var data = JSON.parse(raw)
      sessionActive = !!data.active
      sessionMode = data.mode || "off"
      sessionLabel = data.label || "Off"
      sessionTitle = data.title || data.label || "Off"
      expiresAt = Number(data.expiresAt) || 0
      tick()
    } catch (e) {
      clearState()
    }
  }

  function clearState() {
    sessionActive = false
    sessionMode = "off"
    sessionLabel = "Off"
    sessionTitle = "Off"
    expiresAt = 0
    remainingSec = 0
  }

  function loadConfig(raw) {
    try {
      var data = JSON.parse(raw)
      if (data.displayOffOnLidClose !== undefined) displayOffOnLidClose = !!data.displayOffOnLidClose
      if (data.keepDisplayAwake !== undefined) keepDisplayAwake = !!data.keepDisplayAwake
    } catch (e) {
      // A half-written config is transient; keep showing the last good values.
    }
  }

  function loadCapabilities(raw) {
    try {
      var data = JSON.parse(raw)
      caps = data
      presets = (data.presets || []).filter(function (p) { return p.seconds > 0 })
      if (cursorIndex >= cursorCount) cursorIndex = 0
    } catch (e) {
      // Leave the previous snapshot in place rather than emptying the menu.
    }
  }

  function tick() {
    if (sessionActive && sessionMode === "timer" && expiresAt > 0) {
      remainingSec = Math.max(0, expiresAt - Math.floor(Date.now() / 1000))
    } else {
      remainingSec = 0
    }
  }

  // --------------------------------------------------------------- commands

  function runCommand(proc, args) {
    if (proc.running) return
    proc.command = [root.binPath].concat(args)
    proc.running = true
  }

  function startSession(duration) { runCommand(actionProc, ["on", duration]) }
  function stopSession() { runCommand(actionProc, ["off"]) }
  function toggleSession() { sessionActive ? stopSession() : startSession("indefinite") }
  function setConfig(key, value) { runCommand(configProc, ["config", "set", key, String(value)]) }
  function refreshCapabilities() { if (!capsProc.running) capsProc.running = true }

  // --------------------------------------------------------------- keyboard

  function moveCursor(dx, dy) {
    if (cursorCount === 0) return
    if (!cursorActive) { cursorActive = true; return }

    var i = cursorIndex
    // Inside the preset grid a vertical move should skip a whole row; falling
    // off either edge hands the cursor to the section above or below.
    if (dy !== 0 && i >= presetStart && i < presetStart + presetCount) {
      var next = i + dy * presetColumns
      if (next >= presetStart && next < presetStart + presetCount) { cursorIndex = next; return }
      cursorIndex = dy > 0 ? Math.min(cursorCount - 1, presetStart + presetCount) : 0
      return
    }
    var step = dx !== 0 ? dx : dy
    cursorIndex = Math.max(0, Math.min(cursorCount - 1, i + step))
  }

  function activateCursor() {
    if (!cursorActive) return
    if (cursorIndex === 0) { toggleSession(); return }
    if (cursorIndex < presetStart + presetCount) {
      startSession(presets[cursorIndex - presetStart].value)
      return
    }
    var offset = cursorIndex - toggleStart
    if (lidControlAvailable && offset === 0) {
      setConfig("displayOffOnLidClose", !displayOffOnLidClose)
    } else {
      setConfig("keepDisplayAwake", !keepDisplayAwake)
    }
  }

  function hoverCursor(index, hovered) {
    if (!hovered) return
    cursorActive = true
    cursorIndex = index
  }

  // ------------------------------------------------------------------ wiring

  onOpenedChanged: {
    if (!opened) return
    cursorActive = false
    cursorIndex = 0
    refreshCapabilities()
    stateFile.reload()
    configFile.reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadState(text())
    onFileChanged: reload()
    onLoadFailed: root.clearState()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onFileChanged: reload()
  }

  Process {
    id: capsProc
    command: [root.binPath, "capabilities"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.loadCapabilities(text) }
  }

  Process {
    id: actionProc
    onExited: {
      stateFile.reload()
      root.refreshCapabilities()
    }
  }

  Process {
    id: configProc
    onExited: configFile.reload()
  }

  // The bar tails state.json, but a timer's remaining time is derived, so it
  // has to be recomputed locally once a second while one is running.
  Timer {
    interval: 1000
    running: root.sessionActive && root.sessionMode === "timer"
    repeat: true
    onTriggered: root.tick()
  }

  // Lid state and attached monitors change without anything writing a file,
  // so re-read them while the panel is on screen.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refreshCapabilities()
  }

  Component.onCompleted: {
    stateFile.reload()
    configFile.reload()
    refreshCapabilities()
  }

  // -------------------------------------------------------------- bar icon

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showRemaining && root.sessionActive && root.sessionMode === "timer" && !vertical
      ? "󰛊 " + root.sessionLabel
      : "󰛊"
    slotSize: Style.bar.iconSlot * (root.showRemaining && root.sessionActive
                                    && root.sessionMode === "timer" && !vertical ? 2 : 1)
    active: root.sessionActive
    tooltipText: root.tooltip()
    onPressed: function (b) {
      if (b === Qt.RightButton) root.toggleSession()
      else root.toggle()
    }
  }

  // --------------------------------------------------------------- dropdown

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onMoveRequested: function (dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroText.implicitHeight, heroClock.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: "󰛊"
            color: root.fg
            opacity: root.sessionActive ? 1.0 : 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on opacity { NumberAnimation { duration: 200 } }
          }

          Column {
            id: heroText
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroClock.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "Amphetamine"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.statusLine().toUpperCase()
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroClock
            textFormat: Text.PlainText
            visible: root.sessionActive
            text: root.sessionMode === "timer" ? root.formatRemaining(root.remainingSec) : "∞"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- primary action ----------
        Button {
          width: parent.width
          text: root.sessionActive ? "End session" : "Keep awake indefinitely"
          iconText: root.sessionActive ? "󰅙" : "󰐊"
          iconSize: Style.font.title
          fontSize: Style.font.body
          foreground: root.fg
          fontFamily: root.fontFamily
          verticalPadding: Style.spacing.controlPaddingY + Style.space(3)
          bordered: true
          active: root.sessionActive && root.sessionMode === "indefinite"
          hasCursor: root.cursorActive && root.cursorIndex === 0
          onClicked: root.toggleSession()
          onHovered: function (h) { root.hoverCursor(0, h) }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- timed presets ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: root.sessionActive ? "SWITCH TO" : "OR STAY AWAKE FOR"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Grid {
            id: presetGrid
            width: parent.width
            columns: root.presetColumns
            spacing: Style.space(6)

            readonly property real cellWidth:
              (width - spacing * (root.presetColumns - 1)) / root.presetColumns

            Repeater {
              model: root.presets

              Button {
                required property var modelData
                required property int index

                width: presetGrid.cellWidth
                text: modelData.short
                fontSize: Style.font.body
                foreground: root.fg
                fontFamily: root.fontFamily
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                tooltipText: "Stay awake for " + modelData.label
                active: root.sessionActive && root.sessionMode === "timer"
                        && root.sessionLabel === modelData.short
                hasCursor: root.cursorActive && root.cursorIndex === root.presetStart + index
                onClicked: root.startSession(modelData.value)
                onHovered: function (h) { root.hoverCursor(root.presetStart + index, h) }
              }
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- lid preferences ----------
        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: root.lidPresent ? "WHEN THE LID CLOSES" : "WHILE A SESSION RUNS"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Toggle {
            width: parent.width
            visible: root.lidControlAvailable
            label: "Turn the screen off"
            description: "Keep working with the lid shut without cooking the panel"
            checked: root.displayOffOnLidClose
            foreground: root.fg
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.cursorIndex === root.toggleStart
            onClicked: root.setConfig("displayOffOnLidClose", !root.displayOffOnLidClose)
            onHovered: function (h) { root.hoverCursor(root.toggleStart, h) }
          }

          Toggle {
            width: parent.width
            label: "Block the screensaver and lock"
            description: "Also hold off idle dimming while a session is running"
            checked: root.keepDisplayAwake
            foreground: root.fg
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive
                       && root.cursorIndex === root.toggleStart + (root.lidControlAvailable ? 1 : 0)
            onClicked: root.setConfig("keepDisplayAwake", !root.keepDisplayAwake)
            onHovered: function (h) {
              root.hoverCursor(root.toggleStart + (root.lidControlAvailable ? 1 : 0), h)
            }
          }

          // Said plainly rather than hidden, so a desktop user is not left
          // wondering why the lid row above is missing.
          Text {
            width: parent.width
            visible: !root.lidControlAvailable
            textFormat: Text.PlainText
            text: root.lidPresent
              ? "No display power control detected, so the screen is left alone on lid close."
              : "No lid switch on this machine — sleep and idle are still held off."
            color: Qt.darker(root.fg, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator {
          foreground: root.fg
          visible: machineInfo.visible
        }

        // ---------- what we detected on this machine ----------
        Column {
          id: machineInfo
          width: parent.width
          spacing: Style.space(6)
          visible: root.lidPresent || root.internalDisplay !== ""

          PanelSectionHeader {
            text: "THIS MACHINE"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          InfoRow {
            visible: root.lidPresent
            label: "Lid"
            value: root.lidState === "closed" ? "Closed" : "Open"
          }

          InfoRow {
            visible: root.internalDisplay !== ""
            label: "Built-in display"
            value: root.internalDisplay
          }

          InfoRow {
            label: "External displays"
            value: root.externalDisplays.length > 0 ? root.externalDisplays.join(", ") : "None"
          }
        }
      }
    }
  }

  component InfoRow: Item {
    property string label: ""
    property string value: ""

    width: parent ? parent.width : 0
    implicitHeight: Math.max(rowLabel.implicitHeight, rowValue.implicitHeight)

    Text {
      id: rowLabel
      textFormat: Text.PlainText
      text: parent.label
      color: root.fg
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: rowValue
      textFormat: Text.PlainText
      text: parent.value
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.right: parent.right
      anchors.left: rowLabel.right
      anchors.leftMargin: Style.space(10)
      horizontalAlignment: Text.AlignRight
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
