"""Scientific negative cases and pure, scoped directed review contracts."""
import copy
import hashlib
import json
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from directed import (CLASSIFICATIONS, DEFAULT_THRESHOLDS, PANEL_GENES, TOOLS, DirectedError,
                      classify_pair, describe_label, load_taxonomy, make_plan, propose, triage)


def sha(value):
    return hashlib.sha256(value.encode()).hexdigest()


def evidence_fixture(n=100):
    models = []
    for index, label in enumerate(("Terminal effector CD8+ T cell", "NK cell", "NK cell", "NK cell")):
        models.append({"callId": "test-%s" % index, "strict": {"status": "valid", "label": label},
                       "posthoc": {"status": "valid", "label": label, "normalizationApplied": False}})
    return {"dataset": {"id": "synthetic-scope"}, "revision": sha("synthetic core"),
            "sources": [{"id": "pbmc3k_reference_inputs/input_cells.csv", "sha256": sha("cellmap")},
                        {"id": "pbmc3k_verified/scagentkit_fixed_labels.csv", "sha256": sha("labels")},
                        {"id": "pbmc3k_verified/scagentkit_fixed_umap.csv", "sha256": sha("umap")}],
            "clusters": [{"id": "6", "cellCount": n, "cellIds": ["synthetic-%04d" % i for i in range(n)],
                          "models": models, "candidates": [{"label": "CD56+ natural killer cell"}, {"label": "CD8 T cell"}]}]}


def expression_fixture(evidence, t_only=0, nk_only=0, both=0, missing=(), depth=2000, features=900):
    cluster = evidence["clusters"][0]
    source = {"rds_sha256": sha("rds"), "cell_map_sha256": sha("cellmap"), "retained_labels_sha256": sha("labels"),
              "umap_sha256": sha("umap"), "extractor_sha256": sha("extractor"), "assay": "RNA", "layers": {"counts": "counts", "data": "data"}}
    cells = []
    for index, cell_id in enumerate(cluster["cellIds"]):
        counts = {gene: None if gene in missing else 0 for gene in PANEL_GENES}
        t_gate = index < t_only or t_only + nk_only <= index < t_only + nk_only + both
        nk_gate = t_only <= index < t_only + nk_only + both
        for gene in ("CD3D", "CD3E") if t_gate else ():
            if gene not in missing:
                counts[gene] = 1
        for gene in ("KLRD1", "KLRF1") if nk_gate else ():
            if gene not in missing:
                counts[gene] = 1
        cells.append({"cell_id": cell_id, "counts": counts, "normalized": dict(counts),
                      "qc": {"nCount_RNA": depth, "nFeature_RNA": features}})
    return {"schema_version": "scAgentKit.directed_expression.v1", "source": source,
            "scope": {"cluster_id": "6", "n_cells": cluster["cellCount"], "cell_ids": cluster["cellIds"]},
            "panel": [{"gene": gene, "measurement_status": "missing" if gene in missing else "measured"} for gene in PANEL_GENES],
            "cells": cells, "candidate_controls": []}


