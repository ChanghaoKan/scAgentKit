#!/usr/bin/env node
/** Actual Chrome + fixed R bridge. Copies an awaiting-QC fixture into fresh,
 * private test projects. The source fixture and existing services stay intact.
 * node browser_qc.mjs --project /fixture --output /fresh/report --r-library /lib
 * Optional --rscript /binary --chrome /binary --playwright /module --python /binary
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
assert(args.project && args["r-library"], "Supply an awaiting-QC fixture and the newly installed R library");
const source = path.resolve(args.project), root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const output = path.resolve(args.output || await fs.mkdtemp(path.join(os.tmpdir(), "scagentkit-qc-browser-")));
await fs.mkdir(output, {recursive: true});
const reportFile = path.join(output, "qc-browser-report.json");
assert.equal(await fs.access(reportFile).then(() => true, () => false), false, "Use a fresh report directory");
const require = createRequire(import.meta.url);
const {chromium} = require(args.playwright || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
const report = {startedAt: new Date().toISOString(), sourceFixture: source, tests: [], screenshots: [],
  pageErrors: [], externalRequests: [], providerCalls: 0, actualChrome: true, actualRBridge: true};
const gatingOnly = args["response-gating-only"] === "true";
if (gatingOnly) {report.scope = "UI response gating only; injected POST replies are not dispatched to R"; report.serverDecisionsDispatched = 0;}
const env = {...process.env};
for (const key of ["DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY"]) delete env[key];
let server, browser, page, origin; const logs = [];
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const array = value => value == null ? [] : Array.isArray(value) ? value : [value];
const hash = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
async function snapshot(directory) {
  const result = {};
  async function walk(here) {
    for (const entry of await fs.readdir(here, {withFileTypes: true})) {
      const full = path.join(here, entry.name); assert(!entry.isSymbolicLink(), "Fixture must not contain symlinks");
      if (entry.isDirectory()) await walk(full);
      else if (entry.isFile()) result[path.relative(directory, full)] = hash(await fs.readFile(full));
    }
  }
  await walk(directory); return result;
}
const protectedBefore = await snapshot(source);
const fixture = async name => {
  const target = path.join(output, name); await fs.cp(source, target, {recursive: true, errorOnExist: true, force: false}); return target;
};
const approveProject = await fixture("approve-project"), rejectProject = await fixture("reject-project");
report.projects = {approveProject, rejectProject};
async function test(name, fn) {
  const begin = Date.now();
  try {await fn(); report.tests.push({name, outcome: "passed", milliseconds: Date.now() - begin}); console.log("PASS " + name);}
  catch(error) {report.tests.push({name, outcome: "failed", error: error.message}); throw error;}
}
async function port() {
  const listener = net.createServer(); await new Promise((resolve, reject) => {listener.once("error", reject); listener.listen(0, "127.0.0.1", resolve);});
  const number = listener.address().port; await new Promise(resolve => listener.close(resolve)); return number;
}
async function start(project) {
  origin = "http://127.0.0.1:" + await port();
  server = spawn(args.python || "python3", [path.join(root, "server.py"), "--run-project", project,
    "--r-library", args["r-library"], "--rscript", args.rscript || "Rscript", "--port", new URL(origin).port],
    {cwd: path.dirname(root), env, stdio: ["ignore", "pipe", "pipe"]});
  server.stdout.on("data", data => logs.push(data.toString())); server.stderr.on("data", data => logs.push(data.toString()));
  for (let i = 0; i < 180; i++) {
    if (server.exitCode != null) throw new Error("QC server exited: " + logs.slice(-8).join(""));
    try {if ((await fetch(origin + "/api/qc/inspect")).ok) return;} catch {}
    await pause(200);
  }
  throw new Error("Fresh QC server did not become ready");
}
async function stop() {
  if (!server || server.exitCode != null) return;
  const child = server; child.kill("SIGTERM"); await Promise.race([new Promise(resolve => child.once("exit", resolve)), pause(3000)]);
  if (child.exitCode == null) child.kill("SIGKILL");
}
async function api(body, expected = 200) {
  const token = (await (await fetch(origin + "/api/qc/inspect")).json()).csrf_token;
  const response = await fetch(origin + (body ? "/api/qc/decision" : "/api/qc/inspect"), body ? {
    method: "POST", headers: {"Content-Type": "application/json", Origin: origin, "X-ScAgentKit-QC-Token": token}, body: JSON.stringify(body)
  } : {});
  const value = await response.json(); assert.equal(response.status, expected, JSON.stringify(value)); return value;
}
const ui = id => page.locator('[data-testid="' + id + '"]');
async function idle() {await ui("qc-refresh").waitFor(); await page.waitForFunction(() => !document.getElementById("qc-refresh").disabled);}
async function credentials() {await ui("qc-reviewer").fill("Browser acceptance analyst"); await ui("qc-reason").fill("Offline test of the exact reviewed public/synthetic QC scope");}
function payload(run, action) {return {action, expected_revision: run.revision, proposal_hash: run.pending.hash,
  preview_hash: run.qc_preview.hash, reviewer: "Browser acceptance analyst", reason: "Explicit offline browser state test"};}
async function refresh() {await ui("qc-refresh").click(); await idle();}
async function screenshot(name) {const file = path.join(output, name + ".png"); await page.screenshot({path: file, fullPage: true}); report.screenshots.push(file);}
try {
  await start(approveProject);
  browser = await chromium.launch({headless: true, executablePath: args.chrome || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"});
  const context = await browser.newContext({viewport: {width: 1440, height: 1000}});
  await context.route("**/*", route => {
    const url = route.request().url();
    if (url.startsWith(origin + "/")) return route.continue();
    report.externalRequests.push(url); return route.abort();
  });
  page = await context.newPage(); page.on("pageerror", error => report.pageErrors.push(error.message));
  await page.goto(origin + "/qc"); await idle();
  let initial;
  if (gatingOnly) {
    for (const kind of ["schema", "project-id"]) await test("UI gating: HTTP200 invalid " + kind + " blocks writes until verified refresh", async () => {
      const before = await snapshot(approveProject), verified = await api(); let intercepted = 0;
      const bad = structuredClone(verified);
      if (kind === "schema") bad.schema = "unverified-response";
      else bad.run.project_id = "foreign-project";
      await page.route("**/api/qc/decision", async route => {
        intercepted++; assert.equal(route.request().method(), "POST");
        await route.fulfill({status: 200, contentType: "application/json", body: JSON.stringify(bad)});
      });
      await credentials(); assert.equal(await ui("qc-approve").isEnabled(), true);
      await ui("qc-approve").click(); await idle();
      assert.equal(await page.evaluate(() => state.stale), true);
      assert.equal(await page.evaluate(() => state.view.run.project_id), verified.run.project_id);
      assert((await ui("qc-message").textContent()).includes(kind === "schema" ? "not a verified" : "project changed"));
      for (const action of ["approve", "reject", "revise", "preview"]) assert.equal(await ui("qc-" + action).isDisabled(), true);
      await page.evaluate(() => {for (const action of ["approve", "reject", "revise", "preview"]) document.getElementById("qc-" + action).click();});
      assert.equal(intercepted, 1, "Disabled controls must not send another POST");
      const failedRefresh = structuredClone(verified); failedRefresh.schema = "unverified-refresh";
      await page.route("**/api/qc/inspect", route => route.fulfill({status: 200, contentType: "application/json", body: JSON.stringify(failedRefresh)}));
      await refresh(); assert.equal(await page.evaluate(() => state.stale), true);
      for (const action of ["approve", "reject", "revise", "preview"]) assert.equal(await ui("qc-" + action).isDisabled(), true);
      await screenshot("gating-" + kind + "-failed-refresh");
      await page.unroute("**/api/qc/inspect"); await refresh();
      assert.equal(await page.evaluate(() => state.stale), false);
      for (const action of ["approve", "reject", "revise", "preview"]) assert.equal(await ui("qc-" + action).isEnabled(), true);
      await page.unroute("**/api/qc/decision");
      assert.deepEqual(await snapshot(approveProject), before, "UI reply injection must not change the server project");
      await screenshot("gating-" + kind + "-verified-refresh");
    });
  } else {
  await test("actual saved preview exact cell scope and measured quantile plot", async () => {
    initial = (await api()).run; assert.equal(initial.status, "awaiting_review"); assert.equal(initial.pending.kind, "qc");
    const d = initial.qc_preview.details; assert.equal(array(d.keep_cells).length + array(d.remove_cells).length, d.retention.before);
    const scope = await ui("qc-cell-scope").textContent(); for (const id of [...array(d.keep_cells), ...array(d.remove_cells)]) assert(scope.includes(id));
    assert.equal(await ui("qc-distributions").locator("svg").count(), 3);
    assert(!(await ui("qc-distributions").innerHTML()).includes("NaN"));
    assert((await ui("qc-unavailable").textContent()).includes("gene_panels"));
    assert.equal(await ui("qc-approve").isEnabled(), true);
    await screenshot("01-qc-preview");
  });
  await test("draft rules cannot be approved before rebuilding", async () => {
    const proposal = structuredClone(initial.qc_preview.details.canonical_parameters.proposal);
    proposal.rationale += " <img src=x onerror=alert(1)> literal reviewer text";
    await page.locator(".qc-edit > summary").click();
    await ui("qc-proposal").fill(JSON.stringify(proposal, null, 2));
    assert.equal(await ui("qc-approve").isDisabled(), true);
    assert.equal(await ui("qc-preview").isDisabled(), true);
    await credentials(); await ui("qc-revise").click(); await idle();
    assert.equal(await ui("qc-approve").isEnabled(), true);
    assert.equal(await ui("qc-rules").locator("img").count(), 0);
    assert((await ui("qc-rules").textContent()).includes("<img"));
    const revised = (await api()).run; assert.notEqual(revised.pending.hash, initial.pending.hash); assert.notEqual(revised.qc_preview.hash, initial.qc_preview.hash);
  });
  await test("explicit sensitivity and missing gene settings rebuild immutable preview", async () => {
    const current = (await api()).run, proposal = structuredClone(current.qc_preview.details.canonical_parameters.proposal);
    const first = proposal.filters.find(f => f.min != null); assert(first, "Fixture needs one lower-bound range for this typed comparison"); first.min = 0;
    proposal.rationale = "Explicit test control with zero lower bound; no biological recommendation";
    await ui("qc-alternatives").fill(JSON.stringify([{id: "explicit-low-bound-control", proposal}], null, 2));
    await ui("qc-panels").fill(JSON.stringify({"availability-only-control": ["SCAGENTKIT_UNAVAILABLE_TEST_GENE"]}, null, 2));
    assert.equal(await ui("qc-approve").isDisabled(), true); await ui("qc-preview").click(); await idle();
    const rebuilt = (await api()).run;
    assert.notEqual(rebuilt.pending.hash, current.pending.hash);
    assert.equal(rebuilt.qc_preview.details.sensitivity.length, 1);
    assert((await ui("qc-sensitivity").textContent()).includes("explicit-low-bound-control"));
    assert((await ui("qc-unavailable").textContent()).includes("SCAGENTKIT_UNAVAILABLE_TEST_GENE"));
    assert.equal(rebuilt.qc_preview.details.unavailable.gene_panels[0].expression_assessed, false);
    await screenshot("02-qc-sensitivity");
  });
  await test("unsupported operation fails without altering the saved project", async () => {
    const before = await snapshot(approveProject), run = (await api()).run;
    const body = payload(run, "revise"); body.proposal = structuredClone(run.qc_preview.details.canonical_parameters.proposal); body.proposal.filters[0].op = "eval";
    await api(body, 409); assert.deepEqual(await snapshot(approveProject), before);
  });
  await test("two browser tabs reject a stale approval", async () => {
    const stale = (await api()).run;
    const second = await context.newPage(); await second.goto(origin + "/qc");
    await second.waitForFunction(() => !document.getElementById("qc-refresh").disabled);
    const proposal = structuredClone(stale.qc_preview.details.canonical_parameters.proposal); proposal.rationale += " Second tab reviewed rationale.";
    await second.locator(".qc-edit > summary").click();
    await second.locator("#qc-reviewer").fill("Second analyst"); await second.locator("#qc-reason").fill("Revise one audited proposal before first-tab approval");
    await second.locator("#qc-proposal").fill(JSON.stringify(proposal)); await second.locator("#qc-revise").click();
    await second.waitForFunction(() => !document.getElementById("qc-refresh").disabled);
    const before = await snapshot(approveProject); await ui("qc-approve").click(); await idle();
    assert((await ui("qc-message").textContent()).includes("Stale")); assert.equal(await ui("qc-approve").isDisabled(), true);
    assert.deepEqual(await snapshot(approveProject), before); await second.close(); await refresh();
  });
  let approvedPayload;
  await test("same reviewed QC approval saved once without executing analysis", async () => {
    const run = (await api()).run; approvedPayload = payload(run, "approve");
    await ui("qc-approve").click(); await idle();
    const approved = (await api()).run; assert.equal(approved.status, "ready"); assert.equal(approved.stage, "qc_apply"); assert.equal(approved.pending, null);
    assert.equal(await ui("qc-approve").isDisabled(), true); assert((await ui("qc-next").textContent()).includes("sc_run_resume"));
    const before = await snapshot(approveProject); const repeated = await api(approvedPayload); assert.equal(repeated.run.status, "ready"); assert.deepEqual(await snapshot(approveProject), before);
    await screenshot("03-qc-approved-paused");
  });
  await test("fresh server and browser restore the saved approved boundary", async () => {
    await stop(); await start(approveProject); await page.goto(origin + "/qc"); await idle();
    assert.equal((await api()).run.status, "ready"); assert.equal(await ui("qc-approve").isDisabled(), true);
  });
  await test("separate exact-scope rejection remains headless-recoverable and unexecuted", async () => {
    await stop(); await start(rejectProject); await page.goto(origin + "/qc"); await idle(); await credentials();
    const before = (await api()).run; await ui("qc-reject").click(); await idle();
    const rejected = (await api()).run; assert.equal(rejected.status, "rejected"); assert.equal(rejected.stage, "qc_propose");
    assert.equal(rejected.input_hash, before.input_hash); assert.equal(await ui("qc-approve").isDisabled(), true);
  });
  }
  await test("input checkpoint/source fixture preserved and browser made no external requests", async () => {
    assert.deepEqual(await snapshot(source), protectedBefore);
    for (const project of [approveProject, rejectProject]) {
      const after = await snapshot(project);
      for (const [name, digest] of Object.entries(protectedBefore)) if (name.startsWith("checkpoints/input-")) assert.equal(after[name], digest);
    }
    assert.deepEqual(report.externalRequests, []); assert.deepEqual(report.pageErrors, []);
    report.sourceFixturePreserved = true; report.inputCheckpointsPreserved = true;
  });
  report.outcome = "passed";
} catch(error) {
  report.outcome = "failed"; report.error = error.stack; console.error(error.stack);
  if (page) await screenshot("failure").catch(() => {}); process.exitCode = 1;
} finally {
  await browser?.close(); await stop(); report.finishedAt = new Date().toISOString();
  report.sourceFixtureAfter = await snapshot(source); report.sourceFixtureBefore = protectedBefore;
  await fs.writeFile(reportFile, JSON.stringify(report, null, 2) + "\n");
}
