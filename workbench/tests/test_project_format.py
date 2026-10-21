"""Unsupported projects fail before any runtime lock, cache or job is written."""
import contextlib
import io
import json
import os
import subprocess
import hashlib
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
from format_test_support import SourceFormatContract
import qc_runtime


def snapshot(root):
    return {str(path.relative_to(root)): (path.lstat().st_mode, path.lstat().st_mtime_ns,
            path.read_bytes() if path.is_file() else None)
            for path in [root, *root.rglob("*")]}


class ProjectFormatTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.project = self.root / "run"
        self.project.mkdir()
        self.contract = SourceFormatContract(self.root)
        self.contract.state(self.project, PROJECT_FORMAT_VERSION)
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
        return [lambda path, cls=cls: cls(path, rscript=str(self.contract.executable))
                for cls in (QCRuntime, RunReviewRuntime, RunWorkbenchRuntime, RunContinueRuntime, RunSuggestionRuntime)] + [
                    lambda path: RunSubclusterRuntime(path, self.workspace, rscript=str(self.contract.executable))]

    def test_every_run_runtime_rejects_missing_old_and_future_versions_without_writes(self):
        for version in (None, 1, 2, PROJECT_FORMAT_VERSION + 1):
            if version is None:
                self.marker.unlink(missing_ok=True)
            else:
                self.mark(version)
            for constructor in self.constructors():
                with self.subTest(version=version, runtime=constructor):
                    self.unchanged_rejection(lambda: constructor(self.project))

    def test_marker_has_exact_bounded_typed_contract(self):
        for value in ({"project_format_version": True}, {"project_format_version": str(PROJECT_FORMAT_VERSION)},
                      {"project_format_version": 3, "extra": None}, {}, [],
                      {"project_format_version": "x" * 4096}):
            self.marker.write_text(json.dumps(value))
            with self.subTest(value=str(value)[:60]):
                self.unchanged_rejection(lambda: check_project_format(self.project, rscript=str(self.contract.executable)))
        self.marker.unlink()
        target = self.root / "marker.json"
        target.write_text('{"project_format_version":3}')
        self.marker.symlink_to(target)
        self.unchanged_rejection(lambda: check_project_format(self.project, rscript=str(self.contract.executable)))

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

    def test_current_marker_cannot_admit_old_missing_or_future_R_state(self):
        self.mark()
        for version in (None, 1, 2, PROJECT_FORMAT_VERSION + 1):
            self.contract.state(self.project, version)
            for constructor in self.constructors():
                with self.subTest(version=version, runtime=constructor):
                    self.unchanged_rejection(lambda: constructor(self.project))

    def test_missing_or_linked_state_is_rejected_before_runtime_writes_or_R(self):
        self.mark()
        runtimes = [constructor(self.project) for constructor in self.constructors()]
        operations = [runtime.describe for runtime in runtimes]
        operations += [lambda constructor=constructor: constructor(self.project)
                       for constructor in self.constructors()]
        state = self.project / "state.rds"
        outside = self.root / "saved-state.rds"
        state.rename(outside)
        for linked in (False, True):
            if linked:
                state.symlink_to(outside)
            with patch("subprocess.run") as run, patch("subprocess.Popen") as launch:
                for operation in operations:
                    self.unchanged_rejection(operation)
                run.assert_not_called()
                launch.assert_not_called()

    def test_authoritative_checksum_and_parent_are_checked_with_current_markers(self):
        self.mark()
        self.contract.state(self.project, PROJECT_FORMAT_VERSION, bad_hash=True)
        for constructor in self.constructors():
            self.unchanged_rejection(lambda: constructor(self.project))
        parent = self.root / "parent"
        parent.mkdir()
        (parent / "project-format.json").write_text(json.dumps({"project_format_version": PROJECT_FORMAT_VERSION}))
        self.contract.state(parent, 2)
        self.contract.state(self.project, PROJECT_FORMAT_VERSION, parent=parent)
        for constructor in self.constructors():
            self.unchanged_rejection(lambda: constructor(self.project))
        self.contract.state(parent, PROJECT_FORMAT_VERSION)
        runtime = RunContinueRuntime(self.project, rscript=str(self.contract.executable))
        self.contract.state(parent, PROJECT_FORMAT_VERSION, bad_hash=True)
        self.unchanged_rejection(runtime.describe)

    def test_parent_requires_regular_nonsymlink_state_before_construction_and_live_writes(self):
        self.mark()
        parent = self.root / "parent"
        parent.mkdir()
        (parent / "project-format.json").write_text(json.dumps({"project_format_version": PROJECT_FORMAT_VERSION}))
        self.contract.state(parent, PROJECT_FORMAT_VERSION)
        self.contract.state(self.project, PROJECT_FORMAT_VERSION, parent=parent)
        qc, review, saved, continuation, suggestion, child = [constructor(self.project)
                                                            for constructor in self.constructors()]
        continuation_payload = {"project_id": "run", "input_hash": "a" * 64,
            "expected_revision": 0, "request_id": "request", "retry": False}
        control = {"project_id": "run", "input_hash": "a" * 64,
            "expected_revision": 0, "suggestion_hash": "b" * 64,
            "reviewer": "analyst", "reason": "Reviewed"}
        operations = [lambda constructor=constructor: constructor(self.project)
                      for constructor in self.constructors()]
        operations += [qc.describe, review.describe, saved.describe, continuation.describe,
            lambda: continuation.submit(continuation_payload),
            lambda: continuation.restore("analyst", "Restored", original_workers_stopped=True),
            suggestion.describe, suggestion.job_status,
            lambda: suggestion.submit(dict(control, request_id="request")),
            lambda: suggestion.operate("cancel", control, suggestion.csrf_token),
            child.describe, child.readiness]
        state = parent / "state.rds"
        original = state.read_bytes()
        state.unlink()
        for kind in ("missing", "dangling", "directory"):
            if kind == "dangling":
                state.symlink_to(parent / "absent-state.rds")
            elif kind == "directory":
                state.unlink()
                state.mkdir()
            for operation in operations:
                with self.subTest(parent_state=kind, operation=operation):
                    self.unchanged_rejection(operation)
        state.rmdir()
        state.write_bytes(original)
        before = snapshot(self.root)
        check_project_format(self.project, rscript=str(self.contract.executable))
        self.assertEqual(before, snapshot(self.root))

    def test_live_instances_reject_changed_state_before_local_writes(self):
        self.mark()
        qc, review, saved, continuation, suggestion, child = [constructor(self.project)
                                                            for constructor in self.constructors()]
        self.contract.state(self.project, 2)
        continuation_payload = {"project_id": "run", "input_hash": "a" * 64,
            "expected_revision": 0, "request_id": "request", "retry": False}
        suggestion_payload = {"project_id": "run", "input_hash": "a" * 64,
            "expected_revision": 0, "suggestion_hash": "b" * 64,
            "request_id": "request", "reviewer": "analyst", "reason": "Reviewed"}
        control = {k: v for k, v in suggestion_payload.items() if k != "request_id"}
        operations = [qc.describe, lambda: qc.decide(qc_decision(), qc.csrf_token),
            review.describe, lambda: review.decide(review_decision(), review.csrf_token),
            saved.describe, continuation.describe, lambda: continuation.submit(continuation_payload),
            lambda: continuation.restore("analyst", "Restored", original_workers_stopped=True),
            suggestion.describe, suggestion.job_status, lambda: suggestion.submit(suggestion_payload),
            lambda: suggestion.operate("approve", control, suggestion.csrf_token),
            lambda: suggestion.operate("cancel", control, suggestion.csrf_token), child.describe, child.readiness]
        for operation in operations:
            with self.subTest(operation=operation):
                self.unchanged_rejection(operation)

    def test_workers_reject_old_state_before_owner_job_or_request_publication(self):
        self.mark()
        continuation = RunContinueRuntime(self.project, rscript=str(self.contract.executable))
        suggestion = RunSuggestionRuntime(self.project, rscript=str(self.contract.executable))
        configs = [
            (dict(runtime=str(continuation.runtime), worker=str(continuation.worker),
                  bridge=str(continuation.bridge), code_hashes=continuation.code_hashes),
             [sys.executable, "-B", str(continuation.worker)]),
            (dict(code_hashes=suggestion.code_hashes),
             [sys.executable, "-B", str(suggestion.runtime), "--worker"])]
        for index, (config, argv) in enumerate(configs):
            # Trace only the test executable outside the protected fixture tree.
            # This proves the worker reached real R admission, rather than
            # passing this negative test through an unrelated early rejection.
            with tempfile.TemporaryDirectory() as observed:
                trace = Path(observed) / "format-invocation"
                contract = SourceFormatContract(observed, trace=trace)
                config.update(project=str(self.project), library=None, rscript=str(contract.executable))
                path = self.root / ("queued-worker-%s.json" % index)
                path.write_text(json.dumps(config))
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                self.contract.state(self.project, 2)
                before = snapshot(self.root)
                result = subprocess.run(argv + [str(path), digest, "0"], capture_output=True, timeout=30,
                    env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
                self.assertEqual(result.returncode, 2)
                self.assertEqual(trace.read_text(), str(qc_runtime.FORMAT_BRIDGE))
                self.assertEqual(before, snapshot(self.root))
                trace.unlink()
                (self.project / "state.rds").unlink()
                before = snapshot(self.root)
                result = subprocess.run(argv + [str(path), digest, "0"], capture_output=True, timeout=30,
                    env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
                self.assertEqual(result.returncode, 2)
                self.assertFalse(trace.exists())
                self.assertEqual(before, snapshot(self.root))

    def test_fixed_gate_is_configured_credential_free_and_fails_closed(self):
        self.mark()
        success = subprocess.CompletedProcess([], 0, b"scagentkit.project-format.ok\n", b"")
        with patch.dict(os.environ, {"CUSTOM_PROVIDER_AUTH": "private", "OPENAI_API_KEY": "private"}), \
                patch("qc_runtime.subprocess.run", return_value=success) as run:
            check_project_format(self.project, "operator-library", "operator-Rscript", 7)
        argv = run.call_args.args[0]
        options = run.call_args.kwargs
        self.assertEqual(argv, ["operator-Rscript", "--vanilla", str(qc_runtime.FORMAT_BRIDGE), str(self.project)])
        self.assertEqual(options["timeout"], 7)
        self.assertFalse(options["shell"])
        self.assertEqual(options["env"]["R_LIBS_USER"], "operator-library")
        self.assertFalse({"CUSTOM_PROVIDER_AUTH", "OPENAI_API_KEY"} & options["env"].keys())
        for name in ("R_PROFILE", "R_PROFILE_USER", "R_ENVIRON", "R_ENVIRON_USER"):
            self.assertEqual(options["env"][name], os.devnull)
        for failure in [OSError("R missing"), subprocess.TimeoutExpired("R", 7)]:
            with patch("qc_runtime.subprocess.run", side_effect=failure):
                self.unchanged_rejection(lambda: check_project_format(self.project))
        for result in [subprocess.CompletedProcess([], 1, b"scagentkit.project-format.ok\n", b""),
                       subprocess.CompletedProcess([], 0, b"unexpected output", b"")]:
            with patch("qc_runtime.subprocess.run", return_value=result):
                self.unchanged_rejection(lambda: check_project_format(self.project))
        self.mark(2)
        with patch("qc_runtime.subprocess.run") as run:
            self.unchanged_rejection(lambda: check_project_format(self.project))
            run.assert_not_called()

    def test_server_run_entry_rejects_before_runtime_state(self):
        self.mark(1)
        before = snapshot(self.root)
        with contextlib.redirect_stderr(io.StringIO()) as error, self.assertRaises(SystemExit) as stopped:
            server.main(["--run-project", str(self.project), "--local-continue", "--model-mock"])
        self.assertEqual(stopped.exception.code, 2)
        self.assertIn("请用原软件环境打开，或新建项目", error.getvalue())
        self.assertEqual(before, snapshot(self.root))

    def test_portable_loader_registry_and_import_reject_before_cache_lock(self):
        for version in (None, 1, 2, PROJECT_FORMAT_VERSION + 1):
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
        for version in (None, 1, 2, PROJECT_FORMAT_VERSION + 1):
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
