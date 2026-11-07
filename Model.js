.pragma library

// Pure helpers for the rconnect panel. No QML types in here, so
// tests/model.test.mjs can run them under node.

function glyph(cp) { return String.fromCodePoint(cp) }

// Nerd Font Material Design glyphs.
var GLYPH = {
  phone: glyph(0xF011C),        // cellphone
  tablet: glyph(0xF04F6),
  laptop: glyph(0xF0322),
  desktop: glyph(0xF01C4),
  tv: glyph(0xF0502),
  unknown: glyph(0xF011C),
  ring: glyph(0xF009E),         // bell-ring
  ping: glyph(0xF04E5),         // signal / wave
  sendFile: glyph(0xF0552),     // file-upload
  sendClipboard: glyph(0xF0147),// clipboard-arrow-right
  pair: glyph(0xF0339),         // link
  unpair: glyph(0xF0337),       // link-off
  refresh: glyph(0xF0450),
  clearAll: glyph(0xF0234),     // notification-clear-all
  reply: glyph(0xF0167),
  close: glyph(0xF0156),
  send: glyph(0xF048A)
}

function deviceGlyph(type) {
  return GLYPH[String(type || "unknown")] || GLYPH.unknown
}

// rust-connect wraps every reply as {status, data, metadata}; errors as
// {status:"error", error:{code, message}}. Returns {ok, data, error}.
function unwrap(raw) {
  var parsed
  try {
    parsed = typeof raw === "string" ? JSON.parse(raw) : raw
  } catch (e) {
    return { ok: false, data: null, error: "Unreadable reply from rust-connect" }
  }
  if (!parsed || typeof parsed !== "object") return { ok: false, data: null, error: "Empty reply" }
  if (parsed.status === "error" || parsed.error) {
    var err = parsed.error || {}
    return { ok: false, data: null, error: String(err.message || err.code || "Request failed") }
  }
  return { ok: true, data: parsed.data !== undefined ? parsed.data : parsed, error: "" }
}

// One SSE line at a time, as SplitParser hands them over. `pending` is the
// name from a preceding `event:` line ("" for the default message event).
// Returns one of:
//   {type:"name", name}            remember for the next data line
//   {type:"dispatch", name, data}  a complete frame (single-line JSON data)
//   {type:"reset"}                 blank line, frame boundary
//   {type:"ignore"}                comment / keepalive / id / malformed
function parseSseLine(line, pending) {
  var s = String(line === undefined || line === null ? "" : line).replace(/\r$/, "")
  if (s === "") return { type: "reset" }
  if (s.charAt(0) === ":") return { type: "ignore" }
  var colon = s.indexOf(":")
  var field = colon < 0 ? s : s.slice(0, colon)
  var value = colon < 0 ? "" : s.slice(colon + 1).replace(/^ /, "")
  if (field === "event") return { type: "name", name: value }
  if (field !== "data") return { type: "ignore" }
  var data
  try { data = JSON.parse(value) } catch (e) { return { type: "ignore" } }
  return { type: "dispatch", name: pending || "message", data: data }
}

function normalizeDevice(d) {
  var pairState = String(d.pair_state || (d.paired_at ? "paired" : "not_paired"))
  return {
    id: String(d.id || ""),
    name: String(d.name || d.id || "Unknown device"),
    type: String(d.device_type || "unknown"),
    state: String(d.state || "discovered"),
    pairState: pairState,
    paired: pairState === "paired",
    reachable: d.state === "connected",
    pairRequested: pairState === "requested_by_peer",
    pairing: pairState === "requested",
    verificationKey: d.verification_key ? String(d.verification_key) : "",
    lastSeen: String(d.last_seen || "")
  }
}

// Paired+reachable first, then pair requests, then other paired devices,
// then whatever else is on the LAN; ties by name.
function rank(d) {
  if (d.paired && d.reachable) return 0
  if (d.pairRequested) return 1
  if (d.paired) return 2
  if (d.reachable) return 3
  return 4
}

function normalizeDevices(list) {
  var arr = []
  var src = list && list.devices ? list.devices : (list instanceof Array ? list : [])
  for (var i = 0; i < src.length; i++) {
    if (src[i] && src[i].id) arr.push(normalizeDevice(src[i]))
  }
  arr.sort(function(a, b) {
    var r = rank(a) - rank(b)
    if (r !== 0) return r
    return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0)
  })
  return arr
}

function primaryDevice(devices) {
  for (var i = 0; i < devices.length; i++) {
    if (devices[i].paired && devices[i].reachable) return devices[i]
  }
  return null
}

