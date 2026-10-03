"use strict";

const $ = id => document.getElementById(id);
const palette = ["#759bd1", "#e4a675", "#73b3aa", "#9881c8", "#ce899d", "#9bad6e", "#3d67d7", "#bc9b5e", "#799da6"];
const state = { evidence: null, session: null, clusterId: "6", tab: "models", busy: false, showAll: false, undoTarget: null, historyAll: false, directed: null, directedBusy: false, directedToken: 0, draftReference: null };
const node = (tag, attrs = {}, text = null) => {
  const n = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === "class") n.className = value;
    else if (key.startsWith("on")) n.addEventListener(key.slice(2), value);
    else n.setAttribute(key, String(value));
  }
  if (text !== null && text !== undefined) n.textContent = String(text);
  return n;
};
const pill = (text, tone = "muted") => node("span", { class: `pill ${tone}` }, text);
const number = value => Number(value).toLocaleString("en-US");
const short = revision => String(revision || "").slice(0, 14);
const chosenCluster = () => state.evidence?.clusters.find(c => String(c.id) === state.clusterId);
const eventId = event => event.id || event.eventId;
const eventScope = event => event.scope || {};
const eventLabel = event => event.label ?? event.decision?.label ?? "";
const eventStatus = event => event.status ?? event.decision?.status ?? "proposed";
const currentDimension = () => $("dimension").value;
const decisions = () => state.session?.decisions || [];
const latestDecision = (clusterId, dimension = currentDimension()) => {
  const scoped = decisions().filter(d => String(eventScope(d).clusterId) === String(clusterId) && eventScope(d).dimension === dimension && !d.undone);
  return scoped.filter(d => eventScope(d).revision === state.evidence?.revision).at(-1) || scoped.at(-1);
};

function message(text, kind = "notice") {
  const target = $(kind === "error" ? "error-banner" : "notice");
  target.textContent = text;
  target.hidden = false;
  $(kind === "error" ? "notice" : "error-banner").hidden = true;
}
async function request(path, body) {
  const response = await fetch(path, body === undefined ? { cache: "no-store" } : {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body)
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || data.message || `Request failed (${response.status}).`);
  return data;
}
async function importFileText(text) {
  // Preserve the file bytes for the backend's strict duplicate-key parser.
  const response = await fetch("/api/import", { method: "POST", headers: { "Content-Type": "application/json" }, body: text });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || `Import failed (${response.status}).`);
  return data;
}
async function exportFileText() {
  const response=await fetch("/api/export",{cache:"no-store"});
  const text=await response.text();
  if(!response.ok){let data;try{data=JSON.parse(text);}catch{}throw new Error(data?.error || `Export failed (${response.status}).`);}
  return text;
}
function setBusy(busy) {
  state.busy = busy;
  const readOnly = !state.evidence || state.session?.readOnly;
  for (const id of ["save-decision", "retain-unknown", "confirm-undo"]) $(id).disabled = busy || readOnly;
  for (const id of ["export-session", "import-session", "refresh-evidence"]) $(id).disabled = busy;
  for (const control of document.querySelectorAll('[data-testid="directed-execute"], [data-testid="directed-adopt"], [data-testid="directed-unresolved"]')) {
    control.disabled = busy || readOnly || (control.dataset.testid === "directed-execute" ? !state.directed?.execution?.available : !state.directed?.artifact);
  }
  $("save-decision").textContent = busy ? "Saving…" : "Record decision";
}

async function load(refresh = false) {
  setBusy(true);
  try {
    const previousRevision = state.evidence?.revision;
    state.evidence = await request("/api/evidence");
    state.session = await request("/api/session");
    const revisionChanged = previousRevision && previousRevision !== state.evidence.revision;
    const referenceChanged = state.draftReference && !state.evidence.directedArtifacts?.[state.draftReference.id];
    state.directed = null; state.directedToken++;
    if (revisionChanged || referenceChanged) {
      $("label").value = ""; $("reason").value = ""; $("review-status").value = "proposed";
      state.draftReference = null;
    }
    if (!chosenCluster()) state.clusterId = String(state.evidence.clusters[0].id);
    renderOverview(); renderSelection();
    if (state.session.readOnly) message(`Session is read only: ${state.session.integrityError || "history integrity could not be verified"}. Original history has been preserved.`, "error");
    else if (refresh) message(revisionChanged || referenceChanged ? "Evidence fingerprint changed. The unsaved draft was cleared; review the new evidence before making a decision. Old decisions remain marked stale." : "Evidence refreshed from local files. Old decisions remain in history; a changed fingerprint marks them stale.");
  } catch (error) {
    state.evidence = null;
    state.directed = null; state.draftReference = null; state.directedToken++;
    $("label").value = ""; $("reason").value = ""; $("review-status").value = "proposed";
    message(`Cannot load verified evidence: ${error.message} Decisions are disabled until the input is valid.`, "error");
  } finally { setBusy(false); }
}

