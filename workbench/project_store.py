"""Independent generic review journal; original JSON payload bytes are immutable."""
from __future__ import annotations

import copy
import fcntl
import hashlib
import os
import re
import stat
import tempfile
import threading
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

try:
    from .evidence import canonical, digest, strict_json
except ImportError:
    from evidence import canonical, digest, strict_json

SCHEMA = "scagentkit.review-journal.v1"
MAX_SESSION_BYTES = 32 * 1024 * 1024 - 1024
ZERO_HASH = "0" * 64
HASH = re.compile(r"^[a-f0-9]{64}$")
TIMESTAMP = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$")
DIMENSIONS = ("type", "state", "QC")
STATUSES = ("proposed", "reviewed", "accepted")


class ProjectStoreError(ValueError):
    def __init__(self, message, status=422):
        super().__init__(message)
        self.status = status


StoreError = ProjectStoreError


def _string(value, field, maximum=4000):
    if not isinstance(value, str) or not value or not value.strip() or len(value) > maximum or "\x00" in value:
        raise ProjectStoreError("Invalid nonempty string: " + field)
    return value


def _hash(value, field):
    if not isinstance(value, str) or not HASH.fullmatch(value):
        raise ProjectStoreError("Invalid lowercase SHA256: " + field)
    return value


def _bytes_hash(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def envelope_hash(previous, payload):
    return _bytes_hash(previous + "\n" + payload)


def _header(evidence):
    return {"schema": SCHEMA, "projectId": evidence["projectId"] if "projectId" in evidence else evidence["dataset"]["id"],
            "sourceFingerprint": evidence["sourceFingerprint"], "bundleDigest": evidence["revision"]}


def _empty(evidence):
    return {**_header(evidence), "events": [], "artifacts": {}}


def _scope_key(scope):
    return (scope["datasetId"], scope["revision"], scope["sourceFingerprint"], scope["clusterId"], scope["dimension"])


def _parsed(package):
    return [strict_json(envelope["payload"]) for envelope in package["events"]]


def _replay(events):
    undone = {event["targetEventId"] for event in events if event["kind"] == "undo"}
    active = {}
    for event in events:
        if event["kind"] == "decision" and event["id"] not in undone:
            active[_scope_key(event["scope"])] = event
    return active, undone


def _validate_impl(package, evidence=None):
    if not isinstance(package, dict) or set(package) != {"schema", "projectId", "sourceFingerprint", "bundleDigest", "events", "artifacts"}:
        raise ProjectStoreError("Unknown generic review journal structure")
    if package["schema"] != SCHEMA:
        raise ProjectStoreError("Unknown journal schema; legacy PBMC journals cannot acquire generic identity")
    _string(package["projectId"], "projectId")
    _hash(package["sourceFingerprint"], "sourceFingerprint")
    _hash(package["bundleDigest"], "bundleDigest")
    if evidence is not None and any(package[key] != value for key, value in _header(evidence).items()):
        raise ProjectStoreError("Journal project/source/bundle identity differs from the verified project", 409)
    groups = {row["id"]: row["cellIds"] for row in evidence["clusters"]} if evidence is not None else None
    artifacts = package["artifacts"]
    if not isinstance(artifacts, dict) or len(artifacts) > 1000:
        raise ProjectStoreError("Invalid artifact registry")
    artifact_contents = {}
    for key, record in artifacts.items():
        _string(key, "artifact key", 512)
        if not isinstance(record, dict) or set(record) != {"payload", "sha256"} or not isinstance(record["payload"], str):
            raise ProjectStoreError("Artifact must retain its raw JSON payload and SHA256")
        _hash(record["sha256"], "artifact SHA256")
        if _bytes_hash(record["payload"]) != record["sha256"]:
            raise ProjectStoreError("Artifact payload bytes differ from SHA256")
        content = strict_json(record["payload"])
        if not isinstance(content, dict):
            raise ProjectStoreError("Artifact raw payload must be a JSON object")
        artifact_contents[key] = content
    if not isinstance(package["events"], list) or len(package["events"]) > 10000:
        raise ProjectStoreError("Invalid event count")
    previous, by_id, requests, active, undone, declared_groups = ZERO_HASH, {}, set(), {}, set(), {}
    for sequence, envelope in enumerate(package["events"], 1):
        if not isinstance(envelope, dict) or set(envelope) != {"sequence", "payload", "prevHash", "hash"}:
            raise ProjectStoreError("Invalid immutable event envelope")
        if type(envelope["sequence"]) is not int or envelope["sequence"] != sequence or not isinstance(envelope["payload"], str):
            raise ProjectStoreError("Invalid envelope sequence or raw payload")
        if envelope["prevHash"] != previous or envelope["hash"] != envelope_hash(previous, envelope["payload"]):
            raise ProjectStoreError("Raw event payload hash chain is damaged")
        event = strict_json(envelope["payload"])
        common = {"id", "sequence", "kind", "createdAt", "requestId", "requestDigest", "reason", "scope"}
        if not isinstance(event, dict):
            raise ProjectStoreError("Event payload must be a JSON object")
        if event.get("kind") == "decision":
            required = common | {"label", "status", "supersedes"}
        elif event.get("kind") == "undo":
            required = common | {"targetEventId"}
        else:
            raise ProjectStoreError("Unknown event kind")
        allowed = (required, required | {"evidenceRefs"}) if event["kind"] == "decision" else (required,)
        if set(event) not in allowed:
            raise ProjectStoreError("Invalid event payload fields")
        _string(event["id"], "event ID", 512)
        _string(event["requestId"], "request ID", 160)
        _hash(event["requestDigest"], "requestDigest")
        _string(event["reason"], "reason", 4000)
        _string(event["createdAt"], "createdAt", 100)
        if not TIMESTAMP.fullmatch(event["createdAt"]):
            raise ProjectStoreError("Event timestamp must be RFC3339 with an explicit timezone")
        try:
            datetime.fromisoformat(event["createdAt"].replace("Z", "+00:00"))
        except ValueError:
            raise ProjectStoreError("Invalid event timestamp") from None
        if event["id"] in by_id or event["requestId"] in requests or type(event["sequence"]) is not int or event["sequence"] != sequence:
            raise ProjectStoreError("Duplicate event/request ID or invalid sequence")
        scope = event["scope"]
        fields = {"datasetId", "revision", "sourceFingerprint", "clusterId", "dimension", "cellIds"}
        if not isinstance(scope, dict) or set(scope) != fields:
            raise ProjectStoreError("Invalid event scope structure")
        for name in fields - {"cellIds"}:
            _string(scope[name], name)
        if (scope["datasetId"] != package["projectId"] or scope["revision"] != package["bundleDigest"]
                or scope["sourceFingerprint"] != package["sourceFingerprint"] or scope["dimension"] not in DIMENSIONS):
            raise ProjectStoreError("Event scope differs from journal identity")
        ids = scope["cellIds"]
        if not isinstance(ids, list) or not ids or any(not isinstance(item, str) or not item for item in ids) or ids != sorted(set(ids)):
            raise ProjectStoreError("Scope must contain exact unique sorted literal cell IDs")
        if groups is not None and (scope["clusterId"] not in groups or ids != groups[scope["clusterId"]]):
            raise ProjectStoreError("Event scope differs from verified current cluster")
        prior_ids = declared_groups.setdefault(scope["clusterId"], ids)
        if prior_ids != ids:
            raise ProjectStoreError("Journal claims inconsistent cell IDs for one cluster")
        key = _scope_key(scope)
        if event["kind"] == "decision":
            _string(event["label"], "label", 160)
            if event["status"] not in STATUSES or event["supersedes"] != active.get(key):
                raise ProjectStoreError("Invalid workflow status or supersedes reference")
            references = event.get("evidenceRefs", [])
            if not isinstance(references, list) or len(references) > 8 or any(not isinstance(reference, str) for reference in references) or len(set(references)) != len(references):
                raise ProjectStoreError("Evidence references must be unique artifact key strings")
            for reference in references:
                if reference not in artifact_contents:
                    raise ProjectStoreError("Unknown artifact reference")
                content = artifact_contents[reference]
                claims_list = [content]
                if "scope" in content:
                    claims_list.append(content["scope"])
                if isinstance(content.get("provisional"), dict) and "scope" in content["provisional"]:
                    claims_list.append(content["provisional"]["scope"])
                for claims in claims_list:
                    if not isinstance(claims, dict):
                        raise ProjectStoreError("Artifact scope claims must be an object")
                    for claim, expected in (("projectId", scope["datasetId"]), ("datasetId", scope["datasetId"]),
                                            ("revision", scope["revision"]), ("sourceFingerprint", scope["sourceFingerprint"]),
                                            ("clusterId", scope["clusterId"]), ("cellIds", scope["cellIds"]),
                                            ("dimension", scope["dimension"])):
                        if claim in claims and claims[claim] != expected:
                            raise ProjectStoreError("Artifact reference is outside the decision scope")
            active[key] = event["id"]
        else:
            _string(event["targetEventId"], "undo target", 512)
            target = by_id.get(event["targetEventId"])
            if (not target or target["kind"] != "decision" or target["scope"] != scope
                    or target["id"] in undone or active.get(key) != target["id"]):
                raise ProjectStoreError("Undo requires the current active decision in the same exact scope")
            undone.add(target["id"])
            history = [item for item in by_id.values() if item["kind"] == "decision" and _scope_key(item["scope"]) == key and item["id"] not in undone]
            if history:
                active[key] = history[-1]["id"]
            else:
                active.pop(key, None)
        previous = envelope["hash"]
        requests.add(event["requestId"])
        by_id[event["id"]] = event
    return package


def validate_package(package, evidence=None):
    try:
        return _validate_impl(package, evidence)
    except ProjectStoreError:
        raise
    except (ValueError, TypeError, KeyError, AttributeError, UnicodeError, RecursionError) as error:
        raise ProjectStoreError("Invalid generic journal: %s" % error) from error


class ProjectStore:
    def __init__(self, path):
        self.path = Path(path).expanduser().resolve()
        self.lock = threading.RLock()
        self._last_valid = None

    @contextmanager
    def _locked(self):
        with self.lock:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with self.path.with_suffix(self.path.suffix + ".lock").open("a") as file:
                fcntl.flock(file.fileno(), fcntl.LOCK_EX)
                try:
                    yield
                finally:
                    fcntl.flock(file.fileno(), fcntl.LOCK_UN)

    def _load(self, evidence, current=False):
        if self.path.exists():
            try:
                descriptor = os.open(str(self.path), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
                with os.fdopen(descriptor, "rb") as file:
                    file_stat = os.fstat(file.fileno())
                    if not stat.S_ISREG(file_stat.st_mode):
                        raise ProjectStoreError("Journal must be a regular local file")
                    if file_stat.st_size > MAX_SESSION_BYTES:
                        raise ProjectStoreError("Journal exceeds the local size limit")
                    data = file.read(MAX_SESSION_BYTES + 1)
                if len(data) > MAX_SESSION_BYTES:
                    raise ProjectStoreError("Journal exceeds the local size limit")
                package = strict_json(data.decode("utf-8"))
            except (ValueError, OSError, UnicodeError, RecursionError) as error:
                raise ProjectStoreError("Cannot read generic journal: %s" % error) from error
        else:
            if evidence is None:
                raise ProjectStoreError("An empty generic journal needs a verified project")
            package = _empty(evidence)
        same_identity = evidence is not None and _header(evidence) == {key: package.get(key) for key in _header(evidence)}
        validate_package(package, evidence if current or same_identity else None)
        self._last_valid = copy.deepcopy(package)
        return package

    def _write(self, package, evidence):
        validate_package(package, evidence)
        data = (canonical(package) + "\n").encode("utf-8")
        if len(data) > MAX_SESSION_BYTES:
            raise ProjectStoreError("Journal would exceed the local size limit; existing bytes are unchanged", 413)
        descriptor, temporary = tempfile.mkstemp(prefix=".%s." % self.path.name, dir=str(self.path.parent))
        try:
            with os.fdopen(descriptor, "wb") as file:
                file.write(data)
                file.flush()
                os.fsync(file.fileno())
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
    def _view(package, evidence, error=None, evidence_error=None):
        parsed = _parsed(package)
        active, undone = _replay(parsed)
        stale = evidence is None or any(package[key] != value for key, value in _header(evidence).items())
        if evidence_error:
            stale = True
        registry = evidence.get("directedArtifacts", evidence.get("artifactRegistry", {})) if evidence else {}
        if not isinstance(registry, dict):
            registry = {}
        def event_stale(event):
            # Old capsules remain immutable history after a rules/taxonomy restart.
            # Their human labels are retained; current evidence does not re-endorse them.
            return stale or any(reference not in registry for reference in event.get("evidenceRefs", []))
        events = [dict(event, prevHash=envelope["prevHash"], hash=envelope["hash"], stale=event_stale(event), undone=event["id"] in undone)
                  for envelope, event in zip(package["events"], parsed)]
        decisions = [dict(event, stale=event_stale(event), undone=False) for event in active.values()]
        return {"schemaVersion": 1, "projectId": package["projectId"], "datasetId": package["projectId"],
                "revision": evidence["revision"] if evidence and not evidence_error else None,
                "sourceFingerprint": evidence["sourceFingerprint"] if evidence else package["sourceFingerprint"],
                "events": events, "decisions": decisions, "artifacts": copy.deepcopy(package["artifacts"]),
                "headHash": package["events"][-1]["hash"] if package["events"] else ZERO_HASH,
                "readOnly": bool(error or evidence_error or stale), "integrityError": error, "evidenceError": evidence_error,
                "stale": stale, "journalSchema": SCHEMA}

    def snapshot(self, evidence=None, evidence_error=None):
        with self._locked():
            try:
                package = self._load(evidence)
                error = None
                if evidence is not None and _header(evidence) == {key: package[key] for key in _header(evidence)}:
                    validate_package(package, evidence)
            except (ProjectStoreError, OSError) as problem:
                error = str(problem)
                package = self._last_valid or (_empty(evidence) if evidence else None)
                if package is None:
                    return {"events": [], "decisions": [], "readOnly": True, "integrityError": error, "revision": None}
            return self._view(package, evidence, error, evidence_error)

    session = snapshot

    def export(self, evidence=None):
        with self._locked():
            return copy.deepcopy(self._load(evidence))

    def import_package(self, incoming, evidence):
        with self._locked():
            validate_package(incoming, evidence)
            existing = self._load(evidence, current=True)
            prior = existing["events"]
            if len(incoming["events"]) < len(prior) or incoming["events"][:len(prior)] != prior:
                raise ProjectStoreError("Import would truncate or replace immutable envelope history", 409)
            if any(incoming["artifacts"].get(key) != value for key, value in existing["artifacts"].items()):
                raise ProjectStoreError("Import would replace or remove immutable artifact payloads", 409)
            self._write(copy.deepcopy(incoming), evidence)
            return self._view(incoming, evidence)

    @staticmethod
    def _references(references, evidence, package):
        if not isinstance(references, list) or len(references) > 8:
            raise ProjectStoreError("Invalid evidence references")
        registry = evidence.get("directedArtifacts", evidence.get("artifactRegistry", {}))
        output = []
        for reference in references:
            key = reference if isinstance(reference, str) else reference.get("id") if isinstance(reference, dict) else None
            _string(key, "artifact reference", 512)
            if key in output:
                raise ProjectStoreError("Duplicate artifact reference")
            record = registry.get(key) if isinstance(registry, dict) else None
            existing = package["artifacts"].get(key)
            if record is not None:
                if not isinstance(record, dict) or not isinstance(record.get("payload"), str):
                    raise ProjectStoreError("Runtime artifact must provide original raw JSON payload")
                raw_record = {"payload": record["payload"], "sha256": record.get("sha256")}
                if raw_record["sha256"] != _bytes_hash(raw_record["payload"]):
                    raise ProjectStoreError("Runtime artifact SHA256 differs from its original payload")
                if isinstance(reference, dict) and (set(reference) != {"kind", "id", "sha256"}
                                                   or reference["kind"] != "directed_proposal" or reference["sha256"] != raw_record["sha256"]):
                    raise ProjectStoreError("Invalid runtime artifact reference")
                if existing is not None and existing != raw_record:
                    raise ProjectStoreError("Artifact key cannot replace immutable payload bytes", 409)
                package["artifacts"][key] = raw_record
            elif existing is None or isinstance(reference, dict):
                raise ProjectStoreError("Artifact is absent from the verified runtime registry")
            output.append(key)
        return output

    def _mutate(self, kind, payload, evidence):
        if not isinstance(payload, dict):
            raise ProjectStoreError("Mutation requires a JSON object")
        required = {"revision", "requestId", "reason"}
        required |= {"clusterId", "dimension", "label", "status"} if kind == "decision" else {"targetEventId"}
        optional = {"evidenceRefs"} if kind == "decision" else set()
        if not required.issubset(payload) or not set(payload).issubset(required | optional):
            raise ProjectStoreError("Missing or unexpected mutation fields")
        request_id = _string(payload["requestId"], "requestId", 160)
        reason = _string(payload["reason"], "reason", 4000)
        request_digest = digest({"kind": kind, "payload": payload})
        with self._locked():
            package = self._load(evidence, current=True)
            parsed = _parsed(package)
            for event in parsed:
                if event["requestId"] == request_id:
                    if event["requestDigest"] != request_digest:
                        raise ProjectStoreError("requestId was already used for different input", 409)
                    return self._view(package, evidence)
            if payload["revision"] != evidence["revision"]:
                raise ProjectStoreError("Project bundle changed; refresh before making a new decision", 409)
            active, undone = _replay(parsed)
            if kind == "decision":
                cluster_id = _string(payload["clusterId"], "clusterId")
                cluster = next((row for row in evidence["clusters"] if row["id"] == cluster_id), None)
                if cluster is None or payload["dimension"] not in DIMENSIONS or payload["status"] not in STATUSES:
                    raise ProjectStoreError("Invalid current cluster, dimension or workflow status")
                label = _string(payload["label"], "label", 160).strip()
                if label.casefold() == "unknown":
                    label = "unknown"
                scope = {"datasetId": _header(evidence)["projectId"], "revision": evidence["revision"],
                         "sourceFingerprint": evidence["sourceFingerprint"], "clusterId": cluster_id,
                         "dimension": payload["dimension"], "cellIds": list(cluster["cellIds"])}
                prior = active.get(_scope_key(scope))
                fields = {"label": label, "status": payload["status"], "supersedes": prior["id"] if prior else None}
                if "evidenceRefs" in payload:
                    fields["evidenceRefs"] = self._references(payload["evidenceRefs"], evidence, package)
            else:
                target_id = _string(payload["targetEventId"], "targetEventId", 512)
                target = next((event for event in parsed if event["id"] == target_id), None)
                if (target is None or target["kind"] != "decision" or target_id in undone
                        or active.get(_scope_key(target["scope"]), {}).get("id") != target_id):
                    raise ProjectStoreError("Undo target must be the current active decision", 409)
                scope = copy.deepcopy(target["scope"])
                fields = {"targetEventId": target_id}
            sequence = len(parsed) + 1
            event = {"id": str(uuid.uuid4()), "sequence": sequence, "kind": kind,
                     "createdAt": datetime.now(timezone.utc).isoformat(), "requestId": request_id,
                     "requestDigest": request_digest, "reason": reason, "scope": scope, **fields}
            raw = canonical(event)
            previous = package["events"][-1]["hash"] if package["events"] else ZERO_HASH
            package["events"].append({"sequence": sequence, "payload": raw, "prevHash": previous, "hash": envelope_hash(previous, raw)})
            self._write(package, evidence)
            return self._view(package, evidence)

    def decide(self, payload, evidence):
        try:
            return self._mutate("decision", payload, evidence)
        except ProjectStoreError:
            raise
        except (ValueError, TypeError, KeyError, AttributeError, UnicodeError, RecursionError) as error:
            raise ProjectStoreError("Invalid generic decision: %s" % error) from error

    decision = decide

    def undo(self, payload, evidence):
        try:
            return self._mutate("undo", payload, evidence)
        except ProjectStoreError:
            raise
        except (ValueError, TypeError, KeyError, AttributeError, UnicodeError, RecursionError) as error:
            raise ProjectStoreError("Invalid generic undo: %s" % error) from error
