"""Native production-stage export guard, optional where R/scAgentKit exists."""
import os
import shutil
import subprocess
import unittest
from pathlib import Path


class SavedStageNativeTests(unittest.TestCase):
    def test_exact_production_export_and_checkpoint_guards(self):
        rscript = shutil.which("Rscript")
        if not rscript:
            self.skipTest("Rscript is unavailable")
        env = dict(os.environ)
        for key in tuple(env):
            if key.endswith("_API_KEY") or key in {"HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN"}:
                env.pop(key)
        available = subprocess.run([rscript, "--vanilla", "-e",
            'quit(status=if (requireNamespace("scAgentKit",quietly=TRUE) && requireNamespace("SeuratObject",quietly=TRUE)) 0L else 42L)'],
            env=env, capture_output=True, timeout=30)
        if available.returncode == 42:
            self.skipTest("scAgentKit/SeuratObject are not installed in this R environment")
        self.assertEqual(available.returncode, 0)
        directory = Path(__file__).resolve().parent
        result = subprocess.run([rscript, "--vanilla", str(directory / "test_run_workbench_stage.R"),
            str(directory.parent / "run_workbench_bridge.R")], env=env, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", errors="replace"))
        self.assertIn(b"PASS production R saved-stage export", result.stdout)


if __name__ == "__main__":
    unittest.main()
