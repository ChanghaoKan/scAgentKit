"""Run-review HTTP and fixed IPC boundaries; scientific validation belongs to R.

The stateful HTTP fixture deliberately models coordinator conflicts rather than
interpreting Seurat files. Actual R scope, marker and journal checks are tested
by the coordinator suite and the separate browser/R acceptance run.
"""
import copy
import http.client
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evidence import canonical
from qc_runtime import QCRuntime
from run_review_runtime import RunReviewRuntime
from server import WorkbenchServer
from store import StoreError


KEYS = ("DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY",
        "ANTHROPIC_API_KEY", "GROK_API_KEY")


def inspector(kind="annotation"):
    return {"schema": "scagentkit.run.v1", "project_id": "literal-project",
            "revision": 12, "status": "awaiting_review",
            "stage": "annotation_propose" if kind == "annotation" else "qc_propose",
            "input_hash": "a" * 64,
            "pending": {"kind": kind, "hash": "b" * 64},
            "review_node": {"kind": kind, "hash": "c" * 64}}


def decision(action="approve", kind="annotation"):
    return {"action": action, "kind": kind, "project_id": "literal-project",
            "input_hash": "a" * 64, "proposal_hash": "b" * 64,
            "review_hash": "c" * 64, "expected_revision": 12,
            "reviewer": "analyst", "reason": "Review the measured exact scope"}


class RunReviewRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.project = Path(self.temp.name) / "project"
        self.project.mkdir()
        (self.project / "state.rds").write_bytes(b"fixture; never interpreted by Python")
        self.runtime = RunReviewRuntime(self.project, library=self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    @staticmethod
    def process_result(run=None, error=None, stdout=b"private stdout", stderr=b"private stderr"):
        def process(argv, **kwargs):
            answer = {"ok": error is None, "result": (run or inspector()) if error is None else None,
                      "error": error}
            Path(argv[-1]).write_text(canonical(answer), encoding="utf-8")
            return subprocess.CompletedProcess(argv, int(error is not None), stdout, stderr)
        return process

    def test_fixed_shell_free_bridge_and_secret_environment_removed(self):
        payload = decision("revise")
        payload["proposal"] = {"rationale": "$(touch /not-executed) `literal text`; source('x')"}
        def process_result(argv, **kwargs):
            request = Path(argv[-2])
            self.assertEqual(json.loads(request.read_text(encoding="utf-8")), payload)
            self.assertEqual(request.stat().st_mode & 0o777, 0o600)
            return self.process_result()(argv, **kwargs)
        with patch.dict(os.environ, {key: "never-export-this" for key in KEYS}), \
                patch("qc_runtime.subprocess.run", side_effect=process_result) as process:
            view = self.runtime.decide(payload, self.runtime.csrf_token)
        call = process.call_args
        self.assertFalse(call.kwargs["shell"])
        self.assertEqual(call.args[0][:4], ["Rscript", "--vanilla", str(self.runtime.bridge), "decision"])
        self.assertEqual(self.runtime.bridge.name, "run_review_bridge.R")
        self.assertEqual(call.args[0][4], str(self.project.resolve()))
        self.assertFalse(any(key in call.kwargs["env"] for key in KEYS))
        self.assertNotIn("never-export-this", canonical(view))
        self.assertNotIn("private stdout", canonical(view))
        self.assertNotIn("private stderr", canonical(view))
        self.assertEqual(view["schema"], "scagentkit.run-review.workbench.v1")
        self.assertEqual(view["csrf_token"], self.runtime.csrf_token)

    def test_inspect_uses_fixed_operation_without_decision_fields(self):
        def process(argv, **kwargs):
            self.assertEqual(argv[3], "inspect")
            self.assertEqual(json.loads(Path(argv[-2]).read_text()), {})
            return self.process_result()(argv, **kwargs)
        with patch("qc_runtime.subprocess.run", side_effect=process) as bridge:
            view = self.runtime.describe()
        self.assertEqual(bridge.call_count, 1)
        self.assertEqual(view["run"]["review_node"]["kind"], "annotation")

    def test_all_supported_action_kind_combinations_validate(self):
        for kind in ("qc", "annotation"):
            for action in ("approve", "reject", "revise"):
                payload = decision(action, kind)
                if action == "revise": payload["proposal"] = {"rationale": "Typed proposal"}
                with self.subTest(kind=kind, action=action): self.runtime.validate(payload)
        self.runtime.validate(decision("preview", "qc"))
        self.runtime.validate(dict(decision("undo"), decision_id="decision-123"))

    def test_action_kind_boundaries_are_explicit(self):
        for action, kind in (("preview", "annotation"), ("undo", "qc"), ("resume", "qc"),
                             ("execute", "annotation"), ("approve", "batch")):
            payload = decision(action, kind)
            if action == "undo": payload["decision_id"] = "decision-123"
            with self.subTest(action=action, kind=kind), self.assertRaises(StoreError):
                self.runtime.validate(payload)

    def test_action_and_kind_json_types_rejected_as_validation_errors(self):
        for field in ("action", "kind"):
            for value in (None, [], {}, True, 12):
                payload = decision(); payload[field] = value
                with self.subTest(field=field, value=value), self.assertRaises(StoreError):
                    self.runtime.validate(payload)

    def test_exact_common_fields_required(self):
        for missing in decision():
            payload = decision(); del payload[missing]
            with self.subTest(missing=missing), self.assertRaises(StoreError):
                self.runtime.validate(payload)
        for payload in (None, [], "approve", True):
            with self.subTest(payload=payload), self.assertRaises(StoreError): self.runtime.validate(payload)

    def test_browser_cannot_supply_execution_source_path_provider_or_resume(self):
        for field in ("code", "rscript", "project_dir", "source", "provider", "url",
                      "request_id", "chat_fn", "resume", "output_dir", "library"):
            with self.subTest(field=field), self.assertRaises(StoreError):
                self.runtime.validate(dict(decision(), **{field: "arbitrary"}))

    def test_fingerprints_are_exact_lowercase_sha256(self):
        for field in ("input_hash", "proposal_hash", "review_hash"):
            for value in (None, "old", "C" * 64, "a" * 63, "a" * 65, "a" * 64 + "\n", 12):
                payload = decision(); payload[field] = value
                with self.subTest(field=field, value=str(value)[:20]), self.assertRaises(StoreError):
                    self.runtime.validate(payload)

    def test_revision_is_nonnegative_integer_without_bool_coercion(self):
        for value in (True, False, -1, 1.5, "12", None):
            payload = decision(); payload["expected_revision"] = value
            with self.subTest(value=value), self.assertRaises(StoreError): self.runtime.validate(payload)

    def test_identity_reviewer_reason_require_bounded_literal_text(self):
        for field, limit in (("project_id", 200), ("reviewer", 200), ("reason", 4000)):
            for value in (None, "", " ", "a\x00b", "a" * (limit + 1), 12):
                payload = decision(); payload[field] = value
                with self.subTest(field=field, value=str(value)[:20]), self.assertRaises(StoreError):
                    self.runtime.validate(payload)

    def test_revise_requires_object_and_other_actions_reject_proposal(self):
        for kind in ("qc", "annotation"):
            with self.subTest(kind=kind), self.assertRaises(StoreError): self.runtime.validate(decision("revise", kind))
            for proposal in (None, [], "R code", True):
                with self.subTest(kind=kind, proposal=proposal), self.assertRaises(StoreError):
                    self.runtime.validate(dict(decision("revise", kind), proposal=proposal))
        for action in ("approve", "reject", "preview", "undo"):
            payload = decision(action, "qc" if action == "preview" else "annotation")
            if action == "undo": payload["decision_id"] = "decision-123"
            with self.subTest(action=action), self.assertRaises(StoreError):
                self.runtime.validate(dict(payload, proposal={}))

    def test_sensitivity_and_gene_panels_only_qc_preview_or_revise(self):
        for action in ("preview", "revise"):
            payload = decision(action, "qc")
            if action == "revise": payload["proposal"] = {}
            self.runtime.validate(dict(payload, sensitivity=[], gene_panels={"literal": ["CD3D"]}))
            self.runtime.validate(dict(payload, sensitivity=None, gene_panels=None))
            for field, value in (("sensitivity", {}), ("gene_panels", [])):
                with self.subTest(action=action, field=field), self.assertRaises(StoreError):
                    self.runtime.validate(dict(payload, **{field: value}))
        for kind, action in (("qc", "approve"), ("qc", "reject"),
                             ("annotation", "approve"), ("annotation", "reject"), ("annotation", "revise")):
            payload = decision(action, kind)
            if action == "revise": payload["proposal"] = {}
            for field, value in (("sensitivity", []), ("gene_panels", {})):
                with self.subTest(kind=kind, action=action, field=field), self.assertRaises(StoreError):
                    self.runtime.validate(dict(payload, **{field: value}))

    def test_undo_requires_decision_id_and_rejects_it_on_other_actions(self):
        with self.assertRaises(StoreError): self.runtime.validate(decision("undo"))
        for value in (None, "", " ", "a\x00b", 12):
            with self.subTest(value=value), self.assertRaises(StoreError):
                self.runtime.validate(dict(decision("undo"), decision_id=value))
        with self.assertRaises(StoreError): self.runtime.validate(dict(decision(), decision_id="decision-123"))

    def test_payload_size_is_bounded_without_executing_bridge(self):
        payload = dict(decision("revise"), proposal={"records": ["x" * (1024 * 1024)]})
        with patch("qc_runtime.subprocess.run") as process, self.assertRaises(StoreError) as problem:
            self.runtime.decide(payload, self.runtime.csrf_token)
        self.assertEqual(problem.exception.status, 413)
        process.assert_not_called()

    def test_current_server_token_required_before_process(self):
        with patch("qc_runtime.subprocess.run") as process:
            for token in (None, "", "wrong", 123):
                with self.subTest(token=token), self.assertRaises(StoreError) as problem:
                    self.runtime.decide(decision(), token)
                self.assertEqual(problem.exception.status, 403)
            process.assert_not_called()

    def test_restarted_adapter_has_fresh_token_and_rejects_previous_token(self):
        restarted = RunReviewRuntime(self.project)
        self.assertNotEqual(restarted.csrf_token, self.runtime.csrf_token)
        with patch("qc_runtime.subprocess.run") as process, self.assertRaises(StoreError) as problem:
            restarted.decide(decision(), self.runtime.csrf_token)
        self.assertEqual(problem.exception.status, 403)
        process.assert_not_called()

    def test_bridge_change_fails_before_process(self):
        self.runtime.bridge_hash = "changed"
        with patch("qc_runtime.subprocess.run") as process, self.assertRaises(StoreError): self.runtime.describe()
        process.assert_not_called()

    def test_replaced_project_directory_rejected(self):
        self.project.rename(self.project.with_name("old-project")); self.project.mkdir()
        (self.project / "state.rds").write_bytes(b"replacement")
        with patch("qc_runtime.subprocess.run") as process, self.assertRaises(StoreError): self.runtime.describe()
        process.assert_not_called()

    def test_r_stale_scope_and_hallucinated_gene_errors_preserved_without_logs(self):
        for error in ("Stale review hash", "Input hash changed", "Proposal hash changed",
                      "Unknown cited gene: NOT_A_MEASURED_GENE", "Undo requires a completed annotation decision"):
            payload = dict(decision("revise"), proposal={"gene": "NOT_A_MEASURED_GENE"})
            with self.subTest(error=error), \
                    patch("qc_runtime.subprocess.run", side_effect=self.process_result(error=error)), \
                    self.assertRaises(StoreError) as problem:
                self.runtime.decide(payload, self.runtime.csrf_token)
            self.assertEqual(problem.exception.status, 409)
            self.assertEqual(str(problem.exception), error)
            self.assertNotIn("private", str(problem.exception))

    def test_bounded_timeout_is_not_retried(self):
        with patch("qc_runtime.subprocess.run", side_effect=subprocess.TimeoutExpired("fixed", 120)) as process, \
                self.assertRaises(StoreError) as problem: self.runtime.describe()
        self.assertEqual(process.call_count, 1)
        self.assertIn("Inspect", str(problem.exception))

    def test_response_project_identity_bound_across_processes(self):
        with patch("qc_runtime.subprocess.run", side_effect=self.process_result()): self.runtime.describe()
        replaced = inspector(); replaced["project_id"] = "replacement"
        with patch("qc_runtime.subprocess.run", side_effect=self.process_result(replaced)), self.assertRaises(StoreError):
            self.runtime.describe()

    def test_duplicate_json_invalid_envelope_or_inspector_rejected(self):
        contents = ('{"ok":true,"ok":false,"result":null,"error":null}', '{}', '[]',
                    canonical({"ok": True, "result": {}, "error": None}),
                    canonical({"ok": True, "result": {"schema": "wrong", "project_id": "literal-project"}, "error": None}))
        for content in contents:
            def invalid(argv, **kwargs):
                Path(argv[-1]).write_text(content)
                return subprocess.CompletedProcess(argv, 0, b"", b"")
            with self.subTest(content=content), patch("qc_runtime.subprocess.run", side_effect=invalid), \
                    self.assertRaises((StoreError, ValueError)): self.runtime.describe()

    def test_missing_response_not_replaced_by_stdout(self):
        with patch("qc_runtime.subprocess.run", return_value=subprocess.CompletedProcess([], 0, b"pretend JSON", b"key value")), \
                self.assertRaises(StoreError) as problem: self.runtime.describe()
        self.assertNotIn("key value", str(problem.exception))
        self.assertNotIn("pretend JSON", str(problem.exception))

    def test_library_path_list_keeps_operator_dependencies_separate(self):
        dependency = Path(self.temp.name) / "dependency-library"; dependency.mkdir()
        runtime = RunReviewRuntime(self.project, library=os.pathsep.join((self.temp.name, str(dependency))))
        self.assertEqual(runtime.library, os.pathsep.join((str(Path(self.temp.name).resolve()), str(dependency.resolve()))))


class MockRunReview(RunReviewRuntime):
    """Stateful conflict fixture; this is not evidence of R scientific behavior."""
    def __init__(self, *args, kind="annotation", **kwargs):
        super().__init__(*args, **kwargs)
        self.run = inspector(kind)
        # Model the verified identity established by the real CLI's startup
        # inspection before accepting HTTP requests.
        self.project_id = self.run["project_id"]
        self.calls = []
        self.last_decision_id = None

    def _call(self, operation, payload=None):
        self.calls.append((operation, copy.deepcopy(payload)))
        if operation == "decision":
            if payload["project_id"] != self.run["project_id"] or payload["input_hash"] != self.run["input_hash"]:
                raise StoreError("Stale project or input fingerprint", 409)
            if payload["expected_revision"] != self.run["revision"]:
                raise StoreError("Stale expected revision", 409)
            if payload["proposal_hash"] != "b" * 64 or payload["review_hash"] != "c" * 64:
                raise StoreError("Stale proposal or review fingerprint", 409)
            if payload["kind"] != (self.run.get("review_node") or {}).get("kind"):
                raise StoreError("Stale review kind", 409)
            action = payload["action"]
            if action == "undo":
                if self.run["status"] != "complete" or payload["decision_id"] != self.last_decision_id:
                    raise StoreError("Undo requires the exact completed annotation decision", 409)
                self.run["status"] = "awaiting_review"
                self.run["pending"] = {"kind": "annotation", "hash": "b" * 64}
            elif self.run["status"] != "awaiting_review":
                raise StoreError("No pending review; decision already handled", 409)
            elif action in {"approve", "reject"}:
                self.run["status"] = "ready" if action == "approve" else "rejected"
                self.run["pending"] = None
                self.last_decision_id = "decision-123"
            self.run["revision"] += 1
        return {"schema": "scagentkit.run-review.workbench.v1", "run": copy.deepcopy(self.run),
                "csrf_token": self.csrf_token}


class PassiveQC(QCRuntime):
    def _call(self, operation, payload=None):
        return {"schema": "scagentkit.qc.workbench.v1", "run": inspector("qc"), "csrf_token": self.csrf_token}


class RunReviewHTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.project = Path(self.temp.name); (self.project / "state.rds").write_bytes(b"fixture")
        self.runtime = MockRunReview(self.project)
        self.server = WorkbenchServer(("127.0.0.1", 0), None, None, run_review=self.runtime)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
        self.port = self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(); self.temp.cleanup()

    def request(self, method, path, payload=None, headers=None, raw=None):
        headers = dict(headers or {})
        if payload is not None or raw is not None: headers.setdefault("Content-Type", "application/json")
        body = raw if raw is not None else canonical(payload).encode() if payload is not None else None
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        connection.request(method, path, body, headers)
        response = connection.getresponse(); result = (response.status, dict(response.getheaders()), response.read())
        connection.close(); return result

    def headers(self):
        return {"X-ScAgentKit-Run-Token": self.runtime.csrf_token,
                "Origin": "http://127.0.0.1:" + str(self.port)}

    def test_fresh_run_inspection_schema_token_and_security_headers(self):
        status, headers, body = self.request("GET", "/api/run-review/inspect")
        self.assertEqual(status, 200)
        view = json.loads(body)
        self.assertEqual(view["schema"], "scagentkit.run-review.workbench.v1")
        self.assertEqual(view["run"]["project_id"], "literal-project")
        self.assertEqual(view["csrf_token"], self.runtime.csrf_token)
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertIn("default-src 'none'", headers["Content-Security-Policy"])
        self.assertNotIn("Access-Control-Allow-Origin", headers)

    def test_token_required_and_old_qc_token_header_does_not_authorize(self):
        for headers in ({}, {"X-ScAgentKit-Run-Token": "wrong"},
                        {"X-ScAgentKit-QC-Token": self.runtime.csrf_token}):
            with self.subTest(headers=list(headers)):
                self.assertEqual(self.request("POST", "/api/run-review/decision", decision(), headers=headers)[0], 403)
        self.assertEqual(self.runtime.calls, [])

    def test_same_origin_annotation_approval_keeps_explicit_resume_boundary(self):
        status, _, body = self.request("POST", "/api/run-review/decision", decision(), headers=self.headers())
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["run"]["status"], "ready")
        self.assertEqual(self.runtime.calls[0][0], "decision")
        self.assertEqual(self.runtime.run["revision"], 13)

    def test_qc_preview_and_typed_revision_route_to_same_runtime(self):
        self.runtime.run = inspector("qc")
        for action in ("preview", "revise"):
            payload = decision(action, "qc"); payload["expected_revision"] = self.runtime.run["revision"]
            if action == "revise": payload["proposal"] = {"rules": []}
            payload.update(sensitivity=[], gene_panels={"literal": ["CD3D"]})
            status, _, body = self.request("POST", "/api/run-review/decision", payload, headers=self.headers())
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(body)["run"]["status"], "awaiting_review")
        self.assertEqual([call[1]["action"] for call in self.runtime.calls], ["preview", "revise"])

    def test_duplicate_approval_is_rejected_without_second_state_change(self):
        self.assertEqual(self.request("POST", "/api/run-review/decision", decision(), headers=self.headers())[0], 200)
        self.assertEqual(self.request("POST", "/api/run-review/decision", decision(), headers=self.headers())[0], 409)
        self.assertEqual(self.runtime.run["revision"], 13)

    def test_concurrent_duplicate_approval_applies_one_coordinator_change(self):
        barrier = threading.Barrier(2)
        results = []
        def submit():
            barrier.wait(timeout=5)
            results.append(self.request("POST", "/api/run-review/decision", decision(), headers=self.headers())[0])
        workers = [threading.Thread(target=submit) for _ in range(2)]
        for worker in workers: worker.start()
        for worker in workers: worker.join(timeout=10)
        self.assertFalse(any(worker.is_alive() for worker in workers))
        self.assertEqual(sorted(results), [200, 409])
        self.assertEqual(self.runtime.run["revision"], 13)

    def test_stale_fingerprints_revision_and_kind_fail_closed(self):
        for field, value in (("project_id", "different-project"), ("input_hash", "d" * 64),
                             ("proposal_hash", "d" * 64), ("review_hash", "d" * 64),
                             ("expected_revision", 11), ("kind", "qc")):
            payload = decision(); payload[field] = value
            with self.subTest(field=field):
                self.assertEqual(self.request("POST", "/api/run-review/decision", payload, headers=self.headers())[0], 409)
        self.assertEqual(self.runtime.run["revision"], 12)

    def test_completed_annotation_undo_requires_exact_decision_and_current_scope(self):
        payload = dict(decision("undo"), decision_id="decision-123")
        self.assertEqual(self.request("POST", "/api/run-review/decision", payload, headers=self.headers())[0], 409)
        self.runtime.run["status"] = "complete"; self.runtime.last_decision_id = "decision-123"
        wrong = dict(payload, decision_id="another-decision")
        self.assertEqual(self.request("POST", "/api/run-review/decision", wrong, headers=self.headers())[0], 409)
        self.assertEqual(self.request("POST", "/api/run-review/decision", payload, headers=self.headers())[0], 200)
        self.assertEqual(self.runtime.run["status"], "awaiting_review")
        self.assertEqual(self.runtime.run["revision"], 13)

    def test_hostile_host_origin_cross_site_and_options_rejected_before_runtime(self):
        for foreign in ({"Host": "evil.example"}, {"Origin": "https://evil.example"},
                        {"Origin": "http://127.0.0.1:1"}, {"Sec-Fetch-Site": "cross-site"}):
            headers = dict(self.headers(), **foreign)
            with self.subTest(foreign=foreign):
                self.assertEqual(self.request("POST", "/api/run-review/decision", decision(), headers=headers)[0], 403)
        self.assertEqual(self.request("OPTIONS", "/api/run-review/decision")[0], 403)
        self.assertEqual(self.runtime.calls, [])

    def test_queries_rejected_instead_of_overriding_configured_project(self):
        self.assertEqual(self.request("GET", "/api/run-review/inspect?project_dir=arbitrary")[0], 422)
        self.assertEqual(self.request("POST", "/api/run-review/decision?code=arbitrary", decision(), headers=self.headers())[0], 422)
        self.assertEqual(self.runtime.calls, [])

    def test_malformed_duplicate_json_and_content_type_rejected_before_runtime(self):
        for raw in (b'{"action":"approve","action":"reject"}', b'{', b'[]', b'null', b'\xff'):
            with self.subTest(raw=raw):
                self.assertEqual(self.request("POST", "/api/run-review/decision", headers=self.headers(), raw=raw)[0], 422)
        headers = dict(self.headers(), **{"Content-Type": "text/plain"})
        self.assertEqual(self.request("POST", "/api/run-review/decision", decision(), headers=headers)[0], 415)
        self.assertEqual(self.runtime.calls, [])

    def test_unsupported_browser_fields_never_reach_runtime(self):
        for field in ("provider", "project_dir", "code", "source", "url", "resume"):
            with self.subTest(field=field):
                self.assertEqual(self.request("POST", "/api/run-review/decision", dict(decision(), **{field: "untrusted"}), headers=self.headers())[0], 422)
        self.assertEqual(self.runtime.calls, [])

    def test_run_mode_excludes_legacy_analysis_export_and_source_routes(self):
        for route in ("/api/evidence", "/api/session", "/api/export", "/api/resume", "/api/qc/inspect"):
            with self.subTest(route=route): self.assertEqual(self.request("GET", route)[0], 409)
        for route in ("/api/decision", "/api/project/import", "/api/resume", "/api/qc/decision"):
            with self.subTest(route=route): self.assertEqual(self.request("POST", route, decision(), headers=self.headers())[0], 409)
        for route in ("/run_review_bridge.R", "/state.rds", "/../run_review_bridge.R"):
            with self.subTest(route=route): self.assertEqual(self.request("GET", route)[0], 404)

    def test_delegated_r_rejection_returns_bounded_error_without_private_output(self):
        with patch.object(self.runtime, "_call", side_effect=StoreError("Unknown cited gene: NOT_A_MEASURED_GENE", 409)):
            status, _, body = self.request("POST", "/api/run-review/decision", decision(), headers=self.headers())
        self.assertEqual(status, 409)
        self.assertEqual(json.loads(body)["error"], "Unknown cited gene: NOT_A_MEASURED_GENE")
        self.assertNotIn("private", body.decode())
        self.assertEqual(self.runtime.run["revision"], 12)

    def test_legacy_qc_mode_remains_separate_with_its_own_token(self):
        qc = PassiveQC(self.project)
        server = WorkbenchServer(("127.0.0.1", 0), None, None, qc=qc)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            connection = http.client.HTTPConnection("127.0.0.1", server.server_address[1], timeout=5)
            connection.request("GET", "/api/qc/inspect")
            response = connection.getresponse(); body = response.read()
            self.assertEqual(response.status, 200)
            self.assertEqual(json.loads(body)["schema"], "scagentkit.qc.workbench.v1")
            connection.close()
            connection = http.client.HTTPConnection("127.0.0.1", server.server_address[1], timeout=5)
            connection.request("GET", "/api/run-review/inspect")
            response = connection.getresponse(); response.read()
            self.assertEqual(response.status, 409)
            connection.close()
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_unified_mode_rejects_legacy_qc_writes_even_with_valid_legacy_token(self):
        qc = PassiveQC(self.project)
        self.server.qc = qc
        before = (self.project / "state.rds").read_bytes()
        legacy = dict(action="approve", proposal_hash="a" * 64, preview_hash="b" * 64,
                      expected_revision=12, reviewer="legacy analyst", reason="legacy approval")
        headers = {"Origin": "http://127.0.0.1:" + str(self.port), "X-ScAgentKit-QC-Token": qc.csrf_token}
        with patch.object(qc, "decide") as legacy_decide, patch.object(self.runtime, "decide") as unified_decide:
            status, _, body = self.request("POST", "/api/qc/decision", legacy, headers=headers)
            self.assertEqual(status, 409)
            self.assertIn("fully bound unified", json.loads(body)["error"])
            legacy_decide.assert_not_called(); unified_decide.assert_not_called()
        self.assertEqual((self.project / "state.rds").read_bytes(), before)
        self.assertEqual(self.runtime.run["revision"], 12)
        self.assertEqual(self.request("GET", "/api/qc/inspect")[0], 200)

    def test_non_loopback_run_server_binding_rejected(self):
        with self.assertRaises(ValueError): WorkbenchServer(("0.0.0.0", 0), None, None, run_review=self.runtime)


if __name__ == "__main__": unittest.main()
