"""Native launcher preflight must fail before creating output for bad input/code."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from store import scrub_secrets

ROOT = Path(__file__).resolve().parents[2]


class StartAnalysisTests(unittest.TestCase):
    def test_native_invalid_counts_and_changed_kernel_leave_no_project(self):
        rscript = shutil.which("Rscript")
        if not rscript: self.skipTest("Rscript unavailable")
        env = scrub_secrets(dict(os.environ))
        available = subprocess.run([rscript, "--vanilla", "-e",
            'quit(status=if(requireNamespace("scAgentKit",quietly=TRUE)&&"sc_run_prepare_annotation" %in% getNamespaceExports("scAgentKit"))0L else 42L)'],
            env=env, capture_output=True, timeout=30)
        if available.returncode == 42: self.skipTest("Current workflow package not installed")
        self.assertEqual(available.returncode, 0, available.stderr)
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            input_path, project, config = base / "a.rds", base / "project", base / "request.json"
            setup = subprocess.run([rscript, "--vanilla", "-e",
                'x<-matrix(-1,3,3,dimnames=list(letters[1:3],LETTERS[1:3]));saveRDS(x,commandArgs(TRUE)[1])',
                str(input_path)], env=env, capture_output=True, timeout=30)
            self.assertEqual(setup.returncode, 0, setup.stderr)
            request = {"input": str(input_path), "project": str(project), "checkout": str(ROOT),
                       "runtime": str(ROOT / "inst/workbench"),
                       "context": {"species": "human", "tissue": "software fixture"},
                       "entry": "raw", "cluster_column": "seurat_clusters"}
            config.write_text(json.dumps(request))
            def attempt():
                return subprocess.run([rscript, "--vanilla", str(ROOT / "workbench/start_analysis.R"),
                    str(config), str(base / "result.json")], env=env, capture_output=True, timeout=60)
            rejected = attempt()
            self.assertNotEqual(rejected.returncode, 0)
            self.assertNotIn(b"source checkout differ", rejected.stderr)
            self.assertFalse(project.exists())
            checkout = base / "checkout"
            shutil.copytree(ROOT / "R", checkout / "R")
            file = checkout / "R/project-prepare.R"
            file.write_text(file.read_text() + '\nsc_project_prepare <- function(...) stop("deliberately incompatible test kernel")\n')
            request["checkout"] = str(checkout); config.write_text(json.dumps(request))
            incompatible = attempt()
            self.assertNotEqual(incompatible.returncode, 0)
            self.assertIn(b"source checkout differ", incompatible.stderr)
            self.assertFalse(project.exists())


if __name__ == "__main__": unittest.main()
