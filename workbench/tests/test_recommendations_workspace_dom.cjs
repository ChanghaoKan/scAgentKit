"use strict";
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
    qc: {method: "thresholds", rules: [{metric: "nFeature_RNA", min: 200}]}, analysis: {normalization_method: "LogNormalize", scale_factor: 10000, nfeatures: 2000, npcs: 30, seed: 42},
    pcs: {method: "fixed", ndim: 20}, batch: {method: "none", reason: "No verified batch contrast"}, clustering: {resolution: 0.5, diagnostic_resolutions: [0.3, 0.5]}, umap: {run: true, n_neighbors: 30}};
}
function answer() {
  return {schema: "scagentkit.run-review.workbench.v1", csrf_token: "offline-session-token", run: {schema: "scagentkit.run.v1", project_id: "offline-strategy", input_hash: inputHash, revision: 7, status: "awaiting_review", stage: "strategy_propose", context: {species: "human", tissue: "Blood"},
    review_node: {kind: "strategy", project_id: "offline-strategy", input_hash: inputHash, expected_revision: 7, proposal_hash: proposalHash, review_hash: reviewHash, evidence_hash: evidenceHash, can_decide: true, can_revise: true, can_undo: false},
    strategy_review: {schema: "scagentkit.strategy.review.v1", hash: reviewHash, input_hash: inputHash, evidence_hash: evidenceHash, details: {canonical_proposal: proposal(), background: {facts: {species: "human", tissue: "Blood", group_column: "condition", group_values: ["Ca", "Ctrl"]}, missing: ["batch assignment", "donor identity"]}, quality: {cell_count: 96, actual_source: "saved measured QC summary"}, qc_impact: {expected_retained_cells: 90, input_cell_count: 96}, applicability: {executable: true, blockers: [], details: [{operation: "batch", method: "none", applicable: true}]}, capabilities: {pc_selection: ["fixed", "computed_variance"], batch: ["none", "manual"], cycle: "unsupported", doublet: "unsupported", subcluster: "unsupported"}, execution_plan: ["qc_apply", "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_review"], dependency_hashes: {input: inputHash}, source: {kind: "mock_provider", new_request: false}, limitations: ["Synthetic transport fixture, not scientific validation"]}}}};
}
function setup(value = answer()) {const h = ui(); h.state.view = h.call("verify", copy(value)); h.state.continuation = value.continuation || null; h.call("render"); return h;}
function validReady(value) {value.run.status = "ready"; value.run.stage = "strategy_apply"; value.run.review_node = null; return value;}
function continuation(run, job = null, canRetry = false) {return {schema: "scagentkit.run-continue.workbench.v1", enabled: true, job, availability: {project_id: run.project_id, input_hash: run.input_hash, expected_revision: run.revision, can_continue: !canRetry && run.status === "ready", can_retry: canRetry, requires_explicit_retry: canRetry, reason: canRetry ? "explicit_retry_required" : "ready"}};}

