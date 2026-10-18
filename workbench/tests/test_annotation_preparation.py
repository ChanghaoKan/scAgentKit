"""Typed first-proposal boundary, without a provider or Python scientific authority."""
import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_review_runtime import RunReviewRuntime
from store import StoreError


class AnnotationPreparationTests(unittest.TestCase):
    def test_exact_allowlist_and_binding_types(self):
        valid = {"action": "prepare", "project_id": "parent", "input_hash": "a" * 64,
                 "expected_revision": 3, "evidence_hash": "b" * 64, "reviewer": "analyst",
                 "reason": "Reviewed saved markers", "request_id": "worksheet-1",
                 "proposal": {"schema": "scagentkit.annotation.v1", "annotations": []}}
        RunReviewRuntime.validate(valid)
        for key, value in (("expected_revision", True), ("expected_revision", -1),
                           ("evidence_hash", ""), ("evidence_hash", "A" * 64),
                           ("input_hash", "a"), ("project_id", ""), ("request_id", ""),
                           ("reviewer", " "), ("reason", ""), ("proposal", "source('x')"),
                           ("proposal", {"schema": "scagentkit.strategy.v1"}),
                           ("path", "/not/accepted"), ("kind", "annotation")):
            with self.subTest(field=key, value=value):
                payload = copy.deepcopy(valid); payload[key] = value
                with self.assertRaises(StoreError): RunReviewRuntime.validate(payload)
        for field in valid:
            payload = copy.deepcopy(valid); del payload[field]
            with self.assertRaises(StoreError): RunReviewRuntime.validate(payload)


if __name__ == "__main__": unittest.main()
