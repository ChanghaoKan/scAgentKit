"""One frozen dataset: execute variants once, preserve failures, score original cells."""
import argparse,csv,json,os,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('evidence');p.add_argument('baseline_library');p.add_argument('after_library');p.add_argument('dataset',choices=['pbmc3k','ifnb','baron']);a=p.parse_args()
repo=Path(__file__).resolve().parents[2];scripts=Path(__file__).resolve().parent
e=Path(a.evidence).resolve();dataset=a.dataset;out=e/'comparison'/dataset;out.mkdir(parents=True,exist_ok=True)
input_dir=e/'prepared-v2'/dataset
reference='hpca' if dataset=='baron' else 'blueprint-encode'
env=os.environ.copy();env['R_LIBS_USER']=str(e/'optional-library')+':/Users/kan/R/scagentkit-lib'
for key in list(env):
 if any(x in key for x in ('API_KEY','TOKEN','SECRET','PASSWORD')):env.pop(key,None)
ledger=[]
def run(name,argv):
 log=out/(name+'.log');receipt=out/(name+'-process.json')
 if log.exists() or receipt.exists():raise RuntimeError('Refuse to repeat or overwrite '+name)
 start=time.time()
 print('START '+dataset+' '+name,flush=True)
 with log.open('x') as f:r=subprocess.run(argv,cwd=repo,env=env,stdin=subprocess.DEVNULL,stdout=f,stderr=subprocess.STDOUT)
 result=dict(name=name,argv=list(map(str,argv)),exit_code=r.returncode,elapsed=time.time()-start,peak_rss=None,
  resource_limit='Peak RSS not captured; no resource improvement claim. Concurrent local checks may affect wall time.')
 receipt.write_text(json.dumps(result,indent=2)+'\n');ledger.append(result)
 (out/'dataset-processes.json').write_text(json.dumps(ledger,indent=2)+'\n')
 print('FINISH '+dataset+' '+name+' exit='+str(r.returncode),flush=True)
 if r.returncode:raise RuntimeError('Preserved failure: '+name)
def evaluate(name,predictions,variant,reference_target=None):
 argv=['python3',str(scripts/'evaluate.py'),str(input_dir/'cells.txt'),str(predictions),str(scripts/'label-map.json'),dataset,str(out/variant/(name+'.json'))]
 if reference_target:argv+=['--reference',str(reference_target)]
 elif dataset!='pbmc3k':argv+=['--truth',str(input_dir/'truth.csv')]
 run(variant+'-'+name,argv)
variants=['baseline','after','after-no-diagnostics','after-qc-or']
if dataset=='baron':variants+=['after-sample-hvg']
else:
 (out/'sample-hvg-ineligible.json').write_text(json.dumps(dict(dataset=dataset,status='ineligible',reason='PBMC3k has one sample; IFNB has condition but no declared actual sample. Treatment is never a sample surrogate.'),indent=2)+'\n')
for variant in variants:
 # PBMC pair already executes separately: reuse only explicitly complete artifacts.
 name=variant+'-1';root=out/name
 if dataset=='pbmc3k' and variant in ('baseline','after'):
  receipt=json.loads((root/'run.json').read_text());assert receipt['status']=='complete'
 else:
  lib=Path(a.baseline_library if variant=='baseline' else a.after_library).resolve()
  run(name,['Rscript','--vanilla',str(scripts/'run_workflow.R'),str(input_dir/'input.rds'),str(root),str(lib),variant,str(e/'references'/(reference+'-markers.csv')),dataset])
 classifier=out/('singler-'+name)
 if dataset=='pbmc3k' and variant=='baseline':
  assert json.loads((classifier/'run.json').read_text())['cells']==2700
 else:
  run('singler-'+name,['Rscript','--vanilla',str(scripts/'run_singler.R'),str(root/'analysis.rds'),str(e/'references'/(reference+'.rds')),str(classifier)])
 with (root/'membership.csv').open(newline='') as f:membership=list(csv.DictReader(f))
 manual=root/'reviewed-labels.csv'
 with manual.open('x',newline='') as f:
  w=csv.DictWriter(f,fieldnames=['cell_id','label','status']);w.writeheader()
  w.writerows(dict(cell_id=r['cell_id'],label=r['reviewed_label'],status='explicit_unknown_control') for r in membership)
 evaluate('candidate-author-agreement',root/'reference-candidates.csv',name)
 evaluate('singler-author-agreement',classifier/'predictions.csv',name)
 evaluate('reviewed-control-agreement',manual,name)
 evaluate('candidate-reference-agreement',root/'reference-candidates.csv',name,out/'singler-baseline-1'/'predictions.csv')
print('DATASET COMPLETE '+dataset,flush=True)
