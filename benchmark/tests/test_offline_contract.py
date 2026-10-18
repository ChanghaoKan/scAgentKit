"""Tiny explicit synthetic controls; no expression files, network, or providers."""
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "contracts" / "compare_offline.py"
spec = importlib.util.spec_from_file_location("offline_contract", MODULE)
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class OfflineContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.manifest = {"schema": "scagentkit.offline-comparison.v1", "dataset_role": "synthetic_control",
            "input_sha256": "a" * 64, "protocol_sha256": "b" * 64,
            "software_commit": "synthetic-fixture", "environment": {"python": "fixture-only"},
            "cells": self.write("cells.csv", [{"cell_id": i} for i in ("C1", "C2", "C3")]),
            "methods": []}
        self.add_method("manual", ["T", "unknown", "B"], ["reviewed", "unknown", "reviewed"])

    def write(self, name, rows):
        with (self.root / name).open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        return {"path": name, "sha256": hashlib.sha256((self.root / name).read_bytes()).hexdigest()}

    def add_method(self, name, labels, statuses, ids=("C1", "C2", "C3")):
        record = self.write(name + ".csv", [dict(cell_id=i, label=l, status=s) for i, l, s in zip(ids, labels, statuses)])
        self.manifest["methods"].append(dict(record, name=name))

    def run_contract(self):
        (self.root / "comparison.json").write_text(json.dumps(self.manifest), encoding="utf-8")
        return contract.compare(self.root)

    def test_no_truth_never_yields_accuracy(self):
        result = self.run_contract()
        self.assertFalse(result["scientific_accuracy_claim"])
        self.assertIsNone(result["methods"][0]["annotation_accuracy"])
        self.assertEqual(result["methods"][0]["reviewed_coverage"], 2 / 3)

    def test_unknown_counts_in_frozen_truth_denominator(self):
        truth = self.write("truth.csv", [dict(cell_id=i, label=l, status="reviewed")
            for i, l in zip(("C1", "C2", "C3"), ("T", "T", "B"))])
        self.manifest["truth"] = dict(truth, source="synthetic labels", granularity="fixture broad", mapping_sha256="c" * 64)
        result = self.run_contract()["methods"][0]
        self.assertEqual(result["annotation_accuracy"], 2 / 3)
        self.assertEqual(result["accuracy_denominator"], 3)
        self.assertEqual(result["accuracy_status"], "synthetic_only")

    def test_unknown_cannot_hide_a_top1_prediction(self):
        self.manifest["methods"] = []
        self.add_method("top1", ["T", "B", "B"], ["reviewed", "unknown", "reviewed"])
        with self.assertRaisesRegex(contract.ContractError, "unknown labels"):
            self.run_contract()

    def test_candidate_is_not_reviewed_prediction(self):
        self.manifest["methods"] = []
        self.add_method("top1", ["T", "unknown", "B"], ["candidate", "unknown", "reviewed"])
        with self.assertRaisesRegex(contract.ContractError, "Candidates are evidence"):
            self.run_contract()

    def test_exact_ids_no_positional_join(self):
        self.manifest["methods"] = []
        self.add_method("changed", ["T", "unknown", "B"], ["reviewed", "unknown", "reviewed"], ids=("C1", "C2", "OTHER"))
        with self.assertRaisesRegex(contract.ContractError, "complete frozen cell set"):
            self.run_contract()

    def test_truth_provenance_required(self):
        self.manifest["truth"] = dict(self.manifest["cells"])
        with self.assertRaisesRegex(contract.ContractError, "predeclared granularity"):
            self.run_contract()

    def test_artifact_cannot_escape_experiment(self):
        self.manifest["cells"]["path"] = "../outside.csv"
        with self.assertRaisesRegex(contract.ContractError, "inside the experiment"):
            self.run_contract()

    def test_duplicate_ids_rejected(self):
        self.manifest["methods"] = []
        self.add_method("duplicate", ["T", "unknown", "B"], ["reviewed", "unknown", "reviewed"], ids=("C1", "C1", "C3"))
        with self.assertRaisesRegex(contract.ContractError, "unique"):
            self.run_contract()

    def test_changed_artifact_rejected(self):
        with (self.root / "manual.csv").open("a") as stream:
            stream.write("C4,B,reviewed\n")
        with self.assertRaisesRegex(contract.ContractError, "checksum"):
            self.run_contract()

    def test_no_silent_omission_of_failed_cells(self):
        self.manifest["methods"] = []
        self.add_method("incomplete", ["T", "unknown"], ["reviewed", "unknown"], ids=("C1", "C2"))
        with self.assertRaisesRegex(contract.ContractError, "complete frozen cell set"):
            self.run_contract()

    def test_unlabeled_truth_is_not_in_denominator(self):
        truth = self.write("truth.csv", [dict(cell_id=i, label=l, status=s) for i,l,s in
            [("C1", "T", "reviewed"), ("C2", "", "unlabeled"), ("C3", "B", "ambiguous")]])
        self.manifest["truth"] = dict(truth, source="synthetic", granularity="fixture", mapping_sha256="d" * 64)
        result = self.run_contract()["methods"][0]
        self.assertEqual(result["accuracy_denominator"], 1)
        self.assertEqual(result["annotation_accuracy"], 1)


if __name__ == "__main__":
    unittest.main()
