#!/usr/bin/env node
// Real installed Chrome + actual production HTML/CSS/JS, controlled synthetic API.
// This verifies browser behavior only: no server, R bridge, scientific execution or provider.
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import crypto from "node:crypto";
import {createRequire} from "node:module";
import {fileURLToPath} from "node:url";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const output = path.resolve(process.argv[2] || path.join(root, "../evidence/browser-final-review-controls.json"));
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.SCAGENTKIT_PLAYWRIGHT || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
const read = name => fs.readFile(path.join(root, name), "utf8");
const strategyTest = await read("workbench/tests/strategy_review_dom.cjs"), annotationTest = await read("workbench/tests/test_review_response.mjs");
// Reuse pure synthetic fixture constructors from offline tests; no production function is patched.
const strategyFixtures = vm.createContext({});
vm.runInContext(strategyTest.slice(strategyTest.indexOf('const inputHash ='), strategyTest.indexOf('function setup(')) + strategyTest.slice(strategyTest.indexOf('function harmonyAnswer('), strategyTest.indexOf('async function main(')), strategyFixtures);
const annotationFixtures = vm.createContext({});
vm.runInContext(annotationTest.slice(annotationTest.indexOf('const clone ='), annotationTest.indexOf('class InertNode')), annotationFixtures);
const clone = v => JSON.parse(JSON.stringify(v));
const harmony = clone(vm.runInContext('harmonyAnswer()', strategyFixtures)), annotation = clone(vm.runInContext('view()', annotationFixtures));
annotation.run.annotation_review.details.annotations[0].joint_evidence = {schema: "scagentkit.joint-annotation-evidence.v1", clusterId: "literal:A", database: {status: "ok", candidates: [{label: "Singleton", score: 1, overlap: 1, referenceSize: 1}, {label: "Broad", score: .5, overlap: 10, referenceSize: 20}]}};
const assets = new Map();
for (const file of ["review.html", "review.js", "review.css", "qc.css", "styles.css", "ortholog-map.js", "gene-links.js"]) assets.set('/' + file, await read('workbench/static/' + file));
const report = {schema: "scagentkit.final-review-controls.browser.v1", actualChrome: true, productionHTMLAndJavaScript: true, controlledStubAPI: true, actualRBridge: false, scientificAnalysisRun: false, paidCalls: 0, externalRequests: [], requests: [], pageErrors: [], tests: [], sourceSHA256: Object.fromEntries([...assets].map(([name, source]) => [name, crypto.createHash("sha256").update(source).digest("hex")])), screenshots: []};
const browser = await chromium.launch({executablePath: process.env.SCAGENTKIT_CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: true});
try {
  const context = await browser.newContext({viewport: {width: 1440, height: 1100}});
  let active, posts = [];
  await context.route("**/*", async route => {
    const request = route.request(), url = new URL(request.url());
    if (url.origin !== 'http://127.0.0.1:19999') {report.externalRequests.push(url.origin + url.pathname); return route.abort();}
    const pathname = url.pathname;
    if (pathname.startsWith('/api/')) {
      report.requests.push({pathname, method: request.method()});
      if (pathname === '/api/run-review/scopes') return route.fulfill({json: {schema: "scagentkit.run-scopes.workbench.v1", workspace_enabled: false, parent: {project_id: active.run.project_id, input_hash: active.run.input_hash, revision: active.run.revision, ready: false, frozen: false, status: active.run.status}, children: []}});
      if (pathname === '/api/run-review/inspect') return route.fulfill({json: active});
      if (pathname === '/api/run-review/decision' && request.method() === 'POST') {
        const body = request.postDataJSON(); posts.push(body);
        assert.equal(body.action, 'revise'); assert.equal(body.kind, 'strategy'); assert.equal(body.project_id, active.run.project_id); assert.equal(body.expected_revision, active.run.revision);
        active = clone(active); active.run.revision++;
        active.run.review_node.expected_revision = active.run.revision;
        const hash = crypto.createHash('sha256').update(JSON.stringify(body)).digest('hex');
        active.run.review_node.review_hash = hash; active.run.review_node.proposal_hash = hash;
        active.run.strategy_review.hash = hash; active.run.strategy_review.details.canonical_proposal = body.proposal;
        return route.fulfill({json: active});
      }
      return route.fulfill({status: 500, json: {error: 'Unexpected stub endpoint: ' + pathname}});
    }
    const source = assets.get(pathname === '/review' ? '/review.html' : pathname);
    if (source != null) return route.fulfill({body: source, contentType: pathname === '/review' ? 'text/html' : pathname.endsWith('.js') ? 'application/javascript' : 'text/css'});
    if (pathname === '/favicon.ico') return route.fulfill({status: 204});
    return route.fulfill({status: 404, body: 'Not in controlled fixture'});
  });
  const open = async fixture => {
    active = clone(fixture); const page = await context.newPage();
    page.on('pageerror', error => report.pageErrors.push(error.message));
    await page.goto('http://127.0.0.1:19999/review?project_id=' + encodeURIComponent(active.run.project_id));
    await page.waitForFunction(() => !document.getElementById('run-refresh').disabled && document.getElementById('run-status').textContent.includes('awaiting_review'));
    assert.equal(await page.locator('#run-message').isVisible(), false, await page.locator('#run-message').textContent());
    return page;
  };
  const reveal = async locator => {
    for (const detail of await locator.locator('xpath=ancestor::details').all()) if (!await detail.evaluate(el => el.open)) await detail.locator(':scope > summary').click();
  };
  let page = await open(annotation);
  const candidates = page.locator('#annotation-joint-candidates');
  assert.deepEqual(await candidates.locator('th').allTextContents(), ['Candidate', 'Coverage', 'Unique hits / reference genes']);
  assert.deepEqual(await candidates.locator('tbody tr').allTextContents(), ['Singleton · single-marker evidence (weak)11 / 1', 'Broad0.510 / 20']);
  assert.match(await page.locator('#annotation-joint-database').textContent(), /Candidate order does not establish a cell identity/);
  assert.match(await page.locator('#annotation-joint-database').textContent(), /A single matching marker is weak evidence, even at 100% coverage/);
  await page.locator('#annotation-all-markers').click(); assert.equal(await page.locator('#annotation-markers tbody tr').count(), 2);
  await page.locator('#annotation-cited-markers').click(); assert.equal(await page.locator('#annotation-markers tbody tr').count(), 1);
  assert.equal(posts.length, 0); report.tests.push({name: 'marker-candidate-hits-reference-coverage-and-weak-evidence', passed: true}, {name: 'marker-all-cited-buttons-only-change-local-evidence-view', passed: true});
  const markerShot = output.replace(/\.json$/, '-markers.png'); await page.screenshot({path: markerShot, fullPage: true}); report.screenshots.push(markerShot); await page.close();
  page = await open(harmony);
  const policy = page.locator('#harmony-nested-biology'); await reveal(policy);
  assert.equal(await policy.inputValue(), 'block');
  assert.deepEqual(await policy.locator('option').evaluateAll(options => options.map(o => o.value)), ['block', 'reviewed_embedding_only']);
  let draft = JSON.parse(await page.locator('#strategy-json').inputValue()); assert.equal(Object.hasOwn(draft.batch, 'nested_biology'), false);
  await page.locator('#harmony-reason').fill('Reviewed synthetic donor design; embedding exploration only.');
  draft = JSON.parse(await page.locator('#strategy-json').inputValue()); assert.equal(Object.hasOwn(draft.batch, 'nested_biology'), false); assert.equal(posts.length, 0);
  await policy.selectOption('reviewed_embedding_only'); draft = JSON.parse(await page.locator('#strategy-json').inputValue()); assert.equal(draft.batch.nested_biology, 'reviewed_embedding_only');
  assert.equal(await page.locator('#strategy-approve').isDisabled(), true); assert.equal(posts.length, 0);
  assert.match(await page.locator('#harmony-nested-note').textContent(), /at least two independent donor\/sample IDs per biological level/);
  assert.match(await page.locator('#harmony-nested-note').textContent(), /must not be used for condition-effect inference/);
  await page.locator('#strategy-reviewer').fill('Synthetic browser acceptance'); await page.locator('#strategy-reason').fill('Explicit nested design choice for transport and UI acceptance only.');
  await page.locator('#strategy-save').click(); await page.waitForFunction(() => document.getElementById('run-message').textContent.includes('Strategy revision'));
  assert.equal(posts.length, 1); assert.equal(posts[0].proposal.batch.nested_biology, 'reviewed_embedding_only'); assert.equal(await page.locator('#harmony-nested-biology').inputValue(), 'reviewed_embedding_only');
  report.tests.push({name: 'harmony-default-block-legacy-omission-retained', passed: true}, {name: 'explicit-embedding-policy-edits-draft-without-auto-execution', passed: true}, {name: 'save-submits-exact-explicit-policy-to-controlled-api', passed: true});
  await reveal(page.locator('#harmony-nested-biology'));
  const harmonyShot = output.replace(/\.json$/, '-harmony.png'); await page.screenshot({path: harmonyShot, fullPage: true}); report.screenshots.push(harmonyShot);
  await page.locator('#harmony-method').selectOption('none'); draft = JSON.parse(await page.locator('#strategy-json').inputValue()); assert.equal(Object.hasOwn(draft.batch, 'nested_biology'), false); assert.equal(await page.locator('#harmony-parameters').isHidden(), true); assert.equal(posts.length, 1);
  report.tests.push({name: 'switch-to-none-removes-harmony-only-policy-from-draft', passed: true});
  await page.close(); await context.close();
  assert.deepEqual(report.pageErrors, []); assert.deepEqual(report.externalRequests, []);
  report.stubDecisionPayloads = posts; report.passed = report.tests.length; report.failed = 0;
} catch (error) {report.failed = 1; report.error = error.stack; throw error;}
finally {await browser.close(); await fs.writeFile(output, JSON.stringify(report, null, 2) + '\n'); console.log(JSON.stringify(report, null, 2));}