function renderOverview() {
  const { dataset, summary, revision, sources, limitations } = state.evidence;
  $("retained-count").textContent = number(dataset.retainedCells);
  $("input-count").textContent = `${number(dataset.inputCells)} input · ${number(dataset.inputCells - dataset.retainedCells)} excluded by QC`;
  $("cluster-count").textContent = number(dataset.clusterCount);
  $("strict-count").textContent = `${summary.strictValid} / ${summary.modelCalls}`;
  $("call-count").textContent = "2 models × 2 reference conditions";
  $("failure-count").textContent = number(summary.formatRejected + summary.networkFailed);
  $("failure-detail").textContent = `${summary.formatRejected} format rejected · ${summary.networkFailed} transport failed`;
  $("revision").textContent = short(revision); $("revision").title = revision;
  const sourceContent = $("source-content"); sourceContent.replaceChildren();
  sourceContent.append(node("h3", {}, "Frozen run evidence & limits"));
  sourceContent.append(node("p", { class: "evidence-explainer" }, "Marker and model views read local frozen results. Directed evidence can execute a reviewed, read-only RNA summary plan from an explicitly configured Seurat object; it performs no new normalization, clustering or provider request. The evidence revision hashes the actual source bytes; paths alone do not define a revision."));
  const limits = node("ul", { class: "limits" });
  for (const limitation of limitations || []) limits.append(node("li", {}, limitation));
  sourceContent.append(limits);
  const list = node("ul", { class: "sources-list" });
  for (const source of sources || []) {
    const li = node("li", {}, source.id || source.file || source.name);
    li.append(node("code", {}, `SHA-256 ${source.sha256}`)); list.append(li);
  }
  sourceContent.append(list);
}

function selectCluster(id) {
  if (state.busy || !state.evidence) return;
  state.clusterId = String(id);
  state.directed = null; state.draftReference = null; state.directedToken++;
  $("label").value = ""; $("reason").value = "";
  $("notice").hidden = true;
  renderSelection();
}
function renderSelection() {
  const cluster = chosenCluster(); if (!cluster) return;
  $("selection-title").textContent = `Cluster ${cluster.id}`;
  $("cell-count").textContent = `${number(cluster.cellCount)} cells`;
  $("cluster-issue").textContent = cluster.id === "6" || String(cluster.id) === "6" ? "CD8 / NK disagreement" : (cluster.issueKinds?.length ? "Needs evidence review" : "Inspect evidence");
  $("cluster-issue").className = `pill ${String(cluster.id) === "6" ? "amber" : "muted"}`;
  renderClusterList(); renderUmap(); renderDecision(); renderEvidence();
}
function renderClusterList() {
  const list = $("cluster-list"); list.replaceChildren();
  let reviewed = 0;
  for (const [i, cluster] of state.evidence.clusters.entries()) {
    const d = latestDecision(cluster.id, "type");
    if (d && !d.stale && ["reviewed", "accepted"].includes(eventStatus(d))) reviewed++;
    const button = node("button", { class: `cluster-button ${String(cluster.id) === state.clusterId ? "selected" : ""}`, "data-testid": `cluster-${cluster.id}`, "data-cluster": cluster.id, "aria-pressed": String(cluster.id) === state.clusterId, onclick: () => selectCluster(cluster.id) });
    const dot = node("i", { class: "cluster-dot" }); dot.style.background = palette[i % palette.length];
    button.append(dot, node("span", { class: "cluster-name" }, `Cluster ${cluster.id}`), node("span", { class: "count" }, number(cluster.cellCount)));
    button.append(node("span", { class: "cluster-meta" }, d ? (d.stale ? "Stale decision" : `${eventStatus(d)} · ${eventLabel(d)}`) : (String(cluster.id) === "6" ? "Priority · CD8 / NK" : "No decision")));
    list.append(button);
  }
  $("review-progress").textContent = `${reviewed} reviewed`;
}
function renderUmap() {
  if (!state.evidence) return;
  const points = state.evidence.umap;
  const xs = points.map(p => p.x), ys = points.map(p => p.y);
  const bounds = { x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys) };
  const width = 640, height = 350, pad = 38;
  const scaleX = x => pad + 9 + (x - bounds.x0) / (bounds.x1 - bounds.x0 || 1) * (width - pad * 2 - 18);
  const scaleY = y => height - pad - 8 - (y - bounds.y0) / (bounds.y1 - bounds.y0 || 1) * (height - pad * 2 - 10);
  const ns = "http://www.w3.org/2000/svg";
  const svgNode = (tag, attrs, text) => { const n = document.createElementNS(ns, tag); for (const [k,v] of Object.entries(attrs)) n.setAttribute(k,v); if (text) n.textContent = text; return n; };
  const svg = svgNode("svg", { viewBox: `0 0 ${width} ${height}`, role: "img", "aria-label": `Real UMAP: ${points.length} retained cells, cluster ${state.clusterId} selected` });
  svg.append(svgNode("title", {}, `PBMC3k frozen UMAP, ${points.length} retained cells`));
  svg.append(svgNode("line", { x1: pad, y1: height-pad, x2: width-pad, y2: height-pad, class: "umap-axis" }), svgNode("line", { x1: pad, y1: pad, x2: pad, y2: height-pad, class: "umap-axis" }));
  svg.append(svgNode("text", { x: width/2, y: height-8, "text-anchor": "middle", class: "umap-axis-text" }, "UMAP 1"), svgNode("text", { x: 12, y: height/2, transform: `rotate(-90 12 ${height/2})`, "text-anchor": "middle", class: "umap-axis-text" }, "UMAP 2"));
  const colors = new Map(state.evidence.clusters.map((c,i) => [String(c.id), palette[i % palette.length]]));
  for (const p of [...points].sort((a,b) => Number(String(a.clusterId) === state.clusterId) - Number(String(b.clusterId) === state.clusterId))) {
    const selected = String(p.clusterId) === state.clusterId;
    const circle = svgNode("circle", { cx: scaleX(p.x), cy: scaleY(p.y), r: selected ? 2.05 : 1.6, fill: selected || state.showAll ? colors.get(String(p.clusterId)) : "#dce2ed", opacity: selected ? .9 : .72, class: "umap-point", "data-cluster": p.clusterId, "data-cell-id": p.cellId });
    circle.append(svgNode("title", {}, `${p.cellId} · cluster ${p.clusterId}`));
    circle.addEventListener("click", () => selectCluster(p.clusterId)); svg.append(circle);
  }
  $("umap-chart").replaceChildren(svg);
  $("umap-legend").replaceChildren();
  for (const [id,color] of colors) {
    const item = node("span"); const dot = node("i"); dot.style.background = color;
    item.append(dot, node("span", {}, `C${id}`)); $("umap-legend").append(item);
  }
}