function recommendations() {
  return {schema:"scagentkit.recommendations.v1",policy_version:"1",completed:["Measured QC distributions"],next_decision:"Review strategy, save edits and approve local computation",limitations:["Heuristic suggestions, not biological optima"],steps:[
    {id:"qc",title:"QC",status:"recommend_execute",assessment:"assessed",reasons:["Inspect distributions"],completed:["Sample-aware distributions measured"],conflicts:["Multimodal group"],uncertainty:["No optimal threshold established"],missing:[{field:"chemistry",label:"Chemistry",reason:"Not declared"}],next_decision:"Compare retention before approval",candidates:[{id:"keep",label:"Keep all pending review",available:true,changes:{qc:{schema:"scagentkit.qc.v1",rationale:"Keep uncertain cells",risks:[],filters:[{op:"range",metric:"nCount",min:1}]}},reasons:["No tissue-specific cutoff"],impact:{removed_cells:0},conflicts:[]}]},
    {id:"resolution",title:"Resolution",status:"insufficient_information",assessment:"pending_computation",reasons:["No scan yet"],completed:[],conflicts:[],uncertainty:[],missing:[],next_decision:"Compute the approved fixed-graph scan",candidates:[{id:"r06",label:"Measured 0.6",available:false,changes:{clustering:{resolution:.6}},reasons:["Not computed"],impact:{},conflicts:[]}]}
  ]};
}
const value=answer();value.run.strategy_review.details.canonical_proposal.qc={schema:"scagentkit.qc.v1",rationale:"Inspect input",risks:[],filters:[{op:"range",metric:"nCount",min:1}]};value.run.strategy_review.details.recommendations=recommendations();
const h=setup(value),target=h.el("strategy-recommendations");
for(const phrase of ["Measured QC distributions","Sample-aware distributions measured","Multimodal group","Chemistry","Not declared","pending computation","Compute the approved fixed-graph scan","not biological optima"])assert(target.textContent.includes(phrase),phrase);
const before=copy(h.state.view),beforeDraft=copy(h.call("strategyDraft"));
assert.equal(h.call("applyRecommendation","qc","keep",reviewHash),true);
assert.equal(h.requests.length,0,"Applying a recommendation cannot call any API");
assert.equal(JSON.stringify(h.state.view),JSON.stringify(before),"Saved proposal and approvals unchanged");
assert.equal(h.call("strategyDraft").qc.rationale,"Keep uncertain cells");
assert.equal(JSON.stringify(h.call("strategyDraft").clustering),JSON.stringify(beforeDraft.clustering));
assert.match(h.el("run-message").textContent,/Save complete strategy/);
assert.equal(h.el("strategy-approve").disabled,true,"Unsaved candidate cannot be approved");
const changed=copy(beforeDraft);changed.clustering.resolution=.6;
const next=h.call("recommendationDraft",beforeDraft,"resolution",{available:true,changes:{clustering:{resolution:.6}}});
assert.equal(next.clustering.resolution,.6);assert.equal(JSON.stringify(next.clustering.diagnostic_resolutions),JSON.stringify(beforeDraft.clustering.diagnostic_resolutions));
for(const candidate of [{available:false,changes:{pcs:{method:"fixed",ndim:4}}},{available:true,changes:{analysis:{npcs:4}}},{available:true,changes:{pcs:{method:"fixed",ndim:4},batch:{method:"none"}}},{available:true,changes:{clustering:{resolution:.6,diagnostic_resolutions:[.6]}}}])assert.throws(()=>h.call("recommendationDraft",beforeDraft,candidate.changes.clustering?"resolution":"pcs",candidate));
for(const [step,choice] of [["pcs",{method:"fixed",ndim:4}],["batch",{method:"none",reason:"Explicit no correction"}],["doublet",{method:"keep",reason:"Keep predicted cells"}]]) {
  const result=h.call("recommendationDraft",beforeDraft,step,{available:true,changes:{[step]:choice}});
  assert.equal(JSON.stringify(result[step]),JSON.stringify(choice),"Replace the whole typed choice");
  assert.equal(JSON.stringify(beforeDraft),JSON.stringify(copy(beforeDraft)),"No draft reference mutation");
}
assert.equal(h.call("applyRecommendation","resolution","r06",reviewHash),false);
assert.equal(h.call("applyRecommendation","qc","keep","f".repeat(64)),false,"Old review binding cannot change draft");
h.state.stale=true;h.call("buttons");assert.match(target.textContent,/Refresh.*saved review|not current/);assert.equal(h.call("applyRecommendation","qc","keep",reviewHash),false);
const missing=copy(value);delete missing.run.strategy_review.details.recommendations;const absent=setup(missing);assert.match(absent.el("strategy-recommendations").textContent,/not recorded|unavailable/i);assert.equal(absent.call("applyRecommendation","qc","keep",reviewHash),false);
const foreignBinding=copy(value);foreignBinding.run.strategy_review.details.recommendations.binding={input_hash:"e".repeat(64)};assert.match(setup(foreignBinding).el("strategy-recommendations").textContent,/binding is not current/);
const malformed=copy(value);malformed.run.strategy_review.details.recommendations.steps[0].candidates=[null];assert.match(setup(malformed).el("strategy-recommendations").textContent,/unavailable/i);
const invalid=copy(value);invalid.run.strategy_review.details.recommendations.policy_version="unsupported";assert.match(setup(invalid).el("strategy-recommendations").textContent,/unavailable|unsupported/i);
console.log(JSON.stringify({passed:true,actualProductionRenderer:true,actualBrowser:false,modelCalls:0,apiCalls:h.requests.length,cases:["saved measured and missing evidence","candidate only changes local draft","approval blocked until save","resolution preserves diagnostic grid","unknown and cross-step fields rejected","stale/absent recommendations fail closed"]}));

// A bound preselection may fill memory, never write/approve or overwrite edits.
const preselected=copy(value);
preselected.run.strategy_review.details.recommendations.fact_editable=true;
preselected.run.strategy_review.details.recommendations.steps[0].draft_preselection={candidate_id:"keep",automatic:true,draft_only:true,reason:"Synthetic transport eligibility"};
const pre=setup(preselected);
assert.equal(pre.requests.length,0);
const afterApproval=copy(preselected);
afterApproval.run.strategy_review.details.recommendations.fact_editable=false;
const preserved=setup(afterApproval);
assert.equal(JSON.stringify(preserved.call("strategyDraft").qc),JSON.stringify(afterApproval.run.strategy_review.details.canonical_proposal.qc),"An already executed/approved strategy keeps its explicit QC policy");
assert.equal(preserved.requests.length,0);
assert(!/NOT SAVED, NOT APPROVED/.test(preserved.el("run-message").textContent));
assert.equal(pre.call("strategyDraft").qc.rationale,"Keep uncertain cells");
assert.equal(pre.el("strategy-approve").disabled,true);
assert.match(pre.el("run-message").textContent,/NOT SAVED, NOT APPROVED/);
assert.equal(JSON.stringify(pre.state.view),JSON.stringify(preselected));
const altered=copy(pre.call("strategyDraft"));altered.qc.rationale="Own unsaved edit";
pre.call("setStrategyDraft",altered,true);
pre.call("renderRecommendations");
assert.equal(pre.call("strategyDraft").qc.rationale,"Own unsaved edit");
assert.equal(pre.requests.length,0);
