"""Verified local generic project bundles. No matrix deserialization or network."""
from __future__ import annotations

import copy
import fcntl
import hashlib
import io
import math
import os
import re
import shutil
import stat
import tempfile
import threading
import unicodedata
import zipfile
import zlib
from contextlib import contextmanager
from pathlib import Path, PurePosixPath

try:
    from .evidence import strict_json
except ImportError:
    from evidence import strict_json

BUNDLE_SCHEMA = "scagentkit.project-bundle.v1"
PROJECT_SCHEMA = "scagentkit.project.v1"
EXPRESSION_SCHEMA = "scAgentKit.directed_expression.v2"
MAX_UPLOAD_BYTES = 64 * 1024 * 1024
MAX_EXPANDED_BYTES = 128 * 1024 * 1024
MAX_MEMBERS = 512
MAX_COMPRESSION_RATIO = 200
HASH = re.compile(r"^[a-f0-9]{64}$")
T_ANCHORS = ("CD3D", "CD3E", "CD3G", "TRAC", "TRBC1", "TRBC2")
NK_ANCHORS = ("KLRD1", "KLRF1", "NCR1", "NCAM1")
PANEL_GENES = T_ANCHORS + ("CD8A", "CD8B") + NK_ANCHORS + ("FCGR3A", "NKG7", "GNLY", "PRF1", "GZMB", "GZMA", "GZMH", "CTSW", "CST7", "MS4A1", "CD79A", "CD79B")


class ProjectError(ValueError):
    def __init__(self, message, status=422):
        super().__init__(message)
        self.status = status


def _string(value, context):
    if not isinstance(value, str) or not value or not value.strip() or "\x00" in value:
        raise ProjectError("Expected a literal nonempty string: " + context)
    return value


def _hash(value, context):
    if not isinstance(value, str) or not HASH.fullmatch(value):
        raise ProjectError("Expected lowercase SHA256: " + context)
    return value


