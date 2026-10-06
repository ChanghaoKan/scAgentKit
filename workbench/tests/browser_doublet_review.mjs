#!/usr/bin/env node
/** Actual Chrome + fixed R acceptance for ONE fresh public PBMC doublet run.
 * Begins after root's approved keep analysis and before annotation writeback.
 * Root executes only after the private installed namespace and fixture freeze.
 * No custom R source, provider callback or arbitrary browser code IPC.
 */
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import {spawn} from "node:child_process";
import {createRequire} from "node:module";
import {fileURLToPath} from "node:url";

const args = {}, allowedArgs = new Set(["project", "output", "r-library", "implementation", "python", "rscript", "chrome", "playwright"]);
for (let index = 2; index < process.argv.length; index += 2) {
  const name = process.argv[index]?.slice(2);
  assert(process.argv[index]?.startsWith("--") && allowedArgs.has(name) && process.argv[index + 1], "Use supported --name value pairs");
  assert(!Object.hasOwn(args, name), "Duplicate driver argument"); args[name] = process.argv[index + 1];
}
assert(args.project && args.output && args["r-library"] && /^[a-f0-9]{64}$/.test(args.implementation || ""), "Project, output, library and exact implementation hash are required");
const workbench = path.resolve(path.dirname(fileURLToPath(import.meta.url)), ".."), workspace = path.dirname(path.dirname(workbench));
const fixtureRoot = path.join(workspace, "evidence", "doublet-public-pbmc"), project = path.resolve(args.project), output = path.resolve(args.output);
const projectVersion = project === path.join(fixtureRoot, "project") ? "" : project === path.join(fixtureRoot, "project-v2") ? "-v2" : null;
assert(projectVersion !== null, "Only root's explicitly authorized public doublet project or project-v2 is supported");
assert.equal(output, path.join(fixtureRoot, "browser" + projectVersion), "Use the matching isolated doublet browser evidence directory");
assert.equal((await fs.lstat(project)).isSymbolicLink(), false); assert.equal(await fs.realpath(project), project);
await fs.mkdir(output, {recursive: true}); assert.equal(await fs.realpath(output), output);
const exists = file => fs.access(file).then(() => true, () => false), reportFile = path.join(output, "doublet-browser-report.json");
assert.equal(await exists(reportFile), false, "Never overwrite prior browser evidence");
assert.equal(await exists(path.join(project, ".workbench-jobs")), false, "Root prepares the new project in R before browser jobs exist");
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex"), array = value => value == null ? [] : Array.isArray(value) ? value : [value];
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const env = {...process.env, PYTHONDONTWRITEBYTECODE: "1", R_LIBS_USER: args["r-library"], SCAGENTKIT_EXPECTED_IMPLEMENTATION: args.implementation,
  R_PROFILE_USER: "/dev/null", R_ENVIRON_USER: "/dev/null", R_PROFILE: "/dev/null", R_ENVIRON: "/dev/null"};
for (const key of ["DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY",
  "AZURE_OPENAI_API_KEY", "COHERE_API_KEY", "MISTRAL_API_KEY", "OPENROUTER_API_KEY", "HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN"]) delete env[key];