function pairRequests(devices) {
  return devices.filter(function(d) { return d.pairRequested })
}

function batteryGlyph(b) {
  if (!b) return ""
  if (b.charging) return glyph(0xF0084)
  var c = b.charge
  if (c >= 95) return glyph(0xF0079)
  if (c >= 80) return glyph(0xF0082)
  if (c >= 60) return glyph(0xF0080)
  if (c >= 40) return glyph(0xF007E)
  if (c >= 20) return glyph(0xF007C)
  return glyph(0xF007A)
}

function batteryText(b) {
  if (!b || b.charge < 0) return ""
  return b.charge + "%" + (b.charging ? " charging" : "")
}

function stateText(d, battery) {
  if (!d) return ""
  if (d.pairRequested) return "Wants to pair"
  if (d.pairing) return "Waiting for the phone to accept…"
  if (!d.paired) return d.reachable ? "Not paired" : "Seen on network"
  if (!d.reachable) return "Paired · offline"
  var b = batteryText(battery)
  return b ? "Connected · " + b : "Connected"
}

function lowBattery(b) {
  return !!b && !b.charging && b.charge >= 0 && b.charge <= 15
}

// Readable fallbacks for helper failures that came back as text.
function errorText(stdout, stderr, fallback) {
  var u = unwrap(stdout)
  if (!u.ok && u.error && u.error !== "Unreadable reply from rust-connect") return u.error
  var e = String(stderr || "").trim()
  if (e.indexOf("Connection refused") !== -1 || e.indexOf("Couldn't connect") !== -1) return "rust-connect is not running"
  if (e !== "") return e.split("\n")[0].replace(/^curl: \(\d+\) /, "")
  return fallback || "Request failed"
}

// ---- phone notifications ---------------------------------------------------
// History entries from GET /api/v1/notifications are camelCase; SSE
// plugin.notification events are snake_case. Accept both. Strings are
// clamped: this is phone-controlled text.

var MAX_NOTIFICATIONS = 50

function clampText(v, n) {
  var s = String(v === undefined || v === null ? "" : v)
  return s.length > n ? s.substring(0, n - 1) + "…" : s
}

function pick(o, camel, snake) {
  if (!o) return undefined
  return o[camel] !== undefined ? o[camel] : o[snake]
}

function normalizeNotification(o) {
  if (!o) return null
  var id = String(pick(o, "id", "id") || "")
  var deviceId = String(pick(o, "deviceId", "device_id") || "")
  if (!id || !deviceId) return null
  var app = clampText(pick(o, "appName", "app_name"), 60)
  var title = clampText(pick(o, "title", "title"), 120)
  var replyId = pick(o, "replyId", "reply_id")
  var received = Date.parse(String(pick(o, "receivedAt", "received_at") || ""))
  return {
    key: deviceId + "\n" + id,
    deviceId: deviceId,
    id: id,
    app: app,
    title: title || app,
    text: clampText(pick(o, "text", "text"), 600),
    canReply: !!replyId,
    cancel: pick(o, "isCancel", "is_cancel") === true,
    receivedAt: isFinite(received) ? received : Date.now()
  }
}

// Newest first. History arrives oldest-first from the daemon (or newest-first
// with ?page); sort so either works.
function normalizeNotifications(data) {
  var src = data && data.notifications ? data.notifications : (data instanceof Array ? data : [])
  var out = []
  var seen = {}
  for (var i = 0; i < src.length; i++) {
    var n = normalizeNotification(src[i])
    if (!n || n.cancel || seen[n.key]) continue
    seen[n.key] = true
    out.push(n)
  }
  out.sort(function(a, b) { return b.receivedAt - a.receivedAt })
  return out.slice(0, MAX_NOTIFICATIONS)
}

// Apply one event: a cancel removes, anything else replaces-or-prepends.
function applyNotification(list, n) {
  if (!n) return list
  var out = (list || []).filter(function(x) { return x.key !== n.key })
  if (n.cancel) return out
  out.unshift(n)
  return out.slice(0, MAX_NOTIFICATIONS)
}

function removeNotification(list, key) {
  return (list || []).filter(function(x) { return x.key !== key })
}

function timeAgo(ms, now) {
  var s = Math.max(0, Math.round(((now || Date.now()) - ms) / 1000))
  if (s < 60) return "now"
  if (s < 3600) return Math.floor(s / 60) + "m"
  if (s < 86400) return Math.floor(s / 3600) + "h"
  return Math.floor(s / 86400) + "d"
}
