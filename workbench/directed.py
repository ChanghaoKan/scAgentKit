"""Deterministic, local review triage and positive-RNA proposals.

This module only returns data. It does not execute tools, write decisions, query a
model, infer a doublet, or use author labels. Thresholds are uncalibrated review
heuristics. Detection is count > 0 in the existing RNA counts layer.
"""
from __future__ import annotations

import copy
import hashlib
import itertools
import math
from pathlib import Path

try:
    from .evidence import canonical, digest, strict_json
except ImportError:
    from evidence import canonical, digest, strict_json

TAXONOMY_PATH = Path(__file__).with_name("taxonomy.v1.json")
CLASSIFICATIONS = (
    "execution_failure", "format_failure", "explicit_synonym", "granularity_difference",
    "identity_vs_state", "lineage_conflict", "candidate_missing", "lexicon_unknown",
)
TOOLS = ("local.expression_panel", "local.coexpression", "local.qc_summary")
PANELS = {
    "T_identity": ("CD3D", "CD3E", "CD3G", "TRAC", "TRBC1", "TRBC2"),
    "T_subtype_support": ("CD8A", "CD8B"),
    "NK_identity": ("KLRD1", "KLRF1", "NCR1", "NCAM1"),
    "nonexclusive": ("FCGR3A",),
    "shared_cytotoxic": ("NKG7", "GNLY", "PRF1", "GZMB", "GZMA", "GZMH", "CTSW", "CST7"),
}
PANEL_GENES = tuple(gene for genes in PANELS.values() for gene in genes)
DEFAULT_THRESHOLDS = {
    "anchorCount": 2, "minimumPositiveCells": 5, "minimumPositiveFraction": 0.10,
    "minimumMeasuredTAnchors": 3, "minimumMeasuredNKAnchors": 3,
    "minimumMedianUMIs": 1000, "minimumMedianFeatures": 500,
    "maximumLowDepthFraction": 0.25,
}


class DirectedError(ValueError):
    pass


def _label_key(value):
    return " ".join(value.casefold().split())


def load_taxonomy():
    data = TAXONOMY_PATH.read_bytes()
    taxonomy = strict_json(data)
    nodes, aliases = taxonomy["nodes"], {}
    for identity in nodes:
        visited, cursor = set(), identity
        while cursor is not None:
            if cursor not in nodes or cursor in visited:
                raise DirectedError("Taxonomy has an invalid or cyclic parent reference")
            visited.add(cursor)
            cursor = nodes[cursor]["parent"]
    for term in taxonomy["terms"]:
        if term["node"] is not None and term["node"] not in nodes:
            raise DirectedError("Taxonomy alias refers to an unknown identity")
        for alias in term["aliases"]:
            key = _label_key(alias)
            if key in aliases:
                raise DirectedError("Taxonomy aliases must be unique")
            aliases[key] = term
    return {**taxonomy, "hash": hashlib.sha256(data).hexdigest(), "aliasIndex": aliases}


def describe_label(label, taxonomy=None):
    taxonomy = taxonomy or load_taxonomy()
    if not isinstance(label, str) or not label.strip():
        return {"raw": label, "known": False, "node": None, "states": [], "lineage": None, "dimension": None}
    term = taxonomy["aliasIndex"].get(_label_key(label))
    if not term:
        return {"raw": label, "known": False, "node": None, "states": [], "lineage": None, "dimension": None}
    node = term["node"]
    return {"raw": label, "known": True, "node": node, "states": sorted(term["states"]),
            "lineage": taxonomy["nodes"][node]["lineage"] if node else None,
            "dimension": term.get("dimension", "type"), "abstention": term.get("abstention", False),
            "canonicalLabel": taxonomy["nodes"][node]["label"] if node else term["aliases"][0]}


def _ancestors(identity, taxonomy):
    result = []
    while identity is not None:
        result.append(identity)
        identity = taxonomy["nodes"][identity]["parent"]
    return result


