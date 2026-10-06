"""Bounded local execution, immutable cache and fingerprint-race regression tests."""
from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

WORKBENCH = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKBENCH))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import directed_runtime
from directed_runtime import DirectedRuntime, file_hash
from evidence import EvidenceLoader, canonical, digest
from store import StoreError
from test_directed import evidence_fixture, expression_fixture


class DirectedRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / "readonly-fixture.rds"
        self.source.write_bytes(b"synthetic existing RNA source; never sent to a provider")
        self.evidence = evidence_fixture()
        self.current = copy.deepcopy(self.evidence)
        self.runtime = DirectedRuntime(
            self.root / "results", source=self.source, cache=self.root / "cache",
            library=self.root / "local-r-library", rscript="mock-local-Rscript",
            evidence_reader=lambda: copy.deepcopy(self.current),
        )
        self.bundle = expression_fixture(self.evidence, nk_only=40)
        self.bundle["scope"]["cell_ids_sha256"] = digest(self.bundle["scope"]["cell_ids"])
        self.bundle["source"].update(
            rds_sha256=file_hash(self.source),
            extractor_sha256=file_hash(WORKBENCH / "extract_directed.R"),
            input_evidence_revision=self.evidence["revision"],
        )
        self.original_source = self.source.read_bytes()

    def payload(self, request_id="local-test-request"):
        view = self.runtime.describe(self.evidence)
        return {"clusterId": "6", "revision": self.evidence["revision"],
                "planHash": view["planHash"], "requestId": request_id}

    def mock_extractor(self, args, **kwargs):
        self.assertFalse(kwargs["shell"])
        self.assertTrue(kwargs["capture_output"])
        self.assertTrue(kwargs["text"])
        self.assertEqual(kwargs["timeout"], 120)
        self.assertEqual(args[:2], ["mock-local-Rscript", "--vanilla"])
        self.assertEqual(args[args.index("--rds") + 1], str(self.source))
        self.assertEqual(args[args.index("--cluster") + 1], "6")
        self.assertEqual(args[args.index("--input-evidence-revision") + 1], self.evidence["revision"])
        self.assertEqual(kwargs["env"]["R_LIBS_USER"], str(self.root / "local-r-library"))
        output = Path(args[args.index("--output-dir") + 1])
        (output / "expression.json").write_text(canonical(self.bundle) + "\n")
        return types.SimpleNamespace(returncode=0, stdout="offline extraction completed", stderr="")

    def failed_temporaries(self):
        return sorted((self.root / "cache").glob(".extract-*"))

    def assert_not_promoted_and_failure_preserved(self, plan_hash):
        self.assertFalse((self.root / "cache" / plan_hash).exists())
        failed = self.failed_temporaries()
        self.assertEqual(len(failed), 1)
        self.assertTrue((failed[0] / "FAILED.txt").is_file())
        return failed[0]

    def test_success_promotes_verified_immutable_bundle_and_replays_without_r_or_api(self):
        payload = self.payload()
        with mock.patch.object(directed_runtime.subprocess, "run", side_effect=self.mock_extractor) as process, \
                mock.patch("socket.socket", side_effect=AssertionError("Unexpected network request")):
            completed = self.runtime.execute(self.evidence, payload)
            repeated = self.runtime.execute(self.evidence, payload)
            another_click = self.runtime.execute(self.evidence, dict(payload, requestId="second-click"))
            process.assert_called_once()
        self.assertEqual(completed["execution"]["status"], "cached")
        self.assertFalse(completed["execution"]["cacheHit"])
        self.assertTrue(repeated["execution"]["cacheHit"])
        self.assertTrue(another_click["execution"]["cacheHit"])
        self.assertEqual(completed["artifact"], repeated["artifact"])
        self.assertEqual(completed["proposal"], repeated["proposal"])
        self.assertEqual(completed["modelReview"]["calls"], 0)
        self.assertEqual(completed["modelReview"]["incrementalCostUSD"], 0)
        self.assertFalse(completed["modelReview"]["enabled"])
        self.assertEqual(self.source.read_bytes(), self.original_source)
        directory = self.root / "cache" / payload["planHash"]
        self.assertEqual(json.loads((directory / "runtime-manifest.json").read_text()),
                         {"planHash": payload["planHash"], "bundleHash": digest(self.bundle)})
        self.assertEqual(self.failed_temporaries(), [])
        fresh = DirectedRuntime(self.root / "results", source=self.source, cache=self.root / "cache",
                                evidence_reader=lambda: copy.deepcopy(self.evidence))
        with mock.patch.object(directed_runtime.subprocess, "run", side_effect=AssertionError("Cache replay invoked R")):
            reloaded = fresh.describe(self.evidence)
        self.assertEqual(reloaded["artifact"], completed["artifact"])
        self.assertEqual(reloaded["expression"], self.bundle)

    def test_malformed_output_is_not_promoted_and_temp_is_retained(self):
        payload = self.payload()
        def malformed(args, **kwargs):
            output = Path(args[args.index("--output-dir") + 1])
            (output / "expression.json").write_text("{}\n")
            return types.SimpleNamespace(returncode=0, stdout="", stderr="")
        with mock.patch.object(directed_runtime.subprocess, "run", side_effect=malformed):
            with self.assertRaisesRegex(ValueError, "Invalid directed expression schema"):
                self.runtime.execute(self.evidence, payload)
        failed = self.assert_not_promoted_and_failure_preserved(payload["planHash"])
        self.assertEqual((failed / "expression.json").read_text(), "{}\n")
        self.assertEqual(self.source.read_bytes(), self.original_source)

    def test_oversized_output_is_rejected_before_promotion(self):
        payload = self.payload()
        def oversized(args, **kwargs):
            output = Path(args[args.index("--output-dir") + 1])
            with (output / "expression.json").open("wb") as stream:
                stream.write(b" " * (16 * 1024 * 1024 + 1))
            return types.SimpleNamespace(returncode=0, stdout="", stderr="")
        with mock.patch.object(directed_runtime.subprocess, "run", side_effect=oversized):
            with self.assertRaisesRegex(ValueError, "Invalid directed bundle file"):
                self.runtime.execute(self.evidence, payload)
        failed = self.assert_not_promoted_and_failure_preserved(payload["planHash"])
        self.assertGreater((failed / "expression.json").stat().st_size, 16 * 1024 * 1024)

    def test_bad_scope_digest_output_is_rejected_before_promotion(self):
        payload = self.payload()
        self.bundle["scope"]["cell_ids_sha256"] = "0" * 64
        with mock.patch.object(directed_runtime.subprocess, "run", side_effect=self.mock_extractor):
            with self.assertRaisesRegex(ValueError, "exact cell scope"):
                self.runtime.execute(self.evidence, payload)
        self.assert_not_promoted_and_failure_preserved(payload["planHash"])

    def test_core_revision_change_during_execution_is_not_promoted(self):
        payload = self.payload()
        def changed_core(args, **kwargs):
            result = self.mock_extractor(args, **kwargs)
            self.current["revision"] = "a" * 64
            return result
        with mock.patch.object(directed_runtime.subprocess, "run", side_effect=changed_core):
            with self.assertRaisesRegex(StoreError, "changed during execution") as problem:
                self.runtime.execute(self.evidence, payload)
        self.assertEqual(problem.exception.status, 409)
        self.assert_not_promoted_and_failure_preserved(payload["planHash"])

    def test_source_content_change_during_execution_is_not_promoted(self):
        payload = self.payload()
        def changed_source(args, **kwargs):
            result = self.mock_extractor(args, **kwargs)
            self.source.write_bytes(b"new RNA revision")
            return result
        with mock.patch.object(directed_runtime.subprocess, "run", side_effect=changed_source):
            with self.assertRaisesRegex(StoreError, "changed during execution"):
                self.runtime.execute(self.evidence, payload)
        self.assert_not_promoted_and_failure_preserved(payload["planHash"])

    def test_extractor_or_taxonomy_change_during_execution_is_not_promoted(self):
        original_hash = directed_runtime.file_hash
        for filename in ("extract_directed.R", "taxonomy.v1.json"):
            with self.subTest(tool=filename), tempfile.TemporaryDirectory() as cache:
                self.runtime.cache = Path(cache)
                changed = False
                def simulated_hash(path):
                    return "b" * 64 if changed and Path(path).name == filename else original_hash(path)
                def changed_tool(args, **kwargs):
                    nonlocal changed
                    result = self.mock_extractor(args, **kwargs)
                    changed = True
                    return result
                payload = self.payload()
                with mock.patch.object(directed_runtime, "file_hash", side_effect=simulated_hash), \
                        mock.patch.object(directed_runtime.subprocess, "run", side_effect=changed_tool):
                    with self.assertRaisesRegex(StoreError, "changed during execution"):
                        self.runtime.execute(self.evidence, payload)
                self.assertFalse((Path(cache) / payload["planHash"]).exists())
                failed = list(Path(cache).glob(".extract-*"))
                self.assertEqual(len(failed), 1)
                self.assertTrue((failed[0] / "FAILED.txt").is_file())

    def test_running_rules_drift_requires_restart_before_execution(self):
        payload = self.payload()
        original_hash = directed_runtime.file_hash
        def simulated_hash(path):
            return "c" * 64 if Path(path).name == "directed.py" else original_hash(path)
        with mock.patch.object(directed_runtime, "file_hash", side_effect=simulated_hash), \
                mock.patch.object(directed_runtime.subprocess, "run") as process:
            with self.assertRaisesRegex(StoreError, "Restart the local server") as problem:
                self.runtime.execute(self.evidence, payload)
            process.assert_not_called()
        self.assertEqual(problem.exception.status, 409)
        self.assertFalse((self.root / "cache").exists())

    def test_rule_change_during_execution_retains_failure_without_promotion(self):
        payload = self.payload()
        original_hash = directed_runtime.file_hash
        changed = False
        def simulated_hash(path):
            return "d" * 64 if changed and Path(path).name == "directed.py" else original_hash(path)
        def changed_rule(args, **kwargs):
            nonlocal changed
            result = self.mock_extractor(args, **kwargs)
            changed = True
            return result
        with mock.patch.object(directed_runtime, "file_hash", side_effect=simulated_hash), \
                mock.patch.object(directed_runtime.subprocess, "run", side_effect=changed_rule):
            with self.assertRaisesRegex(StoreError, "Restart the local server"):
                self.runtime.execute(self.evidence, payload)
        self.assert_not_promoted_and_failure_preserved(payload["planHash"])

    def test_bad_exact_scope_cache_is_rejected_without_reexecution(self):
        payload = self.payload()
        with mock.patch.object(directed_runtime.subprocess, "run", side_effect=self.mock_extractor):
            self.runtime.execute(self.evidence, payload)
        directory = self.root / "cache" / payload["planHash"]
        corrupt = copy.deepcopy(self.bundle)
        corrupt["scope"]["cell_ids"] = list(reversed(corrupt["scope"]["cell_ids"]))
        (directory / "expression.json").write_text(canonical(corrupt))
        (directory / "runtime-manifest.json").write_text(canonical({"planHash": payload["planHash"], "bundleHash": digest(corrupt)}))
        view = self.runtime.describe(self.evidence)
        self.assertIsNone(view["expression"])
        self.assertIn("exact cell scope", view["execution"]["error"])
        with mock.patch.object(directed_runtime.subprocess, "run") as process:
            with self.assertRaises(StoreError):
                self.runtime.execute(self.evidence, payload)
            process.assert_not_called()
        self.assertEqual(json.loads((directory / "expression.json").read_text()), corrupt)

    def test_bad_bundle_manifest_digest_is_rejected_without_reexecution(self):
        payload = self.payload()
        with mock.patch.object(directed_runtime.subprocess, "run", side_effect=self.mock_extractor):
            self.runtime.execute(self.evidence, payload)
        directory = self.root / "cache" / payload["planHash"]
        manifest = {"planHash": payload["planHash"], "bundleHash": "0" * 64}
        (directory / "runtime-manifest.json").write_text(canonical(manifest))
        view = self.runtime.describe(self.evidence)
        self.assertIsNone(view["expression"])
        self.assertIn("content hash", view["execution"]["error"])
        with mock.patch.object(directed_runtime.subprocess, "run") as process:
            with self.assertRaises(StoreError):
                self.runtime.execute(self.evidence, payload)
            process.assert_not_called()

    def test_fingerprint_payload_and_scope_errors_do_not_launch_tools(self):
        correct = self.payload()
        invalid = [dict(correct, clusterId="0"), dict(correct, revision="e" * 64),
                   dict(correct, planHash="e" * 64), dict(correct, requestId=" "),
                   dict(correct, requestId="x" * 161), dict(correct, extra="ignored")]
        with mock.patch.object(directed_runtime.subprocess, "run") as process:
            for payload in invalid:
                with self.subTest(payload=payload), self.assertRaises(StoreError):
                    self.runtime.execute(self.evidence, payload)
            process.assert_not_called()

    def test_failed_process_and_timeout_are_bounded_and_retained(self):
        for timeout in (False, True):
            with self.subTest(timeout=timeout), tempfile.TemporaryDirectory() as cache:
                self.runtime.cache = Path(cache)
                payload = self.payload()
                failure = subprocess.TimeoutExpired("mock-Rscript", 120) if timeout else None
                patch_args = {"side_effect": failure} if timeout else {"return_value": types.SimpleNamespace(returncode=1, stderr="read-only extraction failed", stdout="")}
                with mock.patch.object(directed_runtime.subprocess, "run", **patch_args):
                    with self.assertRaises(StoreError):
                        self.runtime.execute(self.evidence, payload)
                self.assertFalse((Path(cache) / payload["planHash"]).exists())
                failed = list(Path(cache).glob(".extract-*"))
                self.assertEqual(len(failed), 1)
                self.assertTrue((failed[0] / "FAILED.txt").is_file())

    def test_no_configured_source_remains_not_run_without_a_mocked_tool(self):
        runtime = DirectedRuntime(self.root / "results", cache=self.root / "no-source-cache",
                                  evidence_reader=lambda: self.evidence)
        view = runtime.describe(self.evidence)
        self.assertEqual(view["execution"]["status"], "not_run")
        self.assertFalse(view["execution"]["available"])
        self.assertIsNone(view["artifact"])
        with mock.patch.object(directed_runtime.subprocess, "run") as process:
            with self.assertRaisesRegex(StoreError, "local RNA source"):
                runtime.execute(self.evidence, {"clusterId": "6", "revision": self.evidence["revision"],
                                               "planHash": view["planHash"], "requestId": "no-source"})
            process.assert_not_called()

    def test_fresh_runtime_compiles_exact_fingerprinted_bytes_without_module_cache(self):
        rules_directory = self.root / "fresh-rules"
        rules_directory.mkdir()
        exact_bytes = (WORKBENCH / "directed.py").read_bytes() + b'\nRUNTIME_TEST_SENTINEL = "fresh exact source bytes"\n'
        (rules_directory / "directed.py").write_bytes(exact_bytes)
        for filename in ("taxonomy.v1.json", "extract_directed.R"):
            (rules_directory / filename).write_bytes((WORKBENCH / filename).read_bytes())
        poison = types.ModuleType("directed")
        poison.RUNTIME_TEST_SENTINEL = "stale imported module"
        with mock.patch.object(directed_runtime, "ROOT", rules_directory), \
                mock.patch.dict(sys.modules, {"directed": poison}):
            fresh = DirectedRuntime(self.root / "results", source=self.source, cache=self.root / "fresh-cache",
                                    evidence_reader=lambda: self.evidence)
            self.assertEqual(fresh.rules_hash, hashlib.sha256(exact_bytes).hexdigest())
            self.assertEqual(fresh.domain.RUNTIME_TEST_SENTINEL, "fresh exact source bytes")
            self.assertEqual(fresh.domain.propose.__code__.co_filename, str(rules_directory / "directed.py"))
            self.assertEqual(fresh.describe(self.evidence)["execution"]["status"], "not_run")


