"""Post-hoc fixed common-class agreement from saved aggregate confusion counts.

No scientific reruns, label remapping, fitting or model calls. Original metrics
and failures are inputs, never overwritten. Optional timings are saved wall API
intervals, not pure numerical costs or measured human effort.
"""
import argparse
import hashlib
import json
from pathlib import Path
from evaluate import PREDICTION_STATUS_VERSION, SCOREABLE_STATUSES

COMMON_CLASSES = ['B', 'Dendritic', 'Monocyte', 'NK', 'T']

def common_class_score(metric, classes):
    if not classes or len(set(classes)) != len(classes):
        raise ValueError('Require fixed unique common classes')
    if metric.get('status_policy_version') != PREDICTION_STATUS_VERSION:
        raise ValueError('Require a status-aware score regenerated from raw predictions or a bound frozen audit')
    counts = metric.get('status_counts', {})
    if any(not isinstance(v,int) or v<0 for v in counts.values()) or sum(counts.values()) != metric['original_cells']:
        raise ValueError('Status counts disagree with original denominator')
    confusion = metric['confusion']
    if any(not isinstance(r['cells'], int) or r['cells'] < 0 for r in confusion):
        raise ValueError('Invalid confusion counts')
    if sum(r['cells'] for r in confusion) != metric['agreement_denominator']:
        raise ValueError('Confusion counts disagree with original agreement denominator')
    if sum(r['cells'] for r in confusion if r['prediction']!='Unknown') > sum(counts.get(s,0) for s in SCOREABLE_STATUSES):
        raise ValueError('Unscoreable statuses may have received prediction credit; regenerate from raw rows')
    selected = [r for r in confusion if r['author'] in classes]
    n = sum(r['cells'] for r in selected)
    per_type = []
    for label in classes:
        support = sum(r['cells'] for r in selected if r['author'] == label)
        predicted = sum(r['cells'] for r in selected if r['prediction'] == label)
        correct = sum(r['cells'] for r in selected if r['author'] == label and r['prediction'] == label)
        precision = correct / predicted if predicted else 0
        recall = correct / support if support else 0
        per_type.append(dict(label=label, n=support, predicted=predicted, correct=correct,
            precision=precision, recall=recall, f1=2*correct/(support+predicted) if support+predicted else 0))
    correct = sum(r['correct'] for r in per_type)
    return dict(original_cells=metric['original_cells'],
        original_agreement_denominator=metric['agreement_denominator'], subset_cells=n,
        excluded_truth_cells=metric['agreement_denominator']-n, correct=correct,
        common_classes=classes, macro_f1=sum(r['f1'] for r in per_type)/len(classes) if n else None,
        subset_correct_yield=correct/n if n else None,
        original_universe_correct_yield=correct/metric['original_cells'] if metric['original_cells'] else None,
        unknown_predictions=sum(r['cells'] for r in selected if r['prediction']=='Unknown'),
        noncommon_predictions=sum(r['cells'] for r in selected if r['prediction'] not in classes and r['prediction']!='Unknown'),
        per_type=per_type,
        policy='Exclude only noncommon author truth; Unknown, noncommon, excluded and failed predictions remain misses in the selected truth denominator.')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('metrics',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--timings',type=Path,help='Directory of saved DATASET--STORAGE.json stage timing projections')
    parser.add_argument('--prediction-audit',type=Path,help='Status-aware scores bound to legacy frozen metrics; defaults to sibling prediction-status-audit.json')
    args=parser.parse_args()
    metrics=json.loads(args.metrics.read_text())
    audit_path=args.prediction_audit or args.metrics.with_name('prediction-status-audit.json')
    audit=json.loads(audit_path.read_text()) if audit_path.exists() else None
    source_hash=hashlib.sha256(args.metrics.read_bytes()).hexdigest()
    if audit is not None and audit['original_metrics_sha256']!=source_hash:
        raise ValueError('Prediction audit is not bound to these original frozen metrics')
    rows=[]
    for entry in metrics['details']:
        if entry['dataset']=='ifnb':
            for method in ['candidate_author','singler_author']:
                metric=entry[method]
                if metric.get('status_policy_version')!=PREDICTION_STATUS_VERSION:
                    key=entry['storage']+'/'+method
                    if audit is None or key not in audit['ifnb_status_aware_scores']:
                        raise ValueError('Legacy aggregate needs a bound raw-prediction status audit')
                    metric=audit['ifnb_status_aware_scores'][key]
                result=common_class_score(metric,COMMON_CLASSES)
                result.update(storage=entry['storage'],method=method)
                rows.append(result)
    timings=[]
    for entry in metrics['details']:
        run=entry['run']
        item=dict(dataset=entry['dataset'],storage=entry['storage'],wall_seconds=run.get('elapsed'),
            cpu_user_seconds=run.get('user'),cpu_system_seconds=run.get('system'),
            peak_memory_bytes=None,human_time_seconds=None,pure_compute_seconds=None)
        if args.timings:
            source=args.timings/(entry['dataset']+'--'+entry['storage']+'.json')
            if source.exists():
                item['saved_stage_intervals']=json.loads(source.read_text())
                item['timing_projection_sha256']=hashlib.sha256(source.read_bytes()).hexdigest()
        timings.append(item)
    out=dict(schema='scagentkit.posthoc-common-class.v1',
        status='exploratory_seen_data_not_confirmatory',
        status_policy_version=PREDICTION_STATUS_VERSION,
        prediction_audit_sha256=hashlib.sha256(audit_path.read_bytes()).hexdigest() if audit else None,
        source_metrics_sha256=hashlib.sha256(args.metrics.read_bytes()).hexdigest(),
        label_map_unchanged=True,scientific_rerun=False,model_calls=0,
        ifnb_common_class_policy='Post-hoc intersection of frozen author/reference vocabularies, excluding Other; not selected by model score. Original all-class metrics remain in metrics.json.',
        ifnb=rows,
        baron=dict(pancreatic_accuracy_status='not_applicable_incompatible_hpca_reference',
            pancreatic_accuracy=None,pancreatic_macro_f1=None,
            legacy_results='Original literal matches and failures preserved unchanged in metrics.json and report-original-v1.md; they do not validate pancreatic labels.'),
        resources=timings,
        timing_limitation='Wall intervals include integrity checks, persistence, API work and review rendering under concurrent load. They are not pure compute, isolated logging cost or human time. No peak memory was captured. PBMC snapshot/resume intervals are not whole runs.',
        failures_preserved=metrics['failures'])
    args.output.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':main()
