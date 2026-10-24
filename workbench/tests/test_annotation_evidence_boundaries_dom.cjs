// Inert DOM regression of the production renderer; not a real-browser claim.
const fs = require('fs'), vm = require('vm'), path = require('path'), assert = require('assert/strict');
const nodes = new Map();
function node(tag, text, attrs) { return {tag, text, attrs, children: [], append(...x) {this.children.push(...x);}, replaceChildren(...x) {this.children = x;}, addEventListener() {}}; }
const context = vm.createContext({document: {getElementById(id) {if (!nodes.has(id)) nodes.set(id, node('target')); return nodes.get(id);}}, window: {addEventListener(){},location:{search:''}}, URLSearchParams});
const source = fs.readFileSync(path.resolve(__dirname, '../../inst/workbench/static/review.js'), 'utf8');
vm.runInContext(source.replace(/\nload\(\);\s*$/, '\n'), context);
context.testNode = node;
vm.runInContext('element = testNode; table = (headings, rows) => ({headings,rows}); geneParagraph = (text, genes) => ({text,genes}); raw = value => ({raw:value});', context);
const joint = {schema:'scagentkit.joint-annotation-evidence.v1',clusterId:'0', database:{status:'matched',candidates:[{label:'Single',overlap:1,referenceSize:1,score:1},{label:'Broad',overlap:10,referenceSize:20,score:.5}]},current:{source:{kind:'manual'},citations:[]},expression_review:{interpretation:'pct2 is other cells; no negative-lineage panel.',records:[{gene:'LOW',direction:'lower_in_cluster',detection_difference:-.8}]},limitations:['Confidence is uncalibrated.']};
context.item = {clusterId:'0',joint_evidence:joint,proposal:{label:'Unknown',confidence:'low',rationale:'Unresolved',markers:[]}};
joint.database.enrichment={status:'measured',records:[{label:'Single',a:1,b:2,c:3,d:4,p_value:.2,p_adjusted:.4,universe_size:10}]};
joint.database.all_candidates=[{label:'Single',enrichment:[{p_value:.2,p_adjusted:.4,universe_size:10}]}];
context.expression={status:'measured',missing_genes:['ABSENT'],clusters:[{cluster:'0',genes:[{gene:'LOW',mean_log_normalized:1.25,pct_detected:.5}]}],cell_quality:[{cell_id:'local-cell',total_umi:100,high_count_flag:false}]};
vm.runInContext('state.view = {run:{annotation_review:{details:{measured_expression:expression}}}};', context);
assert.equal(vm.runInContext('renderJointEvidence(item)', context), true);
const rendered = JSON.stringify(nodes.get('annotation-joint-evidence'));
for (const text of ['1/1 ranks above 10/20 by coverage only','single-marker evidence (weak)','10 / 20','qualitative, uncalibrated','label semantics not validated','lower_in_cluster','-0.8']) assert(rendered.includes(text),text);
for (const text of ['annotation-marker-enrichment','p_adjusted','universe_size','annotation-measured-panels','mean_log_normalized','pct_detected','ABSENT','high_count_flag','missing background remains unavailable']) assert(rendered.includes(text),text);
delete joint.database.enrichment;
assert.equal(vm.runInContext('renderJointEvidence(item)', context), true);
const perCandidateRendered=JSON.stringify(nodes.get('annotation-joint-evidence'));
for(const text of ['Saved per-candidate native enrichment records','p_adjusted','universe_size'])assert(perCandidateRendered.includes(text),text);
console.log(JSON.stringify({passed:true, actualProductionRenderer:true, actualBrowser:false, modelCalls:0, cases:['absolute support and small denominator warning','qualitative confidence','saved negative-direction contrast without semantic validation','native Fisher background and BH fields visible','measured panel means, detection, missing genes and cell flags visible']}));