def _number(value, context, integer=False, fraction=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or (isinstance(value, float) and not math.isfinite(value)):
        raise ProjectError("Expected finite number: " + context)
    if integer and (value < 0 or int(value) != value):
        raise ProjectError("Expected nonnegative integer: " + context)
    if fraction and not 0 <= value <= 1:
        raise ProjectError("Expected fraction between 0 and 1: " + context)
    return value


def _object(value, context):
    if not isinstance(value, dict):
        raise ProjectError("Expected object: " + context)
    return value


def _json(data, context):
    try:
        return strict_json(data.decode("utf-8"))
    except (ValueError, UnicodeError, TypeError, RecursionError) as error:
        raise ProjectError("Invalid UTF-8 JSON %s: %s" % (context, error)) from error


def _path(value):
    _string(value, "bundle member path")
    if (value.startswith(("/", "\\")) or "\\" in value or ":" in value
            or any(ord(character) < 32 for character in value)):
        raise ProjectError("Unsafe bundle member path")
    parts = value.split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise ProjectError("Unsafe bundle member path")
    return value


def _path_key(value):
    return unicodedata.normalize("NFC", value).casefold()


def _distribution(record, values, context):
    fields = {"n", "mean", "q0", "q25", "q50", "q75", "q90", "max"}
    if not isinstance(record, dict) or set(record) != fields or type(record["n"]) is not int or record["n"] != len(values):
        raise ProjectError("Invalid distribution size or fields: " + context)
    if not values:
        if any(record[field] is not None for field in fields - {"n"}):
            raise ProjectError("Empty measured distribution needs null statistics: " + context)
        return
    values = sorted(values)
    expected = {"mean": math.fsum(value / len(values) for value in values)}
    for field, fraction in (("q0", 0), ("q25", .25), ("q50", .5), ("q75", .75), ("q90", .9), ("max", 1)):
        position = (len(values) - 1) * fraction
        lower = int(position)
        expected[field] = values[lower] + (values[min(lower + 1, len(values) - 1)] - values[lower]) * (position - lower)
    for field, value in expected.items():
        _number(record[field], context + " " + field)
        if abs(record[field] - value) > 1e-7 * max(1, abs(value)):
            raise ProjectError("Distribution differs from actual scoped measurements: " + context)


def _validate_asset(asset, identity, groups, cluster_id):
    fields = {"schema_version", "rule_version", "source", "inventory", "scope", "coverage", "panel", "coexpression",
              "identity_threshold_sensitivity", "qc", "cells", "candidate_controls", "comparisons", "limitations", "package_id"}
    if set(asset) != fields or asset["schema_version"] != EXPRESSION_SCHEMA or asset["rule_version"] != "rna-observed-panel-v1":
        raise ProjectError("Unknown or incomplete directed expression asset schema")
    _hash(asset["package_id"], "directed package ID")
    source = _object(asset["source"], "directed source")
    source_fields = {"object_fingerprint", "identity_algorithm", "assay", "layers", "n_features_counts", "n_features_data",
                     "counts_integer_nonnegative_validated", "cell_join", "normalization"}
    if set(source) != source_fields:
        raise ProjectError("Unknown directed source provenance fields")
    for field in ("n_features_counts", "n_features_data"):
        _number(source[field], field, integer=True)
    if (source.get("object_fingerprint") != identity["fingerprint"] or source.get("identity_algorithm") != identity["algorithm"]
            or source.get("assay") != identity["assay"] or source.get("assay") != "RNA"
            or source.get("layers") != {"counts": identity["countsLayer"], "data": identity["normalizedLayer"]}
            or source.get("counts_integer_nonnegative_validated") is not True
            or source.get("n_features_counts") != identity["featureCount"] or source.get("n_features_data") != identity["featureCount"]):
        raise ProjectError("Directed source assay, layers, dimensions or fingerprint differs from project identity")
    _object(source.get("normalization"), "existing normalization provenance")
    inventory = _object(asset["inventory"], "directed inventory")
    if set(inventory) != {"n_cells", "n_input_cells", "n_clusters", "counts_by_cluster"}:
        raise ProjectError("Invalid directed inventory fields")
    for field in ("n_cells", "n_input_cells", "n_clusters"):
        _number(inventory[field], field, integer=True)
    for value in _object(inventory["counts_by_cluster"], "directed cluster counts").values():
        _number(value, "directed cluster count", integer=True)
    counts_by_cluster = {key: len(ids) for key, ids in groups.items()}
    if (inventory.get("n_cells") != identity["cellCount"] or inventory.get("n_input_cells") != identity["cellCount"]
            or inventory.get("n_clusters") != len(groups) or inventory.get("counts_by_cluster") != counts_by_cluster):
        raise ProjectError("Directed inventory differs from the complete project cell universe")
    scope = _object(asset["scope"], "directed scope")
    _number(scope.get("n_cells"), "directed scope cell count", integer=True)
    expected_ids = sorted(groups[cluster_id])
    if (set(scope) != {"cluster_id", "n_cells", "cell_ids", "cell_ids_sha256"}
            or scope["cluster_id"] != cluster_id or scope["n_cells"] != len(expected_ids) or scope["cell_ids"] != expected_ids):
        raise ProjectError("Directed asset scope differs from exact cluster")
    _hash(scope["cell_ids_sha256"], "directed cell IDs hash")
    panel = asset["panel"]
    if not isinstance(panel, list) or len(panel) != len(PANEL_GENES):
        raise ProjectError("Fixed directed panel needs every feature, including explicit missing records")
    features = {}
    panel_fields = {"gene", "panel_group", "assay", "detection_layer", "normalized_layer", "n_cells", "measurement_status",
                    "counts_status", "normalized_status", "detected_n", "detected_fraction", "raw_counts", "normalized"}
    for row in panel:
        if (not isinstance(row, dict) or set(row) != panel_fields or not isinstance(row.get("gene"), str)
                or row["gene"] not in PANEL_GENES or row["gene"] in features):
            raise ProjectError("Invalid or duplicated directed panel feature")
        if (row["measurement_status"] not in ("measured", "missing") or row["counts_status"] != row["measurement_status"]
                or row["normalized_status"] != row["measurement_status"] or row["assay"] != "RNA"
                or row["detection_layer"] != identity["countsLayer"] or row["normalized_layer"] != identity["normalizedLayer"]
                or row["n_cells"] != len(expected_ids)):
            raise ProjectError("Directed feature availability or assay/layers differs from its source")
        _number(row["n_cells"], "directed feature cell count", integer=True)
        _string(row["panel_group"], "directed panel group")
        normalized = _object(row["normalized"], "normalized feature distributions")
        if set(normalized) != {"all", "detected"}:
            raise ProjectError("Normalized distributions must distinguish all and detected cells")
        if row["measurement_status"] == "missing" and any(row[key] is not None for key in ("detected_n", "detected_fraction", "raw_counts")):
            raise ProjectError("Missing feature summaries must be null, not zero")
        features[row["gene"]] = row
    observations = asset["cells"]
    if (not isinstance(observations, list) or len(observations) != len(expected_ids)
            or any(not isinstance(row, dict) or not isinstance(row.get("cell_id"), str) for row in observations)
            or sorted(row["cell_id"] for row in observations) != expected_ids):
        raise ProjectError("Directed per-cell observations do not match exact scope")
    detected = {gene: 0 for gene in PANEL_GENES}
    raw_values = {gene: [] for gene in PANEL_GENES}
    normalized_values = {gene: [] for gene in PANEL_GENES}
    coexpression = dict.fromkeys(("t_only", "nk_only", "both", "neither"), 0)
    for row in observations:
        if row.get("cluster_id") != cluster_id:
            raise ProjectError("Directed observation has a foreign or missing cluster")
        counts = _object(row.get("counts"), "directed counts")
        normalized = _object(row.get("normalized"), "directed normalized")
        _object(row.get("qc"), "directed cell QC")
        if set(counts) != set(PANEL_GENES) or set(normalized) != set(PANEL_GENES):
            raise ProjectError("Directed cells need explicit values or nulls for every panel feature")
        for gene in PANEL_GENES:
            if features[gene]["measurement_status"] == "missing":
                if counts[gene] is not None or normalized[gene] is not None:
                    raise ProjectError("Missing feature cannot have measured counts or normalized data")
            else:
                _number(counts[gene], "directed RNA count", integer=True)
                _number(normalized[gene], "directed normalized value")
                if normalized[gene] < 0 or (counts[gene] == 0) != (normalized[gene] == 0):
                    raise ProjectError("Existing RNA counts and normalized detection disagree")
                detected[gene] += counts[gene] > 0
                raw_values[gene].append(counts[gene])
                normalized_values[gene].append(normalized[gene])
        t = sum(counts[gene] is not None and counts[gene] > 0 for gene in T_ANCHORS)
        nk = sum(counts[gene] is not None and counts[gene] > 0 for gene in NK_ANCHORS)
        category = "both" if t >= 2 and nk >= 2 else "t_only" if t >= 2 else "nk_only" if nk >= 2 else "neither"
        coexpression[category] += 1
    for gene, row in features.items():
        if row["measurement_status"] == "measured":
            _number(row["detected_n"], "directed detected_n", integer=True)
            _number(row["detected_fraction"], "directed detected fraction", fraction=True)
            if row["detected_n"] != detected[gene] or abs(row["detected_fraction"] - detected[gene] / len(expected_ids)) > 1e-5:
                raise ProjectError("Directed summary detection differs from actual scoped observations")
            _distribution(row["raw_counts"], raw_values[gene], "raw counts " + gene)
            _distribution(row["normalized"]["all"], normalized_values[gene], "normalized all " + gene)
            _distribution(row["normalized"]["detected"], [value for value in normalized_values[gene] if value > 0], "normalized detected " + gene)
        elif any(value is not None for value in row["normalized"].values()):
            raise ProjectError("Missing normalized feature distributions must be null")
    summary = _object(asset["coexpression"], "directed coexpression")
    for field in ("n_cells", "threshold_n"):
        _number(summary.get(field), "coexpression " + field, integer=True)
    for value in _object(summary.get("counts"), "coexpression counts").values():
        _number(value, "coexpression count", integer=True)
    if summary.get("n_cells") != len(expected_ids) or summary.get("threshold_n") != 2 or summary.get("counts") != coexpression:
        raise ProjectError("Directed observed coexpression differs from actual scoped counts")
    for field in ("coverage", "qc", "comparisons"):
        _object(asset[field], "directed " + field)
    coverage = asset["coverage"]
    for field in ("panel_gene_n", "measured_gene_n", "scope_n_cells"):
        _number(coverage.get(field), "coverage " + field, integer=True)
    missing = [gene for gene in PANEL_GENES if features[gene]["measurement_status"] == "missing"]
    if (coverage["panel_gene_n"] != len(PANEL_GENES) or coverage["measured_gene_n"] != len(PANEL_GENES) - len(missing)
            or coverage["scope_n_cells"] != len(expected_ids) or coverage.get("missing_genes") != missing):
        raise ProjectError("Directed coverage differs from the explicit feature availability")
    for field in ("identity_threshold_sensitivity", "candidate_controls", "limitations"):
        if not isinstance(asset[field], list):
            raise ProjectError("Directed " + field + " must be an array")


def _validate_files_impl(blobs):
    if "manifest.json" not in blobs or "project.json" not in blobs:
        raise ProjectError("Bundle requires manifest.json and project.json at its root")
    manifest = _object(_json(blobs["manifest.json"], "manifest.json"), "manifest")
    if set(manifest) != {"schema", "projectId", "sourceFingerprint", "bundleDigest", "files"} or manifest["schema"] != BUNDLE_SCHEMA:
        raise ProjectError("Unknown manifest schema or fields")
    _string(manifest["projectId"], "projectId")
    _hash(manifest["sourceFingerprint"], "sourceFingerprint")
    _hash(manifest["bundleDigest"], "bundleDigest")
    if not isinstance(manifest["files"], list) or not 1 <= len(manifest["files"]) < MAX_MEMBERS:
        raise ProjectError("Invalid manifest file count")
    listed, keys = {}, set()
    for record in manifest["files"]:
        if not isinstance(record, dict) or set(record) != {"path", "bytes", "sha256"}:
            raise ProjectError("Invalid manifest file record")
        name = _path(record["path"])
        if name == "manifest.json" or _path_key(name) in keys:
            raise ProjectError("Duplicate manifest member")
        keys.add(_path_key(name))
        _number(record["bytes"], "member byte size", integer=True)
        _hash(record["sha256"], "member hash")
        listed[name] = record
    if set(blobs) != set(listed) | {"manifest.json"}:
        raise ProjectError("Unlisted or missing bundle member")
    for name, record in listed.items():
        if len(blobs[name]) != record["bytes"] or hashlib.sha256(blobs[name]).hexdigest() != record["sha256"]:
            raise ProjectError("Bundle member byte size or SHA256 does not match: " + name)
    project_bytes = blobs["project.json"]
    if hashlib.sha256(project_bytes).hexdigest() != manifest["bundleDigest"]:
        raise ProjectError("Project bundle digest does not match actual project.json bytes")
    project = _object(_json(project_bytes, "project.json"), "project")
    required = {"schema", "projectId", "displayName", "identity", "cells", "clusters", "embedding", "markers", "candidates", "models", "parameters", "provenance", "directed"}
    if set(project) not in (required, required | {"sourceAnnotation"}) or project["schema"] != PROJECT_SCHEMA:
        raise ProjectError("Unknown project schema or fields")
    if project["projectId"] != manifest["projectId"]:
        raise ProjectError("Project identity differs from manifest")
    _string(project["displayName"], "displayName")
    identity = _object(project["identity"], "identity")
    identity_fields = {"algorithm", "fingerprint", "assay", "countsLayer", "normalizedLayer", "clusterColumn", "cellCount", "featureCount", "cellsHash", "featuresHash", "membershipHash", "countsHash", "dataHash"}
    if set(identity) != identity_fields or identity["algorithm"] != "scagentkit.source.v1" or identity["fingerprint"] != manifest["sourceFingerprint"]:
        raise ProjectError("Invalid source identity schema or manifest fingerprint")
    for field in ("fingerprint", "cellsHash", "featuresHash", "membershipHash", "countsHash"):
        _hash(identity[field], field)
    for field in ("assay", "countsLayer", "clusterColumn"):
        _string(identity[field], field)
    if identity["normalizedLayer"] is None:
        if identity["dataHash"] is not None:
            raise ProjectError("Counts-only identity requires dataHash null")
    else:
        _string(identity["normalizedLayer"], "normalizedLayer")
        _hash(identity["dataHash"], "dataHash")
    for field in ("cellCount", "featureCount"):
        _number(identity[field], field, integer=True)
        if identity[field] <= 0:
            raise ProjectError("Source dimensions must be positive")
    for field in ("parameters", "provenance"):
        _object(project[field], field)
    if not isinstance(project["cells"], list) or len(project["cells"]) != identity["cellCount"]:
        raise ProjectError("Project cell universe differs from source identity")
    cells, groups = {}, {}
    for cell in project["cells"]:
        if not isinstance(cell, dict) or set(cell) != {"cellId", "clusterId", "qc"}:
            raise ProjectError("Invalid cell record")
        cell_id, cluster_id = _string(cell["cellId"], "cellId"), _string(cell["clusterId"], "clusterId")
        if cell_id in cells:
            raise ProjectError("Duplicate literal cell ID")
        _object(cell["qc"], "cell QC")
        cells[cell_id] = cell
        groups.setdefault(cluster_id, []).append(cell_id)
    if not isinstance(project["clusters"], list) or len(project["clusters"]) != len(groups):
        raise ProjectError("Cluster list differs from exact cell memberships")
    seen_clusters = set()
    for cluster in project["clusters"]:
        if not isinstance(cluster, dict) or set(cluster) != {"id", "cellIds"}:
            raise ProjectError("Invalid cluster record")
        cluster_id = _string(cluster["id"], "cluster ID")
        if cluster_id in seen_clusters or cluster_id not in groups:
            raise ProjectError("Duplicate or foreign cluster ID")
        cell_ids = cluster["cellIds"]
        if not isinstance(cell_ids, list) or any(not isinstance(item, str) for item in cell_ids) or sorted(cell_ids) != sorted(groups[cluster_id]):
            raise ProjectError("Cluster scope differs from exact cell memberships")
        seen_clusters.add(cluster_id)
    embedding = project["embedding"]
    if embedding is not None:
        if not isinstance(embedding, dict) or set(embedding) != {"name", "points"}:
            raise ProjectError("Invalid embedding record")
        _string(embedding["name"], "embedding name")
        if not isinstance(embedding["points"], list) or len(embedding["points"]) != len(cells):
            raise ProjectError("Embedding must exactly cover the cell universe")
        points = set()
        for point in embedding["points"]:
            if not isinstance(point, dict) or set(point) != {"cellId", "x", "y"}:
                raise ProjectError("Invalid embedding point")
            cell_id = _string(point["cellId"], "embedding cell ID")
            if cell_id not in cells or cell_id in points:
                raise ProjectError("Duplicate or foreign embedding cell ID")
            _number(point["x"], "embedding x")
            _number(point["y"], "embedding y")
            points.add(cell_id)
    for field in ("markers", "candidates", "models"):
        if not isinstance(project[field], list):
            raise ProjectError(field + " must be an array, including when empty")
    markers_seen, calls_seen = set(), set()
    for marker in project["markers"]:
        fields = {"clusterId", "gene", "avgLog2FC", "pct1", "pct2", "pAdj", "source"}
        if not isinstance(marker, dict) or set(marker) != fields or marker["clusterId"] not in groups:
            raise ProjectError("Invalid marker record or cluster reference")
        _string(marker["gene"], "marker gene")
        _string(marker["source"], "marker source")
        key = (marker["clusterId"], marker["gene"])
        if key in markers_seen:
            raise ProjectError("Duplicate cluster marker")
        markers_seen.add(key)
        _number(marker["avgLog2FC"], "marker logFC")
        for field in ("pct1", "pct2", "pAdj"):
            _number(marker[field], field, fraction=True)
    for candidate in project["candidates"]:
        fields = {"clusterId", "label", "score", "overlap", "referenceSize", "markers", "source"}
        if not isinstance(candidate, dict) or set(candidate) != fields or candidate["clusterId"] not in groups:
            raise ProjectError("Invalid candidate record or cluster reference")
        _string(candidate["label"], "candidate label")
        _string(candidate["source"], "candidate source")
        _number(candidate["score"], "candidate score", fraction=True)
        _number(candidate["overlap"], "candidate overlap", integer=True)
        _number(candidate["referenceSize"], "candidate reference size", integer=True)
        if candidate["overlap"] > candidate["referenceSize"]:
            raise ProjectError("Candidate overlap exceeds its reference size")
        if not isinstance(candidate["markers"], list) or any(not isinstance(item, str) or not item for item in candidate["markers"]):
            raise ProjectError("Candidate markers must be literal strings")
        if len(set(candidate["markers"])) != len(candidate["markers"]):
            raise ProjectError("Candidate marker strings must be unique")
    for model in project["models"]:
        fields = {"clusterId", "callId", "provider", "mode", "strictStatus", "strict", "posthoc", "rawText", "source"}
        if not isinstance(model, dict) or set(model) != fields or model["clusterId"] not in groups:
            raise ProjectError("Invalid model record or cluster reference")
        for field in ("callId", "provider", "mode", "source"):
            _string(model[field], field)
        if model["callId"] in calls_seen:
            raise ProjectError("Duplicate model call ID")
        calls_seen.add(model["callId"])
        if model["strictStatus"] not in ("not_run", "valid", "format_rejected", "network_failed"):
            raise ProjectError("Unknown model status")
        if model["strict"] is not None:
            _object(model["strict"], "strict model result")
        if model["posthoc"] is not None:
            _object(model["posthoc"], "posthoc model result")
        if (model["strict"] or {}).get("status", model["strictStatus"]) != model["strictStatus"]:
            raise ProjectError("Strict status fields disagree")
        if model["strictStatus"] == "valid":
            _string((model["strict"] or {}).get("label"), "strict model label")
        if model["rawText"] is not None and not isinstance(model["rawText"], str):
            raise ProjectError("Model responses must be plain text")
    if "sourceAnnotation" in project:
        annotation = _object(project["sourceAnnotation"], "source annotation")
        if set(annotation) != {"column", "role", "values"} or annotation["role"] != "source_context":
            raise ProjectError("Source annotation must be explicit source context")
        _string(annotation["column"], "source annotation column")
        if not isinstance(annotation["values"], list) or len(annotation["values"]) != len(cells):
            raise ProjectError("Source annotation must exactly cover cells")
        seen = set()
        for row in annotation["values"]:
            if not isinstance(row, dict) or set(row) != {"cellId", "value"} or row["cellId"] not in cells or row["cellId"] in seen:
                raise ProjectError("Invalid source annotation cell reference")
            if row["value"] is not None and not isinstance(row["value"], str):
                raise ProjectError("Source annotation must preserve nullable literal strings")
            seen.add(row["cellId"])
    directed = _object(project["directed"], "directed declaration")
    if set(directed) != {"panel", "clusters"} or directed["panel"] != "T_NK.v1" or not isinstance(directed["clusters"], dict):
        raise ProjectError("Unknown directed panel schema")
    if identity["normalizedLayer"] is None and directed["clusters"]:
        raise ProjectError("Counts-only projects cannot include normalization-dependent directed assets")
    assets, asset_paths = {}, set()
    for cluster_id, record in directed["clusters"].items():
        if cluster_id not in groups or not isinstance(record, dict) or set(record) != {"path", "sha256"}:
            raise ProjectError("Invalid directed cluster asset reference")
        name = _path(record["path"])
        if name == "project.json" or not name.endswith(".json") or name in asset_paths or name not in listed:
            raise ProjectError("Directed asset must be a unique listed JSON file")
        asset_paths.add(name)
        if record["sha256"] != listed[name]["sha256"]:
            raise ProjectError("Directed asset hash differs from manifest")
        asset = _object(_json(blobs[name], name), "directed asset")
        _validate_asset(asset, identity, groups, cluster_id)
        assets[cluster_id] = asset
    if set(listed) != {"project.json"} | asset_paths:
        raise ProjectError("Manifest includes unsupported or unreferenced assets")
    return manifest, project, assets


def _validate_files(blobs):
    """Malformed nested references fail closed just like an invalid checksum."""
    try:
        return _validate_files_impl(blobs)
    except ProjectError:
        raise
    except (ValueError, TypeError, KeyError, AttributeError, UnicodeError, RecursionError, OverflowError) as error:
        raise ProjectError("Invalid project bundle: %s" % error) from error


def _directory_bytes(root):
    root = Path(root).expanduser()
    if root.is_symlink():
        raise ProjectError("Project directory may not be a symlink")
    root = root.resolve()
    if not root.is_dir():
        raise ProjectError("Project directory is unavailable")
    blobs, total, keys = {}, 0, set()
    def walk_error(error):
        raise ProjectError("Cannot enumerate the complete bundle tree: %s" % error) from error
    for directory, directories, names, directory_fd in os.fwalk(root, follow_symlinks=False, onerror=walk_error):
        for name in directories:
            if stat.S_ISLNK(os.stat(name, dir_fd=directory_fd, follow_symlinks=False).st_mode):
                raise ProjectError("Bundle directories may not contain symlinks")
        for name in names:
            target = Path(directory) / name
            file_stat = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            if not stat.S_ISREG(file_stat.st_mode):
                raise ProjectError("Bundle members must be regular files")
            relative = _path(target.relative_to(root).as_posix())
            if _path_key(relative) in keys:
                raise ProjectError("Case or Unicode-colliding bundle members")
            keys.add(_path_key(relative))
            size = file_stat.st_size
            if len(keys) > MAX_MEMBERS or total + size > MAX_EXPANDED_BYTES:
                raise ProjectError("Expanded bundle exceeds size or member limits", 413)
            descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory_fd)
            with os.fdopen(descriptor, "rb") as stream:
                opened = os.fstat(stream.fileno())
                if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (file_stat.st_dev, file_stat.st_ino):
                    raise ProjectError("Bundle member changed while being opened")
                chunks, actual = [], 0
                while True:
                    chunk = stream.read(min(65536, MAX_EXPANDED_BYTES - total - actual + 1))
                    if not chunk:
                        break
                    actual += len(chunk)
                    if total + actual > MAX_EXPANDED_BYTES or actual > size:
                        raise ProjectError("Bundle grew beyond its declared or allowed size", 413)
                    chunks.append(chunk)
                data = b"".join(chunks)
            if len(data) != size:
                raise ProjectError("Bundle changed while being read")
            total += len(data)
            blobs[relative] = data
    _validate_files(blobs)
    return root, blobs


