# Analysis strategy: supported scope and evidence

This document distinguishes an exported package function, an operation connected
to the resumable coordinator, and an operation actually validated in this
increment. The capability audit starts from commit `2ffa17ed`. The historical
strategy receipts below use mock responses and local computations only: no new
paid model requests, key-file reads, private data transfer, dependency installation,
or Linux/HPC environment claims. The cell-cycle increment is described in
[CELL_CYCLE_REVIEW.md](CELL_CYCLE_REVIEW.md), including its versioned Mac validation. The prior strategy receipts below apply to the
previous implementation, not all later optional modules. The current doublet
contract and its historical execution acceptance are described in
[DOUBLET_REVIEW.md](DOUBLET_REVIEW.md). Current MAD, guarded Harmony and scoped
child contracts are in [MAD_REVIEW.md](MAD_REVIEW.md),
[HARMONY_PC_REVIEW.md](HARMONY_PC_REVIEW.md) and
[SUBCLUSTER_REVIEW.md](SUBCLUSTER_REVIEW.md). Use the
[release checklist](RELEASE_CANDIDATE_CHECKLIST.md) for final-source validation;
older counts below are not a new test run against the release candidate.

## Baseline capability audit

At the audit baseline, `sc_run()` supports exact raw-count QC evidence, typed QC
range proposals and their impact review, standard preparation, markers, and
annotation review. Analysis settings are supplied directly rather than proposed
and reviewed as a sample-background strategy. A processed Seurat start explicitly
reuses its existing foundation; it does not rerun QC, normalization, PCA, or
clustering. The baseline has no connected batch correction, cell-cycle operation,
doublet operation, or subclustering node.

| Capability | Existing exported/local engine | Historical baseline connection | Supported strategy or later explicit contract |
| --- | --- | --- | --- |
| Input and layers | `sc_project_prepare()` and shared exact-layer helpers validate genuine integer counts and literal IDs | Connected; split-layer ambiguity fails closed | Reuse exact raw counts and public SeuratObject layer access |
| QC evidence | Raw `nCount`, `nFeature`, mitochondrial percentage; aggregate distributions within explicitly declared sample/capture groups | Connected; absence of matching mitochondrial genes is unavailable, not zero | Reuse actual evidence and exact impact validation |
| QC selection | Typed inclusive ranges for those three metrics and literal sample/capture selectors | Connected; retained cell set requires approval | Approved ranges define QC scope; explicitly enabled doublet selection additionally requires joint whole-strategy approval |
| Legacy fixed/MAD QC | `qc_threshold()` defaults to count >1000, features >500, mt <50%; `qc_mad()` defaults to 3 MAD and log-count/features | Not connected to the typed range executor | No automatic legacy invocation. Explicit `qc_mad` has a separate reviewed candidate-panel contract; no universal-threshold claim |
| Normalization | `sc_normalize()`; exact-count `sc_project_prepare()` accepts LogNormalize and RC | Connected preparation defaults to LogNormalize, scale factor 10000 | LogNormalize in the supported strategy path; RC is legacy preparation functionality unless separately demonstrated |
| HVG and scaling | `sc_find_hvg()` and preparation use VST; HVG-only scaling available | Connected preparation defaults to 2000 requested features | VST/HVG-only scaling; requested and effective sizes recorded |
| PCA | `sc_pca()` and preparation | Connected preparation requests 30 PCs and validates requested dimensions against the result | Explicit bounded PCA request and approved leading PC count |
| Variance PC choice | `sc_select_pcs()` defaults to cumulative threshold 0.80 | Exported only | Guarded computed-PC variance selection; denominator disclosed below |
| Visual PC choice | `sc_select_pcs_visual()` compares UMAPs and can fall back after invalid AI replies | Exported only | Unsupported; no visual-model decision or fallback is executed |
| Clustering | `sc_cluster()` requires a resolution; preparation defaults to 0.5 | Connected through analysis settings | Approved scalar Louvain resolution; optional numeric diagnostics |
| Resolution diagnostics | `sc_cluster_sweep()` plus `sc_resolution_recommend()` aggregate cluster counts, small clusters and adjacent ARI | Exported only; legacy sweep requires clustree | Numeric diagnostics may reuse local clustering/ARI helpers; no automatic vision recommender |
| Batch candidates | `sc_select_batch_var()` scores metadata names, cardinality and cell counts | Exported only | Evidence only; explicit role declarations control applicability |
| Batch correction | `sc_harmony()` requires PCA, explicit columns and the optional harmony package | Not connected; baseline skips integration | `none`, explicit `manual` stop, or the later guarded and whole-strategy-approved Harmony contract; no automatic batch/method selection |
| Cell-cycle scoring | `sc_cellcycle_score()` uses explicit literal, versioned lists; `sc_cycle_gene_set()` declares human defaults or supplied human/mouse programs | Exported only at baseline | Opt-in `cycle_diagnostics`: nonfiltering full-input LogNormalize/CellCycleScoring reference, preserved after approved QC; insufficient evidence stays Unknown/NA |
| Cell-cycle regression | `sc_cellcycle_regress()` delegates explicit score regression to scaling; default none | Exported only at baseline | Raw strategy ordinary choices none or standard full S/G2M regression; advanced optional difference uses S minus G2M. One whole-strategy approval, no cycling-cell deletion; processed reuse permits none only |
| Doublets | Legacy `qc_doublet()` consumes a supplied Seurat list and defaults to removal; its list units are not validated as captures | Legacy wrapper exported only at baseline | Explicit `doublet_diagnostics` uses the separate strict scDblFinder adapter with declared loading units and sourced rates; default `keep`, available predictions permit exact jointly approved `remove_predicted` in raw strategy only |
| Subclustering | Legacy `annot_subcluster()` subsets broad types; its behavior is separate | Exported only at baseline | Later `sc_run_subcluster()` creates a separately reviewed raw-count child and exact-ID derived output; it does not call the legacy positional-write path |

