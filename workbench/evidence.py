"""Read the explicit, frozen phase-one evidence allowlist. No network or matrices."""
from __future__ import annotations

import csv
import hashlib
import io
import json
import math
from collections import Counter
from pathlib import Path

DATASET_ID = "pbmc3k-phase1"
CORE_FILES = (
    "pbmc3k_verified/scagentkit_fixed_umap.csv",
    "pbmc3k_verified/scagentkit_fixed_labels.csv",
    "pbmc3k_verified/scagentkit_fixed_markers_filtered.csv",
    "pbmc3k_reference_inputs/database_top5_candidates.csv",
    "pbmc3k_reference_inputs/prepared_reference_manifest.json",
    "pbmc3k_api_analysis_final/all_cluster_annotations.csv",
    "pbmc3k_api_analysis_final/all_response_statuses.csv",
    "pbmc3k_api_analysis_final/all_evidence_review_lexical.csv",
    "pbmc3k_api_analysis_final/all_evidence_review_broad.csv",
    "pbmc3k_api_posthoc_cluster_prefix/all_cluster_annotations_posthoc.csv",
    "pbmc3k_api_posthoc_cluster_prefix/normalization_audit.csv",
    "pbmc3k_reference_inputs/input_cells.csv",
)
CONDITIONS = ("deepseek_guided", "grok_guided", "deepseek_independent", "grok_independent")
RAW_FILES = tuple("pbmc3k_api/%s_%s.json" % (condition, cluster)
                  for condition in CONDITIONS for cluster in range(9))
ALLOWED_FILES = CORE_FILES + RAW_FILES


class EvidenceError(ValueError):
    pass


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def strict_json(value):
    def pairs(items):
        result = {}
        for key, item in items:
            if key in result:
                raise ValueError("Duplicate JSON object key")
            result[key] = item
        return result
    def constant(value):
        raise ValueError("Non-finite JSON value")
    return json.loads(value, object_pairs_hook=pairs, parse_constant=constant)


def revision_for(sources):
    return digest(sorted(sources, key=lambda source: source["id"]))


def _number(value, context):
    try:
        result = float(value)
    except (TypeError, ValueError) as error:
        raise EvidenceError("Invalid numeric evidence: %s" % context) from error
    if not math.isfinite(result):
        raise EvidenceError("Non-finite evidence: %s" % context)
    return result


def _text(value):
    return None if value in (None, "", "NA") else str(value)


def _list(value):
    return [item for item in (value or "").split(";") if item]