def zip_bytes(data):
    """Verify before extracting; size and ratio limits apply to actual bytes too."""
    if not isinstance(data, (bytes, bytearray)) or not data or len(data) > MAX_UPLOAD_BYTES:
        raise ProjectError("ZIP upload is empty or exceeds 64 MB", 413)
    blobs, keys, directories, total = {}, set(), set(), 0
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            infos = archive.infolist()
            if len(infos) > MAX_MEMBERS:
                raise ProjectError("ZIP has too many members", 413)
            for info in infos:
                if info.orig_filename != info.filename:
                    raise ProjectError("ZIP member contains an embedded NUL")
                name = _path(info.filename[:-1] if info.is_dir() else info.filename)
                key = _path_key(name)
                if key in keys:
                    raise ProjectError("Duplicate or colliding ZIP member")
                keys.add(key)
                file_type = stat.S_IFMT(info.external_attr >> 16)
                if file_type not in (0, stat.S_IFREG, stat.S_IFDIR) or (file_type == stat.S_IFDIR and not info.is_dir()):
                    raise ProjectError("ZIP symlinks and special files are rejected")
                if info.flag_bits & 1 or info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                    raise ProjectError("Encrypted or unsupported compressed members are rejected")
                if info.is_dir():
                    directories.add(name)
                    continue
                if info.file_size > MAX_EXPANDED_BYTES or info.file_size / max(1, info.compress_size) > MAX_COMPRESSION_RATIO:
                    raise ProjectError("ZIP member exceeds size or compression ratio limits", 413)
                chunks, size = [], 0
                with archive.open(info) as stream:
                    while True:
                        chunk = stream.read(65536)
                        if not chunk:
                            break
                        size += len(chunk)
                        total += len(chunk)
                        if total > MAX_EXPANDED_BYTES or size > info.file_size:
                            raise ProjectError("Expanded ZIP exceeds declared or allowed size", 413)
                        chunks.append(chunk)
                if size != info.file_size:
                    raise ProjectError("ZIP member has an inconsistent actual size")
                blobs[name] = b"".join(chunks)
    except (zipfile.BadZipFile, RuntimeError, OSError, EOFError, NotImplementedError, ValueError, UnicodeError) as error:
        if isinstance(error, ProjectError):
            raise
        raise ProjectError("Invalid ZIP: %s" % error) from error
    parents = {str(parent) for name in blobs for parent in PurePosixPath(name).parents if str(parent) != "."}
    if not directories.issubset(parents):
        raise ProjectError("ZIP contains unreferenced directories")
    _validate_files(blobs)
    return blobs