class TaxonomyTests(unittest.TestCase):
    def test_versioned_registry_unknown_is_preserved(self):
        taxonomy = load_taxonomy()
        self.assertEqual(taxonomy["version"], "pbmc-review-taxonomy.v1")
        self.assertEqual(len(taxonomy["hash"]), 64)
        unknown = describe_label("Novel phenotype xyz")
        self.assertFalse(unknown["known"])
        self.assertEqual(unknown["raw"], "Novel phenotype xyz")
        self.assertEqual(classify_pair("Novel phenotype xyz", "NK cell")["kind"], "lexicon_unknown")

    def test_explicit_alias_is_exact_but_cd56_is_coarse(self):
        exact = classify_pair("NK cell", "Natural killer cell")
        self.assertEqual((exact["kind"], exact["compatibility"]), ("explicit_synonym", "exact"))
        coarse = classify_pair("NK cell", "CD56+ natural killer cell")
        self.assertEqual((coarse["kind"], coarse["compatibility"]), ("granularity_difference", "coarse"))
        self.assertNotEqual(coarse["left"]["node"], coarse["right"]["node"])

    def test_lineage_and_identity_state_distinct(self):
        self.assertEqual(classify_pair("CD8 T cell", "NK cell")["kind"], "lineage_conflict")
        self.assertEqual(classify_pair("Cytotoxic", "NK cell")["kind"], "identity_vs_state")
        self.assertEqual(classify_pair("Cytotoxic CD8+ T cell", "CD8 T cell")["kind"], "identity_vs_state")
        self.assertEqual(classify_pair("Platelet", "Megakaryocyte")["kind"], "lineage_conflict")
        self.assertFalse(describe_label("Patelet")["known"])

    def test_biological_unknown_is_abstention_not_lexicon_failure(self):
        description = describe_label("Unknown")
        self.assertTrue(description["known"])
        self.assertTrue(description["abstention"])
        result = classify_pair("Unknown", "NK cell")
        self.assertIsNone(result["kind"])
        self.assertTrue(result["abstention"])
        evidence = evidence_fixture()
        evidence["clusters"][0]["models"][0]["strict"]["label"] = "Unknown"
        self.assertNotIn("lexicon_unknown", triage(evidence)["clusters"][0]["classifications"])


class TriageTests(unittest.TestCase):
    def setUp(self):
        self.evidence = evidence_fixture()

    def test_failure_not_converted_to_unknown_and_posthoc_separate(self):
        models = self.evidence["clusters"][0]["models"]
        models[0]["strict"] = {"status": "network_failed", "label": "unknown", "formatReason": "request unavailable"}
        models[0]["posthoc"] = {"status": "network_failed", "label": None}
        models[1]["strict"] = {"status": "format_rejected", "label": None, "formatReason": "Cluster prefix"}
        models[1]["posthoc"] = {"status": "valid", "label": "NK cell", "normalizationApplied": True}
        result = triage(self.evidence)["clusters"][0]
        self.assertIn("execution_failure", result["classifications"])
        self.assertIn("format_failure", result["classifications"])
        self.assertEqual(len(result["strictLabels"]), 2)
        self.assertEqual(result["posthocLabels"][1]["label"], "NK cell")
        self.assertNotIn("lexicon_unknown", result["classifications"])

    def test_candidate_missing_separate_from_lexicon_unknown(self):
        cluster = self.evidence["clusters"][0]
        cluster["candidates"] = [{"label": "CD56+ natural killer cell"}]
        cluster["models"][0]["strict"]["label"] = "CD4 T cell"
        cluster["models"][1]["strict"]["label"] = "Unregistered lineage"
        result = triage(self.evidence)["clusters"][0]
        self.assertIn("candidate_missing", result["classifications"])
        self.assertIn("lexicon_unknown", result["classifications"])
        missing = [row for row in result["issues"] if row["kind"] == "candidate_missing"]
        self.assertEqual([row["label"] for row in missing], ["CD4 T cell"])

    def test_valid_status_with_missing_or_invalid_label_is_format_failure(self):
        for value in (None, "", " ", 1, [], {}):
            evidence = copy.deepcopy(self.evidence)
            evidence["clusters"][0]["models"][0]["strict"]["label"] = value
            with self.subTest(label=value):
                result = triage(evidence)["clusters"][0]
                self.assertIn("format_failure", result["classifications"])
                self.assertNotIn("lexicon_unknown", result["classifications"])
                self.assertEqual(len(result["strictLabels"]), 3)

    def test_state_only_claim_is_not_a_missing_biological_candidate(self):
        self.evidence["clusters"][0]["models"] = [{"callId": "state-only", "strict": {"status": "valid", "label": "Cytotoxic"},
                                                 "posthoc": {"status": "valid", "label": "Cytotoxic"}}]
        result = triage(self.evidence)["clusters"][0]
        self.assertIn("identity_vs_state", result["classifications"])
        self.assertNotIn("candidate_missing", result["classifications"])

    def test_plan_scopes_tools_reason_and_read_only(self):
        before = copy.deepcopy(self.evidence)
        plan = make_plan(self.evidence)
        self.assertTrue(plan["readOnly"])
        self.assertEqual(tuple(step["tool"] for step in plan["steps"]), TOOLS)
        for step in plan["steps"]:
            self.assertEqual(step["scope"]["cellIds"], self.evidence["clusters"][0]["cellIds"])
            self.assertEqual(step["scope"]["revision"], self.evidence["revision"])
            self.assertTrue(step["reason"])
            self.assertTrue(step["id"])
            self.assertTrue(step["readOnly"])
        self.assertEqual(self.evidence, before)
        self.assertEqual(make_plan(self.evidence), plan)
        with self.assertRaises(DirectedError):
            make_plan(self.evidence, "99")