The strategy scope above is wired in the implementation. Its bounded validation
record below identifies which paths actually ran for the previous strategy
increment. Optional modules have their own versioned acceptance records linked
above. Support is not a claim of biological correctness.
An optional dependency being listed in `Suggests`, or a legacy function existing,
does not make its method supported by the coordinator.

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
configuration boundaries. This increment tests `name = "mock", external = FALSE`
only; it does not call a real provider or read keys. Enabling a future remote
provider still requires the existing explicit aggregate-payload transfer review.

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
and does not create a Harmony reduction. A proposal naming Harmony is rejected
rather than reported as completed. Doublet removal requires explicitly enabled,
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
does not make an unsupported method executable. This increment exercises mocks
only, so there is no new external request behind an approval.

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

## Known legacy gaps and deferred methods

Cell-cycle scores describe expression programs. Regressing scores changes
scaled expression and requires downstream PCA/graph/clustering recomputation;
it does not delete cells. The current default is `none`; standard `full`
regression uses `S.Score` and `G2M.Score`. Advanced optional difference regression
uses `S.Score - G2M.Score`, retaining cycling versus noncycling contrast while
reducing S/G2M phase variation. Earlier default and difference-description
errors were corrected in this increment. Scores and coverage alone cannot
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
Operational or strict scDblFinder 1.26.7 audit failures remain recoverable failed
stages. Manual rates require provenance; standard-10x automatic estimation
additionally requires the exact applicable technology and explicit
`full_called_cohort = TRUE`. These guards and versioned real-method execution
acceptance are documented in [DOUBLET_REVIEW.md](DOUBLET_REVIEW.md). This adapter
does not infer list units, donors or samples as captures and does not call the
legacy wrapper.

The later sample-aware MAD extension is described in [MAD_REVIEW.md](MAD_REVIEW.md).
This historical range-QC increment did not enable it. MAD-derived suggestions
preserve declared metadata roles, materialize an inspectable typed proposal and
exact cell impact, and require approval before changing the cell set.

