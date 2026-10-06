#!/usr/bin/env node
/** Phase 3 only: real cached calls + local expression extraction, isolated session.
 * Run after integration stabilizes. No providers, uploads, or live session access.
 * node workbench/tests/browser_directed.mjs --results-root /path/to/results
 *   --directed-source /path/to/retained-seurat.rds --r-library /path/to/R/library
 * Optional --output /fresh/local/dir --chrome /path/to/chrome --playwright /path/to/playwright
 */
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import {spawn} from 'node:child_process';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = {};
for (let i = 2; i < process.argv.length; i += 2) {
  assert(process.argv[i]?.startsWith('--') && process.argv[i + 1], 'Use --name value argument pairs');
  args[process.argv[i].slice(2)] = process.argv[i + 1];
}
assert(args['results-root'] && args['directed-source'] && args['r-library'],
  '--results-root, --directed-source and --r-library are required');
const output = path.resolve(args.output || await fs.mkdtemp(path.join(os.tmpdir(), 'scagentkit-directed-browser-')));
await fs.mkdir(output, {recursive: true});
const sessionFile = path.join(output, 'review-session.json');
assert.equal(await fs.access(sessionFile).then(() => true, () => false), false, 'Use a fresh output directory; never overwrite review history');
const copiedRDS = path.join(output, 'source-seurat.rds');
await fs.copyFile(path.resolve(args['directed-source']), copiedRDS);
const cacheDir = path.join(output, 'directed-cache');
const {chromium} = require(args.playwright || process.env.PLAYWRIGHT_MODULE_PATH ||
  '/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright');
const report = {startedAt: new Date().toISOString(), output, tests: [], screenshots: [], pageErrors: [], externalRequests: []};
let server, browser, page, origin, evidence;
const logs = [];
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const ui = id => page.locator(`[data-testid="${id}"]`);

async function test(name, fn) {
  const start = Date.now();
  try { await fn(); report.tests.push({name, outcome: 'passed', milliseconds: Date.now() - start}); console.log(`PASS ${name}`); }
  catch (error) { report.tests.push({name, outcome: 'failed', error: error.message}); throw error; }
}
async function freePort() {
  const listener = net.createServer();
  await new Promise((resolve, reject) => {listener.once('error', reject); listener.listen(0, '127.0.0.1', resolve);});
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  return port;
}
async function start() {
  const port = await freePort(); origin = `http://127.0.0.1:${port}`;
  const extra = args.rscript ? ['--rscript', args.rscript] : [];
  server = spawn(args.python || 'python3', [path.join(root, 'server.py'),
    '--results-root', path.resolve(args['results-root']), '--session', sessionFile,
    '--port', String(port), '--directed-source', copiedRDS, '--directed-cache', cacheDir,
    '--r-library', path.resolve(args['r-library']), ...extra], {cwd: path.dirname(root), stdio: ['ignore', 'pipe', 'pipe']});
  server.stdout.on('data', chunk => logs.push(chunk.toString()));
  server.stderr.on('data', chunk => logs.push(chunk.toString()));
  for (let i = 0; i < 180; i++) {
    if (server.exitCode !== null) throw new Error(`Server exited: ${logs.join('')}`);
    try {const response = await fetch(`${origin}/api/evidence`); if (response.ok) return response.json();}
    catch {}
    await pause(100);
  }
  throw new Error('Isolated directed server did not become ready');
}
async function api(route, body, status = 200) {
  const response = await fetch(origin + route, body === undefined ? {} : {
    method: 'POST', headers: {'Content-Type': 'application/json', Origin: origin}, body: JSON.stringify(body)
  });
  assert.equal(response.status, status, `${route}: ${await response.clone().text()}`);
  return response.json();
}
const session = () => api('/api/session');
const directed = () => api('/api/directed?clusterId=6');
const originalEvent = ({stale, undone, ...event}) => event;
async function screenshot(name) { const filename = path.join(output, `${name}.png`); await page.screenshot({path: filename, fullPage: true}); report.screenshots.push(filename); }
async function awaitIdle() { await ui('directed-execute').waitFor({state: 'visible'}); await page.waitForFunction(() => !document.querySelector('[data-testid="directed-execute"]')?.disabled, null, {timeout: 120000}); }
async function awaitEvents(count) {
  for (let i = 0; i < 100; i++) {const current = await session(); if (current.events.length === count) return current; await pause(75);}
  assert.equal((await session()).events.length, count);
}
function assertHumanScope(event) {
  assert.equal(event.scope.clusterId, '6'); assert.equal(event.scope.dimension, 'type');
  assert.equal(event.scope.revision, evidence.revision);
  assert.deepEqual(event.scope.cellIds, evidence.clusters.find(item => item.id === '6').cellIds);
  assert.equal(event.scope.cellIds.length, 155);
}

