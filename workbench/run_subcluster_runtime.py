"""Fixed local subanalysis IPC. R owns provenance, locks and scientific writes."""
from __future__ import annotations

import hashlib
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

try:
    from .evidence import canonical, strict_json
    from .qc_runtime import QCRuntime, ROOT, HASH, MAX_RESULT
    from .run_review_runtime import RunReviewRuntime
    from .run_continue_runtime import RunContinueRuntime
    from .store import StoreError
except ImportError:
    from evidence import canonical, strict_json
    from qc_runtime import QCRuntime, ROOT, HASH, MAX_RESULT
    from run_review_runtime import RunReviewRuntime
    from run_continue_runtime import RunContinueRuntime
    from store import StoreError

KEYS = ("DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROK_API_KEY",
        "GOOGLE_API_KEY", "GEMINI_API_KEY", "AZURE_OPENAI_API_KEY", "COHERE_API_KEY", "MISTRAL_API_KEY",
        "OPENROUTER_API_KEY", "HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN")
CONTEXT_FIELDS = {"enabled", "lineage_hint", "identity_status", "tissue", "notes"}


def _context_edits(value):
    if not isinstance(value, dict) or not value or set(value) - CONTEXT_FIELDS:
        raise StoreError("Child context requires only the supported nonempty typed edit object")
    for name, item in value.items():
        if name == "enabled":
            if not isinstance(item, bool): raise StoreError("Child context enabled must be boolean")
        elif name == "identity_status":
            if not isinstance(item, str) or item not in {"labeled", "unknown", "mixed", "unreviewed"}:
                raise StoreError("Child context identity_status must be a supported soft hypothesis")
        elif item is not None:
            limit = 2000 if name == "notes" else 200
            allowed_controls = "\t\r\n" if name == "notes" else ""
            if (not isinstance(item, str) or not item.strip()
                    or any((ord(char) < 32 and char not in allowed_controls) or ord(char) == 127 for char in item)):
                raise StoreError("Child context %s must be bounded literal text or null" % name)
            try:
                length = len(item.encode("utf-8"))
            except UnicodeEncodeError:
                raise StoreError("Child context %s must be valid UTF-8 literal text" % name) from None
            if length > limit:
                raise StoreError("Child context %s exceeds %s UTF-8 bytes" % (name, limit))


def _text(value, name, limit=200):
    if not isinstance(value, str) or not value.strip() or len(value) > limit or any(ord(c) < 32 for c in value):
        raise StoreError("%s must be bounded nonempty literal text" % name)


def _revision(value, name):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise StoreError("%s must be a nonnegative integer" % name)


def _context_receipt(value, payload):
    child = value["child"]
    receipt = child.get("context_receipt")
    fields = {"schema", "action", "outcome", "request_id", "request_hash", "payload_sha256", "project_id", "input_hash",
              "expected_revision", "parent_scope_hash", "expected_parent_revision", "previous_context_hash", "context_hash",
              "generation", "committed_revision", "context", "reviewer", "reason", "journal_event_hash", "is_current"}
    problem = "Saved child context has no verified receipt for this exact request; inspect before retrying"
    if (not isinstance(receipt, dict) or set(receipt) != fields
            or receipt.get("schema") != "scagentkit.child-context-receipt.v1"
            or receipt.get("action") != "context" or receipt.get("outcome") != "committed"):
        raise StoreError(problem, 409)
    for name in ("request_id", "project_id", "input_hash", "expected_revision", "parent_scope_hash",
                 "expected_parent_revision", "context", "reviewer", "reason"):
        if canonical(receipt[name]) != canonical(payload[name]): raise StoreError(problem, 409)
    for name in ("request_hash", "payload_sha256", "input_hash", "parent_scope_hash", "previous_context_hash",
                 "context_hash", "journal_event_hash"):
        if not isinstance(receipt[name], str) or not HASH.fullmatch(receipt[name]): raise StoreError(problem, 409)
    payload_hash = hashlib.sha256((canonical(payload) + "\n").encode("utf-8")).hexdigest()
    if receipt["payload_sha256"] != payload_hash or receipt["previous_context_hash"] != payload["expected_context_hash"]:
        raise StoreError(problem, 409)
    for name in ("generation", "committed_revision"):
        if isinstance(receipt[name], bool) or not isinstance(receipt[name], int) or receipt[name] < 1:
            raise StoreError(problem, 409)
    run = child["run"]; current = run.get("child_context")
    if (not isinstance(current, dict) or current.get("schema") != "scagentkit.child-context.v1"
            or not isinstance(current.get("hash"), str) or not HASH.fullmatch(current["hash"])
            or isinstance(current.get("generation"), bool) or not isinstance(current.get("generation"), int)
            or isinstance(run.get("revision"), bool) or not isinstance(run.get("revision"), int)
            or receipt["committed_revision"] <= payload["expected_revision"]
            or run["revision"] < receipt["committed_revision"] or current["generation"] < receipt["generation"]
            or receipt["context_hash"] == receipt["previous_context_hash"]
            or not isinstance(receipt["is_current"], bool)
            or receipt["is_current"] != (current["hash"] == receipt["context_hash"])
            or (current["generation"] == receipt["generation"]) != receipt["is_current"]):
        raise StoreError(problem, 409)
    if receipt["is_current"]:
        effective = current.get("effective")
        if (current.get("previous_hash") != receipt["previous_context_hash"] or not isinstance(effective, dict)
                or any(name not in effective or canonical(effective[name]) != canonical(item)
                                                 for name, item in payload["context"].items())):
            raise StoreError(problem, 409)


