"""Persistent worker mechanism tests with actual Python children, not real R/API."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_continue_runtime as module
from run_continue_runtime import RunContinueRuntime
from store import StoreError


FAKE_R = '''#!/usr/bin/env python3
import json, os, pathlib, sys, tempfile, time
project=pathlib.Path(sys.argv[3]); request=pathlib.Path(sys.argv[4]); output=pathlib.Path(sys.argv[5])
payload=json.loads(request.read_text()); run=json.loads((project/'status.json').read_text())
def atomic(path,value):
 fd,tmp=tempfile.mkstemp(dir=path.parent)
 with os.fdopen(fd,'w') as f: json.dump(value,f)
 os.replace(tmp,path)
calls=project/'fake-calls.json'; prior=json.loads(calls.read_text()) if calls.exists() else []
prior.append({'pid':os.getpid(),'key_environment_empty':all(not os.environ.get(k) for k in %s),
 'argv_prefix':sys.argv[1:3]})
atomic(calls,prior)
gate=os.getenv('FAKE_CONTINUE_GATE')
if gate:
 deadline=time.monotonic()+10
 while not pathlib.Path(gate).is_file():
  if time.monotonic()>deadline: sys.exit(8)
  time.sleep(.01)
time.sleep(float(os.getenv('FAKE_CONTINUE_SLEEP','0.05')))
mode=os.getenv('FAKE_CONTINUE_MODE','boundary')
if mode=='exit':
 atomic(output,{'ok':False,'result':None,'error':{'code':'fake','message':'never expose'}});sys.exit(7)
run.update(status='failed' if mode=='failed' else 'complete' if mode=='complete' else 'awaiting_configuration',
 stage='analysis' if mode=='failed' else 'complete' if mode=='complete' else 'annotation_propose',revision=run['revision']+2)
atomic(project/'status.json',run)
result={k:run[k] for k in ('schema','project_id','input_hash','status','stage','revision')}
if mode=='foreign': result['project_id']='different-project'
if mode=='invalidstatus': result['status']='invented_success'
atomic(output,{'ok':True,'result':result,'error':None})
''' % repr(module.KEYS)


def manifest(path):
    return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in path.rglob("*") if p.is_file() and not p.is_symlink()}


@unittest.skipIf(module.fcntl is None, "POSIX continuation requires flock")
class ContinueRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="scagentkit-continue-test-")
        self.root = Path(self.temp.name)
        self.project = self.root / "project"; self.project.mkdir()
        (self.project / "state.rds").write_bytes(b"fixture-authority-not-real-R")
        self.run = {"schema": "scagentkit.run.v1", "project_id": "literal-project", "input_hash": "a"*64,
                    "revision": 9, "status": "ready", "stage": "qc_apply"}
        self.write_run()
        self.fake = self.root / "fake-rscript"; self.fake.write_text(FAKE_R); self.fake.chmod(0o700)
        self.runtime = RunContinueRuntime(self.project, rscript=str(self.fake))
        self.runtime.describe()
        self.payload = {"project_id": self.run["project_id"], "input_hash": self.run["input_hash"],
                        "expected_revision": self.run["revision"], "request_id": "click-001", "retry": False}

    def tearDown(self):
        # Only children created by this test operator; no product cancellation.
        for process in list(self.runtime._workers.values()):
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=3)
        self.temp.cleanup()

    def write_run(self, **updates):
        self.run.update(updates); module._atomic(self.project / "status.json", self.run)

    def wait_terminal(self, runtime=None):
        runtime = runtime or self.runtime
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            current = runtime.describe()
            if current["job"] and current["job"]["status"] in module.TERMINAL:
                if not self.runtime._workers:
                    return current
            time.sleep(.02)
        self.fail("Test-only child did not reach a terminal record")

    def calls(self):
        path = self.project / "fake-calls.json"
        return json.loads(path.read_text()) if path.exists() else []

    def test_describe_is_cheap_and_returns_exact_binding_without_process(self):
        with patch.object(module.subprocess, "Popen", side_effect=AssertionError("poll must not spawn")):
            current = self.runtime.describe()
        self.assertTrue(current["enabled"]); self.assertIsNone(current["job"])
        self.assertTrue(current["availability"]["can_continue"])
        self.assertEqual(current["availability"]["expected_revision"], 9)
        self.assertEqual(current["schema"], module.SCHEMA)

    def test_typed_contract_rejects_missing_extra_and_wrong_fields_without_jobs(self):
        before = manifest(self.project)
        bad = [{}, dict(self.payload, code="system('bad')"), dict(self.payload, retry="true"),
               dict(self.payload, expected_revision=True), dict(self.payload, expected_revision=-1),
               dict(self.payload, request_id="bad\nlog"), dict(self.payload, input_hash="A"*64),
               dict(self.payload, project_id=" "), dict(self.payload, request_id=4)]
        with patch.object(module.subprocess, "Popen") as process:
            for payload in bad:
                with self.subTest(payload=payload), self.assertRaises(StoreError): self.runtime.submit(payload)
            process.assert_not_called()
        self.assertEqual(manifest(self.project), before)

    def test_stale_and_foreign_snapshot_never_launches(self):
        before = manifest(self.project)
        with patch.object(module.subprocess, "Popen") as process:
            for payload in (dict(self.payload, project_id="foreign"), dict(self.payload, input_hash="b"*64),
                            dict(self.payload, expected_revision=8)):
                with self.assertRaises(StoreError): self.runtime.submit(payload)
            process.assert_not_called()
        self.assertEqual(manifest(self.project), before)

    def test_scientific_review_configuration_complete_and_proposal_failures_are_gated(self):
        with patch.object(module.subprocess, "Popen") as process:
            for status in ("awaiting_review", "awaiting_configuration", "complete", "rejected"):
                self.write_run(status=status)
                self.assertFalse(self.runtime.describe()["availability"]["can_continue"])
                with self.assertRaises(StoreError): self.runtime.submit(self.payload)
            self.write_run(status="failed", stage="annotation_propose")
            self.assertFalse(self.runtime.describe()["availability"]["can_retry"])
            with self.assertRaises(StoreError): self.runtime.submit(dict(self.payload, retry=True))
            process.assert_not_called()

    def test_spawn_failure_is_persistent_idempotent_and_requires_explicit_retry(self):
        with patch.object(module.subprocess, "Popen", side_effect=OSError("key must not be logged")) as process:
            started = self.runtime.submit(self.payload)
            repeated = self.runtime.submit(self.payload)
            self.assertEqual(process.call_count, 1)
        self.assertEqual(started["job"]["status"], "failed")
        self.assertEqual(started["job"]["error"]["code"], "worker_start_failed")
        self.assertTrue(repeated["duplicate"])
        self.assertEqual(started["job"]["job_id"], repeated["job"]["job_id"])
        self.assertTrue(self.runtime.describe()["availability"]["can_retry"])
        with self.assertRaises(StoreError): self.runtime.submit(dict(self.payload, request_id="new-click"))
        self.runtime.submit(dict(self.payload, request_id="explicit-retry", retry=True))
        self.assertEqual(self.wait_terminal()["job"]["status"], "succeeded")
        self.assertEqual(len(self.calls()), 1)
        self.assertNotIn("key must not be logged", json.dumps(manifest(self.project)))

    def test_duplicate_request_id_cannot_change_scope_or_retry(self):
        with patch.object(module.subprocess, "Popen", side_effect=OSError("start")):
            self.runtime.submit(self.payload)
        for change in ({"expected_revision": 10}, {"retry": True}, {"input_hash": "b"*64}):
            with self.assertRaises(StoreError): self.runtime.submit(dict(self.payload, **change))

    def _competing_request_receipts(self, first_claim):
        """Schedule the old-job replay and next-revision admission at their race."""
        gate = self.root / "first-job-gate"
        release_replay = threading.Event(); replay_waiting = threading.Event()
        release_admission = threading.Event(); admission_waiting = threading.Event()
        results = {}; errors = {}; threads = []
        original_once = module._once; original_atomic = module._atomic
        payload = dict(self.payload, request_id="competing-click")
        request_path = self.runtime.base / "requests" / (hashlib.sha256(payload["request_id"].encode()).hexdigest()+".json")

        def staged_once(path, value):
            if threading.current_thread().name == "active-replay" and Path(path) == request_path:
                replay_waiting.set()
                if not release_replay.wait(5): raise AssertionError("Replay fixture was not released")
            return original_once(path, value)

        def staged_atomic(path, value):
            admitting = threading.current_thread().name == "next-revision"
            if admitting and first_claim == "admission" and Path(path) == self.runtime.base / "current.json":
                admission_waiting.set()
                if not release_admission.wait(5): raise AssertionError("Admission fixture was not released")
            original_atomic(path, value)
            if admitting and first_claim == "replay" and Path(path).name == "job.json" and value.get("status") == "queued":
                admission_waiting.set()
                if not release_admission.wait(5): raise AssertionError("Admission fixture was not released")

        def submit(name, runtime, value):
            try: results[name] = runtime.submit(value)
            except Exception as problem: errors[name] = problem

        try:
            # The test-only Python child holds A's real inherited flock until
            # the replay has captured A and observed the new ID as absent.
            with patch.dict(os.environ, {"FAKE_CONTINUE_GATE": str(gate)}):
                initial = self.runtime.submit(self.payload)
            other = RunContinueRuntime(self.project, rscript=str(self.fake))
            with patch.object(module, "_once", side_effect=staged_once), patch.object(module, "_atomic", side_effect=staged_atomic):
                replay = threading.Thread(target=submit, args=("replay", other, payload), name="active-replay")
                threads.append(replay); replay.start()
                self.assertTrue(replay_waiting.wait(5), "Replay did not capture the active job")
                self.assertFalse(request_path.exists())
                gate.touch()
                self.assertEqual(self.wait_terminal()["job"]["status"], "succeeded")
                self.write_run(status="ready", stage="analysis", revision=11)
                next_payload = dict(payload, expected_revision=11)
                with patch.object(module.subprocess, "Popen", side_effect=OSError("test-only launch")) as launch:
                    admission = threading.Thread(target=submit, args=("admission", self.runtime, next_payload), name="next-revision")
                    threads.append(admission); admission.start()
                    self.assertTrue(admission_waiting.wait(5), "Next-revision admission did not reach its checkpoint")
                    self.assertEqual(module._current(self.runtime.base)["job_id"], initial["job"]["job_id"])
                    if first_claim == "admission":
                        # B's durable claim already exists while its publication
                        # is paused; an old active-A snapshot cannot overwrite it.
                        self.assertTrue(request_path.is_file(), "Admission must claim its receipt before publication")
                        admitted_record = request_path.read_bytes()
                        admitted = module._read(request_path)
                        self.assertEqual(admitted["payload_hash"], module._payload_hash(next_payload))
                        self.assertNotEqual(admitted["job_id"], initial["job"]["job_id"])
                    release_replay.set(); replay.join(5)
                    self.assertFalse(replay.is_alive())
                    if first_claim == "replay":
                        self.assertNotIn("replay", errors)
                        self.assertTrue(results["replay"]["duplicate"])
                        self.assertEqual(results["replay"]["job"]["job_id"], initial["job"]["job_id"])
                        accepted_record = request_path.read_bytes()
                    else:
                        self.assertIsInstance(errors.get("replay"), StoreError)
                        self.assertEqual(errors["replay"].status, 409)
                        self.assertEqual(request_path.read_bytes(), admitted_record)
                    launch.assert_not_called()
                    release_admission.set(); admission.join(5)
                    self.assertFalse(admission.is_alive())
                    if first_claim == "replay":
                        self.assertIsInstance(errors.get("admission"), StoreError)
                        self.assertEqual(errors["admission"].status, 409)
                        launch.assert_not_called()
                        self.assertEqual(request_path.read_bytes(), accepted_record)
                        self.assertEqual(module._current(self.runtime.base)["job_id"], initial["job"]["job_id"])
                        self.assertEqual(other.submit(payload)["job"]["job_id"], initial["job"]["job_id"])
                        with self.assertRaises(StoreError): self.runtime.submit(next_payload)
                    else:
                        self.assertNotIn("admission", errors)
                        self.assertFalse(results["admission"]["duplicate"])
                        self.assertEqual(launch.call_count, 1)
                        self.assertEqual(request_path.read_bytes(), admitted_record)
                        self.assertEqual(module._current(self.runtime.base)["job_id"], admitted["job_id"])
                        self.assertEqual(self.runtime.submit(next_payload)["job"]["job_id"], admitted["job_id"])
                        self.assertEqual(launch.call_count, 1)
                        with self.assertRaises(StoreError): other.submit(payload)
            self.assertEqual(len(self.calls()), 1)
        finally:
            gate.touch(); release_replay.set(); release_admission.set()
            for thread in threads: thread.join(5)

    def test_active_replay_receipt_wins_competing_next_revision_admission(self):
        self._competing_request_receipts("replay")

    def test_new_admission_receipt_wins_delayed_active_replay_before_publication(self):
        self._competing_request_receipts("admission")

    def test_start_failed_job_retries_only_saved_local_stages_even_when_R_is_ready(self):
        self.assertIn("prefilter", module.LOCAL_RETRY_STAGES)
        self.assertIn("strategy_selection", module.LOCAL_RETRY_STAGES)
        with patch.object(module.subprocess, "Popen", side_effect=OSError("start")):
            self.runtime.submit(self.payload)
        with patch.object(module.subprocess, "Popen") as process:
            for stage in ("qc_propose", "annotation_propose"):
                self.write_run(status="ready", stage=stage)
                availability = self.runtime.describe()["availability"]
                self.assertFalse(availability["can_continue"])
                self.assertFalse(availability["can_retry"])
                self.assertEqual(availability["reason"], "configuration_required")
                with self.assertRaises(StoreError):
                    self.runtime.submit(dict(self.payload, request_id="retry-"+stage, retry=True))
            process.assert_not_called()
        for stage in module.LOCAL_RETRY_STAGES:
            self.write_run(status="ready", stage=stage)
            self.assertTrue(self.runtime.describe()["availability"]["can_retry"])

    def test_real_detached_child_keeps_flock_across_server_instances_and_double_click(self):
        with patch.dict(os.environ, {"FAKE_CONTINUE_SLEEP": ".45"}):
            initial = self.runtime.submit(self.payload)
        other = RunContinueRuntime(self.project, rscript=str(self.fake))
        same = other.submit(dict(self.payload, request_id="second-click"))
        self.assertTrue(same["duplicate"])
        self.assertEqual(initial["job"]["job_id"], same["job"]["job_id"])
        self.assertEqual(other.describe()["availability"]["reason"], "job_active")
        with self.assertRaises(StoreError): other.submit(dict(self.payload, expected_revision=8))
        terminal = self.wait_terminal(other)
        self.assertEqual(terminal["job"]["status"], "succeeded")
        self.assertEqual(terminal["job"]["next_run_status"], "awaiting_configuration")
        self.assertFalse(terminal["availability"]["can_continue"])
        self.assertEqual(len(self.calls()), 1)
        before = manifest(self.project)
        replay = other.submit(self.payload)
        self.assertTrue(replay["duplicate"])
        alias_replay = other.submit(dict(self.payload, request_id="second-click"))
        self.assertTrue(alias_replay["duplicate"])
        self.assertEqual(alias_replay["job"]["job_id"], initial["job"]["job_id"])
        self.assertEqual(manifest(self.project), before)

    def test_server_process_exit_does_not_kill_worker_and_new_instance_reads_completion(self):
        command = "import sys; from run_continue_runtime import RunContinueRuntime; " + \
            "r=RunContinueRuntime(sys.argv[1],rscript=sys.argv[2]); print(r.submit(__import__('json').loads(sys.argv[3]))['job']['job_id'])"
        env = dict(os.environ, PYTHONPATH=str(module.ROOT), FAKE_CONTINUE_SLEEP=".35")
        result = subprocess.run([sys.executable, "-c", command, str(self.project), str(self.fake), json.dumps(self.payload)],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        fresh = RunContinueRuntime(self.project, rscript=str(self.fake))
        terminal = self.wait_terminal(fresh)
        self.assertEqual(terminal["job"]["job_id"], result.stdout.strip())
        self.assertEqual(terminal["job"]["status"], "succeeded")
        self.assertEqual(len(self.calls()), 1)

    def test_nonzero_and_local_failed_state_never_report_success(self):
        for mode in ("exit", "failed", "foreign", "invalidstatus"):
            with self.subTest(mode=mode):
                if (self.project / "fake-calls.json").exists(): (self.project / "fake-calls.json").unlink()
                self.write_run(status="ready", stage="analysis", revision=9)
                with patch.dict(os.environ, {"FAKE_CONTINUE_MODE": mode}):
                    self.runtime.submit(dict(self.payload, request_id="mode-"+mode, retry=mode != "exit"))
                final = self.wait_terminal()
                self.assertEqual(final["job"]["status"], "failed")
                self.assertEqual(len(self.calls()), 1)
                # An invalid worker response does not grant permission to
                # cross the independently saved configuration boundary.
                self.assertEqual(final["job"]["retry_permitted"], mode in {"exit", "failed"})

    def test_r_child_keeps_job_lock_after_worker_is_killed(self):
        with patch.dict(os.environ, {"FAKE_CONTINUE_SLEEP": ".75"}):
            initial = self.runtime.submit(self.payload)
        directory = self.runtime.base / "jobs" / initial["job"]["job_id"]
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            owner = module._read(directory / "owner.json", optional=True)
            if owner and owner.get("r_pid") is not None: break
            time.sleep(.01)
        else: self.fail("Test child did not publish its owner identity")
        os.kill(owner["worker_pid"], signal.SIGTERM)
        self.runtime._workers[initial["job"]["job_id"]].wait(timeout=3)
        active = RunContinueRuntime(self.project, rscript=str(self.fake)).describe()
        self.assertEqual(active["availability"]["reason"], "job_active")
        duplicate = self.runtime.submit(dict(self.payload, request_id="after-worker-exit"))
        self.assertTrue(duplicate["duplicate"])
        self.assertEqual(duplicate["job"]["job_id"], initial["job"]["job_id"])
        final = self.wait_terminal()
        self.assertEqual(final["job"]["status"], "interrupted")
        self.assertEqual(len(self.calls()), 1)
        self.assertFalse(final["job"]["retry_permitted"])

    def test_dead_owner_queued_job_is_interrupted_not_auto_restarted(self):
        class Exited:
            pid = 99999999
            def wait(self): return 2
        with patch.object(module.subprocess, "Popen", return_value=Exited()):
            self.runtime.submit(self.payload)
        interrupted = self.wait_terminal()
        self.assertEqual(interrupted["job"]["status"], "interrupted")
        self.assertEqual(interrupted["job"]["error"]["code"], "worker_interrupted")
        self.assertTrue(interrupted["availability"]["can_retry"])
        self.assertEqual(self.calls(), [])

    def test_keys_removed_fixed_argv_and_no_stdout_stderr_or_operator_paths_in_public_job(self):
        key = "SECRET_UNIT_VALUE_DO_NOT_PERSIST"
        with patch.dict(os.environ, {name: key for name in module.KEYS}): self.runtime.submit(self.payload)
        final = self.wait_terminal()
        self.assertTrue(self.calls()[0]["key_environment_empty"])
        self.assertEqual(self.calls()[0]["argv_prefix"], ["--vanilla", str(module.ROOT / "run_continue_bridge.R")])
        serialized = json.dumps(final)
        self.assertNotIn(str(self.root), serialized)
        self.assertNotIn("stdout", serialized); self.assertNotIn("stderr", serialized)
        for path in self.project.rglob("*"):
            if path.is_file(): self.assertNotIn(key.encode(), path.read_bytes(), str(path))

    def test_project_code_and_persisted_configuration_changes_fail_closed(self):
        bridge = self.root / "bridge.R"; bridge.write_text("changed")
        old = self.runtime.bridge; self.runtime.bridge = bridge
        with self.assertRaises(StoreError): self.runtime.submit(self.payload)
        self.runtime.bridge = old
        with patch.object(module.subprocess, "Popen", side_effect=OSError("start")): self.runtime.submit(self.payload)
        config = next((self.runtime.base / "jobs").glob("*/config.json"))
        contents = json.loads(config.read_text()); contents["threads"] = 13; module._atomic(config, contents)
        with self.assertRaises(StoreError): self.runtime.describe()

    def test_copied_job_directory_cannot_authorize_a_different_project(self):
        with patch.object(module.subprocess, "Popen", side_effect=OSError("start")): self.runtime.submit(self.payload)
        other = self.root / "other"; shutil.copytree(self.project, other)
        copied = RunContinueRuntime(other, rscript=str(self.fake))
        with self.assertRaises(StoreError): copied.describe()
        with self.assertRaises(StoreError): copied.submit(self.payload)

    def test_replaced_job_or_request_subdirectory_is_rejected_before_writes(self):
        for name in ("jobs", "requests"):
            path = self.runtime.base / name
            moved = self.root / ("old-"+name)
            path.rename(moved)
            outside = self.root / ("outside-"+name); outside.mkdir()
            path.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(StoreError): self.runtime.submit(self.payload)
            with self.assertRaises(StoreError): self.runtime.describe()
            self.assertEqual(list(outside.iterdir()), [])
            path.unlink(); moved.rename(path)

    def test_non_posix_only_rejects_opted_in_runtime(self):
        with patch.object(module, "fcntl", None), self.assertRaises(StoreError) as problem:
            RunContinueRuntime(self.project)
        self.assertIn("POSIX", str(problem.exception))


if __name__ == "__main__":
    unittest.main()
