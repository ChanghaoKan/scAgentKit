"""QC HTTP/IPC boundaries. Scientific state checks remain in the R coordinator."""
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
from server import WorkbenchServer
from store import StoreError


def inspector():
    return {"schema": "scagentkit.run.v1", "project_id": "literal-project", "revision": 12,
            "status": "awaiting_review", "stage": "qc_propose", "input_hash": "a" * 64,
            "pending": {"kind": "qc", "hash": "b" * 64},
            "qc_preview": {"schema": "scagentkit.qc.review.v1", "hash": "c" * 64}}


def decision(action="approve"):
    return {"action": action, "expected_revision": 12, "proposal_hash": "b" * 64,
            "preview_hash": "c" * 64, "reviewer": "analyst", "reason": "Review the measured scope"}


class QCRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.project = Path(self.temp.name) / "project"
        self.project.mkdir()
        (self.project / "state.rds").write_bytes(b"fixture only; never interpreted by Python")
        self.runtime = QCRuntime(self.project, library=self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def successful_process(self, argv, **kwargs):
        Path(argv[-1]).write_text(canonical({"ok": True, "result": inspector(), "error": None}))
        return subprocess.CompletedProcess(argv, 0, b"private stdout is not returned", b"private stderr is not returned")

    def test_fixed_shell_free_bridge_and_keys_removed(self):
        with patch.dict(os.environ, {key: "never-export-this" for key in ("DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY")}), patch("qc_runtime.subprocess.run", side_effect=self.successful_process) as process:
            payload = decision("revise")
            payload["proposal"] = {"rationale": "$(touch /not-executed) `shell text` ; arbitrary text"}
            view = self.runtime.decide(payload, self.runtime.csrf_token)
            call = process.call_args
            self.assertFalse(call.kwargs["shell"])
            self.assertEqual(call.args[0][:4], ["Rscript", "--vanilla", str(self.runtime.bridge), "decision"])
            self.assertEqual(call.args[0][4], str(self.project.resolve()))
            self.assertFalse(any(key in call.kwargs["env"] for key in ("DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY")))
            self.assertNotIn("never-export-this", canonical(view))
            self.assertNotIn("private stdout", canonical(view))

    def test_browser_cannot_supply_execution_source_path_provider_or_resume(self):
        for field in ("code", "rscript", "project_dir", "source", "provider", "url", "request_id"):
            with self.subTest(field=field), self.assertRaises(StoreError):
                self.runtime.validate(dict(decision(), **{field: "arbitrary"}))
        with self.assertRaises(StoreError):
            self.runtime.validate(decision("resume"))

    def test_operator_library_path_list_preserves_separate_libraries(self):
        dependency = Path(self.temp.name) / "dependency-library"; dependency.mkdir()
        runtime = QCRuntime(self.project, library=os.pathsep.join((self.temp.name, str(dependency))))
        self.assertEqual(runtime.library, os.pathsep.join((str(Path(self.temp.name).resolve()), str(dependency.resolve()))))

    def test_strict_fingerprints_revision_reviewer_reason_and_json_types(self):
        variants = [("preview_hash", "old"), ("proposal_hash", "C" * 64), ("expected_revision", True),
                    ("expected_revision", -1), ("expected_revision", 1.5), ("reviewer", " "), ("reason", ""),
                    ("reason", "a\x00b"), ("reason", "a" * 4001)]
        for field, value in variants:
            payload = decision(); payload[field] = value
            with self.subTest(field=field, value=str(value)[:20]), self.assertRaises(StoreError):
                self.runtime.validate(payload)
        for field, value in (("proposal", "R code"), ("sensitivity", {}), ("gene_panels", [])):
            payload = dict(decision("revise"), proposal={}); payload[field] = value
            with self.subTest(field=field), self.assertRaises(StoreError): self.runtime.validate(payload)

    def test_current_server_token_required_before_process(self):
        with patch("qc_runtime.subprocess.run") as process:
            for token in (None, "", "wrong"):
                with self.assertRaises(StoreError) as problem: self.runtime.decide(decision(), token)
                self.assertEqual(problem.exception.status, 403)
            process.assert_not_called()

    def test_bridge_change_fails_before_process(self):
        self.runtime.bridge_hash = "changed"
        with patch("qc_runtime.subprocess.run") as process, self.assertRaises(StoreError): self.runtime.describe()
        process.assert_not_called()

    def test_replaced_project_directory_rejected(self):
        self.project.rename(self.project.with_name("old-project")); self.project.mkdir()
        (self.project / "state.rds").write_bytes(b"replacement")
        with self.assertRaises(StoreError): self.runtime.describe()

    def test_coordinator_stale_error_returned_without_stdout_or_stderr(self):
        def rejected(argv, **kwargs):
            Path(argv[-1]).write_text(canonical({"ok": False, "result": None, "error": "Stale preview hash"}))
            return subprocess.CompletedProcess(argv, 1, b"do not expose stdout", b"do not expose stderr")
        with patch("qc_runtime.subprocess.run", side_effect=rejected), self.assertRaises(StoreError) as problem:
            self.runtime.decide(decision(), self.runtime.csrf_token)
        self.assertEqual(str(problem.exception), "Stale preview hash")

    def test_bounded_timeout_is_not_retried(self):
        with patch("qc_runtime.subprocess.run", side_effect=subprocess.TimeoutExpired("fixed", 120)) as process, self.assertRaises(StoreError) as problem:
            self.runtime.describe()
        self.assertEqual(process.call_count, 1)
        self.assertIn("Inspect", str(problem.exception))

    def test_response_project_identity_bound_across_processes(self):
        with patch("qc_runtime.subprocess.run", side_effect=self.successful_process): self.runtime.describe()
        def replacement(argv, **kwargs):
            run = inspector(); run["project_id"] = "replacement"
            Path(argv[-1]).write_text(canonical({"ok": True, "result": run, "error": None}))
            return subprocess.CompletedProcess(argv, 0, b"", b"")
        with patch("qc_runtime.subprocess.run", side_effect=replacement), self.assertRaises(StoreError): self.runtime.describe()

    def test_duplicate_or_invalid_result_rejected(self):
        for content in ('{"ok":true,"ok":false,"result":null,"error":null}', '{}', '[]'):
            def invalid(argv, **kwargs):
                Path(argv[-1]).write_text(content)
                return subprocess.CompletedProcess(argv, 0, b"", b"")
            with self.subTest(content=content), patch("qc_runtime.subprocess.run", side_effect=invalid), self.assertRaises((StoreError, ValueError)):
                self.runtime.describe()


class MockQC(QCRuntime):
    def _call(self, operation, payload=None):
        run = inspector()
        if operation == "decision":
            if payload["expected_revision"] != 12 or payload["proposal_hash"] != "b" * 64 or payload["preview_hash"] != "c" * 64:
                raise StoreError("Stale proposal, revision or preview", 409)
            run["status"] = "ready" if payload["action"] == "approve" else "rejected"
            run["revision"] = 13; run["pending"] = None
        return {"schema": "scagentkit.qc.workbench.v1", "run": run, "csrf_token": self.csrf_token}


class QCHTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.project = Path(self.temp.name); (self.project / "state.rds").write_bytes(b"fixture")
        self.runtime = MockQC(self.project)
        self.server = WorkbenchServer(("127.0.0.1", 0), None, None, qc=self.runtime)
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

    def test_qc_page_fixed_assets_and_fresh_run(self):
        for asset in ("/", "/qc", "/qc.js", "/qc.css"):
            status, headers, body = self.request("GET", asset)
            self.assertEqual(status, 200); self.assertIn("default-src 'none'", headers["Content-Security-Policy"])
            self.assertNotIn("Access-Control-Allow-Origin", headers)
        status, _, body = self.request("GET", "/api/qc/inspect")
        self.assertEqual(status, 200); self.assertEqual(json.loads(body)["run"]["project_id"], "literal-project")

    def test_same_origin_nonce_and_typed_decision(self):
        status, _, _ = self.request("POST", "/api/qc/decision", decision())
        self.assertEqual(status, 403)
        headers = {"X-ScAgentKit-QC-Token": self.runtime.csrf_token, "Origin": "http://127.0.0.1:" + str(self.port)}
        status, _, body = self.request("POST", "/api/qc/decision", decision(), headers=headers)
        self.assertEqual(status, 200); self.assertEqual(json.loads(body)["run"]["status"], "ready")

    def test_hostile_origin_host_cross_site_even_with_valid_nonce(self):
        for foreign in ({"Host": "evil.example"}, {"Origin": "https://evil.example"}, {"Sec-Fetch-Site": "cross-site"}):
            headers = dict(foreign, **{"X-ScAgentKit-QC-Token": self.runtime.csrf_token})
            self.assertEqual(self.request("POST", "/api/qc/decision", decision(), headers=headers)[0], 403)
        self.assertEqual(self.request("OPTIONS", "/api/qc/decision")[0], 403)

    def test_stale_revision_and_fingerprints_fail_closed(self):
        headers = {"X-ScAgentKit-QC-Token": self.runtime.csrf_token}
        for field, value in (("expected_revision", 11), ("proposal_hash", "d" * 64), ("preview_hash", "d" * 64)):
            payload = decision(); payload[field] = value
            self.assertEqual(self.request("POST", "/api/qc/decision", payload, headers=headers)[0], 409)

    def test_no_legacy_annotation_resume_or_file_routes(self):
        for route in ("/api/evidence", "/api/session", "/api/export", "/api/resume"):
            self.assertEqual(self.request("GET", route)[0], 409)
        for route in ("/api/decision", "/api/project/import", "/api/resume"):
            self.assertEqual(self.request("POST", route, decision())[0], 409)
        for path in ("/qc_bridge.R", "/state.rds", "/../qc_bridge.R"):
            self.assertEqual(self.request("GET", path)[0], 404)
        self.assertEqual(self.request("GET", "/api/qc/inspect?project_dir=arbitrary")[0], 422)
        self.assertEqual(self.request("POST", "/api/qc/decision?code=arbitrary", decision(), headers={"X-ScAgentKit-QC-Token": self.runtime.csrf_token})[0], 422)

    def test_duplicate_json_and_wrong_content_type(self):
        headers = {"X-ScAgentKit-QC-Token": self.runtime.csrf_token}
        self.assertEqual(self.request("POST", "/api/qc/decision", headers=headers, raw=b'{"action":"approve","action":"reject"}')[0], 422)
        headers["Content-Type"] = "text/plain"
        self.assertEqual(self.request("POST", "/api/qc/decision", decision(), headers=headers)[0], 415)

    def test_non_loopback_server_binding_rejected(self):
        with self.assertRaises(ValueError): WorkbenchServer(("0.0.0.0", 0), None, None, qc=self.runtime)


if __name__ == "__main__": unittest.main()