const require = createRequire(import.meta.url), {chromium} = require(args.playwright || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
const report = {schema: "scagentkit.doublet.browser-acceptance.v1", startedAt: new Date().toISOString(), project, output,
  requiredImplementationHash: args.implementation, library: args["r-library"], driverSHA256: sha(await fs.readFile(fileURLToPath(import.meta.url))),
  projectVersion: projectVersion || "v1", actualChrome: false, actualRBridge: false, simulatedRBridge: false, sourceOriginalsRead: false, tests: [], jobs: [], screenshots: [],
  pageErrors: [], externalRequests: [], unexpectedDialogs: [], newProviderCalls: 0, realAPIRequests: 0, paidProviderCalls: 0, costUSD: 0,
  providerEnvNamesRemoved: 13, rProfilesDisabled: true, workerTimeoutMilliseconds: 180000, productionSHA256: {}};
for (const file of ["server.py", "qc_runtime.py", "run_review_runtime.py", "run_review_bridge.R", "run_continue_runtime.py", "run_continue_worker.py", "run_continue_bridge.R", "static/review.js", "static/review.html", "static/review.css"])
  report.productionSHA256[file] = sha(await fs.readFile(path.join(workbench, file)));
const checkpointNames = await fs.readdir(path.join(project, "checkpoints")), inputFiles = [];
for (const prefix of ["input", "doublet_diagnostics", "cycle_diagnostics", "strategy_preprocess"]) {
  const files = checkpointNames.filter(name => new RegExp("^" + prefix + "-[a-f0-9]{64}\\.rds$").test(name));
  assert.equal(files.length, 1, "Exactly one immutable " + prefix + " checkpoint is expected"); inputFiles.push(...files);
}
const inputDigests = {};
for (const name of inputFiles) {const file = path.join(project, "checkpoints", name); assert.equal((await fs.lstat(file)).isSymbolicLink(), false); inputDigests[name] = sha(await fs.readFile(file));}
report.immutableCheckpointSHA256 = inputDigests;
const ledgerFile = path.join(project, "provider", "ledger.json"), ledgerPresent = await exists(ledgerFile), ledgerBytes = ledgerPresent ? await fs.readFile(ledgerFile) : null;
const entries = ledgerBytes ? array(JSON.parse(ledgerBytes).entries) : [];
for (const entry of entries) {assert.equal(entry.provider?.external, false); assert.equal(entry.cost_usd, 0); assert.equal(entry.charged_or_held_usd, 0);}
report.initialMockResponses = entries.length; report.initialLedgerSHA256 = ledgerBytes ? sha(ledgerBytes) : null;
report.ledgerSummary = entries.map(entry => ({purpose: entry.purpose, status: entry.status, external: entry.provider.external, costUSD: entry.cost_usd, chargedOrHeldUSD: entry.charged_or_held_usd}));
let server, browser, context, page, profile, origin, token, activeJobId;
const lifecycle = [];
async function protectedInputs() {
  for (const [name, digest] of Object.entries(inputDigests)) assert.equal(sha(await fs.readFile(path.join(project, "checkpoints", name))), digest, "Immutable input/doublet/cycle diagnostic/first keep preprocessing checkpoint changed");
  assert.equal(await exists(ledgerFile), ledgerPresent, "Browser actions changed the provider ledger presence"); if (ledgerPresent) assert.equal(sha(await fs.readFile(ledgerFile)), report.initialLedgerSHA256, "Browser actions changed the local mock ledger");
}
async function scientificSnapshot() {
  const files = {};
  async function walk(directory) {
    for (const item of await fs.readdir(directory, {withFileTypes: true})) {
      if (directory === project && item.name === ".workbench-jobs") continue;
      assert.equal(item.isSymbolicLink(), false); const file = path.join(directory, item.name);
      if (item.isDirectory()) await walk(file); else if (item.isFile()) files[path.relative(project, file)] = sha(await fs.readFile(file));
    }
  }
  await walk(project); return files;
}
async function test(name, action) {
  const started = Date.now();
  try {await action(); await protectedInputs(); report.tests.push({name, outcome: "passed", milliseconds: Date.now() - started, immutableCheckpointsAndLedgerUnchanged: true}); console.log("PASS " + name);}
  catch (error) {report.tests.push({name, outcome: "failed", error: error.message}); throw error;}
}
async function startServer() {
  server = spawn(args.python || "python3", [path.join(workbench, "server.py"), "--run-project", project, "--local-continue", "--r-library", args["r-library"], "--rscript", args.rscript || "Rscript", "--port", "0"],
    {cwd: path.dirname(workbench), env, stdio: ["ignore", "pipe", "pipe"]});
  lifecycle.push({event: "owned_server_started", pid: server.pid, portRequested: 0});
  let startup = "", startError;
  server.once("error", error => {startError = error;});
  server.stdout.on("data", bytes => {startup = (startup + bytes.toString()).slice(-8192); const match = startup.match(/scAgentKit workbench: (http:\/\/127\.0\.0\.1:[0-9]+)/); if (match) origin = match[1];});
  // Raw process output is not written: no response/token or credential logs.
  server.stderr.on("data", () => {});
  const deadline = Date.now() + 45000;
  while (!origin && Date.now() < deadline) {if (startError) throw startError; assert.equal(server.exitCode, null, "Owned server exited before readiness"); await pause(100);}
  assert(origin && /^http:\/\/127\.0\.0\.1:[0-9]+$/.test(origin), "The fixed server did not report its ephemeral loopback URL");
  report.ownedLoopbackOrigin = origin; return inspect();
}
async function stopServer() {
  if (!server || server.exitCode != null || server.signalCode != null) return;
  const owned = server, closed = new Promise(resolve => owned.once("exit", resolve)); owned.kill("SIGTERM");
  await Promise.race([closed, pause(3000)]);
  if (owned.exitCode == null && owned.signalCode == null) {owned.kill("SIGKILL"); await closed;}
  lifecycle.push({event: "owned_server_stopped", pid: owned.pid, exitCode: owned.exitCode, signal: owned.signalCode});
  // Only the owned server PID is signalled. Detached R workers are untouched.
}
async function inspect() {
  const response = await fetch(origin + "/api/run-review/inspect"), answer = await response.json(); assert.equal(response.status, 200, "Fixed R inspection rejected");
  assert.equal(answer.schema, "scagentkit.run-review.workbench.v1"); assert.equal(answer.run.schema, "scagentkit.run.v1");
  assert.equal(answer.run.implementation_hash, args.implementation, "Installed implementation guard mismatch"); token = answer.csrf_token; assert(typeof token === "string" && token); return answer;
}
function binding(run, action) {return {action, kind: "strategy", project_id: run.project_id, input_hash: run.input_hash, proposal_hash: run.review_node.proposal_hash,
  review_hash: run.review_node.review_hash, expected_revision: run.revision, reviewer: "Offline public doublet Chrome analyst", reason: "Exact complete supported strategy on public PBMC with fixed doublet scores"};}
async function staleApproval(run) {
  const response = await fetch(origin + "/api/run-review/decision", {method: "POST", headers: {"Content-Type": "application/json", Origin: origin, "X-ScAgentKit-Run-Token": token}, body: JSON.stringify(binding(run, "approve"))});
  const answer = await response.json(); assert.equal(response.status, 409, "Old actual strategy approval must fail at HTTP 409"); return {httpStatus: response.status, message: answer.error};
}
const ui = id => page.locator('[data-testid="' + id + '"]');
async function idle() {await ui("run-refresh").waitFor(); await page.waitForFunction(() => !document.getElementById("run-refresh").disabled);}
async function refresh() {await idle(); await ui("run-refresh").click(); await idle();}
async function rendered(status, stage) {
  await page.waitForFunction(({status, stage}) => document.getElementById("run-status").textContent.trim() === status + " / " + stage && !document.getElementById("run-refresh").disabled, {status, stage});
}
async function screenshot(name) {const file = path.join(output, name + ".png"); assert.equal(await exists(file), false); await page.screenshot({path: file, fullPage: true}); report.screenshots.push(file);}
async function responseFrom(button, route) {
  const response = page.waitForResponse(answer => new URL(answer.url()).pathname === route && answer.request().method() === "POST");
  await ui(button).click(); return response;
}
async function terminalJob(jobId) {
  const deadline = Date.now() + report.workerTimeoutMilliseconds; let answer;
  while (Date.now() < deadline) {
    const response = await fetch(origin + "/api/run-review/continuation", {signal: AbortSignal.timeout(Math.min(5000, Math.max(1, deadline - Date.now())))}); assert.equal(response.status, 200); answer = await response.json();
    assert.equal(answer.schema, "scagentkit.run-continue.workbench.v1"); assert.equal(answer.job.job_id, jobId);
    if (!["queued", "running"].includes(answer.job.status)) return answer;
    await pause(500);
  }
  report.interruptedByDriverDeadline = {jobId, lastVerifiedJob: answer?.job, detachedWorkerLeftRunning: true};
  throw new Error("180-second verification deadline reached; saved detached job remains untouched and may continue");
}
let initial, revised, approved, stopped;
async function history() {
  const value = JSON.parse(await fs.readFile(path.join(project, "decision_history.json"), "utf8"));
  const approvals = array(value.events).filter(event => event.action === "approved"), stages = array(value.events).filter(event => event.action === "executed").map(event => event.details.stage);
  return {approvals, stages};
}
function roles(evidence) {
  assert.equal(evidence.schema, "scagentkit.doublet.evidence.v1");
  if (Array.isArray(evidence.columns)) {assert.equal(evidence.columns.length, 3); assert(evidence.columns.every(value => typeof value === "string" && value)); return Object.fromEntries(["score", "class", "capture"].map((name, index) => [name, evidence.columns[index]]));}
  assert(["score", "class", "capture"].every(name => typeof evidence.columns?.[name] === "string" && evidence.columns[name])); return evidence.columns;
}
function exactImpact(run, method) {
  const details = run.strategy_review.details, impact = details.applicability.doublet;
  assert.equal(details.canonical_proposal.doublet.method, method); assert.equal(impact.method, method);
  assert(/^[a-f0-9]{64}$/.test(details.doublet_evidence_hash)); assert.equal(impact.evidence_hash, details.doublet_evidence_hash); assert(/^[a-f0-9]{64}$/.test(impact.selection_hash));
  const qc = array(impact.qc_keep_cell_ids), selected = array(impact.selected_cell_ids), removed = array(impact.removed_cell_ids);
  for (const list of [qc, selected, removed]) {assert(list.every(value => typeof value === "string" && value)); assert.equal(new Set(list).size, list.length);}
  assert.equal(qc.length, impact.qc_retained); assert.equal(selected.length, impact.retained_cells); assert.equal(removed.length, impact.removed_cells);
  assert.deepEqual(new Set([...selected, ...removed]), new Set(qc)); assert(removed.every(cell => !selected.includes(cell)));
  if (method === "keep") assert.equal(removed.length, 0);
  const rows = Object.entries(impact.per_capture); assert(rows.length > 0);
  for (const [name, row] of rows) {assert(name); assert.equal(row.removed + row.retained, row.qc_retained); assert(row.removed <= row.predicted_after_qc);}
  for (const [field, expected] of [["qc_retained", qc.length], ["removed", removed.length], ["retained", selected.length]]) assert.equal(rows.reduce((sum, [, row]) => sum + row[field], 0), expected);
  return {impact, qc, selected, removed};
}
async function displayedImpact(run, method) {
  const {impact, removed} = exactImpact(run, method);
  assert.equal(await ui("doublet-method").getAttribute("data-method"), method);
  assert.equal(await ui("doublet-status").getAttribute("data-status"), "available");
  assert.equal(await ui("doublet-scope-status").getAttribute("data-status"), method === "keep" ? "keep" : "verified");
  assert.equal(await ui("doublet-cell-scope").evaluate(node => node.open), false);
  await ui("doublet-cell-scope").locator("summary").click();
  assert.equal((await ui("doublet-cell-ids").textContent()).trim(), removed.length ? removed.join("\n") : "None — no doublet removal selected.");
  assert((await ui("doublet-cell-count").textContent()).replace(/,/g, "").includes("Exact removal count: " + removed.length));
  await ui("doublet-cell-scope").locator("summary").click();
  for (const [name, row] of Object.entries(impact.per_capture)) {
    const text = (await ui("doublet-capture-impact").textContent()).replace(/,/g, ""); assert(text.includes(name)); assert(text.includes(String(row.removed))); assert(text.includes(String(row.retained)));
  }
  assert((await ui("doublet-risk").textContent()).includes("not a calibrated probability"));
  assert((await ui("doublet-risk").textContent()).includes("homotypic"));
  assert.equal(await page.locator("#doublet-card button, #doublet-card input, #doublet-card select, #doublet-card textarea").count(), 0);
  return impact;
}
async function debugPage() {
  if (!page || page.isClosed()) return;
  try {
    report.failureUI = await page.evaluate(() => {
      const text = id => document.getElementById(id)?.textContent?.trim() || "";
      return {status: text("run-status"), message: text("run-message"), messageHidden: document.getElementById("run-message")?.hidden, continuationNote: text("run-continuation-note"), jobStatus: text("run-job-status"), scopeStatus: text("doublet-scope-status"), controller: typeof state === "object" ? {busy: state.busy, stale: state.stale, connectionLost: state.connectionLost, awaitingFreshInspect: state.awaitingFreshInspect, status: state.view?.run.status, stage: state.view?.run.stage, revision: state.view?.run.revision} : null};
    });
    await screenshot("failure-ui-status-and-message");
  } catch (error) {report.failureUIError = error.message;}
}
try {
  const baseline = await history(); report.initialHistory = baseline.stages;
  initial = (await startServer()).run;
  assert.equal(initial.status, "awaiting_review"); assert.equal(initial.stage, "strategy_propose"); assert.equal(initial.review_node.kind, "strategy");
  assert.equal(initial.strategy_review.details.applicability.executable, true);
  const evidence = initial.strategy_review.details.doublet_diagnostics, columns = roles(evidence);
  assert.equal(evidence.status, "available"); assert.equal(evidence.species, "human"); assert.equal(evidence.reference, "fixed_full_input"); assert.equal(evidence.refit_after_qc, false);
  assert.equal(evidence.capture.method, "single"); assert(typeof evidence.capture.id === "string" && evidence.capture.id); assert(typeof evidence.capture.source === "string" && evidence.capture.source);
  assert.equal(evidence.full_called_cohort, true); assert.equal(evidence.technology, "10x_chromium_standard"); assert.equal(evidence.rate.method, "10x_standard"); assert.equal(evidence.cohort.removed_cells, 0); assert.equal(evidence.scoring.function_name, "scDblFinder::scDblFinder"); assert(typeof evidence.scoring.versions.scDblFinder === "string");
  assert.equal(baseline.stages.filter(stage => stage === "strategy_evidence").length, 1); assert.equal(baseline.stages.filter(stage => stage === "qc_apply").length, 1);
  assert.equal(baseline.stages.filter(stage => stage === "strategy_selection").length, 1); assert.equal(baseline.stages.filter(stage => stage === "strategy_preprocess").length, 1);
  assert.equal(baseline.approvals.filter(event => event.details.kind === "annotation").length, 0);
  report.initialInputHash = initial.input_hash; report.initialSnapshot = {projectId: initial.project_id, revision: initial.revision, proposalHash: initial.review_node.proposal_hash, reviewHash: initial.review_node.review_hash, evidenceHash: initial.strategy_review.evidence_hash, implementationHash: initial.implementation_hash};
  profile = await fs.mkdtemp(path.join(output, ".owned-chrome-profile-")); report.isolatedProfile = true;
  context = await chromium.launchPersistentContext(profile, {headless: true, env, executablePath: args.chrome || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", viewport: {width: 1440, height: 1100}});
  browser = context.browser(); report.actualChrome = true; report.chromeVersion = browser?.version() || "Chrome persistent context";
  await context.route("**/*", route => {
    const request = route.request(), url = request.url();
    if (url.startsWith(origin + "/") && (["GET", "HEAD"].includes(request.method()) || request.method() === "POST" && ["/api/run-review/decision", "/api/run-review/continue"].includes(new URL(url).pathname)) || url.startsWith("data:")) return route.continue();
    report.externalRequests.push(url); return route.abort();
  });
  page = await context.newPage(); page.setDefaultTimeout(45000); page.on("pageerror", error => report.pageErrors.push(error.message));
  page.on("dialog", async dialog => {report.unexpectedDialogs.push({type: dialog.type()}); await dialog.dismiss();});
  await page.goto(origin + "/"); await rendered("awaiting_review", "strategy_propose");
  await test("actual Chrome displays score-first keep and declared public PBMC capture evidence without a deletion control", async () => {
    assert.equal(await ui("run-strategy").isVisible(), true); assert.equal(await ui("run-qc").isVisible(), false); assert.equal(await ui("run-annotation").isVisible(), false);
    assert.equal(await page.locator("#run-qc-frame").getAttribute("src"), null);
    assert.deepEqual(JSON.parse(await ui("strategy-json").inputValue()), initial.strategy_review.details.canonical_proposal);
    assert((await ui("doublet-capture").textContent()).includes(evidence.capture.id)); assert((await ui("doublet-capture").textContent()).includes(evidence.capture.source));
    assert((await ui("doublet-cohort").textContent()).includes("no refit after QC or deletion"));
    report.initialImpact = await displayedImpact(initial, "keep"); assert.equal(initial.strategy_review.details.canonical_proposal.cycle.method, "none"); assert.equal(initial.strategy_review.details.cycle_diagnostics.schema, "scagentkit.cycle.evidence.v1");
    assert.equal(await ui("doublet-details").evaluate(node => node.open), false); await ui("doublet-details").locator("summary").click();
    const record = await ui("doublet-record").textContent(); for (const value of [detailsHash(initial), evidence.rate.source, evidence.scoring.versions.scDblFinder, columns.score, columns.class, columns.capture]) assert(record.includes(String(value)));
    await screenshot("01-central-public-doublet-keep"); await ui("doublet-details").locator("summary").click(); report.savedDoubletEvidence = evidence;
  });
  await test("actual whole JSON keep-to-remove revision exposes exact IDs and rejects stale approval without scientific mutations", async () => {
    const proposal = structuredClone(initial.strategy_review.details.canonical_proposal); proposal.doublet = {method: "remove_predicted", reason: "Explicitly review and remove only the saved algorithm-predicted doublets still within QC; retain the fixed full-input scoring reference."};
    await ui("strategy-json").fill(JSON.stringify(proposal, null, 2)); assert.equal(await ui("strategy-approve").isDisabled(), true);
    await ui("strategy-reviewer").fill("Offline public doublet Chrome analyst"); await ui("strategy-reason").fill("Review the complete strategy and exact predicted-doublet deletion impact on the declared public PBMC loading unit.");
    const response = await responseFrom("strategy-save", "/api/run-review/decision"); assert.equal(response.status(), 200);
    const request = response.request().postDataJSON(); assert.equal(request.kind, "strategy"); assert.equal(request.action, "revise"); assert.deepEqual(request.proposal, proposal);
    await rendered("awaiting_review", "strategy_propose"); revised = (await inspect()).run;
    assert.equal(revised.input_hash, initial.input_hash); assert.notEqual(revised.review_node.review_hash, initial.review_node.review_hash); assert.notEqual(revised.review_node.proposal_hash, initial.review_node.proposal_hash);
    assert.equal(revised.strategy_review.evidence_hash, initial.strategy_review.evidence_hash); assert.deepEqual(revised.strategy_review.details.doublet_diagnostics, evidence);
    assert.deepEqual(revised.strategy_review.details.canonical_proposal, proposal); report.removalImpact = await displayedImpact(revised, "remove_predicted"); assert(report.removalImpact.removed_cells > 0);
    const before = await scientificSnapshot(), rejection = await staleApproval(initial); assert.deepEqual(await scientificSnapshot(), before);
    assert.equal(await ui("strategy-approve").isDisabled(), false); report.revision = {...rejection, oldRevision: initial.revision, newRevision: revised.revision, oldProposalHash: initial.review_node.proposal_hash, newProposalHash: revised.review_node.proposal_hash, oldReviewHash: initial.review_node.review_hash, newReviewHash: revised.review_node.review_hash, staleApprovalScientificBytesUnchanged: true};
    await screenshot("02-exact-public-doublet-removal-impact");
  });
  await test("one central approval and actual fixed R Continue apply exact deletion without rescoring or repeating QC", async () => {
    await ui("strategy-reviewer").fill("Offline public doublet Chrome analyst"); await ui("strategy-reason").fill("Approve the complete plan and exact algorithm-predicted doublet removal scope. Keep the fixed full-input scoring and source metadata. Annotation requires its later review.");
    const decision = await responseFrom("strategy-approve", "/api/run-review/decision"); assert.equal(decision.status(), 200); assert.equal(decision.request().postDataJSON().action, "approve");
    await rendered("ready", "strategy_apply"); approved = (await inspect()).run; assert.equal(approved.input_hash, initial.input_hash); assert.equal(await ui("run-continue").isDisabled(), false);
    const accepted = await responseFrom("run-continue", "/api/run-review/continue"); assert.equal(accepted.status(), 202); const submission = accepted.request().postDataJSON(), queued = await accepted.json();
    assert.deepEqual(Object.keys(submission).sort(), ["project_id", "input_hash", "expected_revision", "request_id", "retry"].sort()); assert.equal(submission.retry, false); activeJobId = queued.job.job_id; assert(/^[a-f0-9]{32}$/.test(activeJobId)); report.savedJobId = activeJobId;
    const completed = await terminalJob(activeJobId); assert.equal(completed.job.status, "succeeded"); assert.equal(completed.job.next_run_status, "awaiting_configuration"); assert.equal(completed.job.next_run_stage, "annotation_propose");
    const directory = path.join(project, ".workbench-jobs", "jobs", activeJobId), owner = JSON.parse(await fs.readFile(path.join(directory, "owner.json"), "utf8")), config = JSON.parse(await fs.readFile(path.join(directory, "config.json"), "utf8")), responseBytes = await fs.readFile(path.join(directory, "response.json")), response = JSON.parse(responseBytes);
    assert(owner.r_pid > 0 && owner.worker_pid > 0 && owner.r_pid !== owner.worker_pid); assert.equal(owner.r_exit_code, 0); assert.equal(path.basename(config.bridge), "run_continue_bridge.R"); assert.equal(config.library, args["r-library"]); assert.equal(response.ok, true); assert.equal(response.result.input_hash, initial.input_hash);
    report.actualRBridge = true; report.jobs.push({public: completed.job, owner, codeHashes: config.code_hashes, responseSHA256: sha(responseBytes), result: response.result}); activeJobId = null;
    await refresh(); await rendered("awaiting_configuration", "annotation_propose"); stopped = (await inspect()).run;
    assert.equal(stopped.input_hash, initial.input_hash); assert(stopped.review_node == null, "No review node is present at the annotation configuration boundary"); assert(stopped.output == null, "No completed output is present at the annotation configuration boundary"); assert(stopped.annotation_review == null);
    assert.deepEqual(stopped.strategy_review.details.doublet_diagnostics, evidence); assert.equal(stopped.strategy_review.details.canonical_proposal.doublet.method, "remove_predicted");
    assert.equal(await ui("run-continue").isDisabled(), true); assert((await ui("run-continuation-note").textContent()).includes("current run needs configuration"));
    const after = await history(); assert.equal(after.approvals.filter(event => event.details.kind === "strategy").length, baseline.approvals.filter(event => event.details.kind === "strategy").length + 1);
    assert.equal(after.approvals.filter(event => event.details.kind === "qc").length, 0); assert.equal(after.approvals.filter(event => event.details.kind === "annotation").length, 0);
    for (const stage of ["strategy_evidence", "qc_apply"]) assert.equal(after.stages.filter(value => value === stage).length, baseline.stages.filter(value => value === stage).length);
    for (const stage of ["strategy_selection", "strategy_preprocess", "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence"]) assert.equal(after.stages.filter(value => value === stage).length, baseline.stages.filter(value => value === stage).length + 1);
    assert.equal(after.stages.includes("annotation_apply"), false); assert.equal(after.stages.includes("finalize"), false);
    report.executionStages = after.stages; report.approvals = after.approvals.map(event => ({sequence: event.sequence, kind: event.details.kind, proposalHash: event.details.proposal_hash, reviewHash: event.details.review_hash, decisionId: event.details.decision_id}));
    report.stop = {status: stopped.status, stage: stopped.stage, revision: stopped.revision, inputHash: stopped.input_hash, historyHead: stopped.history_head, annotationApplied: false, predictedDeletionMethod: "remove_predicted", retainedCells: report.removalImpact.retained_cells, removedCells: report.removalImpact.removed_cells};
    await screenshot("03-public-doublet-annotation-configuration-stop");
  });
  assert.equal(report.pageErrors.length, 0); assert.equal(report.externalRequests.length, 0); assert.equal(report.unexpectedDialogs.length, 0);
  for (const [file, digest] of Object.entries(report.productionSHA256)) assert.equal(sha(await fs.readFile(path.join(workbench, file))), digest, "Production changed during acceptance"); report.passed = true;
} catch (error) {report.passed = false; report.error = error.stack; await debugPage(); console.error(error.stack); process.exitCode = 1;}
finally {
  if (activeJobId) {
    try {const directory = path.join(project, ".workbench-jobs", "jobs", activeJobId); report.savedUnfinishedJob = {job: JSON.parse(await fs.readFile(path.join(directory, "job.json"), "utf8")), owner: JSON.parse(await fs.readFile(path.join(directory, "owner.json"), "utf8")), detachedWorkerLeftUntouched: true};}
    catch (_) {report.savedUnfinishedJob = {jobId: activeJobId, detachedWorkerLeftUntouched: true};}
  }
  try {await context?.close(); if (browser?.isConnected()) await browser.close();} catch (error) {report.passed = false; report.chromeCleanupError = error.message; process.exitCode = 1;}
  try {await stopServer();} catch (error) {report.passed = false; report.serverCleanupError = error.message; process.exitCode = 1;}
  if (profile) {await fs.rm(profile, {recursive: true, force: true}); report.isolatedProfileRemoved = true;}
  try {await protectedInputs(); report.immutableCheckpointsAndLocalLedgerUnchanged = true;} catch (error) {report.passed = false; report.preservationError = error.message; process.exitCode = 1;}
  report.completedAt = new Date().toISOString(); report.lifecycle = lifecycle; await fs.writeFile(path.join(output, "server-lifecycle.json"), JSON.stringify(lifecycle, null, 2) + "\n"); await fs.writeFile(reportFile, JSON.stringify(report, null, 2) + "\n");
}
function detailsHash(run) {return run.strategy_review.details.doublet_evidence_hash;}
