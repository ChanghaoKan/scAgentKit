#!/usr/bin/env node
// Actual standalone presentation helper, tested with an inert DOM. No service,
// provider, scientific runtime, or native browser is involved in these tests.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import {fileURLToPath} from "node:url";

const filename = fileURLToPath(import.meta.url);
const root = path.resolve(path.dirname(filename), "..");
const sourcePath = path.join(root, "static/evidence-display.js");
const source = fs.readFileSync(sourcePath, "utf8");
const geneSource = fs.readFileSync(path.join(root, "static/gene-links.js"), "utf8");
const mapSource = fs.readFileSync(path.join(root, "static/ortholog-map.js"), "utf8");
const results = [];
let networkRequests = 0, windowAccesses = 0, htmlParses = 0;
class Element {
  constructor(tag, namespace = null) {this.tagName = tag.toUpperCase(); this.namespaceURI = namespace; this.children = []; this.attributes = {}; this.text = ""; this.listeners = {}; this.style = {};}
  set textContent(value) {this.text = String(value ?? ""); this.children = [];}
  get textContent() {return this.text + this.children.map(child => child.textContent ?? String(child)).join("");}
  set innerHTML(_) {htmlParses++; throw new Error("Evidence must remain literal text");}
  set outerHTML(_) {htmlParses++; throw new Error("Evidence must remain literal text");}
  insertAdjacentHTML() {htmlParses++; throw new Error("Evidence must remain literal text");}
  setAttribute(name, value) {this.attributes[name] = String(value);}
  getAttribute(name) {return this.attributes[name] ?? null;}
  append(...values) {this.children.push(...values);}
  replaceChildren(...values) {this.text = ""; this.children = values;}
  addEventListener(name, callback) {(this.listeners[name] ||= []).push(callback);}
  emit(name) {for (const callback of this.listeners[name] || []) callback({target: this});}
}
const descendants = value => [value, ...(value.children || []).flatMap(descendants)];
const tags = (target, tag) => descendants(target).filter(value => value.tagName === tag.toUpperCase());
const testid = (target, id) => descendants(target).find(value => value.getAttribute?.("data-testid") === id);
const freeze = value => {if (value && typeof value === "object") {Object.freeze(value); Object.values(value).forEach(freeze);} return value;};
const copy = value => JSON.parse(JSON.stringify(value));
function setup(withGenes = false) {
  const document = {createElement: tag => new Element(tag), createElementNS: (namespace, tag) => new Element(tag, namespace), createTextNode: text => ({textContent: String(text)})};
  const forbiddenRequest = () => {networkRequests++; throw new Error("Display must not request data or POST a selection");};
  const sandbox = {document, fetch: forbiddenRequest, XMLHttpRequest: forbiddenRequest, WebSocket: forbiddenRequest, navigator: {sendBeacon: forbiddenRequest}};
  Object.defineProperty(sandbox, "window", {get() {windowAccesses++; throw new Error("Display must not access a browser window");}});
  const context = vm.createContext(sandbox);
  if (withGenes) {vm.runInContext(mapSource, context, {filename: "ortholog-map.js"}); vm.runInContext(geneSource, context, {filename: "gene-links.js"});}
  vm.runInContext(source, context, {filename: "evidence-display.js"});
  return {api: context.ScEvidenceDisplay, context, target: new Element("div")};
}
function check(name, action) {
  try {action(); results.push({name, passed: true});}
  catch (error) {results.push({name, passed: false, error: error.stack});}
}
const points = () => [
  {cellId: "cell:A", clusterId: "01", x: -2, y: -5},
  {cellId: "cell:B", clusterId: "1", x: 8, y: 15},
  {cellId: "cell:C", clusterId: "0", x: 3, y: 5}
];
const clusters = () => [{id: "01", cellCount: 1}, {id: "1", cellCount: 1}, {id: "0", cellCount: 1}];
const marker = () => ({gene: "CD3D", avgLog2FC: 1.23456789012345, pct1: .700000000000001, pct2: .100000000000002, pctDiff: 0, pAdj: 1.23456789123456e-105, source: "saved original source"});
const cells = target => tags(target, "tbody")[0]?.children.map(row => row.children.map(cell => cell.textContent)) || [];

