"""Local targeted-expression tests. Real fixture is external and never committed."""
from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import shutil
import statistics
import subprocess
import unittest
from pathlib import Path

WORKBENCH = Path(__file__).resolve().parents[1]
REPOSITORY = WORKBENCH.parent
DEFAULT_EVIDENCE = REPOSITORY.parent / "phase3-evidence"
EVIDENCE = Path(os.environ.get("SCAGENTKIT_EXPRESSION_DIR", str(DEFAULT_EVIDENCE)))
RESULTS = Path(os.environ.get("SCAGENTKIT_RESULTS", str(REPOSITORY.parent.parent / "task-2/results")))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def quantile(values, p):
    values = sorted(values)
    if not values:
        return None
    offset = (len(values) - 1) * p
    lower = math.floor(offset)
    upper = math.ceil(offset)
    return values[lower] + (values[upper] - values[lower]) * (offset - lower)


class ExtractorSyntheticTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("Rscript"), "Rscript unavailable")
    def test_r_synthetic_missing_zero_mix_depth_and_invalid_inputs(self):
        environment = os.environ.copy()
        candidate = RESULTS.parent / ".r-lib"
        if candidate.is_dir() and "R_LIBS_USER" not in environment:
            environment["R_LIBS_USER"] = str(candidate)
        result = subprocess.run(
            ["Rscript", "--vanilla", str(WORKBENCH / "extract_directed.R"), "--self-test"],
            capture_output=True, text=True, env=environment, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("9 cases passed", result.stdout)


@unittest.skipUnless((EVIDENCE / "expression.json").exists(), "Generate external real expression fixture first")
class RealExpressionExportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bundle = json.loads((EVIDENCE / "expression.json").read_text())
        cls.cells = cls.bundle["cells"]
        cls.genes = {row["gene"]: row for row in cls.bundle["panel"]}

    def test_real_inventory_and_exact_scope_join(self):
        bundle = self.bundle
        self.assertEqual((bundle["inventory"]["n_cells"], bundle["inventory"]["n_clusters"]), (2638, 9))
        self.assertEqual(bundle["scope"]["cluster_id"], "6")
        ids = bundle["scope"]["cell_ids"]
        self.assertEqual(len(ids), 155)
        self.assertEqual(ids, sorted(set(ids)))
        self.assertEqual(ids, [cell["cell_id"] for cell in self.cells])
        canonical = json.dumps(ids, ensure_ascii=False, separators=(",", ":"))
        self.assertEqual(bundle["scope"]["cell_ids_sha256"], hashlib.sha256(canonical.encode()).hexdigest())
        with (RESULTS / "pbmc3k_reference_inputs/input_cells.csv").open() as stream:
            expected = sorted(row["cell_id"] for row in csv.DictReader(stream) if row["cluster"] == "6")
        self.assertEqual(ids, expected)
        with (RESULTS / "pbmc3k_verified/scagentkit_fixed_umap.csv").open() as stream:
            # Deliberately map reversed row order to verify ID based alignment.
            points = {row["cell_id"]: row for row in reversed(list(csv.DictReader(stream)))}
        for cell in self.cells:
            self.assertAlmostEqual(cell["umap"]["x"], float(points[cell["cell_id"]]["umap_1"]), places=12)
            self.assertAlmostEqual(cell["umap"]["y"], float(points[cell["cell_id"]]["umap_2"]), places=12)

    def test_actual_source_and_extractor_hashes_manifest(self):
        source = self.bundle["source"]
        sources = {
            "rds_sha256": RESULTS / "pbmc3k_verified/scagentkit_fixed_seurat.rds",
            "cell_map_sha256": RESULTS / "pbmc3k_reference_inputs/input_cells.csv",
            "retained_labels_sha256": RESULTS / "pbmc3k_verified/scagentkit_fixed_labels.csv",
            "umap_sha256": RESULTS / "pbmc3k_verified/scagentkit_fixed_umap.csv",
            "extractor_sha256": WORKBENCH / "extract_directed.R",
        }
        for field, path in sources.items():
            self.assertEqual(source[field], sha(path), field)
        manifest = json.loads((EVIDENCE / "expression-manifest.json").read_text())
        self.assertEqual(manifest["package_id"], self.bundle["package_id"])
        self.assertEqual(manifest["files"][0]["sha256"], sha(EVIDENCE / "expression.json"))
        self.assertTrue(manifest["read_only_sources_unchanged"])
        self.assertFalse(manifest["credentials_read"])
        self.assertEqual(manifest["network_calls"], 0)
        self.assertEqual(source["assay"], "RNA")
        self.assertEqual(source["layers"], {"counts": "counts", "data": "data"})
        self.assertTrue(source["counts_integer_nonnegative_validated"])

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript unavailable")
    def test_per_cell_panel_and_qc_independently_match_actual_rna_layers(self):
        environment = os.environ.copy()
        candidate = RESULTS.parent / ".r-lib"
        if candidate.is_dir() and "R_LIBS_USER" not in environment:
            environment["R_LIBS_USER"] = str(candidate)
        result = subprocess.run(
            ["Rscript", "--vanilla", str(WORKBENCH / "tests/verify_expression.R"),
             str(RESULTS / "pbmc3k_verified/scagentkit_fixed_seurat.rds"),
             str(EVIDENCE / "expression.json"), str(RESULTS / "pbmc3k_reference_inputs/input_cells.csv")],
            capture_output=True, text=True, env=environment, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["gene_checks"], 24)
        self.assertEqual(report["qc_checks"], 4)
        self.assertTrue(report["read_only_source_unchanged"])

    def test_missing_is_null_observed_zero_is_zero(self):
        self.assertEqual(set(self.bundle["coverage"]["missing_genes"]), {"TRAC", "TRBC1", "TRBC2"})
        self.assertEqual(self.bundle["coverage"]["measured_gene_n"], 21)
        for name in ("TRAC", "TRBC1", "TRBC2"):
            gene = self.genes[name]
            self.assertEqual(gene["measurement_status"], "missing")
            self.assertIsNone(gene["detected_n"])
            self.assertIsNone(gene["detected_fraction"])
            self.assertIsNone(gene["normalized"]["all"])
            for cell in self.cells:
                self.assertIsNone(cell["counts"][name])
                self.assertIsNone(cell["normalized"][name])
        observed_zero_cells = [cell for cell in self.cells if cell["counts"]["CD3D"] == 0]
        self.assertTrue(observed_zero_cells)
        self.assertTrue(all(cell["normalized"]["CD3D"] == 0 for cell in observed_zero_cells))
        self.assertEqual(self.genes["CD3D"]["measurement_status"], "measured")

    def test_counts_distribution_and_detection_reconstruct_from_local_panel(self):
        for name, gene in self.genes.items():
            if gene["measurement_status"] == "missing":
                continue
            values = [cell["counts"][name] for cell in self.cells]
            self.assertTrue(all(value >= 0 and value == int(value) for value in values))
            detected = [i for i, value in enumerate(values) if value > 0]
            self.assertEqual(gene["n_cells"], 155)
            self.assertEqual(gene["detected_n"], len(detected))
            self.assertAlmostEqual(gene["detected_fraction"], len(detected) / 155, places=13)
            normalized = [cell["normalized"][name] for cell in self.cells]
            for field, selected in (("all", normalized), ("detected", [normalized[i] for i in detected])):
                distribution = gene["normalized"][field]
                self.assertEqual(distribution["n"], len(selected))
                self.assertAlmostEqual(distribution["mean"], statistics.mean(selected), places=12)
                for key, p in (("q0", 0), ("q25", .25), ("q50", .5), ("q75", .75), ("q90", .9), ("max", 1)):
                    self.assertAlmostEqual(distribution[key], quantile(selected, p), places=12)

    def test_observed_gates_exclude_subtype_shared_and_nonexclusive(self):
        co = self.bundle["coexpression"]
        self.assertEqual(co["threshold_n"], 2)
        self.assertNotIn("CD8A", co["anchors"]["t"])
        self.assertNotIn("CD8B", co["anchors"]["t"])
        self.assertNotIn("FCGR3A", co["anchors"]["nk"])
        self.assertEqual(co["n_complete_gate_coverage"], 0)
        totals = dict(t_only=0, nk_only=0, both=0, neither=0)
        for cell in self.cells:
            t_n = sum((cell["counts"][gene] or 0) > 0 for gene in co["anchors"]["t"])
            nk_n = sum((cell["counts"][gene] or 0) > 0 for gene in co["anchors"]["nk"])
            self.assertEqual(cell["t_anchor_detected_n"], t_n)
            self.assertEqual(cell["nk_anchor_detected_n"], nk_n)
            self.assertEqual(cell["t_missing_anchor_n"], 3)
            if t_n < 2:
                self.assertIsNone(cell["t_identity_gate_possible"])
            label = "both" if t_n >= 2 and nk_n >= 2 else "t_only" if t_n >= 2 else "nk_only" if nk_n >= 2 else "neither"
            self.assertEqual(cell["coexpression_class"], label)
            totals[label] += 1
        self.assertEqual(co["counts"], totals)
        self.assertEqual(totals, dict(t_only=13, nk_only=39, both=2, neither=101))

    def test_depth_boundary_sensitivity_and_actual_qc_whitelist(self):
        qc = self.bundle["qc"]
        self.assertEqual(qc["threshold_status"], "exploratory_uncalibrated")
        self.assertEqual(qc["low_depth_n"], 2)
        self.assertEqual({row["field"] for row in qc["fields"]}, {"nCount_RNA", "nFeature_RNA", "percent.mt", "orig.ident"})
        for sensitivity in qc["sensitivity"]:
            config = sensitivity["config"]
            flags = [cell["qc"]["nCount_RNA"] < config["nCount_RNA_lt"] or cell["qc"]["nFeature_RNA"] < config["nFeature_RNA_lt"] for cell in self.cells]
            self.assertEqual(sensitivity["low_depth_n"], sum(flags))
            self.assertEqual(sensitivity["above_depth_threshold_n"], 155 - sum(flags))
        self.assertEqual([row["threshold_n"] for row in self.bundle["identity_threshold_sensitivity"]], [1, 2, 3])

    def test_controls_are_complete_correlated_and_not_truth_selected(self):
        controls = self.bundle["candidate_controls"]
        self.assertEqual([row["cluster_id"] for row in controls], [str(i) for i in range(9) if i != 6])
        self.assertEqual(sum(row["n_cells"] for row in controls), 2483)
        for control in controls:
            self.assertEqual(control["designation"], "candidate_control_unverified_correlated")
            self.assertEqual(control["selection"]["rule_status"], "exploratory_uncalibrated")
            self.assertNotIn("cells", control)
            self.assertNotIn("label", control)
        self.assertEqual(self.bundle["comparisons"]["all_rest"]["n_cells"], 2483)
        self.assertEqual(self.bundle["comparisons"]["candidate_lymphocyte"]["cluster_ids"], ["0", "2", "3", "4"])

    def test_no_truth_authorlabel_matrix_credentials_or_absolute_source_paths(self):
        serialized = json.dumps(self.bundle)
        for forbidden in ("/Users/", "API.R", "API_KEY", '"truth"', '"author_label"', '"doublet_score"', '"vdj"'):
            self.assertNotIn(forbidden, serialized)
        self.assertEqual(len(self.cells), 155)
        for cell in self.cells:
            self.assertEqual(set(cell["counts"]), set(self.genes))
            self.assertEqual(set(cell["normalized"]), set(self.genes))


if __name__ == "__main__":
    unittest.main(verbosity=2)
