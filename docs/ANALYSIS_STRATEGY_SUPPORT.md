# Analysis strategy

Enable `strategy = TRUE` to review one typed QC and analysis plan before local
execution. The plan covers raw-count QC, normalization, features, PCs, optional
correction, clustering and UMAP. Annotation is reviewed separately. A processed
entry reuses its declared foundation instead of rerunning these steps.

| Choice | Current coordinator contract |
| --- | --- |
| Input | Genuine named raw counts, explicit count layers and verified metadata roles |
| QC | Exact range rules or explicit sample-aware [MAD candidates](MAD_REVIEW.md) |
| Preparation | LogNormalize, VST features and recorded effective dimensions |
| PCs | Fixed leading PCs or guarded computed-PC variance policy |
| Clustering | Approved Louvain resolution, with optional numeric diagnostics |
| Batch | Default none, explicit manual stop, or guarded [Harmony](HARMONY_PC_REVIEW.md) |
| Cell cycle | Optional full-input diagnostics; approved keep/full/difference choices within the [contract](CELL_CYCLE_REVIEW.md) |
| Doublets | Explicit capture/rate prerequisites, default keep; jointly approved removal under the [adapter contract](DOUBLET_REVIEW.md) |
| Subclusters | Separately reviewed raw-count [child projects](SUBCLUSTER_REVIEW.md) |

Exported legacy functions are documented in R help. Their presence does not make
an automatic or fallback behavior part of the reviewed coordinator workflow.

## R entry and complete typed proposal

Enable the concentrated strategy with `sc_run(..., strategy = TRUE)`. A supplied
`strategy_proposal` also enables it. This mode owns QC and analysis together, so
competing `qc_proposal` or nonempty `analysis` arguments are rejected. A fresh raw
run defaults to a new `sc_strategy_clusters` column, preserving prior cluster
metadata. Matrix, Seurat and local RDS input remain accepted. The raw strategy
requires canonical `counts` and `data` layer names and at least 21 projected
retained cells for its explicit 20-neighbor graph.

Doublet scoring is enabled only by a complete explicit `doublet_diagnostics`
configuration list, not by a bare `TRUE` or an arbitrary doublet proposal. The
default reviewed doublet choice is `keep`. See [DOUBLET_REVIEW.md](DOUBLET_REVIEW.md)
for required raw-count, called-cell, loading-unit and expected-rate declarations,
strict dependency/audit guards, and the fixed pre-QC reference. Processed reuse
supports diagnostics and `keep` only. These declarations do not invoke the
legacy `qc_doublet()` wrapper.

New context fields are `research_goal` (text) and `design` (a named list accepting
`type`, `technical_batch`, and `notes`). `technical_batch` is an explicit logical
user declaration; its absence is not inferred as TRUE. `columns` additionally
accepts the biological `group` role. Declared metadata columns must exist and
cover every cell with finite, nonmissing values. Species, tissue, research goal,
design and undeclared roles remain visible as missing facts when omitted.
Formal species support is human and mouse, ignoring case and surrounding
whitespace. Human aliases are `human`, `Homo sapiens`, `homo_sapiens`,
`homo-sapiens`, `h. sapiens`, `h.sapiens`, `hsapiens` and the character string
`"9606"`. Mouse aliases are `mouse`, `Mus musculus`, `mus_musculus`,
`mus-musculus`, `m. musculus`, `m.musculus`, `mmusculus` and the character string
`"10090"`. Other species are unsupported. These explicit aliases canonicalize
to human/mouse for compatibility checks. No gene-case species guess or
human-to-mouse capitalization conversion is performed. Diagnostics require an
explicit context species matching the
versioned gene-set declaration. Mouse and custom human lists require both
literal vectors with source and version; an explicit complete one-to-one symbol
mapping is available when input IDs differ.

A proposal has these required top-level fields:

