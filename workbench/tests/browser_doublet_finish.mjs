#!/usr/bin/env node
/** READONLY actual Chrome verification after root completes the approved public
 * PBMC doublet project. Requires a completely passed matching scientific
 * browser attempt and preserves its original successful worker receipts.
 * No decision, Continue or scientific execution; every project byte is checked.
 */
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import {spawn} from "node:child_process";
import {createRequire} from "node:module";
import {fileURLToPath} from "node:url";

const args = {}, allowed = new Set(["project", "output", "r-library", "implementation", "python", "rscript", "chrome", "playwright"]);
for (let index = 2; index < process.argv.length; index += 2) {
  const name = process.argv[index]?.slice(2); assert(process.argv[index]?.startsWith("--") && allowed.has(name) && process.argv[index + 1]);
  assert(!Object.hasOwn(args, name)); args[name] = process.argv[index + 1];
}
assert(args.project && args.output && args["r-library"] && /^[a-f0-9]{64}$/.test(args.implementation || ""));
const workbench = path.resolve(path.dirname(fileURLToPath(import.meta.url)), ".."), workspace = path.dirname(path.dirname(workbench));
const fixtureRoot = path.join(workspace, "evidence", "doublet-public-pbmc"), project = path.resolve(args.project), output = path.resolve(args.output);
const projectVersion = project === path.join(fixtureRoot, "project") ? "" : project === path.join(fixtureRoot, "project-v2") ? "-v2" : null;
assert(projectVersion !== null, "Only the explicitly authorized public project or project-v2 is supported"); assert.equal(output, path.join(fixtureRoot, "browser-finish" + projectVersion));
assert.equal(await fs.realpath(project), project); assert.equal((await fs.lstat(project)).isSymbolicLink(), false);
await fs.mkdir(output, {recursive: true}); assert.equal(await fs.realpath(output), output);
const exists = file => fs.access(file).then(() => true, () => false), sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
const array = value => value == null ? [] : Array.isArray(value) ? value : [value], pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const reportFile = path.join(output, "doublet-finish-browser-report.json"); assert.equal(await exists(reportFile), false, "Never overwrite recovery evidence");
const priorFile = path.join(fixtureRoot, "browser" + projectVersion, "doublet-browser-report.json"), priorBytes = await fs.readFile(priorFile), prior = JSON.parse(priorBytes);
assert.equal(prior.passed, true); assert.equal(prior.actualChrome, true); assert.equal(prior.actualRBridge, true); assert.equal(prior.tests.length, 3); assert(prior.tests.every(test => test.outcome === "passed"));
assert.equal(prior.jobs.length, 1); assert.equal(prior.jobs[0].public.status, "succeeded"); assert.equal(prior.jobs[0].owner.r_exit_code, 0);
assert.equal(prior.jobs[0].result.status, "awaiting_configuration"); assert.equal(prior.jobs[0].result.stage, "annotation_propose");
assert.equal(prior.requiredImplementationHash, args.implementation); assert(/^[a-f0-9]{32}$/.test(prior.savedJobId));
const env = {...process.env, PYTHONDONTWRITEBYTECODE: "1", R_LIBS_USER: args["r-library"], SCAGENTKIT_EXPECTED_IMPLEMENTATION: args.implementation,
  R_PROFILE_USER: "/dev/null", R_ENVIRON_USER: "/dev/null", R_PROFILE: "/dev/null", R_ENVIRON: "/dev/null"};
