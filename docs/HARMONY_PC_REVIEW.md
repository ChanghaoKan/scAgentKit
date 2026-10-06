# Explicit Harmony and computed-PC policies

The raw-entry `sc_run(..., strategy = TRUE)` workflow supports an explicitly
reviewed Harmony choice and two `computed_top50` PC policies. The default batch
choice remains `none`. Neither metadata names nor apparent separation in a
UMAP authorize correction. The whole strategy must identify the intended
covariate, exact supported settings and scientific reason before computation.

This is a bounded extension to the existing
[concentrated strategy review](ANALYSIS_STRATEGY_SUPPORT.md). The saved R journal
remains the authority for both headless operation and the optional loopback
workbench. It does not add treatment-effect testing, sample exclusion, automatic
integration-method selection or a biological-preservation guarantee.

## Declare the correction variable and biological design

A Harmony variable must be the literal metadata column explicitly declared in
context as `batch`, `sample` or `donor`. Sample, donor, physical capture and
condition retain separate meanings; no role is inferred from another. Declare
`context$design$technical_batch = TRUE` with an explanation of the technical
effect being investigated. This records an analyst declaration, not a measured
finding. A biological condition, treatment or group is never automatically
promoted to a technical variable.

The projected cell set must contain at least two covariate levels and at least
one explicitly declared biological `group`, `condition` or `treatment` with two
levels. Its relationship to the proposed correction factor must be crossed and
identifiable under the supported design checks. The review records observed
contingency tables and applicability after the proposed QC/doublet selection.
It does not automatically remove a sample to create a preferable table.

| Design evidence | Coordinator behavior |
| --- | --- |
| Explicit supported variable and technical provenance; selected covariate/biological factors have a supported identifiable crossed design | The specific Harmony proposal may be reviewed and executed |
| Variable missing, ambiguous, undeclared or single-level | Block Harmony and retain a configuration boundary |
| Missing biological design information or only one observed biological level | Block Harmony; do not invent a treatment/control relationship |
| Full confounding, nested aliases or a rank-deficient selected design | Block Harmony; retaining or deferring is available, automatic correction is not |
| Processed entry with a supplied foundation | `none` or `manual` reuse only; this increment does not correct its existing basis |