class ProposalTests(unittest.TestCase):
    def setUp(self):
        self.evidence = evidence_fixture()

    def test_no_bundle_is_unresolved_without_fabricated_expression(self):
        result = propose(self.evidence)
        self.assertEqual(result["status"], "unresolved")
        self.assertEqual(result["candidates"], [])
        self.assertNotIn("measurements", result)
        self.assertTrue(result["nextSteps"])

    def test_full_positive_panel_support_is_provisional_and_broad(self):
        result = propose(self.evidence, expression=expression_fixture(self.evidence, nk_only=40))
        self.assertEqual(result["status"], "supported")
        self.assertEqual(result["candidates"][0]["label"], "NK-compatible RNA program")
        self.assertEqual(result["granularity"], "broad_program_only")
        self.assertTrue(result["uncalibrated"])
        self.assertEqual(result["automaticActions"], [])
        self.assertTrue(result["readOnly"])
        self.assertEqual(result["recommendedLabel"], "NK cell")
        self.assertEqual(result["resolution"], "provisional_broad_identity")
        self.assertFalse(result["candidateSupport"][0]["isCellTypeLabel"])
        self.assertFalse(result["evidenceSummary"]["identityEstablished"])

    def test_sufficient_t_program_derives_provisional_identity_from_evidence(self):
        result = propose(self.evidence, expression=expression_fixture(self.evidence, t_only=40))
        self.assertEqual(result["status"], "supported")
        self.assertEqual(result["recommendedLabel"], "T cell")
        self.assertEqual(result["resolution"], "provisional_broad_identity")
        self.assertFalse(result["evidenceSummary"]["identityEstablished"])
        self.assertTrue(result["uncalibrated"])
        self.assertEqual(result["automaticActions"], [])
        # Both synthetic supported cases use cluster 6. Its real unknown result is
        # derived from incomplete/conflicting measured evidence, not this ID.
        self.assertEqual(result["scope"]["clusterId"], "6")

    def test_missing_and_measured_zero_are_different(self):
        result = propose(self.evidence, expression=expression_fixture(self.evidence, nk_only=40, missing=("TRAC", "TRBC1", "TRBC2")))
        self.assertEqual(result["status"], "coarse_only")
        self.assertEqual(result["recommendedLabel"], "unknown")
        self.assertEqual(result["resolution"], "unresolved_identity")
        self.assertEqual(result["candidateSupport"][0]["label"], "NK-compatible RNA program")
        self.assertEqual(result["candidateSupport"][0]["role"], "rna_program_evidence")
        self.assertFalse(result["candidateSupport"][0]["isCellTypeLabel"])
        by_gene = {row["gene"]: row for row in result["measurements"]["genes"]}
        self.assertIsNone(by_gene["TRAC"]["detectedCells"])
        self.assertEqual(by_gene["CD3D"]["detectedCells"], 0)
        self.assertEqual(by_gene["CD3D"]["measurementStatus"], "measured")
        self.assertEqual({row["gene"] for row in result["missing"]}, {"TRAC", "TRBC1", "TRBC2"})

    def test_shared_cytotoxic_cd8a_fcgr3a_alone_never_choose_lineage(self):
        for genes in (("NKG7", "GNLY", "PRF1"), ("CD8A",), ("FCGR3A",)):
            bundle = expression_fixture(self.evidence)
            for cell in bundle["cells"]:
                for gene in genes:
                    cell["counts"][gene] = cell["normalized"][gene] = 2
            with self.subTest(genes=genes):
                result = propose(self.evidence, expression=bundle)
                self.assertEqual(result["status"], "unresolved")
                self.assertEqual(result["candidates"], [])

    def test_same_cluster_means_cannot_replace_cell_distribution(self):
        coexpressed = propose(self.evidence, expression=expression_fixture(self.evidence, both=20))
        segregated = propose(self.evidence, expression=expression_fixture(self.evidence, t_only=20, nk_only=20))
        for result in (coexpressed, segregated):
            self.assertEqual(result["status"], "mixed_candidate")
            self.assertEqual(result["automaticActions"], [])
            labels = [row["label"] for row in result["candidates"]]
            self.assertFalse(any("NKT" in label or "doublet" in label for label in labels))
        self.assertEqual([row["detectedCells"] for row in coexpressed["measurements"]["genes"]],
                         [row["detectedCells"] for row in segregated["measurements"]["genes"]])
        self.assertNotEqual(coexpressed["measurements"]["counts"], segregated["measurements"]["counts"])
        self.assertNotEqual(coexpressed["conflict"][0]["kind"], segregated["conflict"][0]["kind"])

    def test_rare_extreme_coexpression_does_not_force_mixed(self):
        bundle = expression_fixture(self.evidence, nk_only=40, both=2)
        for cell in bundle["cells"][-60:-58]:
            for gene in ("CD3D", "CD3E", "KLRD1", "KLRF1"):
                cell["counts"][gene] = 500
                cell["normalized"][gene] = 5
        result = propose(self.evidence, expression=bundle)
        self.assertEqual(result["status"], "coarse_only")
        self.assertEqual(result["measurements"]["counts"]["both"], 2)
        self.assertIn("observed_same_cell_coexpression", [row["kind"] for row in result["conflict"]])

    def test_aggregate_positive_gates_cannot_bypass_mixed_distribution_gate(self):
        result = propose(self.evidence, expression=expression_fixture(self.evidence, t_only=6, nk_only=6, both=4))
        self.assertEqual(result["measurements"]["counts"], {"t_only": 6, "nk_only": 6, "both": 4, "neither": 84})
        self.assertEqual(result["status"], "unresolved")
        self.assertEqual(len(result["candidates"]), 2)
        self.assertIn("neither same-cell nor separate-population", result["stopReason"])

    def test_low_depth_and_missing_qc_stop_identity_claim(self):
        bundle = expression_fixture(self.evidence, nk_only=40, depth=600, features=300)
        self.assertEqual(propose(self.evidence, expression=bundle)["status"], "unresolved")
        bundle = expression_fixture(self.evidence, nk_only=40)
        bundle["cells"][0]["qc"] = {}
        self.assertEqual(propose(self.evidence, expression=bundle)["status"], "unresolved")

    def test_count_and_fraction_gates_both_required_and_boundaries_visible(self):
        result = propose(self.evidence, expression=expression_fixture(self.evidence, nk_only=9))
        self.assertEqual(result["status"], "unresolved")
        self.assertTrue(result["boundarySensitive"])
        result = propose(self.evidence, expression=expression_fixture(self.evidence, nk_only=10))
        self.assertEqual(result["status"], "supported")
        smaller = evidence_fixture(40)
        self.assertEqual(propose(smaller, expression=expression_fixture(smaller, nk_only=4))["status"], "unresolved")
        self.assertEqual(propose(smaller, expression=expression_fixture(smaller, nk_only=5))["status"], "supported")

    def test_insufficient_panel_coverage_never_coarse_without_positive_support(self):
        missing = ("CD3D", "CD3E", "TRAC", "TRBC1")
        self.assertEqual(propose(self.evidence, expression=expression_fixture(self.evidence, nk_only=40, missing=missing))["status"], "unresolved")
        self.assertEqual(propose(self.evidence, expression=expression_fixture(self.evidence, missing=("TRAC",)))["status"], "unresolved")

    def test_source_scope_and_invalid_measurements_fail_closed(self):
        for change in ("cluster", "cell", "duplicate", "missing_value", "negative_count", "fractional_count", "normalized", "layer", "source"):
            bundle = expression_fixture(self.evidence, nk_only=40, missing=("TRAC",))
            if change == "cluster":
                bundle["scope"]["cluster_id"] = "0"
            elif change == "cell":
                bundle["scope"]["cell_ids"] = ["wrong"]
            elif change == "duplicate":
                bundle["cells"][1] = copy.deepcopy(bundle["cells"][0])
            elif change == "missing_value":
                bundle["cells"][0]["counts"]["TRAC"] = 0
            elif change == "negative_count":
                bundle["cells"][0]["counts"]["KLRD1"] = -1
            elif change == "fractional_count":
                bundle["cells"][0]["counts"]["KLRD1"] = 1.2
            elif change == "normalized":
                bundle["cells"][0]["normalized"]["CD3D"] = 2
            elif change == "layer":
                bundle["source"]["layers"]["data"] = "scale.data"
            elif change == "source":
                bundle["source"]["cell_map_sha256"] = sha("other map")
            with self.subTest(change=change), self.assertRaises(DirectedError):
                propose(self.evidence, expression=bundle)

    def test_model_truth_and_human_labels_do_not_drive_rna_conclusion(self):
        bundle = expression_fixture(self.evidence, nk_only=40)
        first = propose(self.evidence, expression=bundle)
        changed = copy.deepcopy(self.evidence)
        for model in changed["clusters"][0]["models"]:
            model["strict"]["label"] = "B cell"
        changed["clusters"][0]["candidates"] = [{"label": "Platelet"}]
        changed["syntheticTruthText"] = "Any hypothetical author label"
        event = {"id": "human-accepted", "label": "CD8 T cell", "status": "accepted", "stale": False,
                 "scope": {"clusterId": "6", "dimension": "type"}, "hash": sha("immutable human history")}
        session = {"events": [event], "decisions": [event]}
        original = copy.deepcopy(session)
        result = propose(changed, expression=bundle, session=session)
        self.assertEqual(result["status"], first["status"])
        self.assertEqual(result["candidates"], first["candidates"])
        self.assertEqual(result["conclusionHash"], first["conclusionHash"])
        self.assertEqual(result["id"], first["id"])
        self.assertEqual(result["humanDecision"]["status"], "accepted")
        self.assertEqual(session, original)
        result["humanDecision"]["label"] = "try to mutate"
        self.assertEqual(session, original)

    def test_reordering_observations_keeps_measured_conclusion_identical(self):
        bundle = expression_fixture(self.evidence, nk_only=40)
        first = propose(self.evidence, expression=bundle)
        bundle["cells"].reverse()
        second = propose(self.evidence, expression=bundle)
        self.assertEqual(first["conclusionHash"], second["conclusionHash"])
        self.assertEqual(first["measurements"], second["measurements"])

    def test_heuristic_thresholds_are_explicit_validated_and_configurable(self):
        bundle = expression_fixture(self.evidence, nk_only=9)
        result = propose(self.evidence, expression=bundle, thresholds={"minimumPositiveFraction": .05})
        self.assertEqual(result["status"], "supported")
        self.assertEqual(result["thresholds"]["minimumPositiveFraction"], .05)
        for settings in ({"probability": .9}, {"anchorCount": 0}, {"minimumPositiveFraction": float("nan")}, {"minimumPositiveCells": True}):
            with self.subTest(settings=settings), self.assertRaises(DirectedError):
                propose(self.evidence, expression=bundle, thresholds=settings)

    def test_relevant_comparator_changes_actual_enrichment_disclosure(self):
        bundle = expression_fixture(self.evidence, nk_only=40)
        bundle["comparisons"] = {"all_rest": {"n_cells": 200, "panel": [{"gene": "KLRD1", "measurement_status": "measured", "detected_fraction": .01}]},
                                 "candidate_lymphocyte": {"n_cells": 100, "panel": [{"gene": "KLRD1", "measurement_status": "measured", "detected_fraction": .01}]}}
        first = propose(self.evidence, expression=bundle)
        self.assertEqual(first["status"], "supported")
        changed = copy.deepcopy(bundle)
        changed["comparisons"]["candidate_lymphocyte"]["panel"][0]["detected_fraction"] = .8
        second = propose(self.evidence, expression=changed)
        self.assertEqual(second["status"], "coarse_only")
        self.assertNotEqual(first["stopReason"], second["stopReason"])
        self.assertIn("KLRD1", second["stopReason"])
        self.assertIn("relevant_comparator_enrichment_disappears", [row["kind"] for row in second["conflict"]])
        row = next(row for row in second["comparisonReview"] if row["gene"] == "KLRD1")
        self.assertAlmostEqual(row["allRestDelta"], .39)
        self.assertAlmostEqual(row["candidateDelta"], -.4)
        self.assertNotEqual(first["conclusionHash"], second["conclusionHash"])

    def test_comparator_missing_is_not_measured_zero(self):
        bundle = expression_fixture(self.evidence, nk_only=40)
        bundle["comparisons"] = {"all_rest": {"panel": [{"gene": "KLRD1", "measurement_status": "measured", "detected_fraction": 0}]},
                                 "candidate_lymphocyte": {"panel": [{"gene": "KLRD1", "measurement_status": "missing", "detected_fraction": None}]}}
        result = propose(self.evidence, expression=bundle)
        row = next(row for row in result["comparisonReview"] if row["gene"] == "KLRD1")
        self.assertEqual(row["allRestDetectedFraction"], 0)
        self.assertIsNone(row["candidateDetectedFraction"])
        self.assertEqual(row["outcome"], "missing_comparator")