```r
list(
  schema = "scagentkit.strategy.v1",
  rationale = "Explain this policy using supplied facts and measured evidence.",
  risks = list("State unresolved risks."),
  inferences = list("Label any interpretation as an inference."),
  qc = list(schema = "scagentkit.qc.v1", rationale = "...",
            risks = list(), filters = actual_reviewed_filters),
  analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
                  nfeatures = 60L, npcs = 6L, seed = 17L),
  pcs = list(method = "fixed", ndim = 4L),
  batch = list(method = "none", reason = "Explain why no correction is selected."),
  clustering = list(resolution = 0.4, diagnostic_resolutions = c(0.2, 0.4, 0.6)),
  umap = list(run = TRUE, n_neighbors = 15L)
)
```

With explicit `cycle_diagnostics = list(gene_set = sc_cycle_gene_set("human"))`
and matching context species, the proposal additionally accepts
`cycle = list(method = "none", reason = "...")`. Omission canonicalizes to
`none`. The ordinary review choices keep signal (`none`) or use standard
regression of both S and G2M scores (`full`). `difference` is advanced and
optional, with the same whole-strategy approval. A cycle/proliferation research
goal suggests considering retained signal; it never forces a method or claims
one is automatically best. See [CELL_CYCLE_REVIEW.md](CELL_CYCLE_REVIEW.md) for
the fixed reference, applicability checks and complete offline example.

This shape illustration is not an executable cleaning recommendation; use the
complete example below for real typed ranges. Integer HVG requests must be at
least three and within actually expressed input features after proposed QC.
Requested PCs must be at least two and strictly below both requested HVGs and
retained cells. Fixed leading dimensions must be in `[2, npcs]`. Alternatively,
`pcs = list(method = "computed_variance", threshold = 0.8)` uses the measured
computed-PC rule; a result selecting only one component fails and requires a
revised policy. Resolution is in `(0, 2]`; an optional diagnostic array has at
most five unique values in that interval. UMAP neighbors are an integer from
three to retained cells minus one, including when `run = FALSE`. Requests are not
silently clipped. Runtime validates the actual HVG/PCA/layer result again.

The existing provider adapter receives aggregate actual QC/background evidence
and returns this typed JSON document. A manual proposal can be supplied without
a provider. Missing/invalid model responses remain recoverable failures or
configuration boundaries. Offline examples use `name = "mock", external = FALSE`.
An external provider requires explicit aggregate-payload transfer review.

For processed reuse, `qc`, `analysis`, `pcs`, `clustering`, and `umap` are explicit
NULL. Supply `start_stage = "processed"`, the existing `cluster_column`, and a
nonempty `processed_reason` identifying the source and accepted foundation. The
strategy records that reuse and computes markers after approval. It does not
pretend to newly choose thresholds, PCs or clustering for the existing object.
Available genuine counts can support optional fresh cycle diagnostic columns
without recomputing the foundation, but processed entry requires method `none`.
Regression requires a new raw strategy project.

## Copyable offline example

The bundled [analysis-strategy.R](../inst/examples/analysis-strategy.R) supplies a
starting wrapper, exact-snapshot review/Continue helpers, revision helpers and an
explicit manual Unknown annotation. Source it after installing this checkout
into your selected library; it performs no installation itself.

```r
library(scAgentKit)
source(system.file("examples", "analysis-strategy.R", package = "scAgentKit"))

project_dir <- "/absolute/path/to/a/fresh-strategy-project"
input <- strategy_example_input()       # synthetic Seurat; use your local input instead
context <- strategy_example_context()   # replace facts/column roles for your own object

strategy_example_start(input, project_dir, context,
  chat_fn = strategy_example_mock(), annotation_column = "reviewed_identity")

s <- strategy_example_inspect(project_dir)  # read facts, missing information and exact QC impact
strategy_example_decide(project_dir, s, "approve", "analyst",
  "Approve this exact synthetic software-test strategy; biology remains unresolved.")
strategy_example_continue(project_dir, sc_run_inspect(project_dir))

# Local Continue stops at annotation evidence. It never dispatches a provider.
s <- strategy_example_inspect(project_dir)
strategy_example_unknown(project_dir, s, "analyst")
s <- strategy_example_inspect(project_dir)  # separate label decision is mandatory
strategy_example_decide(project_dir, s, "approve", "analyst",
  "Retain Unknown identities after reviewing the supplied cluster evidence.")
strategy_example_continue(project_dir, sc_run_inspect(project_dir))
final <- readRDS(sc_run_inspect(project_dir)$output$seurat)
```

