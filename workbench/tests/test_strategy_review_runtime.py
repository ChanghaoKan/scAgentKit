"""Strategy transport boundaries only; these tests never execute R or providers."""
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
from run_review_runtime import RunReviewRuntime
from run_continue_runtime import RunContinueRuntime, LOCAL_RETRY_STAGES, KEYS
from store import StoreError


def decision(action="approve"):
    return {"action": action, "kind": "strategy", "project_id": "strategy-fixture",
            "input_hash": "a" * 64, "proposal_hash": "b" * 64,
            "review_hash": "c" * 64, "expected_revision": 12,
            "reviewer": "analyst", "reason": "Review the complete supported strategy"}


def proposal():
    return {"schema": "scagentkit.strategy.v1", "rationale": "Public offline fixture",
            "risks": ["Scientific choices require review"], "inferences": [],
            "qc": None, "analysis": None, "pcs": None,
            "batch": {"method": "none", "reason": "No verified batch contrast"},
            "clustering": None, "umap": None}


class StrategyReviewBoundaryTests(unittest.TestCase):
    def test_complete_strategy_actions_are_allowlisted(self):
        for action in ("approve", "reject", "revise"):
            payload = decision(action)
            if action == "revise": payload["proposal"] = proposal()
            with self.subTest(action=action): RunReviewRuntime.validate(payload)

    def test_strategy_cannot_preview_undo_resume_or_execute(self):
        for action in ("preview", "undo", "resume", "execute", "chat", "integrate"):
            payload = decision(action)
            if action == "undo": payload["decision_id"] = "literal-decision"
            with self.subTest(action=action), self.assertRaises(StoreError):
                RunReviewRuntime.validate(payload)

    def test_revise_requires_complete_object_transport(self):
        for value in (None, [], "source('x')", True, 42):
            with self.subTest(value=value), self.assertRaises(StoreError):
                RunReviewRuntime.validate(dict(decision("revise"), proposal=value))
        with self.assertRaises(StoreError): RunReviewRuntime.validate(decision("revise"))
        for action in ("approve", "reject"):
            with self.subTest(action=action), self.assertRaises(StoreError):
                RunReviewRuntime.validate(dict(decision(action), proposal=proposal()))

    def test_browser_cannot_choose_source_provider_paths_or_execution(self):
        for field in ("code", "provider", "chat_fn", "project_dir", "rscript", "library",
                      "output_dir", "url", "source", "resume", "request_id",
                      "sensitivity", "gene_panels", "decision_id"):
            with self.subTest(field=field), self.assertRaises(StoreError):
                RunReviewRuntime.validate(dict(decision(), **{field: "never-used"}))

    def test_exact_revision_and_hash_scope_are_required(self):
        for field in ("project_id", "input_hash", "proposal_hash", "review_hash", "expected_revision"):
            payload = decision(); del payload[field]
            with self.subTest(field=field), self.assertRaises(StoreError): RunReviewRuntime.validate(payload)
        for field in ("input_hash", "proposal_hash", "review_hash"):
            for value in ("A" * 64, "a" * 63, "a" * 64 + "\n", None):
                with self.subTest(field=field, value=value), self.assertRaises(StoreError):
                    RunReviewRuntime.validate(dict(decision(), **{field: value}))
        for value in (True, -1, 1.5, "12"):
            with self.subTest(value=value), self.assertRaises(StoreError):
                RunReviewRuntime.validate(dict(decision(), expected_revision=value))

    def test_strategy_payload_is_bounded(self):
        value = proposal(); value["rationale"] = "x" * (1024 * 1024)
        with self.assertRaises(StoreError) as problem:
            RunReviewRuntime.validate(dict(decision("revise"), proposal=value))
        self.assertEqual(problem.exception.status, 413)

    def test_fixed_bridge_forwards_literal_json_and_strips_all_provider_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / "project"; project.mkdir()
            (project / "state.rds").write_bytes(b"Not interpreted by Python")
            runtime = RunReviewRuntime(project, library=directory)
            value = proposal(); value["rationale"] = "$(touch /never-execute) `literal`; source('x')"
            payload = dict(decision("revise"), proposal=value)
            def result(argv, **kwargs):
                self.assertFalse(kwargs["shell"])
                self.assertEqual(argv[:4], ["Rscript", "--vanilla", str(runtime.bridge), "decision"])
                self.assertEqual(json.loads(Path(argv[-2]).read_text()), payload)
                self.assertEqual(Path(argv[-2]).stat().st_mode & 0o777, 0o600)
                self.assertFalse(any(key in kwargs["env"] for key in KEYS))
                run = {"schema": "scagentkit.run.v1", "project_id": "strategy-fixture",
                       "input_hash": "a" * 64, "revision": 13, "status": "awaiting_review",
                       "stage": "strategy_propose", "review_node": {"kind": "strategy"}}
                Path(argv[-1]).write_text(canonical({"ok": True, "result": run, "error": None}))
                return subprocess.CompletedProcess(argv, 0, b"private stdout", b"private stderr")
            with patch.dict(os.environ, {key: "never-export" for key in KEYS}), \
                    patch("qc_runtime.subprocess.run", side_effect=result) as process:
                answer = runtime.decide(payload, runtime.csrf_token)
            self.assertEqual(process.call_count, 1)
            self.assertEqual(answer["run"]["review_node"]["kind"], "strategy")
            self.assertNotIn("never-export", canonical(answer))
            self.assertNotIn("private stdout", canonical(answer))
            self.assertNotIn("private stderr", canonical(answer))

    def test_strategy_csrf_rejected_before_bridge(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / "project"; project.mkdir()
            (project / "state.rds").write_bytes(b"fixture")
            runtime = RunReviewRuntime(project)
            with patch("qc_runtime.subprocess.run") as process:
                with self.assertRaises(StoreError) as problem: runtime.decide(decision(), "old-token")
                self.assertEqual(problem.exception.status, 403); process.assert_not_called()

    def test_strategy_local_retry_stages_are_explicit(self):
        stages = {"strategy_evidence", "strategy_apply", "strategy_basis", "strategy_neighbors", "strategy_cluster"}
        self.assertTrue(stages <= LOCAL_RETRY_STAGES)
        runtime = object.__new__(RunContinueRuntime)
        for stage in stages:
            for status in ("failed", "running"):
                run = {"project_id": "strategy-fixture", "input_hash": "a" * 64, "revision": 12,
                       "status": status, "stage": stage}
                with self.subTest(stage=stage, status=status):
                    answer = runtime._availability(run, None, False)
                    self.assertTrue(answer["can_retry"]); self.assertFalse(answer["can_continue"])
                    self.assertTrue(answer["requires_explicit_retry"])

    def test_strategy_model_stage_failure_cannot_retry_in_browser(self):
        runtime = object.__new__(RunContinueRuntime)
        for stage in ("strategy_propose", "cycle", "doublet", "subcluster"):
            run = {"project_id": "strategy-fixture", "input_hash": "a" * 64, "revision": 12,
                   "status": "failed", "stage": stage}
            with self.subTest(stage=stage):
                answer = runtime._availability(run, None, False)
                self.assertFalse(answer["can_retry"]); self.assertFalse(answer["can_continue"])

    def test_waiting_strategy_and_manual_configuration_cannot_continue(self):
        runtime = object.__new__(RunContinueRuntime)
        for status in ("awaiting_review", "awaiting_configuration", "rejected", "complete", "budget_exceeded"):
            run = {"project_id": "strategy-fixture", "input_hash": "a" * 64, "revision": 12,
                   "status": status, "stage": "strategy_apply"}
            with self.subTest(status=status):
                answer = runtime._availability(run, None, False)
                self.assertFalse(answer["can_retry"]); self.assertFalse(answer["can_continue"])


if __name__ == "__main__": unittest.main()
