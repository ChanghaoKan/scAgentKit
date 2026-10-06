"""Per-request child routing and same-origin authority with mocked R runtimes."""
import http.client
import json
import sys
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server import WorkbenchServer
from store import StoreError


class Review:
    def __init__(self, project): self.project_id = project; self.csrf_token = "token-" + project; self.calls = []
    def describe(self): self.calls.append("inspect"); return {"schema": "scagentkit.run-review.workbench.v1", "csrf_token": self.csrf_token, "run": {"project_id": self.project_id, "input_hash": "a" * 64, "revision": 5}}
    def decide(self, payload, token): self.calls.append(("decision", payload, token)); return self.describe()


class Continue:
    def __init__(self, project): self.project_id = project; self.calls = []
    def describe(self, run=None): self.calls.append(("describe", run)); return {"enabled": True, "job": None, "availability": {"project_id": self.project_id}}
    def submit(self, payload): self.calls.append(("submit", payload)); return {"job": {"status": "queued", "project_id": self.project_id}}


class Scope:
    def __init__(self):
        self.calls = []; self.csrf_token = "scope-token"
        self.contexts = {key: (Review(key), Continue(key), Review(key + "-qc")) for key in ("child-A", "child-B")}
    def describe(self, **query): self.calls.append(("inspect", query)); return {"schema": "scagentkit.subcluster.workbench.v1", "csrf_token": self.csrf_token, "query": query}
    def readiness(self): return {"ready": True, "frozen": True, "parent_run": {"project_id": "parent", "status": "complete", "stage": "complete", "revision": 5}, "children": []}
    def child_context(self, key):
        self.calls.append(("resolve", key))
        if key not in self.contexts: raise StoreError("Unknown or foreign child", 409)
        return self.contexts[key]
    def operate(self, payload, token):
        if token != self.csrf_token: raise StoreError("Scope token required", 403)
        self.calls.append(("operation", payload)); return {"saved": True}