The mock derives inclusive floor(p05)/ceiling(p99) feature-count bounds from
each actual aggregate sample/capture group. That deterministic quantile rule
exists to test the mechanism; it is not a real AI judgment or a scientific
recommendation. The local validator still computes exact retention and can
reject an inapplicable plan. Synthetic sample, capture, batch and Ca/Ctrl labels
are explicitly test facts, not real batch-effect evidence. Missing mitochondrial
symbol matches remain unavailable. The final Unknown labels prove a software
writeback flow, not a validated biological annotation.

The same helper supports existing processed objects without rerunning their
foundation:

```r
strategy_example_processed(processed_seurat, "/absolute/path/to/a/new-reuse-project",
  context = your_declared_context,
  processed_reason = "Reuse the supplied locally saved, analyst-reviewed foundation and literal cluster membership.",
  cluster_column = "your_existing_cluster_column")
# Inspect/approve/Continue, then inspect/propose/review annotation as above.
```

An Rscript-only interface is also bundled:

```sh
Rscript --vanilla inst/examples/analysis-strategy.R /absolute/new/project demo
Rscript --vanilla inst/examples/analysis-strategy.R /absolute/new/project inspect
Rscript --vanilla inst/examples/analysis-strategy.R /absolute/new/project approve
# Inspect again before Continue or each later decision, since revision changed.
Rscript --vanilla inst/examples/analysis-strategy.R /absolute/new/project inspect
Rscript --vanilla inst/examples/analysis-strategy.R /absolute/new/project continue
# At annotation evidence: inspect, propose-unknown, inspect, approve, inspect,
# continue, then output. Reject is available at either concentrated review.
```

CLI approval uses the exact snapshot displayed by `inspect`; stale snapshots are
rejected. Convenience snapshots are separate from the authoritative journal.
There is no automatic scientific approval or browser requirement.

## Background and applicability

User declarations identify species, tissue, sample, capture, technical batch,
biological group/condition, design, and research goal. Sample, donor and capture
are separate roles; capture is the loading unit, not an inferred donor. A
biological condition such as Ca/Ctrl is not promoted to technical batch merely
because its column has multiple levels.

Strategy evidence must separate:

- User facts: literal declared fields and metadata roles.
- Local measurements: counts, layers, group sizes, QC summaries, PCA or numeric
  clustering evidence actually computed from the project.
- Missing information: undeclared roles, missing design, unavailable metrics,
  or evidence that cannot support an operation.
- Model inferences: explicitly labelled suggestions with their rationale and
  uncertainty; they cannot overwrite user facts or invent measured values.

The local validator owns execution eligibility. Proposals cannot supply R code,
package installation, arbitrary function names, expressions, or unrecognized
parameters. Cell counts, feature counts, PCA bounds, layer availability and
metadata scope are verified before execution. Impossible requests require a
revised proposal or additional information; they are not silently converted into
another scientific choice.

Declared batch/group contingency evidence must reveal complete confounding and
missing overlap. Distinct column names alone do not establish independent
technical and biological effects. Candidate-name scoring is a heuristic, not a
technical-batch classifier or a confounding test. A no-correction choice records
its reason; a manual batch choice records that integration remains unresolved
and does not create a Harmony reduction. A Harmony proposal runs only after the
design guards in [HARMONY_PC_REVIEW.md](HARMONY_PC_REVIEW.md) pass; otherwise it
stops at a manual boundary rather than being reported as completed. Doublet removal requires explicitly enabled,
available saved diagnostics, a supported raw strategy and exact joint approval
of `remove_predicted`; otherwise it is rejected. A score or high RNA content
alone never authorizes deletion. Cycle regression is
allowed only with explicit usable diagnostics, an applicable raw strategy and
whole-strategy approval; it never authorizes cycle-based cell deletion.

## Meaning of PC and resolution evidence

For computed standard deviations `s`, the legacy PC rule selects the smallest
leading count `k` such that `sum(s[1:k]^2) / sum(s^2)` reaches the approved
threshold. The denominator covers the PCs computed and retained in this PCA;
it is **not total transcriptome variance**. Changing the number of computed PCs
can change the result. Zero/nonfinite variance and unavailable components cannot
support this rule. Neither an 80% threshold nor a fixed PC count proves that
rare or research-relevant populations are resolved.