class RunSubclusterRuntime(QCRuntime):
    def __init__(self, parent_project, workspace, library=None, rscript="Rscript", local_continue=False, timeout=120, inherit_model=False):
        super().__init__(parent_project, library, rscript, timeout)
        supplied = Path(workspace).expanduser()
        if supplied.is_symlink() or not supplied.is_dir():
            raise StoreError("Subanalysis workspace must be an existing nonsymlink directory")
        self.workspace = supplied.resolve()
        if self.workspace == self.project or self.project in self.workspace.parents or self.workspace in self.project.parents:
            raise StoreError("Subanalysis workspace must be separate from the original parent project")
        self.workspace_identity = (self.workspace.stat().st_dev, self.workspace.stat().st_ino)
        self.bridge = ROOT / "run_subcluster_bridge.R"
        self.bridge_hash = hashlib.sha256(self.bridge.read_bytes()).hexdigest()
        self.local_continue = bool(local_continue)
        if not isinstance(inherit_model, bool):
            raise StoreError("Operator child model inheritance must be boolean")
        self.inherit_model = inherit_model
        self.contexts = {}
        self.parent_frozen = False
        self.parent_frozen_binding = None

    def _fresh(self):
        super()._fresh()
        if hasattr(self, "workspace") and (self.workspace.is_symlink() or not self.workspace.is_dir()
                or (self.workspace.stat().st_dev, self.workspace.stat().st_ino) != self.workspace_identity):
            raise StoreError("Subanalysis workspace changed; restart and inspect", 409)

    @staticmethod
    def validate(payload):
        if (not isinstance(payload, dict) or not isinstance(payload.get("action"), str)
                or payload["action"] not in {"create", "unknown", "apply", "undo", "context"}):
            raise StoreError("Subanalysis action must be create, unknown, apply, undo or context")
        action = payload["action"]
        common = {"action", "reviewer", "reason", "request_id"}
        fields = {
            "create": {"parent_scope_hash", "expected_parent_revision", "clusters", "annotation_column", "choices"},
            "unknown": {"child_id", "project_id", "input_hash", "expected_revision"},
            "apply": {"child_id", "project_id", "input_hash", "expected_revision", "parent_scope_hash",
                      "expected_parent_revision", "annotation_hash", "apply_hash", "column", "outside"},
            "undo": {"child_id", "application_id", "project_id", "input_hash", "expected_revision", "integration_revision"},
            "context": {"child_id", "project_id", "input_hash", "expected_revision", "expected_context_hash",
                        "parent_scope_hash", "expected_parent_revision", "context"},
        }
        required = common | fields[action]
        optional = {"strategy_proposal"} if action == "create" else {"supersedes"} if action == "apply" else set()
        if not required <= set(payload) or set(payload) - required - optional:
            raise StoreError("Subanalysis request has missing or unsupported fields")
        for name in ("reviewer", "request_id"):
            _text(payload[name], name)
        _text(payload["reason"], "reason", 4000)
        for name in ("child_id", "project_id", "application_id", "annotation_column", "column"):
            if name in payload: _text(payload[name], name)
        if action != "create" and payload["child_id"] != payload["project_id"]:
            raise StoreError("Selected child ID and bound project ID differ", 409)
        for name in ("expected_revision", "expected_parent_revision", "integration_revision"):
            if name in payload: _revision(payload[name], name)
        for name in ("input_hash", "parent_scope_hash", "annotation_hash", "apply_hash", "expected_context_hash"):
            if name in payload and (not isinstance(payload[name], str) or not HASH.fullmatch(payload[name])):
                raise StoreError("%s requires an exact lowercase SHA-256 fingerprint" % name)
        if action == "create":
            labels = payload["clusters"]
            if not isinstance(labels, list) or not labels or len(labels) > 1000:
                raise StoreError("Select one or more explicit literal parent clusters")
            for label in labels: _text(label, "cluster label")
            if len(set(labels)) != len(labels): raise StoreError("Parent cluster selection contains duplicate literal labels")
            choices = payload["choices"]
            if not isinstance(choices, dict) or set(choices) != {"qc", "doublet", "batch", "cycle", "reference"}:
                raise StoreError("Declare all five child inheritance choices")
            supported = {"qc": {"retain_selected", "review"}, "doublet": {"keep"}, "batch": {"none", "review"},
                         "cycle": {"none", "recompute"}, "reference": {"none", "inherit"}}
            if any(not isinstance(value, str) or value not in supported[key] for key, value in choices.items()):
                raise StoreError("Unsupported explicit child inheritance choice")
            # The first browser increment supports the disclosed default choices.
            # Fresh cycle diagnostic configuration remains in headless R.
            if choices["cycle"] != "none":
                raise StoreError("Fresh cycle diagnostics require explicit headless R configuration")
            if "strategy_proposal" in payload and (not isinstance(payload["strategy_proposal"], dict)
                    or payload["strategy_proposal"].get("schema") != "scagentkit.strategy.v1"):
                raise StoreError("Optional child strategy must be the complete supported typed object")
            if "strategy_proposal" in payload:
                def unsafe(value):
                    if isinstance(value, dict):
                        return any(key.lower() in {"code", "r_code", "script", "provider", "chat_fn", "api_key", "rscript", "project_dir", "library"}
                                   or unsafe(item) for key, item in value.items())
                    return isinstance(value, list) and any(unsafe(item) for item in value)
                if unsafe(payload["strategy_proposal"]): raise StoreError("Strategy cannot contain code, providers or secret-bearing fields")
        if action == "apply":
            if payload["outside"] != "NA": raise StoreError("This version preserves unselected cells as explicit NA in the new columns")
            if payload.get("supersedes") is not None: _text(payload["supersedes"], "supersedes")
        if action == "context": _context_edits(payload["context"])
        if len(canonical(payload).encode("utf-8")) > 1024 * 1024: raise StoreError("Subanalysis request exceeds 1 MB", 413)

    def _call(self, operation, payload=None):
        self._fresh()
        with tempfile.TemporaryDirectory(prefix="scagentkit-subcluster-") as temporary:
            directory = Path(temporary)
            request, response = directory / "request.json", directory / "response.json"
            request.write_text(canonical(payload or {}) + "\n", encoding="utf-8")
            request.chmod(0o600)
            argv = [self.rscript, "--vanilla", str(self.bridge), operation, str(self.project), str(self.workspace), str(request), str(response)]
            if self.inherit_model:
                argv.append("true")
            env = dict(os.environ)
            for key in KEYS: env.pop(key, None)
            if self.library: env["R_LIBS_USER"] = self.library
            try:
                result = subprocess.run(argv, env=env, capture_output=True, timeout=self.timeout, shell=False)
            except subprocess.TimeoutExpired as problem:
                raise StoreError("Subanalysis bridge timed out; inspect saved child state before retrying", 409) from problem
            self._fresh()
            if response.is_symlink() or not response.is_file() or response.stat().st_size > MAX_RESULT:
                raise StoreError("Subanalysis bridge returned no bounded verified result", 409)
            answer = strict_json(response.read_text(encoding="utf-8"))
            if not isinstance(answer, dict) or set(answer) != {"ok", "result", "error"}:
                raise StoreError("Subanalysis bridge returned an invalid response", 409)
            if not answer["ok"] or result.returncode:
                raise StoreError(answer["error"] or "Subanalysis coordinator rejected this operation", 409)
            value = answer["result"]
            if not isinstance(value, dict) or value.get("schema") != "scagentkit.subcluster.bridge.v1":
                raise StoreError("Subanalysis bridge returned an unverified scope", 409)
            parent = value.get("parent")
            expected_schema = {"scagentkit.subcluster.parent.v1"}
            if operation == "readiness": expected_schema.add("scagentkit.subcluster.parent-waiting.v1")
            if not isinstance(parent, dict) or parent.get("schema") not in expected_schema:
                raise StoreError("Subanalysis bridge returned no verified parent binding", 409)
            if self.project_id is None: self.project_id = parent["parent_project_id"]
            elif self.project_id != parent.get("parent_project_id"):
                raise StoreError("Configured parent project was replaced; restart and inspect", 409)
            if operation == "operation" and payload.get("action") == "context":
                child = value.get("child")
                run = child.get("run") if isinstance(child, dict) else None
                origin = child.get("origin") if isinstance(child, dict) else None
                registered = value.get("children")
                if (parent.get("parent_scope_hash") != payload["parent_scope_hash"]
                        or parent.get("expected_parent_revision") != payload["expected_parent_revision"]
                        or not isinstance(child, dict) or child.get("schema") != "scagentkit.subcluster.child.v1"
                        or child.get("parent_current") is not True
                        or not isinstance(run, dict) or run.get("schema") != "scagentkit.run.v1"
                        or run.get("project_id") != payload["child_id"] or run.get("input_hash") != payload["input_hash"]
                        or not isinstance(origin, dict) or origin.get("parent_project_id") != self.project_id
                        or origin.get("parent_scope_hash") != payload["parent_scope_hash"]
                        or not isinstance(registered, list)
                        or sum(isinstance(item, dict) and item.get("project_id") == payload["child_id"] for item in registered) != 1):
                    raise StoreError("Saved child context returned a foreign or stale registered scope; inspect before retrying", 409)
                _context_receipt(value, payload)
            return value

    def _public(self, value):
        result = {key: item for key, item in value.items() if key != "child_path"}
        result["schema"] = "scagentkit.subcluster.workbench.v1"
        result["csrf_token"] = self.csrf_token
        result["local_continue"] = self.local_continue
        result["inherit_model"] = self.inherit_model
        result["boundary"] = "Independent child scope; original parent is read-only. R validates exact IDs and saves derived objects. Model inheritance is operator-selected; browser cannot configure a provider or matrix endpoint."
        return result

    def readiness(self):
        """Authoritative R readiness, with a one-way freeze for this service."""
        with self.lock:
            value = self._call("readiness")
            run = value.get("parent_run")
            if (not isinstance(run, dict) or run.get("schema") != "scagentkit.run.v1"
                    or run.get("project_id") != self.project_id
                    or not isinstance(value.get("ready"), bool)
                    or value["ready"] != (run.get("status") == "complete" and run.get("stage") == "complete")):
                raise StoreError("Parent lifecycle returned no verified run binding", 409)
            _revision(run.get("revision"), "parent revision")
            if not isinstance(run.get("input_hash"), str) or not HASH.fullmatch(run["input_hash"]):
                raise StoreError("Parent lifecycle returned no verified input fingerprint", 409)
            parent = value["parent"]
            if parent.get("expected_parent_revision") != run["revision"]:
                raise StoreError("Parent lifecycle changed while inspecting; refresh the registered scope", 409)
            if value["ready"] and (parent.get("input_hash") != run["input_hash"]
                    or not isinstance(parent.get("parent_scope_hash"), str)
                    or not HASH.fullmatch(parent["parent_scope_hash"])):
                raise StoreError("Completed parent scope and run fingerprints differ", 409)
            binding = (run.get("project_id"), run.get("input_hash"), run.get("revision"),
                       value["parent"].get("parent_scope_hash"))
            if self.parent_frozen and (not value["ready"] or binding != self.parent_frozen_binding):
                raise StoreError("Frozen parent changed; restart and inspect the source before writing", 409)
            if value["ready"]:
                self.parent_frozen = True
                self.parent_frozen_binding = binding
            result = self._public(value)
            result["frozen"] = self.parent_frozen
            if not value["ready"]:
                result["boundary"] = "Finish the configured parent review in this service. Registered child creation becomes available after its saved run is complete."
            return result

    def describe(self, child_id=None, column="sc_subtype", supersedes=None):
        if child_id is not None: _text(child_id, "child_id")
        _text(column, "column")
        if supersedes is not None: _text(supersedes, "supersedes")
        with self.lock:
            return self._public(self._call("inspect", {"child_id": child_id, "column": column, "supersedes": supersedes} if child_id else {}))

    def operate(self, payload, token):
        if not isinstance(token, str) or not secrets.compare_digest(token, self.csrf_token):
            raise StoreError("Subanalysis writes require this server's same-origin token", 403)
        self.validate(payload)
        with self.lock:
            return self._public(self._call("operation", payload))

    def child_context(self, child_id):
        _text(child_id, "child_id")
        with self.lock:
            # R verifies origin and registry on every request, even cached contexts.
            value = self._call("resolve", {"child_id": child_id})
            child = value.get("child")
            if not isinstance(child, dict) or child.get("schema") != "scagentkit.subcluster.child.v1" or child.get("run", {}).get("project_id") != child_id:
                raise StoreError("Resolved child inspector does not match selected literal project ID", 409)
            supplied = Path(value.get("child_path", ""))
            if not supplied.is_absolute() or supplied.is_symlink() or not supplied.is_dir() or supplied.resolve().parent != self.workspace:
                raise StoreError("Resolved child is outside the registered immediate workspace", 409)
            path = supplied.resolve()
            prior = self.contexts.get(child_id)
            if prior is not None and prior[0].project != path:
                raise StoreError("Registered child directory changed; restart and inspect", 409)
            if prior is None:
                review = RunReviewRuntime(path, self.library, self.rscript)
                review.project_id = child_id  # The R resolve above verified it.
                qc = QCRuntime(path, self.library, self.rscript)
                continuation = RunContinueRuntime(path, self.library, self.rscript) if self.local_continue else None
                prior = (review, continuation, qc)
                self.contexts[child_id] = prior
            return prior
