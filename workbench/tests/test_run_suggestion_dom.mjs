#!/usr/bin/env node
// Executes production review.js with an inert DOM and explicit simulated HTTP.
// No native browser, R bridge, external provider, credential or network access.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import {webcrypto, createHash} from "node:crypto";
import {fileURLToPath} from "node:url";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const sourcePath = path.join(repo, "workbench/static/review.js"), htmlPath = path.join(repo, "workbench/static/review.html");
const source = fs.readFileSync(sourcePath, "utf8"), html = fs.readFileSync(htmlPath, "utf8");
const clone = value => JSON.parse(JSON.stringify(value));
const inputHash = "a".repeat(64), suggestionHash = "b".repeat(64), requestHash = "c".repeat(64), proposalHash = "d".repeat(64), reviewHash = "e".repeat(64), evidenceHash = "f".repeat(64);
class Element {
  constructor(tag) {this.tagName = tag.toUpperCase(); this.children = []; this.attributes = {}; this.dataset = {}; this.value = ""; this._text = ""; this.hidden = false; this.disabled = false; this.inert = false; this.listeners = {}; this.contentWindow = {}; this.className = ""; this.open = false; this.focused = false; this.classList = {toggle() {}};}
  get textContent() {return this._text + this.children.map(child => child instanceof Element ? child.textContent : String(child)).join("");}
  set textContent(value) {this._text = String(value ?? ""); this.children = [];}
  get innerHTML() {throw new Error("No evidence may be rendered as executable HTML");}
  set innerHTML(_) {throw new Error("No evidence may be rendered as executable HTML");}
  append(...children) {this.children.push(...children);}
  replaceChildren(...children) {this._text = ""; this.children = children;}
  setAttribute(key, value) {this.attributes[key] = String(value); if (key.startsWith("data-")) this.dataset[key.slice(5)] = String(value);}
  getAttribute(key) {return this.attributes[key] ?? null;}
  addEventListener(key, callback) {(this.listeners[key] ||= []).push(callback);}
  reportValidity() {return true;}
  focus() {this.focused = true;}
}
function harness(search = "", storage = new Map()) {
  assert.match(source, /\nload\(\);\s*$/);
  const elements = new Map(), timers = new Map(); let timer = 0;
  for (const match of html.matchAll(/<([\w-]+)\b[^>]*\bid="([^"]+)"/g)) {assert.equal(elements.has(match[2]), false, "Duplicate HTML ID"); elements.set(match[2], new Element(match[1]));}
  const h = {requests: [], fetchImpl: null, elements, timers, storage};
  const document = {getElementById(id) {assert(elements.has(id), "Missing production HTML ID " + id); return elements.get(id);}, createElement(tag) {return new Element(tag);}};
  const context = vm.createContext({document, window: {location: {origin: "http://127.0.0.1:19999", search}, addEventListener() {}, confirm() {return false;}}, URLSearchParams, AbortController, Uint8Array, crypto: webcrypto,
    sessionStorage: {getItem(key) {return storage.get(key) ?? null;}, setItem(key, value) {storage.set(key, value);}},
    setTimeout(callback, delay) {timers.set(++timer, {callback, delay}); return timer;}, clearTimeout(id) {timers.delete(id);},
    async fetch(url, options = {}) {h.requests.push({url, options}); assert(h.fetchImpl, "Offline fixture forbids network"); return h.fetchImpl(url, options);}});
  vm.runInContext(source.replace(/\nload\(\);\s*$/, "\n"), context, {filename: sourcePath});
  h.state = vm.runInContext("state", context); h.call = (name, ...args) => vm.runInContext(name, context)(...args); h.el = id => document.getElementById(id);
  return h;
}
function strategy() {return {schema: "scagentkit.strategy.v1", rationale: "Explicit simulated candidate from actual fixture aggregates", risks: ["Model suggestions do not prove scientific benefit"], inferences: [], qc: {schema: "scagentkit.qc.v1", rationale: "Retain the selected cohort", risks: [], filters: [{op: "range", metric: "nFeature", min: 0, max: 5000, group: null}]}, analysis: {normalization_method: "LogNormalize", scale_factor: 10000, nfeatures: 100, npcs: 12, seed: 17}, pcs: {method: "fixed", ndim: 10}, batch: {method: "none", reason: "No declared technical batch"}, clustering: {resolution: .4}, umap: {run: true, n_neighbors: 20}};}
function science(revision = 7, approved = false) {
  const value = {schema: "scagentkit.run-review.workbench.v1", csrf_token: "science-token", suggestion_enabled: true, run: {schema: "scagentkit.run.v1", project_id: "literal-project", input_hash: inputHash, revision, status: "awaiting_configuration", stage: "strategy_propose", context: {species: "human", tissue: "public fixture"}, review_node: null}};
  if (approved) value.run.status = "ready";
  return value;
}
function scientificReview(revision = 9, approved = false) {
  const value = science(revision, approved), run = value.run;
  run.status = approved ? "ready" : "awaiting_review"; run.stage = approved ? "strategy_apply" : "strategy_propose";
  run.review_node = approved ? null : {kind: "strategy", project_id: run.project_id, input_hash: inputHash, expected_revision: revision, proposal_hash: proposalHash, review_hash: reviewHash, evidence_hash: evidenceHash, can_decide: true, can_revise: true, can_undo: false};
  run.strategy_review = {schema: "scagentkit.strategy.review.v1", hash: reviewHash, input_hash: inputHash, evidence_hash: evidenceHash, details: {canonical_proposal: strategy(), background: {facts: run.context}, applicability: {executable: true, blockers: []}, source: {kind: "simulated_model_candidate"}, quality: {cell_count: 72}, qc_impact: {expected_retained_cells: 72}, capabilities: {}, limitations: ["Simulated fixture"]}};
  value.continuation = {schema: "scagentkit.run-continue.workbench.v1", enabled: true, job: null, availability: {project_id: run.project_id, input_hash: inputHash, expected_revision: revision, can_continue: approved, can_retry: false, requires_explicit_retry: false, reason: approved ? "ready" : "review"}};
  return value;
}
function annotationReview(revision = 9, approved = false) {
  const value = scientificReview(revision, approved), run = value.run;
  run.stage = approved ? "annotation_apply" : "annotation_propose";
  run.review_node = approved ? null : {kind: "annotation", project_id: run.project_id, input_hash: inputHash, expected_revision: revision, proposal_hash: proposalHash, review_hash: reviewHash, can_decide: true, can_revise: true, can_undo: false};
  const row = {clusterId: "literal:C", cell_count: 1, cell_ids: ["cell:X"], proposal: {clusterId: "literal:C", label: "Unknown", confidence: "low", rationale: "Identity unresolved in this simulated fixture", markers: []}, supplied_marker_stats: [], cited_marker_stats: [], local_reference: {status: "not_supplied"}};
  run.annotation_review = {schema: "scagentkit.annotation.review.v1", hash: reviewHash, input_hash: inputHash, details: {cell_count: 1, cluster_count: 1, input_cells: [{cell_id: "cell:X", cluster: "literal:C"}], annotations: [row], source: {kind: "simulated_model_candidate"}, limitations: []}};
  return value;
}
function model(revision = 7, status = "preview") {
  return {schema: "scagentkit.run-suggestion.workbench.v1", csrf_token: "suggestion-token", enabled: true, simulated: true, job: null,
    suggestion: {schema: "scagentkit.run-suggestion.v1", project_id: "literal-project", input_hash: inputHash, revision, kind: "strategy", available: true, blocked_reason: null, suggestion_hash: suggestionHash, status,
      preview: {request_hash: requestHash, provider: {name: "mock", model: "simulated-v1", external: true}, model: "simulated-v1", generation: {temperature: 0, max_tokens: 4096}, budget: .5, reservation_usd: .05, external: true, allow_external: true, simulated: true, notice: "Aggregate QC and supplied context leave the machine; raw matrix and cell IDs are excluded.", system_prompt: "Return a typed strategy", user_prompt: '{"context":{"notes":"public fixture"},"evidence":{"cells":72}}', charged_or_held_usd: 0, known_cost_usd: 0, held_usd: 0}, candidate: null, response: null, can_approve: status === "preview", can_request: status === "approved", can_adopt: false, can_discard: false}};
}
function candidate(revision = 9) {const value = model(revision, "candidate"); value.suggestion.candidate = strategy(); value.suggestion.response = {status: "ok", cached: false, cost_state: "known", cost_usd: 0, charged_or_held_usd: 0, usage: {input_tokens: 20, output_tokens: 40}, response_metadata: {finish_reason: "stop"}}; value.suggestion.can_approve = false; value.suggestion.can_request = false; value.suggestion.can_adopt = true; value.suggestion.can_discard = true; return value;}
function job(status = "running", revision = 7, id = "saved-request") {return {job_id: "0123456789abcdef0123456789abcdef", status, project_id: "literal-project", input_hash: inputHash, expected_revision: revision, suggestion_hash: suggestionHash, request_id: id, simulated: true, retry_permitted: false};}
function setup(scientific = science(), suggestion = model(), search = "", storage = new Map()) {const h = harness(search, storage); h.state.view = h.call("verify", clone(scientific)); h.state.continuation = scientific.continuation || null; if (suggestion) h.state.suggestion = h.call("verifySuggestion", clone(suggestion)); h.call("render"); h.el("suggestion-reviewer").value = " Analyst "; h.el("suggestion-reason").value = " Reviewed exact aggregate "; return h;}
function response(value, ok = true) {return {ok, json: async () => clone(value)};}
const results = [];
async function test(name, action) {try {await action(); results.push({name, passed: true});} catch (error) {results.push({name, passed: false, error: error.message});}}

