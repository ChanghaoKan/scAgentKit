"""Fixed local R bridge for a single explicitly configured sc_run project.

This adapter never accepts R code, executable paths, source paths or provider
configuration from HTTP. The R coordinator remains the state/lock authority.
"""
from __future__ import annotations

import hashlib
import os
import re
import secrets
import subprocess
import tempfile
import threading
from pathlib import Path

try:
    from .evidence import canonical, strict_json, PROJECT_FORMAT_VERSION, PROJECT_FORMAT_ERROR
    from .store import StoreError, scrub_secrets
except ImportError:
    from evidence import canonical, strict_json, PROJECT_FORMAT_VERSION, PROJECT_FORMAT_ERROR
    from store import StoreError, scrub_secrets

ROOT = Path(__file__).resolve().parent
HASH = re.compile(r"[a-f0-9]{64}\Z")
MAX_RESULT = 64 * 1024 * 1024
FORMAT_BRIDGE = ROOT / "project_format_bridge.R"
FORMAT_BRIDGE_HASH = hashlib.sha256(FORMAT_BRIDGE.read_bytes()).hexdigest()


def _check_project_state(project, library, rscript, timeout):
    """Read authoritative R state and parent formats without project writes."""
    if (FORMAT_BRIDGE.is_symlink() or not FORMAT_BRIDGE.is_file()
            or hashlib.sha256(FORMAT_BRIDGE.read_bytes()).hexdigest() != FORMAT_BRIDGE_HASH):
        raise StoreError("Project format bridge changed; restart and inspect", 409)
    names = {"PATH", "HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "TMP", "TEMP", "LANG", "TZ",
             "R_HOME", "R_LIBS", "R_LIBS_SITE", "R_LIBS_USER", "DYLD_FALLBACK_LIBRARY_PATH"}
    env = {name: value for name, value in os.environ.items() if name in names or name.startswith("LC_")}
    env.update({name: os.devnull for name in
                ("R_PROFILE", "R_PROFILE_USER", "R_ENVIRON", "R_ENVIRON_USER")})
    if library:
        env["R_LIBS"] = library
        env["R_LIBS_USER"] = library
    try:
        result = subprocess.run([str(rscript), "--vanilla", str(FORMAT_BRIDGE), str(project)],
            env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, timeout=timeout, shell=False)
    except (OSError, subprocess.TimeoutExpired) as problem:
        raise StoreError("Read-only project format verification failed. " + PROJECT_FORMAT_ERROR, 409) from problem
    if result.returncode != 0 or result.stdout != b"scagentkit.project-format.ok\n":
        raise StoreError(PROJECT_FORMAT_ERROR, 409)


def check_project_format(project, library=None, rscript="Rscript", timeout=120):
    """Check marker, authoritative state and parents before local project writes."""
    marker = Path(project) / "project-format.json"
    try:
        if marker.is_symlink() or not marker.is_file() or marker.stat().st_size > 4096:
            raise ValueError("Missing or invalid project format marker")
        value = strict_json(marker.read_text(encoding="utf-8"))
        if (not isinstance(value, dict) or set(value) != {"project_format_version"}
                or type(value["project_format_version"]) is not int
                or value["project_format_version"] != PROJECT_FORMAT_VERSION):
            raise ValueError("Unsupported project format")
    except (OSError, UnicodeError, ValueError) as problem:
        raise StoreError(PROJECT_FORMAT_ERROR, 409) from problem
    state = Path(project) / "state.rds"
    if state.is_symlink() or not state.is_file():
        raise StoreError("Authoritative local state.rds is required. " + PROJECT_FORMAT_ERROR, 409)
    _check_project_state(project, library, rscript, timeout)


