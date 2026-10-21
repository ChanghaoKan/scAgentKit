"""Installed native startup preserves provider policy without dispatching a model."""
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from store import scrub_secrets
import start_analysis

ROOT = Path(__file__).resolve().parents[2]


class StartProviderConfigTests(unittest.TestCase):
    def test_launcher_accepts_current_setup_and_rejects_removed_fields_before_r(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            input_path = root / "input.rds"
            input_path.write_bytes(b"opaque fixture input")
            setup_path = root / "model.json"
            project = root / "project"
            setup = {"provider": None, "review": {"allow_external": False}}
            argv = [str(input_path), "--project", str(project), "--species", "human",
                    "--tissue", "fixture", "--research-goal", "Offline contract test",
                    "--model-config-file", str(setup_path), "--background", "--no-browser"]

            def accepted(command, **kwargs):
                request = json.loads(Path(command[-2]).read_text())
                self.assertEqual(request["model_setup"], setup)
                Path(command[-1]).write_text(json.dumps({"project_id": "fixture", "provider": {}}))
                return subprocess.CompletedProcess(command, 0)

            with patch.object(start_analysis.socket, "socket"), \
                    patch.object(start_analysis.shutil, "which", return_value="Rscript"), \
                    patch.object(start_analysis, "open_results", return_value={}), \
                    patch.object(start_analysis.subprocess, "run", side_effect=accepted) as run:
                setup_path.write_text(json.dumps(setup))
                with contextlib.redirect_stdout(io.StringIO()):
                    start_analysis.main(argv)
                self.assertEqual(run.call_count, 1)
                for field in ("budget", "cost_mode", "reservation_usd", "charged_or_held_usd"):
                    run.reset_mock()
                    setup_path.write_text(json.dumps(dict(setup, **{field: 0})))
                    with self.subTest(field=field), contextlib.redirect_stderr(io.StringIO()), \
                            self.assertRaises(SystemExit) as stopped:
                        start_analysis.main(argv)
                    self.assertEqual(stopped.exception.code, 2)
                    run.assert_not_called()
                    self.assertFalse(project.exists())

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
                       "review": {"allow_external": True}}}
            config = base / "request.json"
            config.write_text(json.dumps(request))
            result = subprocess.run([rscript, "--vanilla", str(ROOT / "workbench/start_analysis.R"),
                str(config), str(base / "result.json")], env=env, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            self.assertFalse((project / "provider/ledger.json").exists())
            checked = subprocess.run([rscript, "--vanilla", "-e",
                'library(scAgentKit);s<-getFromNamespace(".sc_run_load","scAgentKit")(commandArgs(TRUE)[1]);'
                'stopifnot(s$config$provider$name=="openai_compatible",!any(c("budget","cost_mode") %in% names(s$config)),'
                'isTRUE(s$config$review$allow_external),s$status=="awaiting_review",'
                's$pending$kind=="strategy",length(s$approvals)==0L,is.null(s$files$analysis))',
                str(project)], env=env, capture_output=True, timeout=30)
            self.assertEqual(checked.returncode, 0, checked.stderr.decode(errors="replace"))


if __name__ == "__main__":
    unittest.main()