await test("readonly shared model card displays exact preview without a request", () => {const h = setup(); assert.equal(h.requests.length, 0); assert.match(h.el("suggestion-summary").textContent, /mock.*simulated-v1.*strategy/); assert.match(h.el("suggestion-payload").textContent, /Return a typed strategy.*public fixture/s); assert.match(h.el("suggestion-notice").textContent, /leave the machine.*raw matrix and cell IDs/s); assert.equal(h.el("suggestion-approve").disabled, false); assert.equal(h.el("suggestion-request").hidden, true);});
await test("simulated provenance is conspicuous and real configured models have no simulated badge", () => {const h = setup(); assert.equal(h.el("suggestion-simulated").hidden, false); const value = model(); value.simulated = false; value.suggestion.preview.simulated = false; value.suggestion.preview.provider.name = "deepseek"; value.suggestion.preview.model = "configured-model"; h.state.suggestion = h.call("verifySuggestion", value); h.call("renderSuggestion"); assert.equal(h.el("suggestion-simulated").hidden, true); assert.doesNotMatch(h.el("suggestion-summary").textContent, /paid.*completed|scientifically correct/);});
await test("disabled optional worker cannot lock ordinary scientific approval", async () => {const value = scientificReview(); value.suggestion_enabled = false; const h = setup(value, null); assert.equal(h.el("suggestion-preview").disabled, true); assert.equal(h.el("strategy-approve").disabled, false); await h.call("loadSuggestion"); assert.equal(h.requests.length, 0); assert.equal(h.state.suggestionLost, false); assert.match(h.el("suggestion-summary").textContent, /disabled.*no request has been sent.*remain available/s);});
await test("missing hint never probes an old server model endpoint", async () => {const value = scientificReview(); delete value.suggestion_enabled; const h = setup(value, null); await h.call("loadSuggestion"); assert.equal(h.requests.length, 0); assert.equal(h.el("strategy-approve").disabled, false);});
await test("available exact preview opens without transmission and page has no browser credential controls", () => {const h = setup(); assert.equal(h.el("suggestion-preview-details").open, true); assert.equal(h.requests.length, 0); assert.match(html, /<details id="suggestion-preview-details"[^>]*>/); assert.doesNotMatch(html, /<(?:input|textarea|select)[^>]*(?:api.key|endpoint|provider|model|password)[^>]*>/i); assert.match(html, /<details id="strategy-edit-details"/);});
for (const [name, mutate] of [["foreign project", value => value.suggestion.project_id = "other"], ["changed input", value => value.suggestion.input_hash = "0".repeat(64)], ["invalid revision", value => value.suggestion.revision = 7.2], ["invalid suggestion hash", value => value.suggestion.suggestion_hash = "changed"], ["missing action permission", value => delete value.suggestion.can_request], ["unverified request hash", value => value.suggestion.preview.request_hash = "wrong"], ["untyped candidate", value => {value.suggestion.candidate = {schema: "run_arbitrary_R", code: "never()"};}], ["foreign task", value => {value.job = job(); value.job.project_id = "other";}], ["invalid task state", value => {value.job = job("resending");}]]) await test("unverified model response fails closed: " + name, () => {const h = setup(), value = model(); mutate(value); assert.throws(() => h.call("verifySuggestion", value));});
await test("candidate display does not invent observed retention or apply it", () => {const h = setup(science(9), candidate()); assert.match(h.el("suggestion-candidate").textContent, /simulated candidate.*LogNormalize.*100.*12.*none.*0.4/s); assert.match(h.el("suggestion-impact").textContent, /will calculate.*when.*scientific review.*No candidate has changed/s); assert.match(h.el("suggestion-risks").textContent, /do not prove/); assert.equal(h.el("suggestion-adopt").disabled, false); assert.equal(h.requests.length, 0);});
await test("annotation candidate keeps Unknown visible with literal IDs and qualitative confidence", () => {const value = candidate(), h = setup(science(9)); value.suggestion.kind = "annotation"; value.suggestion.candidate = {schema: "scagentkit.annotation.v1", annotations: [{clusterId: "literal:01", label: "Unknown", confidence: "low", rationale: "Unresolved", markers: []}]}; h.state.suggestion = h.call("verifySuggestion", value); h.call("renderSuggestion"); assert.match(h.el("suggestion-candidate").textContent, /literal:01: Unknown.*low/); assert.match(h.el("suggestion-risks").textContent, /Use Unknown/);});
await test("transmitted text and candidate strings render inertly", () => {const value = candidate(); value.suggestion.preview.user_prompt = "<script>never()</script>"; value.suggestion.candidate.rationale = "<img onerror=never()>"; const h = setup(science(9), value); assert.match(h.el("suggestion-payload").textContent, /<script>/); assert.match(h.el("suggestion-candidate").textContent, /<img/); assert.equal(h.requests.length, 0);});
await test("new aggregate approval is explicit and does not start model request", async () => {const h = setup(); h.fetchImpl = async (url, options) => {if (url.endsWith("/approve")) {const value = model(8, "approved"); return response(value);} if (url.endsWith("/inspect")) return response(science(8)); return response(model(8, "approved"));}; await h.call("suggestionAction", "approve"); const writes = h.requests.filter(item => item.options.method === "POST"); assert.equal(writes.length, 1); assert.match(writes[0].url, /\/suggestion\/approve$/); assert.deepEqual(Object.keys(JSON.parse(writes[0].options.body)).sort(), ["project_id", "input_hash", "expected_revision", "suggestion_hash", "reviewer", "reason"].sort()); assert.equal(writes[0].options.headers["X-ScAgentKit-Suggestion-Token"], "suggestion-token"); assert.equal(h.el("suggestion-request").disabled, false);});
await test("missing explicit reviewer or reason prevents transfer", async () => {const h = setup(); h.el("suggestion-reason").value = " "; await h.call("suggestionAction", "approve"); assert.equal(h.requests.length, 0); assert.match(h.el("suggestion-message").textContent, /Enter a reviewer and a reason/);});
await test("exact request starts one durable simulated task and disables scientific mutations", async () => {const h = setup(scientificReview(7), model(7, "approved")); h.fetchImpl = async (_, options) => {const payload = JSON.parse(options.body), value = model(7, "approved"); value.job = job("queued", 7, payload.request_id); return response(value);}; await h.call("suggestionAction", "request"); assert.equal(h.requests.length, 1); const payload = JSON.parse(h.requests[0].options.body); assert.deepEqual(Object.keys(payload).sort(), ["project_id", "input_hash", "expected_revision", "suggestion_hash", "reviewer", "reason", "request_id"].sort()); assert.equal(h.el("strategy-approve").disabled, true); assert.equal(h.el("suggestion-request").disabled, true); assert.match(h.el("suggestion-job-id").textContent, /012345/); assert.equal(h.timers.size, 1);});
await test("double-click while request submission is pending cannot send a second request", async () => {const h = setup(science(), model(7, "approved")); let finish; h.fetchImpl = async (_, options) => new Promise(resolve => {finish = () => {const value = model(7, "approved"); value.job = job("running", 7, JSON.parse(options.body).request_id); resolve(response(value));};}); const first = h.call("suggestionAction", "request"); await h.call("suggestionAction", "request"); assert.equal(h.requests.length, 1); finish(); await first; assert.equal(h.requests.length, 1);});
await test("request identity persists without payload or credential storage", () => {const storage = new Map(), h = setup(science(), model(7, "approved"), "", storage); const first = h.call("suggestionPayload", "request"); const reloaded = setup(science(), model(7, "approved"), "", storage); const second = reloaded.call("suggestionPayload", "request"); assert.equal(second.request_id, first.request_id); assert.doesNotMatch([...storage.values()].join(""), /system_prompt|user_prompt|api_key|model|Bearer/);});
await test("reloading discovers an existing task using read-only HTTP only", async () => {const h = setup(), value = model(); value.job = job(); h.fetchImpl = async () => response(value); await h.call("loadSuggestion"); assert.equal(h.requests.length, 1); assert.equal(h.requests[0].options.method, undefined); assert.equal(h.state.suggestion.job.status, "running");});
await test("all suggestion HTTP operations allow the bounded local IPC response window", async () => {
  const runtime = fs.readFileSync(path.join(repo, "workbench/qc_runtime.py"), "utf8");
  const ipc = runtime.match(/^    def __init__\([^\n]*timeout=(\d+)\):/m);
  assert(ipc, "Verify the actual inherited local IPC timeout");
  const ceiling = Number(ipc[1]) * 1000;
  for (const action of [null, "preview", "approve", "request", "adopt", "discard"]) {
    const h = setup(); let finish, signal;
    h.fetchImpl = async (_, options) => new Promise(resolve => {signal = options.signal; finish = () => resolve(response(model()));});
    const pending = h.call("suggestionRequest", action, {});
    assert.equal(h.requests.length, 1); assert.equal(h.timers.size, 1);
    const [timer] = h.timers.values();
    assert.equal(timer.delay, ceiling + 5000, "Cover the unchanged backend bound plus response margin");
    assert.equal(signal.aborted, false);
    finish(); await pending;
    assert.equal(h.timers.size, 0, "Successful response cancels the HTTP abort timer");
  }
});
await test("preview HTTP timer abort fails closed and read-only refresh can reconcile", async () => {
  const h = setup(scientificReview(7), model(7, "approved")); let signal;
  h.fetchImpl = async (_, options) => new Promise((_, reject) => {signal = options.signal; signal.addEventListener("abort", () => {const error = new Error("Simulated bounded HTTP abort"); error.name = "AbortError"; reject(error);}, {once: true});});
  const pending = h.call("loadSuggestion"), [timer] = h.timers.values();
  assert.equal(timer.delay, 125000); assert.equal(signal.aborted, false);
  timer.callback(); await pending;
  assert.equal(signal.aborted, true); assert.equal(h.state.suggestionLost, true);
  assert.equal(h.el("strategy-approve").disabled, true); assert.equal(h.timers.size, 0);
  assert.equal(h.requests.length, 1); assert.equal(h.requests[0].options.method, undefined);
  await h.call("suggestionAction", "request"); assert.equal(h.requests.length, 1, "No write follows an uncertain read");
  const value = model(7, "approved"); value.job = job("running");
  h.fetchImpl = async () => response(value); await h.call("loadSuggestion");
  assert.equal(h.state.suggestionLost, false); assert.equal(h.requests.length, 2);
  assert.equal(h.requests.every(item => item.options.method !== "POST"), true);
  assert.equal(h.state.suggestion.job.status, "running");
});
await test("request HTTP timer abort retains its binding and cannot automatically resubmit", async () => {
  const h = setup(scientificReview(7), model(7, "approved")); let signal;
  h.fetchImpl = async (_, options) => new Promise((_, reject) => {signal = options.signal; signal.addEventListener("abort", () => reject(new Error("Simulated request HTTP abort")), {once: true});});
  const pending = h.call("suggestionAction", "request"), [timer] = h.timers.values();
  const sent = JSON.parse(h.requests[0].options.body);
  assert.equal(timer.delay, 125000); timer.callback(); await pending;
  assert.equal(signal.aborted, true); assert.equal(h.state.suggestionLost, true);
  assert.equal(h.state.suggestionPending.request_id, sent.request_id);
  assert.equal(h.el("strategy-approve").disabled, true); assert.equal(h.timers.size, 0);
  await h.call("suggestionAction", "request");
  assert.equal(h.requests.length, 1); assert.match(h.el("suggestion-message").textContent, /will not resubmit automatically/);
});
await test("scope query binds parent and child model routes without browser paths", async () => {const h = setup(science(), model(7, "approved"), "?child_id=literal-project"); h.fetchImpl = async (_, options) => {const value = model(7, "approved"); value.job = job("queued", 7, JSON.parse(options.body).request_id); return response(value);}; await h.call("suggestionAction", "request"); assert.equal(h.requests[0].url, "/api/run-review/suggestion/request?child_id=literal-project"); assert.equal("child_id" in JSON.parse(h.requests[0].options.body), false); assert.equal("project_dir" in JSON.parse(h.requests[0].options.body), false);});
await test("request transport loss retains task binding and never retries automatically", async () => {const h = setup(scientificReview(7), model(7, "approved")); h.fetchImpl = async () => {throw new Error("simulated transport interruption");}; await h.call("suggestionAction", "request"); assert.equal(h.requests.length, 1); assert.equal(h.state.suggestionLost, true); assert(h.state.suggestionPending.request_id); assert.equal(h.el("strategy-approve").disabled, true); assert.equal(h.timers.size, 0); await h.call("suggestionAction", "request"); assert.equal(h.requests.length, 1); assert.match(h.el("suggestion-message").textContent, /will not resubmit automatically/);});
await test("preview can reconcile a lost response without resending a request", async () => {const h = setup(science(), model(7, "approved")); h.state.suggestionLost = true; const value = model(7, "approved"); value.job = job("running"); h.fetchImpl = async () => response(value); await h.call("loadSuggestion"); assert.equal(h.state.suggestionLost, false); assert.equal(h.requests.every(item => item.options.method !== "POST"), true); assert.equal(h.el("suggestion-request").disabled, true);});
await test("unknown accounting hold is distinct from a successful candidate", () => {const value = model(7, "failed"); value.suggestion.can_approve = false; value.suggestion.preview.held_usd = .05; value.suggestion.response = {status: "accounting_hold", cached: false, cost_state: "unknown", cost_usd: null, charged_or_held_usd: .05, usage: null, error: "Unconfirmed delivery; reconcile manually"}; value.job = job("timed_out"); const h = setup(science(), value); assert.equal(h.el("suggestion-result").hidden, true); assert.equal(h.el("suggestion-request").hidden, true); assert.match(h.el("suggestion-message").textContent, /accounting_hold.*reconcile.*No automatic retry/s); assert.match(h.el("suggestion-accounting").textContent, /held_usd.*0.05.*unknown.*null/s);});
for (const status of ["truncated_response", "invalid_response", "empty_response"]) await test(status + " has no pretend candidate or implicit repair", () => {const value = model(7, "failed"); value.suggestion.can_approve = false; value.suggestion.response = {status, cached: false, cost_state: "known", cost_usd: 0, error: "Explicit new action or manual proposal required"}; const h = setup(science(), value); assert.equal(h.el("suggestion-adopt").hidden, true); assert.equal(h.el("suggestion-result").hidden, true); assert.match(h.el("suggestion-message").textContent, /No automatic retry/); assert.equal(h.requests.length, 0);});
await test("cached simulated response is labeled as the saved matching cache", () => {const value = candidate(); value.suggestion.response.cached = true; const h = setup(science(9), value); assert.match(h.el("suggestion-message").textContent, /matching saved cache.*still unapproved/); assert.equal(h.el("suggestion-simulated").hidden, false);});
await test("candidate adoption enters scientific review without approval or Continue", async () => {const h = setup(science(9), candidate()); h.fetchImpl = async url => {if (url.endsWith("/adopt")) {const value = model(10, "adopted"); value.suggestion.can_approve = false; return response(value);} if (url.endsWith("/inspect")) return response(scientificReview(10)); const value = model(10, "adopted"); value.suggestion.can_approve = false; return response(value);}; await h.call("suggestionAction", "adopt"); assert.equal(h.state.view.run.status, "awaiting_review"); assert.equal(h.el("strategy-approve").disabled, false); assert.equal(h.requests.filter(item => item.options.method === "POST").length, 1); assert.equal(h.requests.some(item => item.url.endsWith("/continue") || item.url.endsWith("/request") || item.url.endsWith("/decision")), false);});
await test("Modify adopts only then opens the typed scientific editor", async () => {const h = setup(science(9), candidate()); h.fetchImpl = async url => {if (url.endsWith("/inspect")) return response(scientificReview(10)); const value = model(10, "adopted"); value.suggestion.can_approve = false; return response(value);}; await h.call("suggestionAction", "adopt", true); assert.equal(h.el("strategy-edit-details").open, true); assert.equal(h.el("strategy-json").focused, true); assert.match(h.el("run-message").textContent, /Modify.*save corrections.*before approval/s); assert.equal(h.requests.filter(item => item.options.method === "POST").length, 1);});
await test("stale saved preview cannot be requested until science revision is refreshed", async () => {const h = setup(science(8), model(7, "approved")); await h.call("suggestionAction", "request"); assert.equal(h.requests.length, 0); assert.equal(h.el("suggestion-request").disabled, true);});
await test("unsaved scientific modifications prevent model mutation and preserve draft", async () => {const h = setup(scientificReview(7), model(7, "approved")), draft = strategy(); draft.clustering.resolution = .7; h.state.strategyDraftText = JSON.stringify(draft); h.call("buttons"); await h.call("suggestionAction", "request"); assert.equal(h.requests.length, 0); assert.equal(h.state.strategyDraftText, JSON.stringify(draft)); assert.equal(h.el("suggestion-preview").disabled, true);});
await test("explicit combined strategy action approves once then starts local Continue at returned revision", async () => {const h = setup(scientificReview(9), null); h.el("strategy-reviewer").value = "analyst"; h.el("strategy-reason").value = "Reviewed complete strategy"; h.fetchImpl = async (url, options) => {if (url.endsWith("/decision")) return response(scientificReview(10, true)); if (url.endsWith("/continue")) {const payload = JSON.parse(options.body), result = clone(h.state.continuation); result.duplicate = false; result.job = {job_id: "0123456789abcdef0123456789abcdef", status: "queued", request_id: payload.request_id, project_id: payload.project_id, input_hash: payload.input_hash, expected_revision: payload.expected_revision, retry: false}; result.availability.can_continue = false; return response(result);} throw new Error("Unexpected route " + url);}; await h.call("decideStrategy", "approve", true); assert.equal(h.requests.length, 2); assert.match(h.requests[0].url, /\/decision$/); assert.match(h.requests[1].url, /\/continue$/); assert.equal(JSON.parse(h.requests[1].options.body).expected_revision, 10); assert.equal(h.requests.some(item => item.url.includes("suggestion")), false);});
await test("explicit combined annotation action starts local label application without requesting a model", async () => {const h = setup(annotationReview(9), null); h.el("annotation-reviewer").value = "analyst"; h.el("annotation-reason").value = "Retain Unknown labels"; h.fetchImpl = async (url, options) => {if (url.endsWith("/decision")) return response(annotationReview(10, true)); const payload = JSON.parse(options.body), result = clone(h.state.continuation); result.duplicate = false; result.job = {job_id: "0123456789abcdef0123456789abcdef", status: "queued", request_id: payload.request_id, project_id: payload.project_id, input_hash: payload.input_hash, expected_revision: payload.expected_revision, retry: false}; result.availability.can_continue = false; return response(result);}; await h.call("decide", "approve", true); assert.equal(h.requests.length, 2); assert.equal(JSON.parse(h.requests[0].options.body).kind, "annotation"); assert.equal(JSON.parse(h.requests[1].options.body).expected_revision, 10); assert.equal(h.requests.some(item => item.url.includes("suggestion")), false);});
await test("failed scientific approval never starts combined local computation", async () => {const h = setup(scientificReview(9), null); h.el("strategy-reviewer").value = "analyst"; h.el("strategy-reason").value = "Reviewed strategy"; h.fetchImpl = async () => response({error: "Stale exact science revision"}, false); await h.call("decideStrategy", "approve", true); assert.equal(h.requests.length, 1); assert.equal(h.state.stale, true);});
await test("parent manual Unknown configuration gap is explicit and never dispatched as invented labels", () => {const value = model(); value.suggestion.kind = "annotation"; value.suggestion.available = false; value.suggestion.blocked_reason = "Manual annotation configuration required in R"; value.suggestion.can_approve = false; const h = setup(science(), value); assert.match(h.el("suggestion-message").textContent, /Manual annotation configuration required in R/); assert.equal(h.requests.length, 0);});
await test("local simulated preview does not pretend to authorize external transmission", () => {const value = model(); value.suggestion.preview.external = false; value.suggestion.preview.notice = "SIMULATED offline response; no model request or biological inference"; const h = setup(science(), value); assert.match(h.el("suggestion-approve").textContent, /Approve and run this exact simulated suggestion/); assert.match(h.el("suggestion-request").textContent, /Run this approved simulated suggestion/); assert.match(h.el("suggestion-summary").textContent, /does not transmit/);});
await test("legacy annotation without a strategy can continue after its exact approval", () => {const value = annotationReview(10, true); delete value.run.strategy_review; value.suggestion_enabled = false; const h = setup(value, null); assert.equal(h.call("canContinue", false), true); assert.equal(h.el("run-continue").disabled, false);});
await test("legacy approved QC without a strategy is not blocked by an absent strategy schema", () => {const value = science(10, true); value.run.stage = "qc_apply"; value.suggestion_enabled = false; value.continuation = {schema: "scagentkit.run-continue.workbench.v1", enabled: true, job: null, availability: {project_id: value.run.project_id, input_hash: inputHash, expected_revision: 10, can_continue: true, can_retry: false, requires_explicit_retry: false, reason: "ready"}}; const h = setup(value, null); assert.equal(h.call("canContinue", false), true);});
await test("terminal task failure remains visible even before R result metadata is available", () => {const value = model(7, "approved"); value.suggestion.can_request = false; value.job = job("interrupted"); value.job.requires_reconciliation = true; value.job.error = {message: "Simulated worker interrupted"}; const h = setup(science(), value); assert.match(h.el("suggestion-status").textContent, /interrupted/); assert.match(h.el("suggestion-message").textContent, /worker interrupted.*explicit reconciliation.*No automatic retry/s);});
await test("request receipt with another revision fails closed without a new request", async () => {const h = setup(science(), model(7, "approved")); h.fetchImpl = async (_, options) => {const value = model(7, "approved"); value.job = job("queued", 8, JSON.parse(options.body).request_id); return response(value);}; await h.call("suggestionAction", "request"); assert.equal(h.requests.length, 1); assert.equal(h.state.suggestionLost, true); assert.equal(h.timers.size, 0); assert.match(h.el("suggestion-message").textContent, /exact preview binding/);});
await test("polling a finished model task refreshes science and candidate through GET only", async () => {const value = model(7, "approved"); value.job = job("running"); const h = setup(science(), value), finished = candidate(9); finished.job = job("succeeded"); h.fetchImpl = async url => url.endsWith("/inspect") ? response(science(9)) : response(finished); await h.call("pollSuggestion", h.state.suggestionGeneration); assert.equal(h.requests.length, 3); assert.equal(h.requests.every(item => item.options.method !== "POST"), true); assert.equal(h.state.view.run.revision, 9); assert.equal(h.el("suggestion-adopt").disabled, false); assert.equal(h.timers.size, 0);});
await test("terminal model refresh preserves another tab's unsaved scientific draft", async () => {const value = model(7, "approved"); value.job = job("running"); const h = setup(scientificReview(7), value), modified = strategy(); modified.clustering.resolution = .8; h.state.strategyDraftText = JSON.stringify(modified); const finished = candidate(9); finished.job = job("succeeded"); h.fetchImpl = async () => response(finished); await h.call("pollSuggestion", h.state.suggestionGeneration); assert.equal(h.requests.length, 1); assert.equal(h.state.stale, true); assert.equal(h.state.strategyDraftText, JSON.stringify(modified)); assert.match(h.el("suggestion-message").textContent, /Unsaved scientific corrections are preserved/);});
await test("historical terminal replay is a receipt and triggers fresh readonly authority checks", async () => {const h = setup(science(), model(7, "approved")); h.fetchImpl = async (url, options) => {if (options.method === "POST") {const value = model(7, "approved"); value.duplicate = true; value.historical_receipt = true; value.suggestion.replay_only = true; value.suggestion.can_request = false; value.job = job("succeeded", 7, JSON.parse(options.body).request_id); return response(value);} if (url.endsWith("/inspect")) return response(science(9)); return response(candidate(9));}; await h.call("suggestionAction", "request"); assert.equal(h.requests.filter(item => item.options.method === "POST").length, 1); assert.equal(h.requests.filter(item => item.options.method !== "POST").length, 2); assert.equal(h.state.view.run.revision, 9); assert.equal(h.el("suggestion-adopt").disabled, false);});

