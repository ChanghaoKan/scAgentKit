import copy
import unittest
from evaluate import score

class PredictionStatusTests(unittest.TestCase):
    def test_failed_correct_label_never_gets_credit_and_raw_output_is_preserved(self):
        predictions={'a':{'label':'T','status':'failed'}}
        original=copy.deepcopy(predictions)
        result=score(['a'],predictions,{'a':{'label':'T','status':'author'}},{'T':'T'},{'T':'T'})
        self.assertEqual(result['correct'],0)
        self.assertEqual(result['known_coverage'],0)
        self.assertEqual(result['macro_f1'],0)
        self.assertEqual(result['confusion'][0]['prediction'],'Unknown')
        self.assertEqual(predictions,original)
    def test_missing_unknown_and_nonrun_statuses_abstain_without_dropping_cells(self):
        statuses=[None,'mystery','not_run','schema_failed','unknown','explicit_unknown_control']
        predictions={str(i):dict(label='T',**({} if s is None else dict(status=s))) for i,s in enumerate(statuses)}
        truth={c:{'label':'T','status':'author'} for c in predictions}
        result=score(list(predictions),predictions,truth,{'T':'T'},{'T':'T'})
        self.assertEqual(result['agreement_denominator'],len(statuses))
        self.assertEqual(result['correct'],0)
        self.assertEqual(result['known_coverage'],0)
        self.assertEqual(result['status_counts']['missing_status'],1)
    def test_existing_candidate_and_reference_producers_are_scoreable(self):
        p={'a':dict(label='T',status='candidate_only_not_reviewed'),
           'b':dict(label='T',status='reference_prediction')}
        x=score(list(p),p,{c:dict(label='T',status='author') for c in p},{'T':'T'},{'T':'T'})
        self.assertEqual(x['correct'],2)
        self.assertEqual(x['macro_f1'],1)

if __name__=='__main__':unittest.main()
