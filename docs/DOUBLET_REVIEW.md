# Doublet evidence and an explicit cell-selection decision

Enable `doublet_diagnostics` in `sc_run(..., strategy = TRUE)` to obtain real,
capture-specific scDblFinder scores before the concentrated strategy review.
The default strategy choice is `keep`. Scoring does not delete cells. Only an
exactly approved `remove_predicted` choice removes saved predicted-doublet IDs
that also survive the approved QC filters. QC, this choice, and downstream
analysis settings share one review snapshot and one approval boundary.

This is an optional extension to the existing [strategy workflow](ANALYSIS_STRATEGY_SUPPORT.md).
R inspection, approval and Continue work without a browser. The existing
loopback workbench uses the same saved evidence and locked R authority. Earlier
strategy documentation describing doublet execution as unsupported refers to
runs without this explicit diagnostics configuration.

## Input and loading-unit declarations

The supported scope is explicitly declared human or mouse droplet scRNA-seq,
with genuine raw counts, a known called-cell input source, and empty droplets
already removed. Normalized or scaled expression cannot replace raw counts.
Seurat 5 public layer APIs and exact original cell IDs are used. Ambiguous
layers, metadata collisions or undeclared input facts fail closed.

A capture is a physical loading unit in which doublets could form. Sample,
donor, disease/condition and technical-batch labels are separate roles. Several
donors may share a capture, and one donor may have several captures. These roles
are never inferred from one another. Declare the actual capture metadata column
in both context and diagnostics:

```r
context <- list(
  species = "human", tissue = "your declared tissue",
  columns = list(sample = "sample_id", donor = "donor_id", capture = "capture_id"),
  research_goal = "Your question, including populations you want to preserve",
  design = list(type = "your declared design", technical_batch = FALSE))

options <- list(
  data_type = "scrna_droplet", technology = "declared_droplet_other",
  input_source = "Describe the counts source and called-cell/empty-droplet processing",
  empty_droplets_removed = TRUE,
  full_called_cohort = FALSE,
  capture = list(method = "column", column = "capture_id",
    source = "Describe how these literal labels identify physical loading units"),
  rate = list(method = "manual", value = .08, sd = .02,
    source = "Replace with a defensible external expected-rate source for this experiment"),
  nfeatures = 200L, dims = 10L, artificial_doublets = 1500L,
  seed = 999L, iter = 3L, clusters = FALSE, column_prefix = "sc_doublet")
```

The `.08` above only illustrates syntax. It is not a recommended biological
rate. Manual rates must be finite and strictly between zero and `.5`, either a
scalar or an exactly named map of every declared capture. For example,
`value = c(capture_A = .06, capture_B = .09)` requires those exact capture labels.
The rate source is mandatory. `sd` is explicit expected-rate uncertainty, from
zero through `.5`; the wrapper's default `.02` is a software setting, not a
universal upstream default or a measured experimental confidence interval.

For a genuinely single loading unit with no context capture column, the other
supported declaration is `capture = list(method = "single", id = "capture_A",
source = "Explicit original loading-unit provenance")`. A single donor or
sample name alone is insufficient evidence for this declaration.

## Automatic rate estimation has additional prerequisites

Use `rate = list(method = "10x_standard", source = "Document the applicable
standard 10x loading protocol", sd = .02)` only with
`technology = "10x_chromium_standard"` and an explicit
`full_called_cohort = TRUE`. This declares that the input contains the complete
called-cell cohort from each original capture before quality filtering.
`empty_droplets_removed = TRUE` alone does not establish cohort completeness.
The input source and capture source must still be supplied.

