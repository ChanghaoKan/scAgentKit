"""Actual Rscript + R-launched descendant, no analysis or provider/API calls."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import sys
import time
import unittest

import test_run_continue_runtime as continuation
import test_run_suggestion_runtime as suggestion


@unittest.skipUnless(shutil.which("Rscript"), "Rscript required for actual R inheritance test")
class RWorkerLockTests(unittest.TestCase):
    def wait_for(self, predicate, message):
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.025)
        self.fail(message)

    def exercise(self, kind):
        fixture = (continuation.ContinueRuntimeTests if kind == "continue" else suggestion.SuggestionRuntimeTests)()
        fixture.setUp()
        root, project = fixture.root, fixture.project
        r_gate, child_gate = root / "release-r", root / "release-descendant"
        descendant = root / "descendant.py"
        descendant.write_text("import os,pathlib,sys,time\np=pathlib.Path(sys.argv[1])\n(p/'descendant-pid').write_text(str(os.getpid()))\nwhile not (p/'release-descendant').exists(): time.sleep(.025)\n")
        r_code = root / "hold.R"
        r_code.write_text('args <- commandArgs(TRUE)\n'
            'system2(args[1], c(shQuote(args[2]), shQuote(args[3])), wait = FALSE)\n'
            'writeLines(as.character(Sys.getpid()), file.path(args[3], "r-pid"))\n'
            'while (!file.exists(file.path(args[3], "release-r"))) Sys.sleep(.025)\n')
        # The wrapper delegates request execution to genuine Rscript. Suggestions'
        # read-only descriptor probes retain the established local fake fixture.
        prefix = "#!/usr/bin/env python3\nimport os,sys\n"
        condition = "len(sys.argv)==6" if kind == "continue" else "sys.argv[3]=='suggestion_request'"
        prefix += "if " + condition + ":\n os.execv(" + repr(shutil.which("Rscript")) + ", " + repr([
            shutil.which("Rscript"), "--vanilla", str(r_code), sys.executable, str(descendant), str(root)]) + ")\n"
        fake = continuation.FAKE_R if kind == "continue" else suggestion.FAKE_R
        fixture.fake.write_text(prefix + fake.split("\n", 1)[1])
        try:
            initial = fixture.runtime.submit(fixture.payload)
            job_id = initial["job"]["job_id"]
            self.wait_for(lambda: (root / "r-pid").exists() and (root / "descendant-pid").exists(), "R and descendant did not start")
            base = fixture.runtime.base
            directory = base / "jobs" / job_id
            self.wait_for(lambda: (directory / "owner.json").exists() and json.loads((directory / "owner.json").read_text()).get("r_pid"), "R ownership not published")
            owner = json.loads((directory / "owner.json").read_text())
            process = fixture.runtime._workers[job_id]
            os.kill(owner["worker_pid"], signal.SIGKILL)
            process.wait(timeout=5)
            lock_path = fixture.runtime.lock_file

            def assert_busy_and_replay():
                # This independent open is the same admission primitive as a new
                # server process, not a cached PID or in-memory worker reference.
                with lock_path.open("r+") as lock:
                    with self.assertRaises(BlockingIOError):
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                fresh = (continuation.RunContinueRuntime if kind == "continue" else suggestion.RunSuggestionRuntime)(
                    project, rscript=str(fixture.fake), **({"simulate": True} if kind == "suggestion" else {}))
                view = fresh.describe()
                self.assertIn(view["job"]["status"], {"queued", "running"})
                replay = fresh.submit(dict(fixture.payload, request_id="reopen-" + str(time.monotonic_ns())))
                self.assertEqual(replay["job"]["job_id"], job_id)
                self.assertTrue(replay["duplicate"])

            assert_busy_and_replay()  # Worker dead, actual R and descendant alive.
            r_gate.touch()
            self.wait_for(lambda: not self.process_alive(int((root / "r-pid").read_text())), "R did not exit")
            self.assertTrue(self.process_alive(int((root / "descendant-pid").read_text())))
            assert_busy_and_replay()  # Only R's descendant still owns the flock.
            child_gate.touch()

            def released():
                with lock_path.open("r+") as lock:
                    try:
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        return True
                    except BlockingIOError:
                        return False
            self.wait_for(released, "Lock did not release after the last descendant exited")
            final = fixture.runtime.describe()["job"]
            self.assertEqual(final["status"], "interrupted")
            self.assertEqual(final["job_id"], job_id)
            if kind == "suggestion":
                self.assertTrue(final["requires_reconciliation"])
        finally:
            r_gate.touch(); child_gate.touch()
            try:
                fixture.tearDown()
            finally:
                fixture.doCleanups()

    @staticmethod
    def process_alive(pid):
        # A terminated orphan can remain a zombie until its OS parent reaps it.
        import subprocess
        result = subprocess.run(["ps", "-p", str(pid), "-o", "stat="], capture_output=True, text=True)
        return result.returncode == 0 and not result.stdout.strip().startswith("Z")

    def test_continue_worker_real_r_and_descendant_hold_lock_until_all_exit(self):
        self.exercise("continue")

    def test_suggestion_worker_real_r_and_descendant_hold_lock_until_all_exit(self):
        self.exercise("suggestion")


if __name__ == "__main__":
    unittest.main()
