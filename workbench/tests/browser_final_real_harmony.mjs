#!/usr/bin/env node
// Actual server + installed R + real Chrome. Revise only a synthetic saved strategy.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const evidence = path.resolve(repo, '../evidence'), project = path.join(evidence, 'browser-final-real-harmony-project-v2'), library = path.resolve(repo, '../r-library');
const output = path.join(evidence, 'browser-final-real-harmony.json');
const env = {...process.env, R_LIBS: library + ':/Users/kan/R/scagentkit-lib', R_LIBS_USER: library + ':/Users/kan/R/scagentkit-lib', R_PROFILE_USER: '/dev/null', R_ENVIRON_USER: '/dev/null', PYTHONDONTWRITEBYTECODE: '1'};
for (const name of Object.keys(env)) if (/(API_KEY|TOKEN|SECRET)$/.test(name)) delete env[name];
const report = {schema: 'scagentkit.real-harmony-browser-policy.v1', actualChrome: true, actualServer: true, actualRBridge: true, stubAPI: false, project, tests: [], requests: [], externalRequests: [], pageErrors: [], approved: false, resumed: false, scientificAnalysisExecuted: false, providerCalls: 0};
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
const checkpointsBefore = {};
for (const name of await fs.readdir(path.join(project, 'checkpoints'))) checkpointsBefore[name] = sha(await fs.readFile(path.join(project, 'checkpoints', name)));
const exists = name => fs.access(path.join(project, name)).then(() => true, () => false);
assert.equal(await exists('provider'), false);
const server = spawn('python3', [path.join(repo, 'workbench/server.py'), '--run-project', project, '--r-library', library, '--rscript', '/usr/local/bin/Rscript', '--port', '0'], {cwd: repo, env, stdio: ['ignore', 'pipe', 'pipe']});
let origin, browser, startup = '', errors = '';
server.stdout.on('data', bytes => {startup += bytes; origin = startup.match(/scAgentKit workbench: (http:\/\/127\.0\.0\.1:[0-9]+)/)?.[1] || origin;});
server.stderr.on('data', bytes => {errors = (errors + bytes).slice(-4000);});
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
try {
  for (let i = 0; !origin && i < 600; i++) {assert.equal(server.exitCode, null, errors); await pause(100);}
  assert(origin, 'Owned server did not start');
  report.origin = origin;
  const beforeResponse = await fetch(origin + '/api/run-review/inspect'), before = await beforeResponse.json();
  assert.equal(beforeResponse.status, 200, JSON.stringify(before)); assert.equal(before.run.strategy_review.details.canonical_proposal.batch.method, 'none');
  report.initialRevision = before.run.revision;
  const require = createRequire(import.meta.url), {chromium} = require(process.env.SCAGENTKIT_PLAYWRIGHT || '/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright');
  browser = await chromium.launch({executablePath: process.env.SCAGENTKIT_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true});
  const context = await browser.newContext({viewport: {width: 1440, height: 1100}});
  await context.route('**/*', route => {
    const request = route.request(), url = new URL(request.url());
    if (url.origin !== origin) {report.externalRequests.push(url.origin + url.pathname); return route.abort();}
    if (url.pathname.startsWith('/api/')) report.requests.push({path: url.pathname, method: request.method()});
    assert(!/\/continuation|\/suggestion/.test(url.pathname));
    return route.continue();
  });
  const page = await context.newPage(); page.on('pageerror', error => report.pageErrors.push(error.message));
  await page.goto(origin + '/review?project_id=' + encodeURIComponent(before.run.project_id));
  await page.waitForFunction(() => document.querySelector('#run-status').textContent.includes('awaiting_review') && !document.querySelector('#run-refresh').disabled, {timeout: 60000});
  const reveal = async locator => {for (const detail of await locator.locator('xpath=ancestor::details').all()) if (!await detail.evaluate(el => el.open)) await detail.locator(':scope > summary').click();};
  await reveal(page.locator('#harmony-method')); await page.locator('#harmony-method').selectOption('harmony');
  for (const [name, value] of Object.entries({group_by_vars: '["donor"]', theta: '2', lambda: '1', sigma: '.1', max_iter: '3', nclust: '4', reason: 'Software-only replicated donor nesting; embedding exploration, no condition-effect inference.'})) await page.locator('#harmony-' + name).fill(value);
  assert.equal(await page.locator('#harmony-nested-biology').inputValue(), 'block');
  await page.locator('#harmony-nested-biology').selectOption('reviewed_embedding_only');
  assert.equal(await page.locator('#strategy-approve').isDisabled(), true);
  assert.equal(report.requests.filter(r => r.method === 'POST').length, 0);
  report.tests.push({name: 'real-R-none-review-renders-and-explicit-choice-edits-only-draft', passed: true});
  await page.locator('#strategy-reviewer').fill('Software-only real Chrome acceptance');
  await page.locator('#strategy-reason').fill('Persist the reviewed nested policy only; do not approve or execute integration.');
  const responsePromise = page.waitForResponse(response => new URL(response.url()).pathname === '/api/run-review/decision' && response.request().method() === 'POST', {timeout: 120000});
  await page.locator('#strategy-save').click(); const response = await responsePromise, result = await response.json();
  assert.equal(response.status(), 200, JSON.stringify(result));
  assert.equal(result.run.status, 'awaiting_review'); assert.equal(result.run.stage, 'strategy_propose');
  assert.equal(result.run.strategy_review.details.canonical_proposal.batch.nested_biology, 'reviewed_embedding_only');
  assert.deepEqual([result.run.strategy_review.details.canonical_proposal.batch.group_by_vars].flat(), ['donor']);
  assert.equal(result.run.strategy_review.details.applicability.executable, true);
  assert(result.run.revision > before.run.revision); report.finalRevision = result.run.revision;
  report.savedBatch = result.run.strategy_review.details.canonical_proposal.batch;
  report.savedApplicability = result.run.strategy_review.details.applicability;
  await page.waitForFunction(() => !document.querySelector('#run-refresh').disabled && document.querySelector('#run-message').textContent.includes('Strategy revision'));
  await reveal(page.locator('#harmony-nested-biology')); assert.equal(await page.locator('#harmony-nested-biology').inputValue(), 'reviewed_embedding_only');
  report.tests.push({name: 'real-R-saves-policy-rebuilds-executable-review-without-approval', passed: true});
  const freshResponse = await fetch(origin + '/api/run-review/inspect'), fresh = await freshResponse.json();
  assert.equal(freshResponse.status, 200); assert.equal(fresh.run.strategy_review.details.canonical_proposal.batch.nested_biology, 'reviewed_embedding_only'); assert.equal(fresh.run.status, 'awaiting_review');
  for (const [name, hash] of Object.entries(checkpointsBefore)) assert.equal(sha(await fs.readFile(path.join(project, 'checkpoints', name))), hash);
  const names = await fs.readdir(path.join(project, 'checkpoints'));
  assert.equal(names.some(name => /^(strategy_basis|strategy_batch|analysis|output|annotation_applied)-/.test(name)), false);
  for (const name of ['provider', 'output', 'bundle', '.workbench-jobs']) assert.equal(await exists(name), false, name + ' must not be created by review only');
  const history = JSON.parse(await fs.readFile(path.join(project, 'decision_history.json'), 'utf8'));
  assert.equal((history.events || []).some(event => event.action === 'approved'), false);
  report.tests.push({name: 'fresh-real-R-inspect-persists-policy-and-upstream-checkpoints-unchanged', passed: true}, {name: 'no-analysis-output-provider-or-continuation-created', passed: true});
  report.checkpointsBefore = checkpointsBefore; report.checkpointsAfter = names;
  await page.screenshot({path: output.replace(/\.json$/, '.png'), fullPage: true});
  assert.deepEqual(report.pageErrors, []); assert.deepEqual(report.externalRequests, []); assert.equal(report.requests.filter(r => r.method === 'POST').length, 1);
  report.passed = report.tests.length; report.failed = 0;
} catch (error) {report.failed = 1; report.error = error.stack; throw error;}
finally {
  if (browser) await browser.close();
  if (server.exitCode === null) {server.kill('SIGTERM'); await Promise.race([new Promise(resolve => server.once('exit', resolve)), pause(3000)]);}
  await fs.writeFile(output, JSON.stringify(report, null, 2) + '\n'); console.log(JSON.stringify(report, null, 2));
}
