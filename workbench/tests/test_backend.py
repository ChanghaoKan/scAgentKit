"""Portable ledger / HTTP tests plus opt-in real frozen PBMC evidence checks.

SCAGENTKIT_TEST_RESULTS=/path/to/results python3 -m unittest discover -s workbench/tests -v
"""
import copy
import hashlib
import http.client
import json
import os
import shutil
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evidence import ALLOWED_FILES, DATASET_ID, EvidenceError, EvidenceLoader, digest, revision_for
from server import WorkbenchServer
from store import SessionStore, StoreError, validate_package


def synthetic_evidence():
    sizes = (400, 400, 400, 400, 400, 250, 155, 150, 83)
    groups, index = [], 0
    for cluster, size in enumerate(sizes):
        groups.append({"id": str(cluster), "cellIds": ["test-cell-%04d" % value for value in range(index, index + size)]})
        index += size
    sources = [{"id": source, "sha256": hashlib.sha256(source.encode()).hexdigest()} for source in ALLOWED_FILES]
    return {"revision": revision_for(sources), "dataset": {"id": DATASET_ID}, "clusters": groups, "sources": sources}


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.evidence = synthetic_evidence()
        self.path = Path(self.temp.name) / "session.json"
        self.store = SessionStore(self.path)

    def tearDown(self):
        self.temp.cleanup()

    def payload(self, **change):
        return {"clusterId": "6", "dimension": "type", "label": "unknown", "reason": "Cytotoxic evidence needs review",
                "status": "proposed", "revision": self.evidence["revision"], "requestId": "test-request", **change}

    def test_unknown_exact_scope_is_saved_without_source_mutation(self):
        original = copy.deepcopy(self.evidence)
        result = self.store.decision(self.payload(label="Unknown"), self.evidence)
        decision = result["decisions"][0]
        self.assertEqual(decision["label"], "unknown")
        self.assertEqual(decision["scope"]["cellIds"], self.evidence["clusters"][6]["cellIds"])
        self.assertEqual(len(decision["scope"]["cellIds"]), 155)
        self.assertEqual(decision["scope"]["dimension"], "type")
        self.assertEqual(self.evidence, original)
        self.assertFalse(result["readOnly"])

    def test_no_decision_is_distinct_from_explicit_unknown(self):
        self.assertEqual(self.store.session(self.evidence)["decisions"], [])
        self.assertEqual(self.store.decision(self.payload(), self.evidence)["decisions"][0]["label"], "unknown")

    def test_dimensions_and_workflow_states_do_not_conflate(self):
        for dimension, status in zip(("type", "state", "QC"), ("proposed", "reviewed", "accepted")):
            result = self.store.decision(self.payload(dimension=dimension, status=status, requestId=dimension), self.evidence)
        self.assertEqual(len(result["decisions"]), 3)
        self.assertEqual({row["scope"]["dimension"] for row in result["decisions"]}, {"type", "state", "QC"})

    def test_repeated_click_is_idempotent_and_changed_reuse_rejected(self):
        first = self.store.decision(self.payload(), self.evidence)
        self.assertEqual(self.store.decision(self.payload(), self.evidence), first)
        with self.assertRaises(StoreError):
            self.store.decision(self.payload(label="NK"), self.evidence)
        self.assertEqual(len(self.store.session(self.evidence)["events"]), 1)

    def test_concurrent_repeated_clicks_create_one_event(self):
        errors = []
        def click():
            try:
                self.store.decision(self.payload(), self.evidence)
            except Exception as error:
                errors.append(error)
        threads = [threading.Thread(target=click) for _ in range(8)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(errors, [])
        self.assertEqual(len(self.store.session(self.evidence)["events"]), 1)

    def test_invalid_missing_fields_rejected(self):
        changes = [{"reason": " "}, {"label": ""}, {"dimension": "wrong"}, {"status": "truth"},
                   {"clusterId": "99"}, {"clusterId": []}, {"requestId": ""}, {"extra": "ignored?"}]
        for change in changes:
            with self.subTest(change=change), self.assertRaises(StoreError):
                self.store.decision(self.payload(**change), self.evidence)
        missing = self.payload()
        del missing["reason"]
        with self.assertRaises(StoreError):
            self.store.decision(missing, self.evidence)
        self.assertFalse(self.path.exists())

    def test_undo_appends_compensation_and_restores_prior_decision(self):
        self.store.decision(self.payload(), self.evidence)
        first = copy.deepcopy(self.store.export(self.evidence)["events"])
        state = self.store.decision(self.payload(label="NK cell", status="reviewed", requestId="second"), self.evidence)
        target = state["events"][-1]["id"]
        payload = {"targetEventId": target, "reason": "Review reversed", "revision": self.evidence["revision"], "requestId": "undo"}
        state = self.store.undo(payload, self.evidence)
        self.assertEqual(len(state["events"]), 3)
        self.assertEqual(state["decisions"][0]["label"], "unknown")
        self.assertEqual(self.store.export(self.evidence)["events"][:1], first)
        self.assertEqual(self.store.undo(payload, self.evidence), state)
        with self.assertRaises(StoreError):
            self.store.undo(dict(payload, requestId="undo-again"), self.evidence)

    def test_refresh_reload_and_export_import_are_identical(self):
        state = self.store.decision(self.payload(), self.evidence)
        self.assertEqual(SessionStore(self.path).session(self.evidence), state)
        package = self.store.export(self.evidence)
        second = SessionStore(Path(self.temp.name) / "reloaded.json")
        self.assertEqual(second.import_package(package, self.evidence), state)
        self.assertEqual(second.export(self.evidence), package)
        self.assertEqual(second.import_package(package, self.evidence), state)
        serialized = json.dumps(package)
        for forbidden in ("rawText", "raw_response", "truth", "matrix", "system_prompt"):
            self.assertNotIn(forbidden, serialized)

    def test_import_never_replaces_or_truncates_history(self):
        self.store.decision(self.payload(), self.evidence)
        old = self.store.export(self.evidence)
        self.store.decision(self.payload(requestId="second", label="NK cell"), self.evidence)
        with self.assertRaises(StoreError):
            self.store.import_package(old, self.evidence)
        changed = self.store.export(self.evidence)
        changed["events"][0]["reason"] = "rewrite"
        changed["events"][0]["hash"] = digest({key: value for key, value in changed["events"][0].items() if key != "hash"})
        with self.assertRaises(StoreError):
            self.store.import_package(changed, self.evidence)
        self.assertEqual(len(self.store.session(self.evidence)["events"]), 2)

    def test_actual_changed_source_hash_marks_old_decision_stale(self):
        self.store.decision(self.payload(), self.evidence)
        changed = copy.deepcopy(self.evidence)
        changed["sources"][0]["sha256"] = "a" * 64
        changed["revision"] = revision_for(changed["sources"])
        state = self.store.session(changed)
        self.assertTrue(state["decisions"][0]["stale"])
        with self.assertRaises(StoreError):
            self.store.decision(self.payload(requestId="stale"), changed)
        result = self.store.decision(self.payload(revision=changed["revision"], requestId="fresh"), changed)
        self.assertEqual([decision["stale"] for decision in result["decisions"]], [True, False])

    def test_invalid_changed_input_disables_writes_in_view(self):
        self.store.decision(self.payload(), self.evidence)
        state = self.store.session(self.evidence, "Input is missing")
        self.assertTrue(state["readOnly"])
        self.assertEqual(state["evidenceError"], "Input is missing")
        self.assertIsNone(state["revision"])
        self.assertTrue(state["decisions"][0]["stale"])

    def test_corrupt_duplicate_and_broken_reference_packages_rejected(self):
        self.store.decision(self.payload(), self.evidence)
        original = self.store.export(self.evidence)
        modifications = [("scope", "revision", []), ("scope", "clusterId", []), ("scope", "dimension", []),
                         ("scope", "cellIds", ["invented"]), (None, "id", []), (None, "supersedes", "missing"),
                         (None, "requestId", []), (None, "hash", "f" * 64)]
        for parent, key, value in modifications:
            broken = copy.deepcopy(original)
            if parent:
                broken["events"][0][parent][key] = value
            else:
                broken["events"][0][key] = value
            if key != "hash":
                broken["events"][0]["hash"] = digest({k: v for k, v in broken["events"][0].items() if k != "hash"})
            with self.subTest(key=key), self.assertRaises(StoreError):
                validate_package(broken, self.evidence)
        duplicate = copy.deepcopy(original)
        duplicate["events"].append(copy.deepcopy(duplicate["events"][0]))
        with self.assertRaises(StoreError):
            validate_package(duplicate, self.evidence)

    def test_damaged_disk_history_is_read_only_and_never_rewritten(self):
        self.store.decision(self.payload(), self.evidence)
        package = self.store.export(self.evidence)
        package["events"][0]["scope"]["revision"] = []
        package["events"][0]["hash"] = digest({key: value for key, value in package["events"][0].items() if key != "hash"})
        self.path.write_text(json.dumps(package))
        content = self.path.read_bytes()
        state = SessionStore(self.path).session(self.evidence)
        self.assertTrue(state["readOnly"])
        self.assertTrue(state["integrityError"])
        with self.assertRaises(StoreError):
            self.store.decision(self.payload(requestId="after-corruption"), self.evidence)
        self.assertEqual(self.path.read_bytes(), content)

    def test_size_rejected_write_preserves_readable_identical_history(self):
        state = self.store.decision(self.payload(), self.evidence)
        original = self.path.read_bytes()
        exported = self.store.export(self.evidence)
        with patch("store.MAX_SESSION_BYTES", len(original) + 100):
            with self.assertRaises(StoreError) as failure:
                self.store.decision(self.payload(requestId="would-overflow", reason="A" * 4000), self.evidence)
            self.assertEqual(failure.exception.status, 413)
            self.assertEqual(self.path.read_bytes(), original)
            self.assertEqual(self.store.export(self.evidence), exported)
            self.assertEqual(self.store.session(self.evidence), state)
            self.assertFalse(SessionStore(self.path).session(self.evidence)["readOnly"])
            self.assertEqual(list(self.path.parent.glob(".session.json.*")), [])

    def test_size_rejected_import_preserves_empty_store(self):
        self.store.decision(self.payload(), self.evidence)
        package = self.store.export(self.evidence)
        empty_path = Path(self.temp.name) / "empty.json"
        empty = SessionStore(empty_path)
        with patch("store.MAX_SESSION_BYTES", 100):
            with self.assertRaises(StoreError) as failure:
                empty.import_package(package, self.evidence)
            self.assertEqual(failure.exception.status, 413)
            self.assertFalse(empty_path.exists())
            self.assertEqual(empty.session(self.evidence)["events"], [])
            self.assertFalse(empty.session(self.evidence)["readOnly"])


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        evidence = synthetic_evidence()
        class Loader:
            latest = evidence
            def load(self):
                return evidence
        self.server = WorkbenchServer(("127.0.0.1", 0), Loader(), SessionStore(Path(self.temp.name) / "session.json"))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        connection.request(method, path, body, headers or {})
        response = connection.getresponse()
        content = response.read()
        connection.close()
        return response.status, dict(response.getheaders()), content

    def test_csp_and_local_assets(self):
        status, headers, content = self.request("GET", "/")
        self.assertEqual(status, 200)
        self.assertIn("connect-src 'self'", headers["Content-Security-Policy"])
        self.assertIn("no-store", headers["Cache-Control"])
        self.assertNotIn("Access-Control-Allow-Origin", headers)
        self.assertTrue(content)

    def test_host_origin_cross_site_and_path_traversal_rejected(self):
        for headers in ({"Host": "attacker.example"}, {"Origin": "https://attacker.example"}, {"Sec-Fetch-Site": "cross-site"}):
            with self.subTest(headers=headers):
                self.assertEqual(self.request("GET", "/api/session", headers=headers)[0], 403)
        for path in ("/../server.py", "/%2e%2e/server.py", "/api/../../store.py", "/server.py"):
            self.assertEqual(self.request("GET", path)[0], 404)
        self.assertEqual(self.request("OPTIONS", "/api/decision")[0], 403)

    def test_invalid_json_content_type_duplicate_keys_and_fields(self):
        self.assertEqual(self.request("POST", "/api/decision", "{}")[0], 415)
        headers = {"Content-Type": "application/json"}
        for body in ("{", "null", "[]", '{"revision":NaN}', '{"package":{},"package":{}}', "{}"):
            self.assertEqual(self.request("POST", "/api/decision", body, headers)[0], 422)

    def test_explicit_scope_ignores_no_client_cell_list(self):
        evidence = self.server.loader.load()
        payload = {"clusterId": "6", "dimension": "type", "label": "unknown", "reason": "Review", "status": "proposed",
                   "revision": evidence["revision"], "requestId": "http"}
        status, _, content = self.request("POST", "/api/decision", json.dumps(payload), {"Content-Type": "application/json"})
        self.assertEqual(status, 200)
        self.assertEqual(len(json.loads(content)["events"][0]["scope"]["cellIds"]), 155)
        payload["cellIds"] = ["other-cell"]
        self.assertEqual(self.request("POST", "/api/decision", json.dumps(payload), {"Content-Type": "application/json"})[0], 422)

    def test_direct_raw_handoff_import_checks_original_duplicate_keys(self):
        evidence = self.server.loader.load()
        self.server.store.decision({"clusterId": "6", "dimension": "type", "label": "unknown", "reason": "Review",
                                    "status": "proposed", "revision": evidence["revision"], "requestId": "direct-import"}, evidence)
        prior = self.server.store.session(evidence)
        package = self.server.store.export(evidence)
        raw = json.dumps(package, separators=(",", ":"))
        headers = {"Content-Type": "application/json"}
        status, _, content = self.request("POST", "/api/import", raw, headers)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(content), prior)
        self.assertEqual(self.request("POST", "/api/import", json.dumps({"package": package}), headers)[0], 200)
        duplicated = raw.replace('"datasetId":"pbmc3k-phase1"', '"datasetId":"pbmc3k-phase1","datasetId":"pbmc3k-phase1"', 1)
        status, _, content = self.request("POST", "/api/import", duplicated, headers)
        self.assertEqual(status, 422)
        self.assertIn("Duplicate JSON object key", json.loads(content)["error"])
        self.assertEqual(self.server.store.session(evidence), prior)


