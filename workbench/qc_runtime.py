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
    from .evidence import canonical, strict_json
    from .store import StoreError
except ImportError:
    from evidence import canonical, strict_json
    from store import StoreError

ROOT = Path(__file__).resolve().parent
HASH = re.compile(r"[a-f0-9]{64}\Z")
MAX_RESULT = 64 * 1024 * 1024


class QCRuntime:
    def __init__(self, project_dir, library=None, rscript="Rscript", timeout=120):
        supplied = Path(project_dir).expanduser()
        if supplied.is_symlink() or not supplied.is_dir():
            raise StoreError("QC run project must be an existing nonsymlink directory")
        self.project = supplied.resolve()
        if (self.project / "state.rds").is_symlink() or not (self.project / "state.rds").is_file():
            raise StoreError("QC run project requires its authoritative local state.rds")
        self.library = os.pathsep.join(str(Path(entry).expanduser().resolve())
                                      for entry in library.split(os.pathsep) if entry) if library else None
        self.rscript = rscript
        self.timeout = timeout
        self.bridge = ROOT / "qc_bridge.R"
        self.bridge_hash = hashlib.sha256(self.bridge.read_bytes()).hexdigest()
        self.project_identity = (self.project.stat().st_dev, self.project.stat().st_ino)
        self.project_id = None
        self.csrf_token = secrets.token_urlsafe(32)
        self.lock = threading.RLock()

    def _fresh(self):
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
            env = dict(os.environ)
            for key in ("DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY",
                        "GOOGLE_API_KEY", "GEMINI_API_KEY", "AZURE_OPENAI_API_KEY", "COHERE_API_KEY",
                        "MISTRAL_API_KEY", "OPENROUTER_API_KEY", "HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN"):
                env.pop(key, None)
            if self.library:
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
