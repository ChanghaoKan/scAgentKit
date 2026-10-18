#!/usr/bin/env python3
"""Verify local source bytes, DESCRIPTION identity and dependency DAG, offline."""
import argparse,csv,json,pathlib,re,tarfile
from fetch import verify
BASE=set('base compiler datasets graphics grDevices grid methods parallel splines stats stats4 tcltk tools utils boot class cluster codetools foreign KernSmooth lattice MASS Matrix mgcv nlme nnet rpart spatial survival'.split())
def audit(lock,cache):
 records={p['package']:p for p in lock['packages']};edges={}
 base_versions={p['package']:p['version'] for p in lock.get('base_recommended',[])}
 def compare(a,b):
  a=[int(x) for x in re.split(r'[.-]',a)];b=[int(x) for x in re.split(r'[.-]',b)]
  a += [0]*(len(b)-len(a));b += [0]*(len(a)-len(b))
  return (a>b)-(a<b)
 for name,item in records.items():
  path=cache/item['file'];verify(path,item['sha256'])
  with tarfile.open(path) as t:
   names=[n for n in t.getnames() if n.count('/')==1 and n.endswith('/DESCRIPTION')]
   if len(names)!=1:raise ValueError('Ambiguous DESCRIPTION: '+name)
   raw=t.extractfile(names[0]).read().decode()
  fields={};key=None
  for line in raw.splitlines():
   if line[:1].isspace() and key:fields[key]+=' '+line.strip()
   elif ':' in line:key,value=line.split(':',1);fields[key]=value.strip()
  if fields.get('Package')!=name or fields.get('Version')!=item['version']:raise ValueError('Identity mismatch: '+name)
  deps=[]
  for field in ('Depends','Imports','LinkingTo'):
   for part in fields.get(field,'').split(','):
    dep=re.sub(r'\s*\(.*','',part).strip()
    match=re.search(r'\(\s*(>=|<=|==|>|<)\s*([0-9][0-9.-]*)\s*\)',part)
    actual=lock['R'] if dep=='R' else records.get(dep,{}).get('version',base_versions.get(dep))
    if match and actual:
     op,want=match.groups();c=compare(actual,want)
     if not {'>=':c>=0,'<=':c<=0,'==':c==0,'>':c>0,'<':c<0}[op]:raise ValueError('Version constraint mismatch: '+name+' -> '+part)
    if dep and dep!='R' and dep not in BASE:
     if dep not in records:raise ValueError('Unlocked dependency: '+name+' -> '+dep)
     deps.append(dep)
  edges[name]=set(deps)
 order=[]
 while edges:
  ready=sorted(n for n,deps in edges.items() if not deps)
  if not ready:raise ValueError('Dependency cycle')
  order.extend(ready)
  for n in ready:del edges[n]
  for deps in edges.values():deps.difference_update(ready)
 with (cache/'verified-install-order.tsv').open('w') as f:
  w=csv.DictWriter(f,fieldnames=['package','version','file'],delimiter='\t');w.writeheader()
  for n in order:w.writerow({k:records[n][k] for k in ['package','version','file']})
 if base_versions:
  with (cache/'verified-base-library.tsv').open('w') as f:
   w=csv.DictWriter(f,fieldnames=['package','version'],delimiter='\t');w.writeheader()
   for name,version in sorted(base_versions.items()):w.writerow(dict(package=name,version=version))
 print('Verified SHA256, DESCRIPTION and local dependency order:',len(order),'packages.')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('cache',type=pathlib.Path);p.add_argument('--lock',type=pathlib.Path,default=pathlib.Path(__file__).with_name('v0.6.0-linux.json'))
 a=p.parse_args();audit(json.loads(a.lock.read_text()),a.cache)
