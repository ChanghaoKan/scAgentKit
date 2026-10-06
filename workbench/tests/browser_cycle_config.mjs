#!/usr/bin/env node
/** Fresh synthetic configuration-boundary regression in actual readonly Chrome.
 * Root creates the fixture with the exact installed implementation. This driver
 * only inspects and refreshes; no decision, continuation, job or model dispatch.
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
const fixture = path.join(workspace, "evidence", "cycle-configuration-regression"), project = path.resolve(args.project), output = path.resolve(args.output);
assert.equal(project, path.join(fixture, "project")); assert.equal(output, path.join(fixture, "browser"));
assert.equal(await fs.realpath(project), project); assert.equal((await fs.lstat(project)).isSymbolicLink(), false);
await fs.mkdir(output, {recursive: true}); assert.equal(await fs.realpath(output), output);
const exists = file => fs.access(file).then(() => true, () => false), sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
const pause = ms => new Promise(resolve => setTimeout(resolve, ms)), reportFile = path.join(output, "cycle-config-browser-report.json");
assert.equal(await exists(reportFile), false, "Never overwrite regression evidence");
assert.equal(await exists(path.join(project, ".workbench-jobs")), false, "The headless fixture must have no browser jobs");
const env = {...process.env, PYTHONDONTWRITEBYTECODE: "1", R_LIBS_USER: args["r-library"], SCAGENTKIT_EXPECTED_IMPLEMENTATION: args.implementation,
  R_PROFILE_USER: "/dev/null", R_ENVIRON_USER: "/dev/null", R_PROFILE: "/dev/null", R_ENVIRON: "/dev/null"};
for (const key of ["DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY",
  "AZURE_OPENAI_API_KEY", "COHERE_API_KEY", "MISTRAL_API_KEY", "OPENROUTER_API_KEY", "HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN"]) delete env[key];
const {chromium} = createRequire(import.meta.url)(args.playwright || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
const report = {schema: "scagentkit.cycle.configuration-browser-regression.v1", startedAt: new Date().toISOString(), project, output,
  driverSHA256: sha(await fs.readFile(fileURLToPath(import.meta.url))), requiredImplementationHash: args.implementation, library: args["r-library"],
  readonly: true, actualChrome: false, newDecisionRequests: 0, newContinueRequests: 0, newBrowserJobs: 0, newScientificExecutions: 0,
  newProviderCalls: 0, realAPIRequests: 0, costUSD: 0, sourceOriginalsRead: false, fallbackLibraryAttempts: 0, providerEnvNamesRemoved: 13, rProfilesDisabled: true,
  tests: [], screenshots: [], pageErrors: [], externalRequests: [], unexpectedDialogs: [], unexpectedMutationRequests: [], inspectResponses: []};
let server, context, browser, page, profile, origin, startError, current;
const lifecycle = [];
async function snapshot() {
  const files = {};
  async function walk(directory) {for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
    assert.equal(entry.isSymbolicLink(), false); const file = path.join(directory, entry.name);
    if (entry.isDirectory()) await walk(file); else if (entry.isFile()) files[path.relative(project, file)] = sha(await fs.readFile(file));
  }}
  await walk(project); return files;
}
const before = await snapshot(); report.initialProjectSHA256 = before;
async function protect() {assert.deepEqual(await snapshot(), before); assert.equal(await exists(path.join(project, ".workbench-jobs")), false);}
async function test(name, action) {const start = Date.now(); try {await action(); await protect(); report.tests.push({name, outcome: "passed", milliseconds: Date.now() - start}); console.log("PASS " + name);} catch (error) {report.tests.push({name, outcome: "failed", error: error.message}); throw error;}}
async function startServer() {
  // Continuation is deliberately not enabled: no job namespace is created.
  server = spawn(args.python || "python3", [path.join(workbench, "server.py"), "--run-project", project, "--r-library", args["r-library"], "--rscript", args.rscript || "Rscript", "--port", "0"], {cwd: path.dirname(workbench), env, stdio: ["ignore", "pipe", "pipe"]});
  lifecycle.push({event: "owned_readonly_server_started", pid: server.pid, portRequested: 0, localContinue: false}); let startup = "";
  server.once("error", error => {startError = error;});
  server.stdout.on("data", bytes => {startup = (startup + bytes.toString()).slice(-8192); const match = startup.match(/scAgentKit workbench: (http:\/\/127\.0\.0\.1:[0-9]+)/); if (match) origin = match[1];});
  server.stderr.on("data", () => {});
  const deadline = Date.now() + 45000;
  while (!origin && Date.now() < deadline) {if (startError) throw startError; assert.equal(server.exitCode, null, "Owned server failed; no alternative library is attempted"); await pause(100);}
  assert(origin && /^http:\/\/127\.0\.0\.1:[0-9]+$/.test(origin)); report.ownedLoopbackOrigin = origin;
}
async function stopServer() {
  if (!server || server.exitCode != null || server.signalCode != null) return;
  const owned = server, closed = new Promise(resolve => owned.once("exit", resolve)); owned.kill("SIGTERM"); await Promise.race([closed, pause(3000)]);
  if (owned.exitCode == null && owned.signalCode == null) {owned.kill("SIGKILL"); await closed;}
  lifecycle.push({event: "owned_readonly_server_stopped", pid: owned.pid, exitCode: owned.exitCode, signal: owned.signalCode});
}
async function inspect() {
  const response = await fetch(origin + "/api/run-review/inspect", {signal: AbortSignal.timeout(45000)}), answer = await response.json(); assert.equal(response.status, 200);
  assert.equal(answer.schema, "scagentkit.run-review.workbench.v1"); assert.equal(answer.run.implementation_hash, args.implementation);
  assert.equal(answer.run.status, "awaiting_configuration"); assert.equal(answer.run.stage, "annotation_propose"); assert(answer.run.review_node == null);
  assert(answer.run.annotation_review == null); assert.equal(answer.run.output, null); assert.equal(answer.run.strategy_review.details.canonical_proposal.cycle.method, "none"); return answer;
}
const ui = id => page.locator('[data-testid="' + id + '"]');
async function rendered() {await page.waitForFunction(() => document.getElementById("run-status").textContent.trim() === "awaiting_configuration / annotation_propose" && !document.getElementById("run-refresh").disabled, null, {timeout: 45000});}
async function captureFailure() {
  if (!page || page.isClosed()) return;
  try {
    report.uiDiagnostics = await page.evaluate(() => {const text = id => document.getElementById(id)?.textContent?.trim() || ""; return {status: text("run-status"), message: text("run-message"), messageHidden: document.getElementById("run-message")?.hidden, continuationNote: text("run-continuation-note"), refreshDisabled: document.getElementById("run-refresh")?.disabled};});
    const file = path.join(output, "failure-ui-status-and-message.png"); assert.equal(await exists(file), false); await page.screenshot({path: file, fullPage: true}); report.screenshots.push(file);
  } catch (error) {report.uiDiagnosticsError = error.message;}
}
try {
  await startServer(); current = (await inspect()).run; await protect();
  const cycle = current.strategy_review.details.cycle_diagnostics; assert.equal(cycle.schema, "scagentkit.cycle.evidence.v1"); assert.equal(cycle.cohort.input_cells, 180); assert.equal(cycle.reference, "fixed_full_input"); assert.equal(cycle.refit_after_qc, false); assert(["available", "insufficient"].includes(cycle.status));
  profile = await fs.mkdtemp(path.join(output, ".owned-config-chrome-profile-"));
  context = await chromium.launchPersistentContext(profile, {headless: true, env, executablePath: args.chrome || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", viewport: {width: 1440, height: 1100}});
  browser = context.browser(); report.actualChrome = true; report.chromeVersion = browser?.version() || "Chrome persistent context";
  await context.route("**/*", route => {const request = route.request(), url = request.url(); if (!["GET", "HEAD"].includes(request.method())) {report.unexpectedMutationRequests.push({method: request.method(), path: new URL(url).pathname}); return route.abort();} if (url.startsWith(origin + "/") || url.startsWith("data:")) return route.continue(); report.externalRequests.push(url); return route.abort();});
  page = await context.newPage(); page.setDefaultTimeout(45000); page.on("pageerror", error => report.pageErrors.push(error.message)); page.on("dialog", async dialog => {report.unexpectedDialogs.push({type: dialog.type()}); await dialog.dismiss();});
  page.on("response", async response => {if (new URL(response.url()).pathname !== "/api/run-review/inspect") return; const receipt = {httpStatus: response.status()}; report.inspectResponses.push(receipt); try {const answer = await response.json(); receipt.status = answer.run?.status; receipt.stage = answer.run?.stage; receipt.revision = answer.run?.revision; receipt.reviewNodeAbsent = answer.run?.review_node == null; if (!response.ok()) receipt.error = answer.error;} catch (error) {receipt.readError = error.message;}});
  await page.goto(origin + "/"); await rendered();
  await test("actual readonly Chrome renders annotation configuration with no review node and the saved none cycle plan", async () => {
    assert.equal(await ui("run-strategy").isVisible(), true); assert.equal(await ui("run-qc").isVisible(), false); assert.equal(await ui("run-annotation").isVisible(), false); assert.equal(await page.locator("#run-qc-frame").getAttribute("src"), null);
    for (const id of ["strategy-json", "strategy-save", "strategy-approve", "strategy-reject", "annotation-save", "annotation-approve", "annotation-reject", "run-continue"]) assert.equal(await ui(id).isDisabled(), true);
    assert.equal(JSON.parse(await ui("strategy-json").inputValue()).cycle.method, "none"); assert.equal(await page.locator("#strategy-operations > section").count(), 7); assert.equal(await ui("cycle-status").getAttribute("data-status"), cycle.status);
    assert((await ui("cycle-regressors").textContent()).includes("Reviewed scaling inputs: none")); assert.equal(await ui("cycle-advanced").evaluate(node => node.open), false); assert((await ui("cycle-ordinary").textContent()).includes("default"));
    const cohort = (await ui("cycle-cohort").textContent()).replace(/,/g, ""); assert(cohort.includes("before QC; no refit after QC") && cohort.includes("180"));
    assert.equal(await ui("run-message").isVisible(), false); assert((await ui("run-next").textContent()).includes("needs a supported proposal or configuration in R"));
    const file = path.join(output, "01-saved-cycle-configuration-boundary.png"); assert.equal(await exists(file), false); await page.screenshot({path: file, fullPage: true}); report.screenshots.push(file);
    report.currentRun = {projectId: current.project_id, inputHash: current.input_hash, status: current.status, stage: current.stage, revision: current.revision, reviewNode: null, cycleMethod: "none", diagnosticStatus: cycle.status, inputCells: 180};
  });
  await test("readonly refresh retains the same saved state and every fixture byte without jobs or decisions", async () => {
    const responsePromise = page.waitForResponse(response => new URL(response.url()).pathname === "/api/run-review/inspect" && response.request().method() === "GET"); await ui("run-refresh").click(); assert.equal((await responsePromise).status(), 200); await rendered();
    const latest = (await inspect()).run; assert.equal(latest.project_id, current.project_id); assert.equal(latest.input_hash, current.input_hash); assert.equal(latest.revision, current.revision); assert.equal(latest.history_head, current.history_head); assert.deepEqual(latest.strategy_review, current.strategy_review); assert(latest.review_node == null);
    assert.equal(await ui("run-message").isVisible(), false); assert.equal(await ui("strategy-approve").isDisabled(), true);
  });
  assert.equal(report.pageErrors.length, 0); assert.equal(report.externalRequests.length, 0); assert.equal(report.unexpectedDialogs.length, 0); assert.equal(report.unexpectedMutationRequests.length, 0); report.passed = true;
} catch (error) {report.passed = false; report.error = error.stack; await captureFailure(); console.error(error.stack); process.exitCode = 1;}
finally {
  try {await context?.close(); if (browser?.isConnected()) await browser.close();} catch (error) {report.passed = false; report.chromeCleanupError = error.message; process.exitCode = 1;}
  try {await stopServer();} catch (error) {report.passed = false; report.serverCleanupError = error.message; process.exitCode = 1;}
  if (profile) {await fs.rm(profile, {recursive: true, force: true}); report.isolatedProfileRemoved = true;}
  try {await protect(); report.allProjectBytesUnchanged = true;} catch (error) {report.passed = false; report.preservationError = error.message; process.exitCode = 1;}
  report.completedAt = new Date().toISOString(); report.lifecycle = lifecycle; await fs.writeFile(path.join(output, "server-lifecycle.json"), JSON.stringify(lifecycle, null, 2) + "\n"); await fs.writeFile(reportFile, JSON.stringify(report, null, 2) + "\n");
}