function combinedFixture(h, {approved = model(8, "approved"), inspected = science(8), preview = model(8, "approved"), failure = null} = {}) {
  h.fetchImpl = async (url, options) => {
    if (url.endsWith("/approve")) {if (failure) throw new Error(failure); return response(approved);}
    if (url.endsWith("/inspect")) return response(inspected);
    if (url.endsWith("/suggestion")) return response(preview);
    if (url.endsWith("/request")) {const payload = JSON.parse(options.body), value = clone(preview); value.job = job("queued", payload.expected_revision, payload.request_id); return response(value);}
    throw new Error("Unexpected combined fixture route " + url);
  };
}
const clickCombined = h => h.el("suggestion-approve").listeners.click[0]();
await test("combined button explicitly distinguishes external, local and simulated requests", () => {
  for (const [simulated, external, expected] of [[true, false, /Approve and run this exact simulated suggestion/], [false, true, /Approve and request this exact aggregate transfer/], [false, false, /Approve and request this exact local suggestion/]]) {
    const value = model(); value.suggestion.preview.simulated = simulated; value.suggestion.preview.external = external;
    const h = setup(science(), value); assert.match(h.el("suggestion-approve").textContent, expected);
    assert.equal(h.el("suggestion-preview-details").open, true); assert.equal(h.requests.length, 0);
  }
  assert.match(html, /immediately starts its configured request.*external provider.*aggregate leaves/s);
});
await test("one explicit approve click requests the same preview at the fresh saved revision with no scientific mutation", async () => {
  const h = setup(); combinedFixture(h); await clickCombined(h);
  assert.deepEqual(h.requests.map(row => row.url), ["/api/run-review/suggestion/approve", "/api/run-review/inspect", "/api/run-review/suggestion", "/api/run-review/suggestion/request"]);
  const posts = h.requests.filter(row => row.options.method === "POST"), approved = JSON.parse(posts[0].options.body), requested = JSON.parse(posts[1].options.body);
  assert.equal(approved.expected_revision, 7); assert.equal(requested.expected_revision, 8);
  for (const key of ["project_id", "input_hash", "suggestion_hash", "reviewer", "reason"]) assert.equal(requested[key], approved[key]);
  assert.equal(h.state.view.run.revision, 8); assert.equal(h.state.suggestion.job.request_id, requested.request_id);
  assert.equal(posts.length, 2); assert.equal(h.requests.some(row => /\/(adopt|decision|continue)$/.test(row.url)), false);
});
for (const [name, mutate] of [
  ["different valid suggestion hash", v => v.suggestion.suggestion_hash = "1".repeat(64)],
  ["different valid request hash", v => v.suggestion.preview.request_hash = "2".repeat(64)],
  ["different model", v => v.suggestion.preview.model = "different-configured-model"],
  ["different generation", v => v.suggestion.preview.generation.temperature = .5],
  ["different payload", v => v.suggestion.preview.user_prompt = "A changed aggregate"],
  ["different external permission", v => v.suggestion.preview.external = false],
  ["unexpected revision", v => v.suggestion.revision = 9],
  ["request unavailable", v => v.suggestion.can_request = false],
  ["active saved task", v => v.job = job("running", 8)],
  ["uncertain accounting", v => {v.job = job("failed", 8); v.job.requires_reconciliation = true;}],
  ["historical replay", v => v.suggestion.replay_only = true]
]) await test("combined consent stops after approval if " + name, async () => {
  const h = setup(), approved = model(8, "approved"); mutate(approved); combinedFixture(h, {approved}); await clickCombined(h);
  assert.equal(h.requests.length, 1); assert.equal(h.state.suggestionLost, true); assert.equal(h.timers.size, 0);
  await clickCombined(h); assert.equal(h.requests.length, 1, "No automatic repeat after an unverified response");
});
for (const [name, values] of [
  ["project revision changed", {inspected: science(9)}],
  ["scientific stage changed", {inspected: {...science(8), run: {...science(8).run, stage: "annotation_propose"}}}],
  ["fresh suggestion hash changed", {preview: {...model(8, "approved"), suggestion: {...model(8, "approved").suggestion, suggestion_hash: "3".repeat(64)}}}],
  ["fresh request hash changed", {preview: {...model(8, "approved"), suggestion: {...model(8, "approved").suggestion, preview: {...model(8, "approved").suggestion.preview, request_hash: "4".repeat(64)}}}}],
  ["fresh task now active", {preview: {...model(8, "approved"), job: job("running", 8)}}]
]) await test("combined consent stops when readonly reconciliation finds " + name, async () => {
  const h = setup(); combinedFixture(h, values); await clickCombined(h);
  assert.equal(h.requests.filter(row => row.options.method === "POST").length, 1);
  assert.equal(h.state.suggestionLost, true); assert.equal(h.requests.some(row => row.url.endsWith("/request")), false);
});
await test("combined approval failure or lost response never requests and readonly refresh cannot replay intent", async () => {
  const h = setup(); combinedFixture(h, {failure: "Simulated approval response lost"}); await clickCombined(h);
  assert.equal(h.requests.length, 1); assert.equal(h.state.suggestionLost, true);
  combinedFixture(h); await h.call("load");
  assert.equal(h.requests.filter(row => row.options.method === "POST").length, 1); assert.equal(h.state.suggestionLost, false);
  assert.equal(h.el("suggestion-request").hidden, false, "An approved request remains available only by a new explicit click");
});
await test("combined consent blocks double clicks throughout approval and request submission", async () => {
  const h = setup(); let finishApprove, finishRequest;
  h.fetchImpl = async (url, options) => {
    if (url.endsWith("/approve")) return new Promise(resolve => {finishApprove = () => resolve(response(model(8, "approved")));});
    if (url.endsWith("/inspect")) return response(science(8));
    if (url.endsWith("/suggestion")) return response(model(8, "approved"));
    if (url.endsWith("/request")) return new Promise(resolve => {finishRequest = () => {const payload = JSON.parse(options.body), value = model(8, "approved"); value.job = job("queued", 8, payload.request_id); resolve(response(value));};});
    throw new Error("Unexpected route");
  };
  const first = clickCombined(h); await clickCombined(h); assert.equal(h.requests.length, 1); finishApprove();
  for (let turn = 0; turn < 30 && !finishRequest; turn++) await Promise.resolve();
  assert(finishRequest); await clickCombined(h); assert.equal(h.requests.filter(row => row.options.method === "POST").length, 2);
  assert.equal(h.state.suggestionChaining, true); assert.equal(h.el("run-refresh").disabled, true); assert.equal(h.el("suggestion-preview").disabled, true);
  finishRequest(); await first; assert.equal(h.requests.filter(row => row.options.method === "POST").length, 2);
  assert.equal(h.state.suggestionChaining, false);
});
await test("combined transaction remains locked throughout fresh readonly inspection", async () => {
  const h = setup(); let inspectSaved;
  h.fetchImpl = async (url, options) => {
    if (url.endsWith("/approve")) return response(model(8, "approved"));
    if (url.endsWith("/inspect")) return new Promise(resolve => {inspectSaved = () => resolve(response(science(8)));});
    if (url.endsWith("/suggestion")) {assert.equal(h.state.suggestionChaining, true); assert.equal(h.call("ready"), false); return response(model(8, "approved"));}
    if (url.endsWith("/request")) {assert.equal(h.state.suggestionChaining, true); const payload = JSON.parse(options.body), value = model(8, "approved"); value.job = job("queued", 8, payload.request_id); return response(value);}
    throw new Error("Unexpected route");
  };
  const pending = clickCombined(h); for (let turn = 0; turn < 30 && !inspectSaved; turn++) await Promise.resolve(); assert(inspectSaved);
  assert.equal(h.state.suggestionChaining, true); assert.equal(h.call("ready"), false); assert.equal(h.el("suggestion-reviewer").disabled, true);
  await clickCombined(h); await h.call("suggestionAction", "request"); assert.equal(h.requests.filter(row => row.options.method === "POST").length, 1);
  inspectSaved(); await pending; assert.equal(h.requests.filter(row => row.options.method === "POST").length, 2); assert.equal(h.state.suggestionChaining, false);
});
await test("two independent tabs cannot use an old combined consent after the other tab starts a saved request", async () => {
  const first = setup(), second = setup(); let approved = false, dispatches = 0;
  const service = async (url, options) => {
    if (url.endsWith("/approve")) {if (approved) return response({error: "Stale exact saved revision"}, false); approved = true; return response(model(8, "approved"));}
    if (url.endsWith("/inspect")) return response(science(8));
    if (url.endsWith("/suggestion")) return response(model(8, "approved"));
    if (url.endsWith("/request")) {dispatches++; const payload = JSON.parse(options.body), value = model(8, "approved"); value.job = job("queued", 8, payload.request_id); return response(value);}
    throw new Error("Unexpected route");
  };
  first.fetchImpl = service; second.fetchImpl = service; await clickCombined(first); await clickCombined(second);
  assert.equal(dispatches, 1); assert.equal(second.requests.length, 1); assert.equal(second.state.suggestionLost, true);
  assert.equal(first.state.suggestion.job.job_id, "0123456789abcdef0123456789abcdef");
});

