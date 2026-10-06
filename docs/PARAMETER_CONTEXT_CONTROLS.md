# Reviewable parameters and child annotation context

Use one saved project for the strategy, analysis and annotation decisions. R can
finish the workflow without a browser. The workbench exposes the same saved
evidence through three primary views: **Overview + next step**, **Figures +
annotation**, and **Results + records**. Its secondary navigation retains QC,
strategy, annotation, children and complete history. Navigation reads saved
state; parameter edits belong in the current strategy review.

## A fresh, offline software control

The bundled [parameter-context-demo.R](../inst/examples/parameter-context-demo.R)
reuses the public convenience functions in
[analysis-strategy.R](../inst/examples/analysis-strategy.R). Use an installed copy
of this checkout in your selected R library. The example creates a new sparse
synthetic Seurat object with declared sample/capture columns, a typed manual
strategy, and zero provider budget. It performs no installation, download, key
read or model request. Its inclusive QC ranges deliberately retain the fixture;
they are not cleaning recommendations or an AI decision. Synthetic programs,
mock responses and `Unknown/low` labels establish no biological accuracy.

From the repository root, choose a new project directory and run each command
after reading the preceding evidence:

```sh
Rscript --vanilla inst/examples/parameter-context-demo.R /absolute/new/synthetic-project start any
Rscript --vanilla inst/examples/parameter-context-demo.R /absolute/new/synthetic-project inspect
Rscript --vanilla inst/examples/parameter-context-demo.R /absolute/new/synthetic-project approve
Rscript --vanilla inst/examples/parameter-context-demo.R /absolute/new/synthetic-project resume
Rscript --vanilla inst/examples/parameter-context-demo.R /absolute/new/synthetic-project inspect
Rscript --vanilla inst/examples/parameter-context-demo.R /absolute/new/synthetic-project propose-unknown
Rscript --vanilla inst/examples/parameter-context-demo.R /absolute/new/synthetic-project inspect
Rscript --vanilla inst/examples/parameter-context-demo.R /absolute/new/synthetic-project approve
Rscript --vanilla inst/examples/parameter-context-demo.R /absolute/new/synthetic-project resume
Rscript --vanilla inst/examples/parameter-context-demo.R /absolute/new/synthetic-project output
```

Every command is a fresh R process. `approve` saves only the displayed decision;
`resume` calls the existing exact-bound local Continue operation and stops at the
next review/configuration boundary. No approval is automatic. `reject` is also
available. The convenience snapshot is a displayed copy; the hash-checked project
journal is the authority. Stale revisions, changed inputs and concurrent locks
are refused. An execution failure requires inspection and explicit retry; the
driver does not retry provider or computation failures automatically.

In R, the same short cycle returns the final object directly:

```r
source(system.file("examples", "parameter-context-demo.R", package = "scAgentKit"))
project <- "/absolute/new/synthetic-project-r"
parameter_context_demo_start(project, remove_if = "any", pcs_fraction = .80,
  resolution = .4, diagnostic_resolutions = c(.2, .4, .6, .8, 1))
view <- parameter_context_demo_inspect(project)  # read QC impact and whole strategy
parameter_context_demo_approve(project, view, "analyst", "Accept this synthetic strategy")
view <- parameter_context_demo_inspect(project)
parameter_context_demo_resume(project, view)
view <- parameter_context_demo_inspect(project)  # read actual clusters and markers
parameter_context_demo_unknown(project, view, "analyst")
view <- parameter_context_demo_inspect(project)  # separate annotation review
parameter_context_demo_approve(project, view, "analyst", "Keep unresolved identities")
view <- parameter_context_demo_inspect(project)
parameter_context_demo_resume(project, view)
final <- parameter_context_demo_output(project)
```

The original input object is checked for mutation. The final object, tables,
figures, parameter records, report, recovery script and decision history stay in
the project directory; no manual ZIP transfer is needed. Stage counts describe
verified saved input/QC/selection/analysis/output checkpoints, with unavailable
or processed-reuse states stated explicitly. Proposed retention is not an
executed cell count.

## QC, PCs and clustering

`scagentkit.qc.rules.v1` combines at most 32 typed failure predicates with
`remove_if="any"` (OR failures) or `"all"` (AND failures). A range uses measured
`nCount`, `nFeature` or available `percent_mt`, optional inclusive min/max bounds,
and optional literal **declared** sample/capture selectors. Outside a selector,
that rule's failure is false. Consequently, AND between disjoint groups cannot
remove a cell. The example uses a global range and one actual sample/capture
range. Its ToyGene IDs do not supply a mitochondrial convention, so it does not
filter an unavailable mitochondrial metric.

When `qc_mad` was explicitly configured, one rule may instead choose an available
saved `mad_preset` and its exact `panel_hash`. The finite MAD candidates and
minimal-prefilter eligibility remain bound to their saved evidence; custom
failure ranges do not silently refit MAD or restore prefilter-excluded cells.
The review shows per-rule failures, overlaps, unique removals and exact retained
cells. Doublet prediction/removal remains a separate explicit reviewed choice:
minimal prefilter, fixed pre-score doublet diagnostics, then quality QC and the
approved keep/remove-predicted intersection. This demo does not fit doublets.

The example explicitly chooses `pcs=list(method="computed_variance",
threshold=.80)`. Any finite fraction strictly between 0 and 1 can be supplied.
Its denominator is the variance of **all actually computed PCs**, including
computed PCs beyond 50; this is not total expressed-gene variance. The legacy
`computed_top50` method accepts only `.80` or `.85` and uses the first
`min(50, computed PCs)`. A fixed `ndim` must be an integer from 2 through the
supported computed-PC range. `.80` is a reference/example choice, not a proven optimum.
Before approved PCA executes, actual diagnostics are unavailable. Inspection
then exposes saved per-PC/cumulative fractions; it does not run PCA.

