#!/usr/bin/env node
/** Execute actual review.js against an inert DOM; browser/R acceptance is separate. */
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import {fileURLToPath} from "node:url";

const source = await fs.readFile(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../static/review.js"), "utf8");
assert(source.endsWith("load();\n"), "The isolated test must remove only the identifiable automatic first load");
const clone = value => JSON.parse(JSON.stringify(value));
const response = value => ({ok: true, status: 200, json: async () => value});
const proposal = (clusterId, label, markers) => ({clusterId, label, confidence: "medium", rationale: "Saved positive marker evidence; identity remains provisional.", markers});
const marker = (clusterId, gene) => ({clusterId, gene, avgLog2FC: 2.1, pct1: 0.7, pct2: 0.1, pAdj: 0.002, source: "saved test"});
function view() {
  const input = [{cell_id: "cell:A", cluster: "literal:A"}, {cell_id: "cell:B", cluster: "literal:A"}, {cell_id: "cell:C", cluster: "01"}];
  const rows = [{clusterId: "literal:A", cell_count: 2, cell_ids: ["cell:A", "cell:B"], proposal: proposal("literal:A", "T-like", ["CD3D"]), cited_marker_stats: [marker("literal:A", "CD3D")], supplied_marker_stats: [marker("literal:A", "CD3D"), marker("literal:A", "CD3E")], local_reference: {status: "not_supplied"}},
    {clusterId: "01", cell_count: 1, cell_ids: "cell:C", proposal: proposal("01", "B-like", "CD79A"), cited_marker_stats: [marker("01", "CD79A")], supplied_marker_stats: [marker("01", "CD79A")], local_reference: {status: "not_supplied"}}];
  return {schema: "scagentkit.run-review.workbench.v1", csrf_token: "local-only-review-token", run: {
    schema: "scagentkit.run.v1", project_id: "verified-project", input_hash: "a".repeat(64), revision: 5,
    status: "awaiting_review", stage: "annotation_propose", context: {species: "human", tissue: "public test"},
    pending: {kind: "annotation", hash: "b".repeat(64)},
    review_node: {kind: "annotation", project_id: "verified-project", input_hash: "a".repeat(64),
      proposal_hash: "b".repeat(64), review_hash: "c".repeat(64), expected_revision: 5,
      can_decide: true, can_revise: true, can_undo: false, decision_id: null},
    annotation_review: {schema: "scagentkit.annotation.review.v1", hash: "c".repeat(64), input_hash: "a".repeat(64),
      details: {cell_count: 3, cluster_count: 2, input_cells: input, annotations: rows,
        source: {kind: "manual"}, output_columns: {label: "reviewed"}, limitations: ["Qualitative confidence is not calibrated."]}}
  }};
}
class InertNode {
  constructor(tag = "div") {
    this.tag = tag; this.value = ""; this.children = []; this.attributes = new Map(); this.listeners = new Map(); this.dataset = {};
    this.hidden = false; this.className = ""; this.classList = {toggle() {}}; this.contentWindow = {};
    let disabled = false;
    Object.defineProperty(this, "disabled", {get: () => disabled, set: value => {disabled = Boolean(value);}});
    Object.defineProperty(this, "innerHTML", {set() {throw new Error("Review data must never become HTML source");}});
  }
  setAttribute(name, value) {
    this.attributes.set(name, String(value));
    if (name.startsWith("data-")) this.dataset[name.slice(5).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = String(value);
  }
  getAttribute(name) {return this.attributes.get(name) ?? null;}
  append(...items) {this.children.push(...items);}
  replaceChildren(...items) {this.children = [...items];}
  addEventListener(type, callback) {this.listeners.set(type, callback);}
  focus() {}
  reportValidity() {return true;}
}
function client(fetch = async () => {throw new Error("Unexpected request");}, initial = view()) {
  const nodes = new Map(), document = {getElementById(id) {
    if (!nodes.has(id)) nodes.set(id, new InertNode());
    return nodes.get(id);
  }, createElement: tag => new InertNode(tag)};
  const window = {confirm: () => true, location: {origin: "http://127.0.0.1:1"}, addEventListener() {}};
  const context = vm.createContext({document, window, fetch, console, URLSearchParams});
  // Production render/event logic executes with DOM operations made inert.
  vm.runInContext(source.slice(0, -"load();\n".length) + "\nglobalThis.reviewClient = {state, verify, request, load, buttons, dirty, draftError, basePayload, decide, edit, render, admissibleGenes};", context);
  const api = context.reviewClient; api.state.view = initial; api.verify(initial); api.render();
  return {api, nodes, context, click: id => nodes.get(id).listeners.get("click")()};
}
function disabled(c) {
  c.api.buttons();
  for (const id of ["annotation-save", "annotation-approve", "annotation-reject", "run-undo-button",
    "annotation-keep", "annotation-coarser", "annotation-unknown", "annotation-label", "annotation-confidence", "annotation-rationale"])
    assert.equal(c.nodes.get(id).disabled, true, id);
  for (const input of c.api.state.citationInputs) assert.equal(input.disabled, true, "marker citation checkbox");
  assert.equal(c.nodes.get("run-refresh").disabled, false);
}
let cases = 0, checks = 0;
async function test(name, fn) {await fn(); cases++; console.log("PASS " + name);}
const invalid = [
  ["outer schema", v => {v.schema = "foreign";}], ["run schema", v => {v.run.schema = "foreign";}],
  ["changed project", v => {v.run.project_id = "other-project";}], ["missing project", v => {delete v.run.project_id;}],
  ["changed input", v => {v.run.input_hash = "d".repeat(64);}], ["invalid input", v => {v.run.input_hash = "invalid";}],
  ["trailing newline hash", v => {v.run.input_hash += "\n"; v.run.review_node.input_hash = v.run.input_hash; v.run.annotation_review.input_hash = v.run.input_hash;}],
  ["missing token", v => {delete v.csrf_token;}], ["non-text token", v => {v.csrf_token = 7;}],
  ["fractional revision", v => {v.run.revision = 1.5;}], ["negative revision", v => {v.run.revision = -1;}],
  ["foreign node kind", v => {v.run.review_node.kind = "integration";}], ["node project", v => {v.run.review_node.project_id = "other";}],
  ["node input", v => {v.run.review_node.input_hash = "d".repeat(64);}], ["node revision", v => {v.run.review_node.expected_revision = 4;}],
  ["node review hash", v => {v.run.review_node.review_hash = "d".repeat(64);}], ["node proposal format", v => {v.run.review_node.proposal_hash = "invalid";}],
  ["record schema", v => {v.run.annotation_review.schema = "foreign";}], ["record input", v => {v.run.annotation_review.input_hash = "d".repeat(64);}],
  ["record absent", v => {delete v.run.annotation_review;}]
];
await test("20 malformed HTTP200 snapshots preserve prior view and disable every write", async () => {
  for (const [name, mutate] of invalid) {
    const bad = view(); mutate(bad); const c = client(async () => response(bad)), prior = c.api.state.view;
    await assert.rejects(c.api.request({action: "approve"}), undefined, name);
    assert.equal(c.api.state.stale, true, name); assert.equal(c.api.state.view, prior, name); disabled(c); checks++;
  }
});
const invalidScope = [
  ["duplicate cluster", d => {d.annotations[1].clusterId = d.annotations[0].clusterId; d.annotations[1].proposal.clusterId = d.annotations[0].clusterId;}],
  ["proposal cluster mismatch", d => {d.annotations[0].proposal.clusterId = "different";}],
  ["cell count mismatch", d => {d.annotations[0].cell_count = 1;}], ["fractional cell count", d => {d.annotations[0].cell_count = 1.5;}],
  ["empty cell ID", d => {d.annotations[0].cell_ids[0] = "";}], ["cell ID scalar type", d => {d.annotations[0].cell_ids[0] = 7;}],
  ["duplicate cell within cluster", d => {d.annotations[0].cell_ids[1] = d.annotations[0].cell_ids[0];}],
  ["duplicate cell across clusters", d => {d.annotations[1].cell_ids = "cell:A";}],
  ["total cell count", d => {d.cell_count = 4;}], ["total cluster count", d => {d.cluster_count = 1;}],
  ["missing input membership", d => {d.input_cells.pop();}], ["foreign input membership", d => {d.input_cells[0].cell_id = "foreign";}],
  ["different input cluster", d => {d.input_cells[0].cluster = "01";}], ["duplicate input membership", d => {d.input_cells[1] = {...d.input_cells[0]};}],
  ["proposal label scalar", d => {d.annotations[0].proposal.label = {text: "T"};}], ["blank label", d => {d.annotations[0].proposal.label = " ";}],
  ["proposal rationale scalar", d => {d.annotations[0].proposal.rationale = 1;}], ["empty rationale", d => {d.annotations[0].proposal.rationale = "";}],
  ["unsupported confidence", d => {d.annotations[0].proposal.confidence = "certain";}],
  ["cited gene scalar", d => {d.annotations[0].proposal.markers = [{gene: "CD3D"}];}], ["empty cited gene", d => {d.annotations[0].proposal.markers = [""];}]
];
await test("21 inconsistent exact scopes and proposal scalar fields fail closed", async () => {
  for (const [name, mutate] of invalidScope) {
    const bad = view(); mutate(bad.run.annotation_review.details); const c = client(async () => response(bad));
    await assert.rejects(c.api.request(), undefined, name); assert.equal(c.api.state.stale, true, name); disabled(c); checks++;
  }
});
for (const [name, fetch] of [
  ["network", async () => {throw new Error("disconnected");}],
  ["JSON", async () => ({ok: true, status: 200, json: async () => {throw new Error("truncated");}})],
  ["HTTP409", async () => ({ok: false, status: 409, json: async () => ({error: "Stale saved review"})})]
]) await test("GET " + name + " failure disables writes without discarding the saved view", async () => {
  const c = client(fetch), prior = c.api.state.view; await c.api.load();
  assert.equal(c.api.state.stale, true); assert.equal(c.api.state.view, prior); disabled(c); checks++;
});
await test("failed refresh remains disabled; only verified fresh load restores permitted actions", async () => {
  let next = response({...view(), schema: "foreign"}); const c = client(async () => next);
  await c.api.load(); disabled(c); await c.api.load(); disabled(c);
  next = response(view()); await c.api.load(); assert.equal(c.api.state.stale, false);
  assert.equal(c.nodes.get("annotation-approve").disabled, false); assert.equal(c.nodes.get("annotation-reject").disabled, false);
  assert.equal(c.nodes.get("annotation-save").disabled, true); assert.equal(c.nodes.get("run-undo-button").disabled, true); checks++;
});
await test("a verified request alone never clears an already stale page", async () => {
  const c = client(async () => response(view())); c.api.state.stale = true;
  await c.api.request(); assert.equal(c.api.state.stale, true); disabled(c); checks++;
});
await test("dirty corrections disable approve and need a changed nonempty cluster reason", async () => {
  const c = client(), original = JSON.stringify(c.api.state.view), row = c.api.state.drafts.get("literal:A");
  row.label = "Coarser T lineage"; c.api.buttons(); assert.equal(c.api.dirty(), true);
  assert.equal(c.nodes.get("annotation-approve").disabled, true); assert.equal(c.nodes.get("annotation-save").disabled, true);
  assert.match(c.api.draftError(), /reason/);
  row.rationale = "  "; assert.match(c.api.draftError(), /reason/);
  row.rationale = "Independent evidence is insufficient for a finer subtype.";
  c.api.buttons(); assert.equal(c.api.draftError(), null); assert.equal(c.nodes.get("annotation-save").disabled, false);
  assert.equal(c.nodes.get("annotation-approve").disabled, true); assert.equal(JSON.stringify(c.api.state.view), original); checks++;
});
await test("Unknown edits local draft only; empty citations and low confidence need a reason", async () => {
  let requests = 0; const c = client(async () => {requests++; throw new Error("Unexpected write");}), original = JSON.stringify(c.api.state.view);
  c.click("annotation-unknown"); const row = c.api.state.drafts.get("literal:A");
  assert.equal(row.label, "Unknown"); assert.equal(row.confidence, "low"); assert.deepEqual(Array.from(row.markers), []);
  assert.equal(row.rationale, ""); assert.equal(c.nodes.get("annotation-save").disabled, true);
  assert.equal(JSON.stringify(c.api.state.view), original); assert.equal(requests, 0); checks++;
});
await test("Keep restores the original saved proposal and reenables clean approval", async () => {
  const c = client(), original = clone(c.api.state.view.run.annotation_review.details.annotations[0].proposal);
  c.click("annotation-unknown"); c.click("annotation-keep");
  assert.deepEqual(clone(c.api.state.drafts.get("literal:A")), original);
  assert.equal(c.api.state.citationInputs[0].getAttribute("data-marker-gene"), "CD3D");
  assert.equal(c.api.state.citationInputs[0].checked, true); assert.equal(c.api.state.citationInputs[1].checked, false);
  assert.equal(c.api.dirty(), false); assert.equal(c.nodes.get("annotation-approve").disabled, false); checks++;
});
await test("Unknown to known needs an explicit supplied citation; checkbox edits only local draft", async () => {
  let requests = 0; const c = client(async () => {requests++; throw new Error("Unexpected write");}), saved = JSON.stringify(c.api.state.view);
  c.click("annotation-unknown"); c.nodes.get("annotation-label").value = "Coarse T lineage";
  c.nodes.get("annotation-rationale").value = "Only a coarse identity is supported by the reviewed supplied evidence."; c.api.edit();
  assert.match(c.api.draftError(), /supporting citation/); assert.equal(c.nodes.get("annotation-save").disabled, true);
  const input = c.api.state.citationInputs[0]; input.checked = true; input.listeners.get("change")();
  assert.deepEqual(Array.from(c.api.state.drafts.get("literal:A").markers), ["CD3D"]);
  assert.equal(c.api.draftError(), null); assert.equal(c.nodes.get("annotation-save").disabled, false);
  assert.equal(c.nodes.get("annotation-approve").disabled, true); assert.equal(JSON.stringify(c.api.state.view), saved);
  assert.equal(requests, 0); checks++;
});
await test("citation choices are unique literal supplied genes from the selected cluster", async () => {
  const initial = view(), stats = initial.run.annotation_review.details.annotations[0].supplied_marker_stats;
  stats.push(marker("literal:A", "CD3D"), marker("literal:A", "GENE.with|literal"));
  const c = client(undefined, initial), saved = JSON.stringify(c.api.state.view);
  assert.deepEqual(Array.from(c.api.admissibleGenes({supplied_marker_stats: [{gene: "CD3D"}, {gene: "CD3D"}, {gene: 7}, {gene: null}, {gene: ""}, {gene: "GENE.with|literal"}]})), ["CD3D", "GENE.with|literal"]);
  assert.deepEqual(Array.from(c.api.state.citationInputs, input => input.getAttribute("data-marker-gene")), ["CD3D", "CD3E", "GENE.with|literal"]);
  for (const input of c.api.state.citationInputs) input.checked = true;
  c.api.state.citationInputs[2].listeners.get("change")();
  assert.deepEqual(Array.from(c.api.state.drafts.get("literal:A").markers), ["CD3D", "CD3E", "GENE.with|literal"]);
  assert.equal(JSON.stringify(c.api.state.view), saved); checks++;
});
await test("foreign cluster citations are rejected for both known and Unknown local drafts", async () => {
  const c = client(), saved = JSON.stringify(c.api.state.view), row = c.api.state.drafts.get("literal:A");
  row.markers = ["CD79A"]; row.rationale = "Explicit correction reason.";
  assert.match(c.api.draftError(), /exact cluster/); row.label = "Unknown";
  assert.match(c.api.draftError(), /exact cluster/); c.api.buttons(); assert.equal(c.nodes.get("annotation-save").disabled, true);
  assert.equal(JSON.stringify(c.api.state.view), saved); checks++;
});
await test("saved known labels need same-cluster citations; Unknown cannot smuggle foreign genes", async () => {
  for (const mutate of [row => {row.proposal.markers = [];}, row => {row.proposal.markers = ["CD79A"];}, row => {row.proposal.label = "Unknown"; row.proposal.markers = ["FOREIGN"]; }]) {
    const bad = view(); mutate(bad.run.annotation_review.details.annotations[0]); const c = client(async () => response(bad));
    await assert.rejects(c.api.request()); assert.equal(c.api.state.stale, true); disabled(c); checks++;
  }
});
await test("a verified Unknown proposal allows empty citations without inventing evidence", async () => {
  const initial = view(), row = initial.run.annotation_review.details.annotations[0];
  row.proposal.label = "Unknown"; row.proposal.confidence = "low"; row.proposal.markers = []; row.cited_marker_stats = [];
  const c = client(undefined, initial); assert.equal(c.api.draftError(), null); assert.equal(c.api.dirty(), false);
  assert.equal(c.nodes.get("annotation-approve").disabled, false); assert.equal(c.api.state.citationInputs.some(input => input.checked), false); checks++;
});
await test("a coarser label requires explicit editing and does not rewrite the saved state", async () => {
  const c = client(), original = JSON.stringify(c.api.state.view); c.click("annotation-coarser");
  assert.equal(c.api.state.drafts.get("literal:A").label, "T-like"); assert.equal(c.api.state.drafts.get("literal:A").rationale, "");
  assert.equal(c.nodes.get("annotation-save").disabled, true); assert.equal(JSON.stringify(c.api.state.view), original); checks++;
});
await test("dirty approval cannot dispatch HTTP even when called directly", async () => {
  let requests = 0; const c = client(async () => {requests++; throw new Error("Unexpected write");});
  c.api.state.drafts.get("literal:A").label = "Unknown"; await c.api.decide("approve");
  assert.equal(requests, 0); assert.match(c.nodes.get("run-message").textContent, /Save corrections/); checks++;
});
await test("literal cluster ID and snapshot fingerprints enter only the typed local payload", async () => {
  const c = client(); const payload = clone(c.api.basePayload("approve", "analyst", "Reviewed scope"));
  assert.deepEqual(payload, {action: "approve", kind: "annotation", project_id: "verified-project", input_hash: "a".repeat(64),
    proposal_hash: "b".repeat(64), review_hash: "c".repeat(64), expected_revision: 5, reviewer: "analyst", reason: "Reviewed scope"});
  assert.deepEqual(Array.from(c.api.state.drafts.keys()), ["literal:A", "01"]); checks++;
});
await test("completed undo is enabled only by the verified node and carries its decision ID", async () => {
  const complete = view(); complete.run.status = "complete"; complete.run.stage = "complete";
  Object.assign(complete.run.review_node, {can_decide: false, can_revise: false, can_undo: true, decision_id: "executed-decision"});
  let sent; const c = client(async (route, options) => {assert.equal(route, "/api/run-review/decision"); sent = JSON.parse(options.body); return response(complete);}, complete);
  assert.equal(c.nodes.get("annotation-approve").disabled, true); assert.equal(c.nodes.get("run-undo-button").disabled, false);
  c.nodes.get("run-undo-reviewer").value = "analyst"; c.nodes.get("run-undo-reason").value = "Reopen for a corrected proposal";
  await c.api.decide("undo"); assert.equal(sent.action, "undo"); assert.equal(sent.decision_id, "executed-decision");
  assert.equal(sent.review_hash, complete.run.review_node.review_hash); checks++;
});
await test("HTML, JS and R-looking text stays literal; no automatic provider or decision request", async () => {
  const literal = "<script>globalThis.executed = true</script> $(touch /not-executed); source('unknown.R')";
  const initial = view(); initial.run.annotation_review.details.annotations[0].proposal.label = literal;
  initial.run.annotation_review.details.annotations[0].proposal.rationale = literal;
  let requests = 0; const c = client(async () => {requests++; throw new Error("Unexpected request");}, initial);
  assert.equal(c.nodes.get("annotation-suggestion").children[0].textContent, literal);
  assert.equal(c.nodes.get("annotation-rationale").value, literal); assert.equal(c.context.executed, undefined);
  assert.equal(requests, 0); checks++;
});
console.log(`${cases} client cases / ${checks} focused checks passed; no GUI, R or external API calls`);
