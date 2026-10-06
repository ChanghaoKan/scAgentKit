"""Persistent, allowlisted local continuation. Polling never starts R.

The server opts in for one operator-selected project. R remains authoritative
for project/revision/input validation, scientific approval and analysis locks.
"""
from __future__ import annotations

try:
    import fcntl
except ImportError:
    fcntl = None
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import tempfile
import threading
from datetime import datetime, timezone

try:
    from .evidence import canonical, strict_json
    from .store import StoreError
except ImportError:
    from evidence import canonical, strict_json
    from store import StoreError

ROOT = Path(__file__).resolve().parent
SCHEMA = "scagentkit.run-continue.workbench.v1"
JOB_SCHEMA = "scagentkit.run-continue.job.v1"
HASH = re.compile(r"[a-f0-9]{64}\Z")
JOB_ID = re.compile(r"[a-f0-9]{32}\Z")
ACTIVE = {"queued", "running"}
TERMINAL = {"succeeded", "failed", "interrupted"}
LOCAL_RETRY_STAGES = {"prefilter", "qc_evidence", "qc_apply", "analysis", "strategy_evidence", "strategy_apply", "strategy_selection", "strategy_preprocess", "strategy_basis", "strategy_batch", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence", "annotation_apply", "finalize"}
KEYS = ("DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY",
        "GOOGLE_API_KEY", "GEMINI_API_KEY", "AZURE_OPENAI_API_KEY", "COHERE_API_KEY",
        "MISTRAL_API_KEY", "OPENROUTER_API_KEY", "HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN")
MAX_JSON = 4 * 1024 * 1024


def _time():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def _sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _payload_hash(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def _read(path, optional=False):
    path = Path(path)
    if optional and not path.exists():
        return None
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_JSON:
        raise StoreError("Local continuation record is missing or invalid; inspect the saved project", 409)
    try:
        value = strict_json(path.read_text(encoding="utf-8"))
    except (ValueError, OSError, UnicodeError) as problem:
        raise StoreError("Local continuation record is unreadable; inspect the saved project", 409) from problem
    if not isinstance(value, dict):
        raise StoreError("Local continuation record must be an object", 409)
    return value


def _atomic(path, value):
    path = Path(path)
    if path.is_symlink():
        raise StoreError("Local continuation record was replaced by a link", 409)
    fd, temporary = tempfile.mkstemp(prefix=".continue-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(canonical(value) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _once(path, value):
    """Atomically install an immutable replay alias without the active job lock.

    Different tabs may reuse a running job while its worker owns the flock.
    They must still preserve each accepted request ID after it finishes.
    """
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix=".continue-alias-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(canonical(value) + "\n"); stream.flush(); os.fsync(stream.fileno())
        try:
            os.link(temporary, path, follow_symlinks=False)
        except FileExistsError:
            if _read(path) != value:
                raise StoreError("This Continue request ID already binds another job/snapshot", 409)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def _alive(pid):
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return None
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def _safe_directory(path, create=False):
    path = Path(path)
    if create:
        try:
            path.mkdir(mode=0o700)
        except FileExistsError:
            pass
    if path.is_symlink() or not path.is_dir():
        raise StoreError("Local continuation directory must be a nonsymlink directory", 409)
    return path


def _lock(path, blocking=False):
    flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
    if Path(path).is_symlink():
        raise StoreError("Local continuation lock was replaced by a link", 409)
    fd = os.open(path, flags, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        return fd
    except BlockingIOError:
        os.close(fd)
        return None
    except Exception:
        os.close(fd)
        raise


def _projection(project):
    result = _read(project / "status.json")
    if (result.get("schema") != "scagentkit.run.v1" or not isinstance(result.get("project_id"), str)
            or not isinstance(result.get("input_hash"), str) or not HASH.fullmatch(result["input_hash"])
            or isinstance(result.get("revision"), bool) or not isinstance(result.get("revision"), int)
            or result["revision"] < 0 or not isinstance(result.get("status"), str)
            or not isinstance(result.get("stage"), str)):
        raise StoreError("Saved run projection is invalid; inspect its authoritative R state", 409)
    return result


def _job_directory(base, job_id):
    if not isinstance(job_id, str) or not JOB_ID.fullmatch(job_id):
        raise StoreError("Invalid saved local continuation job identity", 409)
    _safe_directory(base / "jobs")
    return _safe_directory(base / "jobs" / job_id)


def _saved_job(base, job_id):
    directory = _job_directory(base, job_id)
    job = _read(directory / "job.json")
    if (job.get("schema") != JOB_SCHEMA or job.get("job_id") != job_id
            or job.get("status") not in ACTIVE | TERMINAL):
        raise StoreError("Invalid saved local continuation state", 409)
    config = _read(directory / "config.json")
    if (job.get("config_hash") != _sha(directory / "config.json")
            or config.get("job_id") != job["job_id"]
            or config.get("payload_hash") != _payload_hash(config.get("payload"))
            or job.get("payload_hash") != config["payload_hash"]):
        raise StoreError("Local continuation configuration changed; inspect before continuing", 409)
    project = base.parent
    if (config.get("project") != str(project) or
            config.get("project_identity") != [project.stat().st_dev, project.stat().st_ino] or
            config.get("base_identity") != [base.stat().st_dev, base.stat().st_ino]):
        raise StoreError("Saved local continuation belongs to a different project directory", 409)
    identities = config.get("subdirectory_identities")
    if not isinstance(identities, dict) or set(identities) != {"jobs", "requests"}:
        raise StoreError("Saved local continuation directory binding is invalid", 409)
    for name, identity in identities.items():
        path = _safe_directory(base / name)
        if identity != [path.stat().st_dev, path.stat().st_ino]:
            raise StoreError("Saved local continuation subdirectory was replaced", 409)
    for field in ("project_id", "input_hash", "expected_revision", "request_id", "retry"):
        if job.get(field) != config["payload"].get(field):
            raise StoreError("Local continuation scope record changed", 409)
    return job


def _current(base):
    pointer = _read(base / "current.json", optional=True)
    if pointer is None:
        return None
    if set(pointer) != {"job_id"}:
        raise StoreError("Invalid saved local continuation pointer", 409)
    return _saved_job(base, pointer["job_id"])


def _owners_dead(base, job):
    if job.get("start_failed") is True:
        return True
    directory = _job_directory(base, job["job_id"])
    launch = _read(directory / "launch.json", optional=True)
    owner = _read(directory / "owner.json", optional=True)
    worker_pid = (owner or launch or {}).get("worker_pid")
    if _alive(worker_pid) is not False:
        return False
    r_pid = (owner or {}).get("r_pid")
    return r_pid is None or _alive(r_pid) is False


def _public_job(job, retry_permitted=False):
    if job is None:
        return None
    fields = ("job_id", "status", "request_id", "project_id", "input_hash", "expected_revision", "retry",
              "created_at", "updated_at", "next_run_status", "next_run_stage", "next_run_revision", "error")
    result = {field: job.get(field) for field in fields}
    result["retry_permitted"] = bool(retry_permitted)
    return result


class RunContinueRuntime:
    def __init__(self, project_dir, library=None, rscript="Rscript", threads=2):
        if fcntl is None:
            raise StoreError("Background local Continue requires POSIX flock; use explicit R continuation on this platform")
        supplied = Path(project_dir).expanduser()
        if supplied.is_symlink() or not supplied.is_dir():
            raise StoreError("Continue requires an existing nonsymlink local project")
        self.project = supplied.resolve()
        if (self.project / "state.rds").is_symlink() or not (self.project / "state.rds").is_file():
            raise StoreError("Continue requires the authoritative local state.rds")
        if isinstance(threads, bool) or not isinstance(threads, int) or not 1 <= threads <= 64:
            raise StoreError("Operator continuation threads must be an integer from 1 to 64")
        self.threads = threads
        self.library = os.pathsep.join(str(Path(entry).expanduser().resolve()) for entry in library.split(os.pathsep) if entry) if library else None
        self.rscript = str(rscript)
        self.project_identity = (self.project.stat().st_dev, self.project.stat().st_ino)
        self.bridge = ROOT / "run_continue_bridge.R"
        self.worker = ROOT / "run_continue_worker.py"
        self.runtime = ROOT / "run_continue_runtime.py"
        self.code_hashes = {"bridge": _sha(self.bridge), "worker": _sha(self.worker), "runtime": _sha(self.runtime)}
        self.base = _safe_directory(self.project / ".workbench-jobs", create=True)
        self.base_identity = (self.base.stat().st_dev, self.base.stat().st_ino)
        self.subdirectory_identities = {}
        for name in ("jobs", "requests"):
            path = _safe_directory(self.base / name, create=True)
            self.subdirectory_identities[name] = (path.stat().st_dev, path.stat().st_ino)
        self.lock_file = self.base / "continue.lock"
        self._workers = {}
        self._worker_lock = threading.Lock()
        self._fresh()

    def _fresh(self):
        for path, expected in ((self.project, self.project_identity), (self.base, self.base_identity)):
            if path.is_symlink() or not path.is_dir() or (path.stat().st_dev, path.stat().st_ino) != expected:
                raise StoreError("Configured continuation project/directory changed; restart and inspect", 409)
        for name, path in (("bridge", self.bridge), ("worker", self.worker), ("runtime", self.runtime)):
            if path.is_symlink() or not path.is_file() or _sha(path) != self.code_hashes[name]:
                raise StoreError("Local continuation code changed; restart and inspect", 409)
        for name, expected in self.subdirectory_identities.items():
            path = _safe_directory(self.base / name)
            if (path.stat().st_dev, path.stat().st_ino) != expected:
                raise StoreError("Local continuation subdirectory changed; restart and inspect", 409)
        if (self.project / "state.rds").is_symlink():
            raise StoreError("Authoritative local R state was replaced by a link", 409)

    @staticmethod
    def validate(payload):
        expected = {"project_id", "input_hash", "expected_revision", "request_id", "retry"}
        if not isinstance(payload, dict) or set(payload) != expected:
            raise StoreError("Continue requires only its exact project, input, revision, request ID and retry flag")
        for name in ("project_id", "request_id"):
            value = payload[name]
            if not isinstance(value, str) or not value.strip() or len(value) > 200 or any(ord(c) < 32 for c in value):
                raise StoreError("Continue %s must be nonempty bounded literal text" % name)
        if not isinstance(payload["input_hash"], str) or not HASH.fullmatch(payload["input_hash"]):
            raise StoreError("Continue requires the exact lowercase input SHA-256 fingerprint")
        revision = payload["expected_revision"]
        if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
            raise StoreError("Continue expected_revision must be a nonnegative integer")
        if not isinstance(payload["retry"], bool):
            raise StoreError("Continue retry must be an explicit boolean")

    def _reconcile(self, job, lock_held):
        if job is not None and job["status"] in ACTIVE and lock_held and _owners_dead(self.base, job):
            job = dict(job, status="interrupted", updated_at=_time(), error={
                "code": "worker_interrupted", "message": "The local worker stopped. Inspect the saved run before explicitly retrying."})
            _atomic(_job_directory(self.base, job["job_id"]) / "job.json", job)
        return job

    def _availability(self, run, job, busy):
        status, stage = run["status"], run["stage"]
        needs_retry = job is not None and job["status"] in {"failed", "interrupted"}
        owners_dead = job is None or job["status"] == "succeeded" or _owners_dead(self.base, job)
        ready = status == "ready"
        failed_local = status in {"failed", "running"} and stage in LOCAL_RETRY_STAGES
        can_continue = not busy and ready and not needs_retry and owners_dead
        can_retry = not busy and owners_dead and (failed_local or needs_retry and ready and stage in LOCAL_RETRY_STAGES)
        reason = ("job_active" if busy else "owner_still_alive" if not owners_dead else
                  "explicit_retry_required" if can_retry else "ready" if can_continue else
                  "complete" if status == "complete" else "scientific_review_required" if status == "awaiting_review" else
                  "configuration_required" if status == "awaiting_configuration" or needs_retry and ready and stage not in LOCAL_RETRY_STAGES else
                  "unsupported_failed_stage" if status == "failed" else "not_ready")
        return {"can_continue": can_continue, "can_retry": can_retry,
                "requires_explicit_retry": bool(needs_retry or failed_local), "reason": reason,
                "project_id": run["project_id"], "input_hash": run["input_hash"], "expected_revision": run["revision"]}

    def _answer(self, job, run, busy, duplicate=None):
        availability = self._availability(run, job, busy)
        answer = {"schema": SCHEMA, "enabled": True,
                  "job": _public_job(job, availability["can_retry"]), "availability": availability}
        if duplicate is not None:
            answer["duplicate"] = duplicate
        return answer

    def describe(self, run=None):
        self._fresh()
        snapshot = run if run is not None else _projection(self.project)
        # A projection/full inspector is only a convenience admission preview;
        # worker's sc_run_continue revalidates authoritative R data under its lock.
        if not isinstance(snapshot, dict) or not all(key in snapshot for key in ("project_id", "input_hash", "revision", "status", "stage")):
            raise StoreError("Continue availability needs a current run snapshot", 409)
        fd = _lock(self.lock_file)
        try:
            job = self._reconcile(_current(self.base), fd is not None)
            return self._answer(job, snapshot, fd is None)
        finally:
            if fd is not None:
                os.close(fd)

    def submit(self, payload):
        self.validate(payload)
        self._fresh()
        fd = _lock(self.lock_file)
        try:
            run = _projection(self.project)
            job = _current(self.base)
            request_path = self.base / "requests" / (hashlib.sha256(payload["request_id"].encode("utf-8")).hexdigest() + ".json")
            recorded = _read(request_path, optional=True)
            if recorded is not None:
                if set(recorded) != {"job_id", "payload_hash"} or recorded.get("payload_hash") != _payload_hash(payload):
                    raise StoreError("This Continue request ID was already used for different fields", 409)
                previous = _saved_job(self.base, recorded.get("job_id"))
                if any(previous[key] != payload[key] for key in ("project_id", "input_hash", "expected_revision", "retry")):
                    raise StoreError("Saved Continue request/job binding changed", 409)
                return self._answer(previous, run, fd is None, duplicate=True)
            if fd is None:
                if job is not None and job["status"] in ACTIVE and all(payload[key] == job[key] for key in ("project_id", "input_hash", "expected_revision", "retry")):
                    _once(request_path, {"job_id": job["job_id"], "payload_hash": _payload_hash(payload)})
                    return self._answer(job, run, True, duplicate=True)
                raise StoreError("A local continuation is active or locked; inspect it before submitting another request", 409)
            job = self._reconcile(job, True)
            for key, current in (("project_id", run["project_id"]), ("input_hash", run["input_hash"]), ("expected_revision", run["revision"])):
                if payload[key] != current:
                    raise StoreError("Continue snapshot is stale or belongs to another project/input; inspect again", 409)
            availability = self._availability(run, job, False)
            if not (availability["can_retry"] if payload["retry"] else availability["can_continue"]):
                raise StoreError("This saved run cannot continue with that retry choice; inspect its review/configuration or worker state", 409)
            job_id = secrets.token_hex(16)
            directory = self.base / "jobs" / job_id
            directory.mkdir(mode=0o700)
            config = {"schema": "scagentkit.run-continue.config.v1", "job_id": job_id,
                      "project": str(self.project), "project_identity": list(self.project_identity),
                      "base_identity": list(self.base_identity), "payload": payload, "payload_hash": _payload_hash(payload),
                      "subdirectory_identities": {name: list(value) for name, value in self.subdirectory_identities.items()},
                      "rscript": self.rscript, "library": self.library, "threads": self.threads,
                      "bridge": str(self.bridge), "worker": str(self.worker), "runtime": str(self.runtime),
                      "code_hashes": self.code_hashes}
            _atomic(directory / "config.json", config)
            job = {"schema": JOB_SCHEMA, "job_id": job_id, **payload,
                   "payload_hash": config["payload_hash"], "config_hash": _sha(directory / "config.json"),
                   "status": "queued", "created_at": _time(), "updated_at": _time(), "error": None,
                   "next_run_status": None, "next_run_stage": None, "next_run_revision": None}
            _atomic(directory / "job.json", job)
            # A replay may claim this request ID while the previous worker
            # releases its flock. Preserve that claim before publishing or
            # launching a new job; a conflict must leave current.json intact.
            _once(request_path, {"job_id": job_id, "payload_hash": _payload_hash(payload)})
            _atomic(self.base / "current.json", {"job_id": job_id})
            env = dict(os.environ)
            for name in KEYS:
                env.pop(name, None)
            env.update({name: str(self.threads) for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS")})
            if self.library:
                env["R_LIBS_USER"] = self.library
            try:
                process = subprocess.Popen([sys.executable, str(self.worker), str(directory / "config.json"),
                    job["config_hash"], str(fd)], env=env, stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    close_fds=True, pass_fds=(fd,), start_new_session=True, shell=False)
            except (OSError, ValueError) as problem:
                process = None
                job.update(status="failed", start_failed=True, updated_at=_time(),
                           error={"code": "worker_start_failed", "message": "The local worker could not start. Inspect the saved run, then explicitly retry."})
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
                threading.Thread(target=reap, name="scagentkit-continue-reaper", daemon=True).start()
                # A post-spawn disk failure is not a proven start failure: do
                # not claim that its owner is dead or enqueue a replacement.
                _atomic(directory / "launch.json", {"worker_pid": process.pid, "started_at": _time()})
            # Close this copy without LOCK_UN: the worker/R inherited the same
            # open-file description and must retain the interprocess flock.
            current = _read(directory / "job.json")
            return self._answer(current, run, current["status"] in ACTIVE, duplicate=False)
        finally:
            if fd is not None:
                os.close(fd)