class QCRuntime:
    def __init__(self, project_dir, library=None, rscript="Rscript", timeout=120):
        supplied = Path(project_dir).expanduser()
        if supplied.is_symlink() or not supplied.is_dir():
            raise StoreError("QC run project must be an existing nonsymlink directory")
        self.project = supplied.resolve()
        self.library = os.pathsep.join(str(Path(entry).expanduser().resolve())
                                      for entry in library.split(os.pathsep) if entry) if library else None
        self.rscript = rscript
        self.timeout = timeout
        check_project_format(self.project, self.library, self.rscript, self.timeout)
        self.bridge = ROOT / "qc_bridge.R"
        self.bridge_hash = hashlib.sha256(self.bridge.read_bytes()).hexdigest()
        self.project_identity = (self.project.stat().st_dev, self.project.stat().st_ino)
        self.project_id = None
        self.csrf_token = secrets.token_urlsafe(32)
        self.lock = threading.RLock()

    def _fresh(self):
        check_project_format(self.project, self.library, self.rscript, self.timeout)
        if (self.project.is_symlink() or not self.project.is_dir()
                or (self.project.stat().st_dev, self.project.stat().st_ino) != self.project_identity
                or self.bridge.is_symlink()
                or hashlib.sha256(self.bridge.read_bytes()).hexdigest() != self.bridge_hash):
            raise StoreError("QC project directory or bridge changed; restart and inspect before reviewing", 409)

    @staticmethod
    def validate(payload):
        common = {"action", "expected_revision", "proposal_hash", "preview_hash", "reviewer", "reason"}
        if not isinstance(payload, dict) or payload.get("action") not in {"approve", "reject", "revise", "preview"}:
            raise StoreError("QC action must be approve, reject, revise or preview")
        allowed = common | ({"proposal", "sensitivity", "gene_panels"} if payload["action"] == "revise"
                            else {"sensitivity", "gene_panels"} if payload["action"] == "preview" else set())
        if not common <= set(payload) or set(payload) - allowed:
            raise StoreError("QC request has missing or unsupported fields")
        if payload["action"] == "revise" and "proposal" not in payload:
            raise StoreError("Revising QC requires a typed proposal")
        for field in ("proposal_hash", "preview_hash"):
            if not isinstance(payload[field], str) or not HASH.fullmatch(payload[field]):
                raise StoreError("QC requests require exact proposal and preview SHA-256 fingerprints")
        revision = payload["expected_revision"]
        if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
            raise StoreError("expected_revision must be a nonnegative integer")
        for field, limit in (("reviewer", 200), ("reason", 4000)):
            value = payload[field]
            if not isinstance(value, str) or not value.strip() or len(value) > limit or "\x00" in value:
                raise StoreError("QC %s must be nonempty text of at most %s characters" % (field, limit))
        if "proposal" in payload and not isinstance(payload["proposal"], dict):
            raise StoreError("QC proposal must be a typed JSON object")
        if "sensitivity" in payload and payload["sensitivity"] is not None and not isinstance(payload["sensitivity"], list):
            raise StoreError("Sensitivity must be an explicit typed JSON array")
        if "gene_panels" in payload and payload["gene_panels"] is not None and not isinstance(payload["gene_panels"], dict):
            raise StoreError("Gene panels must be an explicit named JSON object")
        if len(canonical(payload).encode("utf-8")) > 1024 * 1024:
            raise StoreError("QC request exceeds 1 MB", 413)

    def _call(self, operation, payload=None):
        self._fresh()
        # Only a known bridge and two fixed operations become argv. Every HTTP
        # value is data in a private JSON file, never shell text or R source.
        with tempfile.TemporaryDirectory(prefix="scagentkit-qc-") as temporary:
            directory = Path(temporary)
            request = directory / "request.json"
            output = directory / "response.json"
            request.write_text(canonical(payload or {}) + "\n", encoding="utf-8")
            request.chmod(0o600)
            argv = [self.rscript, "--vanilla", str(self.bridge), operation, str(self.project), str(request), str(output)]
            env = scrub_secrets(dict(os.environ))
            if self.library:
                env["R_LIBS"] = self.library
                env["R_LIBS_USER"] = self.library
            try:
                result = subprocess.run(argv, env=env, capture_output=True, timeout=self.timeout, shell=False)
            except subprocess.TimeoutExpired as problem:
                raise StoreError("QC bridge exceeded its time limit. Inspect the saved run before submitting again", 409) from problem
            self._fresh()
            if output.is_symlink() or not output.is_file() or output.stat().st_size > MAX_RESULT:
                raise StoreError("QC bridge returned no bounded verified result; inspect the saved run", 409)
            answer = strict_json(output.read_text(encoding="utf-8"))
            if not isinstance(answer, dict) or set(answer) != {"ok", "result", "error"}:
                raise StoreError("QC bridge returned an invalid response", 409)
            if not answer["ok"] or result.returncode:
                # Fixed bridge emits coordinator errors, never stdout/stderr or
                # inherited environment values. Do not log request bodies.
                raise StoreError(answer["error"] or "QC coordinator rejected this operation", 409)
            run = answer["result"]
            if not isinstance(run, dict) or run.get("schema") != "scagentkit.run.v1" or not isinstance(run.get("project_id"), str):
                raise StoreError("QC bridge result is not a verified sc_run inspector", 409)
            if self.project_id is None:
                self.project_id = run["project_id"]
            elif run["project_id"] != self.project_id:
                raise StoreError("The configured QC run was replaced; restart and inspect the new project", 409)
            return {"schema": "scagentkit.qc.workbench.v1", "run": run,
                    "csrf_token": self.csrf_token,
                    "boundary": "QC preview and decisions only. Resume analysis explicitly in R; no provider is configured here."}

    def describe(self):
        with self.lock:
            return self._call("inspect")

    def decide(self, payload, token):
        if not isinstance(token, str) or not secrets.compare_digest(token, self.csrf_token):
            raise StoreError("QC writes require this server's same-origin review token", 403)
        self.validate(payload)
        with self.lock:
            return self._call("decision", payload)
