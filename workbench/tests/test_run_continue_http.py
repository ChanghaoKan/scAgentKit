"""HTTP authority and routing checks; real R/browser execution is separate."""
import http.client
import json
import sys
import tempfile
import threading
import unittest
from unittest import mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server import WorkbenchServer
from store import StoreError


class Review:
    csrf_token = "current-local-token"

    def __init__(self):
        self.calls = []

    def describe(self):
        self.calls.append("inspect")
        return {"schema": "scagentkit.run-review.workbench.v1", "csrf_token": self.csrf_token,
                "run": {"status": "ready", "project_id": "study", "input_hash": "a" * 64,
                        "revision": 10, "stage": "qc_apply"}}

    def decide(self, payload, token):
        self.calls.append("decision")
        return self.describe()


class Continuation:
    def __init__(self):
        self.calls = []
        self.job = None

    def describe(self, run=None):
        self.calls.append(("describe", run is not None))
        return {"enabled": True, "job": self.job, "availability": {"can_continue": True}}

    def submit(self, payload):
        self.calls.append(("submit", payload))
        if set(payload) != {"project_id", "input_hash", "expected_revision", "request_id", "retry"}:
            raise StoreError("Continue has unsupported fields")
        self.job = {"status": "queued", "request_id": payload["request_id"]}
        return self.describe()


class ContinueHTTPTests(unittest.TestCase):
    def setUp(self):
        self.review = Review()
        self.continue_runtime = Continuation()
        self.server = WorkbenchServer(("127.0.0.1", 0), None, None,
                                      run_review=self.review, run_continue=self.continue_runtime)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_address[1]
        self.payload = {"project_id": "study", "input_hash": "a" * 64, "expected_revision": 10,
                        "request_id": "a-request", "retry": False}

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, method, route, payload=None, headers=None):
        headers = dict(headers or {})
        if payload is not None:
            headers.setdefault("Content-Type", "application/json")
        body = json.dumps(payload).encode() if payload is not None else None
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        connection.request(method, route, body, headers)
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), json.loads(response.read())
        connection.close()
        return result

    def valid_headers(self):
        return {"Origin": f"http://127.0.0.1:{self.port}",
                "X-ScAgentKit-Run-Token": self.review.csrf_token}

    def test_explicit_enqueue_returns_202_and_no_scientific_review(self):
        status, headers, result = self.request("POST", "/api/run-review/continue", self.payload, self.valid_headers())
        self.assertEqual(status, 202)
        self.assertEqual(result["job"]["status"], "queued")
        self.assertEqual(self.review.calls, ["inspect"])
        self.assertEqual(self.continue_runtime.calls[0], ("submit", self.payload))
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertNotIn("Access-Control-Allow-Origin", headers)

    def test_status_poll_never_starts_r_inspection_or_submit(self):
        status, _, result = self.request("GET", "/api/run-review/continuation")
        self.assertEqual(status, 200)
        self.assertTrue(result["enabled"])
        self.assertEqual(self.review.calls, [])
        self.assertEqual(self.continue_runtime.calls, [("describe", False)])

    def test_inspect_augments_authoritative_review_with_job_availability(self):
        status, _, result = self.request("GET", "/api/run-review/inspect")
        self.assertEqual(status, 200)
        self.assertEqual(result["run"]["status"], "ready")
        self.assertTrue(result["continuation"]["enabled"])
        self.assertEqual(self.continue_runtime.calls, [("describe", True)])

    def test_missing_wrong_or_old_header_token_cannot_enqueue(self):
        for headers in ({}, {"X-ScAgentKit-Run-Token": "old"},
                        {"X-ScAgentKit-QC-Token": self.review.csrf_token}):
            with self.subTest(headers=headers):
                self.assertEqual(self.request("POST", "/api/run-review/continue", self.payload, headers)[0], 403)
        self.assertEqual(self.continue_runtime.calls, [])

    def test_decision_response_preserves_continue_for_its_new_authoritative_revision(self):
        fresh = {"schema": "scagentkit.run-review.workbench.v1", "csrf_token": self.review.csrf_token,
                 "run": {"status": "ready", "project_id": "study", "input_hash": "a" * 64,
                         "revision": 11, "stage": "annotation_apply"}}
        with mock.patch.object(self.review, "decide", return_value=fresh), mock.patch.object(
                self.continue_runtime, "describe", wraps=self.continue_runtime.describe) as describe:
            status, _, result = self.request("POST", "/api/run-review/decision", {}, self.valid_headers())
        self.assertEqual(status, 200)
        self.assertEqual(result["run"]["revision"], 11)
        self.assertTrue(result["continuation"]["enabled"])
        self.assertEqual(describe.call_args, mock.call(fresh["run"]))
        self.assertEqual(self.review.calls, [])

    def test_review_only_decision_does_not_enable_or_describe_continuation(self):
        self.server.run_continue = None
        status, _, result = self.request("POST", "/api/run-review/decision", {}, self.valid_headers())
        self.assertEqual(status, 200)
        self.assertNotIn("continuation", result)
        self.assertEqual(self.continue_runtime.calls, [])

    def test_cross_origin_and_wrong_host_rejected_before_enqueue(self):
        for patch in ({"Origin": "https://example.invalid"}, {"Host": "example.invalid"},
                      {"Sec-Fetch-Site": "cross-site"}):
            headers = self.valid_headers(); headers.update(patch)
            with self.subTest(headers=patch):
                self.assertEqual(self.request("POST", "/api/run-review/continue", self.payload, headers)[0], 403)
        self.assertEqual(self.continue_runtime.calls, [])

    def test_disabled_operator_mode_cannot_continue_or_read_job(self):
        self.server.run_continue = None
        self.assertEqual(self.request("GET", "/api/run-review/continuation")[0], 409)
        self.assertEqual(self.request("POST", "/api/run-review/continue", self.payload, self.valid_headers())[0], 409)
        self.assertEqual(self.continue_runtime.calls, [])

    def test_query_fields_cannot_change_configured_run(self):
        for method in ("GET", "POST"):
            with self.subTest(method=method):
                route = "/api/run-review/continuation" if method == "GET" else "/api/run-review/continue"
                self.assertEqual(self.request(method, route + "?project_dir=/other", self.payload if method == "POST" else None, self.valid_headers())[0], 422)
        self.assertEqual(self.continue_runtime.calls, [])

    def test_extra_code_provider_or_executable_fields_rejected(self):
        for field in ("code", "chat_fn", "provider", "rscript", "project_dir", "library"):
            with self.subTest(field=field):
                payload = dict(self.payload, **{field: "cannot-be-code"})
                self.assertEqual(self.request("POST", "/api/run-review/continue", payload, self.valid_headers())[0], 422)
        self.assertTrue(all(call == "inspect" for call in self.review.calls))

    def test_running_job_blocks_competing_review_without_starting_r(self):
        self.continue_runtime.job = {"status": "running"}
        self.assertEqual(self.request("POST", "/api/run-review/decision", {}, self.valid_headers())[0], 409)
        self.assertEqual(self.review.calls, [])

    def test_unrelated_execution_endpoint_stays_unavailable(self):
        for route in ("/api/run-review/resume", "/api/directed/execute", "/api/project/import"):
            with self.subTest(route=route):
                self.assertEqual(self.request("POST", route, self.payload, self.valid_headers())[0], 409)
        self.assertEqual(self.review.calls, [])
        self.assertEqual(self.continue_runtime.calls, [])


if __name__ == "__main__":
    unittest.main()
