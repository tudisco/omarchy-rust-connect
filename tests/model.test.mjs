// node tests/model.test.mjs
import fs from "node:fs"
import assert from "node:assert/strict"
const src = fs.readFileSync(new URL("../Model.js", import.meta.url), "utf8").replace(/^\.pragma library\s*$/m, "")
const M = new Function(src + "; return { unwrap, parseSseLine, normalizeDevices, primaryDevice, pairRequests, stateText, lowBattery, errorText, deviceGlyph }")()

assert.deepEqual(M.parseSseLine(": keepalive", ""), { type: "ignore" })
assert.deepEqual(M.parseSseLine("event: snapshot", ""), { type: "name", name: "snapshot" })
assert.equal(M.parseSseLine('data: {"kind":"plugin.battery"}', "").name, "message")
assert.equal(M.parseSseLine('data: {"devices":[]}', "snapshot").name, "snapshot")
assert.deepEqual(M.parseSseLine("", "x"), { type: "reset" })

const list = { status: "success", data: { devices: [
  { id: "b", name: "Zed tablet", device_type: "tablet", state: "discovered", pair_state: "not_paired" },
  { id: "a", name: "Pixel", device_type: "phone", state: "connected", pair_state: "paired" },
  { id: "c", name: "<b>Evil</b>", device_type: "phone", state: "connected", pair_state: "requested_by_peer", verification_key: "1A2B3C" },
], total: 3 } }
const u = M.unwrap(list)
assert.ok(u.ok)
const devs = M.normalizeDevices(u.data)
assert.deepEqual(devs.map(d => d.id), ["a", "c", "b"])
assert.equal(M.primaryDevice(devs).id, "a")
assert.equal(M.pairRequests(devs)[0].verificationKey, "1A2B3C")
assert.equal(M.stateText(devs[0], { charge: 81, charging: false }), "Connected · 81%")
assert.ok(M.lowBattery({ charge: 10, charging: false }))
assert.ok(!M.unwrap({ status: "error", error: { code: "X", message: "nope" } }).ok)
assert.equal(M.errorText("", "curl: (7) Failed to connect to 127.0.0.1 port 9090: Connection refused"), "rust-connect is not running")
console.log("model tests passed")

// notifications
{
  const N = new Function(src + "; return { normalizeNotifications, normalizeNotification, applyNotification, removeNotification, timeAgo }")()
  const hist = { notifications: [
    { deviceId: "a", id: "1", appName: "WhatsApp", title: "Mom", text: "hi", replyId: "r1", receivedAt: "2026-11-07T08:00:00Z", isCancel: false },
    { deviceId: "a", id: "2", appName: "Gmail", title: "", text: "x".repeat(2000), receivedAt: "2026-11-07T09:00:00Z", isCancel: false },
  ] }
  let list = N.normalizeNotifications(hist)
  assert.deepEqual(list.map(n => n.id), ["2", "1"])
  assert.equal(list[0].title, "Gmail")          // empty title falls back to app
  assert.ok(list[0].text.length <= 600)
  assert.ok(list[1].canReply && !list[0].canReply)
  // SSE shape: snake_case
  list = N.applyNotification(list, N.normalizeNotification({ device_id: "a", id: "3", app_name: "Signal", title: "<b>x</b>", text: "yo", is_cancel: false }))
  assert.equal(list[0].id, "3")
  assert.equal(list[0].title, "<b>x</b>")       // kept verbatim; rendered as PlainText
  list = N.applyNotification(list, N.normalizeNotification({ device_id: "a", id: "1", is_cancel: true }))
  assert.deepEqual(list.map(n => n.id), ["3", "2"])
  list = N.removeNotification(list, "a\n2")
  assert.deepEqual(list.map(n => n.id), ["3"])
  assert.equal(N.normalizeNotification({ id: "x" }), null)
  assert.equal(N.timeAgo(0, 90 * 1000), "1m")
  console.log("notification tests passed")
}
