#!/usr/bin/env python3
"""Fetch exact public release sources; reject altered cached bytes."""
import argparse,hashlib,json,pathlib,urllib.request

def verify(path, expected):
 actual=hashlib.sha256(path.read_bytes()).hexdigest()
 if actual!=expected: raise ValueError('SHA256 mismatch: '+path.name)
 return actual

def fetch(lock, directory, runtimes=False):
 directory.mkdir(parents=True,exist_ok=True)
 items = lock['packages'] + (lock.get('runtime_sources',[]) if runtimes else [])
 for item in items:
  target=directory/item['file']
  if not target.exists():
   with urllib.request.urlopen(item['url'],timeout=120) as response:
    data=response.read()
   partial=target.with_suffix('.partial');partial.write_bytes(data)
   verify(partial,item['sha256']);partial.replace(target)
  verify(target,item['sha256'])
 print('Verified',len(items),'exact archives; no installation performed.')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('cache',type=pathlib.Path);p.add_argument('--lock',type=pathlib.Path,default=pathlib.Path(__file__).with_name('v0.6.0-linux.json'))
 p.add_argument('--runtimes',action='store_true',help='Also fetch pinned official R/Python source archives')
 a=p.parse_args();fetch(json.loads(a.lock.read_text()),a.cache,a.runtimes)