class SubclusterHTTPTests(unittest.TestCase):
    def setUp(self):
        self.parent = Review("parent"); self.scope = Scope()
        self.server = WorkbenchServer(("127.0.0.1", 0), None, None, run_review=self.parent, qc=Review("parent-qc"), run_subcluster=self.scope)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
        self.port = self.server.server_address[1]
    def tearDown(self): self.server.shutdown(); self.server.server_close(); self.thread.join()
    def request(self, method, route, payload=None, headers=None):
        headers = dict(headers or {})
        if payload is not None: headers.setdefault("Content-Type", "application/json")
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        connection.request(method, route, json.dumps(payload) if payload is not None else None, headers)
        response = connection.getresponse(); content = response.read(); status = response.status; connection.close()
        return status, json.loads(content) if route.startswith("/api/") else content
    def test_scope_parent_inspection_and_target_preview_queries(self):
        status, value = self.request("GET", "/api/subcluster/inspect")
        self.assertEqual(status, 200); self.assertEqual(value["query"], {})
        status, value = self.request("GET", "/api/subcluster/inspect?child_id=child-A&column=fine&supersedes=old")
        self.assertEqual(status, 200); self.assertEqual(value["query"], {"child_id": "child-A", "column": "fine", "supersedes": "old"})
        for query in ("project_dir=/private", "column=fine", "child_id=", "child_id=child-A&child_id=child-B", "child_id=child-A&outside=original"):
            self.assertEqual(self.request("GET", "/api/subcluster/inspect?" + query)[0], 422)
    def test_tabs_route_independently_and_never_change_parent_context(self):
        for key in ("child-A", "child-B", "child-A"):
            status, value = self.request("GET", "/api/run-review/inspect?child_id=" + key)
            self.assertEqual(status, 200); self.assertEqual(value["run"]["project_id"], key)
            self.assertEqual(value["continuation"]["availability"]["project_id"], key)
        self.assertEqual(self.parent.calls, []); self.assertIs(self.server.run_review, self.parent)
        self.assertEqual([item for item in self.scope.calls if item[0] == "resolve"], [("resolve", "child-A"), ("resolve", "child-B"), ("resolve", "child-A")])
    def test_parent_mutations_and_continuation_unavailable(self):
        for route in ("/api/run-review/decision", "/api/run-review/continue", "/api/qc/decision"):
            self.assertEqual(self.request("POST", route, {})[0], 409)
        self.assertEqual(self.request("GET", "/api/run-review/continuation")[0], 409)
        self.assertEqual(self.parent.calls, [])
    def test_child_continue_requires_that_child_token(self):
        for key in ("child-A", "child-B"):
            payload = {"project_id": key}
            self.assertEqual(self.request("POST", "/api/run-review/continue?child_id=" + key, payload, {"X-ScAgentKit-Run-Token": "token-parent"})[0], 403)
            status, value = self.request("POST", "/api/run-review/continue?child_id=" + key, payload, {"X-ScAgentKit-Run-Token": "token-" + key})
            self.assertEqual(status, 202); self.assertEqual(value["job"]["project_id"], key)
    def test_child_decision_and_poll_use_selected_scope(self):
        status, value = self.request("POST", "/api/run-review/decision?child_id=child-B", {"action": "approve"}, {"X-ScAgentKit-Run-Token": "token-child-B"})
        self.assertEqual(status, 200); self.assertEqual(value["run"]["project_id"], "child-B")
        status, value = self.request("GET", "/api/run-review/continuation?child_id=child-A")
        self.assertEqual(status, 200); self.assertEqual(value["availability"]["project_id"], "child-A")
        self.assertEqual(self.parent.calls, [])
    def test_foreign_and_extra_review_queries_rejected(self):
        self.assertEqual(self.request("GET", "/api/run-review/inspect?child_id=foreign")[0], 409)
        for query in ("project_dir=/private", "child_id=child-A&column=override", "child_id=child-A&child_id=child-B", "child_id="):
            self.assertEqual(self.request("GET", "/api/run-review/inspect?" + query)[0], 422)
    def test_subanalysis_same_origin_csrf_and_no_query_mutation(self):
        payload = {"action": "create"}
        self.assertEqual(self.request("POST", "/api/subcluster/operation", payload)[0], 403)
        headers = {"X-ScAgentKit-Subcluster-Token": "scope-token"}
        self.assertEqual(self.request("POST", "/api/subcluster/operation", payload, headers)[0], 200)
        self.assertEqual(self.request("POST", "/api/subcluster/operation?child_id=child-A", payload, headers)[0], 422)
        for wrong in ({"Origin": "https://example.invalid"}, {"Host": "example.invalid"}, {"Sec-Fetch-Site": "cross-site"}):
            self.assertEqual(self.request("POST", "/api/subcluster/operation", payload, dict(headers, **wrong))[0], 403)
    def test_child_context_uses_exact_project_header_body_and_scope_token(self):
        payload = {"action": "context", "child_id": "child-A", "project_id": "child-A",
                   "input_hash": "a" * 64, "expected_revision": 5, "expected_context_hash": "b" * 64,
                   "parent_scope_hash": "c" * 64, "expected_parent_revision": 5,
                   "context": {"notes": "Engineering test hypothesis"},
                   "reviewer": "engineering reviewer", "reason": "Correct soft context only", "request_id": "context-one"}
        headers = {"X-ScAgentKit-Subcluster-Token": "scope-token", "X-ScAgentKit-Run-Project": "child-A"}
        for wrong in ({"X-ScAgentKit-Run-Project": "parent"}, {"X-ScAgentKit-Run-Project": "child-B"}):
            self.assertEqual(self.request("POST", "/api/subcluster/operation", payload, dict(headers, **wrong))[0], 409)
        for wrong in ({"X-ScAgentKit-Subcluster-Token": "token-child-A"}, {"Origin": "https://example.invalid"}):
            self.assertEqual(self.request("POST", "/api/subcluster/operation", payload, dict(headers, **wrong))[0], 403)
        self.assertEqual(self.request("POST", "/api/subcluster/operation", dict(payload, project_id="child-B"), headers)[0], 409)
        self.assertEqual(self.request("POST", "/api/subcluster/operation?child_id=child-A", payload, headers)[0], 422)
        self.assertFalse(any(item[0] == "operation" for item in self.scope.calls))
        self.assertEqual(self.request("POST", "/api/subcluster/operation", payload, headers)[0], 200)
        self.assertEqual([item for item in self.scope.calls if item[0] == "operation"], [("operation", payload)])
        self.assertEqual(self.parent.calls, [])
    def test_parent_scope_page_assets_and_no_arbitrary_file_routes(self):
        status, content = self.request("GET", "/")
        self.assertEqual(status, 200); self.assertIn(b"review.js", content)
        self.assertEqual(self.request("GET", "/subclusters?child_id=child-A")[0], 200)
        for path in ("/subcluster.js", "/subcluster.css", "/review?child_id=child-A", "/review-qc?child_id=child-A"):
            self.assertEqual(self.request("GET", path)[0], 200)
        self.assertEqual(self.request("GET", "/../../state.rds")[0], 404)
    def test_other_execution_and_import_routes_unavailable(self):
        for route in ("/api/project/import", "/api/directed/execute", "/api/run-review/resume"):
            self.assertEqual(self.request("POST", route, {})[0], 409)


if __name__ == "__main__": unittest.main()
