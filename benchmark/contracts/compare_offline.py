#!/usr/bin/env python3
"""Validate evaluator-only artifacts; never call providers or score candidates as labels."""
import argparse
import csv
import hashlib
import json
from pathlib import Path


class ContractError(ValueError):
    pass


def read_bound(root, item):
    path = (root / item["path"]).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ContractError("Artifact must be an existing file inside the experiment directory")
    if hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]:
        raise ContractError("Artifact checksum differs: " + item["path"])
    with path.open(encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    ids = [r.get("cell_id", "") for r in rows]
    if not ids or any(not i.strip() for i in ids) or len(set(ids)) != len(ids):
        raise ContractError("Cell IDs must be nonempty and unique")
    return {row["cell_id"]: row for row in rows}


def compare(root):
    root = Path(root)
    manifest = json.loads((root / "comparison.json").read_text(encoding="utf-8"))
    if manifest.get("schema") != "scagentkit.offline-comparison.v1":
        raise ContractError("Unsupported contract schema")
    for key in ("dataset_role", "input_sha256", "protocol_sha256", "software_commit", "environment"):
        if not manifest.get(key):
            raise ContractError("Missing frozen provenance: " + key)
    if manifest["dataset_role"] not in ("synthetic_control", "development_case", "held_out"):
        raise ContractError("Unknown dataset role")
    for field in ("input_sha256", "protocol_sha256"):
        value = manifest[field]
        if not isinstance(value, str) or len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
            raise ContractError("Invalid SHA256: " + field)
    cells = read_bound(root, manifest["cells"])
    expected = set(cells)
    truth_record = manifest.get("truth")
    truth = None
    if truth_record is not None:
        if not all(truth_record.get(k) for k in ("source", "granularity", "mapping_sha256")):
            raise ContractError("Truth needs source, predeclared granularity and mapping hash")
        mapping_hash = truth_record["mapping_sha256"]
        if not isinstance(mapping_hash, str) or len(mapping_hash) != 64 or any(c not in "0123456789abcdef" for c in mapping_hash):
            raise ContractError("Invalid frozen truth mapping SHA256")
        truth = read_bound(root, truth_record)
        if set(truth) != expected:
            raise ContractError("Truth must use the exact frozen cell set")
        if any(r.get("status") not in ("reviewed", "ambiguous", "unlabeled") for r in truth.values()):
            raise ContractError("Unknown truth status")
        if any(not r.get("label", "").strip() for r in truth.values() if r["status"] == "reviewed"):
            raise ContractError("Reviewed truth requires a label")
    methods = manifest.get("methods", [])
    names = [m.get("name", "") for m in methods]
    if not names or any(not n for n in names) or len(set(names)) != len(names):
        raise ContractError("Methods need distinct names")
    result = {"schema": manifest["schema"], "dataset_role": manifest["dataset_role"],
              "scientific_accuracy_claim": False, "methods": []}
    for method in methods:
        rows = read_bound(root, method)
        if set(rows) != expected:
            raise ContractError("Methods must preserve the complete frozen cell set")
        statuses = {r.get("status") for r in rows.values()}
        if not statuses <= {"reviewed", "unknown", "excluded", "failed", "not_run"}:
            raise ContractError("Candidates are evidence, not reviewed predictions")
        if any(not r.get("label", "").strip() for r in rows.values() if r["status"] == "reviewed"):
            raise ContractError("Reviewed prediction requires an explicit label")
        if any(r.get("label", "").strip().lower() not in ("", "unknown")
               for r in rows.values() if r["status"] != "reviewed"):
            raise ContractError("Unreviewed rows must retain unknown labels")
        reviewed = [i for i, row in rows.items() if row["status"] == "reviewed"]
        entry = {"name": method["name"], "n_input": len(cells),
                 "status_counts": {s: sum(r["status"] == s for r in rows.values()) for s in sorted(statuses)},
                 "reviewed_coverage": len(reviewed) / len(cells),
                 "annotation_accuracy": None, "accuracy_denominator": 0,
                 "accuracy_status": "not_evaluated_no_truth"}
        if truth is not None:
            eligible = [i for i in cells if truth[i]["status"] == "reviewed"]
            entry["accuracy_denominator"] = len(eligible)
            entry["annotation_accuracy"] = (sum(rows[i]["status"] == "reviewed" and
                rows[i]["label"] == truth[i]["label"] for i in eligible) / len(eligible)) if eligible else None
            entry["accuracy_status"] = "synthetic_only" if manifest["dataset_role"] == "synthetic_control" else "reference_agreement_only"
        result["methods"].append(entry)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("experiment", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(compare(args.experiment), indent=2, allow_nan=False))
    except (ContractError, KeyError, TypeError, json.JSONDecodeError, OSError) as error:
        parser.exit(2, "Contract rejected: " + str(error) + "\n")
