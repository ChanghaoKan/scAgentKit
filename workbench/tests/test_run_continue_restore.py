"""Terminal-job recovery uses real Python workers; R authority remains separate."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest
from unittest.mock import patch

import test_run_continue_runtime as fixture

module = fixture.module
RunContinueRuntime = fixture.RunContinueRuntime
StoreError = fixture.StoreError


@unittest.skipIf(module.fcntl is None, "POSIX continuation requires flock")
class ContinueRestoreTests(unittest.TestCase):
    def setUp(self):
        self.case = fixture.ContinueRuntimeTests()
        self.case.setUp()
        self.backups = 0

    def tearDown(self):
        try:
            self.case.tearDown()
        finally:
            self.case.doCleanups()

    def finish(self, mode="boundary"):
        with patch.dict(os.environ, {"FAKE_CONTINUE_MODE": mode}):
            result = self.case.runtime.submit(self.case.payload)
        self.case.wait_terminal()
        return result["job"]["job_id"]

    def copy_back(self):
        backup = self.case.root / ("backup-" + str(self.backups))
        self.backups += 1
        self.case.project.rename(backup)
        shutil.copytree(backup, self.case.project)
        self.case.runtime = RunContinueRuntime(self.case.project, rscript=str(self.case.fake))
        return self.case.runtime

    def restore(self):
        return self.case.runtime.restore("analyst", "Restore the complete same-path backup",
                                         original_workers_stopped=True)

    def alias(self):
        name = hashlib.sha256(self.case.payload["request_id"].encode()).hexdigest() + ".json"
        return self.case.runtime.base / "requests" / name

    def test_same_path_restore_preserves_authority_replay_and_next_continuation(self):
        old_id = self.finish()
        runtime = self.copy_back()
        before = fixture.manifest(self.case.project)
        with self.assertRaises(StoreError):
            runtime.describe()
        with patch.object(module.subprocess, "Popen", side_effect=AssertionError("restore must not execute")):
            receipt = self.restore()
            self.assertEqual(runtime.describe()["job"]["restoration_sha256"], receipt["sha256"])
            replay = runtime.submit(self.case.payload)
            self.assertTrue(replay["duplicate"])
            self.assertEqual(replay["job"]["job_id"], old_id)
            self.assertEqual(self.restore(), receipt)
        after = fixture.manifest(self.case.project)
        self.assertTrue(all(after[name] == digest for name, digest in before.items()))
        added = set(after) - set(before)
        self.assertEqual(added, {".workbench-jobs/restoration.json",
                                ".workbench-jobs/restorations/" + receipt["sha256"] + ".json"})
        saved = module._restoration(runtime.base)
        self.assertEqual(saved["observed_state_sha256"], before["state.rds"])
        self.assertIn("not atomic R validation", receipt["boundary"])
        self.case.write_run(status="ready", stage="analysis", revision=11)
        next_job = runtime.submit(dict(self.case.payload, expected_revision=11, request_id="next-step"))
        self.assertNotEqual(next_job["job"]["job_id"], old_id)
        self.assertEqual(self.case.wait_terminal()["job"]["status"], "succeeded")
        self.assertEqual(len(self.case.calls()), 2)

    def test_second_copy_requires_new_explicit_receipt_and_keeps_history(self):
        self.finish()
        self.copy_back()
        first = self.restore()
        self.copy_back()
        with self.assertRaises(StoreError):
            self.case.runtime.describe()
        second = self.restore()
        self.assertNotEqual(first["sha256"], second["sha256"])
        saved = module._restoration(self.case.runtime.base)
        self.assertEqual(saved["previous_sha256"], first["sha256"])
        self.assertTrue(self.case.runtime.submit(self.case.payload)["duplicate"])

    def test_cli_requires_confirmation_and_does_not_start_analysis(self):
        self.finish()
        self.copy_back()
        args = [sys.executable, "-B", str(module.ROOT / "run_continue_runtime.py"), "restore",
                str(self.case.project), "--reviewer", "analyst", "--reason", "Backup restore"]
        missing = subprocess.run(args, capture_output=True, text=True)
        self.assertNotEqual(missing.returncode, 0)
        # The CLI uses its operator PATH; this explicit test executable simulates R.
        rscript = self.case.fake.parent / "Rscript"
        rscript.symlink_to(self.case.fake)
        environment = dict(os.environ, PATH=str(rscript.parent) + os.pathsep + os.environ["PATH"])
        result = subprocess.run(args + ["--confirm-original-stopped"], env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["restored_jobs"], 1)
        self.assertEqual(len(self.case.calls()), 1)

    def test_live_lock_r_lock_and_unconfirmed_source_are_rejected(self):
        self.finish()
        self.copy_back()
        runtime = self.case.runtime
        with self.assertRaises(StoreError):
            runtime.restore("analyst", "reason")
        fd = module._lock(runtime.lock_file)
        try:
            with self.assertRaisesRegex(StoreError, "still owns"):
                self.restore()
        finally:
            os.close(fd)
        r_lock = self.case.project / ".run-lock"
        r_lock.mkdir()
        try:
            with self.assertRaisesRegex(StoreError, "R project lock"):
                self.restore()
        finally:
            r_lock.rmdir()
        self.assertFalse((runtime.base / "restoration.json").exists())

    def test_active_saved_jobs_and_live_recorded_owner_are_not_rebound(self):
        job_id = self.finish()
        self.copy_back()
        directory = self.case.runtime.base / "jobs" / job_id
        job_path = directory / "job.json"
        job = module._read(job_path)
        for status in ("queued", "running"):
            module._atomic(job_path, dict(job, status=status))
            with self.assertRaisesRegex(StoreError, "Queued or running"):
                self.restore()
        module._atomic(job_path, job)
        owner = module._read(directory / "owner.json")
        module._atomic(directory / "owner.json", dict(owner, worker_pid=os.getpid()))
        with self.assertRaisesRegex(StoreError, "PID"):
            self.restore()
        self.assertFalse((self.case.runtime.base / "restoration.json").exists())

    def test_matching_exit_records_handle_pid_reuse_without_claiming_descendants_stopped(self):
        self.finish()
        self.copy_back()
        with patch.object(module, "_alive", return_value=True):
            result = self.restore()
        self.assertIn("not atomic R validation or proof", result["boundary"])

    def test_failed_foreign_or_invalid_response_remains_failed_and_preserved(self):
        for mode in ("foreign", "invalidstatus"):
            with self.subTest(mode=mode):
                if mode != "foreign":
                    self.case.write_run(status="ready", stage="analysis", revision=11)
                    self.case.payload = dict(self.case.payload, expected_revision=11,
                                             request_id="second-failure", retry=True)
                job_id = self.finish(mode)
                self.copy_back()
                directory = self.case.runtime.base / "jobs" / job_id
                response = (directory / "response.json").read_bytes()
                self.restore()
                view = self.case.runtime.describe()
                self.assertEqual(view["job"]["status"], "failed")
                self.assertFalse(view["availability"]["can_continue"])
                self.assertEqual((directory / "response.json").read_bytes(), response)

    def test_tampered_records_aliases_and_success_result_fail_before_publication(self):
        job_id = self.finish()
        self.copy_back()
        directory = self.case.runtime.base / "jobs" / job_id
        cases = [(directory / "config.json", lambda value: dict(value, threads=13)),
                 (directory / "job.json", lambda value: dict(value, status=[])),
                 (directory / "response.json", lambda value: dict(value, result=dict(value["result"], input_hash="b"*64))),
                 (directory / "response.json", lambda value: dict(value, result=dict(value["result"], status=[]))),
                 (self.alias(), lambda value: dict(value, job_id="b"*32)),
                 (self.alias(), lambda value: dict(value, job_id=[])),
                 (self.alias(), lambda value: dict(value, payload_hash="b"*64))]
        for path, change in cases:
            with self.subTest(path=path.name):
                original = path.read_bytes()
                try:
                    module._atomic(path, change(module._read(path)))
                    with self.assertRaises(StoreError):
                        self.restore()
                    self.assertFalse((self.case.runtime.base / "restoration.json").exists())
                finally:
                    path.write_bytes(original)

    def test_deleted_restored_alias_cannot_reuse_the_request_id_for_new_execution(self):
        with patch.object(module.subprocess, "Popen", side_effect=OSError("fixture")):
            self.case.runtime.submit(self.case.payload)
        self.copy_back()
        self.restore()
        self.alias().unlink()
        self.case.write_run(status="ready", stage="analysis", revision=11)
        with patch.object(module.subprocess, "Popen") as launch:
            with self.assertRaisesRegex(StoreError, "alias changed or is missing"):
                self.case.runtime.submit(dict(self.case.payload, expected_revision=11, retry=True))
            launch.assert_not_called()

    def test_restored_job_and_receipt_tampering_are_rejected(self):
        job_id = self.finish()
        self.copy_back()
        receipt = self.restore()
        directory = self.case.runtime.base / "jobs" / job_id
        for path in (directory / "job.json", directory / "worker-exit.json",
                     self.case.runtime.base / "restorations" / (receipt["sha256"] + ".json")):
            original = path.read_bytes()
            try:
                value = module._read(path)
                module._atomic(path, dict(value, extra="changed"))
                with self.assertRaises(StoreError):
                    self.case.runtime.describe()
            finally:
                path.write_bytes(original)

    def test_relocation_and_symlinked_job_are_rejected(self):
        job_id = self.finish()
        other = self.case.root / "different-path"
        shutil.copytree(self.case.project, other)
        copied = RunContinueRuntime(other, rscript=str(self.case.fake))
        with self.assertRaisesRegex(StoreError, "recorded project path"):
            copied.restore("analyst", "reason", original_workers_stopped=True)
        self.copy_back()
        directory = self.case.runtime.base / "jobs" / job_id
        moved = self.case.root / "outside-job"
        directory.rename(moved)
        directory.symlink_to(moved, target_is_directory=True)
        with self.assertRaises(StoreError):
            self.restore()

    def test_publication_failure_never_rebinds_and_can_be_retried(self):
        self.finish()
        self.copy_back()
        real_atomic = module._atomic
        def fail_pointer(path, value):
            if Path(path) == self.case.runtime.base / "restoration.json":
                raise OSError("Injected pointer publication failure")
            return real_atomic(path, value)
        with patch.object(module, "_atomic", side_effect=fail_pointer):
            with self.assertRaises(OSError):
                self.restore()
        with self.assertRaises(StoreError):
            self.case.runtime.describe()
        self.restore()
        self.assertEqual(self.case.runtime.describe()["job"]["status"], "succeeded")

    def test_lost_request_claim_leaves_no_unstarted_active_job_blocking_restoration(self):
        self.case.test_active_replay_receipt_wins_competing_next_revision_admission()
        jobs = list((self.case.runtime.base / "jobs").iterdir())
        self.assertEqual(len(jobs), 1)
        self.assertEqual(module._read(jobs[0] / "job.json")["status"], "succeeded")
        self.copy_back()
        self.assertEqual(self.restore()["restored_jobs"], 1)


if __name__ == "__main__":
    unittest.main()
