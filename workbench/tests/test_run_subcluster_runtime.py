"""Subanalysis IPC validation with mocked R; no scientific execution or provider."""
import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from unittest.mock import MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evidence import canonical
from run_subcluster_runtime import RunSubclusterRuntime, KEYS
from store import StoreError


def create():
    return {"action": "create", "reviewer": "analyst", "reason": "Review the selected conditional scope", "request_id": "literal-request",
            "parent_scope_hash": "a" * 64, "expected_parent_revision": 10, "clusters": ["01", "NA"],
            "annotation_column": "child_subtype", "choices": {"qc": "retain_selected", "doublet": "keep", "batch": "none", "cycle": "none", "reference": "none"}}


def child_action(action="unknown"):
    value = {"action": action, "reviewer": "analyst", "reason": "Review this exact child", "request_id": "child-request",
             "child_id": "literal-child", "project_id": "literal-child", "input_hash": "b" * 64, "expected_revision": 20}
    if action == "apply": value.update(parent_scope_hash="a" * 64, expected_parent_revision=10, annotation_hash="c" * 64, apply_hash="d" * 64, column="child_subtype", outside="NA")
    if action == "undo": value.update(application_id="application-a", integration_revision=2)
    if action == "context": value.update(expected_context_hash="e" * 64, parent_scope_hash="a" * 64,
                                         expected_parent_revision=10, context={"notes": "An analyst hypothesis"})
    return value


def result(path=None):
    value = {"schema": "scagentkit.subcluster.bridge.v1", "parent": {"schema": "scagentkit.subcluster.parent.v1", "parent_project_id": "parent"},
             "children": [], "child": None, "child_path": None}
    if path:
        value.update(child_path=str(path), child={"schema": "scagentkit.subcluster.child.v1", "run": {"project_id": "literal-child"}})
    return value


def context_result(payload=None, historical=False):
    payload = payload or child_action("context")
    value = result()
    value["parent"].update(parent_scope_hash="a" * 64, expected_parent_revision=10)
    value["children"] = [{"project_id": "literal-child"}]
    value["child"] = {"schema": "scagentkit.subcluster.child.v1", "parent_current": True,
        "run": {"schema": "scagentkit.run.v1", "project_id": "literal-child", "input_hash": "b" * 64,
                "revision": 22 if historical else 21, "stage": "annotation_propose", "status": "awaiting_configuration",
                "child_context": {"schema": "scagentkit.child-context.v1", "generation": 2 if historical else 1,
                    "hash": "2" * 64 if historical else "1" * 64,
                    "previous_hash": "1" * 64 if historical else "e" * 64,
                    "effective": {"enabled": True, "lineage_hint": None, "identity_status": "unknown", "tissue": None,
                                  **payload["context"]}}},
        "origin": {"parent_project_id": "parent", "parent_scope_hash": "a" * 64}}
    value["child"]["context_receipt"] = {"schema": "scagentkit.child-context-receipt.v1", "action": "context", "outcome": "committed",
        **{key: copy.deepcopy(payload[key]) for key in ("request_id", "project_id", "input_hash", "expected_revision",
                 "parent_scope_hash", "expected_parent_revision", "context", "reviewer", "reason")},
        "request_hash": "f" * 64, "payload_sha256": hashlib.sha256((canonical(payload) + "\n").encode()).hexdigest(),
        "previous_context_hash": payload["expected_context_hash"], "context_hash": "1" * 64,
        "generation": 1, "committed_revision": 21, "journal_event_hash": "3" * 64, "is_current": not historical}
    if historical: value["child"]["run"]["child_context"]["effective"]["notes"] = "A later analyst correction"
    return value


class SubclusterRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.parent = self.root / "parent"; self.parent.mkdir()
        (self.parent / "state.rds").write_bytes(b"mock; never interpreted as R")
        self.workspace = self.root / "children"; self.workspace.mkdir()
        self.runtime = RunSubclusterRuntime(self.parent, self.workspace, library=str(self.root))

    def tearDown(self): self.temporary.cleanup()

    def process(self, value=None, error=None):
        def call(argv, **kwargs):
            Path(argv[-1]).write_text(canonical({"ok": not error, "result": value or result(), "error": error}))
            return subprocess.CompletedProcess(argv, int(bool(error)), b"private stdout", b"private stderr")
        return call

    def test_validate_all_supported_bound_operations(self):
        for value in (create(), child_action(), child_action("apply"), child_action("undo"), child_action("context"), dict(child_action("apply"), supersedes="earlier-own-application")):
            with self.subTest(action=value["action"]): self.runtime.validate(value)

    def test_missing_extra_and_secret_execution_fields_fail_closed(self):
        for name in create():
            value = create(); del value[name]
            with self.subTest(missing=name), self.assertRaises(StoreError): self.runtime.validate(value)
        for name in ("code", "rscript", "project_dir", "child_project", "provider", "chat_fn", "cycle_diagnostics", "library", "url"):
            with self.subTest(extra=name), self.assertRaises(StoreError): self.runtime.validate(dict(create(), **{name: "never"}))

    def test_literal_cluster_scope_types_duplicates_and_bounds(self):
        for labels in (None, [], [1], ["01", "01"], [""], ["a\x00b"], ["a"] * 1001):
            value = create(); value["clusters"] = labels
            with self.subTest(labels=labels), self.assertRaises(StoreError): self.runtime.validate(value)
        value = create(); value["clusters"] = ["1", "01", "NA", "cell space"]
        self.runtime.validate(value)

    def test_choices_explicit_and_no_cycle_configuration_or_doublet_refit(self):
        for key, choice in (("qc", "automatic"), ("doublet", "remove_predicted"), ("batch", "harmony"), ("cycle", "recompute"), ("reference", "network")):
            value = create(); value["choices"][key] = choice
            with self.subTest(key=key), self.assertRaises(StoreError): self.runtime.validate(value)
        value = create(); del value["choices"]["cycle"]
        with self.assertRaises(StoreError): self.runtime.validate(value)

    def test_fingerprints_revision_and_cross_project_are_strict(self):
        for action in ("unknown", "apply", "undo"):
            for field, invalid in (("project_id", "foreign"), ("input_hash", "A" * 64), ("expected_revision", True), ("expected_revision", -1)):
                value = child_action(action); value[field] = invalid
                with self.subTest(action=action, field=field), self.assertRaises(StoreError): self.runtime.validate(value)
        for name in ("parent_scope_hash", "annotation_hash", "apply_hash"):
            value = child_action("apply"); value[name] = "wrong"
            with self.subTest(name=name), self.assertRaises(StoreError): self.runtime.validate(value)
        with self.assertRaises(StoreError): self.runtime.validate(dict(child_action("apply"), outside="original"))

    def test_strategy_json_is_typed_never_code_provider_or_secret_fields(self):
        for proposal in ([], "source('never')", {}, {"schema": "scagentkit.strategy.v1", "provider": {}}, {"schema": "scagentkit.strategy.v1", "analysis": {"api_key": "never"}}):
            with self.subTest(proposal=proposal), self.assertRaises(StoreError): self.runtime.validate(dict(create(), strategy_proposal=proposal))
        self.runtime.validate(dict(create(), strategy_proposal={"schema": "scagentkit.strategy.v1", "rationale": "$(literal) `source('never')`"}))

    def test_context_is_a_nonempty_partial_allowlist_never_execution_configuration(self):
        for action in (None, [], {}, True, 1):
            with self.subTest(action=action), self.assertRaises(StoreError):
                self.runtime.validate(dict(child_action("context"), action=action))
        for edits in (None, [], "source('never')", {}, False, 1, {"code": "never"},
                      {"notes": {"provider": "never"}}, {"notes": ["literal"]},
                      {"parent_snapshot": {}}, {"generation": 3}, {"hash": "a" * 64},
                      {"tissue": "blood", "api_key": "never"}):
            with self.subTest(edits=edits), self.assertRaises(StoreError):
                self.runtime.validate(dict(child_action("context"), context=edits))
        value = child_action("context")
        value["context"] = {"enabled": False, "lineage_hint": None, "identity_status": "unknown", "tissue": None,
                            "notes": "Literal `source('never')` $(never)\nSecond line\r\n\tA note"}
        self.runtime.validate(value)
        for key in ("provider", "chat_fn", "project_dir", "library", "rscript", "expected_context_generation"):
            with self.subTest(key=key), self.assertRaises(StoreError):
                self.runtime.validate(dict(value, **{key: "never"}))

    def test_context_fields_use_boolean_enum_nullable_text_and_utf8_byte_limits(self):
        invalid = [{"enabled": value} for value in (None, 0, 1, "true", [], {})]
        invalid += [{"identity_status": value} for value in (None, True, 1, [], {}, "known", "Labeled")]
        for key in ("lineage_hint", "tissue", "notes"):
            invalid += [{key: value} for value in (False, 5, "", " \t", "a\x00b", "a\x01b", "a\x7fb", "\ud800")]
            invalid.append({key: "汉" * (667 if key == "notes" else 67)})
        for key in ("lineage_hint", "tissue"):
            invalid.extend({key: value} for value in ("a\nb", "a\rb", "a\tb"))
        for edits in invalid:
            with self.subTest(edits=repr(edits)), self.assertRaises(StoreError):
                self.runtime.validate(dict(child_action("context"), context=edits))
        for edits in ({"notes": "汉" * 666 + "ab"}, {"tissue": "汉" * 66 + "ab"},
                      {"lineage_hint": "a" * 200}, {"notes": "a" * 2000},
                      {"lineage_hint": None, "tissue": None, "notes": None}, {"enabled": True}):
            with self.subTest(edits=edits): self.runtime.validate(dict(child_action("context"), context=edits))

    def test_context_requires_exact_child_parent_and_context_bindings(self):
        value = child_action("context")
        for field in value:
            missing = dict(value); missing.pop(field)
            with self.subTest(missing=field), self.assertRaises(StoreError): self.runtime.validate(missing)
        for field, item in (("child_id", "foreign"), ("project_id", "foreign"),
                            ("expected_revision", True), ("expected_parent_revision", True),
                            ("expected_parent_revision", -1), ("expected_context_hash", "A" * 64),
                            ("expected_context_hash", "wrong"), ("parent_scope_hash", None)):
            with self.subTest(field=field), self.assertRaises(StoreError): self.runtime.validate(dict(value, **{field: item}))

    def test_context_fixed_ipc_and_replayed_payload_are_passed_unchanged_to_r_authority(self):
        value = child_action("context"); value["context"]["notes"] = "literal\n$(never) `source('never')`"
        original = copy.deepcopy(value)
        def process(argv, **kwargs):
            self.assertEqual(json.loads(Path(argv[-2]).read_text()), original)
            return self.process(context_result(original))(argv, **kwargs)
        with patch.dict(os.environ, {name: "never-inherit" for name in KEYS}), \
                patch("run_subcluster_runtime.subprocess.run", side_effect=process) as call:
            self.runtime.operate(value, self.runtime.csrf_token)
            self.runtime.operate(value, self.runtime.csrf_token)
        self.assertEqual(call.call_count, 2)  # R, not a Python shortcut, owns idempotent request replay.
        self.assertEqual(value, original)
        for args in call.call_args_list:
            self.assertEqual(args.args[0][:6], ["Rscript", "--vanilla", str(self.runtime.bridge), "operation",
                                               str(self.parent.resolve()), str(self.workspace.resolve())])
            self.assertFalse(args.kwargs["shell"])
            self.assertFalse(set(KEYS) & set(args.kwargs["env"]))

    def test_context_never_accepts_foreign_stale_or_unregistered_success_receipt(self):
        variants = []
        for field, item in (("parent_scope_hash", "f" * 64), ("expected_parent_revision", 11)):
            value = context_result(); value["parent"][field] = item; variants.append(value)
        for field, item in (("project_id", "foreign"), ("input_hash", "f" * 64)):
            value = context_result(); value["child"]["run"][field] = item; variants.append(value)
        value = context_result(); value["child"]["parent_current"] = False; variants.append(value)
        value = context_result(); value["child"]["origin"]["parent_project_id"] = "foreign"; variants.append(value)
        value = context_result(); value["child"]["origin"]["parent_scope_hash"] = "f" * 64; variants.append(value)
        for listing in ([], [{"project_id": "foreign"}], [{"project_id": "literal-child"}] * 2):
            value = context_result(); value["children"] = listing; variants.append(value)
        for value in variants:
            with self.subTest(value=value), patch("run_subcluster_runtime.subprocess.run", side_effect=self.process(value)):
                with self.assertRaisesRegex(StoreError, "foreign or stale"): self.runtime.operate(child_action("context"), self.runtime.csrf_token)

    def test_context_stale_lock_and_reused_request_errors_are_not_hidden_or_retried(self):
        for error in ("Stale child context; inspect its exact current hash", "Run is locked", "request_id reused with different payload"):
            with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process(error=error)) as call:
                with self.subTest(error=error), self.assertRaises(StoreError):
                    self.runtime.operate(child_action("context"), self.runtime.csrf_token)
                self.assertEqual(call.call_count, 1)
        with patch("run_subcluster_runtime.subprocess.run") as call:
            with self.assertRaises(StoreError): self.runtime.operate(child_action("context"), "foreign-token")
            with self.assertRaises(StoreError): self.runtime.operate(dict(child_action("context"), context={"code": "never"}), self.runtime.csrf_token)
        call.assert_not_called()

    def test_context_same_scope_old_success_and_foreign_receipts_do_not_acknowledge_this_request(self):
        variants = []
        value = context_result(); value["child"].pop("context_receipt"); variants.append(value)
        for field, item in (("request_id", "an-earlier-request"), ("request_hash", "wrong"),
                            ("payload_sha256", "0" * 64), ("project_id", "foreign"), ("input_hash", "0" * 64),
                            ("parent_scope_hash", "0" * 64), ("expected_revision", 19), ("expected_parent_revision", 11),
                            ("previous_context_hash", "0" * 64), ("context", {"notes": "an older payload"}),
                            ("reviewer", "other"), ("reason", "other"), ("outcome", "queued"), ("journal_event_hash", None),
                            ("generation", True), ("generation", 0), ("committed_revision", True),
                            ("committed_revision", 20), ("committed_revision", 22), ("context_hash", "e" * 64),
                            ("is_current", False), ("is_current", 1)):
            value = context_result(); value["child"]["context_receipt"][field] = item; variants.append(value)
        value = context_result(); value["child"]["context_receipt"]["extra"] = "never"; variants.append(value)
        value = context_result(); value["child"]["run"]["child_context"]["effective"]["notes"] = "old current note"; variants.append(value)
        value = context_result(); value["child"]["run"]["child_context"]["previous_hash"] = "0" * 64; variants.append(value)
        value = context_result(); value["child"]["run"]["child_context"]["generation"] = 0; variants.append(value)
        for value in variants:
            with self.subTest(receipt=value["child"].get("context_receipt")), \
                    patch("run_subcluster_runtime.subprocess.run", side_effect=self.process(value)):
                with self.assertRaisesRegex(StoreError, "verified receipt"): self.runtime.operate(child_action("context"), self.runtime.csrf_token)

    def test_context_exact_replay_acknowledges_historical_commit_without_replacing_newer_context(self):
        payload = child_action("context")
        saved = context_result(payload, historical=True)
        with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process(saved)):
            answer = self.runtime.operate(payload, self.runtime.csrf_token)
        self.assertEqual(answer["child"]["context_receipt"]["generation"], 1)
        self.assertFalse(answer["child"]["context_receipt"]["is_current"])
        self.assertEqual(answer["child"]["run"]["child_context"]["generation"], 2)
        self.assertEqual(answer["child"]["run"]["child_context"]["effective"]["notes"], "A later analyst correction")
        for mutate in (lambda value: value["child"]["context_receipt"].update(is_current=True),
                       lambda value: value["child"]["run"]["child_context"].update(generation=1),
                       lambda value: value["child"]["run"].update(revision=20)):
            value = copy.deepcopy(saved); mutate(value)
            with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process(value)):
                with self.assertRaisesRegex(StoreError, "verified receipt"): self.runtime.operate(payload, self.runtime.csrf_token)

    def test_context_receipt_remains_verifiable_after_new_steps_with_same_context(self):
        value = context_result()
        value["child"]["run"].update(revision=24, status="awaiting_review")
        with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process(value)):
            answer = self.runtime.operate(child_action("context"), self.runtime.csrf_token)
        self.assertTrue(answer["child"]["context_receipt"]["is_current"])  # Context identity only.
        self.assertLess(answer["child"]["context_receipt"]["committed_revision"], answer["child"]["run"]["revision"])
        self.assertEqual(answer["child"]["run"]["status"], "awaiting_review")

    def test_fixed_shell_free_ipc_removes_all_provider_secrets(self):
        value = create()
        def process(argv, **kwargs):
            self.assertEqual(json.loads(Path(argv[-2]).read_text()), value)
            self.assertEqual(Path(argv[-2]).stat().st_mode & 0o777, 0o600)
            return self.process()(argv, **kwargs)
        with patch.dict(os.environ, {name: "never-inherit" for name in KEYS}), patch("run_subcluster_runtime.subprocess.run", side_effect=process) as call:
            answer = self.runtime.operate(value, self.runtime.csrf_token)
        argv = call.call_args.args[0]
        self.assertEqual(argv[:4], ["Rscript", "--vanilla", str(self.runtime.bridge), "operation"])
        self.assertEqual(argv[4:6], [str(self.parent.resolve()), str(self.workspace.resolve())])
        self.assertFalse(call.call_args.kwargs["shell"])
        self.assertFalse(any(name in call.call_args.kwargs["env"] for name in KEYS))
        self.assertNotIn("child_path", answer)
        self.assertNotIn("private stdout", canonical(answer)); self.assertNotIn("private stderr", canonical(answer))

    def test_inspect_bound_column_supersession_as_data(self):
        with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process()) as call:
            self.runtime.describe("literal-child", column="fine_2", supersedes="earlier")
        self.assertEqual(call.call_args.args[0][3], "inspect")

    def test_bad_tokens_and_directory_replacement_never_start_r(self):
        with patch("run_subcluster_runtime.subprocess.run") as call:
            for token in (None, "wrong"):
                with self.subTest(token=token), self.assertRaises(StoreError): self.runtime.operate(create(), token)
            old = self.root / "original-workspace"; self.workspace.rename(old); self.workspace.mkdir()
            with self.assertRaises(StoreError): self.runtime.describe()
        call.assert_not_called()

    def test_bridge_errors_timeout_invalid_and_replaced_parent_fail_closed(self):
        with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process(error="Stale parent scope")):
            with self.assertRaisesRegex(StoreError, "Stale parent"): self.runtime.describe()
        with patch("run_subcluster_runtime.subprocess.run", side_effect=subprocess.TimeoutExpired("fixed", 1)):
            with self.assertRaisesRegex(StoreError, "timed out"): self.runtime.describe()
        with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process({"schema": "wrong"})):
            with self.assertRaisesRegex(StoreError, "unverified"): self.runtime.describe()
        with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process()): self.runtime.describe()
        replaced = result(); replaced["parent"]["parent_project_id"] = "different"
        with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process(replaced)):
            with self.assertRaisesRegex(StoreError, "replaced"): self.runtime.describe()

    def test_child_resolution_rechecks_r_registry_per_request_and_only_child_continuation(self):
        path = self.workspace / "child"; path.mkdir(); (path / "state.rds").write_bytes(b"mock")
        with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process(result(path))) as call, \
                patch("run_subcluster_runtime.RunReviewRuntime") as review, patch("run_subcluster_runtime.QCRuntime") as qc, patch("run_subcluster_runtime.RunContinueRuntime") as continuation:
            review.return_value.project = path.resolve()
            first = self.runtime.child_context("literal-child"); second = self.runtime.child_context("literal-child")
        self.assertIs(first, second); self.assertEqual(call.call_count, 2)
        review.assert_called_once(); qc.assert_called_once(); continuation.assert_not_called()
        self.assertFalse((self.parent / ".workbench-jobs").exists())

    def test_child_resolution_rejects_foreign_paths_or_identity(self):
        for value in (result(self.parent), result(self.root)):
            with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process(value)), self.assertRaises(StoreError): self.runtime.child_context("literal-child")
        path = self.workspace / "child"; path.mkdir()
        value = result(path); value["child"]["run"]["project_id"] = "foreign"
        with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process(value)), self.assertRaises(StoreError): self.runtime.child_context("literal-child")

    def test_parent_and_workspace_must_not_overlap_or_use_symlink(self):
        nested = self.parent / "nested"; nested.mkdir()
        for workspace in (self.parent, nested, self.root):
            with self.subTest(workspace=str(workspace)), self.assertRaises(StoreError): RunSubclusterRuntime(self.parent, workspace)
        link = self.root / "link"; link.symlink_to(self.workspace, target_is_directory=True)
        with self.assertRaises(StoreError): RunSubclusterRuntime(self.parent, link)

    def test_completed_scoped_startup_never_constructs_parent_continue(self):
        import server
        fake = MagicMock(); fake.server_address = ("127.0.0.1", 19001)
        with patch("server.QCRuntime"), patch("server.RunReviewRuntime") as review, \
                patch("server.RunSubclusterRuntime") as scope, patch("server.RunContinueRuntime") as continuation, \
                patch("server.WorkbenchServer", return_value=fake):
            review.return_value.describe.return_value = {"run": {"status": "complete", "revision": 50}}
            scope.return_value.readiness.return_value = {"frozen": True, "parent_run": {"status": "complete", "revision": 50}}
            server.main(["--run-project", str(self.parent), "--subcluster-workspace", str(self.workspace), "--local-continue", "--port", "0"])
        continuation.assert_not_called()
        review.return_value.describe.assert_not_called()
        scope.return_value.readiness.assert_called_once_with()
        scope.assert_called_once_with(str(self.parent), str(self.workspace), None, "Rscript", True)
        self.assertFalse((self.parent / ".workbench-jobs").exists())

    def test_incomplete_scoped_startup_constructs_parent_continue_and_model(self):
        import server
        fake = MagicMock(); fake.server_address = ("127.0.0.1", 19001)
        with patch("server.QCRuntime"), patch("server.RunReviewRuntime"), \
                patch("server.RunSubclusterRuntime") as scope, patch("server.RunContinueRuntime") as continuation, \
                patch("server.RunSuggestionRuntime") as model, patch("server.WorkbenchServer", return_value=fake):
            scope.return_value.readiness.return_value = {"frozen": False, "parent_run": {"status": "awaiting_configuration", "revision": 50}}
            server.main(["--run-project", str(self.parent), "--subcluster-workspace", str(self.workspace), "--local-continue", "--model-mock", "--port", "0"])
        continuation.assert_called_once_with(str(self.parent), None, "Rscript")
        model.assert_called_once_with(str(self.parent), None, "Rscript", simulate=True, worker_timeout=300)

    def test_unscoped_startup_keeps_normal_review_and_continue(self):
        import server
        fake = MagicMock(); fake.server_address = ("127.0.0.1", 19002)
        with patch("server.QCRuntime"), patch("server.RunReviewRuntime") as review, \
                patch("server.RunSubclusterRuntime") as scope, patch("server.RunContinueRuntime") as continuation, \
                patch("server.WorkbenchServer", return_value=fake):
            review.return_value.describe.return_value = {"run": {"status": "ready", "revision": 51}}
            server.main(["--run-project", str(self.parent), "--local-continue", "--port", "0"])
        review.return_value.describe.assert_called_once_with()
        continuation.assert_called_once_with(str(self.parent), None, "Rscript")
        scope.assert_not_called()


if __name__ == "__main__": unittest.main()