try {
  evidence = await start(); report.coreRevision = evidence.revision;
  assert.equal(evidence.umap.length, 2638); assert.equal(evidence.clusters.length, 9);
  browser = await chromium.launch({headless: true, executablePath: args.chrome || process.env.CHROME_EXECUTABLE ||
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', args: [
      '--disable-background-networking', '--disable-component-update', '--disable-sync', '--no-pings'
    ]});
  report.browser = await browser.version();
  const context = await browser.newContext({viewport: {width: 1440, height: 1060}, acceptDownloads: true});
  await context.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (url.origin === origin || ['data:', 'blob:'].includes(url.protocol)) return route.continue();
    report.externalRequests.push(url.href); return route.abort('blockedbyclient');
  });
  page = await context.newPage(); page.on('pageerror', error => report.pageErrors.push(error.message));
  await page.goto(origin, {waitUntil: 'networkidle'});
  await ui('evidence-directed').click();

  await test('Directed triage covers all nine clusters without creating human decisions', async () => {
    await ui('directed-triage').waitFor({state: 'visible'});
    const value = await directed();
    const rows = Array.isArray(value.triage) ? value.triage : value.triage?.clusters;
    assert.equal(rows.length, 9);
    assert.deepEqual(rows.map(row => String(row.clusterId ?? row.id)).sort(), ['0','1','2','3','4','5','6','7','8']);
    assert.equal((await session()).decisions.length, 0);
    report.triage = rows;
    await screenshot('01-directed-plan');
  });

  await test('Real triage separates synonyms, state, granularity, failures and CD8/NK identity conflict', async () => {
    const rows = (await directed()).triage.clusters;
    const row = id => rows.find(item => item.clusterId === String(id));
    assert(row(0).classifications.includes('explicit_synonym'));
    assert(row(1).classifications.includes('granularity_difference'));
    assert(row(2).classifications.includes('format_failure'));
    assert.equal(row(2).strictLabels.length, 2);
    assert(row(3).classifications.includes('identity_vs_state'));
    assert(row(4).classifications.includes('execution_failure'));
    assert(row(5).classifications.includes('granularity_difference'));
    assert(row(6).classifications.includes('lineage_conflict'));
    assert(row(7).classifications.includes('granularity_difference'));
    assert(row(8).classifications.includes('lineage_conflict'));
    const terminal = row(6).strictLabels.find(item => item.label === 'Terminal effector CD8+ T cell');
    assert.equal(terminal.descriptor.known, true);
    assert.equal(terminal.descriptor.lineage, 'T');
    assert(terminal.descriptor.states.includes('terminal_effector'));
    assert.equal(evidence.clusters.find(item => item.id === '6').models.find(item => item.callId === terminal.callId).strict.broadLabel, 'unknown',
      'Directed vocabulary cannot overwrite the legacy dictionary result');
  });

  await test('Local directed execution produces evidence and a provisional proposal, preserving source calls', async () => {
    await ui('label').fill('unknown');
    await ui('reason').fill('Accepted human uncertainty before new local measurements; the automatic proposal cannot replace this decision.');
    await ui('review-status').selectOption('accepted');
    await ui('save-decision').click();
    await awaitEvents(1);
    const before = await session();
    const sourceModels = structuredClone(evidence.clusters.find(item => item.id === '6').models);
    await ui('directed-execute').click(); await awaitIdle();
    await ui('directed-evidence').waitFor({state: 'visible'});
    const value = await directed();
    assert(value.expression && value.proposal && value.evidenceFingerprint);
    assert.deepEqual((await session()).decisions, before.decisions);
    assert.equal((await session()).decisions[0].label, 'unknown');
    assert.equal((await session()).decisions[0].status, 'accepted');
    assert.deepEqual((await api('/api/evidence')).clusters.find(item => item.id === '6').models, sourceModels);
    assert.match(await ui('directed-proposal').textContent(), /provisional|unresolved|hypothesis|heuristic/i);
    assert.match(await ui('directed-stop-reason').textContent(), /stop|cached|evidence|round|budget/i);
    report.evidenceFingerprint = value.evidenceFingerprint;
    report.execution = value.execution;
    report.modelReview = value.modelReview;
    assert.equal(value.modelReview.enabled, false);
    assert.equal(value.modelReview.calls, 0);
    assert.equal(value.modelReview.incrementalCostUSD, 0);
    await screenshot('02-directed-expression');
  });

  await test('Actual expression preserves missing statistics, per-cell coexpression, measured controls and coverage', async () => {
    const value = await directed(); const expression = value.expression;
    assert.equal(expression.scope.cluster_id, '6'); assert.equal(expression.scope.n_cells, 155);
    assert.deepEqual(expression.scope.cell_ids, evidence.clusters.find(item => item.id === '6').cellIds);
    assert.equal(expression.cells.length, 155);
    assert.deepEqual(expression.cells.map(item => item.cell_id).sort(), expression.scope.cell_ids);
    assert.equal(expression.source.assay, 'RNA');
    assert.deepEqual(expression.source.layers, {counts: 'counts', data: 'data'});
    const trac = expression.panel.find(item => item.gene === 'TRAC');
    assert(trac, 'Requested TRAC must have an explicit record');
    if (trac.measurement_status === 'missing') {
      assert.equal(trac.detected_n, null); assert.equal(trac.detected_fraction, null); assert.equal(trac.raw_counts, null);
      assert.match(await ui('directed-evidence').textContent(), /TRAC/);
      assert.match(await ui('directed-evidence').textContent(), /missing|not measured/i);
    }
    const zeros = expression.panel.filter(item => item.measurement_status === 'measured' && item.detected_n === 0);
    for (const gene of zeros) {
      assert.equal(gene.detected_fraction, 0); assert(gene.raw_counts);
      const row = ui('directed-evidence').locator(`[data-gene="${gene.gene}"]`);
      assert.match(await row.textContent(), /Measured RNA/);
      assert.match(await row.textContent(), /0\s*\/\s*155/);
    }
    report.measuredZeroGenes = zeros.map(item => item.gene);
    report.measuredZeroObservation = zeros.length ? 'Directly observed in this real panel' : 'No measured-zero gene in this real panel; synthetic domain/extraction tests cover zero versus missing';
    assert.equal(Object.values(expression.coexpression.counts).reduce((sum, count) => sum + count, 0), 155);
    assert.equal(expression.coexpression.n_cells, 155);
    assert.match(expression.coexpression.interpretation, /not.*NKT|does not.*NKT/i);
    assert.equal(expression.comparisons.all_rest.n_cells, 2483);
    assert(expression.comparisons.candidate_lymphocyte.n_cells > 0);
    assert(expression.identity_threshold_sensitivity.length >= 3);
    assert(expression.qc.sensitivity.length >= 3);
    assert(value.proposal.sensitivity.length >= 3);
    assert.equal(value.proposal.uncalibrated, true);
    assert.equal(value.proposal.granularity, 'broad_program_only');
    assert.equal(value.proposal.recommendedLabel, 'unknown');
    assert.equal(value.proposal.resolution, 'unresolved_identity');
    assert.match(await ui('directed-evidence').textContent(), /coverage|missing|measured/i);
    assert.match(await ui('directed-evidence').textContent(), /control|contrast/i);
    assert.match(await ui('directed-evidence').textContent(), /sensitivity|threshold/i);
    for (const contrast of value.proposal.comparisonReview || []) {
      const missingKeys = ['targetDetectedFraction', 'allRestDelta', 'candidateDelta'].map((key, index) => contrast[key] === null ? index + 1 : null).filter(index => index !== null);
      if (!missingKeys.length) continue;
      const row = ui('directed-evidence').locator('table').last().locator('tbody tr').filter({has: page.getByText(contrast.gene, {exact: true})});
      const values = await row.locator('td').allTextContents();
      for (const index of missingKeys) assert.equal(values[index], '—', 'A missing contrast cannot display a fabricated numerical zero');
    }
  });

  await test('Proposal adoption only fills a reasoned draft; accepted human decision records exact155-cell scope', async () => {
    const before = await session();
    await ui('directed-adopt').click();
    assert.equal((await session()).events.length, before.events.length);
    assert.equal(await ui('dimension').inputValue(), 'type');
    assert.equal(await ui('review-status').inputValue(), 'proposed');
    assert.equal(await ui('label').inputValue(), 'unknown', 'RNA program compatibility cannot become a formal cell-type draft');
    await ui('reason').fill('Human review accepts only this scoped provisional label, with the displayed coverage and biological limits.');
    await ui('review-status').selectOption('accepted');
    await ui('save-decision').click();
    const current = await awaitEvents(before.events.length + 1);
    assertHumanScope(current.events.at(-1));
    assert.equal(current.events.at(-1).status, 'accepted');
    assert(current.events.at(-1).evidenceRefs?.length, 'Adoption must bind the directed proposal evidence reference');
  });

  await test('Repeated unchanged evidence stops or reuses cached output and never overwrites accepted human review', async () => {
    const before = await session(); const first = await directed();
    await ui('directed-execute').click(); await awaitIdle();
    const repeated = await directed();
    assert.deepEqual(repeated.evidenceFingerprint, first.evidenceFingerprint);
    assert.deepEqual((await session()).events.map(originalEvent), before.events.map(originalEvent));
    assert.deepEqual((await session()).decisions, before.decisions);
    assert.equal(repeated.execution.status, 'cached');
    assert.match(repeated.execution.stopReason, /no new|same evidence|cache|stop/i);
    assert.equal(repeated.modelReview.calls, 0);
    assert.equal(repeated.modelReview.incrementalCostUSD, 0);
  });

  await test('Changed expression source bytes stale proposal references without changing accepted labels or raw history', async () => {
    const before = await session(); const prior = await directed();
    const size = (await fs.stat(copiedRDS)).size;
    const adopted = before.decisions.find(item => item.evidenceRefs?.length);
    assert(adopted);
    try {
      await fs.appendFile(copiedRDS, '\n');
      const changed = await directed();
      assert.notEqual(changed.evidenceFingerprint.sourceHash, prior.evidenceFingerprint.sourceHash);
      assert.equal(changed.expression, null, 'An old expression bundle cannot be reused under a changed source hash');
      const stale = await session();
      assert.deepEqual(stale.events.map(originalEvent), before.events.map(originalEvent));
      const retained = stale.decisions.find(item => item.id === adopted.id);
      assert.equal(retained.label, adopted.label); assert.equal(retained.status, 'accepted'); assert.equal(retained.stale, true);
      await api('/api/decision', {clusterId: '6', dimension: 'type', label: adopted.label, reason: 'Stale directed reference must be rejected before saving.',
        status: 'proposed', revision: evidence.revision, requestId: 'qa-stale-directed-reference', evidenceRefs: adopted.evidenceRefs}, 409);
      assert.deepEqual((await session()).events.map(originalEvent), before.events.map(originalEvent));
      await ui('refresh-evidence').click();
      await page.waitForFunction(() => /stale/i.test(document.body.textContent));
      await screenshot('03-directed-source-stale');
    } finally { await fs.truncate(copiedRDS, size); }
    await ui('refresh-evidence').click();
    assert.equal((await directed()).artifact.id, prior.artifact.id, 'Restoring exact source bytes restores the existing verified artifact');
    assert.equal((await session()).decisions.find(item => item.id === adopted.id).stale, false);
  });

  await test('Directed undo is append-only; actual UI download and portable JSON replay restore identical history', async () => {
    const before = await session(); const packageBefore = await api('/api/export');
    const target = before.events.at(-1);
    await ui('evidence-history').click(); await ui(`undo-${target.id}`).click();
    await page.locator('#undo-reason').fill('Undo the human adoption while keeping proposal provenance and audit history.');
    await page.locator('#confirm-undo').click();
    const current = await awaitEvents(before.events.length + 1);
    assert.deepEqual((await api('/api/export')).events.slice(0, -1), packageBefore.events);
    assert.equal(current.events.at(-1).targetEventId, target.id);
    const packageValue = await api('/api/export');
    const filename = path.join(output, 'directed-handoff.json');
    const downloadPending = page.waitForEvent('download');
    await ui('export-session').click();
    await (await downloadPending).saveAs(filename);
    assert.deepEqual(JSON.parse(await fs.readFile(filename, 'utf8')), packageValue, 'The actual UI download must contain the complete replay package');
    await ui('import-file').setInputFiles(filename);
    await page.waitForFunction(() => /restored|integrity checked/i.test(document.querySelector('[data-testid="notice"]')?.textContent || ''));
    assert.deepEqual(await api('/api/export'), packageValue);
    assert.deepEqual(await session(), current);
    await api('/api/import', packageValue);
    assert.deepEqual(await api('/api/export'), packageValue, 'A JS-parsed and JSON.stringify-encoded import must preserve the scientific capsule');
    assert.deepEqual(await session(), current);
    await page.reload({waitUntil: 'networkidle'});
    assert.deepEqual(await session(), current);
    await ui('evidence-history').click();
    await screenshot('04-directed-adoption-history');
  });

  await test('Directed panel fits a narrow viewport with no provider replay, remote request or page errors', async () => {
    await page.setViewportSize({width: 390, height: 844});
    await ui('evidence-directed').click();
    await ui('directed-evidence').waitFor({state: 'visible'});
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'Directed evidence must not widen the document beyond the viewport');
    await ui('directed-proposal').scrollIntoViewIfNeeded();
    const filename = path.join(output, '05-directed-narrow-viewport.png');
    await page.screenshot({path: filename}); report.screenshots.push(filename);
    assert.deepEqual(report.externalRequests, []); assert.deepEqual(report.pageErrors, []);
  });
  report.outcome = 'passed';
} catch (error) {
  report.outcome = 'failed'; report.error = error.stack || error.message; process.exitCode = 1;
  if (page) await screenshot('failure').catch(() => {});
  console.error(error.stack || error.message);
} finally {
  if (browser) await browser.close().catch(() => {});
  if (server && server.exitCode === null) {const current = server; current.kill('SIGTERM'); await Promise.race([new Promise(resolve => current.once('exit', resolve)), pause(3000)]); if (current.exitCode === null) current.kill('SIGKILL');}
  report.finishedAt = new Date().toISOString();
  await fs.writeFile(path.join(output, 'directed-browser-report.json'), JSON.stringify(report, null, 2));
  await fs.writeFile(path.join(output, 'server.log'), logs.join(''));
  console.log(`Directed QA artifacts: ${output}`);
}
