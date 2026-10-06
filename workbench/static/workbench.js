"use strict";
const WB_SECTIONS = ["overview", "qc", "strategy", "analysis", "annotation", "children", "outputs", "history"];
const wbState = {view: null, scopes: null, projectId: null, child: false, section: "overview", clusterId: null, busy: false, failed: false};
const wb$ = id => document.getElementById(id);
const wbArray = value => value == null ? [] : Array.isArray(value) ? value : [value];
const wbHash = value => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
const wbCanonical = value => JSON.stringify(value, (_, item) => item && typeof item === "object" && !Array.isArray(item) ? Object.fromEntries(Object.keys(item).sort().map(key => [key, item[key]])) : item);
const wbText = value => value == null ? "Unavailable" : typeof value === "object" ? JSON.stringify(value, null, 2) : String(value);
function wbNode(tag, text, attrs = {}) {const node = document.createElement(tag); if (text != null) node.textContent = String(text); for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, String(value)); return node;}
function wbEmpty(target, text) {target.append(wbNode("p", text, {class: "wb-empty"}));}
function wbFacts(value) {const list = wbNode("dl", null, {class: "wb-facts"}); for (const [key, item] of Object.entries(value || {})) list.append(wbNode("dt", key.replace(/_/g, " ")), wbNode("dd", wbText(item))); return list;}
function wbRecord(title, value) {const details = wbNode("details"); details.append(wbNode("summary", title), wbNode("pre", wbText(value), {class: "wb-record"})); return details;}
function wbCard(title, ...content) {const card = wbNode("section", null, {class: "wb-card"}); if (title) card.append(wbNode("h3", title)); card.append(...content); return card;}
function wbTable(headings, rows) {const wrap = wbNode("div", null, {class: "table-wrap"}), table = wbNode("table"), head = wbNode("thead"), tr = wbNode("tr"), body = wbNode("tbody"); for (const title of headings) tr.append(wbNode("th", title)); head.append(tr); table.append(head); for (const values of rows) {const row = wbNode("tr"); for (const value of values) row.append(wbNode("td", wbText(value))); body.append(row);} table.append(body); wrap.append(table); return wrap;}
function wbScopeQuery() {
  const query = new URLSearchParams(window.location.search || "");
  if ([...query.keys()].some(key => !["project_id", "child_id"].includes(key))) throw new Error("Only a registered project identity is accepted in this URL.");
  for (const key of ["project_id", "child_id"]) if (query.has(key) && (query.getAll(key).length !== 1 || !query.get(key) || query.get(key).length > 200 || /[\x00-\x1f\x7f]/.test(query.get(key)))) throw new Error("Open one literal registered project scope; this URL is invalid.");
  const selected = {project_id: query.get("project_id"), child_id: query.get("child_id")};
  if (selected.child_id && selected.project_id && selected.child_id !== selected.project_id) throw new Error("The child and project identities do not match.");
  if (wbState.projectId && (selected.child_id || selected.project_id || wbState.scopes?.parent.project_id) !== wbState.projectId) throw new Error("This page's project URL changed. Open the registered project in a fresh page.");
  return selected;
}
function wbScopeURL(path, id, child = false) {const query = new URLSearchParams(); if (child) query.set("child_id", id); query.set("project_id", id); return path + "?" + query.toString();}
function wbVerifyScopes(value) {
  const parent = value?.parent;
  if (value?.schema !== "scagentkit.run-scopes.workbench.v1" || typeof parent?.project_id !== "string" || !parent.project_id || !wbHash(parent.input_hash) || !Number.isInteger(parent.revision)) throw new Error("The registered project list is unverified.");
  const seen = new Set([parent.project_id]);
  for (const child of wbArray(value.children)) {if (typeof child?.project_id !== "string" || !child.project_id || seen.has(child.project_id) || Object.hasOwn(child, "project_dir") || !Number.isInteger(child.revision)) throw new Error("The child registry has invalid identities."); seen.add(child.project_id);}
  const selected = wbScopeQuery(), id = selected.child_id || selected.project_id || parent.project_id;
  if (!seen.has(id) || selected.child_id === parent.project_id || !selected.child_id && id !== parent.project_id) throw new Error("This URL does not name the parent or one registered child.");
  if (wbState.scopes && parent.project_id !== wbState.scopes.parent.project_id) throw new Error("The service's parent binding changed.");
  return value;
}
function wbVerify(value) {
  const project = value?.project, run = value?.run, binding = value?.binding, selected = wbScopeQuery();
  const id = selected.child_id || selected.project_id || wbState.scopes?.parent.project_id;
  if (value?.schema !== "scagentkit.workbench.v1" || value.readonly !== true || project?.project_id !== id || run?.schema !== "scagentkit.run.v1" || run.project_id !== id || typeof run.status !== "string" || typeof run.stage !== "string" || !wbHash(project.input_hash) || !Number.isInteger(project.revision) || project.revision < 0 || run.input_hash !== project.input_hash || run.revision !== project.revision || binding?.project_id !== id || binding.input_hash !== project.input_hash || binding.revision !== project.revision || !wbHash(binding.state_sha256) || !["parent", "child"].includes(project.scope) || (project.scope === "child") !== Boolean(selected.child_id) || typeof project.frozen !== "boolean") throw new Error("The saved snapshot does not match this exact project and input.");
  const history = value.history;
  if (history?.schema !== "scagentkit.run-history.v1" || !Array.isArray(history.events) || history.head !== project.history_head || binding.history_head !== project.history_head || run.history_head !== project.history_head) throw new Error("The saved history and snapshot binding do not match.");
  let previous = "0".repeat(64), sequence = 0;
  for (const event of history.events) {if (!Number.isInteger(event.sequence) || event.sequence <= sequence || !wbHash(event.hash) || !wbHash(event.previous_hash) || typeof event.action !== "string" || !event.action || typeof event.created_at !== "string" || event.sequence === 1 && event.previous_hash !== previous || sequence && event.sequence === sequence + 1 && event.previous_hash !== previous) throw new Error("Saved history records have inconsistent sequence or hash links."); previous = event.hash; sequence = event.sequence;}
  if (history.events.length && history.truncated !== true && previous !== history.head) throw new Error("The supplied history does not reach the saved head.");
  if (history.provided_events != null && history.provided_events !== history.events.length || history.truncated !== true && history.total_events != null && history.total_events !== history.events.length || history.truncated !== true && history.events.length !== run.revision) throw new Error("Saved history counts do not match the supplied event records.");
  const registeredChildren = new Set(wbArray(wbState.scopes?.children).map(child => child.project_id));
  for (const child of wbArray(value.children)) if (!registeredChildren.has(child?.project_id) || Object.hasOwn(child, "project_dir")) throw new Error("The workspace changed or supplied an unregistered child; refresh this scope.");
  const audit = value.integration_history;
  if (audit != null) {
    if (project.scope !== "child" || audit.schema !== "scagentkit.subcluster.integration-history.v1" || !Number.isInteger(audit.revision) || audit.revision < 0 || !Array.isArray(audit.events) || audit.events.length !== audit.revision || audit.total_events !== audit.events.length || audit.provided_events !== audit.events.length || audit.truncated !== false || binding.integration_revision !== audit.revision || binding.integration_history_head !== audit.head) throw new Error("The child application audit is not bound to this exact saved snapshot.");
    if (audit.authority === "not_created") {
      if (audit.revision !== 0 || audit.head !== null || binding.integration_state_sha256 !== null) throw new Error("An uncreated application audit cannot supply saved journal facts.");
    } else {
      if (audit.authority !== "reintegration/state.rds" || !wbHash(binding.integration_state_sha256) || !wbHash(audit.head) || !audit.events.length) throw new Error("The child application audit has no verified saved journal authority.");
      let prior = "0".repeat(64);
      for (const [index, event] of audit.events.entries()) {if (event.sequence !== index + 1 || event.previous_hash !== prior || !wbHash(event.hash) || typeof event.action !== "string" || !event.action || typeof event.created_at !== "string") throw new Error("The child application audit has inconsistent sequence or hash links."); prior = event.hash;}
      if (prior !== audit.head) throw new Error("The child application audit does not reach its own saved head.");
    }
  }
  const kind = value.evidence_kind, stageRecords = binding.stage_checkpoint_records;
  if (!["final_output_bundle", "saved_analysis_checkpoint", "unavailable"].includes(kind) || (kind === "unavailable") !== (value.evidence == null) || value.evidence_complete !== (value.evidence != null)) throw new Error("The saved evidence source and completeness are undeclared or inconsistent.");
  if (kind !== "saved_analysis_checkpoint" && [stageRecords, binding.stage_records_hash, binding.stage_scope_hash].some(item => item !== null)) throw new Error("Final or unavailable evidence cannot claim a pending checkpoint binding.");
  if (kind === "saved_analysis_checkpoint") {
    const names = ["analysis", "annotation_evidence", "markers"], snapshot = value.evidence?.parameters?.savedStageSnapshot;
    if (run.status === "complete" || !["annotation_propose", "annotation_apply"].includes(run.stage) || run.output?.bundle || binding.evidence_project_id !== id || !stageRecords || wbCanonical(Object.keys(stageRecords).sort()) !== wbCanonical(names) || !wbHash(binding.stage_records_hash) || !wbHash(binding.stage_scope_hash) || !wbHash(run.config_hash) || !wbHash(run.implementation_hash)) throw new Error("Saved analysis checkpoints are unavailable or do not belong to this pending annotation scope.");
    for (const name of names) {const record = stageRecords[name]; if (!record || wbCanonical(Object.keys(record).sort()) !== wbCanonical(["path", "sha256"]) || typeof record.path !== "string" || !new RegExp("^checkpoints/" + name + "-[a-f0-9]{64}\\.rds$").test(record.path) || !wbHash(record.sha256)) throw new Error("A saved analysis checkpoint receipt is invalid.");}
    if (!snapshot || snapshot.stateSHA !== binding.state_sha256 || snapshot.inputHash !== run.input_hash || snapshot.configHash !== run.config_hash || snapshot.implementationHash !== run.implementation_hash || snapshot.revision !== run.revision || snapshot.historyHead !== run.history_head || snapshot.scopeHash !== binding.stage_scope_hash || snapshot.bundleScopeHash !== binding.bundle_cell_scope_hash || wbCanonical(snapshot.records) !== wbCanonical(stageRecords)) throw new Error("The displayed analysis checkpoint does not match this exact saved run and receipt.");
    if (wbArray(value.evidence?.clusters).some(cluster => wbArray(cluster.sourceAnnotations).length || cluster.sourceLabels != null)) throw new Error("Pending analysis evidence cannot present annotation labels as saved output.");
  }
  if (value.evidence != null) {
    const evidence = value.evidence, owner = binding.evidence_project_id;
    if (value.evidence_complete !== true || typeof owner !== "string" || evidence.projectId !== owner || !wbHash(binding.bundle_digest) || !wbHash(binding.source_fingerprint) || !wbHash(binding.bundle_cell_scope_hash) || evidence.bundleDigest !== binding.bundle_digest || evidence.sourceFingerprint !== binding.source_fingerprint || !Array.isArray(evidence.clusters) || !Array.isArray(evidence.umap)) throw new Error("The saved evidence is not a complete, bound snapshot of this project's declared source.");
    const clusters = new Set(), cells = new Map();
    for (const cluster of evidence.clusters) {
      if (typeof cluster.id !== "string" || !cluster.id || clusters.has(cluster.id) || !Array.isArray(cluster.cellIds) || !Number.isInteger(cluster.cellCount) || cluster.cellCount !== cluster.cellIds.length) throw new Error("The saved literal cluster scope is inconsistent."); clusters.add(cluster.id);
      for (const cell of cluster.cellIds) {if (typeof cell !== "string" || !cell || cells.has(cell)) throw new Error("The saved output has duplicate or invalid cell IDs."); cells.set(cell, cluster.id);}
      for (const marker of wbArray(cluster.markers)) if (typeof marker?.gene !== "string" || !marker.gene || marker.clusterId !== cluster.id) throw new Error("A marker row belongs to another literal cluster.");
    }
    if (evidence.dataset?.retainedCells !== cells.size || evidence.dataset?.clusterCount !== clusters.size) throw new Error("Saved output counts do not match the supplied exact scope.");
    const points = new Set(); for (const point of evidence.umap) {if (!cells.has(point.cellId) || cells.get(point.cellId) !== point.clusterId || points.has(point.cellId) || !Number.isFinite(point.x) || !Number.isFinite(point.y)) throw new Error("The saved embedding has a foreign cell, duplicate point or invalid coordinate."); points.add(point.cellId);}
    if (points.size && points.size !== cells.size) throw new Error("The supplied embedding does not cover this exact saved output scope.");
  }
  return value;
}
function wbProvider() {
  const provider = wbState.view.provider || {}, badge = wb$("wb-model"); badge.hidden = false;
  if (provider.name === "mock") {badge.textContent = "Configured mock · simulated suggestions"; badge.className = "pill simulated-badge";}
  else if (provider.name === "manual") {badge.textContent = "Manual configuration · no provider selected"; badge.className = "pill muted";}
  else if (typeof provider.name === "string" && provider.name) {badge.textContent = "Configured provider: " + provider.name + (provider.model ? " / " + provider.model : ""); badge.className = "pill muted";}
  else {badge.textContent = "Provider configuration unavailable"; badge.className = "pill muted";}
}
function wbProjection(target, name, value) {
  if (!value || typeof value !== "object") return;
  if (value.truncated === true || value.partial === true || value.status === "partial") target.append(wbNode("p", name + " is a bounded projection. Supplied records are shown; omitted details stay in the saved server-side artifacts.", {class: "wb-scope-warning"}), wbRecord("Projection counts and omitted fields", value));
}
function wbRenderScopes() {
  const list = wb$("wb-scopes"); list.replaceChildren();
  for (const [item, child] of [[wbState.scopes.parent, false], ...wbArray(wbState.scopes.children).map(item => [item, true])]) {
    const link = wbNode("a", (child ? "Child · " : "Parent · ") + item.project_id, {href: wbScopeURL("/workbench", item.project_id, child), "data-project-id": item.project_id});
    link.append(wbNode("small", item.status + " · revision " + item.revision)); if (item.project_id === wbState.projectId) link.setAttribute("aria-current", "page"); list.append(link);
  }
}
function wbSelectSection(section, updateURL = false) {
  wbState.section = WB_SECTIONS.includes(section) ? section : "overview";
  for (const item of WB_SECTIONS) wb$("wb-section-" + item).hidden = item !== wbState.section && !(wbState.section === "overview" && item === "analysis");
  for (const link of wb$("wb-navigation").children) {if (link.getAttribute("data-section") === wbState.section) link.setAttribute("aria-current", "page"); else link.removeAttribute("aria-current");}
  const group = ["analysis", "annotation"].includes(wbState.section) ? "figures" : ["outputs", "history", "children"].includes(wbState.section) ? "results" : "overview";
  for (const link of wb$("wb-primary-navigation").children) {if (link.getAttribute("data-view") === group) link.setAttribute("aria-current", "page"); else link.removeAttribute("aria-current");}
  if (updateURL) window.location.hash = wbState.section;
}
// Display saved aggregate records only. These helpers never evaluate a filter,
// infer a biological role, sum overlapping exclusions or authorize a stage.
const wbCount = value => typeof value === "number" && Number.isFinite(value) && value >= 0 ? value.toLocaleString() : "Unavailable";
const wbNumber = value => typeof value === "number" && Number.isFinite(value) ? String(value) : "Unavailable";
const wbPreviewNumber = value => typeof value === "number" && Number.isFinite(value) ? value.toFixed(2) : "Unavailable";
const wbSelector = value => value && Object.keys(value).length ? Object.entries(value).map(([key, item]) => key + "=" + wbText(item)).join(" · ") : "All declared cells";
function wbQCRecord() {const value = wbState.view; return value.qc?.preview?.details || value.strategy?.review?.details?.qc_impact || null;}
function wbQCProposal() {return wbQCRecord()?.canonical_parameters?.proposal || wbState.view.strategy?.review?.details?.canonical_proposal?.qc || null;}
function wbStageCountRecord(name) {
  const value = wbState.view, counts = value.analysis?.computed_diagnostics?.stage_counts || value.run.computed_diagnostics?.stage_counts;
  const sources = {input: ["input_checkpoint"], qc: ["executed_quality_qc_checkpoint"], selection: ["executed_doublet_selection_checkpoint"], analysis: ["executed_analysis_checkpoint", "processed_reused_analysis_checkpoint"], output: ["final_output_checkpoint"]};
  const record = counts?.[name];
  if (counts?.schema !== "scagentkit.stage-counts.v1" || record?.status !== "saved" || !sources[name]?.includes(record.source) || !wbHash(record.artifact_sha256) || !Number.isInteger(record.cells) || record.cells < 0) return null;
  if (name === "analysis" && value.evidence_kind === "saved_analysis_checkpoint" && record.artifact_sha256 !== value.binding.stage_checkpoint_records.analysis.sha256) return null;
  return record;
}
function wbRenderStageCountDetails() {
  const details = wbNode("details", null, {class: "wb-workflow-detail"}); details.append(wbNode("summary", "Actual saved cell counts by stage"), wbNode("p", "These are verified saved checkpoint sizes. Missing stages remain unavailable; proposal retention and overlapping filter hits do not populate these counts."));
  const rows = [["input", "Input"], ["qc", "Quality QC"], ["selection", "Separate doublet selection"], ["analysis", "Analysis"], ["output", "Final output"]].map(([name, title]) => {const record = wbStageCountRecord(name); return [title, record ? wbCount(record.cells) : "Unavailable", record ? "Saved checkpoint" : wbState.view.source?.start_stage === "processed" && ["qc", "selection"].includes(name) ? "Reused; no execution in this run" : "Not recorded", record?.source ?? "Unavailable"];});
  details.append(wbTable(["Stage", "Actual cells", "Recorded state", "Source"], rows));
  const counts = wbState.view.analysis?.computed_diagnostics?.stage_counts || wbState.view.run.computed_diagnostics?.stage_counts;
  const prefilter = counts?.prefilter;
  if (counts?.schema === "scagentkit.stage-counts.v1" && prefilter?.status === "saved" && prefilter.source === "verified_prefilter_record" && wbHash(prefilter.artifact_sha256) && [prefilter.original_cells, prefilter.eligible_cells, prefilter.excluded_cells].every(count => Number.isInteger(count) && count >= 0)) details.append(wbNode("p", "Recorded minimal prefilter: " + wbText(prefilter.method) + "; original " + wbCount(prefilter.original_cells) + "; eligible for scoring " + wbCount(prefilter.eligible_cells) + "; excluded " + wbCount(prefilter.excluded_cells) + ". It precedes fixed doublet scoring and later quality QC."));
  details.append(wbRecord("Saved count sources and artifact fingerprints", counts || "Unavailable")); return details;
}
function wbRuleText(rule) {
  if (rule.op === "mad_preset") return "MAD preset " + wbText(rule.preset_id);
  if (rule.op !== "range") return "Recorded rule (inspect details)";
  const bounds = []; if (typeof rule.min === "number" && Number.isFinite(rule.min)) bounds.push("≥ " + rule.min); if (typeof rule.max === "number" && Number.isFinite(rule.max)) bounds.push("≤ " + rule.max);
  return wbText(rule.metric) + " " + (bounds.join(" and ") || "bounds unavailable") + " · " + wbSelector(rule.group);
}
function wbQCDetails() {
  const record = wbQCRecord(), proposal = wbQCProposal(), details = wbNode("details", null, {class: "wb-workflow-detail"});
  details.append(wbNode("summary", "Exact QC thresholds, scopes and retention"));
  if (!proposal) {wbEmpty(details, "No saved threshold proposal. Unrun QC has no inferred default thresholds."); return details;}
  const rules = wbArray(proposal.rules || proposal.filters), impacts = wbArray(record?.filter_impacts);
  const logic = proposal.schema === "scagentkit.qc.rules.v1" ? proposal.remove_if === "any" ? "Remove on ANY failed rule (OR failures)." : proposal.remove_if === "all" ? "Remove on ALL failed rules (AND failures)." : "Combination unavailable." : Array.isArray(proposal.filters) ? "Retain cells satisfying every applicable range (AND retention)." : proposal.preset_id ? "Use the exact saved MAD preset; its group thresholds remain in the saved panel." : "Saved combination unavailable; inspect the exact proposal.";
  details.append(wbNode("p", logic + " Independent filter hits can overlap; their counts are not added to obtain removed cells."));
  if (rules.length) details.append(wbTable(["Rule", "Declared scope", "Lower bound", "Upper bound", "Independent hits", "Exclusive hits"], rules.map((rule, i) => [rule.op === "mad_preset" ? "MAD " + wbText(rule.preset_id) : rule.metric || rule.op, rule.op === "mad_preset" ? "Every saved MAD group; expand thresholds below" : wbSelector(rule.group), rule.min == null ? "No lower bound" : wbNumber(rule.min), rule.max == null ? "No upper bound" : wbNumber(rule.max), wbCount(impacts[i]?.independently_removed), wbCount(impacts[i]?.exclusively_removed)])));
  const retention = record?.retention;
  if (retention) {details.append(wbNode("p", "Saved quality-QC preview, with overlapping removals counted once: before " + wbCount(retention.before) + "; retained " + wbCount(retention.retained) + "; removed " + wbCount(retention.removed) + ". This projection is not an execution receipt.")); const groups = wbArray(retention.groups); if (groups.length) details.append(wbTable(["Group", "Exact selector", "Before", "Projected retained", "Projected removed"], groups.map(group => [group.group_id, wbSelector(group.selector), wbCount(group.before), wbCount(group.retained), wbCount(group.removed)])));}
  const panel = record?.mad_panel || wbState.view.strategy?.review?.details?.mad_panel;
  if (panel) {
    details.append(wbNode("p", "MAD thresholds differ by the exact declared QC group. Strict comparisons and transformations use saved exact values; high RNA is flagged, and the panel does not imply a donor/capture relationship."));
    const rows = []; for (const group of wbArray(panel.groups)) for (const [metric, measurement] of Object.entries(group.metrics || {})) rows.push([group.group_id, group.value ?? "Unavailable", metric, measurement.available === true ? "Available" : "Unavailable", measurement.transform ?? "Unavailable", wbNumber(measurement.exact?.lower_raw), wbNumber(measurement.exact?.lower_transformed), wbNumber(measurement.exact?.upper_raw), measurement.tail ?? "Unavailable"]);
    if (rows.length) details.append(wbTable(["Group", "Literal group value", "Metric", "Availability", "Transformation", "Exact raw lower", "Exact transformed lower", "Exact raw upper", "Supported action"], rows));
    details.append(wbRecord("Saved MAD panel and exact group thresholds", panel));
  }
  if (record?.overlap) details.append(wbRecord("Saved overlap counts; no summed deletion total", record.overlap));
  const strategy = wbState.view.strategy?.review?.details;
  if (strategy?.prefilter) details.append(wbRecord("Recorded minimal prefilter before doublet scoring", strategy.prefilter));
  const doublet = strategy?.canonical_proposal?.doublet;
  if (doublet) details.append(wbNode("p", "Separate doublet policy: " + wbText(doublet.method) + ". Only the recorded QC-survivor intersection can be removed; doublet counts are not added to independent QC hits."), wbRecord("Saved doublet policy and exact intersection preview", {choice: doublet, impact: strategy.applicability?.doublet, diagnostic: strategy.doublet_diagnostics}));
  details.append(wbRecord("Exact saved threshold proposal", proposal)); return details;
}
function wbStageDone(names) {const run = wbState.view.run; return names.some(name => wbArray(run.completed).includes(name) || run.nodes?.[name] === "EXECUTED");}
function wbFlowStatus(names, {reused = false, executed = false, suggested = false, approved = false, executionStages = names} = {}) {
  const run = wbState.view.run;
  if (reused) return "Reused";
  if (run.status === "failed" && names.includes(run.stage) || names.some(name => run.nodes?.[name] === "FAILED")) return "Failed";
  if (executed || wbStageDone(executionStages)) return "Executed";
  if (approved) return "Approved · awaiting execution";
  if (run.status === "rejected" && names.includes(run.stage)) return "Rejected";
  if (names.some(name => ["DEFERRED", "NEEDS_CONFIGURATION"].includes(run.nodes?.[name])) || run.status === "awaiting_configuration" && names.includes(run.stage)) return "Deferred · configuration needed";
  if (suggested || names.some(name => run.nodes?.[name] === "PROPOSED")) return "Suggested · awaiting review";
  if (names.some(name => run.nodes?.[name] === "RUNNING")) return "Running";
  return "Not run";
}
function wbCurrentApproved(kind, review) {
  const node = wbState.view.run.review_node;
  return Boolean(wbHash(review?.hash) && node?.kind === kind && node.review_hash === review.hash && typeof node.decision_id === "string" && node.decision_id && node.can_decide === false && node.undone !== true);
}
function wbNextStepText() {
  const run = wbState.view.run;
  if (run.status === "complete") {
    const scopeAvailable = wbState.scopes.workspace_enabled !== false && wbState.scopes.parent.ready;
    if (scopeAvailable && wbState.child) return "Explore clusters and labels, or inspect label writeback to the parent.";
    if (scopeAvailable) return "Explore clusters and labels, or select cells for an independent analysis.";
    return "Explore a cluster and its markers, or inspect the saved labels in Review.";
  }
  if (run.status === "awaiting_review") return "Inspect the saved proposal and its impact before approving or revising.";
  if (run.status === "failed") return "Inspect the saved failure in Review. Retry must be explicit; refresh only reads saved evidence.";
  if (run.status === "rejected") return "Revise the rejected proposal before a new approval.";
  if (run.status === "awaiting_configuration") return "Choose the required configuration in Review; no default is silently executed.";
  if (run.status === "ready" && [["strategy", wbState.view.strategy?.review], ["qc", wbState.view.qc?.preview], ["annotation", wbState.view.annotation?.review]].some(([kind, review]) => wbCurrentApproved(kind, review))) return "Decision saved. Continue explicitly in Review or resume in R.";
  return "Inspect Review for the next supported action. Refresh only reads saved evidence.";
}
function wbRenderFlow() {
  const value = wbState.view, run = value.run, reused = value.source?.start_stage === "processed", strategy = value.strategy?.review, plan = strategy?.details?.canonical_proposal, record = wbQCRecord(), proposal = wbQCProposal(), execution = value.strategy?.summary?.execution;
  const annotation = value.annotation?.review, retention = record?.retention, diagnostics = run.diagnostics, rules = wbArray(proposal?.rules || proposal?.filters), qcApplied = wbStageDone(["qc_apply", "strategy_apply"]);
  const ruleSummary = rules.length ? rules.slice(0, 2).map(wbRuleText).join("; ") + (rules.length > 2 ? "; +" + (rules.length - 2) + " more scoped rules" : "") : proposal?.preset_id ? "Saved MAD preset: " + proposal.preset_id : proposal ? "Saved proposal has no range filters" : "Thresholds unavailable; no default applied";
  const pcPlan = plan?.pcs, actualPCs = execution?.neighbors?.pcs, parameters = plan?.analysis || value.analysis?.parameters;
  const basis = parameters ? [parameters.normalization_method, typeof parameters.nfeatures === "number" && Number.isFinite(parameters.nfeatures) ? "HVGs " + wbNumber(parameters.nfeatures) : null, typeof parameters.npcs === "number" && Number.isFinite(parameters.npcs) ? "PCA " + wbNumber(parameters.npcs) : null].filter(Boolean).join(" · ") || "Parameters unavailable" : "Parameters unavailable";
  const analysisExecuted = value.analysis?.foundation_executed === true || wbStageDone(["analysis"]) || Boolean(wbStageCountRecord("analysis"));
  const unavailablePCs = analysisExecuted ? "Executed PC count is not exposed by the current saved projection" : "selected count unavailable until recorded execution";
  const pcText = actualPCs?.ndim != null ? "Executed PCs " + wbText(actualPCs.ndim) + " · " + wbText(actualPCs.denominator) : pcPlan ? "Saved PC policy: " + (pcPlan.method === "fixed" ? wbText(pcPlan.ndim) + " fixed PCs" : wbText(pcPlan.threshold) + " / " + wbText(pcPlan.method)) + "; " + unavailablePCs : "PC policy unavailable";
  const clusterPlanText = plan?.clustering?.resolution != null ? "Saved resolution " + wbNumber(plan.clustering.resolution) : "Resolution unavailable";
  const clusterText = execution?.cluster?.resolution != null ? "Executed resolution " + wbNumber(execution.cluster.resolution) : clusterPlanText;
  const markerCount = value.evidence ? wbArray(value.evidence.clusters).reduce((count, cluster) => count + wbArray(cluster.markers).length, 0) : null;
  const approvalKind = strategy ? "strategy" : "qc", approvalReview = strategy || value.qc?.preview;
  const inputCount = wbStageCountRecord("input"), qcCount = wbStageCountRecord("qc"), selectionCount = wbStageCountRecord("selection"), analysisCount = wbStageCountRecord("analysis"), outputCount = wbStageCountRecord("output");
  const actualQC = inputCount || qcCount || selectionCount ? ". Actual checkpoint cells: input " + wbCount(inputCount?.cells) + "; quality QC " + wbCount(qcCount?.cells) + "; separate doublet selection " + wbCount(selectionCount?.cells) : ". Actual stage counts unavailable" + (retention ? "; preview only" : "");
  const qcStatus = wbFlowStatus(["qc_apply", "strategy_apply"], {reused, executed: qcApplied || Boolean(qcCount), suggested: Boolean(proposal), approved: wbCurrentApproved(approvalKind, approvalReview)});
  const selectionStatus = qcStatus === "Executed" && qcCount && !selectionCount && plan?.doublet && !qcApplied ? "QC executed · selection not recorded" : qcStatus;
  const ruleLogic = proposal?.schema === "scagentkit.qc.rules.v1" ? (proposal.remove_if === "all" ? "ALL " : proposal.remove_if === "any" ? "ANY " : "Unavailable ") + rules.length + " rules fail" : rules.length ? "Saved range rules" : "Rules unavailable";
  const compactValues = {input: wbCount(inputCount?.cells ?? diagnostics?.cell_count) + " cells", qc: (qcCount ? wbCount(qcCount.cells) + " saved" : retention ? "Projected " + wbCount(retention.retained) : "Unavailable") + " · " + ruleLogic, decision: wbCurrentApproved(approvalKind, approvalReview) ? "Decision saved" : "Saved " + wbText(plan?.pcs?.method), foundation: reused ? "Reused" : actualPCs?.ndim != null ? wbText(actualPCs.ndim) + " executed PCs" : "PC count unavailable", markers: markerCount == null ? "Unavailable" : wbCount(markerCount) + " rows", annotation: Array.isArray(annotation?.details?.annotations) ? annotation.details.annotations.length + " saved suggestions" : "Unavailable", output: run.status === "complete" && run.output ? wbCount(outputCount?.cells) + " cells saved" : "Not finalized"};
  const steps = [
    ["input", "Input", "overview", inputCount || diagnostics || value.source?.source ? "Evidence saved" : "Not run", "Input cells " + wbCount(inputCount?.cells ?? diagnostics?.cell_count) + " · features " + wbCount(diagnostics?.feature_count)],
    ["qc", "QC evidence + selection", "qc", selectionStatus === "Not run" && value.qc?.summary ? "Evidence saved · selection not run" : selectionStatus, reused ? value.source.processed_reason || "Explicit processed entry; QC thresholds not applied by this run" : ruleSummary + (retention ? ". Projected: " + wbCount(retention.before) + " → " + wbCount(retention.retained) + " cells; " + wbCount(retention.removed) + " unique removals" : "") + (plan?.doublet ? ". Doublet policy: " + wbText(plan.doublet.method) : "") + actualQC],
    ["decision", "Strategy + approval", "strategy", wbFlowStatus(["strategy_propose", "strategy_apply", "qc_propose", "qc_apply"], {reused: reused && !strategy, executionStages: ["strategy_apply", "qc_apply"], suggested: Boolean(strategy || proposal), approved: wbCurrentApproved(approvalKind, approvalReview)}), plan ? "PCs: " + wbText(plan.pcs?.method) + " · batch: " + wbText(plan.batch?.method) + " · " + clusterPlanText : reused ? "Supplied foundation reused; no strategy proposal is invented" : proposal ? "Typed QC proposal saved; execution needs its own approved resume" : "No saved plan or decision"],
    ["foundation", "Normalize → PCA → cluster", "analysis", wbFlowStatus(["analysis", "strategy_apply"], {reused, executed: value.analysis?.foundation_executed === true || Boolean(analysisCount)}), reused ? "Foundation reused from the supplied object. " + (value.source.processed_reason || "") : "Saved foundation plan: " + basis + ". " + pcText + ". " + clusterText + (analysisCount ? ". Actual analysis checkpoint: " + wbCount(analysisCount.cells) + " cells" : "") + (value.evidence ? ". Saved cells " + wbCount(value.evidence.dataset?.retainedCells) + "; clusters " + wbCount(value.evidence.dataset?.clusterCount) : ". Result counts unavailable")],
    ["markers", "Markers", "analysis", wbFlowStatus(["markers"], {executed: value.evidence != null}), markerCount == null ? "No saved marker result" : wbCount(markerCount) + " supplied marker rows · saved statistics; no new test"],
    ["annotation", "Annotation + review", "annotation", annotation?.lifecycle?.undone === true ? "Undone · needs fresh review" : wbFlowStatus(["annotation_propose", "annotation_apply"], {executionStages: ["annotation_apply"], executed: annotation?.lifecycle?.executed === true, suggested: Boolean(annotation), approved: wbCurrentApproved("annotation", annotation)}), annotation?.lifecycle?.undone === true ? "Previous decision undone; a fresh review is required" : value.evidence_kind === "saved_analysis_checkpoint" ? "Analysis saved; annotation not finalized. Labels remain provisional" : annotation ? "Saved proposals and analyst decisions; biological identities remain provisional" : "No saved annotation proposal"],
    ["output", "Results + reproducibility", "outputs", wbFlowStatus(["finalize"], {executed: run.status === "complete" && Boolean(run.output)}), run.status === "complete" && run.output ? wbCount(wbArray(value.outputs?.artifacts).length) + " saved artifacts · revision " + run.revision + "; actual final checkpoint cells " + wbCount(outputCount?.cells) : "No finalized output; pending or approved work is not a saved result"]
  ];
  const target = wb$("wb-flow"); target.replaceChildren();
  for (const [id, title, section, status, summary] of steps) {
    const item = wbNode("li", null, {class: "wb-flow-node", "data-flow-node": id, "data-flow-status": status}), link = wbNode("a", null, {href: "#" + section, "data-section": section, "aria-label": title + ": " + status + ". " + summary + ". Inspect saved " + section});
    link.append(wbNode("span", title, {class: "wb-flow-title"}), wbNode("span", status, {class: "wb-flow-status"}), wbNode("span", compactValues[id], {class: "wb-flow-value"}), wbNode("p", summary));
    link.addEventListener("click", event => {event.preventDefault(); wbSelectSection(section, true);}); item.append(link); target.append(item);
  }
  const exact = wb$("wb-flow-details"); exact.replaceChildren();
  if (!reused) exact.append(wbQCDetails());
  exact.append(wbRenderStageCountDetails());
  const parametersDetail = wbNode("details", null, {class: "wb-workflow-detail"}); parametersDetail.append(wbNode("summary", "Saved choices and executed parameters"), wbNode("p", "Saved proposals and actual execution records are shown separately. Missing fields remain unavailable."), wbRecord("Saved typed strategy proposal", plan || "Unavailable"), wbRecord("Actual saved strategy execution", execution || "Unavailable")); exact.append(parametersDetail);
  const qcSummary = proposal?.schema === "scagentkit.qc.rules.v1" ? "QC: remove only when " + ruleLogic + (retention ? "; projected " + wbCount(retention.before) + " → " + wbCount(retention.retained) + ", " + wbCount(retention.removed) + " unique removals" : "") + (qcCount ? "; actual QC checkpoint " + wbCount(qcCount.cells) : "") : reused ? "QC reused; no threshold execution" : "QC summary unavailable";
  const longSummary = qcSummary + ". " + (reused ? "Foundation reused" : actualPCs?.ndim != null ? "Executed PCs " + wbText(actualPCs.ndim) + (actualPCs.available_pcs != null ? " / " + wbText(actualPCs.available_pcs) + " computed" : "") + "; " + clusterText : pcText + "; " + clusterText);
  const compactQC = reused ? "QC reused" : inputCount && qcCount ? "QC " + wbCount(inputCount.cells) + "→" + wbCount(qcCount.cells) : retention ? "QC projected " + wbCount(retention.before) + "→" + wbCount(retention.retained) : "QC unavailable";
  const compactLogic = proposal?.schema === "scagentkit.qc.rules.v1" && ["all", "any"].includes(proposal.remove_if) ? proposal.remove_if.toUpperCase() + " " + rules.length + " rules" : rules.length ? rules.length + " saved range rules" : null;
  const compactPCs = reused ? "Foundation reused" : typeof actualPCs?.ndim === "number" && Number.isFinite(actualPCs.ndim) ? "PCs " + wbNumber(actualPCs.ndim) + "/" + wbNumber(actualPCs.available_pcs) : analysisExecuted ? "Executed PCs unavailable" : "PCs not executed";
  const compactResolution = typeof execution?.cluster?.resolution === "number" && Number.isFinite(execution.cluster.resolution) ? "res " + wbNumber(execution.cluster.resolution) : "Executed resolution unavailable";
  wb$("wb-parameter-summary").textContent = run.status === "complete" ? [compactQC, compactLogic, compactPCs, compactResolution].filter(Boolean).join(" · ") : longSummary;
  parametersDetail.append(wbNode("p", longSummary));
}
function wbRenderMainRisk() {
  const value = wbState.view, proposal = value.strategy?.review?.details?.canonical_proposal, annotations = wbArray(value.annotation?.review?.details?.annotations), provider = value.provider || {};
  const parts = [provider.name === "manual" ? "Manual configuration · no provider selected." : provider.name === "mock" ? "Mock suggestions · simulated." : typeof provider.name === "string" && provider.name ? "Configured provider: " + provider.name + "." : "Provider configuration unavailable."];
  const allUnknown = annotations.length > 0 && annotations.every(row => row.proposal?.label === "Unknown"), allLow = allUnknown && annotations.every(row => row.proposal?.confidence === "low");
  if (allUnknown) parts.push("All " + annotations.length + " saved annotation suggestions are Unknown" + (allLow ? " / low qualitative confidence." : "."));
  const risks = []; for (const source of [proposal?.risks, proposal?.qc?.risks]) for (const risk of Array.isArray(source) ? source : typeof source === "string" ? [source] : []) if (typeof risk === "string" && risk.trim()) risks.push(risk);
  parts.push(...risks, "Biological identities remain provisional.");
  const uniqueRisks = [...new Set(risks)], full = [...new Set(parts)].join(" ");
  if (value.run.status === "complete") {
    const compact = [provider.name === "manual" ? "Manual / no provider" : provider.name === "mock" ? "SIMULATED suggestions" : parts[0]];
    if (allUnknown) compact.push("all " + annotations.length + " Unknown" + (allLow ? " / low, uncalibrated confidence" : ""));
    compact.push("biological identities unverified / provisional");
    if (wbQCProposal()) compact.push("QC can remove valid populations");
    if (uniqueRisks.includes("These neutral ranges are a control starting point, not suggested QC thresholds.")) compact.push("QC rules are a control example, not recommended thresholds");
    wb$("wb-risk").textContent = compact.join(" · ") + ".";
  } else wb$("wb-risk").textContent = full;
  wb$("wb-risk-panel").hidden = false;
  wb$("wb-risk-summary").textContent = "Full saved cautions" + (uniqueRisks.length ? " (" + uniqueRisks.length + ")" : "") + " + sources";
  wb$("wb-risk-details").replaceChildren(wbNode("p", full));
}
function wbRenderOverview() {
  const value = wbState.view, run = value.run, evidence = value.evidence, rows = wbArray(evidence?.clusters), metrics = wb$("wb-metrics"); metrics.replaceChildren();
  const markerCount = rows.reduce((count, row) => count + wbArray(row.markers).length, 0);
  const checkpoint = value.evidence_kind === "saved_analysis_checkpoint";
  for (const [label, count, note] of [[evidence ? checkpoint ? "Analysis cells" : "Cells" : "Input cells", evidence?.dataset?.retainedCells ?? run.diagnostics?.cell_count, evidence ? checkpoint ? "Exact checkpoint cell universe; annotation pending" : "Exact exported cell universe" : "Saved input diagnostics; no output inferred"], ["Clusters", evidence?.dataset?.clusterCount, "Literal saved membership"], ["Markers", evidence ? markerCount : null, "Saved statistics; no new test"], ["Saved revision", run.revision, "Server-side journal authority"]]) {const metric = wbNode("div", null, {class: "wb-metric"}); metric.append(wbNode("span", label), wbNode("strong", count == null ? "—" : count.toLocaleString()), wbNode("small", note)); metrics.append(metric);}
  const background = wb$("wb-background"); background.replaceChildren(wbFacts(run.context || {})); if (!Object.keys(run.context || {}).length) wbEmpty(background, "No study background was declared.");
  const diagnostics = wb$("wb-diagnostics"); diagnostics.replaceChildren(wbFacts(run.diagnostics || {})); if (!run.diagnostics) wbEmpty(diagnostics, "No saved input diagnostics were supplied.");
  const stages = wb$("wb-stages"); stages.replaceChildren();
  for (const [name, status] of Object.entries(run.nodes || {})) {const reused = value.source?.start_stage === "processed" && ["qc_evidence", "qc_propose", "qc_apply", "analysis"].includes(name); const stage = wbNode("div", null, {class: "wb-stage", "data-stage": name}); stage.append(wbNode("strong", name), wbNode("span", reused ? "Reused / skipped in this run" : wbText(status))); if (reused) stage.append(wbNode("p", value.source.processed_reason || "Processed-entry reason unavailable")); stages.append(stage);}
  if (!stages.children.length) wbEmpty(stages, "No stage records were supplied.");
  wb$("wb-binding").replaceChildren(wbFacts({project_id: value.project.project_id, evidence_kind: value.evidence_kind, input_hash: value.binding.input_hash, revision: value.binding.revision, history_head: value.binding.history_head, state_sha256: value.binding.state_sha256, bundle_digest: value.binding.bundle_digest, source_fingerprint: value.binding.source_fingerprint, cell_scope_hash: value.binding.cell_scope_hash, bundle_cell_scope_hash: value.binding.bundle_cell_scope_hash, stage_scope_hash: value.binding.stage_scope_hash, stage_records_hash: value.binding.stage_records_hash, workspace_fingerprint: value.binding.workspace_fingerprint}), wbRecord("Saved source entry", value.source), ...(checkpoint ? [wbRecord("Saved analysis checkpoint receipts", value.binding.stage_checkpoint_records)] : []), wbRecord("Display boundary", value.detail_projection || {notice: "No additional detail projection declaration was supplied."}));
  wbRenderFlow();
}
function wbRenderQC() {
  const value = wbState.view.qc || {}, target = wb$("wb-qc-content"); target.replaceChildren();
  wb$("wb-qc-status").textContent = value.status === "processed_reused" ? "QC execution was skipped at this processed entry. The saved source and reuse reason are shown below." : value.status === "saved" ? "Saved QC evidence and proposal facts for this project. This view cannot change thresholds or cells." : "No QC evidence was recorded for this project.";
  if (value.status === "processed_reused") {target.append(wbCard("Processed entry · QC reused", wbNode("p", value.reason || wbState.view.source?.processed_reason || "The saved reason is unavailable."), wbRecord("Saved source", wbState.view.source))); return;}
  const summary = value.summary;
  if (!summary) {wbEmpty(target, value.reason || "QC distributions are unavailable. No measurements or checkpoint are inferred from completed stage names."); return;}
  target.append(wbCard("Observed QC scope", wbFacts({cells: summary.cells ?? summary.cell_count, features: summary.features, assay: summary.assay, counts_layer: summary.counts_layer, grouping_roles: summary.grouping_roles, mitochondrial: summary.mitochondrial})));
  const groups = wbArray(summary.groups), metricRows = [];
  for (const group of groups) for (const [metric, distribution] of Object.entries(group.metrics || {})) metricRows.push([group.group_id || "saved group", group.selector || {}, group.cells, metric, distribution?.median, distribution?.p05, distribution?.p95, distribution?.missing ?? distribution?.unavailable]);
  if (metricRows.length) target.append(wbCard("Saved sample / capture summaries", wbTable(["Group", "Declared selector", "Cells", "Metric", "Median", "p05", "p95", "Unavailable"], metricRows)));
  target.append(wbCard("Saved QC record", wbRecord("Aggregate measurements and interpretation", summary)));
  if (value.preview) target.append(wbCard("Saved QC preview", wbRecord("Retention, supported proposal and review snapshot", value.preview)));
  if (wbQCProposal()) target.append(wbQCDetails());
  const impact = wbState.view.strategy?.review?.details?.qc_impact; if (impact) target.append(wbCard("Saved strategy QC impact", wbFacts(impact), wbNode("p", "Expected retention is a saved preview, not an executed filtering count.")));
  wbProjection(target, "QC", value.projection);
}
function wbRenderStrategy() {
  const value = wbState.view.strategy || {}, target = wb$("wb-strategy-content"), review = value.review, details = review?.details || {}, proposal = details.canonical_proposal; target.replaceChildren();
  if (!review && !value.summary) {wbEmpty(target, "No analysis strategy review was saved for this project. A processed entry can preserve an existing analysis without creating a new strategy approval."); return;}
  if (proposal) {target.append(wbCard("Saved rationale", wbNode("p", proposal.rationale || "No rationale supplied"), wbFacts({source: details.source?.kind, risks: proposal.risks, inferences: proposal.inferences, saved_status: value.status}))); for (const [key, title] of [["qc", "QC and cell retention"], ["analysis", "Normalization and PCA basis"], ["pcs", "PC selection"], ["batch", "Batch handling"], ["clustering", "Clustering"], ["umap", "UMAP"], ["doublet", "Doublet policy"], ["cycle", "Cell-cycle policy"]]) if (proposal[key]) target.append(wbCard(title, wbFacts(proposal[key])));}
  if (details.qc_impact) target.append(wbCard("Previewed impact", wbFacts(details.qc_impact)));
  if (details.applicability) target.append(wbCard("Saved applicability", wbFacts(details.applicability)));
  target.append(wbCard("Recorded strategy and decision lifecycle", wbRecord("Saved strategy review", review || value.summary))); wbProjection(target, "Strategy", value.projection);
}
function wbSelectCluster(id) {const clusters = wbArray(wbState.view?.evidence?.clusters); if (!clusters.some(cluster => cluster.id === id)) return; wbState.clusterId = id; wbRenderEmbedding(); wbRenderMarkers();}
function wbRenderEmbedding() {
  const evidence = wbState.view.evidence, clusters = wbArray(evidence?.clusters), points = wbArray(evidence?.umap), name = evidence?.embeddingName || "Saved embedding";
  wb$("wb-embedding-title").textContent = name; wb$("wb-embedding-summary").textContent = points.length ? points.length.toLocaleString() + " plotted cells" + (wbState.view.evidence_kind === "saved_analysis_checkpoint" ? " · annotation not finalized" : "") : "No embedding coordinates were supplied for this snapshot.";
  const toggle = wb$("wb-show-all"); toggle.disabled = !points.length;
  const displayedClusters = clusters.map(cluster => {const annotations = wbArray(cluster.sourceAnnotations); return annotations.length ? {...cluster, sourceLabels: annotations.map(row => (row.value ?? "(missing)") + " (" + row.count + ")").join("; ")} : cluster;});
  ScEvidenceDisplay.embedding(wb$("wb-umap"), {points, clusters: displayedClusters, name, title: wbState.projectId, selectedCluster: wbState.clusterId, onSelect: wbSelectCluster, showAll: toggle.checked});
  wb$("wb-umap-legend").replaceChildren(); // The pure display helper supplies the actual coloured legend.
}
function wbRenderMarkers() {
  const clusters = wbArray(wbState.view.evidence?.clusters), list = wb$("wb-clusters"); list.replaceChildren();
  for (const cluster of clusters) {const button = wbNode("button", cluster.id, {type: "button", "data-cluster-id": cluster.id, "aria-label": "Cluster " + cluster.id + " · " + cluster.cellCount + " cells", "aria-pressed": cluster.id === wbState.clusterId}); button.addEventListener("click", () => wbSelectCluster(cluster.id)); list.append(button);}
  const selected = clusters.find(cluster => cluster.id === wbState.clusterId), markers = wbArray(selected?.markers);
  wb$("wb-marker-summary").textContent = selected ? "Cluster " + selected.id + ": " + markers.length + " supplied marker rows. Missing top-marker evidence does not establish non-expression. Gene lookups use the declared dataset species." : "No literal cluster scope is available for this saved output.";
  ScEvidenceDisplay.markers(wb$("wb-markers"), markers, {species: wbState.view.run.context?.species});
  const selection = wb$("wb-selection"), preview = wb$("wb-marker-preview"); selection.replaceChildren(); preview.replaceChildren();
  if (!selected) {wbEmpty(selection, "No saved cluster evidence is available."); return;}
  selection.append(wbNode("p", "Cluster " + selected.id + " · " + wbCount(selected.cellCount) + " cells", {class: "wb-selection-title"}));
  const labels = wbArray(selected.sourceAnnotations), singleCompleteSource = labels.length === 1 && labels[0].count === selected.cellCount;
  const sourceText = labels.length ? "Source labels: " + labels.map(row => wbText(row.value) + (singleCompleteSource ? "" : " (" + wbCount(row.count) + ")")).join("; ") : "Source labels unavailable";
  const suggestion = wbArray(wbState.view.annotation?.review?.details?.annotations).find(row => row.clusterId === selected.id)?.proposal;
  selection.append(wbNode("p", sourceText + (suggestion ? " · Recorded suggestion: " + wbText(suggestion.label) + " / " + wbText(suggestion.confidence) + " confidence (uncalibrated)" : ""), {class: "wb-selection-note"}));
  preview.append(wbNode("p", Math.min(5, markers.length) + " / " + markers.length + " supplied markers", {class: "wb-marker-preview-heading"}));
  const listPreview = wbNode("ul", null, {class: "wb-marker-preview-list"}); for (const marker of markers.slice(0, 5)) {const row = wbNode("li"); row.append(wbNode("strong", marker.gene), wbNode("span", "avg log2FC " + wbPreviewNumber(marker.avgLog2FC))); listPreview.append(row);} preview.append(listPreview);
  if (!markers.length) wbEmpty(preview, "Markers unavailable; absence here does not establish non-expression.");
  else preview.append(wbNode("p", "Missing markers do not establish non-expression.", {class: "wb-marker-caution"}));
}
function wbRenderAnalysis() {
  const value = wbState.view.analysis || {}, target = wb$("wb-analysis-content"); target.replaceChildren();
  const reused = wbState.view.source?.start_stage === "processed" && value.foundation_executed !== true;
  const checkpoint = wbState.view.evidence_kind === "saved_analysis_checkpoint";
  wb$("wb-analysis-title").textContent = checkpoint ? "Analysis · annotation pending" : wbState.view.evidence_kind === "final_output_bundle" ? "Clusters + markers" : "Analysis evidence unavailable";
  const finalOutput = wbState.view.evidence_kind === "final_output_bundle";
  const fullBoundary = (reused ? "Existing processed analysis was reused; foundation computation was not executed by this run. " + (wbState.view.source.processed_reason || "The saved reason is unavailable.") + " " : "Saved analysis status: " + wbText(value.status) + ". ") + (checkpoint ? "Coordinates and marker statistics come from verified saved analysis checkpoints. Annotation is not finalized; these are not final output labels. " : finalOutput ? "Coordinates and marker statistics come from the fixed saved output bundle. " : "No saved plot and marker snapshot is available. ") + "One point represents one literal cell ID. This page performs no scientific computation.";
  const status = wb$("wb-analysis-status");
  status.textContent = (reused ? "Processed analysis reused; foundation computation was not executed by this run. " : "") + (checkpoint ? "Annotation is not finalized; labels remain provisional." : finalOutput ? "" : "No saved plot or marker snapshot is available.");
  status.hidden = !status.textContent;
  target.append(wbNode("p", fullBoundary));
  if (value.parameters) target.append(wbCard("Recorded analysis parameters", wbFacts(value.parameters)));
  if (value.computed_diagnostics) target.append(wbCard("Saved computed diagnostics", wbRecord("Actual saved PCA / batch diagnostics", value.computed_diagnostics)));
  if (wbState.view.evidence == null) wbEmpty(target, "No verified saved analysis or final output evidence is available yet. A current review proposal is not an embedding or marker result.");
  wbProjection(target, "Analysis", value.projection); wbRenderEmbedding(); wbRenderMarkers();
}
function wbGeneLine(prefix, genes) {const line = wbNode("p", prefix); line.append(ScGeneCards.list(genes, wbState.view.run.context?.species)); return line;}
function wbRenderAnnotation() {
  const value = wbState.view.annotation || {}, target = wb$("wb-annotation-content"), review = value.review, rows = wbArray(review?.details?.annotations); target.replaceChildren();
  if (!rows.length) wbEmpty(target, "No saved per-cluster annotation review was supplied. Unavailable labels stay unavailable; a marker or cluster count is not an identity decision.");
  for (const row of rows) {
    const proposal = row.proposal || {}, card = wbNode("section", null, {class: "wb-annotation-row", "data-cluster-id": row.clusterId});
    card.append(wbNode("h3", "Cluster " + row.clusterId + " · " + wbText(row.cell_count) + " cells"), wbNode("p", proposal.label || "Label unavailable", {class: "wb-annotation-label"}), wbNode("p", (proposal.confidence || "Unavailable") + " qualitative confidence · uncalibrated"), wbNode("p", proposal.rationale || "No rationale supplied"), wbGeneLine("Cited genes: ", proposal.markers));
    const joint = row.joint_evidence;
    if (joint) card.append(wbRecord("Saved database / model joint evidence", joint)); else if (row.local_reference) card.append(wbRecord("Saved local reference evidence", row.local_reference));
    card.append(wbRecord("Supplied marker statistics and scope facts", {supplied_marker_stats: row.supplied_marker_stats, cited_marker_stats: row.cited_marker_stats, cell_ids: row.cell_ids})); target.append(card);
  }
  if (review) target.append(wbCard("Annotation provenance and decision lifecycle", wbRecord("Saved annotation review", {source: review.details?.source, limitations: review.details?.limitations, lifecycle: review.lifecycle, output_columns: review.details?.output_columns})));
  if (value.summary && !review) target.append(wbCard("Saved annotation aggregate", wbRecord("Supplied annotation summary", value.summary)));
  wbProjection(target, "Annotation", value.projection);
}
function wbRenderChildren() {
  const target = wb$("wb-children-content"), children = wbArray(wbState.view.children); target.replaceChildren();
  for (const child of children) {
    const card = wbCard(null), heading = wbNode("div", null, {class: "wb-child-heading"}); heading.append(wbNode("h3", child.project_id), wbNode("a", "Open child workbench", {href: wbScopeURL("/workbench", child.project_id, true), "data-child-id": child.project_id})); card.append(heading, wbFacts({status: child.status, stage: child.stage, revision: child.revision}));
    for (const application of wbArray(child.applications)) card.append(wbNode("p", "Derived parent · " + (application.active ? "active" : "historical") + " · new column " + (application.column || "recorded in receipt")), wbNode("code", application.output_path || application.path || wbText(application.output)), wbNode("a", "Inspect child application receipts", {class: "wb-inline-link", href: wbScopeURL("/subclusters", child.project_id, true)})); target.append(card);
  }
  if (!children.length) wbEmpty(target, "No registered child project has been created in this service's workspace.");
  const tool = wb$("wb-children-tool"); tool.hidden = wbState.scopes.workspace_enabled === false; tool.setAttribute("href", wbScopeURL("/subclusters", wbState.projectId, wbState.child));
}
function wbRenderOutputs() {
  const value = wbState.view.outputs || {}, target = wb$("wb-outputs-content"); target.replaceChildren();
  const artifacts = wbArray(value.artifacts), card = wbCard("Saved project artifacts");
  for (const artifact of artifacts) {const row = wbNode("div", null, {class: "wb-artifact"}); row.append(wbNode("code", artifact.path || "Path unavailable"), wbNode("small", artifact.sha256 ? "SHA-256 " + artifact.sha256 : "Hash unavailable")); card.append(row);}
  if (artifacts.length) target.append(card); else wbEmpty(target, "No completed artifacts were supplied for this snapshot. Pending review is not a published output.");
  if (wbState.view.run.output) target.append(wbCard("Original run output record", wbRecord("Saved R output references", wbState.view.run.output)));
  if (value.scientific_result) target.append(wbCard("Result interpretation", wbRecord("Saved result statement", value.scientific_result)));
  const derived = wbCard("Separate derived parent objects"); let count = 0;
  for (const child of wbArray(wbState.view.children)) for (const application of wbArray(child.applications)) {count++; const row = wbNode("div", null, {class: "wb-artifact"}); row.append(wbNode("p", "Child " + child.project_id + " · " + (application.active ? "active" : "historical") + " · " + (application.column || "recorded column")), wbNode("code", application.output_path || application.path || wbText(application.output)), wbNode("a", "Inspect child application receipts", {class: "wb-inline-link", href: wbScopeURL("/subclusters", child.project_id, true)})); derived.append(row);}
  if (!count) derived.append(wbNode("p", "No derived parent object is recorded. Completing a child does not automatically apply its labels.")); target.append(derived);
}
function wbRenderHistory() {
  const history = wbState.view.history, target = wb$("wb-history-content"); target.replaceChildren();
  const provided = history.events.length, total = history.total_events;
  wb$("wb-history-summary").textContent = (Number.isInteger(total) ? provided + " supplied event headers of " + total : provided + " supplied event headers") + " · source: " + (history.authority || "saved run history") + ". Event details are an allowlisted display projection; original hash-linked records stay in the saved project. This history has no edit, approve, retry or resume controls.";
  wbProjection(target, "History", history);
  for (const event of history.events) {const card = wbNode("article", null, {class: "wb-history-event", "data-event-sequence": event.sequence}), heading = wbNode("div", null, {class: "wb-history-heading"}); heading.append(wbNode("strong", "#" + event.sequence + " · " + event.action), wbNode("small", event.created_at)); card.append(heading); const details = event.details || {}; if (details.reviewer) card.append(wbNode("p", "Reviewer: " + details.reviewer)); if (details.reason) card.append(wbNode("p", details.reason)); if (details.rationale) card.append(wbNode("p", details.rationale)); card.append(wbRecord("Saved event facts and hash links", {details, omitted_detail_fields: event.omitted_detail_fields, previous_hash: event.previous_hash, hash: event.hash})); target.append(card);}
  if (!provided) wbEmpty(target, "No event records were supplied. No decision is inferred from the current status.");
  const audit = wbState.view.integration_history;
  if (audit) {
    const card = wbCard("Saved derived application audit");
    card.append(wbNode("p", audit.provided_events + " supplied event headers of " + audit.total_events + " · source: " + audit.authority + ". This separate journal records derived-parent application and undo; its revision is independent of the run history. All records here are read-only."), wbRecord("Independent application journal binding", {revision: audit.revision, head: audit.head, state_sha256: wbState.view.binding.integration_state_sha256, hash_verification: audit.hash_verification}));
    for (const event of audit.events) {const row = wbNode("article", null, {class: "wb-history-event", "data-integration-sequence": event.sequence}); row.append(wbNode("strong", "Application #" + event.sequence + " · " + event.action), wbNode("small", event.created_at), wbRecord("Saved application event facts and hash links", {details: event.details, omitted_detail_fields: event.omitted_detail_fields, previous_hash: event.previous_hash, hash: event.hash})); card.append(row);}
    if (!audit.events.length) wbEmpty(card, "No derived application journal has been created for this child. Completing the child does not apply its labels to the parent.");
    target.append(card);
  }
}
function wbRender() {
  const value = wbState.view, run = value.run, selected = value.project; wbState.child = selected.scope === "child";
  wb$("wb-home").setAttribute("href", wbScopeURL("/workbench", selected.project_id, wbState.child)); wb$("wb-title").textContent = selected.project_id;
  wb$("wb-scope").textContent = (wbState.child ? "Independent child project" : "Parent project") + " · " + (selected.frozen ? "frozen / read-only" : "saved view / read-only");
  wb$("wb-dataset-title").textContent = run.context?.tissue || "Saved dataset";
  wb$("wb-context").textContent = (run.context?.species || "species undeclared");
  wb$("wb-status").textContent = ({complete: "Saved", awaiting_review: "Awaiting review", awaiting_configuration: "Configuration needed", ready: "Ready to continue", failed: "Failed", rejected: "Rejected", running: "Running"})[run.status] || run.status; wb$("wb-status").setAttribute("data-run-status", run.status); wbProvider(); wbRenderScopes();
  const review = wb$("wb-review"); review.hidden = false; review.setAttribute("href", wbScopeURL("/review", selected.project_id, wbState.child));
  wb$("wb-header-review").hidden = false; wb$("wb-header-review").setAttribute("href", wbScopeURL("/review", selected.project_id, wbState.child));
  wb$("wb-header-scope").hidden = wbState.scopes.workspace_enabled === false; wb$("wb-header-scope").setAttribute("href", wbScopeURL("/subclusters", selected.project_id, wbState.child));
  review.textContent = selected.frozen ? "Inspect review · read-only" : run.status === "complete" && (value.navigation?.can_revise || value.navigation?.can_undo) ? "Review result" : run.status === "complete" ? "Inspect result" : "Review current step";
  wb$("wb-next").textContent = wbNextStepText();
  wb$("wb-current-title").textContent = run.status === "complete" ? "Next" : run.status === "awaiting_review" ? "Decision needed" : run.status === "failed" ? "Resolve saved failure" : "Next";
  const parameterReview = wb$("wb-parameter-review"); parameterReview.hidden = false; parameterReview.setAttribute("href", wbScopeURL("/review", selected.project_id, wbState.child)); parameterReview.textContent = selected.frozen || !(value.navigation?.can_review || value.navigation?.can_revise) ? "Inspect saved parameters · read-only" : "Review / edit supported parameters"; wbRenderMainRisk();
  const childAction = wb$("wb-child-action"); childAction.hidden = wbState.scopes.workspace_enabled === false || !wbState.scopes.parent.ready;
  childAction.setAttribute("href", wbScopeURL("/subclusters", wbState.child ? selected.project_id : wbState.scopes.parent.project_id, wbState.child)); childAction.textContent = wbState.child && run.status === "complete" ? "Review writeback" : wbState.child ? "Child scope" : "Select cells";
  const clusters = wbArray(value.evidence?.clusters); if (!clusters.some(cluster => cluster.id === wbState.clusterId)) wbState.clusterId = clusters[0]?.id || null;
  wbRenderOverview(); wbRenderQC(); wbRenderStrategy(); wbRenderAnalysis(); wbRenderAnnotation(); wbRenderChildren(); wbRenderOutputs(); wbRenderHistory(); wbSelectSection(wbState.section);
}
async function wbGET(path, headers = {}) {const response = await fetch(path, {method: "GET", cache: "no-store", headers}); const answer = await response.json(); if (!response.ok) throw new Error(answer?.error || "The saved evidence could not be inspected."); return answer;}
async function wbLoad() {
  if (wbState.busy) return; wbState.busy = true; wb$("wb-refresh").disabled = true;
  try {
    const selected = wbScopeQuery(), scopes = wbVerifyScopes(await wbGET("/api/run-review/scopes")), id = selected.child_id || selected.project_id || scopes.parent.project_id;
    wbState.scopes = scopes; wbState.projectId = id; wbState.child = Boolean(selected.child_id);
    const answer = wbVerify(await wbGET(wbScopeURL("/api/run-review/workbench", id, wbState.child), {"X-ScAgentKit-Run-Project": id}));
    wbState.view = answer; wbState.failed = false; wbRender(); wb$("wb-notice").hidden = true;
  } catch (error) {
    wbState.failed = true; wbState.view = null; wb$("wb-review").hidden = true; wb$("wb-header-review").hidden = true; wb$("wb-header-scope").hidden = true; wb$("wb-parameter-review").hidden = true; wb$("wb-child-action").hidden = true; wb$("wb-children-tool").hidden = true; wb$("wb-model").hidden = true;
    wb$("wb-title").textContent = "Saved project evidence unavailable"; wb$("wb-context").textContent = ""; wb$("wb-scope").textContent = "EXACT SNAPSHOT NOT VERIFIED";
    wb$("wb-status").textContent = "Saved evidence unavailable"; wb$("wb-next").textContent = "Refresh this exact registered scope after resolving the saved-state error.";
    wb$("wb-notice").textContent = error.message; wb$("wb-notice").hidden = false; wb$("wb-notice").className = "banner error";
    for (const id of ["wb-metrics", "wb-flow", "wb-flow-details", "wb-risk-details", "wb-background", "wb-diagnostics", "wb-stages", "wb-binding", "wb-qc-content", "wb-strategy-content", "wb-analysis-content", "wb-umap", "wb-umap-legend", "wb-clusters", "wb-markers", "wb-selection", "wb-marker-preview", "wb-risk", "wb-parameter-summary", "wb-annotation-content", "wb-children-content", "wb-outputs-content", "wb-history-content"]) wb$(id).replaceChildren();
    wb$("wb-risk-panel").hidden = true; wb$("wb-risk-summary").textContent = "Full saved cautions"; wb$("wb-status").setAttribute("data-run-status", "unverified");
    wb$("wb-current-title").textContent = "Saved evidence unavailable";
    wb$("wb-dataset-title").textContent = "Saved evidence unavailable";
    for (const id of ["wb-qc-status", "wb-analysis-status", "wb-embedding-summary", "wb-marker-summary", "wb-history-summary"]) wb$(id).textContent = "";
  } finally {wbState.busy = false; wb$("wb-refresh").disabled = false;}
}
for (const link of wb$("wb-navigation").children) link.addEventListener("click", event => {event.preventDefault(); wbSelectSection(link.getAttribute("data-section"), true);});
for (const link of wb$("wb-primary-navigation").children) link.addEventListener("click", event => {event.preventDefault(); wbSelectSection(link.getAttribute("href").slice(1), true);});
for (const [id, section] of [["wb-open-annotation", "annotation"], ["wb-open-history", "history"]]) wb$(id).addEventListener("click", event => {event.preventDefault(); wbSelectSection(section, true);});
wb$("wb-show-all").addEventListener("change", () => {if (wbState.view) wbRenderEmbedding();});
wb$("wb-refresh").addEventListener("click", wbLoad);
window.addEventListener("hashchange", () => wbSelectSection((window.location.hash || "").slice(1)));
window.addEventListener("pageshow", event => {if (event.persisted) wbLoad();});
wbState.section = WB_SECTIONS.includes((window.location.hash || "").slice(1)) ? window.location.hash.slice(1) : "overview";
wbSelectSection(wbState.section);
wbLoad();
