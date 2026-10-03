"""Generic replay uses declared portable assets and actual source identities."""
import copy
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from directed import DirectedError
from project_runtime import ProjectRuntime
import project_runtime
from store import StoreError
from test_directed import evidence_fixture, expression_fixture


def inputs(cluster_id="T alpha"):
    evidence = evidence_fixture()
    evidence["sources"] = []
    evidence["clusters"][0]["id"] = cluster_id
    evidence["clusters"][0]["models"] = []
    identity = {"algorithm": "scagentkit.source.v1", "fingerprint": "a" * 64,
                "assay": "RNA", "countsLayer": "counts", "normalizedLayer": "data"}
    evidence.update(identity=identity, sourceFingerprint=identity["fingerprint"])
    expression = expression_fixture(evidence, t_only=80)
    expression["schema_version"] = "scAgentKit.directed_expression.v2"
    expression["scope"]["cluster_id"] = cluster_id
    expression["source"] = {"object_fingerprint": identity["fingerprint"], "assay": "RNA",
                             "layers": {"counts": "counts", "data": "data"}}
    return evidence, expression


class Loader:
    def __init__(self, bundle):
        self.bundle = bundle

    def directed_asset(self, cluster_id):
        return copy.deepcopy(self.bundle)


class ProjectRuntimeTests(unittest.TestCase):
    def test_non_numeric_scope_supported_without_rds_or_models(self):
        evidence, expression = inputs("T α / 001")
        runtime = ProjectRuntime(Loader(expression))
        original = copy.deepcopy(evidence)
        view = runtime.describe(evidence, "T α / 001")
        self.assertEqual(view["proposal"]["recommendedLabel"], "T cell")
        self.assertEqual(view["proposal"]["scope"]["sourceFingerprint"], "a" * 64)
        self.assertEqual(view["artifact"]["sha256"], hashlib.sha256(view["artifact"]["payload"].encode()).hexdigest())
        self.assertNotIn("rds_sha256", view["expression"]["source"])
        self.assertEqual(view["modelReview"]["calls"], 0)
        self.assertEqual(evidence, original)

    def test_unassigned_b_cell_panel_unavailable_not_implicitly_executed(self):
        evidence, _ = inputs("B alpha")
        runtime = ProjectRuntime(Loader(None))
        view = runtime.describe(evidence, "B alpha")
        self.assertFalse(view["execution"]["available"])
        self.assertEqual(view["execution"]["status"], "unavailable")
        self.assertIsNone(view["artifact"])
        self.assertEqual(view["proposal"]["nextSteps"], [])
        self.assertTrue(all(step["availability"] == "unavailable" for step in view["plan"]["steps"]))
        with self.assertRaises(StoreError):
            runtime.execute(evidence, {"clusterId": "B alpha", "revision": evidence["revision"],
                                     "planHash": view["planHash"], "requestId": "run"})

    def test_same_barcode_wrong_object_identity_or_layer_rejected(self):
        evidence, expression = inputs()
        for change in ({"object_fingerprint": "b" * 64}, {"layers": {"counts": "scale.data", "data": "data"}}):
            damaged = copy.deepcopy(expression)
            damaged["source"].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                ProjectRuntime(Loader(damaged)).describe(evidence, "T alpha")

    def test_explicit_genuine_layer_names_supported(self):
        evidence, expression = inputs()
        evidence["identity"].update(countsLayer="counts.selected", normalizedLayer="data.selected")
        expression["source"]["layers"] = {"counts": "counts.selected", "data": "data.selected"}
        view = ProjectRuntime(Loader(expression)).describe(evidence, "T alpha")
        self.assertEqual(view["proposal"]["recommendedLabel"], "T cell")
        self.assertEqual(view["plan"]["steps"][0]["parameters"]["layers"], ["counts.selected", "data.selected"])

    def test_counts_only_project_remains_reviewable_with_directed_unavailable(self):
        evidence, expression = inputs()
        evidence["identity"]["normalizedLayer"] = None
        expression["source"]["layers"]["data"] = None
        for cell in expression["cells"]:
            cell["normalized"] = {gene: None for gene in cell["normalized"]}
        runtime = ProjectRuntime(Loader(expression))
        view = runtime.describe(evidence, "T alpha")
        self.assertFalse(view["execution"]["available"])
        self.assertIn("no normalized", view["execution"]["error"])
        self.assertIsNone(view["artifact"])
        self.assertEqual(runtime.augment(evidence)["directedArtifacts"], {})

    def test_replay_requires_current_exact_revision_and_plan(self):
        evidence, expression = inputs()
        runtime = ProjectRuntime(Loader(expression))
        view = runtime.describe(evidence, "T alpha")
        payload = {"clusterId": "T alpha", "revision": evidence["revision"], "planHash": view["planHash"], "requestId": "replay"}
        self.assertTrue(runtime.execute(evidence, payload)["execution"]["cacheHit"])
        for field in ("revision", "planHash"):
            with self.subTest(field=field), self.assertRaises(StoreError):
                runtime.execute(evidence, dict(payload, **{field: "b" * 64}))

    def test_human_accepted_context_does_not_change_scientific_capsule(self):
        evidence, expression = inputs()
        runtime = ProjectRuntime(Loader(expression))
        first = runtime.describe(evidence, "T alpha")
        session = {"decisions": [{"id": "human", "label": "B cell", "status": "accepted",
                    "scope": {"clusterId": "T alpha", "dimension": "type"}, "stale": False}]}
        second = runtime.describe(evidence, "T alpha", session)
        self.assertEqual(first["artifact"], second["artifact"])
        self.assertEqual(second["proposal"]["humanDecision"]["label"], "B cell")
        self.assertFalse(second["proposal"]["evidenceSummary"]["identityEstablished"])

    def test_rules_drift_requires_restart(self):
        evidence, expression = inputs()
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp)
            for name in ("directed.py", "taxonomy.v1.json"):
                (target / name).write_bytes((project_runtime.ROOT / name).read_bytes())
            with patch.object(project_runtime, "ROOT", target):
                runtime = ProjectRuntime(Loader(expression))
                runtime.describe(evidence, "T alpha")
                with (target / "directed.py").open("a") as changed:
                    changed.write("\n# changed rules\n")
                with self.assertRaisesRegex(StoreError, "restart"):
                    runtime.describe(evidence, "T alpha")


if __name__ == "__main__":
    unittest.main()
