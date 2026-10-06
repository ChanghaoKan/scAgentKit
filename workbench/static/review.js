"use strict";
const $ = id => document.getElementById(id);
const array = value => value == null ? [] : Array.isArray(value) ? value : [value];
const json = value => JSON.stringify(value, null, 2);
const hash = value => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
const fmt = value => value == null || !Number.isFinite(Number(value)) ? "unknown" : Number(value).toLocaleString(undefined, {maximumSignificantDigits: 5});
function scopedRunURL(path) {
  const selected = scopeQuery(), id = selected.child_id;
  const suffix = new URLSearchParams();
  if (id) suffix.set("child_id", id);
  if (selected.project_id) suffix.set("project_id", selected.project_id);
  return suffix.size ? path + (path.includes("?") ? "&" : "?") + suffix.toString() : path;
}
const state = {view: null, scopes: null, scopeProject: null, busy: false, stale: false, selectedCluster: null, drafts: new Map(), strategyDraftText: null, madSelect: null, strategyControls: [], batchControls: null, pcControls: null, qcControls: null, clusteringControls: null, strategyFeedback: null, markerMode: "cited", citationInputs: [], continuation: null, pollTimer: null, pollGeneration: 0, pollInFlight: false, connectionLost: false, awaitingFreshInspect: false, pendingRequest: null, suggestion: null, suggestionBusy: false, suggestionChaining: false, suggestionLost: false, suggestionError: "", suggestionTimer: null, suggestionGeneration: 0, suggestionPollInFlight: false, suggestionPending: null};
function scopeQuery() {
  const query = new URLSearchParams(window.location.search || "");
  if ([...query.keys()].some(key => !["child_id", "project_id"].includes(key))) throw new Error("Only registered project identities are accepted in this URL.");
  for (const key of ["child_id", "project_id"]) if (query.has(key) && (query.getAll(key).length !== 1 || !query.get(key) || query.get(key).length > 200 || /[\x00-\x1f\x7f]/.test(query.get(key)))) throw new Error("The selected project URL is invalid. Open one registered scope from the project list.");
  const value = {child_id: query.get("child_id"), project_id: query.get("project_id")};
  if (value.child_id && value.project_id && value.child_id !== value.project_id) throw new Error("The selected child and project identities do not match.");
  if (state.scopeProject && (value.child_id || value.project_id || state.scopes?.parent?.project_id) !== state.scopeProject) throw new Error("The selected project URL changed. Open its registered link in a fresh page.");
  return value;
}
function projectHeaders(headers = {}) {scopeQuery(); const id = state.scopeProject || state.view?.run?.project_id; return id ? {...headers, "X-ScAgentKit-Run-Project": id} : headers;}
function scopeLink(path, projectId, child = false) {const query = new URLSearchParams(); if (child) query.set("child_id", projectId); query.set("project_id", projectId); return path + "?" + query.toString();}
function verifyScopes(answer) {
  const parent = answer?.parent, children = array(answer?.children), seen = new Set();
  if (answer?.schema !== "scagentkit.run-scopes.workbench.v1" || typeof parent?.project_id !== "string" || !parent.project_id || !hash(parent.input_hash) || !Number.isInteger(parent.revision) || typeof parent.ready !== "boolean" || typeof parent.frozen !== "boolean") throw new Error("The registered project list is unverified.");
  seen.add(parent.project_id);
  for (const item of children) if (typeof item?.project_id !== "string" || !item.project_id || seen.has(item.project_id) || Object.hasOwn(item, "project_dir") || !Number.isInteger(item.revision)) throw new Error("The child registry has an invalid or duplicate project identity."); else seen.add(item.project_id);
  const selected = scopeQuery(), id = selected.child_id || parent.project_id;
  if (selected.project_id && selected.project_id !== id || !seen.has(id) || selected.child_id === parent.project_id) throw new Error("This URL does not select a registered parent or child project.");
  if (state.scopeProject && state.scopeProject !== id || state.scopes && state.scopes.parent.project_id !== parent.project_id) throw new Error("The service project binding changed. Reopen the correct registered project.");
  return answer;
}
async function loadScopes() {
  scopeQuery(); const response = await fetch("/api/run-review/scopes", {cache: "no-store"});
  const answer = await response.json(); if (!response.ok) throw new Error(answer?.error || "The registered projects could not be inspected.");
  state.scopes = verifyScopes(answer); state.scopeProject = scopeQuery().child_id || answer.parent.project_id; renderScopes();
}
function renderScopes() {
  const value = state.scopes, section = $("run-scopes"); section.hidden = !value;
  if (!value) return;
  const selected = state.scopeProject, list = $("run-scope-links"); list.replaceChildren();
  for (const [item, child] of [[value.parent, false], ...array(value.children).map(item => [item, true])]) {
    const link = element("a", (child ? "Child: " : "Parent: ") + item.project_id + " · " + item.status, {href: scopeLink("/review", item.project_id, child), "data-project-id": item.project_id, "data-scope-role": child ? "child" : "parent"});
    if (selected === item.project_id) link.setAttribute("aria-current", "page"); list.append(link);
  }
  $("run-scope-current").textContent = (selected === value.parent.project_id ? "Parent project" : "Independent child project") + ": " + selected + ". This tab stays bound to this project; opening another scope does not stop its saved tasks." + (selected === value.parent.project_id && value.parent.frozen ? " The completed parent is read-only in this service; registered children have their own scientific review." : "");
  const workspace = $("run-workspace-link"); workspace.hidden = value.workspace_enabled === false;
  workspace.setAttribute("href", scopeLink("/subclusters", value.parent.project_id));
  workspace.textContent = value.parent.ready ? "Select parent cells or inspect derived outputs" : "Child workspace · available after parent completion";
  const results = $("run-derived-outputs"); results.replaceChildren();
  let activeDerived = false;
  for (const item of array(value.children)) for (const receipt of array(item.applications)) {
    if (receipt.active === true) activeDerived = true;
    const row = element("div", null, {class: "scope-derived-row", "data-application-id": receipt.application_id || ""});
    row.append(element("strong", "Derived parent · " + (receipt.active ? "active" : "historical")), element("p", "Child " + item.project_id + "; new column " + (receipt.column || "recorded in receipt") + ". The original parent output remains saved."), element("a", "Inspect derived output receipt", {href: scopeLink("/subclusters", item.project_id, true)}));
    const output = receipt.output || receipt.path || receipt.output_path; if (output) row.append(element("code", typeof output === "string" ? output : json(output))); results.append(row);
  }
  if (activeDerived) {$("run-derived-details").open = true; section.open = true;}
  if (!results.children.length) results.append(element("p", "No derived parent output has been recorded. Creating a child and reviewing it does not write back labels."));
}
function element(tag, text, attributes = {}) {
  const item = document.createElement(tag); if (text != null) item.textContent = String(text);
  for (const [name, value] of Object.entries(attributes)) item.setAttribute(name, String(value)); return item;
}
function message(text, error = false) {$("run-message").textContent = text; $("run-message").hidden = !text; $("run-message").className = "banner " + (error ? "error" : "notice");}
function node() {return state.view?.run.review_node;}
function activeJob() {return ["queued", "running"].includes(state.continuation?.job?.status);}
function activeSuggestion() {return ["queued", "running"].includes(state.suggestion?.job?.status);}
function continuationEnabled() {return state.continuation?.enabled === true;}
function ready() {return !!state.view && state.view.effective_readonly !== true && !state.busy && !state.stale && !activeJob() && !activeSuggestion() && !state.suggestionBusy && !state.suggestionChaining && !state.suggestionLost && !state.awaitingFreshInspect;}
function annotationRows() {return array(state.view?.run.annotation_review?.details?.annotations);}
function normalizeRow(row) {return {clusterId: String(row.clusterId), label: row.label, confidence: row.confidence, rationale: row.rationale, markers: array(row.markers)};}
function admissibleGenes(item) {return [...new Set(array(item?.supplied_marker_stats).map(row => row.gene).filter(gene => typeof gene === "string" && gene))];}
function unresolvedLabel(label) {return ["unknown", "unannotated"].includes(label.trim().toLowerCase());}
function annotationDirty() {return annotationRows().some(item => json(state.drafts.get(String(item.clusterId))) !== json(normalizeRow(item.proposal)));}
function strategyProposal() {return state.view?.run.strategy_review?.details?.canonical_proposal;}
function strategyDraft() {
  const value = JSON.parse(state.strategyDraftText ?? "null");
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("The strategy must be a complete typed JSON object.");
  return value;
}
function strategyDirty() {
  if (!strategyProposal() || state.strategyDraftText == null) return false;
  try {return json(strategyDraft()) !== json(strategyProposal());} catch (_) {return true;}
}
function strategyDraftError() {
  try {return typedStrategyError(strategyDraft());}
  catch (error) {return error instanceof SyntaxError ? "Enter valid JSON for the complete strategy. No code is evaluated." : error.message;}
}
function harmonyEnabled(details = state.view?.run.strategy_review?.details) {return details?.pc_diagnostics != null || array(details?.capabilities?.batch).includes("harmony");}
function declaredHarmonyColumns(details = state.view?.run.strategy_review?.details) {
  const facts = details?.background?.facts || {}, columns = facts.columns || {}, technical = facts.design?.technical_batch === true;
  const candidates = ["batch", "sample", "donor"].map(role => columns[role]).filter(column => typeof column === "string" && column), protectedColumns = ["capture", "group", "condition", "treatment"].map(role => columns[role]);
  return technical ? [...new Set(candidates)].filter(column => candidates.filter(value => value === column).length === 1 && !protectedColumns.includes(column)) : [];
}
function qcRulesEnabled(details) {return details?.capabilities?.qc_rules?.schema === "scagentkit.qc.rules.v1";}
function typedQCRulesError(qc, details) {
  const legacyRanges = qc?.schema === "scagentkit.qc.v1";
  if (!legacyRanges && qc?.schema !== "scagentkit.qc.rules.v1") return null; // Other legacy choices keep their separate validation.
  if (!legacyRanges && !qcRulesEnabled(details)) return "The saved runtime does not advertise typed combined QC rules. Rebuild the review with supported R capabilities before changing this schema.";
  const fields = legacyRanges ? ["schema", "rationale", "risks", "filters"] : ["schema", "rationale", "risks", "remove_if", "rules"];
  // R's canonical character/numeric vectors auto-unbox at length one.
  const risks = array(qc.risks);
  if (Object.keys(qc).some(key => !fields.includes(key)) || fields.some(key => !Object.hasOwn(qc, key)) ||
      typeof qc.rationale !== "string" || !qc.rationale.trim() || !(Array.isArray(qc.risks) || typeof qc.risks === "string") || risks.some(value => typeof value !== "string" || !value.trim()))
    return legacyRanges ? "QC ranges require exactly schema, a nonempty rationale, risks as text entries and filters." : "QC rules require exactly schema, a nonempty rationale, risks as text entries, remove_if and rules.";
  const rules = legacyRanges ? qc.filters : qc.rules;
  if (legacyRanges ? !Array.isArray(rules) || !rules.length : !["any", "all"].includes(qc.remove_if) || !Array.isArray(rules) || !rules.length || rules.length > 32)
    return legacyRanges ? "QC filters must be a nonempty array of explicit range operations; an empty response is not a keep-all decision." : "Choose failure logic any or all and 1–32 explicit QC rules.";
  let mad = 0;
  for (const rule of rules) {
    if (!rule || typeof rule !== "object" || Array.isArray(rule)) return legacyRanges ? "Every legacy QC filter must be a typed range operation." : "Each QC rule must be a typed range or one saved MAD preset.";
    if (rule.op === "mad_preset" && !legacyRanges) {
      mad++;
      const panel = details?.mad_panel;
      if (mad > 1 || Object.keys(rule).some(key => !["op", "preset_id", "panel_hash"].includes(key)) || !madPresets.includes(rule.preset_id) ||
          !hash(rule.panel_hash) || rule.panel_hash !== panel?.panel_hash || !array(panel?.presets).some(row => row.preset_id === rule.preset_id && row.available === true))
        return "QC supports at most one available MAD preset bound to the saved panel; no MAD parameters or unavailable candidate is invented.";
    } else if (rule.op === "range") {
      if (Object.keys(rule).some(key => !["op", "metric", "min", "max", "group"].includes(key)) || !["nCount", "nFeature", "percent_mt"].includes(rule.metric))
        return "QC ranges support only nCount, nFeature or percent_mt with min, max and an optional sample/capture selector.";
      if (rule.min == null && rule.max == null) return "Every QC range needs at least one explicit bound; blank is not an implicit keep-all rule.";
      for (const bound of [rule.min, rule.max]) if (bound != null && (typeof bound !== "number" || !Number.isFinite(bound) || bound < 0 || (rule.metric === "percent_mt" ? bound > 100 : !Number.isInteger(bound))))
        return "QC bounds must be finite nonnegative numbers; counts/features are integers and percent_mt is 0–100.";
      if (rule.min != null && rule.max != null && rule.min > rule.max) return "QC range minimum cannot exceed maximum.";
      if (rule.group != null && (typeof rule.group !== "object" || Array.isArray(rule.group) || !Object.keys(rule.group).length || Object.keys(rule.group).some(role => !["sample", "capture"].includes(role) || typeof rule.group[role] !== "string" || !rule.group[role])))
        return "QC grouping accepts only literal declared sample/capture selectors; donor, condition and batch are separate roles.";
    } else return legacyRanges ? "The saved range-QC schema supports only typed range operations; no arbitrary code or MAD conversion is executed." : "Only typed range and saved mad_preset QC operations are supported; no arbitrary code is executed.";
  }
  return null;
}
function clusteringDraftError(clustering) {
  if (clustering == null) return null; // Explicit processed reuse.
  if (typeof clustering !== "object" || Array.isArray(clustering) || Object.keys(clustering).some(key => !["resolution", "diagnostic_resolutions"].includes(key)) ||
      typeof clustering.resolution !== "number" || !Number.isFinite(clustering.resolution) || clustering.resolution <= 0 || clustering.resolution > 2)
    return "Clustering needs a direct finite resolution in (0,2]; only optional diagnostic_resolutions are supported.";
  const supplied = clustering.diagnostic_resolutions, values = array(supplied);
  if (supplied != null && (!(Array.isArray(supplied) || typeof supplied === "number") || !values.length || values.length > 5 || new Set(values).size !== values.length || values.some(value => typeof value !== "number" || !Number.isFinite(value) || value <= 0 || value > 2)))
    return "Supply at most five unique finite diagnostic resolutions in (0,2], or leave the comparison empty. No candidate is rounded or clipped.";
  return null;
}
function typedStrategyError(value, details = state.view?.run.strategy_review?.details) {
  if (value?.schema !== "scagentkit.strategy.v1") return "Keep the supported scagentkit.strategy.v1 schema. R validates every operation and parameter.";
  const allowed = ["schema", "rationale", "risks", "inferences", "qc", "analysis", "pcs", "batch", "clustering", "umap", "cycle", "doublet"];
  if (Object.keys(value).some(key => !allowed.includes(key))) return "Only supported typed strategy fields can be saved. Provider settings, arbitrary code and extra operations are rejected.";
  function unsafeFields(item) {return item && typeof item === "object" && Object.entries(item).some(([key, child]) => ["code", "r_code", "provider", "chat_fn", "command", "script", "api_key", "system_prompt"].includes(key) || unsafeFields(child));}
  if (unsafeFields(value)) return "Arbitrary code, provider settings and secret-bearing fields cannot be saved as strategy operations.";
  const parameterError = typedQCRulesError(value.qc, details) || clusteringDraftError(value.clustering);
  if (parameterError) return parameterError;
  if (value.doublet != null && (typeof value.doublet !== "object" || Array.isArray(value.doublet) || Object.keys(value.doublet).some(key => !["method", "reason"].includes(key)) ||
      !["keep", "remove_predicted"].includes(value.doublet.method) || typeof value.doublet.reason !== "string" || !value.doublet.reason.trim()))
    return "Doublet choices accept only keep or remove_predicted with an explicit analyst reason; scores alone never authorize deletion.";
  const batch = value.batch, strict = harmonyEnabled(details);
  if (!batch || typeof batch !== "object" || Array.isArray(batch) || !["none", "manual", "harmony"].includes(batch.method)) return "Choose a supported batch method: none, manual or harmony.";
  const fields = batch.method === "harmony" ? ["method", "group_by_vars", "theta", "lambda", "sigma", "max_iter", "nclust", "reason"] : ["method", "reason"];
  if (Object.keys(batch).some(key => !fields.includes(key)) || batch.method === "harmony" && fields.some(key => !Object.hasOwn(batch, key))) return "The batch operation accepts exactly its typed method fields; arbitrary code and provider parameters are rejected.";
  if ((strict || batch.method === "harmony" || Object.hasOwn(batch, "reason")) && (typeof batch.reason !== "string" || !batch.reason.trim())) return "Every batch choice needs an explicit nonempty analyst reason.";
  if (batch.method === "harmony") {
    const groups = array(batch.group_by_vars), declared = declaredHarmonyColumns(details);
    if (groups.length < 1 || groups.length > 3 || groups.some(column => typeof column !== "string" || !column || !declared.includes(column)) || new Set(groups).size !== groups.length)
      return "Harmony needs 1–3 unique explicitly declared technical batch/sample/donor metadata columns. Condition, group and capture are not inferred as correction variables.";
    for (const key of ["theta", "lambda"]) {
      const values = array(batch[key]);
      if (!(typeof batch[key] === "number" || Array.isArray(batch[key])) || ![1, groups.length].includes(values.length) || values.some(number => typeof number !== "number" || !Number.isFinite(number) || (key === "theta" ? number < 0 : number <= 0)))
        return "Harmony " + key + " must be a finite numeric scalar or array with one value or one per correction column; theta >= 0 and lambda > 0.";
    }
    if (typeof batch.sigma !== "number" || !Number.isFinite(batch.sigma) || batch.sigma <= 0 || batch.sigma > 1 ||
        !Number.isInteger(batch.max_iter) || batch.max_iter < 1 || batch.max_iter > 50 || !Number.isInteger(batch.nclust) || batch.nclust < 2 || batch.nclust > 100)
      return "Harmony requires sigma in (0,1], integer max_iter 1–50 and integer nclust 2–100. No parameter is clipped or guessed.";
  }
  const pcs = value.pcs;
  if (pcs == null) return null; // Explicit processed-object reuse.
  const pcFields = pcs.method === "fixed" ? ["method", "ndim"] : ["method", "threshold"];
  if (!pcs || typeof pcs !== "object" || Array.isArray(pcs) || !["fixed", "computed_variance", "computed_top50"].includes(pcs.method) ||
      Object.keys(pcs).some(key => !pcFields.includes(key)) || pcFields.some(key => !Object.hasOwn(pcs, key))) return "PC selection accepts only fixed ndim, computed_variance threshold or the computed_top50 policy; no code or invented dimensions.";
  if (pcs.method === "fixed" && (!Number.isInteger(pcs.ndim) || pcs.ndim < 2 || Number.isInteger(value.analysis?.npcs) && pcs.ndim > value.analysis.npcs) || pcs.method === "computed_variance" && (typeof pcs.threshold !== "number" || !Number.isFinite(pcs.threshold) || pcs.threshold <= 0 || pcs.threshold >= 1) ||
      pcs.method === "computed_top50" && ![0.8, 0.85].includes(pcs.threshold)) return "Choose valid typed PCs. computed_top50 supports only 0.80 or 0.85 and derives actual dimensions after PCA is computed.";
  return null;
}
function doubletEnabled(details, proposal) {
  return details?.doublet_diagnostics != null || Object.hasOwn(proposal || {}, "doublet") || Array.isArray(details?.capabilities?.doublet);
}
const madPresets = ["keep_all", "conservative_and3", "low_counts3", "low_features3", "high_mt3", "any_quality3"];
function madEnabled(details, proposal) {return details?.mad_panel != null || details?.qc_mad != null || proposal?.qc?.schema === "scagentkit.qc.mad.v1";}
function madReviewError(details = state.view?.run.strategy_review?.details, proposal = details?.canonical_proposal) {
  if (proposal?.qc?.schema === "scagentkit.qc.rules.v1") return qcRulesReviewError(details, proposal);
  if (!madEnabled(details, proposal)) return null;
  const saved = details?.qc_mad, panel = details?.mad_panel, choice = proposal?.qc;
  if (choice?.schema !== "scagentkit.qc.mad.v1" || panel?.schema !== "scagentkit.qc.mad.evidence.v1" ||
      !hash(choice.panel_hash) || choice.panel_hash !== saved.panel_hash || choice.panel_hash !== panel.panel_hash || !hash(saved.evidence_hash))
    return "MAD review is unverified: the saved finite panel or proposal binding is unavailable or mismatched. Rebuild the complete review in R.";
  const candidates = array(panel.presets), ids = candidates.map(row => row?.preset_id);
  if (!madPresets.includes(choice.preset_id) || ids.some(id => !madPresets.includes(id)) || new Set(ids).size !== ids.length ||
      !candidates.some(row => row.preset_id === choice.preset_id && row.available === true && row.all_cells_removed !== true))
    return "MAD review is unverified: the selected preset is unsupported or unavailable. Choose an available saved candidate and save the complete strategy.";
  if (saved.choice?.preset_id !== choice.preset_id || saved.choice?.panel_hash !== choice.panel_hash)
    return "MAD review is unverified: the selected preset differs from its saved impact. Rebuild the complete review in R.";
  const exact = details.qc_impact, selected = candidates.find(row => row.preset_id === choice.preset_id), scopes = {};
  for (const key of ["keep_cells", "remove_cells"]) {
    if (!exact || !Object.hasOwn(exact, key) || !(Array.isArray(exact[key]) || typeof exact[key] === "string"))
      return "MAD review is unverified: the complete exact quality scope is unavailable. Rebuild the review in R.";
    scopes[key] = array(exact[key]);
    if (scopes[key].some(cell => typeof cell !== "string" || !cell) || new Set(scopes[key]).size !== scopes[key].length)
      return "MAD review is unverified: exact quality cell IDs are missing or duplicated. Rebuild the review in R.";
  }
  if (!hash(exact.keep_cell_hash) || !hash(exact.remove_cell_hash) || scopes.keep_cells.some(cell => scopes.remove_cells.includes(cell)) ||
      !Number.isInteger(selected.retained) || selected.retained <= 0 || selected.retained !== scopes.keep_cells.length || !Number.isInteger(selected.before) || selected.before !== scopes.keep_cells.length + scopes.remove_cells.length)
    return "MAD review is unverified: quality scope fingerprints or counts do not match the selected panel candidate. Rebuild the review in R.";
  return null;
}
function qcRulesReviewError(details, proposal) {
  const error = typedQCRulesError(proposal.qc, details); if (error) return error;
  const preview = details?.qc_impact, logic = preview?.rule_logic;
  if (preview?.schema !== "scagentkit.qc.preview.v1" || !hash(preview.evidence_hash) || logic?.remove_if !== proposal.qc.remove_if ||
      array(logic?.rule_ids).length !== proposal.qc.rules.length || new Set(array(logic?.rule_ids)).size !== proposal.qc.rules.length || array(logic?.rule_ids).some(id => typeof id !== "string" || !id) || json(preview.canonical_parameters?.proposal) !== json(proposal.qc))
    return "QC rule review is unverified: the saved logic, parameters or evidence differ. Save and inspect a rebuilt review in R.";
  const keep = array(preview.keep_cells), remove = array(preview.remove_cells), retention = preview.retention;
  if (!Object.hasOwn(preview, "keep_cells") || !Object.hasOwn(preview, "remove_cells") || !hash(preview.keep_cell_hash) || !hash(preview.remove_cell_hash) ||
      [...keep, ...remove].some(cell => typeof cell !== "string" || !cell) || new Set([...keep, ...remove]).size !== keep.length + remove.length ||
      !Number.isInteger(retention?.before) || !Number.isInteger(retention?.retained) || retention.retained < 1 || retention.retained !== keep.length || retention.before !== keep.length + remove.length)
    return "QC rule review is unverified: exact retained/removed IDs, counts or fingerprints do not partition the original input.";
  if (proposal.qc.rules.some(rule => rule.op === "mad_preset") && (!hash(details?.qc_mad?.evidence_hash) ||
      details.qc_mad.panel_hash !== details.mad_panel?.panel_hash || json(details.qc_mad.choice) !== json(proposal.qc)))
    return "QC rule review is unverified: the saved MAD panel or combined choice is mismatched. Rebuild in R.";
  return null;
}
function chooseMadPreset(presetId) {
  if (!ready() || node()?.kind !== "strategy" || !node()?.can_revise) return;
  const saved = state.view?.run.strategy_review?.details?.qc_mad;
  if (!madPresets.includes(presetId) || !array(state.view?.run.strategy_review?.details?.mad_panel?.presets).some(row => row.preset_id === presetId && row.available === true && row.all_cells_removed !== true)) return;
  try {
    const draft = strategyDraft();
    draft.qc = {schema: "scagentkit.qc.mad.v1", rationale: "Analyst selected the saved " + presetId + " candidate for concentrated impact review.",
      risks: array(draft.qc?.risks), preset_id: presetId, panel_hash: saved.panel_hash};
    state.strategyDraftText = json(draft); $("strategy-json").value = state.strategyDraftText;
    updateStrategyDraftStatus(); buttons();
  } catch (_) {message("Correct the complete strategy JSON before selecting a saved MAD preset.", true);}
}
function namedEvidenceRows(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? Object.entries(value).filter(([, row]) => row && typeof row === "object" && !Array.isArray(row)) : [];
}
function doubletReviewError(details = state.view?.run.strategy_review?.details, proposal = details?.canonical_proposal) {
  if (!doubletEnabled(details, proposal)) return null;
  const impact = details?.applicability?.doublet, evidence = details?.doublet_diagnostics;
  if ((proposal?.doublet?.method ?? "keep") === "keep") {
    if (impact && (impact.method !== "keep" || array(impact.removed_cell_ids).length || impact.removed_cells > 0)) return "Doublet removal is unverified: keep cannot include a deletion scope. Rebuild the complete review in R.";
    return null;
  }
  if (proposal?.doublet?.method !== "remove_predicted" || impact?.method !== "remove_predicted") return "Doublet removal is unverified: inspect the saved supported method and rebuild the complete review in R.";
  if (evidence?.schema !== "scagentkit.doublet.evidence.v1" || evidence.status !== "available" ||
      !hash(details.doublet_evidence_hash) || !hash(impact.evidence_hash) || impact.evidence_hash !== details.doublet_evidence_hash || !hash(impact.selection_hash))
    return "Doublet removal is unverified: the saved diagnostic or exact selection fingerprint is unavailable or mismatched. Rebuild the review in R.";
  const keys = ["qc_keep_cell_ids", "selected_cell_ids", "removed_cell_ids"], scopes = {};
  for (const key of keys) {
    if (!Object.hasOwn(impact, key) || !(Array.isArray(impact[key]) || typeof impact[key] === "string")) return "Doublet removal is unverified: the exact cell scope is unavailable. Rebuild the review in R.";
    const cells = array(impact[key]);
    if (cells.some(cell => typeof cell !== "string" || !cell) || new Set(cells).size !== cells.length) return "Doublet removal is unverified: exact cell IDs are missing or duplicated. Rebuild the review in R.";
    scopes[key] = new Set(cells);
  }
  const qc = scopes.qc_keep_cell_ids, selected = scopes.selected_cell_ids, removed = scopes.removed_cell_ids;
  if ([...selected].some(cell => !qc.has(cell) || removed.has(cell)) || [...removed].some(cell => !qc.has(cell)) ||
      selected.size + removed.size !== qc.size) return "Doublet removal is unverified: selected and removed IDs do not partition the saved QC scope. Rebuild the review in R.";
  for (const [key, count] of [["qc_retained", qc.size], ["removed_cells", removed.size], ["retained_cells", selected.size]])
    if (!Number.isInteger(impact[key]) || impact[key] !== count) return "Doublet removal is unverified: the saved impact count does not match its exact cell scope. Rebuild the review in R.";
  const captureRows = namedEvidenceRows(impact.per_capture);
  if (!captureRows.length || captureRows.length !== Object.keys(impact.per_capture).length ||
      captureRows.some(([, row]) => ["input_cells", "qc_retained", "removed", "retained", "predicted_input", "predicted_after_qc", "predicted_qc_excluded"].some(key => !Number.isInteger(row[key]) || row[key] < 0) || row.removed + row.retained !== row.qc_retained || row.qc_retained > row.input_cells || row.removed > row.predicted_after_qc) ||
      captureRows.reduce((sum, [, row]) => sum + row.qc_retained, 0) !== qc.size ||
      captureRows.reduce((sum, [, row]) => sum + row.removed, 0) !== removed.size ||
      captureRows.reduce((sum, [, row]) => sum + row.retained, 0) !== selected.size)
    return "Doublet removal is unverified: the saved per-capture impact is unavailable or inconsistent with the exact scope. Rebuild the review in R.";
  return null;
}
function dirty() {return annotationDirty() || strategyDirty();}
function draftError() {
  for (const item of annotationRows()) {
    const row = state.drafts.get(String(item.clusterId)), base = normalizeRow(item.proposal);
    if (!row || typeof row.label !== "string" || !row.label.trim() || !["low", "medium", "high"].includes(row.confidence)) return "Every cluster needs a supported label and qualitative confidence.";
    if (!unresolvedLabel(row.label) && !array(row.markers).length) return "A known label needs a supporting citation from this cluster's supplied marker evidence; choose a citation or Unknown.";
    if (array(row.markers).some(gene => !admissibleGenes(item).includes(gene))) return "Citations must come from this exact cluster's supplied marker evidence.";
    if (json(row) !== json(base) && (!row.rationale?.trim() || row.rationale.trim() === base.rationale.trim())) return "Each changed cluster needs its own explicit reason for the correction.";
  }
  return null;
}
function suggestionButtons() {
  const answer = state.suggestion, item = answer?.suggestion;
  const idle = !!state.view && !state.busy && !state.stale && !activeJob() && !activeSuggestion() && !state.suggestionBusy && !state.suggestionChaining && !state.suggestionLost && !dirty();
  const current = idle && answer?.enabled === true && item?.revision === state.view.run.revision && hash(item?.suggestion_hash);
  $("suggestion-preview").disabled = state.view?.suggestion_enabled !== true || state.busy || activeJob() || state.suggestionBusy || state.suggestionChaining || dirty();
  for (const [id, permission] of [["suggestion-approve", "can_approve"], ["suggestion-request", "can_request"], ["suggestion-adopt", "can_adopt"], ["suggestion-modify", "can_adopt"], ["suggestion-discard", "can_discard"]]) {
    $(id).hidden = item?.[permission] !== true;
    $(id).disabled = !current || item?.[permission] !== true;
  }
  for (const id of ["suggestion-reviewer", "suggestion-reason"]) $(id).disabled = !idle;
}
function verifySuggestion(answer) {
  const item = answer?.suggestion, run = state.view?.run;
  if (answer?.schema !== "scagentkit.run-suggestion.workbench.v1" || typeof answer.enabled !== "boolean" || typeof answer.csrf_token !== "string" || !answer.csrf_token ||
      item?.schema !== "scagentkit.run-suggestion.v1" || !run || item.project_id !== run.project_id || item.input_hash !== run.input_hash || !Number.isInteger(item.revision) || item.revision < 0 ||
      typeof item.available !== "boolean" || ![null, "strategy", "qc", "annotation"].includes(item.kind) || (item.suggestion_hash != null && !hash(item.suggestion_hash)))
    throw new Error("The model preview is not bound to this saved project and input.");
  for (const permission of ["can_approve", "can_request", "can_adopt", "can_discard"]) {
    if (typeof item[permission] !== "boolean" || item[permission] && !hash(item.suggestion_hash)) throw new Error("The model action has no verified saved preview binding.");
  }
  const preview = item.preview;
  if (preview != null && (!hash(preview.request_hash) || typeof preview.model !== "string" || !preview.model || typeof preview.external !== "boolean" || typeof preview.simulated !== "boolean" ||
      typeof preview.system_prompt !== "string" || typeof preview.user_prompt !== "string" || !preview.generation || typeof preview.generation !== "object" || Array.isArray(preview.generation)))
    throw new Error("The exact outgoing model payload or generation settings are unverified.");
  if (["can_approve", "can_request", "can_adopt"].some(key => item[key]) && (!preview || !item.available)) throw new Error("This model action is not available for the inspected saved boundary.");
  if (item.candidate != null) {
    const schema = item.kind === "strategy" ? "scagentkit.strategy.v1" : item.kind === "qc" ? ["scagentkit.qc.v1", "scagentkit.qc.mad.v1"] : "scagentkit.annotation.v1";
    if (typeof item.candidate !== "object" || Array.isArray(item.candidate) || !array(schema).includes(item.candidate.schema)) throw new Error("The model candidate is not a supported typed proposal.");
  } else if (item.can_adopt) throw new Error("There is no typed candidate to review.");
  const job = answer.job;
  if (job != null && (typeof job.job_id !== "string" || !/^[a-zA-Z0-9._-]{1,128}$/.test(job.job_id) || !["queued", "running", "succeeded", "failed", "interrupted", "timed_out"].includes(job.status) ||
      job.project_id !== run.project_id || job.input_hash !== run.input_hash || !Number.isInteger(job.expected_revision) || job.expected_revision < 0 ||
      typeof job.request_id !== "string" || !/^[a-zA-Z0-9._-]{1,200}$/.test(job.request_id) || (job.suggestion_hash != null && !hash(job.suggestion_hash))))
    throw new Error("The saved model task does not match this project and input.");
  return answer;
}
function qcRulesSummary(qc) {
  const rules = Array.isArray(qc.rules) ? qc.rules : [], ranges = rules.filter(rule => rule?.op === "range").length, mad = rules.filter(rule => rule?.op === "mad_preset").length;
  return "QC: " + rules.length + " typed failure rules (" + ranges + " fixed ranges; " + mad + " saved MAD presets) · remove_if " + qc.remove_if + (qc.remove_if === "all" ? " · AND" : qc.remove_if === "any" ? " · OR" : " · unsupported logic");
}
function suggestionSummary(candidate, kind) {
  if (!candidate) return [];
  if (kind === "annotation") return array(candidate.annotations).map(row => `${String(row.clusterId)}: ${row.label} · ${row.confidence} confidence`);
  if (kind === "qc" && candidate.schema === "scagentkit.qc.rules.v1") return [candidate.rationale || "Typed QC proposal", qcRulesSummary(candidate)];
  if (kind === "qc") return [candidate.rationale || "Typed QC proposal", candidate.preset_id ? "Saved MAD preset: " + candidate.preset_id : "Supported range rules: " + array(candidate.filters).length];
  const parts = [candidate.rationale || "Typed analysis strategy"];
  if (candidate.qc?.schema === "scagentkit.qc.rules.v1") parts.push(qcRulesSummary(candidate.qc));
  else if (candidate.qc?.preset_id) parts.push("QC: saved MAD preset " + candidate.qc.preset_id);
  else if (candidate.qc) parts.push("QC: " + array(candidate.qc.filters).length + " supported range rules");
  if (candidate.analysis) parts.push(`${candidate.analysis.normalization_method} · ${candidate.analysis.nfeatures} requested HVGs · ${candidate.analysis.npcs} requested PCs`);
  if (candidate.batch) parts.push("Batch: " + candidate.batch.method);
  if (candidate.clustering) parts.push("Clustering resolution: " + candidate.clustering.resolution);
  if (candidate.cycle) parts.push("Cycle: " + candidate.cycle.method);
  if (candidate.doublet) parts.push("Doublets: " + candidate.doublet.method);
  return parts;
}
function renderSuggestion() {
  const answer = state.suggestion, item = answer?.suggestion, preview = item?.preview, job = answer?.job;
  const section = $("run-suggestion"); section.setAttribute("data-connection", state.suggestionLost ? "lost" : "verified"); section.setAttribute("data-job-status", job?.status || "none");
  const disabled = state.view?.suggestion_enabled !== true;
  $("suggestion-status").textContent = state.suggestionLost ? "Connection unverified" : job && ["queued", "running", "failed", "interrupted", "timed_out"].includes(job.status) ? "Model task: " + job.status : item?.available === false ? "Unavailable at this step" : item?.status || (answer?.enabled === false || disabled ? "Unavailable" : "Not requested");
  $("suggestion-simulated").hidden = preview?.simulated !== true && answer?.simulated !== true;
  const provider = typeof preview?.provider === "string" ? preview.provider : preview?.provider?.name;
  $("suggestion-summary").textContent = preview ? `${provider || "Configured provider"} · ${preview.model} · ${item.kind || "analysis"} suggestion. ${preview.external ? "Review and approve this exact aggregate before transmission." : "This declared local provider does not transmit to an external model."}` : answer?.enabled === false || disabled ? "Model suggestions are disabled for this server. Configure a supported provider on the analysis machine and explicitly enable the suggestion worker; no request has been sent. Scientific review and local Continue remain available." : item?.blocked_reason || "Preview the provider already configured on the analysis machine. This page cannot set a key, endpoint, model or budget.";
  $("suggestion-notice").textContent = preview?.notice || "";
  $("suggestion-approve").textContent = preview?.simulated ? "Approve and run this exact simulated suggestion" : preview?.external ? "Approve and request this exact aggregate transfer" : "Approve and request this exact local suggestion";
  $("suggestion-request").textContent = preview?.simulated ? "Run this approved simulated suggestion" : "Request this approved suggestion";
  if (item?.available === true && preview && (item.can_approve || item.can_request)) $("suggestion-preview-details").open = true;
  $("suggestion-result").hidden = !item?.candidate;
  $("suggestion-candidate").replaceChildren(...suggestionSummary(item?.candidate, item?.kind).map(text => element("p", text)));
  $("suggestion-impact").textContent = item?.kind === "annotation" ? "These labels are suggestions for the saved cluster scopes. Accepting them opens scientific review; it does not change cells or apply labels." : "R will calculate and display exact retention and operation applicability when this candidate enters scientific review. No candidate has changed the object.";
  const risks = array(item?.candidate?.risks).filter(value => typeof value === "string" && value);
  if (item?.kind === "annotation") risks.push("Marker agreement and model confidence do not establish biological identity. Use Unknown for unresolved clusters.");
  if (!risks.length) risks.push("No candidate-specific risks were supplied. Inspect the rebuilt scientific evidence before approval.");
  $("suggestion-risks").replaceChildren(...risks.map(text => element("li", text)));
  const response = item?.response;
  let note = state.suggestionError || item?.blocked_reason || "";
  if (!note && activeSuggestion()) note = "The request is saved on the analysis machine. Closing or reloading the page does not submit another request. Scientific decisions are disabled while this task is active.";
  else if (!note && response && response.status !== "ok") note = "Model result: " + response.status + ". " + (response.error || "No candidate was accepted. Inspect the saved accounting before an explicit next action.") + " No automatic retry will occur.";
  else if (!note && job && ["failed", "interrupted", "timed_out"].includes(job.status)) note = "The saved model task " + job.status + ". " + (job.error?.message || "Inspect the authoritative saved result and usage ledger.") + (job.requires_reconciliation ? " Delivery or accounting may be uncertain; explicit reconciliation is required." : "") + " No automatic retry will occur.";
  else if (!note && item?.candidate) note = response?.cached ? "This candidate came from the matching saved cache. Accept or modify it in central scientific review; it is still unapproved." : "The typed candidate is saved. Accept or modify it in central scientific review; it is still unapproved.";
  else if (!note && item?.can_request) note = preview?.external ? "The exact transfer is approved. Requesting a suggestion is a separate explicit action." : "Requesting this declared local suggestion is an explicit action.";
  if (!note && item?.kind === "annotation" && !item?.candidate) note = "A manual Unknown proposal can be prepared for a child on its scope page. A parent without a proposal still needs a supported manual annotation configuration in R.";
  $("suggestion-message").textContent = note; $("suggestion-message").className = "suggestion-message" + (state.suggestionLost || response && response.status !== "ok" ? " error" : "");
  const disclosure = $("suggestion-disclosure");
  if (disclosure.dataset.initialized !== "true") {disclosure.open = !disabled; disclosure.setAttribute("data-initialized", "true");}
  // A collapsed disabled worker is presentation only. Exact consent, saved
  // candidates, active/failed tasks and errors must remain visibly reachable.
  if (preview || item?.candidate || job || state.suggestionLost || state.suggestionError || response && response.status !== "ok") disclosure.open = true;
  $("suggestion-disclosure-status").textContent = $("suggestion-status").textContent;
  $("suggestion-job-details").hidden = !job; $("suggestion-job-id").textContent = job?.job_id || "";
  $("suggestion-payload").replaceChildren(preview ? raw({model: preview.model, generation: preview.generation, external: preview.external, simulated: preview.simulated, system_prompt: preview.system_prompt, user_prompt: preview.user_prompt}) : element("p", "No exact request preview is available.", {class: "review-empty"}));
  $("suggestion-accounting").replaceChildren(raw(preview ? {budget_usd: preview.budget, reservation_usd: preview.reservation_usd, charged_or_held_usd: preview.charged_or_held_usd, known_cost_usd: preview.known_cost_usd, held_usd: preview.held_usd, response: response ? {status: response.status, cached: response.cached, cost_state: response.cost_state, cost_usd: response.cost_usd, charged_or_held_usd: response.charged_or_held_usd, usage: response.usage, response_metadata: response.response_metadata} : null} : {status: "No request accounting is available."}));
  const fingerprints = $("suggestion-fingerprints"); fingerprints.replaceChildren();
  for (const [name, value] of Object.entries({project_id: item?.project_id, input_hash: item?.input_hash, revision: item?.revision, suggestion_hash: item?.suggestion_hash, request_hash: preview?.request_hash})) fingerprints.append(element("span", name), element("code", value == null ? "Unavailable" : value));
  $("suggestion-candidate-details").hidden = !item?.candidate; $("suggestion-candidate-json").replaceChildren(item?.candidate ? raw(item.candidate) : element("p", "No typed candidate."));
  suggestionButtons();
}
function stopSuggestionPolling() {if (state.suggestionTimer != null) clearTimeout(state.suggestionTimer); state.suggestionTimer = null; state.suggestionGeneration += 1;}
function scheduleSuggestionPoll() {
  if (!activeSuggestion() || state.suggestionLost || state.suggestionTimer != null) return;
  const generation = state.suggestionGeneration;
  state.suggestionTimer = setTimeout(() => {state.suggestionTimer = null; pollSuggestion(generation);}, 1000);
}
async function suggestionRequest(action = null, payload = null) {
  // Local preview/review IPC is bounded at 120 seconds. Allow its response to
  // arrive before aborting HTTP; model execution still returns an async job.
  const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 125000);
  try {
    const route = "/api/run-review/suggestion" + (action ? "/" + action : "");
    const response = await fetch(scopedRunURL(route), action ? {method: "POST", headers: projectHeaders({"Content-Type": "application/json", "X-ScAgentKit-Suggestion-Token": state.suggestion?.csrf_token || state.view.csrf_token}), body: JSON.stringify(payload || {}), signal: controller.signal} : {cache: "no-store", headers: projectHeaders(), signal: controller.signal});
    const answer = await response.json(); if (!response.ok) throw new Error(answer?.error || "The saved model suggestion could not be verified.");
    return verifySuggestion(answer);
  } finally {clearTimeout(timer);}
}
function suggestionLost(error) {
  stopSuggestionPolling(); state.suggestionLost = true;
  state.suggestionError = error.message + " The saved model task may still be running. Preview or refresh to verify it; this page will not resubmit automatically.";
  renderSuggestion(); buttons();
}
async function loadSuggestion() {
  if (!state.view || state.view.suggestion_enabled !== true) return;
  stopSuggestionPolling(); state.suggestionBusy = true; buttons();
  try {
    state.suggestion = await suggestionRequest(); state.suggestionLost = false; state.suggestionError = "";
    renderSuggestion();
  } catch (error) {suggestionLost(error);}
  finally {state.suggestionBusy = false; renderSuggestion(); buttons(); if (activeSuggestion() && !state.suggestionLost) scheduleSuggestionPoll();}
}
async function pollSuggestion(generation) {
  if (generation !== state.suggestionGeneration || !activeSuggestion() || state.suggestionPollInFlight || state.busy || state.suggestionBusy) {scheduleSuggestionPoll(); return;}
  state.suggestionPollInFlight = true;
  try {
    const answer = await suggestionRequest(); if (generation !== state.suggestionGeneration) return;
    state.suggestion = answer; state.suggestionError = ""; renderSuggestion(); buttons();
    if (activeSuggestion()) scheduleSuggestionPoll();
    else {stopSuggestionPolling(); if (dirty()) {state.stale = true; state.suggestionError = "The model task stopped. Unsaved scientific corrections are preserved; refresh the saved project before another action."; renderSuggestion(); buttons();} else await load();}
  } catch (error) {if (generation === state.suggestionGeneration) suggestionLost(error);}
  finally {state.suggestionPollInFlight = false;}
}
function suggestionPayload(action) {
  const item = state.suggestion.suggestion;
  const payload = {project_id: item.project_id, input_hash: item.input_hash, expected_revision: item.revision, suggestion_hash: item.suggestion_hash};
  payload.reviewer = $("suggestion-reviewer").value.trim(); payload.reason = $("suggestion-reason").value.trim();
  if (!payload.reviewer || !payload.reason) throw new Error("Enter a reviewer and a reason for this exact transfer, request or candidate decision.");
  if (action === "request") {
    const key = "scagentkit.model-request.v1:" + item.project_id + ":" + item.input_hash + ":" + item.suggestion_hash;
    let saved = state.suggestionPending;
    try {saved ||= JSON.parse(sessionStorage.getItem(key) || "null");} catch (_) {}
    if (saved && Object.keys(payload).every(name => saved[name] === payload[name]) && typeof saved.request_id === "string" && /^[a-zA-Z0-9._-]{1,200}$/.test(saved.request_id)) payload.request_id = saved.request_id;
    else payload.request_id = crypto.randomUUID();
    state.suggestionPending = payload;
    try {sessionStorage.setItem(key, JSON.stringify(payload));} catch (_) {}
  }
  return payload;
}
function exactSuggestionBinding(item) {
  const preview = item?.preview;
  return json({project_id: item?.project_id, input_hash: item?.input_hash, kind: item?.kind, suggestion_hash: item?.suggestion_hash,
    request_hash: preview?.request_hash, provider: preview?.provider, model: preview?.model, generation: preview?.generation,
    external: preview?.external, simulated: preview?.simulated, system_prompt: preview?.system_prompt, user_prompt: preview?.user_prompt});
}
function verifyApprovedSuggestion(answer, binding, revision) {
  const item = answer?.suggestion;
  if (answer?.enabled !== true || item?.available !== true || item.status !== "approved" || item.revision !== revision ||
      item.can_approve !== false || item.can_request !== true || item.can_adopt !== false || item.replay_only === true || exactSuggestionBinding(item) !== binding ||
      ["queued", "running"].includes(answer.job?.status) || answer.job?.requires_reconciliation === true)
    throw new Error("The approved request or saved task changed. Inspect the exact saved preview before an explicit request.");
}
async function suggestionAction(action, modify = false, requestAfterApproval = false) {
  const permission = {approve: "can_approve", request: "can_request", adopt: "can_adopt", discard: "can_discard"}[action];
  const item = state.suggestion?.suggestion;
  if (!permission || !ready() || dirty() || state.suggestion?.enabled !== true || item?.revision !== state.view.run.revision || !item?.[permission]) return;
  let payload; try {payload = suggestionPayload(action);} catch (error) {state.suggestionError = error.message; renderSuggestion(); return;}
  const binding = exactSuggestionBinding(item), approvedRevision = payload.expected_revision + 1, approvedStage = state.view.run.stage;
  stopSuggestionPolling(); state.busy = true; state.suggestionChaining = action === "approve" && requestAfterApproval; buttons();
  try {
    state.suggestion = await suggestionRequest(action, payload); state.suggestionLost = false; state.suggestionError = "";
    if (action === "approve" && requestAfterApproval) {
      verifyApprovedSuggestion(state.suggestion, binding, approvedRevision);
      await load();
      if (state.stale || state.connectionLost || state.suggestionLost || state.awaitingFreshInspect || dirty() || activeJob() ||
          state.view?.run.revision !== approvedRevision || state.view.run.stage !== approvedStage) throw new Error("The saved project changed after approval. Inspect it before an explicit request.");
      verifyApprovedSuggestion(state.suggestion, binding, approvedRevision);
      const requestPayload = suggestionPayload("request");
      if (requestPayload.reviewer !== payload.reviewer || requestPayload.reason !== payload.reason) throw new Error("The request decision changed after approval. Inspect it before an explicit request.");
      state.busy = true; buttons(); payload = requestPayload; action = "request";
      state.suggestion = await suggestionRequest(action, payload);
    }
    if (action === "request") {
      const job = state.suggestion.job;
      if (!job || job.expected_revision !== payload.expected_revision || job.suggestion_hash !== payload.suggestion_hash || job.request_id !== payload.request_id && state.suggestion.duplicate !== true) throw new Error("The model task receipt does not match the submitted request ID and exact preview binding.");
      if (activeSuggestion()) {renderSuggestion(); scheduleSuggestionPoll();}
      else await load();
    } else {
      await load();
      if (modify && action === "adopt") {
        if (node()?.kind === "strategy") {$("strategy-edit-details").open = true; $("strategy-json").focus();}
        else if (node()?.kind === "annotation") $("annotation-label").focus();
        message("Candidate prepared for scientific review. Modify the typed plan or use Unknown for unresolved clusters, save corrections, then review the rebuilt evidence before approval.");
      }
    }
  } catch (error) {suggestionLost(error);}
  finally {state.busy = false; state.suggestionChaining = false; renderSuggestion(); buttons(); if (activeSuggestion() && !state.suggestionLost) scheduleSuggestionPoll();}
}
function buttons() {
  $("run-refresh").disabled = state.busy || state.suggestionChaining;
  const annotation = ready() && node()?.kind === "annotation";
  $("annotation-save").disabled = !annotation || !node().can_revise || !annotationDirty() || !!draftError();
  $("annotation-approve").disabled = !annotation || !node().can_decide || annotationDirty();
  $("annotation-approve-continue").hidden = !continuationEnabled();
  $("annotation-approve-continue").disabled = $("annotation-approve").disabled || !continuationEnabled();
  $("annotation-reject").disabled = !annotation || !node().can_decide;
  $("run-undo-button").disabled = !ready() || !node()?.can_undo;
  for (const id of ["annotation-label", "annotation-confidence", "annotation-rationale", "annotation-keep", "annotation-coarser", "annotation-unknown"]) $(id).disabled = !annotation || !node()?.can_revise;
  for (const input of state.citationInputs) input.disabled = !annotation || !node()?.can_revise;
  for (const id of ["annotation-reviewer", "annotation-reason", "run-undo-reviewer", "run-undo-reason"]) $(id).disabled = state.busy || activeJob() || activeSuggestion() || state.suggestionBusy;
  const strategy = ready() && node()?.kind === "strategy";
  $("strategy-save").disabled = !strategy || !node().can_revise || !strategyDirty() || !!strategyDraftError();
  $("strategy-approve").disabled = !strategy || !node().can_decide || strategyDirty() || !!typedStrategyError(strategyProposal()) || !!doubletReviewError() || !!madReviewError();
  $("strategy-approve-continue").hidden = !continuationEnabled();
  $("strategy-approve-continue").disabled = $("strategy-approve").disabled || !continuationEnabled();
  $("strategy-reject").disabled = !strategy || !node().can_decide;
  $("strategy-json").disabled = !strategy || !node().can_revise;
  if (state.madSelect) state.madSelect.disabled = !strategy || !node()?.can_revise || !!madReviewError();
  for (const control of state.strategyControls) control.disabled = !strategy || !node()?.can_revise || control.getAttribute("data-unavailable") === "true";
  for (const id of ["strategy-reviewer", "strategy-reason"]) $(id).disabled = state.busy || activeJob() || activeSuggestion() || state.suggestionBusy;
  $("run-qc").inert = activeJob() || activeSuggestion() || state.suggestionBusy;
  $("run-continue").disabled = !canContinue(false);
  $("run-continue-retry").disabled = !canContinue(true);
  suggestionButtons();
}
function verifyContinuation(answer, run, fullInspect = false) {
  const availability = answer?.availability, job = answer?.job;
  if (answer?.schema !== "scagentkit.run-continue.workbench.v1" || typeof answer.enabled !== "boolean" || !availability ||
      ![availability.can_continue, availability.can_retry, availability.requires_explicit_retry].every(value => typeof value === "boolean") ||
      typeof availability.reason !== "string" || availability.project_id !== run.project_id || availability.input_hash !== run.input_hash ||
      !Number.isInteger(availability.expected_revision) || availability.expected_revision < 0 ||
      (fullInspect && availability.expected_revision !== run.revision) || (availability.can_continue && availability.can_retry))
    throw new Error("The local task response does not match this project's saved state.");
  if (job != null && (typeof job.job_id !== "string" || !job.job_id || typeof job.request_id !== "string" || !job.request_id ||
      !["queued", "running", "succeeded", "failed", "interrupted", "timed_out"].includes(job.status) || job.project_id !== run.project_id || job.input_hash !== run.input_hash ||
      !Number.isInteger(job.expected_revision) || job.expected_revision < 0 || typeof job.retry !== "boolean" || typeof job.retry_permitted !== "boolean" ||
      typeof job.created_at !== "string" || typeof job.updated_at !== "string" ||
      (job.next_run_status != null && typeof job.next_run_status !== "string") || (job.next_run_stage != null && typeof job.next_run_stage !== "string") ||
      (job.next_run_revision != null && (!Number.isInteger(job.next_run_revision) || job.next_run_revision < 0)) ||
      (job.error != null && (typeof job.error.code !== "string" || typeof job.error.message !== "string"))))
    throw new Error("The saved local task identity or status is unverified.");
  if ((availability.can_continue || availability.can_retry) && !answer.enabled ||
      availability.can_continue && (availability.requires_explicit_retry || ["queued", "running"].includes(job?.status)) ||
      availability.can_retry && (!availability.requires_explicit_retry || ["queued", "running"].includes(job?.status) || (fullInspect && !supportedSavedLocalRetry(run, job))))
    throw new Error("The local task permissions are inconsistent; refresh the saved state.");
  return answer;
}
function supportedSavedLocalRetry(run, job) {
  if (!["prefilter", "qc_evidence", "qc_apply", "analysis", "strategy_evidence", "strategy_apply", "strategy_selection", "strategy_preprocess", "strategy_basis", "strategy_batch", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence", "annotation_apply", "finalize"].includes(run.stage) || ["queued", "running"].includes(job?.status)) return false;
  if (["failed", "interrupted"].includes(job?.status)) return job.retry_permitted === true && ["ready", "failed", "running"].includes(run.status);
  return (job == null || job.status === "succeeded") && ["failed", "running"].includes(run.status);
}
function canContinue(retry) {
  const run = state.view?.run, availability = state.continuation?.availability;
  if (!ready() || !continuationEnabled() || dirty() || strategyProposal() && typedStrategyError(strategyProposal()) || doubletReviewError() || madReviewError() || !availability || availability.expected_revision !== run.revision ||
      availability.project_id !== run.project_id || availability.input_hash !== run.input_hash ||
      ["awaiting_review", "awaiting_configuration", "rejected", "complete", "budget_exceeded"].includes(run.status)) return false;
  if (retry) return availability.can_retry && availability.requires_explicit_retry && supportedSavedLocalRetry(run, state.continuation.job);
  return run.status === "ready" && availability.can_continue && !availability.requires_explicit_retry;
}
function storedRequestKey(run) {return "scagentkit.run-continue.v1:" + encodeURIComponent(run.project_id) + ":" + run.input_hash;}
function savedRequest(run) {
  try {
    const record = JSON.parse(sessionStorage.getItem(storedRequestKey(run)) || "null");
    if (record && Object.keys(record).sort().join(",") === "expected_revision,input_hash,project_id,request_id,retry" &&
        record.project_id === run.project_id && record.input_hash === run.input_hash && Number.isInteger(record.expected_revision) && record.expected_revision >= 0 &&
        typeof record.retry === "boolean" && typeof record.request_id === "string" && /^[a-zA-Z0-9._-]{1,128}$/.test(record.request_id)) return record;
  } catch (_) { /* Storage can be unavailable; the saved server job remains authoritative. */ }
  return null;
}
function rememberRequest(record) {
  state.pendingRequest = record;
  try {sessionStorage.setItem(storedRequestKey(record), JSON.stringify(record));} catch (_) { /* Retain the same request in this page's memory. */ }
}
function requestFor(retry) {
  const run = state.view.run, previous = state.pendingRequest || savedRequest(run);
  const job = state.continuation?.job;
  const completedPrevious = previous && ["succeeded", "failed", "interrupted"].includes(job?.status) &&
    ["project_id", "input_hash", "expected_revision", "retry"].every(key => job[key] === previous[key]);
  if (previous && previous.project_id === run.project_id && previous.input_hash === run.input_hash && previous.expected_revision === run.revision && previous.retry === retry &&
      job?.request_id !== previous.request_id && !completedPrevious) return previous;
  const bytes = new Uint8Array(16); crypto.getRandomValues(bytes);
  const request_id = typeof crypto.randomUUID === "function" ? crypto.randomUUID() : Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("");
  const record = {project_id: run.project_id, input_hash: run.input_hash, expected_revision: run.revision, request_id, retry};
  rememberRequest(record); return record;
}
function stopPolling() {if (state.pollTimer != null) clearTimeout(state.pollTimer); state.pollTimer = null; state.pollGeneration += 1;}
function schedulePoll() {
  if (!activeJob() || state.connectionLost || state.pollTimer != null) return;
  const generation = state.pollGeneration;
  state.pollTimer = setTimeout(() => {state.pollTimer = null; pollJob(generation);}, 1000);
}
async function continuationRequest(payload) {
  // A read-only status inspection may traverse the same bounded R bridge as
  // the full saved-project inspect. Allow its 120-second IPC bound plus margin.
  const controller = new AbortController(), timer = setTimeout(() => controller.abort(), payload ? 15000 : 125000);
  try {
    const response = await fetch(scopedRunURL(payload ? "/api/run-review/continue" : "/api/run-review/continuation"), payload ? {
      method: "POST", headers: projectHeaders({"Content-Type": "application/json", "X-ScAgentKit-Run-Token": state.view.csrf_token}), body: JSON.stringify(payload), signal: controller.signal
    } : {cache: "no-store", headers: projectHeaders(), signal: controller.signal});
    const answer = await response.json(); if (!response.ok) throw new Error(answer?.error || "The local task could not be verified.");
    return verifyContinuation(answer, state.view.run);
  } finally {clearTimeout(timer);}
}
function continuationLost(error) {
  stopPolling(); state.stale = true; state.connectionLost = true;
  message(error.message + " The saved task may still be running. Refresh to verify its state before another request. This page will not relaunch it automatically.", true);
  renderContinuation(); buttons();
}
async function pollJob(generation) {
  if (generation !== state.pollGeneration || !activeJob() || state.pollInFlight || state.busy) {schedulePoll(); return;}
  state.pollInFlight = true;
  try {
    const answer = await continuationRequest(); if (generation !== state.pollGeneration) return;
    state.continuation = answer; renderContinuation(); buttons();
    if (activeJob()) schedulePoll();
    else {
      stopPolling(); state.awaitingFreshInspect = true; buttons();
      if (dirty()) {state.stale = true; renderContinuation(); message("The local task stopped. Your unsaved review corrections are preserved. Refresh the saved state before a new decision or computation.", true);}
      else await load();
    }
  } catch (error) {if (generation === state.pollGeneration) continuationLost(error);}
  finally {state.pollInFlight = false;}
}
async function continueRun(retry = false) {
  if (!canContinue(retry)) return;
  let payload;
  try {payload = requestFor(retry);} catch (_) {message("A secure request ID could not be created. Refresh before starting local work.", true); return;}
  stopPolling(); state.busy = true; buttons();
  try {
    const answer = await continuationRequest(payload);
    if (typeof answer.duplicate !== "boolean" || !answer.job ||
        !["project_id", "input_hash", "expected_revision", "retry"].every(key => answer.job[key] === payload[key]) ||
        (answer.job.request_id !== payload.request_id && !answer.duplicate)) throw new Error("The saved task does not match the submitted request binding.");
    state.continuation = answer; state.connectionLost = false;
    renderContinuation();
    if (activeJob()) {message("Saved local task is " + answer.job.status + ". You can leave this page and inspect the saved task after reconnecting."); schedulePoll();}
    else {state.awaitingFreshInspect = true; await load();}
  } catch (error) {continuationLost(error);}
  finally {state.busy = false; buttons(); if (activeJob() && !state.connectionLost) schedulePoll();}
}
function renderContinuation() {
  const continuation = state.continuation, job = continuation?.job, section = $("run-continuation");
  section.hidden = !continuation || (!continuation.enabled && !job);
  if (section.hidden) return;
  section.dataset.jobStatus = job?.status || "none"; section.dataset.connection = state.connectionLost ? "lost" : "verified";
  $("run-job-status").textContent = job ? (state.connectionLost ? "Last verified task: " : "Local task: ") + job.status + (state.connectionLost ? " · connection unverified" : "") : state.connectionLost ? "Connection unverified" : "No local task";
  $("run-job-status").className = "pill " + (activeJob() ? "blue" : "muted");
  $("run-job-details").hidden = !job; $("run-job-id").textContent = job?.job_id || "";
  $("run-continue").hidden = !continuation.enabled;
  $("run-continue-retry").hidden = !continuation.enabled || !continuation.availability?.can_retry;
  let text;
  if (state.connectionLost) text = "Connection lost or response unverified. The saved task may still be running; its ID is retained above. Refresh saved state to check it. This page will not launch another task automatically.";
  else if (!continuation.enabled) text = "Browser continuation is disabled for this server. Inspect the saved task and continue the analysis in R.";
  else if (activeJob()) text = "This saved task is " + job.status + " on the data machine. Closing the page does not stop it. Decisions and another continuation are disabled while it is active.";
  else if (state.awaitingFreshInspect || state.stale) text = dirty() ? "The task stopped; unsaved review corrections are preserved. Refresh the saved state when you are ready to discard them." : "Refresh a verified saved state before another continuation or decision.";
  else if (dirty()) text = "Unsaved review corrections are preserved. Save and review them before continuing local computation.";
  else if (canContinue(true) && (!job || job.status === "succeeded")) text = "The current saved run needs an explicit retry of local " + state.view.run.stage + " computation. " + (job ? "The previous task's success does not mean this run is complete. " : "No browser task is recorded for this saved local failure. ") + "Use Retry saved local failure. This makes no model request.";
  else if (job?.status === "succeeded") text = state.view.run.status === "complete" ? "The current saved run has completed output. Inspect the object and judge the biological result separately." : state.view.run.status === "awaiting_configuration" ? "The local task stopped; the current run needs configuration. Supply provider settings or a supported manual proposal in R; no model request is started by this page." : state.view.run.status === "awaiting_review" ? "The current run awaits its next review. Inspect and approve the saved plan; this task's success does not mean the analysis is complete." : canContinue(false) ? "The previous local task stopped successfully. The current approved plan can continue locally and will stop at the next review or configuration step." : "The local task stopped at " + (job.next_run_status || "a saved stopping point") + (job.next_run_stage ? " / " + job.next_run_stage : "") + ". Current saved run: " + state.view.run.status + " / " + state.view.run.stage + ". Task success does not establish analysis completion.";
  else if (["failed", "interrupted"].includes(job?.status)) text = "The saved local task " + job.status + ". " + (job.error?.message || "Inspect the saved run state.") + (canContinue(true) ? " Retry saved local failure is an explicit retry of this local computation." : " A retry is unavailable until the saved state is verified and supports it.");
  else if (canContinue(false)) text = "The current approved plan can continue locally. The worker stops at the next review or configuration boundary.";
  else text = "Local continuation is unavailable: " + (continuation.availability?.reason || "inspect the next saved review or configuration step") + ". Review the saved plan or supply the required configuration in R.";
  $("run-continuation-note").textContent = text; $("run-continuation-note").className = "continuation-note" + (state.connectionLost ? " connection-lost" : "");
}
function verify(answer) {
  const run = answer?.run;
  if (answer?.schema !== "scagentkit.run-review.workbench.v1" || run?.schema !== "scagentkit.run.v1" || typeof run.project_id !== "string" || !run.project_id || !hash(run.input_hash) || !Number.isInteger(run.revision) || run.revision < 0 || typeof answer.csrf_token !== "string" || !answer.csrf_token)
    throw new Error("The response is not a verified saved run.");
  const selected = scopeQuery();
  if ((selected.child_id || selected.project_id || state.scopeProject) && run.project_id !== (selected.child_id || selected.project_id || state.scopeProject)) throw new Error("The response belongs to a different selected project.");
  if (state.scopes && run.project_id === state.scopes.parent.project_id && run.input_hash !== state.scopes.parent.input_hash) throw new Error("The parent input does not match this service registry.");
  if (state.view && (run.project_id !== state.view.run.project_id || run.input_hash !== state.view.run.input_hash)) throw new Error("The configured project or input changed; restart the server and inspect the correct run.");
  const current = run.review_node;
  if (current) {
    if (!["qc", "strategy", "annotation"].includes(current.kind) || current.project_id !== run.project_id || current.input_hash !== run.input_hash || current.expected_revision !== run.revision || !hash(current.review_hash) || !hash(current.proposal_hash)) throw new Error("The review node does not match this project's saved snapshot.");
    const record = current.kind === "qc" ? run.qc_preview : current.kind === "strategy" ? run.strategy_review : run.annotation_review;
    const schema = current.kind === "qc" ? "scagentkit.qc.review.v1" : current.kind === "strategy" ? "scagentkit.strategy.review.v1" : "scagentkit.annotation.review.v1";
    if (record?.hash !== current.review_hash || record?.input_hash !== run.input_hash || record.schema !== schema) throw new Error("The displayed evidence does not match the review fingerprint.");
    if (current.kind === "strategy" && (!hash(record.evidence_hash) || !record.details || record.details.canonical_proposal?.schema !== "scagentkit.strategy.v1" ||
        (current.evidence_hash != null && record.evidence_hash !== current.evidence_hash))) throw new Error("The saved strategy evidence or typed proposal is unverified.");
  }
  if (run.annotation_review) {
    const details = run.annotation_review.details, rows = array(details?.annotations), seen = new Set(), scope = new Map();
    if (!rows.length) throw new Error("The annotation review has no exact cluster scopes.");
    for (const item of rows) {
      const row = item.proposal, cells = array(item.cell_ids);
      if (typeof item.clusterId !== "string" || !item.clusterId || seen.has(item.clusterId) || row?.clusterId !== item.clusterId || !Number.isInteger(item.cell_count) || cells.length !== item.cell_count || typeof row.label !== "string" || !row.label.trim() || typeof row.rationale !== "string" || !row.rationale.trim() || !["low", "medium", "high"].includes(row.confidence) || array(row.markers).some(gene => typeof gene !== "string" || !gene)) throw new Error("An annotation cluster's literal ID, proposal or cell scope is inconsistent.");
      if ((!unresolvedLabel(row.label) && !array(row.markers).length) || array(row.markers).some(gene => !admissibleGenes(item).includes(gene))) throw new Error("Saved annotation citations do not match the supplied cluster evidence.");
      seen.add(item.clusterId);
      for (const cell of cells) {if (typeof cell !== "string" || !cell || scope.has(cell)) throw new Error("Annotation cell IDs are missing or duplicated across scopes."); scope.set(cell, item.clusterId);}
    }
    if (details.cell_count !== scope.size || details.cluster_count !== rows.length || array(details.input_cells).length !== scope.size || array(details.input_cells).some(row => scope.get(row.cell_id) !== row.cluster) || new Set(array(details.input_cells).map(row => row.cell_id)).size !== scope.size) throw new Error("The annotation preview does not cover the exact saved input membership.");
  }
  if (answer.continuation != null) verifyContinuation(answer.continuation, run, true);
  return answer;
}
async function request(payload) {
  try {
    const response = await fetch(scopedRunURL(payload ? "/api/run-review/decision" : "/api/run-review/inspect"), payload ? {
      method: "POST", headers: projectHeaders({"Content-Type": "application/json", "X-ScAgentKit-Run-Token": state.view.csrf_token}), body: JSON.stringify(payload)
    } : {cache: "no-store", headers: projectHeaders()});
    const answer = await response.json(); if (!response.ok) throw new Error(answer?.error || "The local run review failed."); return verify(answer);
  } catch (error) {state.stale = true; throw error;}
}
function geneNode(gene) {return typeof ScGeneCards === "undefined" ? element("span", gene) : ScGeneCards.render(gene, state.view?.run.context?.species);}
function geneList(genes) {return typeof ScGeneCards === "undefined" ? element("span", genes.join(", ") || "none") : ScGeneCards.list(genes, state.view?.run.context?.species);}
function geneParagraph(prefix, genes, attributes = {}) {const line = element("p", prefix, attributes); line.append(geneList(genes)); return line;}
function table(headings, rows, renderCell = null) {
  const wrapper = element("div", null, {class: "table-wrap"}), t = element("table"), head = element("thead"), tr = element("tr"), body = element("tbody");
  headings.forEach(label => tr.append(element("th", label))); head.append(tr); t.append(head);
  rows.forEach(values => {const row = element("tr"); values.forEach((value, index) => {const cell = element("td"), rendered = renderCell?.(value, index); if (rendered) cell.append(rendered); else cell.textContent = value; row.append(cell);}); body.append(row);}); t.append(body); wrapper.append(t); return wrapper;
}
function raw(value) {return element("pre", json(value), {class: "qc-small-json"});}
function empty(target, text) {target.append(element("p", text, {class: "review-empty"}));}
function renderMarkers(item) {
  const target = $("annotation-markers"); target.replaceChildren();
  const rows = array(state.markerMode === "all" ? item?.supplied_marker_stats : item?.cited_marker_stats);
  if (!rows.length) {empty(target, "No " + (state.markerMode === "all" ? "supplied" : "cited") + " marker statistics are available for this exact cluster. This does not establish non-expression."); return;}
  target.append(table(["Gene", "avgLog2FC", "pct1 (fraction)", "pct2 (fraction)", "Adjusted p", "Saved source"], rows.map(row => [row.gene, fmt(row.avgLog2FC), fmt(row.pct1), fmt(row.pct2), fmt(row.pAdj), row.source || "unspecified"]), (value, index) => index === 0 ? geneNode(value) : null));
  if (typeof ScGeneCards !== "undefined") target.append(element("p", ScGeneCards.note(state.view?.run.context?.species), {class: "microcopy"}));
}
function evidenceNumber(value) {return typeof value === "number" && Number.isFinite(value) ? fmt(value) : "Unavailable";}
function evidenceRecord(value, keys) {
  const result = {};
  if (value && typeof value === "object" && !Array.isArray(value)) for (const key of keys) if (Object.hasOwn(value, key)) result[key] = value[key];
  return Object.keys(result).length ? result : null;
}
function evidenceSource(value) {
  const result = evidenceRecord(value, ["kind", "name", "database", "version", "url", "status", "mode", "species", "tissue_filter", "source_md5", "source_sha256", "source_url", "requested_url", "source_url_verified", "source_version", "retrieved_at", "source_file_status", "n_input_rows", "n_scoped_rows", "n_unique_pairs", "duplicate_pair_count", "file_sha256", "sha256", "fingerprint", "marker_column", "license", "license_status", "citation", "provider", "model", "response_sha256", "source_object_sha256", "scope_status", "reference_dependency"]);
  if (!result) return null;
  for (const key of Object.keys(result)) if (result[key] != null && !["string", "number", "boolean"].includes(typeof result[key]) && !(Array.isArray(result[key]) && result[key].every(value => value == null || ["string", "number", "boolean"].includes(typeof value)))) delete result[key];
  return Object.keys(result).length ? result : null;
}
function jointDetail(target, title, id, value) {
  const section = element("section", null, {id, "data-testid": id}); section.append(element("h3", title));
  if (value == null) empty(section, "Unavailable in this saved evidence."); else section.append(raw(value));
  target.append(section); return section;
}
function renderJointEvidence(item) {
  const target = $("annotation-joint-evidence"), joint = item.joint_evidence;
  target.replaceChildren(); target.hidden = true;
  if (joint?.schema !== "scagentkit.joint-annotation-evidence.v1" || joint.clusterId !== item.clusterId) return false;
  target.hidden = false;
  const database = joint.database || {}, current = joint.current || {}, comparison = joint.comparison || {}, dependency = joint.dependency || {};
  const names = {exact_label: "Same saved label", mapped_name: "Explicit name map", granularity: "Declared granularity relation", lineage_disagreement: "Declared lineage difference", unresolved_label_difference: "Unresolved label difference", missing_information: "Missing information"};
  const status = element("span", names[comparison.status] || "Comparison unavailable", {id: "annotation-joint-comparison", "data-testid": "annotation-joint-comparison", "data-status": comparison.status || "unavailable", class: "pill muted"});
  const statusLine = element("div", null, {class: "joint-evidence-status"});
  statusLine.append(status, element("p", comparison.source === "historical_model_response" ? "Comparison uses the imported historical model response." : comparison.source === "current_proposal" ? "Comparison uses the current saved proposal." : "Comparison source is unavailable.")); target.append(statusLine);
  target.append(element("p", typeof comparison.reason === "string" && comparison.reason ? comparison.reason : "No comparison reason was supplied.", {id: "annotation-joint-comparison-reason", "data-testid": "annotation-joint-comparison-reason", class: "joint-evidence-reason"}));
  const grid = element("div", null, {class: "joint-evidence-grid"});
  const dbCard = element("section", null, {id: "annotation-joint-database", "data-testid": "annotation-joint-database", class: "joint-evidence-card"});
  dbCard.append(element("h3", "Local database candidates"), element("p", "Saved reference status: " + (typeof database.status === "string" ? database.status : "unavailable"), {class: "annotation-reference-status"}));
  const candidates = array(database.candidates).filter(row => row && typeof row === "object" && !Array.isArray(row));
  const candidateTarget = element("div", null, {id: "annotation-joint-candidates", "data-testid": "annotation-joint-candidates"});
  if (candidates.length) candidateTarget.append(table(["Candidate", "Coverage", "Unique hits / reference genes"], candidates.map(row => [typeof row.label === "string" ? row.label + (row.tiedBest === true ? " · tied best" : "") : "Unavailable label", evidenceNumber(row.score), evidenceNumber(row.overlap) + " / " + evidenceNumber(row.referenceSize)])));
  else empty(candidateTarget, "No positive candidate is available. This does not establish a biological exclusion.");
  dbCard.append(candidateTarget, element("p", "Coverage is descriptive reference-marker overlap, not a probability.", {class: "annotation-confidence-note"}));
  const currentCard = element("section", null, {id: "annotation-joint-current", "data-testid": "annotation-joint-current", class: "joint-evidence-card"});
  const source = current.source || state.view?.run.annotation_review?.details?.source;
  currentCard.append(element("h3", "Current annotation proposal"), element("p", "Saved source: " + (typeof source?.kind === "string" ? source.kind : "unavailable"), {class: "annotation-reference-status"}), element("p", item.proposal.label, {class: "annotation-saved-label"}), element("p", item.proposal.confidence + " confidence · qualitative, uncalibrated", {class: "annotation-confidence-note"}), element("p", item.proposal.rationale, {class: "annotation-saved-rationale"}), geneParagraph("Cited genes: ", array(item.proposal.markers), {class: "annotation-confidence-note"}));
  grid.append(dbCard, currentCard); target.append(grid);
  const plannedMode = dependency.planned_mode ?? dependency.mode;
  const mode = ["independent", "guided"].includes(plannedMode) ? plannedMode : "unavailable";
  const modeText = mode === "guided" ? "Saved prompt mode: guided. This mode includes database candidates, so a model response is dependent on that evidence." : mode === "independent" ? "Saved prompt mode: independent. This mode excludes database candidates from the prompt." : "Prompt dependency was not declared in this saved evidence.";
  const actualMode = ["independent", "guided", "unknown", "not_dispatched"].includes(dependency.actual_mode) ? dependency.actual_mode : "unknown";
  const actualText = actualMode === "not_dispatched" ? "No model request is recorded for the current proposal." : actualMode === "guided" ? "Recorded current response: its prompt included database candidates, so it depends on that evidence." : actualMode === "independent" ? "Recorded current response: database candidates were excluded from its prompt." : "The current response's actual prompt dependency was not recorded.";
  target.append(element("p", modeText + " " + actualText + (typeof dependency.declaration === "string" && dependency.declaration ? " " + dependency.declaration : "") + " Prompt separation does not establish independent biological confirmation.", {id: "annotation-joint-dependency", "data-testid": "annotation-joint-dependency", "data-mode": mode, "data-actual-mode": actualMode, class: "joint-evidence-dependency"}));
  const details = element("details", null, {id: "annotation-joint-details", "data-testid": "annotation-joint-details", class: "joint-evidence-details"}); details.append(element("summary", "Evidence details: formula, sources, aliases, comparison and historical response"));
  jointDetail(details, "Saved scoring formula", "annotation-joint-scoring", evidenceRecord(database.scoring, ["formula", "quantity", "denominator", "calibrated_probability"]));
  const sources = jointDetail(details, "Saved database and current proposal sources", "annotation-joint-source", {database: evidenceSource(database.provenance), current: evidenceSource(source)}); sources.append(element("p", "A missing dataset license is unknown; an article's license does not establish a database redistribution license."));
  jointDetail(details, "Declared database scope", "annotation-joint-scope", evidenceRecord(database.provenance?.scope, ["method", "tissue_all_rows", "unavailable_columns", "excluded_unavailable_rows"]));
  jointDetail(details, "Canonical symbols and explicit aliases", "annotation-joint-symbols", evidenceRecord(database.marker_symbols, ["original", "canonical", "unique", "duplicate_count", "alias_resolutions"]));
  jointDetail(details, "Saved candidate details, including zero overlap", "annotation-joint-all-candidates", array(database.all_candidates).map(row => evidenceRecord(row, ["label", "score", "overlap", "referenceSize", "markers", "formula", "referenceGenes", "availableGenes", "unmeasuredGenes", "notInTopMarkers", "tiedBest", "source"])));
  jointDetail(details, "Explicit name and relationship comparisons", "annotation-joint-comparison-details", evidenceRecord(comparison, ["source", "label", "label_normalized", "label_map", "reference_labels", "related_candidates", "ambiguous", "reason", "relationships"]));
  const currentCitations = jointDetail(details, "Current proposal citations", "annotation-joint-citations", array(current.citations).map(row => ({gene: row?.gene, status: row?.status, statistics: evidenceRecord(row?.statistics, ["gene", "avgLog2FC", "pct1", "pct2", "pAdj", "source"])})));
  currentCitations.append(geneParagraph("Supplied citation genes: ", array(current.citations).map(row => row?.gene).filter(gene => typeof gene === "string")));
  const historical = joint.historical || {}, history = jointDetail(details, "Historical model response · read-only import", "annotation-joint-history", null);
  history.replaceChildren(element("h3", "Historical model response · read-only import"), element("p", "Saved historical status: " + (typeof historical.status === "string" ? historical.status : "unavailable") + ". This is a saved import; no new model request is made."));
  if (historical.status === "supplied" && historical.row?.clusterId === item.clusterId) {
    const row = historical.row; history.append(element("p", typeof row.label === "string" ? row.label : "Historical label unavailable", {class: "annotation-saved-label"}), element("p", typeof row.confidence === "string" ? row.confidence + " confidence · qualitative, uncalibrated" : "Historical confidence unavailable", {class: "annotation-confidence-note"}), element("p", typeof row.rationale === "string" ? row.rationale : "Historical rationale unavailable", {class: "annotation-saved-rationale"}), geneParagraph("Historical citation genes: ", array(row.citations).map(citation => citation?.gene).filter(gene => typeof gene === "string")), raw({citations: array(row.citations).map(citation => ({gene: citation?.gene, status: citation?.status, statistics: evidenceRecord(citation?.statistics, ["gene", "avgLog2FC", "pct1", "pct2", "pAdj", "source"])})), provenance: evidenceSource(historical.provenance), eligible_for_comparison: typeof historical.eligible_for_comparison === "boolean" ? historical.eligible_for_comparison : null}));
  } else empty(history, "No historical response for this exact cluster was supplied.");
  const counter = joint.counterevidence || {}, counterSection = jointDetail(details, "Explicit counterevidence", "annotation-joint-counterevidence", counter.status === "supplied" ? counter.records : null);
  counterSection.append(element("p", counter.status === "supplied" ? "These are supplied records; the workbench adds no biological exclusion rule." : "No explicit counterevidence was supplied. Zero overlap, unmeasured genes and absence from top markers are not negative evidence."));
  const limits = element("ul", null, {id: "annotation-joint-limitations", "data-testid": "annotation-joint-limitations", class: "joint-evidence-limits"});
  for (const limit of array(joint.limitations)) if (typeof limit === "string") limits.append(element("li", limit)); details.append(limits); target.append(details);
  return true;
}
function renderCluster() {
  const rows = annotationRows(), item = rows.find(row => String(row.clusterId) === state.selectedCluster); if (!item) return;
  for (const button of $("annotation-clusters").children) button.classList.toggle("selected", button.getAttribute("data-cluster-id") === item.clusterId);
  $("annotation-title").textContent = `Cluster ${item.clusterId} · ${item.cell_count} cells`;
  $("annotation-source").textContent = "Saved " + (state.view.run.annotation_review.details.source?.kind || "unclassified") + " proposal";
  const suggestion = $("annotation-suggestion"); suggestion.replaceChildren(element("p", item.proposal.label, {class: "annotation-saved-label"}), element("p", `${item.proposal.confidence} confidence · qualitative, uncalibrated`, {class: "annotation-confidence-note"}), element("p", item.proposal.rationale, {class: "annotation-saved-rationale"}), geneParagraph("Cited genes: ", array(item.proposal.markers), {class: "annotation-confidence-note"}));
  const joint = renderJointEvidence(item); suggestion.hidden = joint; $("annotation-reference-section").hidden = joint;
  $("annotation-cell-ids").textContent = array(item.cell_ids).join("\n"); renderMarkers(item);
  const reference = $("annotation-reference"); reference.replaceChildren(element("p", "Saved reference status: " + (item.local_reference?.status || "unavailable"), {class: "annotation-reference-status"}), raw(item.local_reference || {status: "unavailable", interpretation: "No local-reference evidence was supplied."}));
  const row = state.drafts.get(item.clusterId); $("annotation-label").value = row.label; $("annotation-confidence").value = row.confidence; $("annotation-rationale").value = row.rationale;
  const citations = $("annotation-citations"), genes = admissibleGenes(item); citations.replaceChildren(); state.citationInputs = [];
  for (const gene of genes) {
    const label = element("label", null, {class: "annotation-citation"}), input = element("input", null, {type: "checkbox", "data-marker-gene": gene});
    input.checked = array(row.markers).includes(gene); state.citationInputs.push(input); label.append(input, geneNode(gene)); citations.append(label);
    input.addEventListener("change", () => {row.markers = genes.filter((_, index) => state.citationInputs[index].checked); updateDraftStatus(); buttons();});
  }
  if (!genes.length) empty(citations, "No supplied marker citations are available for this cluster; use Unknown or supply additional reviewed evidence in R.");
  updateDraftStatus(); buttons();
}
function updateDraftStatus() {
  const error = draftError(); $("annotation-draft-status").textContent = error || (dirty() ? "Unsaved corrections. Rebuild and inspect the saved snapshot before approval." : "This draft matches the saved review snapshot.");
  renderContinuation();
}
function renderAnnotation() {
  const record = state.view.run.annotation_review, details = record.details, rows = annotationRows();
  state.drafts = new Map(rows.map(item => [String(item.clusterId), normalizeRow(item.proposal)]));
  if (!rows.some(item => item.clusterId === state.selectedCluster)) state.selectedCluster = rows[0].clusterId;
  $("annotation-counts").textContent = `${details.cell_count} exact cells · ${details.cluster_count} clusters · output ${details.output_columns?.label || record.target_column}`;
  const clusterList = $("annotation-clusters"); clusterList.replaceChildren();
  for (const item of rows) {
    const button = element("button", `Cluster ${item.clusterId}`, {type: "button", "data-cluster-id": item.clusterId, "data-testid": "annotation-cluster-" + item.clusterId});
    button.append(element("small", `${item.cell_count} cells`)); button.addEventListener("click", () => {state.selectedCluster = item.clusterId; renderCluster();}); clusterList.append(button);
  }
  $("annotation-provenance").replaceChildren(raw(details.source));
  $("annotation-limitations").replaceChildren(...array(details.limitations).map(value => element("li", value)));
  renderCluster();
}
function strategySection(title, value, notice) {
  const section = element("section", null, {class: "strategy-evidence-card"}); section.append(element("h3", title));
  if (value == null || Array.isArray(value) && !value.length) empty(section, notice || "Not supplied in this saved snapshot.");
  else section.append(strategyRecord(value));
  return section;
}
function strategyTextSection(title, value, notice = "No supported text entries were supplied in this saved record.", preserveStructured = false) {
  if (preserveStructured && value != null && typeof value !== "string" && (!Array.isArray(value) || value.some(entry => typeof entry !== "string"))) return strategySection(title, value, notice);
  const section = element("section", null, {class: "strategy-evidence-card"}); section.append(element("h3", title));
  const entries = (typeof value === "string" ? [value] : Array.isArray(value) ? value : []).filter(text => typeof text === "string" && text.trim());
  if (entries.length) {const list = element("ul"); list.append(...entries.map(text => element("li", text))); section.append(list);}
  else empty(section, notice);
  return section;
}
function strategyRecord(value, title = "Complete typed record") {
  const details = element("details"); details.append(element("summary", title), raw(value)); return details;
}
function strategyControl(tag, id, value, attributes = {}) {
  const control = cycleNode(tag, null, id, attributes); if (value != null) control.value = value; state.strategyControls.push(control); return control;
}
function numericDraft(value) {
  const text = String(value ?? "").trim();
  if (!text) return null;
  const number = Number(text); return Number.isFinite(number) ? number : text;
}
function setStrategyDraft(draft, rebuildControls = false) {
  state.strategyDraftText = json(draft); $("strategy-json").value = state.strategyDraftText;
  if (rebuildControls) renderStrategyOperations(state.view.run.strategy_review.details, draft);
  updateStrategyDraftStatus(); buttons();
}
function qcDraftRules(qc) {
  if (qc?.schema === "scagentkit.qc.rules.v1") return array(qc.rules);
  if (qc?.schema === "scagentkit.qc.v1") return array(qc.filters);
  if (qc?.schema === "scagentkit.qc.mad.v1") return [{op: "mad_preset", preset_id: qc.preset_id, panel_hash: qc.panel_hash}];
  return [];
}
function rulesQC(qc, rules, removeIf = qc?.remove_if || "any") {
  return {schema: "scagentkit.qc.rules.v1", rationale: qc?.rationale || "", risks: array(qc?.risks), remove_if: removeIf, rules};
}
function qcGroupOptions(details, rules) {
  const options = new Map([["null", "All supplied QC cells"]]);
  const add = selector => {
    if (!selector || typeof selector !== "object" || Array.isArray(selector) || !Object.keys(selector).length || Object.keys(selector).some(role => !["sample", "capture"].includes(role) || typeof selector[role] !== "string" || !selector[role])) return;
    const value = Object.fromEntries(["sample", "capture"].filter(role => Object.hasOwn(selector, role)).map(role => [role, selector[role]]));
    options.set(JSON.stringify(value), Object.entries(value).map(([role, label]) => role + ": " + label).join(" · "));
  };
  for (const row of [...array(details.qc_impact?.retention?.groups), ...array(details.qc_impact?.distributions?.groups), ...array(details.quality?.groups)]) {
    add(row?.selector); for (const role of ["sample", "capture"]) if (row?.selector?.[role]) add({[role]: row.selector[role]});
  }
  for (const rule of rules) add(rule.group); // Preserve an existing literal selector; R checks the actual declared data.
  return options;
}
function chooseQCDraft() {
  if (!ready() || node()?.kind !== "strategy" || !node()?.can_revise || !state.qcControls) return;
  try {
    const draft = strategyDraft(), controls = state.qcControls;
    if (controls.logic.value === "all" && !qcRulesEnabled(state.view.run.strategy_review.details)) return;
    const rules = controls.rows.map(row => row.op === "range" ? {op: "range", metric: row.metric.value, min: numericDraft(row.min.value), max: numericDraft(row.max.value), group: JSON.parse(row.group.value)} :
      row.op === "mad_preset" ? {op: "mad_preset", preset_id: row.preset.value, panel_hash: controls.panelHash} : row.rule);
    const previousSchema = draft.qc?.schema;
    if (previousSchema === "scagentkit.qc.v1" && controls.logic.value === "any" && rules.every(rule => rule.op === "range")) draft.qc = {...draft.qc, filters: rules};
    else if (previousSchema === "scagentkit.qc.mad.v1" && controls.logic.value === "any" && rules.length === 1 && rules[0].op === "mad_preset") draft.qc = {...draft.qc, preset_id: rules[0].preset_id, panel_hash: rules[0].panel_hash};
    else draft.qc = rulesQC(draft.qc, rules, controls.logic.value);
    setStrategyDraft(draft, previousSchema !== draft.qc.schema);
  } catch (_) {message("Correct the complete JSON draft before changing QC rules.", true);}
}
function changeQCRules(action, index) {
  if (!ready() || node()?.kind !== "strategy" || !node()?.can_revise) return;
  if (!qcRulesEnabled(state.view.run.strategy_review.details)) return;
  try {
    const draft = strategyDraft(), rules = qcDraftRules(draft.qc).slice(), panel = state.view.run.strategy_review.details.mad_panel;
    if (action === "remove") rules.splice(index, 1);
    else if (rules.length < 32 && action === "range") rules.push({op: "range", metric: "", min: null, max: null, group: null});
    else if (rules.length < 32 && action === "mad" && hash(panel?.panel_hash) && !rules.some(rule => rule.op === "mad_preset")) rules.push({op: "mad_preset", preset_id: "", panel_hash: panel.panel_hash});
    else return;
    draft.qc = rulesQC(draft.qc, rules); setStrategyDraft(draft, true);
  } catch (_) {message("Correct the complete JSON draft before adding or removing a QC rule.", true);}
}
function renderQCControls(details, proposal) {
  const qc = proposal.qc, supported = ["scagentkit.qc.v1", "scagentkit.qc.mad.v1", "scagentkit.qc.rules.v1"].includes(qc?.schema);
  if (!supported) return strategySection("QC and cell retention", qc, "Processed QC is reused; no new cell filtering is implied.");
  const card = cycleNode("section", null, "qc-parameter-card", {class: "strategy-evidence-card qc-parameter-card"});
  card.append(element("h3", "QC rules")); state.strategyFeedback = cycleNode("p", null, "strategy-controls-status", {class: "microcopy strategy-controls-status", role: "status", "aria-live": "polite"}); card.append(state.strategyFeedback);
  card.append(element("p", "Fixed inclusive ranges and at most one saved sample-aware MAD preset. Any / all combines rule failures, not individual thresholds. Editing creates a complete typed draft; no impact is recalculated here.", {class: "microcopy"}));
  const rules = qcDraftRules(qc), logic = strategyControl("select", "qc-rule-combine", null, {"aria-label": "Combine explicit QC rule failures"});
  const allOption = element("option", "Remove only if all rules fail · AND", {value: "all"}); allOption.disabled = !qcRulesEnabled(details);
  logic.append(element("option", "Remove if any rule fails · OR", {value: "any"}), allOption); logic.value = qc.remove_if || "any";
  card.append(element("label", "Draft failure logic", {for: "qc-rule-combine"}), logic);
  const controls = {logic, rows: [], panelHash: details.mad_panel?.panel_hash}; state.qcControls = controls; logic.addEventListener("change", chooseQCDraft);
  const groupOptions = qcGroupOptions(details, rules);
  rules.forEach((rule, index) => {
    const row = cycleNode("div", null, "qc-rule-" + index, {class: "qc-rule-row"}); row.append(element("h4", "Rule " + (index + 1) + " · " + (rule.op === "mad_preset" ? "Saved dynamic MAD preset" : "Fixed range")));
    if (rule.op === "range") {
      const fields = {op: "range"};
      fields.metric = strategyControl("select", "qc-range-metric-" + index, null, {"aria-label": "QC range metric " + (index + 1)});
      fields.metric.append(element("option", "Choose a metric", {value: ""})); for (const value of ["nCount", "nFeature", "percent_mt"]) fields.metric.append(element("option", value, {value})); fields.metric.value = rule.metric;
      for (const bound of ["min", "max"]) fields[bound] = strategyControl("input", "qc-range-" + bound + "-" + index, rule[bound] == null ? "" : String(rule[bound]), {type: "text", inputmode: "decimal", "aria-label": "QC inclusive " + bound + " " + (index + 1), placeholder: "No bound"});
      fields.group = strategyControl("select", "qc-range-group-" + index, null, {"aria-label": "Literal declared sample/capture QC scope " + (index + 1)});
      for (const [value, label] of groupOptions) fields.group.append(element("option", label, {value})); fields.group.value = rule.group == null ? "null" : JSON.stringify(Object.fromEntries(["sample", "capture"].filter(role => Object.hasOwn(rule.group, role)).map(role => [role, rule.group[role]])));
      const grid = element("div", null, {class: "parameter-fields"});
      for (const [key, title] of [["metric", "Metric"], ["min", "Inclusive minimum"], ["max", "Inclusive maximum"], ["group", "Declared QC scope"]]) {const label = element("label", title); label.append(fields[key]); grid.append(label); fields[key].addEventListener(key === "metric" || key === "group" ? "change" : "input", chooseQCDraft);}
      row.append(grid); controls.rows.push(fields);
    } else if (rule.op === "mad_preset") {
      if (qc.schema === "scagentkit.qc.mad.v1") {
        row.append(element("p", "Saved dynamic choice: " + rule.preset_id + ". Use the single candidate picker in the sample-aware quality section below."));
        controls.rows.push({op: "mad_preset", preset: {get value() {return state.madSelect?.value || rule.preset_id;}}});
      } else {
        const preset = strategyControl("select", "qc-mad-preset", null, {"aria-label": "One saved dynamic MAD preset"}); preset.append(element("option", "Choose a saved available preset", {value: ""}));
        for (const candidate of array(details.mad_panel?.presets)) {const option = element("option", (candidate.label || candidate.preset_id) + (candidate.available === true ? "" : " · unavailable"), {value: candidate.preset_id}); option.disabled = candidate.available !== true || !madPresets.includes(candidate.preset_id); preset.append(option);}
        preset.value = rule.preset_id; preset.addEventListener("change", chooseQCDraft); row.append(preset); controls.rows.push({op: "mad_preset", preset});
      }
    } else {row.append(raw(rule)); controls.rows.push({op: "unsupported", rule});}
    const remove = strategyControl("button", "qc-rule-remove-" + index, null, {type: "button", class: "button quiet", "data-unavailable": String(!qcRulesEnabled(details))}); remove.textContent = "Remove this draft rule"; remove.addEventListener("click", () => changeQCRules("remove", index)); row.append(remove); card.append(row);
  });
  const addRange = strategyControl("button", "qc-add-range", null, {type: "button", class: "button quiet", "data-unavailable": String(!qcRulesEnabled(details) || rules.length >= 32)}); addRange.textContent = "Add fixed range"; addRange.addEventListener("click", () => changeQCRules("range"));
  const addMad = strategyControl("button", "qc-add-mad", null, {type: "button", class: "button quiet", "data-unavailable": String(!qcRulesEnabled(details) || !array(details.capabilities?.qc_rules?.operations).includes("mad_preset") || rules.length >= 32 || rules.some(rule => rule.op === "mad_preset") || !hash(details.mad_panel?.panel_hash))}); addMad.textContent = "Add saved dynamic MAD rule"; addMad.addEventListener("click", () => changeQCRules("mad"));
  const actions = element("div", null, {class: "parameter-actions"}); actions.append(addRange, addMad); card.append(actions);
  card.append(cycleNode("p", "Fields update the complete JSON draft only. Save once, inspect the rebuilt exact impact, then approve the whole strategy. Blank bounds are unbounded; at least one real bound is required. Unknown measurements are not zero or an automatic failure.", "qc-draft-note", {class: "microcopy"}));
  const record = element("details"); record.append(element("summary", "Saved QC parameters and dynamic panel provenance"), raw({saved_qc: details.canonical_proposal?.qc, mad_panel: details.mad_panel ?? null})); card.append(record); return card;
}
function renderQCImpact(details) {
  const preview = details.qc_impact, card = cycleNode("section", null, "qc-readable-impact", {class: "qc-readable-impact"}); card.append(element("h3", "Saved QC impact"));
  if (preview?.schema !== "scagentkit.qc.preview.v1") {
    if (typeof preview?.expected_retained_cells === "number" && typeof preview?.input_cell_count === "number")
      card.append(element("p", "Saved legacy projected retention: " + evidenceNumber(preview.expected_retained_cells) + " of " + evidenceNumber(preview.input_cell_count) + " input cells. The full exact QC preview and rule-level impacts are not recorded.", {class: "parameter-impact-summary"}));
    else empty(card, "No verified saved QC preview is recorded. Counts are unavailable; editing never computes an estimate.");
    return card;
  }
  const retention = preview.retention || {}, stage = details.qc_stage_counts || details.qc_mad?.impact?.stage_counts || {}, logic = preview.rule_logic || {};
  const original = stage.original_cells ?? retention.before, preScore = stage.pre_score_cells;
  const percent = value => typeof value === "number" && Number.isFinite(value) && typeof original === "number" && original > 0 ? (100 * value / original).toFixed(2) + "%" : "Unavailable";
  card.append(cycleNode("p", "Original input: " + evidenceNumber(original) + "; pre-score: " + evidenceNumber(preScore) + "; after QC: " + evidenceNumber(retention.retained) + "; after separate doublet choice: " + evidenceNumber(details.applicability?.doublet?.retained_cells ?? stage.final_selected_cells) + ".", "qc-stage-counts", {class: "parameter-impact-summary"}));
  card.append(cycleNode("p", "Saved preview only. New draft values have not been evaluated; Save rebuilds this evidence in R. All percentages below use original input as denominator. Independent failures overlap and must not be added. Exclusive means actually removed while failing only that rule. Any/all applies to failed rules; Unknown is disclosed separately.", "qc-impact-note", {class: "microcopy"}));
  card.append(cycleNode("p", "Explicit minimal prefilter exclusions cannot be restored by any later fixed range, MAD preset or any/all choice. Saved prefilter removed: " + evidenceNumber(logic.prefilter_removed) + "; quality removed among eligible cells: " + evidenceNumber(logic.quality_removed) + ". Doublet predictions and keep/remove_predicted remain a separate later choice; cells already excluded by QC are not removed twice.", "qc-prefilter-boundary", {class: "microcopy"}));
  const rows = array(preview.filter_impacts);
  if (rows.length) card.append(table(["Rule", "Saved condition", "Scoped", "Independent failures", "% original", "Exclusive removals", "% original", "Unknown"], rows.map(row => [row.id, row.filter?.op === "mad_preset" ? "MAD " + row.filter.preset_id : (row.filter?.metric || "Unknown") + " [" + (row.filter?.min ?? "unbounded") + ", " + (row.filter?.max ?? "unbounded") + "]", evidenceNumber(row.scoped), evidenceNumber(row.independently_removed), percent(row.independently_removed), evidenceNumber(row.exclusively_removed), percent(row.exclusively_removed), evidenceNumber(row.unavailable)])));
  else empty(card, "Rule-level impacts are not recorded.");
  const groups = element("details"); groups.append(element("summary", "QC retention for every declared sample/capture group"));
  groups.append(table(["Literal QC group", "Original input", "Retained", "Removed", "Retained / group original"], array(retention.groups).map(row => [json(row.selector), evidenceNumber(row.before), evidenceNumber(row.retained), evidenceNumber(row.removed), typeof row.fraction_retained === "number" ? (100 * row.fraction_retained).toFixed(2) + "%" : "Unavailable"]))); card.append(groups);
  const overlaps = element("details"); overlaps.append(element("summary", "Pairwise failure overlap and complete failure patterns"));
  const ids = array(preview.overlap?.filter_ids), matrix = array(preview.overlap?.counts);
  if (ids.length) overlaps.append(table(["Failed rule", ...ids], ids.map((id, index) => [id, ...array(matrix[index]).map(evidenceNumber)])));
  overlaps.append(table(["Failed rules", "Unavailable rules", "Prefilter excluded", "Cells", "Retained", "Removed"], array(preview.patterns).map(row => [array(row.filter_ids).join(", ") || "None", array(row.unavailable_filter_ids).join(", ") || "None", typeof row.prefilter_excluded === "boolean" ? String(row.prefilter_excluded) : "Not recorded", evidenceNumber(row.count), evidenceNumber(row.retained), evidenceNumber(row.removed)]))); card.append(overlaps);
  const audit = element("details"); audit.append(element("summary", "Complete saved QC record and exact local scope fingerprints"), raw(preview)); card.append(audit); return card;
}
function chooseClusteringDraft() {
  if (!ready() || node()?.kind !== "strategy" || !node()?.can_revise || !state.clusteringControls) return;
  try {
    const draft = strategyDraft(), controls = state.clusteringControls, text = controls.candidates.value.trim();
    draft.clustering = {resolution: numericDraft(controls.resolution.value), diagnostic_resolutions: text ? text.split(",").map(numericDraft) : null}; setStrategyDraft(draft);
  } catch (_) {message("Correct the complete JSON draft before changing clustering settings.", true);}
}
function renderClustering(details, proposal) {
  if (proposal.clustering == null) return strategySection("Clustering and resolution", null, "Processed clusters are reused; no new resolution or diagnostic comparison is invented.");
  const card = cycleNode("section", null, "clustering-card", {class: "strategy-evidence-card clustering-card"}); card.append(element("h3", "Clustering and resolution"));
  const resolution = strategyControl("input", "clustering-resolution", proposal.clustering.resolution == null ? "" : String(proposal.clustering.resolution), {type: "text", inputmode: "decimal", "aria-label": "Direct draft Louvain resolution in (0,2]"});
  const candidates = strategyControl("input", "clustering-diagnostic-resolutions", array(proposal.clustering.diagnostic_resolutions).join(", "), {type: "text", "aria-label": "At most five explicit diagnostic resolutions", placeholder: "Optional, comma-separated numbers"});
  for (const [control, title] of [[resolution, "Direct resolution · (0,2]"], [candidates, "Optional comparison · up to five unique resolutions"]]) {const label = element("label", title); label.append(control); card.append(label); control.addEventListener("input", chooseClusteringDraft);}
  state.clusteringControls = {resolution, candidates};
  card.append(element("p", "This edits the complete plan only. The existing engine evaluates explicitly approved candidates on one saved neighbor graph; counts and ARI describe computational sensitivity, not biological correctness. No sweep runs during review.", {class: "microcopy"}));
  const diagnostic = state.view.run.computed_diagnostics, actual = diagnostic?.cluster_candidates, comparison = cycleNode("div", null, "clustering-actual-comparison");
  const bound = actual?.status === "saved" && actual.source === "analysis_saved_louvain_diagnostics" && hash(actual.basis_artifact_sha256) && actual.basis_artifact_sha256 === diagnostic.basis_artifact_sha256 && hash(actual.analysis_artifact_sha256);
  if (bound && Array.isArray(actual.candidates) && actual.candidates.length) comparison.append(element("p", "Actual saved comparison from the approved analysis checkpoint; new draft values have not been executed."), table(["Resolution", "Chosen", "Clusters", "Smallest", "Largest", "ARI / chosen", "ARI / previous"], actual.candidates.map(row => [evidenceNumber(row.resolution), typeof row.chosen === "boolean" ? String(row.chosen) : "Unknown", evidenceNumber(row.n_clusters), evidenceNumber(row.min_cluster_size), evidenceNumber(row.max_cluster_size), evidenceNumber(row.ari_vs_chosen), evidenceNumber(row.ari_vs_previous)])));
  else empty(comparison, "Not run or no bound saved diagnostic comparison is available. Candidate settings do not imply observed cluster counts.");
  card.append(comparison); return card;
}
function chooseBatchDraft() {
  if (!ready() || node()?.kind !== "strategy" || !node()?.can_revise || !state.batchControls) return;
  const controls = state.batchControls;
  try {
    const draft = strategyDraft(), method = controls.method.value, choice = {method, reason: controls.reason.value};
    if (method === "harmony") {
      for (const key of ["group_by_vars", "theta", "lambda"]) {try {choice[key] = JSON.parse(controls[key].value);} catch (_) {choice[key] = null;}}
      for (const key of ["sigma", "max_iter", "nclust"]) choice[key] = controls[key].value.trim() ? Number(controls[key].value) : null;
    }
    draft.batch = choice; state.strategyDraftText = json(draft); $("strategy-json").value = state.strategyDraftText;
    controls.parameters.hidden = method !== "harmony"; updateStrategyDraftStatus(); buttons();
  } catch (_) {message("Correct the complete strategy JSON before changing batch fields.", true);}
}
function choosePCDraft() {
  if (!ready() || node()?.kind !== "strategy" || !node()?.can_revise || !state.pcControls) return;
  const controls = state.pcControls;
  try {
    const draft = strategyDraft(), method = controls.method.value;
    draft.pcs = method === "fixed" ? {method, ndim: numericDraft(controls.ndim.value)} : {method, threshold: numericDraft(method === "computed_top50" ? controls.top50.value : controls.threshold.value)};
    state.strategyDraftText = json(draft); $("strategy-json").value = state.strategyDraftText;
    controls.ndim.hidden = method !== "fixed"; controls.threshold.hidden = method !== "computed_variance"; controls.top50.hidden = method !== "computed_top50"; updateStrategyDraftStatus(); buttons();
  } catch (_) {message("Correct the complete strategy JSON before changing PC fields.", true);}
}
function renderBatch(details, proposal) {
  const batch = proposal.batch || {method: "none"}, facts = details.background?.facts || {}, columns = facts.columns || {}, eligible = declaredHarmonyColumns(details);
  const card = cycleNode("section", null, "harmony-card", {class: "strategy-evidence-card harmony-card"}); card.append(element("h3", "Batch handling"), strategyRecord(details.canonical_proposal?.batch, "Saved typed batch choice"));
  card.append(cycleNode("p", "Default none keeps the computed PCA representation. Manual records a pending analyst decision. Harmony requires explicit technical provenance, supported metadata columns and one whole-plan approval; it does not delete cells or claim preserved biological effects.", "harmony-note", {class: "microcopy"}));
  const method = strategyControl("select", "harmony-method", null, {"aria-label": "Draft batch handling method"});
  for (const name of ["none", "manual", "harmony"]) method.append(element("option", name, {value: name})); method.value = batch.method || "none";
  const reason = strategyControl("textarea", "harmony-reason", batch.reason || "", {"aria-label": "Required analyst reason for batch handling", rows: "2"});
  card.append(element("label", "Draft method", {for: "harmony-method"}), method, element("label", "Required analyst reason", {for: "harmony-reason"}), reason);
  const parameters = cycleNode("div", null, "harmony-parameters"), controls = {method, reason, parameters}; parameters.hidden = batch.method !== "harmony";
  for (const [key, label] of [["group_by_vars", "Explicit correction metadata columns · JSON string array"], ["theta", "theta · numeric scalar or array; >= 0"], ["lambda", "lambda · numeric scalar or array; > 0"], ["sigma", "sigma · (0,1]"], ["max_iter", "max_iter · integer 1–50"], ["nclust", "nclust · integer 2–100"]]) {
    const input = strategyControl("input", "harmony-" + key, batch[key] == null ? "" : ["group_by_vars", "theta", "lambda"].includes(key) ? json(key === "group_by_vars" ? array(batch[key]) : batch[key]) : String(batch[key]), {type: "text", "aria-label": label}); controls[key] = input;
    parameters.append(element("label", label, {for: "harmony-" + key}), input); input.addEventListener("input", chooseBatchDraft);
  }
  method.addEventListener("change", chooseBatchDraft); reason.addEventListener("input", chooseBatchDraft); state.batchControls = controls; card.append(parameters);
  card.append(cycleNode("p", "Declared technical_batch: " + (typeof facts.design?.technical_batch === "boolean" ? String(facts.design.technical_batch).toUpperCase() : "Unknown") + "; design notes/source: " + (facts.design?.notes || "Unknown") + ". Eligible explicit technical batch/sample/donor columns: " + (eligible.join(", ") || "None available") + ". Group, condition, treatment and physical capture are excluded; aliases and ambiguous role mappings are rejected.", "harmony-provenance", {class: "microcopy"}));
  card.append(cycleNode("p", "Correction can remove biological signal. Crossed design is an estimability check; it does not prove correction is necessary or beneficial. Complete confounding is blocked by R. The biological group is excluded as a correction covariate; that is not a claim that its effect is preserved. Do not select parameters by whether UMAP looks cleaner.", "harmony-risk", {class: "evidence-explainer"}));
  const design = cycleNode("details", null, "harmony-design"); design.append(element("summary", "Declared roles, design risks, corrected factors and saved applicability"), raw({columns, design: facts.design || null, selected: batch.group_by_vars || [], audit: details.harmony?.audit || details.batch_design || details.applicability?.details?.harmony_audit || details.applicability?.details?.batch_group_audit || null, applicability: details.harmony || details.applicability || null})); card.append(design);
  card.append(cycleNode("p", "These fields edit the complete JSON draft only. Save, inspect the rebuilt scope and approve once before Continue; no browser control runs a model or integration.", "harmony-draft-note", {class: "microcopy"})); return card;
}
function renderPCs(details, proposal) {
  if (proposal.pcs == null) return strategySection("PC selection", null, "Reuse is explicit for a processed start; no PCA dimensions are invented.");
  const pcs = proposal.pcs, record = details.pc_diagnostics || {}, runtime = state.view.run.computed_diagnostics;
  const reviewBound = record.schema === "scagentkit.strategy.pc-review.v1" && record.status === "computed" && hash(record.artifact?.sha256) && hash(record.basis_dependency_hash);
  const diagnostic = reviewBound ? record.actual?.top50_candidates || {} : hash(runtime?.basis_artifact_sha256) ? runtime.pc_candidates || {} : {}, candidates = diagnostic.candidates || {};
  const actual = diagnostic.schema === "scagentkit.pc.candidates.v1" && (reviewBound || hash(runtime?.basis_artifact_sha256));
  const card = cycleNode("section", null, "pc-card", {class: "strategy-evidence-card pc-card"}); card.append(element("h3", "PC selection"), strategyRecord(details.canonical_proposal?.pcs, "Saved typed PC policy"));
  const method = strategyControl("select", "pc-method", null, {"aria-label": "Draft typed PC selection policy"}); for (const name of ["fixed", "computed_variance", "computed_top50"]) method.append(element("option", name, {value: name})); method.value = pcs.method;
  const ndim = strategyControl("input", "pc-ndim", pcs.ndim == null ? "" : String(pcs.ndim), {type: "text", inputmode: "numeric", "aria-label": "Explicit fixed PC dimensions · integer 2 through computed basis size"});
  const threshold = strategyControl("input", "pc-threshold", pcs.method === "computed_variance" && pcs.threshold != null ? String(pcs.threshold) : "", {type: "text", inputmode: "decimal", "aria-label": "Fraction of all actually computed PC variance · 0 < fraction < 1", placeholder: "0.80 reference · enter any 0 < fraction < 1"});
  const top50 = strategyControl("select", "pc-top50-threshold", null, {"aria-label": "Computed first 50 PC variance policy fraction"}); top50.append(element("option", "0.80", {value: "0.8"}), element("option", "0.85", {value: "0.85"})); top50.value = [0.8, 0.85].includes(pcs.threshold) ? String(pcs.threshold) : "";
  ndim.hidden = pcs.method !== "fixed"; threshold.hidden = pcs.method !== "computed_variance"; top50.hidden = pcs.method !== "computed_top50";
  state.pcControls = {method, ndim, threshold, top50}; for (const input of [method, top50]) input.addEventListener("change", choosePCDraft); for (const input of [ndim, threshold]) input.addEventListener("input", choosePCDraft);
  card.append(element("label", "Draft PC policy", {for: "pc-method"}), method, ndim, threshold, top50, cycleNode("p", "computed_variance accepts any explicit fraction 0 < f < 1; 0.80 is a reference, not an automatic choice. Its denominator is the sum of all actually computed PC variances. Fixed ndim is an explicit dimension count. The legacy computed_top50 0.80 / 0.85 are explicit empirical policies, not universal optima. They use only the first min(50, computed PCs), not total expressed-gene variance; shortfalls are disclosed and unsupported one-PC results are not clipped to two.", "pc-policy-note", {class: "microcopy"}));
  card.append(cycleNode("p", actual ? "Saved computed PCA diagnostics are available. Inspect actual candidates and their basis fingerprint below. A historical initial review may predate computation; saved diagnostics do not update the approved policy or execute a draft." : "Deferred: PCA has not been computed or no matching cached basis is recorded. Actual computed PC count and selected dimensions are unknown; the initial review approves a typed policy only.", "pc-status", {"data-status": actual ? "computed" : "deferred", class: "microcopy"}));
  const target = cycleNode("div", null, "pc-candidates");
  if (actual) target.append(table(["Policy", "Threshold", "Actual dimensions", "Supported", "Reason"], ["p80", "p85"].map(key => {const row = candidates[key] || {}; return [key, evidenceNumber(row.threshold), evidenceNumber(row.ndim), typeof row.supported === "boolean" ? String(row.supported) : "Unknown", row.reason || "None recorded"]})), element("p", "Computed PCs: " + evidenceNumber(diagnostic.total_computed_pcs) + "; reference PCs: " + evidenceNumber(diagnostic.reference_pcs) + "; shortfall: " + evidenceNumber(diagnostic.shortfall_count) + "."));
  else empty(target, "Actual 80% / 85% candidate dimensions are deferred; no preview value is fabricated."); card.append(target);
  const all = cycleNode("details", null, "pc-all-computed"), projected = runtime?.all_pc_variance;
  const allBound = projected?.status === "saved" && projected.source === "strategy_basis_saved_pca_evidence" && hash(projected.basis_artifact_sha256) && projected.basis_artifact_sha256 === runtime.basis_artifact_sha256;
  const measured = allBound ? projected : reviewBound ? record.actual : null;
  all.append(element("summary", "All computed PC variances · distinct from the legacy first-50 reference"));
  if ((allBound || reviewBound) && Number.isInteger(measured?.available_pcs) && Array.isArray(measured.fraction_per_pc) && measured.fraction_per_pc.length === measured.available_pcs && Array.isArray(measured.cumulative_fraction) && measured.cumulative_fraction.length === measured.available_pcs)
    all.append(element("p", "Actually computed PCs: " + evidenceNumber(measured.available_pcs) + ". Denominator: " + (measured.denominator || "Unavailable") + "."), table(["PC", "Fraction / all computed PCs", "Cumulative fraction"], measured.fraction_per_pc.map((fraction, index) => [index + 1, evidenceNumber(fraction), evidenceNumber(measured.cumulative_fraction[index])])));
  else empty(all, "All-computed-PC variances are not recorded in this bound review; no curve or selected dimension is inferred."); card.append(all);
  const bound = cycleNode("details", null, "pc-details"); bound.append(element("summary", "Saved actual PC variances, denominator, shortfall and basis binding"), raw(record)); card.append(bound); return card;
}
function renderMad(details, proposal) {
  const saved = details.qc_mad || {}, panel = details.mad_panel || {}, choice = proposal.qc || {}, selected = array(panel.presets).find(row => row?.preset_id === choice.preset_id), error = madReviewError(details, proposal);
  const card = cycleNode("section", null, "mad-card", {class: "strategy-evidence-card mad-card"});
  card.append(element("h3", "Sample-aware quality candidates"), cycleNode("p", "Saved choice: " + (choice.preset_id || "Unknown") + (choice.preset_id === "keep_all" ? " · keep all pre-score cells (default)" : " · explicit reviewed quality rule"), "mad-choice", {"data-preset": choice.preset_id || "unknown"}));
  card.append(cycleNode("p", "One saved panel covers every declared QC group. A choice edits the complete plan draft only; save, inspect and approve the whole plan before Continue. No preset is universally best and retained cell counts are not biological truth.", "mad-review-note", {class: "microcopy"}));
  const grouping = panel.grouping || {}, capture = details.doublet_diagnostics?.capture || {}, method = panel.method || {};
  card.append(cycleNode("p", "QC grouping: " + (grouping.column || grouping.id || "Unknown") + "; role: " + (grouping.declared_role || "Unknown") + "; source: " + (grouping.source || "Unknown") + ". Capture/loading unit: " + (capture.column || capture.id || "Unknown") + ". QC group, sample, capture and donor are distinct declarations; no relationship is inferred.", "mad-grouping", {class: "microcopy"}));
  card.append(cycleNode("p", "Counts/features: log10(x+1), median ± " + evidenceNumber(method.k) + " × scaled MAD; scaled MAD constant: " + evidenceNumber(method.mad_constant) + ". Mitochondrial fraction: upper tail on its original scale. Strict comparisons use the saved exact thresholds; rounded display values never control execution.", "mad-method", {class: "microcopy"}));
  card.append(cycleNode("p", "High RNA is flagged only. Ribosomal and haemoglobin measurements are diagnostic only; none authorizes automatic deletion. MAD zero/near zero, small groups, missing/nonfinite values and distribution warnings can make a candidate unavailable. Unknown is distinct from an observed zero.", "mad-risk", {class: "evidence-explainer"}));
  const stage = panel.stage_counts || {}, impact = saved.impact || {}, counts = details.qc_stage_counts || details.stage_counts || impact.stage_counts || {};
  card.append(cycleNode("p", "Original: " + evidenceNumber(counts.original_cells ?? stage.original_cells) + "; minimal prefilter: " + evidenceNumber(counts.prefilter_cells ?? stage.pre_score_cells) + "; pre-score: " + evidenceNumber(counts.pre_score_cells ?? stage.pre_score_cells) + "; post-QC: " + evidenceNumber(counts.post_qc_cells ?? impact.impact?.post_qc_cells ?? impact.retained ?? impact.retained_cells ?? selected?.retained) + "; post-doublet: " + evidenceNumber(details.applicability?.doublet?.retained_cells ?? counts.final_selected_cells) + ". Quality statistics cells: " + evidenceNumber(stage.statistics_cells) + ".", "mad-stage-counts", {class: "microcopy"}));
  const rate = details.doublet_diagnostics?.rate || {}, reference = details.doublet_diagnostics?.reference;
  card.append(cycleNode("p", "Doublet rate method: " + (rate.method || "Unknown") + "; source: " + (rate.source || "Unknown") + "; score reference: " + (reference || "Unknown") + ". The rate provenance remains separate from the post-QC retained count.", "mad-rate-source", {class: "microcopy"}));
  const prefilter = details.prefilter || {}, prefilterOptions = prefilter.options || {};
  card.append(cycleNode("p", "Minimal prefilter: " + (prefilterOptions.method === "none" ? "none; every supplied cell remains eligible" : prefilterOptions.method === "min_counts" ? "raw total counts >= " + String(prefilterOptions.min_counts) + " (inclusive, explicit preapproved rule)" : "Unknown; inspect the recorded R configuration") + ". Source: " + (prefilterOptions.source || "Unknown") + ". Later quality filtering follows this stage and the saved capture scores; the preset panel does not silently alter legacy range rules.", "mad-prefilter", {class: "microcopy"}));
  const select = cycleNode("select", null, "mad-preset-select", {"aria-label": "Draft whole-plan MAD quality preset"});
  state.madSelect = select;
  for (const candidate of array(panel.presets)) {
    const option = element("option", (candidate.label || candidate.preset_id || "Unknown") + (candidate.available === true ? "" : " · unavailable"), {value: candidate.preset_id || "unknown"});
    option.disabled = candidate.available !== true || candidate.all_cells_removed === true || !madPresets.includes(candidate.preset_id); select.append(option);
  }
  select.value = choice.preset_id || ""; select.addEventListener("change", () => chooseMadPreset(select.value));
  card.append(element("label", "Draft candidate for the whole plan", {for: "mad-preset-select"}), select);
  const candidates = cycleNode("div", null, "mad-candidates"); candidates.append(table(["Preset", "Rule", "Available", "Pre-score", "Retained", "Removed", "Retained fraction", "Unavailable reasons"], array(panel.presets).map(row => [row.preset_id, row.rule || row.label || "Unknown", row.available === true ? "Yes" : "No", evidenceNumber(row.pre_score), evidenceNumber(row.retained), evidenceNumber(row.removed), evidenceNumber(row.fraction_retained), array(row.unavailable_reasons).join("; ") || "None recorded"]))); card.append(candidates);
  const warnings = cycleNode("div", null, "mad-warnings"); warnings.append(element("h4", "Saved panel warnings")); for (const warning of array(panel.warnings)) warnings.append(element("p", typeof warning === "string" ? warning : json(warning))); if (!array(panel.warnings).length) empty(warnings, "None recorded; this does not establish an optimal distribution."); card.append(warnings);
  const groupDetails = cycleNode("details", null, "mad-groups"); groupDetails.append(element("summary", "Every QC group: exact thresholds, rounded displays, diagnostics and candidate effects"));
  for (const group of array(panel.groups)) {
    const section = element("section", null, {class: "mad-group", "data-qc-group": group.group_id || "unknown"});
    section.append(element("h4", typeof group.value === "string" && group.value ? group.value : "Unknown group"), element("p", "Original: " + evidenceNumber(group.before) + "; pre-score: " + evidenceNumber(group.pre_score)));
    for (const [name, metric] of Object.entries(group.metrics || {})) section.append(element("h5", name + " · " + (metric.available === true ? "available" : "Unknown / unavailable")), element("p", "Exact thresholds used by R"), raw(metric.exact || null), element("p", "Rounded display only"), raw(metric.display || null), raw({unavailable_reasons: metric.unavailable_reasons, warnings: metric.warnings}));
    section.append(element("h5", "Diagnostic-only ribosomal / haemoglobin and high-RNA flags"), raw(group.diagnostic_metrics || null), raw({flags: group.flags, warnings: group.warnings}));
    const effects = array(panel.presets).map(candidate => {const row = array(candidate.groups).find(item => item.group_id === group.group_id) || {}; return [candidate.preset_id, evidenceNumber(row.pre_score), evidenceNumber(row.retained), evidenceNumber(row.removed), evidenceNumber(row.fraction_retained)];});
    section.append(table(["Preset", "Pre-score", "Retained", "Removed", "Retained fraction"], effects)); groupDetails.append(section);
  }
  card.append(groupDetails);
  const scope = cycleNode("details", null, "mad-cell-scope"); scope.append(element("summary", "Complete exact quality retained / removed cell IDs"), cycleNode("p", error ? "Unavailable — rebuild the saved binding before approving." : "Retained: " + array(details.qc_impact?.keep_cells).length + "; removed from original input: " + array(details.qc_impact?.remove_cells).length + ". Includes explicit prefilter exclusions; every literal ID is shown without truncation.", "mad-cell-count"), element("h4", "Retained quality cells"), cycleNode("pre", error ? "Unavailable" : array(details.qc_impact?.keep_cells).join("\n") || "None", "mad-keep-ids", {class: "doublet-id-list", tabindex: "0"}), element("h4", "Removed quality cells"), cycleNode("pre", error ? "Unavailable" : array(details.qc_impact?.remove_cells).join("\n") || "None", "mad-remove-ids", {class: "doublet-id-list", tabindex: "0"})); card.append(scope);
  const record = cycleNode("details", null, "mad-details"); record.append(element("summary", "Saved panel, provenance and selection fingerprints"), cycleNode("div", null, "mad-record")); record.children[1].append(raw({panel, ...saved})); card.append(record);
  card.append(cycleNode("p", error || "Panel and selected preset bindings verified locally in the saved review. R rechecks the exact approval before execution.", "mad-binding", {class: "mad-binding" + (error ? " blocked" : ""), "data-status": error ? "unverified" : "verified"}));
  return card;
}
function cycleNode(tag, text, id, attributes = {}) {
  return element(tag, text, {...attributes, id, "data-testid": id});
}
function cycleColumns(evidence) {
  const columns = evidence.columns;
  if (!Array.isArray(columns)) return columns && typeof columns === "object" ? columns : {};
  // The versioned R record fixes the role order before JSON drops vector names.
  if (evidence.schema !== "scagentkit.cycle.evidence.v1" || columns.length !== 4 || !columns.every(value => typeof value === "string" && value)) return {};
  return Object.fromEntries(["s_score", "g2m_score", "phase", "difference"].map((role, index) => [role, columns[index]]));
}
function renderCycle(details, proposal) {
  const saved = details.cycle_diagnostics, evidence = saved && typeof saved === "object" && !Array.isArray(saved) ? saved : {}, choice = proposal.cycle || {method: "none"}, applicability = details.applicability?.cycle;
  const method = ["none", "full", "difference"].includes(choice.method) ? choice.method : "unknown", available = evidence.status === "available";
  const card = cycleNode("section", null, "cycle-card", {class: "strategy-evidence-card cycle-card"});
  card.append(element("h3", "Cell-cycle scores and regression"));
  card.append(cycleNode("span", available ? "Available · saved scores" : "Unknown · " + (evidence.status === "insufficient" ? "insufficient evidence" : "evidence unavailable"), "cycle-status", {class: "pill " + (available ? "blue" : "muted"), "data-status": evidence.status || "unavailable"}));
  card.append(cycleNode("p", "Ordinary choices: none keeps cell-cycle signal (default); full uses standard regression of the S and G2M scores.", "cycle-ordinary", {class: "microcopy"}));
  const methods = {none: "none · keep cell-cycle signal (default)", full: "full · standard regression of S and G2M scores", difference: "difference · advanced regression of S minus G2M score", unknown: "Unknown · inspect the saved method"};
  card.append(cycleNode("p", "Saved method: " + methods[method], "cycle-method", {class: "cycle-method", "data-method": method}));
  const columns = cycleColumns(evidence), regressors = method === "full" ? [columns.s_score, columns.g2m_score] : method === "difference" ? [columns.difference] : [];
  card.append(cycleNode("p", method === "none" ? "Reviewed scaling inputs: none. Keep the saved signal." : "Reviewed scaling inputs: " + (regressors.length && regressors.every(value => typeof value === "string" && value) ? regressors.join(", ") : "Unknown; saved score columns are unavailable."), "cycle-regressors", {class: "cycle-regressors"}));
  if (typeof choice.reason === "string" && choice.reason) card.append(element("p", choice.reason, {class: "strategy-rationale"}));
  card.append(cycleNode("p", "Full regression of S and G2M scores can remove biological signal. These score-based phase labels are not biological truth.", "cycle-risk", {class: "evidence-explainer"}));
  card.append(cycleNode("p", "If proliferation or cell cycle is the research goal, consider keeping the signal with none. The analyst can revise the complete plan.", "cycle-goal", {class: "microcopy"}));
  const advanced = cycleNode("details", null, "cycle-advanced"); advanced.append(element("summary", "Advanced option: difference regression"), cycleNode("p", "Difference preserves the cycling/noncycling contrast while reducing differences between phases. It regresses only the saved S minus G2M score column: " + (typeof columns.difference === "string" && columns.difference ? columns.difference : "Unknown") + ". Select it only by revising the complete strategy JSON; the same central approval covers it.", "cycle-difference-risk", {class: "evidence-explainer"})); card.append(advanced);
  card.append(element("p", "Regression does not delete cells. Change the complete strategy JSON, save the rebuilt review, then use the same central approval before local computation.", {class: "microcopy"}));
  const cohort = evidence.cohort || {}, fixed = evidence.reference === "fixed_full_input" && evidence.refit_after_qc === false;
  card.append(cycleNode("p", (fixed ? "Fixed full input cohort before QC; no refit after QC. " : "Scoring reference: Unknown; inspect the saved record. ") + "Input cells: " + evidenceNumber(cohort.input_cells) + "; scored: " + evidenceNumber(cohort.scored_cells) + "; Unknown: " + evidenceNumber(cohort.unknown_cells) + ". Projected retained cells: " + evidenceNumber(applicability?.retained_cells) + ".", "cycle-cohort", {class: "cycle-cohort"}));
  const coverage = cycleNode("div", null, "cycle-coverage"), rows = ["S", "G2M"].map(phase => {const value = evidence.coverage?.[phase] || {}; return [phase, evidenceNumber(value.present) + " / " + evidenceNumber(value.requested), evidenceNumber(value.expressed) + " / " + evidenceNumber(value.requested), evidenceNumber(value.present_fraction), evidenceNumber(value.expressed_fraction)];});
  coverage.append(table(["Gene set", "Present / requested", "Expressed / requested", "Present fraction", "Expressed fraction"], rows)); card.append(coverage);
  const geneSet = evidence.gene_set || {};
  card.append(cycleNode("p", "Species: " + (evidence.species || "Unknown") + ". Gene source: " + (geneSet.source || "Unknown") + "; version: " + (geneSet.version || "Unknown") + ". Literal species-tagged lists are used; any symbol mapping must be explicit. Human and mouse symbols are not inferred by changing case.", "cycle-provenance", {class: "microcopy"}));
  const expanded = cycleNode("details", null, "cycle-details"); expanded.append(element("summary", "Gene provenance, exact coverage, normalization, score summaries and applicability"));
  const record = cycleNode("div", null, "cycle-record"); record.append(raw({status: evidence.status ?? "unavailable", reasons: evidence.reasons ?? [], species: evidence.species ?? null, assay: evidence.assay ?? null, counts_layer: evidence.counts_layer ?? null, gene_set: evidence.gene_set ?? null, coverage: evidence.coverage ?? null, normalization: evidence.normalization ?? null, cohort: evidence.cohort ?? null, reference: evidence.reference ?? null, refit_after_qc: evidence.refit_after_qc ?? null, columns: evidence.columns ?? null, phase_counts: evidence.phase_counts ?? null, score_distributions: evidence.score_distributions ?? null, scoring: evidence.scoring ?? null, control: evidence.control ?? null, options: evidence.options ?? null, applicability: applicability ?? null})); expanded.append(record);
  card.append(expanded); return card;
}
function renderDoublet(details, proposal) {
  const saved = details.doublet_diagnostics, evidence = saved && typeof saved === "object" && !Array.isArray(saved) ? saved : {}, impact = details.applicability?.doublet;
  const choice = details.canonical_proposal?.doublet || {method: "keep"}, method = ["keep", "remove_predicted"].includes(choice.method) ? choice.method : "unknown";
  const available = evidence.schema === "scagentkit.doublet.evidence.v1" && evidence.status === "available", scopeError = doubletReviewError(details, details.canonical_proposal);
  const card = cycleNode("section", null, "doublet-card", {class: "strategy-evidence-card doublet-card"});
  card.append(element("h3", "Doublet predictions and exact cell impact"));
  card.append(cycleNode("span", available ? "Available · saved algorithm predictions" : "Unavailable · " + (evidence.status || "evidence not saved"), "doublet-status", {class: "pill " + (available ? "blue" : "muted"), "data-status": evidence.status || "unavailable"}));
  card.append(cycleNode("p", "Saved reasons: " + (array(evidence.reasons).filter(value => typeof value === "string" && value).join("; ") || (available ? "None declared by the diagnostic record." : "Unavailable; inspect the saved record.")), "doublet-reasons", {class: "microcopy"}));
  card.append(cycleNode("p", "Species: " + (typeof evidence.species === "string" ? evidence.species : "Unavailable") + ". Called-cell input source: " + (typeof evidence.input_source === "string" ? evidence.input_source : "Unavailable") + ". Algorithm: " + (typeof evidence.scoring?.function_name === "string" ? evidence.scoring.function_name : "Unavailable") + "; scDblFinder version: " + (typeof evidence.scoring?.versions?.scDblFinder === "string" ? evidence.scoring.versions.scDblFinder : "Unavailable") + ". All parameters and dependency versions are saved in the evidence details.", "doublet-provenance", {class: "microcopy"}));
  card.append(cycleNode("p", "Choices: keep retains all QC-selected cells (default); remove_predicted removes only the saved algorithm-predicted doublets within the approved QC scope.", "doublet-choices", {class: "microcopy"}));
  card.append(cycleNode("p", "Saved method: " + (method === "keep" ? "keep · scores only; no doublet removal (default)" : method === "remove_predicted" ? "remove_predicted · exact reviewed predicted-doublet scope" : "Unknown · inspect the supported saved method"), "doublet-method", {class: "doublet-method", "data-method": method}));
  if (qcRulesEnabled(details)) {
    const draftChoice = proposal.doublet || choice;
    const draftMethod = strategyControl("select", "doublet-draft-method", null, {"aria-label": "Separate draft doublet keep or remove_predicted choice"});
    draftMethod.append(element("option", "Keep predicted doublets · diagnostic only", {value: "keep"}));
    const removeOption = element("option", "Remove exact predicted-doublet intersection after QC", {value: "remove_predicted"}); removeOption.disabled = !available || !array(details.capabilities?.doublet).includes("remove_predicted"); draftMethod.append(removeOption); draftMethod.value = ["keep", "remove_predicted"].includes(draftChoice.method) ? draftChoice.method : "";
    const draftReason = strategyControl("textarea", "doublet-draft-reason", draftChoice.reason || "", {rows: "2", "aria-label": "Explicit reason for the separate doublet choice"});
    const change = () => {if (!ready() || node()?.kind !== "strategy" || !node()?.can_revise) return; try {const draft = strategyDraft(); draft.doublet = {method: draftMethod.value, reason: draftReason.value}; setStrategyDraft(draft);} catch (_) {message("Correct the complete JSON draft before changing the doublet choice.", true);}};
    draftMethod.addEventListener("change", change); draftReason.addEventListener("input", change);
    card.append(element("label", "Separate draft doublet choice", {for: "doublet-draft-method"}), draftMethod, element("label", "Explicit analyst reason", {for: "doublet-draft-reason"}), draftReason, element("p", "Predicted doublets are independent of QC rule failures. This edits the plan only; save to rebuild the exact post-QC intersection. Already excluded cells are not counted as a second removal.", {class: "microcopy"}));
  }
  if (typeof choice.reason === "string" && choice.reason) card.append(element("p", choice.reason, {class: "strategy-rationale"}));
  card.append(cycleNode("p", "The score is not a calibrated probability; the class is an algorithm prediction, not biological truth. Similar-cell (homotypic) doublets can be difficult to detect. A score or model suggestion does not authorize deletion.", "doublet-risk", {class: "evidence-explainer"}));
  card.append(cycleNode("p", "Capture means the declared physical loading unit. Donor, condition and batch do not establish a capture; the coordinator uses only the saved declaration and its source.", "doublet-capture-note", {class: "microcopy"}));
  const capture = evidence.capture || {}, captureDescription = capture.method === "single" && typeof capture.id === "string" ? "Explicit single loading unit: " + capture.id : capture.method === "column" && typeof capture.column === "string" ? "Declared loading-unit column: " + capture.column : "Loading-unit declaration unavailable";
  card.append(cycleNode("p", captureDescription + ". Source: " + (typeof capture.source === "string" && capture.source ? capture.source : "Unavailable") + ".", "doublet-capture", {class: "microcopy"}));
  const cohort = evidence.cohort || {}, fixed = evidence.reference === "fixed_full_input" && evidence.refit_after_qc === false;
  const prefilterScoring = details.prefilter != null || namedEvidenceRows(evidence.capture_stats).some(([, row]) => Object.hasOwn(row, "pre_score_cells"));
  card.append(cycleNode("p", (fixed ? (prefilterScoring ? "Fixed explicit pre-score cohort after the recorded minimal prefilter and before quality filtering; no refit after QC or deletion. Original full-called capture size remains the rate reference. This does not establish a complete capture. " : "Fixed full project input before QC; no refit after QC or deletion. This does not establish a complete capture. ") : "Scoring reference unavailable; inspect the saved record. ") + "Input: " + evidenceNumber(cohort.input_cells) + "; scored: " + evidenceNumber(cohort.scored_cells) + "; predicted doublets: " + evidenceNumber(cohort.predicted_doublets) + "; Unknown: " + evidenceNumber(cohort.unknown_cells) + ". Projected retained: " + evidenceNumber(impact?.retained_cells) + "; removed by this choice: " + evidenceNumber(impact?.removed_cells) + ".", "doublet-cohort", {class: "microcopy"}));
  const rate = evidence.rate || {};
  card.append(cycleNode("p", "Declared full_called_cohort: " + (typeof evidence.full_called_cohort === "boolean" ? String(evidence.full_called_cohort).toUpperCase() : "Unavailable") + "; technology: " + (typeof evidence.technology === "string" ? evidence.technology : "Unavailable") + ". Expected-rate method: " + (typeof rate.method === "string" ? rate.method : "Unavailable") + ". Source: " + (typeof rate.source === "string" ? rate.source : "Unavailable") + ". Expected rate is a sourced assumption, not a required deletion quota. Standard-10x estimation requires an explicit complete called-cell capture declaration; it is not inferred from project size. Exact per-capture rates and thresholds are saved below.", "doublet-rate", {class: "microcopy"}));
  const predicted = cycleNode("div", null, "doublet-capture-stats"), stats = namedEvidenceRows(evidence.capture_stats);
  if (stats.length) predicted.append(table(prefilterScoring ? ["Declared capture", "Original input", "Pre-score cells", "Prefilter excluded", "Expressed features", "Expected rate (fraction)", "Expected doublets / original", "Predicted doublets", "Predicted fraction / original", "Predicted fraction / scored", "Unknown", "Status"] : ["Declared capture", "Input cells", "Expressed features", "Expected rate (fraction)", "Expected doublets", "Predicted doublets", "Predicted fraction", "Unknown", "Status"], stats.map(([name, row]) => [name, evidenceNumber(row.input_cells), ...(prefilterScoring ? [evidenceNumber(row.pre_score_cells), evidenceNumber(row.prefilter_excluded_cells)] : []), evidenceNumber(row.expressed_features), evidenceNumber(row.expected_rate), evidenceNumber(row.expected_doublets), evidenceNumber(row.predicted_doublets), evidenceNumber(row.predicted_fraction), ...(prefilterScoring ? [evidenceNumber(row.predicted_fraction_scored)] : []), evidenceNumber(row.unknown_cells), typeof row.status === "string" ? row.status : "Unavailable"])));
  else empty(predicted, "Saved per-capture scoring summaries are unavailable. No donor or loading-unit values are inferred."); card.append(predicted);
  const impactTable = cycleNode("div", null, "doublet-capture-impact"), captureImpact = namedEvidenceRows(impact?.per_capture);
  if (captureImpact.length) impactTable.append(table(["Capture", "Input", "QC retained", "Predicted input", "Predicted after QC", "Predicted excluded by QC", "Proposed removed", "Final retained", "Removed / QC (fraction)", "Retained / QC (fraction)", "Removed / input (fraction)", "Retained / input (fraction)"], captureImpact.map(([name, row]) => [name, ...["input_cells", "qc_retained", "predicted_input", "predicted_after_qc", "predicted_qc_excluded", "removed", "retained", "removed_fraction_after_qc", "retained_fraction_after_qc", "removed_fraction_input", "retained_fraction_input"].map(key => evidenceNumber(row[key]))])));
  else empty(impactTable, "Saved per-capture QC and deletion impact is unavailable. No rates or retained counts are inferred."); card.append(impactTable);
  const relation = cycleNode("details", null, "doublet-cycle-relation"); relation.append(element("summary", "QC and cycle relationships, including Unknown"));
  if (impact?.cycle && typeof impact.cycle === "object") {
    const phases = namedEvidenceRows(impact.cycle.phase_by_scope);
    if (phases.length) relation.append(table(["Saved scope", "G1", "S", "G2M", "Undecided", "Unknown"], phases.map(([name, row]) => [name, ...["G1", "S", "G2M", "Undecided", "Unknown"].map(key => evidenceNumber(row[key]))])));
    relation.append(raw(impact.cycle));
  } else empty(relation, "Cycle overlap is unavailable because no bound cycle diagnostics were supplied. No cycle phase or score is inferred."); card.append(relation);
  card.append(cycleNode("p", scopeError || (method === "keep" ? "No cells are selected for doublet removal. Scores and classes remain available for analyst review." : "The exact saved scope and fingerprints are present. Review the full ID list and capture impact before the central approval; R verifies the decision before execution."), "doublet-scope-status", {class: "doublet-scope-status" + (scopeError ? " blocked" : ""), role: "status", "data-status": scopeError ? "unverified" : method === "keep" ? "keep" : "verified"}));
  const ids = cycleNode("details", null, "doublet-cell-scope"); ids.append(element("summary", "Exact cells selected for removal · complete saved list"));
  const literalIds = impact && Object.hasOwn(impact, "removed_cell_ids") ? array(impact.removed_cell_ids) : null;
  const listValid = literalIds != null && literalIds.every(cell => typeof cell === "string" && cell) && new Set(literalIds).size === literalIds.length;
  ids.append(cycleNode("p", listValid && !scopeError ? "Exact removal count: " + fmt(literalIds.length) + ". The list is complete and scrollable; no ID is truncated." : "Exact removal scope unavailable or unverified. Inspect the saved record and rebuild the review in R.", "doublet-cell-count", {class: "microcopy"}));
  ids.append(cycleNode("pre", listValid && !scopeError ? literalIds.length ? literalIds.join("\n") : "None — no doublet removal selected." : "Unavailable", "doublet-cell-ids", {class: "qc-id-list doublet-id-list", tabindex: "0", "aria-label": "Complete exact cell IDs selected for doublet removal"})); card.append(ids);
  const expanded = cycleNode("details", null, "doublet-details"); expanded.append(element("summary", "Capture declaration, fixed scoring reference, rate assumptions, parameters and dependency versions"));
  const record = cycleNode("div", null, "doublet-record"); record.append(raw({diagnostics: saved ?? null, evidence_hash: details.doublet_evidence_hash ?? null, applicability: impact ?? null})); expanded.append(record); card.append(expanded);
  card.append(element("p", "Revise the complete strategy JSON and save once to rebuild this impact review. The same central approval covers QC, the doublet choice and cycle regression. Continue approved local computation separately; source counts and prior metadata remain preserved.", {class: "microcopy"}));
  return card;
}
function updateStrategyDraftStatus() {
  const typedError = strategyDraftError(), dirty = strategyDirty(), savedError = dirty ? null : doubletReviewError() || madReviewError();
  const status = typedError || (dirty ? "Unsaved complete strategy. Saved preview is unchanged. Save to run local validation and rebuild the review before approval." : savedError || "This typed JSON matches the saved strategy proposal.");
  $("strategy-draft-status").textContent = status;
  if (state.strategyFeedback) {state.strategyFeedback.textContent = status; state.strategyFeedback.setAttribute("data-invalid", String(!!(typedError || savedError)));}
  $("strategy-impact-draft-status").textContent = typedError || savedError || (dirty ? "Unsaved draft. These saved impact values have not changed. Save and inspect the rebuilt review before approval." : "These impact values belong to the current saved proposal; approval and execution are separate.");
  $("strategy-impact-draft-status").setAttribute("data-invalid", String(!!(typedError || savedError)));
  renderContinuation();
}
function savedOperationSummary(key, proposal) {
  const choice = proposal[key === "qc-mad" ? "qc" : key];
  if (choice === null) return "Explicit reuse · no new parameters";
  if (choice == null) return "No saved choice supplied";
  if (key === "qc-mad") return choice.preset_id ? "Saved preset · " + choice.preset_id : "Inspect the saved QC panel and choice";
  if (key === "qc") {
    if (["scagentkit.qc.v1", "scagentkit.qc.mad.v1", "scagentkit.qc.rules.v1"].includes(choice.schema)) {
      const rules = qcDraftRules(choice), fixed = rules.filter(rule => rule.op === "range").length, mad = rules.filter(rule => rule.op === "mad_preset").length;
      return `${fixed} fixed ranges · ${mad} saved MAD presets · remove_if ${choice.remove_if || "any"}`;
    }
    return "Inspect the saved QC record";
  }
  if (key === "analysis") return `${choice.normalization_method || "method undeclared"} · ${fmt(choice.nfeatures)} requested HVGs · ${fmt(choice.npcs)} basis PCs`;
  if (key === "pcs") return choice.method === "fixed" ? `Fixed ${fmt(choice.ndim)} PCs` : choice.method === "computed_variance" ? `${fmt(typeof choice.threshold === "number" ? 100 * choice.threshold : null)}% of all computed PC variance` : choice.method === "computed_top50" ? `${fmt(typeof choice.threshold === "number" ? 100 * choice.threshold : null)}% of first min(50, computed PCs) variance` : choice.method || "No saved PC policy";
  if (key === "clustering") return `Resolution ${fmt(choice.resolution)} · ${array(choice.diagnostic_resolutions).length} requested comparison candidates`;
  if (key === "umap") return choice.run === true ? `Requested · ${fmt(choice.n_neighbors)} neighbors` : choice.run === false ? "Not requested" : "Inspect the saved UMAP choice";
  return choice.method || "Inspect the saved choice";
}
function strategyOperationGroup(key, title, card, savedProposal, opened) {
  const group = element("details", null, {class: "strategy-parameter-group", "data-operation": key, id: "strategy-group-" + key});
  const summary = element("summary"); summary.append(element("span", title, {class: "parameter-group-title"}), element("span", "Saved · " + savedOperationSummary(key, savedProposal), {class: "parameter-group-saved"}));
  group.append(summary, card); group.open = opened.has(key); return group;
}
function renderStrategyOperations(details, proposal) {
  state.strategyFeedback = null; state.madSelect = null; state.strategyControls = []; state.batchControls = null; state.pcControls = null; state.qcControls = null; state.clusteringControls = null;
  const operations = $("strategy-operations"), opened = new Set([...operations.children].filter(child => child.open).map(child => child.getAttribute("data-operation"))); operations.replaceChildren();
  for (const [key, title] of [["qc", "QC and cell retention"], ["analysis", "Normalization and PCA basis"], ["pcs", "PC selection"], ["batch", "Batch handling"], ["clustering", "Clustering and resolution"], ["umap", "UMAP"]]) {
    const card = key === "qc" ? renderQCControls(details, proposal) : key === "pcs" ? renderPCs(details, proposal) : key === "clustering" ? renderClustering(details, proposal) : harmonyEnabled(details) && key === "batch" ? renderBatch(details, proposal) : strategySection(title, proposal[key], "Reuse is explicit for a processed start; consult the saved execution plan for this step.");
    operations.append(strategyOperationGroup(key, title, card, details.canonical_proposal || {}, opened));
  }
  if (madEnabled(details, proposal) && proposal.qc?.schema !== "scagentkit.qc.rules.v1") {operations.append(strategyOperationGroup("qc-mad", "Saved sample-aware MAD panel", renderMad(details, details.canonical_proposal), details.canonical_proposal || {}, opened)); if (state.madSelect && proposal.qc?.schema === "scagentkit.qc.mad.v1") state.madSelect.value = proposal.qc.preset_id;}
  if (details.cycle_diagnostics != null || Object.hasOwn(proposal, "cycle") || Array.isArray(details.capabilities?.cycle)) operations.append(strategyOperationGroup("cycle", "Cell-cycle choice and evidence", renderCycle(details, details.canonical_proposal), details.canonical_proposal || {}, opened));
  if (doubletEnabled(details, proposal)) operations.append(strategyOperationGroup("doublet", "Separate doublet choice and evidence", renderDoublet(details, proposal), details.canonical_proposal || {}, opened));
}
function renderStrategy() {
  const record = state.view.run.strategy_review, details = record.details || {}, proposal = details.canonical_proposal || {}, applicability = details.applicability || {};
  state.strategyDraftText = json(proposal); $("strategy-json").value = state.strategyDraftText;
  $("strategy-source").textContent = "Saved " + (details.source?.kind || "unclassified") + " proposal";
  $("strategy-applicability").textContent = applicability.executable === true ? "Local validation: executable within the saved supported scope" : applicability.executable === false ? "Local validation: blocked — inspect the saved blockers before revising" : "Local applicability has not been recorded";
  $("strategy-applicability").className = "strategy-applicability" + (applicability.executable === false ? " blocked" : "");
  $("strategy-execution-note").textContent = proposal.batch?.method === "manual" ? "Manual batch handling remains pending. Approval can record this plan, but local continuation stops for configuration before QC and analysis. No integration is executed. Follow the saved R boundary to revise the batch choice or prepare a separate processed project." : "Approval records the complete plan. Execute approved work separately; it stops at the next review or configuration boundary, including the later annotation review.";
  const background = details.background || {};
  $("strategy-background").replaceChildren(
    strategySection("User-provided facts", background.facts, "No structured user facts were supplied."),
    strategySection("Missing background", background.missing, "No missing background was recorded; this is not a claim that the study design is complete."),
    strategyTextSection("Model / proposal inferences", proposal.inferences, "No model inferences are recorded. Inferences are proposals, not user facts.", true));
  $("strategy-rationale").replaceChildren(element("p", proposal.rationale || "No proposal rationale was supplied.", {class: "strategy-rationale"}), strategyTextSection("Risks declared by the proposal", proposal.risks));
  $("strategy-plan-summary").textContent = suggestionSummary(proposal, "strategy").slice(1).join(" · ") || "Reuse of the supplied processed analysis is explicit in this strategy.";
  $("strategy-key-parameters").replaceChildren(...[["qc", "QC failure rules"], ["pcs", "PC policy"], ["batch", "Batch choice"], ["clustering", "Clustering"]].map(([key, title]) => {const item = element("div", null, {class: "strategy-key-parameter"}); item.append(element("span", title), element("strong", savedOperationSummary(key, proposal))); return item;}));
  const impact = details.qc_impact?.impact || details.qc_impact || {}, counts = details.qc_stage_counts || impact.stage_counts || {};
  const retained = details.applicability?.doublet?.retained_cells ?? counts.final_selected_cells ?? counts.post_qc_cells ?? impact.expected_retained_cells ?? impact.retained_cells ?? impact.retained;
  const original = counts.original_cells ?? impact.input_cell_count ?? details.quality?.cell_count;
  $("strategy-impact-summary").textContent = Number.isFinite(Number(retained)) && retained != null ? "Saved projected retention: " + fmt(retained) + (original != null ? " of " + fmt(original) + " input cells" : " cells") + ". Inspect the exact scopes and applicable operations below before approval." : "Exact cell retention and applicability are saved in the detailed impact evidence below. Approval covers this complete typed strategy; no calculation runs while reviewing.";
  renderStrategyOperations(details, proposal);
  const cycleSupported = details.cycle_diagnostics != null || Object.hasOwn(proposal, "cycle") || Array.isArray(details.capabilities?.cycle);
  const doubletSupported = doubletEnabled(details, proposal);
  $("strategy-blockers").replaceChildren(strategyTextSection("Local blockers", applicability.blockers, "No local blockers were recorded.", true));
  $("strategy-blockers").hidden = !array(applicability.blockers).length;
  $("strategy-quality").replaceChildren(strategySection("Actual quality summary", details.quality));
  $("strategy-qc-impact").replaceChildren(renderQCImpact(details));
  $("strategy-capabilities").replaceChildren(strategySection("Supported capabilities and dependencies", details.capabilities), strategySection("Saved execution plan", details.execution_plan));
  $("strategy-unsupported").textContent = doubletSupported ? (cycleSupported ? "Subclustering is a separate scoped-child action from a completed parent; nested child creation is not a strategy operation." : "Cell-cycle regression is unsupported in this strategy version. Subclustering is a separate scoped-child action from a completed parent.") + " Doublet classes are algorithm predictions. Only an explicitly approved remove_predicted strategy can remove its exact saved scope; cycle regression does not delete cells." : cycleSupported ? "Doublet scoring/removal is unsupported in this strategy version. Subclustering is a separate scoped-child action from a completed parent. Cell-cycle regression does not mean deleting cycling cells; a doublet score alone does not authorize removal." : "Cell-cycle regression and doublet scoring/removal are unsupported in this strategy version. Subclustering is a separate scoped-child action from a completed parent. Cell-cycle regression does not mean deleting cycling cells; a doublet score alone does not authorize removal.";
  $("strategy-limitations").replaceChildren(...array(details.limitations).map(value => element("li", value)));
  $("strategy-record").replaceChildren(raw(record));
  updateStrategyDraftStatus();
}
function render() {
  const run = state.view.run, current = run.review_node;
  $("run-workbench-link").hidden = false; $("run-workbench-link").setAttribute("href", scopedRunURL("/workbench"));
  $("run-home").setAttribute("href", scopedRunURL("/workbench"));
  $("run-header-scope").hidden = state.scopes?.workspace_enabled === false || !state.scopes;
  $("run-header-scope").setAttribute("href", scopedRunURL("/subclusters"));
  $("run-current-scope").textContent = (scopeQuery().child_id ? "Independent child" : "Parent project") + " · " + run.project_id + (state.view.effective_readonly === true ? " · Saved source is read-only" : " · Review edits stay in this exact project");
  renderScopes();
  const childTools = $("run-child-tools"), selectedChild = scopeQuery().child_id;
  childTools.hidden = !selectedChild;
  if (selectedChild) {
    $("run-child-scope-link").setAttribute("href", scopedRunURL("/subclusters"));
    $("run-child-scope-link").textContent = run.status === "complete" ? "Review exact child labels and save a new parent object" : "Child scope, manual Unknown and safe writeback";
  }
  $("run-project").textContent = `${run.project_id} · ${run.context?.species || "species undeclared"} · ${run.context?.tissue || "tissue undeclared"} · revision ${run.revision}`;
  $("run-status").textContent = `${run.status} / ${run.stage}`;
  const strategyFlow = !!run.strategy_review || run.stage.startsWith("strategy"), index = run.status === "complete" ? 3 : run.stage.startsWith("annotation") || ["finalize"].includes(run.stage) ? 2 : ["analysis", "markers", "strategy_basis", "strategy_neighbors", "strategy_cluster"].includes(run.stage) ? 1 : 0;
  $("run-progress").replaceChildren(...[strategyFlow ? "Analysis strategy review · includes QC" : "QC review", continuationEnabled() ? "Analysis · local continuation" : "Analysis · explicit R resume", "Annotation review", "Saved output"].map((label, i) => element("li", label, {class: i === index ? "current" : i < index ? "complete" : ""})));
  const next = $("run-next"); next.replaceChildren();
  if (run.status === "ready") {
    if (continuationEnabled()) next.append(element("p", "The decision is saved. Use the local task controls below to execute approved work. The worker stops at the next review or configuration step."));
    else next.append(element("p", "The decision is saved. Start the next computation on the data machine in R, then refresh this page."), element("code", "scAgentKit::sc_run_resume(project_dir)"));
  }
  else if (run.status === "complete") next.append(element("p", "The reviewed labels and audit are saved in the new output object. Inspect the output in R; biological result acceptance remains a separate analyst judgement."));
  else if (run.status === "rejected" || run.status === "awaiting_configuration") next.append(element("p", current?.can_revise ? "The previous decision is inactive. Edit the supported saved proposal and rebuild the review, or provide a corrected proposal in R." : state.view.suggestion_enabled === true ? "Preview and request a configured model suggestion above, or prepare a supported manual proposal in R. A suggestion must still pass the central scientific review." : "The project needs a supported proposal or configuration in R. No browser calculation or external request is started."));
  else if (run.status === "awaiting_review") next.append(element("p", current ? `Review the saved ${current.kind} snapshot below. Approval records this plan; ${continuationEnabled() ? "continue approved local work separately after approval." : "execution still requires R resume."}` : run.pending?.kind === "external_transfer" && state.view.suggestion_enabled === true ? "Review the exact aggregate preview above. Approve transmission before requesting a model suggestion; scientific review remains a separate decision." : "This node is outside the browser's supported review scope. Inspect and decide on it in R."));
  else next.append(element("p", "Saved status: " + run.status + ". Inspect or resume the computation in R, then refresh the saved state."));
  $("run-qc").hidden = !run.stage.startsWith("qc") || current?.kind !== "qc";
  if (!$("run-qc").hidden && !$("run-qc-frame").getAttribute("src")) $("run-qc-frame").setAttribute("src", scopedRunURL(continuationEnabled() ? "/review-qc?localContinue=1" : "/review-qc"));
  $("run-strategy").hidden = !run.strategy_review;
  if (run.strategy_review) renderStrategy(); else state.strategyDraftText = null;
  $("run-annotation").hidden = !run.annotation_review;
  if (run.annotation_review) renderAnnotation(); else state.drafts.clear();
  $("run-complete").hidden = run.status !== "complete" && !current?.can_undo;
  const output = $("run-output"); output.replaceChildren();
  if (run.output && typeof run.output === "object") {
    const list = element("ul", null, {class: "saved-artifact-list"});
    for (const [name, value] of Object.entries(run.output)) {
      const row = element("li"); row.append(element("span", name), element("code", typeof value === "string" ? value : json(value))); list.append(row);
    }
    output.append(list);
  } else output.append(element("p", state.view.effective_readonly === true && run.status === "complete" ? "The completed source is verified. Its original output path is unavailable in this runtime; inspect the source in R." : "No completed output is currently published.", {class: "review-empty"}));
  $("run-undo").hidden = !current?.can_undo;
  const fingerprints = element("div", null, {class: "qc-hashes"});
  for (const [label, value] of Object.entries({project_id: run.project_id, input_hash: run.input_hash, revision: run.revision, kind: current?.kind, proposal_hash: current?.proposal_hash, review_hash: current?.review_hash, config_hash: run.config_hash, implementation_hash: run.implementation_hash, decision_id: current?.decision_id})) fingerprints.append(element("span", label), element("code", value == null ? "Unavailable" : value));
  $("run-fingerprints").replaceChildren(fingerprints, raw(current?.kind === "strategy" ? run.strategy_review?.lifecycle || {notice: "Strategy decisions and revisions are retained in the R journal."} : run.annotation_review?.lifecycle || {notice: "No annotation decision lifecycle is available yet."}));
  renderContinuation(); renderSuggestion(); buttons();
}
async function load() {
  stopPolling();
  stopSuggestionPolling();
  state.busy = true; buttons();
  try {
    if (!state.view || state.scopes) await loadScopes();
    const answer = await request(); state.view = answer; state.continuation = answer.continuation || null;
    state.stale = false; state.connectionLost = false; state.awaitingFreshInspect = false;
    state.pendingRequest = savedRequest(answer.run); render(); message("");
    if (answer.suggestion_enabled === true) await loadSuggestion();
    else {state.suggestion = null; state.suggestionLost = false; state.suggestionError = ""; renderSuggestion();}
  } catch (error) {
    state.stale = true; state.connectionLost = !!state.continuation;
    message(error.message + " Refresh a verified saved state before submitting again. " + (state.continuation?.job ? "The saved task may still be running; its ID is retained." : ""), true);
    renderContinuation();
  } finally {state.busy = false; renderContinuation(); buttons(); if (activeJob() && !state.connectionLost) schedulePoll();}
}
function basePayload(action, reviewer, reason) {
  const run = state.view.run, current = run.review_node;
  return {action, kind: current.kind, project_id: run.project_id, input_hash: run.input_hash, proposal_hash: current.proposal_hash, review_hash: current.review_hash, expected_revision: run.revision, reviewer, reason};
}
async function decide(action, continueAfter = false) {
  if (!ready() || node()?.kind !== "annotation") return;
  const undo = action === "undo";
  if (undo ? !node().can_undo : action === "revise" ? !node().can_revise : !node().can_decide) return;
  if (!undo && action === "approve" && dirty()) {message("Save corrections and inspect the rebuilt review before approval.", true); return;}
  if (!undo && action === "revise" && draftError()) {message(draftError(), true); return;}
  if (!$(undo ? "run-undo-form" : "annotation-decision-form").reportValidity()) return;
  const payload = basePayload(action, $(undo ? "run-undo-reviewer" : "annotation-reviewer").value.trim(), $(undo ? "run-undo-reason" : "annotation-reason").value.trim());
  if (undo) payload.decision_id = node().decision_id;
  if (action === "revise") payload.proposal = {schema: "scagentkit.annotation.v1", annotations: annotationRows().map(item => state.drafts.get(item.clusterId))};
  let continueApproved = false;
  state.busy = true; buttons();
  try {
    const answer = await request(payload); state.view = answer; state.continuation = answer.continuation || null; state.stale = false; state.connectionLost = false; state.awaitingFreshInspect = false; render();
    continueApproved = continueAfter && action === "approve" && answer.run.status === "ready";
    message(undo ? "Annotation undo saved and previous outputs archived. Review a fresh proposal before applying labels again." : action === "revise" ? "Corrections and reasons saved. Review the rebuilt exact snapshot before approval." : action === "approve" ? continuationEnabled() ? "Annotation approval saved. Continue local computation to apply the reviewed labels." : "Annotation approval saved. Apply the reviewed labels with explicit R resume, then refresh." : "Annotation proposal rejected. The input, evidence and previous proposals remain recorded.");
  } catch (error) {state.stale = true; message(error.message + " Refresh the saved state before submitting again.", true);}
  finally {state.busy = false; renderContinuation(); buttons();}
  if (continueApproved) await continueRun(false);
}
async function decideStrategy(action, continueAfter = false) {
  if (!ready() || node()?.kind !== "strategy" || !["approve", "reject", "revise"].includes(action)) return;
  if (action === "revise" ? !node().can_revise : !node().can_decide) return;
  if (action === "approve" && strategyDirty()) {message("Save the complete strategy and inspect the rebuilt review before approval.", true); return;}
  if (action === "approve" && typedStrategyError(strategyProposal())) {message(typedStrategyError(strategyProposal()), true); return;}
  if (action === "approve" && doubletReviewError()) {message(doubletReviewError(), true); return;}
  if (action === "approve" && madReviewError()) {message(madReviewError(), true); return;}
  if (action === "revise" && strategyDraftError()) {message(strategyDraftError(), true); return;}
  if (!$("strategy-decision-form").reportValidity()) return;
  const payload = basePayload(action, $("strategy-reviewer").value.trim(), $("strategy-reason").value.trim());
  if (action === "revise") payload.proposal = strategyDraft();
  let continueApproved = false;
  state.busy = true; buttons();
  try {
    const answer = await request(payload); state.view = answer; state.continuation = answer.continuation || null;
    state.stale = false; state.connectionLost = false; state.awaitingFreshInspect = false; render();
    continueApproved = continueAfter && action === "approve" && answer.run.status === "ready";
    message(action === "revise" ? "Strategy revision and reason saved. R revalidated the operations; inspect the rebuilt snapshot before approval." : action === "approve" ? "Whole strategy approval saved. Execute approved local work separately; it will stop at the next review or configuration boundary." : "Strategy rejected. The input, evidence and earlier decisions remain recorded.");
  } catch (error) {state.stale = true; message(error.message + " Refresh the saved state before submitting again.", true);}
  finally {state.busy = false; renderContinuation(); buttons();}
  if (continueApproved) await continueRun(false);
}
function edit() {
  const row = state.drafts.get(state.selectedCluster); if (!row) return;
  row.label = $("annotation-label").value; row.confidence = $("annotation-confidence").value; row.rationale = $("annotation-rationale").value; updateDraftStatus(); buttons();
}
$("run-refresh").addEventListener("click", () => {if (dirty() && !window.confirm("Refresh and discard unsaved review corrections? Saved decisions remain in the audit.")) return; load();});
$("run-continue").addEventListener("click", () => continueRun(false));
$("run-continue-retry").addEventListener("click", () => continueRun(true));
for (const id of ["annotation-label", "annotation-confidence", "annotation-rationale"]) $(id).addEventListener("input", edit);
$("annotation-keep").addEventListener("click", () => {const item = annotationRows().find(item => item.clusterId === state.selectedCluster); if (item) {state.drafts.set(item.clusterId, normalizeRow(item.proposal)); renderCluster();}});
$("annotation-coarser").addEventListener("click", () => {const row = state.drafts.get(state.selectedCluster); if (row) {row.rationale = ""; renderCluster(); $("annotation-label").focus();}});
$("annotation-unknown").addEventListener("click", () => {const row = state.drafts.get(state.selectedCluster); if (row) {row.label = "Unknown"; row.confidence = "low"; row.markers = []; row.rationale = ""; renderCluster(); $("annotation-rationale").focus();}});
$("annotation-cited-markers").addEventListener("click", () => {state.markerMode = "cited"; renderCluster();});
$("annotation-all-markers").addEventListener("click", () => {state.markerMode = "all"; renderCluster();});
for (const [id, action] of [["annotation-save", "revise"], ["annotation-approve", "approve"], ["annotation-reject", "reject"], ["run-undo-button", "undo"]]) $(id).addEventListener("click", () => decide(action));
$("strategy-json").addEventListener("input", () => {state.strategyDraftText = $("strategy-json").value; try {renderStrategyOperations(state.view.run.strategy_review.details, strategyDraft());} catch (_) {} updateStrategyDraftStatus(); buttons();});
for (const [id, action] of [["strategy-save", "revise"], ["strategy-approve", "approve"], ["strategy-reject", "reject"]]) $(id).addEventListener("click", () => decideStrategy(action));
$("strategy-approve-continue").addEventListener("click", () => decideStrategy("approve", true));
$("annotation-approve-continue").addEventListener("click", () => decide("approve", true));
$("suggestion-preview").addEventListener("click", loadSuggestion);
$("suggestion-approve").addEventListener("click", () => suggestionAction("approve", false, true));
for (const [id, action] of [["suggestion-request", "request"], ["suggestion-adopt", "adopt"], ["suggestion-discard", "discard"]]) $(id).addEventListener("click", () => suggestionAction(action));
$("suggestion-modify").addEventListener("click", () => suggestionAction("adopt", true));
$("suggestion-form").addEventListener("submit", event => event.preventDefault());
for (const id of ["annotation-decision-form", "strategy-decision-form", "run-undo-form"]) $(id).addEventListener("submit", event => event.preventDefault());
window.addEventListener("message", event => {
  if (event.origin === window.location.origin && event.source === $("run-qc-frame").contentWindow && event.data?.type === "scagentkit.qc-reviewed" && event.data.project_id === state.view?.run.project_id && !state.busy && !activeJob() && !dirty()) load();
});
window.addEventListener("pagehide", () => {stopPolling(); stopSuggestionPolling();});
window.addEventListener("pageshow", event => {if (event.persisted && state.view && !state.busy) {if (dirty()) {state.stale = true; state.awaitingFreshInspect = true; renderContinuation(); buttons();} else load();}});
load();
