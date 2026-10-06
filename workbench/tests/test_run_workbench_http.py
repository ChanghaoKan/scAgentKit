"""Exact-scope aggregate HTTP reads with local stand-ins, no R or providers."""
import copy
import http.client
import json
import sys
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server import WorkbenchServer
from store import StoreError


def workbench_view(identity, revision=10, complete=True):
    """Rich facts distinguish full inspection from the trimmed old run view."""
    input_hash = ("a" if identity == "parent" else "b") * 64
    history_head = "f" * 64
    run = {
        "schema": "scagentkit.run.v1", "project_id": identity,
        "input_hash": input_hash, "revision": revision,
        "history_head": history_head,
        "status": "complete" if complete else "awaiting_review",
        "stage": "finalize" if complete else "strategy_propose",
        "context": {"species": "Homo sapiens", "tissue": "blood",
                    "notes": "Public fixture, no private source data",
                    "columns": {"sample": "sample", "condition": "Ca_Ctrl"}},
        "diagnostics": {"input_cells": 72, "raw_counts": True},
        "config": {"assay": "RNA", "layer": "counts", "budget": 0},
        "stages": {"qc": {"status": "complete", "retained_cells": 70},
                   "markers": {"status": "complete", "table": "tables/markers.tsv"}},
        "strategy_review": {"hash": "c" * 64,
                            "details": {"qc_impact": {"expected_retained_cells": 70},
                                        "source": {"kind": "manual"}}},
        "annotation_review": {"hash": "d" * 64,
                              "details": {"annotations": [{"clusterId": "01", "label": "Unknown",
                                                            "confidence": "low", "markers": []}]}},
        "review_node": {"kind": "strategy", "can_decide": True,
                        "can_revise": True, "can_undo": True},
        "output": {"seurat": "outputs/original-parent.rds" if identity == "parent"
                   else "outputs/child.rds", "report": "outputs/report.html"},
    }
    project = {key: run[key] for key in ("project_id", "input_hash", "revision", "history_head")}
    evidence_id = "bundle-" + identity
    return {
        "schema": "scagentkit.workbench.v1", "project": project, "run": run,
        "full": {"diagnostics": copy.deepcopy(run["diagnostics"]),
                 "saved_parameters": copy.deepcopy(run["config"])},
        "history": [{"event": "annotation_applied", "hash": history_head,
                     "revision": revision, "reviewer": "fixture-analyst"}],
        "evidence": {"projectId": evidence_id, "revision": "e" * 64,
                     "clusters": [{"id": "01", "cell_count": 70,
                                   "proposed_label": "Unknown"}]},
        "binding": {**project, "evidence_project_id": evidence_id,
                    "evidence_revision": "e" * 64},
        # The HTTP layer must supply its own scope-safe local navigation.
        "navigation": {"review_url": "https://invalid.example/review",
                       "subclusters_url": "https://invalid.example/subclusters",
                       "can_review": True, "can_revise": True, "can_undo": True},
    }


class ReadRuntime:
    def __init__(self, identity, revision=10, complete=True):
        self.project = Path("/fixed-registered-" + identity)
        self.project_id = identity
        self.view = workbench_view(identity, revision, complete)
        self.calls = []

    def describe(self):
        self.calls.append("inspect")
        return copy.deepcopy(self.view)


class Review:
    def __init__(self, runtime):
        self.runtime = runtime
        self.project_id = runtime.project_id
        self.project = runtime.project
        self.library = None
        self.rscript = "Rscript"
        self.csrf_token = "review-" + self.project_id
        self.reads = []
        self.decisions = []

    def describe(self):
        self.reads.append("inspect")
        return {"schema": "scagentkit.run-review.workbench.v1",
                "csrf_token": self.csrf_token,
                "run": copy.deepcopy(self.runtime.view["run"])}

    def decide(self, payload, token):
        self.decisions.append(copy.deepcopy(payload))
        raise AssertionError("Aggregate workbench GET cannot decide science")


class Jobs:
    def __init__(self, identity):
        self.identity = identity
        self.job = None
        self.submissions = []

    def describe(self, run=None):
        return {"job": self.job, "availability": {"project_id": self.identity}}

    def submit(self, payload):
        self.submissions.append(copy.deepcopy(payload))
        raise AssertionError("Aggregate workbench GET cannot submit a job")


class Suggestions:
    def __init__(self):
        self.operations = []
        self.csrf_token = "model-token"

    def job_status(self):
        return None

    def describe(self):
        return {"job": None, "csrf_token": self.csrf_token}

    def operate(self, action, payload, token):
        self.operations.append((action, copy.deepcopy(payload)))
        raise AssertionError("Aggregate workbench GET cannot dispatch a model")


