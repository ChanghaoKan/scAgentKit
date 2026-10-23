"""Strict facts transport validation; R remains the metadata/state authority."""
import copy
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from format_test_support import mock_format_authority

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_review_runtime import RunReviewRuntime
from store import StoreError


def request(facts=None):
    return dict(action="facts", kind="strategy", project_id="literal-project",
                input_hash="a" * 64, proposal_hash="b" * 64, review_hash="c" * 64,
                expected_revision=2, reviewer="author", reason="Explicit source facts; no approval",
                facts=facts if facts is not None else dict(batch=dict(technical_batch=False, source="Author declaration")))


class FactsTransport(unittest.TestCase):
    def setUp(self):
        mock_format_authority(self)

    def test_valid_partial_nested_facts_and_literal_provenance(self):
        for facts in [dict(columns=dict(capture="physical_load", condition="condition")),
                      dict(doublet=dict(capture=dict(method="column", column="physical_load", source="Author loading manifest"))),
                      dict(doublet=dict(rate=dict(method="manual", value={"load1": .05, "load2": .07}, source="Author sourced assumption"))),
                      dict(batch=dict(technical_batch=False, source="$(literal text); never executable"))]:
            with self.subTest(facts=facts):
                before = copy.deepcopy(facts)
                RunReviewRuntime.validate(request(facts))
                self.assertEqual(facts, before)

    def test_unknown_fields_at_every_depth_rejected(self):
        for facts in [dict(executable_R="ignored"), dict(columns=dict(infer_sample="other")),
                      dict(columns=dict(infer_qc_group="other")), dict(batch=dict(method="harmony")),
                      dict(doublet=dict(seed=123)), dict(doublet=dict(capture=dict(path="input.rds"))),
                      dict(doublet=dict(rate=dict(code="anything")))]:
            with self.subTest(facts=facts), self.assertRaises(StoreError):
                RunReviewRuntime.validate(request(facts))

    def test_typed_scalar_boundaries_are_strict(self):
        for facts in [[], {}, dict(batch=[]), dict(batch=dict(technical_batch="false")),
                      dict(batch=dict(technical_batch=0)), dict(doublet=dict(empty_droplets_removed=1)),
                      dict(columns=dict(capture=["x"])), dict(columns=dict(capture="   ")),
                      dict(doublet=dict(rate=dict(value=True))), dict(doublet=dict(rate=dict(value=float("nan")))),
                      dict(doublet=dict(rate=dict(value=.5))), dict(doublet=dict(rate=dict(value=[.05]))),
                      dict(doublet=dict(capture=dict(method="infer"))), dict(doublet=dict(rate=dict(method="automatic")))]:
            with self.subTest(facts=facts), self.assertRaises(StoreError):
                RunReviewRuntime.validate(request(facts))

    def test_facts_is_exclusive_to_strategy_action(self):
        for action, kind in [("facts", "qc"), ("facts", "annotation"), ("approve", "strategy"), ("revise", "strategy")]:
            payload = request(); payload.update(action=action, kind=kind)
            if action == "revise": payload["proposal"] = {}
            with self.subTest(action=action, kind=kind), self.assertRaises(StoreError):
                RunReviewRuntime.validate(payload)
        for field in ["proposal", "sensitivity", "gene_panels", "decision_id"]:
            with self.subTest(field=field), self.assertRaises(StoreError):
                RunReviewRuntime.validate(dict(request(), **{field: {}}))

    def test_invalid_facts_never_start_the_R_bridge(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp); (project / "state.rds").write_bytes(b"authority fixture")
            (project / "project-format.json").write_text('{"project_format_version":4}')
            runtime = RunReviewRuntime(project)
            with patch("qc_runtime.subprocess.run") as process, self.assertRaises(StoreError):
                runtime.decide(request(dict(columns=dict(infer_sample="forbidden"))), runtime.csrf_token)
            process.assert_not_called()


if __name__ == "__main__":
    unittest.main()