class ProjectLoader:
    def __init__(self, path):
        self.root = Path(path).expanduser()
        self.project = None
        self.manifest = None
        self.assets = {}
        self.latest = None
        self.error = None

    def load(self):
        try:
            _, blobs = _directory_bytes(self.root)
            manifest, project, assets = _validate_files(blobs)
            self.project, self.manifest, self.assets = project, manifest, assets
            evidence = self._evidence(project, manifest, assets)
        except (OSError, ValueError, TypeError, KeyError, AttributeError, RecursionError) as error:
            self.error = str(error)
            raise ProjectError(str(error), getattr(error, "status", 422)) from error
        self.latest, self.error = evidence, None
        return evidence

    def directed_asset(self, cluster_id):
        if self.project is None:
            self.load()
        return copy.deepcopy(self.assets.get(str(cluster_id)))

    @staticmethod
    def _evidence(project, manifest, assets):
        grouped = {row["id"]: sorted(row["cellIds"]) for row in project["clusters"]}
        annotations = {row["cellId"]: row["value"] for row in project.get("sourceAnnotation", {}).get("values", [])}
        clusters = []
        for cluster_id, cell_ids in sorted(grouped.items()):
            marker_rows = [copy.deepcopy(row) for row in project["markers"] if row["clusterId"] == cluster_id]
            for row in marker_rows:
                row["pctDiff"] = row["pct1"] - row["pct2"]
            candidate_rows = [copy.deepcopy(row) for row in project["candidates"] if row["clusterId"] == cluster_id]
            for rank, row in enumerate(candidate_rows, 1):
                row["rank"] = rank
            model_rows = [copy.deepcopy(row) for row in project["models"] if row["clusterId"] == cluster_id]
            for row in model_rows:
                row["strictProvided"] = row["strict"] is not None
                row["posthocProvided"] = row["posthoc"] is not None
                row["strict"] = row["strict"] or {}
                row["posthoc"] = row["posthoc"] or {}
                row["strict"].setdefault("status", row["strictStatus"])
            counts = {}
            for cell_id in cell_ids:
                if cell_id in annotations:
                    label = annotations[cell_id]
                    counts[label] = counts.get(label, 0) + 1
            source_labels = [{"value": label, "count": count} for label, count in sorted(counts.items(), key=lambda item: (item[0] is not None, str(item[0])))]
            clusters.append({"id": cluster_id, "cellIds": cell_ids, "cellCount": len(cell_ids),
                             "markers": marker_rows, "candidates": candidate_rows, "models": model_rows, "issueKinds": [],
                             "modelStatus": "not_run" if all(row["strictStatus"] == "not_run" for row in model_rows) else "supplied",
                             "sourceAnnotations": source_labels, "sourceAnnotation": copy.deepcopy(project.get("sourceAnnotation")),
                             "sourceLabel": source_labels[0]["value"] if len(source_labels) == 1 else None,
                             "sourceLabelStatus": "source_context" if source_labels else "not_supplied"})
        embedding = project["embedding"]
        cells = {row["cellId"]: row["clusterId"] for row in project["cells"]}
        umap = [{"cellId": row["cellId"], "clusterId": cells[row["cellId"]], "x": row["x"], "y": row["y"]}
                for row in embedding["points"]] if embedding else []
        statuses = [row["strictStatus"] for row in project["models"]]
        return {"schemaVersion": 1, "projectSchema": PROJECT_SCHEMA, "projectId": project["projectId"],
                "displayName": project["displayName"], "revision": manifest["bundleDigest"], "bundleDigest": manifest["bundleDigest"],
                "sourceFingerprint": manifest["sourceFingerprint"], "identity": copy.deepcopy(project["identity"]),
                "dataset": {"id": project["projectId"], "name": project["displayName"], "inputCells": len(cells),
                            "retainedCells": len(cells), "clusterCount": len(clusters)},
                "summary": {"modelCalls": len(statuses) - statuses.count("not_run"), "strictValid": statuses.count("valid"),
                            "formatRejected": statuses.count("format_rejected"), "networkFailed": statuses.count("network_failed"),
                            "notRun": statuses.count("not_run"), "modelStatus": "not_run" if all(status == "not_run" for status in statuses) else "supplied"},
                "sources": [{"id": row["path"], "sha256": row["sha256"]} for row in manifest["files"]],
                "sourceAnnotation": copy.deepcopy(project.get("sourceAnnotation")), "clusters": clusters,
                "embeddingName": embedding["name"] if embedding else None, "umap": umap,
                "parameters": copy.deepcopy(project["parameters"]), "provenance": copy.deepcopy(project["provenance"]),
                "directed": copy.deepcopy(project["directed"]), "directedAssets": copy.deepcopy(assets),
                "limitations": ["Generic local project. Model and database records are supplied evidence, not truth.",
                                "No model was run by this loader. Absent embedding or evidence remains unavailable.",
                                "Source annotations are immutable source context, never accepted review decisions.",
                                "Source identity is declared by the exporter; R writeback verifies it against the original object."]}


