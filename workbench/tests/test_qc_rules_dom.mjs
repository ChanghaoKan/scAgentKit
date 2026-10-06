#!/usr/bin/env node
// Real production rendering with an inert DOM; no browser or external request.
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import {fileURLToPath} from "node:url";

const source = await fs.readFile(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../static/qc.js"), "utf8");
assert(source.endsWith("load();\n"));
class Node {
  constructor(tag = "div") {this.tagName = tag; this.children = []; this.attributes = {}; this.value = ""; this._text = "";}
  set textContent(value) {this._text = String(value); this.children = [];}
  get textContent() {return this._text + this.children.map(node => node.textContent).join(" ");}
  append(...nodes) {this.children.push(...nodes);}
  replaceChildren(...nodes) {this._text = ""; this.children = nodes;}
  setAttribute(name, value) {this.attributes[name] = value;}
  addEventListener() {}
}
const nodes = new Map(), document = {
  body: {dataset: {runReview: "true"}},
  getElementById(id) {if (!nodes.has(id)) nodes.set(id, new Node()); return nodes.get(id);},
  createElement(tag) {return new Node(tag);}
};
let requests = 0;
const context = vm.createContext({document, window: {location: {search: ""}}, URLSearchParams, console,
  fetch: async () => {requests++; throw new Error("No requests permitted by the inert rendering fixture");}});
vm.runInContext(source.slice(0, -"load();\n".length) + "\nglobalThis.fixture={state,renderRules,renderImpacts};", context);
const api = context.fixture; api.state.view = {run: {pending: null}};
const descendants = (node, tag) => node.children.flatMap(child => [...(child.tagName === tag ? [child] : []), ...descendants(child, tag)]);
let passed = 0;
function test(name, fn) {fn(); passed++; console.log("PASS " + name);}
const range = {op: "range", metric: "nFeature", min: 200, max: null, group: {sample: "literal <img src=x onerror=alert(1)>"}};
const mad = {op: "mad_preset", preset_id: "conservative_and3", panel_hash: "a".repeat(64)};
const details = proposal => ({canonical_parameters: {proposal}, keep_cells: ["001", "cell space"], remove_cells: ["NA"]});
test("legacy ranges retain their five-column table", () => {
  api.renderRules(details({schema: "scagentkit.qc.v1", rationale: "Legacy", risks: [], filters: [range]}));
  const table = descendants(nodes.get("qc-rules"), "table")[0];
  assert.equal(descendants(table, "th").length, 5); assert.equal(descendants(table, "td").length, 5);
  assert.match(table.textContent, /nFeature/); assert.match(table.textContent, /No upper bound/);
  assert.doesNotMatch(nodes.get("qc-rules").textContent, /ANY|ALL/);
});
test("OR combination displays every range and saved MAD predicate", () => {
  api.renderRules(details({schema: "scagentkit.qc.rules.v1", rationale: "Combined", risks: [], remove_if: "any", rules: [range, mad]}));
  const target = nodes.get("qc-rules"), table = descendants(target, "table")[0];
  assert.match(target.textContent, /ANY rule fails \(OR of failures\)/);
  assert.equal(descendants(table, "th").length, 6); assert.equal(descendants(table, "td").length, 12);
  assert.match(table.textContent, /nFeature/); assert.match(table.textContent, /Saved MAD predicate/);
  assert.match(table.textContent, /conservative_and3/); assert.match(target.textContent, new RegExp(mad.panel_hash));
  assert.match(target.textContent, /minimal-prefilter exclusions remain mandatory/);
});
test("AND and unsupported logic are disclosed without inventing an execution", () => {
  api.renderRules(details({schema: "scagentkit.qc.rules.v1", rationale: "Combined", risks: [], remove_if: "all", rules: [range]}));
  assert.match(nodes.get("qc-rules").textContent, /ALL rules fail \(AND of failures\)/);
  api.renderRules(details({schema: "scagentkit.qc.rules.v1", rationale: "Combined", risks: [], remove_if: "unknown", rules: [range]}));
  assert.match(nodes.get("qc-rules").textContent, /Failure combination unavailable/);
});
test("literal scopes and exact IDs remain text with no generated image or link", () => {
  api.renderRules(details({schema: "scagentkit.qc.rules.v1", rationale: "Combined", risks: [], remove_if: "any", rules: [range]}));
  assert.match(nodes.get("qc-rules").textContent, /literal <img src=x onerror=alert\(1\)>/);
  assert.equal(descendants(nodes.get("qc-rules"), "img").length, 0);
  assert.equal(descendants(nodes.get("qc-rules"), "a").length, 0);
  assert.match(nodes.get("qc-cell-scope").textContent, /001\ncell space/);
  assert.match(nodes.get("qc-cell-scope").textContent, /NA/);
});
test("saved MAD impact rows display the predicate label and exact overlap counts", () => {
  api.renderImpacts({filter_impacts: [{id: "rule2", filter: mad, scope_cells: ["001", "NA"], scoped: 2,
    low_cells: [], low: 0, high_cells: [], high: 0, unavailable_cells: [], unavailable: 0,
    independently_removed_cells: ["NA"], independently_removed: 1, exclusively_removed_cells: [], exclusively_removed: 0}],
    overlap: {filter_ids: ["rule2"], counts: [[1]]}, patterns: [{reason_ids: ["rule2:mad_preset"],
      unavailable_filter_ids: [], retained: 0, removed: 1, cell_ids: ["NA"]}]});
  assert.match(nodes.get("qc-filter-impacts").textContent, /conservative_and3/);
  assert.match(nodes.get("qc-filter-impacts").textContent, /Independent removal/);
  assert.match(nodes.get("qc-overlap").textContent, /rule2/);
  assert.match(nodes.get("qc-patterns").textContent, /NA/);
});
test("rendering does not request previews or execute computation", () => assert.equal(requests, 0));
console.log(JSON.stringify({ok: true, passed, failed: 0, network_requests: requests}));
