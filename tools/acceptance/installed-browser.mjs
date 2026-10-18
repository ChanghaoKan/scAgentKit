#!/usr/bin/env node
/** Actual Chrome acceptance of a matching installed source archive.
 * No implementation sourcing, request simulation, direct scientific HTTP calls,
 * provider calls, downloaded data, or checkout runtime. Evidence stays external.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const args = {};
for (let i=2;i<process.argv.length;i+=2) {
  assert(process.argv[i].startsWith('--') && process.argv[i+1], 'Use --name value pairs');
  args[process.argv[i].slice(2)] = process.argv[i+1];
}
for (const key of ['archive','r-library','output']) assert(args[key], `Missing --${key}`);
const output=path.resolve(args.output), archive=path.resolve(args.archive);
await fs.mkdir(output,{recursive:true});
assert.equal(await fs.access(path.join(output,'browser-report.json')).then(()=>true,()=>false),false,'Use a fresh evidence directory');
const script=path.join(path.dirname(fileURLToPath(import.meta.url)),'installed-browser-fixture.R');
const env={...process.env,R_LIBS_USER:path.resolve(args['r-library']),R_LIBS:args['dependency-library']||process.env.R_LIBS||'',PYTHONDONTWRITEBYTECODE:'1'};
for (const key of Object.keys(env)) if (/API_KEY|TOKEN|SECRET|PASSWORD|SCAGENTKIT_CHECKOUT/.test(key)) delete env[key];
const report={started_at:new Date().toISOString(),archive_sha256:crypto.createHash('sha256').update(await fs.readFile(archive)).digest('hex'),
  actual_browser:false,actual_R_workers:false,source_checkout:null,provider_calls:null,scientific_accuracy_tested:false,
  tests:[],screenshots:[],external_requests:[],page_errors:[],jobs:[]};
let browser,context,page,launch,view;const responses=[],requests=[];
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const require=createRequire(import.meta.url);
const {chromium}=require(args.playwright||'/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright');
const ui=id=>page.getByTestId(id);
async function r(action) {
  const log=await fs.open(path.join(output,`R-${action}.log`),'wx');
  try {await new Promise((resolve,reject)=>{
    const child=spawn(args.rscript||'Rscript',['--vanilla',script,action,output,args['r-library'],archive],{env,stdio:['ignore',log.fd,log.fd]});
    child.once('error',reject);child.once('exit',code=>code===0?resolve():reject(new Error(`R ${action} exited ${code}; see R-${action}.log`)));
  });} finally {await log.close();}
}
async function test(name,fn) {const begin=Date.now();try{await fn();report.tests.push({name,status:'passed',milliseconds:Date.now()-begin});console.log('PASS '+name);}catch(e){report.tests.push({name,status:'failed',error:e.message});throw e;}}
async function screenshot(name) {await page.screenshot({path:path.join(output,name+'.png'),fullPage:true});report.screenshots.push(name+'.png');}
async function fresh(allowBusy=false) {
  const received=page.waitForResponse(r=>r.request().method()==='GET' && (r.url().includes('/api/run-review/inspect') || r.url().includes('/api/run-review/scopes') && r.status()>=400));
  await ui('run-refresh').click();const res=await received;
  if(allowBusy && res.status()===409 && res.url().includes('/scopes')) {
    await page.waitForFunction(()=>!document.getElementById('run-refresh').disabled);return null;
  }
  assert.equal(res.status(),200);
  view=await res.json();await page.waitForFunction(()=>!document.getElementById('run-refresh').disabled);return view.run;
}
async function clickResponse(id,suffix) {
  const received=page.waitForResponse(r=>new URL(r.url()).pathname===suffix && r.request().method()==='POST');
  await ui(id).click();const res=await received;assert(res.status()>=200&&res.status()<300,await res.text());
  const result=await res.json();if(result.run)view=result;return result;
}
async function untilBoundary() {
  const deadline=Date.now()+10*60*1000;
  while(Date.now()<deadline){
    const run=await fresh(true);
    if(run && ['awaiting_review','awaiting_configuration','complete','failed'].includes(run.status))return run;
    await wait(1000);
  }throw new Error('Real R worker did not reach review/configuration/completion in ten minutes');
}
async function approveStrategy() {
  await ui('strategy-reviewer').fill('Offline real-browser acceptance author');
  await ui('strategy-reason').fill('Inspect saved sample QC and actual PC/resolution evidence; approve only the displayed software fixture policy.');
  await clickResponse('strategy-approve','/api/run-review/decision');await fresh();
}
async function continueOnce() {
  const before=requests.filter(x=>x.path==='/api/run-review/continue').length;
  const received=page.waitForResponse(r=>new URL(r.url()).pathname==='/api/run-review/continue' && r.request().method()==='POST');
  const box=await ui('run-continue').boundingBox();assert(box);
  // Two real pointer clicks: synchronous busy state must prevent the second run.
  await page.mouse.click(box.x+box.width/2,box.y+box.height/2);
  await page.mouse.click(box.x+box.width/2,box.y+box.height/2);
  const response=await received;assert.equal(response.status(),202);await wait(350);
  assert.equal(requests.filter(x=>x.path==='/api/run-review/continue').length-before,1,'Rapid duplicate click starts exactly one job');
  const result=await response.json();assert(result.job?.job_id);report.jobs.push({job_id:result.job.job_id});
  return untilBoundary();
}
try {
  await test('matching installed archive starts the public entry without checkout or provider',async()=>{
    await r('setup');launch=JSON.parse(await fs.readFile(path.join(output,'launch.json'),'utf8'));
    assert.equal(launch.archive_sha256,report.archive_sha256);assert.equal(launch.source_checkout,null);
    assert(launch.runtime.startsWith(launch.package+path.sep));assert(launch.launch.url);
    report.runtime=launch.runtime;report.package_version=launch.version;report.R=launch.R;
  });
  browser=await chromium.launch({headless:true,executablePath:args.chrome||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
  report.actual_browser=true;report.browser_version=browser.version();
  context=await browser.newContext({viewport:{width:1440,height:1080}});
  const origin=new URL(launch.launch.url).origin;
  await context.route('**/*',route=>{const u=route.request().url();if(u.startsWith(origin+'/')||u.startsWith('data:'))return route.continue();report.external_requests.push(u);return route.abort();});
  page=await context.newPage();page.on('pageerror',e=>report.page_errors.push(e.message));
  page.on('request',req=>{if(req.method()==='POST')requests.push({path:new URL(req.url()).pathname,body:req.postDataJSON()});});
  page.on('response',res=>{if(res.url().includes('/api/run-review/')) responses.push({path:new URL(res.url()).pathname,status:res.status()});});
  page.on('dialog',dialog=>dialog.accept());
  await page.goto(launch.launch.url);await ui('run-refresh').waitFor();await fresh();
  await test('main entry exposes sample-aware QC, top-50 empirical PC policy and editable strategy',async()=>{
    const d=view.run.strategy_review?.details,p=d?.canonical_proposal;assert(d&&p);
    assert(d.mad_panel,'Main entry must attach the saved sample-aware MAD/QC panel');
    assert.equal(p.pcs.method,'computed_top50');assert.equal(p.pcs.threshold,.8);assert(p.analysis.npcs<=50);
    assert(Array.isArray(p.clustering.diagnostic_resolutions)&&p.clustering.diagnostic_resolutions.length>1,'Main entry must request several resolutions');
    assert(/first|50|computed/i.test(await ui('pc-policy-note').textContent()));
    report.initial_policy=p;await screenshot('01-main-strategy');
  });
  await test('author approval runs the real worker once and stops at measured cluster-tree review',async()=>{
    await approveStrategy();const run=await continueOnce();assert.equal(run.status,'awaiting_review');assert.equal(run.review_node.kind,'strategy');
    const d=run.strategy_review.details.cluster_diagnostics;assert(d?.tree?.nodes&&d.tree.edges);assert(d.resolutions.length>1);
    assert(await page.locator('svg').count()>0,'Measured cluster tree must be rendered');
    report.cluster_diagnostics=d;await screenshot('02-measured-cluster-tree');
    const chosen=d.resolutions.find(x=>x!==d.provisional_resolution)??d.resolutions[0];
    const control=page.locator('#clustering-resolution');
    while(!await control.isVisible()){
      const closed=control.locator('xpath=ancestor::details[not(@open)]').first();
      assert(await closed.count(),'Resolution control must be visible or inside an expandable section');
      await closed.locator(':scope > summary').click();
    }
    await control.fill(String(chosen));
    await ui('strategy-reviewer').fill('Offline real-browser acceptance author');
    await ui('strategy-reason').fill('Choose this scanned resolution after inspecting measured cluster relationships; this is software acceptance, not biological optimization.');
    if(await ui('strategy-save').isEnabled())await clickResponse('strategy-save','/api/run-review/decision');
    await fresh();report.author_resolution=view.run.strategy_review.details.canonical_proposal.clustering.resolution;
    assert.equal(report.author_resolution,chosen);
    await fs.writeFile(path.join(output,'author-selection.json'),JSON.stringify({resolution:chosen,scan_hash:d.hash})+'\n');
    await approveStrategy();
    const next=await continueOnce();assert.equal(next.stage,'annotation_propose');assert.equal(next.status,'awaiting_configuration');
  });
  await test('incomplete annotation draft survives refresh and cannot create a proposal or approval',async()=>{
    await ui('annotation-prepare-start').click();
    const label=page.locator('[data-testid^="prepare-label-"]').first();await label.fill('Unknown');
    const before=requests.length, revision=view.run.revision;
    await ui('prepare-submit').click();await wait(200);assert.equal(requests.length,before,'Native/UI validation prevents incomplete submission');
    await page.reload();await ui('prepare-recovery').waitFor();
    assert(/restored/i.test(await ui('prepare-recovery').textContent()));
    assert.equal(await page.locator('[data-testid^="prepare-label-"]').first().inputValue(),'Unknown');
    await fresh();assert.equal(view.run.revision,revision);assert.equal(view.run.annotation_review,null);
    await screenshot('03-restored-incomplete-worksheet');
  });
  await test('complete manual Unknown proposal saves separately from approval and finishes once',async()=>{
    const labels=page.locator('[data-testid^="prepare-label-"]');
    for(let i=0;i<await labels.count();i++){
      const id=(await labels.nth(i).getAttribute('data-testid')).slice('prepare-label-'.length);
      await ui('prepare-label-'+id).fill('Unknown');await ui('prepare-confidence-'+id).selectOption('low');
      await ui('prepare-rationale-'+id).fill('Offline software control: no independent biological label truth; retain Unknown.');
    }
    await ui('prepare-reviewer').fill('Offline real-browser acceptance author');await ui('prepare-reason').fill('Complete unresolved labels for software control; no marker semantic accuracy claim.');
    await clickResponse('prepare-submit','/api/run-review/decision');await fresh();
    assert.equal(view.run.status,'awaiting_review');assert.equal(view.run.review_node.kind,'annotation');assert.equal(view.run.output,null);
    await screenshot('04-saved-unapproved-annotation');
    await ui('annotation-reviewer').fill('Offline real-browser acceptance author');await ui('annotation-reason').fill('Approve the exact saved Unknown labels and cluster membership for software acceptance.');
    await clickResponse('annotation-approve','/api/run-review/decision');await fresh();
    const completed=await continueOnce();assert.equal(completed.status,'complete');await r('verify');
    report.verification=JSON.parse(await fs.readFile(path.join(output,'r-output-verification.json'),'utf8'));
    assert.equal(report.verification.provider_calls,0);report.provider_calls=report.verification.provider_calls;
    for(const job of report.jobs){
      const directory=path.join(output,'project','.workbench-jobs','jobs',job.job_id);
      const owner=JSON.parse(await fs.readFile(path.join(directory,'owner.json'),'utf8'));
      const config=JSON.parse(await fs.readFile(path.join(directory,'config.json'),'utf8'));
      assert(owner.worker_pid>0&&owner.r_pid>0&&owner.worker_pid!==owner.r_pid);assert.equal(owner.r_exit_code,0);
      assert(config.bridge.startsWith(launch.runtime+path.sep));job.owner=owner;job.bridge=config.bridge;
    }
    report.actual_R_workers=true;await screenshot('05-completed');
  });
  await test('installed public entry reopens completed project without another run or mutation',async()=>{
    const before=report.verification;await r('reopen');const reopened=JSON.parse(await fs.readFile(path.join(output,'reopen.json'),'utf8'));
    assert.equal(reopened.view.status,'complete');assert.equal(reopened.view.revision,before.view.revision);
    await page.goto(reopened.launch.url);await ui('run-refresh').waitFor();await fresh();
    assert.equal(await ui('run-continue').isDisabled(),true);assert.equal(view.run.status,'complete');
    assert.equal(view.run.history_head,before.view.history_head);await screenshot('06-reopened');
  });
  assert.deepEqual(report.page_errors,[]);assert.deepEqual(report.external_requests,[]);report.status='passed';
} catch(e){report.status='failed';report.error=e.stack;console.error(e.stack);process.exitCode=1;if(page)await screenshot('failure').catch(()=>{});}
finally {
  await context?.close().catch(()=>{});await browser?.close().catch(()=>{});
  // Terminate only the service created for this fresh private project.
  if(launch?.launch?.pid)try{process.kill(launch.launch.pid,'SIGTERM');}catch{}
  report.finished_at=new Date().toISOString();report.browser_responses=responses;
  // Request bindings are retained for reproducibility, never CSRF tokens/headers.
  report.browser_requests=requests;
  await fs.writeFile(path.join(output,'browser-report.json'),JSON.stringify(report,null,2)+'\n');
}
