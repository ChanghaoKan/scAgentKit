#!/usr/bin/env python3
"""Optional read-only numeric crosscheck against the prior exploratory pilot.

This never imports pilot judgments, lineage gates, truth or model responses.
"""
import argparse
import hashlib
import json
from pathlib import Path


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare(expression_path, pilot_path):
    expression = json.loads(expression_path.read_text())
    pilot = json.loads(pilot_path.read_text())
    checks = []
    source_match = expression["source"]["rds_sha256"] == pilot["source"]["source_sha256"]
    checks.append({"check": "same_actual_rds_sha256", "passed": source_match})
    own_groups = {
        "cluster6": expression["panel"],
        "other_cells": expression["comparisons"]["all_rest"]["panel"],
    }
    denominator = {"cluster6": expression["scope"]["n_cells"], "other_cells": 2483}
    common_genes = set()
    for group, panel in own_groups.items():
        own_genes = {row["gene"]: row for row in panel}
        for row in pilot["gene_summary"]:
            gene = row["gene"]
            if row["comparison_group"] != group or gene not in own_genes:
                continue
            own = own_genes[gene]
            common_genes.add(gene)
            measured = own["measurement_status"] == "measured"
            fields = {
                "denominator": own["n_cells"] == row["n_cells"] == denominator[group],
                "measurement_status": measured == (row["counts_status"] == "present"),
                "detected_n": own["detected_n"] == row["detected_cells"],
            }
            for name, own_value, prior_value in (
                ("detected_fraction", own["detected_fraction"], row["raw_count_detection_fraction"]),
                ("existing_normalized_mean", own["normalized"]["all"]["mean"] if measured else None, row["existing_normalized_arithmetic_mean"]),
            ):
                fields[name] = own_value is None and prior_value is None or (
                    own_value is not None and prior_value is not None and abs(own_value - prior_value) <= 5e-13
                )
            checks.append({"check": f"{group}:{gene}", "passed": all(fields.values()), "fields": fields})
    return {
        "schema_version": "scAgentKit.directed_expression_crosscheck.v1",
        "status": "passed" if checks and all(check["passed"] for check in checks) else "failed",
        "expression_sha256": file_hash(expression_path),
        "pilot_summary_sha256": file_hash(pilot_path),
        "numeric_tolerance": 5e-13,
        "common_genes": sorted(common_genes),
        "checks": checks,
        "limitations": "Same source RNA object; numerical crosscheck only, not independent biological validation. Prior pilot gates and judgments are not imported.",
        "api_calls": 0,
        "source_files_modified": False,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--expression", required=True, type=Path)
    parser.add_argument("--pilot-summary", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = compare(args.expression, args.pilot_summary)
    data = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    if args.output.exists() and args.output.read_text() != data:
        raise SystemExit("Refusing to overwrite a different crosscheck")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(data)
    print(json.dumps({"status": result["status"], "checks": len(result["checks"]), "common_genes": len(result["common_genes"])}))
    raise SystemExit(0 if result["status"] == "passed" else 1)
