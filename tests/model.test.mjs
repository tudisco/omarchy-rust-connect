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