Several donor/sample IDs can each occur only within one treatment. Having more
than one sample per treatment does not make sample and treatment independently
estimable: treatment indicators can still be constructed from sample indicators.
Correcting that sample factor can therefore absorb treatment-associated signal,
even when treatment is omitted from `group_by_vars`. This is a design inference,
not a claim about a particular user's experiment. Passing a design guard is also
insufficient evidence that correction is necessary or that biology is preserved.
The [OSCA discussion of corrected values](https://bioconductor.org/books/release/OSCA.multisample/using-corrected-values.html)
illustrates how correction can remove donor-associated disease variation and
why gene-level comparisons need separate statistical care.

The official Harmony vignette includes a stimulation covariate example. That
example demonstrates its API; it does not authorize using treatment as this
coordinator's technical variable. Record the narrower factual statement
“treatment was not supplied as a Harmony correction covariate,” rather than
claiming that all treatment biology was preserved.

## Exact typed Harmony choice

`none` retains its existing two-field shape:

```r
proposal$batch <- list(method = "none", reason = "Your reason to retain the PCA basis")
```

A Harmony choice requires exactly these fields; unsupported or misspelled
arguments are rejected rather than ignored:

```r
proposal$batch <- list(
  method = "harmony", group_by_vars = "technical_batch",
  theta = 2, lambda = 1, sigma = 0.1,
  max_iter = 10L, nclust = 10L,
  reason = "Describe the declared technical provenance, crossed design and accepted risks")
```

`group_by_vars` contains one to three unique literal column names. Each must
map uniquely to a declared allowed role, and a column also declared as capture,
group, condition or treatment cannot be a correction variable. These numbers
illustrate typed syntax, not optimal settings for another experiment. The
example below starts with `none`; the analyst explicitly revises to Harmony
after inspecting the saved context and PCA evidence. The coordinator does not
ask a provider to invent R code, Harmony options or a new covariate. A manual
deferral remains `list(method = "manual", reason = "...")` and stops without an
integration result.

| Parameter | Supported declaration |
| --- | --- |
| `theta` | Finite nonnegative scalar or one unnamed value per selected factor |
| `lambda` | Finite positive scalar or one unnamed value per factor; automatic `NULL` is rejected |
| `sigma` | One finite number in `(0, 1]` |
| `max_iter` | Integer from 1 through 50 |
| `nclust` | Integer from 2 through `min(100, retained_cells - 1)` |

Execution uses one Harmony core, early stopping enabled and no convergence
plot. These are recorded software settings, not optimized recommendations.

The adapter targets the selected official Harmony **2.0.5** package. Its current
Seurat method accepts `object`, `group.by.vars`, `reduction.use`, `dims.use`,
`reduction.save`, `project.dim` and `...`. The adapter uses explicit
`reduction.use = "pca"` and the current `max_iter` argument, rather than a partial
`reduction` name or historical `max.iter.harmony` public spelling. It saves a
fresh reduction and uses `project.dim = FALSE` for an embedding-only operation.
[Official Seurat adapter source](https://raw.githubusercontent.com/cran/harmony/master/R/RunHarmony.R)

The current algorithm interface has an automatic lambda default, and some prose
descriptions of cluster counts and convergence tolerance differ from the
release source. This workflow uses explicit approved parameters and records the
actual supported package/source/settings instead of treating those descriptions
as an execution receipt.
[Official algorithm entry](https://raw.githubusercontent.com/cran/harmony/master/R/ui.R)
Dependency installation is a separate, explicit operation in the execution
machine's selected private R library. The example does not install, upgrade or
download anything. The [CRAN release page](https://cran.r-project.org/web/packages/harmony/index.html)
provides official source and platform-specific binaries; local receipt hashes
and installed versions, rather than a changing HEAD, identify a run.

## Two PC policies, with the denominator disclosed

For a raw entry, `analysis$npcs` authorizes how many PCA components to calculate.
It must fit the supported feature/cell rank; there is no silent clipping of an
impossible requested basis. The rule can be approved before those components
exist:

```r
proposal$analysis$npcs <- 50L
proposal$pcs <- list(method = "computed_top50", threshold = 0.80)
# The other supported candidate is threshold = 0.85.
```

After the approved QC and PCA calculation, let `w = min(50, number of actually
computed PCs)`. For each of the first `w` components, variance is its saved PCA
standard deviation squared. The cumulative fraction is
`cumsum(variance[1:w]) / sum(variance[1:w])`; the selected dimension is the first
index reaching or exceeding the approved `.80` or `.85` threshold, subject to
the existing minimum-dimensionality and finite-variance checks.

The saved PCA record contains both actual `top50_candidates`, the variance
vector, actual computed count, window length and selected policy. If fewer than
50 PCs were computed, the shortfall is disclosed. Twenty saved components mean
a twenty-component window; no missing thirty components are invented. If more
than 50 were computed, later components are outside this rule's denominator.
An unavailable/invalid candidate is not silently replaced by a fixed choice.

This is variance within the specified computed-PC window of the selected,
scaled features. It is not total RNA, total transcriptome, full-expression or
total biological variance. Changing the requested/computed basis can change the
fractions and selected number. Eighty and eighty-five percent are explicit
empirical comparison policies, not universal optima. Seurat documents the
number of stored components and the scaled-feature input to
[RunPCA](https://satijalab.org/seurat/reference/runpca).

The first central review authorizes the rule, with actual candidate numbers
pending PCA. Approved execution later saves the actual numbers; this does not
create an automatic second approval or silently change the rule. Before
annotation writeback, inspecting and revising the cached basis can show both
measured candidates and create a fresh whole strategy review. In a computed
review these appear at `strategy_review$details$pc_diagnostics$actual`; its
artifact path/hash and basis dependency are also exposed. Existing `fixed` and
`computed_variance` choices retain their previous meaning; they are not silently
reinterpreted as the new top-50 window.
After approved computation, `sc_run_inspect()` also exposes the saved candidates
at `computed_diagnostics$pc_candidates`. This describes the cached calculation
without mutating the original pre-computation review.

## Computation, expression and recovery

For an approved Harmony plan the new `strategy_batch` checkpoint follows PCA
and the approved PC policy, then precedes neighbors, UMAP, clustering and
markers. It records selected dimensions, exact covariate assignments, settings,
dependency/source identity, input basis and output embedding fingerprints.
Neighbors and UMAP use the fresh Harmony reduction explicitly. A `none` choice
continues on the unintegrated PCA basis.

Raw RNA counts, normalized RNA data, existing metadata and unintegrated PCA are
preserved. Harmony coordinates are not corrected gene-expression values.
Markers use RNA/data; changing the embedding can still change clusters and thus
the cells compared in marker testing. Those marker tables are exploratory
cluster evidence, not a replicated treatment-effect analysis. Sample-associated
confounding and pseudoreplication remain relevant even when counts are unchanged.
The official [Seurat integration guide](https://satijalab.org/seurat/articles/integration_introduction)
distinguishes embedding-based clustering from expression comparisons and
discusses replicate-aware condition testing.

Revising only the batch choice or PC policy preserves approved QC,
normalization/HVG/scaling and the computed PCA checkpoint. It invalidates the
affected batch/neighbor and later analysis results, and creates a fresh joint
approval. Restoring `none` uses the saved original PCA rather than an already
harmonized basis. Changing normalization, HVGs, PCA count or cell selection
requires the corresponding earlier recomputation. An applied final annotation
requires a new project; old decisions and versioned files remain available.

Changing the audited Harmony runtime source also makes an existing approval
stale, even when the numeric parameters are unchanged. An explicit revision
with those same parameters discards the cached Harmony correction and its
downstream results, retains input, approved QC and the raw PCA basis, and
requires a fresh central approval bound to the current source.

R and browser decisions are bound to the same project/input/proposal/review
hashes and expected revision under the existing lock. Duplicate execution,
concurrent requests, a stale tab or changed evidence cannot create a second
authorized scientific result. R can exit at an approval/configuration boundary
and continue in another process using checkpoints. Missing dependencies,
unsupported method shape, warnings or execution failures remain visible and
recoverable; there is no fallback to a silently unintegrated successful result.

## One headless example

The installed `examples/harmony-pc-review.R` creates a small sparse synthetic
fixture with a two-level constructed technical factor crossing two condition
labels, plus distinct sample/donor/capture roles. These are software controls,
not real batch-effect or cell-type evidence. Its initial strategy uses `none`
and an approved `.80` top-50 policy. Optional revision to explicit Harmony tests
the mechanism. No provider, key read, model request or dependency installation
is part of this example.

```r
library(scAgentKit)
source(system.file("examples", "harmony-pc-review.R", package = "scAgentKit"))
input <- harmony_pc_example_input()
before <- digest::digest(input, algo = "sha256")
project <- "/absolute/path/to/a/new/harmony-pc-project"
harmony_pc_example_start(input, project, harmony_pc_example_context(),
  harmony_pc_example_proposal())
shown <- harmony_pc_example_inspect(project)
harmony_pc_example_approve(project, shown, "analyst",
  "Approve the exact synthetic none strategy and .80 computed-PC policy")
shown <- harmony_pc_example_inspect(project)
harmony_pc_example_continue(project, shown)

# Inspect now-computed PC candidates and saved design before any revision.
shown <- harmony_pc_example_inspect(project)
harmony_pc_example_revise(project, shown, "harmony", 0.85, "analyst",
  "Explicit crossed synthetic comparison; accept the stated integration risks")
shown <- harmony_pc_example_inspect(project)
harmony_pc_example_approve(project, shown, "analyst",
  "Approve the exact revised strategy and affected downstream recomputation")
shown <- harmony_pc_example_inspect(project)
harmony_pc_example_continue(project, shown)

shown <- harmony_pc_example_inspect(project)
strategy_example_unknown(project, shown, "analyst")
shown <- harmony_pc_example_inspect(project)
harmony_pc_example_finish_unknown(project, shown, "analyst",
  "Approve these displayed Unknown/low synthetic labels and finalize")
final <- readRDS(sc_run_inspect(project)$output$seurat)
stopifnot(identical(before, digest::digest(input, algo = "sha256")))
```

Omit the Harmony revision block to complete the default unintegrated run. The
same helper's `Rscript --vanilla` modes allow begin, inspection, revision,
approval, Continue and manual Unknown finishing in separate processes. Inspect
again after each mutation; saved convenience snapshots do not bypass authority.
Files and scientific computation remain on the data machine. The optional UI
uses loopback and your explicit SSH tunnel; it does not change authentication,
open a public listener or submit scheduler jobs.

## Support and execution status

| Supported | Not established by this increment |
| --- | --- |
| Explicit bounded Harmony on a guarded raw-entry design; retained `none` and manual boundary | Automatic covariate/method selection, biological preservation or optimal integration |
| Saved actual `.80`/`.85` top-50 PC candidates and the declared window denominator | Full-transcriptome variance or universal optimal PC counts |
| Headless and optional workbench review of one saved strategy; cached-basis revision | Replicated disease/treatment inference or batch-adjusted RNA marker modeling |
| Exact cell/metadata/expression/PCA preservation and fresh corrected embeddings | Cross-platform bitwise identity or Linux/HPC/user-server execution acceptance |

The following is historical Harmony-increment acceptance, not a fresh check of
the release candidate. See the [release checklist](RELEASE_CANDIDATE_CHECKLIST.md)
for current-source results. Mocked adapter tests and separately executed real
algorithm receipts are distinct evidence.

Acceptance was completed on the user's Mac with the audited private CRAN
Harmony **2.0.5** installation. These results do not establish compatibility
with every 2.0.x release:

- `R CMD check --no-manual --ignore-vignettes` finished with `Status: OK`;
  testthat recorded **6,737 passes**, with zero failures, warnings or skips.
  All **231 Python tests** passed. The focused mock suite passed **769
  assertions in 29 tests**.
- Actual Chrome review passed **3/3 approval cases** and **3/3 read-only
  completed-project cases**, with no external requests. The UI displays saved
  diagnostics and output paths. It currently has no route for displaying PNG
  artifacts; the acceptance checks verified the PNG files and their SHA hashes
  on disk.
- The synthetic **480-cell, 700-gene** run computed 55 PCs and used the first
  50 as the candidate window: `.80` selected **34 PCs**, and `.85` selected
  **38**. Real Harmony 2.0.5 executed once. Approved QC, the raw PCA basis,
  RNA counts/data, exact cell IDs and the old annotation were preserved; the
  new annotation column contained explicit `Unknown`/`low` decisions. The
  project completed at revision **68**.
- The public **2,700-cell PBMC** run computed 50 PCs, with candidates **33**
  for `.80` and **37** for `.85`. Its single batch level blocked Harmony;
  explicitly choosing `none` allowed completion at revision **38**. This is
  an applicability guard check, not evidence for multi-sample correction.
- In the synthetic comparison, the descriptive technical mixing statistic
  changed from **0.0159375 to 0.0504167**, while biological-group same-label
  neighbor fraction changed from **0.999479 to 0.999688**. The modest change
  describes this constructed control; it does not prove biological accuracy
  or a generally optimal correction.
- Each project was finalized and verified in a fresh R process, including an
  idempotent repeat. Model API requests and cost were **zero**. The installed
  **240-cell example** above was parsed and checked against its installed
  source hash; its complete scientific execution was not part of this
  acceptance run.

Linux, HPC and the user's server were not tested. Acceptance read no credentials,
used no new private user dataset and performed no push, PR creation or merge.