Harmony requires a computed PCA and declared correction variables. Existing
`sc_harmony()` fails if the optional dependency is absent, but it does not perform
the strategy's required biological-design validation. The later guarded
coordinator execution is described in [HARMONY_PC_REVIEW.md](HARMONY_PC_REVIEW.md).
This historical range-QC increment did not execute Harmony; no real
batch-removal efficacy is established by these software checks.
[Harmony RunHarmony reference](https://portals.broadinstitute.org/harmony/reference/RunHarmony.html).

The historical range-QC increment did not include the coordinator-specific
exact-cell-ID subcluster contract. The later applicability checks, approvals and
bounded request accounting are described in [SUBCLUSTER_REVIEW.md](SUBCLUSTER_REVIEW.md).
The legacy path
accepts positional subset alignment, continues after per-target failures and
can replace an invalid auto-resolution reply with 0.5; it is not invoked by this
strategy increment. Paper-grade validation of biological labels, batch effects,
cycle decisions, doublet handling and research conclusions remains separate
work. Synthetic multi-batch fixtures can test guards and execution mechanics;
they cannot demonstrate real batch correction efficacy.

## Code audit anchors

Paths and line positions below describe the baseline `2ffa17ed`, before strategy
implementation shifts their positions.

| Area | Baseline code |
| --- | --- |
| Context role contract and input diagnostics | `R/run-qc.R:4–103` |
| Sparse raw QC evidence and scope | `R/run-qc.R:142–198` |
| Typed range validation and exact subset | `R/run-qc.R:202–331` |
| Entry and processed reuse | `R/run.R:29–78` |
| Durable stage execution | `R/run.R:205–267` |
| Analysis settings adapter | `R/run-annotation.R:23–40` |
| Exact public layer API and sparse validation | `R/project-identity.R:58–95` |
| Standard preparation and effective parameters | `R/project-prepare.R:18–107` |
| PC computation and variance rule | `R/sc-pca.R:14–52`, `71–133` |
| Visual PC fallback | `R/decision-schema.R:99–110` |
| Resolution sweep and numeric evidence | `R/sc-cluster.R:70–143`; `R/sc-resolution-recommend.R:96–155`, `346–358` |
| Batch heuristic and Harmony | `R/sc-select-batch-var.R:68–129`; `R/sc-harmony.R:27–69` |
| Cycle scoring/regression | `R/sc-cellcycle.R:32–79`; `R/sc-cellcycle-regress.R:29–52` |
| Doublet dependency/layer/removal behavior | `R/qc-doublet.R:20–59` |
| Legacy subcluster alignment/fallback | `R/annot-subcluster.R:379–412`, `720–728` |
| Current approval binding and review kinds | `R/run-state.R:161–197`; `R/run-review.R:54–96` |
| Optional dependency declarations | `DESCRIPTION:34–49` |

## Current cell-cycle validation record

The focused Mac suite passed 94 tests and 1924 assertions with zero failures,
warnings or skips. The final `R CMD check --no-manual --ignore-vignettes` exited
0 with `Status: OK` in 169.102 seconds and passed 4103 assertions with zero
failures, warnings or skips. The earlier 4092-assertion check's code NOTE was
resolved by qualifying `utils::capture.output`. The final receipt is
`evidence/cycle-delivery-check/check-result.json`.
The full Python suite passed 231 tests and preserved 62 protected files. The
current DOM checks passed 17 cycle checks and 34 strategy checks.

The bundled synthetic CLI completed across 24 fresh R processes, including
none/full/advanced difference revisions and reviewed Unknown writeback, without
a provider call. The public sparse PBMC input had 32738 features and 2700 cells;
its original raw RDS SHA256 remained
`aae453d43fe6a31c8ffe758f8ab59ce6c6074edca85fe1037d661e56fd633610`.
Twenty-one feature IDs were explicitly mapped on a copy. All 2700 cells had
available fixed pre-QC scores with declared `nbin = 12` and `ctrl = 5`; these are
software scoring settings, not validated biological adequacy criteria or a
claim of using Seurat's default control count. The final output completed at
revision 73 with
2540 cells, seven clusters and Unknown/low annotations. A fresh R process passed
21 read-only checks of literal retained sparse counts, IDs, fixed scores and
actual execution. Diagnostics, approved QC and normalization/HVG ran once;
scaling/PCA, neighbors/UMAP, clustering and markers ran three times for the
three genuinely executed choices. Workspace receipts are
`evidence/cycle-synthetic-cli/cli-result.json` and
`evidence/cycle-public-pbmc/verify-receipt.json`.

Two actual Chrome scenarios passed. A third actual difference R worker
completed, but the terminal browser DOM wait failed; that attempt is retained.
A separate read-only Chrome finish passed three checks of the complete public
project at revision 73, preserving every project byte without new decisions or
scientific computation. Its receipt is
`evidence/cycle-public-pbmc/browser-finish/cycle-finish-browser-report.json`;
it does not change the earlier failed attempt into a pass.

The final checked runtime fingerprint is
`b5c0c313a62ddaa0688302a3f4dec8068e869f83d4f9196036fc164c646fb16b`.
Public scientific and CLI acceptance used
`6e1d2bfa220521083b247917aa3528f1ff934437263211fec10ab25f9382f003`;
the later review-node dispatcher correction and legacy output qualifier did
not change the scientific functions. On the final runtime, a separate 180-cell
fixture at revision 27 passed two actual read-only Chrome checks of
`awaiting_configuration` / `annotation_propose`: a null review node, saved none
plan, fixed cohort, disabled decisions/Continue and byte-preserving refresh,
with no new job, provider request or scientific computation. The receipt is
`evidence/cycle-configuration-regression/browser/cycle-config-browser-report.json`.

Validation is Mac only, with zero real provider API calls, zero key-file reads
and US$0 incremental provider cost. Linux/HPC deployment and biological phase
calls, coverage thresholds or research conclusions were not validated. See
[CELL_CYCLE_REVIEW.md](CELL_CYCLE_REVIEW.md) for the current scope and limits.

## Prior strategy validation record

The following receipts describe the previous strategy implementation. They do
not verify the new cell-cycle implementation; current receipts are separate
above.

The frozen implementation was installed and checked on the user's Mac with
R 4.6.1, Seurat 5.5.1 and SeuratObject 5.4.0. `R CMD check --no-manual
--ignore-vignettes` exited 0 with `Status: OK`; testthat reported 3070 passing
expectations, zero failures, zero warnings and zero skips. The checked
implementation fingerprint is
`57784527054ba87087862232169ef7ee89dc7d06635a972dcad6becd27d0680f`.
The retained check-process log, `analysis-strategy-final/check.log`, has SHA256
`102f745e58e004156a07e00b883b150f73c38f22103f8c6315a208e22c0969f2`.
The R production files, tests and example are frozen; this validation paragraph
is a documentation update after that check.

The complete Python suite passed 231 tests with zero failures, errors or skips.
Its first sandbox attempt encountered 48 errors when loopback socket operations
were blocked; that failed attempt is retained. The authorized rerun with working
loopback access passed. This is an environment-specific failure record followed
by actual verification, rather than a claim that the initial run passed. The
strategy DOM checks passed 34 checks and the legacy DOM checks passed 33. DOM
checks alone do not establish actual Chrome-to-R execution.

The public PBMC offline workflow now reaches a complete new Seurat object:
2540 retained cells in eight clusters from the supplied sparse 32738-feature,
2700-cell raw counts. The original raw RDS SHA256 remains
`aae453d43fe6a31c8ffe758f8ab59ce6c6074edca85fe1037d661e56fd633610`.
Its first input attempt correctly failed because 21 feature IDs contained `_` or
`|`, which Seurat would otherwise rename implicitly. That attempt's failure log
is retained. The root worker explicitly replaced those characters with `-` on
a copy, checked for collisions, and saved `public-feature-id-preparation.csv`.
The original raw bytes and 45 previously frozen inputs remained unchanged.
Feature ID/order preservation refers to that explicitly prepared copy; retained
cell IDs/order and exact sparse raw counts were verified against it.

Actual isolated Chrome and the actual R bridge passed two browser scenarios:
the concentrated strategy display, and a full-JSON resolution change from 0.4
to 0.5 with stale approval rejected as HTTP 409. A fixed R Continue job then
succeeded and saved the provider-free `annotation_propose` /
`awaiting_configuration` boundary. The third browser scenario's harness checked
the combined `run-status` text before the asynchronous DOM refresh reached that
element, although the actual API/job state had already saved the boundary. Its
failed report is retained. The driver now waits for that combined status/stage
text; the first run is still recorded as two passes and one failed assertion,
not retrospectively counted as a complete passing run.

A fresh R process supplied a manual Unknown annotation, approved the exact
annotation snapshot and used local Continue to complete the public project.
QC application, basis preparation, neighbors, clustering, markers, annotation
evidence, annotation application and finalization each executed once. The
journal contains one strategy approval, zero redundant QC approvals and one
separate annotation approval. The completed object retains sparse counts and
literal retained IDs, and adds Unknown/low labels without claiming correct
biological identity. The public prepare and finalize receipts are retained in
`strategy-public-pbmc/prepare-receipt.json` and
`strategy-public-pbmc/finalize-receipt.json`.

A subsequent fresh R readonly verification exited 0 with the project still at
`complete`, revision 35, and all supported stage counts unchanged at one. Its
17 checks inspected the saved result without another scientific execution.
A separate actual isolated Chrome readonly finish run exited 0 in 17.277 seconds
and passed all three scenarios: completed status/stage with central strategy and
output paths for 2540 cells/eight clusters; the saved fixed R job's original
annotation boundary and exact approval/stage counts; and a refresh preserving
all project bytes, input checkpoint, mock ledger and first failed browser
receipt. It made no new decision, Continue request, computation or provider call;
page errors and external requests were zero, and its owned server/profile were
cleaned up. This is a complete passing readonly finish check, separate from the
earlier browser assertion failure. Its report is
`strategy-public-pbmc/browser-finish/strategy-finish-browser-report.json`; the
root execution log SHA256 is
`5c5e86810f8f4e9bab386b764c3f0780fff239d3ccdc4bf1b8eadec2b69e4ebc`.

The bundled CLI example also completed its synthetic mock/manual-Unknown flow
across 12 fresh R processes in 21.934 seconds. The example source was unchanged
from the checked implementation. Across public and CLI acceptance there were
two aggregate mock calls, one per project. Neither was a real provider request.
Synthetic multi-batch checks cannot demonstrate real batch correction efficacy.
All completed validation used mocks/local computation: zero real provider API
calls, zero key-file reads and US$0 incremental provider cost. This increment
does not validate Linux, HPC, a scheduler or a user server. These prior receipts
did not execute cell-cycle or doublet handling. Opt-in cycle support is described
above with its bounded validation. Optional doublet support is described in
[DOUBLET_REVIEW.md](DOUBLET_REVIEW.md), including its separate completed Mac
acceptance; these historical receipts do not validate it. Subcluster execution
remains unsupported. Paper-grade biological validation remains outside these
receipts.
