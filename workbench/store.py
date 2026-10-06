"""Append-only local review ledger, with content scopes and portable handoffs."""
from __future__ import annotations

import copy
import fcntl
import json
import math
import os
import re
import tempfile
import threading
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

try:
    from .evidence import ALLOWED_FILES, DATASET_ID, canonical, digest, revision_for, snapshot, strict_json
except ImportError:
    from evidence import ALLOWED_FILES, DATASET_ID, canonical, digest, revision_for, snapshot, strict_json

FORMAT = "scagentkit.workbench.handoff.v1"
DIRECTED_FORMAT = "scagentkit.workbench.handoff.v2"
# Leave room for the {"package": ...} HTTP import wrapper. Export uses compact JSON.
MAX_SESSION_BYTES = 32 * 1024 * 1024 - 1024
ZERO_HASH = "0" * 64
HASH_RE = re.compile(r"^[a-f0-9]{64}$")
DIMENSIONS = ("type", "state", "QC")
STATUSES = ("proposed", "reviewed", "accepted")


def portable_content(value):
    """Keep capsule numbers stable across Python and browser JSON round trips.

    JSON has one numeric type. Integral safe floats become integers before
    hashing; unusually large numbers are refused rather than rounded by JS.
    This applies only to new evidence capsules, never existing event hashes.
    """
    if isinstance(value, dict):
        return {key: portable_content(item) for key, item in value.items()}
    if isinstance(value, list):
        return [portable_content(item) for item in value]
    if type(value) in (int, float):
        if abs(value) > 9007199254740991 or not math.isfinite(value):
            raise StoreError("Directed capsule contains a number outside the portable JSON range")
        if isinstance(value, float) and value.is_integer():
            return int(value)
    return value


class StoreError(ValueError):
    def __init__(self, message, status=422):
        super().__init__(message)
        self.status = status


def _plain(value, name, maximum=2000):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        raise StoreError("%s must be a non-empty string of at most %s characters" % (name, maximum))
    if any(ord(character) < 32 and character not in "\n\t" for character in value):
        raise StoreError("%s contains unsupported control characters" % name)
    return value.strip()


def _scope_key(scope):
    return (scope["revision"], scope["datasetId"], scope["clusterId"], scope["dimension"])


def _empty():
    return {"format": FORMAT, "datasetId": DATASET_ID, "revisions": {}, "events": []}


def _replay(events):
    undone = {event["targetEventId"] for event in events if event["kind"] == "undo"}
    current = {}
    for event in events:
        if event["kind"] == "decision" and event["id"] not in undone:
            current[_scope_key(event["scope"])] = event
    return current, undone


