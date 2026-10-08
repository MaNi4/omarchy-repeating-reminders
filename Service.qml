import QtQuick
import Quickshell
import Quickshell.Io
import "Store.js" as Store

// The list of reminders and the commands that change it, mounted once for the
// shell. Omarchy builds a bar per monitor, so listing from the widget would
// run bin/repeating-reminder once per screen. Every Panel.qml is a view of this.
Item {
  id: service
  visible: false

  readonly property string pluginDir: {
    var s = String(Qt.resolvedUrl("."))
    return s.indexOf("file://") === 0 ? s.substring(7) : s
  }
  readonly property string command: pluginDir + "bin/repeating-reminder"

  // ---------- Data ----------
  property var items: []
  property real now: Date.now() / 1000
  readonly property var soonest: items.length ? items[0] : null
  // How many panels are open, on any monitor.
  property int openPanels: 0

  // ---------- Timers ----------
  property bool refreshAgain: false

  function refresh() {
    if (listProc.running) refreshAgain = true
    else listProc.running = true
  }

  Process {
    id: listProc
    command: [service.command, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          service.now = Date.now() / 1000
          service.items = d && d.reminders ? d.reminders : []
        } catch (e) { }
      }
    }
    onExited: {
      if (service.refreshAgain) { service.refreshAgain = false; service.refresh() }
    }
  }

  // Commands run one at a time, each followed by a fresh list.
  property var queue: []

  function run(args) {
    queue = queue.concat([args])
    pump()
  }

  function pump() {
    if (actionProc.running || !queue.length) return
    actionProc.command = [command].concat(queue[0])
    queue = queue.slice(1)
    actionProc.running = true
  }

  Process {
    id: actionProc
    onExited: {
      service.refresh()
      service.pump()
    }
  }

  // The list is also what starts a repeating reminder again after a reboot,
  // so it runs once at load and then every minute.
  Component.onCompleted: {
    // Where panels that the shell does not hand this service to find it.
    Store.set(service)
    refresh()
  }
  Component.onDestruction: Store.clear(service)

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: service.refresh()
  }

  // Counts down while a panel is open, and fetches the list again as soon
  // as a reminder is due.
  Timer {
    interval: 1000
    running: service.openPanels > 0
    repeat: true
    onTriggered: {
      service.now = Date.now() / 1000
      if (service.soonest && service.soonest.at <= service.now) service.refresh()
    }
  }

  // With the panels closed, look again just after the next reminder fires so
  // the icon goes out on time.
  Timer {
    interval: service.soonest ? Math.max(2000, (service.soonest.at - service.now) * 1000 + 2000) : 60000
    running: !!service.soonest && service.openPanels === 0
    onTriggered: service.refresh()
  }
}
