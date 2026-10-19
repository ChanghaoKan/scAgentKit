import unittest
from posthoc_report import common_class_score

class CommonClassTests(unittest.TestCase):
    def test_exclude_only_noncommon_truth_keep_unknown_and_foreign_predictions_as_failures(self):
        metric=dict(original_cells=5,agreement_denominator=5,confusion=[
            dict(author='T',prediction='T',cells=1),dict(author='T',prediction='Unknown',cells=1),
            dict(author='B',prediction='Other',cells=1),dict(author='B',prediction='B',cells=1),
            dict(author='Other',prediction='B',cells=1)])
        result=common_class_score(metric,['B','T'])
        self.assertEqual(result['original_cells'],5)
        self.assertEqual(result['subset_cells'],4)
        self.assertEqual(result['excluded_truth_cells'],1)
        self.assertEqual(result['correct'],2)
        self.assertEqual(result['unknown_predictions'],1)
        self.assertEqual(result['noncommon_predictions'],1)
        self.assertEqual(result['macro_f1'],2/3)
        self.assertEqual(result['subset_correct_yield'],.5)
        self.assertEqual(result['original_universe_correct_yield'],.4)
    def test_bad_denominator_fails_closed(self):
        with self.assertRaisesRegex(ValueError,'denominator'):
            common_class_score(dict(original_cells=2,agreement_denominator=2,
                confusion=[dict(author='T',prediction='T',cells=1)]),['T'])
    def test_fixed_classes_do_not_disappear_for_an_all_unknown_method(self):
        result=common_class_score(dict(original_cells=1,agreement_denominator=1,
            confusion=[dict(author='T',prediction='Unknown',cells=1)]),['B','T'])
        self.assertEqual(result['macro_f1'],0)
        self.assertEqual(len(result['per_type']),2)

if __name__=='__main__':unittest.main()
