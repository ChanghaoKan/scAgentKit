"""Audit saved CSV producer statuses and rescore bookkeeping without refitting."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from evaluate import rows,score,mapped,prediction_status,SCOREABLE_STATUSES,PREDICTION_STATUS_VERSION


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('evidence',type=Path);p.add_argument('metrics',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--mapping',type=Path,default=Path(__file__).with_name('label-map.json'))
    a=p.parse_args();original=json.loads(a.metrics.read_text());mapping=json.loads(a.mapping.read_text())
    files=sorted(set(a.evidence.glob('comparison/*/**/reference-candidates.csv'))|
        set(a.evidence.glob('comparison/*/**/reviewed-labels.csv'))|
        set(a.evidence.glob('comparison/*/singler-*/predictions.csv')))
    if not files:raise ValueError('No saved prediction CSVs; no results were audited')
    receipts=[];counts=Counter();changed_raw_labels=0
    for path in files:
        records=rows(path);dataset=path.relative_to(a.evidence).parts[1]
        labelmap=mapping['pancreas_reference' if dataset=='baron' else 'blood_reference']
        local=Counter(prediction_status(r) for r in records.values());counts.update(local)
        changed=sum(prediction_status(r) not in SCOREABLE_STATUSES and mapped(r.get('label'),labelmap)!='Unknown' for r in records.values())
        changed_raw_labels+=changed
        receipts.append(dict(source=path.relative_to(a.evidence).as_posix(),rows=len(records),
            sha256=hashlib.sha256(path.read_bytes()).hexdigest(),status_counts=dict(local),
            ineligible_nonunknown_raw_labels=changed))
    scores={};comparisons=[]
    for entry in original['details']:
        dataset,storage=entry['dataset'],entry['storage'];base=a.evidence/'comparison'/dataset
        universe=(a.evidence/'prepared-v2'/dataset/'cells.txt').read_text().splitlines()
        truth_path=a.evidence/'prepared-v2'/dataset/'truth.csv'
        truth=rows(truth_path) if truth_path.exists() else None
        pm=mapping['pancreas_reference' if dataset=='baron' else 'blood_reference']
        tm=mapping['pancreas_author' if dataset=='baron' else 'ifnb_author']
        for method,path in [('candidate_author',base/storage/'reference-candidates.csv'),
                            ('singler_author',base/('singler-'+storage)/'predictions.csv')]:
            current=score(universe,rows(path),truth,pm,tm);saved=entry[method]
            keys=['known_coverage','agreement_denominator','correct','end_to_end_correct_yield','macro_f1','confusion']
            changes={key:dict(before=saved.get(key),after=current.get(key)) for key in keys if saved.get(key)!=current.get(key)}
            comparisons.append(dict(dataset=dataset,storage=storage,method=method,changes=changes))
            if dataset=='ifnb':scores[storage+'/'+method]=current
    for receipt,path in zip(receipts,files):
        if hashlib.sha256(path.read_bytes()).hexdigest()!=receipt['sha256']:
            raise ValueError('Saved raw output changed during audit')
    out=dict(schema='scagentkit.frozen-prediction-status-audit.v1',status_policy_version=PREDICTION_STATUS_VERSION,
        original_metrics_sha256=hashlib.sha256(a.metrics.read_bytes()).hexdigest(),
        label_map_sha256=hashlib.sha256(a.mapping.read_bytes()).hexdigest(),
        scoreable_statuses=sorted(SCOREABLE_STATUSES),files=len(files),rows=sum(r['rows'] for r in receipts),
        status_counts=dict(counts),ineligible_nonunknown_raw_labels=changed_raw_labels,
        original_raw_outputs_unchanged=True,scientific_refits=0,model_calls=0,
        changed_saved_metrics=sum(bool(r['changes']) for r in comparisons),comparisons=comparisons,
        sources=receipts,ifnb_status_aware_scores=scores,
        limitation='Status validation is a software prerequisite. Frozen candidates and reference predictions are not reviewed biological truth. Original metrics and failed attempts are retained.')
    a.output.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
    print('Audited',len(files),'saved CSVs;',out['rows'],'rows;',changed_raw_labels,'ineligible nonunknown raw labels;',out['changed_saved_metrics'],'changed metric comparisons')

if __name__=='__main__':main()
