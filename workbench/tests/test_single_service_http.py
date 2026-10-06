"""Single-service lifecycle and per-tab binding with fixed local R stand-ins."""
import copy
import http.client
import json
import sys
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server import WorkbenchServer, main
from store import StoreError


class Review:
    def __init__(self, identity):
        self.project_id = identity; self.csrf_token = "review-" + identity
        self.calls = []; self.project = Path("/fixed-registered-" + identity)
        self.library = None; self.rscript = "Rscript"
    def describe(self):
        self.calls.append("inspect")
        return {"csrf_token": self.csrf_token, "run": {"project_id": self.project_id,
                "status": "awaiting_review", "stage": "strategy_propose", "revision": 5,
                "input_hash": "a" * 64}}
    def decide(self, payload, token):
        if token != self.csrf_token: raise StoreError("Wrong scientific token", 403)
        self.calls.append(copy.deepcopy(payload)); return self.describe()


class Jobs:
    def __init__(self, identity): self.identity = identity; self.job = None; self.submissions = []
    def describe(self, run=None): return {"job": self.job, "availability": {"project_id": self.identity}}
    def submit(self, payload):
        self.submissions.append(copy.deepcopy(payload))
        self.job = {"status": "running", "project_id": self.identity, "request_id": payload["request_id"]}
        return self.describe()


class Suggestions:
    def __init__(self, identity): self.identity = identity; self.csrf_token = "model-" + identity; self.job = None; self.operations = []
    def describe(self): return {"job": self.job, "csrf_token": self.csrf_token, "project_id": self.identity}
    def job_status(self): return self.job
    def operate(self, action, payload, token):
        if token != self.csrf_token: raise StoreError("Wrong model token", 403)
        self.operations.append((action, copy.deepcopy(payload)))
        if action == "request": self.job = {"status": "running", "project_id": self.identity}
        return self.describe()


class Workspace:
    def __init__(self):
        self.ready = False; self.calls = []; self.csrf_token = "workspace-token"
        self.contexts = {key: (Review(key), Jobs(key), Review(key)) for key in ("child-A", "child-B")}
    def readiness(self):
        return {"ready": self.ready, "frozen": self.ready,
                "parent_run": {"schema": "scagentkit.run.v1", "project_id": "parent",
                    "status": "complete" if self.ready else "awaiting_review",
                    "stage": "complete" if self.ready else "strategy_propose", "revision": 10,
                    "input_hash": "a" * 64, "output": {"seurat": "output/final.rds"}},
                "csrf_token": self.csrf_token, "child": None,
                "parent": {"context": {"species": "Homo sapiens", "tissue": "blood"}},
                "children": [{"project_id": key, "status": "complete", "stage": "complete", "revision": 20,
                              "applications": [{"application_id": "derived-" + key, "active": True,
                                                "output_path": "reintegration/derived/final.rds"}]} for key in self.contexts] if self.ready else []}
    def describe(self, **query):
        self.calls.append(("inspect", query)); return dict(self.readiness(), query=query)
    def child_context(self, key):
        self.calls.append(("resolve", key))
        if not self.ready or key not in self.contexts: raise StoreError("Unregistered child", 409)
        return self.contexts[key]
    def operate(self, payload, token):
        if token != self.csrf_token: raise StoreError("Wrong workspace token", 403)
        self.calls.append(("operate", copy.deepcopy(payload))); return self.describe()


