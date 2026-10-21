"use strict";
const {qcPreviewFixture} = require("./qc_fixture.cjs");
// Actual production-source offline DOM tests; no browser, R, provider or network.
const fs = require("node:fs"), path = require("node:path"), vm = require("node:vm");
const assert = require("node:assert/strict"), {webcrypto, createHash} = require("node:crypto");
const repo = path.resolve(__dirname, "../.."), sourcePath = path.join(repo, "inst/workbench/static/review.js"), htmlPath = path.join(repo, "inst/workbench/static/review.html");
const results = [];
class Element {
  constructor(tag = "div") {this.tagName = tag.toUpperCase(); this.children = []; this.attributes = {}; this.dataset = {}; this.value = ""; this._text = ""; this.hidden = false; this.disabled = false; this.inert = false; this.listeners = {}; this.contentWindow = {}; this.className = ""; this.open = false; this.classList = {toggle() {}};}
  get textContent() {return this._text + this.children.map(child => child instanceof Element ? child.textContent : String(child)).join("");}
  set textContent(value) {this._text = String(value ?? ""); this.children = [];}
  get innerHTML() {throw new Error("Evidence rendering must not access innerHTML");}
  set innerHTML(_) {throw new Error("Evidence rendering must use textContent");}
  insertAdjacentHTML() {throw new Error("Evidence rendering must not insert HTML strings");}
  append(...items) {this.children.push(...items);}
  appendChild(item) {this.append(item); return item;}
  replaceChildren(...items) {this._text = ""; this.children = [...items];}
  setAttribute(key, value) {this.attributes[key] = String(value); if (key === "open") this.open = true; if (key.startsWith("data-")) this.dataset[key.slice(5).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = String(value);}
  getAttribute(key) {return this.attributes[key] ?? null;}
  addEventListener(key, callback) {(this.listeners[key] ||= []).push(callback);}
  reportValidity() {return true;}
  focus() {}
}
function copy(value) {return JSON.parse(JSON.stringify(value));}
function descendants(element) {return element.children.flatMap(child => child instanceof Element ? [child, ...descendants(child)] : []);}
function sha(file) {return createHash("sha256").update(fs.readFileSync(file)).digest("hex");}
function ui() {
  const source = fs.readFileSync(sourcePath, "utf8"), html = fs.readFileSync(htmlPath, "utf8"), elements = new Map();
  assert.match(source, /\nload\(\);\s*$/);
  for (const match of html.matchAll(/<([\w-]+)\b[^>]*\bid="([^"]+)"/g)) {assert.equal(elements.has(match[2]), false, "Duplicate HTML ID"); elements.set(match[2], new Element(match[1]));}
  const timers = new Map(), storage = new Map(); let sequence = 0;
  const harness = {elements, timers, requests: [], fetchImpl: null, confirmations: []};
  const document = {body: {dataset: {}}, getElementById(id) {assert.ok(elements.has(id), `Missing production HTML ID ${id}`); return elements.get(id);}, createElement(tag) {return new Element(tag);}};
  const window = {location: {origin: "http://127.0.0.1:19999", search: ""}, addEventListener() {}, confirm(value) {harness.confirmations.push(value); return false;}};
  const context = vm.createContext({document, window, URLSearchParams, AbortController, Uint8Array, crypto: webcrypto,
    sessionStorage: {getItem(key) {return storage.get(key) ?? null;}, setItem(key, value) {storage.set(key, value);}},
    setTimeout(callback, delay) {const id = ++sequence; timers.set(id, {callback, delay}); return id;}, clearTimeout(id) {timers.delete(id);},
    async fetch(url, options) {harness.requests.push({url, options}); if (!harness.fetchImpl) throw new Error("Offline tests forbid network"); return harness.fetchImpl(url, options);}});
  // Only the final initial HTTP load is omitted. Production functions are intact.
  vm.runInContext(source.replace(/\nload\(\);\s*$/, "\n"), context, {filename: sourcePath});
  harness.state = vm.runInContext("state", context); harness.call = (name, ...args) => vm.runInContext(name, context)(...args);
  harness.el = id => document.getElementById(id); return harness;
}
const inputHash = "a".repeat(64), proposalHash = "b".repeat(64), reviewHash = "c".repeat(64), evidenceHash = "d".repeat(64);
function proposal() {
  return {schema: "scagentkit.strategy.v1", rationale: "Use measured public quality and an explicit analyst plan.", risks: ["Clustering does not validate cell identity"], inferences: [{claim: "The contrast may be biological", uncertainty: "unverified design"}],
    qc: {schema: "scagentkit.qc.rules.v1", rationale: "Explicit synthetic range", risks: [], remove_if: "any", rules: [{op: "range", metric: "nFeature", min: 200}]}, analysis: {normalization_method: "LogNormalize", scale_factor: 10000, nfeatures: 2000, npcs: 30, seed: 42},
    pcs: {method: "fixed", ndim: 20}, batch: {method: "none", reason: "No verified batch contrast"}, clustering: {resolution: 0.5, diagnostic_resolutions: [0.3, 0.5]}, umap: {run: true, n_neighbors: 30}};
}
function answer() {
  return {schema: "scagentkit.run-review.workbench.v1", csrf_token: "offline-session-token", run: {schema: "scagentkit.run.v1", project_id: "offline-strategy", input_hash: inputHash, revision: 7, status: "awaiting_review", stage: "strategy_propose", context: {species: "human", tissue: "Blood"},
    review_node: {kind: "strategy", project_id: "offline-strategy", input_hash: inputHash, expected_revision: 7, proposal_hash: proposalHash, review_hash: reviewHash, evidence_hash: evidenceHash, can_decide: true, can_revise: true, can_undo: false},
    strategy_review: {schema: "scagentkit.strategy.review.v1", hash: reviewHash, input_hash: inputHash, evidence_hash: evidenceHash, details: {canonical_proposal: proposal(), background: {facts: {species: "human", tissue: "Blood", group_column: "condition", group_values: ["Ca", "Ctrl"]}, missing: ["batch assignment", "donor identity"]}, quality: {cell_count: 96, actual_source: "saved measured QC summary"}, qc_impact: qcPreviewFixture(proposal().qc, 96, 90), applicability: {executable: true, blockers: [], details: [{operation: "batch", method: "none", applicable: true}]}, capabilities: {qc_rules: {schema: "scagentkit.qc.rules.v1", operations: ["range", "mad_preset"]}, pc_selection: ["fixed", "computed_variance"], batch: ["none", "manual"], cycle: "unsupported", doublet: "unsupported", subcluster: "unsupported"}, execution_plan: ["qc_apply", "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_review"], dependency_hashes: {input: inputHash}, source: {kind: "mock_provider", new_request: false}, limitations: ["Synthetic transport fixture, not scientific validation"]}}}};
}
function setup(value = answer()) {const h = ui(); h.state.view = h.call("verify", copy(value)); h.state.continuation = value.continuation || null; h.call("render"); return h;}
function validReady(value) {value.run.status = "ready"; value.run.stage = "strategy_apply"; value.run.review_node = null; return value;}
function continuation(run, job = null, canRetry = false) {return {schema: "scagentkit.run-continue.workbench.v1", enabled: true, job, availability: {project_id: run.project_id, input_hash: run.input_hash, expected_revision: run.revision, can_continue: !canRetry && run.status === "ready", can_retry: canRetry, requires_explicit_retry: canRetry, reason: canRetry ? "explicit_retry_required" : "ready"}};}

function recommendations() {
  return {schema:"scagentkit.recommendations.v1",policy_version:"1",completed:["Measured QC distributions"],next_decision:"Review strategy, save edits and approve local computation",limitations:["Heuristic suggestions, not biological optima"],steps:[
    {id:"qc",title:"QC",status:"recommend_execute",assessment:"assessed",reasons:["Inspect distributions"],completed:["Sample-aware distributions measured"],conflicts:["Multimodal group"],uncertainty:["No optimal threshold established"],missing:[{field:"chemistry",label:"Chemistry",reason:"Not declared"}],next_decision:"Compare retention before approval",candidates:[{id:"keep",label:"Keep all pending review",available:true,changes:{qc:{schema: "scagentkit.qc.rules.v1", remove_if: "any",rationale:"Keep uncertain cells",risks:[],rules:[{op:"range",metric:"nCount",min:1}]}},reasons:["No tissue-specific cutoff"],impact:{removed_cells:0},conflicts:[]}]},
    {id:"resolution",title:"Resolution",status:"insufficient_information",assessment:"pending_computation",reasons:["No scan yet"],completed:[],conflicts:[],uncertainty:[],missing:[],next_decision:"Compute the approved fixed-graph scan",candidates:[{id:"r06",label:"Measured 0.6",available:false,changes:{clustering:{resolution:.6}},reasons:["Not computed"],impact:{},conflicts:[]}]}
  ]};
}

const value=answer();value.run.status="complete";value.run.stage="complete";value.run.review_node=null;value.run.scientific_assessment={schema:"scagentkit.scientific-assessment.v1",certified_qc:false,workflow_status:"complete",source_review_hash:reviewHash,unassessed_steps:["qc","doublet","batch"],qc_choice:"keep_all_quality_deferred",message:"Scientific assessment remains incomplete for QC, doublets and technical batch. Software completion does not certify full QC or cell identities."};
const h=setup(value),banner=h.el("run-scientific-assessment");assert.equal(banner.hidden,false);for(const text of ["Scientific assessment remains incomplete","keep-all","doublet","batch","does not certify"])assert(banner.textContent.includes(text),text);
for (const [choice, expected] of [
  ["no_additional_filtering_quality_deferred", /No additional filtering; previously excluded cells are not restored.*QC assessment remains deferred.*empty rule set/s],
  ["processed_reuse_raw_quality_unassessed", /reuses the processed input.*Raw-input quality was not assessed by this run/s]
]) {
  const deferred=copy(value); deferred.run.scientific_assessment.qc_choice=choice;
  const displayed=setup(deferred).el("run-scientific-assessment");
  assert.match(displayed.textContent, expected); assert.match(displayed.textContent, /Unassessed steps: qc/);
}
const clean=copy(value);clean.run.scientific_assessment.unassessed_steps=[];clean.run.scientific_assessment.qc_choice="explicit_reviewed_quality_rule";clean.run.scientific_assessment.message="Declared decisions and supported diagnostics are recorded; software completion is not biological or QC certification.";assert.match(setup(clean).el("run-scientific-assessment").textContent,/not biological or QC certification/);
const unresolved=copy(clean);unresolved.run.scientific_assessment.unresolved_steps=["resolution"];unresolved.run.scientific_assessment.unresolved_details=[{id:"resolution",missing:[],conflicts:["Alternative partition remains plausible"],uncertainty:["ARI measures sensitivity only"]}];const conflict=setup(unresolved).el("run-scientific-assessment");assert.match(conflict.textContent,/Unresolved decisions or conflicts: resolution/);assert.match(conflict.textContent,/Alternative partition remains plausible/);assert.match(conflict.textContent,/Scientific assessment remains incomplete/);
const absent=copy(value);delete absent.run.scientific_assessment;assert.match(setup(absent).el("run-scientific-assessment").textContent,/not recorded|unavailable/i);
const foreign=copy(value);foreign.run.scientific_assessment.source_review_hash="e".repeat(64);assert.match(setup(foreign).el("run-scientific-assessment").textContent,/unavailable|unverified/i);
console.log(JSON.stringify({passed:true,actualBrowser:false,actualProductionRenderer:true,modelCalls:0,cases:["workflow completion distinct from scientific assessment","keep-all deferred QC visible","empty rules do not restore prior exclusions or certify QC","processed reuse leaves raw-input quality unassessed","optional unassessed paths retained","absent or foreign assessment never certified"]}));