@unittest.skipUnless(os.environ.get("SCAGENTKIT_TEST_RESULTS") and os.environ.get("SCAGENTKIT_TEST_EXPRESSION"),
                     "Set SCAGENTKIT_TEST_RESULTS and SCAGENTKIT_TEST_EXPRESSION for real cache tests")
class RealDirectedRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.results = Path(os.environ["SCAGENTKIT_TEST_RESULTS"])
        cls.expression_path = Path(os.environ["SCAGENTKIT_TEST_EXPRESSION"])
        cls.evidence = EvidenceLoader(cls.results).load()
        cls.bundle = json.loads(cls.expression_path.read_text())

    def test_real_exact_scope_bundle_is_validated_and_cached_without_r_or_api(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            # Only the provided source fingerprint is mocked in this aggregate-only test.
            source = root / "source-fingerprint-only.rds"
            source.write_bytes(b"not a matrix; fingerprint supplied by frozen manifest")
            original_hash = directed_runtime.file_hash
            def existing_source_hash(path):
                return self.bundle["source"]["rds_sha256"] if Path(path).resolve() == source else original_hash(path)
            with mock.patch.object(directed_runtime, "file_hash", side_effect=existing_source_hash):
                runtime = DirectedRuntime(self.results, source=source, cache=root / "cache",
                                          evidence_reader=lambda: EvidenceLoader(self.results).load())
                view = runtime.describe(self.evidence)
                payload = {"clusterId": "6", "revision": self.evidence["revision"],
                           "planHash": view["planHash"], "requestId": "real-frozen-cache"}
                def supplied_frozen_output(args, **kwargs):
                    output = Path(args[args.index("--output-dir") + 1])
                    (output / "expression.json").write_bytes(self.expression_path.read_bytes())
                    return types.SimpleNamespace(returncode=0, stdout="", stderr="")
                with mock.patch.object(directed_runtime.subprocess, "run", side_effect=supplied_frozen_output) as process, \
                        mock.patch("socket.socket", side_effect=AssertionError("Unexpected external request")):
                    result = runtime.execute(self.evidence, payload)
                    reloaded = runtime.execute(self.evidence, payload)
                    process.assert_called_once()
                self.assertEqual(result["expression"]["scope"]["n_cells"], 155)
                self.assertEqual(result["expression"]["inventory"]["n_cells"], 2638)
                self.assertEqual(result["artifact"], reloaded["artifact"])
                self.assertEqual(result["modelReview"]["calls"], 0)

    @unittest.skipUnless(os.environ.get("SCAGENTKIT_TEST_RDS"), "Set SCAGENTKIT_TEST_RDS for a full local source-content hash check")
    def test_real_rds_content_hash_cache_without_reextracting(self):
        source = Path(os.environ["SCAGENTKIT_TEST_RDS"])
        before = file_hash(source)
        self.assertEqual(before, self.bundle["source"]["rds_sha256"])
        with tempfile.TemporaryDirectory() as directory:
            runtime = DirectedRuntime(self.results, source=source, cache=Path(directory),
                                      evidence_reader=lambda: EvidenceLoader(self.results).load())
            view = runtime.describe(self.evidence)
            target = Path(directory) / view["planHash"]
            target.mkdir()
            (target / "expression.json").write_bytes(self.expression_path.read_bytes())
            (target / "runtime-manifest.json").write_text(canonical({"planHash": view["planHash"], "bundleHash": digest(self.bundle)}))
            with mock.patch.object(directed_runtime.subprocess, "run", side_effect=AssertionError("Cached real evidence must not rerun R")), \
                    mock.patch("socket.socket", side_effect=AssertionError("Unexpected external request")):
                cached = runtime.execute(self.evidence, {"clusterId": "6", "revision": self.evidence["revision"],
                                                        "planHash": view["planHash"], "requestId": "real-local-hash"})
            self.assertEqual(cached["execution"]["status"], "cached")
            self.assertTrue(cached["execution"]["cacheHit"])
            self.assertEqual(cached["expression"], self.bundle)
        self.assertEqual(file_hash(source), before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
