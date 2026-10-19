"""Allowlisted QC/strategy/annotation review for one selected local run."""
from __future__ import annotations

import hashlib
import math
from pathlib import PurePosixPath

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

    def annotation_plot(self, sha):
        """Serve only PNG bytes referenced by the freshly verified R review."""
        if not isinstance(sha, str) or not HASH.fullmatch(sha):
            raise StoreError("Select a saved annotation plot", 400)
        with self.lock:
            self._fresh()
            view = self.describe()
            records = (((view.get("run") or {}).get("annotation_review") or {}).get("details") or {}).get("plot_evidence") or {}
            plots = records.get("plots") or []
            matches = [row for row in plots if isinstance(row, dict) and row.get("sha256") == sha]
            if len(matches) != 1:
                raise StoreError("The plot is not part of the current reviewed annotation evidence", 404)
            relative = matches[0].get("path")
            if not isinstance(relative, str):
                raise StoreError("Saved plot path is invalid", 409)
            parts = PurePosixPath(relative)
            if parts.is_absolute() or ".." in parts.parts or len(parts.parts) != 4 or parts.parts[:2] != ("review-evidence", "annotation") or not parts.name.endswith(".png"):
                raise StoreError("Saved plot path is outside annotation evidence", 409)
            path = self.project
            for part in parts.parts:
                path = path / part
                if path.is_symlink():
                    raise StoreError("Saved plot path cannot contain a symlink", 409)
            if not path.is_file() or path.stat().st_size > 10 * 1024 * 1024:
                raise StoreError("Saved annotation PNG is unavailable or exceeds 10 MiB", 409)
            data = path.read_bytes()
            if not data.startswith(b"\x89PNG\r\n\x1a\n") or hashlib.sha256(data).hexdigest() != sha:
                raise StoreError("Saved annotation PNG changed; inspect the current review", 409)
            return data

    @staticmethod
    def validate_facts(facts):
        def obj(value, allowed, label):
            if not isinstance(value, dict) or not value or set(value) - set(allowed):
                raise StoreError(label + " requires a nonempty object with supported fields")

        def text(value, label, limit=4000):
            if not isinstance(value, str) or not value.strip() or len(value) > limit or "\x00" in value:
                raise StoreError(label + " requires bounded nonempty text")

        def boolean(value, label):
            if not isinstance(value, bool):
                raise StoreError(label + " requires a boolean")

        def number(value, label, upper, positive=False):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0 or value > upper or positive and (value == 0 or value == upper):
                raise StoreError(label + " requires a finite supported numeric value")

        obj(facts, {"columns", "batch", "doublet"}, "Facts")
        if "columns" in facts:
            obj(facts["columns"], {"sample", "qc_group", "capture", "batch", "donor", "condition", "group", "treatment"}, "Facts columns")
            for role, value in facts["columns"].items(): text(value, "columns." + role, 200)
        if "batch" in facts:
            obj(facts["batch"], {"technical_batch", "source"}, "Batch facts")
            if "technical_batch" in facts["batch"]: boolean(facts["batch"]["technical_batch"], "batch.technical_batch")
            if "source" in facts["batch"]: text(facts["batch"]["source"], "batch.source")
        if "doublet" in facts:
            d = facts["doublet"]
            obj(d, {"data_type", "technology", "input_source", "empty_droplets_removed", "full_called_cohort", "capture", "rate"}, "Doublet facts")
            for key in {"data_type", "technology", "input_source"} & set(d): text(d[key], "doublet." + key)
            for key in {"empty_droplets_removed", "full_called_cohort"} & set(d): boolean(d[key], "doublet." + key)
            if "capture" in d:
                obj(d["capture"], {"method", "column", "id", "source"}, "Capture facts")
                for key, value in d["capture"].items(): text(value, "doublet.capture." + key)
                if "method" in d["capture"] and d["capture"]["method"] not in {"column", "single"}:
                    raise StoreError("Unsupported capture method")
            if "rate" in d:
                rate = d["rate"]
                obj(rate, {"method", "value", "source", "sd"}, "Rate facts")
                for key in {"method", "source"} & set(rate): text(rate[key], "doublet.rate." + key)
                if "method" in rate and rate["method"] not in {"manual", "10x_standard"}:
                    raise StoreError("Unsupported rate method")
                if "sd" in rate: number(rate["sd"], "doublet.rate.sd", .5)
                if "value" in rate:
                    if isinstance(rate["value"], dict):
                        if not rate["value"]: raise StoreError("Expected-rate map cannot be empty")
                        for key, value in rate["value"].items():
                            text(key, "Capture ID", 200); number(value, "Expected rate", .5, True)
                    else: number(rate["value"], "Expected rate", .5, True)

    @staticmethod
    def validate(payload):
        if isinstance(payload, dict) and payload.get("action") == "prepare":
            required = {"action", "project_id", "input_hash", "expected_revision", "evidence_hash",
                        "proposal", "reviewer", "reason", "request_id"}
            if set(payload) != required:
                raise StoreError("Annotation preparation requires its exact evidence binding and complete proposal")
            for field in ("input_hash", "evidence_hash"):
                if not isinstance(payload[field], str) or not HASH.fullmatch(payload[field]):
                    raise StoreError("Annotation preparation requires exact SHA-256 fingerprints")
            revision = payload["expected_revision"]
            if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
                raise StoreError("expected_revision must be a nonnegative integer")
            for field, limit in (("project_id", 200), ("request_id", 200), ("reviewer", 200), ("reason", 4000)):
                value = payload[field]
                if not isinstance(value, str) or not value.strip() or len(value) > limit or "\x00" in value:
                    raise StoreError("Annotation preparation requires nonempty bounded " + field)
            if not isinstance(payload["proposal"], dict) or payload["proposal"].get("schema") != "scagentkit.annotation.v1":
                raise StoreError("Annotation preparation requires a typed annotation proposal")
            if len(canonical(payload).encode("utf-8")) > 1024 * 1024:
                raise StoreError("Annotation preparation exceeds 1 MB", 413)
            return
        common = {"action", "kind", "project_id", "input_hash", "proposal_hash", "review_hash",
                  "expected_revision", "reviewer", "reason"}
        if not isinstance(payload, dict) or not common <= set(payload):
            raise StoreError("Run review requires its exact project, input, proposal and review snapshot")
        action, kind = payload["action"], payload["kind"]
        if not isinstance(kind, str) or not isinstance(action, str) or kind not in {"qc", "strategy", "annotation"} or action not in {"approve", "reject", "revise", "preview", "undo", "facts"}:
            raise StoreError("Unsupported run review kind or action")
        if action == "preview" and kind != "qc" or action == "undo" and kind != "annotation":
            raise StoreError("Preview applies to QC; undo applies to executed annotation only")
        optional = {"proposal"} if action == "revise" else {"decision_id"} if action == "undo" else {"facts"} if action == "facts" else set()
        if kind == "qc" and action in {"revise", "preview"}: optional |= {"sensitivity", "gene_panels"}
        if set(payload) - (common | optional): raise StoreError("Run review has unsupported fields")
        if action == "facts":
            if kind != "strategy": raise StoreError("Facts apply only to the initial strategy review")
            RunReviewRuntime.validate_facts(payload.get("facts"))
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
