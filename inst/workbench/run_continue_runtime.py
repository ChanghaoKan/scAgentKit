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
    from .store import SECRET_NAMES, StoreError, scrub_secrets
except ImportError:
    from evidence import canonical, strict_json
    from store import SECRET_NAMES, StoreError, scrub_secrets

ROOT = Path(__file__).resolve().parent
SCHEMA = "scagentkit.run-continue.workbench.v1"
JOB_SCHEMA = "scagentkit.run-continue.job.v1"
RESTORE_SCHEMA = "scagentkit.run-continue.restoration.v1"
HASH = re.compile(r"[a-f0-9]{64}\Z")
JOB_ID = re.compile(r"[a-f0-9]{32}\Z")
ACTIVE = {"queued", "running"}
TERMINAL = {"succeeded", "failed", "interrupted"}
LOCAL_RETRY_STAGES = {"prefilter", "qc_evidence", "qc_apply", "analysis", "strategy_evidence", "strategy_apply", "strategy_selection", "strategy_preprocess", "strategy_basis", "strategy_batch", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence", "annotation_apply", "finalize"}
KEYS = SECRET_NAMES
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


def _directory_binding(base):
    def identity(path):
        path = _safe_directory(path)
        return [path.stat().st_dev, path.stat().st_ino]
    return {"project": str(base.parent), "project_identity": identity(base.parent),
            "base_identity": identity(base),
            "subdirectory_identities": {name: identity(base / name) for name in ("jobs", "requests")}}


def _config_binding(config):
    if not isinstance(config, dict):
        raise StoreError("Saved local continuation directory binding is invalid", 409)
    fields = ("project", "project_identity", "base_identity", "subdirectory_identities")
    binding = {name: config.get(name) for name in fields}
    identities = binding["subdirectory_identities"]
    if (not isinstance(binding["project"], str) or not Path(binding["project"]).is_absolute()
            or not isinstance(identities, dict) or set(identities) != {"jobs", "requests"}):
        raise StoreError("Saved local continuation directory binding is invalid", 409)
    for value in (binding["project_identity"], binding["base_identity"], *identities.values()):
        if (not isinstance(value, list) or len(value) != 2
                or any(isinstance(item, bool) or not isinstance(item, int) or item < 0 for item in value)):
            raise StoreError("Saved local continuation directory identity is invalid", 409)
    return binding


def _job_record(base, job_id):
    """Validate content without granting directory or execution authority."""
    directory = _job_directory(base, job_id)
    job = _read(directory / "job.json")
    if (job.get("schema") != JOB_SCHEMA or job.get("job_id") != job_id
            or not isinstance(job.get("status"), str)
            or job.get("status") not in ACTIVE | TERMINAL):
        raise StoreError("Invalid saved local continuation state", 409)
    config = _read(directory / "config.json")
    if (job.get("config_hash") != _sha(directory / "config.json")
            or config.get("job_id") != job["job_id"]
            or config.get("payload_hash") != _payload_hash(config.get("payload"))
            or job.get("payload_hash") != config["payload_hash"]):
        raise StoreError("Local continuation configuration changed; inspect before continuing", 409)
    RunContinueRuntime.validate(config.get("payload"))
    _config_binding(config)
    for field in ("project_id", "input_hash", "expected_revision", "request_id", "retry"):
        if job.get(field) != config["payload"].get(field):
            raise StoreError("Local continuation scope record changed", 409)
    return job, config


def _restoration(base):
    pointer = _read(base / "restoration.json", optional=True)
    if pointer is None:
        return None
    if set(pointer) != {"sha256"}:
        raise StoreError("Invalid continuation restoration pointer", 409)
    digest = pointer["sha256"]
    directory = _safe_directory(base / "restorations")
    current = None
    seen = set()
    while digest is not None:
        if not isinstance(digest, str) or not HASH.fullmatch(digest) or digest in seen:
            raise StoreError("Invalid continuation restoration history", 409)
        seen.add(digest)
        receipt = _read(directory / (digest + ".json"))
        if receipt.get("schema") != RESTORE_SCHEMA or _payload_hash(receipt) != digest:
            raise StoreError("Continuation restoration receipt changed", 409)
        _config_binding(receipt.get("target", {}))
        if not isinstance(receipt.get("jobs"), dict) or not isinstance(receipt.get("requests"), dict):
            raise StoreError("Invalid continuation restoration inventory", 409)
        if current is None:
            current = dict(receipt, sha256=digest)
        digest = receipt.get("previous_sha256")
    return current


def _job_hashes(base, job_id):
    directory = _job_directory(base, job_id)
    hashes = {}
    for name in ("job.json", "config.json", "request.json", "response.json",
                 "owner.json", "launch.json", "worker-exit.json"):
        path = directory / name
        if path.is_symlink() or path.exists() and not path.is_file():
            raise StoreError("Saved continuation artifact was replaced by a link or directory", 409)
        if path.exists():
            hashes[name] = _sha(path)
    return hashes


def _saved_job(base, job_id):
    job, config = _job_record(base, job_id)
    binding = _directory_binding(base)
    if _config_binding(config) == binding:
        return job
    receipt = _restoration(base)
    restored = (receipt or {}).get("jobs", {}).get(job_id)
    if (job["status"] not in TERMINAL or receipt is None or receipt["target"] != binding
            or restored != {"hashes": _job_hashes(base, job_id), "binding": _config_binding(config)}):
        raise StoreError("Saved local continuation belongs to a different project directory; "
                         "restore terminal jobs explicitly with run_continue_runtime.py restore", 409)
    # This receipt authorizes reading/replaying an immutable terminal record,
    # never executing its old config or bypassing the R coordinator's checks.
    return dict(job, restoration_sha256=receipt["sha256"])


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


def _restoration_owners_exited(base, job):
    if _owners_dead(base, job):
        return True
    directory = _job_directory(base, job["job_id"])
    owner = _read(directory / "owner.json", optional=True) or {}
    launch = _read(directory / "launch.json", optional=True) or {}
    exited = _read(directory / "worker-exit.json", optional=True) or {}
    # Exit receipts can distinguish an already reaped worker from a PID reused
    # by an unrelated process. They do not prove that all descendants stopped:
    # the operator must separately confirm that before restoring a backup.
    pid = owner.get("worker_pid", launch.get("worker_pid"))
    worker_done = (isinstance(pid, int) and not isinstance(pid, bool) and pid > 0
                   and exited.get("worker_pid") == pid
                   and isinstance(exited.get("exit_code"), int)
                   and not isinstance(exited.get("exit_code"), bool)
                   and isinstance(exited.get("finished_at"), str) and bool(exited["finished_at"]))
    r_done = (owner.get("r_pid") is None or
              isinstance(owner.get("r_exit_code"), int) and not isinstance(owner.get("r_exit_code"), bool)
              and isinstance(owner.get("r_finished_at"), str) and bool(owner["r_finished_at"]))
    return worker_done and r_done


def _public_job(job, retry_permitted=False):
    if job is None:
        return None
    fields = ("job_id", "status", "request_id", "project_id", "input_hash", "expected_revision", "retry",
              "created_at", "updated_at", "next_run_status", "next_run_stage", "next_run_revision", "error")
    result = {field: job.get(field) for field in fields}
    if job.get("restoration_sha256"):
        result["restoration_sha256"] = job["restoration_sha256"]
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

    def restore(self, reviewer, reason, *, original_workers_stopped=False):
        """Explicitly rebind terminal local jobs after a same-path backup restore.

        No R process, model request, scientific state write or approval occurs.
        Hashes are observed audit context, not an atomic R snapshot. A copied
        flock cannot prove that descendants on the original filesystem stopped.
        """
        if original_workers_stopped is not True:
            raise StoreError("Confirm that the original service, worker, R processes and their "
                             "descendants have stopped before restoring terminal jobs", 400)
        for name, value, limit in (("reviewer", reviewer, 200), ("reason", reason, 4000)):
            if (not isinstance(value, str) or not value.strip() or len(value) > limit
                    or any(ord(char) < 32 for char in value)):
                raise StoreError("Restoration requires bounded nonempty " + name, 400)
        self._fresh()
        fd = _lock(self.lock_file)
        if fd is None:
            raise StoreError("A local continuation still owns its lock; restoration was not performed", 409)
        try:
            previous = _restoration(self.base)
            snapshot = self._restore_snapshot(previous)
            if previous is not None and previous["target"] == snapshot["target"]:
                return {"schema": RESTORE_SCHEMA, "sha256": previous["sha256"],
                        "restored_jobs": len(previous["jobs"]), "boundary": previous["boundary"]}
            if all(record["binding"] == snapshot["target"] for record in snapshot["jobs"].values()):
                raise StoreError("Terminal jobs already match this directory; restoration is unnecessary", 409)
            receipt = dict(snapshot, schema=RESTORE_SCHEMA, created_at=_time(),
                           reviewer=reviewer, reason=reason,
                           previous_sha256=previous["sha256"] if previous else None,
                           original_workers_stopped=True,
                           boundary="Local terminal-job directory binding only. Hashes record an "
                                    "observed audit snapshot, not atomic R validation or proof that "
                                    "original processes stopped. R must still verify scientific state, "
                                    "checkpoints and approvals before continuation.")
            if len(canonical(receipt).encode("utf-8")) + 1 > MAX_JSON:
                raise StoreError("Restoration inventory exceeds the bounded local receipt size", 409)
            self._fresh()
            if snapshot != self._restore_snapshot(previous):
                raise StoreError("Project changed during restoration; no binding was published", 409)
            digest = _payload_hash(receipt)
            directory = _safe_directory(self.base / "restorations", create=True)
            _once(directory / (digest + ".json"), receipt)
            _atomic(self.base / "restoration.json", {"sha256": digest})
            return {"schema": RESTORE_SCHEMA, "sha256": digest,
                    "restored_jobs": len(snapshot["jobs"]), "boundary": receipt["boundary"]}
        finally:
            os.close(fd)

    def _restore_snapshot(self, previous):
        lock = self.project / ".run-lock"
        if lock.exists() or lock.is_symlink():
            raise StoreError("The R project lock must be resolved in R before restoring local jobs", 409)
        state_file = self.project / "state.rds"
        if state_file.is_symlink() or not state_file.is_file():
            raise StoreError("Restoration requires the unchanged local state.rds file", 409)
        run = _projection(self.project)
        jobs = {}
        bindings = []
        for directory in sorted((self.base / "jobs").iterdir()):
            job, config = _job_record(self.base, directory.name)
            if job["status"] not in TERMINAL:
                raise StoreError("Queued or running jobs cannot be restored; reconcile the original "
                                 "worker at its original directory before taking a terminal backup", 409)
            if not _restoration_owners_exited(self.base, job):
                raise StoreError("A recorded worker/R PID is alive or its exit cannot be established. "
                                 "Inspect the original processes, including possible PID reuse, "
                                 "before restoring terminal jobs", 409)
            binding = _config_binding(config)
            if binding["project"] != str(self.project):
                raise StoreError("Restore the backup at its recorded project path; project relocation "
                                 "and scientific path migration are not supported by this command", 409)
            if (job["project_id"] != run["project_id"] or job["input_hash"] != run["input_hash"]
                    or job["expected_revision"] > run["revision"]):
                raise StoreError("Restored jobs do not belong to the saved project/input/revision", 409)
            # Failed/interrupted responses can be malformed or foreign: that
            # may be why the worker failed. Preserve their bytes as evidence,
            # never reinterpret them as a successful scientific result.
            if job["status"] == "succeeded":
                result = _read(directory / "response.json")
                summary = (result or {}).get("result")
                if (set(result) != {"ok", "result", "error"} or result.get("ok") is not True
                        or not isinstance(summary, dict) or summary.get("schema") != "scagentkit.run.v1"
                        or summary.get("project_id") != run["project_id"]
                        or summary.get("input_hash") != run["input_hash"]
                        or not isinstance(summary.get("status"), str)
                        or summary.get("status") not in {"complete", "awaiting_review", "awaiting_configuration",
                                                        "failed", "rejected", "ready"}
                        or not isinstance(summary.get("stage"), str)
                        or isinstance(summary.get("revision"), bool)
                        or not isinstance(summary.get("revision"), int)
                        or not job["expected_revision"] <= summary["revision"] <= run["revision"]
                        or any(job.get("next_run_" + field) != summary.get(field)
                               for field in ("status", "stage", "revision"))):
                    raise StoreError("Restored worker result differs from the saved project or job", 409)
            record = {"hashes": _job_hashes(self.base, job["job_id"]), "binding": binding}
            old = (previous or {}).get("jobs", {}).get(job["job_id"])
            if previous and (old != record if old is not None else binding != previous["target"]):
                raise StoreError("Job changed since the previous restoration receipt", 409)
            jobs[job["job_id"]] = record
            bindings.append(binding)
        if not jobs:
            raise StoreError("There are no saved terminal continuation jobs to restore", 409)
        if previous is None and any(binding != bindings[0] for binding in bindings):
            raise StoreError("Saved jobs contain inconsistent original directory bindings", 409)
        if previous and set(previous["jobs"]) - set(jobs):
            raise StoreError("A previously restored job is missing", 409)
        pointer = _read(self.base / "current.json")
        if (set(pointer) != {"job_id"} or not isinstance(pointer["job_id"], str)
                or pointer["job_id"] not in jobs):
            raise StoreError("Current continuation pointer does not name a verified terminal job", 409)
        requests = {}
        for path in sorted((self.base / "requests").iterdir()):
            alias = _read(path)
            if (not re.fullmatch(r"[a-f0-9]{64}\.json", path.name)
                    or set(alias) != {"job_id", "payload_hash"} or not isinstance(alias["job_id"], str)
                    or alias["job_id"] not in jobs
                    or not isinstance(alias["payload_hash"], str) or not HASH.fullmatch(alias["payload_hash"])):
                raise StoreError("Restored request alias does not name a verified terminal job", 409)
            requests[path.name] = {"sha256": _sha(path), **alias}
        if previous and any(requests.get(name) != record for name, record in previous["requests"].items()):
            raise StoreError("A previously restored request alias changed or is missing", 409)
        for job_id in jobs:
            job, config = _job_record(self.base, job_id)
            name = hashlib.sha256(job["request_id"].encode("utf-8")).hexdigest() + ".json"
            alias = requests.get(name)
            if alias is None or alias["job_id"] != job_id or alias["payload_hash"] != config["payload_hash"]:
                raise StoreError("Restored job has no matching original request alias", 409)
        return {"target": _directory_binding(self.base), "jobs": jobs, "requests": requests,
                "current_job_id": pointer["job_id"], "project_id": run["project_id"],
                "input_hash": run["input_hash"], "revision": run["revision"],
                "observed_state_sha256": _sha(state_file),
                "observed_status_sha256": _sha(self.project / "status.json")}

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
        # The worker and its R child inherit the flock descriptor for their whole
        # lifetime, so acquiring it proves no owner is running. Do not let a
        # missing launch record or a reused PID keep the job active forever.
        if job is not None and job["status"] in ACTIVE and lock_held:
            job = dict(job, status="interrupted", updated_at=_time(), error={
                "code": "worker_interrupted", "message": "The local worker stopped. Inspect the saved run before explicitly retrying."})
            _atomic(_job_directory(self.base, job["job_id"]) / "job.json", job)
        return job

    def _availability(self, run, job, busy):
        status, stage = run["status"], run["stage"]
        needs_retry = job is not None and job["status"] in {"failed", "interrupted"}
        owners_dead = job is None or job["status"] == "succeeded" or not busy or _owners_dead(self.base, job)
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
            receipt = _restoration(self.base)
            protected_alias = (receipt or {}).get("requests", {}).get(request_path.name)
            if protected_alias is not None and (recorded is None or
                    protected_alias != {"sha256": _sha(request_path), **recorded}):
                raise StoreError("Restored Continue request alias changed or is missing", 409)
            if recorded is not None:
                if set(recorded) != {"job_id", "payload_hash"} or recorded.get("payload_hash") != _payload_hash(payload):
                    raise StoreError("This Continue request ID was already used for different fields", 409)
                previous = _saved_job(self.base, recorded.get("job_id"))
                if previous.get("restoration_sha256"):
                    receipt = _restoration(self.base)
                    expected = receipt["requests"].get(request_path.name)
                    if expected != {"sha256": _sha(request_path), **recorded}:
                        raise StoreError("Restored Continue request alias changed", 409)
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
            alias = {"job_id": job_id, "payload_hash": _payload_hash(payload)}
            try:
                _once(request_path, alias)
            except StoreError:
                # A competing replay may own this ID before publication. This
                # directory was never accepted, published or given to a worker.
                # Remove only our two known new files after proving another
                # claim won; retain ambiguous disk failures for inspection.
                claim = _read(request_path, optional=True)
                if claim is not None and claim != alias:
                    (directory / "job.json").unlink()
                    (directory / "config.json").unlink()
                    directory.rmdir()
                raise
            _atomic(self.base / "current.json", {"job_id": job_id})
            env = scrub_secrets(dict(os.environ))
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


def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser(description="Explicit local continuation metadata recovery; "
                                     "does not verify or alter scientific state.")
    commands = parser.add_subparsers(dest="command", required=True)
    restore = commands.add_parser("restore", help="Rebind only terminal jobs after restoring a backup "
                                  "at its original path; active jobs and project relocation are refused.")
    restore.add_argument("project", help="Project restored at its recorded absolute path")
    restore.add_argument("--reviewer", required=True)
    restore.add_argument("--reason", required=True)
    restore.add_argument("--confirm-original-stopped", action="store_true", required=True,
                         help="Confirm the original service, worker, R processes and all descendants "
                              "are stopped; a copied lock cannot establish this.")
    args = parser.parse_args(argv)
    try:
        result = RunContinueRuntime(args.project).restore(args.reviewer, args.reason,
                                                         original_workers_stopped=args.confirm_original_stopped)
    except (StoreError, OSError, ValueError) as problem:
        print(str(problem), file=sys.stderr)
        return 1
    print(canonical(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