def validate_package(package, current_evidence=None):
    if not isinstance(package, dict):
        raise StoreError("Unrecognized handoff package structure")
    version = package.get("format")
    fields = {"format", "datasetId", "revisions", "events"}
    if version == DIRECTED_FORMAT:
        fields.add("artifacts")
    if set(package) != fields:
        raise StoreError("Unrecognized handoff package structure")
    if version not in (FORMAT, DIRECTED_FORMAT) or package["datasetId"] != DATASET_ID:
        raise StoreError("Handoff format or dataset does not match")
    artifacts = package.get("artifacts", {})
    if not isinstance(artifacts, dict) or len(artifacts) > 1000:
        raise StoreError("Invalid directed evidence artifacts")
    for identity, artifact in artifacts.items():
        if (not isinstance(identity, str) or not HASH_RE.fullmatch(identity)
                or not isinstance(artifact, dict)
                or set(artifact) != {"kind", "id", "sha256", "content"}
                or artifact["kind"] != "directed_proposal" or artifact["id"] != identity
                or artifact["sha256"] != identity
                or identity not in (digest(portable_content(artifact["content"])), digest(artifact["content"]))):
            raise StoreError("Invalid directed evidence artifact identity / hash")
        content = artifact["content"]
        required = {"schemaVersion", "clusterId", "revision", "sourceHash", "extractorHash", "taxonomyHash", "bundleHash", "planHash", "provisional"}
        if (not isinstance(content, dict) or set(content) != required or content["schemaVersion"] != 1
                or content["clusterId"] != "6" or not isinstance(content["provisional"], dict)
                or any(not isinstance(content[name], str) or not HASH_RE.fullmatch(content[name])
                       for name in ("revision", "sourceHash", "extractorHash", "taxonomyHash", "bundleHash", "planHash"))):
            raise StoreError("Invalid directed evidence artifact content")
    revisions = package["revisions"]
    if not isinstance(revisions, dict) or len(revisions) > 200:
        raise StoreError("Invalid revision snapshots")
    for revision, record in revisions.items():
        if not isinstance(revision, str) or not HASH_RE.fullmatch(revision):
            raise StoreError("Invalid evidence revision")
        if not isinstance(record, dict) or set(record) != {"datasetId", "sources", "cellGroups"}:
            raise StoreError("Invalid revision snapshot shape")
        if record["datasetId"] != DATASET_ID or not isinstance(record["sources"], list):
            raise StoreError("Invalid revision source references")
        seen_sources = set()
        for source in record["sources"]:
            if not isinstance(source, dict) or set(source) != {"id", "sha256"}:
                raise StoreError("Invalid source reference")
            if not isinstance(source["id"], str) or not source["id"] or source["id"] in seen_sources:
                raise StoreError("Duplicate or invalid source reference")
            if not isinstance(source["sha256"], str) or not HASH_RE.fullmatch(source["sha256"]):
                raise StoreError("Invalid source content hash")
            seen_sources.add(source["id"])
        if seen_sources != set(ALLOWED_FILES) or revision_for(record["sources"]) != revision:
            raise StoreError("Revision does not match its source content hashes")
        groups = record["cellGroups"]
        if not isinstance(groups, dict) or set(groups) != {str(i) for i in range(9)}:
            raise StoreError("Invalid revision cluster references")
        cells = set()
        for cluster_id, cell_ids in groups.items():
            if not isinstance(cell_ids, list) or not cell_ids or any(not isinstance(value, str) or not value for value in cell_ids):
                raise StoreError("Invalid cell scope")
            if cell_ids != sorted(set(cell_ids)) or cells.intersection(cell_ids):
                raise StoreError("Duplicate or unordered cell scope")
            cells.update(cell_ids)
        if len(cells) != 2638 or len(groups["6"]) != 155:
            raise StoreError("Revision snapshot has unexpected retained cell counts")
        if current_evidence and revision == current_evidence["revision"] and record != snapshot(current_evidence):
            raise StoreError("Revision cell scope differs from current evidence")

    events = package["events"]
    if not isinstance(events, list) or len(events) > 10000:
        raise StoreError("Invalid event history")
    by_id, request_ids, undone, active = {}, set(), set(), {}
    previous_hash = ZERO_HASH
    for sequence, event in enumerate(events, 1):
        required = {"id", "sequence", "kind", "createdAt", "requestId", "requestDigest", "scope", "reason", "prevHash", "hash"}
        if not isinstance(event, dict):
            raise StoreError("Event must be an object")
        kind = event.get("kind")
        if kind == "decision":
            required |= {"label", "status", "supersedes"}
            if "evidenceRefs" in event and version == DIRECTED_FORMAT:
                required.add("evidenceRefs")
        elif kind == "undo":
            required |= {"targetEventId"}
        else:
            raise StoreError("Unknown event kind")
        if set(event) != required:
            raise StoreError("Invalid event structure")
        try:
            if not isinstance(event["id"], str) or str(uuid.UUID(event["id"])) != event["id"]:
                raise ValueError("Noncanonical event ID")
            datetime.fromisoformat(event["createdAt"].replace("Z", "+00:00"))
        except (ValueError, TypeError, AttributeError):
            raise StoreError("Invalid event identity or time") from None
        if event["id"] in by_id or type(event["sequence"]) is not int or event["sequence"] != sequence:
            raise StoreError("Duplicate event ID or invalid sequence")
        if _plain(event["requestId"], "requestId", 160) != event["requestId"]:
            raise StoreError("Event request ID is not canonical")
        if event["requestId"] in request_ids:
            raise StoreError("Duplicate request ID")
        if not isinstance(event["requestDigest"], str) or not HASH_RE.fullmatch(event["requestDigest"]):
            raise StoreError("Invalid request digest")
        if event["prevHash"] != previous_hash or event["hash"] != digest({key: value for key, value in event.items() if key != "hash"}):
            raise StoreError("Event hash chain is damaged")
        _plain(event["reason"], "reason", 4000)
        scope = event["scope"]
        if not isinstance(scope, dict) or set(scope) != {"datasetId", "revision", "clusterId", "dimension", "cellIds"}:
            raise StoreError("Invalid event scope structure")
        if (not all(isinstance(scope[field], str) for field in ("datasetId", "revision", "clusterId", "dimension"))
                or scope["datasetId"] != DATASET_ID or scope["revision"] not in revisions or scope["dimension"] not in DIMENSIONS):
            raise StoreError("Invalid dataset / revision / dimension reference")
        groups = revisions[scope["revision"]]["cellGroups"]
        if scope["clusterId"] not in groups or scope["cellIds"] != groups[scope["clusterId"]]:
            raise StoreError("Event cell IDs do not exactly match its cluster scope")
        key = _scope_key(scope)
        if kind == "decision":
            _plain(event["label"], "label", 160)
            if event["status"] not in STATUSES:
                raise StoreError("Invalid workflow status")
            if "evidenceRefs" in event:
                references = event["evidenceRefs"]
                if not isinstance(references, list) or not references or len(references) > 8:
                    raise StoreError("Invalid directed evidence references")
                seen = set()
                for reference in references:
                    if (not isinstance(reference, dict) or set(reference) != {"kind", "id", "sha256"}
                            or reference["kind"] != "directed_proposal" or not isinstance(reference["id"], str)
                            or reference["id"] in seen or reference["id"] not in artifacts
                            or reference != {key: artifacts[reference["id"]][key] for key in ("kind", "id", "sha256")}):
                        raise StoreError("Invalid or duplicate directed evidence reference")
                    content = artifacts[reference["id"]]["content"]
                    if content["revision"] != scope["revision"] or content["clusterId"] != scope["clusterId"] or scope["dimension"] != "type":
                        raise StoreError("Directed evidence reference is outside this decision scope")
                    seen.add(reference["id"])
            expected_previous = active.get(key)
            if event["supersedes"] != expected_previous:
                raise StoreError("Decision supersedes reference is not the active decision in its scope")
            active[key] = event["id"]
        else:
            _plain(event["targetEventId"], "targetEventId", 64)
            target = by_id.get(event["targetEventId"])
            if not target or target["kind"] != "decision" or target["scope"] != scope or target["id"] in undone:
                raise StoreError("Invalid or duplicate undo target reference")
            undone.add(target["id"])
            history = [item for item in by_id.values() if item["kind"] == "decision" and _scope_key(item["scope"]) == key and item["id"] not in undone]
            if history:
                active[key] = history[-1]["id"]
            else:
                active.pop(key, None)
        by_id[event["id"]] = event
        request_ids.add(event["requestId"])
        previous_hash = event["hash"]
    return package


