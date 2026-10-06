"use strict";
const $ = id => document.getElementById(id);
const array = value => value == null ? [] : Array.isArray(value) ? value : [value];
const hash = value => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
const json = value => JSON.stringify(value, null, 2);
const state = {view: null, scopes: null, scopeProject: null, busy: false, stale: false, selection: new Set(), controls: [], pending: null, previewEdited: false, contextDraftHash: null};
function element(tag, text, attrs = {}) {const node = document.createElement(tag); if (text != null) node.textContent = String(text); for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, String(value)); return node;}
function message(text, error = false) {$("sub-message").textContent = text; $("sub-message").hidden = !text; $("sub-message").className = "banner " + (error ? "error" : "notice");}
function scopeQuery() {const query = new URLSearchParams(window.location.search || ""); if ([...query.keys()].some(key => !["child_id", "project_id"].includes(key))) throw new Error("Only registered project identities are accepted in this URL."); for (const key of ["child_id", "project_id"]) if (query.has(key) && (query.getAll(key).length !== 1 || !query.get(key) || query.get(key).length > 200 || /[\x00-\x1f\x7f]/.test(query.get(key)))) throw new Error("Open one registered project scope; the project URL is invalid."); const selected = {child_id: query.get("child_id"), project_id: query.get("project_id")}; if (selected.child_id && selected.project_id && selected.child_id !== selected.project_id) throw new Error("The selected child and project identities do not match."); if (state.scopeProject && (selected.child_id || selected.project_id || state.scopes?.parent?.project_id) !== state.scopeProject) throw new Error("The selected project URL changed; reopen its registered link."); return selected;}
function childID() {return scopeQuery().child_id;}
function viewURL(id) {return "/subclusters?child_id=" + encodeURIComponent(id) + "&project_id=" + encodeURIComponent(id);}
function reviewURL(id, child = true) {return "/review?" + (child ? "child_id=" + encodeURIComponent(id) + "&" : "") + "project_id=" + encodeURIComponent(id);}
function projectHeaders(headers = {}) {const selected = scopeQuery(), id = state.scopeProject || selected.child_id || state.view?.parent?.parent_project_id; return id ? {...headers, "X-ScAgentKit-Run-Project": id} : headers;}
async function loadScopes() {
  scopeQuery(); const response = await fetch("/api/run-review/scopes", {cache: "no-store"}), answer = await response.json();
  if (!response.ok) throw new Error(answer?.error || "The registered project list is unavailable.");
  const parent = answer?.parent, seen = new Set(); if (answer?.schema !== "scagentkit.run-scopes.workbench.v1" || typeof parent?.project_id !== "string" || !parent.project_id || !hash(parent.input_hash) || !Number.isInteger(parent.revision) || typeof parent.ready !== "boolean") throw new Error("The registered parent identity is unverified.");
  seen.add(parent.project_id); for (const item of array(answer.children)) if (typeof item?.project_id !== "string" || !item.project_id || seen.has(item.project_id) || Object.hasOwn(item, "project_dir")) throw new Error("The child registry is invalid."); else seen.add(item.project_id);
  const selected = scopeQuery(), id = selected.child_id || parent.project_id;
  if (!seen.has(id) || selected.project_id && selected.project_id !== id || selected.child_id === parent.project_id || state.scopes && state.scopes.parent.project_id !== parent.project_id) throw new Error("This URL does not select a registered parent or child.");
  state.scopes = answer; state.scopeProject = id;
}
function child() {return state.view?.child;}
function run() {return child()?.run;}
function applications() {return array(child()?.applications);}
function activeApplication() {const id = child()?.active_application_id, matches = applications().filter(item => item.application_id === id && item.active === true); return typeof id === "string" && matches.length === 1 ? matches[0] : null;}
function selectedCount() {return array(state.view?.parent?.clusters).filter(item => state.selection.has(item.clusterId)).reduce((sum, item) => sum + item.cell_count, 0);}
function unsafe(value) {if (value && typeof value === "object") return Object.entries(value).some(([key, item]) => ["code", "r_code", "script", "provider", "chat_fn", "api_key", "rscript", "project_dir", "library"].includes(key.toLowerCase()) || unsafe(item)); return false;}
function strategyDraft() {const text = $("sub-strategy").value.trim(); if (!text) return null; const value = JSON.parse(text); if (!value || Array.isArray(value) || value.schema !== "scagentkit.strategy.v1" || unsafe(value)) throw new Error("Supply only the complete supported typed child strategy, with no code or provider settings."); return value;}
function draftValid() {try {strategyDraft(); return true;} catch (_) {return false;}}
function creationChoices() {const value = {qc: $("sub-choice-qc").value, doublet: "keep", batch: $("sub-choice-batch").value, cycle: "none", reference: $("sub-choice-reference").value}; if (!["retain_selected", "review"].includes(value.qc) || !["none", "review"].includes(value.batch) || !["none", "inherit"].includes(value.reference)) throw new Error("Select supported explicit child policies."); return value;}
function choicesValid() {try {creationChoices(); return true;} catch (_) {return false;}}
function snapshotMatches() {const snapshot = child()?.apply_snapshot; return snapshot && !state.previewEdited && snapshot.column === $("sub-column").value.trim() && (snapshot.supersedes || "") === $("sub-supersedes").value && snapshot.outside === "NA";}
function childContext() {return run()?.child_context;}
function contextBindingMatches() {
  const edit = child()?.context_edit, current = run(), context = childContext(), parent = state.view?.parent, binding = edit?.binding;
  return edit?.enabled === true && ["annotation_propose", "annotation_apply"].includes(current?.stage) && !["complete", "running"].includes(current?.status) && binding?.project_id === current?.project_id && binding.input_hash === current?.input_hash &&
    binding.expected_revision === current?.revision && binding.expected_context_hash === context?.hash &&
    binding.parent_scope_hash === parent?.parent_scope_hash && binding.expected_parent_revision === parent?.expected_parent_revision;
}
function contextDraft() {
  const nullable = (id, limit, multiline = false) => {
    const text = $(id).value.trim();
    if ((multiline ? /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/ : /[\x00-\x1f\x7f]/).test(text)) throw new Error("Context text contains an unsupported control character.");
    let bytes; try {bytes = encodeURIComponent(text).replace(/%[A-Fa-f0-9]{2}|./g, "x").length;} catch (_) {throw new Error("Context text must be valid UTF-8.");}
    if (bytes > limit) throw new Error("Context text exceeds its UTF-8 byte limit: lineage/tissue 200, notes 2000.");
    return text || null;
  };
  const identity = $("sub-context-identity").value;
  if (!["labeled", "unknown", "mixed", "unreviewed"].includes(identity)) throw new Error("Choose a supported identity status for this hypothesis.");
  return {enabled: $("sub-context-enabled").checked, lineage_hint: nullable("sub-context-lineage", 200), identity_status: identity,
    tissue: nullable("sub-context-tissue", 200), notes: nullable("sub-context-notes", 2000, true)};
}
function contextDraftError() {try {contextDraft(); return null;} catch (error) {return error.message;}}
function contextDirty() {
  try {
    const draft = contextDraft(), saved = childContext()?.effective;
    return !saved || ["enabled", "lineage_hint", "identity_status", "tissue", "notes"].some(key => draft[key] !== saved[key]);
  } catch (_) {return true;}
}
function contextStatus() {
  const context = childContext(), edit = child()?.context_edit;
  if (!context) return;
  $("sub-context-status").textContent = !contextBindingMatches() ? edit?.reason || "Context is read-only at this saved stage. Correction is supported only at a stopped annotation step before application." :
    contextDraftError() || (contextDirty() ? "Unsaved annotation context. Save to create a new context generation and deactivate prior annotation decisions. The saved analysis and markers remain in place." : "This draft matches the saved annotation context; no correction is pending.");
}
function renderContext() {
  const context = childContext(); $("sub-context-panel").hidden = !context;
  if (!context) {state.contextDraftHash = null; return;}
  $("sub-context-heading").textContent = "Child annotation context · generation " + context.generation;
  if (state.contextDraftHash !== context.hash) {
    const value = context.effective;
    $("sub-context-enabled").checked = value.enabled; $("sub-context-lineage").value = value.lineage_hint || "";
    $("sub-context-identity").value = value.identity_status; $("sub-context-tissue").value = value.tissue || ""; $("sub-context-notes").value = value.notes || "";
    state.contextDraftHash = context.hash;
  }
  $("sub-context-summary").textContent = "Saved identity hypothesis: " + context.effective.identity_status + ". The frozen parent snapshot is provenance, not an independently validated label.";
  const binding = $("sub-context-binding"); binding.replaceChildren();
  for (const [key, value] of Object.entries({context_hash: context.hash, generation: context.generation, previous_hash: context.previous_hash, ...child()?.context_edit?.binding})) binding.append(element("span", key), element("code", value == null ? "Not supplied" : value));
  $("sub-context-parent").replaceChildren(raw(context.parent_snapshot)); contextStatus();
}
function buttons() {
  const ready = !!state.view && state.view.ready !== false && !state.busy && !state.stale && !state.pending;
  $("sub-refresh").disabled = state.busy;
  const editContextReady = ready && child()?.parent_current === true && contextBindingMatches();
  $("sub-context-save").disabled = !editContextReady || !!contextDraftError() || !contextDirty();
  for (const id of ["sub-context-enabled", "sub-context-lineage", "sub-context-identity", "sub-context-tissue", "sub-context-notes", "sub-context-reviewer", "sub-context-reason"]) $(id).disabled = !editContextReady;
  contextStatus();
  $("sub-create").disabled = !ready || !state.selection.size || selectedCount() < 21 || !draftValid() || !choicesValid();
  $("sub-cancel").disabled = state.busy; $("sub-apply-cancel").disabled = state.busy;
  $("sub-unknown").disabled = !ready || run()?.status !== "awaiting_configuration" || run()?.stage !== "annotation_propose" || child()?.parent_current !== true;
  $("sub-apply").disabled = !ready || run()?.status !== "complete" || child()?.parent_current !== true || !snapshotMatches();
  $("sub-undo").disabled = !ready || !activeApplication() || child()?.parent_current !== true;
  $("sub-retry").disabled = state.busy || !state.pending || !state.view;
  $("sub-clear-pending").disabled = state.busy || state.stale || !state.pending || !state.view;
  for (const control of state.controls) control.disabled = !ready;
  for (const id of ["sub-choice-qc", "sub-choice-batch", "sub-choice-reference", "sub-annotation-column", "sub-strategy", "sub-create-reviewer", "sub-create-reason", "sub-column", "sub-supersedes", "sub-apply-reviewer", "sub-apply-reason", "sub-unknown-reviewer", "sub-unknown-reason", "sub-undo-reviewer", "sub-undo-reason", "sub-undo-application"]) $(id).disabled = !ready;
  $("sub-pending-panel").hidden = !state.pending;
  $("sub-selection").textContent = `${state.selection.size} literal parent cluster(s), ${selectedCount()} selected cells. ${selectedCount() < 21 ? "The supported child graph requires at least 21 cells; settings will not be silently clipped." : "Create freezes this exact scope in R before review."}`;
}
function verify(answer) {
  const parent = answer?.parent;
  if (answer?.schema === "scagentkit.subcluster.workbench.v1" && answer.ready === false) {
    const run = answer.parent_run, selected = scopeQuery();
    if (typeof answer.csrf_token !== "string" || !answer.csrf_token || parent?.schema !== "scagentkit.subcluster.parent-waiting.v1" || run?.schema !== "scagentkit.run.v1" || !hash(run.input_hash) || !Number.isInteger(run.revision) || parent.parent_project_id !== run.project_id || selected.child_id || selected.project_id && selected.project_id !== run.project_id || state.scopeProject && state.scopeProject !== run.project_id) throw new Error("The pending parent workspace does not match this project.");
    return answer;
  }
  if (answer?.schema !== "scagentkit.subcluster.workbench.v1" || typeof answer.csrf_token !== "string" || !answer.csrf_token || parent?.schema !== "scagentkit.subcluster.parent.v1" || typeof parent.parent_project_id !== "string" || !parent.parent_project_id || !hash(parent.input_hash) || !hash(parent.parent_scope_hash) || !hash(parent.parent_output_hash) || !Number.isInteger(parent.expected_parent_revision) || parent.expected_parent_revision < 0 || !Number.isInteger(parent.total_cells)) throw new Error("The response does not contain a verified parent scope.");
  const labels = new Set(); let count = 0;
  for (const row of array(parent.clusters)) {if (typeof row.clusterId !== "string" || !row.clusterId || labels.has(row.clusterId) || !Number.isInteger(row.cell_count) || row.cell_count < 1) throw new Error("Parent literal cluster counts are invalid or duplicated."); labels.add(row.clusterId); count += row.cell_count;}
  if (!labels.size || count !== parent.total_cells) throw new Error("Parent cluster counts do not cover the saved parent cells.");
  const ids = new Set(); for (const item of array(answer.children)) {if (typeof item.project_id !== "string" || !item.project_id || ids.has(item.project_id) || Object.hasOwn(item, "project_dir")) throw new Error("Child registry has an invalid identity or exposes an execution path."); ids.add(item.project_id);}
  const selected = answer.child;
  if (selected != null) {
    const run = selected.run;
    if (selected.schema !== "scagentkit.subcluster.child.v1" || run?.schema !== "scagentkit.run.v1" || !ids.has(run.project_id) || !hash(run.input_hash) || !Number.isInteger(run.revision) || !Number.isInteger(selected.integration_revision) || typeof selected.parent_current !== "boolean" || selected.origin?.parent_project_id !== parent.parent_project_id || selected.origin?.parent_scope_hash !== parent.parent_scope_hash && selected.parent_current) throw new Error("Child scope does not match the registered parent binding.");
    if (childID() && run.project_id !== childID()) throw new Error("The response belongs to a different selected child.");
    const context = run.child_context, edit = selected.context_edit;
    if (context != null) {
      const fields = context.effective;
      if (context.schema !== "scagentkit.child-context.v1" || !Number.isInteger(context.generation) || context.generation < 0 || !hash(context.hash) ||
          (context.generation === 0 ? context.previous_hash != null : !hash(context.previous_hash)) || typeof fields?.enabled !== "boolean" ||
          !["labeled", "unknown", "mixed", "unreviewed"].includes(fields?.identity_status) || Object.keys(fields).length !== 5 || ["enabled", "lineage_hint", "identity_status", "tissue", "notes"].some(key => !Object.hasOwn(fields, key)) || ["lineage_hint", "tissue", "notes"].some(key => fields[key] != null && typeof fields[key] !== "string"))
        throw new Error("The child annotation context has an invalid schema or saved fingerprint.");
    }
    if (edit != null) {
      if (edit.schema !== "scagentkit.child-context-edit.v1" || typeof edit.enabled !== "boolean" || typeof edit.reason !== "string" ||
          (context ? edit.context_hash !== context.hash || edit.generation !== context.generation : edit.enabled)) throw new Error("The child context editing capability is unverified.");
      const binding = edit.binding;
      if (edit.enabled && (!context || !["annotation_propose", "annotation_apply"].includes(run.stage) || ["running", "complete"].includes(run.status) || selected.parent_current !== true || binding?.project_id !== run.project_id || binding.input_hash !== run.input_hash || binding.expected_revision !== run.revision ||
          binding.expected_context_hash !== context.hash || binding.parent_scope_hash !== parent.parent_scope_hash || binding.expected_parent_revision !== parent.expected_parent_revision))
        throw new Error("The child context correction binding is stale or belongs to a different scope.");
    }
    const snapshot = selected.apply_snapshot;
    if (snapshot != null && (snapshot.project_id !== run.project_id || snapshot.input_hash !== run.input_hash || snapshot.expected_revision !== run.revision || snapshot.parent_scope_hash !== parent.parent_scope_hash || snapshot.expected_parent_revision !== parent.expected_parent_revision || !hash(snapshot.annotation_hash) || !hash(snapshot.apply_hash) || typeof snapshot.column !== "string" || snapshot.outside !== "NA")) throw new Error("Writeback preview has stale or mismatched authority.");
  }
  if (state.view && state.view.parent.parent_project_id !== parent.parent_project_id) throw new Error("Configured parent identity changed; restart before reviewing.");
  const selectedScope = scopeQuery(); if (selectedScope.project_id && selectedScope.project_id !== (selectedScope.child_id || parent.parent_project_id) || state.scopes && parent.parent_project_id !== state.scopes.parent.project_id) throw new Error("The response does not match the selected service project.");
  return answer;
}
function storageKey() {return "scagentkit.subcluster.pending.v1:" + state.view.parent.parent_project_id + ":" + state.view.parent.input_hash + ":" + (childID() || "create");}
function persistPending() {try {if (state.pending) sessionStorage.setItem(storageKey(), json(state.pending)); else sessionStorage.removeItem(storageKey());} catch (_) {}}
function restorePending() {if (state.pending) return; try {const saved = JSON.parse(sessionStorage.getItem(storageKey()) || "null"); if (saved && typeof saved.action === "string" && typeof saved.request_id === "string") state.pending = saved;} catch (_) {}}
function raw(value) {return element("pre", json(value), {class: "qc-small-json"});}
function render() {
  const parent = state.view.parent;
  $("sub-workbench-link").hidden = false; $("sub-workbench-link").setAttribute("href", reviewURL(childID() || parent.parent_project_id, Boolean(childID())).replace(/^\/review\?/, "/workbench?"));
  $("sub-home").setAttribute("href", $("sub-workbench-link").getAttribute("href"));
  $("sub-header-review").hidden = false; $("sub-header-review").setAttribute("href", reviewURL(childID() || parent.parent_project_id, Boolean(childID())));
  $("sub-header-current").setAttribute("href", childID() ? "#sub-child-panel" : state.view.ready === false ? "#sub-waiting" : "#sub-create-panel");
  $("sub-current-scope").textContent = (childID() ? "Independent child · " + childID() + " · Parent " : "Parent project · ") + parent.parent_project_id + ". New child analysis and writeback require explicit reviewed scopes.";
  const parentId = parent.parent_project_id, link = $("sub-parent-review"); link.setAttribute("href", reviewURL(parentId, false));
  $("sub-scope-current").textContent = (childID() ? "Child workspace: " + childID() : "Parent workspace: " + parentId) + ". This tab keeps its own selected project; navigation does not stop saved tasks.";
  const nav = $("sub-scope-links"); nav.replaceChildren(element("a", "Parent review", {href: reviewURL(parentId, false), "data-scope-role": "parent"}));
  for (const item of array(state.scopes?.children || state.view.children)) nav.append(element("a", "Child: " + item.project_id, {href: viewURL(item.project_id), "data-child-id": item.project_id}));
  $("sub-waiting").hidden = state.view.ready !== false;
  if (state.view.ready === false) {$("sub-parent").textContent = `${parentId} · ${state.view.parent_run.status} / ${state.view.parent_run.stage} · revision ${state.view.parent_run.revision}`; $("sub-create-panel").hidden = true; $("sub-child-panel").hidden = true; $("sub-binding").replaceChildren(); $("sub-children").replaceChildren(element("p", "Finish the parent review before selecting a child scope.")); state.controls = []; renderContext(); buttons(); return;}
  $("sub-parent").textContent = `${parent.parent_project_id} · ${parent.context?.species || "species undeclared"} · ${parent.context?.tissue || "tissue undeclared"} · parent revision ${parent.expected_parent_revision}`;
  const binding = $("sub-binding"); binding.replaceChildren(); for (const [key, value] of Object.entries({parent_input: parent.input_hash, parent_scope: parent.parent_scope_hash, parent_output: parent.parent_output_hash, cluster_column: parent.cluster_column})) binding.append(element("span", key), element("code", value));
  $("sub-create-panel").hidden = !!childID(); state.controls = [];
  const clusters = $("sub-clusters"); clusters.replaceChildren();
  for (const item of array(parent.clusters)) {const label = element("label", null, {class: "sub-cluster-choice"}), input = element("input", null, {type: "checkbox", "data-cluster-id": item.clusterId}); input.checked = state.selection.has(item.clusterId); input.addEventListener("change", () => {if (input.checked) state.selection.add(item.clusterId); else state.selection.delete(item.clusterId); buttons();}); state.controls.push(input); label.append(input, element("span", `${item.clusterId} · ${item.cell_count} cells`)); clusters.append(label);}
  const list = $("sub-children"); list.replaceChildren();
  for (const item of array(state.view.children)) {const row = element("div", null, {class: "sub-child-row"}); row.append(element("span", `${item.project_id} · ${item.status} / ${item.stage} · revision ${item.revision}`), element("a", "Inspect child scope", {href: viewURL(item.project_id), "data-child-id": item.project_id})); list.append(row);}
  if (!array(state.view.children).length) list.append(element("p", "No child has been created for this parent in the configured workspace."));
  const selected = child(); $("sub-child-panel").hidden = !selected; renderContext();
  if (selected) {
    const current = run(); $("sub-child-status").textContent = `${current.project_id} · ${current.status} / ${current.stage} · child revision ${current.revision} · integration revision ${selected.integration_revision}`;
    $("sub-review-link").setAttribute("href", reviewURL(current.project_id)); $("sub-child-origin").replaceChildren(raw(selected.origin));
    $("sub-parent-current").textContent = selected.parent_current ? "The frozen parent binding is current." : "Parent binding changed. Writeback and undo are blocked: " + (selected.parent_error || "inspect the parent source and revision in R.");
    $("sub-unknown-panel").hidden = !(current.status === "awaiting_configuration" && current.stage === "annotation_propose");
    $("sub-apply-panel").hidden = current.status !== "complete";
    const snapshot = selected.apply_snapshot;
    $("sub-apply-summary").textContent = snapshot ? "Verified target " + snapshot.column + "; outside NA. Exact project, parent, annotation and application hashes are shown below. Refresh after changing the column or supersession." : "No applicable writeback snapshot is available; inspect saved approval, exact scope and any column conflict in R.";
    const receipts = $("sub-derived-receipts"); receipts.replaceChildren();
    for (const receipt of applications()) {const row = element("div", null, {class: "scope-derived-row", "data-application-id": receipt.application_id}); row.append(element("strong", "Derived parent · " + (receipt.active ? "active" : "historical")), element("p", "New annotation column: " + receipt.column + ". Original parent files and annotations remain saved.")); const output = receipt.output || receipt.path || receipt.output_path; if (output) row.append(element("code", typeof output === "string" ? output : json(output))); receipts.append(row);}
    if (!applications().length) receipts.append(element("p", "No derived parent output is saved for this child yet."));
    $("sub-applications").replaceChildren(raw({integration_revision: selected.integration_revision, apply_snapshot: snapshot, applications: selected.applications, undos: selected.undos, application: selected.application, undo: selected.undo}));
    const supersedes = $("sub-supersedes"), priorValue = supersedes.value; supersedes.replaceChildren(element("option", "New application; no supersession", {value: ""}));
    const active = activeApplication(); if (active) supersedes.append(element("option", active.application_id, {value: active.application_id})); supersedes.value = priorValue;
    const undo = $("sub-undo-application"); undo.replaceChildren(); if (active) undo.append(element("option", active.application_id, {value: active.application_id})); $("sub-undo-form").hidden = !active;
  }
  buttons();
}
function inspectURL() {const selected = scopeQuery(), id = selected.child_id, query = new URLSearchParams(); if (id) {query.set("child_id", id); query.set("column", $("sub-column").value.trim() || "sc_subtype"); if ($("sub-supersedes").value) query.set("supersedes", $("sub-supersedes").value);} if (selected.project_id) query.set("project_id", selected.project_id); return "/api/subcluster/inspect" + (query.size ? "?" + query.toString() : "");}
async function request(payload) {const response = await fetch(payload ? "/api/subcluster/operation" : inspectURL(), payload ? {method: "POST", headers: projectHeaders({"Content-Type": "application/json", "X-ScAgentKit-Subcluster-Token": state.view.csrf_token}), body: json(payload)} : {cache: "no-store", headers: projectHeaders()}); const answer = await response.json(); if (!response.ok) throw new Error(answer?.error || "The local subanalysis operation failed."); return verify(answer);}
async function load() {state.busy = true; buttons(); try {if (!state.view || state.scopes) await loadScopes(); state.view = await request(); state.stale = false; state.previewEdited = false; if (state.view.ready !== false) restorePending(); for (const id of [...state.selection]) if (!array(state.view.parent.clusters).some(row => row.clusterId === id)) state.selection.delete(id); render(); message("");} catch (error) {state.stale = true; message(error.message + " Refresh a verified saved scope before submitting a new operation.", true);} finally {state.busy = false; buttons();}}
function reviewFields(action) {return {action, reviewer: $("sub-" + action + "-reviewer").value.trim(), reason: $("sub-" + action + "-reason").value.trim(), request_id: crypto.randomUUID()};}
function childFields() {return {child_id: run().project_id, project_id: run().project_id, input_hash: run().input_hash, expected_revision: run().revision};}
function confirmedContextReceipt(answer, payload) {
  const selected = answer.child, current = selected?.run, context = current?.child_context, receipt = selected?.context_receipt;
  const edits = receipt?.context, keys = Object.keys(payload.context || {}).sort();
  if (receipt?.schema !== "scagentkit.child-context-receipt.v1" || receipt.action !== "context" || receipt.outcome !== "committed" ||
      receipt.request_id !== payload.request_id || receipt.project_id !== payload.project_id || receipt.project_id !== payload.child_id ||
      current?.project_id !== payload.project_id || receipt.input_hash !== payload.input_hash || current.input_hash !== payload.input_hash ||
      receipt.expected_revision !== payload.expected_revision || receipt.parent_scope_hash !== payload.parent_scope_hash ||
      receipt.expected_parent_revision !== payload.expected_parent_revision || receipt.previous_context_hash !== payload.expected_context_hash ||
      receipt.reviewer !== payload.reviewer || receipt.reason !== payload.reason || !hash(receipt.request_hash) || !hash(receipt.payload_sha256) ||
      !hash(receipt.journal_event_hash) || !hash(receipt.context_hash) || receipt.context_hash === receipt.previous_context_hash ||
      !Number.isInteger(receipt.generation) || receipt.generation < 1 || !Number.isInteger(receipt.committed_revision) ||
      receipt.committed_revision <= payload.expected_revision || current.revision < receipt.committed_revision ||
      !context || context.generation < receipt.generation || typeof receipt.is_current !== "boolean" ||
      receipt.is_current !== (context.hash === receipt.context_hash) ||
      (context.generation === receipt.generation && (!receipt.is_current || context.hash !== receipt.context_hash)) ||
      (context.generation > receipt.generation && (receipt.is_current || current.revision <= receipt.committed_revision)) ||
      !edits || Array.isArray(edits) || json(Object.keys(edits).sort()) !== json(keys) || keys.some(key => edits[key] !== payload.context[key]) ||
      (receipt.is_current && (context.previous_hash !== payload.expected_context_hash || keys.some(key => context.effective[key] !== payload.context[key]))))
    throw new Error("The saved child context receipt does not confirm this exact correction. Inspect the durable request record before clearing its draft.");
  return receipt;
}
function contextSavedMessage(answer) {
  const receipt = answer.child.context_receipt, context = answer.child.run.child_context;
  if (!receipt.is_current) return "This exact correction was already saved at generation " + receipt.generation + ". The current child context is the newer generation " + context.generation + "; this acknowledgment does not replace newer context or decisions. No new model request was made.";
  if (answer.child.run.revision > receipt.committed_revision) return "This exact correction was already saved at generation " + receipt.generation + ". The context is still current, but the workflow has advanced to revision " + answer.child.run.revision + "; this acknowledgment does not replace newer context or decisions. Inspect the saved current annotation state. No new model request was made.";
  return "Child context correction saved as generation " + receipt.generation + ". Previous annotation proposals, approvals and transfer consents are inactive. Saved analysis and markers are reused; no model request was made. Open the child Review for a new annotation proposal.";
}
function savedDestination(answer, payload) {
  if (!["create", "apply", "context"].includes(payload.action)) return null;
  const parent = answer.parent, selected = answer.child;
  if (parent.parent_scope_hash !== payload.parent_scope_hash || parent.expected_parent_revision !== payload.expected_parent_revision || selected?.parent_current !== true)
    throw new Error("The saved operation has a different parent binding. Inspect its receipt before navigating.");
  if (payload.action === "context") {confirmedContextReceipt(answer, payload); return null;}
  if (payload.action === "create") {
    if (json(array(selected.origin?.selected_clusters)) !== json(payload.clusters))
      throw new Error("The saved child selection differs from these literal clusters. Inspect the saved scope before navigating.");
    return reviewURL(selected.run.project_id);
  }
  const receipt = array(selected.applications).find(item => item.application_id === selected.active_application_id && item.active === true && item.request_id === payload.request_id);
  if (selected.run.project_id !== payload.child_id || !receipt || receipt.status !== "applied" || receipt.child_project_id !== payload.child_id || receipt.parent_project_id !== parent.parent_project_id ||
      receipt.child_input_hash !== payload.input_hash || receipt.child_revision !== payload.expected_revision || receipt.parent_input_hash !== parent.input_hash ||
      receipt.parent_scope_hash !== payload.parent_scope_hash || receipt.parent_revision !== payload.expected_parent_revision || receipt.parent_output_sha256 !== parent.parent_output_hash ||
      receipt.apply_hash !== payload.apply_hash || receipt.annotation_hash !== payload.annotation_hash || receipt.column !== payload.column || receipt.outside !== payload.outside || !hash(receipt.output_sha256))
    throw new Error("The derived output receipt does not match this exact approval. Inspect the saved scope before navigating.");
  return reviewURL(parent.parent_project_id, false) + "#run-derived-details";
}
async function operate(payload) {
  if (state.busy || !state.view) return;
  state.pending = payload; persistPending(); state.busy = true; buttons();
  try {const answer = await request(payload), destination = savedDestination(answer, payload); state.pending = null; persistPending(); state.view = answer; state.stale = false; state.previewEdited = false; render(); message(payload.action === "context" ? contextSavedMessage(answer) : "Saved " + payload.action + " operation. Inspect the exact child review or derived output receipt before the next decision."); if (destination) window.location.assign(destination);}
  catch (error) {state.stale = true; message(error.message + " The exact request is retained. Refresh to inspect, then retry this saved operation if its response was lost.", true);}
  finally {state.busy = false; buttons();}
}
async function createChild() {if ($("sub-create").disabled || !$("sub-create-form").reportValidity()) return; const proposal = strategyDraft(), payload = {...reviewFields("create"), parent_scope_hash: state.view.parent.parent_scope_hash, expected_parent_revision: state.view.parent.expected_parent_revision, clusters: [...state.selection], annotation_column: $("sub-annotation-column").value.trim(), choices: creationChoices()}; if (proposal) payload.strategy_proposal = proposal; await operate(payload);}
async function saveContext() {
  if ($("sub-context-save").disabled || !$("sub-context-form").reportValidity() || !contextBindingMatches()) return;
  const binding = child().context_edit.binding;
  await operate({...reviewFields("context"), ...childFields(), expected_context_hash: binding.expected_context_hash,
    parent_scope_hash: binding.parent_scope_hash, expected_parent_revision: binding.expected_parent_revision, context: contextDraft()});
}
async function unknown() {if ($("sub-unknown").disabled || !$("sub-unknown-form").reportValidity()) return; await operate({...reviewFields("unknown"), ...childFields()});}
async function apply() {if ($("sub-apply").disabled || !$("sub-apply-form").reportValidity()) return; const snapshot = child().apply_snapshot, keys = ["project_id", "input_hash", "expected_revision", "parent_scope_hash", "expected_parent_revision", "annotation_hash", "apply_hash", "column", "outside", "supersedes"], payload = {...reviewFields("apply"), child_id: run().project_id}; for (const key of keys) if (snapshot[key] != null) payload[key] = snapshot[key]; await operate(payload);}
async function undo() {if ($("sub-undo").disabled || !$("sub-undo-form").reportValidity()) return; await operate({...reviewFields("undo"), ...childFields(), application_id: activeApplication().application_id, integration_revision: child().integration_revision});}
function cancelSelection() {if (state.busy) return; state.selection.clear(); $("sub-strategy").value = ""; $("sub-choice-qc").value = "retain_selected"; $("sub-choice-batch").value = "none"; $("sub-choice-reference").value = "none"; render(); message("Selection draft cleared. No child or saved project was changed.");}
function cancelApply() {if (state.busy) return; $("sub-column").value = child()?.apply_snapshot?.column || "sc_subtype"; $("sub-supersedes").value = child()?.apply_snapshot?.supersedes || ""; state.previewEdited = false; $("sub-apply-reason").value = ""; buttons(); message("Writeback draft cleared. No derived object or parent file was changed.");}
function clearPending() {if ($("sub-clear-pending").disabled) return; state.pending = null; persistPending(); buttons(); message("Saved request draft cleared after inspection. Any already committed child or application remains in the saved history.");}
$("sub-refresh").addEventListener("click", load); $("sub-create").addEventListener("click", createChild); $("sub-unknown").addEventListener("click", unknown); $("sub-apply").addEventListener("click", apply); $("sub-undo").addEventListener("click", undo); $("sub-cancel").addEventListener("click", cancelSelection); $("sub-apply-cancel").addEventListener("click", cancelApply); $("sub-retry").addEventListener("click", () => {if (state.pending) operate(state.pending);});
$("sub-clear-pending").addEventListener("click", clearPending);
$("sub-context-save").addEventListener("click", saveContext);
for (const id of ["sub-context-enabled", "sub-context-lineage", "sub-context-identity", "sub-context-tissue", "sub-context-notes"]) $(id).addEventListener("input", buttons);
$("sub-strategy").addEventListener("input", buttons); for (const id of ["sub-column", "sub-supersedes"]) $(id).addEventListener("input", () => {state.previewEdited = true; buttons();});
for (const id of ["sub-choice-qc", "sub-choice-batch", "sub-choice-reference"]) $(id).addEventListener("change", buttons);
for (const id of ["sub-create-form", "sub-unknown-form", "sub-apply-form", "sub-undo-form", "sub-context-form"]) $(id).addEventListener("submit", event => event.preventDefault());
load();
