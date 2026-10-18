import unittest
from evaluate import score
class MetricTests(unittest.TestCase):
    def test_missing_truth_remains_null(self):
        x=score(['a'],{'a':{'label':'T','status':'candidate'}})
        self.assertIsNone(x['annotation_accuracy']);self.assertEqual(x['agreement_denominator'],0)
    def test_excluded_unknown_and_unmapped_cannot_disappear(self):
        truth={c:{'label':l,'status':'author'} for c,l in zip('abcd',['T','B','B','T'])}
        pred={'a':{'label':'T','status':'candidate'},'b':{'label':'Unknown','status':'unknown'},'c':{'label':'B','status':'candidate'}}
        x=score(list('abcd'),pred,truth,{'T':'T','B':'B'},{'T':'T','B':'B'})
        self.assertEqual(x['agreement_denominator'],4);self.assertEqual(x['correct'],2)
        self.assertEqual(x['end_to_end_correct_yield'],.5);self.assertEqual(x['status_counts']['excluded'],1)
        self.assertEqual(x['macro_f1'],2/3)
    def test_foreign_cells_are_errors(self):
        with self.assertRaisesRegex(ValueError,'Foreign'):score(['a'],{'b':{}})
if __name__=='__main__':unittest.main()
