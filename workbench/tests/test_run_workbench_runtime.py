"""Fixed read-only IPC, authority races, and bound existing bundle evidence."""
import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evidence import canonical
from run_workbench_runtime import RunWorkbenchRuntime
from store import StoreError
from test_project import project_fixture, write_bundle


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class RunWorkbenchRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "registered"
        self.root.mkdir()
        self.root = self.root.resolve()
        (self.root / "state.rds").write_bytes(b"Fixed fixture envelope; never read as R by Python")
        self.runtime = RunWorkbenchRuntime(self.root, library=self.temp.name)
        event = {"sequence": 1, "created_at": "2026-10-05T10:00:00Z", "action": "processed_stage_reused",
                 "details": {"reason": "Explicit processed public fixture", "skipped": ["qc_evidence", "analysis"]},
                 "previous_hash": "0" * 64, "hash": "f" * 64}
        self.run = {"schema": "scagentkit.run.v1", "project_id": "run-literal",
                    "input_hash": "a" * 64, "config_hash": "b" * 64, "implementation_hash": "c" * 64,
                    "revision": 1, "history_head": "f" * 64, "status": "complete", "stage": "complete",
                    "completed": ["qc_evidence", "qc_propose", "qc_apply", "analysis", "annotation_apply"],
                    "context": {"species": "Homo sapiens"}, "output": None, "annotation_review": None}
        self.saved = {"schema": "scagentkit.workbench.saved.v1", "state_sha256": sha(self.root / "state.rds"),
                      "source": {"start_stage": "processed", "processed_reason": "Explicit processed public fixture",
                                 "source": {"type": "Seurat", "path": None, "rds_sha256": None}},
                      "provider": {"name": "manual", "model": None, "external": False},
                      "history": {"schema": "scagentkit.run-history.v1", "events": [event], "head": "f" * 64,
                                  "authority": "state.rds", "total_events": 1, "provided_events": 1, "truncated": False},
                      "qc_summary": None, "analysis": {"parameters": {}}, "artifacts": [], "bundle_records": []}

    def tearDown(self):
        self.temp.cleanup()

    def process(self, argv, **kwargs):
        result = copy.deepcopy(self.run)
        result["workbench_projection"] = copy.deepcopy(self.saved)
        Path(argv[-1]).write_text(canonical({"ok": True, "result": result, "error": None}))
        return subprocess.CompletedProcess(argv, 0, b"private stdout", b"private stderr")

    def describe(self, process=None):
        with patch("qc_runtime.subprocess.run", side_effect=process or self.process):
            return self.runtime.describe()

    def bundle(self, embedded=True):
        value = project_fixture(project_id="directory-name-different-from-run", embedded=embedded)
        value["parameters"]["analysisExecution"] = {"inputHash": self.run["input_hash"],
            "configHash": self.run["config_hash"], "implementationHash": self.run["implementation_hash"],
            "startStage": "processed", "foundationExecuted": False}
        write_bundle(self.root / "bundle", value)
        self.run["output"] = {"bundle": str(self.root / "bundle"), "scientific_result": "EXECUTED"}
        self.run["annotation_review"] = {"cell_scope_hash": "d" * 64, "details": {"cell_count": 4}}
        self.saved["bundle_records"] = [{"path": "bundle/" + file.name, "sha256": sha(file)}
                                        for file in sorted((self.root / "bundle").iterdir())]
        self.saved["bundle_scope_hash"] = "e" * 64
        return value

    def test_fixed_inspect_ipc_strips_key_environment_and_never_accepts_mutation(self):
        calls = []
        def process(argv, **kwargs):
            calls.append(argv)
            self.assertEqual(argv[1:4], ["--vanilla", str(self.runtime.bridge), "inspect"])
            self.assertEqual(argv[4], str(self.root))
            self.assertFalse(kwargs["shell"])
            self.assertEqual(json.loads(Path(argv[-2]).read_text()), {})
            for key in ("DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "HF_TOKEN"):
                self.assertNotIn(key, kwargs["env"])
            self.assertEqual(kwargs["env"]["R_LIBS_USER"], self.runtime.library)
            return self.process(argv, **kwargs)
        with patch.dict(os.environ, {key: "synthetic-secret" for key in
                                     ("DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "HF_TOKEN")}):
            answer = self.describe(process)
        self.assertEqual(len(calls), 1)
        self.assertTrue(answer["readonly"])
        self.assertNotIn("csrf_token", answer)
        self.assertNotIn("synthetic-secret", canonical(answer))
        with self.assertRaises(StoreError): self.runtime.decide({"action": "approve"}, "anything")

    def test_processed_nodes_are_reuse_even_when_completed_lists_qc_and_analysis(self):
        answer = self.describe()
        self.assertEqual(answer["qc"]["status"], "processed_reused")
        self.assertEqual(answer["qc"]["reason"], self.saved["source"]["processed_reason"])
        self.assertIsNone(answer["qc"]["summary"])
        self.assertFalse(answer["analysis"]["foundation_executed"])
        self.assertEqual(answer["analysis"]["status"], "processed_reused")
        self.assertEqual(answer["history"]["events"], self.saved["history"]["events"])

    def test_real_bundle_loader_reuses_exact_literal_ids_and_embedding(self):
        self.bundle()
        before = {file.name: sha(file) for file in (self.root / "bundle").iterdir()}
        answer = self.describe()
        self.assertEqual(answer["project"]["project_id"], "run-literal")
        self.assertNotEqual(answer["evidence"]["projectId"], "run-literal")
        self.assertEqual(answer["binding"]["evidence_project_id"], answer["evidence"]["projectId"])
        self.assertEqual(answer["binding"]["bundle_digest"], answer["evidence"]["bundleDigest"])
        self.assertEqual(answer["binding"]["source_fingerprint"], answer["evidence"]["sourceFingerprint"])
        self.assertEqual(answer["binding"]["bundle_cell_scope_hash"], "e" * 64)
        self.assertEqual([point["cellId"] for point in answer["evidence"]["umap"]], ["NA", "001", "1", "cell 中文"])
        self.assertEqual(answer["evidence"]["dataset"]["retainedCells"], 4)
        self.assertEqual(before, {file.name: sha(file) for file in (self.root / "bundle").iterdir()})

    def test_absent_embedding_stays_absent_no_analysis_fallback(self):
        self.bundle(embedded=False)
        answer = self.describe()
        self.assertEqual(answer["evidence"]["umap"], [])
        self.assertIsNone(answer["evidence"]["embeddingName"])

    def test_foreign_changed_or_unreceipted_bundle_is_rejected(self):
        self.bundle()
        original = copy.deepcopy(self.saved)
        for mutation in ("foreign_path", "missing_receipt", "scope", "changed", "traversal", "duplicate"):
            with self.subTest(mutation=mutation):
                self.saved = copy.deepcopy(original)
                self.run["output"]["bundle"] = str(self.root / "bundle")
                if mutation == "foreign_path": self.run["output"]["bundle"] = "/outside/bundle"
                elif mutation == "missing_receipt": self.saved["bundle_records"].pop()
                elif mutation == "scope": self.saved["bundle_scope_hash"] = None
                elif mutation == "changed": self.saved["bundle_records"][0]["sha256"] = "0" * 64
                elif mutation == "traversal": self.saved["bundle_records"][0]["path"] = "bundle/../outside.json"
                elif mutation == "duplicate": self.saved["bundle_records"].append(self.saved["bundle_records"][0])
                with self.assertRaises(StoreError): self.describe()

    def test_bundle_different_input_config_implementation_or_cell_count_is_rejected(self):
        self.bundle()
        for field in ("input_hash", "config_hash", "implementation_hash"):
            with self.subTest(field=field):
                previous = self.run[field]; self.run[field] = "0" * 64
                with self.assertRaises(StoreError): self.describe()
                self.run[field] = previous
        self.run["annotation_review"]["details"]["cell_count"] = 5
        with self.assertRaises(StoreError): self.describe()

    def test_corrupt_history_sequence_previous_head_or_revision_is_rejected(self):
        original = copy.deepcopy(self.saved)
        for mutation in ("sequence", "previous", "head", "revision", "missing_history"):
            with self.subTest(mutation=mutation):
                self.saved = copy.deepcopy(original); self.run["revision"] = 1
                if mutation == "sequence": self.saved["history"]["events"][0]["sequence"] = 2
                elif mutation == "previous": self.saved["history"]["events"][0]["previous_hash"] = "1" * 64
                elif mutation == "head": self.saved["history"]["head"] = "0" * 64
                elif mutation == "revision": self.run["revision"] = 2
                elif mutation == "missing_history": self.saved["history"] = None
                with self.assertRaises(StoreError): self.describe()

    def test_state_change_before_bridge_or_while_loading_bundle_is_rejected(self):
        self.saved["state_sha256"] = "0" * 64
        with self.assertRaises(StoreError): self.describe()
        self.saved["state_sha256"] = sha(self.root / "state.rds")
        def changed(argv, **kwargs):
            result = self.process(argv, **kwargs)
            (self.root / "state.rds").write_bytes(b"A different committed revision")
            return result
        with self.assertRaises(StoreError): self.describe(changed)

    def test_changed_bundle_during_loader_is_rejected_without_replaying_bridge(self):
        self.bundle()
        from project import ProjectLoader
        load = ProjectLoader.load
        def changed(loader):
            value = load(loader)
            (self.root / "bundle" / "project.json").write_bytes(b"Changed after validation")
            return value
        with patch("run_workbench_runtime.ProjectLoader.load", changed), \
             patch("qc_runtime.subprocess.run", side_effect=self.process) as process:
            with self.assertRaises(StoreError): self.runtime.describe()
        self.assertEqual(process.call_count, 1)

    def test_timeout_unknown_bridge_and_changed_directory_never_retry(self):
        with patch("qc_runtime.subprocess.run", side_effect=subprocess.TimeoutExpired("Rscript", 120)) as process:
            with self.assertRaises(StoreError): self.runtime.describe()
        self.assertEqual(process.call_count, 1)
        with patch("qc_runtime.subprocess.run", return_value=subprocess.CompletedProcess([], 0, b"", b"")) as process:
            with self.assertRaises(StoreError): self.runtime.describe()
        self.assertEqual(process.call_count, 1)
        self.runtime.project_identity = (-1, -1)
        with patch("qc_runtime.subprocess.run") as process:
            with self.assertRaises(StoreError): self.runtime.describe()
        process.assert_not_called()

    def integration(self):
        self.run["subcluster"] = {"schema": "scagentkit.subcluster-summary.v1", "parent_project_id": "parent"}
        directory = self.root / "reintegration"
        directory.mkdir()
        (directory / "state.rds").write_bytes(b"Independent saved integration fixture")
        self.saved["integration_state_sha256"] = sha(directory / "state.rds")
        self.saved["integration_history"] = {"schema": "scagentkit.subcluster.integration-history.v1",
            "revision": 1, "head": "d" * 64, "total_events": 1, "provided_events": 1, "truncated": False,
            "authority": "reintegration/state.rds", "events": [{"sequence": 1, "created_at": "2026-10-05T10:00:01Z",
            "action": "applied_to_derived_parent", "previous_hash": "0" * 64, "hash": "d" * 64,
            "details": {"child_project_id": self.run["project_id"], "child_input_hash": self.run["input_hash"],
                        "reviewer": "QA", "reason": "Create a separately approved derived version"}}]}

    def test_integration_is_a_separate_verified_revision_not_a_fabricated_run_event(self):
        self.integration()
        answer = self.describe()
        self.assertEqual(answer["project"]["revision"], 1)
        self.assertEqual(answer["history"]["head"], "f" * 64)
        self.assertEqual(len(answer["history"]["events"]), 1)
        self.assertEqual(answer["integration_history"]["events"][0]["action"], "applied_to_derived_parent")
        self.assertEqual(answer["binding"]["integration_revision"], 1)
        self.assertEqual(answer["binding"]["integration_history_head"], "d" * 64)
        self.assertEqual(answer["binding"]["integration_state_sha256"], sha(self.root / "reintegration/state.rds"))

    def test_foreign_or_missing_integration_history_and_corrupt_link_are_rejected(self):
        self.integration()
        original = copy.deepcopy(self.saved)
        for mutation in ("missing", "foreign", "input", "sequence", "source_sha"):
            with self.subTest(mutation=mutation):
                self.saved = copy.deepcopy(original)
                if mutation == "missing": self.saved["integration_history"] = None
                elif mutation == "foreign": self.saved["integration_history"]["events"][0]["details"]["child_project_id"] = "other-child"
                elif mutation == "input": self.saved["integration_history"]["events"][0]["details"]["child_input_hash"] = "0" * 64
                elif mutation == "sequence": self.saved["integration_history"]["events"][0]["sequence"] = 2
                elif mutation == "source_sha": self.saved["integration_state_sha256"] = "0" * 64
                with self.assertRaises(StoreError): self.describe()

    def test_integration_changes_or_symlink_during_read_are_rejected_without_replay(self):
        self.integration()
        def changed(argv, **kwargs):
            result = self.process(argv, **kwargs)
            (self.root / "reintegration/state.rds").write_bytes(b"A committed undo appeared")
            return result
        with self.assertRaises(StoreError): self.describe(changed)
        (self.root / "reintegration/state.rds").unlink()
        (self.root / "reintegration/state.rds").symlink_to(self.root / "state.rds")
        with patch("qc_runtime.subprocess.run") as process:
            with self.assertRaises(StoreError): self.runtime.describe()
        process.assert_not_called()


if __name__ == "__main__":
    unittest.main()
