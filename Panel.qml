import QtQuick
import Quickshell
import Quickshell.Io
import "Store.js" as Store
import qs.Ui
import qs.Commons

// Reminders that can repeat. The same flow as the built-in reminder (minutes,
// then a message), with one more choice at the end: remind once, or keep
// reminding every that many minutes. Minutes can be a fraction ("0.5"), or
// the time can be given in seconds ("30s"). The timers themselves belong to
// bin/repeating-reminder; this panel sets them, lists them and stops them.
// Service.qml owns the list and the commands; this widget exists once per
// monitor and shows it. Theme colours, stock qs.Ui parts.
Panel {
  id: root

  moduleName: "mani4.repeating-reminders"
  ipcTarget: "mani4.repeating-reminders"

  readonly property string ff: bar ? bar.fontFamily : Style.font.family
  readonly property color dimForeground: Qt.darker(barForeground, 1.4)
  readonly property color accent: Color.accent

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string pluginDir: {
    var s = String(Qt.resolvedUrl("."))
    return s.indexOf("file://") === 0 ? s.substring(7) : s
  }

  // ---------- Service ----------
  // The list is a shell service, not a child of this widget: listing from
  // here would run bin/repeating-reminder once per monitor.
  property var service: null
  // Whether this panel is counted in the service's openPanels.
  property bool counted: false

  function bindService() {
    if (service) return
    var host = bar && bar.shell ? bar.shell : null
    var s = host && typeof host.serviceFor === "function" ? host.serviceFor(moduleName) : null
    // A tray drawer hands its widgets a facade without their service; see Store.js.
    if (!s) s = Store.get()
    if (!s) return
    service = s
    countOpen()
  }

  // The service polls faster while any panel is open.
  function countOpen() {
    if (!service || counted === opened) return
    counted = opened
    service.openPanels += opened ? 1 : -1
  }

  Component.onDestruction: if (service && counted) service.openPanels -= 1

  // Polled: serviceFor() is a call, so nothing notifies a binding.
  Timer {
    interval: 100
    repeat: true
    running: root.service === null
    triggeredOnStart: true
    onTriggered: root.bindService()
  }

  // ---------- Data ----------
  readonly property var items: service ? service.items : []
  readonly property real now: service ? service.now : Date.now() / 1000
  readonly property var soonest: items.length ? items[0] : null

  function remaining(at) {
    var s = Math.max(0, Math.round(Number(at || 0) - now))
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    if (h > 0) return h + "h " + m + "m"
    if (m > 0) return opened && m < 10 ? m + "m " + (s % 60) + "s" : m + "m"
    return s + "s"
  }

  function clock(at) {
    return Qt.formatTime(new Date(Number(at || 0) * 1000), "H:mm")
  }

  function when(reminder) {
    var next = "in " + remaining(reminder.at) + " (" + clock(reminder.at) + ")"
    return reminder.loop ? "Every " + length(reminder.seconds) + "  ·  next " + next : next
  }

  // ---------- Commands ----------
  function refresh() {
    if (service) service.refresh()
  }

  // Commands run one at a time, each followed by a fresh list.
  function run(args) {
    if (service) service.run(args)
  }

  // ---------- New reminder ----------
  // Minutes, which may be a fraction ("0.5" or "0,5"), or seconds ("30s").
  // Gives whole seconds, or 0 for anything under five seconds or not a time.
  function validSeconds(value) {
    var v = String(value || "").trim().replace(",", ".")
    var s = /^[0-9]+s$/.test(v) ? Number(v.slice(0, -1))
      : /^([0-9]+\.[0-9]+|\.[0-9]+|[0-9]+)$/.test(v) ? Math.round(Number(v) * 60) : 0
    return s >= 5 && s <= 5999940 ? s : 0
  }
  readonly property int seconds: validSeconds(minutesField.text)

  // 30 -> "30 s", 300 -> "5 min", 90 -> "1 min 30 s"
  function length(s) {
    s = Number(s || 0)
    if (s < 60) return s + " s"
    return Math.floor(s / 60) + " min" + (s % 60 ? " " + (s % 60) + " s" : "")
  }

  // Whether the reminder also shows while "Silence notifications" is on.
  // Kept in this widget's shell.json entry, so the panel offers the same
  // answer on every monitor and after a restart.
  readonly property bool throughSilence: {
    var v = setting("throughSilence", false)
    return v === true || v === "true"
  }

  // Saved through the shell's own API, as the stock panels save theirs.
  function saveSetting(key, value) {
    var entry = { id: moduleName }
    for (var k in settings) if (k !== "id") entry[k] = settings[k]
    entry[key] = value
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }

  function toggleSilence() {
    saveSetting("throughSilence", !throughSilence)
  }

  function submit(loop) {
    if (seconds === 0) { setCursor(0, 0); return }
    var message = messageField.text.trim()
    run(["add"].concat(loop ? ["--loop"] : []).concat(throughSilence ? ["--loud"] : [])
      .concat([seconds + "s"]).concat(message !== "" ? [message] : []))
    close()
  }

  function stop(reminder) {
    if (reminder && reminder.unit) run(["stop", reminder.unit])
  }

  // ---------- Keyboard cursor ----------
  // A grid: the two fields, the silence choice, the two ways to set the
  // reminder, then one row for each reminder and the clear button. A field
  // takes the keys while the cursor is on it.
  property int cursorRow: 0
  property int cursorCol: 0
  readonly property var rows: [["minutes", "message"], ["silence"], ["once", "loop"]]
    .concat(items.map(function(r, i) { return ["item:" + i] }))
    .concat(items.length ? [["clear"]] : [])
  readonly property string cursorItem: {
    var row = rows[Math.min(cursorRow, rows.length - 1)]
    return row[Math.min(cursorCol, row.length - 1)]
  }
  onRowsChanged: if (cursorRow >= rows.length) cursorRow = rows.length - 1

  function hasCursor(key) { return cursorItem === key }

  function setCursor(row, col) {
    cursorRow = Math.max(0, Math.min(rows.length - 1, row))
    cursorCol = Math.max(0, Math.min(rows[cursorRow].length - 1, col))
    if (!opened) return
    if (cursorItem === "minutes") minutesField.forceActiveFocus()
    else if (cursorItem === "message") messageField.forceActiveFocus()
    else keyCatcher.forceActiveFocus()
  }

  function moveCursor(dx, dy) {
    setCursor(cursorRow + dy, dy !== 0 ? cursorCol : cursorCol + dx)
  }

  function activate(key) {
    if (key === "once") submit(false)
    else if (key === "loop") submit(true)
    else if (key === "silence") toggleSilence()
    else if (key === "clear") run(["clear"])
    else if (key.indexOf("item:") === 0) stop(items[Number(key.substring(5))])
  }

  onOpenedChanged: {
    countOpen()
    if (opened) {
      minutesField.text = ""
      messageField.text = ""
      cursorRow = 0
      cursorCol = 0
      if (service) service.now = Date.now() / 1000
      refresh()
      Qt.callLater(function() { if (root.opened) minutesField.forceActiveFocus() })
    }
  }

  // ---------- Bar icon ----------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.items.length ? "\u{f009e}" : "\u{f009c}" // nf-md-bell-ring, nf-md-bell-outline
    active: root.items.length > 0
    tooltipText: !root.soonest ? "Set a reminder"
      : (root.items.length === 1 ? "1 reminder" : root.items.length + " reminders")
        + "  ·  " + root.soonest.label + " in " + root.remaining(root.soonest.at)
    onPressed: function(b) { root.toggle() }
  }

  // ---------- Pieces ----------
  // One reminder: its message over when it is due, and a cross that stops it.
  // One that shows even while notifications are silenced says so, in the
  // accent colour: that is the one to know about before a presentation.
  component ReminderRow: Rectangle {
    id: row
    property var reminder: ({})
    property bool hasCursor: false
    signal stopRequested()

    width: parent ? parent.width : 0
    implicitHeight: rowText.implicitHeight + Style.spacing.controlPaddingY * 2
    radius: Style.space(4)
    color: hasCursor ? Style.hoverFillFor(root.barForeground, root.accent) : "transparent"

    Text {
      id: kind
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(18)
      textFormat: Text.PlainText
      text: row.reminder.loop ? "\u{f0456}" : "\u{f009a}" // nf-md-repeat, nf-md-bell
      color: row.reminder.loop ? root.accent : root.dimForeground
      font.family: root.ff
      font.pixelSize: Style.font.icon
    }

    Column {
      id: rowText
      anchors.left: kind.right
      anchors.leftMargin: Style.space(8)
      anchors.right: cross.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.reminder.label || ""
        elide: Text.ElideRight
        color: root.barForeground
        font.family: root.ff
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.when(row.reminder)
        elide: Text.ElideRight
        color: root.dimForeground
        font.family: root.ff
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: row.reminder.quiet !== true
        width: parent.width
        textFormat: Text.PlainText
        text: "\u{f009e}  Notifies even when silenced" // nf-md-bell-ring
        elide: Text.ElideRight
        color: root.accent
        font.family: root.ff
        font.pixelSize: Style.font.caption
      }
    }

    Button {
      id: cross
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: "\u{f0156}" // nf-md-close
      iconSize: Style.font.icon
      tooltipText: "Stop this reminder"
      foreground: root.barForeground
      fontFamily: root.ff
      horizontalPadding: Style.spacing.controlPaddingX
      verticalPadding: Style.spacing.controlPaddingY
      onClicked: row.stopRequested()
    }
  }

  // ---------- Panel ----------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: minutesField
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While a field is being typed in, every key belongs to it.
      blocked: minutesField.activeFocus || messageField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activate(root.cursorItem)
      onDeleteRequested: if (root.cursorItem.indexOf("item:") === 0) root.activate(root.cursorItem)

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // ---------- Heading ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heading.implicitHeight, count.implicitHeight)

          PanelSectionHeader {
            id: heading
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "REMINDERS"
            foreground: root.barForeground
            fontFamily: root.ff
          }

          Text {
            id: count
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.items.length ? root.items.length + " active" : "None set"
            color: root.dimForeground
            font.family: root.ff
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- Minutes and message ----------
        // Enter walks on: minutes, message, then the two buttons below.
        // Escape empties a field, or closes the panel when it is empty.
        Row {
          id: fieldRow
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: minutesField
            width: Style.space(96)
            // 0.5 is half a minute, 30s the same in seconds. No validator:
            // anything can be typed, the buttons wake up once it is a time.
            placeholderText: "Min or 30s"
            maximumLength: 8
            font.family: root.ff
            font.pixelSize: Style.font.bodySmall
            foreground: root.barForeground
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            hasCursor: root.hasCursor("minutes")

            onActiveFocusChanged: if (activeFocus) { root.cursorRow = 0; root.cursorCol = 0 }
            // Handled here, not in onAccepted, so the key stops at the field
            // and does not go on to press a button.
            Keys.onReturnPressed: if (root.seconds > 0) root.setCursor(0, 1)
            Keys.onEnterPressed: if (root.seconds > 0) root.setCursor(0, 1)
            Keys.onEscapePressed: text !== "" ? clear() : root.close()
            Keys.onTabPressed: root.setCursor(0, 1)
            Keys.onDownPressed: root.setCursor(1, 0)
          }

          TextField {
            id: messageField
            width: fieldRow.width - minutesField.width - fieldRow.spacing
            placeholderText: "Message (optional)"
            maximumLength: 120
            font.family: root.ff
            font.pixelSize: Style.font.bodySmall
            foreground: root.barForeground
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            hasCursor: root.hasCursor("message")

            onActiveFocusChanged: if (activeFocus) { root.cursorRow = 0; root.cursorCol = 1 }
            Keys.onReturnPressed: root.setCursor(2, 0)
            Keys.onEnterPressed: root.setCursor(2, 0)
            Keys.onEscapePressed: text !== "" ? clear() : root.close()
            Keys.onTabPressed: root.setCursor(0, 0)
            Keys.onBacktabPressed: root.setCursor(0, 0)
            Keys.onDownPressed: root.setCursor(1, 1)
          }
        }

        // ---------- Through "Silence notifications", or not ----------
        // A label with a switch; the whole row takes the click.
        Rectangle {
          id: silenceRow
          width: parent.width
          implicitHeight: Math.max(silenceLabel.implicitHeight, silenceSwitch.implicitHeight) + Style.spacing.controlPaddingY * 2
          radius: Style.space(4)
          color: silenceMouse.containsMouse || root.hasCursor("silence")
            ? Style.hoverFillFor(root.barForeground, root.accent) : "transparent"

          Text {
            id: silenceIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            textFormat: Text.PlainText
            text: root.throughSilence ? "\u{f009e}" : "\u{f009b}" // nf-md-bell-ring, nf-md-bell-off
            color: root.throughSilence ? root.accent : root.dimForeground
            font.family: root.ff
            font.pixelSize: Style.font.icon
          }

          Text {
            id: silenceLabel
            anchors.left: silenceIcon.right
            anchors.leftMargin: Style.space(8)
            anchors.right: silenceSwitch.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: "Notify even when silenced"
            color: root.barForeground
            font.family: root.ff
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            id: silenceMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activate("silence")
          }

          ToggleSwitch {
            id: silenceSwitch
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            checked: root.throughSilence
            foreground: root.barForeground
            onToggled: root.activate("silence")
          }
        }

        // ---------- Once, or in a loop ----------
        Row {
          id: setRow
          width: parent.width
          spacing: Style.space(6)
          opacity: root.seconds > 0 ? 1 : 0.5

          Repeater {
            model: [
              { key: "once", icon: "\u{f009a}" }, // nf-md-bell
              { key: "loop", icon: "\u{f0456}" }  // nf-md-repeat
            ]
            Button {
              required property var modelData
              width: (setRow.width - setRow.spacing) / 2
              iconText: modelData.icon
              iconSize: Style.font.icon
              text: modelData.key === "once" ? "Remind once"
                : root.seconds > 0 ? "Repeat every " + root.length(root.seconds) : "Repeat"
              hasCursor: root.hasCursor(modelData.key)
              fontSize: Style.font.bodySmall
              foreground: root.barForeground
              fontFamily: root.ff
              bordered: true
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.activate(modelData.key)
            }
          }
        }

        PanelSeparator {
          visible: root.items.length > 0
          width: parent.width
          foreground: root.barForeground
        }

        // ---------- Reminders ----------
        // Scrolls when there are more than the screen leaves room for.
        Flickable {
          id: listView
          visible: root.items.length > 0
          width: parent.width
          height: Math.min(list.implicitHeight, Math.max(Style.space(120), panel.availableCardHeight - Style.space(260)))
          contentHeight: list.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          // Keep the row under the keyboard cursor in view.
          function reveal(row) {
            if (!row) return
            if (row.y < contentY) contentY = row.y
            else if (row.y + row.height > contentY + height) contentY = row.y + row.height - height
          }

          Column {
            id: list
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.items.length
              ReminderRow {
                required property int index
                reminder: root.items[index] || ({})
                hasCursor: root.hasCursor("item:" + index)
                onHasCursorChanged: if (hasCursor) listView.reveal(this)
                onStopRequested: root.stop(reminder)
              }
            }
          }
        }

        Button {
          visible: root.items.length > 0
          width: parent.width
          iconText: "\u{f0a7a}" // nf-md-trash-can-outline
          iconSize: Style.font.icon
          text: "Clear all"
          hasCursor: root.hasCursor("clear")
          fontSize: Style.font.bodySmall
          foreground: root.barForeground
          fontFamily: root.ff
          bordered: true
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.activate("clear")
        }
      }
    }
  }
}
