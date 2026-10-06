#!/usr/bin/env node
/** Actual Chrome + fixed R acceptance for ONE fresh public PBMC strategy run.
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
const fixtureRoot = path.join(workspace, "evidence", "strategy-public-pbmc"), project = path.resolve(args.project), output = path.resolve(args.output);
assert.equal(project, path.join(fixtureRoot, "project"), "Only root's fresh public strategy project is authorized");
assert.equal(output, path.join(fixtureRoot, "browser"), "Use the isolated strategy browser evidence directory");
assert.equal((await fs.lstat(project)).isSymbolicLink(), false); assert.equal(await fs.realpath(project), project);
await fs.mkdir(output, {recursive: true}); assert.equal(await fs.realpath(output), output);
const exists = file => fs.access(file).then(() => true, () => false), reportFile = path.join(output, "strategy-browser-report.json");
assert.equal(await exists(reportFile), false, "Never overwrite prior browser evidence");
assert.equal(await exists(path.join(project, ".workbench-jobs")), false, "Root prepares the new project in R before browser jobs exist");
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex"), array = value => value == null ? [] : Array.isArray(value) ? value : [value];
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const env = {...process.env, PYTHONDONTWRITEBYTECODE: "1", R_LIBS_USER: args["r-library"], SCAGENTKIT_EXPECTED_IMPLEMENTATION: args.implementation,
  R_PROFILE_USER: "/dev/null", R_ENVIRON_USER: "/dev/null", R_PROFILE: "/dev/null", R_ENVIRON: "/dev/null"};
for (const key of ["DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY",
  "AZURE_OPENAI_API_KEY", "COHERE_API_KEY", "MISTRAL_API_KEY", "OPENROUTER_API_KEY", "HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN"]) delete env[key];
const require = createRequire(import.meta.url), {chromium} = require(args.playwright || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
const report = {schema: "scagentkit.strategy.browser-acceptance.v1", startedAt: new Date().toISOString(), project, output,
  requiredImplementationHash: args.implementation, library: args["r-library"], driverSHA256: sha(await fs.readFile(fileURLToPath(import.meta.url))),
  actualChrome: false, actualRBridge: false, simulatedRBridge: false, sourceOriginalsRead: false, tests: [], jobs: [], screenshots: [],
  pageErrors: [], externalRequests: [], unexpectedDialogs: [], newProviderCalls: 0, realAPIRequests: 0, paidProviderCalls: 0, costUSD: 0,
  providerEnvNamesRemoved: 13, rProfilesDisabled: true, workerTimeoutMilliseconds: 180000, productionSHA256: {}};
for (const file of ["server.py", "qc_runtime.py", "run_review_runtime.py", "run_review_bridge.R", "run_continue_runtime.py", "run_continue_worker.py", "run_continue_bridge.R", "static/review.js", "static/review.html", "static/review.css"])
  report.productionSHA256[file] = sha(await fs.readFile(path.join(workbench, file)));
const inputFiles = (await fs.readdir(path.join(project, "checkpoints"))).filter(name => /^input-[a-f0-9]{64}\.rds$/.test(name));
assert.equal(inputFiles.length, 1, "Exactly one fresh immutable input checkpoint is expected");
const inputDigests = {};
for (const name of inputFiles) {const file = path.join(project, "checkpoints", name); assert.equal((await fs.lstat(file)).isSymbolicLink(), false); inputDigests[name] = sha(await fs.readFile(file));}
report.inputCheckpointSHA256 = inputDigests;
const ledgerFile = path.join(project, "provider", "ledger.json"), ledgerBytes = await fs.readFile(ledgerFile), ledger = JSON.parse(ledgerBytes);
const entries = array(ledger.entries); assert.equal(entries.length, 1, "Root prepares one saved mock strategy response");
for (const entry of entries) {assert.equal(entry.provider?.external, false, "Only a local mock response belongs in this fixture"); assert.equal(entry.cost_usd, 0); assert.equal(entry.charged_or_held_usd, 0);}
report.initialMockResponses = entries.length; report.initialLedgerSHA256 = sha(ledgerBytes);
report.ledgerSummary = entries.map(entry => ({purpose: entry.purpose, status: entry.status, external: entry.provider.external, costUSD: entry.cost_usd, chargedOrHeldUSD: entry.charged_or_held_usd}));
let server, browser, context, page, profile, origin, token, activeJobId;
const lifecycle = [];
async function protectedInputs() {
  for (const [name, digest] of Object.entries(inputDigests)) assert.equal(sha(await fs.readFile(path.join(project, "checkpoints", name))), digest, "Immutable new input checkpoint changed");
  assert.equal(sha(await fs.readFile(ledgerFile)), report.initialLedgerSHA256, "Browser actions changed the mock provider ledger");
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
  try {await action(); await protectedInputs(); report.tests.push({name, outcome: "passed", milliseconds: Date.now() - started, inputAndLedgerUnchanged: true}); console.log("PASS " + name);}
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
  review_hash: run.review_node.review_hash, expected_revision: run.revision, reviewer: "Offline public strategy Chrome analyst", reason: "Exact whole supported strategy on public PBMC; no browser provider or arbitrary R dispatch"};}
async function staleApproval(run) {
  const response = await fetch(origin + "/api/run-review/decision", {method: "POST", headers: {"Content-Type": "application/json", Origin: origin, "X-ScAgentKit-Run-Token": token}, body: JSON.stringify(binding(run, "approve"))});
  const answer = await response.json(); assert.equal(response.status, 409, "Old actual strategy approval must fail at HTTP 409"); return {httpStatus: response.status, message: answer.error};
}
const ui = id => page.locator('[data-testid="' + id + '"]');
async function idle() {await ui("run-refresh").waitFor(); await page.waitForFunction(() => !document.getElementById("run-refresh").disabled);}
async function refresh() {await idle(); await ui("run-refresh").click(); await idle();}
async function screenshot(name) {const file = path.join(output, name + ".png"); assert.equal(await exists(file), false); await page.screenshot({path: file, fullPage: true}); report.screenshots.push(file);}
async function responseFrom(button, route) {
  const response = page.waitForResponse(answer => new URL(answer.url()).pathname === route && answer.request().method() === "POST");
  await ui(button).click(); return response;
}
async function terminalJob(jobId) {
  const deadline = Date.now() + report.workerTimeoutMilliseconds; let answer;
  while (Date.now() < deadline) {
    const response = await fetch(origin + "/api/run-review/continuation"); assert.equal(response.status, 200); answer = await response.json();
    assert.equal(answer.schema, "scagentkit.run-continue.workbench.v1"); assert.equal(answer.job.job_id, jobId);
    if (!["queued", "running"].includes(answer.job.status)) return answer;
    await pause(500);
  }
  report.interruptedByDriverDeadline = {jobId, lastVerifiedJob: answer?.job, detachedWorkerLeftRunning: true};
  throw new Error("180-second verification deadline reached; saved detached job remains untouched and may continue");
}
let initial, revised, approved, stopped;
try {
  initial = (await startServer()).run;
  assert.equal(initial.status, "awaiting_review"); assert.equal(initial.stage, "strategy_propose"); assert.equal(initial.review_node.kind, "strategy");
  assert.equal(initial.strategy_review.schema, "scagentkit.strategy.review.v1"); assert.equal(initial.strategy_review.hash, initial.review_node.review_hash);
  assert.equal(initial.strategy_review.details.canonical_proposal.schema, "scagentkit.strategy.v1"); assert.equal(initial.strategy_review.details.canonical_proposal.clustering.resolution, 0.4);
  assert.equal(initial.strategy_review.details.applicability.executable, true); report.initialInputHash = initial.input_hash;
  report.initialSnapshot = {projectId: initial.project_id, revision: initial.revision, proposalHash: initial.review_node.proposal_hash, reviewHash: initial.review_node.review_hash, evidenceHash: initial.strategy_review.evidence_hash, implementationHash: initial.implementation_hash};
  profile = await fs.mkdtemp(path.join(output, ".owned-chrome-profile-")); report.isolatedProfile = true;
  context = await chromium.launchPersistentContext(profile, {headless: true, env, executablePath: args.chrome || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", viewport: {width: 1440, height: 1100}});
  browser = context.browser(); report.actualChrome = true; report.chromeVersion = browser?.version() || "Chrome persistent context";
  await context.route("**/*", route => {const url = route.request().url(); if (url.startsWith(origin + "/") || url.startsWith("data:")) return route.continue(); report.externalRequests.push(url); return route.abort();});
  page = await context.newPage(); page.setDefaultTimeout(30000); page.on("pageerror", error => report.pageErrors.push(error.message));
  page.on("dialog", async dialog => {report.unexpectedDialogs.push({type: dialog.type()}); await dialog.dismiss();});
  await page.goto(origin + "/"); await idle();
  await test("actual Chrome central strategy displays typed QC/background/inferences with native readonly evidence", async () => {
    assert.equal(await ui("run-strategy").isVisible(), true); assert.equal(await ui("run-qc").isVisible(), false); assert.equal(await ui("run-annotation").isVisible(), false);
    assert.equal(await page.locator("#run-qc-frame").getAttribute("src"), null); assert.equal(await page.locator("#run-strategy details[open]").count(), 0);
    const displayed = JSON.parse(await ui("strategy-json").inputValue()); assert.deepEqual(displayed, initial.strategy_review.details.canonical_proposal);
    const background = await ui("strategy-background").textContent(); assert(background.includes("User-provided facts") && background.includes("Missing background") && background.includes("Model / proposal inferences"));
    assert(/human|Homo sapiens/i.test(background)); assert(/Blood|PBMC/i.test(background)); assert.equal(await page.locator("#strategy-operations > section").count(), 6);
    const unsupported = await ui("strategy-unsupported").textContent(); assert(/unsupported/i.test(unsupported) && /doublet/i.test(unsupported) && /subcluster/i.test(unsupported));
    assert.equal(await page.locator("#strategy-quality input, #strategy-quality textarea, #strategy-qc-impact button, #strategy-record input, #strategy-record textarea").count(), 0);
    const detail = page.locator("#run-strategy details").filter({hasText: "Actual quality summary and QC impact"}).first(); await detail.locator("summary").click();
    assert.equal(await detail.evaluate(node => node.open), true); assert((await ui("strategy-quality").textContent()).length > 40); assert((await ui("strategy-qc-impact").textContent()).includes("retained"));
    await detail.locator("summary").click(); await screenshot("01-central-public-strategy");
    report.displayedContext = {species: initial.context.species, tissue: initial.context.tissue, facts: initial.strategy_review.details.background.facts, missing: initial.strategy_review.details.background.missing,
      inferences: initial.strategy_review.details.canonical_proposal.inferences, quality: initial.strategy_review.details.quality};
  });
  await test("actual complete JSON resolution revision rebuilds hashes and rejects old approval without provider dispatch", async () => {
    const proposal = structuredClone(initial.strategy_review.details.canonical_proposal); proposal.clustering.resolution = 0.5;
    await ui("strategy-json").fill(JSON.stringify(proposal, null, 2)); assert.equal(await ui("strategy-approve").isDisabled(), true);
    await ui("strategy-reviewer").fill("Offline public strategy Chrome analyst"); await ui("strategy-reason").fill("Revise only clustering resolution from 0.4 to 0.5 in the complete supported public PBMC strategy.");
    const response = await responseFrom("strategy-save", "/api/run-review/decision"); assert.equal(response.status(), 200);
    const request = response.request().postDataJSON(); assert.equal(request.action, "revise"); assert.equal(request.kind, "strategy"); assert.deepEqual(request.proposal, proposal);
    assert.deepEqual(Object.keys(request).sort(), ["action", "kind", "project_id", "input_hash", "proposal_hash", "review_hash", "expected_revision", "reviewer", "reason", "proposal"].sort());
    await idle(); revised = (await inspect()).run; assert.equal(revised.input_hash, initial.input_hash); assert.equal(revised.status, "awaiting_review"); assert.equal(revised.review_node.kind, "strategy");
    assert.notEqual(revised.review_node.review_hash, initial.review_node.review_hash); assert.notEqual(revised.review_node.proposal_hash, initial.review_node.proposal_hash);
    assert.equal(revised.strategy_review.details.canonical_proposal.clustering.resolution, 0.5); assert.equal(revised.strategy_review.evidence_hash, initial.strategy_review.evidence_hash);
    const before = await scientificSnapshot(), rejection = await staleApproval(initial); assert.deepEqual(await scientificSnapshot(), before);
    assert.equal(await ui("strategy-approve").isDisabled(), false); report.revision = {...rejection, oldRevision: initial.revision, newRevision: revised.revision, oldProposalHash: initial.review_node.proposal_hash,
      newProposalHash: revised.review_node.proposal_hash, oldReviewHash: initial.review_node.review_hash, newReviewHash: revised.review_node.review_hash, resolutionBefore: 0.4, resolutionAfter: 0.5};
    await screenshot("02-revised-public-strategy");
  });
  await test("one actual whole-strategy approval and fixed R Continue stop at provider-free annotation configuration", async () => {
    await ui("strategy-reviewer").fill("Offline public strategy Chrome analyst"); await ui("strategy-reason").fill("Approve this complete locally validated public PBMC QC/PC/none-batch/resolution strategy. Annotation needs its later evidence review.");
    const decision = await responseFrom("strategy-approve", "/api/run-review/decision"); assert.equal(decision.status(), 200); const decisionPayload = decision.request().postDataJSON();
    assert.equal(decisionPayload.kind, "strategy"); assert.equal(decisionPayload.action, "approve"); assert.equal("proposal" in decisionPayload, false); await idle(); approved = (await inspect()).run;
    assert.equal(approved.status, "ready"); assert.equal(approved.stage, "strategy_apply"); assert.equal(approved.input_hash, initial.input_hash);
    assert.equal(await ui("run-qc").isVisible(), false); assert.equal(await ui("run-continue").isDisabled(), false);
    const accepted = await responseFrom("run-continue", "/api/run-review/continue"); assert.equal(accepted.status(), 202); const submission = accepted.request().postDataJSON(), queued = await accepted.json();
    assert.deepEqual(Object.keys(submission).sort(), ["project_id", "input_hash", "expected_revision", "request_id", "retry"].sort()); assert.equal(submission.retry, false);
    assert.equal(submission.input_hash, initial.input_hash); activeJobId = queued.job.job_id; assert(/^[a-f0-9]{32}$/.test(activeJobId)); report.savedJobId = activeJobId;
    const completed = await terminalJob(activeJobId); assert.equal(completed.job.status, "succeeded"); assert.equal(completed.job.next_run_status, "awaiting_configuration"); assert.equal(completed.job.next_run_stage, "annotation_propose");
    const directory = path.join(project, ".workbench-jobs", "jobs", activeJobId), owner = JSON.parse(await fs.readFile(path.join(directory, "owner.json"), "utf8")), config = JSON.parse(await fs.readFile(path.join(directory, "config.json"), "utf8"));
    const responseBytes = await fs.readFile(path.join(directory, "response.json")), response = JSON.parse(responseBytes);
    assert(owner.r_pid > 0 && owner.worker_pid > 0 && owner.r_pid !== owner.worker_pid); assert.equal(owner.r_exit_code, 0); assert.equal(path.basename(config.bridge), "run_continue_bridge.R");
    assert.equal(config.library, args["r-library"]); assert.equal(response.ok, true); assert.equal(response.result.input_hash, initial.input_hash); assert.equal(response.result.stage, "annotation_propose"); assert.equal(response.result.status, "awaiting_configuration");
    report.actualRBridge = true; report.jobs.push({public: completed.job, owner, codeHashes: config.code_hashes, responseSHA256: sha(responseBytes), result: response.result}); activeJobId = null;
    await refresh(); stopped = (await inspect()).run; assert.equal(stopped.status, "awaiting_configuration"); assert.equal(stopped.stage, "annotation_propose"); assert.equal(stopped.input_hash, initial.input_hash);
    assert.equal(stopped.output, null); assert.equal(stopped.implementation_hash, args.implementation); assert.equal(stopped.strategy_review.details.canonical_proposal.clustering.resolution, 0.5);
    assert.equal(await ui("run-qc").isVisible(), false); assert.equal(await ui("run-continue").isDisabled(), true);
    // The fresh R API can finish before the page's asynchronous refresh renders.
    // Status and stage share this element; preserve the first failed receipt.
    await page.waitForFunction(() => document.getElementById("run-status").textContent.trim() === "awaiting_configuration / annotation_propose");
    const history = JSON.parse(await fs.readFile(path.join(project, "decision_history.json"), "utf8")), approvals = array(history.events).filter(event => event.action === "approved");
    assert.equal(approvals.filter(event => event.details.kind === "strategy").length, 1); assert.equal(approvals.filter(event => event.details.kind === "qc").length, 0); assert.equal(approvals.filter(event => event.details.kind === "annotation").length, 0);
    const executions = array(history.events).filter(event => event.action === "executed").map(event => event.details.stage);
    for (const stage of ["qc_apply", "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers"]) assert.equal(executions.filter(value => value === stage).length, 1, "Supported stages execute exactly once");
    report.approvals = approvals.map(event => ({sequence: event.sequence, kind: event.details.kind, proposalHash: event.details.proposal_hash, reviewHash: event.details.review_hash, decisionId: event.details.decision_id}));
    report.executionStages = executions; report.stop = {status: stopped.status, stage: stopped.stage, revision: stopped.revision, inputHash: stopped.input_hash, historyHead: stopped.history_head, annotationApplied: false};
    await screenshot("03-saved-annotation-configuration-stop");
  });
  assert.equal(report.pageErrors.length, 0); assert.equal(report.externalRequests.length, 0); assert.equal(report.unexpectedDialogs.length, 0);
  for (const [file, digest] of Object.entries(report.productionSHA256)) assert.equal(sha(await fs.readFile(path.join(workbench, file))), digest, "Production changed during acceptance");
  report.passed = true;
} catch (error) {report.passed = false; report.error = error.stack; console.error(error.stack); process.exitCode = 1;}
finally {
  if (activeJobId) {
    try {const directory = path.join(project, ".workbench-jobs", "jobs", activeJobId); report.savedUnfinishedJob = {job: JSON.parse(await fs.readFile(path.join(directory, "job.json"), "utf8")), owner: JSON.parse(await fs.readFile(path.join(directory, "owner.json"), "utf8")), detachedWorkerLeftUntouched: true};}
    catch (_) {report.savedUnfinishedJob = {jobId: activeJobId, detachedWorkerLeftUntouched: true};}
  }
  try {await context?.close(); if (browser?.isConnected()) await browser.close();}
  catch (error) {report.passed = false; report.chromeCleanupError = error.message; process.exitCode = 1;}
  try {await stopServer();}
  catch (error) {report.passed = false; report.serverCleanupError = error.message; process.exitCode = 1;}
  if (profile) {await fs.rm(profile, {recursive: true, force: true}); report.isolatedProfileRemoved = true;}
  try {await protectedInputs(); report.inputAndMockLedgerUnchanged = true;}
  catch (error) {report.passed = false; report.preservationError = error.message; process.exitCode = 1;}
  report.completedAt = new Date().toISOString(); report.lifecycle = lifecycle;
  await fs.writeFile(path.join(output, "server-lifecycle.json"), JSON.stringify(lifecycle, null, 2) + "\n");
  await fs.writeFile(reportFile, JSON.stringify(report, null, 2) + "\n");
}
