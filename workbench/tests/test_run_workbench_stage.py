"""Pending plots reuse only exact immutable analysis/marker checkpoints."""
import copy
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import test_run_workbench_runtime as baseline
from test_run_workbench_runtime import sha
from test_project import project_fixture, write_bundle
from evidence import digest
from project import ProjectLoader
from store import StoreError


class SavedStageTests(unittest.TestCase):
    setUp = baseline.RunWorkbenchRuntimeTests.setUp
    tearDown = baseline.RunWorkbenchRuntimeTests.tearDown
    process = baseline.RunWorkbenchRuntimeTests.process
    describe = baseline.RunWorkbenchRuntimeTests.describe

    def stage(self, embedded=True):
        self.run.update(status="awaiting_configuration", stage="annotation_propose")
        records = {}
        directory = self.root / "checkpoints"
        directory.mkdir()
        for name in ("analysis", "markers", "annotation_evidence"):
            path = directory / (name + "-" + "e" * 64 + ".rds")
            path.write_bytes(("Immutable mock checkpoint " + name).encode())
            records[name] = {"path": str(path.relative_to(self.root)), "sha256": sha(path)}
        snapshot = {"stateSHA": self.saved["state_sha256"], "inputHash": self.run["input_hash"],
            "configHash": self.run["config_hash"], "implementationHash": self.run["implementation_hash"],
            "revision": self.run["revision"], "historyHead": self.run["history_head"],
            "scopeHash": "d" * 64, "bundleScopeHash": "e" * 64, "records": records}
        self.document = project_fixture(project_id=self.run["project_id"], embedded=embedded)
        self.document.pop("sourceAnnotation")
        for cell in self.document["cells"]:
            cell["qc"] = {}
        self.document["markers"] = [{"clusterId": "T alpha", "gene": "LITERAL", "avgLog2FC": 1.2,
            "pct1": .4, "pct2": .1, "pAdj": .01, "source": "Seurat::FindAllMarkers"}]
        self.document["parameters"] = {"savedStageSnapshot": snapshot, "analysisExecution": {
            key: snapshot[key] for key in ("inputHash", "configHash", "implementationHash")}}
        self.saved["stage_bundle"] = {"schema": "scagentkit.saved-stage-bundle.v1",
            "checkpoint_records": records, "scope_hash": "d" * 64, "bundle_scope_hash": "e" * 64,
            "cell_count": 4, "blobs": None}
        self.encode_document()

    def encode_document(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bundle"
            write_bundle(path, self.document)
            self.saved["stage_bundle"]["blobs"] = {file.name: file.read_text(encoding="utf-8")
                                                    for file in path.iterdir()}

    def test_pending_real_loader_full_scope_marker_and_cleanup_without_project_writes(self):
        self.stage()
        before = {str(p.relative_to(self.root)): sha(p) for p in self.root.rglob("*") if p.is_file()}
        directories = []
        load = ProjectLoader.load
        def inspect(loader):
            directories.append(loader.root)
            return load(loader)
        with patch("run_workbench_runtime.ProjectLoader.load", inspect):
            answer = self.describe()
        self.assertEqual(answer["evidence_kind"], "saved_analysis_checkpoint")
        self.assertTrue(answer["evidence_complete"])
        self.assertNotEqual(answer["run"]["status"], "complete")
        self.assertIsNone(answer["run"]["output"])
        self.assertEqual(answer["evidence"]["dataset"]["retainedCells"], 4)
        self.assertEqual([x["cellId"] for x in answer["evidence"]["umap"]], ["NA", "001", "1", "cell 中文"])
        self.assertEqual(sum(len(x["markers"]) for x in answer["evidence"]["clusters"]), 1)
        self.assertEqual(answer["binding"]["stage_records_hash"], digest(self.saved["stage_bundle"]["checkpoint_records"]))
        self.assertEqual(answer["binding"]["stage_scope_hash"], "d" * 64)
        self.assertIsNone(answer["evidence"]["sourceAnnotation"])
        self.assertTrue(all(not path.exists() for path in directories))
        self.assertEqual(before, {str(p.relative_to(self.root)): sha(p) for p in self.root.rglob("*") if p.is_file()})
        self.assertFalse((self.root / "bundle").exists())

    def test_unavailable_and_no_embedding_are_explicit_without_computation(self):
        answer = self.describe()
        self.assertEqual(answer["evidence_kind"], "unavailable")
        for field in ("stage_checkpoint_records", "stage_records_hash", "stage_scope_hash"):
            self.assertIsNone(answer["binding"][field])
        self.stage(embedded=False)
        answer = self.describe()
        self.assertEqual(answer["evidence_kind"], "saved_analysis_checkpoint")
        self.assertEqual(answer["evidence"]["umap"], [])
        self.assertIsNone(answer["evidence"]["embeddingName"])

    def test_foreign_stale_missing_and_symlink_checkpoint_fail_closed(self):
        self.stage()
        original = copy.deepcopy(self.saved)
        for mutation in ("foreign", "traversal", "sha", "missing", "extra", "scope"):
            with self.subTest(mutation=mutation):
                self.saved = copy.deepcopy(original)
                stage = self.saved["stage_bundle"]
                if mutation == "foreign": stage["checkpoint_records"]["analysis"]["path"] = "checkpoints/markers-" + "e" * 64 + ".rds"
                elif mutation == "traversal": stage["checkpoint_records"]["analysis"]["path"] = "checkpoints/../state.rds"
                elif mutation == "sha": stage["checkpoint_records"]["analysis"]["sha256"] = "0" * 64
                elif mutation == "missing": stage["checkpoint_records"].pop("markers")
                elif mutation == "extra": stage["checkpoint_records"]["raw"] = stage["checkpoint_records"]["analysis"]
                elif mutation == "scope": stage["scope_hash"] = None
                with self.assertRaises(StoreError): self.describe()
        self.saved = original
        path = self.root / original["stage_bundle"]["checkpoint_records"]["analysis"]["path"]
        path.unlink()
        with self.assertRaises(StoreError): self.describe()
        path.symlink_to(self.root / "state.rds")
        with self.assertRaises(StoreError): self.describe()

    def test_export_owner_revision_input_config_impl_or_scope_mismatch_rejected(self):
        self.stage()
        original = copy.deepcopy(self.document)
        for key in ("stateSHA", "inputHash", "configHash", "implementationHash", "revision", "historyHead", "scopeHash", "bundleScopeHash", "records"):
            with self.subTest(field=key):
                self.document = copy.deepcopy(original)
                self.document["parameters"]["savedStageSnapshot"][key] = 2 if key == "revision" else {} if key == "records" else "0" * 64
                self.encode_document()
                with self.assertRaises(StoreError): self.describe()
        self.document = copy.deepcopy(original)
        self.document["projectId"] = "foreign-run"
        self.encode_document()
        with self.assertRaises(StoreError): self.describe()

    def test_private_metadata_candidates_models_or_source_annotation_rejected(self):
        self.stage()
        original = copy.deepcopy(self.document)
        for mutation in ("metadata", "source", "candidates", "models", "directed"):
            with self.subTest(mutation=mutation):
                self.document = copy.deepcopy(original)
                if mutation == "metadata": self.document["cells"][0]["qc"] = {"private": "sentinel"}
                elif mutation == "source": self.document["sourceAnnotation"] = {"private": "sentinel"}
                elif mutation == "directed": self.document["directed"]["clusters"] = {"extra": "sentinel"}
                else: self.document[mutation] = [{"private": "sentinel"}]
                self.encode_document()
                with self.assertRaises(StoreError): self.describe()

    def test_stage_snapshot_never_overrides_final_or_unready_stage(self):
        self.stage()
        for stage, status in (("complete", "complete"), ("analysis", "ready"), ("strategy_apply", "ready")):
            self.run.update(stage=stage, status=status)
            with self.assertRaises(StoreError): self.describe()
        self.run.update(stage="annotation_propose", status="awaiting_review")
        self.run["annotation_review"] = {"cell_scope_hash": "0" * 64, "details": {"cell_count": 4}}
        with self.assertRaises(StoreError): self.describe()
        self.run["annotation_review"] = None
        baseline.RunWorkbenchRuntimeTests.bundle(self)
        with self.assertRaises(StoreError): self.describe()

    def test_tampered_manifest_extra_blob_and_over_bound_rejected(self):
        self.stage()
        original = copy.deepcopy(self.saved)
        for mutation in ("manifest", "extra", "large", "count"):
            self.saved = copy.deepcopy(original)
            stage = self.saved["stage_bundle"]
            if mutation == "manifest": stage["blobs"]["project.json"] += " "
            elif mutation == "extra": stage["blobs"]["raw.json"] = "{}"
            elif mutation == "large": stage["blobs"]["project.json"] = " " * (16 * 1024 * 1024)
            else: stage["cell_count"] = 5
            with self.assertRaises(StoreError): self.describe()

    def test_checkpoint_changes_during_parse_refused_without_replay(self):
        self.stage()
        load = ProjectLoader.load
        def changed(loader):
            evidence = load(loader)
            path = self.root / self.saved["stage_bundle"]["checkpoint_records"]["markers"]["path"]
            path.write_bytes(b"Concurrent changed checkpoint")
            return evidence
        with patch("run_workbench_runtime.ProjectLoader.load", changed), patch("qc_runtime.subprocess.run", side_effect=self.process) as process:
            with self.assertRaises(StoreError): self.runtime.describe()
        self.assertEqual(process.call_count, 1)


if __name__ == "__main__":
    unittest.main()