class ProjectRegistry:
    def __init__(self, cache_dir, journal_dir, initial_project=None):
        self.cache_dir = Path(cache_dir).expanduser().resolve()
        self.journal_dir = Path(journal_dir).expanduser().resolve()
        self.lock = threading.RLock()
        self.entries = {}
        self.stores = {}
        if self.cache_dir.is_dir():
            for path in sorted(self.cache_dir.iterdir()):
                if path.is_dir() and not path.is_symlink() and HASH.fullmatch(path.name):
                    loader = ProjectLoader(path)
                    try:
                        evidence = loader.load()
                    except ProjectError:
                        continue
                    if evidence["revision"] == path.name:
                        self.entries[path.name] = loader
        self.initial_key = None
        if initial_project is not None:
            self.initial_key = self.add_directory(initial_project)["key"]

    @staticmethod
    def _metadata(evidence):
        return {"key": evidence["revision"], "projectId": evidence["projectId"], "displayName": evidence["displayName"],
                "bundleDigest": evidence["revision"], "sourceFingerprint": evidence["sourceFingerprint"],
                "cellCount": evidence["dataset"]["retainedCells"], "clusterCount": evidence["dataset"]["clusterCount"]}

    def list(self):
        with self.lock:
            result = []
            for key, loader in sorted(self.entries.items()):
                evidence = loader.load()
                if evidence["revision"] != key:
                    raise ProjectError("Immutable cached project bytes changed", 409)
                result.append(self._metadata(evidence))
            return result

    @contextmanager
    def _cache_locked(self):
        """Coordinate immutable cache creation across independent local servers."""
        with self.lock:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
            with (self.cache_dir / ".registry.lock").open("a") as lock_file:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
                try:
                    yield
                finally:
                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

    def _add(self, blobs):
        manifest, _, _ = _validate_files(blobs)
        key = manifest["bundleDigest"]
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        destination = self.cache_dir / key
        if destination.exists():
            if destination.is_symlink():
                raise ProjectError("Cache project path may not be a symlink")
            _, existing = _directory_bytes(destination)
            if existing != blobs:
                raise ProjectError("Existing digest cache is immutable and differs from imported bytes", 409)
        else:
            temporary = Path(tempfile.mkdtemp(prefix=".import-", dir=str(self.cache_dir)))
            try:
                for name, data in blobs.items():
                    target = temporary / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with target.open("xb") as output:
                        output.write(data)
                        output.flush()
                        os.fsync(output.fileno())
                ProjectLoader(temporary).load()
                try:
                    os.rename(temporary, destination)
                except FileExistsError:
                    _, existing = _directory_bytes(destination)
                    if existing != blobs:
                        raise ProjectError("Concurrent import conflicts with immutable cache", 409)
            finally:
                if temporary.exists():
                    shutil.rmtree(temporary)
        loader = ProjectLoader(destination)
        evidence = loader.load()
        self.entries[key] = loader
        return self._metadata(evidence)

    def add_directory(self, path):
        _, blobs = _directory_bytes(path)
        with self._cache_locked():
            return self._add(blobs)

    def import_zip(self, data):
        blobs = zip_bytes(data)
        with self._cache_locked():
            return self._add(blobs)

    def select(self, key):
        if not isinstance(key, str) or not HASH.fullmatch(key):
            raise ProjectError("Invalid project key", 404)
        with self.lock:
            loader = self.entries.get(key)
            if loader is None:
                raise ProjectError("Project key is not registered", 404)
            evidence = loader.load()
            if evidence["revision"] != key:
                raise ProjectError("Immutable cached project bytes changed", 409)
            try:
                from .project_store import ProjectStore
            except ImportError:
                from project_store import ProjectStore
            store = self.stores.get(key)
            if store is None:
                store = ProjectStore(self.journal_dir / (key + ".json"))
                self.stores[key] = store
            return loader, evidence, store

    def export_zip(self, key):
        loader, _, _ = self.select(key)
        _, blobs = _directory_bytes(loader.root)
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for name in sorted(blobs):
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                compressor = zlib.compressobj(6, zlib.DEFLATED, -15)
                compressed_size = len(compressor.compress(blobs[name])) + len(compressor.flush())
                # Legitimate repeated JSON still needs an importable export.
                info.compress_type = (zipfile.ZIP_STORED if len(blobs[name]) / max(1, compressed_size) > MAX_COMPRESSION_RATIO
                                      else zipfile.ZIP_DEFLATED)
                info.external_attr = (stat.S_IFREG | 0o600) << 16
                archive.writestr(info, blobs[name])
        data = output.getvalue()
        if len(data) > MAX_UPLOAD_BYTES:
            raise ProjectError("Export exceeds the portable ZIP upload limit", 413)
        zip_bytes(data)
        return data
