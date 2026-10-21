"""Unsupported projects fail before any runtime lock, cache or job is written."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evidence import PROJECT_FORMAT_VERSION
from qc_runtime import QCRuntime, check_project_format
from run_continue_runtime import RunContinueRuntime
from run_review_runtime import RunReviewRuntime
from run_subcluster_runtime import RunSubclusterRuntime
from run_suggestion_runtime import RunSuggestionRuntime
from run_workbench_runtime import RunWorkbenchRuntime
from project import ProjectError, ProjectLoader, ProjectRegistry
from project_runtime import ProjectRuntime
from open_results import open_results
from store import StoreError
import server
import start_analysis
from test_project import project_fixture, write_bundle, bundle_blobs, make_zip
from test_qc_runtime import decision as qc_decision
from test_run_review_runtime import decision as review_decision


def snapshot(root):
    return {str(path.relative_to(root)): (path.lstat().st_mode,
            path.read_bytes() if path.is_file() else None)
            for path in root.rglob("*")}


class ProjectFormatTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.project = self.root / "run"
        self.project.mkdir()
        (self.project / "state.rds").write_bytes(b"Opaque R authority; never deserialized in Python")
        self.workspace = self.root / "children"
        self.workspace.mkdir()
        self.marker = self.project / "project-format.json"

    def tearDown(self):
        self.temporary.cleanup()

    def mark(self, version=PROJECT_FORMAT_VERSION):
        self.marker.write_text(json.dumps({"project_format_version": version}), encoding="utf-8")

    def unchanged_rejection(self, operation, error=StoreError):
        before = snapshot(self.root)
        with self.assertRaisesRegex(error, "请用原软件环境打开，或新建项目"):
            operation()
        self.assertEqual(before, snapshot(self.root))

    def constructors(self):
        return [QCRuntime, RunReviewRuntime, RunWorkbenchRuntime, RunContinueRuntime,
                RunSuggestionRuntime, lambda path: RunSubclusterRuntime(path, self.workspace)]

    def test_every_run_runtime_rejects_missing_old_and_future_versions_without_writes(self):
        for version in (None, 1, PROJECT_FORMAT_VERSION + 1):
            if version is None:
                self.marker.unlink(missing_ok=True)
            else:
                self.mark(version)
            for constructor in self.constructors():
                with self.subTest(version=version, runtime=constructor):
                    self.unchanged_rejection(lambda: constructor(self.project))

    def test_marker_has_exact_bounded_typed_contract(self):
        for value in ({"project_format_version": True}, {"project_format_version": "2"},
                      {"project_format_version": 2, "extra": None}, {}, [],
                      {"project_format_version": "x" * 4096}):
            self.marker.write_text(json.dumps(value))
            with self.subTest(value=str(value)[:60]):
                self.unchanged_rejection(lambda: check_project_format(self.project))
        self.marker.unlink()
        target = self.root / "marker.json"
        target.write_text('{"project_format_version":2}')
        self.marker.symlink_to(target)
        self.unchanged_rejection(lambda: check_project_format(self.project))

    def test_live_runtime_rechecks_before_requests_and_mutations(self):
        self.mark()
        qc, review, saved, continuation, suggestion, child = [constructor(self.project)
                                                            for constructor in self.constructors()]
        self.mark(1)
        continuation_payload = {"project_id": "run", "input_hash": "a" * 64,
            "expected_revision": 0, "request_id": "request", "retry": False}
        suggestion_payload = {"project_id": "run", "input_hash": "a" * 64,
            "expected_revision": 0, "suggestion_hash": "b" * 64,
            "request_id": "request", "reviewer": "analyst", "reason": "Reviewed"}
        operations = [qc.describe, lambda: qc.decide(qc_decision(), qc.csrf_token),
            review.describe, lambda: review.decide(review_decision(), review.csrf_token),
            saved.describe, continuation.describe, lambda: continuation.submit(continuation_payload),
            lambda: continuation.restore("analyst", "Restored", original_workers_stopped=True),
            suggestion.describe, suggestion.job_status, lambda: suggestion.submit(suggestion_payload),
            lambda: suggestion.operate("approve", {k: v for k, v in suggestion_payload.items()
                if k != "request_id"}, suggestion.csrf_token), child.describe, child.readiness]
        with patch("subprocess.run") as run, patch("subprocess.Popen") as launch:
            for operation in operations:
                with self.subTest(operation=operation):
                    self.unchanged_rejection(operation)
            run.assert_not_called()
            launch.assert_not_called()

    def test_saved_view_and_start_reopen_reject_before_launcher_or_bridge(self):
        self.mark(1)
        self.unchanged_rejection(lambda: open_results(self.project, browse=False))
        input_path = self.root / "input.rds"
        input_path.write_bytes(b"opaque source")
        self.unchanged_rejection(lambda: start_analysis.main([str(input_path), "--project",
            str(self.project), "--species", "human", "--tissue", "fixture", "--research-goal",
            "test gate", "--reopen", "--no-browser"]))

    def test_server_run_entry_rejects_before_runtime_state(self):
        self.mark(1)
        before = snapshot(self.root)
        with contextlib.redirect_stderr(io.StringIO()) as error, self.assertRaises(SystemExit) as stopped:
            server.main(["--run-project", str(self.project), "--local-continue", "--model-mock"])
        self.assertEqual(stopped.exception.code, 2)
        self.assertIn("请用原软件环境打开，或新建项目", error.getvalue())
        self.assertEqual(before, snapshot(self.root))

    def test_portable_loader_registry_and_import_reject_before_cache_lock(self):
        for version in (None, 1, PROJECT_FORMAT_VERSION + 1):
            value = project_fixture()
            if version is None:
                value.pop("project_format_version")
            else:
                value["project_format_version"] = version
            bundle = write_bundle(self.root / "bundle", value)
            registry = ProjectRegistry(self.root / "cache", self.root / "journals")
            operations = [lambda: ProjectLoader(bundle).load(),
                lambda: ProjectRegistry(self.root / "cache", self.root / "journals", bundle),
                lambda: registry.add_directory(bundle),
                lambda: registry.import_zip(make_zip(bundle_blobs(value)))]
            for operation in operations:
                with self.subTest(version=version, operation=operation):
                    self.unchanged_rejection(operation, ProjectError)
            self.assertFalse((self.root / "cache").exists())
            self.assertFalse((self.root / "journals").exists())

    def test_portable_runtime_rejects_unversioned_or_old_evidence(self):
        runtime = ProjectRuntime(ProjectLoader(self.root / "unused"))
        for version in (None, 1, PROJECT_FORMAT_VERSION + 1):
            value = {"project_format_version": version}
            for operation in (lambda: runtime.describe(value), lambda: runtime.augment(value)):
                self.unchanged_rejection(operation)

    def test_portable_server_entry_rejects_before_cache(self):
        value = project_fixture()
        value["project_format_version"] = 1
        bundle = write_bundle(self.root / "bundle", value)
        current = write_bundle(self.root / "current-bundle")
        before = snapshot(self.root)
        with contextlib.redirect_stderr(io.StringIO()) as error, self.assertRaises(SystemExit) as stopped:
            server.main(["--project", str(current), "--project", str(bundle), "--project-cache", str(self.root / "cache"),
                         "--journal-root", str(self.root / "journals")])
        self.assertEqual(stopped.exception.code, 2)
        self.assertIn("请用原软件环境打开，或新建项目", error.getvalue())
        self.assertEqual(before, snapshot(self.root))


if __name__ == "__main__":
    unittest.main()
