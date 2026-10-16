"""Actual completed coordinator and web bridge, with no model or network calls."""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_workbench_runtime import RunWorkbenchRuntime
from store import StoreError, scrub_secrets


class CompletedExportRecoveryTests(unittest.TestCase):
    def test_native_completed_exports_and_authority(self):
        rscript = shutil.which("Rscript")
        if not rscript:
            self.skipTest("Rscript unavailable")
        env = scrub_secrets(dict(os.environ))
        available = subprocess.run([rscript, "--vanilla", "-e",
            'quit(status=if(requireNamespace("scAgentKit",quietly=TRUE)) 0L else 42L)'],
            env=env, capture_output=True, timeout=30)
        if available.returncode == 42:
            self.skipTest("scAgentKit is not installed in this R environment")
        self.assertEqual(available.returncode, 0, available.stderr)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "completed"
            setup = subprocess.run([rscript, "--vanilla", str(Path(__file__).with_name(
                "create_completed_export_fixture.R")), str(root)], env=env, capture_output=True, timeout=120)
            self.assertEqual(setup.returncode, 0, setup.stderr.decode(errors="replace"))
            runtime = RunWorkbenchRuntime(root, rscript=rscript, timeout=120)
            original = runtime.describe()
            self.assertTrue(original["evidence_complete"])
            authority = {p: p.read_bytes() for p in [root / "state.rds", root / "output/seurat.rds",
                         *sorted((root / "checkpoints").glob("*.rds"))]}
            csv = sorted((root / "output").glob("*.csv"))
            self.assertTrue(csv, "Completed fixture must contain actual CSV exports")
            targets = [csv[0], root / "output/annotation_evidence_summary.json", root / "bundle/project.json"]
            self.assertTrue(all(p.is_file() for p in targets))
            for target in targets:
                for mutation in ("edit", "delete"):
                    with self.subTest(target=target.name, mutation=mutation):
                        if mutation == "edit":
                            target.write_text("broken convenience export\n")
                        else:
                            target.unlink()
                        inspected = subprocess.run([rscript, "--vanilla", "-e",
                            'library(scAgentKit); p<-commandArgs(TRUE)[1]; stopifnot(sc_run_inspect(p)$status=="complete",sc_run_resume(p)$status=="complete")',
                            str(root)], env=env, capture_output=True, timeout=60)
                        self.assertEqual(inspected.returncode, 0, inspected.stderr)
                        view = runtime.describe()
                        self.assertEqual(view["run"]["status"], "complete")
                        self.assertEqual(view["history"], original["history"])
                        if target.parent.name == "bundle":
                            self.assertFalse(view["evidence_complete"])
                            self.assertIsNone(view["evidence"])
                            self.assertIn("bundle", view["evidence_error"])
                        if target.suffix == ".json" and target.parent.name == "output":
                            self.assertIsNone(view["annotation"]["summary"])
                        self.assertEqual({p: p.read_bytes() for p in authority}, authority)
            for target in (root / "output/seurat.rds", next((root / "checkpoints").glob("analysis-*.rds"))):
                with self.subTest(authority=target.name):
                    original_bytes = target.read_bytes()
                    target.write_bytes(original_bytes + b"changed")
                    with self.assertRaises(StoreError):
                        runtime.describe()
                    target.write_bytes(original_bytes)


if __name__ == "__main__":
    unittest.main()