function renderDecision() {
  const c = chosenCluster(); if (!c) return;
  const dimension = currentDimension(), d = latestDecision(c.id, dimension);
  const current = $("current-decision"); current.replaceChildren();
  $("decision-badge").textContent = d ? (d.stale ? "Stale decision" : eventStatus(d)) : "No decision";
  $("decision-badge").className = `pill ${d?.stale ? "amber" : d ? "blue" : "muted"}`;
  if (d) {
    current.append(node("strong", {}, eventLabel(d)), node("span", {}, d.stale ? " · Previous evidence revision. Review again before reuse." : " · Latest active decision for this dimension."));
  } else current.append(node("span", {}, "No human decision recorded for this dimension. A failed model result is a separate condition."));
  const scope = $("scope-summary"); scope.replaceChildren();
  scope.append(node("strong", {}, `Scope: ${state.evidence.dataset.id} · Cluster ${c.id} · ${dimension}`), node("br"), node("span", {}, `${c.cellCount} exact cell IDs · evidence `), node("code", {}, short(state.evidence.revision)));
  if (state.draftReference) scope.append(node("div", {class:"reference-note"}, `Directed evidence capsule ${short(state.draftReference.id)} will be retained with this decision.`));
  const stale = decisions().filter(d => d.stale).length;
  if (stale) scope.append(node("div", { class: "stale-warning" }, `${stale} decision(s) belong to earlier evidence and are marked stale.`));
  if (state.session?.readOnly) current.append(node("p", { class: "session-integrity" }, "Read only: session integrity failed."));
  $("history-count").textContent = state.session.events.length;
  setBusy(state.busy);
}
function chooseLabel(label, source) {
  if (!state.evidence) { message("Evidence is unavailable. Refresh valid local inputs before choosing a label.", "error"); return; }
  if (state.session?.readOnly || state.busy) return;
  state.draftReference = null;
  $("dimension").value = "type"; $("label").value = label;
  renderDecision(); $("reason").focus();
  message(`“${label}” selected from ${source}. Add your reason and record a decision to save it.`);
}
function renderEvidence() {
  if (!state.evidence) return;
  for (const tab of document.querySelectorAll("[data-tab]")) tab.setAttribute("aria-selected", tab.dataset.tab === state.tab);
  $("evidence-content").setAttribute("aria-labelledby", `evidence-${state.tab}`);
  $("evidence-content").replaceChildren();
  if (state.tab === "models") renderModels();
  else if (state.tab === "database") renderDatabase();
  else if (state.tab === "markers") renderMarkers();
  else if (state.tab === "directed") renderDirected();
  else renderHistory();
}
function renderModels() {
  const target = $("evidence-content");
  target.append(node("p", { class: "evidence-explainer" }, "Guided sees database candidates; independent does not. These are cached single-call outputs, not an ensemble or a truth standard. Strict interpretation and posthoc normalization remain separate."));
  const issues = node("div", { class: "issue-row" });
  for (const issue of chosenCluster().issueKinds || []) issues.append(pill(String(issue).replaceAll("_", " "), String(issue).includes("biological") ? "amber" : "muted"));
  target.append(issues);
  target.append(node("button", {type:"button", class:"button quiet", onclick:()=>{state.tab="directed";renderEvidence();}}, "Review disagreement → local directed evidence"));
  const grid = node("div", { class: "model-grid" });
  for (const model of chosenCluster().models) {
    const card = node("article", { class: "model-card", "data-testid": `model-card-${model.callId}` });
    const strict = model.strict || {}, posthoc = model.posthoc || {};
    const status = strict.status || model.strictStatus;
    const valid = status === "valid";
    const header = node("div", { class: "model-card-header" });
    const h = node("h4", {}, model.provider === "deepseek" ? "DeepSeek Flash" : model.provider === "grok" ? "Grok 4.20" : model.provider);
    h.append(node("span", { class: "mode-tag" }, model.mode));
    header.append(h, pill(valid ? "Strict valid" : status === "network_failed" ? "Transport failed" : "Format rejected", valid ? "green" : "red")); card.append(header);
    if (valid) {
      card.append(node("div", { class: "result-label" }, strict.label || "Unknown output"));
      const facts = node("div", { class: "model-facts" });
      if (strict.confidence) facts.append(pill(`Model confidence: ${strict.confidence}`));
      if (strict.broadLabel) facts.append(pill(`Broad: ${strict.broadLabel}`));
      card.append(facts);
      if (strict.reasoning) card.append(node("p", { class: "reasoning" }, strict.reasoning));
      if (strict.supportingMarkers?.length) card.append(node("p", {}, `Supporting markers: ${Array.isArray(strict.supportingMarkers) ? strict.supportingMarkers.join(", ") : strict.supportingMarkers}`));
      if (strict.contradictingMarkers?.length) card.append(node("p", {}, `Contradicting markers: ${Array.isArray(strict.contradictingMarkers) ? strict.contradictingMarkers.join(", ") : strict.contradictingMarkers}`));
      if (strict.mappingStatus || strict.fineMappingStatus) card.append(node("p", { class: "source-note" }, `Dictionary: ${strict.mappingStatus || "—"} · granularity: ${strict.fineMappingStatus || "—"}`));
    } else {
      card.append(node("div", { class: "failure-box" }, status === "network_failed" ? "No usable response was received. This is a transport failure, not a biological prediction of unknown." : `The response failed the strict output contract. ${strict.formatReason || "Inspect the original response below."} This is not a human unknown decision.`));
    }
    const post = node("div", { class: "posthoc" });
    post.append(node("strong", {}, "POSTHOC · separate interpretation"), node("span", {}, posthoc.label ? `${posthoc.label}${posthoc.normalizationApplied ? " · normalization applied" : " · unchanged"}` : "No usable posthoc label"));
    if (posthoc.normalizationReason) post.append(node("div", {}, posthoc.normalizationReason));
    card.append(post);
    const details = node("details");
    details.append(node("summary", {}, "Inspect original response · plain text"), node("pre", { class: "raw-text" }, model.rawText || "No response body saved."));
    card.append(details, node("div", { class: "source-note" }, `Source: ${typeof model.source === "string" ? model.source : model.source?.id || model.callId}`));
    if (valid && strict.label) card.append(node("button", { type: "button", class: "button link", onclick: () => chooseLabel(strict.label, `${model.provider} ${model.mode}`) }, "Use strict label →"));
    else if (posthoc.label && posthoc.label !== "unknown") card.append(node("button", { type: "button", class: "button link", onclick: () => chooseLabel(posthoc.label, "posthoc interpretation") }, "Use posthoc label →"));
    grid.append(card);
  }
  target.append(grid);
}
function makeTable(headers) {
  const table = node("table"); const row = node("tr");
  for (const h of headers) row.append(node("th", { scope: "col" }, h));
  const head = node("thead"); head.append(row); const body = node("tbody"); table.append(head,body);
  const wrap = node("div", { class: "table-wrap" }); wrap.append(table); return { wrap, body };
}
function renderDatabase() {
  const target = $("evidence-content");
  target.append(node("p", { class: "markers-note" }, "Database overlap produces candidates, not validated identities. A single shared marker or a small reference set can rank highly. Candidate names may differ in lineage, subtype, state, or granularity; inspect the actual overlaps before choosing."));
  const {wrap,body} = makeTable(["Rank / candidate", "Score", "Overlap", "Reference genes", "Matched markers", "Action"]);
  for (const c of chosenCluster().candidates || []) {
    const tr = node("tr", { "data-testid": "candidate-row" });
    const label = node("td", { class: "candidate-label" }); label.append(node("strong", {}, `${c.rank}. ${c.label}`), node("div", { class: "source-note" }, `Source: ${c.source}`));
    tr.append(label,node("td", {class:"number"},formatValue(c.score)),node("td",{class:"number"},c.overlap),node("td",{class:"number"},c.referenceSize),node("td",{},Array.isArray(c.markers) ? c.markers.join(", ") : c.markers));
    const action = node("td"); action.append(node("button", {class:"button quiet small",onclick:()=>chooseLabel(c.label,"database candidate")},"Choose"));tr.append(action);body.append(tr);
  }
  target.append(wrap);
}
function formatValue(value, digits = 3) { if (value === null || value === undefined || value === "") return "—"; const n=Number(value); return Number.isFinite(n) ? n.toFixed(digits) : String(value); }
function percentage(value) { return value===null || value===undefined ? "—" : formatValue(value*100,1); }
function renderMarkers() {
  const target = $("evidence-content");
  target.append(node("p", { class: "markers-note" }, `Showing ${chosenCluster().markers.length} filtered markers (up to 30), not the full expression matrix. An absent gene here does not mean it was not expressed. pct.1 = detected fraction in this cluster; pct.2 = detected fraction outside it. log2FC and adjusted p values come from the frozen Seurat marker result.`));
  const {wrap,body} = makeTable(["Gene", "avg log2FC", "pct.1", "pct.2", "Δ detection", "Adjusted p", "Source"]);
  for (const m of chosenCluster().markers || []) {
    const tr = node("tr", { "data-testid":"marker-row" });
    const gene = node("td"); gene.append(node("strong",{},m.gene));tr.append(gene);
    for (const v of [m.avgLog2FC,m.pct1,m.pct2,m.pctDiff]) tr.append(node("td",{class:"number"},formatValue(v)));
    tr.append(node("td",{class:"number"},m.pAdj === 0 ? "0 (numerical)" : Number(m.pAdj).toExponential(2)),node("td",{class:"source-note"},m.source));body.append(tr);
  }
  target.append(wrap);
}
function detail(title, value) {
  const result=node("details",{class:"directed-details"});
  result.append(node("summary",{},title),node("pre",{class:"raw-text"},JSON.stringify(value,null,2)));
  return result;
}
function explanationList(title, entries) {
  const block=node("div",{class:"explanation-block"});block.append(node("h4",{},title));
  const list=node("ul");
  for(const entry of entries || []) {
    let text=entry.reason || entry.kind || entry.gene || String(entry);
    if(entry.gene && entry.reason)text=`${entry.gene}: ${text}`;
    if(entry.lineage) text=`${entry.lineage}: ${entry.positiveCells}/${entry.totalCells} cells (${formatValue(entry.fraction*100,1)}%) with the observed program.`;
    list.append(node("li",{},text));
  }
  if(!list.children.length)list.append(node("li",{},"No entry recorded."));block.append(list);return block;
}
async function fetchDirected() {
  const clusterId=state.clusterId,token=++state.directedToken;
  state.directedBusy=true;
  try {
    const data=await request(`/api/directed?clusterId=${encodeURIComponent(clusterId)}`);
    if(token!==state.directedToken || clusterId!==state.clusterId)return;
    state.directed=data;
  } catch(error) {
    if(token!==state.directedToken)return;
    state.directed={clusterId,error:error.message};
  } finally {
    if(token===state.directedToken){state.directedBusy=false;if(state.tab==="directed")renderEvidence();}
  }
}
function fillDirected(label) {
  const artifact=state.directed?.artifact;
  if(state.busy || state.session?.readOnly || !artifact)return;
  $("dimension").value="type";$("review-status").value="proposed";$("label").value=label;
  state.draftReference={kind:artifact.kind,id:artifact.id,sha256:artifact.sha256};
  renderDecision();$("reason").focus();
  message(`Draft prepared: ${label}. Add your reason and record it; existing decisions remain in history.`);
}
async function executeDirected() {
  if(state.busy || !state.directed || state.session?.readOnly)return;
  const planHash=state.directed.planHash;
  setBusy(true);renderEvidence();
  try {
    state.directed=await request("/api/directed/execute",{clusterId:"6",revision:state.evidence.revision,planHash,requestId:crypto.randomUUID()});
    state.evidence=await request("/api/evidence");state.session=await request("/api/session");
    renderOverview();renderSelection();
    message("Local evidence executed and fingerprinted. No human decision was changed. Choose a provisional draft, correct it, or keep unknown.");
  }catch(error){message(`Local execution stopped: ${error.message}`,"error");}
  finally{setBusy(false);if(state.tab==="directed")renderEvidence();}
}
function renderDirected() {
  const target=$("evidence-content"),data=state.directed;
  if(!data || data.clusterId!==state.clusterId) {
    target.append(node("p",{class:"evidence-explainer"},"Loading the local disagreement review and typed evidence plan…"));
    fetchDirected();return;
  }
  if(data.error){target.append(node("p",{class:"failure-box"},data.error));return;}
  const triage=node("section",{class:"directed-section","data-testid":"directed-triage"});
  triage.append(node("h3",{},"1 · Classify the disagreement"),node("p",{class:"evidence-explainer"},`Versioned explicit dictionary: ${data.triage.taxonomyVersion}. Failure, identity, state and label granularity remain separate; matching labels do not validate biology.`));
  const {wrap,body}=makeTable(["Cluster","Observed issues","Review"]);
  for(const item of data.triage.clusters) {
    const kinds=[...new Set(item.issues.map(issue=>issue.kind).filter(Boolean))];
    const row=node("tr",{"data-cluster":item.clusterId});
    row.append(node("td",{},`C${item.clusterId}`),node("td",{},kinds.length?kinds.join(" · ").replaceAll("_"," "):"No dictionary discrepancy detected"));
    const action=node("td");action.append(node("button",{type:"button",class:"button quiet small",onclick:()=>selectCluster(item.clusterId)},String(item.clusterId)===state.clusterId?"Selected":"Inspect"));row.append(action);body.append(row);
  }
  triage.append(wrap);
  const selected=data.triage.clusters.find(c=>c.clusterId===state.clusterId);
  const issues=node("details",{class:"directed-details"});issues.append(node("summary",{},`Cluster ${state.clusterId}: inspect classifications and original label lanes`));
  for(const issue of selected?.issues || []) {
    const item=node("div",{class:"classification-item"});item.append(pill((issue.kind || "abstention").replaceAll("_"," ")),node("span",{},` ${issue.lane || ""}: ${issue.left?.raw || ""}${issue.right ? ` ↔ ${issue.right.raw}` : ""}`),node("p",{},issue.reason),node("code",{class:"source-note"},(issue.evidenceRefs || []).join(" · ")));issues.append(item);
  }
  triage.append(issues);target.append(triage);
  if(state.clusterId!=="6") {
    target.append(node("div",{class:"markers-note"},"This minimal evidence loop executes full RNA inspection for cluster 6 only. Other clusters keep their frozen evidence and human decisions; no targeted RNA conclusion has been computed for this selection."));return;
  }
  const plan=node("section",{class:"directed-section","data-testid":"directed-plan"});
  plan.append(node("h3",{},"2 · Read a directed evidence plan"),node("p",{class:"evidence-explainer"},`Read only · cluster 6 · ${data.plan.scope.cellIds.length} exact retained cell IDs. The local Seurat object supplies RNA counts and its existing normalized data. No reclustering, deletion, external request or automatic acceptance.`));
  const steps=node("ol",{class:"plan-steps"});for(const step of data.plan.steps){const li=node("li");li.append(node("strong",{},step.tool),node("p",{},step.reason));steps.append(li);}plan.append(steps);
  plan.append(node("div",{class:"reference-note"},`Plan ${short(data.planHash)} · RNA source ${short(data.evidenceFingerprint.sourceHash)} · rules ${short(data.evidenceFingerprint.taxonomyHash)}`));
  const execute=node("button",{type:"button",class:"button primary","data-testid":"directed-execute",onclick:executeDirected},data.execution.status==="cached"?"Replay cached evidence":"Execute local evidence plan");
  execute.disabled=state.busy || state.session?.readOnly || !data.execution.available;plan.append(execute);
  if(data.execution.error)plan.append(node("p",{class:"failure-box"},data.execution.error));
  plan.append(detail("Typed parameters, exact scope and stop rules",data.plan));target.append(plan);
  const proposal=data.proposal;
  const result=node("section",{class:"directed-section directed-proposal","data-testid":"directed-proposal"});
  const head=node("div",{class:"directed-result-heading"});head.append(node("h3",{},"3 · Review a provisional judgment"),pill(proposal.status.replaceAll("_"," "),proposal.status==="unresolved"?"muted":"amber"));result.append(head);
  result.append(node("p",{class:"evidence-explainer"},`Granularity: ${proposal.granularity.replaceAll("_"," ")} · workflow: proposed · uncalibrated heuristic, not a probability or a truth label.`));
  const comparison=node("div",{class:"judgment-comparison"});
  const old=node("div");old.append(node("h4",{},"Saved model judgments"));for(const model of chosenCluster().models)old.append(node("p",{},`${model.provider} ${model.mode}: ${model.strict.status==="valid"?model.strict.label:model.strict.status}`));
  const fresh=node("div");fresh.append(node("h4",{},proposal.resolution==="provisional_broad_identity"?"New program evidence · provisional broad identity":"New program evidence · cell identity unresolved"),node("strong",{class:"result-label"},proposal.candidates.map(c=>c.label).join(" / ") || "No supported program"),node("p",{},`Recommended cell-type label: ${proposal.recommendedLabel || "unknown"}. Program compatibility does not confirm an NK or T identity.`));
  if(proposal.boundarySensitive)fresh.append(node("p",{class:"boundary-warning"},"Boundary sensitive: changing exploratory thresholds changes the provisional status. Inspect sensitivity before recording a decision."));comparison.append(old,fresh);result.append(comparison);
  if(proposal.measurements) {
    const counts=proposal.measurements.counts;
    const observations=node("div",{class:"observed-counts"});
    for(const [key,label] of [["t_only","T-anchor detection only"],["nk_only","NK-anchor detection only"],["both","Both detection gates"],["neither","Neither detection gate"]])observations.append(node("div",{},`${label}: ${counts[key]}`));result.append(observations);
    const coverage=proposal.measurements.coverage;
    result.append(node("p",{class:"evidence-explainer"},`Program detection under the declared rule: raw gene count > 0 in at least ${proposal.thresholds.anchorCount} measured anchors per cell. Available anchors: T ${coverage.T.measured.length}/${coverage.T.measured.length+coverage.T.missing.length}; NK ${coverage.NK.measured.length}/${coverage.NK.measured.length+coverage.NK.missing.length}. These counts are not true T/NK cell proportions or lineage assignments. Coexpression does not diagnose NKT cells or doublets; separate positive groups and broad coexpression are different evidence.`));
    const explanations=node("div",{class:"explanation-grid"});explanations.append(explanationList("Positive observations",proposal.support),explanationList("Conflicts and limits",proposal.conflict),explanationList("Missing evidence",proposal.missing));result.append(explanations);
  }
  result.append(node("p",{class:"stop-reason","data-testid":"directed-stop-reason"},`Stop: ${proposal.stopReason} ${data.execution.stopReason}`));
  const current=latestDecision("6","type");if(current)result.append(node("p",{class:"human-protected"},`Human record retained: ${eventLabel(current)} · ${eventStatus(current)}${current.stale?" · stale":""}. Executing evidence never replaces this record.`));
  const actions=node("div",{class:"directed-actions"});
  const prepare=node("button",{type:"button",class:"button quiet","data-testid":"directed-adopt",onclick:()=>fillDirected(proposal.recommendedLabel || "unknown")},proposal.recommendedLabel && proposal.recommendedLabel!=="unknown"?"Prepare provisional type draft":"Prepare unresolved draft");prepare.disabled=state.busy || state.session?.readOnly || !data.artifact;actions.append(prepare);
  const unknown=node("button",{type:"button",class:"button quiet","data-testid":"directed-unresolved",onclick:()=>fillDirected("unknown")},"Keep unresolved / unknown");unknown.disabled=state.busy || state.session?.readOnly || !data.artifact;actions.append(unknown);result.append(actions,node("p",{class:"microcopy"},"A draft needs your reason and an explicit Record decision. You can edit its label before recording; the directed evidence capsule is retained for correction and replay."));
  if(proposal.sensitivity)result.append(detail("Threshold sensitivity · no calibrated confidence",proposal.sensitivity));
  if(proposal.nextSteps)result.append(detail("Suggested next checks · never run automatically",proposal.nextSteps));
  result.append(node("p",{class:"reference-note"},`Stop: ${data.modelReview.stopReason} Additional provider calls: ${data.modelReview.calls}; cost: $${formatValue(data.modelReview.incrementalCostUSD,2)}.`));target.append(result);
  if(!data.expression)return;
  const expression=data.expression;
  const evidence=node("section",{class:"directed-section","data-testid":"directed-evidence"});
  evidence.append(node("h3",{},"Measured RNA evidence"),node("p",{class:"markers-note"},`RNA counts + existing data layer · ${expression.coverage.measured_gene_n}/${expression.coverage.panel_gene_n} panel genes available in all 155 scoped cells. Features unavailable in this stored matrix are null, never measured zero; this does not establish experimental or biological absence. A gene omitted from the top 30 marker list may still be expressed. Normalization: ${expression.source.normalization.method}, scale ${expression.source.normalization.scale_factor}.`));
  const genes=makeTable(["Gene / panel","Measurement","Detected n / 155","Detected %","Normalized all: median / p90","Detected: median"]);
  for(const gene of expression.panel) {
    const row=node("tr",{"data-gene":gene.gene});row.append(node("td",{},`${gene.gene} · ${gene.panel_group.replaceAll("_"," ")}`),node("td",{},gene.measurement_status==="missing"?"Missing feature (null)":"Measured RNA"),node("td",{},gene.detected_n===null?"—":`${gene.detected_n} / 155`),node("td",{},gene.detected_fraction===null?"—":formatValue(gene.detected_fraction*100,1)),node("td",{},gene.normalized?.all?`${formatValue(gene.normalized.all.q50)} / ${formatValue(gene.normalized.all.q90)}`:"—"),node("td",{},formatValue(gene.normalized?.detected?.q50)));genes.body.append(row);
  }
  evidence.append(genes.wrap);
  evidence.append(node("h4",{class:"subsection-title"},"Observed library QC and sample metadata"));
  for(const field of expression.qc.fields)evidence.append(node("p",{class:"qc-line"},field.distribution?`${field.field}: median ${formatValue(field.distribution.q50,1)} · range ${formatValue(field.distribution.q0,1)}–${formatValue(field.distribution.max,1)}`:`${field.field}: ${JSON.stringify(field.values)}. ${field.interpretation || ""}`));
  evidence.append(node("p",{class:"evidence-explainer"},`Low depth under the displayed exploratory rule: ${expression.qc.low_depth_n}/155. These whole-library QC fields do not establish absence, donor identity, doublets or VDJ evidence.`));
  evidence.append(node("h4",{class:"subsection-title"},"Compare against two measured denominators"),node("p",{class:"evidence-explainer"},`All rest: ${expression.comparisons.all_rest.n_cells} cells. Candidate lymphocyte controls: ${expression.comparisons.candidate_lymphocyte.n_cells} cells across C${expression.comparisons.candidate_lymphocyte.cluster_ids.join(", C")}. Selected by observed RNA gates; unverified and correlated. A contrast that disappears against these controls is disclosed, not treated as identity confirmation.`));
  if(proposal.comparisonReview){const table=makeTable(["Gene","Cluster %","All-rest Δ%","Candidate-control Δ%","Outcome"]);
    for(const row of proposal.comparisonReview){const tr=node("tr");for(const value of [row.gene,percentage(row.targetDetectedFraction),percentage(row.allRestDelta),percentage(row.candidateDelta),row.outcome.replaceAll("_"," ")])tr.append(node("td",{},value));table.body.append(tr);}evidence.append(table.wrap);}
  evidence.append(detail("Full per-gene distributions and source provenance",{source:expression.source,panel:expression.panel,package_id:expression.package_id}),detail("Candidate controls, selection sensitivity and comparisons",{candidate_controls:expression.candidate_controls,comparisons:expression.comparisons}),detail("QC and identity-gate sensitivity",{qc:expression.qc,identity_threshold_sensitivity:expression.identity_threshold_sensitivity}));
  if(data.artifact)evidence.append(node("p",{class:"reference-note"},`Immutable proposal capsule ${data.artifact.id} · bundle ${short(data.artifact.content.bundleHash)}`));target.append(evidence);
}
function renderHistory() {
  const target = $("evidence-content");
  target.append(node("p", {class:"evidence-explainer"},"History is append only. Undo adds a compensation event and keeps the original. Decisions retain the dataset revision, dimension, cluster and exact cell ID set. An evidence change marks old decisions stale; it never quietly reapplies them."));
  const controls = node("label",{class:"history-controls"});const input=node("input",{type:"checkbox"});input.checked=state.historyAll;input.addEventListener("change",()=>{state.historyAll=input.checked;renderEvidence();});controls.append(input,node("span",{},"Show all clusters"));target.append(controls);
  const list = node("div", {class:"history-list","data-testid":"history-list"});
  const events = state.session.events.filter(e => state.historyAll || String(eventScope(e).clusterId) === state.clusterId);
  if (!events.length) list.append(node("div",{class:"history-empty"},"No decision events yet.\nChoose a label or retain unknown, then record a reason."));
  for (const event of [...events].reverse()) {
    const d = decisions().find(d=>eventId(d)===eventId(event));
    const scope = eventScope(event), undo = event.kind === "undo" || event.type === "undo";
    const stale = d?.stale || event.stale || scope.revision !== state.evidence.revision;
    const undone = d?.undone || event.undone;
    const card=node("article",{class:`history-event ${stale?"stale":""} ${undone?"undone":""}`,"data-event-id":eventId(event)});
    const header=node("div",{class:"history-event-head"});header.append(node("strong",{},undo?"Undo recorded":`${eventLabel(event)} · cluster ${scope.clusterId}`),pill(stale?"stale":undo?"compensation":undone?"undone":eventStatus(event),stale?"amber":"muted"));card.append(header);
    card.append(node("p",{},event.reason || event.decision?.reason || ""));
    card.append(node("div",{class:"history-meta"},`${scope.datasetId} · ${scope.dimension} · ${scope.cellIds?.length || 0} exact cell IDs · revision ${short(scope.revision)}\n${event.timestamp || event.createdAt || ""} · event ${eventId(event)}${undo ? ` · compensates ${event.targetEventId || event.targetId}` : ""}`));
    for (const ref of event.evidenceRefs || []) card.append(node("div", {class:"reference-note"}, `Retained directed evidence: ${ref.id}`));
    if (!undo && !undone && !stale && !state.session.readOnly) card.append(node("button",{class:"button quiet small","data-testid":`undo-${eventId(event)}`,onclick:()=>openUndo(event)},"Undo with reason"));
    list.append(card);
  }
  target.append(list);
}
function openUndo(event) {
  state.undoTarget=event;
  $("undo-description").textContent=`Compensate “${eventLabel(event)}” for cluster ${eventScope(event).clusterId}, dimension ${eventScope(event).dimension}. The original event stays in history.`;
  $("undo-reason").value="";$("undo-dialog").showModal();$("undo-reason").focus();
}

