"""Explicit asynchronous model suggestions for one operator-selected local run.

Only the request worker receives the immutable provider's named credential.
Polling and scientific Continue never dispatch a provider. Persisted jobs are
replayed rather than resent after reload, double-click, timeout or worker loss.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import secrets
import signal
import subprocess
import sys
import tempfile
import threading

try:
    from .evidence import canonical, strict_json
    from .qc_runtime import QCRuntime
    from .store import StoreError
    from .run_continue_runtime import (ROOT, HASH, JOB_ID, KEYS, fcntl, _time, _sha,
        _payload_hash, _read, _atomic, _once, _alive, _safe_directory, _lock, _projection)
except ImportError:
    from evidence import canonical, strict_json
    from qc_runtime import QCRuntime
    from store import StoreError
    from run_continue_runtime import (ROOT, HASH, JOB_ID, KEYS, fcntl, _time, _sha,
        _payload_hash, _read, _atomic, _once, _alive, _safe_directory, _lock, _projection)

SCHEMA = "scagentkit.run-suggestion.workbench.v1"
JOB_SCHEMA = "scagentkit.run-suggestion.job.v1"
ACTIVE = {"queued", "running"}
TERMINAL = {"succeeded", "failed", "interrupted", "timed_out"}
ACTIONS = {"preview", "approve", "request", "adopt", "discard"}
BINDING = ("project_id", "input_hash", "expected_revision", "suggestion_hash")
MAX_RESULT = 4 * 1024 * 1024


def _environment(library=None, threads=2, key_name=None):
    # An allowlist prevents unrelated application credentials from reaching
    # this worker. No credential values are serialized, logged or returned.
    names = {"PATH", "HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "TMP", "TEMP", "LANG", "TZ",
             "R_HOME", "R_LIBS", "R_LIBS_SITE", "R_LIBS_USER", "DYLD_FALLBACK_LIBRARY_PATH"}
    env = {name: value for name, value in os.environ.items() if name in names or name.startswith("LC_")}
    if key_name:
        if (not isinstance(key_name, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]{0,100}", key_name)
                or key_name in names or key_name.startswith(("PYTHON", "R_", "LD_", "DYLD_", "LC_"))):
            raise StoreError("The saved provider has an unsupported credential environment name", 409)
        if key_name in os.environ:
            env[key_name] = os.environ[key_name]
    env.update({name: str(threads) for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS")})
    env.update({name: os.devnull for name in ("R_PROFILE", "R_PROFILE_USER", "R_ENVIRON", "R_ENVIRON_USER")})
    if library:
        env["R_LIBS_USER"] = library
    return env


def _descriptor(value):
    if isinstance(value, dict) and value.get("schema") == "scagentkit.run.v1":
        value = value.get("suggestion")
    if (not isinstance(value, dict) or value.get("schema") != "scagentkit.run-suggestion.v1"
            or not isinstance(value.get("project_id"), str) or not isinstance(value.get("input_hash"), str)
            or not HASH.fullmatch(value["input_hash"])
            or isinstance(value.get("revision"), bool) or not isinstance(value.get("revision"), int)):
        raise StoreError("Suggestion coordinator returned no verified project-bound descriptor", 409)
    if value.get("suggestion_hash") is not None and (not isinstance(value["suggestion_hash"], str) or not HASH.fullmatch(value["suggestion_hash"])):
        raise StoreError("Suggestion coordinator returned an invalid suggestion fingerprint", 409)
    return value


def _job_dir(base, job_id):
    if not isinstance(job_id, str) or not JOB_ID.fullmatch(job_id):
        raise StoreError("Invalid saved suggestion job identity", 409)
    return _safe_directory(base / "jobs" / job_id)


def _saved(base, job_id):
    directory = _job_dir(base, job_id)
    job = _read(directory / "job.json")
    config = _read(directory / "config.json")
    if (job.get("schema") != JOB_SCHEMA or job.get("job_id") != job_id or job.get("status") not in ACTIVE | TERMINAL
            or job.get("config_hash") != _sha(directory / "config.json") or config.get("job_id") != job_id
            or config.get("payload_hash") != _payload_hash(config.get("payload"))
            or job.get("payload_hash") != config["payload_hash"]):
        raise StoreError("Saved suggestion job/configuration changed; inspect before reconciliation", 409)
    project = base.parent
    if (config.get("project") != str(project) or config.get("project_identity") != [project.stat().st_dev, project.stat().st_ino]
            or config.get("base_identity") != [base.stat().st_dev, base.stat().st_ino]):
        raise StoreError("Saved suggestion belongs to another project directory", 409)
    identities = config.get("subdirectory_identities")
    if not isinstance(identities, dict) or set(identities) != {"jobs", "requests"}:
        raise StoreError("Saved suggestion directory binding is invalid", 409)
    for name, expected in identities.items():
        path = _safe_directory(base / name)
        if expected != [path.stat().st_dev, path.stat().st_ino]:
            raise StoreError("Saved suggestion directory was replaced", 409)
    for field in (*BINDING, "request_id", "reviewer", "reason"):
        if job.get(field) != config["payload"].get(field):
            raise StoreError("Saved suggestion scope changed", 409)
    _descriptor(config["preview"])
    return job, config


def _current(base):
    pointer = _read(base / "current.json", optional=True)
    if pointer is None:
        return None, None
    if set(pointer) != {"job_id"}:
        raise StoreError("Saved suggestion pointer is invalid", 409)
    return _saved(base, pointer["job_id"])


def _owners_dead(base, job):
    if job.get("start_failed") is True:
        return True
    directory = _job_dir(base, job["job_id"])
    owner = _read(directory / "owner.json", optional=True)
    launch = _read(directory / "launch.json", optional=True)
    worker_pid = (owner or launch or {}).get("worker_pid")
    if _alive(worker_pid) is not False:
        return False
    r_pid = (owner or {}).get("r_pid")
    return r_pid is None or _alive(r_pid) is False


def _public_job(job):
    if job is None:
        return None
    fields = ("job_id", "status", *BINDING, "request_id", "created_at", "updated_at", "error", "dispatch_state", "result_status", "simulated")
    result = {field: job.get(field) for field in fields}
    result["requires_reconciliation"] = job["status"] in {"failed", "interrupted", "timed_out"}
    result["retry_permitted"] = False
    return result


class RunSuggestionRuntime(QCRuntime):
    def __init__(self, project_dir, library=None, rscript="Rscript", simulate=False, worker_timeout=300, threads=2):
        if fcntl is None:
            raise StoreError("Background suggestions require POSIX flock; use headless R on this platform")
        super().__init__(project_dir, library, rscript)
        if not isinstance(simulate, bool):
            raise StoreError("Operator simulation flag must be boolean")
        if isinstance(worker_timeout, bool) or not isinstance(worker_timeout, int) or not 1 <= worker_timeout <= 3600:
            raise StoreError("Operator suggestion timeout must be an integer from 1 to 3600 seconds")
        if isinstance(threads, bool) or not isinstance(threads, int) or not 1 <= threads <= 64:
            raise StoreError("Operator suggestion threads must be an integer from 1 to 64")
        self.simulate, self.worker_timeout, self.threads = simulate, worker_timeout, threads
        self.bridge = ROOT / "run_review_bridge.R"
        self.bridge_hash = _sha(self.bridge)
        self.runtime = ROOT / "run_suggestion_runtime.py"
        self.code_hashes = {name: _sha(ROOT / name) for name in ("run_review_bridge.R", "run_suggestion_runtime.py", "run_continue_runtime.py", "qc_runtime.py", "evidence.py", "store.py")}
        self.base = _safe_directory(self.project / ".workbench-suggestions", create=True)
        self.base_identity = (self.base.stat().st_dev, self.base.stat().st_ino)
        self.identities = {}
        for name in ("jobs", "requests"):
            path = _safe_directory(self.base / name, create=True)
            self.identities[name] = (path.stat().st_dev, path.stat().st_ino)
        self.lock_file = self.base / "suggestion.lock"
        self._workers = {}
        self._worker_lock = threading.Lock()

    def _fresh(self):
        super()._fresh()
        if hasattr(self, "base"):
            if self.base.is_symlink() or (self.base.stat().st_dev, self.base.stat().st_ino) != self.base_identity:
                raise StoreError("Suggestion directory changed; restart and inspect", 409)
            for name, identity in self.identities.items():
                path = _safe_directory(self.base / name)
                if (path.stat().st_dev, path.stat().st_ino) != identity:
                    raise StoreError("Suggestion subdirectory changed; restart and inspect", 409)
            for name, sha in self.code_hashes.items():
                path = ROOT / name
                if path.is_symlink() or _sha(path) != sha:
                    raise StoreError("Suggestion runtime code changed; restart and inspect", 409)
        if (self.project / "state.rds").is_symlink():
            raise StoreError("Authoritative R state was replaced by a link", 409)

    @staticmethod
    def validate(action, payload):
        if action not in ACTIONS or not isinstance(payload, dict):
            raise StoreError("Unsupported suggestion action")
        if action == "preview":
            if payload:
                raise StoreError("Suggestion preview accepts no configuration or execution fields")
            return
        fields = {*BINDING, "reviewer", "reason"} | ({"request_id"} if action == "request" else set())
        if set(payload) != fields:
            raise StoreError("Suggestion request requires only its exact project/input/revision/suggestion binding and review reason")
        for name in ("input_hash", "suggestion_hash"):
            if not isinstance(payload[name], str) or not HASH.fullmatch(payload[name]):
                raise StoreError("Suggestion request requires exact lowercase SHA-256 fingerprints")
        revision = payload["expected_revision"]
        if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
            raise StoreError("Suggestion expected_revision must be a nonnegative integer")
        for name in ("project_id", "reviewer", "reason", "request_id"):
            if name not in payload:
                continue
            value = payload[name]
            limit = 4000 if name == "reason" else 200
            if not isinstance(value, str) or not value.strip() or len(value) > limit or any(ord(c) < 32 for c in value):
                raise StoreError("Suggestion %s must be nonempty bounded literal text" % name)
        if len(canonical(payload).encode("utf-8")) > 64 * 1024:
            raise StoreError("Suggestion request exceeds 64 KB", 413)

    def _call_suggestion(self, action, payload=None):
        self._fresh()
        with tempfile.TemporaryDirectory(prefix="scagentkit-suggestion-") as temporary:
            directory = Path(temporary)
            request, response = directory / "request.json", directory / "response.json"
            data = dict(payload or {}, simulate=self.simulate)
            _atomic(request, data)
            try:
                result = subprocess.run([self.rscript, "--vanilla", str(self.bridge), "suggestion_" + action,
                    str(self.project), str(request), str(response)], env=_environment(self.library, self.threads),
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=self.timeout, shell=False)
            except subprocess.TimeoutExpired as problem:
                raise StoreError("Suggestion preview/review timed out; inspect the saved run before repeating", 409) from problem
            self._fresh()
            if response.is_symlink() or not response.is_file() or response.stat().st_size > MAX_RESULT:
                raise StoreError("Suggestion coordinator returned no bounded result", 409)
            answer = strict_json(response.read_text(encoding="utf-8"))
            if not isinstance(answer, dict) or set(answer) != {"ok", "result", "error"} or answer["ok"] is not True or result.returncode:
                # Dynamic provider exceptions and response bodies never enter HTTP.
                raise StoreError("Suggestion coordinator rejected this action; inspect its saved state and exact preview binding", 409)
            suggestion = _descriptor(answer["result"])
            if self.project_id is None:
                self.project_id = suggestion["project_id"]
            elif self.project_id != suggestion["project_id"]:
                raise StoreError("Configured suggestion project was replaced; restart and inspect", 409)
            return suggestion

    def _reconcile(self, job, lock_held):
        if job is not None and job["status"] in ACTIVE and lock_held and _owners_dead(self.base, job):
            job = dict(job, status="interrupted", updated_at=_time(), dispatch_state="unknown_hold_possible", error={
                "code": "worker_interrupted", "message": "The suggestion worker stopped. Usage may be unknown; inspect and reconcile the saved provider ledger in R. No request was resent."})
            _atomic(_job_dir(self.base, job["job_id"]) / "job.json", job)
        return job

    def job_status(self):
        self._fresh()
        fd = _lock(self.lock_file)
        try:
            job, _ = _current(self.base)
            return _public_job(self._reconcile(job, fd is not None))
        finally:
            if fd is not None:
                os.close(fd)

    def _answer(self, suggestion, job, duplicate=None):
        suggestion = dict(suggestion)
        if duplicate is True:
            # A durable request receipt is an idempotency record, never a
            # renewed authority after the input/evidence/revision changes.
            # A fresh GET revalidates current R state before another action.
            suggestion.update(can_approve=False, can_request=False, can_adopt=False, can_discard=False,
                              replay_only=True)
        if job is not None and job["status"] in ACTIVE | {"failed", "interrupted", "timed_out"} and job["suggestion_hash"] == suggestion.get("suggestion_hash"):
            suggestion.update(can_request=False)
            if job["status"] in ACTIVE:
                suggestion.update(can_approve=False, can_adopt=False, can_discard=False)
        answer = {"schema": SCHEMA, "enabled": True, "simulated": self.simulate,
                  "csrf_token": self.csrf_token, "suggestion": suggestion, "job": _public_job(job)}
        if duplicate is not None:
            answer["duplicate"] = duplicate
            answer["historical_receipt"] = duplicate
        return answer

    def describe(self):
        self._fresh()
        with self.lock:
            fd = _lock(self.lock_file)
            try:
                job, config = _current(self.base)
                job = self._reconcile(job, fd is not None)
                # R may own its scientific lock during the request; job polling
                # reads the immutable verified preview rather than spawning R.
                suggestion = config["preview"] if fd is None and config is not None else self._call_suggestion("preview")
                return self._answer(suggestion, job)
            finally:
                if fd is not None:
                    os.close(fd)

    def operate(self, action, payload, token):
        if not isinstance(token, str) or not secrets.compare_digest(token, self.csrf_token):
            raise StoreError("Suggestions require this server's same-origin suggestion token", 403)
        self.validate(action, payload)
        if action == "request":
            return self.submit(payload)
        if action == "preview":
            return self.describe()
        with self.lock:
            self._fresh()
            fd = _lock(self.lock_file)
            try:
                if fd is None:
                    raise StoreError("A suggestion is active; inspect its saved job before changing review", 409)
                job, _ = _current(self.base)
                job = self._reconcile(job, True)
                if job is not None and job["status"] in ACTIVE:
                    raise StoreError("Suggestion ownership is unresolved; inspect before changing review", 409)
                suggestion = self._call_suggestion(action, payload)
                return self._answer(suggestion, job)
            finally:
                if fd is not None:
                    os.close(fd)

    def submit(self, payload):
        self.validate("request", payload)
        self._fresh()
        fd = _lock(self.lock_file)
        try:
            job, config = _current(self.base)
            request_path = self.base / "requests" / (_payload_hash(payload["request_id"]) + ".json")
            recorded = _read(request_path, optional=True)
            if recorded is not None:
                if set(recorded) != {"job_id", "payload_hash"} or recorded["payload_hash"] != _payload_hash(payload):
                    raise StoreError("Suggestion request ID already binds different fields", 409)
                prior, prior_config = _saved(self.base, recorded["job_id"])
                return self._answer(prior_config["preview"], self._reconcile(prior, fd is not None), True)
            scope = {key: payload[key] for key in ("project_id", "input_hash", "suggestion_hash")}
            scope_path = self.base / "requests" / ("scope-" + _payload_hash(scope) + ".json")
            recorded_scope = _read(scope_path, optional=True)
            if recorded_scope is not None:
                if set(recorded_scope) != {"job_id", "scope_hash"} or recorded_scope["scope_hash"] != _payload_hash(scope):
                    raise StoreError("Saved suggestion scope alias changed", 409)
                prior, prior_config = _saved(self.base, recorded_scope["job_id"])
                _once(request_path, {"job_id": prior["job_id"], "payload_hash": _payload_hash(payload)})
                return self._answer(prior_config["preview"], self._reconcile(prior, fd is not None), True)
            if fd is None:
                raise StoreError("A suggestion worker is active; inspect it before requesting another scope", 409)
            job = self._reconcile(job, True)
            if job is not None and job["status"] in ACTIVE:
                raise StoreError("Suggestion ownership is unresolved; reconcile before requesting another scope", 409)
            run = _projection(self.project)
            for key, current in (("project_id", run["project_id"]), ("input_hash", run["input_hash"]), ("expected_revision", run["revision"])):
                if payload[key] != current:
                    raise StoreError("Suggestion project/input/revision is stale; preview again", 409)
            suggestion = self._call_suggestion("preview")
            if suggestion.get("suggestion_hash") != payload["suggestion_hash"] or suggestion.get("can_request") is not True:
                raise StoreError("This exact suggestion is not approved and requestable; inspect the current preview", 409)
            preview = suggestion.get("preview") or {}
            provider = preview.get("provider") or {}
            name = provider.get("name") if isinstance(provider, dict) else None
            if self.simulate and name != "mock":
                raise StoreError("--model-mock requires the project's immutable mock provider", 409)
            if not self.simulate and name not in {"deepseek", "grok"}:
                raise StoreError("Browser requests require a saved DeepSeek/Grok provider or explicit --model-mock", 409)
            key_name = None if self.simulate else provider.get("api_key_env")
            worker_env = _environment(self.library, self.threads, key_name)
            job_id = secrets.token_hex(16)
            directory = self.base / "jobs" / job_id
            directory.mkdir(mode=0o700)
            config = {"schema": "scagentkit.run-suggestion.config.v1", "job_id": job_id, "project": str(self.project),
                "project_identity": list(self.project_identity), "base_identity": list(self.base_identity),
                "subdirectory_identities": {name: list(value) for name, value in self.identities.items()},
                "payload": payload, "payload_hash": _payload_hash(payload), "preview": suggestion,
                "rscript": str(self.rscript), "library": self.library, "threads": self.threads,
                "simulate": self.simulate, "worker_timeout": self.worker_timeout, "key_name": key_name,
                "runtime": str(self.runtime), "bridge": str(self.bridge), "code_hashes": self.code_hashes}
            _atomic(directory / "config.json", config)
            job = {"schema": JOB_SCHEMA, "job_id": job_id, **payload, "payload_hash": config["payload_hash"],
                "config_hash": _sha(directory / "config.json"), "simulated": self.simulate, "status": "queued",
                "created_at": _time(), "updated_at": _time(), "error": None, "dispatch_state": "not_started", "result_status": None}
            _atomic(directory / "job.json", job)
            _atomic(self.base / "current.json", {"job_id": job_id})
            _once(scope_path, {"job_id": job_id, "scope_hash": _payload_hash(scope)})
            _once(request_path, {"job_id": job_id, "payload_hash": _payload_hash(payload)})
            try:
                process = subprocess.Popen([sys.executable, str(self.runtime), "--worker", str(directory / "config.json"),
                    job["config_hash"], str(fd)], env=worker_env, stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    close_fds=True, pass_fds=(fd,), start_new_session=True, shell=False)
            except (OSError, ValueError):
                process = None
                job.update(status="failed", start_failed=True, updated_at=_time(), error={"code": "worker_start_failed",
                    "message": "Suggestion worker could not start. Inspect the saved run in R; no automatic retry."})
                _atomic(directory / "job.json", job)
            if process is not None:
                with self._worker_lock:
                    self._workers[job_id] = process
                def reap():
                    code = process.wait()
                    try:
                        _atomic(directory / "worker-exit.json", {"worker_pid": process.pid, "exit_code": code, "finished_at": _time()})
                    finally:
                        with self._worker_lock:
                            self._workers.pop(job_id, None)
                threading.Thread(target=reap, name="scagentkit-suggestion-reaper", daemon=True).start()
                _atomic(directory / "launch.json", {"worker_pid": process.pid, "started_at": _time()})
            return self._answer(suggestion, _read(directory / "job.json"), False)
        finally:
            if fd is not None:
                os.close(fd)


def _worker(config_file, expected_hash, lock_fd):
    config_file = Path(config_file)
    if config_file.is_symlink() or not config_file.is_file() or config_file.stat().st_size > MAX_RESULT or _sha(config_file) != expected_hash:
        return 2
    config = _read(config_file)
    for name, expected in config["code_hashes"].items():
        if name not in {"run_review_bridge.R", "run_suggestion_runtime.py", "run_continue_runtime.py", "qc_runtime.py", "evidence.py", "store.py"}:
            return 2
        path = ROOT / name
        if path.is_symlink() or not path.is_file() or _sha(path) != expected:
            return 2
    project = Path(config["project"])
    base = project / ".workbench-suggestions"
    job, checked = _saved(base, config["job_id"])
    if checked != config or config_file != _job_dir(base, job["job_id"]) / "config.json":
        return 2
    lock_path = base / "suggestion.lock"
    fd_stat, path_stat = os.fstat(lock_fd), lock_path.stat()
    if lock_path.is_symlink() or (fd_stat.st_dev, fd_stat.st_ino) != (path_stat.st_dev, path_stat.st_ino):
        return 2
    fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    current, _ = _current(base)
    if current is None or current["job_id"] != job["job_id"] or job["status"] != "queued":
        return 2
    directory = _job_dir(base, job["job_id"])
    owner = {"worker_pid": os.getpid(), "r_pid": None, "started_at": _time()}
    _atomic(directory / "owner.json", owner)
    job.update(status="running", dispatch_state="unknown_hold_possible", updated_at=_time())
    _atomic(directory / "job.json", job)
    process = None
    try:
        RunSuggestionRuntime.validate("request", config["payload"])
        request, response = directory / "request.json", directory / "response.json"
        if request.exists() or response.exists():
            raise RuntimeError("Request/response already exists")
        payload = {key: value for key, value in config["payload"].items() if key != "request_id"}
        payload["simulate"] = config["simulate"]
        _atomic(request, payload)
        env = _environment(config["library"], config["threads"], config["key_name"])
        process = subprocess.Popen([config["rscript"], "--vanilla", config["bridge"], "suggestion_request", str(project), str(request), str(response)],
            env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            close_fds=True, pass_fds=(lock_fd,), start_new_session=True, shell=False)
        owner["r_pid"] = process.pid
        _atomic(directory / "owner.json", owner)
        try:
            code = process.wait(timeout=config["worker_timeout"])
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=5)
            job.update(status="timed_out", error={"code": "suggestion_timeout", "message": "The model worker exceeded the operator time limit. Usage may be unknown; reconcile the saved provider ledger in R. No request was resent."})
        else:
            answer = _read(response)
            if set(answer) != {"ok", "result", "error"} or answer["ok"] is not True or code:
                raise RuntimeError("Coordinator rejected model request")
            suggestion = _descriptor(answer["result"])
            if (suggestion["project_id"] != job["project_id"] or suggestion["input_hash"] != job["input_hash"]
                    or suggestion.get("suggestion_hash") != job["suggestion_hash"] or suggestion["revision"] < job["expected_revision"]):
                raise RuntimeError("Model result binding changed")
            status = suggestion.get("status")
            job.update(status="succeeded" if suggestion.get("can_adopt") is True else "failed", result_status=status,
                dispatch_state="result_saved", error=None if suggestion.get("can_adopt") is True else {
                    "code": "suggestion_not_validated", "message": "The model response did not yield an adoptable typed proposal. Inspect the saved response and provider ledger in R; no automatic retry."})
    except Exception:
        job.update(status="failed", error={"code": "suggestion_failed", "message": "No verified model suggestion result was received. Usage may be unknown; inspect and reconcile the saved provider ledger in R. No request was resent."})
    finally:
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM); process.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=5)
        owner.update(r_exit_code=process.returncode if process is not None else None, finished_at=_time())
        _atomic(directory / "owner.json", owner)
        job["updated_at"] = _time()
        _atomic(directory / "job.json", job)
        os.close(lock_fd)
    return 0 if job["status"] == "succeeded" else 1


if __name__ == "__main__":
    try:
        sys.exit(_worker(sys.argv[2], sys.argv[3], int(sys.argv[4])) if len(sys.argv) == 5 and sys.argv[1] == "--worker" else 2)
    except Exception:
        sys.exit(2)