for (const key of ["DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY", "AZURE_OPENAI_API_KEY", "COHERE_API_KEY", "MISTRAL_API_KEY", "OPENROUTER_API_KEY", "HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN"]) delete env[key];
const {chromium} = createRequire(import.meta.url)(args.playwright || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
const report = {schema: "scagentkit.doublet.readonly-finish-browser.v1", startedAt: new Date().toISOString(), project, output, requiredImplementationHash: args.implementation,
  driverSHA256: sha(await fs.readFile(fileURLToPath(import.meta.url))), projectVersion: projectVersion || "v1", readonly: true, actualChrome: false, actualRBridge: false, newScientificExecutions: 0, newDecisionRequests: 0, newContinueRequests: 0, newProviderCalls: 0, realAPIRequests: 0, costUSD: 0,
  tests: [], screenshots: [], pageErrors: [], externalRequests: [], unexpectedDialogs: [], unexpectedMutationRequests: [], inspectResponses: [], providerEnvNamesRemoved: 13, rProfilesDisabled: true,
  scientificBrowserAttempt: {path: priorFile, sha256: sha(priorBytes), driverSHA256: prior.driverSHA256, passed: prior.passed, tests: 3,
    passedTests: prior.tests.filter(test => test.outcome === "passed").length, failedTests: prior.tests.filter(test => test.outcome === "failed").length,
    successfulJobId: prior.savedJobId, scientificReplay: false}};
let server, context, browser, page, profile, origin, serverError, current;
const lifecycle = [];
async function snapshot() {
  const files = {};
  async function walk(directory) {for (const item of await fs.readdir(directory, {withFileTypes: true})) {assert.equal(item.isSymbolicLink(), false); const file = path.join(directory, item.name); if (item.isDirectory()) await walk(file); else if (item.isFile()) files[path.relative(project, file)] = sha(await fs.readFile(file));}}
  await walk(project); return files;
}
const before = await snapshot(), ledgerFile = path.join(project, "provider", "ledger.json"), ledgerPresent = await exists(ledgerFile), initialLedgerSHA256 = ledgerPresent ? sha(await fs.readFile(ledgerFile)) : null;
async function protect() {
  assert.equal(sha(await fs.readFile(priorFile)), report.scientificBrowserAttempt.sha256);
  for (const [name, digest] of Object.entries(prior.immutableCheckpointSHA256)) assert.equal(sha(await fs.readFile(path.join(project, "checkpoints", name))), digest);
  assert.equal(await exists(ledgerFile), ledgerPresent); assert.equal(initialLedgerSHA256, prior.initialLedgerSHA256);
  if (ledgerPresent) {const bytes = await fs.readFile(ledgerFile); assert.equal(sha(bytes), initialLedgerSHA256); for (const entry of array(JSON.parse(bytes).entries)) {assert.equal(entry.provider.external, false); assert.equal(entry.cost_usd, 0); assert.equal(entry.charged_or_held_usd, 0);}}
}
async function test(name, action) {const start = Date.now(); try {await action(); await protect(); report.tests.push({name, outcome: "passed", milliseconds: Date.now() - start}); console.log("PASS " + name);} catch (error) {report.tests.push({name, outcome: "failed", error: error.message}); throw error;}}
async function startServer() {
  server = spawn(args.python || "python3", [path.join(workbench, "server.py"), "--run-project", project, "--local-continue", "--r-library", args["r-library"], "--rscript", args.rscript || "Rscript", "--port", "0"], {cwd: path.dirname(workbench), env, stdio: ["ignore", "pipe", "pipe"]});
  lifecycle.push({event: "owned_readonly_server_started", pid: server.pid, portRequested: 0}); let startup = ""; server.once("error", error => {serverError = error;});
  server.stdout.on("data", bytes => {startup = (startup + bytes.toString()).slice(-8192); const match = startup.match(/scAgentKit workbench: (http:\/\/127\.0\.0\.1:[0-9]+)/); if (match) origin = match[1];}); server.stderr.on("data", () => {});
  const deadline = Date.now() + 45000; while (!origin && Date.now() < deadline) {if (serverError) throw serverError; assert.equal(server.exitCode, null); await pause(100);} assert(origin); report.ownedLoopbackOrigin = origin;
}
async function stopServer() {
  if (!server || server.exitCode != null || server.signalCode != null) return;
  const owned = server, closed = new Promise(resolve => owned.once("exit", resolve)); owned.kill("SIGTERM"); await Promise.race([closed, pause(3000)]);
  if (owned.exitCode == null && owned.signalCode == null) {owned.kill("SIGKILL"); await closed;} lifecycle.push({event: "owned_readonly_server_stopped", pid: owned.pid, exitCode: owned.exitCode, signal: owned.signalCode});
}
async function inspect() {
  const response = await fetch(origin + "/api/run-review/inspect"), answer = await response.json(); assert.equal(response.status, 200); assert.equal(answer.schema, "scagentkit.run-review.workbench.v1"); assert.equal(answer.run.implementation_hash, args.implementation); assert.equal(answer.run.input_hash, prior.initialInputHash); return answer;
}
const ui = id => page.locator('[data-testid="' + id + '"]');
async function renderedCurrent() {await page.waitForFunction(({status, stage}) => document.getElementById("run-status").textContent.trim() === status + " / " + stage && !document.getElementById("run-refresh").disabled, {status: current.status, stage: current.stage}, {timeout: 45000});}
async function screenshot(label) {const file = path.join(output, label + ".png"); assert.equal(await exists(file), false); await page.screenshot({path: file, fullPage: true}); report.screenshots.push(file);}
async function debugPage() {
  if (!page || page.isClosed()) return;
  try {report.failureUI = await page.evaluate(() => {const text = id => document.getElementById(id)?.textContent?.trim() || ""; return {status: text("run-status"), message: text("run-message"), messageHidden: document.getElementById("run-message")?.hidden, continuationNote: text("run-continuation-note"), scopeStatus: text("doublet-scope-status"), controller: typeof state === "object" ? {busy: state.busy, stale: state.stale, connectionLost: state.connectionLost, status: state.view?.run.status, stage: state.view?.run.stage, revision: state.view?.run.revision} : null};}); await screenshot("failure-ui-status-and-message");} catch (error) {report.failureUIError = error.message;}
}
try {
  await protect(); await startServer(); current = (await inspect()).run; assert.equal(current.status, "complete"); assert.equal(current.stage, "complete"); assert(current.review_node == null || current.review_node.kind === "annotation" && current.review_node.can_decide === false && current.review_node.can_revise === false);
  assert.deepEqual(current.strategy_review.details.doublet_diagnostics, prior.savedDoubletEvidence); const impact = current.strategy_review.details.applicability.doublet;
  assert.deepEqual(impact, prior.removalImpact); assert.equal(impact.method, "remove_predicted"); assert(impact.removed_cells > 0);
  profile = await fs.mkdtemp(path.join(output, ".owned-readonly-chrome-profile-")); context = await chromium.launchPersistentContext(profile, {headless: true, env, executablePath: args.chrome || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", viewport: {width: 1440, height: 1100}});
  browser = context.browser(); report.actualChrome = true; report.chromeVersion = browser?.version() || "Chrome persistent context";
  await context.route("**/*", route => {const request = route.request(), url = request.url(); if (!["GET", "HEAD"].includes(request.method())) {report.unexpectedMutationRequests.push({method: request.method(), path: new URL(url).pathname}); return route.abort();} if (url.startsWith(origin + "/") || url.startsWith("data:")) return route.continue(); report.externalRequests.push(url); return route.abort();});
  page = await context.newPage(); page.setDefaultTimeout(45000); page.on("pageerror", error => report.pageErrors.push(error.message)); page.on("dialog", async dialog => {report.unexpectedDialogs.push({type: dialog.type()}); await dialog.dismiss();});
  page.on("response", async response => {if (new URL(response.url()).pathname !== "/api/run-review/inspect") return; const receipt = {httpStatus: response.status()}; report.inspectResponses.push(receipt); try {const answer = await response.json(); receipt.status = answer.run?.status; receipt.stage = answer.run?.stage; receipt.revision = answer.run?.revision; if (!response.ok()) receipt.error = answer.error;} catch (error) {receipt.readError = error.message;}});
  await page.goto(origin + "/"); await renderedCurrent();
  await test("actual readonly Chrome displays completed PBMC output and the full saved algorithm deletion scope", async () => {
    assert.equal(await ui("run-complete").isVisible(), true); assert.equal(await ui("run-strategy").isVisible(), true); assert.equal(await ui("run-qc").isVisible(), false); assert.equal(await ui("run-annotation").isVisible(), true);
    for (const id of ["strategy-json", "strategy-approve", "strategy-save", "run-continue", "annotation-approve"]) assert.equal(await ui(id).isDisabled(), true);
    assert.equal(JSON.parse(await ui("strategy-json").inputValue()).doublet.method, "remove_predicted"); assert.equal(await ui("doublet-scope-status").getAttribute("data-status"), "verified");
    await ui("doublet-cell-scope").locator("summary").click(); assert.equal((await ui("doublet-cell-ids").textContent()).trim(), array(impact.removed_cell_ids).join("\n")); await ui("doublet-cell-scope").locator("summary").click();
    assert((await ui("doublet-risk").textContent()).includes("not a calibrated probability")); assert((await ui("doublet-cohort").textContent()).includes("no refit after QC or deletion"));
    const details = current.annotation_review.details; assert.equal(details.cell_count, impact.retained_cells); assert(details.cluster_count > 0);
    assert.equal(array(details.input_cells).length, impact.retained_cells); assert.deepEqual(new Set(array(details.input_cells).map(row => row.cell_id)), new Set(array(impact.selected_cell_ids)));
    const outputText = await ui("run-output").textContent(); assert(outputText.includes("seurat.rds") && outputText.includes("report.md")); assert((await ui("run-continuation-note").textContent()).includes("current saved run has completed output"));
    report.currentRun = {status: current.status, stage: current.stage, revision: current.revision, inputHash: current.input_hash, cells: details.cell_count, clusters: details.cluster_count, doubletMethod: "remove_predicted", removedCells: impact.removed_cells, labels: array(details.annotations).map(row => ({cluster: row.clusterId, label: row.proposal.label, confidence: row.proposal.confidence})), scientificIdentityValidated: false};
    await screenshot("01-complete-public-doublet-output");
  });
  await test("the original actual fixed R job and new final annotation audit remain saved without another worker", async () => {
    const directory = path.join(project, ".workbench-jobs", "jobs", prior.savedJobId), job = JSON.parse(await fs.readFile(path.join(directory, "job.json"), "utf8")), owner = JSON.parse(await fs.readFile(path.join(directory, "owner.json"), "utf8")), config = JSON.parse(await fs.readFile(path.join(directory, "config.json"), "utf8")), responseBytes = await fs.readFile(path.join(directory, "response.json")), response = JSON.parse(responseBytes);
    assert.equal(job.status, "succeeded"); assert.equal(job.next_run_status, "awaiting_configuration"); assert.equal(job.next_run_stage, "annotation_propose"); assert.equal(path.basename(config.bridge), "run_continue_bridge.R"); assert.equal(config.library, args["r-library"]);
    assert(owner.r_pid > 0 && owner.worker_pid > 0 && owner.r_pid !== owner.worker_pid); assert.equal(owner.r_exit_code, 0); assert.equal(response.ok, true); assert.equal(response.result.input_hash, prior.initialInputHash); assert.equal(sha(responseBytes), prior.jobs[0].responseSHA256); report.actualRBridge = true;
    const history = JSON.parse(await fs.readFile(path.join(project, "decision_history.json"), "utf8")), approvals = array(history.events).filter(event => event.action === "approved"), stages = array(history.events).filter(event => event.action === "executed").map(event => event.details.stage);
    assert.equal(approvals.filter(event => event.details.kind === "strategy").length, 2); assert.equal(approvals.filter(event => event.details.kind === "qc").length, 0); assert.equal(approvals.filter(event => event.details.kind === "annotation").length, 1);
    const browserApprovals = approvals.filter(event => event.details.kind === "strategy" && event.details.proposal_hash === prior.revision.newProposalHash && event.details.review_hash === prior.revision.newReviewHash);
    assert.equal(browserApprovals.length, 1); assert.equal(browserApprovals[0].details.input_hash, prior.initialInputHash);
    for (const stage of new Set(prior.executionStages)) assert.equal(stages.filter(value => value === stage).length, prior.executionStages.filter(value => value === stage).length);
    for (const stage of ["strategy_evidence", "qc_apply"]) assert.equal(stages.filter(value => value === stage).length, 1);
    for (const stage of ["strategy_selection", "strategy_preprocess", "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence"]) assert.equal(stages.filter(value => value === stage).length, 2);
    for (const stage of ["annotation_apply", "finalize"]) assert.equal(stages.filter(value => value === stage).length, 1);
    report.savedJobProof = {job, owner, responseSHA256: sha(responseBytes), codeHashes: config.code_hashes, replayed: false, proofSource: "Original successful actual R worker; no new R continuation was launched"}; report.approvalKinds = approvals.map(event => event.details.kind); report.executionStages = stages;
    report.postWorkerAuditChecks = {originalAnnotationConfiguration: {status: response.result.status, stage: response.result.stage, revision: response.result.revision}, finalRootAnnotationApprovals: 1, finalAnnotationApply: 1, finalFinalize: 1, originalScientificBrowserPassed: true};
  });
  await test("readonly refresh preserves every project byte, original successful browser receipt and completed output hashes", async () => {
    await ui("run-refresh").click(); await renderedCurrent(); const latest = (await inspect()).run;
    assert.equal(latest.revision, current.revision); assert.equal(latest.history_head, current.history_head); assert.deepEqual(latest.output, current.output); report.outputHashes = {};
    for (const [name, value] of Object.entries(current.output || {})) if (["seurat", "report"].includes(name)) {const file = path.resolve(value); assert(file.startsWith(project + path.sep)); report.outputHashes[name] = {path: file, sha256: sha(await fs.readFile(file))};}
    assert.deepEqual(await snapshot(), before);
  });
  assert.equal(report.pageErrors.length, 0); assert.equal(report.externalRequests.length, 0); assert.equal(report.unexpectedDialogs.length, 0); assert.equal(report.unexpectedMutationRequests.length, 0); report.passed = true;
} catch (error) {report.passed = false; report.error = error.stack; await debugPage(); console.error(error.stack); process.exitCode = 1;}
finally {
  try {await context?.close(); if (browser?.isConnected()) await browser.close();} catch (error) {report.passed = false; report.chromeCleanupError = error.message; process.exitCode = 1;}
  try {await stopServer();} catch (error) {report.passed = false; report.serverCleanupError = error.message; process.exitCode = 1;}
  if (profile) {await fs.rm(profile, {recursive: true, force: true}); report.isolatedProfileRemoved = true;}
  try {await protect(); assert.deepEqual(await snapshot(), before); report.allProjectBytesUnchanged = true;} catch (error) {report.passed = false; report.preservationError = error.message; process.exitCode = 1;}
  report.completedAt = new Date().toISOString(); report.lifecycle = lifecycle; await fs.writeFile(path.join(output, "server-lifecycle.json"), JSON.stringify(lifecycle, null, 2) + "\n"); await fs.writeFile(reportFile, JSON.stringify(report, null, 2) + "\n");
}
