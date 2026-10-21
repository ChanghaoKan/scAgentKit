#!/usr/bin/env node
// Exercise the production project selector with local response fixtures.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import {fileURLToPath} from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const app = fs.readFileSync(path.join(root, "static/app.js"), "utf8");
assert.match(app, /\nload\(\);\s*$/);
class Element {
  constructor(tag) {this.tagName = tag; this.children = []; this.attributes = {}; this.hidden = false;}
  setAttribute(name, value) {this.attributes[name] = value;}
  append(...children) {this.children.push(...children);}
  replaceChildren(...children) {this.children = children;}
  addEventListener() {}
}
const keyA = "a".repeat(64), keyB = "b".repeat(64), requests = [], elements = new Map();
const storage = new Map([["scagentkit.project", keyA]]);
let response;
const context = vm.createContext({
  document: {
    getElementById(id) {if (!elements.has(id)) elements.set(id, new Element("div")); return elements.get(id);},
    createElement(tag) {return new Element(tag);}, querySelectorAll() {return [];}
  },
  window: {addEventListener() {}},
  sessionStorage: {getItem(key) {return storage.get(key);}, setItem(key, value) {storage.set(key, value);}, removeItem(key) {storage.delete(key);}},
  async fetch(url, options) {
    assert.equal(url, "/api/projects"); requests.push({url, options});
    return {ok: true, status: 200, async json() {return response;}};
  }
});
vm.runInContext(app.replace(/\nload\(\);\s*$/, "\n"), context);
const read = expression => vm.runInContext(expression, context);
let passed = 0;
async function test(name, action) {await action(); passed++; console.log("PASS " + name);}

await test("unavailable registry hides controls and clears a remembered project binding", async () => {
  response = {registry_available: false, projects: [], selected: null};
  await read("refreshProjects()");
  assert.equal(read("state.registryAvailable"), false);
  assert.equal(read("state.selectedProject"), null);
  assert.equal(storage.has("scagentkit.project"), false);
  assert.equal(elements.get("project-controls").hidden, true);
  assert.equal(requests.at(-1).options.headers["X-ScAgentKit-Project"], undefined);
});
await test("available registry displays verified choices and selects the server snapshot", async () => {
  response = {registry_available: true, projects: [{key: keyA, displayName: "Study A"}, {key: keyB, displayName: "Study B"}], selected: keyB};
  await read("refreshProjects()");
  assert.equal(read("state.registryAvailable"), true);
  assert.equal(read("state.selectedProject"), keyB);
  assert.equal(storage.get("scagentkit.project"), keyB);
  assert.equal(elements.get("project-controls").hidden, false);
  assert.deepEqual(elements.get("project-select").children.map(option => [option.attributes.value, option.textContent, option.selected]), [[keyA, "Study A", false], [keyB, "Study B", true]]);
});
await test("verified evidence binds this tab even when another server snapshot is selected", async () => {
  read(`state.evidence = {sourceFingerprint: "source", revision: "${keyA}"}`);
  await read("refreshProjects()");
  assert.equal(read("state.selectedProject"), keyA);
  assert.equal(elements.get("project-select").children[0].selected, true);
});
await test("an unavailable saved snapshot keeps explicit replacement controls visible", async () => {
  response = {registry_available: true, projects: [{key: keyB, displayName: "Study B"}], selected: keyB};
  await read("refreshProjects()");
  assert.equal(read("state.selectedProject"), keyA);
  assert.equal(elements.get("project-controls").hidden, false);
  assert.match(elements.get("project-select").children.at(-1).textContent, /Saved snapshot unavailable/);
});
await test("only an explicit current capability flag enables project controls", async () => {
  for (const flag of [undefined, null, 1, "true", false]) {
    response = {registry_available: flag, projects: [], selected: keyA};
    await read("refreshProjects()");
    assert.equal(read("state.registryAvailable"), false);
    assert.equal(read("state.selectedProject"), null);
    assert.equal(elements.get("project-controls").hidden, true);
  }
});
console.log(JSON.stringify({schema: "scagentkit.project-registry.dom-tests.v1", passed, failed: 0, externalRequests: 0}));
