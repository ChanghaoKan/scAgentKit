#!/usr/bin/env node
/** Focused client trust-state checks using the actual qc.js request/load logic.
 * DOM rendering is stubbed here; actual Chrome rendering is tested separately.
 */
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import {fileURLToPath} from "node:url";

const script = await fs.readFile(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../static/qc.js"), "utf8");
assert(script.endsWith("load();\n"), "Keep the actual application entry identifiable for the isolated logic test");
const view = () => ({schema: "scagentkit.qc.workbench.v1", csrf_token: "local-review-token", run: {
  schema: "scagentkit.run.v1", project_id: "verified-project", status: "awaiting_review", revision: 5,
  pending: {kind: "qc", hash: "a".repeat(64)}, qc_preview: {hash: "b".repeat(64)}
}});
const response = value => ({ok: true, status: 200, json: async () => value});
function client(fetch) {
  const nodes = new Map(), document = {getElementById(id) {
    if (!nodes.has(id)) {
      const node = {value: "", addEventListener() {}}; let disabled = false;
      Object.defineProperty(node, "disabled", {get: () => disabled, set: value => {disabled = Boolean(value);}});
      nodes.set(id, node);
    }
    return nodes.get(id);
  }};
  // Scoped QC routes use standard browser URL parsing even when rendering is inert.
  const window = {location: {search: ""}};
  const context = vm.createContext({document, window, URLSearchParams, fetch, console});
  // Execute production event wiring and logic without its automatic first load.
  vm.runInContext(script.slice(0, -"load();\n".length) + "\nrender = () => {}; globalThis.qcClient = {state, request, load, buttons};", context);
  const api = context.qcClient; api.state.view = view(); return {api, nodes, context};
}
function disabled(client) {
  client.api.buttons();
  for (const id of ["qc-approve", "qc-reject", "qc-revise", "qc-preview"]) assert.equal(client.nodes.get(id).disabled, true, id);
  assert.equal(client.nodes.get("qc-refresh").disabled, false);
}
let passed = 0;
async function test(name, fn) {await fn(); passed++; console.log("PASS " + name);}
const invalid = [
  ["outer schema", v => {v.schema = "foreign";}],
  ["run schema", v => {v.run.schema = "foreign";}],
  ["changed project", v => {v.run.project_id = "foreign-project";}],
  ["missing project", v => {delete v.run.project_id;}],
  ["missing token", v => {delete v.csrf_token;}],
  ["non-text token", v => {v.csrf_token = 17;}]
];
for (const [name, mutate] of invalid) await test("POST HTTP200 " + name + " disables all writes and preserves verified view", async () => {
  const bad = view(); mutate(bad); const c = client(async () => response(bad)); const prior = c.api.state.view;
  await assert.rejects(c.api.request({action: "approve"})); assert.equal(c.api.state.stale, true); assert.equal(c.api.state.view, prior); disabled(c);
});
for (const [name, fetch] of [
  ["network", async () => {throw new Error("disconnected");}],
  ["JSON", async () => ({ok: true, status: 200, json: async () => {throw new Error("truncated");}})],
  ["HTTP422", async () => ({ok: false, status: 422, json: async () => ({error: "Invalid response"})})]
]) await test("GET " + name + " failure cannot enable a previous saved preview", async () => {
  const c = client(fetch), prior = c.api.state.view; await c.api.load(); assert.equal(c.api.state.stale, true); assert.equal(c.api.state.view, prior); disabled(c);
});
await test("failed refresh stays disabled; only verified refresh restores actions", async () => {
  let next = response({...view(), schema: "foreign"}); const c = client(async () => next);
  await assert.rejects(c.api.request({action: "approve"})); disabled(c);
  await c.api.load(); disabled(c);
  next = response(view()); await c.api.load(); assert.equal(c.api.state.stale, false);
  for (const id of ["qc-approve", "qc-reject", "qc-revise", "qc-preview"]) assert.equal(c.nodes.get(id).disabled, false, id);
});
await test("verified refresh with no pending QC keeps actions disabled", async () => {
  const approved = view(); approved.run.pending = null; approved.run.status = "ready";
  const c = client(async () => response(approved)); c.api.state.stale = true; await c.api.load(); assert.equal(c.api.state.stale, false); disabled(c);
});
await test("a verified direct response alone does not clear a stale page", async () => {
  const c = client(async () => response(view())); c.api.state.stale = true; await c.api.request(); assert.equal(c.api.state.stale, true); disabled(c);
});
console.log(passed + " focused client trust-state cases passed");