def classify_pair(left_label, right_label, taxonomy=None):
    """Compare explicit vocabulary claims; no fuzzy synonym guessing."""
    taxonomy = taxonomy or load_taxonomy()
    left, right = describe_label(left_label, taxonomy), describe_label(right_label, taxonomy)
    compatibility = "unresolved"
    if not left["known"] or not right["known"]:
        kind, reason = "lexicon_unknown", "A label has no comparable identity in this versioned local vocabulary."
    elif left.get("abstention") or right.get("abstention"):
        return {"kind": None, "compatibility": "unresolved", "abstention": True,
                "reason": "An explicit biological abstention makes no identity claim; it is not a dictionary failure.",
                "left": left, "right": right}
    elif left["dimension"] != "type" or right["dimension"] != "type":
        kind, reason = "identity_vs_state", "An identity and a state or QC descriptor answer different questions."
    elif left["node"] == right["node"] and left["states"] == right["states"]:
        kind, reason, compatibility = "explicit_synonym", "The explicit alias registry assigns both labels the same identity and state.", "exact"
    elif left["node"] == right["node"]:
        kind, reason, compatibility = "identity_vs_state", "The identity is shared; state modifiers differ and must remain a separate claim.", "coarse"
    elif left["node"] in _ancestors(right["node"], taxonomy) or right["node"] in _ancestors(left["node"], taxonomy):
        kind, reason, compatibility = "granularity_difference", "One identity is a broader ancestor of the other; this is coarse compatibility, not an exact synonym.", "coarse"
    else:
        kind, reason = "lineage_conflict", "The labels claim distinct identity branches; marker evidence must adjudicate this disagreement."
    return {"kind": kind, "compatibility": compatibility, "reason": reason, "left": left, "right": right}


def _cluster(evidence, cluster_id):
    if not isinstance(cluster_id, (str, int)) or isinstance(cluster_id, bool):
        raise DirectedError("clusterId must be a string or integer")
    cluster_id = str(cluster_id)
    cluster = next((row for row in evidence["clusters"] if row["id"] == cluster_id), None)
    if not cluster:
        raise DirectedError("Cluster is not in the current evidence")
    if cluster["cellIds"] != sorted(set(cluster["cellIds"])) or len(cluster["cellIds"]) != cluster["cellCount"]:
        raise DirectedError("Cluster cell IDs are not an exact canonical scope")
    return cluster


def _scope(evidence, cluster, dimension="type"):
    return {"datasetId": evidence["dataset"]["id"], "revision": evidence["revision"],
            "clusterId": cluster["id"], "dimension": dimension, "cellIds": list(cluster["cellIds"])}


def _human(session, cluster_id):
    if not isinstance(session, dict):
        return None
    matches = [item for item in session.get("decisions", []) if item.get("scope", {}).get("clusterId") == cluster_id
               and item.get("scope", {}).get("dimension") == "type" and not item.get("undone")]
    if not matches:
        return None
    fresh = [item for item in matches if not item.get("stale")]
    return copy.deepcopy((fresh or matches)[-1])


def make_plan(evidence, cluster_id="6", expression=None):
    """A typed allowlist of read-only local queries; callers execute separately."""
    cluster = _cluster(evidence, cluster_id)
    taxonomy = load_taxonomy()
    scope = _scope(evidence, cluster)
    availability = "local_bundle_available" if expression is not None else "requires_local_execution"
    definitions = [
        ("local.expression_panel", "Inspect the existing full RNA counts and normalized data for identity, subtype-support and shared cytotoxic genes; top-30 absence is not expression absence.",
         {"assay": "RNA", "layers": ["counts", "data"], "panels": {key: list(value) for key, value in PANELS.items()}, "missingValue": None}),
        ("local.coexpression", "Check distributions in individual scoped cells, separating same-cell coexpression from separate T/NK subpopulations and rare extreme observations.",
         {"assay": "RNA", "layer": "counts", "detection": "count > 0", "TAnchors": list(PANELS["T_identity"]),
          "NKAnchors": list(PANELS["NK_identity"]), "anchorCount": 2, "excludeFromIdentityGates": list(PANELS["T_subtype_support"] + PANELS["nonexclusive"] + PANELS["shared_cytotoxic"])}),
        ("local.qc_summary", "Read existing whole-library depth and mitochondrial QC; low detection in shallow libraries cannot establish biological absence.",
         {"metadata": ["nCount_RNA", "nFeature_RNA", "percent.mt"], "recompute": False, "uncalibrated": True}),
    ]
    steps = []
    for tool, reason, parameters in definitions:
        step_scope = _scope(evidence, cluster, "QC" if tool == "local.qc_summary" else "type")
        step = {"tool": tool, "reason": reason, "scope": step_scope, "parameters": parameters,
                "readOnly": True, "availability": availability}
        step["id"] = "step:" + digest(step)
        steps.append(step)
    plan = {"schemaVersion": 1, "taxonomyVersion": taxonomy["version"], "taxonomyHash": taxonomy["hash"],
            "scope": scope, "readOnly": True, "allowedTools": list(TOOLS), "steps": steps,
            "stopRules": ["No matrix leaves localhost.", "Missing features remain missing, not measured zeros.",
                          "No automatic deletion, splitting, NKT/doublet diagnosis or acceptance of a human decision."]}
    plan["id"] = "plan:" + digest(plan)
    return plan


