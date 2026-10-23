// Actual production helpers in an inert DOM; no browser/R/network/model claims.
const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),path=require('path');
const root=path.resolve(__dirname,'../..'),source=fs.readFileSync(path.join(root,'inst/workbench/static/review.js'),'utf8'),storage=new Map();
const element={addEventListener(){},contentWindow:{}};
const context=vm.createContext({document:{getElementById(){return element;}},window:{addEventListener(){},location:{search:''}},URLSearchParams,sessionStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v)}});
vm.runInContext(source.replace(/\nload\(\);\s*$/,'\n'),context);
const call=(name,...args)=>vm.runInContext(name,context)(...args),clone=x=>JSON.parse(JSON.stringify(x));
const cluster={clusterId:'literal:A',markers:[{gene:'OldA'},{gene:'LocalB'}],assistance:{schema:'scagentkit.annotation-assistance.v1',clusterId:'literal:A',provenance:{status:'matched'},reference:{clusterId:'literal:A',status:'matched',marker_symbols:{alias_resolutions:[{original:'OldA',canonical:'CanonicalA'}]},candidates:[{clusterId:'literal:A',label:'Broad lineage',score:1,overlap:1,referenceSize:1,markers:['CanonicalA','ForeignGene'],tiedBest:true},{clusterId:'literal:A',label:'Other lineage',score:1,overlap:1,referenceSize:1,markers:['LocalB'],tiedBest:true}]}}};
const empty={label:'',confidence:'',rationale:'',markers:[],touched:false,confirmed:false};
const chosen=call('preparationChoose',cluster,empty,0);assert.equal(chosen.label,'Broad lineage');assert.deepEqual(clone(chosen.markers),['OldA']);assert.equal(chosen.confidence,'');assert.equal(chosen.rationale,'');assert.equal(call('preparationConflict',cluster),true);
for(const row of [{...empty,touched:true},{...empty,confirmed:true},{...empty,label:'Human coarse label'},{...empty,rationale:'Human reasoning'},{...empty,markers:['LocalB']}])assert.equal(call('preparationChoose',cluster,row,0),null,'Never overwrite an existing/manual row');
const foreign=clone(cluster);foreign.assistance.reference.candidates[0].clusterId='literal:B';assert.throws(()=>call('preparationFacts',foreign),/scope/);
for(const status of ['scope_unavailable','no_overlap','not_supplied']){const x=clone(cluster);x.assistance.reference.status=status;assert.equal(call('preparationChoose',x,empty,0),null);}
const zero=clone(cluster);zero.assistance.reference.candidates[0].overlap=0;assert.equal(call('preparationCandidates',zero).length,1);
const externalOnly=clone(cluster);externalOnly.assistance.reference.candidates[0].markers=['ForeignGene'];assert.equal(call('preparationCandidates',externalOnly).length,1);
const p={project_id:'project',input_hash:'a'.repeat(64),expected_revision:4,evidence_hash:'b'.repeat(64),clusters:[cluster]};
const saved={binding:call('preparationBinding',p),rows:[{...chosen,clusterId:cluster.clusterId}],reviewer:"",reason:"",unknownReason:"",edited:true};storage.set(call('preparationKey',p),JSON.stringify(saved));assert(call('preparationRestore',p));assert.equal(call('preparationRestore',{...p,expected_revision:5}),null);assert.equal(call('preparationRestore',{...p,input_hash:'c'.repeat(64)}),null);
const overlong=clone(saved);overlong.rows[0].rationale='x'.repeat(4001);assert.throws(()=>call('preparationValidateDraft',overlong,p),/invalid annotation/);
const authority=clone(saved);authority.approved=true;assert.throws(()=>call('preparationValidateDraft',authority,p),/invalid fields/);
saved.rows[0].markers=['ForeignGene'];storage.set(call('preparationKey',p),JSON.stringify(saved));assert.equal(call('preparationRestore',p),null);
const state=vm.runInContext('state',context);state.view={run:{annotation_preparation:p}};state.preparationDraft={edited:true};assert.equal(call('preparationDirty'),true);state.preparationDraft.edited=false;assert.equal(call('preparationDirty'),false);
state.preparationDraft.edited=true;storage.set('another-bound-draft','preserve');call('discardPreparation',p);assert.equal(call('preparationDirty'),false);assert.equal(storage.get('another-bound-draft'),'preserve');assert.equal(call('preparationRestore',p),null);
console.log(JSON.stringify({passed:true,actualProductionSource:true,actualBrowser:false,actualRBridge:false,networkRequests:0,modelCalls:0,cases:['alias-to-original citations','foreign group rejected','manual row preserved','confidence and rationale blank','scope/zero-overlap unavailable','old revision not restored','foreign citation rejected','preparation dirty guard']}));