@unittest.skipUnless(os.environ.get("SCAGENTKIT_TEST_RESULTS"), "Set SCAGENTKIT_TEST_RESULTS for real frozen evidence")
class RealEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(os.environ["SCAGENTKIT_TEST_RESULTS"])
        self.loader = EvidenceLoader(self.root)

    def test_real_frozen_pbmc_shapes_and_conflict(self):
        evidence = self.loader.load()
        self.assertEqual(evidence["dataset"]["retainedCells"], 2638)
        self.assertEqual(len(evidence["clusters"]), 9)
        cluster = next(row for row in evidence["clusters"] if row["id"] == "6")
        self.assertEqual(cluster["cellCount"], 155)
        self.assertEqual(len(cluster["markers"]), 30)
        self.assertAlmostEqual(cluster["markers"][0]["pct1"], .961)
        self.assertEqual(evidence["summary"], {"modelCalls": 36, "strictValid": 33, "formatRejected": 2, "networkFailed": 1})
        self.assertIn("biological_disagreement", cluster["issueKinds"])
        self.assertEqual(cluster["models"][0]["strict"]["label"], "Terminal effector CD8+ T cell")
        self.assertEqual(cluster["models"][1]["strict"]["label"], "NK cell")
        failed = [model for row in evidence["clusters"] for model in row["models"] if model["strictStatus"] != "valid"]
        self.assertTrue(all(model["strict"]["label"] is None for model in failed))

    def copy_fixture(self, root):
        for source in ALLOWED_FILES:
            target = Path(root) / source
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.root / source, target)

    def test_content_changes_stale_but_copy_path_does_not(self):
        with tempfile.TemporaryDirectory() as temporary:
            self.copy_fixture(temporary)
            loader = EvidenceLoader(temporary)
            original = loader.load()
            self.assertEqual(original["revision"], self.loader.load()["revision"])
            store = SessionStore(Path(temporary) / "review.json")
            store.decision({"clusterId": "6", "dimension": "type", "label": "unknown", "reason": "Review",
                            "status": "proposed", "revision": original["revision"], "requestId": "real"}, original)
            target = Path(temporary) / ALLOWED_FILES[0]
            content = target.read_text()
            target.write_text(content.replace("3.25331320391679", "3.25331320391680", 1))
            changed = loader.load()
            self.assertNotEqual(original["revision"], changed["revision"])
            self.assertTrue(store.session(changed)["decisions"][0]["stale"])
            target.unlink()
            with self.assertRaises(EvidenceError):
                loader.load()
            self.assertTrue(loader.error)

    def test_malformed_raw_and_reference_manifest_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            self.copy_fixture(temporary)
            for source, value in ((ALLOWED_FILES[4], "[]"), ("pbmc3k_api/deepseek_guided_0.json", "null")):
                path = Path(temporary) / source
                prior = path.read_bytes()
                path.write_text(value)
                loader = EvidenceLoader(temporary)
                with self.subTest(source=source), self.assertRaises(EvidenceError):
                    loader.load()
                self.assertTrue(loader.error)
                path.write_bytes(prior)


if __name__ == "__main__":
    unittest.main()
