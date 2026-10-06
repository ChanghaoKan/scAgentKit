# Cell-cycle diagnostics and one strategy review

Cell-cycle handling extends the existing `sc_run(..., strategy = TRUE)` flow.
Enabling diagnostics computes local scores before QC, then presents the ordinary
choice of keeping cycle signal (`none`) or standard S/G2M score regression
(`full`) in the same whole-strategy review as QC, normalization, PCs and
clustering. Difference regression is an advanced optional choice within that
same approval. The default is `none`. Diagnostic scoring
does not authorize regression or remove cells; approved QC ranges remain the
authority for cell selection. Annotation still has its separate later review.

The previous strategy baseline is documented in
[ANALYSIS_STRATEGY_SUPPORT.md](ANALYSIS_STRATEGY_SUPPORT.md). This increment adds
only the cycle operations described here. Automatic Harmony, doublet removal
and subclustering remain unsupported by this coordinator. A legacy exported
helper's existence does not establish coordinator support.

## Main entry and declared gene sets

Use a fresh project directory and supply genuine raw counts, a Seurat object or
a local RDS through the usual main entry. Cycle diagnostics require matching
explicit species declarations in the context and gene set:

```r
library(scAgentKit)

gene_set <- sc_cycle_gene_set("human")
sc_run(input, project_dir, context = your_context, strategy = TRUE,
  strategy_proposal = your_complete_strategy,
  cycle_diagnostics = list(gene_set = gene_set))
```

`your_context$species` must explicitly declare human or mouse. Matching ignores
case and surrounding whitespace; the exact accepted aliases are:

| Canonical species | Accepted strings |
| --- | --- |
| `human` | `human`, `Homo sapiens`, `homo_sapiens`, `homo-sapiens`, `h. sapiens`, `h.sapiens`, `hsapiens`, `"9606"` |
| `mouse` | `mouse`, `Mus musculus`, `mus_musculus`, `mus-musculus`, `m. musculus`, `m.musculus`, `mmusculus`, `"10090"` |

Taxonomy identifiers must be character strings. Other species are unsupported.
Neither gene capitalization nor available features are used to guess species.

`sc_cycle_gene_set("human")` loads the installed Seurat package's
`cc.genes.updated.2019` data. The declaration records its source, version,
installed Seurat version and content hash. Missing package data cause an error;
another list is never substituted. For either supported species, an analyst can
instead supply both literal program vectors with explicit source and version:

```r
gene_set <- sc_cycle_gene_set("mouse",
  s_genes = your_literal_mouse_s_genes,
  g2m_genes = your_literal_mouse_g2m_genes,
  source = "Your supplied, verified mouse reference",
  version = "Your reference version")
```

Mouse has no automatic default. Human lists are never converted to mouse by
changing capitalization. An optional `symbol_mapping` must be a complete
one-to-one named character vector from the union of canonical program symbols
to literal input feature IDs. Both names and values must be unique. It declares
an analyst-supplied mapping; the package does not infer orthologs, search
synonyms, fetch a database or merge ambiguous IDs. Keep the factory declaration
intact so its hash remains verifiable.

The available diagnostic options and their defaults are:

```r
cycle_diagnostics = list(
  gene_set = gene_set,           # required explicit declaration
  column_prefix = "sc_cycle",  # must create fresh metadata columns
  seed = 17L, scale_factor = 10000,
  nbin = 12L, ctrl = 5L,
  min_genes = 5L, min_fraction = .2
)
```

Requested options are recorded and validated without silent clipping. The
coverage settings are software preconditions for this operation; five genes or
20% coverage is not a validated scientific adequacy threshold. Use your study,
feature identifiers, tissue and research goal to assess the supplied reference.

## Fixed full-input evidence

