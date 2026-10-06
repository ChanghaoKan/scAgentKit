#!/usr/bin/env node
/**
 * Real-browser acceptance test. Uses a fresh local session and browser profile.
 * No fixture/result files are committed and no external requests are allowed.
 *
 * Usage (Node + Playwright + Chrome must already be available):
 *   node workbench/tests/browser_smoke.mjs --results-root /path/to/phase1/results
 * Optional: --output /tmp/workbench-browser-qa --playwright /path/to/playwright
 *           --chrome /path/to/chrome --python /path/to/python3
 */
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import {spawn} from 'node:child_process';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const require = createRequire(import.meta.url);
const options = {};
for (let i = 2; i < process.argv.length; i += 2) {
  assert(process.argv[i]?.startsWith('--') && process.argv[i + 1], 'Arguments must be --name value pairs');
  options[process.argv[i].slice(2)] = process.argv[i + 1];
}
assert(options['results-root'], '--results-root is required (never infer/read a credentials file)');
const resultsRoot = path.resolve(options['results-root']);
const output = path.resolve(options.output || await fs.mkdtemp(path.join(os.tmpdir(), 'scagentkit-browser-')));
await fs.mkdir(output, {recursive: true});
const playwrightPath = options.playwright || process.env.PLAYWRIGHT_MODULE_PATH ||
  '/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright';
const {chromium} = require(playwrightPath);
const chrome = options.chrome || process.env.CHROME_EXECUTABLE ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const python = options.python || process.env.PYTHON || 'python3';
const report = {startedAt: new Date().toISOString(), resultsRoot, output, tests: [], screenshots: [], externalRequests: []};
let server, browser, page, baseUrl, evidence;
let fixtureRoot;
const pageErrors = [];
const serverLogs = [];

