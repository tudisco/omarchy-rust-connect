import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Talks to the rust-connect daemon through bin/rconnect-api. A long-running
// `rconnect-api events` process feeds the SSE stream line by line; every
// action is a short one-shot process. The API key never leaves the helper.
Item {
  id: root

  property var settings: ({})

  readonly property string helper: {
    var url = String(Qt.resolvedUrl("bin/rconnect-api"))
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.substring(7)) : url
  }

  // State
  property bool streamUp: false          // SSE stream is delivering data
  property bool serviceActive: false     // systemd unit is active
  property bool serviceKnown: false      // the unit file exists
  property var devices: []
  property var batteries: ({})           // id -> {charge, charging}
  property string lastError: ""
  property string actionStatus: ""
  property int pendingActions: 0
  readonly property bool busy: pendingActions > 0

  readonly property var primary: Model.primaryDevice(devices)
  readonly property var primaryBattery: primary ? (batteries[primary.id] || null) : null
  readonly property var requests: Model.pairRequests(devices)

  signal pairRequested(var device)

  property string _pendingEvent: ""
  property var _notifiedRequests: ({})
  property int _backoff: 2000

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  function battery(id) { return batteries[id] || null }

  // ---- event stream -------------------------------------------------------

  function handleStreamLine(line) {
    var r = Model.parseSseLine(line, _pendingEvent)
    if (r.type === "name") { _pendingEvent = r.name; return }
    if (r.type === "reset") { _pendingEvent = ""; return }
    if (r.type !== "dispatch") return
    _pendingEvent = ""
    if (!streamUp) { streamUp = true; _backoff = 2000; lastError = "" }

    if (r.name === "snapshot") { applyDevices(r.data); return }
    if (r.name === "lagged") { refreshDevices(); return }

    var kind = String(r.data && r.data.kind || "")
    if (kind === "plugin.battery") {
      setBattery(String(r.data.device_id || ""), r.data.current_charge, r.data.is_charging)
    } else if (kind.indexOf("device.") === 0) {
      deviceRefreshDebounce.restart()
    }
  }

  function setBattery(id, charge, charging) {
    if (!id) return
    var c = parseInt(charge, 10)
    var next = Object.assign({}, batteries)
    next[id] = { charge: isFinite(c) ? c : -1, charging: charging === true }
    batteries = next
  }

  function applyDevices(raw) {
    var u = Model.unwrap(raw)
    if (!u.ok) { lastError = u.error; return }
    devices = Model.normalizeDevices(u.data)
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (d.paired && d.reachable && !batteries[d.id]) requestBattery(d.id)
    }
    notifyNewRequests()
  }

  function notifyNewRequests() {
    var seen = {}
    var reqs = Model.pairRequests(devices)
    for (var i = 0; i < reqs.length; i++) {
      var d = reqs[i]
      seen[d.id] = true
      if (_notifiedRequests[d.id]) continue
      pairRequested(d)
      if (setting("notifyPairRequests", true)) {
        // argv, not a shell string: names come from the phone.
        Quickshell.execDetached(["notify-send", "-a", "Phone", "-i", "smartphone",
          "Pairing request from " + d.name,
          d.verificationKey ? "Check the code on the phone: " + d.verificationKey + "\nAccept it from the Phone panel in the bar."
                            : "Accept it from the Phone panel in the bar."])
      }
    }
    _notifiedRequests = seen
  }

  // ---- one-shot API calls -------------------------------------------------

  Component {
    id: callComponent
    Process {
      id: proc
      property var onDone: null
      property string _out: ""
      property string _err: ""
      stdout: StdioCollector { id: so; waitForEnd: true; onStreamFinished: proc._out = text }
      stderr: StdioCollector { id: se; waitForEnd: true; onStreamFinished: proc._err = text }
      onExited: function(code) {
        var out = String(so.text || proc._out || "")
        var err = String(se.text || proc._err || "")
        if (proc.onDone) proc.onDone(code, out, err)
        proc.destroy()
      }
    }
  }

  // call(["get", "/api/v1/devices"], function(ok, data, error) {...}, tracked)
  function call(args, cb, tracked) {
    if (tracked) pendingActions += 1
    var p = callComponent.createObject(root, {
      command: ["bash", helper].concat(args),
      onDone: function(code, out, err) {
        if (tracked) pendingActions = Math.max(0, pendingActions - 1)
        var u = Model.unwrap(out)
        var ok = code === 0 && u.ok
        if (cb) cb(ok, u.data, ok ? "" : Model.errorText(out, err, "Request failed"))
      }
    })
    p.running = true
  }

  function act(args, doneText) {
    actionStatus = ""
    call(args, function(ok, data, error) {
      if (ok) { lastError = ""; flash(doneText) }
      else { lastError = error; flash(error) }
      deviceRefreshDebounce.restart()
    }, true)
  }

  function flash(text) {
    actionStatus = text || ""
    actionStatusTimer.restart()
  }

  function enc(id) { return encodeURIComponent(String(id)) }

  function refreshDevices() {
    call(["get", "/api/v1/devices"], function(ok, data, error) {
      if (ok) applyDevices({ data: data })
      else lastError = error
    }, false)
  }

  function requestBattery(id) {
    call(["get", "/api/v1/devices/" + enc(id) + "/battery"], function(ok, data) {
      if (ok && data) setBattery(id, data.current_charge, data.is_charging)
    }, false)
    // Ask the phone for a fresh reading; it arrives as plugin.battery.
    call(["post", "/api/v1/devices/" + enc(id) + "/battery/request"], null, false)
  }

  function pair(id) { act(["post", "/api/v1/devices/" + enc(id) + "/pair"], "Pairing request sent") }
  function acceptPair(id) { act(["post", "/api/v1/devices/" + enc(id) + "/pair"], "Paired") }
  // Declining an incoming request and unpairing are the same packet (pair:false).
  function rejectPair(id) { act(["delete", "/api/v1/devices/" + enc(id) + "/unpair"], "Pairing declined") }
  function unpair(id) { act(["delete", "/api/v1/devices/" + enc(id) + "/unpair"], "Unpaired") }
  function ring(id) { act(["post", "/api/v1/devices/" + enc(id) + "/findmyphone"], "Ringing the phone") }
  function ping(id) { act(["post", "/api/v1/ping", JSON.stringify({ device_id: String(id) })], "Ping sent") }
  function sendClipboard(id) { act(["send-clipboard", String(id)], "Clipboard sent") }
  function sendFiles(id) {
    // Picker can stay open a long time; don't count it as busy.
    actionStatus = ""
    call(["send-pick", String(id)], function(ok, data, error) {
      if (ok) flash("Sent")
      else if (error !== "no file chosen") { lastError = error; flash(error) }
    }, false)
  }

  // ---- daemon service -----------------------------------------------------

  function checkService() {
    if (!serviceProbe.running) serviceProbe.running = true
  }

  function setServiceRunning(on) {
    serviceCtl.command = ["systemctl", "--user", on ? "start" : "stop", "rust-connect.service"]
    serviceActive = on    // optimistic
    serviceCtl.running = true
  }

  Process {
    id: serviceProbe
    command: ["bash", "-c", "systemctl --user cat rust-connect.service >/dev/null 2>&1 && echo known; systemctl --user is-active rust-connect.service"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "")
        root.serviceKnown = t.indexOf("known") !== -1
        root.serviceActive = /(^|\n)active\b/.test(t)
      }
    }
  }

  Process {
    id: serviceCtl
    stderr: StdioCollector { id: ctlErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.flash(String(ctlErr.text || "systemctl failed").split("\n")[0])
      root.checkService()
      events.running = false
      reconnect.interval = 1500
      reconnect.restart()
    }
  }

  // ---- timers and the stream process -------------------------------------

  Process {
    id: events
    command: ["bash", root.helper, "events"]
    running: true
    stdout: SplitParser { onRead: function(line) { root.handleStreamLine(line) } }
    stderr: StdioCollector { id: eventsErr; waitForEnd: true }
    onExited: function(code) {
      root.streamUp = false
      root._pendingEvent = ""
      var e = Model.errorText(String(eventsErr.text || ""), String(eventsErr.text || ""), "")
      if (e) root.lastError = e
      root.checkService()
      reconnect.interval = root._backoff
      root._backoff = Math.min(30000, root._backoff * 2)
      reconnect.restart()
    }
  }

  Timer {
    id: reconnect
    repeat: false
    onTriggered: if (!events.running) events.running = true
  }

  Timer {
    id: deviceRefreshDebounce
    interval: 300
    repeat: false
    onTriggered: root.refreshDevices()
  }

  Timer {
    id: actionStatusTimer
    interval: 2500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    // Battery events only arrive when the phone sends them; nudge it now and
    // then while a phone is connected.
    interval: 5 * 60 * 1000
    repeat: true
    running: root.streamUp && root.primary !== null
    onTriggered: if (root.primary) root.requestBattery(root.primary.id)
  }

  Component.onCompleted: checkService()
}
