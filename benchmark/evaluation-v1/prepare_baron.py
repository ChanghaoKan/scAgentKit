"""Make a sparse query input; author labels go only to a separate evaluator file."""
import argparse,csv,gzip,hashlib,json,shutil
from pathlib import Path

ACCESSIONS=['GSM2230757','GSM2230758','GSM2230759','GSM2230760']
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def prepare(source,out):
    if out.exists():raise FileExistsError('Preserve previous prepared inputs; choose a new directory')
    out.mkdir(parents=True)
    universe=[];genes=None
    for i,acc in enumerate(ACCESSIONS,1):
        with gzip.open(source/('baron-human%d.csv.gz'%i),'rt',newline='') as f:
            rows=csv.reader(f);header=next(rows)
            if genes is None:genes=header[3:]
            assert header[3:]==genes,'Specimens have different gene universes'
            for row in rows:
                literal=row[0];cell=acc+'::'+literal
                h=hashlib.sha256(('evaluation-v1|'+acc+'|'+literal).encode()).hexdigest()
                universe.append((h,cell,acc,literal))
    assert len({x[1] for x in universe})==len(universe),'Duplicate literal cell IDs'
    selected=sorted(universe)[:5000] if len(universe)>5000 else sorted(universe)
    cells=[x[1] for x in selected];indices={cell:i+1 for i,cell in enumerate(cells)}
    # Persist selection before opening any label for the evaluator.
    (out/'selected-cells.json').write_text(json.dumps(dict(rule='SHA256 evaluation-v1|accession|literal_cell_id',cells=cells,source_cells=len(universe)),indent=2))
    assert len(set(genes))==len(genes),'Duplicate gene names need an explicit upstream mapping'
    (out/'genes.txt').write_text('\n'.join(genes)+'\n');(out/'barcodes.txt').write_text('\n'.join(cells)+'\n')
    nnz=0
    with (out/'triplets.tmp').open('w') as triplets,(out/'truth.csv').open('w',newline='') as truth,(out/'metadata.csv').open('w',newline='') as metadata:
        tw=csv.writer(truth);tw.writerow(['cell_id','label','status'])
        mw=csv.writer(metadata);mw.writerow(['cell_id','sample_id'])
        for i,acc in enumerate(ACCESSIONS,1):
            with gzip.open(source/('baron-human%d.csv.gz'%i),'rt',newline='') as f:
                rows=csv.reader(f);next(rows)
                for row in rows:
                    cell=acc+'::'+row[0]
                    if cell not in indices:continue
                    tw.writerow([cell,row[2],'author_annotation']);mw.writerow([cell,acc])
                    assert len(row[3:])==len(genes)
                    for j,v in enumerate(row[3:],1):
                        x=float(v);assert x>=0 and x.is_integer(),'Expected original UMI integers'
                        if x:triplets.write('%d %d %d\n'%(j,indices[cell],int(x)));nnz+=bool(x)
    with (out/'matrix.mtx').open('w') as matrix,(out/'triplets.tmp').open() as triplets:
        matrix.write('%%MatrixMarket matrix coordinate integer general\n% Public Baron counts, author labels excluded\n')
        matrix.write('%d %d %d\n'%(len(genes),len(cells),nnz));shutil.copyfileobj(triplets,matrix)
    (out/'triplets.tmp').unlink()
    receipt=dict(dataset='Baron human pancreas four specimens',cells=len(cells),source_cells=len(universe),genes=len(genes),nonzero=nnz,
                 labels_in_analysis=False,files={p.name:digest(p) for p in out.iterdir() if p.is_file()},physical_capture='unknown',donor_mapping='not_inferred')
    (out/'manifest.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('inputs',type=Path);p.add_argument('output',type=Path);a=p.parse_args();prepare(a.inputs,a.output)