function localContinuation(revision = 37, status = "queued") {
  return {schema: "scagentkit.run-continue.workbench.v1", enabled: true,
    availability: {project_id: "literal-project", input_hash: inputHash, expected_revision: revision, can_continue: false, can_retry: false, requires_explicit_retry: false, reason: status === "succeeded" ? "complete" : "active saved task"},
    job: {job_id: "saved-local-task", request_id: "existing-local-request", project_id: "literal-project", input_hash: inputHash, expected_revision: 37,
      retry: false, retry_permitted: false, status, created_at: "2026-10-05T00:00:00Z", updated_at: "2026-10-05T00:00:01Z", error: null,
      ...(status === "succeeded" ? {next_run_revision: revision, next_run_stage: "complete", next_run_status: "complete"} : {})}};
}
function localPollingClient() {
  const value = scientificReview(37, true); value.suggestion_enabled = false; value.continuation = localContinuation();
  const h = setup(value, null); h.state.pendingRequest = {project_id: "literal-project", input_hash: inputHash, expected_revision: 37, request_id: "existing-local-request", retry: false};
  return h;
}
await test("slow readonly local status uses the R IPC bound and preserves the identical saved task without POST", async () => {
  const h = localPollingClient(), prior = clone(h.state.continuation), pendingRequest = clone(h.state.pendingRequest); let finish, signal;
  h.fetchImpl = async (_, options) => new Promise(resolve => {signal = options.signal; finish = () => resolve(response(prior));});
  const pending = h.call("pollJob", h.state.pollGeneration), [timer] = h.timers.values();
  const runtime = fs.readFileSync(path.join(repo, "workbench/qc_runtime.py"), "utf8"), ipc = runtime.match(/^    def __init__\([^\n]*timeout=(\d+)\):/m);
  assert(ipc); assert.equal(timer.delay, Number(ipc[1]) * 1000 + 5000); assert.equal(timer.delay, 125000); assert.equal(signal.aborted, false);
  assert.equal(h.requests.length, 1); assert.equal(h.requests[0].url, "/api/run-review/continuation");
  assert.equal(h.requests[0].options.method, undefined); assert.equal(h.requests[0].options.headers["X-ScAgentKit-Run-Project"], "literal-project");
  assert.equal(h.state.continuation.job.job_id, prior.job.job_id); assert.equal(h.el("run-continue").disabled, true);
  finish(); await pending;
  assert.equal(signal.aborted, false); assert.deepEqual(clone(h.state.continuation), prior); assert.deepEqual(clone(h.state.pendingRequest), pendingRequest);
  assert.equal(h.state.connectionLost, false); assert.equal(h.requests.length, 1); assert.equal(h.timers.size, 1);
  assert.equal([...h.timers.values()][0].delay, 1000, "Only the ordinary read-only next poll remains; the HTTP abort timer was cleared");
});
await test("readonly local status timeout preserves the saved job and blocks new work until explicit saved-state refresh", async () => {
  const h = localPollingClient(), prior = clone(h.state.continuation); let signal;
  h.fetchImpl = async (_, options) => new Promise((_, reject) => {signal = options.signal; signal.addEventListener("abort", () => reject(new Error("Simulated bounded status abort")), {once: true});});
  const pending = h.call("pollJob", h.state.pollGeneration), [timer] = h.timers.values(); assert.equal(timer.delay, 125000); timer.callback(); await pending;
  assert.equal(signal.aborted, true); assert.equal(h.state.connectionLost, true); assert.equal(h.state.stale, true); assert.deepEqual(clone(h.state.continuation), prior);
  assert.equal(h.el("run-continue").disabled, true); assert.equal(h.el("strategy-approve").disabled, true); assert.equal(h.timers.size, 0);
  h.call("schedulePoll"); await h.call("continueRun", false); assert.equal(h.timers.size, 0); assert.equal(h.requests.length, 1);
  assert.match(h.el("run-message").textContent, /Refresh.*will not relaunch it automatically/s);
  const refreshed = science(42); refreshed.suggestion_enabled = false; refreshed.run.status = "complete"; refreshed.run.stage = "complete"; refreshed.continuation = localContinuation(42, "succeeded");
  h.fetchImpl = async url => {assert(url.endsWith("/inspect")); return response(refreshed);}; await h.call("load");
  assert.equal(h.state.connectionLost, false); assert.equal(h.state.stale, false); assert.equal(h.state.view.run.revision, 42);
  assert.equal(h.state.continuation.job.job_id, prior.job.job_id); assert.equal(h.state.continuation.job.request_id, prior.job.request_id);
  assert.equal(h.requests.length, 2); assert.equal(h.requests.every(row => row.options.method !== "POST"), true); assert.equal(h.timers.size, 0);
});
for (const [name, mutate] of [["unknown task status", value => value.job.status = "unverified"], ["foreign saved task", value => value.job.project_id = "another-project"]])
  await test("readonly local status rejects " + name + " without replacing its last saved binding", async () => {
    const h = localPollingClient(), prior = clone(h.state.continuation), unknown = clone(prior); mutate(unknown); h.fetchImpl = async () => response(unknown);
    await h.call("pollJob", h.state.pollGeneration); assert.equal(h.state.connectionLost, true); assert.equal(h.state.stale, true);
    assert.deepEqual(clone(h.state.continuation), prior); assert.equal(h.el("run-continue").disabled, true); assert.equal(h.el("strategy-approve").disabled, true);
    assert.equal(h.requests.length, 1); assert.equal(h.timers.size, 0); h.call("schedulePoll"); await h.call("continueRun", false); assert.equal(h.requests.length, 1);
  });
