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

(async()=>{
const value=answer();value.run.strategy_review.details.canonical_proposal.qc={schema: "scagentkit.qc.rules.v1", remove_if: "any",rationale:"Input review",risks:[],rules:[{op:"range",metric:"nCount",min:1}]};
const rec=recommendations();rec.fact_editable=true;rec.fact_fields=[
 {key:"columns.capture",label:"Physical capture column",type:"select",options:[{value:"loading_unit",label:"loading_unit"}],value:null,required:false,reason:"Choose actual input metadata; sample is not capture"},
 {key:"doublet.empty_droplets_removed",label:"Upstream cell calling complete",type:"boolean",value:null,required:true,reason:"Raw MEX is not cell calling"},
 {key:"doublet.rate.value",label:"Sourced expected rate",type:"number",value:null,required:false,reason:"Rate is not a deletion quota"}];
rec.fact_values={};value.run.strategy_review.details.recommendations=rec;
value.run.strategy_review.details.qc_impact = qcPreviewFixture(value.run.strategy_review.details.canonical_proposal.qc, 96, 90);
const h=setup(value),form=h.state.recommendationFacts;
assert(form,"Fact form rendered from saved fields only");assert.equal(h.call("recommendationFactsDirty"),false);
assert.equal(form.items.length,3,"Backend boolean fields must not be dropped");
assert.equal(form.items[1].input.value,"","Unknown is not default FALSE");
assert.equal(form.items[1].input.required,false,"A fact needed by an optional path does not force all unrelated facts before partial save");
form.items[0].input.value="loading_unit";form.items[1].input.value="false";form.items[2].input.value="0.08";
const patch=h.call("recommendationFactPatch",form.items);assert.equal(patch.columns.capture,"loading_unit");assert.equal(patch.doublet.empty_droplets_removed,false);assert.equal(patch.doublet.rate.value,.08);
assert.equal(h.call("recommendationFactsDirty"),true);h.call("buttons");assert.equal(h.el("strategy-approve").disabled,true,"Unsaved facts do not enter scientific approval");
assert.equal(h.call("applyRecommendation","qc","keep",reviewHash),false,"Cannot overwrite local facts with draft candidates");
h.el("run-refresh").listeners.click[0]();assert.equal(h.requests.length,0);assert.equal(h.confirmations.length,1,"Refresh warns before discarding dirty facts");assert.equal(form.items[1].input.value,"false");
for(const input of ["NaN","Infinity","nonsense"]){form.items[2].input.value=input;assert.throws(()=>h.call("recommendationFactPatch",form.items));}form.items[2].input.value="0.08";
assert.throws(()=>h.call("recommendationFactPatch",[{field:{key:"__proto__.polluted",type:"text",value:null},input:{value:"yes"}}]));
form.reviewer.value="offline scientist";form.reason.value="Correct declared loading units";
h.fetchImpl=async()=>{const next=answer();next.run.revision=8;next.run.status="ready";next.run.stage="prefilter";next.run.review_node=null;delete next.run.strategy_review;return{ok:true,json:async()=>next};};
const first=h.call("saveRecommendationFacts",reviewHash),second=h.call("saveRecommendationFacts",reviewHash);await Promise.all([first,second]);
assert.equal(h.requests.length,1,"Duplicate save cannot issue a second request");const payload=JSON.parse(h.requests[0].options.body);
assert.equal(h.requests[0].url,"/api/run-review/decision");assert.equal(payload.action,"facts");assert.equal(payload.kind,"strategy");assert.equal(payload.review_hash,reviewHash);assert.equal(payload.facts.doublet.empty_droplets_removed,false);assert(!("proposal" in payload));
assert.match(h.el("run-message").textContent,/not yet|Continue|prepar/i,"No false claim that suggestions were generated without worker");
const auto=setup(value);auto.state.recommendationFacts.items[1].input.value="true";auto.state.recommendationFacts.reviewer.value="analyst";auto.state.recommendationFacts.reason.value="Physical capture facts";
auto.fetchImpl=async(url,options)=>{const next=answer();next.run.revision=8;next.run.status="ready";next.run.stage="prefilter";next.run.review_node=null;delete next.run.strategy_review;
  if(url==="/api/run-review/decision"){next.continuation=continuation(next.run);return{ok:true,json:async()=>next};}
  assert.equal(url,"/api/run-review/continue");const submitted=JSON.parse(options.body),job={...submitted,job_id:"diagnostic-job",status:"queued",retry_permitted:false,created_at:"2026-10-18",updated_at:"2026-10-18"};const response=continuation(next.run,job);response.availability.can_continue=false;response.duplicate=false;return{ok:true,json:async()=>response};};
await auto.call("saveRecommendationFacts",reviewHash);assert.equal(auto.requests.length,2,"Facts save may queue only the fixed local diagnostic worker");assert.equal(JSON.parse(auto.requests[0].options.body).action,"facts");assert.equal(JSON.parse(auto.requests[1].options.body).retry,false);assert.equal(auto.state.continuation.job.status,"queued");
const locked=copy(value);locked.run.strategy_review.details.recommendations.fact_editable=false;const noedit=setup(locked);assert.equal(noedit.state.recommendationFacts.save.disabled,true);await noedit.call("saveRecommendationFacts",reviewHash);assert.equal(noedit.requests.length,0);
const stale=setup(value);stale.state.stale=true;await stale.call("saveRecommendationFacts",reviewHash);assert.equal(stale.requests.length,0);
const mappingValue=copy(value);
mappingValue.run.strategy_review.details.recommendations.metadata_role_candidates={
  schema:"scagentkit.metadata-role-candidates.v1",status:"needs_selection",
  notice:"Choose the sample column explicitly; automatic pooled MAD is disabled.",
  candidates:[{column:"orig.ident",distinct_values:1},{column:"sample",distinct_values:2}],
  privacy:{cell_ids_included:false,per_cell_values_included:false}};
mappingValue.run.strategy_review.details.recommendations.fact_fields=[{
  key:"columns.sample",label:"Sample grouping",type:"select",options:[{value:"orig.ident",label:"orig.ident"},{value:"sample",label:"sample"}],value:null,required:true}];
mappingValue.run.strategy_review.details.automatic_diagnostics={
  cycle:{status:"unavailable",reason:"Mouse scoring needs explicit versioned lists."},
  doublet:{status:"disabled",reason:"No singlet status is inferred."}};
const mappingUI=setup(mappingValue);
assert.match(mappingUI.el("strategy-operations").textContent,/cycle: unavailable.*Mouse scoring.*doublet: disabled/s);
assert.match(mappingUI.el("strategy-recommendations").textContent,/automatic pooled MAD is disabled/);
assert.equal(mappingUI.state.recommendationFacts.items[0].input.value,"");
assert.equal(mappingUI.requests.length,0,"Displaying candidates cannot declare a sample or approve a plan");
console.log(JSON.stringify({passed:true,actualBrowser:false,actualProductionFunctions:true,modelCalls:0,cases:["unknown booleans stay unknown","edited-only typed nested patch","invalid/prototype fields rejected","exact bound facts action","duplicate click blocked","read-only and stale blocked","no generated-assessment claim without worker"]}));
})().catch(error=>{console.error(error);process.exitCode=1;});
