#!/usr/bin/env node
/** Independent headless Chrome + actual fixed R review bridge. The operator
 * supplies one frozen public/mock fixture script; resume is a child R process,
 * never an HTTP action or browser-supplied code. No existing browser is used.
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
assert(args.project && args["r-library"] && args["fixture-script"], "Supply a frozen public awaiting-QC fixture, private R library and fixed offline fixture Rscript");
const source = path.resolve(args.project), fixtureScript = path.resolve(args["fixture-script"]);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const output = path.resolve(args.output || await fs.mkdtemp(path.join(os.tmpdir(), "scagentkit-run-browser-")));
await fs.mkdir(output, {recursive: true});
const reportFile = path.join(output, "run-review-browser-report.json");
assert.equal(await fs.access(reportFile).then(() => true, () => false), false, "Use a fresh report directory");
const require = createRequire(import.meta.url);
const {chromium} = require(args.playwright || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
const report = {startedAt: new Date().toISOString(), sourceFixture: source, fixtureScript,
  tests: [], screenshots: [], pageErrors: [], externalRequests: [], rProcesses: [],
  actualChrome: true, actualRBridge: true, paidProviderCalls: 0, costUSD: 0};
const env = {...process.env, PYTHONDONTWRITEBYTECODE: "1", R_LIBS_USER: args["r-library"]};
for (const key of ["DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY"]) delete env[key];
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
const array = value => value == null ? [] : Array.isArray(value) ? value : [value];
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
let server, browser, context, page, origin; const logs = [];
async function snapshot(directory) {
  const files = {};
  async function walk(here) {
    for (const entry of await fs.readdir(here, {withFileTypes: true})) {
      const full = path.join(here, entry.name); assert(!entry.isSymbolicLink(), "Fixture must not contain symlinks");
      if (entry.isDirectory()) await walk(full);
      else if (entry.isFile()) files[path.relative(directory, full)] = sha(await fs.readFile(full));
    }
  }
  await walk(directory); return files;
}
const protectedBefore = await snapshot(source), scriptHashBefore = sha(await fs.readFile(fixtureScript));
const project = path.join(output, "review-project"), rejectedProject = path.join(output, "reject-project");
await fs.cp(source, project, {recursive: true, force: false, errorOnExist: true});
report.projects = {project, rejectedProject}; report.fixtureScriptSHA256 = scriptHashBefore;
async function test(name, fn) {
  const begin = Date.now();
  try {await fn(); report.tests.push({name, outcome: "passed", milliseconds: Date.now() - begin}); console.log("PASS " + name);}
  catch (error) {report.tests.push({name, outcome: "failed", error: error.message}); throw error;}
}
async function availablePort() {
  const listener = net.createServer(); await new Promise((resolve, reject) => {listener.once("error", reject); listener.listen(0, "127.0.0.1", resolve);});
  const value = listener.address().port; await new Promise(resolve => listener.close(resolve)); return value;
}
async function start(directory) {
  origin = "http://127.0.0.1:" + await availablePort();
  server = spawn(args.python || "python3", [path.join(root, "server.py"), "--run-project", directory,
    "--r-library", args["r-library"], "--rscript", args.rscript || "Rscript", "--port", new URL(origin).port],
    {cwd: path.dirname(root), env, stdio: ["ignore", "pipe", "pipe"]});
  server.stdout.on("data", value => logs.push(value.toString())); server.stderr.on("data", value => logs.push(value.toString()));
  for (let i = 0; i < 180; i++) {
    if (server.exitCode != null) throw new Error("Fresh server exited: " + logs.slice(-8).join(""));
    try {if ((await fetch(origin + "/api/run-review/inspect")).ok) return;} catch {}
    await pause(200);
  }
  throw new Error("Fresh run review server did not become ready");
}
async function stop() {
  if (!server || server.exitCode != null || server.signalCode != null) return;
  const child = server, closed = new Promise(resolve => child.once("exit", resolve));
  child.kill("SIGTERM"); await Promise.race([closed, pause(3000)]);
  if (child.exitCode == null && child.signalCode == null) {child.kill("SIGKILL"); await closed;}
}
async function api(body, expected = 200) {
  const token = (await (await fetch(origin + "/api/run-review/inspect")).json()).csrf_token;
  const response = await fetch(origin + (body ? "/api/run-review/decision" : "/api/run-review/inspect"), body ? {
    method: "POST", headers: {"Content-Type": "application/json", Origin: origin, "X-ScAgentKit-Run-Token": token}, body: JSON.stringify(body)
  } : {});
  const result = await response.json(); assert.equal(response.status, expected, JSON.stringify(result)); return result;
}
function payload(run, action) {
  const current = run.review_node;
  return {action, kind: current.kind, project_id: run.project_id, input_hash: run.input_hash,
    proposal_hash: current.proposal_hash, review_hash: current.review_hash, expected_revision: run.revision,
    reviewer: "Independent browser acceptance analyst", reason: "Explicit offline review mechanism verification"};
}
async function rProcess(mode) {
  assert(["resume", "verify", "inspect"].includes(mode));
  assert.equal(sha(await fs.readFile(fixtureScript)), scriptHashBefore, "The fixed offline Rscript must remain frozen");
  const begin = Date.now(), chunks = [], errors = [];
  const child = spawn(args.rscript || "Rscript", ["--vanilla", fixtureScript, project, mode], {env, stdio: ["ignore", "pipe", "pipe"]});
  child.stdout.on("data", value => chunks.push(value)); child.stderr.on("data", value => errors.push(value));
  const status = await new Promise((resolve, reject) => {child.once("error", reject); child.once("exit", (code, signal) => resolve({code, signal}));});
  const stdout = Buffer.concat(chunks).toString(), stderr = Buffer.concat(errors).toString();
  const filename = `r-${report.rProcesses.length + 1}-${mode}.log`;
  await fs.writeFile(path.join(output, filename), stdout + stderr);
  report.rProcesses.push({mode, ...status, milliseconds: Date.now() - begin, log: filename});
  assert.equal(status.code, 0, "Fixed offline R process failed: " + stdout.slice(-1500) + stderr.slice(-2500));
  assert(stdout.includes("paid API:0"), "Fixture must confirm its offline provider boundary"); return stdout;
}
const ui = id => page.locator('[data-testid="' + id + '"]');
async function idle() {await ui("run-refresh").waitFor(); await page.waitForFunction(() => !document.getElementById("run-refresh").disabled);}
async function refresh() {await ui("run-refresh").click(); await idle();}
async function credentials(reason = "Record the complete reviewed annotation plan for offline software verification") {
  await ui("annotation-reviewer").fill("Independent browser acceptance analyst"); await ui("annotation-reason").fill(reason);
}
async function screenshot(name) {const file = path.join(output, name + ".png"); await page.screenshot({path: file, fullPage: true}); report.screenshots.push(file);}
let qcApprovedPayload, originalAnnotation, correctedAnnotation, executedAnnotationPayload, completed, undoPayload;
try {
  await start(project);
  browser = await chromium.launch({headless: true, executablePath: args.chrome || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"});
  context = await browser.newContext({viewport: {width: 1440, height: 1000}});
  await context.route("**/*", route => {
    const url = route.request().url(); if (url.startsWith(origin + "/")) return route.continue();
    report.externalRequests.push(url); return route.abort();
  });
  page = await context.newPage(); page.setDefaultTimeout(45000); page.on("pageerror", error => report.pageErrors.push(error.message));
  page.on("dialog", dialog => dialog.accept()); await page.goto(origin + "/"); await idle();
  await test("unified page renders actual bound public QC in a fixed same-origin pane", async () => {
    const run = (await api()).run; assert.equal(run.status, "awaiting_review"); assert.equal(run.review_node.kind, "qc");
    assert.equal(run.qc_preview.details.retention.before, 2700); assert.equal(run.qc_preview.details.retention.retained, 2511);
    const frame = page.frameLocator("#run-qc-frame"); await frame.locator("#qc-approve").waitFor();
    await page.waitForFunction(() => document.getElementById("run-qc-frame").contentWindow.document.getElementById("qc-approve")?.disabled === false);
    assert.equal(await frame.locator("#qc-distributions svg").count(), 3);
    const scope = await frame.locator("#qc-cell-scope").textContent();
    for (const cell of [...array(run.qc_preview.details.keep_cells), ...array(run.qc_preview.details.remove_cells)]) assert(scope.includes(cell));
    qcApprovedPayload = payload(run, "approve"); report.inputHash = run.input_hash; report.projectId = run.project_id;
    const before = await snapshot(project), legacyView = await (await fetch(origin + "/api/qc/inspect")).json();
    const legacy = {action: "approve", proposal_hash: run.review_node.proposal_hash,
      preview_hash: run.review_node.review_hash, expected_revision: run.revision,
      reviewer: "Legacy browser analyst", reason: "This unbound legacy write must be rejected"};
    const response = await fetch(origin + "/api/qc/decision", {method: "POST",
      headers: {"Content-Type": "application/json", Origin: origin, "X-ScAgentKit-QC-Token": legacyView.csrf_token}, body: JSON.stringify(legacy)});
    assert.equal(response.status, 409); assert((await response.json()).error.includes("fully bound unified"));
    assert.deepEqual(await snapshot(project), before); report.legacyQCWriteRejected = true;
    await screenshot("01-unified-public-qc");
  });
  await test("actual QC approval is saved once and pauses without analysis", async () => {
    const frame = page.frameLocator("#run-qc-frame");
    await frame.locator("#qc-reviewer").fill("Independent browser acceptance analyst");
    await frame.locator("#qc-reason").fill("Approve the frozen public software-verification cell scope; thresholds are not biological optimization");
    await frame.locator("#qc-approve").click();
    await page.waitForFunction(() => document.getElementById("run-status").textContent.startsWith("ready")); await idle();
    const run = (await api()).run; assert.equal(run.stage, "qc_apply"); assert.equal(run.status, "ready"); assert.equal(run.pending, null);
    const before = await snapshot(project); const repeat = await api(qcApprovedPayload); assert.equal(repeat.run.status, "ready"); assert.deepEqual(await snapshot(project), before);
    const foreign = {...qcApprovedPayload, project_id: "foreign-project"}; await api(foreign, 409); assert.deepEqual(await snapshot(project), before);
    assert((await ui("run-next").textContent()).includes("sc_run_resume")); await screenshot("02-qc-approved-r-required");
  });
  await test("separate fresh R resume computes public PBMC and stops at actual mock annotation review", async () => {
    await rProcess("resume"); await refresh(); originalAnnotation = (await api()).run;
    assert.equal(originalAnnotation.status, "awaiting_review"); assert.equal(originalAnnotation.review_node.kind, "annotation");
    const details = originalAnnotation.annotation_review.details;
    assert.equal(details.cell_count, 2511); assert(details.cluster_count >= 2); assert.equal(details.source.kind, "mock");
    assert.equal(details.source.provider_response.matches_current, true); assert.equal(details.source.provider_response.kind, "mock");
    assert.equal(await ui("annotation-clusters").locator("button").count(), details.cluster_count);
    assert((await ui("annotation-provenance").textContent()).includes("offline-public-review-v1"));
    assert.equal(await ui("annotation-approve").isEnabled(), true); assert.equal(await ui("run-qc").isHidden(), true);
    await ui("annotation-all-markers").click(); assert((await ui("annotation-markers").textContent()).includes("pct1 (fraction)"));
    assert((await ui("run-annotation").textContent()).includes("omitted marker is not evidence of non-expression"));
    await fs.cp(project, rejectedProject, {recursive: true, force: false, errorOnExist: true});
    report.annotationClusters = details.cluster_count; report.originalAnnotationHash = originalAnnotation.annotation_review.hash;
    await screenshot("03-public-mock-annotation");
  });
  await test("coarser and Unknown corrections require per-cluster reasons and block unsaved approval", async () => {
    const rows = array(originalAnnotation.annotation_review.details.annotations);
    const coarse = rows.find(row => row.proposal.label.includes("IL7R-positive")) || rows[0], unresolved = rows.find(row => row.clusterId !== coarse.clusterId);
    report.correctedClusters = {coarser: coarse.clusterId, unknown: unresolved.clusterId};
    await page.locator("#annotation-clusters button").filter({hasText: "Cluster " + coarse.clusterId}).first().click();
    await ui("annotation-coarser").click(); await ui("annotation-label").fill(coarse.proposal.label.includes("IL7R-positive") ? "T cell candidate (reviewed coarse)" : "Broad candidate (reviewed coarse)");
    assert.equal(await ui("annotation-approve").isDisabled(), true); assert.equal(await ui("annotation-save").isDisabled(), true);
    await ui("annotation-rationale").fill("Subtype remains uncertain in this offline mechanism test; keep a coarser candidate. <img src=x onerror=alert(1)> is literal audit text.");
    await page.locator("#annotation-clusters button").filter({hasText: "Cluster " + unresolved.clusterId}).first().click();
    await ui("annotation-unknown").click(); assert.equal(await ui("annotation-label").inputValue(), "Unknown");
    assert.equal(await ui("annotation-confidence").inputValue(), "low"); assert.equal(await ui("annotation-save").isDisabled(), true);
    await ui("annotation-label").fill("Broad candidate supported by reviewed marker (test)");
    await ui("annotation-rationale").fill("Explicit mechanism check after Unknown: cite one supplied marker for a provisional broad candidate, without treating it as proof of identity.");
    assert.equal(await ui("annotation-save").isDisabled(), true);
    const selectedGene = array(unresolved.supplied_marker_stats)[0]?.gene; assert(selectedGene, "Public fixture must supply one literal marker for this correction roundtrip");
    await ui("annotation-citations").getByRole("checkbox", {name: selectedGene, exact: true}).check();
    assert.equal(await ui("annotation-save").isEnabled(), true); await credentials("Verify an Unknown-to-known correction uses only its supplied marker evidence");
    await ui("annotation-save").click(); await idle();
    const supported = (await api()).run.annotation_review.details;
    const supportedRow = array(supported.annotations).find(row => row.clusterId === unresolved.clusterId).proposal;
    assert.equal(supportedRow.label, "Broad candidate supported by reviewed marker (test)"); assert.deepEqual(array(supportedRow.markers), [selectedGene]);
    report.suppliedCitationRoundtrip = {clusterId: unresolved.clusterId, gene: selectedGene, actualRRebuild: true};
    await page.locator("#annotation-clusters button").filter({hasText: "Cluster " + unresolved.clusterId}).first().click();
    await ui("annotation-unknown").click();
    assert.equal(await ui("annotation-citations").getByRole("checkbox", {name: selectedGene, exact: true}).isChecked(), false);
    await ui("annotation-rationale").fill("Keep this cluster unresolved for this software test; supplied top markers do not establish an identity or excluded expression.");
    assert.equal(await ui("annotation-save").isEnabled(), true); await credentials(); await ui("annotation-save").click(); await idle();
    correctedAnnotation = (await api()).run; const d = correctedAnnotation.annotation_review.details;
    assert.notEqual(correctedAnnotation.review_node.proposal_hash, originalAnnotation.review_node.proposal_hash);
    assert.notEqual(correctedAnnotation.annotation_review.hash, originalAnnotation.annotation_review.hash); assert.equal(d.source.kind, "manual");
    assert.equal(d.source.provider_response.kind, "mock"); assert.equal(d.source.provider_response.matches_current, false);
    const currentRows = array(d.annotations); assert.equal(currentRows.find(row => row.clusterId === unresolved.clusterId).proposal.label, "Unknown");
    assert.equal(array(currentRows.find(row => row.clusterId === unresolved.clusterId).proposal.markers).length, 0);
    assert.equal(await ui("annotation-approve").isEnabled(), true); assert.equal(await ui("annotation-save").isDisabled(), true);
    await page.locator("#annotation-clusters button").filter({hasText: "Cluster " + coarse.clusterId}).first().click();
    assert.equal(await ui("annotation-suggestion").locator("img").count(), 0); assert((await ui("annotation-suggestion").textContent()).includes("<img"));
    await screenshot("04-manual-correction-rebuilt");
  });
  await test("R rejects stale annotation fingerprints and hallucinated gene citations without project writes", async () => {
    const before = await snapshot(project); await api(payload(originalAnnotation, "approve"), 409); assert.deepEqual(await snapshot(project), before);
    const body = payload(correctedAnnotation, "revise"); body.proposal = structuredClone(correctedAnnotation.annotation_review.details.canonical_proposal);
    body.proposal.annotations[0].markers = ["SCAGENTKIT_UNSUPPORTED_LITERAL_GENE"];
    await api(body, 409); assert.deepEqual(await snapshot(project), before);
  });
  await test("UI-only invalid POST response gating blocks further writes until a verified refresh", async () => {
    const before = await snapshot(project), verified = await api(); let intercepted = 0;
    const bad = structuredClone(verified); bad.schema = "unverified-response";
    await page.route("**/api/run-review/decision", route => {intercepted++; return route.fulfill({status: 200, contentType: "application/json", body: JSON.stringify(bad)});});
    await credentials(); await ui("annotation-approve").click(); await idle();
    assert.equal(await page.evaluate(() => state.stale), true); assert.equal(await page.evaluate(() => state.view.run.annotation_review.hash), correctedAnnotation.annotation_review.hash);
    for (const id of ["annotation-save", "annotation-approve", "annotation-reject", "run-undo-button"]) assert.equal(await ui(id).isDisabled(), true);
    await page.evaluate(() => document.getElementById("annotation-approve").click()); assert.equal(intercepted, 1);
    await page.route("**/api/run-review/inspect", route => route.fulfill({status: 200, contentType: "application/json", body: JSON.stringify(bad)}));
    await refresh(); assert.equal(await page.evaluate(() => state.stale), true); assert.equal(await ui("annotation-approve").isDisabled(), true);
    await page.unroute("**/api/run-review/inspect"); await refresh(); assert.equal(await page.evaluate(() => state.stale), false);
    assert.equal(await ui("annotation-approve").isEnabled(), true); await page.unroute("**/api/run-review/decision");
    assert.deepEqual(await snapshot(project), before); report.responseGatingInjectedReplies = intercepted; report.responseGatingRDecisions = 0;
  });
  await test("actual corrected annotation approval saves once and does not apply labels in HTTP", async () => {
    executedAnnotationPayload = payload((await api()).run, "approve"); await credentials(); await ui("annotation-approve").click(); await idle();
    const run = (await api()).run; assert.equal(run.status, "ready"); assert.equal(run.stage, "annotation_apply"); assert.equal(run.pending, null);
    assert.equal(await ui("annotation-approve").isDisabled(), true); const before = await snapshot(project);
    await api(executedAnnotationPayload); assert.deepEqual(await snapshot(project), before); await screenshot("05-annotation-approved-r-required");
  });
  await test("fresh R resume writes exact reviewed labels and preserves public counts and old annotation", async () => {
    await rProcess("resume"); const verification = await rProcess("verify"); await refresh(); completed = (await api()).run;
    assert.equal(completed.status, "complete"); assert.equal(completed.review_node.can_undo, true); assert.equal(await ui("annotation-approve").isDisabled(), true);
    assert.equal(await ui("run-undo-button").isEnabled(), true); assert((await ui("run-output").textContent()).includes("seurat.rds"));
    report.outputSeurat = completed.output.seurat; report.outputSHA256 = sha(await fs.readFile(completed.output.seurat));
    assert(verification.includes(report.outputSHA256)); report.finalCanonicalProposal = completed.annotation_review.details.canonical_proposal;
    await screenshot("06-public-reviewed-output");
  });
  await test("another R process and a restarted browser server restore completion without repeated execution", async () => {
    const before = await snapshot(project); await rProcess("resume"); assert.deepEqual(await snapshot(project), before);
    await stop(); await start(project); await page.goto(origin + "/"); await idle();
    const restored = (await api()).run; assert.equal(restored.status, "complete"); assert.equal(restored.revision, completed.revision);
    assert.equal(restored.annotation_review.hash, completed.annotation_review.hash); assert.equal(await ui("run-undo-button").isEnabled(), true);
  });
  await test("actual R-authority undo archives the reviewed output and rejects duplicate or undone decisions", async () => {
    undoPayload = {...payload((await api()).run, "undo"), decision_id: completed.review_node.decision_id};
    await ui("run-undo-reviewer").fill("Independent browser acceptance analyst");
    await ui("run-undo-reason").fill("Exercise the supported annotation undo while retaining original proposals, counts and decision history");
    await ui("run-undo-button").click(); await idle(); const undone = (await api()).run;
    assert.equal(undone.status, "awaiting_configuration"); assert.equal(undone.stage, "annotation_propose");
    assert.equal(undone.review_node.can_undo, false); assert.equal(undone.review_node.can_revise, true); assert.equal(undone.review_node.undone, true);
    const archived = await snapshot(path.join(project, "versions"));
    const matching = Object.entries(archived).filter(([name, digest]) => name.endsWith("/output/seurat.rds") && digest === report.outputSHA256);
    assert.equal(matching.length, 1); report.undoArchiveSeurat = path.join(project, "versions", matching[0][0]);
    const before = await snapshot(project); await api(undoPayload, 409); await api(executedAnnotationPayload, 409); assert.deepEqual(await snapshot(project), before);
    assert.equal(await ui("annotation-approve").isDisabled(), true); await screenshot("07-annotation-undone-archive");
  });
  await test("a separate actual annotation rejection preserves evidence and accepts a fresh reviewed proposal", async () => {
    await stop(); await start(rejectedProject); await page.goto(origin + "/"); await idle();
    const before = (await api()).run; await credentials("Reject this saved mock suggestion during offline review validation"); await ui("annotation-reject").click(); await idle();
    const rejected = (await api()).run; assert.equal(rejected.status, "rejected"); assert.equal(rejected.review_node.can_decide, false); assert.equal(rejected.review_node.can_revise, true);
    assert.equal(rejected.input_hash, before.input_hash); assert.equal(rejected.annotation_review.evidence_hash, before.annotation_review.evidence_hash);
    await ui("annotation-coarser").click(); await ui("annotation-label").fill("Unknown");
    await ui("annotation-rationale").fill("Reopen with an explicit unresolved label; this software test makes no negative expression claim.");
    await credentials("Replace the rejected plan with an audited unresolved proposal"); await ui("annotation-save").click(); await idle();
    const reopened = (await api()).run; assert.equal(reopened.status, "awaiting_review"); assert.equal(reopened.annotation_review.details.source.kind, "manual");
    assert.notEqual(reopened.review_node.proposal_hash, before.review_node.proposal_hash); assert.equal(await ui("annotation-approve").isEnabled(), true);
    await screenshot("08-rejection-reopened-review");
  });
  await test("source fixture and fixed script remain unchanged and Chrome makes no external requests", async () => {
    assert.deepEqual(await snapshot(source), protectedBefore); assert.equal(sha(await fs.readFile(fixtureScript)), scriptHashBefore);
    for (const target of [project, rejectedProject]) {
      const after = await snapshot(target);
      for (const [name, digest] of Object.entries(protectedBefore)) if (name.startsWith("input/") || name.startsWith("inputs/") || name === "browser-source-proof.rds") assert.equal(after[name], digest);
    }
    assert.deepEqual(report.externalRequests, []); assert.deepEqual(report.pageErrors, []); report.sourceFixturePreserved = true;
  });
  report.outcome = "passed";
} catch (error) {report.outcome = "failed"; report.error = error.stack; console.error(error.stack); process.exitCode = 1;}
finally {
  if (browser) await browser.close(); await stop(); report.finishedAt = new Date().toISOString();
  report.cleanup = {browserClosed: !browser || !browser.isConnected(), serverStopped: !server || server.exitCode != null || server.signalCode != null};
  await fs.writeFile(path.join(output, "server.log"), logs.join(""));
  try {assert.deepEqual(await snapshot(source), protectedBefore); report.sourceFixturePreserved = true;} catch(error) {report.sourceFixturePreserved = false; report.sourcePreservationError = error.message; process.exitCode = 1;}
  await fs.writeFile(reportFile, JSON.stringify(report, null, 2) + "\n"); console.log("Report: " + reportFile);
}
