"""Installed native startup preserves provider policy without dispatching a model."""
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


class StartProviderConfigTests(unittest.TestCase):
    def test_native_provider_policy_starts_an_unapproved_local_draft(self):
        rscript = shutil.which("Rscript")
        if not rscript:
            self.skipTest("Rscript unavailable")
        env = scrub_secrets(dict(os.environ))
        env.pop("SCAGENTKIT_START_TEST_KEY", None)
        available = subprocess.run([rscript, "--vanilla", "-e",
            'quit(status=if(requireNamespace("scAgentKit",quietly=TRUE)&&"provider" %in% names(formals(scAgentKit::sc_start)))0L else 42L)'],
            env=env, capture_output=True, timeout=30)
        if available.returncode == 42:
            self.skipTest("Current provider-startup package not installed")
        self.assertEqual(available.returncode, 0, available.stderr)
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            input_path = base / "public.rds"
            setup = subprocess.run([rscript, "--vanilla", "-e",
                'data("pbmc_small",package="SeuratObject");saveRDS(pbmc_small,commandArgs(TRUE)[1])',
                str(input_path)], env=env, capture_output=True, timeout=30)
            self.assertEqual(setup.returncode, 0, setup.stderr)
            project = base / "project"
            request = {"input": str(input_path), "project": str(project), "checkout": str(ROOT),
                       "runtime": str(ROOT / "inst/workbench"), "entry": "raw",
                       "cluster_column": "sc_strategy_clusters", "context": {"species": "human",
                       "tissue": "Public PBMC", "research_goal": "Offline startup validation",
                       "columns": {"sample": "orig.ident"}}, "model_setup": {
                       "provider": {"name": "openai_compatible", "model": "offline-model",
                                    "base_url": "https://offline.invalid/v1",
                                    "api_key_env": "SCAGENTKIT_START_TEST_KEY"},
                       "budget": 0.2, "review": {"allow_external": True}}}
            config = base / "request.json"
            config.write_text(json.dumps(request))
            result = subprocess.run([rscript, "--vanilla", str(ROOT / "workbench/start_analysis.R"),
                str(config), str(base / "result.json")], env=env, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            self.assertFalse((project / "provider/ledger.json").exists())
            checked = subprocess.run([rscript, "--vanilla", "-e",
                'library(scAgentKit);s<-getFromNamespace(".sc_run_load","scAgentKit")(commandArgs(TRUE)[1]);'
                'stopifnot(s$config$provider$name=="openai_compatible",s$config$budget==0,s$config$cost_mode=="posthoc",'
                'isTRUE(s$config$review$allow_external),s$status=="awaiting_review",'
                's$pending$kind=="strategy",length(s$approvals)==0L,is.null(s$files$analysis))',
                str(project)], env=env, capture_output=True, timeout=30)
            self.assertEqual(checked.returncode, 0, checked.stderr.decode(errors="replace"))


if __name__ == "__main__":
    unittest.main()
