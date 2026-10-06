"""Read-only saved-run/evidence projection for one registered run scope.

No generic selection, journal, provider, user-supplied path or mutation lives
here. R verifies its authoritative envelope; ProjectLoader verifies the fixed
existing bundle against that same envelope's saved output receipts.
"""
from __future__ import annotations

import hashlib
import re
import tempfile
from pathlib import Path, PurePosixPath

try:
    from .qc_runtime import QCRuntime, ROOT, HASH
    from .project import ProjectLoader, ProjectError
    from .store import StoreError
    from .evidence import digest, strict_json
except ImportError:
    from qc_runtime import QCRuntime, ROOT, HASH
    from project import ProjectLoader, ProjectError
    from store import StoreError
    from evidence import digest, strict_json


def _sha(path):
    if path.is_symlink() or not path.is_file():
        raise StoreError("Saved workbench authority is missing or replaced", 409)
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class RunWorkbenchRuntime(QCRuntime):
    def __init__(self, project_dir, library=None, rscript="Rscript", timeout=120):
        super().__init__(project_dir, library, rscript, timeout)
        self.bridge = ROOT / "run_workbench_bridge.R"
        self.bridge_hash = hashlib.sha256(self.bridge.read_bytes()).hexdigest()
        self.projection = ROOT / "run_workbench_projection.R"
        self.projection_hash = hashlib.sha256(self.projection.read_bytes()).hexdigest()

    def _fresh(self):
        super()._fresh()
        if (self.projection.is_symlink()
                or hashlib.sha256(self.projection.read_bytes()).hexdigest() != self.projection_hash):
            raise StoreError("Saved display projection changed; restart and inspect", 409)

    def decide(self, *args, **kwargs):
        raise StoreError("Saved workbench history is read-only; use the explicit current review route", 403)

    def _bundle(self, run, saved):
        output = run.get("output")
        records = saved.get("bundle_records")
        if not output or not output.get("bundle"):
            if records:
                raise StoreError("Bundle receipts exist without the current output binding", 409)
            return None
        # Engine outputs are fixed under this run, never selected by an HTTP
        # path or by the unrelated generic workbench session.
        bundle = self.project / "bundle"
        declared = Path(output["bundle"])
        if declared != bundle or bundle.is_symlink() or not bundle.is_dir():
            raise StoreError("Current bundle is outside the configured run's fixed output scope", 409)
        if not isinstance(records, list) or not records:
            raise StoreError("Saved bundle has no authoritative output receipts", 409)
        if not isinstance(saved.get("bundle_scope_hash"), str) or not HASH.fullmatch(saved["bundle_scope_hash"]):
            raise StoreError("Saved bundle has no verified exact cell scope", 409)
        bound = {}
        for record in records:
            if not isinstance(record, dict) or set(record) != {"path", "sha256"}:
                raise StoreError("Invalid saved bundle receipt", 409)
            relative = PurePosixPath(record["path"])
            if (relative.is_absolute() or ".." in relative.parts or len(relative.parts) < 2
                    or relative.parts[0] != "bundle" or relative.as_posix() != record["path"]
                    or not isinstance(record["sha256"], str) or not HASH.fullmatch(record["sha256"])
                    or record["path"] in bound):
                raise StoreError("Saved bundle receipt has a foreign or duplicate scope", 409)
            path = self.project.joinpath(*relative.parts)
            if any(parent.is_symlink() for parent in path.parents if parent != self.project.parent):
                raise StoreError("Saved bundle receipt crosses a symlink", 409)
            if _sha(path) != record["sha256"]:
                raise StoreError("Saved bundle changed; refresh and inspect the coordinator", 409)
            bound[record["path"]] = record["sha256"]
        if not {"bundle/project.json", "bundle/manifest.json"} <= set(bound):
            raise StoreError("Bundle authority does not bind both project and manifest", 409)
        evidence = ProjectLoader(bundle).load()
        # Export's project ID is commonly the directory basename, whereas the
        # coordinator has a run-* ID. Bind them explicitly; do not conflate them.
        execution = evidence.get("parameters", {}).get("analysisExecution", {})
        for field, expected in (("inputHash", run["input_hash"]), ("configHash", run["config_hash"]),
                                ("implementationHash", run["implementation_hash"])):
            if execution.get(field) != expected:
                raise StoreError("Bundle source/configuration differs from this saved run", 409)
        for source in evidence.get("sources", []):
            relative = "bundle/" + source["id"]
            if bound.get(relative) != source["sha256"]:
                raise StoreError("Bundle evidence is not covered by this run's output receipts", 409)
        review = run.get("annotation_review") or {}
        details = review.get("details") or {}
        count = details.get("cell_count")
        if count is not None and count != evidence["identity"]["cellCount"]:
            raise StoreError("Bundle cells differ from the saved annotation scope", 409)
        # Recheck after loader parsing, closing the replacement/read race.
        for relative, digest in bound.items():
            if _sha(self.project / relative) != digest:
                raise StoreError("Bundle changed during read-only inspection", 409)
        return evidence

    def _stage_bundle(self, run, saved):
        stage = saved.get("stage_bundle")
        if stage is None:
            return None, None
        if (run.get("stage") not in {"annotation_propose", "annotation_apply"}
                or run.get("status") == "complete" or (run.get("output") or {}).get("bundle")
                or saved.get("bundle_records") or saved.get("bundle_scope_hash") is not None):
            raise StoreError("Saved stage snapshot conflicts with the current run/output scope", 409)
        if (not isinstance(stage, dict) or set(stage) != {"schema", "blobs", "checkpoint_records",
                "scope_hash", "bundle_scope_hash", "cell_count"}
                or stage.get("schema") != "scagentkit.saved-stage-bundle.v1"):
            raise StoreError("Invalid saved analysis snapshot", 409)
        records = stage["checkpoint_records"]
        if not isinstance(records, dict) or set(records) != {"analysis", "markers", "annotation_evidence"}:
            raise StoreError("Saved stage snapshot has no exact checkpoint authority", 409)
        for key in ("scope_hash", "bundle_scope_hash"):
            if not isinstance(stage[key], str) or not HASH.fullmatch(stage[key]):
                raise StoreError("Saved stage snapshot has no exact cell scope", 409)
        count = stage["cell_count"]
        if isinstance(count, bool) or not isinstance(count, int) or count < 1:
            raise StoreError("Saved stage snapshot has no exact cell count", 409)
        review = run.get("annotation_review") or {}
        if review and (review.get("cell_scope_hash") != stage["scope_hash"]
                or (review.get("details") or {}).get("cell_count") != count):
            raise StoreError("Saved stage cells differ from the current annotation review", 409)

        def check_records():
            for name, record in records.items():
                if (not isinstance(record, dict) or set(record) != {"path", "sha256"}
                        or not isinstance(record["path"], str)
                        or not re.fullmatch(r"checkpoints/" + name + r"-[a-f0-9]{64}\.rds", record["path"])
                        or not isinstance(record["sha256"], str) or not HASH.fullmatch(record["sha256"])):
                    raise StoreError("Saved analysis checkpoint has a foreign or invalid receipt", 409)
                path = self.project / record["path"]
                if (path.parent.is_symlink() or _sha(path) != record["sha256"]):
                    raise StoreError("Saved analysis checkpoint changed; inspect the registered run", 409)
        check_records()
        blobs = stage["blobs"]
        if (not isinstance(blobs, dict) or set(blobs) != {"project.json", "manifest.json"}
                or any(not isinstance(blob, str) for blob in blobs.values())
                or sum(len(blob.encode("utf-8")) for blob in blobs.values()) > 16 * 1024 * 1024):
            raise StoreError("Saved stage snapshot is not a bounded fixed bundle", 409)
        try:
            document = strict_json(blobs["project.json"])
        except (ValueError, TypeError, UnicodeError) as problem:
            raise StoreError("Saved stage snapshot has invalid UTF-8 JSON", 409) from problem
        expected = {"stateSHA": saved["state_sha256"], "inputHash": run["input_hash"],
            "configHash": run["config_hash"], "implementationHash": run["implementation_hash"],
            "revision": run["revision"], "historyHead": run.get("history_head"),
            "scopeHash": stage["scope_hash"], "bundleScopeHash": stage["bundle_scope_hash"], "records": records}
        if (not isinstance(document, dict) or not isinstance(document.get("parameters"), dict)
                or not isinstance(document.get("directed"), dict) or not isinstance(document.get("cells"), list)
                or any(not isinstance(cell, dict) for cell in document["cells"])
                or document.get("projectId") != run["project_id"]
                or document.get("parameters", {}).get("savedStageSnapshot") != expected
                or document.get("parameters", {}).get("analysisExecution") !=
                   {key: expected[key] for key in ("inputHash", "configHash", "implementationHash")}
                or "sourceAnnotation" in document or document.get("candidates") != [] or document.get("models") != []
                or document.get("directed", {}).get("clusters") not in ({}, [])
                or any(cell.get("qc") not in ({}, []) for cell in document.get("cells", []))):
            raise StoreError("Stage bundle is foreign, stale or contains unsupported private evidence", 409)
        # No cache is published into the run. The existing loader verifies the
        # manifest/digest, complete cells/membership and finite saved embedding.
        with tempfile.TemporaryDirectory(prefix="scagentkit-saved-evidence-") as temporary:
            directory = Path(temporary)
            for name, blob in blobs.items():
                (directory / name).write_bytes(blob.encode("utf-8"))
            try:
                evidence = ProjectLoader(directory).load()
            except ProjectError as problem:
                raise StoreError("Saved stage manifest or evidence failed verification", 409) from problem
        if evidence["identity"]["cellCount"] != count:
            raise StoreError("Stage bundle cells differ from the saved annotation scope", 409)
        check_records()
        return evidence, {"stage_checkpoint_records": records, "stage_records_hash": digest(records),
            "stage_scope_hash": stage["scope_hash"], "bundle_cell_scope_hash": stage["bundle_scope_hash"]}

    @staticmethod
    def _history(run, saved):
        history = saved.get("history")
        if not isinstance(history, dict) or history.get("schema") != "scagentkit.run-history.v1":
            raise StoreError("Saved workbench has no verified decision history", 409)
        events = history.get("events")
        if not isinstance(events, list) or len(events) != run["revision"]:
            raise StoreError("Saved history revision differs from the current run", 409)
        previous = "0" * 64
        for sequence, event in enumerate(events, 1):
            if isinstance(event, dict) and event.get("details") == []:
                event["details"] = {}  # jsonlite represents an empty R list as [].
            if (not isinstance(event, dict) or event.get("sequence") != sequence
                    or event.get("previous_hash") != previous
                    or not isinstance(event.get("hash"), str) or not HASH.fullmatch(event["hash"])
                    or not isinstance(event.get("details"), dict)
                    or not isinstance(event.get("action"), str)):
                raise StoreError("Saved history has a different sequence or hash chain", 409)
            previous = event["hash"]
        head = previous if events else None
        if history.get("head") != head or run.get("history_head") != head:
            raise StoreError("Saved history head differs from the inspected run", 409)
        return history

    def _integration_sha(self):
        directory = self.project / "reintegration"
        path = directory / "state.rds"
        if directory.is_symlink() or path.is_symlink():
            raise StoreError("Integration authority cannot cross a symlink", 409)
        return _sha(path) if path.exists() else None

    @staticmethod
    def _integration(run, saved):
        history = saved.get("integration_history")
        if history is None:
            if run.get("subcluster"):
                raise StoreError("Registered child has no verified separate integration projection", 409)
            return None
        if (not run.get("subcluster") or not isinstance(history, dict)
                or history.get("schema") != "scagentkit.subcluster.integration-history.v1"):
            raise StoreError("Integration history belongs to a different run scope", 409)
        revision = history.get("revision")
        if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
            raise StoreError("Integration history has no exact independent revision", 409)
        # Validate the transport's links/counts. R alone verifies the original
        # serialized hash algorithm and the immutable application artifacts.
        RunWorkbenchRuntime._history({"revision": revision, "history_head": history.get("head")},
            {"history": dict(history, schema="scagentkit.run-history.v1")})
        for event in history["events"]:
            child = event["details"].get("child_project_id")
            if child is not None and child != run["project_id"]:
                raise StoreError("Integration event belongs to a foreign child", 409)
            source = event["details"].get("child_input_hash")
            if source is not None and source != run["input_hash"]:
                raise StoreError("Integration event belongs to a different child input", 409)
        return history

    def describe(self):
        with self.lock:
            self._fresh()
            before = _sha(self.project / "state.rds")
            integration_before = self._integration_sha()
            view = super()._call("inspect")
            run = view["run"]
            revision = run.get("revision")
            if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
                raise StoreError("Saved workbench returned no exact revision", 409)
            for field in ("input_hash", "config_hash", "implementation_hash"):
                if not isinstance(run.get(field), str) or not HASH.fullmatch(run[field]):
                    raise StoreError("Saved workbench returned no exact source fingerprints", 409)
            saved = run.pop("workbench_projection", None)
            if (not isinstance(saved, dict) or saved.get("schema") != "scagentkit.workbench.saved.v1"
                    or saved.get("state_sha256") != before):
                raise StoreError("Run changed during saved workbench inspection", 409)
            history = self._history(run, saved)
            integration = self._integration(run, saved)
            if saved.get("integration_state_sha256") != integration_before:
                raise StoreError("Integration changed during saved inspection; refresh", 409)
            evidence = self._bundle(run, saved)
            stage_evidence, stage_binding = self._stage_bundle(run, saved)
            evidence_kind = "final_output_bundle" if evidence is not None else "saved_analysis_checkpoint" if stage_evidence is not None else "unavailable"
            if stage_evidence is not None:
                evidence = stage_evidence
            if _sha(self.project / "state.rds") != before:
                raise StoreError("Run changed while loading evidence; refresh this registered scope", 409)
            if self._integration_sha() != integration_before:
                raise StoreError("Integration changed while loading evidence; refresh", 409)
            source = saved.get("source") or {}
            reused = source.get("start_stage") == "processed"
            preview = run.get("qc_preview")
            summary = saved.get("qc_summary")
            qc_status = "processed_reused" if reused else "saved" if summary or preview else "not_recorded"
            annotation = run.get("annotation_review")
            strategy = run.get("strategy_review")
            cell_scope = (annotation or {}).get("cell_scope_hash")
            completed = run.get("completed") or []
            if isinstance(completed, str): completed = [completed]
            return {"schema": "scagentkit.workbench.v1", "readonly": True,
                "project": {key: run.get(key) for key in ("project_id", "input_hash", "revision", "history_head")},
                "run": run, "source": source, "provider": saved.get("provider"), "history": history,
                "integration_history": integration,
                "qc": {"status": qc_status, "reason": source.get("processed_reason") if reused else
                       "No saved QC evidence exists for this run." if qc_status == "not_recorded" else None,
                       "summary": summary, "preview": preview},
                "strategy": {"status": "saved" if strategy else "not_recorded", "review": strategy,
                             "summary": saved.get("strategy_summary")},
                "analysis": {"status": "processed_reused" if reused else
                             "executed" if "analysis" in completed else "not_executed",
                             "foundation_executed": False if reused else "analysis" in completed,
                             "parameters": (saved.get("analysis") or {}).get("parameters"),
                             "computed_diagnostics": run.get("computed_diagnostics")},
                "annotation": {"status": "saved" if annotation else "not_recorded", "review": annotation,
                               "summary": saved.get("annotation_summary")},
                "evidence": evidence,
                "evidence_kind": evidence_kind,
                "evidence_complete": evidence is not None,
                "detail_projection": saved.get("detail_projection"),
                "binding": {"project_id": run["project_id"], "state_sha256": before, "input_hash": run["input_hash"], "revision": run["revision"],
                    "history_head": run.get("history_head"), "bundle_digest": evidence["bundleDigest"] if evidence else None,
                    "source_fingerprint": evidence["sourceFingerprint"] if evidence else None,
                    "evidence_project_id": evidence["projectId"] if evidence else None, "cell_scope_hash": cell_scope,
                    "bundle_cell_scope_hash": stage_binding["bundle_cell_scope_hash"] if stage_binding else saved.get("bundle_scope_hash") if evidence else None,
                    "stage_checkpoint_records": stage_binding["stage_checkpoint_records"] if stage_binding else None,
                    "stage_records_hash": stage_binding["stage_records_hash"] if stage_binding else None,
                    "stage_scope_hash": stage_binding["stage_scope_hash"] if stage_binding else None,
                    "integration_state_sha256": integration_before,
                    "integration_revision": integration["revision"] if integration else None,
                    "integration_history_head": integration["head"] if integration else None},
                "outputs": {"artifacts": saved.get("artifacts") or [],
                            "scientific_result": (run.get("output") or {}).get("scientific_result")}}