def triage(evidence, session=None):
    taxonomy = load_taxonomy()
    clusters = []
    for cluster in sorted(evidence["clusters"], key=lambda item: item["id"]):
        issues, strict_labels, posthoc_labels = [], [], []
        for model in cluster["models"]:
            status = model["strict"]["status"]
            source_ref = "model:" + model["callId"] + ":strict"
            strict_label = model["strict"].get("label")
            if status == "valid" and (not isinstance(strict_label, str) or not strict_label.strip()):
                issues.append({"kind": "format_failure", "reason": "Strict projection declares validity but its label is missing, blank or not a scalar string. It is not an unknown biological annotation.",
                               "evidenceRefs": [source_ref], "lane": "strict"})
            elif status != "valid":
                kind = "execution_failure" if status == "network_failed" else "format_failure"
                issues.append({"kind": kind, "reason": model["strict"].get("formatReason") or status,
                               "evidenceRefs": [source_ref], "lane": "strict"})
            else:
                strict_labels.append({"callId": model["callId"], "label": model["strict"]["label"],
                                      "descriptor": describe_label(model["strict"]["label"], taxonomy), "evidenceRef": source_ref})
            posthoc_labels.append({"callId": model["callId"], "label": model["posthoc"].get("label"),
                                   "status": model["posthoc"].get("status"), "normalizationApplied": model["posthoc"].get("normalizationApplied", False),
                                   "evidenceRef": "model:" + model["callId"] + ":posthoc"})
        for item in strict_labels:
            descriptor = item["descriptor"]
            if not descriptor["known"]:
                issues.append({"kind": "lexicon_unknown", "reason": "Strict label is absent from the explicit local vocabulary; no automatic fuzzy normalization was applied.",
                               "evidenceRefs": [item["evidenceRef"]], "lane": "strict", "label": item["label"]})
                continue
            if descriptor.get("abstention") or descriptor["dimension"] != "type" or descriptor["node"] is None:
                continue
            comparisons = [classify_pair(item["label"], row["label"], taxonomy) for row in cluster["candidates"]]
            compatible = [comparison for comparison in comparisons if comparison["compatibility"] in ("exact", "coarse")]
            if not compatible:
                issues.append({"kind": "candidate_missing", "reason": "The recognized model identity has no exact or ancestor-compatible label in the displayed database candidates. This is a candidate-list limitation, not proof the prediction is false.",
                               "evidenceRefs": [item["evidenceRef"], "candidates:cluster:" + cluster["id"]], "lane": "strict", "label": item["label"]})
        for candidate in cluster["candidates"]:
            if not describe_label(candidate["label"], taxonomy)["known"]:
                issues.append({"kind": "lexicon_unknown", "reason": "A database candidate is absent from the local vocabulary; its spelling is preserved rather than silently corrected.",
                               "evidenceRefs": ["candidates:cluster:" + cluster["id"]], "lane": "candidate_comparison", "label": candidate["label"]})
        for left, right in itertools.combinations(strict_labels, 2):
            if _label_key(left["label"]) == _label_key(right["label"]):
                continue
            comparison = classify_pair(left["label"], right["label"], taxonomy)
            if comparison["kind"] is not None:
                issues.append({**comparison, "lane": "strict", "evidenceRefs": [left["evidenceRef"], right["evidenceRef"]]})
        # Candidate granularity is shown without declaring every alternative a biological conflict.
        for item in strict_labels:
            for candidate in cluster["candidates"]:
                comparison = classify_pair(item["label"], candidate["label"], taxonomy)
                if comparison["kind"] in ("granularity_difference", "identity_vs_state"):
                    issues.append({**comparison, "lane": "candidate_comparison", "evidenceRefs": [item["evidenceRef"], "candidates:cluster:" + cluster["id"]]})
        issues = sorted({digest(issue): issue for issue in issues}.values(), key=lambda issue: (CLASSIFICATIONS.index(issue["kind"]), canonical(issue)))
        clusters.append({"clusterId": cluster["id"], "scope": _scope(evidence, cluster), "issues": issues,
                         "classifications": [kind for kind in CLASSIFICATIONS if any(issue["kind"] == kind for issue in issues)],
                         "strictLabels": strict_labels, "posthocLabels": posthoc_labels,
                         "humanDecision": _human(session, cluster["id"]), "plan": make_plan(evidence, cluster["id"])})
    return {"schemaVersion": 1, "revision": evidence["revision"], "taxonomyVersion": taxonomy["version"],
            "taxonomyHash": taxonomy["hash"], "classifications": list(CLASSIFICATIONS), "clusters": clusters}


