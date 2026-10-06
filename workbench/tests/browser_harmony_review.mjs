#!/usr/bin/env node
/** Actual Chrome + fixed R acceptance for ONE fresh public synthetic Harmony run.
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

const args = {}, allowedArgs = new Set(["project", "output", "r-library", "implementation", "python", "rscript", "chrome", "playwright", "attempt"]);
for (let index = 2; index < process.argv.length; index += 2) {
  const name = process.argv[index]?.slice(2);
  assert(process.argv[index]?.startsWith("--") && allowedArgs.has(name) && process.argv[index + 1], "Use supported --name value pairs");
  assert(!Object.hasOwn(args, name), "Duplicate driver argument"); args[name] = process.argv[index + 1];
}
assert(args.project && args.output && args["r-library"] && /^[a-f0-9]{64}$/.test(args.implementation || ""), "Project, output, library and exact implementation hash are required");
const workbench = path.resolve(path.dirname(fileURLToPath(import.meta.url)), ".."), workspace = path.dirname(path.dirname(workbench));
const fixtureRoot = path.join(workspace, "evidence", "harmony-synthetic"), project = path.resolve(args.project), output = path.resolve(args.output);
const attempt = args.attempt || "v1"; assert(["v1", "v2"].includes(attempt), "Only explicit first or corrected second browser attempts are supported");
assert.equal(project, path.join(fixtureRoot, "project"), "Only root's fresh explicitly authorized synthetic Harmony project is supported");
assert.equal(output, path.join(fixtureRoot, attempt === "v1" ? "browser" : "browser-v2"), "Use the matching isolated Harmony browser evidence directory; prior evidence is preserved");
const projectVersion = "v1", harmonyChoice = {method: "harmony", group_by_vars: ["technical_batch"], theta: 2, lambda: 1, sigma: .1, max_iter: 10, nclust: 12, reason: "Explicit crossed synthetic batch effect; software-only comparison, no biological recommendation."};
assert.equal((await fs.lstat(project)).isSymbolicLink(), false); assert.equal(await fs.realpath(project), project);
await fs.mkdir(output, {recursive: true}); assert.equal(await fs.realpath(output), output);
const exists = file => fs.access(file).then(() => true, () => false), reportFile = path.join(output, "harmony-browser-report.json");
assert.equal(await exists(reportFile), false, "Never overwrite prior browser evidence");
const jobsRoot = path.join(project, ".workbench-jobs");
if (attempt === "v1" || !await exists(jobsRoot)) {
  assert.equal(await exists(jobsRoot), false, "Root prepares the new project in R before browser jobs exist");
} else {
  // A first readonly inspection initializes these paths without submitting a
  // job. A corrected second attempt may reuse exactly that empty layout.
  const owner = (await fs.lstat(project)).uid, layout = await fs.lstat(jobsRoot); assert(layout.isDirectory() && !layout.isSymbolicLink()); assert.equal(layout.uid, owner); assert.equal(await fs.realpath(jobsRoot), jobsRoot);
  assert.deepEqual((await fs.readdir(jobsRoot)).sort(), ["continue.lock", "jobs", "requests"]);
  for (const name of ["jobs", "requests"]) {
    const directory = path.join(jobsRoot, name), stat = await fs.lstat(directory);
    assert(stat.isDirectory() && !stat.isSymbolicLink()); assert.equal(stat.uid, owner); assert.equal(await fs.realpath(directory), directory); assert.deepEqual(await fs.readdir(directory), []);
  }
  const lock = path.join(jobsRoot, "continue.lock"), stat = await fs.lstat(lock);
  assert(stat.isFile() && !stat.isSymbolicLink()); assert.equal(stat.uid, owner); assert.equal(await fs.realpath(lock), lock); assert.equal(stat.size, 0);
}
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex"), array = value => value == null ? [] : Array.isArray(value) ? value : [value];
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const env = {...process.env, PYTHONDONTWRITEBYTECODE: "1", R_LIBS_USER: args["r-library"], SCAGENTKIT_EXPECTED_IMPLEMENTATION: args.implementation,
  R_PROFILE_USER: "/dev/null", R_ENVIRON_USER: "/dev/null", R_PROFILE: "/dev/null", R_ENVIRON: "/dev/null"};
for (const key of ["DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY",
  "AZURE_OPENAI_API_KEY", "COHERE_API_KEY", "MISTRAL_API_KEY", "OPENROUTER_API_KEY", "HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN"]) delete env[key];
const require = createRequire(import.meta.url), {chromium} = require(args.playwright || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
const report = {schema: "scagentkit.harmony.browser-acceptance.v1", startedAt: new Date().toISOString(), project, output,
  requiredImplementationHash: args.implementation, library: args["r-library"], driverSHA256: sha(await fs.readFile(fileURLToPath(import.meta.url))),
  projectVersion: projectVersion || "v1", attempt, actualChrome: false, actualRBridge: false, simulatedRBridge: false, sourceOriginalsRead: false, tests: [], jobs: [], screenshots: [],
  pageErrors: [], externalRequests: [], unexpectedDialogs: [], newProviderCalls: 0, realAPIRequests: 0, paidProviderCalls: 0, costUSD: 0,
  providerEnvNamesRemoved: 13, rProfilesDisabled: true, workerTimeoutMilliseconds: 180000, productionSHA256: {}};
for (const file of ["server.py", "qc_runtime.py", "run_review_runtime.py", "run_review_bridge.R", "run_continue_runtime.py", "run_continue_worker.py", "run_continue_bridge.R", "static/review.js", "static/review.html", "static/review.css"])
  report.productionSHA256[file] = sha(await fs.readFile(path.join(workbench, file)));
const checkpointNames = await fs.readdir(path.join(project, "checkpoints")), inputFiles = [];
for (const prefix of ["input", "qc_object", "strategy_basis"]) {
  const files = checkpointNames.filter(name => new RegExp("^" + prefix + "-[a-f0-9]{64}\\.rds$").test(name));
  assert.equal(files.length, 1, "Exactly one immutable upstream " + prefix + " checkpoint is expected"); inputFiles.push(...files);
}
const preprocessed = checkpointNames.filter(name => /^strategy_preprocess-[a-f0-9]{64}\.rds$/.test(name));
assert(preprocessed.length <= 1, "Preprocessing is either inline in the basis or one separate immutable checkpoint"); inputFiles.push(...preprocessed);
for (const prefix of ["prefilter", "qc_mad", "doublet_diagnostics", "cycle_diagnostics", "strategy_selected"]) inputFiles.push(...checkpointNames.filter(name => new RegExp("^" + prefix + "-[a-f0-9]{64}\\.rds$").test(name)));
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
  for (const [name, digest] of Object.entries(inputDigests)) assert.equal(sha(await fs.readFile(path.join(project, "checkpoints", name))), digest, "Immutable input/QC/selection/preprocessing/PCA/optional diagnostic checkpoint changed");
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
  review_hash: run.review_node.review_hash, expected_revision: run.revision, reviewer: "Offline synthetic Harmony Chrome analyst", reason: "Concentrated explicitly declared Harmony choice and computed first-50-PC policy on a software-only synthetic crossed design"};}
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
function pcProof(run) {
  const record = run.strategy_review.details.pc_diagnostics;
  assert.equal(record.schema, "scagentkit.strategy.pc-review.v1"); assert.equal(record.status, "computed");
  assert(/^[a-f0-9]{64}$/.test(record.artifact.sha256)); assert(/^[a-f0-9]{64}$/.test(record.basis_dependency_hash));
  const candidates = record.actual.top50_candidates;
  assert.equal(candidates.schema, "scagentkit.pc.candidates.v1"); assert.equal(candidates.total_computed_pcs, 55); assert.equal(candidates.reference_pcs, 50); assert.equal(candidates.target_reference_pcs, 50); assert.equal(candidates.shortfall, false);
  for (const [key, threshold] of [["p80", .8], ["p85", .85]]) {const row = candidates.candidates[key]; assert.equal(row.threshold, threshold); assert.equal(row.supported, true); assert.equal(row.ndim, candidates.cumulative_fraction.findIndex(value => value >= threshold) + 1); assert(row.ndim >= 2);}
  return record;
}
function normalizePlan(proposal) {
  const normalized = structuredClone(proposal);
  // Only a declared character/numeric vector can be singleton-auto-unboxed
  // by R JSON. The submitted request and every other field stay exact.
  normalized.batch.group_by_vars = array(normalized.batch.group_by_vars); return normalized;
}
async function displayedPCs(run) {
  const record = pcProof(run); assert.equal(await ui("pc-status").getAttribute("data-status"), "computed");
  const text = await ui("pc-candidates").textContent(); for (const row of Object.values(record.actual.top50_candidates.candidates)) assert(text.includes(String(row.ndim)));
  assert(text.includes("Computed PCs: 55") && text.includes("reference PCs: 50") && text.includes("shortfall: 0"));
  assert((await ui("pc-policy-note").textContent()).includes("not total expressed-gene variance")); assert((await ui("pc-policy-note").textContent()).includes("not universal optima"));
  return record;
}
async function debugPage() {
  if (!page || page.isClosed()) return;
  try {
    report.failureUI = await page.evaluate(() => {
      const text = id => document.getElementById(id)?.textContent?.trim() || "";
      return {status: text("run-status"), message: text("run-message"), messageHidden: document.getElementById("run-message")?.hidden, continuationNote: text("run-continuation-note"), jobStatus: text("run-job-status"), scopeStatus: text("harmony-provenance"), controller: typeof state === "object" ? {busy: state.busy, stale: state.stale, connectionLost: state.connectionLost, awaitingFreshInspect: state.awaitingFreshInspect, status: state.view?.run.status, stage: state.view?.run.stage, revision: state.view?.run.revision} : null};
    });
    await screenshot("failure-ui-status-and-message");
  } catch (error) {report.failureUIError = error.message;}
}
try {
  const baseline = await history(); report.initialHistory = baseline.stages;
  initial = (await startServer()).run;
  assert.equal(initial.status, "awaiting_review"); assert.equal(initial.stage, "strategy_propose"); assert.equal(initial.review_node.kind, "strategy");
  const details = initial.strategy_review.details, canonical = details.canonical_proposal, facts = details.background.facts;
  assert.equal(details.applicability.executable, true); assert.equal(canonical.batch.method, "none"); assert.deepEqual(canonical.pcs, {method: "computed_top50", threshold: .8});
  assert.equal(facts.design.technical_batch, true); assert.equal(facts.columns.batch, "technical_batch");
  assert.notEqual(facts.columns.batch, facts.columns.capture); assert.notEqual(facts.columns.batch, facts.columns.condition); assert.notEqual(facts.columns.batch, facts.columns.group);
  report.savedPCs = pcProof(initial); report.initialInputHash = initial.input_hash;
  for (const stage of ["qc_apply", "strategy_basis"]) assert.equal(baseline.stages.filter(value => value === stage).length, 1);
  const optionalFoundationStages = {};
  for (const stage of ["strategy_preprocess", "strategy_selection"]) {const count = baseline.stages.filter(value => value === stage).length; assert(count === 0 || count === 1); optionalFoundationStages[stage] = count;}
  assert.equal(optionalFoundationStages.strategy_preprocess, preprocessed.length);
  report.optionalFoundationStages = {...optionalFoundationStages, normalizationAndHVGLocation: preprocessed.length ? "separate preprocessing checkpoint" : "inline in the single PCA basis checkpoint"};
  assert.equal(baseline.stages.filter(stage => stage === "strategy_batch").length, 0); assert.equal(baseline.approvals.filter(event => event.details.kind === "annotation").length, 0);
  report.initialSnapshot = {projectId: initial.project_id, revision: initial.revision, proposalHash: initial.review_node.proposal_hash, reviewHash: initial.review_node.review_hash, evidenceHash: initial.strategy_review.evidence_hash, implementationHash: initial.implementation_hash};
  profile = await fs.mkdtemp(path.join(output, ".owned-chrome-profile-")); report.isolatedProfile = true;
  context = await chromium.launchPersistentContext(profile, {headless: true, env, executablePath: args.chrome || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", viewport: {width: 1440, height: 1100}});
  browser = context.browser(); report.actualChrome = true; report.chromeVersion = browser?.version() || "Chrome persistent context";
  await context.route("**/*", route => {const request = route.request(), url = request.url(); if (url.startsWith(origin + "/") && (["GET", "HEAD"].includes(request.method()) || request.method() === "POST" && ["/api/run-review/decision", "/api/run-review/continue"].includes(new URL(url).pathname)) || url.startsWith("data:")) return route.continue(); report.externalRequests.push(url); return route.abort();});
  page = await context.newPage(); page.setDefaultTimeout(45000); page.on("pageerror", error => report.pageErrors.push(error.message)); page.on("dialog", async dialog => {report.unexpectedDialogs.push({type: dialog.type()}); await dialog.dismiss();});
  await page.goto(origin + "/"); await rendered("awaiting_review", "strategy_propose");
  await test("actual Chrome displays cached 55-PC basis, real 80/85 candidates and explicit batch design before correction", async () => {
    assert.equal(await ui("run-strategy").isVisible(), true); assert.equal(await ui("run-qc").isVisible(), false); assert.equal(await ui("run-annotation").isVisible(), false);
    assert.deepEqual(JSON.parse(await ui("strategy-json").inputValue()), canonical); await displayedPCs(initial);
    assert.equal(await ui("harmony-method").inputValue(), "none"); assert.equal(await ui("pc-top50-threshold").inputValue(), "0.8");
    assert((await ui("harmony-provenance").textContent()).includes("technical_batch: TRUE")); assert((await ui("harmony-provenance").textContent()).includes("technical_batch"));
    assert((await ui("harmony-risk").textContent()).includes("not a claim that its effect is preserved")); assert((await ui("harmony-risk").textContent()).includes("UMAP looks cleaner"));
    assert.equal(await page.locator("#harmony-card button, #pc-card button").count(), 0); await screenshot("01-cached-basis-explicit-batch-design");
  });
  await test("typed Harmony and 85% selector drafts one complete plan, then saved review rejects stale approval without computation", async () => {
    const beforeDraft = await scientificSnapshot(); await ui("harmony-method").selectOption("harmony"); assert.equal(await ui("strategy-save").isDisabled(), true);
    for (const key of ["group_by_vars", "theta", "lambda", "sigma", "max_iter", "nclust"]) await ui("harmony-" + key).fill(JSON.stringify(harmonyChoice[key]));
    await ui("harmony-reason").fill(harmonyChoice.reason); await ui("pc-top50-threshold").selectOption("0.85");
    assert.equal(await ui("strategy-approve").isDisabled(), true); assert.equal(await ui("strategy-save").isDisabled(), false); assert.deepEqual(await scientificSnapshot(), beforeDraft);
    const proposal = JSON.parse(await ui("strategy-json").inputValue()); assert.deepEqual(proposal.batch, harmonyChoice); assert.deepEqual(proposal.pcs, {method: "computed_top50", threshold: .85});
    await ui("strategy-reviewer").fill("Offline synthetic Harmony Chrome analyst"); await ui("strategy-reason").fill("Approve an explicit crossed synthetic technical-factor experiment and computed first-50-PC 85% policy for software validation only; do not optimize biology from UMAP or retained-cell counts.");
    const response = await responseFrom("strategy-save", "/api/run-review/decision"); assert.equal(response.status(), 200); const request = response.request().postDataJSON(); assert.equal(request.action, "revise"); assert.deepEqual(request.proposal, proposal);
    await rendered("awaiting_review", "strategy_propose"); revised = (await inspect()).run;
    assert.equal(revised.input_hash, initial.input_hash); assert.notEqual(revised.review_node.review_hash, initial.review_node.review_hash); assert.notEqual(revised.review_node.proposal_hash, initial.review_node.proposal_hash); assert.equal(revised.strategy_review.evidence_hash, initial.strategy_review.evidence_hash);
    assert.deepEqual(normalizePlan(revised.strategy_review.details.canonical_proposal), normalizePlan(proposal)); assert.equal(revised.strategy_review.details.harmony.executable, true); report.harmonyReview = revised.strategy_review.details.harmony;
    const afterPC = await displayedPCs(revised); assert.deepEqual(afterPC.actual, report.savedPCs.actual); assert.equal(afterPC.artifact.sha256, report.savedPCs.artifact.sha256); assert.equal(afterPC.basis_dependency_hash, report.savedPCs.basis_dependency_hash);
    const unchanged = await history(); assert.deepEqual(unchanged.stages, baseline.stages); assert.equal(unchanged.approvals.length, baseline.approvals.length);
    const beforeStale = await scientificSnapshot(), rejection = await staleApproval(initial); assert.deepEqual(await scientificSnapshot(), beforeStale);
    assert.equal(await ui("strategy-approve").isDisabled(), false); report.revision = {...rejection, oldRevision: initial.revision, newRevision: revised.revision, oldProposalHash: initial.review_node.proposal_hash, newProposalHash: revised.review_node.proposal_hash, oldReviewHash: initial.review_node.review_hash, newReviewHash: revised.review_node.review_hash, staleApprovalScientificBytesUnchanged: true}; await screenshot("02-explicit-harmony-p85-concentrated-review");
  });
  await test("one central approval and actual fixed R Continue execute Harmony once while preserving QC and PCA", async () => {
    await ui("strategy-reviewer").fill("Offline synthetic Harmony Chrome analyst"); await ui("strategy-reason").fill("Approve the exact technical Harmony parameters and actual first-50-PC 85% policy as software-only validation. Retain source raw counts and metadata; labels require separate review.");
    const decision = await responseFrom("strategy-approve", "/api/run-review/decision"); assert.equal(decision.status(), 200); assert.equal(decision.request().postDataJSON().action, "approve");
    approved = (await inspect()).run; assert.equal(approved.status, "ready"); assert.equal(approved.input_hash, initial.input_hash); await rendered("ready", approved.stage); assert.equal(await ui("run-continue").isDisabled(), false);
    const accepted = await responseFrom("run-continue", "/api/run-review/continue"); assert.equal(accepted.status(), 202); const submission = accepted.request().postDataJSON(), queued = await accepted.json();
    assert.deepEqual(Object.keys(submission).sort(), ["project_id", "input_hash", "expected_revision", "request_id", "retry"].sort()); assert.equal(submission.retry, false); activeJobId = queued.job.job_id; assert(/^[a-f0-9]{32}$/.test(activeJobId)); report.savedJobId = activeJobId;
    const completed = await terminalJob(activeJobId); assert.equal(completed.job.status, "succeeded"); assert.equal(completed.job.next_run_status, "awaiting_configuration"); assert.equal(completed.job.next_run_stage, "annotation_propose");
    const directory = path.join(project, ".workbench-jobs", "jobs", activeJobId), owner = JSON.parse(await fs.readFile(path.join(directory, "owner.json"), "utf8")), config = JSON.parse(await fs.readFile(path.join(directory, "config.json"), "utf8")), responseBytes = await fs.readFile(path.join(directory, "response.json")), response = JSON.parse(responseBytes);
    assert(owner.r_pid > 0 && owner.worker_pid > 0 && owner.r_pid !== owner.worker_pid); assert.equal(owner.r_exit_code, 0); assert.equal(path.basename(config.bridge), "run_continue_bridge.R"); assert.equal(config.library, args["r-library"]); assert.equal(response.ok, true); assert.equal(response.result.input_hash, initial.input_hash);
    report.actualRBridge = true; report.jobs.push({public: completed.job, owner, codeHashes: config.code_hashes, responseSHA256: sha(responseBytes), result: response.result}); activeJobId = null;
    await refresh(); await rendered("awaiting_configuration", "annotation_propose"); stopped = (await inspect()).run;
    assert.equal(stopped.input_hash, initial.input_hash); assert(stopped.review_node == null); assert(stopped.output == null); assert(stopped.annotation_review == null);
    assert.equal(stopped.strategy_review.details.canonical_proposal.batch.method, "harmony"); assert.deepEqual(stopped.strategy_review.details.canonical_proposal.pcs, {method: "computed_top50", threshold: .85});
    assert.equal(await ui("run-continue").isDisabled(), true); assert((await ui("run-continuation-note").textContent()).includes("current run needs configuration"));
    const after = await history(); assert.equal(after.approvals.filter(event => event.details.kind === "strategy").length, baseline.approvals.filter(event => event.details.kind === "strategy").length + 1); for (const kind of ["qc", "annotation"]) assert.equal(after.approvals.filter(event => event.details.kind === kind).length, 0);
    for (const stage of ["prefilter", "strategy_evidence", "qc_apply", "strategy_selection", "strategy_preprocess", "strategy_basis"]) assert.equal(after.stages.filter(value => value === stage).length, baseline.stages.filter(value => value === stage).length);
    assert.equal(after.stages.filter(stage => stage === "strategy_batch").length, 1); for (const stage of ["strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence"]) assert.equal(after.stages.filter(value => value === stage).length, baseline.stages.filter(value => value === stage).length + 1);
    assert.equal(after.stages.includes("annotation_apply"), false); assert.equal(after.stages.includes("finalize"), false); report.executionStages = after.stages; report.approvals = after.approvals.map(event => ({sequence: event.sequence, kind: event.details.kind, proposalHash: event.details.proposal_hash, reviewHash: event.details.review_hash, decisionId: event.details.decision_id}));
    report.stop = {status: stopped.status, stage: stopped.stage, revision: stopped.revision, inputHash: stopped.input_hash, historyHead: stopped.history_head, annotationApplied: false, batchMethod: "harmony", pcPolicy: {method: "computed_top50", threshold: .85}, biologicalResultAccepted: false}; await screenshot("03-harmony-annotation-configuration-stop");
  });
  assert.equal(report.pageErrors.length, 0); assert.equal(report.externalRequests.length, 0); assert.equal(report.unexpectedDialogs.length, 0); for (const [file, digest] of Object.entries(report.productionSHA256)) assert.equal(sha(await fs.readFile(path.join(workbench, file))), digest, "Production changed during acceptance"); report.passed = true;
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
