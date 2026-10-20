import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from open_results import open_results

class OperatorTimeoutTests(unittest.TestCase):
    def test_invalid_timeout_fails_before_filesystem_or_runtime(self):
        for value in (True, 0, -1, 86401, 1.5, '300'):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'model_timeout'):
                open_results('/nonexistent', model_timeout=value)
