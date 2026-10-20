// Actual Chrome + installed R bridge. Public mock project only; no paid requests.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {spawn} from 'node:child_process';
const args={};for(let i=2;i<process.argv.length;i+=2)args[process.argv[i].slice(2)]=process.argv[i+1];
for(const name of ['project','output','r-library','playwright','chrome'])assert(args[name]);
const output=path.resolve(args.output);await fs.mkdir(output,{recursive:true});
assert.equal(await fs.access(path.join(output,'report.json')).then(()=>true,()=>false),false);
const require=createRequire(import.meta.url),{chromium}=require(args.playwright);
const env={...process.env,R_LIBS_USER:args['r-library']};
for(const key of Object.keys(env))if(/API_KEY|TOKEN|SECRET/.test(key))delete env[key];
const port=args.port||'18765',origin=`http://127.0.0.1:${port}`;
const server=spawn('python3',['inst/workbench/server.py','--run-project',path.resolve(args.project),'--r-library',env.R_LIBS_USER,'--port',port,'--local-continue','--model-mock'],{env,stdio:['ignore','pipe','pipe']});
let log='',browser;server.stdout.on('data',b=>log+=b);server.stderr.on('data',b=>log+=b);
const report={actualChrome:true,actualRBridge:true,provider:'mock',paidCalls:0,gates:[],externalRequests:[],pageErrors:[]};
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function inspect(){const r=await fetch(origin+'/api/run-review/inspect');const body=await r.json();if(!r.ok){const message=JSON.stringify(body);if(/lock|busy|running|stale.*binding/i.test(message))return null;throw Error(`Inspect ${r.status}: ${message}`);}return body.run;}
try{
 let ready=false;for(let i=0;i<120;i++){try{const r=await inspect();assert(r);assert(['awaiting_review','awaiting_configuration'].includes(r.status));ready=true;break;}catch{}if(server.exitCode!==null)throw Error(log);await pause(500);}assert(ready,log);
 browser=await chromium.launch({headless:true,executablePath:args.chrome});const context=await browser.newContext({viewport:{width:1400,height:1000}});
 await context.route('**/*',route=>{if(new URL(route.request().url()).origin!==origin){report.externalRequests.push(route.request().url());return route.abort();}return route.continue();});
 const page=await context.newPage();page.on('pageerror',e=>report.pageErrors.push(e.message));
 await page.goto(origin+'/review');
 for(let gate=1;gate<=3;gate++){
  await page.waitForFunction(()=>{const b=document.querySelector('#suggestion-adopt');return b&&!b.hidden&&!b.disabled;},null,{timeout:180000});
  const before=await inspect();assert(['awaiting_review','awaiting_configuration'].includes(before.status));
  await page.locator('#suggestion-reviewer').fill('benchmark-policy:accept_drafts');
  await page.locator('#suggestion-reason').fill('Accept this public mock candidate unchanged for separate scientific review.');
  await page.locator('#suggestion-adopt').click();
  const kind=gate<3?'strategy':'annotation';
  await page.waitForFunction(id=>{const b=document.getElementById(id);return b&&!b.hidden&&!b.disabled;},`${kind}-approve-continue`,{timeout:60000});
  const adopted=await inspect();assert.equal(adopted.status,'awaiting_review');
  await page.locator(`#${kind}-reviewer`).fill('benchmark-policy:accept_drafts');
  await page.locator(`#${kind}-reason`).fill('Explicit scripted approval of the complete public mock draft; no biological claim.');
  await page.screenshot({path:path.join(output,`gate-${gate}.png`),fullPage:true});
  await page.locator(`#${kind}-approve-continue`).click();
  const deadline=Date.now()+180000;let after;
  while(Date.now()<deadline){await pause(1000);after=await inspect();if(after&&after.revision>adopted.revision&&(after.status==='complete'||(['awaiting_review','awaiting_configuration'].includes(after.status)&&JSON.stringify(after.completed)!==JSON.stringify(adopted.completed))))break;}
  assert(after&&(after.status==='complete'||(['awaiting_review','awaiting_configuration'].includes(after.status)&&JSON.stringify(after.completed)!==JSON.stringify(adopted.completed))));
  report.gates.push({gate,kind,beforeRevision:before.revision,adoptedRevision:adopted.revision,afterRevision:after.revision,status:after.status});
 }
 assert.equal((await inspect()).status,'complete');assert.equal(report.externalRequests.length,0);assert.equal(report.pageErrors.length,0);
 await page.waitForFunction(()=>document.querySelector('#run-status')?.textContent.startsWith('complete /'),null,{timeout:60000});
 await page.screenshot({path:path.join(output,'complete.png'),fullPage:true});report.passed=true;
}catch(e){report.passed=false;report.error=e.stack;process.exitCode=1;}
finally{if(browser)await browser.close();server.kill('SIGTERM');await fs.writeFile(path.join(output,'report.json'),JSON.stringify(report,null,2));await fs.writeFile(path.join(output,'server.log'),log);console.log(JSON.stringify(report));}
