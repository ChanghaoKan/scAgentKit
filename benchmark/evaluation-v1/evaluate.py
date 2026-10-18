"""Fixed-denominator agreement bookkeeping; never asserts biological accuracy."""
import argparse,csv,json
from collections import Counter
from pathlib import Path

def rows(path):
    with Path(path).open(newline='') as f: data=list(csv.DictReader(f))
    result={row['cell_id']:row for row in data}
    if len(result)!=len(data):raise ValueError('Duplicate cell IDs')
    return result

def mapped(label,mapping,truth=False):
    label=(label or '').strip()
    if label.lower() in ('','unknown','unannotated'):return 'Unknown'
    normalized={key.strip().lower():value for key,value in mapping.items()}
    return normalized.get(label.lower(),('UNMAPPED:'+label) if truth else 'Other')

def score(universe,predictions,truth=None,prediction_map=None,truth_map=None):
    if len(set(universe))!=len(universe):raise ValueError('Duplicate universe IDs')
    if not set(predictions)<=set(universe):raise ValueError('Foreign prediction cell IDs')
    if truth is not None and set(truth)!=set(universe):raise ValueError('Truth must cover the exact original universe')
    prediction_map=prediction_map or {};truth_map=truth_map or {}
    labels={cell:mapped(predictions.get(cell,{}).get('label','Unknown'),prediction_map) for cell in universe}
    counts=Counter(predictions.get(cell,{}).get('status','excluded') for cell in universe)
    coverage=sum(value!='Unknown' for value in labels.values())/len(universe) if universe else None
    out=dict(original_cells=len(universe),status_counts=dict(counts),known_coverage=coverage,
             biological_accuracy=None,scientific_accuracy_claim=False,agreement_status='not_evaluated_no_truth',agreement_denominator=0,
             annotation_accuracy=None,human_time_seconds=None)
    if truth is None:return out
    evaluable=[cell for cell in universe if truth[cell].get('status') not in ('ambiguous','unlabeled') and truth[cell].get('label','').strip()]
    target={cell:mapped(truth[cell]['label'],truth_map,truth=True) for cell in evaluable}
    confusion=Counter((target[cell],labels[cell]) for cell in evaluable)
    tp=sum(target[cell]==labels[cell] and labels[cell]!='Unknown' for cell in evaluable)
    known=sum(labels[cell]!='Unknown' for cell in evaluable)
    per_type=[]
    # Fixed truth classes. Abstention/exclusion is a false negative, not another
    # class added or removed from the macro denominator per method.
    for label in sorted(set(target.values())):
        n=sum(value==label for value in target.values())
        predicted=sum(labels[cell]==label for cell in evaluable)
        correct=sum(target[cell]==label and labels[cell]==label for cell in evaluable)
        precision=correct/predicted if predicted else 0
        recall=correct/n
        f1=2*precision*recall/(precision+recall) if precision+recall else 0
        per_type.append(dict(label=label,n=n,predicted=predicted,correct=correct,precision=precision,recall=recall,f1=f1))
    out.update(agreement_status='author_label_agreement_only',agreement_denominator=len(evaluable),correct=tp,
               conditional_agreement=tp/known if known else None,end_to_end_correct_yield=tp/len(evaluable) if evaluable else None,
               macro_f1=sum(x['f1'] for x in per_type)/len(per_type) if per_type else None,macro_classes='all evaluable frozen truth classes; unknown/excluded count as misses',
               per_type=per_type,unmapped_truth=sum(v.startswith('UNMAPPED:') for v in target.values()),
               confusion=[dict(author=a,prediction=b,cells=n) for (a,b),n in sorted(confusion.items())])
    return out

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('cells');p.add_argument('predictions');p.add_argument('mapping');p.add_argument('dataset');p.add_argument('output')
    target=p.add_mutually_exclusive_group();target.add_argument('--truth');target.add_argument('--reference');a=p.parse_args()
    mapping=json.loads(Path(a.mapping).read_text()); universe=Path(a.cells).read_text().splitlines()
    pred_map=mapping['pancreas_reference' if a.dataset=='baron' else 'blood_reference']
    truth_map=pred_map if a.reference else mapping['pancreas_author' if a.dataset=='baron' else 'ifnb_author']
    target_path=a.reference or a.truth
    result=score(universe,rows(a.predictions),rows(target_path) if target_path else None,pred_map,truth_map)
    if a.reference:
        result['agreement_status']='external_reference_agreement_only'
        result['external_reference_match_fraction']=result.pop('end_to_end_correct_yield')
        result['conditional_reference_agreement']=result.pop('conditional_agreement')
        result['macro_f1']=None
        result['limitation']='External classifier predictions are comparison targets, not independent biological truth; F1 and accuracy are not reported.'
        for row in result['per_type']:row['f1']=None
        for row in result['confusion']:row['reference']=row.pop('author')
    result['label_map_sha256']=__import__('hashlib').sha256(Path(a.mapping).read_bytes()).hexdigest()
    if a.dataset=='baron':
        result['agreement_status']='reference_granularity_mismatch'
        result['fine_subtype_agreement']=None
        result['limitation']=mapping['pancreas_limit']
        result['mapped_label_match_interpretation']='Any retained match metrics describe literal mapped-label agreement only; broad islet predictions cannot validate endocrine subtypes.'
    Path(a.output).write_text(json.dumps(result,indent=2)+'\n')
