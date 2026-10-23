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
async function reveal(locator) {
  while(!await locator.isVisible()){
    const closed=locator.locator('xpath=ancestor::details[not(@open)]').first();
    assert(await closed.count(),'Evidence must be visible or inside an expandable section');
    await closed.locator(':scope > summary').click();
  }
}
async function screenshot(name) {await page.screenshot({path:path.join(output,name+'.png'),fullPage:true});report.screenshots.push(name+'.png');}
async function fresh(allowBusy=false) {
  const received=page.waitForResponse(r=>r.request().method()==='GET' && (r.url().includes('/api/run-review/inspect') || r.url().includes('/api/run-review/scopes') && r.status()>=400));
  await ui('run-refresh').click();const res=await received;
  if(res.status()===409){
    const body=await res.json(),reason=typeof body.error==='string'?body.error:'Missing coordinator error';
    const route=new URL(res.url()).pathname;
    const transientLock=allowBusy && ['/api/run-review/scopes','/api/run-review/inspect'].includes(route) && /Project is locked[. :]/i.test(reason);
    (report.read_conflicts??=[]).push({path:route,status:409,error:reason,transient_lock:transientLock});
    assert(transientLock,'Unexpected read conflict: '+reason);
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
async function untilBoundary(startRevision,jobId) {
  // Follow the browser's native continuation poll. Repeated manual Refresh
  // during a running worker can intentionally reject a cross-revision view.
  await page.waitForFunction(({startRevision,jobId})=>{
    const section=document.getElementById('run-continuation');
    const id=document.getElementById('run-job-id')?.textContent.trim();
    const status=document.getElementById('run-status')?.getAttribute("data-engine-status").trim()||'';
    const revision=Number((document.getElementById('run-project')?.textContent||'').match(/revision (\d+)/)?.[1]);
    return id===jobId && ['succeeded','failed','interrupted','timed_out'].includes(section?.dataset.jobStatus) &&
      !document.getElementById('run-refresh').disabled && revision>startRevision &&
      /^(awaiting_review|awaiting_configuration|complete|failed) \/ /.test(status);
  },{startRevision,jobId},{timeout:10*60*1000,polling:250});
  const directory=path.join(output,'project','.workbench-jobs','jobs',jobId);
  const job=JSON.parse(await fs.readFile(path.join(directory,'job.json'),'utf8'));
  const owner=JSON.parse(await fs.readFile(path.join(directory,'owner.json'),'utf8'));
  assert.equal(job.status,'succeeded');assert.equal(owner.r_exit_code,0);
  assert.equal(await page.locator('#run-continuation').getAttribute('data-connection'),'verified');
  const run=await fresh();assert(run.revision>startRevision);
  assert(['awaiting_review','awaiting_configuration','complete','failed'].includes(run.status));
  (report.native_poll_boundaries??=[]).push({job_id:jobId,start_revision:startRevision,revision:run.revision,
    status:run.status,stage:run.stage,r_exit_code:owner.r_exit_code});
  return run;
}
async function approvals() {
  const history=JSON.parse(await fs.readFile(path.join(output,'project','decision_history.json'),'utf8'));
  return history.events.filter(event=>event.action==='approved');
}
function recommendationStep(id){const step=view.run.strategy_review.details.recommendations.steps.find(row=>row.id===id);assert(step,`Missing saved recommendation step ${id}`);return step;}
async function adoptAndSave(stepId,candidate) {
  assert.equal(candidate.available,true);
  const run=structuredClone(view.run), saved=run.strategy_review.details.canonical_proposal;
  const stateBytes=await fs.readFile(path.join(output,'project','state.rds'));
  const historyBytes=await fs.readFile(path.join(output,'project','decision_history.json'));
  const requestCount=requests.length,approvalCount=(await approvals()).length;
  await ui('recommendation-use-'+stepId+'-'+candidate.id).click();await wait(100);
  assert.equal(requests.length,requestCount,'Candidate adoption must make no POST request');
  assert.deepEqual(await fs.readFile(path.join(output,'project','state.rds')),stateBytes,'Local candidate must not change saved authority');
  assert.deepEqual(await fs.readFile(path.join(output,'project','decision_history.json')),historyBytes);
  const expected=structuredClone(saved), key={qc:'qc',pcs:'pcs',batch:'batch',resolution:'clustering'}[stepId];assert(key);
  if(stepId==='resolution')expected.clustering={...expected.clustering,...candidate.changes.clustering};else expected[key]=candidate.changes[key];
  assert.deepEqual(JSON.parse(await ui('strategy-json').inputValue()),expected);
  assert.notDeepEqual(expected,saved,'Fixture must exercise an actual local draft change');
  assert.equal(await ui('strategy-approve').isDisabled(),true);
  await screenshot('candidate-'+stepId+'-local-only');
  await ui('strategy-reviewer').fill('Offline real-browser acceptance author');
  await ui('strategy-reason').fill('Save the explicitly chosen local recommendation as a complete plan; this saving is not scientific approval.');
  await clickResponse('strategy-save','/api/run-review/decision');await fresh();
  assert.equal((await approvals()).length,approvalCount);
  assert.equal(view.run.input_hash,run.input_hash);
  assert.notEqual(view.run.review_node.proposal_hash,run.review_node.proposal_hash);
  assert.notEqual(view.run.strategy_review.hash,run.strategy_review.hash);
  assert.deepEqual(view.run.strategy_review.details.canonical_proposal,expected);
  (report.candidate_adoptions??=[]).push({step:stepId,candidate:candidate.id,no_post_on_adoption:true,
    saved_authority_unchanged_on_adoption:true,approval_count_before_save:approvalCount,
    old_review_hash:run.strategy_review.hash,new_review_hash:view.run.strategy_review.hash,
    old_proposal_hash:run.review_node.proposal_hash,new_proposal_hash:view.run.review_node.proposal_hash});
}
async function declarePartialStudyFacts() {
  const old=structuredClone(view.run),beforeApproved=(await approvals()).length;
  assert.equal(beforeApproved,0);
  const bool=ui('recommendation-fact-doublet-empty_droplets_removed'),unknown=bool;
  assert.deepEqual(await bool.locator('option').evaluateAll(nodes=>nodes.map(node=>node.value)),['','true','false']);
  assert.equal(await bool.inputValue(),'');assert.equal(await unknown.inputValue(),'');
  assert.equal(await unknown.getAttribute('required'),null,'Optional incomplete paths must not prevent partial fact saving');
  const beforePosts=requests.length;
  await ui('recommendation-fact-doublet-input_source').fill('Bundled pbmc_small software control; original called-cell provenance is unavailable.');
  assert.equal(requests.length,beforePosts,'Fact editing itself must remain local');
  assert.equal(await ui('strategy-approve').isDisabled(),true);
  await ui('recommendation-facts-reviewer').fill('Offline real-browser acceptance author');
  await ui('recommendation-facts-reason').fill('Declare the actual bundled input source. Keep unknown cell-calling and capture facts Unknown; no model or diagnostic deletion requested.');
  await screenshot('01-partial-batch-facts');
  const prepared=page.waitForResponse(res=>new URL(res.url()).pathname==='/api/run-review/continue'&&res.request().method()==='POST');
  const answer=await clickResponse('recommendation-facts-save','/api/run-review/decision');
  assert.equal(answer.run.status,'ready');assert(['prefilter','strategy_evidence'].includes(answer.run.stage));
  const response=await prepared;assert.equal(response.status(),202);const result=await response.json();
  report.jobs.push({job_id:result.job.job_id,purpose:'local-facts-preparation'});
  const current=await untilBoundary(answer.run.revision,result.job.job_id);assert.equal(current.status,'awaiting_review');assert.equal(current.review_node.kind,'strategy');
  assert.equal((await approvals()).length,0,'Fact saving and local preparation record no scientific approval');
  assert.equal(current.input_hash,old.input_hash);assert.notEqual(current.config_hash,old.config_hash);
  assert.notEqual(current.strategy_review.hash,old.strategy_review.hash);
  const rec=current.strategy_review.details.recommendations;
  assert.match(rec.fact_values.doublet.input_source,/Bundled pbmc_small/);assert.equal(rec.fact_values.doublet?.empty_droplets_removed??null,null);
  assert.equal(await ui('recommendation-fact-doublet-empty_droplets_removed').inputValue(),'');
  const doublet=recommendationStep('doublet');assert.equal(doublet.assessment,'unavailable');assert(doublet.missing.length>0);
  report.partial_facts={no_approval:true,retained_unknown_doublet:true,input_source_declared:true,
    old_config_hash:old.config_hash,new_config_hash:current.config_hash};
  await screenshot('01-facts-regenerated-unassessed-doublet');
}
async function approveStrategy() {
  await ui('strategy-reviewer').fill('Offline real-browser acceptance author');
  await ui('strategy-reason').fill('Inspect saved sample QC and actual PC/resolution evidence; approve only the displayed software fixture policy.');
  await clickResponse('strategy-approve','/api/run-review/decision');await fresh();
}
async function continueOnce() {
  const startRevision=view.run.revision;
  const before=requests.filter(x=>x.path==='/api/run-review/continue').length;
  const received=page.waitForResponse(r=>new URL(r.url()).pathname==='/api/run-review/continue' && r.request().method()==='POST');
  const box=await ui('run-continue').boundingBox();assert(box);
  // Two real pointer clicks: synchronous busy state must prevent the second run.
  await page.mouse.click(box.x+box.width/2,box.y+box.height/2);
  await page.mouse.click(box.x+box.width/2,box.y+box.height/2);
  const response=await received;assert.equal(response.status(),202);await wait(350);
  assert.equal(requests.filter(x=>x.path==='/api/run-review/continue').length-before,1,'Rapid duplicate click starts exactly one job');
  const result=await response.json();assert(result.job?.job_id);report.jobs.push({job_id:result.job.job_id});
  return untilBoundary(startRevision,result.job.job_id);
}
try {
  await test('matching installed archive starts the public entry without checkout or provider',async()=>{
    await r(args['sample-hvg']==='true'?'setup-hvg':'setup');launch=JSON.parse(await fs.readFile(path.join(output,'launch.json'),'utf8'));
    assert.equal(launch.archive_sha256,report.archive_sha256);assert.equal(launch.source_checkout,null);
    assert(launch.runtime.startsWith(launch.package+path.sep));assert(launch.launch.url);
    report.runtime=launch.runtime;report.package_version=launch.version;report.R=launch.R;
  });
  browser=await chromium.launch({headless:true,executablePath:args.chrome||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
  report.actual_browser=true;report.browser_version=browser.version();
  context=await browser.newContext({viewport:{width:1440,height:1080}});
  const origin=new URL(launch.launch.url).origin,preselectionOrigin=new URL(launch.preselection_launch.url).origin;
  await context.route('**/*',route=>{const u=route.request().url();if(u.startsWith(origin+'/')||u.startsWith(preselectionOrigin+'/')||u.startsWith('data:'))return route.continue();report.external_requests.push(u);return route.abort();});
  page=await context.newPage();page.on('pageerror',e=>report.page_errors.push(e.message));
  page.on('request',req=>{if(req.method()==='POST')requests.push({path:new URL(req.url()).pathname,body:req.postDataJSON()});});
  page.on('response',res=>{if(res.url().includes('/api/run-review/')) responses.push({path:new URL(res.url()).pathname,status:res.status()});});
  page.on('dialog',dialog=>dialog.accept());
  await test('QC keeps the saved conservative policy until an explicit candidate choice',async()=>{
    const statePath=path.join(output,'preselection-project','state.rds');
    const before=await fs.readFile(statePath),posts=requests.length;
    await page.goto(launch.preselection_launch.url);await ui('run-refresh').waitFor();
    await page.waitForFunction(()=>!document.getElementById('run-refresh').disabled);
    assert.equal(await ui('qc-draft-preselection-opt-in').count(),0);
    const draft=JSON.parse(await ui('strategy-json').inputValue());
    assert.equal(draft.qc.rules.find(rule=>rule.op==='mad_preset').preset_id,'conservative_and3');
    assert.equal(requests.length,posts,'Inspection cannot POST');
    assert.deepEqual(await fs.readFile(statePath),before,'Inspection cannot mutate authority');
    report.qc_policy={actual_browser:true,no_automatic_preselection:true,no_post:true,authority_unchanged:true};
    await screenshot('00-conservative-QC-policy');
  });
  await page.goto(launch.launch.url);await ui('run-refresh').waitFor();await fresh();
  await test('main entry exposes sample-aware QC, top-50 empirical PC policy and editable strategy',async()=>{
    const d=view.run.strategy_review?.details,p=d?.canonical_proposal;assert(d&&p);
    assert.equal(d.recommendations?.schema,'scagentkit.recommendations.v1','Main entry must expose the saved deterministic recommendation layer');
    assert.equal(await ui('strategy-recommendations').isVisible(),false);
    report.initial_layout=await page.evaluate(()=>({height:document.documentElement.scrollHeight,decision_top:document.getElementById('strategy-decision-form').getBoundingClientRect().top,storage_inside_model:document.getElementById('suggestion-disclosure').contains(document.getElementById('storage-refresh'))}));
    assert.equal(report.initial_layout.storage_inside_model,false);
    assert.equal(await ui('run-status').innerText(),'Review analysis plan and QC');
    await reveal(ui('strategy-recommendations'));
    assert.equal(await ui('strategy-recommendations').isVisible(),true);
    assert(d.mad_panel,'Main entry must attach the saved sample-aware MAD/QC panel');
    assert.equal(p.pcs.method,'computed_top50');assert.equal(p.pcs.threshold,.8);assert(p.analysis.npcs<=50);
    assert(Array.isArray(p.clustering.diagnostic_resolutions)&&p.clustering.diagnostic_resolutions.length>1,'Main entry must request several resolutions');
    await reveal(ui('pc-policy-note'));
    assert(/first|50|computed/i.test(await ui('pc-policy-note').innerText()));
    const qc=page.locator('#strategy-group-qc');
    if(await qc.count() && !await qc.getAttribute('open').then(x=>x!==null))await qc.locator(':scope > summary').click();
    report.initial_policy=p;await screenshot('01-main-strategy');
    const rec=d.recommendations;assert.equal(rec.binding.input_hash,view.run.input_hash);
    assert.equal(recommendationStep('qc').assessment,'assessed');
    assert(recommendationStep('qc').candidates.length>0);
    assert.equal(await ui('recommendations-next-decision').isVisible(),true);
    assert((await ui('recommendations-next-decision').innerText()).length>30);
    assert.equal(recommendationStep('doublet').assessment,'unavailable');
    assert.equal(await ui('recommendation-assessment-doublet').isVisible(),true);
    assert.equal(await ui('recommendation-step-qc').isVisible(),true);
    await declarePartialStudyFacts();
    await adoptAndSave('batch',recommendationStep('batch').candidates.find(candidate=>candidate.id==='none'&&candidate.available));
  });
  if(args['sample-hvg']==='true')await test('sample-consensus HVGs are edited and saved through the actual main strategy UI before approval',async()=>{
    assert.equal(launch.sample_hvg_mode,true);
    const plan=JSON.parse(await ui('strategy-json').inputValue()),before=structuredClone(view.run);
    plan.analysis={...plan.analysis,nfeatures:80,npcs:10,hvg_method:'sample_consensus',hvg_column:'acceptance_sample'};
    const count=(await approvals()).length;
    await reveal(ui('strategy-json'));await ui('strategy-json').fill(JSON.stringify(plan,null,2));
    assert.equal(await ui('strategy-approve').isDisabled(),true);
    await ui('strategy-reviewer').fill('Offline sample-HVG UI author');
    await ui('strategy-reason').fill('Explicit synthetic duplicated-count software control; save sample-consensus method without approval.');
    await clickResponse('strategy-save','/api/run-review/decision');await fresh();
    assert.equal((await approvals()).length,count);assert.equal(count,0);
    assert.notEqual(view.run.strategy_review.hash,before.strategy_review.hash);
    assert.equal(view.run.strategy_review.details.canonical_proposal.analysis.hvg_method,'sample_consensus');
    assert.equal(view.run.strategy_review.details.canonical_proposal.analysis.hvg_column,'acceptance_sample');
    await fs.writeFile(path.join(output,'hvg-ui-choice.json'),JSON.stringify({method:'sample_consensus',column:'acceptance_sample',nfeatures:80,npcs:10,explicit_save:true,approvals_at_save:count}));
    report.sample_hvg_ui={edited:true,separately_saved:true,approval_count_at_save:count,biological_effect_test:false};
    await screenshot('01-sample-hvg-saved-before-approval');
  });
  await test('author approval runs the real worker once and stops at measured cluster-tree review',async()=>{
    await approveStrategy();const run=await continueOnce();assert.equal(run.status,'awaiting_review');assert.equal(run.review_node.kind,'strategy');
    const d=run.strategy_review.details.cluster_diagnostics;assert(d?.tree?.nodes&&d.tree.edges);assert(d.resolutions.length>1);
    const optional=ui('recommendation-step-resolution').locator('details').filter({has:page.locator('summary',{hasText:'Optional local sensitivity, resampling and expression evidence'})}).first();
    await reveal(optional.locator(':scope > summary'));
    await optional.locator(':scope > summary').click();
    const optionalText=await optional.innerText();
    for(const field of ['pc_sensitivity','resampling','best_jaccard','resolution_extension'])assert(optionalText.includes(field),field+' must be visible at the measured strategy decision');
    report.optional_science_visible_at_measured_review=true;
    const tree=page.locator('.cluster-tree-evidence');await reveal(tree);
    const treeSVG=tree.locator('svg[aria-label="Shared cell transitions between scanned clustering resolutions"]');
    assert.equal(await treeSVG.isVisible(),true,'Measured cluster SVG must actually be visible');
    assert.equal(await treeSVG.locator('circle').count(),d.tree.nodes.length);
    assert.equal(await treeSVG.locator('line').count(),d.tree.edges.length);
    assert.equal(await tree.getByRole('columnheader',{name:'Shared cells',exact:true}).isVisible(),true);
    assert.equal(await tree.getByRole('heading',{name:'Cluster sample composition',exact:true}).isVisible(),true);
    for(const sample of ['offline_A','offline_B'])assert.equal(await tree.getByRole('cell',{name:sample,exact:true}).first().isVisible(),true);
    const markerDetails=tree.locator('details').first();await markerDetails.locator(':scope > summary').click();
    assert.equal(await markerDetails.getByRole('columnheader',{name:'Gene',exact:true}).isVisible(),true);
    assert.equal(await markerDetails.getByRole('columnheader',{name:'Detected outside',exact:true}).isVisible(),true);
    report.cluster_diagnostics=d;await screenshot('02-tree-visible');
    await reveal(ui('pc-candidates'));assert.equal(await ui('pc-status').getAttribute('data-status'),'computed');
    assert(/Computed PCs: \d+; reference PCs: \d+; shortfall: \d+/.test(await ui('pc-candidates').innerText()));
    assert(/not total expressed-gene variance/.test(await ui('pc-policy-note').innerText()));
    report.visible_pc_evidence=await ui('pc-candidates').innerText();await screenshot('02-computed-PC-evidence-visible');
    const candidates=recommendationStep('resolution').candidates;
    const selected=candidates.find(candidate=>candidate.available&&candidate.changes?.clustering?.resolution!==d.provisional_resolution);
    assert(selected,'An available measured alternative is required for this software fixture');
    const chosen=selected.changes.clustering.resolution;assert(d.resolutions.includes(chosen));
    await adoptAndSave('resolution',selected);
    report.author_resolution=view.run.strategy_review.details.canonical_proposal.clustering.resolution;
    assert.equal(report.author_resolution,chosen);
    await fs.writeFile(path.join(output,'author-selection.json'),JSON.stringify({resolution:chosen,scan_hash:d.hash})+'\n');
    await approveStrategy();
    const next=await continueOnce();assert.equal(next.stage,'annotation_propose');assert.equal(next.status,'awaiting_configuration');
  });
  await test('incomplete annotation draft survives refresh and cannot create a proposal or approval',async()=>{
    assert.equal(await ui('annotation-prepare-start').count(),0);
    await ui('annotation-prepare-form').waitFor();
    const label=page.locator('[data-testid^="prepare-label-"]').first();await label.fill('Unknown');
    const before=requests.length, revision=view.run.revision;
    await ui('prepare-submit').click();await wait(200);assert.equal(requests.length,before,'Native/UI validation prevents incomplete submission');
    const downloaded=page.waitForEvent('download');await ui('prepare-download').click();
    const download=await downloaded, worksheet=path.join(output,'unfinished-worksheet.json');await download.saveAs(worksheet);
    await page.reload();await ui('prepare-recovery').waitFor();
    assert(/restored/i.test(await ui('prepare-recovery').textContent()));
    assert.equal(await page.locator('[data-testid^="prepare-label-"]').first().inputValue(),'Unknown');
    await fresh();assert.equal(view.run.revision,revision);assert.equal(view.run.annotation_review??null,null);
    await page.evaluate(()=>sessionStorage.clear());await page.reload();await ui('annotation-prepare-form').waitFor();
    await page.waitForFunction(()=>!document.getElementById('run-refresh').disabled);
    assert.equal(await page.locator('[data-testid^="prepare-label-"]').first().inputValue(),'');
    await ui('prepare-import').setInputFiles(worksheet);
    await page.waitForFunction(()=>document.getElementById('run-message').textContent.includes('Unfinished worksheet imported'));
    assert.equal(await page.locator('[data-testid^="prepare-label-"]').first().inputValue(),'Unknown');
    const foreign=JSON.parse(await fs.readFile(worksheet,'utf8'));foreign.worksheet.binding[0]='another-project';
    const foreignPath=path.join(output,'foreign-worksheet.json');await fs.writeFile(foreignPath,JSON.stringify(foreign));
    await ui('prepare-import').setInputFiles(foreignPath);
    await page.waitForFunction(()=>document.getElementById('run-message').textContent.includes('Current rows were retained'));
    assert.equal(await page.locator('[data-testid^="prepare-label-"]').first().inputValue(),'Unknown');
    assert.equal(requests.length,before,'Worksheet download and import are local and non-authoritative');
    report.worksheet_portability={downloaded:true,imported_after_tab_storage_cleared:true,foreign_project_rejected:true,no_post:true};
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
    const submitted=page.waitForResponse(res=>new URL(res.url()).pathname==='/api/run-review/continue'&&res.request().method()==='POST');
    const approved=await clickResponse('annotation-approve-continue','/api/run-review/decision');
    const response=await submitted;assert.equal(response.status(),202);const started=await response.json();
    report.jobs.push({job_id:started.job.job_id,purpose:'annotation-approve-and-continue'});
    const completed=await untilBoundary(approved.run.revision,started.job.job_id);assert.equal(completed.status,'complete');await r('verify');
    report.verification=JSON.parse(await fs.readFile(path.join(output,'r-output-verification.json'),'utf8'));
    assert.equal(report.verification.provider_calls,0);report.provider_calls=report.verification.provider_calls;
    for(const job of report.jobs){
      const directory=path.join(output,'project','.workbench-jobs','jobs',job.job_id);
      const owner=JSON.parse(await fs.readFile(path.join(directory,'owner.json'),'utf8'));
      const config=JSON.parse(await fs.readFile(path.join(directory,'config.json'),'utf8'));
      assert(owner.worker_pid>0&&owner.r_pid>0&&owner.worker_pid!==owner.r_pid);assert.equal(owner.r_exit_code,0);
      assert(config.bridge.startsWith(launch.runtime+path.sep));job.owner=owner;job.bridge=config.bridge;
    }
    report.actual_R_workers=true;
    assert.equal(report.verification.approval_kinds.filter(kind=>kind==='strategy').length,2);
    assert.equal(report.verification.approval_kinds.filter(kind=>kind==='annotation').length,1);
    assert.equal(await ui('run-scientific-assessment').isVisible(),true);
    assert.equal(await ui('scientific-unassessed-steps').isVisible(),true);
    assert((await ui('scientific-unassessed-steps').innerText()).includes('doublet'));
    assert.equal(await ui('scientific-unresolved-steps').isVisible(),true);
    report.final_scientific_banner=await ui('run-scientific-assessment').innerText();
    await screenshot('05-completed');
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
  if(launch?.preselection_launch?.pid)try{process.kill(launch.preselection_launch.pid,'SIGTERM');}catch{}
  report.finished_at=new Date().toISOString();report.browser_responses=responses;
  // Request bindings are retained for reproducibility, never CSRF tokens/headers.
  report.browser_requests=requests;
  await fs.writeFile(path.join(output,'browser-report.json'),JSON.stringify(report,null,2)+'\n');
}