class SessionStore:
    def __init__(self, path):
        self.path = Path(path).expanduser().resolve()
        self.lock = threading.RLock()
        self.integrity_error = None
        self._last_valid = _empty()

    @contextmanager
    def _locked(self):
        with self.lock:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with self.path.with_suffix(self.path.suffix + ".lock").open("a") as lockfile:
                fcntl.flock(lockfile.fileno(), fcntl.LOCK_EX)
                try:
                    yield
                finally:
                    fcntl.flock(lockfile.fileno(), fcntl.LOCK_UN)

    def _load(self, evidence=None):
        if not self.path.exists():
            package = _empty()
        else:
            if self.path.stat().st_size > MAX_SESSION_BYTES:
                raise StoreError("Session history exceeds the local size limit")
            try:
                package = strict_json(self.path.read_text(encoding="utf-8"))
            except (OSError, ValueError, UnicodeError) as error:
                raise StoreError("Cannot read session history: %s" % error) from error
        validate_package(package, evidence)
        self._last_valid = copy.deepcopy(package)
        self.integrity_error = None
        return package

    def _write(self, package):
        validate_package(package)
        encoded = (canonical(package) + "\n").encode("utf-8")
        if len(encoded) > MAX_SESSION_BYTES:
            raise StoreError("Session would exceed the local size limit. Existing history is unchanged; export it and continue with a separate session file", 413)
        fd, temporary = tempfile.mkstemp(prefix=".%s." % self.path.name, dir=str(self.path.parent))
        try:
            with os.fdopen(fd, "wb") as output:
                output.write(encoded)
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, self.path)
            directory = os.open(str(self.path.parent), os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        self._last_valid = copy.deepcopy(package)

    @staticmethod
    def _view(package, evidence, integrity_error=None, evidence_error=None):
        revision = evidence["revision"] if evidence and not evidence_error else None
        current, undone = _replay(package["events"])
        registry = evidence.get("directedArtifacts", {}) if evidence and not evidence_error else {}
        def is_stale(event):
            return event["scope"]["revision"] != revision or any(reference["id"] not in registry for reference in event.get("evidenceRefs", []))
        events = [dict(event, stale=is_stale(event),
                       undone=event["id"] in undone) for event in package["events"]]
        decisions = [dict(event, stale=is_stale(event), undone=False)
                     for event in current.values()]
        return {"schemaVersion": 1, "revision": revision, "datasetId": DATASET_ID,
                "events": events, "decisions": decisions,
                "readOnly": bool(integrity_error or evidence_error or not evidence),
                "integrityError": integrity_error, "evidenceError": evidence_error,
                "headHash": package["events"][-1]["hash"] if package["events"] else ZERO_HASH}

    def session(self, evidence=None, evidence_error=None):
        with self._locked():
            try:
                package = self._load(evidence)
            except (StoreError, OSError, ValueError, TypeError, KeyError, RecursionError) as error:
                self.integrity_error = str(error)
                package = self._last_valid
            return self._view(package, evidence, self.integrity_error, evidence_error)

    def export(self, evidence):
        with self._locked():
            try:
                return copy.deepcopy(self._load(evidence))
            except (StoreError, OSError) as error:
                raise StoreError("Damaged history cannot be exported as a verified handoff: %s" % error, 409) from error

    def import_package(self, incoming, evidence):
        with self._locked():
            validate_package(incoming, evidence)
            existing = self._load(evidence)
            # Import can append an existing verified history or initialize an empty store.
            # It must never erase or replace an already recorded decision.
            prior = existing["events"]
            if len(incoming["events"]) < len(prior) or incoming["events"][:len(prior)] != prior:
                raise StoreError("Import conflicts with immutable local history; use a separate empty session file", 409)
            if any(incoming["revisions"].get(key) != value for key, value in existing["revisions"].items()):
                raise StoreError("Import changes a recorded revision snapshot", 409)
            if any(incoming.get("artifacts", {}).get(key) != value for key, value in existing.get("artifacts", {}).items()):
                raise StoreError("Import changes a recorded directed evidence capsule", 409)
            self._write(copy.deepcopy(incoming))
            return self._view(incoming, evidence)

    def _mutate(self, kind, payload, evidence):
        if not isinstance(payload, dict):
            raise StoreError("Request must be a JSON object")
        fields = {"revision", "requestId", "reason"}
        fields |= {"clusterId", "dimension", "label", "status"} if kind == "decision" else {"targetEventId"}
        if kind == "decision" and "evidenceRefs" in payload:
            fields.add("evidenceRefs")
        if set(payload) != fields:
            raise StoreError("Missing or unexpected %s request fields" % kind)
        request_id = _plain(payload["requestId"], "requestId", 160)
        reason = _plain(payload["reason"], "reason", 4000)
        request_digest = digest({"kind": kind, "payload": payload})
        with self._locked():
            package = self._load(evidence)
            for event in package["events"]:
                if event["requestId"] == request_id:
                    if event["requestDigest"] != request_digest:
                        raise StoreError("requestId was already used for different input", 409)
                    return self._view(package, evidence)
            if payload["revision"] != evidence["revision"]:
                raise StoreError("Evidence revision changed. Refresh and review the new evidence before writing", 409)
            current, undone = _replay(package["events"])
            if kind == "decision":
                cluster_id = _plain(payload["clusterId"], "clusterId", 32)
                dimension = payload["dimension"]
                if dimension not in DIMENSIONS or payload["status"] not in STATUSES:
                    raise StoreError("Invalid dimension or workflow status")
                label = _plain(payload["label"], "label", 160)
                if label.lower() == "unknown":
                    label = "unknown"
                cluster = next((row for row in evidence["clusters"] if row["id"] == cluster_id), None)
                if cluster is None:
                    raise StoreError("Cluster does not exist in current evidence")
                scope = {"datasetId": DATASET_ID, "revision": evidence["revision"], "clusterId": cluster_id,
                         "dimension": dimension, "cellIds": list(cluster["cellIds"])}
                previous = current.get(_scope_key(scope))
                fields = {"label": label, "status": payload["status"], "supersedes": previous["id"] if previous else None}
                if "evidenceRefs" in payload:
                    references = payload["evidenceRefs"]
                    registry = evidence.get("directedArtifacts", {})
                    if not isinstance(references, list) or not references or len(references) > 8:
                        raise StoreError("A current directed evidence reference is required")
                    for reference in references:
                        if (not isinstance(reference, dict) or set(reference) != {"kind", "id", "sha256"}
                                or not isinstance(reference.get("id"), str) or reference["id"] not in registry
                                or reference != {key: registry[reference["id"]][key] for key in ("kind", "id", "sha256")}):
                            raise StoreError("Directed evidence changed. Refresh and inspect the new proposal before recording", 409)
                        if registry[reference["id"]]["content"]["clusterId"] != cluster_id or dimension != "type":
                            raise StoreError("Directed evidence reference is outside this decision scope")
                    package["format"] = DIRECTED_FORMAT
                    package.setdefault("artifacts", {}).update({reference["id"]: copy.deepcopy(registry[reference["id"]]) for reference in references})
                    fields["evidenceRefs"] = copy.deepcopy(references)
            else:
                target_id = _plain(payload["targetEventId"], "targetEventId", 64)
                target = next((event for event in package["events"] if event["id"] == target_id), None)
                if not target or target["kind"] != "decision" or target_id in undone:
                    raise StoreError("Undo requires an existing decision that has not already been undone", 409)
                if target["scope"]["revision"] != evidence["revision"]:
                    raise StoreError("Stale history is retained; undo requires its original evidence revision", 409)
                scope = copy.deepcopy(target["scope"])
                fields = {"targetEventId": target_id}
            package["revisions"].setdefault(evidence["revision"], snapshot(evidence))
            event = {"id": str(uuid.uuid4()), "sequence": len(package["events"]) + 1, "kind": kind,
                     "createdAt": datetime.now(timezone.utc).isoformat(), "requestId": request_id,
                     "requestDigest": request_digest, "scope": scope, "reason": reason,
                     "prevHash": package["events"][-1]["hash"] if package["events"] else ZERO_HASH, **fields}
            event["hash"] = digest(event)
            package["events"].append(event)
            self._write(package)
            return self._view(package, evidence)

    def decision(self, payload, evidence):
        return self._mutate("decision", payload, evidence)

    def undo(self, payload, evidence):
        return self._mutate("undo", payload, evidence)
