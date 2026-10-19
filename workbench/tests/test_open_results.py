"""Native reopen/reuse/restart and exact project binding, no analysis or API."""
import http.client
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import open_results as launcher
from open_results import open_results
from store import scrub_secrets


class OpenResultsTests(unittest.TestCase):
    def test_saved_inspect_reconstructs_complete_reviews_from_display_sections(self):
        class Runtime:
            def describe(self):
                return {"run": {"project_id": "literal", "display_sections": {
                    "annotation_review": "annotation.review", "computed_diagnostics": "analysis.computed_diagnostics"}},
                    "annotation": {"review": {"details": {"annotations": [{"clusterId": "01", "saved": "complete"}]}}},
                    "analysis": {"computed_diagnostics": {"saved": "complete"}}}
        runtime = Runtime()
        runtime.project, runtime.library, runtime.rscript = Path("/fixed"), None, "Rscript"
        run = launcher.SavedReview(runtime, "literal").describe()["run"]
        self.assertEqual(run["annotation_review"], runtime.describe()["annotation"]["review"])
        self.assertEqual(run["computed_diagnostics"], runtime.describe()["analysis"]["computed_diagnostics"])
        self.assertNotIn("display_sections", run)

    def test_reopen_reuse_restart_and_wrong_project(self):
        rscript = shutil.which("Rscript")
        if not rscript:
            self.skipTest("Rscript unavailable")
        env = scrub_secrets(dict(os.environ))
        available = subprocess.run([rscript, "--vanilla", "-e",
            'quit(status=if(requireNamespace("scAgentKit",quietly=TRUE) && "sc_run_open" %in% getNamespaceExports("scAgentKit")) 0L else 42L)'],
            env=env, capture_output=True, timeout=30)
        if available.returncode == 42:
            self.skipTest("Current scAgentKit result launcher is not installed")
        self.assertEqual(available.returncode, 0, available.stderr)
        pids = set()
        with tempfile.TemporaryDirectory() as directory:
            def setup(name):
                root = Path(directory) / name
                created = subprocess.run([rscript, "--vanilla", str(Path(__file__).with_name(
                    "create_completed_export_fixture.R")), str(root)], env=env, capture_output=True, timeout=120)
                self.assertEqual(created.returncode, 0, created.stderr)
                return root

            root = setup("first")
            second_root = setup("second")
            authority = {p: p.read_bytes() for p in [root / "state.rds", root / "output/seurat.rds",
                *sorted((root / "checkpoints").glob("*.rds"))]}
            library = env.get("R_LIBS_USER")
            try:
                opened = subprocess.run([rscript, "--vanilla", "-e",
                    'library(scAgentKit); a<-commandArgs(TRUE); x<-sc_run_open(a[1],checkout=a[2],browse=FALSE); cat(jsonlite::toJSON(x,auto_unbox=TRUE),"\n")',
                    str(root), str(Path(__file__).resolve().parents[2])], env=env, capture_output=True, timeout=120)
                self.assertEqual(opened.returncode, 0, opened.stderr)
                first = json.loads(opened.stdout.decode().splitlines()[-1])
                pids.add(first["pid"])
                self.assertFalse(first["reused"])
                # R wrapper remembers checkout; future use needs only project.
                again = subprocess.run([rscript, "--vanilla", "-e",
                    'library(scAgentKit); x<-sc_run_open(commandArgs(TRUE)[1],browse=FALSE); cat(jsonlite::toJSON(x,auto_unbox=TRUE),"\n")',
                    str(root)], cwd=directory, env=env, capture_output=True, timeout=120)
                self.assertEqual(again.returncode, 0, again.stderr)
                repeated = json.loads(again.stdout.decode().splitlines()[-1])
                self.assertTrue(repeated["reused"])
                self.assertEqual(repeated["pid"], first["pid"])
                port = urlsplit(first["url"]).port
                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=30)
                connection.request("GET", "/api/run-review/workbench?project_id=" + first["project_id"],
                    headers={"X-ScAgentKit-Run-Project": first["project_id"]})
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                self.assertEqual(json.loads(response.read())["project"]["project_id"], first["project_id"])
                connection.request("POST", "/api/run-review/continue", body="{}")
                response = connection.getresponse(); response.read()
                self.assertEqual(response.status, 403)
                connection.close()
                os.kill(first["pid"], signal.SIGTERM)
                time.sleep(.2)
                restarted = open_results(root, rscript, library, browse=False)
                pids.add(restarted["pid"])
                self.assertFalse(restarted["reused"])
                self.assertNotEqual(restarted["pid"], first["pid"])
                other = open_results(second_root, rscript, library, browse=False)
                pids.add(other["pid"])
                # A live unrelated service in stale metadata cannot be reused.
                (root / ".workbench-launcher/service.json").write_bytes(
                    (second_root / ".workbench-launcher/service.json").read_bytes())
                recovered = open_results(root, rscript, library, browse=False)
                pids.add(recovered["pid"])
                self.assertFalse(recovered["reused"])
                self.assertEqual(recovered["project_id"], first["project_id"])
                self.assertNotEqual(recovered["pid"], other["pid"])
                self.assertEqual({p: p.read_bytes() for p in authority}, authority)
            finally:
                for pid in pids:
                    try:
                        os.kill(pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    process = launcher._LAUNCHED.pop(pid, None)
                    if process is not None:
                        process.wait(timeout=10)


if __name__ == "__main__":
    unittest.main()