const selector = id => `[data-testid="${id}"]`;
const ui = id => page.locator(selector(id));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const test = async (name, fn) => {
  const start = Date.now();
  try {
    await fn();
    report.tests.push({name, outcome: 'passed', milliseconds: Date.now() - start});
    console.log(`PASS ${name}`);
  } catch (error) {
    report.tests.push({name, outcome: 'failed', milliseconds: Date.now() - start, error: error.message});
    throw error;
  }
};
async function freePort() {
  const listener = net.createServer();
  await new Promise((resolve, reject) => {listener.once('error', reject); listener.listen(0, '127.0.0.1', resolve);});
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  return port;
}
async function startServer(fixtureRoot, sessionFile) {
  const port = await freePort();
  baseUrl = `http://127.0.0.1:${port}`;
  server = spawn(python, [path.join(root, 'server.py'), '--results-root', fixtureRoot, '--session', sessionFile,
    '--port', String(port)], {cwd: path.dirname(root), stdio: ['ignore', 'pipe', 'pipe']});
  server.stdout.on('data', chunk => serverLogs.push(chunk.toString()));
  server.stderr.on('data', chunk => serverLogs.push(chunk.toString()));
  for (let i = 0; i < 150; i++) {
    if (server.exitCode !== null) throw new Error(`Local server exited: ${serverLogs.join('')}`);
    try {
      const response = await fetch(`${baseUrl}/api/evidence`);
      if (response.ok) return response.json();
      throw new Error(`Evidence load ${response.status}: ${await response.text()}`);
    } catch (error) {
      if (i === 149) throw error;
      await sleep(100);
    }
  }
}
async function stopServer() {
  if (!server || server.exitCode !== null) return;
  const current = server;
  server = null;
  current.kill('SIGTERM');
  await Promise.race([new Promise(resolve => current.once('exit', resolve)), sleep(3000)]);
  if (current.exitCode === null) current.kill('SIGKILL');
}
async function api(route, body, expectedStatus = 200) {
  const response = await fetch(`${baseUrl}${route}`, body === undefined ? {} : {
    method: 'POST', headers: {'Content-Type': 'application/json', 'Origin': baseUrl}, body: JSON.stringify(body)
  });
  assert.equal(response.status, expectedStatus, `${route}: ${await response.clone().text()}`);
  return response.json();
}
async function session() { return api('/api/session'); }
async function waitEvents(count) {
  for (let i = 0; i < 80; i++) {
    const result = await session();
    if (result.events.length === count) return result;
    await sleep(75);
  }
  assert.equal((await session()).events.length, count, 'Expected durable event count');
}
async function screenshot(name) {
  const target = path.join(output, `${name}.png`);
  await page.screenshot({path: target, fullPage: true});
  report.screenshots.push(target);
}
async function selectCluster(id) {
  await ui(`cluster-${id}`).click();
  await page.waitForFunction(id => document.querySelector('[data-testid="scope-summary"]')?.textContent.toLowerCase().includes(`cluster ${id}`), String(id));
}
async function copyExactSources() {
  fixtureRoot = path.join(output, 'evidence-fixture');
  for (const source of evidence.sources) {
    assert(typeof source.id === 'string' && !path.isAbsolute(source.id) && !source.id.split(/[\\/]/).includes('..'), 'Source allowlist identity must be safe');
    const target = path.join(fixtureRoot, source.id);
    await fs.mkdir(path.dirname(target), {recursive: true});
    await fs.copyFile(path.join(resultsRoot, source.id), target);
  }
}
function eventScope(event) { return event.scope || event; }
function immutableEvent(event) {
  const {stale, undone, ...original} = event;
  return original;
}
function sortedJSON(value) {
  if (Array.isArray(value)) return `[${value.map(sortedJSON).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${sortedJSON(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
}
function resealEvents(packageValue) {
  let previous = '0'.repeat(64);
  for (const event of packageValue.events) {
    event.prevHash = previous;
    const {hash, ...content} = event;
    event.hash = createHash('sha256').update(sortedJSON(content), 'utf8').digest('hex');
    previous = event.hash;
  }
  return packageValue;
}
async function fillDecision({dimension = 'type', label = 'unknown', reason, status = 'proposed'}) {
  await ui('dimension').selectOption(dimension);
  await ui('label').fill(label);
  await ui('reason').fill(reason);
  await ui('review-status').selectOption(status);
}
async function saveDecision(options) {
  const before = (await session()).events.length;
  await fillDecision(options);
  await ui('save-decision').click();
  return waitEvents(before + 1);
}
function cluster(id) { return evidence.clusters.find(item => String(item.id) === String(id)); }
function assertScope(event, id, dimension) {
  const scope = eventScope(event);
  assert.equal(String(scope.clusterId), String(id));
  assert.equal(scope.dimension, dimension);
  assert.equal(scope.revision || event.revision, evidence.revision);
  assert.deepEqual([...scope.cellIds].sort(), [...cluster(id).cellIds].sort(), 'Scope must include exact frozen cell ID set');
}

try {
  const sessionFile = path.join(output, 'browser-session.json');
  evidence = await startServer(resultsRoot, sessionFile);
  await copyExactSources();
  await stopServer();
  const fixtureEvidence = await startServer(fixtureRoot, sessionFile);
  assert.equal(fixtureEvidence.revision, evidence.revision, 'Moving sources must not change their content fingerprint');
  report.revision = evidence.revision;
  browser = await chromium.launch({headless: true, executablePath: chrome, args: [
    '--disable-background-networking', '--disable-component-update', '--disable-sync',
    '--disable-domain-reliability', '--no-pings'
  ]});
  report.browser = await browser.version();
  const context = await browser.newContext({viewport: {width: 1440, height: 1080}, acceptDownloads: true});
  await context.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (url.protocol === 'data:' || url.protocol === 'blob:' ||
        (url.protocol === 'http:' && url.hostname === '127.0.0.1' && url.origin === baseUrl)) {
      return route.continue();
    }
    report.externalRequests.push(url.href);
    return route.abort('blockedbyclient');
  });
  page = await context.newPage();
  page.on('pageerror', error => pageErrors.push(error.message));
  await page.goto(baseUrl, {waitUntil: 'networkidle'});
  await ui('cluster-6').waitFor({state: 'visible'});

  await test('Real frozen PBMC data: 2,638 cells, 9 clusters, cluster 6 = 155 cells', async () => {
    assert.equal(evidence.clusters.length, 9);
    assert.equal(evidence.umap.length, 2638);
    assert.equal(evidence.clusters.reduce((sum, item) => sum + item.cellCount, 0), 2638);
    assert.equal(cluster(6).cellCount, 155);
    assert.equal(cluster(6).cellIds.length, 155);
    assert.equal(new Set(evidence.umap.map(item => item.cellId)).size, 2638);
    assert.equal((await session()).events.length, 0, 'Fresh session starts without human decisions');
    assert.equal(evidence.clusters.flatMap(item => item.models).length, 36);
    assert.deepEqual(evidence.summary, {modelCalls: 36, strictValid: 33, formatRejected: 2, networkFailed: 1});
    assert.match(await ui('scope-summary').textContent(), /cluster 6/i);
    assert.match(await ui('cell-count').textContent(), /155/);
    report.cellCount = 2638;
    report.clusterCount = 9;
    await screenshot('01-cluster6-evidence');
  });

  await test('Cluster list and actual UMAP select the same exact cell set', async () => {
    await selectCluster(0);
    assert.match(await ui('cell-count').textContent(), new RegExp(String(cluster(0).cellCount)));
    const point = ui('umap-chart').locator('circle[data-cluster="6"]').last();
    await point.click({force: true});
    await page.waitForFunction(() => document.querySelector('[data-testid="scope-summary"]')?.textContent.toLowerCase().includes('cluster 6'));
    assert.match(await ui('cell-count').textContent(), /155/);
  });

  await test('Thirty real marker rows retain percentages, logFC and source', async () => {
    await ui('evidence-markers').click();
    assert.equal(await ui('marker-row').count(), 30);
    const tableText = await ui('marker-row').first().textContent();
    assert(tableText?.trim(), 'Marker values must render');
    const marker = cluster(6).markers[0];
    assert((await page.locator('body').textContent()).includes(marker.gene), 'Top frozen marker gene must appear');
    const cells = await ui('marker-row').first().locator('td').allTextContents();
    assert.equal(await ui('marker-row').first().locator('td').first().locator('.gene-lookup > :first-child').textContent(), marker.gene);
    assert.match(cells[0], /species undeclared · no GeneCards mapping/, 'Legacy evidence without declared species must retain its mapping warning');
    assert.deepEqual(cells.slice(1, 5), [marker.avgLog2FC, marker.pct1, marker.pct2, marker.pctDiff].map(value => value.toFixed(3)));
    assert.equal(cells.at(-1), marker.source);
    assert.match(await page.locator('body').textContent(), /pct|percent/i);
    assert.match(await page.locator('body').textContent(), /logFC|log2FC/i);
    assert.match(await page.locator('body').textContent(), /top.?30.*not|not.*top.?30|absence|absent/i);
    await ui('evidence-models').click();
  });

  await test('Real format rejects and transport failure remain separate from unmade and unknown', async () => {
    for (const item of evidence.clusters) {
      const failures = item.models.filter(model => model.strictStatus !== 'valid');
      if (!failures.length) continue;
      await selectCluster(item.id);
      await ui('evidence-models').click();
      assert.match(await page.locator('#current-decision').textContent(), /No human decision/);
      for (const model of failures) {
        const card = ui(`model-card-${model.callId}`);
        assert.match(await card.textContent(), model.strictStatus === 'network_failed' ? /Transport failed/ : /Format rejected/);
        assert.match(await card.textContent(), model.strictStatus === 'network_failed' ? /not.*biological prediction of unknown/ : /not.*human unknown decision/);
        assert.equal(await card.locator('.result-label').count(), 0, 'Parser failure cannot render as an unknown type label');
        if (model.posthoc.label) {
          assert((await card.locator('.posthoc').textContent()).includes(model.posthoc.label));
          assert.match(await card.locator('.posthoc').textContent(), /separate interpretation/i);
        }
      }
    }
    assert.equal((await session()).events.length, 0);
    await selectCluster(6);
  });

  await test('A real database candidate can populate a draft without overwriting source or creating a decision', async () => {
    await ui('evidence-database').click();
    const candidate = cluster(6).candidates[0];
    assert(candidate?.label);
    assert((await page.locator('#evidence-content').textContent()).includes(candidate.label));
    const firstRow = page.locator('#evidence-content tbody tr').first();
    assert((await firstRow.textContent()).includes(candidate.markers.join(', ')));
    await firstRow.getByRole('button').click();
    assert.equal(await ui('label').inputValue(), candidate.label);
    assert.equal(await ui('dimension').inputValue(), 'type');
    assert.equal((await session()).events.length, 0);
    assert.deepEqual((await api('/api/evidence')).clusters.find(item => String(item.id) === '6').candidates, cluster(6).candidates);
    await ui('evidence-models').click();
  });

  await test('Missing reason rejects save and does not create a decision', async () => {
    await fillDecision({label: 'CD8 T', reason: '', status: 'reviewed'});
    await ui('save-decision').click();
    assert.equal((await session()).events.length, 0);
    assert(await ui('reason').evaluate(element => !element.validity.valid) ||
      (await ui('notice').textContent())?.trim(), 'Missing reason must produce visible feedback');
  });

  await test('Retain unknown is distinct from undecided and model failure', async () => {
    await ui('retain-unknown').click();
    assert.equal(await ui('label').inputValue(), 'unknown');
    assert.equal((await session()).events.length, 0, 'Unknown shortcut still requires reason and Save');
    const current = await saveDecision({label: 'unknown', reason: 'CD8/NK evidence remains unresolved; retain uncertainty.', status: 'proposed'});
    assert.equal(current.events.at(-1).label, 'unknown');
    assertScope(current.events.at(-1), 6, 'type');
    assert.equal((await api('/api/evidence')).clusters.find(item => String(item.id) === '6').models.length, 4);
    assert.deepEqual((await api('/api/evidence')).clusters.find(item => String(item.id) === '6').models, cluster(6).models,
      'Human decisions must not rewrite model source');
  });

  await test('Type, state and QC each require explicit revision + cluster + exact cell IDs', async () => {
    let current = await saveDecision({dimension: 'state', label: 'cytotoxic', reason: 'State is separate from unresolved lineage.', status: 'reviewed'});
    assertScope(current.events.at(-1), 6, 'state');
    current = await saveDecision({dimension: 'QC', label: 'needs review', reason: 'Keep the QC concern separate from type and state.', status: 'accepted'});
    assertScope(current.events.at(-1), 6, 'QC');
    await selectCluster(0);
    current = await saveDecision({dimension: 'type', label: 'CD4 T', reason: 'Independent human review limited to cluster 0.', status: 'reviewed'});
    assertScope(current.events.at(-1), 0, 'type');
    assert.equal(current.events.length, 4);
    await selectCluster(6);
  });

  await test('Repeated save activation adds exactly one durable event', async () => {
    const before = (await session()).events.length;
    await fillDecision({label: 'CD8 T / NK unresolved', reason: 'Record the unresolved boundary exactly once.', status: 'reviewed'});
    await ui('save-decision').dblclick();
    const current = await waitEvents(before + 1);
    await sleep(300);
    assert.equal((await session()).events.length, before + 1);
    assertScope(current.events.at(-1), 6, 'type');
  });

  await test('Undo appends a compensation event and preserves original event bytes', async () => {
    const before = await session();
    const originalEvents = (await api('/api/export')).events;
    const target = before.events.at(-1);
    await ui('evidence-history').click();
    // Reason is the shared editor field; undo also needs a reason.
    await ui('reason').fill('Revert the last lineage edit while preserving its audit event.');
    await ui(`undo-${target.id || target.eventId}`).click();
    await page.locator('#undo-reason').fill('Revert the last lineage edit while preserving its audit event.');
    await page.locator('#confirm-undo').click();
    const current = await waitEvents(before.events.length + 1);
    assert.deepEqual((await api('/api/export')).events.slice(0, -1), originalEvents, 'Undo must not delete or alter old events');
    assert.equal(current.events.at(-1).targetEventId, target.id || target.eventId);
    assert(current.events.at(-1).reason.trim(), 'Compensation requires a reason');
    assertScope(current.events.at(-1), 6, 'type');
    assert.equal(await ui(`undo-${target.id || target.eventId}`).count(), 0, 'A compensated decision cannot offer another undo');
    assert.match(await page.locator(`[data-event-id="${target.id || target.eventId}"]`).textContent(), /undone/i);
    await screenshot('02-decisions-and-compensation');
  });

  await test('Refresh restores the identical durable session', async () => {
    const before = await session();
    await page.reload({waitUntil: 'networkidle'});
    await ui('cluster-6').waitFor({state: 'visible'});
    assert.deepEqual(await session(), before);
  });

  await test('Server restart reloads the identical durable session', async () => {
    const before = await session();
    await stopServer();
    await startServer(fixtureRoot, sessionFile);
    await page.goto(baseUrl, {waitUntil: 'networkidle'});
    await ui('cluster-6').waitFor({state: 'visible'});
    assert.deepEqual(await session(), before);
  });

  await test('Exported handoff can be reimported without changing any event or decision', async () => {
    const before = await session();
    const packageBefore = await api('/api/export');
    const downloadEvent = page.waitForEvent('download');
    await ui('export-session').click();
    const download = await downloadEvent;
    const exportFile = path.join(output, 'browser-handoff.json');
    await download.saveAs(exportFile);
    assert.deepEqual(JSON.parse(await fs.readFile(exportFile, 'utf8')), packageBefore);
    await ui('import-file').setInputFiles(exportFile);
    await page.waitForFunction(() => /import|loaded|restor/i.test(document.querySelector('[data-testid="notice"]')?.textContent || ''));
    assert.deepEqual(await api('/api/export'), packageBefore);
    assert.deepEqual(await session(), before);
  });

  await test('Actual UI rejects duplicate JSON keys from original file bytes atomically', async () => {
    const beforePackage = await api('/api/export');
    const beforeSession = await session();
    // A normal JSON.parse would silently keep the last, valid format field.
    const raw = JSON.stringify(beforePackage).replace('"format":', '"format":"untrusted duplicate","format":');
    assert.equal(JSON.parse(raw).format, beforePackage.format);
    const filename = path.join(output, 'duplicate-key-handoff.json');
    await fs.writeFile(filename, raw);
    const importResponse = page.waitForResponse(response => response.url().endsWith('/api/import') && response.request().method() === 'POST');
    await ui('import-file').setInputFiles(filename);
    const response = await importResponse;
    assert.equal(response.request().postData(), raw, 'UI must preserve original bytes so duplicate keys are detectable');
    assert.equal(response.status(), 422);
    assert.match((await response.json()).error, /duplicate.*(JSON|object|key)/i);
    await ui('error-banner').waitFor({state: 'visible'});
    assert.match(await ui('error-banner').textContent(), /duplicate/i);
    assert.deepEqual(await api('/api/export'), beforePackage, 'Rejected raw import must not alter immutable package');
    assert.deepEqual(await session(), beforeSession, 'Rejected raw import must not alter decisions or lock a valid session');
  });

  await test('Invalid, missing and duplicate-reference handoffs are rejected atomically', async () => {
    const before = await api('/api/export');
    const malformedPackages = [{}, {schema: 'unsupported'}, {...before, events: [...before.events, before.events[0]]}];
    for (const key of ['revision', 'clusterId']) {
      const damaged = structuredClone(before);
      damaged.events[0].scope[key] = [];
      malformedPackages.push(resealEvents(damaged));
    }
    const badUndo = structuredClone(before);
    badUndo.events.find(event => event.kind === 'undo').targetEventId = [];
    malformedPackages.push(resealEvents(badUndo));
    for (const malformed of malformedPackages) {
      const response = await fetch(`${baseUrl}/api/import`, {method: 'POST', headers: {'Content-Type': 'application/json', 'Origin': baseUrl},
        body: JSON.stringify({package: malformed})});
      assert(response.status >= 400 && response.status < 500, 'Malformed import must be rejected');
      assert.deepEqual(await api('/api/export'), before, 'Rejected handoff must leave session untouched');
    }
  });

  await test('Model response HTML renders as text and cannot execute', async () => {
    const actualEvidence = structuredClone(evidence);
    const malicious = '<img src=x onerror="window.__workbenchXss=true"><script>window.__workbenchXss=true</script>';
    // Browser-only network substitution tests rendering, leaving real source files unchanged.
    for (const model of actualEvidence.clusters.find(item => String(item.id) === '6').models) {
      for (const key of Object.keys(model)) if (/raw|response|text/i.test(key) && typeof model[key] === 'string') model[key] = malicious;
    }
    await page.route('**/api/evidence', route => route.fulfill({status: 200, contentType: 'application/json', body: JSON.stringify(actualEvidence)}));
    await page.reload({waitUntil: 'networkidle'});
    await ui('cluster-6').waitFor({state: 'visible'});
    await ui('evidence-models').click();
    for (const details of await page.locator('details').all()) if (!(await details.evaluate(element => element.open))) await details.locator('summary').click();
    assert.equal(await page.evaluate(() => !!window.__workbenchXss), false);
    assert.equal(await page.locator('img[onerror]').count(), 0);
    assert.equal(await page.locator('script').filter({hasText: '__workbenchXss'}).count(), 0);
    assert((await page.locator('body').textContent()).includes('<img src=x'), 'Malicious model raw text must be visible literally');
    await page.unroute('**/api/evidence');
    await page.reload({waitUntil: 'networkidle'});
  });

  await test('Desktop and narrow viewport remain usable without horizontal overflow', async () => {
    await page.setViewportSize({width: 390, height: 844});
    await ui('cluster-6').waitFor({state: 'visible'});
    const overflow = await page.evaluate(() => ({width: window.innerWidth, scrollWidth: document.documentElement.scrollWidth,
      elements: [...document.querySelectorAll('body *')].map(element => ({tag: element.tagName, id: element.id,
        class: String(element.className), right: element.getBoundingClientRect().right, width: element.getBoundingClientRect().width}))
        .filter(element => element.right > window.innerWidth + 1).slice(0, 30)}));
    report.narrowViewport = overflow;
    assert.equal(overflow.scrollWidth <= overflow.width + 1, true, JSON.stringify(overflow));
    await screenshot('03-narrow-viewport');
    await page.setViewportSize({width: 1440, height: 1080});
  });

  await test('Actual changed source bytes change revision and mark old decisions stale', async () => {
    const before = await session();
    await fillDecision({label: 'draft from prior evidence', reason: 'This unsaved draft was based only on the previous revision.', status: 'reviewed'});
    const source = evidence.sources.find(item => item.id.endsWith('_umap.csv'));
    assert(source, 'Actual UMAP source must be fingerprinted');
    const target = path.join(fixtureRoot, source.id);
    const lines = (await fs.readFile(target, 'utf8')).split('\n');
    const index = lines[0].split(',').map(value => value.replaceAll('"', '')).indexOf('umap_1');
    assert(index >= 0);
    const first = lines[1].split(',');
    first[index] = String(Number(first[index].replaceAll('"', '')) + 0.00001);
    lines[1] = first.join(',');
    await fs.writeFile(target, lines.join('\n'));
    const changed = await api('/api/evidence');
    assert.notEqual(changed.revision, evidence.revision);
    const current = await session();
    assert.deepEqual(current.events.map(immutableEvent), before.events.map(immutableEvent), 'Evidence changes must not rewrite old journal');
    const decisions = Array.isArray(current.decisions) ? current.decisions : Object.values(current.decisions);
    assert(decisions.length > 0);
    assert(decisions.every(item => item.stale === true), 'Every old-revision decision must be stale');
    await ui('refresh-evidence').click();
    await page.waitForFunction(() => /stale/i.test(document.body.textContent));
    assert.equal(await ui('label').inputValue(), '', 'Draft labels must not silently transfer to changed evidence');
    assert.equal(await ui('reason').inputValue(), '', 'Draft reasoning must be cleared or explicitly re-reviewed after changed evidence');
    await screenshot('04-changed-evidence-stale');
  });

  await test('Missing evidence enters read-only mode and cannot silently reuse cached input', async () => {
    const source = evidence.sources.find(item => item.id.endsWith('.json') && item.id.startsWith('pbmc3k_api/'));
    const target = path.join(fixtureRoot, source.id);
    const original = await fs.readFile(target);
    const before = (await session()).events;
    await fillDecision({label: 'draft before invalid evidence', reason: 'This draft must not migrate through failed refresh into another revision.', status: 'accepted'});
    await fs.unlink(target);
    await api('/api/evidence', undefined, 422);
    const broken = await session();
    assert.equal(broken.readOnly, true);
    assert.deepEqual(broken.events.map(immutableEvent), before.map(immutableEvent));
    await ui('refresh-evidence').click();
    await ui('error-banner').waitFor({state: 'visible'});
    assert.equal(await ui('save-decision').isDisabled(), true);
    const priorErrors = [...pageErrors];
    const showAll = page.locator('#show-all');
    if (!(await showAll.isDisabled())) await showAll.click();
    const useLabel = page.getByRole('button', {name: /Use strict label/}).first();
    if (await useLabel.count() && !(await useLabel.isDisabled())) await useLabel.click();
    if (!(await ui('dimension').isDisabled())) await ui('dimension').selectOption('QC');
    assert.deepEqual(pageErrors, priorErrors, 'Previously rendered source controls must not crash after evidence rejection');
    await fs.writeFile(target, Buffer.concat([original, Buffer.from('\n')]));
    await ui('refresh-evidence').click();
    assert.equal((await session()).readOnly, false);
    assert.equal(await ui('label').inputValue(), '', 'Invalid-then-changed evidence cannot silently reuse a draft label');
    assert.equal(await ui('reason').inputValue(), '', 'Invalid-then-changed evidence cannot silently reuse draft reasoning');
  });

  await test('Invalid model JSON is rejected rather than crashing or silently using old input', async () => {
    const source = evidence.sources.find(item => item.id.endsWith('.json') && item.id.startsWith('pbmc3k_api/'));
    const target = path.join(fixtureRoot, source.id);
    const original = await fs.readFile(target);
    await fs.writeFile(target, 'null');
    await api('/api/evidence', undefined, 422);
    assert.equal((await session()).readOnly, true);
    await ui('refresh-evidence').click();
    await ui('error-banner').waitFor({state: 'visible'});
    assert.equal(await ui('save-decision').isDisabled(), true);
    await fs.writeFile(target, original);
    await ui('refresh-evidence').click();
    assert.equal((await session()).readOnly, false);
  });

  await test('Corrupt on-disk history becomes read-only and cannot export a verified handoff', async () => {
    const original = await fs.readFile(sessionFile, 'utf8');
    const corrupt = JSON.parse(original);
    corrupt.events[0].scope.revision = [];
    resealEvents(corrupt);
    await fs.writeFile(sessionFile, JSON.stringify(corrupt));
    assert.equal((await session()).readOnly, true);
    await api('/api/export', undefined, 409);
    await ui('refresh-evidence').click();
    await ui('error-banner').waitFor({state: 'visible'});
    assert.equal(await ui('save-decision').isDisabled(), true);
    await fs.writeFile(sessionFile, original);
    await ui('refresh-evidence').click();
    assert.equal((await session()).readOnly, false);
  });

  await test('No browser page errors and no external network attempts', async () => {
    assert.deepEqual(pageErrors, []);
    assert.deepEqual(report.externalRequests, []);
  });
  report.outcome = 'passed';
} catch (error) {
  report.outcome = 'failed';
  report.error = error.stack || error.message;
  if (page) await screenshot('failure').catch(() => {});
  console.error(error.stack || error.message);
  process.exitCode = 1;
} finally {
  if (browser) await browser.close().catch(() => {});
  await stopServer();
  report.pageErrors = pageErrors;
  report.finishedAt = new Date().toISOString();
  await fs.writeFile(path.join(output, 'browser-report.json'), JSON.stringify(report, null, 2));
  await fs.writeFile(path.join(output, 'server.log'), serverLogs.join(''));
  console.log(`QA artifacts: ${output}`);
}