await test("local Continue POST retains its existing 15-second response deadline", async () => {
  const h = localPollingClient(); let finish; const payload = clone(h.state.pendingRequest);
  h.fetchImpl = async (_, options) => new Promise(resolve => {assert.equal(options.method, "POST"); finish = () => resolve(response(localContinuation()));});
  const pending = h.call("continuationRequest", payload), [timer] = h.timers.values(); assert.equal(timer.delay, 15000);
  finish(); const answer = await pending; assert.equal(answer.job.job_id, "saved-local-task"); assert.equal(h.timers.size, 0);
});

const report = {schema: "scagentkit.unified-suggestion.offline-dom-tests.v1", actualProductionSource: true, actualBrowser: false, actualRBridge: false, simulatedHTTP: true, networkRequests: 0, providerRequests: 0, keyReads: 0, sourceSha256: createHash("sha256").update(source).digest("hex"), htmlSha256: createHash("sha256").update(html).digest("hex"), driverSha256: createHash("sha256").update(fs.readFileSync(fileURLToPath(import.meta.url))).digest("hex"), tests: results.length, passed: results.filter(item => item.passed).length, failed: results.filter(item => !item.passed).length, results};
if (process.argv[2]) fs.writeFileSync(path.resolve(process.argv[2]), JSON.stringify(report, null, 2) + "\n");
process.stdout.write(JSON.stringify(report, null, 2) + "\n");
if (report.failed) process.exitCode = 1;