class SingleServiceHTTPTests(unittest.TestCase):
    def setUp(self):
        self.parent = Review("parent"); self.jobs = Jobs("parent"); self.models = Suggestions("parent"); self.workspace = Workspace()
        self.server = WorkbenchServer(("127.0.0.1", 0), None, None, run_review=self.parent,
            run_continue=self.jobs, qc=Review("parent"), run_subcluster=self.workspace,
            run_suggestion=self.models)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
    def tearDown(self): self.server.shutdown(); self.server.server_close(); self.thread.join()
    def request(self, method, route, payload=None, project=None, token=None, model_token=None):
        headers = {"Content-Type": "application/json"}
        if project is not None: headers["X-ScAgentKit-Run-Project"] = project
        if token is not None: headers["X-ScAgentKit-Run-Token"] = token
        if model_token is not None: headers["X-ScAgentKit-Suggestion-Token"] = model_token
        conn = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=5)
        conn.request(method, route, json.dumps(payload) if payload is not None else None, headers)
        response = conn.getresponse(); status = response.status; body = json.loads(response.read()); conn.close()
        return status, body
    def test_live_parent_remains_reviewable_then_frozen_without_restarting(self):
        identity = id(self.server)
        status, scopes = self.request("GET", "/api/run-review/scopes")
        self.assertEqual(status, 200); self.assertFalse(scopes["parent"]["frozen"]); self.assertEqual(scopes["children"], [])
        status, waiting = self.request("GET", "/api/subcluster/inspect?project_id=parent", project="parent")
        self.assertEqual(status, 200); self.assertFalse(waiting["ready"])
        self.assertEqual(self.request("POST", "/api/run-review/decision?project_id=parent", {"project_id": "parent", "action": "approve"}, "parent", "review-parent")[0], 200)
        self.assertEqual(self.request("POST", "/api/run-review/suggestion/approve?project_id=parent", {"project_id": "parent"}, "parent", model_token="model-parent")[0], 200)
        self.workspace.ready = True
        status, scopes = self.request("GET", "/api/run-review/scopes?project_id=parent", project="parent")
        self.assertTrue(scopes["parent"]["frozen"]); self.assertEqual(len(scopes["children"]), 2)
        self.assertNotIn("context", scopes["parent"])
        self.assertTrue(scopes["children"][0]["applications"][0]["active"])
        status, view = self.request("GET", "/api/run-review/inspect?project_id=parent", project="parent")
        self.assertEqual(status, 200); self.assertTrue(view["effective_readonly"]); self.assertFalse(view["suggestion_enabled"])
        self.assertEqual(view["run"]["context"], {"species": "Homo sapiens", "tissue": "blood"})
        before = copy.deepcopy(self.parent.calls)
        for route in ("decision", "continue", "suggestion/request"):
            self.assertEqual(self.request("POST", "/api/run-review/" + route + "?project_id=parent", {"project_id": "parent", "action": "undo"}, "parent", "review-parent", "model-parent")[0], 409)
        self.assertEqual(self.parent.calls, before); self.assertEqual(id(self.server), identity)
    def test_parent_undo_is_always_blocked_in_workspace_service(self):
        self.assertEqual(self.request("POST", "/api/run-review/decision", {"project_id": "parent", "action": "undo"}, "parent", "review-parent")[0], 409)
        self.assertEqual(self.parent.calls, [])
    def test_query_header_body_project_mismatch_never_mutates(self):
        self.workspace.ready = True
        for route in ("decision", "continue", "suggestion/request"):
            for query, body, header in (("child_id=child-A&project_id=child-B", "child-A", "child-A"),
                                       ("child_id=child-A&project_id=child-A", "child-B", "child-A"),
                                       ("child_id=child-A", "child-A", "child-B")):
                self.assertEqual(self.request("POST", "/api/run-review/" + route + "?" + query, {"project_id": body}, header)[0], 409)
        self.assertEqual(self.workspace.calls, [])
        self.assertTrue(all(not context[0].calls and not context[1].submissions for context in self.workspace.contexts.values()))
    def test_navigation_and_two_tabs_preserve_distinct_jobs_and_tokens(self):
        self.workspace.ready = True
        for key in ("child-A", "child-B"):
            self.assertEqual(self.request("POST", "/api/run-review/continue?child_id=" + key, {"project_id": key, "request_id": key}, key, "review-" + key)[0], 202)
        for key in ("child-B", "parent", "child-A", "child-B"):
            query = "project_id=" + key + ("&child_id=" + key if key != "parent" else "")
            status, view = self.request("GET", "/api/run-review/inspect?" + query, project=key)
            self.assertEqual(status, 200); self.assertEqual(view["run"]["project_id"], key)
        for key, context in self.workspace.contexts.items():
            self.assertEqual(len(context[1].submissions), 1); self.assertEqual(context[1].job["project_id"], key)
            self.assertEqual(self.request("POST", "/api/run-review/continue?child_id=" + key, {"project_id": key}, key, "review-parent")[0], 403)
    def test_completed_parent_job_can_still_be_polled_without_resubmission(self):
        self.jobs.job = {"status": "succeeded", "project_id": "parent"}; self.workspace.ready = True
        status, value = self.request("GET", "/api/run-review/continuation?project_id=parent", project="parent")
        self.assertEqual(status, 200); self.assertEqual(value["job"]["status"], "succeeded"); self.assertEqual(self.jobs.submissions, [])
    def test_scope_listing_is_allowlisted_and_readonly(self):
        for query in ("project_id=", "project_id=a&project_id=b", "child_id=child-A", "project_dir=/tmp"):
            self.assertEqual(self.request("GET", "/api/run-review/scopes?" + query)[0], 422)
        self.assertEqual(self.request("GET", "/api/run-review/scopes?project_id=foreign")[0], 409)
        self.workspace.ready = True
        self.assertEqual(self.request("GET", "/api/run-review/scopes?project_id=child-A", project="child-B")[0], 409)
        for query in ("project_id=", "project_id=a&project_id=b", "child_id=child-A&project_id=parent"):
            self.assertIn(self.request("GET", "/api/run-review/inspect?" + query)[0], (422, 409))
        self.assertFalse(any(entry[0] == "operate" for entry in self.workspace.calls))
    def test_subcluster_header_and_body_bind_the_exact_operation_scope(self):
        self.workspace.ready = True
        for body, header in (({"action": "create"}, "child-A"),
                             ({"action": "apply", "project_id": "child-B", "child_id": "child-A"}, "child-A"),
                             ({"action": "undo", "project_id": "child-A", "child_id": "child-A"}, "parent")):
            self.assertEqual(self.request("POST", "/api/subcluster/operation", body, header)[0], 409)
        self.assertEqual(self.workspace.calls, [])
    def test_parent_and_child_model_runtimes_remain_distinct(self):
        self.workspace.ready = True
        self.server.model_suggestion_options = {"simulate": True}
        runtimes = {key: Suggestions(key) for key in self.workspace.contexts}
        with patch("server.RunSuggestionRuntime", side_effect=lambda path, *args, **kwargs: runtimes[path.name.removeprefix("fixed-registered-")]):
            for key in ("child-A", "child-B", "child-A"):
                status, view = self.request("GET", "/api/run-review/suggestion?child_id=" + key, project=key)
                self.assertEqual(status, 200); self.assertEqual(view["project_id"], key)
        self.assertEqual(len(self.server.suggestion_contexts), 2); self.assertIs(self.server.run_suggestion, self.models)
        self.assertEqual(self.models.operations, [])


if __name__ == "__main__": unittest.main()