Diagnostics run on a nonfiltering copy of the full input before approved QC.
The copy is LogNormalized with the recorded scale factor and scored with
`Seurat::CellCycleScoring`, using the recorded seed, bin and control counts.
The control pool contains positive expressed input features, symbol search is
disabled, and phase assignment never replaces cell identities. Seurat module
scores compare program expression with expression-matched sampled controls;
their values depend on that scoring reference.
[Seurat AddModuleScore reference](https://satijalab.org/seurat/reference/addmodulescore).

The saved reference records exact input cell/feature scope, counts and options,
gene-set provenance, coverage, reasons for insufficiency and score hashes.
Per-cell scores and literal identifiers stay in local private artifacts;
aggregate status, coverage, phase counts and score distributions appear in
`strategy_review$details$cycle_diagnostics`; the chosen operation's applicability
appears in `strategy_review$details$applicability$cycle`. The inspected review
binds this evidence and the
exact retained cell scope to its approval.

After approved QC, retained cells receive the same saved full-input scores in
their exact order. Controls and normalization for scoring are not refitted on
the retained subset. QC revisions therefore change the retained set without
changing the input scoring reference. This permits comparison across approved
strategies without silently changing what a score means.

The fresh default output columns are `sc_cycle_S.Score`,
`sc_cycle_G2M.Score`, `sc_cycle_Phase` and `sc_cycle_CC.Difference`.
The difference is S minus G2/M. Diagnostics leave the source object's metadata,
labels and layers unchanged, and column collisions require a fresh prefix.
Missing program genes,
inadequate coverage or insufficient control/bin capacity yield `insufficient`
evidence with `Unknown` phases and `NA` scores. The review still permits `none`;
it rejects `full` and `difference` when usable regressors are unavailable.
Finite scores, positive regressor variance, a full-rank retained-cell design
and residual degrees of freedom are also required for regression. These checks
establish executability, not valid phase classification or biological adequacy.

## Keep signal or use standard regression

When diagnostics are enabled, the complete `scagentkit.strategy.v1` proposal
accepts this additional field:

```r
cycle = list(method = "none", reason = "Explain the study-specific choice.")
```

An omitted choice becomes an explicit canonical `none` choice for review.
Arbitrary regressors, code and cycle-based deletion rules are unsupported.
If the declared research goal concerns cell cycle or proliferation, consider
keeping the signal. That context is a review prompt, never a forced choice or
an automatic claim that one method is best.

| Method | Operation during approved HVG scaling | Scientific interpretation to review |
| --- | --- | --- |
| `none` | No cycle regressors | Retain cycle-related variation; scores remain diagnostic. |
| `full` (standard regression) | Regress the fresh quantitative S and G2/M scores | Can reduce both phase and proliferation-associated variation, including research-relevant biology. |

The advanced optional `difference` method regresses the fresh S minus G2/M
score. It targets phase contrast among cycling cells while retaining the cycling
versus noncycling distinction. Selecting it uses the same whole-strategy
approval; it does not add a separate cycle approval.

Seurat describes these two regression strategies and warns that removing both
scores can blur meaningful distinctions associated with proliferation. Their
effect on a particular study requires inspection; neither method guarantees
preservation of a population or a correct biological conclusion.
[Seurat cell-cycle scoring and regression vignette](https://satijalab.org/seurat/articles/cell_cycle_vignette).
The discrete `Phase` assignment is a diagnostic heuristic; regression uses
quantitative scores.
[Seurat CellCycleScoring reference](https://satijalab.org/seurat/reference/cellcyclescoring).

One explicit whole-strategy approval binds the chosen method, its reason,
diagnostic evidence, QC impact and analysis settings. Approval stops at the
review boundary. The separate `sc_run_continue()` action performs supported
local computation; review actions do not run regression or contact a provider.

## Offline example: inspect, approve and Continue

The bundled [cell-cycle-review.R](../inst/examples/cell-cycle-review.R) reuses
the existing strategy helpers and requires this checkout to be installed in the
selected R library. It makes no provider request and installs nothing. Its
960-gene, 180-cell fixture combines explicit synthetic S/G2M programs with
independent artificial expression programs and ample background controls.
Human symbols identify planted programs; their counts are simulated. The
versioned custom gene set and no-filter QC policy isolate software behavior.
They do not validate a human biological analysis, marker specificity or a
cleaning recommendation.

```r
library(scAgentKit)
source(system.file("examples", "cell-cycle-review.R", package = "scAgentKit"))

project_dir <- "/absolute/path/to/a/fresh-cycle-project"
input <- cycle_example_input()
cycle_example_start(input, project_dir, cycle_example_context(),
  cycle_example_gene_set(), cycle_example_proposal())

s <- cycle_example_inspect(project_dir) # read cycle status, coverage and exact QC impact
strategy_example_decide(project_dir, s, "approve", "analyst",
  "Approve this exact synthetic none strategy; biology remains unresolved.")
strategy_example_continue(project_dir, sc_run_inspect(project_dir))

# At saved annotation evidence, before any annotation writeback:
s <- cycle_example_inspect(project_dir)
cycle_example_revise(project_dir, s, "full", "analyst",
  "Inspect both-score regression as a software comparison, including loss of proliferation variation.")
s <- cycle_example_inspect(project_dir)
strategy_example_decide(project_dir, s, "approve", "analyst",
  "Approve this exact full strategy for the synthetic comparison.")
strategy_example_continue(project_dir, sc_run_inspect(project_dir))

# Optional advanced comparison; skip this block to retain the standard full result.
s <- cycle_example_inspect(project_dir)
cycle_example_revise(project_dir, s, "difference", "analyst",
  "Inspect S minus G2M regression as a software comparison of phase contrast.")
s <- cycle_example_inspect(project_dir)
strategy_example_decide(project_dir, s, "approve", "analyst",
  "Approve this exact difference strategy for the synthetic comparison.")
strategy_example_continue(project_dir, sc_run_inspect(project_dir))

# Only now perform the separate annotation review, explicitly retaining Unknown.
s <- cycle_example_inspect(project_dir)
strategy_example_unknown(project_dir, s, "analyst")
s <- cycle_example_inspect(project_dir)
strategy_example_decide(project_dir, s, "approve", "analyst",
  "Retain Unknown identities after reviewing the saved cluster evidence.")
strategy_example_continue(project_dir, sc_run_inspect(project_dir))
final <- readRDS(sc_run_inspect(project_dir)$output$seurat)
```

The same CLI supports a saved project across R processes:

```sh
Rscript --vanilla inst/examples/cell-cycle-review.R /absolute/new/project demo
Rscript --vanilla inst/examples/cell-cycle-review.R /absolute/new/project inspect
Rscript --vanilla inst/examples/cell-cycle-review.R /absolute/new/project approve
Rscript --vanilla inst/examples/cell-cycle-review.R /absolute/new/project inspect
Rscript --vanilla inst/examples/cell-cycle-review.R /absolute/new/project continue
# Before annotation writeback, repeat inspect -> revise-full -> inspect ->
# approve -> inspect -> continue. An advanced optional comparison uses the same
# sequence with revise-difference, without adding a separate approval type.
# Finish with inspect -> propose-unknown -> inspect -> approve -> inspect ->
# continue -> output. Reject and revise-none are also available.
```

Every CLI mutation uses the exact snapshot previously displayed by `inspect`.
Changed revisions or hashes reject stale decisions. The convenience snapshot is
separate from the authoritative journal. For supplied local data, use
`cycle_example_start()` with your declared context, gene set and complete typed
strategy rather than the synthetic defaults.

## Execution, reuse and processed input

The raw path is approved QC application, normalization/HVG selection in
`strategy_preprocess`, HVG scaling and PCA in `strategy_basis`, then reviewed
PCs, neighbors/UMAP, clustering, markers and annotation evidence. Diagnostic
scoring is the separate fixed full-input reference.

| Revision | Retained active computation | Rebuilt after fresh strategy approval |
| --- | --- | --- |
| Cycle method changes | Input diagnostic reference, approved QC, normalization/HVG checkpoint | Scaling/PCA, neighbors/UMAP, clustering, markers and affected annotation evidence |
| Leading PC selection changes | Input reference, QC, normalization/HVG and computed PCA | Neighbors/UMAP and downstream evidence |
| QC ranges change | Original input diagnostic reference | QC output, normalization/HVG, scaling/PCA and downstream evidence |

Changes to normalization/HVG settings rebuild preprocessing and its dependent
results; PCA count changes rebuild PCA as required. Calculation reuse never
bypasses the new whole-strategy approval. Historical decisions and versioned
artifacts remain saved. Strategy revisions require a stopped project before
annotation writeback; an applied or completed result requires a new project.

Processed entry can add diagnostics from available genuine raw counts while
reusing the supplied foundation and literal cluster membership. It permits
only `cycle$method = "none"`, with the existing null execution settings and a
nonempty `processed_reason`. Fresh score columns do not imply that PCA or
clustering were recomputed. Regression of a processed foundation requires a
new raw strategy project.

## Validation record and limits

These are historical cell-cycle receipts for the versions named below, not new
release-candidate checks. See the [release checklist](RELEASE_CANDIDATE_CHECKLIST.md)
for current-source validation.

Validation ran on the user's Mac with R 4.6.1, Seurat 5.5.1 and SeuratObject
5.4.0. The focused suite passed 94 tests and 1924 assertions with zero failures,
warnings or skips. The final `R CMD check --no-manual --ignore-vignettes` exited
0 with `Status: OK` in 169.102 seconds, and passed 4103 assertions with zero
failures, warnings or skips. Its receipt is
`evidence/cycle-delivery-check/check-result.json`. The earlier 4092-assertion
check's code NOTE about `capture.output` was resolved by qualification as
`utils::capture.output`.
The Python suite passed all 231 tests and preserved all 62 protected files.
Current DOM checks passed 17 cycle checks and 34 strategy checks.

The bundled CLI completed none, standard full and advanced difference reviews,
computation and manual Unknown annotation across 24 fresh R processes, with no
provider call. Its receipt is
`evidence/cycle-synthetic-cli/cli-result.json` in the task workspace.

The public PBMC workflow used the real sparse 32738-feature, 2700-cell input.
Its original RDS bytes remained unchanged, with SHA256
`aae453d43fe6a31c8ffe758f8ab59ce6c6074edca85fe1037d661e56fd633610`.
Twenty-one feature IDs were explicitly mapped on a copy, with collision checks,
before input. All 2700 cells had available fixed pre-QC scores. Scoring
explicitly used `nbin = 12` and `ctrl = 5`; these declared settings do
not claim Seurat's default control count or biologically adequate coverage.
The final run completed at revision 73 with 2540 retained cells in seven clusters and reviewed
Unknown labels at low confidence. The literal retained sparse counts, feature
order, cell IDs and score attachments were verified in a fresh R process with
21 passing read-only checks. The receipt is
`evidence/cycle-public-pbmc/verify-receipt.json` in the task workspace.

The three cycle choices genuinely executed scaling/PCA, neighbors/UMAP,
clustering and markers three times. The full-input diagnostic reference,
approved QC and normalization/HVG checkpoint each ran once and were reused.
This verifies local execution and dependency reuse; it does not establish which
cycle choice serves a biological study.

Two actual Chrome scenarios passed. In a third, the actual difference R worker
completed successfully, but the browser's terminal DOM wait failed; that failed
attempt remains retained. A separate read-only Chrome finish then passed all
three checks of the complete public project at revision 73, preserving every
project byte and creating no new decisions or scientific computation. Its
receipt is
`evidence/cycle-public-pbmc/browser-finish/cycle-finish-browser-report.json`.
This finish verifies the completed display; it does not erase the earlier
browser failure or turn that attempt into a complete pass.

The final checked runtime fingerprint is
`b5c0c313a62ddaa0688302a3f4dec8068e869f83d4f9196036fc164c646fb16b`.
The public scientific and bundled CLI runs used
`6e1d2bfa220521083b247917aa3528f1ff934437263211fec10ab25f9382f003`.
The later changes were the review-node dispatcher correction and the legacy
`utils::capture.output` qualifier; the scientific functions were unchanged.
The final runtime also passed two actual read-only Chrome configuration checks
on a separate 180-cell fixture at revision 27, `awaiting_configuration` /
`annotation_propose`. The saved none plan and fixed cohort rendered with a null
review node, disabled decisions/Continue, and unchanged project bytes after
refresh. No new job, provider call or scientific computation occurred, and there
were no page errors, external requests or dialogs. Its receipt is
`evidence/cycle-configuration-regression/browser/cycle-config-browser-report.json`.
These versioned receipts distinguish the scientific execution checks from the
later dispatcher regression check.

All of this validation used local computations and supplied/manual or mock
proposals: zero real provider API calls, zero key-file reads and US$0 incremental
provider cost. Linux, HPC, user-server deployment and biological accuracy were
not validated. The synthetic fixture is a software control; successful cycle
execution cannot validate tissue-specific phase calls, coverage thresholds or
the scientific suitability of regression. Automatic Harmony, doublet removal
and subclustering remain outside this coordinator increment.
