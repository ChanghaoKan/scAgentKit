#!/usr/bin/env node
/** Generic project round trip: actual browser, real PBMC + deterministic synthetic.
 * Generate fixtures with create_project_fixtures.R first; output remains outside Git.
 * node browser_project.mjs --fixtures /private/fixtures --output /fresh/private/report
 * Optional --r-library /existing/library --chrome /browser --playwright /module.
 * No provider calls, credentials, original-source writes or live-server access.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import http from 'node:http';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';

const args = {};
for (let i = 2; i < process.argv.length; i += 2) {
  assert(process.argv[i]?.startsWith('--') && process.argv[i + 1], 'Use --name value pairs');
  args[process.argv[i].slice(2)] = process.argv[i + 1];
}
assert(args.fixtures, '--fixtures must point to completed private fixture-projects.json');
const fixtureRoot = path.resolve(args.fixtures);
const fixtures = JSON.parse(await fs.readFile(path.join(fixtureRoot, 'fixture-projects.json'), 'utf8'));
assert(fixtures.projects.pbmc && fixtures.projects.synthetic && fixtures.projects.noEmbedding && fixtures.projects.prepared,
  'Export real PBMC, independent synthetic, counts-prepared and no-embedding projects first');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repo = path.dirname(root);
const output = path.resolve(args.output || await fs.mkdtemp(path.join(os.tmpdir(), 'scagentkit-project-browser-')));
await fs.mkdir(output, {recursive: true});
assert.equal(await fs.access(path.join(output, 'project-browser-report.json')).then(() => true, () => false), false,
  'Use a fresh output directory; never overwrite QA review history');
const resumeRoot = args['resume-after-writeback'] ? path.resolve(args['resume-after-writeback']) : null;
let previousEvidence;
if(resumeRoot) {
  const prior = JSON.parse(await fs.readFile(path.join(resumeRoot, 'project-browser-report.json'), 'utf8'));
  assert.equal(prior.tests.slice(0,8).filter(item=>item.outcome==='passed').length,8,
    'Resume requires all first eight actual browser cases to have passed');
  const writeback = {};
  for(const name of ['synthetic','agentseurat','pbmc']) {
    const file = path.join(resumeRoot,'r-writeback-'+name+'.json');
    const result = JSON.parse(await fs.readFile(file,'utf8'));
    assert.equal(result.outcome,'passed');assert.equal(result.originalPreserved,true);
    writeback[name] = file;
  }
  previousEvidence = {browserReport:path.join(resumeRoot,'project-browser-report.json'),writeback};
}
const stateRoot = resumeRoot || output;
const cache = path.join(stateRoot, 'project-cache'), journals = path.join(stateRoot, 'journals');
const require = createRequire(import.meta.url);
const {chromium} = require(args.playwright || process.env.PLAYWRIGHT_MODULE_PATH ||
  '/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright');
const report = {startedAt: new Date().toISOString(), output, tests: [], screenshots: [],
  pageErrors: [], externalRequests: [], sourceProjects: fixtures.projects,
  scope:resumeRoot?'remaining_six_cases_only':'complete_fifteen_cases',previousEvidence};
let server, browser, page, origin;
const logs = [];
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const ui = id => page.locator('[data-testid="' + id + '"]');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const projectSpec = name => fixtures.projects[name];
const manifest = async name => JSON.parse(await fs.readFile(path.join(projectSpec(name).path, 'manifest.json'), 'utf8'));
const projects = async () => api('/api/projects');
const evidence = async () => api('/api/evidence');
const session = async () => api('/api/session');
const journal = async () => api('/api/export');
let testIndex = 0;

async function test(name, fn) {
  testIndex += 1;
  if(resumeRoot && testIndex <= 9)return;
  const started = Date.now();
  try {await fn(); report.tests.push({name, outcome: 'passed', milliseconds: Date.now() - started}); console.log('PASS ' + name);}
  catch(error) {report.tests.push({name, outcome: 'failed', error: error.message}); throw error;}
}
async function subprocess(command, argv, timeout = 180000) {
  const child = spawn(command, argv, {cwd: repo, stdio: ['ignore', 'pipe', 'pipe']});
  let stdout = '', stderr = '';
  child.stdout.on('data', bytes => {stdout += bytes;});
  child.stderr.on('data', bytes => {stderr += bytes;});
  const timer = setTimeout(() => child.kill('SIGKILL'), timeout);
  try {
    const code = await new Promise((resolve, reject) => {child.once('error', reject); child.once('exit', resolve);});
    assert.equal(code, 0, command + ': ' + stderr + stdout);
    return {stdout, stderr};
  } finally {clearTimeout(timer);}
}
async function freePort() {
  const listener = net.createServer();
  await new Promise((resolve, reject) => {listener.once('error', reject); listener.listen(0, '127.0.0.1', resolve);});
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  return port;
}
async function startServer() {
  const port = await freePort(); origin = 'http://127.0.0.1:' + port;
  server = spawn(args.python || 'python3', [path.join(root, 'server.py'),
    '--project', projectSpec('pbmc').path, '--project', projectSpec('synthetic').path,
    '--project-cache', cache, '--journal-root', journals, '--port', String(port)], {cwd: repo, stdio: ['ignore', 'pipe', 'pipe']});
  server.stdout.on('data', chunk => logs.push(chunk.toString()));
  server.stderr.on('data', chunk => logs.push(chunk.toString()));
  for(let i = 0; i < 150; i++) {
    if(server.exitCode !== null) throw new Error('Server exited: ' + logs.join(''));
    try {if((await fetch(origin + '/api/projects')).ok) return;}
    catch {}
    await pause(100);
  }
  throw new Error('Fresh generic localhost server did not become ready');
}
async function stopServer() {
  if(!server || server.exitCode !== null)return;
  const current = server; current.kill('SIGTERM');
  await Promise.race([new Promise(resolve => current.once('exit', resolve)), pause(3000)]);
  if(current.exitCode === null)current.kill('SIGKILL');
}
async function api(route, body, status = 200, contentType = 'application/json', boundKey) {
  const key = boundKey || (page ? await ui('project-select').inputValue() : null);
  const headers = key ? {'X-ScAgentKit-Project': key} : {};
  const options = body === undefined ? {headers} : {method: 'POST',
    headers: {...headers, 'Content-Type': contentType, Origin: origin},
    body: Buffer.isBuffer(body) || typeof body === 'string' ? body : JSON.stringify(body)};
  const response = await fetch(origin + route, options);
  const text = await response.text();
  assert.equal(response.status, status, route + ': ' + text);
  return JSON.parse(text);
}
async function waitIdle() {
  await page.waitForFunction(() => !document.querySelector('[data-testid="project-select"]')?.disabled);
}
async function selectProject(name) {
  const value = projectSpec(name).bundleDigest;
  await ui('project-select').selectOption(value);
  await page.waitForFunction(expected => document.querySelector('[data-testid="project-select"]')?.value === expected &&
    !document.querySelector('[data-testid="project-select"]')?.disabled, value);
  assert.equal((await evidence()).projectId, projectSpec(name).projectId);
}
async function selectCluster(id) {
  await ui('cluster-' + id).click();
  await page.waitForFunction(expected => document.querySelector('[data-testid="scope-summary"]')?.textContent.includes('Cluster ' + expected), id);
}
async function awaitEventCount(count) {
  for(let i = 0; i < 100; i++) {const current = await session(); if(current.events.length === count)return current; await pause(80);}
  assert.equal((await session()).events.length, count);
}
async function record(clusterId, label, status, dimension = 'type', reason = 'Synthetic human review with explicit limits and exact cell IDs.') {
  await selectCluster(clusterId);
  await ui('dimension').selectOption(dimension);
  await ui('label').fill(label); await ui('reason').fill(reason);
  await ui('review-status').selectOption(status);
  const before = await session(); await ui('save-decision').click();
  const current = await awaitEventCount(before.events.length + 1);
  await waitIdle();
  const event = current.events.at(-1), actual = await evidence();
  assert.deepEqual(event.scope.cellIds, actual.clusters.find(item => item.id === clusterId).cellIds);
  assert.equal(event.scope.sourceFingerprint, actual.sourceFingerprint);
  assert.equal(event.scope.datasetId, actual.projectId);
  assert.equal(event.scope.revision, actual.bundleDigest);
  assert.equal(event.scope.dimension, dimension);
  return event;
}
async function undo(event) {
  await ui('evidence-history').click();
  await ui('undo-' + event.id).click();
  await page.locator('#undo-reason').fill('Undo this correction while retaining the original scoped human history.');
  const before = await journal(); await page.locator('#confirm-undo').click();
  await awaitEventCount(before.events.length + 1); await waitIdle();
  const after = await journal();
  assert.deepEqual(after.events.slice(0, -1), before.events);
  assert.equal(JSON.parse(after.events.at(-1).payload).targetEventId, event.id);
}
async function screenshot(name, fullPage = true) {
  const file = path.join(output, name + '.png');
  await page.screenshot({path: file, fullPage}); report.screenshots.push(file);
}
async function download(id, file) {
  const pending = page.waitForEvent('download'); await ui(id).click();
  await (await pending).saveAs(file); await waitIdle();
}
async function verifyR(name, journalFile, objectFile, suffix = name) {
  const reportFile = path.join(output, 'r-writeback-' + suffix + '.json');
  const argv = ['--vanilla', path.join(root, 'tests', 'create_project_fixtures.R'),
    '--verify-journal', journalFile, '--project', projectSpec(name).path,
    '--object', objectFile, '--report-file', reportFile];
  if(args['r-library'])argv.push('--r-library', args['r-library']);
  const result = await subprocess(args.rscript || 'Rscript', argv);
  await fs.writeFile(path.join(output, 'r-writeback-' + suffix + '.log'), result.stdout + result.stderr);
  const verified = JSON.parse(await fs.readFile(reportFile, 'utf8'));
  assert.equal(verified.outcome, 'passed'); assert.equal(verified.originalPreserved, true);
  return verified;
}
async function makeAdversarialZips() {
  const python = [
    'import pathlib,sys,zipfile,io,stat,json',
    'source=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2]); out.mkdir()',
    'base={p.relative_to(source).as_posix():p.read_bytes() for p in source.rglob("*") if p.is_file()}',
    'def write(name,extra=None,replace=None,duplicate=None,symlink=False,ratio=False):',
    ' b=dict(base); b.update(replace or {})',
    ' with zipfile.ZipFile(out/(name+".zip"),"w",zipfile.ZIP_DEFLATED) as z:',
    '  for key,value in b.items(): z.writestr(key,value)',
    '  if extra: z.writestr(extra,b"unlisted")',
    '  if duplicate: z.writestr(duplicate,b"duplicate")',
    '  if symlink:',
    '   item=zipfile.ZipInfo("link"); item.create_system=3; item.external_attr=(stat.S_IFLNK|0o777)<<16; z.writestr(item,b"/tmp/never-follow")',
    '  if ratio: z.writestr("oversized.txt",b"0"*200000)',
    'write("traversal",extra="../never-written.txt")',
    'write("absolute",extra="/tmp/never-written.txt")',
    'write("drive",extra="C:/never-written.txt")',
    'write("duplicate",duplicate="project.json")',
    'write("case-collision",duplicate="PROJECT.JSON")',
    'write("symlink",symlink=True)',
    'write("unlisted",extra="unlisted.txt")',
    'write("checksum",replace={"project.json":base["project.json"]+b" "})',
    'write("ratio",ratio=True)',
    'm=json.loads(base["manifest.json"]);m["schema"]="future.unsupported.v99"',
    'write("unknown-schema",replace={"manifest.json":json.dumps(m).encode()})',
    'write("duplicate-key",replace={"manifest.json":base["manifest.json"].replace(b"{",b"{"+json.dumps({"schema":"scagentkit.project-bundle.v1"})[1:-1].encode()+b",",1)})',
  ].join('\n');
  const target = path.join(output, 'bad-zips');
  await subprocess(args.python || 'python3', ['-c', python, projectSpec('synthetic').path, target]);
  return target;
}
const parsedEvent = envelope => JSON.parse(envelope.payload);
function rehash(packageValue) {
  let previous = '0'.repeat(64);
  for(const envelope of packageValue.events) {
    envelope.prevHash = previous; envelope.hash = hash(previous + '\n' + envelope.payload); previous = envelope.hash;
  }
  return packageValue;
}

try {
  await startServer();
  browser = await chromium.launch({headless: true, executablePath: args.chrome || process.env.CHROME_EXECUTABLE ||
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', args: ['--disable-background-networking','--disable-component-update','--disable-sync','--no-pings']});
  report.browser = await browser.version();
  const context = await browser.newContext({viewport: {width: 1440, height: 1060}, acceptDownloads: true});
  await context.route('**/*', async route => {
    const url = new URL(route.request().url());
    if(url.origin === origin || ['data:','blob:'].includes(url.protocol))return route.continue();
    report.externalRequests.push(url.href); return route.abort('blockedbyclient');
  });
  page = await context.newPage();
  page.on('pageerror', error => report.pageErrors.push(error.message));
  page.on('dialog', dialog => dialog.accept());
  await page.goto(origin, {waitUntil: 'networkidle'}); await waitIdle();
  if(resumeRoot)await selectProject('synthetic');

  await test('Real PBMC project loads without a hardcoded path or fabricated model results', async () => {
    await selectProject('pbmc');
    const value = await evidence();
    assert.equal(value.dataset.retainedCells, 2638); assert.equal(value.clusters.length, 9);
    assert.equal(value.clusters.find(row => row.id === '6').cellCount, 155);
    assert.equal(value.summary.modelCalls, 0); assert.equal(value.summary.modelStatus, 'not_run');
    await ui('evidence-models').click(); await ui('models-not-run').waitFor({state: 'visible'});
    assert.equal((await session()).events.length, 0);
    await record('6', 'unknown', 'accepted', 'type', 'CD8/NK remains uncertain after reviewing the portable local RNA evidence.');
    report.pbmcIdentity = value.identity;
    await screenshot('01-pbmc-project');
  });

  await test('Independent synthetic project preserves literal clusters, source annotations and every exact barcode', async () => {
    await selectProject('synthetic');
    const value = await evidence();
    assert.equal(value.dataset.retainedCells, 120); assert.equal(value.identity.featureCount, 1000);
    assert.deepEqual(value.clusters.map(row => row.id).sort(), ['001','1','B alpha','NA','中文'].sort());
    for(const id of ['001','1','NA','B alpha','中文']) {
      await selectCluster(id); assert.equal(value.clusters.find(row => row.id === id).cellCount, 24);
      assert.match(await ui('cell-count').textContent(), /24/);
    }
    assert.equal(new Set(value.clusters.flatMap(row => row.cellIds)).size, 120);
    assert(value.clusters.flatMap(row => row.cellIds).includes('001'));
    assert(value.clusters.flatMap(row => row.cellIds).includes('1'));
    assert(value.clusters.flatMap(row => row.cellIds).includes('NA'));
    assert.equal((await session()).events.length, 0, 'Source annotations cannot become accepted human decisions');
    report.syntheticIdentity = value.identity;
    await screenshot('02-independent-string-clusters');
  });

  await test('Directed RNA replay uses explicit arbitrary scopes and distinguishes missing genes from actual measured zeros', async () => {
    await selectCluster('001'); await ui('evidence-directed').click();
    await ui('directed-plan').waitFor({state: 'visible'});
    const view = await api('/api/directed?clusterId=001');
    assert.equal(view.expression.scope.cluster_id, '001'); assert.equal(view.expression.scope.n_cells, 24);
    assert.deepEqual(view.expression.scope.cell_ids, (await evidence()).clusters.find(row => row.id === '001').cellIds);
    assert.equal(view.expression.source.object_fingerprint, (await evidence()).sourceFingerprint);
    assert.equal(view.expression.source.rds_sha256, undefined, 'A portable export cannot invent an RDS identity');
    assert.equal(view.expression.panel.find(row => row.gene === 'TRAC').measurement_status, 'missing');
    const zero = view.expression.panel.find(row => row.gene === 'NCR1');
    assert.equal(zero.measurement_status, 'measured'); assert.equal(zero.detected_n, 0);
    assert.match(await ui('directed-evidence').locator('[data-gene="TRAC"]').textContent(), /missing/i);
    assert.match(await ui('directed-evidence').locator('[data-gene="NCR1"]').textContent(), /0\s*\/\s*24/);
    await ui('directed-execute').click(); await waitIdle();
    assert.equal((await session()).events.length, 0);
    assert.equal(view.modelReview.calls, 0); assert.equal(view.modelReview.incrementalCostUSD, 0);
    await selectCluster('B alpha');
    await ui('directed-unavailable').waitFor({state: 'visible'});
    const unavailable = await api('/api/directed?clusterId=B%20alpha');
    assert.equal(unavailable.expression, null); assert.equal(unavailable.execution.available, false);
    assert.equal(unavailable.proposal.recommendedLabel, 'unknown');
    if(await ui('directed-adopt').count())assert.equal(await ui('directed-adopt').isDisabled(), true);
    assert.equal(await ui('directed-execute').isDisabled(), true, 'An unselected lineage cannot execute an inferred T/NK panel');
    await screenshot('03-unavailable-other-lineage');
  });

  await test('Partial human review keeps accepted labels, unknown, deferred decisions and unreviewed cells separate', async () => {
    await selectCluster('001'); await ui('evidence-directed').click();
    await ui('directed-adopt').waitFor({state: 'visible'}); await ui('directed-adopt').click();
    assert.equal((await session()).events.length, 0, 'Proposal adoption creates only a draft');
    await ui('label').fill('Synthetic reviewed T'); await ui('review-status').selectOption('accepted');
    await ui('reason').fill('<img src=x onerror="window.__reviewXss=1"> Human test reason retained as plain text.');
    await ui('save-decision').click(); await awaitEventCount(1); await waitIdle();
    assert((await session()).events[0].evidenceRefs.length > 0);
    await record('1', 'unknown', 'accepted');
    await record('NA', 'Pending assessment', 'proposed');
    await record('NA', 'Pending assessment', 'reviewed');
    await record('中文', 'Original human B label', 'accepted');
    const correction = await record('中文', 'Corrected human B label', 'accepted');
    await undo(correction);
    assert.equal((await session()).decisions.find(row => row.scope.clusterId === '中文').label, 'Original human B label');
    await record('001', 'Observed program state', 'proposed', 'state');
    await record('NA', 'Depth review pending', 'reviewed', 'QC');
    assert.equal((await session()).decisions.some(row => row.scope.clusterId === 'B alpha'), false);
    await ui('evidence-history').click(); assert.equal(await page.evaluate(() => window.__reviewXss), undefined);
    assert.equal(await page.locator('img[src="x"]').count(), 0);
    await screenshot('04-partial-review-and-undo');
  });

  await test('Repeated request IDs are idempotent while invalid mutation input rejects atomically', async () => {
    const value = await evidence(), before = await journal();
    const body = {clusterId:'B alpha',dimension:'QC',label:'Temporary observation',reason:'Local idempotency check',status:'proposed',revision:value.revision,requestId:crypto.randomUUID()};
    const once = await api('/api/decision', body); const twice = await api('/api/decision', body);
    assert.deepEqual(twice, once); assert.equal(once.events.length, before.events.length + 1);
    await api('/api/decision', {...body,label:'Conflicting reuse'}, 409);
    const unchanged = await journal();
    for(const mutation of [{...body,requestId:crypto.randomUUID(),reason:''},
      {...body,requestId:crypto.randomUUID(),clusterId:'nonexistent'},
      {...body,requestId:crypto.randomUUID(),dimension:'lineage'},
      {...body,requestId:crypto.randomUUID(),revision:'0'.repeat(64)}]) {
      await api('/api/decision', mutation, mutation.revision === '0'.repeat(64) ? 409 : 422);
      assert.deepEqual(await journal(), unchanged);
    }
    await api('/api/undo', {targetEventId:once.events.at(-1).id,reason:'Remove temporary idempotency observation',revision:value.revision,requestId:crypto.randomUUID()});
    await page.reload({waitUntil:'networkidle'}); await waitIdle();
  });

  await test('Actual review download/import and browser refresh preserve original envelope and artifact bytes', async () => {
    const before = await journal();
    const file = path.join(output, 'synthetic-review-journal.json');
    await download('export-session', file);
    assert.deepEqual(JSON.parse(await fs.readFile(file,'utf8')), before);
    await ui('import-file').setInputFiles(file); await waitIdle();
    assert.deepEqual(await journal(), before);
    await api('/api/import', JSON.parse(await fs.readFile(file,'utf8')));
    assert.deepEqual(await journal(), before);
    await page.reload({waitUntil:'networkidle'}); await waitIdle();
    assert.deepEqual(await journal(), before);
    report.syntheticJournal = file;
  });

  await test('Moving project ZIP bytes to a new local folder preserves identity and keeps journals separate', async () => {
    const before = await journal(), listBefore = await projects();
    const moved = path.join(output,'relocated'); await fs.mkdir(moved);
    const zip = path.join(moved,'own-project.zip'); await download('export-project',zip);
    await ui('project-file').setInputFiles(zip); await waitIdle();
    assert.deepEqual(await journal(), before);
    assert.equal((await projects()).projects.length,listBefore.projects.length);
    await selectProject('pbmc');
    assert.equal((await session()).events.length,1);
    await api('/api/import',before,409);
    assert.equal((await session()).events.length,1);
    const file = path.join(output,'pbmc-review-journal.json'); await download('export-session',file);
    report.pbmcJournal = file;
    await selectProject('synthetic'); assert.deepEqual(await journal(),before);
  });

  await test('Two browser tabs retain their own project for writes, RNA, history, downloads and reload', async () => {
    const keyA = projectSpec('synthetic').bundleDigest, keyB = projectSpec('pbmc').bundleDigest;
    const tabB = await context.newPage();
    tabB.on('pageerror', error => report.pageErrors.push(error.message));
    tabB.on('dialog', dialog => dialog.accept());
    const bUI = id => tabB.locator('[data-testid="' + id + '"]');
    const bIdle = () => tabB.waitForFunction(() => !document.querySelector('[data-testid="project-select"]')?.disabled);
    try {
      await tabB.goto(origin, {waitUntil:'networkidle'}); await bIdle();
      await bUI('project-select').selectOption(keyB); await bIdle();
      assert.equal(await ui('project-select').inputValue(),keyA);
      const beforeB = await api('/api/export',undefined,200,'application/json',keyB);
      const probeA = await record('B alpha','Two-tab QC observation','proposed','QC');
      assert.deepEqual(await api('/api/export',undefined,200,'application/json',keyB),beforeB);
      await undo(probeA);
      const stableA = await journal();
      await bUI('cluster-6').click();
      await bUI('dimension').selectOption('QC');
      await bUI('label').fill('Two-tab QC observation');await bUI('reason').fill('This temporary observation belongs to PBMC alone.');
      await bUI('review-status').selectOption('proposed');await bUI('save-decision').click();await bIdle();
      const changedB = await api('/api/session',undefined,200,'application/json',keyB);
      assert.equal(changedB.events.length,beforeB.events.length+1);
      const probeB=changedB.events.at(-1);
      assert.equal(probeB.scope.datasetId,projectSpec('pbmc').projectId);
      assert.equal(probeB.scope.cellIds.length,155);
      assert.deepEqual(await journal(),stableA);
      await bUI('evidence-history').click();await bUI('undo-'+probeB.id).click();
      await tabB.locator('#undo-reason').fill('Undo the scoped PBMC probe; leave the other project intact.');
      await tabB.locator('#confirm-undo').click();await bIdle();
      await selectCluster('001');await ui('evidence-directed').click();
      await ui('directed-evidence').waitFor({state:'visible'});
      await bUI('evidence-directed').click();await bUI('directed-evidence').waitFor({state:'visible'});
      assert.match(await ui('directed-plan').textContent(),/24/);
      assert.match(await bUI('directed-plan').textContent(),/155/);
      const fileA=path.join(output,'tab-a-synthetic-review.json'),fileB=path.join(output,'tab-b-pbmc-review.json');
      await download('export-session',fileA);
      const pendingB=tabB.waitForEvent('download');await bUI('export-session').click();
      await(await pendingB).saveAs(fileB);await bIdle();
      assert.equal(JSON.parse(await fs.readFile(fileA,'utf8')).projectId,projectSpec('synthetic').projectId);
      assert.equal(JSON.parse(await fs.readFile(fileB,'utf8')).projectId,projectSpec('pbmc').projectId);
      report.syntheticJournal=fileA;report.pbmcJournal=fileB;
      await page.reload({waitUntil:'networkidle'});await waitIdle();
      await tabB.reload({waitUntil:'networkidle'});await bIdle();
      assert.equal(await ui('project-select').inputValue(),keyA);assert.equal(await bUI('project-select').inputValue(),keyB);
      assert.deepEqual(await journal(),stableA);
      assert.deepEqual(await api('/api/export',undefined,200,'application/json',keyB),JSON.parse(await fs.readFile(fileB,'utf8')));
      await screenshot('04b-two-tab-project-isolation');
    } finally {await tabB.close();}
  });

  await test('The actual browser journal writes back by every cell ID with original metadata, factors, NA and Idents preserved', async () => {
    const verified = await verifyR('synthetic',report.syntheticJournal,path.join(fixtureRoot,'sources','synthetic-processed.rds'));
    assert.equal(verified.cells,120); assert.equal(verified.perCellOracle.length,360);
    const typeStates = new Set(verified.perCellOracle.filter(row=>row.dimension==='type').map(row=>row.reviewState));
    assert.deepEqual([...typeStates].sort(),['abstained','deferred','labeled','unreviewed'].sort());
    assert.equal(verified.equivalents['permuted-equivalent'],'accepted; every cell matched by literal ID');
    assert.equal(verified.equivalents['dense-equivalent'],'accepted; every cell matched by literal ID');
    report.syntheticWriteback = verified;
    const wrapper = path.join(fixtureRoot,'sources','synthetic-agentseurat.rds');
    if(await fs.access(wrapper).then(()=>true,()=>false))
      report.wrapperWriteback = await verifyR('synthetic',report.syntheticJournal,wrapper,'agentseurat');
    const pbmcSource = args['pbmc-rds'] || process.env.SCAGENTKIT_QA_PBMC_RDS;
    assert(pbmcSource,'Supply --pbmc-rds or SCAGENTKIT_QA_PBMC_RDS for real per-cell writeback verification');
    const real = await verifyR('pbmc',report.pbmcJournal,path.resolve(pbmcSource));
    assert.equal(real.cells,2638); assert.equal(real.perCellOracle.filter(row=>row.dimension==='type'&&row.reviewState==='abstained').length,155);
    report.pbmcWriteback = {outcome:real.outcome,cells:real.cells,eventCount:real.eventCount,originalPreserved:real.originalPreserved};
  });

  await test('Explicit counts preparation preserves all low-depth cells and its genuine new embedding in the GUI', async () => {
    await ui('project-file').setInputFiles(projectSpec('prepared').archive);await waitIdle();
    const value=await evidence();
    assert.equal(value.projectId,projectSpec('prepared').projectId);assert.equal(value.dataset.retainedCells,60);
    assert.equal(value.identity.featureCount,500);assert.equal(value.umap.length,60);
    const cells=value.clusters.flatMap(row=>row.cellIds);
    assert(cells.includes('rawcell001'));assert(cells.includes('rawcell002'));
    assert(value.parameters.prepare);
    assert.equal(value.summary.modelStatus,'not_run');
    await screenshot('04c-explicit-counts-preparation');
    await selectProject('synthetic');
  });

  await test('Damaged hashes, rehashed invalid scopes, duplicate keys and unknown journal versions cannot alter saved history', async () => {
    const before = await journal();
    const tampered = structuredClone(before); tampered.events[0].payload += ' ';
    await api('/api/import',tampered,422); assert.deepEqual(await journal(),before);
    const scope = structuredClone(before), event = parsedEvent(scope.events[0]);
    event.scope.cellIds.pop(); scope.events[0].payload = JSON.stringify(event); rehash(scope);
    await api('/api/import',scope,422); assert.deepEqual(await journal(),before);
    await api('/api/import',{...before,schema:'unsupported.v99'},422);
    await api('/api/import',JSON.stringify(before).replace('{','{"schema":"scagentkit.review-journal.v1",'),422);
    assert.deepEqual(await journal(),before);
  });

  await test('Fresh project ZIP import honestly exposes missing embedding and model evidence and renders names as text', async () => {
    const archive = projectSpec('noEmbedding').archive;
    await ui('project-file').setInputFiles(archive); await waitIdle();
    assert.equal((await evidence()).projectId,projectSpec('noEmbedding').projectId);
    await ui('embedding-unavailable').waitFor({state:'visible'});
    await ui('evidence-models').click(); await ui('models-not-run').waitFor({state:'visible'});
    await ui('evidence-directed').click(); await ui('directed-unavailable').waitFor({state:'visible'});
    assert.equal(await page.evaluate(()=>window.__projectXss),undefined);
    assert.equal(await page.locator('img[src="x"]').count(),0);
    assert.equal((await session()).events.length,0);
    await screenshot('05-no-embedding-no-models');
  });

  await test('Unsafe ZIPs and oversized HTTP upload declarations reject without changing selection or journals', async () => {
    const bad = await makeAdversarialZips(), prior = await projects(), before = await journal();
    await ui('project-file').setInputFiles(path.join(bad,'traversal.zip')); await waitIdle();
    assert.match(await ui('error-banner').textContent(),/rejected|unsafe|path/i);
    for(const name of ['absolute','drive','duplicate','case-collision','symlink','unlisted','checksum','ratio','unknown-schema','duplicate-key']) {
      await api('/api/project/import',await fs.readFile(path.join(bad,name+'.zip')),name==='ratio'?413:422,'application/zip');
      assert.deepEqual(await journal(),before); assert.deepEqual(await projects(),prior);
    }
    const code = await new Promise((resolve,reject)=>{
      const request=http.request(origin+'/api/project/import',{method:'POST',headers:{'Content-Type':'application/zip','Content-Length':64*1024*1024+1,Origin:origin}},response=>{response.resume();response.on('end',()=>resolve(response.statusCode));});
      request.on('error',reject); request.setTimeout(5000,()=>request.destroy(new Error('Upload limit response timeout')));request.end();
    });
    assert.equal(code,413); assert.deepEqual(await journal(),before); assert.deepEqual(await projects(),prior);
  });

  await test('Changed cached evidence fails closed, clears drafts and preserves accepted history until exact bytes are restored', async () => {
    await selectProject('synthetic'); const before = await journal();
    const journalFile = path.join(journals, projectSpec('synthetic').bundleDigest + '.json');
    const journalBytes = await fs.readFile(journalFile);
    await selectCluster('001'); await ui('label').fill('Must not survive changed inputs'); await ui('reason').fill('Unsaved stale draft');
    const file = path.join(cache,projectSpec('synthetic').bundleDigest,'project.json'), bytes = await fs.readFile(file);
    try {
      await fs.appendFile(file,' ');
      await ui('refresh-evidence').click(); await waitIdle();
      const failed = await session();
      assert.equal(failed.readOnly,true); assert.equal(failed.stale,true);
      assert.equal(await ui('label').inputValue(),''); assert.equal(await ui('reason').inputValue(),'');
      await api('/api/export',undefined,422);
      assert.deepEqual(await fs.readFile(journalFile),journalBytes);
      assert.equal(await ui('save-decision').isDisabled(),true);
      await screenshot('06-stale-input-readonly');
    } finally {await fs.writeFile(file,bytes);}
    await ui('refresh-evidence').click(); await waitIdle();
    assert.equal((await session()).readOnly,false); assert.deepEqual(await journal(),before);
  });

  await test('Fresh server restart restores the selected project journal; narrow view stays local and usable', async () => {
    const before = await journal();
    await stopServer(); await startServer();
    await context.unroute('**/*');
    await context.route('**/*',async route=>{
      const url=new URL(route.request().url());
      if(url.origin===origin || ['data:','blob:'].includes(url.protocol))return route.continue();
      report.externalRequests.push(url.href);return route.abort('blockedbyclient');
    });
    await page.goto(origin,{waitUntil:'networkidle'});await waitIdle();await selectProject('synthetic');
    assert.deepEqual(await journal(),before);
    await page.setViewportSize({width:390,height:844});
    await ui('evidence-history').click();
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth+1));
    await screenshot('07-project-narrow-viewport',false);
    assert.deepEqual(report.pageErrors,[]);assert.deepEqual(report.externalRequests,[]);
  });
  report.outcome='passed';
} catch(error) {
  report.outcome='failed';report.error=error.stack||error.message;process.exitCode=1;
  if(page)await screenshot('failure').catch(()=>{});
  console.error(error.stack||error.message);
} finally {
  if(browser)await browser.close().catch(()=>{});
  await stopServer().catch(()=>{});
  report.finishedAt=new Date().toISOString();
  await fs.writeFile(path.join(output,'project-browser-report.json'),JSON.stringify(report,null,2));
  await fs.writeFile(path.join(output,'server.log'),logs.join(''));
  console.log('Project QA artifacts: '+output);
}