def _numeric(value, context, integer=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        raise DirectedError("Invalid nonnegative measurement: " + context)
    if integer and int(value) != value:
        raise DirectedError("Expected integer count: " + context)
    return int(value) if integer else float(value)


def _thresholds(override):
    result = dict(DEFAULT_THRESHOLDS)
    if override is not None:
        if not isinstance(override, dict) or not set(override).issubset(result):
            raise DirectedError("Unknown heuristic threshold")
        result.update(override)
    for key, value in result.items():
        _numeric(value, key, key in ("anchorCount", "minimumPositiveCells", "minimumMeasuredTAnchors", "minimumMeasuredNKAnchors"))
        if key.endswith("Fraction"):
            if not 0 <= value <= 1:
                raise DirectedError("Fractions must be between 0 and 1")
        elif value <= 0:
            raise DirectedError("Heuristic thresholds must be positive")
    if not 1 <= result["anchorCount"] <= 4 or not 1 <= result["minimumMeasuredTAnchors"] <= 6 or not 1 <= result["minimumMeasuredNKAnchors"] <= 4:
        raise DirectedError("Anchor thresholds exceed the fixed panel")
    return result


def _median(values):
    values = sorted(values)
    middle = len(values) // 2
    return values[middle] if len(values) % 2 else (values[middle - 1] + values[middle]) / 2


def _measure(expression, cluster, thresholds, evidence=None):
    if not isinstance(expression, dict) or not isinstance(expression.get("scope"), dict):
        raise DirectedError("Expression bundle must provide an explicit scope")
    scope = expression["scope"]
    if str(scope.get("cluster_id")) != cluster["id"] or scope.get("cell_ids") != cluster["cellIds"] or scope.get("n_cells") != cluster["cellCount"]:
        raise DirectedError("Expression scope must exactly match current cluster and cell IDs")
    source = expression.get("source")
    if (not isinstance(source, dict) or source.get("assay") != "RNA"
            or source.get("layers") != {"counts": "counts", "data": "data"}):
        raise DirectedError("Only the existing RNA assay is allowed")
    for key in ("rds_sha256", "cell_map_sha256", "extractor_sha256"):
        value = source.get(key)
        if not isinstance(value, str) or len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
            raise DirectedError("Missing actual source hash: " + key)
    if evidence is not None:
        recorded_sources = {row["id"]: row["sha256"] for row in evidence.get("sources", [])}
        for source_key, source_id in (("cell_map_sha256", "pbmc3k_reference_inputs/input_cells.csv"),
                                      ("retained_labels_sha256", "pbmc3k_verified/scagentkit_fixed_labels.csv"),
                                      ("umap_sha256", "pbmc3k_verified/scagentkit_fixed_umap.csv")):
            if source_id in recorded_sources and source.get(source_key) != recorded_sources[source_id]:
                raise DirectedError("Expression source differs from current evidence: " + source_key)
    panel = expression.get("panel")
    if not isinstance(panel, list):
        raise DirectedError("Expression panel must be a list")
    features = {}
    for row in panel:
        if not isinstance(row, dict) or not isinstance(row.get("gene"), str) or row["gene"] in features:
            raise DirectedError("Invalid or duplicated panel feature")
        if row.get("measurement_status") not in ("measured", "missing"):
            raise DirectedError("Panel features must distinguish measured from missing")
        features[row["gene"]] = row
    if not set(PANEL_GENES).issubset(features):
        raise DirectedError("Fixed panel feature records are incomplete; absent features need explicit missing records")
    cells = expression.get("cells")
    if not isinstance(cells, list) or len(cells) != cluster["cellCount"]:
        raise DirectedError("Per-cell observations must cover the exact cluster scope")
    if any(not isinstance(cell, dict) or not isinstance(cell.get("cell_id"), str) for cell in cells):
        raise DirectedError("Invalid per-cell observation")
    if sorted(cell["cell_id"] for cell in cells) != cluster["cellIds"]:
        raise DirectedError("Duplicate, missing or foreign per-cell observations")
    detected = {gene: 0 for gene in PANEL_GENES}
    observations, count_depths, feature_depths, low_depth = [], [], [], 0
    for cell in sorted(cells, key=lambda row: row["cell_id"]):
        counts = cell.get("counts")
        normalized = cell.get("normalized")
        if not isinstance(counts, dict) or not isinstance(normalized, dict):
            raise DirectedError("Per-cell existing RNA counts and normalized data are required")
        for gene in PANEL_GENES:
            value = counts.get(gene)
            if features[gene]["measurement_status"] == "missing":
                if value is not None or normalized.get(gene) is not None:
                    raise DirectedError("Missing feature cannot have a numeric count or normalized value")
            else:
                value = _numeric(value, "RNA count " + gene, integer=True)
                normalized_value = _numeric(normalized.get(gene), "existing normalized RNA value " + gene)
                if (value == 0) != (normalized_value == 0):
                    raise DirectedError("Existing RNA counts and normalized detection disagree")
                detected[gene] += value > 0
        t_anchors = sum(counts.get(gene) is not None and counts[gene] > 0 for gene in PANELS["T_identity"])
        nk_anchors = sum(counts.get(gene) is not None and counts[gene] > 0 for gene in PANELS["NK_identity"])
        observations.append({"cellId": cell["cell_id"], "TAnchors": t_anchors, "NKAnchors": nk_anchors,
                             "TPositive": t_anchors >= thresholds["anchorCount"], "NKPositive": nk_anchors >= thresholds["anchorCount"]})
        qc = cell.get("qc", {})
        if not isinstance(qc, dict):
            raise DirectedError("QC observations must be an object")
        count_depth = qc.get("nCount_RNA")
        feature_depth = qc.get("nFeature_RNA")
        if count_depth is not None and feature_depth is not None:
            count_depth = _numeric(count_depth, "whole-library UMI count")
            feature_depth = _numeric(feature_depth, "whole-library detected features")
            count_depths.append(count_depth)
            feature_depths.append(feature_depth)
            low_depth += count_depth < thresholds["minimumMedianUMIs"] or feature_depth < thresholds["minimumMedianFeatures"]
    for gene in PANEL_GENES:
        feature = features[gene]
        if feature["measurement_status"] == "missing":
            if feature.get("detected_n") is not None or feature.get("detected_fraction", feature.get("fraction")) is not None:
                raise DirectedError("Missing feature detection summaries must be null")
        else:
            if "detected_n" in feature and _numeric(feature["detected_n"], "detected_n", integer=True) != detected[gene]:
                raise DirectedError("Panel detected counts disagree with per-cell observations")
            fraction = feature.get("detected_fraction", feature.get("fraction"))
            if fraction is not None and abs(_numeric(fraction, "detected fraction") - detected[gene] / len(cells)) > 1e-5:
                raise DirectedError("Panel detection fraction disagrees with per-cell observations")
    counts = {"t_only": 0, "nk_only": 0, "both": 0, "neither": 0}
    for cell in observations:
        key = "both" if cell["TPositive"] and cell["NKPositive"] else "t_only" if cell["TPositive"] else "nk_only" if cell["NKPositive"] else "neither"
        counts[key] += 1
    coverage = {"T": {"measured": [gene for gene in PANELS["T_identity"] if features[gene]["measurement_status"] == "measured"],
                       "missing": [gene for gene in PANELS["T_identity"] if features[gene]["measurement_status"] == "missing"]},
                "NK": {"measured": [gene for gene in PANELS["NK_identity"] if features[gene]["measurement_status"] == "measured"],
                        "missing": [gene for gene in PANELS["NK_identity"] if features[gene]["measurement_status"] == "missing"]}}
    qc = {"measuredCells": len(count_depths), "totalCells": len(cells), "lowDepthCells": low_depth,
          "lowDepthFraction": low_depth / len(count_depths) if count_depths else None,
          "medianUMIs": _median(count_depths) if count_depths else None,
          "medianFeatures": _median(feature_depths) if feature_depths else None}
    return {"counts": counts, "coverage": coverage, "qc": qc, "observations": observations,
            "genes": [{"gene": gene, "measurementStatus": features[gene]["measurement_status"],
                       "detectedCells": detected[gene] if features[gene]["measurement_status"] == "measured" else None,
                       "detectedFraction": detected[gene] / len(cells) if features[gene]["measurement_status"] == "measured" else None,
                       "normalized": copy.deepcopy(features[gene].get("normalized"))} for gene in PANEL_GENES]}


def _conclusion(measurements, thresholds, total):
    counts, coverage, qc = measurements["counts"], measurements["coverage"], measurements["qc"]
    def qualified(number):
        return number >= thresholds["minimumPositiveCells"] and number / total >= thresholds["minimumPositiveFraction"]
    t_positive, nk_positive = counts["t_only"] + counts["both"], counts["nk_only"] + counts["both"]
    robust_same_cell = qualified(counts["both"])
    robust_separate = qualified(counts["t_only"]) and qualified(counts["nk_only"])
    quality = (qc["measuredCells"] == total and qc["medianUMIs"] >= thresholds["minimumMedianUMIs"]
               and qc["medianFeatures"] >= thresholds["minimumMedianFeatures"]
               and qc["lowDepthFraction"] <= thresholds["maximumLowDepthFraction"])
    enough_coverage = (len(coverage["T"]["measured"]) >= thresholds["minimumMeasuredTAnchors"]
                       and len(coverage["NK"]["measured"]) >= thresholds["minimumMeasuredNKAnchors"])
    if robust_same_cell or robust_separate:
        return "mixed_candidate", ["T-compatible RNA program", "NK-compatible RNA program"], "Robust observed coexpression or separate positive subpopulations require manual review. This is not an NKT or doublet diagnosis."
    if not quality:
        return "unresolved", [], "Whole-library depth is missing or below an uncalibrated QC gate; low detection cannot establish biological absence."
    if not enough_coverage:
        return "unresolved", [], "The measured identity panel has insufficient coverage for this heuristic."
    positive = []
    if qualified(t_positive):
        positive.append("T-compatible RNA program")
    if qualified(nk_positive):
        positive.append("NK-compatible RNA program")
    if not positive:
        return "unresolved", [], "No identity-anchor program meets the positive-cell count and fraction gates. Shared cytotoxic genes and CD8A alone cannot choose a lineage."
    if len(positive) == 2:
        return "unresolved", positive, "Both aggregate observed programs pass the positive gate, but neither same-cell nor separate-population distribution passes the robust mixed gate. Retain alternatives and review the individual cells."
    missing = coverage["T"]["missing"] or coverage["NK"]["missing"]
    rare_other = counts["both"] > 0 or (counts["t_only"] > 0 and counts["nk_only"] > 0)
    if missing or rare_other:
        return "coarse_only", positive, "Positive RNA evidence supports only a broad compatible program. Missing anchors or rare opposing observations prevent exclusions or finer identity claims."
    return "supported", positive, "Positive broad RNA program passes uncalibrated review gates; this remains provisional and does not establish exclusive identity or subtype."


def _control_contrasts(expression, measurements):
    """Report measured contrast changes, without treating controls as truth."""
    comparison = expression.get("comparisons", {})
    if not isinstance(comparison, dict):
        raise DirectedError("Control comparisons must be an object")
    def panel_for(key):
        record = comparison.get(key)
        if record is None:
            return {}
        if not isinstance(record, dict) or not isinstance(record.get("panel"), list):
            raise DirectedError("Control comparison needs an explicit panel")
        rows = {}
        for row in record["panel"]:
            if not isinstance(row, dict) or not isinstance(row.get("gene"), str) or row["gene"] in rows:
                raise DirectedError("Invalid or duplicated control feature")
            rows[row["gene"]] = row
        return rows
    all_rest, relevant = panel_for("all_rest"), panel_for("candidate_lymphocyte")
    if not all_rest and not relevant:
        return []
    def fraction(rows, gene):
        row = rows.get(gene)
        if row is None or row.get("measurement_status") == "missing":
            return None
        value = row.get("detected_fraction", row.get("fraction"))
        if value is None:
            return None
        value = _numeric(value, "control detected fraction")
        if value > 1:
            raise DirectedError("Control fractions must be between zero and one")
        return value
    result = []
    for feature in measurements["genes"]:
        gene = feature["gene"]
        target = feature["detectedFraction"]
        rest = fraction(all_rest, gene)
        candidate = fraction(relevant, gene)
        rest_delta = target - rest if target is not None and rest is not None else None
        candidate_delta = target - candidate if target is not None and candidate is not None else None
        if rest_delta is None or candidate_delta is None:
            outcome = "missing_comparator"
        elif rest_delta > 1e-12 and candidate_delta <= 1e-12:
            outcome = "disappears_or_reverses_against_candidate"
        elif rest_delta > 1e-12 and candidate_delta < rest_delta - 1e-12:
            outcome = "weaker_against_candidate"
        elif rest_delta > 1e-12 and candidate_delta > 1e-12:
            outcome = "positive_in_both"
        else:
            outcome = "no_positive_all_rest_contrast"
        result.append({"gene": gene, "targetDetectedFraction": target, "allRestDetectedFraction": rest,
                       "candidateDetectedFraction": candidate, "allRestDelta": rest_delta,
                       "candidateDelta": candidate_delta, "outcome": outcome,
                       "evidenceRefs": ["gene:" + gene, "controls:all_rest:" + gene, "controls:candidate_lymphocyte:" + gene]})
    return result


def _contrast_conclusion(status, candidates, stop_reason, contrasts):
    disappeared = [row["gene"] for row in contrasts if row["outcome"] == "disappears_or_reverses_against_candidate"]
    if disappeared:
        stop_reason += " All-rest detection enrichment disappears or reverses against candidate lymphocyte controls for: " + ", ".join(disappeared) + ". These contrasts do not prove identity or biological absence."
        identity_genes = set(PANELS["T_identity"] + PANELS["NK_identity"])
        if status == "supported" and identity_genes.intersection(disappeared):
            status = "coarse_only"
    return status, candidates, stop_reason


def propose(evidence, cluster_id="6", expression=None, session=None, thresholds=None):
    """Bare proposal: measured input drives conclusions; model names never vote."""
    cluster = _cluster(evidence, cluster_id)
    taxonomy = load_taxonomy()
    settings = _thresholds(thresholds)
    result = {"schemaVersion": 1, "scope": _scope(evidence, cluster), "taxonomyVersion": taxonomy["version"],
              "taxonomyHash": taxonomy["hash"], "ruleVersion": "positive-rna-review.v1", "uncalibrated": True,
              "thresholds": settings, "status": "unresolved", "granularity": "broad_program_only",
              "recommendedLabel": "unknown", "resolution": "unresolved_identity",
              "candidates": [], "support": [], "conflict": [], "missing": [], "nextSteps": [],
              "stopReason": "The typed local expression plan has not been executed.", "evidenceRefs": [],
              "readOnly": True, "automaticActions": [], "humanDecision": _human(session, cluster["id"])}
    result["nextSteps"] = [{"tool": step["tool"], "reason": step["reason"], "id": step["id"]}
                           for step in make_plan(evidence, cluster["id"], expression)["steps"]]
    if expression is not None:
        measurements = _measure(expression, cluster, settings, evidence)
        status, candidates, stop_reason = _conclusion(measurements, settings, cluster["cellCount"])
        contrasts = _control_contrasts(expression, measurements)
        status, candidates, stop_reason = _contrast_conclusion(status, candidates, stop_reason, contrasts)
        result.update(status=status, candidates=[{"label": label, "granularity": "broad_program", "workflowStatus": "proposed",
                                                  "role": "rna_program_evidence", "isCellTypeLabel": False} for label in candidates],
                      stopReason=stop_reason, measurements=measurements,
                      expressionHash=digest(expression), evidenceRefs=["coexpression:T_NK", "qc:depth"] + ["gene:" + gene for gene in PANEL_GENES])
        result["comparisonReview"] = contrasts
        result["comparisons"] = copy.deepcopy(expression.get("comparisons", {}))
        disappeared = [row for row in contrasts if row["outcome"] == "disappears_or_reverses_against_candidate"]
        if disappeared:
            result["conflict"].append({"kind": "relevant_comparator_enrichment_disappears",
                                       "genes": [row["gene"] for row in disappeared], "measurements": disappeared,
                                       "reason": "Positive all-rest detection contrast is absent or reversed against candidate lymphocyte controls. Controls are expression-selected, correlated and unverified; no identity is confirmed.",
                                       "evidenceRefs": [ref for row in disappeared for ref in row["evidenceRefs"]]})
        for lineage in ("T", "NK"):
            count = measurements["counts"]["t_only" if lineage == "T" else "nk_only"] + measurements["counts"]["both"]
            result["support"].append({"kind": "observed_identity_program", "lineage": lineage, "positiveCells": count,
                                      "totalCells": cluster["cellCount"], "fraction": count / cluster["cellCount"],
                                      "evidenceRefs": ["coexpression:T_NK"]})
        for item in measurements["genes"]:
            if item["measurementStatus"] == "missing":
                result["missing"].append({"gene": item["gene"], "reason": "Feature unavailable in the current stored RNA matrix/assay; not a measured zero or a claim about what the experiment measured.", "evidenceRef": "gene:" + item["gene"]})
        if measurements["counts"]["both"]:
            result["conflict"].append({"kind": "observed_same_cell_coexpression", "cells": measurements["counts"]["both"],
                                       "reason": "Descriptive observed T/NK anchor detection. Rare observations alone do not force a mixed classification; no NKT/doublet claim.", "evidenceRefs": ["coexpression:T_NK"]})
        if measurements["counts"]["t_only"] and measurements["counts"]["nk_only"]:
            result["conflict"].append({"kind": "observed_separate_positive_groups", "TCells": measurements["counts"]["t_only"], "NKCells": measurements["counts"]["nk_only"],
                                       "reason": "Separate observed programs can have the same cluster means as coexpressing cells; inspect the individual-cell distribution.", "evidenceRefs": ["coexpression:T_NK"]})
        controls = expression.get("candidate_controls", [])
        result["controls"] = copy.deepcopy(controls)
        if controls:
            result["conflict"].append({"kind": "control_specificity_limit", "reason": "Controls are correlated, unverified cluster summaries. All-rest enrichment can disappear against candidate lymphocyte controls; no control label is ground truth.", "evidenceRefs": ["controls:candidate_clusters"]})
        sensitivity = []
        for fraction in (.05, .10, .20):
            alternative = dict(settings, minimumPositiveFraction=fraction)
            alt_status, alt_candidates, _ = _conclusion(measurements, alternative, cluster["cellCount"])
            alt_status, alt_candidates, _ = _contrast_conclusion(alt_status, alt_candidates, "", contrasts)
            sensitivity.append({"parameter": "minimumPositiveFraction", "value": fraction, "status": alt_status, "candidatePrograms": alt_candidates})
        for anchors in (1, 2, 3):
            alternative = dict(settings, anchorCount=anchors)
            alternative_measurements = _measure(expression, cluster, alternative, evidence)
            alt_status, alt_candidates, _ = _conclusion(alternative_measurements, alternative, cluster["cellCount"])
            alt_status, alt_candidates, _ = _contrast_conclusion(alt_status, alt_candidates, "", contrasts)
            sensitivity.append({"parameter": "anchorCount", "value": anchors, "status": alt_status,
                                "candidatePrograms": alt_candidates, "observedCounts": alternative_measurements["counts"]})
        for depth in (500, 1000, 1500):
            alternative = dict(settings, minimumMedianUMIs=depth)
            alternative_measurements = _measure(expression, cluster, alternative, evidence)
            alt_status, alt_candidates, _ = _conclusion(alternative_measurements, alternative, cluster["cellCount"])
            alt_status, alt_candidates, _ = _contrast_conclusion(alt_status, alt_candidates, "", contrasts)
            sensitivity.append({"parameter": "minimumMedianUMIs", "value": depth, "status": alt_status,
                                "candidatePrograms": alt_candidates, "lowDepthFraction": alternative_measurements["qc"]["lowDepthFraction"]})
        result["sensitivity"] = sensitivity
        result["boundarySensitive"] = any(row["status"] != status or row["candidatePrograms"] != candidates for row in sensitivity)
        result["conclusionHash"] = digest({"status": status, "candidates": result["candidates"],
                                           "measurements": measurements, "thresholds": settings,
                                           "comparisonReview": contrasts,
                                           "ruleVersion": result["ruleVersion"], "taxonomyHash": taxonomy["hash"]})
    result["candidateSupport"] = copy.deepcopy(result["candidates"])
    broad_labels = {"T-compatible RNA program": "T cell", "NK-compatible RNA program": "NK cell"}
    if result["status"] == "supported" and len(result["candidates"]) == 1:
        provisional_label = broad_labels.get(result["candidates"][0]["label"])
        if provisional_label is not None:
            result["recommendedLabel"] = provisional_label
            result["resolution"] = "provisional_broad_identity"
    result["evidenceSummary"] = {"role": "rna_program_evidence", "identityEstablished": False,
                                  "programs": [candidate["label"] for candidate in result["candidates"]],
                                  "interpretation": "RNA program support is an evidence summary or tendency. Only sufficient positive support under the uncalibrated rules yields a provisional broad identity recommendation; incomplete or conflicting evidence retains unknown. No identity is established or automatically accepted. A human may make a separate type correction with its own reason and scope."}
    # Human history is deliberately excluded from the scientific conclusion ID.
    result["id"] = "proposal:" + digest({key: value for key, value in result.items() if key not in ("humanDecision", "id")})
    return result