class EvidenceLoader:
    def __init__(self, results_root):
        self.root = Path(results_root).expanduser().resolve()
        self.latest = None
        self.error = None

    def load(self):
        """Rehash actual bytes on every refresh; file paths never determine revision."""
        try:
            evidence = self._load()
        except (OSError, ValueError, KeyError, TypeError, UnicodeError, AttributeError, RecursionError) as error:
            self.error = str(error)
            raise EvidenceError(str(error)) from error
        self.latest = evidence
        self.error = None
        return evidence

    def _load(self):
        blobs = {}
        sources = []
        for source_id in ALLOWED_FILES:
            path = self.root / source_id
            # No symlink can expand this small allowlist into an unrelated file.
            if path.is_symlink() or self.root not in path.resolve().parents:
                raise EvidenceError("Evidence source must be a regular local allowlisted file: %s" % source_id)
            data = path.read_bytes()
            if len(data) > 8 * 1024 * 1024:
                raise EvidenceError("Evidence source too large: %s" % source_id)
            blobs[source_id] = data
            sources.append({"id": source_id, "sha256": hashlib.sha256(data).hexdigest()})

        def rows(source_id, required=()):
            reader = csv.DictReader(io.StringIO(blobs[source_id].decode("utf-8-sig")))
            if not set(required).issubset(reader.fieldnames or []):
                raise EvidenceError("Missing CSV columns: %s" % source_id)
            result = list(reader)
            if not result or any(None in row for row in result):
                raise EvidenceError("Empty or damaged CSV: %s" % source_id)
            return result

        label_source = CORE_FILES[1]
        labels = rows(label_source, ("cell_id", "cluster", "status"))
        if len({row["cell_id"] for row in labels}) != len(labels):
            raise EvidenceError("Duplicate cell IDs in labels")
        if any(row["status"] not in ("retained", "qc_filtered") for row in labels):
            raise EvidenceError("Unknown input QC status")
        retained = {row["cell_id"]: row["cluster"] for row in labels if row["status"] == "retained"}
        groups = {}
        for cell_id, cluster_id in retained.items():
            if cluster_id not in {str(i) for i in range(9)}:
                raise EvidenceError("Unexpected cluster ID")
            groups.setdefault(cluster_id, []).append(cell_id)
        if len(labels) != 2700 or len(retained) != 2638 or len(groups) != 9 or len(groups.get("6", [])) != 155:
            raise EvidenceError("Fixture must contain 2700 input / 2638 retained cells, 9 clusters, and cluster 6 = 155 cells")
        groups = {key: sorted(value) for key, value in groups.items()}
        provider_cells = rows(CORE_FILES[11], ("cell_id", "cluster"))
        if len(provider_cells) != len(retained) or {row["cell_id"]: row["cluster"] for row in provider_cells} != retained:
            raise EvidenceError("Frozen provider input cell scopes differ from retained clustering")

        umap = []
        for row in rows(CORE_FILES[0], ("cell_id", "umap_1", "umap_2")):
            cell_id = row["cell_id"]
            if cell_id not in retained:
                raise EvidenceError("UMAP has a cell outside the retained cluster scope")
            umap.append({"cellId": cell_id, "clusterId": retained[cell_id],
                         "x": _number(row["umap_1"], "UMAP x"), "y": _number(row["umap_2"], "UMAP y")})
        if len(umap) != len(retained) or len({point["cellId"] for point in umap}) != len(umap):
            raise EvidenceError("UMAP cell IDs must exactly match retained cells")

        markers = {key: [] for key in groups}
        for row in rows(CORE_FILES[2], ("cluster", "gene", "avg_log2FC", "pct.1", "pct.2", "pct_diff", "p_val_adj")):
            key = row["cluster"]
            if key not in markers or not row["gene"]:
                raise EvidenceError("Invalid marker cluster or gene")
            marker = {"gene": row["gene"], "avgLog2FC": _number(row["avg_log2FC"], "marker logFC"),
                      "pct1": _number(row["pct.1"], "marker pct.1"), "pct2": _number(row["pct.2"], "marker pct.2"),
                      "pctDiff": _number(row["pct_diff"], "marker pct difference"),
                      "pAdj": _number(row["p_val_adj"], "marker adjusted p"), "source": CORE_FILES[2]}
            if not all(0 <= marker[field] <= 1 for field in ("pct1", "pct2", "pAdj")):
                raise EvidenceError("Marker percentages or p-values out of range")
            if any(other["gene"] == marker["gene"] for other in markers[key]):
                raise EvidenceError("Duplicate marker in a cluster")
            markers[key].append(marker)
        for key in markers:
            markers[key] = sorted(markers[key], key=lambda row: -row["pctDiff"])[:30]
            if not markers[key]:
                raise EvidenceError("Cluster has no marker evidence")

        candidates = {key: [] for key in groups}
        for row in rows(CORE_FILES[3], ("cluster", "cell_type", "score", "overlap_count", "celltype_size", "matched_markers")):
            key = row["cluster"]
            if key not in candidates:
                raise EvidenceError("Candidate has unknown cluster")
            candidates[key].append({"label": row["cell_type"], "score": _number(row["score"], "candidate score"),
                                    "overlap": int(row["overlap_count"]), "referenceSize": int(row["celltype_size"]),
                                    "markers": [value for value in row["matched_markers"].split(",") if value],
                                    "rank": len(candidates[key]) + 1, "source": CORE_FILES[3]})

        def indexed(source_id):
            output = {}
            for row in rows(source_id, ("condition_id", "cluster")):
                key = (row["condition_id"], row["cluster"])
                if key in output or key[0] not in CONDITIONS or key[1] not in groups:
                    raise EvidenceError("Duplicate or invalid condition / cluster evidence: %s" % source_id)
                output[key] = row
            if len(output) != 36:
                raise EvidenceError("Expected 36 condition / cluster rows: %s" % source_id)
            return output

        annotations = indexed(CORE_FILES[5])
        statuses = indexed(CORE_FILES[6])
        lexical = indexed(CORE_FILES[7])
        broad = indexed(CORE_FILES[8])
        posthoc = indexed(CORE_FILES[9])
        normalization = indexed(CORE_FILES[10])
        models = {key: [] for key in groups}
        counts = Counter()

        def projection(row):
            return {"label": _text(row.get("primary_annotation")), "annotationStatus": row.get("annotation_status"),
                    "confidence": _text(row.get("confidence")), "reasoning": _text(row.get("reasoning")),
                    "supportingMarkers": _list(row.get("supporting_markers")),
                    "contradictingMarkers": _list(row.get("contradicting_markers")),
                    "alternatives": _list(row.get("alternative_annotations")),
                    "recommendedAction": _text(row.get("recommended_action")),
                    "broadLabel": _text(row.get("broad_label")), "mappingStatus": _text(row.get("mapping_status")),
                    "fineMappingStatus": _text(row.get("fine_mapping_status"))}

        for condition in CONDITIONS:
            for key in sorted(groups):
                call_id = "%s_%s" % (condition, key)
                source = "pbmc3k_api/%s.json" % call_id
                raw = strict_json(blobs[source])
                if not isinstance(raw, dict):
                    raise EvidenceError("Raw call must be a JSON object")
                if raw.get("call_id") != call_id or str(raw.get("cluster")) != key:
                    raise EvidenceError("Raw call identity does not match its source")
                provider, mode = condition.split("_")
                if raw.get("provider") != provider or raw.get("mode") != mode:
                    raise EvidenceError("Raw call provider or mode does not match its condition")
                status = statuses[(condition, key)]
                annotation = annotations[(condition, key)]
                if status.get("call_id") != call_id:
                    raise EvidenceError("Status call reference does not match raw source")
                for annotated_row in (annotation, posthoc[(condition, key)]):
                    if annotated_row.get("provider") != provider or annotated_row.get("reference_mode") != mode:
                        raise EvidenceError("Annotation provider or mode differs from its frozen condition")
                transport = raw.get("status")
                if transport not in ("http_success", "request_failed", "network_error", "invalid_content_schema"):
                    raise EvidenceError("Unknown frozen provider transport status")
                if (status.get("provider_status") not in (transport, "invalid_content_schema")
                        or status.get("annotation_status") != annotation.get("annotation_status")
                        or annotation.get("annotation_status") not in ("ok", "failed")):
                    raise EvidenceError("Status projection is inconsistent with raw transport or annotation")
                if annotation.get("annotation_status") == "ok":
                    strict_status = "valid"
                elif transport in ("request_failed", "network_error"):
                    strict_status = "network_failed"
                else:
                    strict_status = "format_rejected"
                counts[strict_status] += 1
                strict = projection(annotation)
                strict.update(status=strict_status, formatReason=_text(status.get("annotation_error")))
                # Parser fallback unknown after a failed call is not a model's unknown annotation.
                if strict_status != "valid":
                    strict["label"] = None
                normalized = projection(posthoc[(condition, key)])
                audit = normalization[(condition, key)]
                normalized.update(status="valid" if normalized["annotationStatus"] == "ok" else strict_status,
                                  normalizationApplied=audit.get("normalization_applied") == "TRUE",
                                  normalizationReason=audit.get("normalization_reason"),
                                  source=CORE_FILES[9])
                if normalized["status"] != "valid":
                    normalized["label"] = None
                reviews = {"lexical": lexical[(condition, key)], "broad": broad[(condition, key)]}
                content = raw.get("content")
                if content is not None and not isinstance(content, str):
                    raise EvidenceError("Raw model content must be plain text")
                if strict_status == "valid":
                    parsed = strict_json(content or "")
                    if not isinstance(parsed, dict) or parsed.get("primary_annotation") != strict["label"]:
                        raise EvidenceError("Strict label does not match its raw model content")
                    required_strings = ("primary_annotation", "confidence", "proportion_assessment", "recommended_action", "reasoning")
                    required_arrays = ("supporting_markers", "contradicting_markers", "alternative_annotations")
                    if (any(not isinstance(parsed.get(field), str) or not parsed[field].strip() for field in required_strings)
                            or any(not isinstance(parsed.get(field), list) or any(not isinstance(item, str) or not item.strip() for item in parsed[field]) for field in required_arrays)
                            or parsed["confidence"] not in ("high", "medium", "low")
                            or parsed["recommended_action"] not in ("accept", "flag_for_review", "reject", "mark_unknown")
                            or parsed["proportion_assessment"] not in ("reasonable", "suspicious", "abnormal")
                            or ("cluster" in parsed and parsed["cluster"] != key)):
                        raise EvidenceError("Strict-valid call has inconsistent or malformed raw content")
                models[key].append({"callId": call_id, "provider": raw.get("provider"), "mode": raw.get("mode"),
                                    "model": raw.get("model_reported") or raw.get("model_requested"),
                                    "transportStatus": transport, "strictStatus": strict_status,
                                    "rawText": content, "strict": strict, "posthoc": normalized,
                                    "review": reviews, "source": source})
        if counts != Counter(valid=33, format_rejected=2, network_failed=1):
            raise EvidenceError("Frozen calls must be 33 strict valid / 2 format rejected / 1 network failed")

        clusters = []
        for key in sorted(groups):
            issue_kinds = []
            if any(model["strictStatus"] == "network_failed" for model in models[key]):
                issue_kinds.append("transport_failure")
            if any(model["strictStatus"] == "format_rejected" for model in models[key]):
                issue_kinds.append("format_rejection")
            if any(model["strict"].get("mappingStatus") == "unmapped"
                   or model["strict"].get("fineMappingStatus") == "unmapped_or_lacks_subtype" for model in models[key]):
                issue_kinds.append("dictionary_or_granularity")
            if key == "6":
                issue_kinds.append("biological_disagreement")
            clusters.append({"id": key, "cellCount": len(groups[key]), "cellIds": groups[key],
                             "markers": markers[key], "candidates": candidates[key],
                             "models": models[key], "issueKinds": issue_kinds,
                             "sourceLabel": "unknown", "sourceLabelStatus": "not_run_no_authorization"})
        reference_manifest = strict_json(blobs[CORE_FILES[4]])
        if not isinstance(reference_manifest, dict) or not isinstance(reference_manifest.get("data_license", {}), dict):
            raise EvidenceError("Reference manifest must be a JSON object with an object license record")
        return {"schemaVersion": 1, "revision": revision_for(sources),
                "dataset": {"id": DATASET_ID, "name": "PBMC3k · frozen phase 1", "inputCells": len(labels),
                            "retainedCells": len(retained), "clusterCount": len(groups), "tissue": "human PBMC / blood"},
                "summary": {"modelCalls": 36, "strictValid": counts["valid"],
                            "formatRejected": counts["format_rejected"], "networkFailed": counts["network_failed"]},
                "sources": sorted(sources, key=lambda source: source["id"]),
                "reference": {"database": reference_manifest.get("database"),
                              "licenseStatus": reference_manifest.get("data_license", {}).get("status"),
                              "role": "heuristic marker overlap candidates; not truth"},
                "limitations": [
                    "One public PBMC dataset; cells within a cluster are correlated. Model predictions are pending human review.",
                    "Top 30 markers are a filtered, ranked subset. A gene missing from this list is not evidence of absent expression.",
                    "Database overlap scores and ties are heuristic; dictionary mismatch and label granularity differ from biological disagreement.",
                    "Published author labels are contextual references, not absolute biological truth. This workbench does not load truth or the matrix.",
                    "Type, state and QC decisions are separate. Proposed, reviewed and accepted are workflow states, not truth claims.",
                    "Raw strict results and posthoc cluster-prefix normalization remain separate; failures are not unknown labels.",
                    "All cached evidence remains local. No model, external API or network request is made by this server."],
                "clusters": clusters, "umap": umap}


def snapshot(evidence):
    """Small handoff provenance, without matrix, truth, candidates or model text."""
    return {"datasetId": evidence["dataset"]["id"], "sources": evidence["sources"],
            "cellGroups": {cluster["id"]: cluster["cellIds"] for cluster in evidence["clusters"]}}
