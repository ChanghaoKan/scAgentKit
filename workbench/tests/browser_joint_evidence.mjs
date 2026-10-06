#!/usr/bin/env node
/** Actual Chrome + fixed real R bridge on a NEW processed public PBMC fixture.
 * Historical responses are readonly companions, never live provider callbacks.
 * Root executes only after production, UI, fixture, and private R install freeze.
 */
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import net from "node:net";
import {spawn} from "node:child_process";
import {createRequire} from "node:module";
import {fileURLToPath} from "node:url";

const args = {};
for (let i = 2; i < process.argv.length; i += 2) {
  assert(process.argv[i]?.startsWith("--") && process.argv[i + 1], "Use --name value pairs");
  args[process.argv[i].slice(2)] = process.argv[i + 1];
}
assert(args.project && args.output && args["fixture-script"] && args["source-plan"] && args["r-library"] && /^[a-f0-9]{64}$/.test(args.implementation || ""));
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = path.resolve(args.project), output = path.resolve(args.output), fixture = path.resolve(args["fixture-script"]);
await fs.mkdir(output, {recursive: true});
const reportFile = path.join(output, "joint-evidence-browser-report.json");
assert.equal(await fs.access(reportFile).then(() => true, () => false), false, "Never overwrite prior browser evidence");
const require = createRequire(import.meta.url);
const {chromium} = require(args.playwright || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
const array = value => value == null ? [] : Array.isArray(value) ? value : [value];
const exists = file => fs.access(file).then(() => true, () => false);
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const env = {...process.env, PYTHONDONTWRITEBYTECODE: "1", R_LIBS_USER: args["r-library"], SCAGENTKIT_EXPECTED_IMPLEMENTATION: args.implementation};
for (const key of ["DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY",
  "GOOGLE_API_KEY", "GEMINI_API_KEY", "AZURE_OPENAI_API_KEY", "COHERE_API_KEY", "MISTRAL_API_KEY", "OPENROUTER_API_KEY", "HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN"]) delete env[key];
const planFile = path.resolve(args["source-plan"]), planBytes = await fs.readFile(planFile), plan = JSON.parse(planBytes);
const report = {startedAt: new Date().toISOString(), sourceFixture: source, fixtureScript: fixture,
  implementationHash: args.implementation, sourcePlan: planFile, sourcePlanSHA256: sha(planBytes),
  tests: [], rProcesses: [], jobs: [], screenshots: [], pageErrors: [], externalRequests: [],
  actualChrome: false, actualRBridge: false, simulatedRBridge: false,
  newProviderCalls: 0, paidProviderCalls: 0, costUSD: 0, historicalImport: "Original public DeepSeek independent nine-cluster responses; not a new model request"};
let server, browser, context, page, origin, token; const origins = new Set(), logs = [];
async function snapshot(directory, scientificOnly = false) {
  const files = {};
  async function walk(here) {
    for (const item of await fs.readdir(here, {withFileTypes: true})) {
      if (scientificOnly && here === directory && item.name === ".workbench-jobs") continue;
      const full = path.join(here, item.name); assert(!item.isSymbolicLink());
      if (item.isDirectory()) await walk(full);
      else if (item.isFile()) files[path.relative(directory, full)] = sha(await fs.readFile(full));
    }
  }
  await walk(directory); return files;
}
async function protect() {
  let count = 0;
  for (const [file, record] of Object.entries(plan.inputs)) {assert.equal(sha(await fs.readFile(file)), record.sha256, "Readonly source/reference/history byte hash"); count++;}
  assert.equal(sha(await fs.readFile(planFile)), report.sourcePlanSHA256); return count;
}
report.protectedInputFileCount = await protect();
const sourceBefore = await snapshot(source), fixtureHash = sha(await fs.readFile(fixture));
assert.equal(await exists(path.join(source, ".workbench-jobs")), false, "Prepare in R only; do not copy a directory-bound HTTP job");
const project = path.join(output, "review-project");
await fs.cp(source, project, {recursive: true, force: false, errorOnExist: true});
report.project = project; report.fixtureScriptSHA256 = fixtureHash;
report.productionSHA256 = {};
for (const file of ["server.py", "run_review_runtime.py", "run_review_bridge.R", "run_continue_runtime.py", "run_continue_worker.py", "run_continue_bridge.R", "static/review.js", "static/review.html", "static/review.css"])
  report.productionSHA256[file] = sha(await fs.readFile(path.join(root, file)));
async function test(name, action) {
  const began = Date.now();
  try {await action(); await protect(); report.tests.push({name, outcome: "passed", milliseconds: Date.now() - began, readonlyInputsUnchanged: true}); console.log("PASS " + name);}
  catch (error) {report.tests.push({name, outcome: "failed", error: error.message}); throw error;}
}
async function availablePort() {
  const listener = net.createServer(); await new Promise((resolve, reject) => {listener.once("error", reject); listener.listen(0, "127.0.0.1", resolve);});
  const port = listener.address().port; await new Promise(resolve => listener.close(resolve)); return port;
}
async function start() {
  origin = "http://127.0.0.1:" + await availablePort(); origins.add(origin);
  server = spawn(args.python || "python3", [path.join(root, "server.py"), "--run-project", project, "--local-continue", "--r-library", args["r-library"], "--rscript", args.rscript || "Rscript", "--port", new URL(origin).port], {cwd: path.dirname(root), env, stdio: ["ignore", "pipe", "pipe"]});
  server.stdout.on("data", bytes => logs.push(bytes.toString())); server.stderr.on("data", bytes => logs.push(bytes.toString()));
  for (let i = 0; i < 180; i++) {
    if (server.exitCode != null) throw new Error("Owned server exited before readiness");
    let response; try {response = await fetch(origin + "/api/run-review/inspect");} catch {}
    if (response?.ok) {token = (await response.json()).csrf_token; return;}
    if (response && response.status >= 400 && response.status < 500) throw new Error("Configured fixture rejected at HTTP " + response.status);
    await pause(200);
  }
  throw new Error("Owned server did not become ready");
}
async function stop() {
  if (!server || server.exitCode != null || server.signalCode != null) return;
  const child = server, closed = new Promise(resolve => child.once("exit", resolve)); child.kill("SIGTERM");
  await Promise.race([closed, pause(3000)]);
  if (child.exitCode == null && child.signalCode == null) {child.kill("SIGKILL"); await closed;}
}
async function inspect() {
  const response = await fetch(origin + "/api/run-review/inspect"), result = await response.json();
  assert.equal(response.status, 200, result.error?.message); token = result.csrf_token; return result;
}
function binding(run, action) {return {action, kind: "annotation", project_id: run.project_id, input_hash: run.input_hash,
  proposal_hash: run.review_node.proposal_hash, review_hash: run.review_node.review_hash, expected_revision: run.revision,
  reviewer: "Offline CM2 Chrome analyst", reason: "Exact local public evidence software acceptance; biological identity remains Unknown"};}
async function post(route, body, reject = false, csrf = token) {
  const response = await fetch(origin + route, {method: "POST", headers: {"Content-Type": "application/json", Origin: origin, "X-ScAgentKit-Run-Token": csrf || ""}, body: JSON.stringify(body)});
  const result = await response.json(), summary = JSON.stringify({httpStatus: response.status, schema: result.schema, error: result.error, stage: result.run?.stage});
  if (reject) assert(response.status >= 400 && response.status < 500, summary);
  else assert.equal(response.status, route.endsWith("continue") ? 202 : 200, summary);
  return result;
}
async function fixedR(mode) {
  assert(["inspect", "refresh", "verify", "continue"].includes(mode)); assert.equal(sha(await fs.readFile(fixture)), fixtureHash);
  const stdout = [], stderr = [], began = Date.now();
  const child = spawn(args.rscript || "Rscript", ["--vanilla", fixture, project, mode], {env, stdio: ["ignore", "pipe", "pipe"]});
  child.stdout.on("data", bytes => stdout.push(bytes)); child.stderr.on("data", bytes => stderr.push(bytes));
  const status = await new Promise((resolve, reject) => {child.once("error", reject); child.once("exit", (code, signal) => resolve({code, signal}));});
  const text = Buffer.concat(stdout).toString() + Buffer.concat(stderr).toString(), log = `r-${report.rProcesses.length + 1}-${mode}.log`;
  await fs.writeFile(path.join(output, log), text);
  const line = text.split("\n").find(line => line.startsWith("SC_CM2_FIXTURE_JSON="));
  const proof = line ? JSON.parse(line.slice("SC_CM2_FIXTURE_JSON=".length)) : null;
  report.rProcesses.push({mode, pid: proof?.pid, ...status, milliseconds: Date.now() - began, log, proof});
  assert.equal(status.code, 0, text.slice(-1800)); assert(proof && text.includes("paid API:0")); assert.equal(proof.provider_calls, 0); return proof;
}
const ui = id => page.locator('[data-testid="' + id + '"]');
async function idle() {await ui("run-refresh").waitFor(); await page.waitForFunction(() => !document.getElementById("run-refresh").disabled);}
async function refresh() {await ui("run-refresh").click(); await idle();}
async function newPage() {page = await context.newPage(); page.setDefaultTimeout(90000); page.on("pageerror", error => report.pageErrors.push(error.message)); page.on("dialog", dialog => dialog.accept()); await page.goto(origin + "/"); await idle();}
async function screenshot(name) {const file = path.join(output, name + ".png"); await page.screenshot({path: file, fullPage: true}); report.screenshots.push(file);}
async function select(id) {await page.locator("#annotation-clusters button").filter({hasText: "Cluster " + id}).first().click();}
function checkJoint(row, topN) {
  const joint = row.joint_evidence; assert.equal(joint.schema, "scagentkit.joint-annotation-evidence.v1"); assert.equal(joint.clusterId, row.clusterId);
  assert.equal(joint.current.label, "Unknown"); assert.equal(joint.current.source.kind, "manual");
  assert.equal(joint.historical.status, "supplied"); assert.equal(joint.historical.row.clusterId, row.clusterId);
  assert.equal(joint.historical.provenance.scope_status, "verified"); assert.equal(joint.historical.provenance.model, "deepseek-flash");
  assert.equal(joint.historical.provenance.reference_dependency, "independent");
  assert.equal(joint.dependency.planned_mode ?? joint.dependency.mode, "independent");
  assert.equal(joint.dependency.actual_mode, "not_dispatched");
  assert(["exact_label", "unresolved_label_difference", "missing_information"].includes(joint.comparison.status), "No explicit maps/relations means no guessed mapped/granularity/lineage status");
  assert.equal(joint.database.scoring.formula, "unique hits / unique reference genes"); assert.equal(joint.database.scoring.calibrated_probability, false);
  const candidates = array(joint.database.candidates); assert(candidates.length <= topN);
  for (const candidate of candidates) {
    assert(candidate.overlap > 0 && candidate.referenceSize > 0); assert(Math.abs(candidate.score - candidate.overlap / candidate.referenceSize) < 1e-12);
    assert.equal(new Set(array(candidate.markers)).size, candidate.overlap);
    assert.equal(new Set(array(candidate.referenceGenes)).size, candidate.referenceSize);
  }
  assert.equal(joint.counterevidence.status, "not_supplied"); assert.equal(array(joint.counterevidence.records).length, 0);
  return joint;
}
let initial, changed, reviewed, complete;
try {
  await start(); browser = await chromium.launch({headless: true, env, executablePath: args.chrome || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}); report.actualChrome = true;
  context = await browser.newContext({viewport: {width: 1440, height: 1100}});
  await context.route("**/*", route => {const url = route.request().url(); if ([...origins].some(local => url.startsWith(local + "/")) || url.startsWith("data:")) return route.continue(); report.externalRequests.push(url); return route.abort();});
  await newPage();
  await test("actual compact CM2/current summary and readonly historical detail on exact public scope", async () => {
    initial = (await inspect()).run; assert.equal(initial.status, "awaiting_review"); assert.equal(initial.review_node.kind, "annotation");
    const rows = array(initial.annotation_review.details.annotations); assert.equal(rows.length, 9); assert.equal(initial.annotation_review.details.cell_count, 2638);
    report.clusters = []; report.mappingDeclarations = "none supplied for actual PBMC; explicit mapping/lineage classes are covered by focused controlled fixtures";
    for (const row of rows) {
      const joint = checkJoint(row, 5); await select(row.clusterId);
      assert.equal(await ui("annotation-joint-comparison").getAttribute("data-status"), joint.comparison.status);
      assert.equal(await ui("annotation-joint-dependency").getAttribute("data-mode"), "independent");
      assert.equal(await ui("annotation-joint-dependency").getAttribute("data-actual-mode"), "not_dispatched");
      assert.equal(await ui("annotation-joint-details").evaluate(node => node.open), false);
      assert.equal(await page.locator("#annotation-joint-evidence input, #annotation-joint-evidence button, #annotation-joint-evidence select, #annotation-joint-evidence textarea").count(), 0);
      assert.equal(await ui("annotation-joint-current").isVisible(), true); assert.equal(await ui("annotation-joint-database").isVisible(), true);
      await ui("annotation-joint-details").locator("summary").click();
      assert((await ui("annotation-joint-scoring").textContent()).includes("unique hits / unique reference genes"));
      assert((await ui("annotation-joint-history").textContent()).includes(joint.historical.row.label));
      assert(/histor|import|new.*request/i.test(await ui("annotation-joint-history").textContent()));
      assert((await ui("annotation-joint-source").textContent()).includes("CellMarker"));
      assert((await ui("annotation-joint-source").textContent()).includes("c1428d56ca52ad1c8e28207d93c4e50004d466e780fd717a032372d483b225a2"));
      await ui("annotation-joint-details").locator("summary").click();
      report.clusters.push({clusterId: row.clusterId, cells: row.cell_count, comparison: joint.comparison,
        displayedCandidates: array(joint.database.candidates).length, historicalLabel: joint.historical.row.label,
        historicalCitationCount: array(joint.historical.row.citations).length, provenance: joint.historical.provenance});
    }
    await fixedR("inspect"); await screenshot("01-compact-joint-evidence");
  });
  await test("explicit R reference refresh makes the actual old browser approval stale without provider or foundation rerun", async () => {
    await fixedR("refresh"); const before = await snapshot(project, true);
    await ui("annotation-reviewer").fill("Offline CM2 Chrome analyst"); await ui("annotation-reason").fill("Deliberately test stale exact evidence approval; it must be rejected.");
    const response = page.waitForResponse(result => new URL(result.url()).pathname === "/api/run-review/decision" && result.request().method() === "POST");
    await ui("annotation-approve").click(); const rejected = await response; assert(rejected.status() >= 400 && rejected.status() < 500);
    assert.deepEqual(await snapshot(project, true), before);
    await post("/api/run-review/decision", binding(initial, "approve"), true); assert.deepEqual(await snapshot(project, true), before);
    await refresh(); changed = (await inspect()).run;
    assert.notEqual(changed.review_node.review_hash, initial.review_node.review_hash); assert.equal(changed.input_hash, initial.input_hash);
    for (const row of array(changed.annotation_review.details.annotations)) checkJoint(row, 3);
    report.referenceRefresh = {oldReviewHash: initial.review_node.review_hash, newReviewHash: changed.review_node.review_hash, staleBrowserHTTP: rejected.status(), sourceUnchanged: true};
    await screenshot("02-refreshed-exact-evidence");
  });
  await test("whole Unknown plan revision preserves imported history and rejects stale or hallucinated citations", async () => {
    for (const row of array(changed.annotation_review.details.annotations)) {
      await select(row.clusterId); await ui("annotation-unknown").click();
      await ui("annotation-rationale").fill("Current manual review keeps this literal public cluster Unknown. CM2 coverage and historical AI labels are companion evidence without biological identity acceptance.");
    }
    assert.equal(await ui("annotation-approve").isDisabled(), true);
    await ui("annotation-reviewer").fill("Offline CM2 Chrome analyst"); await ui("annotation-reason").fill("Save the complete Unknown plan on the exact current evidence and scope; no per-cluster approval.");
    await ui("annotation-save").click(); await idle(); reviewed = (await inspect()).run;
    assert.notEqual(reviewed.review_node.proposal_hash, changed.review_node.proposal_hash);
    for (const row of array(reviewed.annotation_review.details.annotations)) checkJoint(row, 3);
    const before = await snapshot(project, true);
    await post("/api/run-review/decision", binding(changed, "approve"), true);
    const changedInput = binding(reviewed, "approve");
    changedInput.input_hash = reviewed.input_hash === "0".repeat(64) ? "1".repeat(64) : "0".repeat(64);
    await post("/api/run-review/decision", changedInput, true);
    const forged = binding(reviewed, "revise"); forged.proposal = structuredClone(reviewed.annotation_review.details.canonical_proposal);
    forged.proposal.annotations[0].markers = ["HALLUCINATED_GENE_NOT_IN_CURRENT_EVIDENCE"];
    await post("/api/run-review/decision", forged, true);
    await post("/api/run-review/decision", binding(reviewed, "approve"), true, "invalid-csrf-token");
    assert.deepEqual(await snapshot(project, true), before); await screenshot("03-whole-reviewed-unknown-plan");
  });
  await test("actual browser approval plus real fixed R Continue writes only new Unknown columns", async () => {
    await ui("annotation-reviewer").fill("Offline CM2 Chrome analyst"); await ui("annotation-reason").fill("Approve only the complete current manual Unknown plan, exact cells, and immutable joint evidence.");
    await ui("annotation-approve").click(); await idle(); const approved = (await inspect()).run;
    assert.equal(approved.status, "ready"); assert.equal(approved.stage, "annotation_apply");
    const response = page.waitForResponse(result => new URL(result.url()).pathname === "/api/run-review/continue" && result.request().method() === "POST");
    await ui("run-continue").click(); const accepted = await response, answer = await accepted.json(), request = accepted.request().postDataJSON();
    assert.equal(accepted.status(), 202); assert.equal(request.retry, false); const jobId = answer.job.job_id;
    assert.deepEqual(Object.keys(request).sort(), ["project_id", "input_hash", "expected_revision", "request_id", "retry"].sort());
    const duplicate = await post("/api/run-review/continue", request); assert.equal(duplicate.duplicate, true); assert.equal(duplicate.job.job_id, jobId);
    let current;
    for (let i = 0; i < 1200; i++) {current = await (await fetch(origin + "/api/run-review/continuation")).json(); assert.equal(current.job.job_id, jobId); if (!["queued", "running"].includes(current.job.status)) break; await pause(500);}
    assert.equal(current.job.status, "succeeded"); assert.equal(current.job.next_run_status, "complete");
    const location = path.join(project, ".workbench-jobs/jobs", jobId), owner = JSON.parse(await fs.readFile(path.join(location, "owner.json"), "utf8"));
    const config = JSON.parse(await fs.readFile(path.join(location, "config.json"), "utf8")), bytes = await fs.readFile(path.join(location, "response.json"));
    assert(owner.r_pid > 0 && owner.worker_pid > 0 && owner.r_pid !== owner.worker_pid); assert.equal(owner.r_exit_code, 0);
    assert.equal(path.basename(config.bridge), "run_continue_bridge.R"); assert.equal(JSON.parse(bytes).ok, true);
    report.actualRBridge = true; report.jobs.push({public: current.job, owner, codeHashes: config.code_hashes, responseSHA256: sha(bytes)});
    await refresh(); complete = (await inspect()).run; assert.equal(complete.status, "complete");
    const verified = await fixedR("verify"); report.approvedEvidenceSummary = verified.approved_evidence_summary;
    assert.equal(report.approvedEvidenceSummary.review_hash, complete.annotation_review.hash);
    assert.equal(sha(await fs.readFile(report.approvedEvidenceSummary.path)), report.approvedEvidenceSummary.sha256);
    report.finalObject = complete.output.seurat; report.finalObjectSHA256 = sha(await fs.readFile(complete.output.seurat));
    const before = await snapshot(project, true); const replay = await post("/api/run-review/continue", request); assert.equal(replay.duplicate, true); assert.deepEqual(await snapshot(project, true), before);
    await screenshot("04-completed-public-unknown-output");
  });
  await test("new R process and server restart preserve completed output and all saved project bytes", async () => {
    const before = await snapshot(project); await fixedR("continue"); assert.deepEqual(await snapshot(project), before);
    await stop(); await start(); await page.goto(origin + "/"); await idle(); const run = (await inspect()).run;
    assert.equal(run.status, "complete"); assert.equal(run.revision, complete.revision); assert.equal(run.annotation_review.hash, complete.annotation_review.hash);
    assert.deepEqual(await snapshot(project), before); assert.equal(sha(await fs.readFile(run.output.seurat)), report.finalObjectSHA256);
  });
  assert.equal(report.pageErrors.length, 0); assert.equal(report.externalRequests.length, 0);
  for (const [file, digest] of Object.entries(report.productionSHA256)) assert.equal(sha(await fs.readFile(path.join(root, file))), digest, "Production changed during acceptance");
  report.passed = true;
} catch (error) {report.passed = false; report.error = error.stack; console.error(error.stack); process.exitCode = 1;}
finally {
  await browser?.close(); await stop(); report.completedAt = new Date().toISOString(); report.ownedLoopbackOrigins = [...origins];
  try {assert.deepEqual(await snapshot(source), sourceBefore); assert.equal(sha(await fs.readFile(fixture)), fixtureHash); assert.equal(await protect(), report.protectedInputFileCount); report.readonlySourcesUnchanged = true;}
  catch (error) {report.passed = false; report.preservationError = error.message; process.exitCode = 1;}
  await fs.writeFile(path.join(output, "server.log"), logs.join("")); await fs.writeFile(reportFile, JSON.stringify(report, null, 2) + "\n");
}
