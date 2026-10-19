# Scientific review: operator guide

This guide describes the [fixed-commit developer preview](../README.md#developer-preview),
not the published v0.6.0 archive. [简体中文](SCIENTIFIC_REVIEW_QUICKSTART_ZH.md).
For v0.6.0, use its [two-approval protocol](RELEASE_060_PROTOCOL.md).
Do not resume an old project with a different implementation or dependency
fingerprint; preserve its exact environment or review a new project.

## Initialize the input and model mode

`sc_start()` accepts an RDS file containing raw counts/Seurat, a 10x MEX directory,
or a declared sample table (data.frame/CSV/TSV). It does not accept an in-memory
Seurat object. Declare only verified sample, donor, capture, condition and batch
roles; do not infer roles from names or treat condition as technical batch.

Before creating the project, choose manual or model-assisted operation. The
default is manual: no provider, no model calls, zero budget. You enter labels
and qualitative confidence. For a model project, initialize the immutable
provider/model/generation settings/budget in `sc_analyze()` or `sc_run()` first,
then reopen the same input with `sc_start(..., model_suggestions="configured")`.
See [configuration and separate transfer consent](UNIFIED_MODEL_REVIEW.md).
The browser cannot add or change a provider on a saved manual project.

```r
service <- sc_start("input.rds", "new-review-project",
  context=list(species="human", tissue="Blood", research_goal="Review local evidence",
    columns=list(sample="sample_id", condition="condition")))
```

Use these columns only if they exist and their study roles are established.
Otherwise omit them. `scientific_review` is unnecessary for the ordinary path.
It retains LogNormalize/global vst HVGs/PCA, the internal 80% PC candidate,
ordinary resolution scan/tree, applicable sample QC/elbow/citation/Fisher
evidence and declared-human blood/PBMC or pancreas classic mean/detection panels.
Species/tissue are never inferred from genes, clusters or predictions. Other
declarations are unavailable; missing genes are not observed zero expression.

PC k±5, five 80% resamples, extra resolution extension, sample-consensus HVGs,
automatic QC draft preselection and cross-sample/mixed-lineage expression are
off by default. If appropriate, request extra diagnostics in a **new project**:

```r
extra_review <- list(pc_sensitivity=TRUE, resampling=TRUE,
  resolution_extension=TRUE, panels="blood", cross_sample=TRUE, mixed_lineage=TRUE)
# sc_start(..., scientific_review=extra_review)
```

Explicit gene panels can support other species without guessing orthology.
Sample-consensus HVGs require at least two declared samples with at least 30
retained cells each; explicitly set analysis `hvg_method="sample_consensus"`
and its `hvg_column`, then save and review the full plan.

## Inspect QC, then approve the initial plan

Read per-group distributions, disjoint single-metric flags/intersections and
candidate retention. Do not add overlapping failures. Check original,
pre-score, selected QC and separate doublet denominators. Keep_all is a starting
proposal, not an assessed quality decision. Counts/features use low tails on
log10(x+1); high RNA flags only. MT uses its original-scale upper tail. Positive
MAD can imply a tiny absolute MT margin; read the percentage-point difference,
precision, overlaps and sample comparisons. No minimum absolute difference,
normality gate, exclusion quota or default AND rule is added.

Sample medians and between-sample robust flags are separate from within-group
cell MAD. Between-sample flags require at least five comparable samples,
complete measurements and nonzero between-sample MAD; they never delete samples.
Without independent identity evidence, cell-type-specific deletion risk is
unassessed. Do not infer author labels or run a new annotation merely to justify QC.

Manual candidate selection changes the local draft. Experimental automatic
prefill requires explicit opt-in and existing completeness/risk guards; it
does not change the saved proposal or delete cells. Save to rebuild impact,
inspect it and approve the whole strategy. The
[methods appendix](SCIENTIFIC_METHODS_APPENDIX.md#reading-qc-flags-and-retention)
documents the measured QC rules; the old direct-filtering API is retired in this build.

## Approve measured clustering, then annotation

After the first approval, inspect computed PCs, ordinary scan/tree, marker
contrasts and sample composition. The 80/85% crossings are relative to the
computed first at most 50 PCs, not total expression variance. Tree overlap is
not lineage. Select an actually scanned resolution, save edits and separately
approve this measured review. Optional k±5 and resampling are computational
stability diagnostics, not independent donors or an optimality proof. Unsupported
Harmony/cycle reruns remain unavailable; applicable cheap expression evidence survives.

At annotation, prepare a worksheet. Configured local references supply candidate
labels only; on the manual path, you supply labels, confidence and reasons.
Main citations/reference overlap use the selected top-marker pool (default
top 30, strict FC>1 and adjusted p<0.05), not every assayed gene. Seurat's
min.pct prefilter uses the larger of inside/outside detection; known-label
citations separately need positive FC and inside detection greater than outside.
Missing from the list is not absent expression. Read absolute hits, reference
denominators and provenance; coverage is not probability. Fisher/BH requires
the actual pre-test background and remains conditional on query/reference selection.
These gates do not validate gene-label semantics. Retain Unknown when unresolved.
Save the full annotation proposal, inspect it, then approve separately.

Use `sc_result()` for the integrity-checked final Seurat. `sc_open()` inspects;
it neither continues computation nor requests a model. The public
`examples/three-gate-analysis.R` tutorial exercises all three approvals with
Unknown labels and no provider; it tests software, not annotation accuracy.

## Optional ambient correction

`sc_run_ambient_correction()` is R-only, with no browser correction action.
SoupX needs one explicitly complete capture, matching raw/filtered counts,
at least 20 extra background droplets and named preliminary clusters.
decontX can infer background from other clusters without raw droplets; that
assumption may remove real RNA. Neither replaces input counts/checkpoints.
Inspect separate corrected counts and version/seed/hash/comparison receipts;
use a new project if adopted. Floating estimates are preserved unless explicit
`round_counts=TRUE` is chosen. Dependencies are never installed automatically.
See [the methods and full parameter contract](SCIENTIFIC_METHODS_APPENDIX.md#ambient-estimation-and-correction)
and `?sc_run_ambient_correction` before using study data.

## Development API consolidation

This build has one saved-project workflow. Redundant direct orchestration and
AgentSeurat objects are removed; standalone utilities use Seurat or tables and
never grant scientific approval. See the [exact API/type changes](API_CONSOLIDATION.md).
Development test projects can be rebuilt with this implementation. No backward
compatibility for old test objects is promised; preserve baseline evidence and
published history, and never edit saved hashes to force a resume.

Full evidence remains in `snapshot$view` despite bounded R print summaries.
Evaluation boundaries remain in the [frozen protocol](EVALUATION_PROTOCOL_V1.md);
workflow completion does not establish accuracy or human-time benefit.