class Workspace:
    def __init__(self, parent_runtime, child_runtimes):
        self.ready = True
        self.parent_snapshot = copy.deepcopy(parent_runtime.view["run"])
        self.contexts = {key: (Review(runtime), Jobs(key), Review(runtime))
                         for key, runtime in child_runtimes.items()}
        self.resolutions = []
        self.operations = []

    def readiness(self):
        return {"ready": self.ready, "frozen": self.ready,
                "parent_run": copy.deepcopy(self.parent_snapshot),
                "parent": {"context": copy.deepcopy(self.parent_snapshot["context"])},
                "children": [{"project_id": key, "revision": context[0].runtime.view["project"]["revision"],
                              "status": "awaiting_review", "stage": "strategy_propose",
                              "applications": [{"application_id": "derived-" + key,
                                                "active": True, "column": "sc_subtype",
                                                "output_path": "reintegration/derived/final.rds"}]}
                             for key, context in self.contexts.items()] if self.ready else []}

    def child_context(self, key):
        self.resolutions.append(key)
        if not self.ready or key not in self.contexts:
            raise StoreError("Unregistered child", 409)
        return self.contexts[key]

    def operate(self, payload, token):
        self.operations.append(copy.deepcopy(payload))
        raise AssertionError("Aggregate workbench GET cannot mutate its workspace")


