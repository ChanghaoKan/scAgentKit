#!/usr/bin/env node
/** READONLY Chrome recovery after root's fresh-R manual annotation completion.
 * Preserves the first immediate DOM assertion failure and its successful real
 * strategy execution. No decision, Continue, provider callback or R script.
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
const fixtureRoot = path.join(workspace, "evidence", "strategy-public-pbmc"), project = path.resolve(args.project), output = path.resolve(args.output);
assert.equal(project, path.join(fixtureRoot, "project")); assert.equal(output, path.join(fixtureRoot, "browser-finish"));
assert.equal(await fs.realpath(project), project); assert.equal((await fs.lstat(project)).isSymbolicLink(), false);
await fs.mkdir(output, {recursive: true}); assert.equal(await fs.realpath(output), output);
const exists = file => fs.access(file).then(() => true, () => false), sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
const array = value => value == null ? [] : Array.isArray(value) ? value : [value], pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const reportFile = path.join(output, "strategy-finish-browser-report.json"); assert.equal(await exists(reportFile), false, "Never overwrite recovery evidence");
const priorFile = path.join(fixtureRoot, "browser", "strategy-browser-report.json"), priorBytes = await fs.readFile(priorFile), prior = JSON.parse(priorBytes);
assert.equal(prior.passed, false); assert.equal(prior.actualChrome, true); assert.equal(prior.actualRBridge, true);
assert.equal(prior.tests.filter(test => test.outcome === "passed").length, 2); assert(/run-status.*annotation_propose/s.test(prior.error));
assert.equal(prior.requiredImplementationHash, args.implementation); assert(/^[a-f0-9]{32}$/.test(prior.savedJobId));
const env = {...process.env, PYTHONDONTWRITEBYTECODE: "1", R_LIBS_USER: args["r-library"], SCAGENTKIT_EXPECTED_IMPLEMENTATION: args.implementation,
  R_PROFILE_USER: "/dev/null", R_ENVIRON_USER: "/dev/null", R_PROFILE: "/dev/null", R_ENVIRON: "/dev/null"};
for (const key of ["DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY",
  "AZURE_OPENAI_API_KEY", "COHERE_API_KEY", "MISTRAL_API_KEY", "OPENROUTER_API_KEY", "HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN"]) delete env[key];
const {chromium} = createRequire(import.meta.url)(args.playwright || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
const report = {schema: "scagentkit.strategy.readonly-browser-recovery.v1", startedAt: new Date().toISOString(), project, output,
  requiredImplementationHash: args.implementation, driverSHA256: sha(await fs.readFile(fileURLToPath(import.meta.url))),
  readonly: true, actualChrome: false, actualRBridge: false, newScientificExecutions: 0, newDecisionRequests: 0, newContinueRequests: 0,
  newProviderCalls: 0, realAPIRequests: 0, costUSD: 0, tests: [], screenshots: [], pageErrors: [], externalRequests: [], unexpectedDialogs: [], unexpectedMutationRequests: [],
  preservedFirstAttempt: {path: priorFile, sha256: sha(priorBytes), driverSHA256: prior.driverSHA256, passed: false, passedTests: 2,
    failure: "Immediate DOM status/stage assertion raced the asynchronous page refresh after successful real R continuation.", successfulJobId: prior.savedJobId}};
let server, context, browser, page, profile, origin, serverError;
const lifecycle = [];
async function snapshot() {
  const files = {};
  async function walk(directory) {
    for (const item of await fs.readdir(directory, {withFileTypes: true})) {
      assert.equal(item.isSymbolicLink(), false); const file = path.join(directory, item.name);
      if (item.isDirectory()) await walk(file); else if (item.isFile()) files[path.relative(project, file)] = sha(await fs.readFile(file));
    }
  }
  await walk(project); return files;
}
const before = await snapshot();
async function protect() {
  assert.equal(sha(await fs.readFile(priorFile)), report.preservedFirstAttempt.sha256);
  for (const [name, digest] of Object.entries(prior.inputCheckpointSHA256)) assert.equal(sha(await fs.readFile(path.join(project, "checkpoints", name))), digest);
  const ledgerBytes = await fs.readFile(path.join(project, "provider", "ledger.json")); assert.equal(sha(ledgerBytes), prior.initialLedgerSHA256);
  const entries = array(JSON.parse(ledgerBytes).entries); assert.equal(entries.length, 1);
  for (const entry of entries) {assert.equal(entry.provider.external, false); assert.equal(entry.cost_usd, 0); assert.equal(entry.charged_or_held_usd, 0);}
}
async function test(name, action) {
  const start = Date.now();
  try {await action(); await protect(); report.tests.push({name, outcome: "passed", milliseconds: Date.now() - start}); console.log("PASS " + name);}
  catch (error) {report.tests.push({name, outcome: "failed", error: error.message}); throw error;}
}
async function startServer() {
  server = spawn(args.python || "python3", [path.join(workbench, "server.py"), "--run-project", project, "--local-continue", "--r-library", args["r-library"], "--rscript", args.rscript || "Rscript", "--port", "0"],
    {cwd: path.dirname(workbench), env, stdio: ["ignore", "pipe", "pipe"]});
  lifecycle.push({event: "owned_readonly_server_started", pid: server.pid, portRequested: 0}); let startup = "";
  server.once("error", error => {serverError = error;});
  server.stdout.on("data", bytes => {startup = (startup + bytes.toString()).slice(-8192); const match = startup.match(/scAgentKit workbench: (http:\/\/127\.0\.0\.1:[0-9]+)/); if (match) origin = match[1];});
  server.stderr.on("data", () => {});
  const deadline = Date.now() + 45000;
  while (!origin && Date.now() < deadline) {if (serverError) throw serverError; assert.equal(server.exitCode, null); await pause(100);}
  assert(origin); report.ownedLoopbackOrigin = origin;
}
async function stopServer() {
  if (!server || server.exitCode != null || server.signalCode != null) return;
  const owned = server, closed = new Promise(resolve => owned.once("exit", resolve)); owned.kill("SIGTERM"); await Promise.race([closed, pause(3000)]);
  if (owned.exitCode == null && owned.signalCode == null) {owned.kill("SIGKILL"); await closed;}
  lifecycle.push({event: "owned_readonly_server_stopped", pid: owned.pid, exitCode: owned.exitCode, signal: owned.signalCode});
}
async function inspect() {
  const response = await fetch(origin + "/api/run-review/inspect"), answer = await response.json(); assert.equal(response.status, 200);
  assert.equal(answer.schema, "scagentkit.run-review.workbench.v1"); assert.equal(answer.run.implementation_hash, args.implementation);
  assert.equal(answer.run.input_hash, prior.initialInputHash); return answer;
}
const ui = id => page.locator('[data-testid="' + id + '"]');
let current;
try {
  await protect(); await startServer(); current = (await inspect()).run; assert.equal(current.status, "complete"); assert.equal(current.stage, "complete");
  profile = await fs.mkdtemp(path.join(output, ".owned-readonly-chrome-profile-"));
  context = await chromium.launchPersistentContext(profile, {headless: true, env, executablePath: args.chrome || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", viewport: {width: 1440, height: 1100}});
  browser = context.browser(); report.actualChrome = true; report.chromeVersion = browser?.version() || "Chrome persistent context";
  await context.route("**/*", route => {
    const request = route.request(), url = request.url();
    if (request.method() !== "GET" && request.method() !== "HEAD") {report.unexpectedMutationRequests.push({method: request.method(), path: new URL(url).pathname}); return route.abort();}
    if (url.startsWith(origin + "/") || url.startsWith("data:")) return route.continue();
    report.externalRequests.push(url); return route.abort();
  });
  page = await context.newPage(); page.setDefaultTimeout(30000); page.on("pageerror", error => report.pageErrors.push(error.message));
  page.on("dialog", async dialog => {report.unexpectedDialogs.push({type: dialog.type()}); await dialog.dismiss();});
  await page.goto(origin + "/");
  await page.waitForFunction(() => document.getElementById("run-status").textContent.trim() === "complete / complete" && !document.getElementById("run-refresh").disabled);
  await test("actual readonly Chrome displays the fresh completed status/stage, saved output paths and central strategy", async () => {
    assert.equal((await ui("run-status").textContent()).trim(), "complete / complete"); assert.equal(await ui("run-complete").isVisible(), true);
    assert.equal(await ui("run-continue").isDisabled(), true); assert.equal(await ui("run-qc").isVisible(), false); assert.equal(await ui("run-strategy").isVisible(), true);
    assert.equal(await ui("strategy-json").isDisabled(), true); assert.equal(await ui("strategy-approve").isDisabled(), true); assert.equal(await ui("strategy-save").isDisabled(), true);
    assert.equal(JSON.parse(await ui("strategy-json").inputValue()).clustering.resolution, 0.5);
    const outputText = await ui("run-output").textContent(); assert(outputText.includes("seurat.rds") && outputText.includes("report.md"));
    const details = current.annotation_review.details; assert.equal(details.cell_count, 2540); assert.equal(details.cluster_count, 8);
    for (const row of array(details.annotations)) {assert.equal(row.proposal.label, "Unknown"); assert.equal(row.proposal.confidence, "low");}
    assert.equal(await ui("run-annotation").isVisible(), true); assert((await ui("annotation-counts").textContent()).includes("2540"));
    assert((await ui("run-continuation-note").textContent()).includes("current saved run has completed output"));
    report.currentRun = {status: current.status, stage: current.stage, revision: current.revision, inputHash: current.input_hash, cells: details.cell_count, clusters: details.cluster_count, labels: "Unknown", confidence: "low", scientificIdentityValidated: false};
    report.outputDisplay = {savedPathsVisible: true, directDownloadLinks: await page.locator("#run-output a").count()};
    const file = path.join(output, "01-complete-public-strategy.png"); assert.equal(await exists(file), false); await page.screenshot({path: file, fullPage: true}); report.screenshots.push(file);
  });
  await test("saved actual fixed R job preserves its original annotation boundary and exact once approvals/stages", async () => {
    const directory = path.join(project, ".workbench-jobs", "jobs", prior.savedJobId), owner = JSON.parse(await fs.readFile(path.join(directory, "owner.json"), "utf8"));
    const job = JSON.parse(await fs.readFile(path.join(directory, "job.json"), "utf8")), config = JSON.parse(await fs.readFile(path.join(directory, "config.json"), "utf8")), responseBytes = await fs.readFile(path.join(directory, "response.json")), response = JSON.parse(responseBytes);
    assert.equal(job.status, "succeeded"); assert.equal(job.next_run_status, "awaiting_configuration"); assert.equal(job.next_run_stage, "annotation_propose");
    assert.equal(path.basename(config.bridge), "run_continue_bridge.R"); assert.equal(config.library, args["r-library"]);
    assert(owner.r_pid > 0 && owner.worker_pid > 0 && owner.r_pid !== owner.worker_pid); assert.equal(owner.r_exit_code, 0);
    assert.equal(response.ok, true); assert.equal(response.result.status, "awaiting_configuration"); assert.equal(response.result.stage, "annotation_propose"); assert.equal(response.result.input_hash, prior.initialInputHash);
    assert.equal(sha(responseBytes), prior.jobs[0].responseSHA256); report.actualRBridge = true;
    report.savedJobProof = {job, owner, responseSHA256: sha(responseBytes), codeHashes: config.code_hashes, result: response.result, replayed: false};
    const history = JSON.parse(await fs.readFile(path.join(project, "decision_history.json"), "utf8")), approvals = array(history.events).filter(event => event.action === "approved");
    assert.equal(approvals.filter(event => event.details.kind === "strategy").length, 1); assert.equal(approvals.filter(event => event.details.kind === "qc").length, 0); assert.equal(approvals.filter(event => event.details.kind === "annotation").length, 1);
    const stages = array(history.events).filter(event => event.action === "executed").map(event => event.details.stage);
    for (const stage of ["qc_apply", "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence", "annotation_apply", "finalize"]) assert.equal(stages.filter(value => value === stage).length, 1);
    report.approvalKinds = approvals.map(event => event.details.kind); report.executionStages = stages;
  });
  await test("readonly refresh preserves completed project bytes, original input checkpoint, ledger and failed first receipt", async () => {
    await ui("run-refresh").click();
    await page.waitForFunction(() => document.getElementById("run-status").textContent.trim() === "complete / complete" && !document.getElementById("run-refresh").disabled);
    const latest = (await inspect()).run; assert.equal(latest.revision, current.revision); assert.equal(latest.history_head, current.history_head); assert.deepEqual(latest.output, current.output);
    report.finalOutputs = {};
    for (const [name, value] of Object.entries(current.output)) {
      if (!["seurat", "report"].includes(name)) continue;
      const file = path.resolve(value); assert(file.startsWith(project + path.sep)); report.finalOutputs[name] = {path: file, sha256: sha(await fs.readFile(file))};
    }
    assert.deepEqual(await snapshot(), before);
  });
  assert.equal(report.pageErrors.length, 0); assert.equal(report.externalRequests.length, 0); assert.equal(report.unexpectedDialogs.length, 0); assert.equal(report.unexpectedMutationRequests.length, 0);
  report.passed = true;
} catch (error) {report.passed = false; report.error = error.stack; console.error(error.stack); process.exitCode = 1;}
finally {
  try {await context?.close(); if (browser?.isConnected()) await browser.close();} catch (error) {report.passed = false; report.chromeCleanupError = error.message; process.exitCode = 1;}
  try {await stopServer();} catch (error) {report.passed = false; report.serverCleanupError = error.message; process.exitCode = 1;}
  if (profile) {await fs.rm(profile, {recursive: true, force: true}); report.isolatedProfileRemoved = true;}
  try {await protect(); assert.deepEqual(await snapshot(), before); report.allProjectBytesUnchanged = true;} catch (error) {report.passed = false; report.preservationError = error.message; process.exitCode = 1;}
  report.completedAt = new Date().toISOString(); report.lifecycle = lifecycle;
  await fs.writeFile(path.join(output, "server-lifecycle.json"), JSON.stringify(lifecycle, null, 2) + "\n"); await fs.writeFile(reportFile, JSON.stringify(report, null, 2) + "\n");
}