@unittest.skipUnless(os.environ.get("SCAGENTKIT_TEST_RESULTS") and os.environ.get("SCAGENTKIT_TEST_EXPRESSION"), "Set both real evidence environment variables")
class RealDirectedTests(unittest.TestCase):
    def test_real_nine_cluster_triage_and_scoped_rna_proposal(self):
        from evidence import EvidenceLoader
        evidence = EvidenceLoader(os.environ["SCAGENTKIT_TEST_RESULTS"]).load()
        bundle = json.loads(Path(os.environ["SCAGENTKIT_TEST_EXPRESSION"]).read_text())
        clusters = triage(evidence)["clusters"]
        self.assertEqual(len(clusters), 9)
        self.assertIn("lineage_conflict", clusters[6]["classifications"])
        self.assertIn("execution_failure", clusters[4]["classifications"])
        self.assertIn("format_failure", clusters[2]["classifications"])
        result = propose(evidence, expression=bundle)
        self.assertEqual(len(result["scope"]["cellIds"]), 155)
        self.assertEqual(result["measurements"]["counts"], {"t_only": 13, "nk_only": 39, "both": 2, "neither": 101})
        self.assertEqual(result["status"], "coarse_only")
        self.assertEqual(result["recommendedLabel"], "unknown")
        self.assertEqual(result["resolution"], "unresolved_identity")
        self.assertEqual(result["candidateSupport"][0]["label"], "NK-compatible RNA program")
        self.assertFalse(result["candidateSupport"][0]["isCellTypeLabel"])
        self.assertFalse(result["evidenceSummary"]["identityEstablished"])
        self.assertEqual({row["gene"] for row in result["missing"]}, {"TRAC", "TRBC1", "TRBC2"})
        self.assertTrue(all("current stored RNA matrix/assay" in row["reason"] for row in result["missing"]))
        self.assertTrue(result["boundarySensitive"])
        self.assertEqual(result["automaticActions"], [])


if __name__ == "__main__":
    unittest.main()
