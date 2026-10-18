// Synthetic renderer contract only; actual installed browser acceptance is separate.
const fs = require('fs'), vm = require('vm'), path = require('path'), assert = require('assert/strict');
function node(tag) {return {tag,children:[],attributes:{},style:{},append(...x){this.children.push(...x)},setAttribute(k,v){this.attributes[k]=v},addEventListener(){},replaceChildren(){}};}
const context = vm.createContext({document:{getElementById(){return node('root')},createElement:node,createElementNS(ns,tag){return node(tag)}},window:{addEventListener(){},location:{search:''}},URLSearchParams});
const source = fs.readFileSync(path.resolve(__dirname,'../../inst/workbench/static/review.js'),'utf8');
vm.runInContext(source.replace(/\nload\(\);\s*$/, '\n'),context);
context.scan = {interpretation:'Author approves; no model dispatch',resolutions:[.2,.6],tree:{interpretation:'Sensitivity is not biological stability',nodes:[{id:'1:0',resolution:.2,cluster:'<script>bad</script>',cells:4,sample_counts:[{value:'sample A',cells:4}]},{id:'2:0',resolution:.6,cluster:'0',cells:4,sample_counts:[]}],edges:[{source:'1:0',target:'2:0',cells:4,source_fraction:1,target_fraction:1}]},markers:{'0.2':{status:'measured',limitation:'No independent validation',markers:[{clusterId:'0',gene:'Gene',avgLog2FC:2,pct1:.8,pct2:.1,pAdj:.001}]}}};
const output = vm.runInContext('renderClusterTree(scan)',context), serialized = JSON.stringify(output);
for(const text of ['svg','Shared cell transitions','Source fraction','sample A','Gene','not biological stability','<script>bad</script>']) assert(serialized.includes(text),text);
assert.equal(output.children.find(n=>n?.tag==='div').style.overflowX,'auto');
console.log('PASS: production cluster-tree SVG, transition table, sample composition, marker evidence, literal labels; no browser/model/network claim.');
