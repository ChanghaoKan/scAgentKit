"""Provision prespecified public bytes only; no model calls or outcome scoring."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import time
import urllib.error
import urllib.request

SOURCES = {
    'pbmc3k-filtered.tar.gz': 'https://cf.10xgenomics.com/samples/cell/pbmc3k/pbmc3k_filtered_gene_bc_matrices.tar.gz',
    'pbmc3k-raw.tar.gz': 'https://cf.10xgenomics.com/samples/cell/pbmc3k/pbmc3k_raw_gene_bc_matrices.tar.gz',
    'ifnb.SeuratData_3.0.0.tar.gz': 'https://seurat.nygenome.org/src/contrib/ifnb.SeuratData_3.0.0.tar.gz',
    'baron-human1.csv.gz': 'https://ftp.ncbi.nlm.nih.gov/geo/samples/GSM2230nnn/GSM2230757/suppl/GSM2230757_human1_umifm_counts.csv.gz',
    'baron-human2.csv.gz': 'https://ftp.ncbi.nlm.nih.gov/geo/samples/GSM2230nnn/GSM2230758/suppl/GSM2230758_human2_umifm_counts.csv.gz',
    'baron-human3.csv.gz': 'https://ftp.ncbi.nlm.nih.gov/geo/samples/GSM2230nnn/GSM2230759/suppl/GSM2230759_human3_umifm_counts.csv.gz',
    'baron-human4.csv.gz': 'https://ftp.ncbi.nlm.nih.gov/geo/samples/GSM2230nnn/GSM2230760/suppl/GSM2230760_human4_umifm_counts.csv.gz',
}

def fetch(root, name, url):
    target = root / name
    if target.exists():
        return dict(name=name,url=url,status='cached',bytes=target.stat().st_size,sha256=hashlib.sha256(target.read_bytes()).hexdigest())
    partial = root / (name + '.partial')
    for attempt in range(3):
        try:
            request=urllib.request.Request(url,headers={'User-Agent':'scAgentKit-public-offline-evaluation/1'})
            h=hashlib.sha256(); total=0
            with urllib.request.urlopen(request,timeout=180) as response, partial.open('wb') as output:
                if response.status != 200: raise RuntimeError('Unexpected status %s' % response.status)
                while True:
                    block=response.read(1024*1024)
                    if not block: break
                    total += len(block)
                    if total > 512*1024*1024: raise RuntimeError('Public input exceeds declared 512MiB per-file provisioning cap')
                    h.update(block);output.write(block)
            partial.replace(target)
            return dict(name=name,url=url,status='downloaded',bytes=total,sha256=h.hexdigest())
        except Exception as error:
            partial.unlink(missing_ok=True)
            if attempt==2 or isinstance(error,urllib.error.HTTPError) and error.code not in (408,429,500,502,503,504):
                return dict(name=name,url=url,status='unavailable',error=str(error))
            time.sleep(2**attempt)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('output');args=parser.parse_args()
    root=Path(args.output);root.mkdir(parents=True,exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        results=list(pool.map(lambda item:fetch(root,*item),SOURCES.items()))
    pbmc=next(x for x in results if x['name']=='pbmc3k-filtered.tar.gz')
    if pbmc['status']!='unavailable':
        assert pbmc['sha256']=='847d6ebd9a1ec9a768f2be7e40ca42cbfe75ebeb6d76a4c24167041699dc28b5','Official PBMC bytes differ from preregistration'
    result=dict(protocol='evaluation-v1',purpose='public input provisioning, not effect measurement',provider_calls=0,files=results)
    (root/'download-manifest.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