$("decision-form").addEventListener("submit",async event=>{
  event.preventDefault(); if(state.busy||!state.evidence||state.session.readOnly)return;
  const label=$("label").value.trim(),reason=$("reason").value.trim();
  if(!label||!reason){message("A label and a reason are required. Use unknown when the identity remains unresolved.","error");return;}
  const body={clusterId:state.clusterId,dimension:currentDimension(),label,reason,status:$("review-status").value,revision:state.evidence.revision,requestId:crypto.randomUUID()};
  if (state.draftReference) body.evidenceRefs = [state.draftReference];
  setBusy(true);
  try{state.session=await request("/api/decision",body);$("reason").value="";state.draftReference=null;renderSelection();message(`Decision recorded for cluster ${body.clusterId} · ${body.dimension}. Source evidence is unchanged.`);}catch(error){message(error.message,"error");}finally{setBusy(false);}
});
$("undo-form").addEventListener("submit",async event=>{
  event.preventDefault();if(state.busy||!state.undoTarget)return;
  const reason=$("undo-reason").value.trim();if(!reason){message("Undo requires a reason.","error");return;}
  setBusy(true);
  try{state.session=await request("/api/undo",{targetEventId:eventId(state.undoTarget),reason,revision:state.evidence.revision,requestId:crypto.randomUUID()});$("undo-dialog").close();renderSelection();message("Undo recorded as a new compensation event. The original decision is preserved.");}catch(error){message(error.message,"error");}finally{setBusy(false);}
});
$("cancel-undo").addEventListener("click",()=>$("undo-dialog").close());
$("retain-unknown").addEventListener("click",()=>{$("label").value="unknown";$("reason").focus();message("Unknown selected. Record why the evidence remains unresolved to save this decision.");});
$("dimension").addEventListener("change",()=>{state.draftReference=null;$("label").value="";$("reason").value="";renderDecision();});
$("show-all").addEventListener("change",event=>{state.showAll=event.target.checked;renderUmap();});
for(const tab of document.querySelectorAll("[data-tab]"))tab.addEventListener("click",()=>{state.tab=tab.dataset.tab;if(state.evidence)renderEvidence();});
$("refresh-evidence").addEventListener("click",()=>load(true));
$("export-session").addEventListener("click",async()=>{
  if(state.busy)return;setBusy(true);
  try{const text=await exportFileText();const blob=new Blob([text],{type:"application/json"});const url=URL.createObjectURL(blob);const a=node("a",{href:url,download:`scagentkit-handoff-${short(state.evidence?.revision)}.json`});document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);message("Handoff exported: decisions, exact scope, revision and source hashes. Matrix, truth and model response bodies are excluded.");}catch(error){message(error.message,"error");}finally{setBusy(false);}
});
$("import-session").addEventListener("click",()=>$("import-file").click());
$("import-file").addEventListener("change",async event=>{
  const file=event.target.files[0];if(!file||state.busy)return;setBusy(true);
  try{if(file.size>32*1024*1024-64)throw new Error("Handoff exceeds the 32 MB request limit.");state.session=await importFileText(await file.text());renderSelection();message("Handoff restored and integrity checked. Evidence with a different fingerprint marks imported decisions stale.");}catch(error){message(`Import rejected: ${error.message}`,"error");}finally{event.target.value="";setBusy(false);}
});
load();