Seurat's tutorial describes PC choice as uncertain and recommends inspecting
relevant heterogeneity and sensitivity to dimensionality. Its example numbers
are not universal defaults for unrelated tissues or designs.
[Seurat guided clustering tutorial](https://satijalab.org/seurat/articles/pbmc3k_tutorial).

A scalar clustering resolution controls graph partition granularity. Numeric
diagnostics can report cluster counts, small-cluster sizes and adjacent adjusted
Rand index using the package's existing helper. ARI measures agreement between
partitions; stability alone cannot establish correct cell types. A diagnostic
sweep is evidence, not a separate scientific approval for every candidate.
Seurat exposes resolution, algorithm and random seed as clustering parameters.
[Seurat FindClusters reference](https://satijalab.org/seurat/reference/findclusters).

UMAP is a visualization of selected components. Visual separation alone is not
evidence that the chosen strategy removed technical effects or recovered valid
biological populations.
[Seurat guided clustering tutorial](https://satijalab.org/seurat/articles/pbmc3k_tutorial).

## One strategy review and existing authorities

A strategy is proposed as one typed document, locally validated, then reviewed
as a whole. It does not add a dialog for every numeric parameter. Approval binds
the exact proposal, evidence, input scope and supported implementation. A stale
approval is rejected after the corresponding evidence or proposal changes.

In strategy mode the existing QC validator and exact impact preview are embedded
in this one review; a second QC approval is not requested for those same ranges.
Annotation review remains a later, separate responsibility for label writeback.
Legacy non-strategy projects keep their existing QC and annotation boundaries.

`sc_run_strategy_revise()` takes the complete canonical saved proposal plus exact
`project_id`, `input_hash`, `expected_revision`, `reviewer` and `reason`. It accepts
a stopped strategy project before annotation writeback; an applied or completed
result requires a new project. The bundled helpers modify the current canonical
plan, avoiding accidentally dropping other approved fields:

```r
s <- strategy_example_inspect(project_dir)
strategy_example_revise_resolution(project_dir, s, 0.6, "analyst",
  "Inspect finer partitioning using the current accepted QC and PCA.")
# Inspect and approve the fresh whole strategy before Continue.

# Alternative revision from a newly inspected snapshot:
s <- strategy_example_inspect(project_dir)
strategy_example_revise_pcs(project_dir, s, 3L, "analyst",
  "Assess sensitivity to this explicit leading PC count.")
```

The implementation fingerprints calculation components rather than rationale
text. QC rule changes drop QC output and all affected foundation results while
retaining the original full-input cycle reference. With diagnostics enabled,
normalization/HVG has a reusable `strategy_preprocess` checkpoint. Changing
cycle method retains that preprocessing, QC and diagnostics, then rebuilds
scaling/PCA and downstream evidence. Normalization/HVG or seed changes rebuild
preprocessing and its dependents; PCA-count changes rebuild the basis as needed.
PC-selection changes retain QC, preprocessing and the computed PCA basis, then
rebuild the neighbor/UMAP checkpoint and its
downstream results. Resolution/diagnostic-grid changes retain QC, basis and
neighbors, then rebuild clustering, markers and affected annotation evidence.
UMAP changes currently rebuild the combined neighbor/UMAP checkpoint. Explanatory
text-only revisions preserve calculation fingerprints and, after fresh strategy
approval, can restore the unaffected annotation proposal/approval. Historical
decisions and versioned checkpoint files are retained; only active dependent
artifacts and authorities are invalidated.

`batch = list(method = "manual", reason = "...")` is an approvable declaration
of unresolved work. Continue then stops at `awaiting_configuration`; approval
does not execute integration or bypass that stop. To proceed, explicitly revise
to a justified supported `none` choice or start a new processed project from an
independently prepared object. The helper's `defer-batch` CLI mode demonstrates
this boundary.

At a saved `awaiting_review` state R can exit. Headless inspect/approve/reject and
resume are the required path; a loopback browser is optional. The coordinator's
external-transfer approval is independent of scientific strategy approval and
does not make an unsupported method executable.

## Layer and memory constraints

Exact assay and layer names are checked using public `Layers()` and
`LayerData()`. Raw counts must cover the literal cell set, remain nonnegative
integer counts, and cannot be substituted with normalized or scaled values.
Ambiguous or fragmented input layers need explicit preparation outside the run;
the coordinator does not choose an arbitrary matching layer.
[SeuratObject layer API](https://satijalab.github.io/seurat-object/reference/Layers.html).

Normalization reads the selected sparse counts matrix. Scaling is limited to
selected HVGs; its scaled representation can be dense without expanding the
full raw or normalized matrix. Legacy `sc_scale()` falls back to scaling all
features when variable features are absent, so the strategy path must validate
HVG availability instead of using that fallback. LogNormalize scales by each
cell's total expression and applies a log transformation; this is a supported
method, not a claim that its assumptions suit every experiment.
[Seurat NormalizeData reference](https://satijalab.org/seurat/reference/normalizedata).

## Legacy APIs and scientific limits

Cell-cycle scores describe expression programs. Regressing scores changes
scaled expression and requires downstream PCA/graph/clustering recomputation;
it does not delete cells. The current default is `none`; standard `full`
regression uses `S.Score` and `G2M.Score`. Advanced optional difference regression
uses `S.Score - G2M.Score`, retaining cycling versus noncycling contrast while
reducing S/G2M phase variation. Scores and coverage alone cannot
decide whether removing proliferation signal serves the research goal.
[Seurat cell-cycle scoring and regression](https://satijalab.org/seurat/articles/cell_cycle_vignette).

Doublet detection needs capture/loading-unit provenance, real counts, applicable
platform/rate assumptions and an explicit removal decision. scDblFinder's
`samples` role denotes captures; multiplexed biological donors can share one
capture. Its documentation distinguishes scores and classifications and
describes limitations for homotypic doublets. The legacy wrapper's
`remove = TRUE` default is not inherited by the strategy allowlist.
[scDblFinder official vignette](https://bioconductor.org/packages/release/bioc/vignettes/scDblFinder/inst/doc/scDblFinder.html).

The optional coordinator adapter uses the fixed full-input pre-QC reference,
defaults to `keep`, and derives only the approved exact predicted-ID subset that
also survives QC. Small or inadequately covered captures remain `Unknown`/`NA`
with `keep` only; the minimum scoring prerequisites never silently filter cells.
Operational or strict scDblFinder adapter audit failures remain recoverable failed
stages. Manual rates require provenance; standard-10x automatic estimation
additionally requires the exact applicable technology and explicit
`full_called_cohort = TRUE`. These guards and versioned real-method execution
acceptance are documented in [DOUBLET_REVIEW.md](DOUBLET_REVIEW.md). This adapter
does not infer list units, donors or samples as captures and does not call the
legacy wrapper.

The later sample-aware MAD extension is described in [MAD_REVIEW.md](MAD_REVIEW.md).
MAD-derived suggestions
preserve declared metadata roles, materialize an inspectable typed proposal and
exact cell impact, and require approval before changing the cell set.

Harmony requires a computed PCA and declared correction variables. Existing
`sc_harmony()` fails if the optional dependency is absent, but it does not perform
the strategy's required biological-design validation. Guarded
coordinator execution is described in [HARMONY_PC_REVIEW.md](HARMONY_PC_REVIEW.md).
Software checks do not establish real batch-removal efficacy.
[Harmony RunHarmony reference](https://portals.broadinstitute.org/harmony/reference/RunHarmony.html).

The coordinator-specific exact-cell-ID subcluster applicability checks, approvals and
bounded request accounting are described in [SUBCLUSTER_REVIEW.md](SUBCLUSTER_REVIEW.md).
The legacy path
accepts positional subset alignment, continues after per-target failures and
can replace an invalid auto-resolution reply with 0.5; it is not invoked by this
reviewed path. Paper-grade validation of biological labels, batch effects,
cycle decisions, doublet handling and research conclusions remains separate
work. Synthetic multi-batch fixtures can test guards and execution mechanics;
they cannot demonstrate real batch correction efficacy.
