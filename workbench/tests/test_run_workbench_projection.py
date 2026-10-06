"""Exercise the actual pure R display helper, no package engine or data analysis."""
import subprocess
import unittest
from pathlib import Path


class RunWorkbenchProjectionTests(unittest.TestCase):
    def test_native_qc_schema_sentinel_and_count_regression(self):
        root = Path(__file__).resolve().parents[1]
        result = subprocess.run(["Rscript", "--vanilla", str(Path(__file__).with_suffix(".R")),
                                 str(root / "run_workbench_projection.R")],
                                capture_output=True, text=True, timeout=30, shell=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("scalar cohort counts: PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()
