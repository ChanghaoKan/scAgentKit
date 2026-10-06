#!/usr/bin/env node
/** Actual isolated Chrome + fixed Python worker + real R bridge acceptance.
 * Fixture scripts configure offline proposals separately. HTTP never receives
 * provider callbacks/R code. Do not start before the operator's source freeze.
 */
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import net from "node:net";
import crypto from "node:crypto";
import {spawn} from "node:child_process";
import {createRequire} from "node:module";
import {fileURLToPath} from "node:url";

const args = {};
for (let i = 2; i < process.argv.length; i += 2) {
  assert(process.argv[i]?.startsWith("--") && process.argv[i + 1], "Use --name value pairs");
  args[process.argv[i].slice(2)] = process.argv[i + 1];
}
assert(args.project && args["r-library"] && args["fixture-script"] && /^[a-f0-9]{64}$/.test(args.implementation || ""),
  "Supply a NEW frozen awaiting-QC fixture, exact new R library, fixed offline Rscript and verified implementation hash");
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = path.resolve(args.project), fixtureScript = path.resolve(args["fixture-script"]);
const resumeSource = args["resume-from"] ? path.resolve(args["resume-from"]) : null;
const resumePhase = args["resume-phase"] || "qc-approved";
assert(["qc-approved", "annotation-failed", "complete"].includes(resumePhase));
const recoveryScript = args["annotation-recovery-script"] ? path.resolve(args["annotation-recovery-script"]) : null;
const externalScript = args["external-preview-script"] ? path.resolve(args["external-preview-script"]) : null;
assert(resumePhase !== "annotation-failed" || (resumeSource && recoveryScript), "Annotation recovery requires its preserved segment and explicit fixed manual R script");
assert(resumePhase !== "complete" || (resumeSource && externalScript), "Supplemental-only completion resume requires its preserved finished report and fixed external-preview script");
const output = path.resolve(args.output || await fs.mkdtemp(path.join(os.tmpdir(), "scagentkit-continue-browser-")));
await fs.mkdir(output, {recursive: true});
const reportFile = path.join(output, "continue-browser-report.json");
assert.equal(await fs.access(reportFile).then(() => true, () => false), false, "Never overwrite an existing report/run");
const require = createRequire(import.meta.url);
const {chromium} = require(args.playwright || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
const env = {...process.env, PYTHONDONTWRITEBYTECODE: "1", R_LIBS_USER: args["r-library"],
  SCAGENTKIT_EXPECTED_IMPLEMENTATION: args.implementation};
for (const key of ["DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY",
  "GOOGLE_API_KEY", "GEMINI_API_KEY", "AZURE_OPENAI_API_KEY", "COHERE_API_KEY", "MISTRAL_API_KEY", "OPENROUTER_API_KEY", "HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN"]) delete env[key];
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
const array = value => value == null ? [] : Array.isArray(value) ? value : [value];
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const exists = file => fs.access(file).then(() => true, () => false);
const report = {startedAt: new Date().toISOString(), sourceFixture: source,
  fixtureScript, implementationHash: args.implementation, tests: [], screenshots: [],
  actualChrome: false, actualRBridge: false, simulatedRBridge: false,
  jobs: [], rProcesses: [], pageErrors: [], externalRequests: [], paidProviderCalls: 0, costUSD: 0};
let server, browser, context, page, origin, token; const logs = [], ownedOrigins = new Set();
async function snapshot(directory, scientificOnly = false, excludedRootNames = []) {
  const files = {};
  async function walk(here) {
    for (const item of await fs.readdir(here, {withFileTypes: true})) {
      if (here === directory && excludedRootNames.includes(item.name)) continue;
      if (scientificOnly && here === directory && item.name === ".workbench-jobs") continue;
      const full = path.join(here, item.name); assert(!item.isSymbolicLink(), "Fixture contains no symlinks");
      if (item.isDirectory()) await walk(full);
      else if (item.isFile()) files[path.relative(directory, full)] = sha(await fs.readFile(full));
    }
  }
  await walk(directory); return files;
}
const sourceBefore = await snapshot(source), fixtureHash = sha(await fs.readFile(fixtureScript));
const resumeExcluded = resumePhase === "annotation-failed" ? ["review-project"] : [];
const resumeBefore = resumeSource ? await snapshot(resumeSource, false, resumeExcluded) : null;
const recoveryHash = recoveryScript ? sha(await fs.readFile(recoveryScript)) : null;
const externalHash = externalScript ? sha(await fs.readFile(externalScript)) : null;
if (recoveryScript) {report.annotationRecoveryScript = recoveryScript; report.annotationRecoverySHA256 = recoveryHash;}
if (externalScript) {report.externalPreviewScript = externalScript; report.externalPreviewSHA256 = externalHash;}
const protectedManifest = args["protected-manifest"] ? JSON.parse(await fs.readFile(args["protected-manifest"], "utf8")) : {};
async function verifyProtected() {
  let count = 0;
  for (const [directory, files] of Object.entries(protectedManifest)) for (const [relative, expected] of Object.entries(files)) {
    assert.equal(sha(await fs.readFile(path.join(directory, relative))), expected, "Protected prior source/project byte hash"); count++;
  }
  return count;
}
report.protectedOldFileCount = await verifyProtected();
let project = resumeSource && resumePhase === "annotation-failed" ? path.join(resumeSource, "review-project") : path.join(output, "review-project");
const approvedCopy = path.join(output, "approved-before-analysis");
let previous;
if (resumeSource) {
  const previousFile = path.join(resumeSource, "continue-browser-report.json");
  const bytes = await fs.readFile(previousFile); previous = JSON.parse(bytes);
  assert.equal(previous.sourceFixture, source); assert.equal(previous.implementationHash, args.implementation);
  assert.equal(previous.actualChrome, true); assert.equal(previous.passed, false);
  assert.equal(previous.tests[0]?.outcome, "passed");
  if (resumePhase === "qc-approved") {
    assert.equal(previous.actualRBridge, false); assert.equal(previous.jobs.length, 0);
    assert.equal(previous.tests[1]?.name, "actual browser QC approval authorizes the exact frozen scope only");
    assert.equal(previous.tests[1]?.outcome, "failed");
  } else if (resumePhase === "annotation-failed") {
    assert.equal(previous.actualRBridge, true); assert.equal(previous.jobs.length, 1);
    assert.equal(previous.tests[1]?.name, "real async R worker survives browser and HTTP server disconnect, duplicate ID never reruns");
    assert.equal(previous.tests[1]?.outcome, "passed"); assert.equal(previous.tests[2]?.outcome, "failed");
    assert.equal(previous.jobs[0].owner.r_exit_code, 0); assert(previous.jobs[0].owner.r_pid > 0);
    const responseBytes = await fs.readFile(path.join(resumeSource, "review-project", ".workbench-jobs", "jobs", previous.jobs[0].public.job_id, "response.json"));
    assert.equal(sha(responseBytes), previous.jobs[0].responseSHA256); assert.equal(JSON.parse(responseBytes).ok, true);
    report.jobs = previous.jobs.map(job => ({...job, fromPreviousSegment: previousFile}));
    report.actualRBridge = true; report.dataset = previous.dataset;
    report.analysisBoundary = previous.analysisBoundary; report.jobBeforeDisconnect = previous.jobBeforeDisconnect;
    report.analysisContinueRequest = previous.analysisContinueRequest;
  } else {
    assert.equal(previous.actualRBridge, true); assert.equal(previous.jobs.length, 3);
    assert.equal(previous.tests.length, 6); assert(previous.tests.slice(0, 5).every(test => test.outcome === "passed"));
    assert.equal(previous.tests[5].name, "synthetic external-transfer review cannot be bypassed by local Continue");
    assert.equal(previous.tests[5].outcome, "failed"); assert.equal(previous.dataset, "synthetic");
    assert(previous.finalObject && /^[a-f0-9]{64}$/.test(previous.finalObjectSHA256));
    project = path.resolve(previous.project);
    assert.equal(sha(await fs.readFile(previous.finalObject)), previous.finalObjectSHA256);
    report.jobs = [];
    for (const job of previous.jobs) {
      assert.equal(job.public.status, "succeeded"); assert.equal(job.owner.r_exit_code, 0);
      assert(job.owner.r_pid > 0 && job.owner.worker_pid > 0 && job.owner.r_pid !== job.owner.worker_pid);
      const roots = [project, path.join(resumeSource, "actual-failed-analysis-project")];
      let evidence;
      for (const directory of roots) {
        const candidate = path.join(directory, ".workbench-jobs", "jobs", job.public.job_id, "response.json");
        if (await exists(candidate)) {evidence = candidate; break;}
      }
      assert(evidence, "Each reused real worker result needs its actual saved response");
      const bytes = await fs.readFile(evidence);
      assert.equal(sha(bytes), job.responseSHA256); assert.equal(JSON.parse(bytes).ok, true);
      report.jobs.push({...job, fromPreviousSegment: previousFile, responseEvidencePath: evidence});
    }
    report.actualRBridge = true;
    for (const field of ["dataset", "finalObject", "finalObjectSHA256", "finalCanonicalProposal", "actualFailureRetry",
      "analysisBoundary", "jobBeforeDisconnect", "analysisContinueRequest", "annotationClusterCount",
      "annotationSuppliedMarkerCounts", "coarseCoverageAvailable", "coarseCoverageLimitation"])
      if (previous[field] !== undefined) report[field] = previous[field];
    report.supplementalOnly = true;
  }
  assert.equal(previous.fixtureScriptSHA256, fixtureHash);
  assert.deepEqual(previous.productionSHA256 && Object.keys(previous.productionSHA256).sort(), productionPathsForResume());
  report.previousSegment = {report: previousFile, sha256: sha(bytes), actualChrome: previous.actualChrome, actualRBridge: previous.actualRBridge,
    completedTests: previous.tests.filter(test => test.outcome === "passed"),
    originalProductionSHA256: previous.productionSHA256,
    previousSegment: previous.previousSegment || null, resumePhase,
    allowedMutableProject: resumePhase === "annotation-failed" ? project : null,
    reason: resumePhase === "qc-approved" ? "Resume the browser-approved QC checkpoint after correcting an idempotent-approval test expectation; no Continue or analysis had run." :
      resumePhase === "annotation-failed" ? "Resume genuine completed QC/analysis/markers after the recorded offline mock rejected absent markers. Manually configure Unknown without another provider or analysis." :
      "Preserve the finished canonical project and five actual passed cases. Run only corrected external-preview and isolated changed-input supplemental safeguards."};
  if (resumePhase === "qc-approved") await fs.cp(path.join(resumeSource, "review-project"), project, {recursive: true, force: false, errorOnExist: true});
  await fs.cp(path.join(resumeSource, "approved-before-analysis"), approvedCopy, {recursive: true, force: false, errorOnExist: true});
  if (resumePhase !== "complete") assert.deepEqual(await snapshot(project), await snapshot(path.join(resumeSource, "review-project")));
  report.rawCells = previous.rawCells; report.retainedCells = previous.retainedCells;
} else await fs.cp(source, project, {recursive: true, force: false, errorOnExist: true});
report.project = project; report.fixtureScriptSHA256 = fixtureHash;
const completedProjectBefore = resumePhase === "complete" ? await snapshot(project) : null;
const productionPaths = ["server.py", "run_continue_runtime.py", "run_continue_worker.py", "run_continue_bridge.R",
  "run_review_runtime.py", "run_review_bridge.R", "static/review.js", "static/review.html", "static/review.css",
  "static/qc.js", "static/qc.html", "static/qc.css"];
report.productionSHA256 = {};
for (const relative of productionPaths) if (await exists(path.join(root, relative))) report.productionSHA256[relative] = sha(await fs.readFile(path.join(root, relative)));
async function test(name, fn) {
  const begin = Date.now();
  try {await fn(); await verifyProtected(); report.tests.push({name, outcome: "passed", milliseconds: Date.now() - begin, protectedOldFilesUnchanged: true}); console.log("PASS " + name);}
  catch (error) {report.tests.push({name, outcome: "failed", error: error.message}); throw error;}
}
function productionPathsForResume() {
  return ["server.py", "run_continue_runtime.py", "run_continue_worker.py", "run_continue_bridge.R",
    "run_review_runtime.py", "run_review_bridge.R", "static/review.js", "static/review.html", "static/review.css",
    "static/qc.js", "static/qc.html", "static/qc.css"].sort();
}
async function availablePort() {
  const listener = net.createServer();
  await new Promise((resolve, reject) => {listener.once("error", reject); listener.listen(0, "127.0.0.1", resolve);});
  const port = listener.address().port; await new Promise(resolve => listener.close(resolve)); return port;
}
async function start(directory) {
  origin = "http://127.0.0.1:" + await availablePort();
  ownedOrigins.add(origin);
  server = spawn(args.python || "python3", [path.join(root, "server.py"), "--run-project", directory,
    "--local-continue", "--r-library", args["r-library"], "--rscript", args.rscript || "Rscript", "--port", new URL(origin).port],
    {cwd: path.dirname(root), env, stdio: ["ignore", "pipe", "pipe"]});
  server.stdout.on("data", value => logs.push(value.toString())); server.stderr.on("data", value => logs.push(value.toString()));
  for (let i = 0; i < 180; i++) {
    if (server.exitCode != null) throw new Error("New server exited: " + logs.slice(-6).join(""));
    let response;
    try {response = await fetch(origin + "/api/run-review/inspect");} catch {}
    if (response?.ok) {token = (await response.json()).csrf_token; return;}
    if (response && response.status >= 400 && response.status < 500) throw new Error("Configured isolated run inspection rejected HTTP " + response.status);
    await pause(200);
  }
  throw new Error("New isolated loopback server did not become ready");
}
async function stop() {
  if (!server || server.exitCode != null || server.signalCode != null) return;
  const child = server, closed = new Promise(resolve => child.once("exit", resolve));
  child.kill("SIGTERM"); await Promise.race([closed, pause(3000)]);
  if (child.exitCode == null && child.signalCode == null) {child.kill("SIGKILL"); await closed;}
}
async function inspect() {
  const response = await fetch(origin + "/api/run-review/inspect"); const result = await response.json();
  assert.equal(response.status, 200, JSON.stringify(result)); token = result.csrf_token; return result;
}
async function continuation() {
  const response = await fetch(origin + "/api/run-review/continuation"); const result = await response.json();
  assert.equal(response.status, 200, JSON.stringify(result)); assert.equal(result.schema, "scagentkit.run-continue.workbench.v1"); return result;
}
async function post(route, body, rejected = false, csrf = token) {
  const response = await fetch(origin + route, {method: "POST", headers: {
    "Content-Type": "application/json", Origin: origin, "X-ScAgentKit-Run-Token": csrf || ""}, body: JSON.stringify(body)});
  const result = await response.json();
  const summary = JSON.stringify({httpStatus: response.status, schema: result.schema, error: result.error,
    runStatus: result.run?.status, runStage: result.run?.stage, revision: result.run?.revision,
    jobStatus: result.job?.status, jobId: result.job?.job_id});
  if (rejected) assert(response.status >= 400 && response.status < 500, summary);
  else assert.equal(response.status, route.endsWith("continue") ? 202 : 200, summary);
  return result;
}
function reviewPayload(run, action) {
  const node = run.review_node;
  return {action, kind: node.kind, project_id: run.project_id, input_hash: run.input_hash,
    proposal_hash: node.proposal_hash, review_hash: node.review_hash, expected_revision: run.revision,
    reviewer: "Independent offline browser analyst", reason: "Exact synthetic/public mechanism review; biological accuracy not accepted"};
}
function continuePayload(run, retry = false) {
  return {project_id: run.project_id, input_hash: run.input_hash, expected_revision: run.revision,
    request_id: crypto.randomUUID(), retry};
}
async function fixedR(directory, mode) {
  assert(["annotate", "verify", "inspect", "continue", "fail-analysis", "mutate-input", "external-preview"].includes(mode));
  assert.equal(sha(await fs.readFile(fixtureScript)), fixtureHash, "Fixed offline R fixture cannot change during acceptance");
  const script = mode === "annotate" && resumePhase === "annotation-failed" ? recoveryScript :
    mode === "external-preview" && externalScript ? externalScript : fixtureScript;
  if (script === recoveryScript) assert.equal(sha(await fs.readFile(script)), recoveryHash);
  if (script === externalScript) assert.equal(sha(await fs.readFile(script)), externalHash);
  const chunks = [], errors = [], began = Date.now();
  const child = spawn(args.rscript || "Rscript", ["--vanilla", script, directory, mode], {env, stdio: ["ignore", "pipe", "pipe"]});
  child.stdout.on("data", value => chunks.push(value)); child.stderr.on("data", value => errors.push(value));
  const result = await new Promise((resolve, reject) => {child.once("error", reject); child.once("exit", (code, signal) => resolve({code, signal}));});
  const text = Buffer.concat(chunks).toString() + Buffer.concat(errors).toString();
  const name = `r-${report.rProcesses.length + 1}-${mode}.log`; await fs.writeFile(path.join(output, name), text);
  const line = text.split("\n").find(line => line.startsWith("SC_CONTINUE_FIXTURE_JSON="));
  const proof = line ? JSON.parse(line.slice("SC_CONTINUE_FIXTURE_JSON=".length)) : null;
  report.rProcesses.push({mode, directory, script, ...result, milliseconds: Date.now() - began, log: name, proof});
  assert.equal(result.code, 0, text.slice(-3500)); assert(text.includes("paid API:0")); assert(proof); return proof;
}
const ui = id => page.locator('[data-testid="' + id + '"]');
async function idle() {await ui("run-refresh").waitFor(); await page.waitForFunction(() => !document.getElementById("run-refresh").disabled);}
async function refresh() {await ui("run-refresh").click(); await idle();}
async function newPage() {
  page = await context.newPage(); page.setDefaultTimeout(90000); page.on("pageerror", error => report.pageErrors.push(error.message));
  page.on("dialog", dialog => dialog.accept()); await page.goto(origin + "/"); await idle();
}
async function screenshot(name) {const file = path.join(output, name + ".png"); await page.screenshot({path: file, fullPage: true}); report.screenshots.push(file);}
async function clickContinue(retry = false) {
  const received = page.waitForResponse(response => new URL(response.url()).pathname === "/api/run-review/continue" && response.request().method() === "POST");
  await ui(retry ? "run-continue-retry" : "run-continue").click();
  const response = await received, result = await response.json(), body = response.request().postDataJSON();
  assert.equal(response.status(), 202, JSON.stringify(result)); assert.equal(result.schema, "scagentkit.run-continue.workbench.v1");
  assert.deepEqual(Object.keys(body).sort(), ["expected_revision", "input_hash", "project_id", "request_id", "retry"].sort());
  assert.equal(body.retry, retry); assert(result.job?.job_id); return {body, result};
}
async function finish(jobId, directory) {
  let view;
  for (let i = 0; i < 1200; i++) {
    view = await continuation(); assert.equal(view.job?.job_id, jobId);
    if (!["queued", "running"].includes(view.job.status)) break;
    await pause(500);
  }
  assert.equal(view.job.status, "succeeded", JSON.stringify(view));
  const location = path.join(directory, ".workbench-jobs", "jobs", jobId);
  const owner = JSON.parse(await fs.readFile(path.join(location, "owner.json"), "utf8"));
  const config = JSON.parse(await fs.readFile(path.join(location, "config.json"), "utf8"));
  const response = JSON.parse(await fs.readFile(path.join(location, "response.json"), "utf8"));
  assert(owner.worker_pid > 0 && owner.r_pid > 0 && owner.worker_pid !== owner.r_pid);
  assert.equal(owner.r_exit_code, 0); assert.equal(path.basename(config.bridge), "run_continue_bridge.R"); assert.equal(response.ok, true);
  assert.equal(response.result.status, view.job.next_run_status); assert.equal(response.result.stage, view.job.next_run_stage);
  report.jobs.push({public: view.job, owner, codeHashes: config.code_hashes, bridge: config.bridge, responseSHA256: sha(await fs.readFile(path.join(location, "response.json")))});
  report.actualRBridge = true;
  return view;
}
let initial, approved, analysisStop, annotationInitial, annotationReviewed, complete;
try {
  await start(project);
  browser = await chromium.launch({headless: true, executablePath: args.chrome || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"});
  report.actualChrome = true;
  context = await browser.newContext({viewport: {width: 1440, height: 1000}});
  await context.route("**/*", route => {
    const url = route.request().url(); if ([...ownedOrigins].some(local => url.startsWith(local + "/")) || url.startsWith("data:")) return route.continue();
    report.externalRequests.push(url); return route.abort();
  });
  await newPage();
  if (resumePhase === "complete") await test("restore completed canonical project byte-identically and reuse prior real positive/retry evidence", async () => {
    complete = (await inspect()).run;
    assert.equal(complete.status, "complete"); assert.equal(complete.stage, "complete"); assert.equal(complete.revision, 30);
    assert.equal(complete.output.seurat, report.finalObject);
    assert.equal(sha(await fs.readFile(complete.output.seurat)), report.finalObjectSHA256);
    assert.equal(await ui("run-continue").isDisabled(), true);
    assert.deepEqual(await snapshot(project), completedProjectBefore);
    report.completedCanonicalAllBytesUnchanged = true;
    await screenshot("00-preserved-completed-canonical-project");
  });
  else {
  if (resumeSource && resumePhase === "qc-approved") await test("resume the previously browser-approved checkpoint and replay approval byte-identically", async () => {
    approved = (await inspect()).run;
    assert.equal(approved.status, "ready"); assert.equal(approved.stage, "qc_apply"); assert.equal(approved.revision, 7);
    assert.equal((await continuation()).job, null); assert.equal(await ui("run-continue").isEnabled(), true);
    assert.equal(approved.qc_preview.details.retention.before, report.rawCells);
    assert.equal(approved.qc_preview.details.retention.retained, report.retainedCells);
    const before = await snapshot(project);
    const originalBinding = {...approved, revision: approved.revision - 1};
    const replay = await post("/api/run-review/decision", reviewPayload(originalBinding, "approve"));
    assert.equal(replay.run.revision, approved.revision); assert.deepEqual(await snapshot(project), before);
    const body = continuePayload(approved);
    for (const bad of [{...body, project_id: "foreign-project"}, {...body, input_hash: "0".repeat(64)}, {...body, expected_revision: approved.revision - 1}])
      await post("/api/run-review/continue", bad, true);
    assert.deepEqual(await snapshot(project), before);
    report.qcBrowserApproval = {priorReport: report.previousSegment.report, restoredRevision: approved.revision,
      priorActualChrome: true, approveReplayHTTP: 200, sourceCheckpointBytesUnchanged: true};
    await screenshot("02-qc-approved-checkpoint-resumed");
  });
  else if (resumeSource) await test("restore the actual saved annotation failure without repeating completed local science", async () => {
    analysisStop = (await inspect()).run;
    assert.equal(analysisStop.status, "failed"); assert.equal(analysisStop.stage, "annotation_propose");
    assert.equal(analysisStop.revision, 19); assert.equal(analysisStop.failure.message, "Provider request stopped: provider_error");
    for (const stage of ["qc_apply", "analysis", "markers", "annotation_evidence"]) assert.equal(analysisStop.nodes[stage], "EXECUTED");
    assert.equal(await ui("run-continue").isDisabled(), true); assert.equal(await ui("run-continue-retry").isDisabled(), true);
    const proof = await fixedR(project, "inspect"); assert.equal(proof.provider_ledger_entries, 2); assert.equal(proof.mock_calls_this_process, 0);
    await screenshot("03-saved-offline-mock-failure-recovery-boundary");
  });
  else {
  await test("pending QC/CSRF/unsupported R callback requests cannot dispatch computation", async () => {
    initial = (await inspect()).run; assert.equal(initial.status, "awaiting_review"); assert.equal(initial.review_node.kind, "qc");
    report.rawCells = initial.qc_preview.details.retention.before; report.retainedCells = initial.qc_preview.details.retention.retained;
    const before = await snapshot(project, true), body = continuePayload(initial);
    await post("/api/run-review/continue", body, true); await post("/api/run-review/continue", body, true, "invalid-csrf-token");
    await post("/api/run-review/continue", {...body, chat_fn: "not executable R", provider: "forbidden HTTP provider"}, true);
    assert.deepEqual(await snapshot(project, true), before); assert.equal((await continuation()).job, null);
    assert.equal(await ui("run-continue").isDisabled(), true); await screenshot("01-qc-review-continue-disabled");
  });
  await test("actual browser QC approval authorizes the exact frozen scope only", async () => {
    const frame = page.frameLocator("#run-qc-frame"); await frame.locator("#qc-approve").waitFor();
    await frame.locator("#qc-reviewer").fill("Independent offline browser analyst");
    await frame.locator("#qc-reason").fill("Approve the exact toy/public software-control scope; not optimal biological QC");
    await frame.locator("#qc-approve").click(); await idle();
    await page.waitForFunction(() => document.getElementById("run-status").textContent.startsWith("ready"));
    approved = (await inspect()).run; assert.equal(approved.stage, "qc_apply"); assert.equal(await ui("run-continue").isEnabled(), true);
    await fs.cp(project, approvedCopy, {recursive: true, force: false, errorOnExist: true});
    const before = await snapshot(project, true), body = continuePayload(approved);
    for (const bad of [{...body, project_id: "foreign-project"}, {...body, input_hash: "0".repeat(64)}, {...body, expected_revision: approved.revision - 1}])
      await post("/api/run-review/continue", bad, true);
    const replayBefore = await snapshot(project);
    const replay = await post("/api/run-review/decision", reviewPayload(initial, "approve"));
    assert.equal(replay.run.revision, approved.revision); assert.deepEqual(await snapshot(project), replayBefore);
    assert.deepEqual(await snapshot(project, true), before); await screenshot("02-qc-approved-local-continue");
  });
  }
  if (resumePhase !== "annotation-failed") await test("real async R worker survives browser and HTTP server disconnect, duplicate ID never reruns", async () => {
    const request = await clickContinue(), id = request.result.job.job_id;
    const duplicate = await post("/api/run-review/continue", request.body); assert.equal(duplicate.duplicate, true); assert.equal(duplicate.job.job_id, id);
    report.analysisContinueRequest = request.body; report.jobBeforeDisconnect = (await continuation()).job;
    assert(["queued", "running"].includes(report.jobBeforeDisconnect.status), "Disconnect must occur while the genuine R task is still active");
    await page.close(); await stop(); await start(project); await newPage();
    const done = await finish(id, project); assert.equal(done.job.next_run_status, "awaiting_configuration"); assert.equal(done.job.next_run_stage, "annotation_propose");
    analysisStop = (await inspect()).run; assert.equal(analysisStop.status, "awaiting_configuration"); assert.equal(analysisStop.stage, "annotation_propose");
    const scienceBefore = await snapshot(project, true), replay = await post("/api/run-review/continue", request.body);
    assert.equal(replay.duplicate, true); assert.equal(replay.job.job_id, id); assert.deepEqual(await snapshot(project, true), scienceBefore);
    await refresh(); assert.equal(await ui("run-continue").isDisabled(), true);
    const offline = await fixedR(project, "inspect"); assert.equal(offline.provider_ledger_entries, 1); assert.equal(offline.mock_calls_this_process, 0);
    report.dataset = offline.dataset; report.analysisBoundary = analysisStop.diagnostics?.local_continue_boundary;
    assert.equal(report.analysisBoundary?.dispatch, "not_sent"); assert.equal(report.analysisBoundary?.kind, "annotation");
    await screenshot("03-annotation-configuration-boundary");
  });
  await test("explicit fixed R annotation configuration then browser whole-proposal coarse/Unknown edits", async () => {
    const configured = await fixedR(project, "annotate"); assert.equal(configured.status, "awaiting_review"); await refresh();
    annotationInitial = (await inspect()).run; assert.equal(annotationInitial.review_node.kind, "annotation");
    let rows = array(annotationInitial.annotation_review.details.annotations); assert(rows.length >= 1);
    assert.equal(annotationInitial.annotation_review.details.cell_count, report.retainedCells);
    report.annotationClusterCount = rows.length;
    report.annotationSuppliedMarkerCounts = rows.map(row => ({clusterId: row.clusterId, count: array(row.supplied_marker_stats).length}));
    const coarseCandidate = rows.find(row => array(row.supplied_marker_stats).length > 0);
    report.coarseCoverageAvailable = !!coarseCandidate;
    if (!coarseCandidate) report.coarseCoverageLimitation = "Actual saved synthetic analysis has one cluster and no supplied markers. Review retains Unknown; coarse/cited-marker coverage is unavailable.";
    if (report.dataset === "pbmc") {
      assert(coarseCandidate, "Public coarse UI test needs one actual current marker; final labels remain Unknown");
      const gene = array(coarseCandidate.supplied_marker_stats)[0].gene;
      await page.locator("#annotation-clusters button").filter({hasText: "Cluster " + coarseCandidate.clusterId}).first().click();
      await ui("annotation-coarser").click(); await ui("annotation-label").fill("Software-test coarse candidate");
      await ui("annotation-citations").getByRole("checkbox", {name: gene, exact: true}).check();
      await ui("annotation-rationale").fill("Temporary software-control correction using one actual supplied marker; not a biological identity. Revise to Unknown before approval.");
      await ui("annotation-reviewer").fill("Independent offline browser analyst");
      await ui("annotation-reason").fill("Save a temporary coarse-control proposal to verify current-marker binding; final approval will retain Unknown.");
      await ui("annotation-save").click(); await idle();
      const temporary = (await inspect()).run;
      const candidate = array(temporary.annotation_review.details.annotations).find(row => row.clusterId === coarseCandidate.clusterId);
      assert.equal(candidate.proposal.label, "Software-test coarse candidate"); assert(array(candidate.proposal.markers).includes(gene));
      report.temporaryCoarseCorrection = {clusterId: coarseCandidate.clusterId, citedGene: gene,
        proposalHash: temporary.review_node.proposal_hash, approved: false, finalAction: "revise to Unknown before approval"};
      rows = array(temporary.annotation_review.details.annotations);
    }
    for (const [index, row] of rows.entries()) {
      await page.locator("#annotation-clusters button").filter({hasText: "Cluster " + row.clusterId}).first().click();
      if (index === 0 && report.dataset === "synthetic" && array(row.supplied_marker_stats).length > 0) {
        await ui("annotation-coarser").click(); await ui("annotation-label").fill("Mock broad planted-program candidate");
        const gene = array(row.supplied_marker_stats)[0]?.gene; assert(gene);
        await ui("annotation-citations").getByRole("checkbox", {name: gene, exact: true}).check();
        await ui("annotation-rationale").fill("Explicit coarse synthetic-program correction using one current marker; no biological identity established.");
      } else {
        await ui("annotation-unknown").click();
        await ui("annotation-rationale").fill("Explicit offline review keeps this literal cluster Unknown; supplied markers are insufficient for identity.");
      }
    }
    assert.equal(await ui("annotation-approve").isDisabled(), true);
    await ui("annotation-reviewer").fill("Independent offline browser analyst");
    await ui("annotation-reason").fill("Save the entire reviewed current-cluster proposal with explicit coarse/Unknown uncertainty.");
    await ui("annotation-save").click(); await idle(); annotationReviewed = (await inspect()).run;
    assert.notEqual(annotationReviewed.review_node.proposal_hash, annotationInitial.review_node.proposal_hash);
    assert.equal(annotationReviewed.annotation_review.details.source.kind, "manual");
    const before = await snapshot(project, true); await post("/api/run-review/decision", reviewPayload(annotationInitial, "approve"), true);
    const body = reviewPayload(annotationReviewed, "revise"); body.proposal = structuredClone(annotationReviewed.annotation_review.details.canonical_proposal);
    const negativeIndex = coarseCandidate ? body.proposal.annotations.findIndex(row => row.clusterId === coarseCandidate.clusterId) : 0;
    body.proposal.annotations[negativeIndex].markers = ["HALLUCINATED_GENE_NOT_IN_CURRENT_EVIDENCE"];
    await post("/api/run-review/decision", body, true); assert.deepEqual(await snapshot(project, true), before);
    await screenshot("04-exact-manual-annotation-review");
  });
  await test("browser exact annotation approval plus real async Continue creates final object", async () => {
    await ui("annotation-reviewer").fill("Independent offline browser analyst");
    await ui("annotation-reason").fill("Approve exact current manual coarse/Unknown view, cells and cited markers; no biological truth claim.");
    await ui("annotation-approve").click(); await idle();
    const run = (await inspect()).run; assert.equal(run.stage, "annotation_apply"); assert.equal(run.status, "ready");
    const request = await clickContinue(), done = await finish(request.result.job.job_id, project);
    assert.equal(done.job.next_run_status, "complete"); await refresh(); complete = (await inspect()).run;
    assert.equal(complete.status, "complete"); assert.equal(await ui("run-continue").isDisabled(), true);
    await fixedR(project, "verify"); report.finalObject = complete.output.seurat; report.finalObjectSHA256 = sha(await fs.readFile(complete.output.seurat));
    report.finalCanonicalProposal = complete.annotation_review.details.canonical_proposal; await screenshot("05-browser-completed-object");
    const before = await snapshot(project, true); const duplicate = await post("/api/run-review/continue", request.body);
    assert.equal(duplicate.duplicate, true); assert.equal(duplicate.job.job_id, request.result.job.job_id); assert.deepEqual(await snapshot(project, true), before);
  });
  await test("fresh R local Continue and another HTTP server restore completion byte-identically", async () => {
    const before = await snapshot(project); await fixedR(project, "continue"); assert.deepEqual(await snapshot(project), before);
    await stop(); await start(project); await page.goto(origin + "/"); await idle();
    const current = (await inspect()).run; assert.equal(current.status, "complete"); assert.equal(current.revision, complete.revision);
    assert.equal(current.annotation_review.hash, complete.annotation_review.hash); assert.deepEqual(await snapshot(project), before);
  });
  }
  if (report.dataset === "synthetic") {
    if (resumePhase !== "complete") await test("actual R saved local failure requires explicit UI retry and reruns no completed QC stage", async () => {
      const failureProject = path.join(output, "actual-failed-analysis-project");
      await fs.cp(approvedCopy, failureProject, {recursive: true, force: false, errorOnExist: true});
      const failed = await fixedR(failureProject, "fail-analysis"); assert.equal(failed.status, "failed"); assert.equal(failed.stage, "analysis");
      await stop(); await start(failureProject); await page.goto(origin + "/"); await idle();
      const before = await snapshot(failureProject, true), current = (await inspect()).run;
      await post("/api/run-review/continue", continuePayload(current), true);
      assert.deepEqual(await snapshot(failureProject, true), before); assert.equal(await ui("run-continue").isDisabled(), true);
      assert.equal(await ui("run-continue-retry").isEnabled(), true);
      const request = await clickContinue(true), done = await finish(request.result.job.job_id, failureProject);
      assert.equal(done.job.next_run_status, "awaiting_configuration"); assert.equal(done.job.next_run_stage, "annotation_propose");
      report.actualFailureRetry = {failure: failed, job: done.job}; await refresh(); await screenshot("06-explicit-actual-r-retry");
    });
    await test("synthetic external-transfer review cannot be bypassed by local Continue", async () => {
      const externalProject = path.join(output, "synthetic-external-preview-project");
      const proof = await fixedR(externalProject, "external-preview"); assert.equal(proof.mock_calls_this_process, 0);
      await stop(); await start(externalProject); await page.goto(origin + "/"); await idle();
      const run = (await inspect()).run; assert.equal(run.pending.kind, "external_transfer");
      const before = await snapshot(externalProject, true); await post("/api/run-review/continue", continuePayload(run), true);
      assert.deepEqual(await snapshot(externalProject, true), before); assert.equal((await continuation()).job, null);
      assert.equal(await ui("run-continue").isDisabled(), true); report.externalPreviewDispatches = 0;
    });
    await test("isolated changed-input copy is rejected by actual R bridge without changing scientific journal", async () => {
      const changedProject = path.join(output, "isolated-changed-input-project");
      await fs.cp(approvedCopy, changedProject, {recursive: true, force: false, errorOnExist: true});
      await stop(); await start(changedProject); const run = (await inspect()).run;
      await fixedR(changedProject, "mutate-input"); const before = await snapshot(changedProject, true);
      const response = await fetch(origin + "/api/run-review/continue", {method: "POST", headers: {
        "Content-Type": "application/json", Origin: origin, "X-ScAgentKit-Run-Token": token}, body: JSON.stringify(continuePayload(run))});
      const result = await response.json();
      if (response.status === 202) {
        for (let i = 0; i < 180; i++) {
          const current = await continuation();
          if (!["queued", "running"].includes(current.job.status)) {assert.equal(current.job.status, "failed"); report.changedInputRejectionJob = current.job; break;}
          await pause(200);
          if (i === 179) throw new Error("Changed-input bridge rejection timed out");
        }
      } else assert(response.status >= 400 && response.status < 500, JSON.stringify(result));
      assert.deepEqual(await snapshot(changedProject, true), before);
    });
  } else report.reusedSyntheticMechanismCoverage = ["actual local failure/retry", "external preview", "isolated input-byte mutation"];
  assert.equal(report.pageErrors.length, 0, JSON.stringify(report.pageErrors)); assert.equal(report.externalRequests.length, 0, JSON.stringify(report.externalRequests));
  assert.deepEqual(await snapshot(source), sourceBefore, "Frozen source fixture never changes");
  if (resumeSource) {
    assert.deepEqual(await snapshot(resumeSource, false, resumeExcluded), resumeBefore, "Preserved partial browser reports, logs, screenshots and approved checkpoint never change");
    report.previousSegment.allPreservedEvidenceBytesUnchanged = true;
  }
  assert.equal(sha(await fs.readFile(fixtureScript)), fixtureHash);
  if (recoveryScript) assert.equal(sha(await fs.readFile(recoveryScript)), recoveryHash);
  if (externalScript) assert.equal(sha(await fs.readFile(externalScript)), externalHash);
  if (completedProjectBefore) {
    assert.deepEqual(await snapshot(project), completedProjectBefore); report.completedCanonicalAllBytesUnchanged = true;
  }
  for (const [relative, hash] of Object.entries(report.productionSHA256)) assert.equal(sha(await fs.readFile(path.join(root, relative))), hash, "Production cannot change during real acceptance");
  report.passed = true;
} catch (error) {
  report.passed = false; report.error = error.stack; console.error(error.stack); process.exitCode = 1;
} finally {
  await browser?.close(); await stop(); report.completedAt = new Date().toISOString();
  report.ownedLoopbackOrigins = [...ownedOrigins];
  try {
    assert.deepEqual(await snapshot(source), sourceBefore); report.sourceFixtureAllBytesUnchanged = true;
    assert.equal(await verifyProtected(), report.protectedOldFileCount); report.protectedOldFilesUnchanged = true;
    if (resumeSource) {
      assert.deepEqual(await snapshot(resumeSource, false, resumeExcluded), resumeBefore);
      report.previousSegment.allPreservedEvidenceBytesUnchanged = true;
    }
    if (completedProjectBefore) {
      assert.deepEqual(await snapshot(project), completedProjectBefore); report.completedCanonicalAllBytesUnchanged = true;
    }
  } catch (error) {report.passed = false; report.preservationError = error.message; process.exitCode = 1;}
  await fs.writeFile(path.join(output, "server.log"), logs.join(""));
  await fs.writeFile(reportFile, JSON.stringify(report, null, 2) + "\n");
}