class RunWorkbenchHTTPTests(unittest.TestCase):
    def setUp(self):
        self.parent_runtime = ReadRuntime("parent")
        self.child_runtimes = {key: ReadRuntime(key, revision=20, complete=False)
                               for key in ("child-A", "child-B")}
        self.parent_review = Review(self.parent_runtime)
        self.parent_qc = Review(self.parent_runtime)
        self.jobs = Jobs("parent")
        self.models = Suggestions()
        self.workspace = Workspace(self.parent_runtime, self.child_runtimes)
        self.server = WorkbenchServer(("127.0.0.1", 0), None, None,
            run_review=self.parent_review, qc=self.parent_qc, run_continue=self.jobs,
            run_suggestion=self.models, run_subcluster=self.workspace,
            run_workbench=self.parent_runtime)
        for key, runtime in self.child_runtimes.items():
            self.server.workbench_contexts[str(self.workspace.contexts[key][0].project)] = runtime
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, route, project=None, method="GET", payload=None):
        headers = {"Content-Type": "application/json"}
        if project is not None:
            headers["X-ScAgentKit-Run-Project"] = project
        conn = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=5)
        conn.request(method, route, json.dumps(payload) if payload is not None else None, headers)
        response = conn.getresponse()
        status, body = response.status, json.loads(response.read())
        conn.close()
        return status, body

    @staticmethod
    def route(identity="parent"):
        return "/api/run-review/workbench?project_id=" + identity + (
            "&child_id=" + identity if identity != "parent" else "")

    def assert_no_mutation(self):
        self.assertEqual(self.parent_review.decisions, [])
        self.assertEqual(self.parent_qc.decisions, [])
        self.assertEqual(self.jobs.submissions, [])
        self.assertEqual(self.models.operations, [])
        self.assertEqual(self.workspace.operations, [])
        for review, jobs, qc in self.workspace.contexts.values():
            self.assertEqual(review.decisions, [])
            self.assertEqual(qc.decisions, [])
            self.assertEqual(jobs.submissions, [])
        self.assertIsNone(self.server.store)
        self.assertIsNone(self.server.registry)
        self.assertEqual(self.server.project_contexts, {})

    def assert_navigation(self, body, identity, frozen):
        navigation = body["navigation"]
        for key, path in (("review_url", "/review"), ("subclusters_url", "/subclusters")):
            parsed = urlsplit(navigation[key])
            self.assertEqual(parsed.scheme, "")
            self.assertEqual(parsed.netloc, "")
            self.assertEqual(parsed.path, path)
            self.assertEqual(parsed.fragment, "")
            expected = {"project_id": [identity]}
            if identity != "parent":
                expected["child_id"] = [identity]
            self.assertEqual(parse_qs(parsed.query, keep_blank_values=True), expected)
        self.assertEqual(navigation["frozen"], frozen)
        for key in ("can_review", "can_revise", "can_undo"):
            self.assertEqual(navigation[key], not frozen)

    def test_frozen_parent_retains_complete_run_history_evidence_and_binding(self):
        before = copy.deepcopy(self.parent_runtime.view)
        status, body = self.request(self.route(), "parent")
        self.assertEqual(status, 200)
        self.assertEqual(body["schema"], "scagentkit.workbench.v1")
        for key in ("run", "full", "history", "evidence"):
            self.assertEqual(body[key], before[key], "Frozen inspection must preserve " + key)
        for key, value in before["binding"].items():
            self.assertEqual(body["binding"][key], value, "Frozen inspection must preserve binding " + key)
        self.assertEqual(len(body["binding"]["workspace_fingerprint"]), 64)
        self.assertEqual(body["project"]["scope"], "parent")
        self.assertTrue(body["project"]["frozen"])
        self.assertEqual(body["children"], self.workspace.readiness()["children"])
        self.assert_navigation(body, "parent", True)
        self.assertEqual(self.parent_runtime.view, before, "HTTP augmentation cannot mutate the runtime fixture")
        self.assert_no_mutation()

    def test_live_parent_full_inspection_keeps_scientific_authority_in_navigation(self):
        self.workspace.ready = False
        self.parent_runtime.view = workbench_view("parent", complete=False)
        self.workspace.parent_snapshot = copy.deepcopy(self.parent_runtime.view["run"])
        status, body = self.request(self.route(), "parent")
        self.assertEqual(status, 200)
        self.assertFalse(body["project"]["frozen"])
        self.assertEqual(body["run"], self.parent_runtime.view["run"])
        self.assertEqual(body["children"], [])
        self.assert_navigation(body, "parent", False)
        self.assert_no_mutation()

    def test_registered_child_reads_keep_selected_identity_across_tabs_and_refresh(self):
        for identity in ("child-A", "parent", "child-B", "child-A"):
            with self.subTest(identity=identity):
                status, body = self.request(self.route(identity), identity)
                self.assertEqual(status, 200)
                runtime = self.parent_runtime if identity == "parent" else self.child_runtimes[identity]
                self.assertEqual(body["run"], runtime.view["run"])
                self.assertEqual(body["project"]["project_id"], identity)
                self.assertEqual(body["project"]["scope"], "parent" if identity == "parent" else "child")
                self.assert_navigation(body, identity, identity == "parent")
        self.assertEqual(self.child_runtimes["child-A"].calls, ["inspect", "inspect"])
        self.assertEqual(self.child_runtimes["child-B"].calls, ["inspect"])
        self.assertEqual(self.workspace.resolutions, ["child-A", "child-B", "child-A"])
        self.assert_no_mutation()

    def test_child_runtime_is_created_only_from_registered_review_and_then_cached(self):
        self.server.workbench_contexts.clear()
        created = []
        def factory(project, library, rscript):
            created.append((project, library, rscript))
            key = next(key for key, context in self.workspace.contexts.items() if context[0].project == project)
            return self.child_runtimes[key]
        with patch("server.RunWorkbenchRuntime", side_effect=factory):
            for identity in ("child-A", "child-B", "child-A"):
                self.assertEqual(self.request(self.route(identity), identity)[0], 200)
        self.assertEqual(created, [(self.workspace.contexts[key][0].project, None, "Rscript")
                                   for key in ("child-A", "child-B")])
        self.assertEqual(len(self.server.workbench_contexts), 2)
        self.assertIs(self.server.run_workbench, self.parent_runtime)
        self.assert_no_mutation()

    def test_exact_query_and_run_header_are_both_required(self):
        cases = [("/api/run-review/workbench", "parent"),
                 ("/api/run-review/workbench?child_id=child-A", "child-A"),
                 (self.route(), None), (self.route("child-A"), None)]
        for route, header in cases:
            with self.subTest(route=route, header=header):
                self.assertIn(self.request(route, header)[0], (409, 422))
        self.assertEqual(self.parent_runtime.calls, [])
        self.assertTrue(all(not runtime.calls for runtime in self.child_runtimes.values()))
        self.assert_no_mutation()

    def test_other_child_header_and_query_identity_mismatch_stop_before_resolution(self):
        cases = [(self.route("child-A"), "child-B"),
                 (self.route(), "child-A"),
                 ("/api/run-review/workbench?project_id=child-B&child_id=child-A", "child-A")]
        for route, header in cases:
            with self.subTest(route=route, header=header):
                self.assertEqual(self.request(route, header)[0], 409)
        self.assertEqual(self.workspace.resolutions, [])
        self.assertTrue(all(not runtime.calls for runtime in self.child_runtimes.values()))
        self.assert_no_mutation()

    def test_foreign_child_and_parent_disguised_as_child_have_no_parent_fallback(self):
        for identity in ("foreign-child", "parent"):
            route = "/api/run-review/workbench?project_id=" + identity + "&child_id=" + identity
            with self.subTest(identity=identity):
                self.assertEqual(self.request(route, identity)[0], 409)
        self.assertEqual(self.parent_runtime.calls, [])
        self.assertTrue(all(not runtime.calls for runtime in self.child_runtimes.values()))
        self.assert_no_mutation()

    def test_duplicate_blank_and_path_query_parameters_are_rejected(self):
        queries = ["project_id=parent&project_id=parent",
                   "project_id=child-A&child_id=child-A&child_id=child-A",
                   "project_id=", "project_id=parent&child_id=",
                   "project_id=parent&project_dir=/tmp/data",
                   "project_id=parent&path=/tmp/data", "project_id=parent&column=sc_subtype"]
        for query in queries:
            with self.subTest(query=query):
                self.assertEqual(self.request("/api/run-review/workbench?" + query, "parent")[0], 422)
        self.assertEqual(self.parent_runtime.calls, [])
        self.assertEqual(self.workspace.resolutions, [])
        self.assert_no_mutation()

    def test_path_cannot_be_used_as_a_registered_project_identity(self):
        self.assertEqual(self.request("/api/run-review/workbench?project_id=%2Ftmp%2Fdata", "/tmp/data")[0], 409)
        self.assertEqual(self.parent_runtime.calls, [])
        self.assert_no_mutation()

    def test_runtime_project_must_match_its_complete_run_binding(self):
        for name, value in (("project_id", "foreign"), ("input_hash", "0" * 64),
                            ("revision", 11), ("history_head", "0" * 64)):
            with self.subTest(name=name):
                self.parent_runtime.view = workbench_view("parent")
                self.parent_runtime.view["project"][name] = value
                self.assertEqual(self.request(self.route(), "parent")[0], 409)
        self.assert_no_mutation()

    def test_workspace_application_change_during_projection_rejects_stale_response(self):
        before = self.workspace.readiness()
        changed = copy.deepcopy(before)
        changed["children"][0]["applications"].append({"application_id": "new-derived", "active": True})
        with patch.object(self.workspace, "readiness", side_effect=[before, changed]):
            self.assertEqual(self.request(self.route(), "parent")[0], 409)
        self.assert_no_mutation()

    def test_oversized_full_history_refuses_display_without_truncating_saved_events(self):
        original = copy.deepcopy(self.parent_runtime.view["history"])
        self.parent_runtime.view["run"]["context"]["notes"] = "x" * (16 * 1024 * 1024)
        status, body = self.request(self.route(), "parent")
        self.assertEqual(status, 409)
        self.assertIn("No history or evidence was truncated", body["error"])
        self.assertEqual(self.parent_runtime.view["history"], original)
        self.assert_no_mutation()

    def test_frozen_lifecycle_cannot_authorize_another_input_or_revision(self):
        for name, value in (("input_hash", "0" * 64), ("revision", 11),
                            ("history_head", "0" * 64)):
            with self.subTest(name=name):
                self.parent_runtime.view = workbench_view("parent")
                self.parent_runtime.view["project"][name] = value
                self.parent_runtime.view["run"][name] = value
                self.parent_runtime.view["binding"][name] = value
                self.assertEqual(self.request(self.route(), "parent")[0], 409)
        self.assert_no_mutation()

    def test_no_workspace_navigation_exposes_no_child_path(self):
        self.server.run_subcluster = None
        status, body = self.request(self.route(), "parent")
        self.assertEqual(status, 200)
        self.assertEqual(body["children"], [])
        self.assertEqual(body["navigation"]["review_url"], "/review?project_id=parent")
        self.assertIsNone(body["navigation"]["subclusters_url"])
        self.assert_no_mutation()

    def test_post_cannot_turn_the_aggregate_read_route_into_an_operation(self):
        for identity in ("parent", "child-A"):
            with self.subTest(identity=identity):
                status, _ = self.request(self.route(identity), identity, "POST",
                                         {"project_id": identity, "action": "approve"})
                self.assertIn(status, (404, 405, 409))
        self.assertEqual(self.parent_runtime.calls, [])
        self.assertTrue(all(not runtime.calls for runtime in self.child_runtimes.values()))
        self.assert_no_mutation()

    def test_legacy_evidence_and_generic_store_routes_keep_the_run_only_guard(self):
        for route in ("/api/evidence", "/api/session", "/api/export", "/api/projects"):
            with self.subTest(route=route):
                self.assertEqual(self.request(route, "parent")[0], 409)
        self.assertEqual(self.parent_runtime.calls, [])
        self.assert_no_mutation()

    def test_repeated_readonly_inspection_never_changes_saved_facts_or_dispatches(self):
        before_parent = copy.deepcopy(self.parent_runtime.view)
        before_children = {key: copy.deepcopy(runtime.view) for key, runtime in self.child_runtimes.items()}
        for _ in range(2):
            for identity in ("parent", "child-A", "child-B"):
                self.assertEqual(self.request(self.route(identity), identity)[0], 200)
        self.assertEqual(self.parent_runtime.view, before_parent)
        self.assertEqual({key: runtime.view for key, runtime in self.child_runtimes.items()}, before_children)
        self.assert_no_mutation()


if __name__ == "__main__":
    unittest.main()