The implemented estimate is `.008 * number_of_called_cells_in_capture / 1000`,
resolved separately for each original declared capture. It is an expected-rate
assumption, not measured doublet prevalence. It is never recomputed from the
QC-retained subset or survivors of an explicitly enabled minimal prefilter.
Previously strongly filtered data, a processed object with
unknown original cohort size, or uncertain completeness require a manually
sourced external expected rate. No rate is guessed from donor names or a small
surviving subset. Automatic Flex and HT rates are unsupported; there is no silent
fallback to the standard formula. These assumptions and the homotypic limitation
are described in the [official scDblFinder vignette](https://bioconductor.org/packages/release/bioc/vignettes/scDblFinder/inst/doc/scDblFinder.html).

## Supported settings and failure behavior

`doublet_diagnostics` is immutable for a project. Changing rate, capture mapping,
input, RNG settings or scoring parameters requires a fresh project. The bounded
settings are `nfeatures` 200–10000, `dims` 2–100 and less than `nfeatures`,
`artificial_doublets` 500–50000, a nonnegative integer seed, exactly `iter = 3`,
and exactly `clusters = FALSE`. Defaults are 1000 features, 20 dimensions, 1500
artificial doublets and seed 999. Feature names and cell IDs must be unique.

| Situation | Behavior |
| --- | --- |
| Every capture's declared scoring-eligible pool has at least 100 cells, every eligible cell at least 200 raw counts, and each pool enough expressed features for the declared settings | Attempt the supported real algorithm independently for each capture |
| Any capture's eligible pool has fewer than 100 cells, any eligible cell fewer than 200 counts, too few expressed features, or incompatible dimension count | Whole diagnostic reference is `unsupported`; every original input cell has `Unknown` class and `NA` score; only `keep` is executable |
| Missing dependencies, unexpected algorithm/version shape, warning, classifier failure, malformed score/class output or wrong returned cell IDs | Recoverable failed stage; no heuristic score substitution and no successful diagnostic claim |
| Processed entry reusing existing analysis | Diagnostics may be inspected; only `keep` is supported, so reused analysis remains applicable |
| Other species, plate-based data, ATAC, unvalidated nucleus protocols, or missing capture/rate provenance | Outside this declared support scope; no biological interpretation is inferred |

The 100-cell and 200-count bounds are **scoring applicability prerequisites**.
They are not automatic QC thresholds and never silently filter input. With
`qc_mad` disabled, the scoring pool is the complete supplied project input and
later quality filtering uses the existing typed ranges. The explicitly enabled
[MAD workflow](MAD_REVIEW.md) adds a default `none` or explicitly preapproved
minimal count prefilter before scoring, followed by one reviewed quality preset.
These prerequisites apply to the resulting scoring-eligible pool; prefilter
exclusions remain unscored with recorded provenance. Legacy `qc_mad()` helpers
and legacy range semantics remain separate. High RNA content,
cell-cycle scores or a high doublet score alone do not authorize removal.

The strict adapter accepts exactly two declared combinations: scDblFinder
**1.26.7** with a valid xgboost version **>=3.1**, or scDblFinder **1.22.0** with
exactly xgboost **1.7.11.1**. The latter is the additional audited existing Linux
pair; another legacy version/backend is rejected. The earlier modern Mac
dependency combination included SingleCellExperiment 1.34.0, BiocParallel 1.46.0
and xgboost 3.2.1.1; that historical combination is not a requirement to upgrade
the older Linux stack. Unexpected version or function shape fails closed.
Runtime versions, function fingerprints and classifier audits are recorded in
evidence. Use a selected private R library without modifying another active
library. See [Linux runtime support](LINUX_RUNTIME_SUPPORT.md) for official
sources, completed Linux v3 full regression and bounded real workflows.

The strict function fingerprint hashes a named representation containing every
formal and the complete body, each rendered by `deparse(..., width.cutoff = 500L)`
and collapsed with literal newlines. It checks canonical expression text rather
than raw serialized R language objects, whose runtime serialization can drift
without an expression change. This normalizes runtime serialization artifacts;
it does not omit expression content or permit a changed algorithm or a hash
bypass. The version-specific accepted canonical fingerprints are:

| scDblFinder release | Function | Canonical formal/body representation SHA-256 |
| --- | --- | --- |
| 1.26.7 | `scDblFinder` | `0beee189415aadb8eb7b1c2bd2d9a87bf7f19b6986cc7b410dd70b3976758fb7` |
| 1.26.7 | `.scDblscore` | `c17836de1f003e867401677a95ddb148311577997c9fd08f9cecda5ba83b4c9f` |
| 1.26.7 | `.xgbtrain` | `9587a78018158c55d5bb3660b87660d9440efadf7d8cbb0476f53bea0aad3307` |
| 1.22.0 | `scDblFinder` | `9a4ad55e93b80d59f4ced150eacd6e5f2429bbe53567c24a5c3dc18194d441b2` |
| 1.22.0 | `.scDblscore` | `c17836de1f003e867401677a95ddb148311577997c9fd08f9cecda5ba83b4c9f` |
| 1.22.0 | `.xgbtrain` | `d9be56120cc9b3e32a117366fbade307f13d06ad08e3e3150f38436fd3d3611a` |

Algorithm parameters, isolated capture execution, three fit/predict audits and
the unchanged installed namespace requirement still apply. These fingerprint
definitions do not establish completed execution or scientific acceptance.

A genuinely missing optional diagnostic dependency can be repaired before
scoring, then the failed local stage can be explicitly retried with
`sc_run_resume(project_dir, retry = TRUE)`. Optional scoring dependencies are
checked and fingerprinted at scoring rather than in the global implementation
version list, so this repair alone does not stale the whole project. The strict
classifier version/source guards still apply. Completed immutable evidence stores
its actual dependency versions and source fingerprints and is reused without
refitting. Changes to core implementation or foundation dependencies still
invalidate the project fingerprint and require a new project. This recovery
policy does not permit changing the immutable input or diagnostics parameters.

Saved evidence is verified against its recorded adapter pair and source hashes,
without looking up the reviewing process's installed optional dependencies.
For older records without an explicit pair field, only saved scDblFinder 1.26.7
plus a valid saved xgboost >=3.1 and the matching successful audits are accepted.
Missing/unknown releases or unversioned legacy evidence require regeneration and
fresh review; there is no automatic approval migration. Explicit unsupported,
unexecuted records remain disclosed and cannot contain fabricated classifier
audits or executed source identities.

Each capture uses a SingleCellExperiment raw `counts` assay, one seeded
`SerialParam`, one xgboost thread, three training iterations and the upstream
thresholding method. An isolated lexical copy of the supported public/scoring
functions audits three actual classifier fits and three predictions per capture.
It preserves that method and leaves the installed namespace unchanged. A swallowed
upstream classifier fallback, warning or incomplete audit causes a failed stage.
Explicit seed and versions improve reproducibility; bitwise identity across
different platforms or dependency versions is not promised.

Each capture seed is derived from the base seed and the literal capture ID's
SHA fingerprint, independently of capture enumeration. The detector receives
features and cells in canonical UTF-8 radix order, then joins results back to
the original input order by exact ID. Canonical input hashes, seed derivation and
runtime RNG settings are recorded. The scoring wrapper restores the caller's RNG
kind and saved seed after using its isolated serial RNG configuration.

## What the scores and classes mean

The score expresses classifier evidence against generated artificial doublets.
It is **not a calibrated probability** that a cell is a biological doublet.
`singlet` and `doublet` are predicted classes at the saved algorithm threshold,
not ground truth. Homotypic doublets can be hard to distinguish from singlets;
rare populations or unusual expression can also complicate interpretation.
Neither a low score nor the expected rate proves biological correctness.
Capture-specific scores are not automatically interchangeable between captures.
The official method documentation explains these [limitations and scoring steps](https://bioconductor.org/packages/release/bioc/vignettes/scDblFinder/inst/doc/scDblFinder.html).

With `qc_mad` disabled, scoring uses the fixed complete project input **before
the approved range QC**. With the MAD workflow enabled, the declared minimal
prefilter first establishes a fixed scoring-eligible cohort; scoring still
precedes the reviewed quality filtering. Original, pre-score and post-QC cell
counts are separate, and expected-rate provenance remains based on the original
declared full called-cell capture, rather than the surviving scoring pool.
Scoring is computed once, persisted with original counts/feature/cell/capture,
prefilter-scope and options fingerprints,
and subsequently joined by exact literal cell ID. Changing QC or the reviewed
keep/remove choice does not refit the classifier or replace the reference.
`full_called_cohort = FALSE` remains disclosed when this input is not the complete
original experimental cohort.

## Review the joint impact before approving

The typed strategy field is one of:

```r
proposal$doublet <- list(method = "keep", reason = "Why these predictions should remain")
# Or, after inspecting the saved scope and consequences:
proposal$doublet <- list(method = "remove_predicted", reason = "Why removing these exact predictions is justified")
```

Omitting this field defaults to `keep`. Custom score cutoffs, arbitrary cell
lists, generated R code and an automatic doublet-removal policy are unsupported.
The displayed evidence includes the fixed cohort, per-capture rate provenance,
score/class summaries, QC-retained predictions, predictions already excluded by
QC, exact final retained/removed scopes, and per-capture removal fractions relative
to both input and QC-retained cells. Optional cycle diagnostics provide descriptive
score/phase summaries for these scopes; they do not add a cycling-cell deletion
rule. A large combined QC/doublet removal is visible before the joint approval.

Revising `keep` to `remove_predicted`, or back to `keep`, creates a fresh whole
strategy snapshot and hash. Inspect and approve that new snapshot. Necessary
selection, normalization and downstream analysis stages are invalidated; saved QC
and doublet evidence are reused. The new `strategy_selection` stage derives the
approved exact subset before recomputing analysis. Restoration therefore restores
previously excluded predictions from the fixed QC object; it does not reuse a
basis fitted to a different cell set. Revisions are available before annotation
writeback. An already applied final result requires a fresh project.

The new `sc_doublet_score`, `sc_doublet_class` and `sc_doublet_capture` columns
are fresh output metadata. Existing `doublet_score`, `doublet_class`, source cell
IDs and annotation columns are preserved. A configured prefix collision fails
rather than overwriting metadata. Source objects are never edited in place.

## One complete headless example

The installed `examples/doublet-review.R` includes a reproducible 440-cell fixture:
two declared captures, each with 200 independent synthetic singlet controls and
20 exact count sums across two artificial expression programs, over 600 genes.
It declares separate sample/donor roles crossing captures. Planted labels are
software controls, not real doublet ground truth. The `.08` expected rate and `.02`
uncertainty are explicit software parameters, not an experimental estimate.
The enabled diagnostics call the real supported scDblFinder method; no mock model,
API key, request, download or dependency installation is used.

After installing this checkout in your selected R library:

```r
library(scAgentKit)
source(system.file("examples", "doublet-review.R", package = "scAgentKit"))
input <- doublet_example_input()
project <- "/absolute/path/to/a/new/doublet-project"
before <- digest::digest(input, algo = "sha256")

doublet_example_start(input, project, doublet_example_context(),
  doublet_example_options(), doublet_example_proposal())
shown <- doublet_example_inspect(project)
strategy_example_decide(project, shown, "approve", "analyst",
  "Approve the exact displayed synthetic strategy while retaining predictions")
shown <- doublet_example_inspect(project)
strategy_example_continue(project, shown)

# At annotation review, use manual Unknown labels for this software fixture.
# This is an explicit unresolved interpretation, never an AI or biological result.
shown <- doublet_example_inspect(project)
strategy_example_unknown(project, shown, "analyst")
shown <- doublet_example_inspect(project)
strategy_example_decide(project, shown, "approve", "analyst",
  "Retain explicitly unresolved synthetic identities")
shown <- doublet_example_inspect(project)
strategy_example_continue(project, shown)
final <- readRDS(sc_run_inspect(project)$output$seurat)
stopifnot(identical(before, digest::digest(input, algo = "sha256")))
```

To compare an approved removal before annotation writeback, inspect the current
strategy evidence, call `doublet_example_revise(project, shown,
"remove_predicted", "analyst", "Your explicit rationale")`, inspect the fresh
snapshot, approve, inspect again and Continue. The same sequence with `"keep"`
restores the QC-retained set. Unsupported evidence permits only `keep`.

The script also supports separate `Rscript --vanilla` processes. Set the script
path to the installed example and the project path to a **new** directory:

```sh
doublet_example_path=/absolute/path/to/scAgentKit/examples/doublet-review.R
doublet_project_dir=/absolute/path/to/a/new/doublet-project
Rscript --vanilla "$doublet_example_path" "$doublet_project_dir" demo
Rscript --vanilla "$doublet_example_path" "$doublet_project_dir" inspect
Rscript --vanilla "$doublet_example_path" "$doublet_project_dir" approve
Rscript --vanilla "$doublet_example_path" "$doublet_project_dir" inspect
Rscript --vanilla "$doublet_example_path" "$doublet_project_dir" continue
Rscript --vanilla "$doublet_example_path" "$doublet_project_dir" inspect
Rscript --vanilla "$doublet_example_path" "$doublet_project_dir" propose-unknown
Rscript --vanilla "$doublet_example_path" "$doublet_project_dir" inspect
Rscript --vanilla "$doublet_example_path" "$doublet_project_dir" approve
Rscript --vanilla "$doublet_example_path" "$doublet_project_dir" inspect
Rscript --vanilla "$doublet_example_path" "$doublet_project_dir" continue
Rscript --vanilla "$doublet_example_path" "$doublet_project_dir" output
```

`inspect` persists a convenience copy of the displayed snapshot. The example's
`approve`, `reject`, `continue`, `revise-keep` and `revise-remove-predicted` modes
require that saved snapshot, so stale revisions are refused. This convenience
file does not replace the authoritative locked journal. Continue performs only
supported local computation and does not contact a provider.

For real public PBMC validation, use the original filtered raw-count matrix and
declare its actual original capture provenance; do not substitute synthetic data
or a previous smaller smoke-test subset. The official [10x PBMC3k dataset page](https://www.10xgenomics.com/datasets/3-k-pbm-cs-from-a-healthy-donor-1-standard-1-1-0)
and [original Cell Ranger summary](https://cf.10xgenomics.com/samples/cell-exp/1.1.0/pbmc3k/pbmc3k_web_summary.html)
describe human PBMC and 2700 called cells. Under an explicit single standard-10x
capture and full-cohort declaration, the formula gives `.0216`, or 58.32 expected
doublets. This is a loading-model assumption, not an observed count, and the donor
label alone does not prove loading-unit identity.

## Saved artifacts, privacy and deployment limits

Alongside the usual new Seurat object, markers, annotation, parameters, report,
recovery script and decision history, enabled runs write:

- `output/doublet_scores.csv`: fixed full-reference scores/classes and literal IDs;
- `output/doublet_selection.csv`: reviewed joint QC/doublet selection membership;
- `output/doublet_summary.json`: provenance, settings, hashes and selection impact;
- `output/doublet_diagnostics.png`: local diagnostic summaries.

Per-cell scores and exact IDs stay in local private checkpoints and outputs.
They are not model payloads. An explicitly approved model payload may include
aggregate diagnostic/QC evidence and supplied context, including declared
capture labels and input/rate source descriptions. Those descriptions must not
contain secrets or unnecessary personal information. Raw counts, barcodes,
individual metadata and planted-control labels are not supplied to a provider.
Keys remain in the running machine's environment or caller memory; they are not
written into the project, browser, exported objects or logs.

A configured workbench binds to loopback and can be reached by an explicit SSH
tunnel. It does not open a public listener, change authentication/firewall rules,
automatically submit scheduler jobs or require a browser to keep R running.
See [SERVER_FIRST.md](SERVER_FIRST.md) for the existing launch/recovery workflow.
This doublet increment did not add Harmony or subclustering. The current
separately reviewed contracts are in [Harmony/PC review](HARMONY_PC_REVIEW.md)
and [subcluster review](SUBCLUSTER_REVIEW.md); batch or child analysis is never
inferred from enabling doublet diagnostics.

## Current bounded Linux runtime acceptance

The accepted scDblFinder 1.22.0/xgboost 1.7.11.1 pair completed real classifier
execution in three new projects and fresh R verification: public PBMC
**2700 → 2511** cells, and two independent synthetic projects each
**440 → 438** cells (two literal captures, each 220 → 219). Each capture
completed three successful training operations and three predictions. Exact
cell/count/metadata joins, old annotation columns and durable fresh-resume
files were preserved; approved filtering did not refit the saved diagnostics.
The first helper failure compared unsorted source features with intentionally
canonical diagnostic ordering; it remains recorded alongside the corrected
helper run. No production change was needed for that helper correction.

Linux v2 full check completed with **7379 PASS, 0 FAIL, 0 WARN, 2 SKIP** and
**Status: 2 NOTEs**. The two genuine checks requiring the modern 1.26.7
runtime were skipped on this legacy-pair Linux runtime. V3 changes only
packaging exclusion; its actual final Linux check is **Status OK**, exit 0,
**7379 PASS / 0 FAIL / 0 WARN / 2 SKIP** in 1325.37 seconds. The same
modern-runtime checks are skipped, while the genuine legacy test ran. All
52 test files and the standard runner match the checked source. These outcomes
establish bounded execution/integrity, not doublet truth or calibrated
probabilities. This increment used no live model request and cost US$0.
See [runtime receipts and limits](LINUX_RUNTIME_SUPPORT.md).

## Prior doublet-increment acceptance

These are historical receipts for the named runtime, not new checks against the
prior `bd8f799` release candidate. See the
[release checklist](RELEASE_CANDIDATE_CHECKLIST.md) for those named receipts and
[current Linux runtime support](LINUX_RUNTIME_SUPPORT.md) for the additional
strict pair, completed bounded Linux acceptance and final Linux v3 full check.

The preceding doublet increment's Mac execution acceptance passed for the frozen runtime fingerprint
`307ca5a303b6546f0b0f2476ae2b60856b4b2205f31afd2460bd555ca1cebf4e`.

- R package check reported `Status: OK` in 235.15 seconds: 5141 passing
  assertions, zero failures, test warnings or skips. Python passed 231 tests
  with zero skips; DOM suites passed 39, 17 and 34 checks. Five missing optional
  Suggests (`harmony`, `clustree`, `magick`, `ontologyIndex`, `SeuratData`) were
  recorded as information. Repository-index network-warning text was retained;
  no installation fallback, manual or vignette validation is claimed.
- The final 440-cell, two-capture synthetic project completed at revision 83
  with two clusters. Each capture had three genuine fits and three predictions;
  21 plus 20 predicted doublets gave 41 total. Reviewed keep → remove → keep
  produced 440 → 399 → 440 cells. Raw counts, legacy factor values/levels and
  prior annotations were preserved, and the PCA basis was restored. Actual
  missing-dependency repair resumed in a fresh R process with QC reuse;
  feature/cell reordering preserved scores/classes bitwise and caller RNG was
  restored. Planted controls remain software checks, not biological truth.
- The unchanged public human PBMC source had 32738 features and 2700 cells.
  One explicitly declared standard-10x full called-cell capture used nominal
  expected rate `.0216` and uncertainty `.02`. There were 90 input predictions:
  84 survived the explicitly supplied historical DeepSeek QC proposal's 2511
  cells and six overlapped QC exclusions. Actual Chrome whole-JSON approval
  removed those 84; stale review returned HTTP 409 without mutation. The fixed
  local R job succeeded at annotation configuration, revision 51. Manual
  Unknown/low annotations completed 2427 cells and seven clusters at revision
  60. Finalization passed 22 checks and fresh readonly R verification 21.
  QC/evidence stages executed once, selection/affected downstream stages twice,
  and annotation application/finalization once.
- Actual Chrome strategy-review and readonly-finish suites each passed 3/3,
  with zero page errors, external requests or provider calls. Readonly finish
  preserved project bytes and 45 protected prior files. Earlier public-v1
  receipts retain two passes and one terminal harness failure despite R-job
  success, plus the repeated-QC numeric-storage hash bug. Final acceptance
  used a fresh public-v2 project; old hashes were not migrated.

Task-workspace receipts are retained under `evidence/doublet-final`,
`evidence/doublet-synthetic-final`, and `evidence/doublet-public-pbmc`
(`v2-*` receipts, `browser-v2`, `browser-finish-v2`). This increment made zero
model API calls or key-file reads and incurred US$0 provider cost. Mouse
scientific acceptance remains **0/1**. Linux, HPC and user-server environments
were not tested. These results establish bounded software execution and review
behavior, not automatic biological accuracy. That acceptance did not include
MAD, Harmony or subcluster execution. Current MAD scope and its separate
verification record are documented in [MAD_REVIEW.md](MAD_REVIEW.md).
