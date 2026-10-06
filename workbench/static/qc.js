"use strict";
const $ = id => document.getElementById(id);
const array = value => value == null ? [] : Array.isArray(value) ? value : [value];
const fmt = value => value == null || !Number.isFinite(Number(value)) ? "unknown" : Number(value).toLocaleString(undefined, {maximumFractionDigits: 3});
const json = value => JSON.stringify(value, null, 2);
const unifiedReview = document.body?.dataset?.runReview === "true";
function scopedQCURL(path) {
  const id = new URLSearchParams(window.location.search || "").get("child_id");
  return id ? path + "?child_id=" + encodeURIComponent(id) : path;
}
const state = {view: null, busy: false, stale: false, savedDraft: null, savedProposal: null};
function element(tag, text, attributes = {}) {
  const result = document.createElement(tag);
  if (text != null) result.textContent = String(text);
  for (const [name, value] of Object.entries(attributes)) result.setAttribute(name, String(value));
  return result;
}
function message(text, error = false) {
  $("qc-message").hidden = !text;
  $("qc-message").textContent = text;
  $("qc-message").className = "banner " + (error ? "error" : "notice");
}
function active() {
  const run = state.view?.run;
  return !state.busy && !state.stale && run?.status === "awaiting_review" && run.pending?.kind === "qc" &&
    /^[a-f0-9]{64}$/.test(run.pending.hash || "") && /^[a-f0-9]{64}$/.test(run.qc_preview?.hash || "");
}
function draftText() {return [$("qc-proposal").value, $("qc-alternatives").value, $("qc-panels").value].join("\n");}
function dirty() {return !!state.savedDraft && draftText() !== state.savedDraft;}
function buttons() {
  $("qc-refresh").disabled = state.busy;
  for (const id of ["qc-approve", "qc-reject", "qc-revise", "qc-preview"]) $(id).disabled = !active();
  $("qc-approve").disabled = !active() || dirty();
  $("qc-preview").disabled = !active() || (state.savedProposal && $("qc-proposal").value !== state.savedProposal);
  for (const id of ["qc-reviewer", "qc-reason", "qc-proposal", "qc-alternatives", "qc-panels"]) $(id).disabled = state.busy;
}
async function request(payload) {
  try {
    let response, answer;
    try {
      const prefix = unifiedReview ? "/api/run-review/" : "/api/qc/";
      response = await fetch(scopedQCURL(prefix + (payload ? "decision" : "inspect")), payload ? {
        method: "POST", headers: {"Content-Type": "application/json", [unifiedReview ? "X-ScAgentKit-Run-Token" : "X-ScAgentKit-QC-Token"]: state.view.csrf_token},
        body: JSON.stringify(payload)
      } : {cache: "no-store"});
      answer = await response.json();
    } catch (error) {
      throw new Error("Local QC connection or response failed. Refresh the saved state before submitting again.");
    }
    if (!response.ok) throw new Error(answer?.error || "The local QC request failed");
    if (answer?.schema !== (unifiedReview ? "scagentkit.run-review.workbench.v1" : "scagentkit.qc.workbench.v1") || answer.run?.schema !== "scagentkit.run.v1" ||
        typeof answer.run.project_id !== "string" || !answer.run.project_id ||
        typeof answer.csrf_token !== "string" || !answer.csrf_token)
      throw new Error("The response is not a verified QC run view.");
    if (state.view && answer.run.project_id !== state.view.run.project_id)
      throw new Error("The configured project changed; reload the server before reviewing.");
    return answer;
  } catch (error) {
    // Even HTTP 200 can be an unverified or foreign result. A dropped POST
    // response can follow a commit; a failed GET cannot restore trusted state.
    state.stale = true;
    throw error;
  }
}
function table(headings, rows) {
  const wrapper = element("div", null, {class: "table-wrap"});
  const result = element("table"), head = element("thead"), tr = element("tr"), body = element("tbody");
  headings.forEach(text => tr.append(element("th", text))); head.append(tr); result.append(head);
  rows.forEach(row => {const item = element("tr"); row.forEach(text => item.append(element("td", text))); body.append(item);});
  result.append(body); wrapper.append(result); return wrapper;
}
function ids(title, values) {
  const list = array(values), details = element("details"), summary = element("summary", `${title} · ${list.length} exact IDs`);
  details.append(summary, element("pre", list.length ? list.join("\n") : "Empty cell set", {class: "qc-id-list"}));
  return details;
}
function raw(value) {return element("pre", json(value), {class: "qc-small-json"});}
function selector(value) {return value ? Object.entries(value).map(([key, val]) => `${key}=${val}`).join("; ") : "All input cells";}
function empty(target, text) {target.append(element("p", text, {class: "qc-empty"}));}
function renderRules(details) {
  const target = $("qc-rules"), proposal = details?.canonical_parameters?.proposal || state.view.run.pending?.proposal?.rules;
  target.replaceChildren();
  if (!proposal) {empty(target, "No current typed QC proposal is available."); return;}
  target.append(element("p", proposal.rationale));
  const risks = array(proposal.risks);
  if (risks.length) {const list = element("ul", null, {class: "qc-rule-risks"}); risks.forEach(value => list.append(element("li", value))); target.append(list);}
  if (proposal.schema === "scagentkit.qc.rules.v1") {
    target.append(element("p", proposal.remove_if === "any" ? "Remove if ANY rule fails (OR of failures)." : proposal.remove_if === "all" ? "Remove if ALL rules fail (AND of failures)." : "Failure combination unavailable."));
    target.append(element("p", "Saved minimal-prefilter exclusions remain mandatory. Independent failure counts overlap; the final cell set is deduplicated. Doublet marking/removal is a separate reviewed choice."));
    target.append(table(["Rule", "Operation", "Metric / saved preset", "Minimum (inclusive)", "Maximum (inclusive)", "Scope"], array(proposal.rules).map((rule, i) => rule.op === "mad_preset" ?
      [i + 1, "Saved MAD predicate", rule.preset_id, "Exact saved panel", "Exact saved panel", "All saved QC groups"] :
      [i + 1, rule.op, rule.metric, rule.min == null ? "No lower bound" : fmt(rule.min), rule.max == null ? "No upper bound" : fmt(rule.max), selector(rule.group)])));
    array(proposal.rules).filter(rule => rule.op === "mad_preset").forEach(rule => target.append(element("p", "Saved MAD panel hash: " + rule.panel_hash)));
  } else target.append(table(["Condition", "Metric", "Minimum (inclusive)", "Maximum (inclusive)", "Scope"], array(proposal.filters).map((f, i) => [i + 1, f.metric, f.min == null ? "No lower bound" : fmt(f.min), f.max == null ? "No upper bound" : fmt(f.max), selector(f.group)])));
  $("qc-cell-scope").replaceChildren(ids("Retained", details?.keep_cells), ids("Removed", details?.remove_cells));
}
function renderImpacts(details) {
  const impacts = array(details?.filter_impacts), target = $("qc-filter-impacts"); target.replaceChildren();
  if (!impacts.length) empty(target, "No verified impact preview is present.");
  else target.append(table(["Condition / scope", "Scoped", "Below", "Above", "Unavailable", "Independent removal", "Exclusive removal"], impacts.map(f => [
    `${f.id} · ${f.filter?.metric || f.filter?.preset_id || ""} · ${selector(f.filter?.group)}`, fmt(f.scoped), fmt(f.low), fmt(f.high), fmt(f.unavailable), fmt(f.independently_removed), fmt(f.exclusively_removed)
  ])));
  impacts.forEach(f => {
    const scope = element("details"); scope.append(element("summary", `${f.id} · exact condition scope and reasons`),
      ids("Scoped", f.scope_cells), ids("Below minimum", f.low_cells), ids("Above maximum", f.high_cells),
      ids("Unavailable metric", f.unavailable_cells), ids("Independent removal", f.independently_removed_cells),
      ids("Exclusive removal", f.exclusively_removed_cells)); target.append(scope);
  });
  const overlap = $("qc-overlap"); overlap.replaceChildren();
  const names = array(details?.overlap?.filter_ids), counts = array(details?.overlap?.counts);
  if (names.length) overlap.append(table(["Condition", ...names], names.map((name, i) => [name, ...array(counts[i]).map(fmt)])));
  else empty(overlap, "No measured overlap table is available.");
  const patterns = $("qc-patterns"); patterns.replaceChildren();
  array(details?.patterns).forEach(pattern => {
    const card = ids(`${array(pattern.reason_ids).join(" + ") || "No measured failure"}; unavailable ${array(pattern.unavailable_filter_ids).join(", ") || "none"}; kept ${fmt(pattern.retained)} / removed ${fmt(pattern.removed)}`, pattern.cell_ids);
    card.className = "qc-pattern"; patterns.append(card);
  });
}
function svgNode(tag, attributes, text) {
  const result = document.createElementNS("http://www.w3.org/2000/svg", tag);
  Object.entries(attributes).forEach(([key, val]) => result.setAttribute(key, String(val)));
  if (text != null) result.textContent = text;
  return result;
}
function distributionPopulation(value, metric) {return value?.[metric] || value?.metrics?.[metric] || {};}
function distributions(target, populations) {
  target.replaceChildren();
  const colors = {before: "#647185", retained: "#375dce", removed: "#b77722"};
  for (const metric of ["nCount", "nFeature", "percent_mt"]) {
    const measures = ["before", "retained", "removed"].map(name => ({name, stats: distributionPopulation(populations?.[name], metric)}));
    const observed = measures.flatMap(({stats}) => [stats.p05, stats.p95]).filter(v => v != null && Number.isFinite(Number(v))).map(Number);
    const card = element("div", null, {class: "qc-metric-plot"});
    const svg = svgNode("svg", {viewBox: "0 0 670 170", class: "qc-chart", role: "img", "aria-label": metric + " quantile distribution summaries"});
    svg.append(svgNode("text", {x: 0, y: 18, class: "qc-chart-title"}, metric));
    if (observed.length) {
      const lo = Math.min(0, ...observed), hi = Math.max(...observed) || 1, x = value => 140 + (Number(value) - lo) / (hi - lo) * 405;
      svg.append(svgNode("line", {x1: 140, y1: 135, x2: 545, y2: 135, stroke: "#dde3eb"}));
      for (const value of [lo, (lo + hi) / 2, hi]) svg.append(svgNode("text", {x: x(value), y: 155, "text-anchor": "middle", class: "qc-chart-label"}, fmt(value)));
      measures.forEach(({name, stats}, i) => {
        const y = 43 + i * 31;
        svg.append(svgNode("text", {x: 0, y: y + 4, class: "qc-chart-label"}, name));
        svg.append(svgNode("text", {x: 555, y: y + 4, class: "qc-population-count"}, `${fmt(stats.measured)} measured`));
        if ([stats.p05, stats.p95, stats.p25, stats.p75, stats.median].every(v => v != null && Number.isFinite(Number(v)))) {
          svg.append(svgNode("line", {x1: x(stats.p05), x2: x(stats.p95), y1: y, y2: y, stroke: colors[name], class: "qc-quantile-line"}));
          svg.append(svgNode("rect", {x: x(stats.p25), y: y - 8, width: Math.max(1, x(stats.p75) - x(stats.p25)), height: 16, fill: colors[name], class: "qc-quantile-box"}));
          svg.append(svgNode("line", {x1: x(stats.median), x2: x(stats.median), y1: y - 10, y2: y + 10, stroke: colors[name], class: "qc-quantile-median"}));
        } else svg.append(svgNode("text", {x: 145, y: y + 4, class: "qc-chart-label"}, "No measured quantiles"));
      });
    } else svg.append(svgNode("text", {x: 0, y: 55, class: "qc-chart-label"}, "Metric unavailable in this preview"));
    card.append(svg, table(["Population", "N", "Measured", "Missing", "Minimum", "Median", "Maximum"], measures.map(({name, stats}) => [name, fmt(stats.n), fmt(stats.measured), fmt(stats.missing), fmt(stats.min), fmt(stats.median), fmt(stats.max)])));
    target.append(card);
  }
}
function renderDistributions(details) {
  distributions($("qc-distributions"), details?.distributions?.global);
  const groups = $("qc-group-distributions"); groups.replaceChildren();
  array(details?.distributions?.groups).forEach(group => {
    const scope = element("details"), body = element("div"); scope.append(element("summary", `${group.group_id} · ${selector(group.selector)}`), body); distributions(body, group); groups.append(scope);
  });
}
function renderSensitivity(details) {
  const target = $("qc-sensitivity"), comparisons = array(details?.sensitivity); target.replaceChildren();
  if (!comparisons.length) {empty(target, "No sensitivity alternatives were requested. Supply a small explicit array in the preview editor to compare supported rules."); return;}
  target.append(table(["Alternative", "Retained", "Removed", "Intersection", "Added", "Removed from primary", "Jaccard"], comparisons.map(c => [c.id, fmt(c.retention?.retained), fmt(c.retention?.removed), array(c.intersection_cells).length, array(c.added_cells).length, array(c.removed_from_primary_cells).length, fmt(c.jaccard)])));
  comparisons.forEach(c => {
    const card = element("details"); card.append(element("summary", `${c.id} · exact scope and typed rules`), raw(c.proposal), ids("Added compared with primary", c.added_cells), ids("Removed compared with primary", c.removed_from_primary_cells));
    const choose = element("button", "Use these rules as an editable draft", {type: "button", class: "button quiet small qc-sensitivity-action"});
    choose.addEventListener("click", () => {$("qc-proposal").value = json(c.proposal); $("qc-proposal").closest("details").open = true; $("qc-proposal").focus(); buttons(); message("Alternative copied to the draft. Save and rebuild the preview before approving this changed plan.");}); card.append(choose); target.append(card);
  });
}
function render() {
  const run = state.view.run, record = run.qc_preview, details = record?.details;
  $("qc-project").textContent = `${run.project_id} · ${run.context?.species || "species undeclared"} · ${run.context?.tissue || "tissue undeclared"} · revision ${run.revision}`;
  $("qc-status").textContent = `${run.status} / ${run.stage}`;
  const metricTarget = $("qc-metrics"); metricTarget.replaceChildren();
  for (const [label, value] of [["Input cells", details?.retention?.before], ["Retained", details?.retention?.retained], ["Removed", details?.retention?.removed], ["Explicit alternatives", array(details?.sensitivity).length]]) {
    const metric = element("div", null, {class: "metric"}); metric.append(element("span", label), element("strong", fmt(value))); metricTarget.append(metric);
  }
  renderRules(details); renderImpacts(details); renderDistributions(details); renderSensitivity(details);
  $("qc-unavailable").replaceChildren(raw(details?.unavailable || {notice: "No verified missing-measurement disclosure is present."}));
  const hashes = element("div", null, {class: "qc-hashes"});
  for (const [label, value] of Object.entries({revision: run.revision, proposal_hash: run.pending?.hash, preview_hash: record?.hash, input_hash: record?.input_hash || run.input_hash, evidence_hash: record?.evidence_hash, rules_hash: record?.rules_hash, parameters_hash: record?.parameters_hash, cell_scope_hash: record?.cell_scope_hash, config_hash: record?.config_hash, implementation_hash: record?.implementation_hash})) hashes.append(element("span", label), element("code", value == null ? "Unavailable" : value));
  $("qc-fingerprints").replaceChildren(hashes);
  const parameters = details?.canonical_parameters || {};
  $("qc-proposal").value = json(parameters.proposal || run.pending?.proposal?.rules || {});
  $("qc-alternatives").value = json(parameters.sensitivity || []);
  $("qc-panels").value = json(Array.isArray(parameters.gene_panels) && parameters.gene_panels.length === 0 ? {} : parameters.gene_panels || {});
  state.savedDraft = [$("qc-proposal").value, $("qc-alternatives").value, $("qc-panels").value].join("\n");
  state.savedProposal = $("qc-proposal").value;
  $("qc-next").textContent = run.status === "ready" ? (new URLSearchParams(window.location.search).get("localContinue") === "1" ? "QC approval is saved. Return to the main review window and use Continue local computation." : "QC approval is saved. Resume on the data machine with sc_run_resume(project_dir).") : run.status === "rejected" ? "QC was rejected. The input and saved evidence remain available for an explicit new proposal in R." : !record ? "No current verified QC impact preview. This page supports QC nodes only; inspect other nodes in R or the annotation workbench." : "Changed fingerprints, concurrent decisions and replaced inputs invalidate a submission. Refresh the saved preview after a conflict.";
  buttons();
}
async function load() {
  state.busy = true; buttons();
  try {state.view = await request(); state.stale = false; render(); message("");}
  catch (error) {message(error.message, true);}
  finally {state.busy = false; buttons();}
}
async function decide(action) {
  if (!active()) return;
  if (action === "approve" && dirty()) {message("Save the changes and review the rebuilt preview before approving.", true); return;}
  if (!$("qc-decision-form").reportValidity()) return;
  const run = state.view.run;
  const payload = {action, expected_revision: run.revision, proposal_hash: run.pending.hash, preview_hash: run.qc_preview.hash, reviewer: $("qc-reviewer").value.trim(), reason: $("qc-reason").value.trim()};
  if (unifiedReview) {
    payload.kind = "qc"; payload.project_id = run.project_id; payload.input_hash = run.input_hash;
    payload.review_hash = payload.preview_hash; delete payload.preview_hash;
  }
  try {
    if (action === "revise") payload.proposal = JSON.parse($("qc-proposal").value);
    if (action === "revise" || action === "preview") {payload.sensitivity = JSON.parse($("qc-alternatives").value); payload.gene_panels = JSON.parse($("qc-panels").value);}
  } catch (error) {message("Draft JSON is invalid: " + error.message, true); return;}
  state.busy = true; buttons();
  try {
    state.view = await request(payload); state.stale = false; render();
    message(action === "approve" ? (new URLSearchParams(window.location.search).get("localContinue") === "1" ? "Approval saved for the exact reviewed QC plan. Return to the main review window and use Continue local computation." : "Approval saved for the exact reviewed QC plan. Resume computation explicitly in R.") : action === "reject" ? "Rejection saved. No cell filtering was executed." : "Changes and reason saved. Review the new impact preview before approving.");
    if (unifiedReview && window.parent !== window) window.parent.postMessage({type: "scagentkit.qc-reviewed", project_id: state.view.run.project_id}, window.location.origin);
  }
  catch (error) {message(error.message + (state.stale ? " Refresh and review the current saved preview before submitting again." : ""), true);}
  finally {state.busy = false; buttons();}
}
$("qc-refresh").addEventListener("click", () => {
  if (dirty() && !window.confirm("Refresh and discard unsaved QC proposal edits? Saved audit history is retained.")) return;
  load();
});
for (const action of ["approve", "reject", "revise", "preview"]) $("qc-" + action).addEventListener("click", () => decide(action));
$("qc-decision-form").addEventListener("submit", event => event.preventDefault());
for (const id of ["qc-proposal", "qc-alternatives", "qc-panels"]) $(id).addEventListener("input", () => {buttons(); if (dirty()) message("The draft differs from the saved preview. Save and rebuild before approving.");});
load();
