"""Immutable raw-payload generic journals, independent of legacy PBMC ledgers."""
import copy
import hashlib
import json
import multiprocessing
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import project_store as module
from evidence import canonical, strict_json
from project import ProjectLoader
from project_store import ProjectStore, ProjectStoreError, envelope_hash, validate_package
from test_project import project_fixture, write_bundle


def decision(evidence, request="decision-1", **fields):
    return {"clusterId": "T alpha", "dimension": "type", "label": "T cell", "reason": "Review actual local evidence",
            "status": "accepted", "revision": evidence["revision"], "requestId": request, **fields}


def rewrite_events(package, change):
    """Deliberately recompute hashes to test semantic validation beyond hashing."""
    package = copy.deepcopy(package)
    previous = module.ZERO_HASH
    for index, envelope in enumerate(package["events"]):
        event = strict_json(envelope["payload"])
        change(event, index)
        raw = canonical(event)
        envelope.update(payload=raw, prevHash=previous, hash=envelope_hash(previous, raw))
        previous = envelope["hash"]
    return package


def process_decide(path, evidence, payload, output):
    try:
        result = ProjectStore(path).decide(payload, evidence)
        output.put((True, len(result["events"])))
    except Exception as error:
        output.put((False, str(error)))


class ProjectStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        write_bundle(self.root / "project")
        self.evidence = ProjectLoader(self.root / "project").load()
        self.store = ProjectStore(self.root / "journals" / "ledger.json")

    def tearDown(self):
        self.temp.cleanup()

    def accept(self, **fields):
        return self.store.decide(decision(self.evidence, **fields), self.evidence)

    def assertUnchangedRejected(self, fn):
        before = self.store.path.read_bytes() if self.store.path.exists() else None
        with self.assertRaises(ProjectStoreError):
            fn()
        after = self.store.path.read_bytes() if self.store.path.exists() else None
        self.assertEqual(after, before)

    def test_unknown_accepted_is_explicit_abstention_with_exact_scope(self):
        empty = self.store.snapshot(self.evidence)
        self.assertFalse(empty["readOnly"])
        self.assertEqual(empty["decisions"], [])
        result = self.accept(label="Unknown")
        current = result["decisions"][0]
        self.assertEqual(current["label"], "unknown")
        self.assertEqual(current["status"], "accepted")
        self.assertEqual(current["scope"], {"datasetId": self.evidence["projectId"], "revision": self.evidence["revision"],
                         "sourceFingerprint": self.evidence["sourceFingerprint"], "clusterId": "T alpha",
                         "dimension": "type", "cellIds": ["001", "NA"]})
        package = self.store.export(self.evidence)
        self.assertEqual(package["schema"], module.SCHEMA)
        envelope = package["events"][0]
        self.assertIsInstance(envelope["payload"], str)
        self.assertEqual(envelope["hash"], hashlib.sha256((envelope["prevHash"] + "\n" + envelope["payload"]).encode()).hexdigest())
        self.assertNotIn("cells", package)
        self.assertNotIn("models", package)
        self.assertEqual(ProjectStore(self.store.path).snapshot(self.evidence), result)

    def test_dimension_and_workflow_independent_and_undo_restores_current(self):
        first = self.accept()
        first_id = first["events"][0]["id"]
        second = self.accept(request="decision-2", label="unknown", status="proposed")
        second_id = second["events"][-1]["id"]
        qc = self.accept(request="qc-1", dimension="QC", label="review required", status="reviewed")
        self.assertEqual(len(qc["decisions"]), 2)
        self.assertEqual(qc["events"][1]["supersedes"], first_id)
        self.assertUnchangedRejected(lambda: self.store.undo({"targetEventId": first_id, "reason": "Too old", "requestId": "undo-old", "revision": self.evidence["revision"]}, self.evidence))
        restored = self.store.undo({"targetEventId": second_id, "reason": "Correction withdrawn", "requestId": "undo-1", "revision": self.evidence["revision"]}, self.evidence)
        current = next(row for row in restored["decisions"] if row["scope"]["dimension"] == "type")
        self.assertEqual(current["id"], first_id)
        self.assertTrue(restored["events"][1]["undone"])
        self.assertEqual(len(restored["events"]), 4)
        self.assertUnchangedRejected(lambda: self.store.undo({"targetEventId": second_id, "reason": "Repeat", "requestId": "undo-2", "revision": self.evidence["revision"]}, self.evidence))
        validate_package(self.store.export(self.evidence), self.evidence)

    def test_duplicate_click_and_concurrent_instances_are_idempotent(self):
        payload = decision(self.evidence)
        stores = [ProjectStore(self.store.path) for _ in range(8)]
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda store: store.decide(payload, self.evidence), stores))
        self.assertTrue(all(len(result["events"]) == 1 for result in results))
        self.assertEqual(len(self.store.export(self.evidence)["events"]), 1)
        self.assertUnchangedRejected(lambda: self.accept(label="NK cell"))

    def test_interprocess_unique_and_duplicate_requests_preserve_chain(self):
        context = multiprocessing.get_context("fork")
        output = context.Queue()
        payloads = [decision(self.evidence, request="shared"), decision(self.evidence, request="shared"),
                    decision(self.evidence, request="distinct-1"), decision(self.evidence, request="distinct-2")]
        children = [context.Process(target=process_decide, args=(str(self.store.path), self.evidence, payload, output)) for payload in payloads]
        for child in children:
            child.start()
        for child in children:
            child.join(10)
            self.assertEqual(child.exitcode, 0)
        results = [output.get(timeout=2) for _ in children]
        self.assertTrue(all(success for success, _ in results), results)
        package = self.store.export(self.evidence)
        self.assertEqual(len(package["events"]), 3)
        validate_package(package, self.evidence)

    def test_invalid_missing_input_wrong_revision_scope_and_status_are_atomic(self):
        self.accept()
        cases = [{"clusterId": []}, {"clusterId": "foreign"}, {"dimension": "state/QC"},
                 {"dimension": []}, {"status": "truth"}, {"label": None}, {"label": " "},
                 {"reason": ""}, {"reason": "x" * 4001}, {"requestId": None},
                 {"revision": "0" * 64}, {"cellIds": ["foreign"]}, {"evidenceRefs": [None]}]
        for index, fields in enumerate(cases):
            payload = decision(self.evidence, request="invalid-%s" % index, **fields)
            with self.subTest(fields=fields):
                self.assertUnchangedRejected(lambda: self.store.decide(payload, self.evidence))
        for payload in (None, [], {}, {"revision": self.evidence["revision"]}):
            self.assertUnchangedRejected(lambda: self.store.decide(payload, self.evidence))
        self.assertFalse(self.store.snapshot(self.evidence)["readOnly"])

    def test_export_import_preserves_original_raw_utf8_float_payloads(self):
        raw = '{ "clusterId" : "T alpha", "revision" : "' + self.evidence["revision"] + '", "sourceFingerprint":"' + self.evidence["sourceFingerprint"] + '", "value":1.234567890123456e-17, "note":"中文" }'
        artifact_hash = hashlib.sha256(raw.encode()).hexdigest()
        key = "proposal:original-raw-bytes"
        self.evidence["directedArtifacts"] = {key: {"kind": "directed_proposal", "id": key,
            "sha256": artifact_hash, "payload": raw, "content": strict_json(raw)}}
        self.accept(evidenceRefs=[{"kind": "directed_proposal", "id": key, "sha256": artifact_hash}])
        original = self.store.export(self.evidence)
        self.assertEqual(original["artifacts"][key], {"payload": raw, "sha256": artifact_hash})
        # Noncanonical imported event bytes remain untouched; the envelope owns them.
        event = strict_json(original["events"][0]["payload"])
        event_raw = json.dumps(event, ensure_ascii=False, indent=1)
        original["events"][0].update(payload=event_raw, hash=envelope_hash(module.ZERO_HASH, event_raw))
        new_store = ProjectStore(self.root / "imported" / "ledger.json")
        new_store.import_package(original, self.evidence)
        exported = new_store.export(self.evidence)
        self.assertEqual(exported, original)
        self.assertEqual(exported["events"][0]["payload"], event_raw)
        self.assertEqual(exported["artifacts"][key]["payload"], raw)
        self.assertEqual(new_store.snapshot(self.evidence)["decisions"][0]["evidenceRefs"], [key])

    def test_immutable_prefix_artifacts_and_foreign_scope_references(self):
        raw = canonical({"scope": {"datasetId": self.evidence["projectId"], "revision": self.evidence["revision"],
                                  "sourceFingerprint": self.evidence["sourceFingerprint"], "clusterId": "T alpha",
                                  "dimension": "type", "cellIds": ["001", "NA"]}})
        key = "capsule"
        sha = hashlib.sha256(raw.encode()).hexdigest()
        self.evidence["directedArtifacts"] = {key: {"payload": raw, "sha256": sha}}
        self.accept(evidenceRefs=[key])
        original = self.store.export(self.evidence)
        changed = rewrite_events(original, lambda event, index: event.update(reason="Rewritten history"))
        self.assertUnchangedRejected(lambda: self.store.import_package(changed, self.evidence))
        truncated = copy.deepcopy(original)
        truncated["events"] = []
        self.assertUnchangedRejected(lambda: self.store.import_package(truncated, self.evidence))
        altered = copy.deepcopy(original)
        altered["artifacts"][key] = {"payload": raw + "\n", "sha256": hashlib.sha256((raw + "\n").encode()).hexdigest()}
        self.assertUnchangedRejected(lambda: self.store.import_package(altered, self.evidence))
        self.evidence["directedArtifacts"][key] = altered["artifacts"][key]
        self.assertUnchangedRejected(lambda: self.accept(request="artifact-replaced", evidenceRefs=[key]))
        self.evidence["directedArtifacts"][key] = {"payload": canonical({"provisional": {"scope": {"clusterId": "NA"}}}), "sha256": "unused"}
        bad_raw = self.evidence["directedArtifacts"][key]["payload"]
        self.evidence["directedArtifacts"]["foreign"] = {"payload": bad_raw, "sha256": hashlib.sha256(bad_raw.encode()).hexdigest()}
        self.assertUnchangedRejected(lambda: self.accept(request="foreign-artifact", evidenceRefs=["foreign"]))
        # Valid extension keeps prefix and raw immutable artifacts.
        other = ProjectStore(self.root / "extended.json")
        other.import_package(original, self.evidence)
        other.decide(decision(self.evidence, request="extension", label="unknown"), self.evidence)
        self.store.import_package(other.export(self.evidence), self.evidence)
        self.assertEqual(self.store.export(self.evidence)["events"][0], original["events"][0])

    def test_changed_source_or_bundle_marks_history_stale_without_reuse(self):
        accepted = self.accept()
        original = self.store.path.read_bytes()
        for field in ("revision", "sourceFingerprint", "projectId"):
            changed = copy.deepcopy(self.evidence)
            changed[field] = "0" * 64 if field != "projectId" else "Another study"
            view = self.store.snapshot(changed)
            self.assertTrue(view["readOnly"])
            self.assertTrue(view["stale"])
            self.assertTrue(view["events"][0]["stale"])
            self.assertEqual(view["decisions"][0]["id"], accepted["decisions"][0]["id"])
            self.assertUnchangedRejected(lambda: self.store.decide(decision(changed, request="stale"), changed))
            self.assertEqual(self.store.path.read_bytes(), original)
        self.assertTrue(self.store.snapshot(self.evidence, evidence_error="Source unavailable")["readOnly"])
        self.assertFalse(self.store.snapshot(self.evidence)["readOnly"])

    def test_hash_corruption_duplicate_json_and_invalid_scope_are_read_only(self):
        known = self.accept()
        original = self.store.path.read_bytes()
        package = self.store.export(self.evidence)
        invalids = [original.replace(b'"events":', b'"events":[],"events":', 1),
                    canonical(rewrite_events(package, lambda e, i: e["scope"].update(cellIds=["foreign"]))).encode(),
                    canonical(rewrite_events(package, lambda e, i: e["scope"].update(clusterId=[]))).encode(),
                    canonical(rewrite_events(package, lambda e, i: e.update(createdAt="2026-10-03"))).encode()]
        damaged = copy.deepcopy(package)
        damaged["events"][0]["hash"] = "0" * 64
        invalids.append(canonical(damaged).encode())
        for data in invalids:
            self.store.path.write_bytes(data)
            view = self.store.snapshot(self.evidence)
            self.assertTrue(view["readOnly"])
            self.assertTrue(view["integrityError"])
            self.assertEqual(view["decisions"][0]["id"], known["decisions"][0]["id"])
            with self.assertRaises(ProjectStoreError):
                self.store.export(self.evidence)
            self.assertEqual(self.store.path.read_bytes(), data)
        self.store.path.write_bytes(original)
        self.assertFalse(self.store.snapshot(self.evidence)["readOnly"])

    def test_malformed_recomputed_payload_and_envelope_refs_fail_closed(self):
        self.accept()
        package = self.store.export(self.evidence)
        mutations = [lambda e, i: e.update(id=[]), lambda e, i: e.update(requestId=[]),
                     lambda e, i: e["scope"].update(revision=[]), lambda e, i: e["scope"].update(clusterId=[]),
                     lambda e, i: e["scope"].update(cellIds=["NA", "001"]),
                     lambda e, i: e.update(evidenceRefs=[[]]), lambda e, i: e.update(supersedes=[]),
                     lambda e, i: e.update(status=[]), lambda e, i: e.update(label=None),
                     lambda e, i: e.update(kind="undo", targetEventId=[])]
        for mutation in mutations:
            with self.subTest(mutation=mutation), self.assertRaises(ProjectStoreError):
                validate_package(rewrite_events(package, mutation), self.evidence)
        for field, value in (("sequence", True), ("prevHash", []), ("hash", []), ("payload", None)):
            bad = copy.deepcopy(package)
            bad["events"][0][field] = value
            with self.subTest(field=field), self.assertRaises(ProjectStoreError):
                validate_package(bad, self.evidence)
        duplicated = copy.deepcopy(package)
        duplicated["events"].append(copy.deepcopy(duplicated["events"][0]))
        with self.assertRaises(ProjectStoreError):
            validate_package(duplicated, self.evidence)
        legacy = {"format": "scagentkit.handoff.v2", "datasetId": self.evidence["projectId"], "events": []}
        with self.assertRaises(ProjectStoreError):
            self.store.import_package(legacy, self.evidence)

    def test_size_guard_rejects_before_replace_preserves_history_and_readonly_false(self):
        known = self.accept()
        original = self.store.path.read_bytes()
        with patch.object(module, "MAX_SESSION_BYTES", len(original) + 50):
            with self.assertRaisesRegex(ProjectStoreError, "existing bytes are unchanged"):
                self.accept(request="larger", reason="Longer reason " * 10)
            self.assertEqual(self.store.path.read_bytes(), original)
            view = self.store.snapshot(self.evidence)
            self.assertFalse(view["readOnly"])
            self.assertEqual(view["events"], known["events"])
            self.assertEqual(self.store.export(self.evidence)["events"], strict_json(original.decode())["events"])
            self.assertEqual(list(self.store.path.parent.glob(".ledger.json.*")), [])

    def test_signed_duplicate_ids_and_duplicate_raw_json_keys_are_rejected(self):
        self.accept()
        self.accept(request="second", label="unknown")
        package = self.store.export(self.evidence)
        first = strict_json(package["events"][0]["payload"])
        for field in ("id", "requestId"):
            changed = rewrite_events(package, lambda e, i: e.update({field: first[field]}) if i == 1 else None)
            self.assertUnchangedRejected(lambda: self.store.import_package(changed, self.evidence))
        changed = copy.deepcopy(package)
        raw = changed["events"][0]["payload"].replace('"label":', '"label":"rewritten","label":', 1)
        changed["events"][0].update(payload=raw, hash=envelope_hash(module.ZERO_HASH, raw))
        with self.assertRaisesRegex(ProjectStoreError, "Duplicate"):
            validate_package(changed, self.evidence)
        self.assertFalse(self.store.snapshot(self.evidence)["readOnly"])

    def test_initial_damaged_or_missing_input_is_explicit_readonly(self):
        self.store.path.parent.mkdir()
        damaged = '{"schema":"scagentkit.review-journal.v1","events":[]}'
        self.store.path.write_text(damaged)
        fresh = ProjectStore(self.store.path)
        view = fresh.snapshot(self.evidence)
        self.assertTrue(view["readOnly"])
        self.assertTrue(view["integrityError"])
        self.assertEqual(view["events"], [])
        self.assertEqual(self.store.path.read_text(), damaged)
        self.assertTrue(ProjectStore(self.root / "empty.json").snapshot(None, "Unavailable project")["readOnly"])

    def test_changed_rule_capsule_only_marks_referenced_decision_stale(self):
        raw = canonical({"clusterId": "T alpha", "revision": self.evidence["revision"],
                         "sourceFingerprint": self.evidence["sourceFingerprint"], "rulesHash": "old rules"})
        key = hashlib.sha256(raw.encode()).hexdigest()
        self.evidence["directedArtifacts"] = {key: {"payload": raw, "sha256": key}}
        self.accept(label="unknown", evidenceRefs=[key])
        self.accept(request="ordinary-qc", dimension="QC", label="manual review", evidenceRefs=[])
        original_package = self.store.export(self.evidence)
        original_bytes = self.store.path.read_bytes()
        fresh = self.store.snapshot(self.evidence)
        self.assertTrue(all(not event["stale"] for event in fresh["events"]))
        new_raw = canonical({"clusterId": "T alpha", "revision": self.evidence["revision"],
                             "sourceFingerprint": self.evidence["sourceFingerprint"], "rulesHash": "new rules"})
        new_key = hashlib.sha256(new_raw.encode()).hexdigest()
        for registry in ({}, {new_key: {"payload": new_raw, "sha256": new_key}}):
            changed = copy.deepcopy(self.evidence)
            changed["directedArtifacts"] = registry
            view = ProjectStore(self.store.path).snapshot(changed)
            self.assertEqual(view["revision"], self.evidence["revision"])
            self.assertFalse(view["readOnly"])
            self.assertFalse(view["stale"])
            referenced = next(item for item in view["decisions"] if item["scope"]["dimension"] == "type")
            ordinary = next(item for item in view["decisions"] if item["scope"]["dimension"] == "QC")
            self.assertTrue(referenced["stale"])
            self.assertEqual((referenced["label"], referenced["status"]), ("unknown", "accepted"))
            self.assertFalse(ordinary["stale"])
            self.assertTrue(view["events"][0]["stale"])
            self.assertFalse(view["events"][1]["stale"])
            imported = ProjectStore(self.root / ("imported-%s.json" % len(registry)))
            import_view = imported.import_package(original_package, changed)
            self.assertTrue(import_view["events"][0]["stale"])
            self.assertEqual(imported.export(changed), original_package)
            self.assertEqual(self.store.export(changed), original_package)
            self.assertEqual(self.store.path.read_bytes(), original_bytes)
        aliased = copy.deepcopy(self.evidence)
        aliased["artifactRegistry"] = aliased.pop("directedArtifacts")
        self.assertFalse(self.store.snapshot(aliased)["events"][0]["stale"])


if __name__ == "__main__":
    unittest.main()
