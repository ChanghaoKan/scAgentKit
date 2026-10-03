"""HTTP project binding, hostile inputs and portable journal integration."""
import http.client
import hashlib
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from project import ProjectRegistry, zip_bytes
from evidence import canonical
from server import WorkbenchServer
from test_project import project_fixture, write_bundle, bundle_blobs, make_zip


class ProjectHTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        self.a = write_bundle(root / "source-a", project_fixture("project-A"))
        self.b = write_bundle(root / "source-b", project_fixture("project-B", embedded=False))
        self.registry = ProjectRegistry(root / "cache", root / "journals", self.a)
        self.key_a = self.registry.initial_key
        self.key_b = self.registry.add_directory(self.b)["key"]
        self.server = WorkbenchServer(("127.0.0.1", 0), None, None, registry=self.registry)
        self.server.select_project(self.key_a)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, method, route, payload=None, key=None, raw=None, content_type="application/json", headers=None):
        headers = dict(headers or {})
        if key is not None:
            headers["X-ScAgentKit-Project"] = key
        if payload is not None or raw is not None:
            headers["Content-Type"] = content_type
        body = raw if raw is not None else json.dumps(payload).encode() if payload is not None else None
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        connection.request(method, route, body, headers)
        response = connection.getresponse()
        data = response.read()
        result = (response.status, dict(response.getheaders()), data)
        connection.close()
        return result

    def parsed(self, method, route, **kwargs):
        status, headers, data = self.request(method, route, **kwargs)
        return status, json.loads(data)

    def decision(self, revision, request_id="record"):
        return {"clusterId": "T alpha", "dimension": "type", "label": "unknown", "reason": "Measured evidence is incomplete",
                "status": "accepted", "revision": revision, "requestId": request_id}

    def test_two_tabs_read_directed_history_and_exports_from_own_project(self):
        self.server.select_project(self.key_b)
        for key, project_id in ((self.key_a, "project-A"), (self.key_b, "project-B")):
            status, evidence = self.parsed("GET", "/api/evidence", key=key)
            self.assertEqual((status, evidence["dataset"]["id"]), (200, project_id))
            status, session = self.parsed("GET", "/api/session", key=key)
            self.assertEqual((status, session["datasetId"]), (200, project_id))
            status, directed = self.parsed("GET", "/api/directed?clusterId=T%20alpha", key=key)
            self.assertEqual((status, directed["plan"]["scope"]["datasetId"]), (200, project_id))
            status, journal = self.parsed("GET", "/api/export", key=key)
            self.assertEqual((status, journal["projectId"]), (200, project_id))
            status, headers, archive = self.request("GET", "/api/project/export", key=key)
            self.assertEqual(status, 200)
            self.assertEqual(headers["Content-Type"], "application/zip")
            self.assertEqual(json.loads(zip_bytes(archive)["project.json"])["projectId"], project_id)
        self.assertEqual(self.server.selected_key, self.key_b)

    def test_bound_write_stays_in_project_and_unbound_stale_write_is_rejected(self):
        self.server.select_project(self.key_b)
        status, _ = self.parsed("POST", "/api/decision", payload=self.decision(self.key_a))
        self.assertEqual(status, 409)
        status, state = self.parsed("POST", "/api/decision", payload=self.decision(self.key_a), key=self.key_a)
        self.assertEqual(status, 200)
        self.assertEqual(state["events"][0]["scope"]["datasetId"], "project-A")
        self.assertEqual(state["events"][0]["scope"]["cellIds"], ["001", "NA"])
        self.assertEqual(self.parsed("GET", "/api/session", key=self.key_b)[1]["events"], [])
        repeated = self.parsed("POST", "/api/decision", payload=self.decision(self.key_a), key=self.key_a)
        self.assertEqual(repeated, (status, state))

    def test_project_zip_import_and_journal_json_are_separate_idempotent_routes(self):
        raw = make_zip(bundle_blobs(project_fixture("project-C")))
        status, imported = self.parsed("POST", "/api/project/import", raw=raw, content_type="application/zip")
        self.assertEqual(status, 200)
        self.assertEqual(imported["projectId"], "project-C")
        self.assertEqual(self.server.selected_key, imported["key"])
        status, journal = self.parsed("GET", "/api/export", key=imported["key"])
        self.assertEqual(status, 200)
        self.assertEqual(journal["schema"], "scagentkit.review-journal.v1")
        self.assertEqual(self.parsed("POST", "/api/import", payload=journal, key=imported["key"])[0], 200)
        self.assertEqual(self.parsed("POST", "/api/project/import", payload=journal)[0], 415)
        self.assertEqual(self.parsed("POST", "/api/import", raw=raw, content_type="application/zip")[0], 415)
        status, again = self.parsed("POST", "/api/project/import", raw=raw, content_type="application/zip")
        self.assertEqual((status, again["key"]), (200, imported["key"]))

    def test_corrupt_actual_cache_disables_evidence_and_session_writes(self):
        self.parsed("POST", "/api/decision", payload=self.decision(self.key_a), key=self.key_a)
        loader, _, _ = self.server.project_context(self.key_a)
        with (loader.root / "project.json").open("ab") as file:
            file.write(b" ")
        status, error = self.parsed("GET", "/api/evidence", key=self.key_a)
        self.assertEqual(status, 422)
        self.assertTrue(error["readOnly"])
        status, session = self.parsed("GET", "/api/session", key=self.key_a)
        self.assertEqual(status, 200)
        self.assertTrue(session["readOnly"])
        self.assertTrue(session["events"][0]["stale"])
        self.assertEqual(self.parsed("POST", "/api/decision", payload=self.decision(self.key_a, "next"), key=self.key_a)[0], 422)

    def test_unknown_binding_and_duplicate_json_fail_closed(self):
        self.assertNotEqual(self.parsed("GET", "/api/session", key="f" * 64)[0], 200)
        status, error = self.parsed("POST", "/api/project/select", raw=b'{"key":"a","key":"b"}')
        self.assertEqual(status, 422)
        self.assertIn("Duplicate", error["error"])
        raw = make_zip(bundle_blobs(project_fixture("bad")), additions=[("../escape", b"bad")])
        self.assertEqual(self.parsed("POST", "/api/project/import", raw=raw, content_type="application/zip")[0], 422)
        self.assertEqual(self.parsed("GET", "/api/session", key=self.key_a)[1]["events"], [])

    def test_validly_resealed_foreign_snapshot_cannot_replace_bound_key(self):
        self.parsed("POST", "/api/decision", payload=self.decision(self.key_a), key=self.key_a)
        loader, _, _ = self.server.project_context(self.key_a)
        # All checksums are valid, but this is a different actual snapshot at A's path.
        write_bundle(loader.root, project_fixture("foreign-snapshot"))
        status, error = self.parsed("GET", "/api/evidence", key=self.key_a)
        self.assertEqual(status, 409)
        self.assertTrue(error["readOnly"])
        status, session = self.parsed("GET", "/api/session", key=self.key_a)
        self.assertEqual(status, 200)
        self.assertEqual(session["datasetId"], "project-A")
        self.assertTrue(session["readOnly"])
        self.assertTrue(session["events"][0]["stale"])
        self.assertEqual(self.parsed("POST", "/api/decision", payload=self.decision(self.key_a, "next"), key=self.key_a)[0], 409)

    def test_rule_registry_change_marks_only_referenced_history_stale_over_http(self):
        loader, store, runtime = self.server.project_context(self.key_a)
        evidence = loader.load()
        raw = canonical({"clusterId": "T alpha", "revision": self.key_a,
                         "sourceFingerprint": evidence["sourceFingerprint"], "rulesHash": "old rules"})
        capsule = hashlib.sha256(raw.encode()).hexdigest()
        # Simulate a restarted runtime with a new rules/taxonomy registry while
        # keeping the same verified project. Requests still use the real HTTP path.
        current = {capsule: {"payload": raw, "sha256": capsule}}
        runtime.augment = lambda current_evidence: dict(current_evidence, directedArtifacts=current)
        payload = dict(self.decision(self.key_a), evidenceRefs=[capsule])
        self.assertEqual(self.parsed("POST", "/api/decision", payload=payload, key=self.key_a)[0], 200)
        ordinary = dict(self.decision(self.key_a, "ordinary-qc"), dimension="QC", label="manual review")
        self.assertEqual(self.parsed("POST", "/api/decision", payload=ordinary, key=self.key_a)[0], 200)
        original_bytes = store.path.read_bytes()
        original_package = self.parsed("GET", "/api/export", key=self.key_a)[1]
        current.clear()
        status, state = self.parsed("GET", "/api/session", key=self.key_a)
        self.assertEqual(status, 200)
        self.assertFalse(state["readOnly"])
        self.assertFalse(state["stale"])
        self.assertEqual([event["stale"] for event in state["events"]], [True, False])
        referenced = next(item for item in state["decisions"] if item["scope"]["dimension"] == "type")
        self.assertEqual((referenced["label"], referenced["status"], referenced["stale"]), ("unknown", "accepted", True))
        self.assertEqual(self.parsed("GET", "/api/export", key=self.key_a)[1], original_package)
        self.assertEqual(store.path.read_bytes(), original_bytes)
        status, imported = self.parsed("POST", "/api/import", payload=original_package, key=self.key_a)
        self.assertEqual((status, imported["events"][0]["stale"]), (200, True))


if __name__ == "__main__":
    unittest.main()
