"""Allowlisted QC/strategy/annotation review for one selected local run."""
from __future__ import annotations

import hashlib

try:
    from .evidence import canonical
    from .qc_runtime import QCRuntime, ROOT, HASH
    from .store import StoreError
except ImportError:
    from evidence import canonical
    from qc_runtime import QCRuntime, ROOT, HASH
    from store import StoreError


class RunReviewRuntime(QCRuntime):
    """Reuse the bounded, shell-free IPC; R owns all scientific state changes."""
    def __init__(self, project_dir, library=None, rscript="Rscript", timeout=120):
        super().__init__(project_dir, library, rscript, timeout)
        self.bridge = ROOT / "run_review_bridge.R"
        self.bridge_hash = hashlib.sha256(self.bridge.read_bytes()).hexdigest()

    @staticmethod
    def validate(payload):
        common = {"action", "kind", "project_id", "input_hash", "proposal_hash", "review_hash",
                  "expected_revision", "reviewer", "reason"}
        if not isinstance(payload, dict) or not common <= set(payload):
            raise StoreError("Run review requires its exact project, input, proposal and review snapshot")
        action, kind = payload["action"], payload["kind"]
        if not isinstance(kind, str) or not isinstance(action, str) or kind not in {"qc", "strategy", "annotation"} or action not in {"approve", "reject", "revise", "preview", "undo"}:
            raise StoreError("Unsupported run review kind or action")
        if action == "preview" and kind != "qc" or action == "undo" and kind != "annotation":
            raise StoreError("Preview applies to QC; undo applies to executed annotation only")
        optional = {"proposal"} if action == "revise" else {"decision_id"} if action == "undo" else set()
        if kind == "qc" and action in {"revise", "preview"}: optional |= {"sensitivity", "gene_panels"}
        if set(payload) - (common | optional): raise StoreError("Run review has unsupported fields")
        if action == "revise" and ("proposal" not in payload or not isinstance(payload["proposal"], dict)):
            raise StoreError("Revision requires a supported typed proposal object")
        if action == "undo" and (not isinstance(payload.get("decision_id"), str) or not payload["decision_id"].strip() or len(payload["decision_id"]) > 200 or "\x00" in payload["decision_id"]):
            raise StoreError("Undo requires the exact executed annotation decision ID")
        for field in ("input_hash", "proposal_hash", "review_hash"):
            if not isinstance(payload[field], str) or not HASH.fullmatch(payload[field]):
                raise StoreError("Run review requires exact lowercase SHA-256 fingerprints")
        if not isinstance(payload["project_id"], str) or not payload["project_id"].strip() or len(payload["project_id"]) > 200 or "\x00" in payload["project_id"]:
            raise StoreError("Run review requires the literal project ID")
        revision = payload["expected_revision"]
        if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
            raise StoreError("expected_revision must be a nonnegative integer")
        for field, limit in (("reviewer", 200), ("reason", 4000)):
            value = payload[field]
            if not isinstance(value, str) or not value.strip() or len(value) > limit or "\x00" in value:
                raise StoreError("Run review %s must be nonempty text of at most %s characters" % (field, limit))
        if "sensitivity" in payload and payload["sensitivity"] is not None and not isinstance(payload["sensitivity"], list):
            raise StoreError("Sensitivity must be a typed JSON array")
        if "gene_panels" in payload and payload["gene_panels"] is not None and not isinstance(payload["gene_panels"], dict):
            raise StoreError("Gene panels must be a named JSON object")
        if len(canonical(payload).encode("utf-8")) > 1024 * 1024: raise StoreError("Run review request exceeds 1 MB", 413)

    def _call(self, operation, payload=None):
        result = super()._call(operation, payload)
        result["schema"] = "scagentkit.run-review.workbench.v1"
        result["boundary"] = "QC, analysis strategy and annotation review only. Approval saves a decision; execution requires explicit local continuation or R resume. No provider or raw matrix is served here."
        return result
