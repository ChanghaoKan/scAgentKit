"""One frozen dataset: execute variants once, preserve failures, score original cells."""
import argparse,csv,hashlib,json,os,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('evidence');p.add_argument('baseline_library');p.add_argument('after_library');p.add_argument('dataset',choices=['pbmc3k','ifnb','baron']);p.add_argument('--after-directory',help='Explicit verified PBMC stopped-snapshot finalization directory; changes storage only, never analysis criteria');a=p.parse_args()
repo=Path(__file__).resolve().parents[2];scripts=Path(__file__).resolve().parent
e=Path(a.evidence).resolve();dataset=a.dataset;out=e/'comparison'/dataset;out.mkdir(parents=True,exist_ok=True)
input_dir=e/'prepared-v2'/dataset
reference='hpca' if dataset=='baron' else 'blueprint-encode'
env=os.environ.copy();env['R_LIBS_USER']=str(e/'optional-library')+':/Users/kan/R/scagentkit-lib'
for key in list(env):
 if any(x in key for x in ('API_KEY','TOKEN','SECRET','PASSWORD')):env.pop(key,None)
ledger_path=out/'dataset-processes.json'
ledger=json.loads(ledger_path.read_text()) if ledger_path.exists() else []
def run(name,argv):
 log=out/(name+'.log');receipt=out/(name+'-process.json')
 if log.exists() or receipt.exists():
  if log.exists() and receipt.exists():
   saved=json.loads(receipt.read_text())
   if saved['exit_code']==0 and saved['argv']==list(map(str,argv)):
    print('REUSE successful process '+name,flush=True);return
  raise RuntimeError('Refuse to repeat or overwrite failed/incomplete/different process '+name)
 start=time.time()
 print('START '+dataset+' '+name,flush=True)
 with log.open('x') as f:r=subprocess.run(argv,cwd=repo,env=env,stdin=subprocess.DEVNULL,stdout=f,stderr=subprocess.STDOUT)
 result=dict(name=name,argv=list(map(str,argv)),exit_code=r.returncode,elapsed=time.time()-start,peak_rss=None,
  resource_limit='Peak RSS not captured; no resource improvement claim. Concurrent local checks may affect wall time.')
 receipt.write_text(json.dumps(result,indent=2)+'\n');ledger.append(result)
 ledger_path.write_text(json.dumps(ledger,indent=2)+'\n')
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
 # Independently executed complete variants may be reused only on exact frozen
 # inputs/library/reference identity. Never repeat failed or incomplete work.
 name=variant+'-1';root=out/name
 if variant=='after' and a.after_directory:
  assert dataset=='pbmc3k'
  root=Path(a.after_directory).resolve();assert root.parent==out.resolve();name=root.name
 lib=Path(a.baseline_library if variant=='baseline' else a.after_library).resolve()
 if root.exists():
  receipt=json.loads((root/'run.json').read_text())
  assert receipt['status']=='complete' and receipt['variant']==variant and receipt['dataset']==dataset
  assert Path(receipt['source_library']).resolve()==lib
  assert receipt['input_sha256']==hashlib.sha256((input_dir/'input.rds').read_bytes()).hexdigest()
  assert receipt['reference_sha256']==hashlib.sha256((e/'references'/(reference+'-markers.csv')).read_bytes()).hexdigest()
  print('REUSE verified complete variant '+name,flush=True)
 else:
  run(name,['Rscript','--vanilla',str(scripts/'run_workflow.R'),str(input_dir/'input.rds'),str(root),str(lib),variant,str(e/'references'/(reference+'-markers.csv')),dataset])
 classifier=out/('singler-'+name)
 if classifier.exists():
  saved=json.loads((classifier/'run.json').read_text())
  assert saved['input_sha256']==hashlib.sha256((root/'analysis.rds').read_bytes()).hexdigest()
  assert saved['reference_sha256']==hashlib.sha256((e/'references'/(reference+'.rds')).read_bytes()).hexdigest()
  print('REUSE verified complete SingleR '+name,flush=True)
 else:
  run('singler-'+name,['Rscript','--vanilla',str(scripts/'run_singler.R'),str(root/'analysis.rds'),str(e/'references'/(reference+'.rds')),str(classifier)])
 with (root/'membership.csv').open(newline='') as f:membership=list(csv.DictReader(f))
 manual=root/'reviewed-labels.csv'
 manual_rows=[dict(cell_id=r['cell_id'],label=r['reviewed_label'],status='explicit_unknown_control') for r in membership]
 if manual.exists():
  with manual.open(newline='') as f:assert list(csv.DictReader(f))==manual_rows
 else:
  with manual.open('x',newline='') as f:
   w=csv.DictWriter(f,fieldnames=['cell_id','label','status']);w.writeheader();w.writerows(manual_rows)
 evaluate('candidate-author-agreement',root/'reference-candidates.csv',name)
 evaluate('singler-author-agreement',classifier/'predictions.csv',name)
 evaluate('reviewed-control-agreement',manual,name)
 evaluate('candidate-reference-agreement',root/'reference-candidates.csv',name,out/'singler-baseline-1'/'predictions.csv')
print('DATASET COMPLETE '+dataset,flush=True)
