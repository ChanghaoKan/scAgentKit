# Diagnostic QC and batch evidence

Engine opt-in: `sc_run(..., strategy=TRUE, biological_diagnostics=TRUE)`.
The independent `cluster_qc` and `batch_assessment` switches are recorded in
configuration. This does not change the three human approval boundaries.

The diagnostic checkpoint uses fixed seed 1234, up to 2,000 HVGs and 20 PCs,
20 neighbors and resolution 0.2 after the declared minimum prefilter.
Zero-count cells are excluded from diagnostics, not silently removed from the
scientific input. Failed diagnostics produce an explicit unavailable record.
Final normalization, PCA, graph and clusters are recomputed after approval.

Cluster QC compares global, sample and diagnostic-cluster MAD thresholds.
More than 50% removed highlights a possible disproportionate effect.
The top five markers are shown. Relaxation requires at least three tested
positive markers with adjusted p<0.05, positive log fold change and pct.1>pct.2,
excluding the recorded mitochondrial, ribosomal and stress lists. This software
guard does not certify a healthy cell type. Unresolved Ensembl features cannot
qualify for relaxation.

`scagentkit.qc.rules.v2` adds `diagnostic_hash`, `membership_hash` and an array of
`replacements` to QC rules v1. A replacement specifies `cluster_id`, `metric`,
`reason` and inclusive `min`/`max`. It replaces that metric's existing baseline
predicate in that cluster, rather than adding another AND filter. Other metrics,
predicate combination logic and minimum prefilter remain unchanged. Duplicate
cluster/metric entries, stale partitions, absent baseline metric coverage,
unavailable measurements and ineligible relaxation are rejected. Tightening
does not require rescue eligibility. Effective predicate bounds and retention
changes are displayed for review.

Batch mixing is the mean same-batch neighbor proportion minus its random
reference in the exact deterministic, batch-balanced candidate pool (at most
512 cells). No-effect or confounded designs recommend none. The provisional
excess cutoff is 0.1; necessity never bypasses the existing Harmony design gate.
Post-correction diagnostics use the actual approved dimensions and the same
fixed diagnostic labels. Type purity and technical mixing remain separate.
Condition centroid distance divided by within-condition sample dispersion
weights samples equally and requires two supported samples per condition.
Missing replication or zero dispersion is unavailable, not zero preservation.
Decline thresholds remain explicitly unfrozen until development-set calibration.
RNA-layer equality remains an integrity check, not evidence of preservation.

First-gate `risk_flags.v1` reuses the annotation risk enumerations and validator.
Its stage is strategy, its evidence hash is the diagnostic checkpoint, and
evidence IDs refer to quality/design/biology or enabled cycle/doublet evidence.
Missing model assessments receive visibly rule-derived or unassessed fields.
Neither risk fields nor diagnostic computation authorize a scientific action.

Method reference: [Subramanian et al., Genome Biology 23, 267 (2022),
Biology-inspired data-driven quality control for scientific discovery in
single-cell transcriptomics](https://doi.org/10.1186/s13059-022-02820-w).
ddqc motivates cluster-adaptive QC. Here those thresholds are reviewable
proposals with saved evidence, deterministic eligibility and explicit human
approval; they are not automatically applied.