check("standalone API exposes only two frozen display functions", () => {
  const {api, context} = setup();
  assert.deepEqual(Object.keys(api), ["embedding", "markers"]); assert.equal(Object.isFrozen(api), true);
  assert.equal(typeof api.embedding, "function"); assert.equal(typeof api.markers, "function");
  assert.throws(() => vm.runInContext('"use strict"; ScEvidenceDisplay.markers = null;', context), /read only|readonly|Cannot assign/i);
  assert.doesNotMatch(source, /\b(?:fetch|XMLHttpRequest|WebSocket|sendBeacon|window|innerHTML|outerHTML|insertAdjacentHTML)\b/);
});
check("SVG matches existing 640 by 350 geometry and supplied coordinate bounds", () => {
  const {api, target} = setup(); api.embedding(target, {points: points(), clusters: clusters(), name: "UMAP", title: "Saved project", selectedCluster: "01"});
  const svg = tags(target, "svg")[0], circles = tags(target, "circle");
  assert.equal(svg.namespaceURI, "http://www.w3.org/2000/svg"); assert.equal(svg.getAttribute("viewBox"), "0 0 640 350");
  const byId = new Map(circles.map(circle => [circle.getAttribute("data-cell-id"), circle]));
  assert.deepEqual([byId.get("cell:A").getAttribute("cx"), byId.get("cell:A").getAttribute("cy")], ["47", "304"]);
  assert.deepEqual([byId.get("cell:B").getAttribute("cx"), byId.get("cell:B").getAttribute("cy")], ["593", "40"]);
  assert.deepEqual([byId.get("cell:C").getAttribute("cx"), byId.get("cell:C").getAttribute("cy")], ["320", "172"]);
  assert.deepEqual(tags(target, "line").map(line => ["x1", "y1", "x2", "y2"].map(key => line.getAttribute(key))), [["38", "312", "602", "312"], ["38", "38", "38", "312"]]);
  assert.equal(circles.at(-1).getAttribute("data-cluster"), "01"); assert.equal(tags(svg, "title")[0].textContent, "Saved project");
  assert.match(testid(target, "embedding-detail").textContent, /Actual exported coordinates/);
});
check("default showAll colors every supplied cluster without a selection", () => {
  const {api, target} = setup(); api.embedding(target, {points: points(), clusters: clusters()});
  assert.deepEqual(tags(target, "circle").map(circle => circle.getAttribute("fill")), ["#759bd1", "#e4a675", "#73b3aa"]);
  assert(tags(target, "circle").every(circle => circle.getAttribute("r") === "1.6"));
  assert.equal(tags(target, "svg")[0].getAttribute("aria-label"), "Real Embedding: 3 cells");
});
check("showAll false greys other clusters without removing points or changing bounds", () => {
  const {api, target} = setup(); api.embedding(target, {points: points(), clusters: clusters(), selectedCluster: "01", showAll: false});
  const circles = tags(target, "circle"); assert.equal(circles.length, 3);
  assert.deepEqual(circles.map(circle => circle.getAttribute("fill")), ["#dce2ed", "#dce2ed", "#759bd1"]);
  assert.deepEqual(circles.map(circle => circle.getAttribute("r")), ["1.6", "1.6", "2.05"]);
  assert.deepEqual(circles.map(circle => circle.getAttribute("opacity")), ["0.72", "0.72", "0.9"]);
  assert.equal(circles[0].getAttribute("cx"), "593"); assert.equal(testid(target, "embedding-legend").children.length, 3);
});
check("literal cell and cluster IDs survive with only a local selection callback", () => {
  const {api, target} = setup(), ids = ["0", "01", "1", "NA", " T alpha ", "簇-α", '<svg onload="never()">', 0];
  const supplied = freeze(ids.map((id, index) => ({cellId: ` cell / ${index} `, clusterId: id, x: index, y: index})));
  const selected = []; api.embedding(target, {points: supplied, clusters: freeze(ids.map(id => ({id}))), selectedCluster: "01", onSelect: id => selected.push(id)});
  const circles = tags(target, "circle"); circles.forEach(circle => circle.emit("click"));
  assert.deepEqual(selected, ids.filter(id => id !== "01").concat("01"));
  assert.deepEqual(circles.map(circle => circle.getAttribute("data-cell-id")), [" cell / 0 ", " cell / 2 ", " cell / 3 ", " cell / 4 ", " cell / 5 ", " cell / 6 ", " cell / 7 ", " cell / 1 "]);
  assert.equal(circles.filter(circle => circle.getAttribute("r") === "2.05").length, 1);
  assert.equal(networkRequests, 0);
});
check("rendering and selection never mutate the supplied arrays or records", () => {
  const {api, target} = setup(), supplied = freeze(points()), groups = freeze(clusters()), before = copy({supplied, groups});
  api.embedding(target, {points: supplied, clusters: groups, selectedCluster: "01", onSelect() {}}); tags(target, "circle")[0].emit("click");
  assert.deepEqual({supplied, groups}, before);
});
check("missing and empty coordinates replace a previous chart with explicit unavailable", () => {
  const {api, target} = setup(); api.embedding(target, {points: points(), clusters: clusters()});
  for (const supplied of [undefined, null, [], {}]) {
    api.embedding(target, {points: supplied, clusters: clusters()}); assert.equal(tags(target, "svg").length, 0);
    assert.match(testid(target, "embedding-unavailable").textContent, /Embedding unavailable.*No coordinates were supplied/);
    assert.equal(testid(target, "embedding-legend"), undefined);
  }
});
check("invalid coordinates are never coerced, filtered, or substituted", () => {
  const {api, target} = setup();
  for (const bad of [{x: NaN}, {x: Infinity}, {x: "3"}, {x: null}, {y: undefined}, {cellId: null}, {clusterId: {id: "01"}}]) {
    api.embedding(target, {points: [...points(), {...points()[0], ...bad}], clusters: clusters()});
    assert.equal(tags(target, "circle").length, 0); assert.match(testid(target, "embedding-unavailable").textContent, /invalid.*no coordinates have been generated/s);
  }
  api.embedding(target, {points: [{cellId: "a", clusterId: "0", x: -1e308, y: 0}, {cellId: "b", clusterId: "0", x: 1e308, y: 0}]});
  assert.equal(tags(target, "circle").length, 0); assert.match(testid(target, "embedding-unavailable").textContent, /coordinate range cannot be displayed/);
});
check("singleton and equal coordinate bounds use the existing deterministic scale", () => {
  const {api, target} = setup();
  for (const supplied of [[{cellId: "a", clusterId: "0", x: 9, y: -4}], [{cellId: "a", clusterId: "0", x: 9, y: -4}, {cellId: "b", clusterId: "0", x: 9, y: -4}]]) {
    api.embedding(target, {points: supplied, clusters: [{id: "0"}]});
    assert(tags(target, "circle").every(circle => circle.getAttribute("cx") === "47" && circle.getAttribute("cy") === "304"));
  }
});
check("large supplied embeddings render every actual point without spread limits", () => {
  const {api, target} = setup(), supplied = Array.from({length: 140000}, (_, index) => ({cellId: `c${index}`, clusterId: "large", x: index, y: index % 31}));
  api.embedding(target, {points: supplied, clusters: [{id: "large", cellCount: supplied.length}]});
  const chart = testid(target, "embedding-chart"), svg = chart.children[0], circles = svg.children.filter(value => value.tagName === "CIRCLE");
  assert.equal(circles.length, supplied.length); assert.equal(circles[0].getAttribute("data-cell-id"), "c0"); assert.equal(circles.at(-1).getAttribute("data-cell-id"), "c139999");
});
check("embedding titles, literal IDs and supplied source labels remain safe text", () => {
  const {api, target} = setup(), literal = '<img src=x onerror="never()">';
  api.embedding(target, {points: [{cellId: literal, clusterId: literal, x: 0, y: 0}], clusters: [{id: literal, cellCount: 0, sourceLabels: [{value: literal, count: 0}]}], name: literal, title: literal, selectedCluster: literal});
  assert.equal(tags(target, "img").length, 0); assert.equal(tags(target, "script").length, 0);
  assert.equal(tags(target, "circle")[0].getAttribute("data-cluster"), literal); assert.equal(testid(target, "embedding-title").textContent, literal);
  assert.match(testid(target, "embedding-legend").textContent, /0 cells/); assert(testid(target, "embedding-legend").textContent.includes(JSON.stringify([{value: literal, count: 0}])));
});
check("undeclared point clusters receive neutral display without invented metadata", () => {
  const {api, target} = setup(); api.embedding(target, {points: points()});
  assert(tags(target, "circle").every(circle => circle.getAttribute("fill") === "#dce2ed")); assert.equal(testid(target, "embedding-legend").children.length, 0);
});
check("markers preserve every original numerical value and all seven existing columns", () => {
  const {api, target} = setup(), supplied = freeze([marker()]); api.markers(target, supplied, {species: "human"});
  assert.deepEqual(tags(target, "th").map(cell => cell.textContent), ["Gene", "avg log2FC", "pct.1", "pct.2", "Δ detection (supplied)", "Adjusted p", "Source"]);
  assert.deepEqual(cells(target)[0], Object.values(marker()).map(String)); assert.equal(tags(target, "a").length, 0);
  assert.equal(cells(target)[0][4], "0"); assert.equal(cells(target)[0][5], "1.23456789123456e-105");
});
check("marker table renders all supplied rows beyond thirty in original order", () => {
  const {api, target} = setup(), supplied = freeze(Array.from({length: 137}, (_, index) => ({...marker(), gene: `literal:${index}`})));
  api.markers(target, supplied); const rendered = cells(target); assert.equal(rendered.length, 137);
  assert.deepEqual(rendered.map(row => row[0]), supplied.map(row => row.gene)); assert.match(target.textContent, /Showing all 137 supplied marker rows/);
  assert.deepEqual(supplied[0], {...marker(), gene: "literal:0"});
});
check("missing statistics are explicit and do not synthesize a detection difference", () => {
  const {api, target} = setup(); api.markers(target, [{gene: "literal", avgLog2FC: null, pct1: .9, pct2: .2, pAdj: 0, source: ""}]);
  assert.deepEqual(cells(target)[0], ["literal", "—", "0.9", "0.2", "—", "0", ""]);
});
check("original numeric strings, structured sources, zero sources and extra columns survive", () => {
  const {api, target} = setup(), originalSource = {kind: "supplied", method: "literal", version: "1", url: "https://example.invalid/source"};
  api.markers(target, [{...marker(), pAdj: "0.00000000100", source: originalSource, pVal: 5e-107, rank: 0}, {...marker(), source: 0, pVal: null, rank: "01"}]);
  assert.deepEqual(tags(target, "th").slice(-2).map(cell => cell.textContent), ["pVal", "rank"]);
  assert.deepEqual(cells(target).map(row => row.slice(5)), [["0.00000000100", JSON.stringify(originalSource), "5e-107", "0"], [String(marker().pAdj), "0", "—", "01"]]);
  assert.equal(tags(target, "a").length, 0);
});
check("empty marker data explicitly states unavailable and replaces stale rows", () => {
  const {api, target} = setup(); api.markers(target, [marker()]);
  for (const supplied of [undefined, null, [], {}]) {api.markers(target, supplied); assert.equal(tags(target, "table").length, 0); assert.match(testid(target, "markers-unavailable").textContent, /No marker table.*No expression absence/);}
});
check("without the gene helper symbols and sources are inert literal text", () => {
  const {api, target} = setup(), literal = '<img src=x onerror="never()">';
  api.markers(target, [{...marker(), gene: literal, source: {literal}, [literal]: literal}], {species: "human"});
  assert.equal(cells(target)[0][0], literal); assert.equal(cells(target)[0][6], JSON.stringify({literal}));
  assert.equal(tags(target, "a").length, 0); assert.equal(tags(target, "img").length, 0); assert.equal(tags(target, "script").length, 0); assert.equal(tags(target, "th").at(-1).textContent, literal);
});
check("human marker links delegate exact symbols to the existing GeneCards helper", () => {
  const {api, target} = setup(true), gene = 'A/B?x=1&y=2#anchor% \"\'()!*';
  api.markers(target, [{...marker(), gene}], {species: "Homo sapiens"});
  const anchor = tags(target, "a")[0], href = new URL(anchor.getAttribute("href"));
  assert.equal(anchor.textContent, gene); assert.equal(href.origin, "https://www.genecards.org"); assert.equal(href.search, ""); assert.equal(href.hash, ""); assert.equal(decodeURIComponent(href.pathname.slice("/card/".length)), gene);
  assert.equal(anchor.getAttribute("target"), "_blank"); assert.equal(anchor.getAttribute("rel"), "noopener noreferrer"); assert.equal(anchor.getAttribute("referrerpolicy"), "no-referrer");
  assert.match(testid(target, "marker-gene-links-note").textContent, /only when a gene is clicked/); assert.equal(networkRequests, 0);
});
check("missing or unsupported species never infer species from a source", () => {
  const {api, target} = setup(true);
  for (const species of [undefined, null, "", "rat"]) {
    api.markers(target, [{...marker(), gene: "Cd3d", source: {species: "human"}}], {species}); assert.equal(tags(target, "a").length, 0);
    assert(target.textContent.includes("Cd3d")); assert.match(target.textContent, /no GeneCards mapping/);
  }
});
check("declared mouse uses exact offline mappings and preserves original marker statistics", () => {
  const {api, target} = setup(true);
  for (const species of ["mouse", "Mus musculus", "10090"]) {
    for (const [gene, humans, mgi] of [["Lyz2", ["LYZ"], "MGI:96897"], ["Adh1", ["ADH1A", "ADH1B", "ADH1C"], "MGI:87921"], ["Lysm", ["LYZ"], "MGI:96897"]]) {
      const input = freeze([{...marker(), gene}]); api.markers(target, input, {species}); const anchors = tags(target, "a");
      assert.equal(anchors.length, humans.length + 1); assert.equal(anchors[0].getAttribute("href"), "https://www.informatics.jax.org/accession/" + encodeURIComponent(mgi));
      assert.deepEqual(anchors.slice(1).map(node => node.getAttribute("data-gene-symbol")), humans);
      assert.equal(input[0].gene, gene); assert(target.textContent.includes(gene)); assert(target.textContent.includes("1.23456789012345"));
    }
    api.markers(target, [{...marker(), gene: "LysM"}], {species}); assert.equal(tags(target, "a").length, 0); assert.match(target.textContent, /no ortholog absence inferred/);
  }
  assert.equal(networkRequests, 0);
});
check("HTML-looking human and mouse gene symbols remain safe literal text", () => {
  const {api, target} = setup(true), gene = '<svg onload="never()">';
  for (const species of ["human", "mouse"]) {
    api.markers(target, [{...marker(), gene, source: gene}], {species}); assert.equal(tags(target, "svg").length, 0); assert.equal(tags(target, "script").length, 0); assert(target.textContent.includes(gene));
    assert.equal(tags(target, "a").length, species === "human" ? 1 : 0);
    if (species === "human") assert.equal(new URL(tags(target, "a")[0].getAttribute("href")).origin, "https://www.genecards.org");
  }
});
check("render and refresh with links do not make requests or attach marker selection actions", () => {
  const {api, target} = setup(true), calls = [];
  for (let index = 0; index < 3; index++) {
    api.embedding(target, {points: points(), clusters: clusters(), selectedCluster: "01", onSelect: id => calls.push(id)});
    tags(target, "circle")[0].emit("click"); api.markers(target, [marker()], {species: "human"});
    tags(target, "a")[0].emit("click"); assert(tags(target, "tr").every(row => !Object.keys(row.listeners).length));
  }
  assert.deepEqual(calls, ["1", "1", "1"]); assert.equal(networkRequests, 0); assert.equal(windowAccesses, 0); assert.equal(htmlParses, 0);
});

const sha = filename => crypto.createHash("sha256").update(fs.readFileSync(filename)).digest("hex");
const report = {schema: "scagentkit.evidence-display.offline-dom-tests.v1", actualProductionSource: true, actualBrowser: false, actualRBridge: false, networkRequests, providerRequests: 0, RProcesses: 0, paidAPICalls: 0, windowAccesses, htmlParses, sourceSha256: sha(sourcePath), mappingSha256: sha(path.join(root, "static/ortholog-map.js")), driverSha256: sha(filename), tests: results.length, passed: results.filter(row => row.passed).length, failed: results.filter(row => !row.passed).length, results};
if (process.argv[2]) fs.writeFileSync(path.resolve(process.argv[2]), JSON.stringify(report, null, 2) + "\n");
process.stdout.write(JSON.stringify(report, null, 2) + "\n");
if (report.failed) process.exitCode = 1;
