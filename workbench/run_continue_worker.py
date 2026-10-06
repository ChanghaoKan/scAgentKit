#!/usr/bin/env python3
"""Detached fixed worker. Survives browser/server exit; never dispatches AI."""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import types


def main():
    if len(sys.argv) != 4:
        return 2
    config_file = Path(sys.argv[1])
    expected_hash = sys.argv[2]
    lock_fd = int(sys.argv[3])
    if config_file.is_symlink() or not config_file.is_file() or config_file.stat().st_size > 4 * 1024 * 1024:
        return 2
    contents = config_file.read_bytes()
    if hashlib.sha256(contents).hexdigest() != expected_hash:
        return 2
    config = json.loads(contents)
    runtime_file = Path(config["runtime"])
    worker_file = Path(config["worker"])
    bridge_file = Path(config["bridge"])
    root = Path(__file__).resolve().parent
    # Verify source before importing it; bypass timestamp-based .pyc reuse.
    for name, path in (("runtime", runtime_file), ("worker", worker_file), ("bridge", bridge_file)):
        if path.parent != root or path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != config["code_hashes"][name]:
            return 2
    module = types.ModuleType("scagentkit_continue_worker_runtime")
    module.__file__ = str(runtime_file)
    exec(compile(runtime_file.read_bytes(), str(runtime_file), "exec"), module.__dict__)
    project = Path(config["project"])
    base = project / ".workbench-jobs"
    if project.is_symlink() or base.is_symlink() or list((project.stat().st_dev, project.stat().st_ino)) != config["project_identity"] or list((base.stat().st_dev, base.stat().st_ino)) != config["base_identity"]:
        return 2
    for name, identity in config["subdirectory_identities"].items():
        if name not in {"jobs", "requests"}:
            return 2
        path = module._safe_directory(base / name)
        if list((path.stat().st_dev, path.stat().st_ino)) != identity:
            return 2
    directory = module._job_directory(base, config["job_id"])
    if directory / "config.json" != config_file:
        return 2
    lock_file = base / "continue.lock"
    fd_stat, file_stat = os.fstat(lock_fd), lock_file.stat()
    if lock_file.is_symlink() or (fd_stat.st_dev, fd_stat.st_ino) != (file_stat.st_dev, file_stat.st_ino):
        return 2
    fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    job = module._current(base)
    if job is None or job["job_id"] != config["job_id"] or job["config_hash"] != expected_hash or job["status"] != "queued":
        return 2
    owner = {"worker_pid": os.getpid(), "r_pid": None, "started_at": module._time()}
    module._atomic(directory / "owner.json", owner)
    job.update(status="running", updated_at=module._time())
    module._atomic(directory / "job.json", job)
    r_process = None
    try:
        module.RunContinueRuntime.validate(config["payload"])
        request = directory / "request.json"
        response = directory / "response.json"
        if request.exists() or response.exists():
            raise RuntimeError("Worker request/response already exists")
        module._atomic(request, config["payload"])
        env = dict(os.environ)
        for name in module.KEYS:
            env.pop(name, None)
        env.update({name: str(config["threads"]) for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS")})
        if config["library"]:
            env["R_LIBS_USER"] = config["library"]
        r_process = subprocess.Popen([config["rscript"], "--vanilla", str(bridge_file), str(project), str(request), str(response)],
            env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            close_fds=True, pass_fds=(lock_fd,), shell=False)
        owner["r_pid"] = r_process.pid
        module._atomic(directory / "owner.json", owner)
        # A real long analysis has no artificial synchronous HTTP timeout.
        exit_code = r_process.wait()
        owner["r_exit_code"] = exit_code
        owner["r_finished_at"] = module._time()
        module._atomic(directory / "owner.json", owner)
        answer = module._read(response)
        if set(answer) != {"ok", "result", "error"} or not isinstance(answer["ok"], bool) or not answer["ok"] or exit_code != 0:
            raise RuntimeError("Coordinator rejected local continuation")
        run = answer["result"]
        if (not isinstance(run, dict) or run.get("schema") != "scagentkit.run.v1" or
                run.get("project_id") != job["project_id"] or run.get("input_hash") != job["input_hash"] or
                run.get("status") not in {"complete", "awaiting_review", "awaiting_configuration", "failed", "rejected", "ready"} or not isinstance(run.get("stage"), str) or
                isinstance(run.get("revision"), bool) or not isinstance(run.get("revision"), int) or
                run["revision"] < job["expected_revision"]):
            raise RuntimeError("Unverified local continuation result")
        job.update(next_run_status=run["status"], next_run_stage=run["stage"], next_run_revision=run["revision"])
        if run["status"] == "failed":
            job.update(status="failed", error={"code": "local_stage_failed",
                "message": "A local analysis stage failed. Inspect the saved run before explicitly retrying."})
        else:
            job.update(status="succeeded", error=None)
    except Exception:
        job.update(status="failed", error={"code": "local_continue_failed",
            "message": "The local worker did not produce a verified result. Inspect the saved run before explicitly retrying."})
    finally:
        # Never finalize while an R child is still alive, nor remove its R lock.
        if r_process is not None and r_process.poll() is None:
            r_process.wait()
        job["updated_at"] = module._time()
        module._atomic(directory / "job.json", job)
        os.close(lock_fd)
    return 0 if job["status"] == "succeeded" else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # No inherited stderr, key or raw R condition is sent/logged. The
        # persisted launch PID enables explicit interruption diagnosis.
        sys.exit(2)
