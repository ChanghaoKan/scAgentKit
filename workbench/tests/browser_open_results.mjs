#!/usr/bin/env node
// Actual Chrome + actual installed R + actual read-only localhost service.
// Uses only an operator-supplied synthetic saved project; never resumes analysis.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const project = path.resolve(process.argv[2]), output = path.resolve(process.argv[3]);
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.SCAGENTKIT_PLAYWRIGHT || '/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright');
const env = {...process.env};
for (const key of Object.keys(env)) if (/API_?KEY|ACCESS_?KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL/i.test(key)) delete env[key];
const report = {actualChrome: true, actualR: true, actualHTTP: true, defaultOSBrowserDispatch: false,
  paidCalls: 0, externalRequests: [], assertions: [], pagesClosed: 0, pageErrors: []};
await fs.mkdir(output, {recursive:true});
const protectedFiles = [path.join(project,'state.rds'),path.join(project,'output/seurat.rds'),
  ...(await fs.readdir(path.join(project,'checkpoints'))).map(name => path.join(project,'checkpoints',name))];
const hashes = async () => Object.fromEntries(await Promise.all(protectedFiles.map(async file => [file, crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex')])));
const before = await hashes();
function reopen(first) {
  const expression = 'library(scAgentKit); a<-commandArgs(TRUE); x<-sc_run_open(a[1],checkout=if(a[2]=="first")a[3] else NULL,browse=FALSE); cat(jsonlite::toJSON(x,auto_unbox=TRUE),"\\n")';
  const child = spawnSync(process.env.SCAGENTKIT_RSCRIPT || 'Rscript', ['--vanilla','-e',expression,project,first?'first':'again',root], {env,encoding:'utf8',cwd:output,timeout:120000});
  assert.equal(child.status,0,child.stderr); return JSON.parse(child.stdout.trim().split('\n').at(-1));
}
let browser, live;
try {
  browser = await chromium.launch({executablePath:process.env.SCAGENTKIT_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
  const context = await browser.newContext({viewport:{width:1440,height:1000}});
  await context.route('**/*',route => {
    if (new URL(route.request().url()).hostname === '127.0.0.1') return route.continue();
    report.externalRequests.push(route.request().url()); return route.abort();
  });
  const first = reopen(true); live=first;
  for (const [index,view] of [[0,first],[1,null],[2,null]]) {
    if (index===1) {live=reopen(false);assert.equal(live.reused,true);assert.equal(live.pid,first.pid);report.assertions.push('independent-R-reuses-live-service-after-page-close');}
    if (index===2) {process.kill(live.pid,'SIGTERM');await new Promise(resolve=>setTimeout(resolve,300));live=reopen(false);assert.equal(live.reused,false);assert.notEqual(live.pid,first.pid);report.assertions.push('dead-service-restarted-and-page-reopened');}
    const page=await context.newPage();page.on('pageerror',error=>report.pageErrors.push(error.message));
    await page.goto(live.url,{waitUntil:'networkidle'});
    await page.waitForFunction(()=>typeof wbState!=='undefined' && (wbState.view!==null || wbState.failed),{timeout:60000});
    const state=await page.evaluate(()=>({failed:wbState.failed,id:wbState.projectId,status:wbState.view?.run?.status,readonly:wbState.view?.readonly}));
    assert.equal(state.failed,false);assert.equal(state.id,first.project_id);assert.equal(state.status,'complete');assert.equal(state.readonly,true);
    await page.screenshot({path:path.join(output,`page-${index+1}.png`),fullPage:true});
    report.assertions.push(`actual-result-page-${index+1}-complete-exact-project-readonly`);
    await page.close();report.pagesClosed++;
  }
  assert.deepEqual(await hashes(),before);report.assertions.push('authority-files-unchanged');
  assert.deepEqual(report.externalRequests,[]);assert.deepEqual(report.pageErrors,[]);
  report.projectId=first.project_id;report.outcome='passed';
} finally {
  if(live)try{process.kill(live.pid,'SIGTERM');}catch(error){if(error.code!=='ESRCH')throw error;}
  if(browser)await browser.close();
  await fs.writeFile(path.join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
}
console.log(JSON.stringify(report,null,2));