Clustering accepts `0 < resolution <= 2` and at most five distinct diagnostic
resolutions in the same interval. Saved candidate cluster counts, sizes and ARI
comparisons describe the actual computed alternatives, not biological scores.
The current web review has direct controls and retains the complete typed JSON.
For R edits, reuse `strategy_example_revise()` from `analysis-strategy.R` with
the inspected canonical plan. Every changed plan needs a fresh whole-strategy
review; dependency hashes determine which downstream stages must be recomputed.
`Ca`/`Ctrl` and other biological groups are not automatically technical batches;
this example explicitly chooses no integration.

## Reuse an already processed Seurat object

Declare the actual cluster column and why its foundation should be retained.
This convenience creates a typed reuse plan, computes current markers after
approval, and writes a fresh annotation column. It does not normalize, select
new PCs or recluster the supplied object.

```r
reused_project <- "/absolute/new/processed-project"
parameter_context_demo_processed(final, reused_project,
  context = list(species = "human", tissue = "synthetic planted expression programs"),
  processed_reason = "Reuse the reviewed synthetic project's saved foundation",
  cluster_column = "sc_strategy_clusters",
  annotation_column = "parameter_reused_identity")
# Use the same inspect -> approve -> resume -> propose-unknown ->
# inspect -> approve -> resume -> output cycle above for reused_project.
```

For another local Seurat/RDS, use its explicitly known membership column and a
new annotation-column name. Processed reuse is not an assertion that earlier
QC, clustering or biology was correct.

## Correct a child's soft parent context

A freshly created scoped child records frozen parent annotation labels,
approval/execution status, annotation source kind, tissue, literal cluster IDs
and counts, and provenance hashes. A reviewed parent label, including a model or
mock label, is a hypothesis rather than child ground truth. `Unknown`, mixed and
unreviewed scopes remain explicit. Local reference scores remain based on
current marker coverage; parent labels do not restrict their vocabulary/ranking.
Explicit lineage relations can produce nonblocking cross-lineage warnings.
Missing a gene from the supplied top-30 markers does not show absent expression.

Use the existing [scoped-child workflow](SUBCLUSTER_REVIEW.md) to select actual
parent clusters, create a separate child, approve its strategy and Continue to
saved `annotation_propose` evidence. At that stopped boundary:

```r
child_project <- "/absolute/path/to/your/fresh-scoped-child"
view <- parameter_context_demo_inspect(child_project)
view$child_context$parent_snapshot             # immutable source facts
view$child_context$generation                  # current generation, not an API argument
view$child_context$hash                        # exact correction binding
corrected <- parameter_context_demo_correct_child(child_project, view,
  context = list(enabled = FALSE,
    notes = "Assess the child markers without a resolved parent-lineage expectation."),
  reviewer = "analyst", reason = "Revise the soft annotation context",
  request_id = "context-correction-001")
# The wrapper calls the public API with these exact inspected fields:
# sc_run_set_child_context(child_project, context = list(enabled = FALSE),
#   project_id = view$project_id, input_hash = view$input_hash,
#   expected_revision = view$revision, expected_context_hash = view$child_context$hash,
#   reviewer = "analyst", reason = "Disable the soft hint", request_id = "another-correction")
view <- parameter_context_demo_inspect(child_project)  # new generation/hash
parameter_context_demo_unknown(child_project, view, "analyst")
# Inspect, explicitly approve the fresh annotation, and resume as above.
```

Editable fields are `enabled`, `lineage_hint`, `identity_status`
(`labeled`, `unknown`, `mixed`, `unreviewed`), annotation `tissue`, and `notes`.
Unspecified fields stay unchanged; explicit NULL clears a hint/tissue override
or notes. A labeled correction to an unresolved scope requires an explicit
lineage hint, which remains a soft hypothesis. Species, metadata roles, cell
selection and frozen parent facts cannot be edited here. Correction is supported
before annotation writeback at `annotation_propose` or approved-but-unexecuted
`annotation_apply`; undo an executed annotation first.

Correction preserves calculated analysis/markers, strategy approval, historical
checkpoints/decisions and the usage ledger. It invalidates current annotation
proposals, response/adoption pointers, scientific approval and both exact
outgoing-payload consents. A to B to A still has a new generation/request identity.
Retry the identical correction with its original request ID and arguments for
idempotent recovery; a different payload with that ID is refused. Obtain a fresh
inspection for a new correction. Context correction is available in R and the
Cell scope web editor for the same five typed fields. The editor binds the
current context generation/hash and saves a durable receipt; saving does not
request a model or continue computation. Completed child context is read-only.

## Optional model assistance

For a fresh model-enabled project, follow the existing
[provider configuration](FIRST_RUN.md#connect-a-built-in-provider-through-the-r-environment)
and [exact suggestion preview workflow](UNIFIED_MODEL_REVIEW.md). Built-in
DeepSeek/Grok factories use `DEEPSEEK_API_KEY`/`XAI_API_KEY` from the analysis
machine's environment or user secret mechanism at dispatch. Supply a verified
model ID, generation settings, current pricing and explicit budget; keep key
values out of code, context, objects, logs and the browser. A headless `chat_fn`
stays in caller memory. This example does not read or configure credentials.

`allow_external=TRUE` permits offering a preview, not sending it. The exact
aggregate context/QC/marker payload must be separately approved before Request;
typed candidate adoption still needs scientific approval before computation.
Raw counts staying on the machine does not mean aggregate evidence stays there.
New child context fields appear in that same preview and need new consent after
correction. Browser review is loopback-only; use the documented SSH tunnel on a
server, or finish in headless R. This guide does not claim Linux/HPC execution or
successful remote website access.
