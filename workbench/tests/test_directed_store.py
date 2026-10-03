"""Evidence-capsule migration, exact scopes and immutable local handoffs."""
import copy
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evidence import digest
from store import DIRECTED_FORMAT, FORMAT, SessionStore, StoreError, validate_package, portable_content
from test_backend import synthetic_evidence


class DirectedStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.evidence = synthetic_evidence()
        content = {"schemaVersion": 1, "clusterId": "6", "revision": self.evidence["revision"],
                   "sourceHash": "a" * 64, "extractorHash": "b" * 64,
                   "taxonomyHash": "c" * 64, "bundleHash": "d" * 64, "planHash": "e" * 64,
                   "provisional": {"status": "coarse_only", "recommendedLabel": "unknown",
                                   "resolution": "unresolved_identity", "uncalibrated": True}}
        identity = digest(content)
        self.artifact = {"kind": "directed_proposal", "id": identity, "sha256": identity, "content": content}
        self.reference = {key: self.artifact[key] for key in ("kind", "id", "sha256")}
        self.evidence["directedArtifacts"] = {identity: self.artifact}
        self.path = Path(self.temp.name) / "history.json"
        self.store = SessionStore(self.path)

    def tearDown(self):
        self.temp.cleanup()

    def payload(self, **updates):
        return {"clusterId": "6", "dimension": "type", "label": "unknown",
                "status": "proposed", "reason": "Current matrix cannot resolve exclusive identity.",
                "revision": self.evidence["revision"], "requestId": "directed", **updates}

    def test_v1_accepted_event_is_preserved_when_v2_reference_is_added(self):
        first = self.store.decision(self.payload(status="accepted", requestId="legacy"), self.evidence)
        legacy = self.store.export(self.evidence)
        self.assertEqual(legacy["format"], FORMAT)
        self.store.decision(self.payload(evidenceRefs=[self.reference]), self.evidence)
        package = self.store.export(self.evidence)
        self.assertEqual(package["format"], DIRECTED_FORMAT)
        self.assertEqual(package["events"][:1], legacy["events"])
        self.assertEqual(package["artifacts"][self.reference["id"]], self.artifact)
        self.assertEqual(package["events"][1]["scope"], first["events"][0]["scope"])
        validate_package(package, self.evidence)

    def test_execution_registry_never_writes_or_overwrites_accepted_history(self):
        self.store.decision(self.payload(requestId="human", label="Human scoped label", status="accepted"), self.evidence)
        before = self.path.read_bytes()
        original = self.store.session(self.evidence)
        newer = copy.deepcopy(self.evidence)
        newer["directedArtifacts"] = {}
        self.assertEqual(self.store.session(newer), original)
        self.assertEqual(self.path.read_bytes(), before)

    def test_changed_supplemental_source_stales_only_referenced_decision(self):
        self.store.decision(self.payload(requestId="legacy"), self.evidence)
        self.store.decision(self.payload(evidenceRefs=[self.reference]), self.evidence)
        before = self.store.export(self.evidence)
        changed = copy.deepcopy(self.evidence)
        changed["directedArtifacts"] = {}
        view = self.store.session(changed)
        self.assertEqual([event["stale"] for event in view["events"]], [False, True])
        self.assertEqual(self.store.export(changed), before)
        self.assertFalse(self.store.session(self.evidence)["decisions"][0]["stale"])

    def test_stale_wrong_dimension_foreign_scope_duplicate_refs_never_write(self):
        bad = [dict(self.payload(), dimension="QC", evidenceRefs=[self.reference]),
               dict(self.payload(), clusterId="5", evidenceRefs=[self.reference]),
               dict(self.payload(), evidenceRefs=[self.reference, self.reference]),
               dict(self.payload(), evidenceRefs=[]),
               dict(self.payload(), evidenceRefs=[dict(self.reference, sha256="f" * 64)])]
        for payload in bad:
            with self.subTest(payload=payload), self.assertRaises(StoreError):
                self.store.decision(payload, self.evidence)
            self.assertFalse(self.path.exists())
        changed = dict(self.evidence, directedArtifacts={})
        with self.assertRaises(StoreError):
            self.store.decision(self.payload(evidenceRefs=[self.reference]), changed)

    def test_repeat_click_export_import_reload_and_undo_preserve_capsule(self):
        payload = self.payload(evidenceRefs=[self.reference])
        first = self.store.decision(payload, self.evidence)
        self.assertEqual(self.store.decision(payload, self.evidence), first)
        package = self.store.export(self.evidence)
        other = SessionStore(Path(self.temp.name) / "reloaded.json")
        self.assertEqual(other.import_package(package, self.evidence), first)
        self.assertEqual(other.export(self.evidence), package)
        result = other.undo({"targetEventId": first["events"][0]["id"], "reason": "Correction withdrawn.",
                             "revision": self.evidence["revision"], "requestId": "undo"}, self.evidence)
        restored = SessionStore(other.path).session(self.evidence)
        self.assertEqual(restored, result)
        final = other.export(self.evidence)
        self.assertEqual(final["events"][:1], package["events"])
        self.assertEqual(final["artifacts"], package["artifacts"])
        self.assertEqual(result["decisions"], [])

    def test_capsule_tamper_or_deletion_is_rejected_before_import_write(self):
        self.store.decision(self.payload(evidenceRefs=[self.reference]), self.evidence)
        package = self.store.export(self.evidence)
        before = self.path.read_bytes()
        for mutation in ("content", "deletion"):
            changed = copy.deepcopy(package)
            if mutation == "content":
                changed["artifacts"][self.reference["id"]]["content"]["provisional"]["recommendedLabel"] = "NK"
            else:
                changed["artifacts"] = {}
            with self.subTest(mutation=mutation), self.assertRaises(StoreError):
                self.store.import_package(changed, self.evidence)
            self.assertEqual(self.path.read_bytes(), before)

    def test_import_cannot_remove_previously_recorded_unreferenced_capsule(self):
        self.store.decision(self.payload(), self.evidence)
        package = self.store.export(self.evidence)
        package["format"] = DIRECTED_FORMAT
        package["artifacts"] = {self.reference["id"]: self.artifact}
        self.store.import_package(package, self.evidence)
        changed = copy.deepcopy(package)
        changed["artifacts"] = {}
        with self.assertRaises(StoreError):
            self.store.import_package(changed, self.evidence)

    def test_capsule_numbers_keep_browser_json_semantics_and_exact_identity(self):
        original = {"fraction": 1.0, "median": 1915.0, "negativeZero": -0.0,
                    "sensitivity": [0.1, 0.0, 1e-8]}
        normalized = portable_content(original)
        self.assertEqual(digest(normalized), digest({"fraction": 1, "median": 1915,
            "negativeZero": 0, "sensitivity": [0.1, 0, 1e-8]}))
        self.assertEqual(original["median"], 1915.0)
        with self.assertRaises(StoreError):
            portable_content({"unsafe": 2**53 + 1})

    def test_earlier_exact_float_capsule_keeps_its_id_and_history_readable(self):
        self.store.decision(self.payload(), self.evidence)
        package = self.store.export(self.evidence)
        content = copy.deepcopy(self.artifact["content"])
        content["provisional"]["medianUMIs"] = 1915.0
        identity = digest(content)
        artifact = {"kind": "directed_proposal", "id": identity, "sha256": identity, "content": content}
        package["format"] = DIRECTED_FORMAT
        package["artifacts"] = {identity: artifact}
        self.store.import_package(package, self.evidence)
        self.assertFalse(self.store.session(self.evidence)["readOnly"])
        self.assertEqual(self.store.export(self.evidence), package)


if __name__ == "__main__":
    unittest.main()
