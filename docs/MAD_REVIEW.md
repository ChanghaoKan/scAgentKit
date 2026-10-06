# Sample-aware MAD candidates and one joint review

`sc_run(..., strategy = TRUE, qc_mad = ...)` adds a deterministic, local QC
candidate panel. It calculates declared group statistics, compares six supported
rules, and waits for a complete strategy proposal and joint approval. The
default candidate is `keep_all`. The coordinator does not pick a rule to meet a
retention target or use annotation/planted labels as quality truth.

R inspection, approval and Continue use the same saved state as the optional
loopback workbench. A browser is not required. This increment does not add
Harmony, automatic donor assignment, ambient-RNA correction, or a claim that
one candidate is universally appropriate.

## Declare QC groups independently of captures

A QC group is the pool whose counts, feature counts and mitochondrial fraction
you want compared with its own distribution. Declare it as `qc_group` or an
explicit `sample` role, with a metadata column and provenance. A capture is the
physical loading unit used for doublet scoring. Donor, condition and technical
batch are additional separate roles. Their relationships are not guessed.

For example, several sample QC groups can share one capture, and a QC group can
cross captures. Such a declaration records the analyst's intended comparison;
it does not prove that cells in that pool have comparable biological quality.
Literal labels and exact cell IDs are preserved. Duplicate IDs, ambiguous
columns and inconsistent context/configuration declarations fail validation.

```r
context <- list(
  species = "human", tissue = "your declared tissue",
  columns = list(qc_group = "qc_pool", sample = "sample_id",
    capture = "capture_id", donor = "donor_id"),
  research_goal = "Your question and populations that require careful retention",
  notes = "Explain how QC pools, biological samples and loading units relate")

mad_options <- list(
  grouping = list(method = "column", declared_role = "qc_group",
    column = "qc_pool", source = "Your explicit QC comparison-pool definition"),
  prefilter = list(method = "none"))
```

For a single explicitly declared pool with no relevant context column, use
`grouping = list(method = "single", id = "my-qc-pool", source = "Explicit pooling
provenance")`. This does not infer a donor, sample or capture from the pool ID.
The installed example below supplies distinct QC-group, sample, donor and
capture labels.

## Two filtering stages with recorded cell scopes

The order is explicit:

1. Validate immutable raw counts, input identity and declarations.
2. Apply the immutable, explicitly preapproved minimal prefilter on a copy.
3. Score doublets separately by declared capture on prefilter-eligible cells,
   when diagnostics are enabled. Persist the fixed scoring reference.
4. Compute group MAD statistics and the quality candidate panel on that same
   prefilter-eligible reference. Inspect all groups and candidates together.
5. Approve one complete strategy with its exact QC and optional doublet impact.
6. Apply the chosen quality rule, then the approved predicted-doublet choice,
   before normalization and downstream analysis.

The default minimal prefilter is `none`. The only removal alternative is
`list(method = "min_counts", min_counts = 200L, source = "Your explicit reason",
preapproved = TRUE)`, with an integer bound from 1 through 200. Cells with raw
counts below the declared bound are excluded before scoring; equality is kept.
This is an explicit eligibility policy, not an automatic dynamic-quality rule.
Its declaration authorizes that limited operation before the later joint review.
Changing it requires a new project. Scoring still has its own applicability
checks; a lower prefilter bound does not make a low-count capture scoreable.

The prior doublet increment scored the whole original input before the approved
legacy range QC. With MAD disabled this legacy behavior remains. Enabling a
prefilter changes the fixed scoring cohort and can change predictions, so the
original-input, prefilter-eligible/pre-score and post-quality-QC scopes are
displayed separately. No existing range proposal is silently translated to MAD.
Legacy inclusive ranges retain their existing conjunction and group semantics.

For declared standard 10x full called cohorts, the expected rate is resolved
from the original declared capture cell counts, before this prefilter, and its
source is recorded. It is not recomputed from prefilter survivors or the final
QC subset. Unknown completeness or previously quality-filtered input requires a
manually sourced rate. The official [scDblFinder ordering discussion](https://bioconductor.org/packages/release/bioc/vignettes/scDblFinder/inst/doc/scDblFinder.html)
motivates limited early coverage handling and later quality filtering; the
implemented 1–200 prefilter bounds are this wrapper's supported policy.

## Exact statistics and finite candidates

Within each declared QC group, counts and detected features are transformed as
`y = log10(x + 1)`. The center is `median(y)` and the scaled MAD is
`1.4826 * median(abs(y - median(y)))`. The lower threshold is `median(y) - 3 *
scaled_MAD`; the high-RNA diagnostic threshold is `median(y) + 3 * scaled_MAD`.
Mitochondrial percentage uses its original 0–100 scale with the upper threshold
`median(percent_mt) + 3 * scaled_MAD(percent_mt)`.

The scale constant follows [R's MAD definition](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/mad.html).
The `+1`, fixed multiplier, guards and candidate combinations are explicit
coordinator choices. They do not promise that each metric is normally
distributed or that a nominal normal-tail interpretation applies to the data.
Saved numeric thresholds and exact comparisons drive execution; rounded UI
numbers are only display text. Threshold equality is retained.

| Preset ID | Cells proposed for quality exclusion |
| --- | --- |
| `keep_all` | None of the prefilter-eligible cells |
| `conservative_and3` | Low log-counts **and** low log-features **and** high mitochondrial percentage |
| `low_counts3` | Low log-counts |
| `low_features3` | Low log-features |
| `high_mt3` | High mitochondrial percentage |
| `any_quality3` | Low log-counts **or** low log-features **or** high mitochondrial percentage |

Each name refers to the same saved 3-scaled-MAD group thresholds; no provider can
invent a seventh rule, arbitrary bound, executable code or exact-ID deletion
list. `conservative_and3` is the user's conservative comparison option, not a
universal recommendation. The single-metric and OR alternatives expose the
different consequences of relaxing that conjunction.

High count/feature tails are diagnostics only and do not remove cells in any
MAD preset. Ribosomal and hemoglobin summaries likewise provide context without
authorizing deletion. The optional doublet choice is separately `keep` or
`remove_predicted` and can remove only the fixed predicted IDs that survive the
approved quality policy. A high-RNA flag does not itself establish a doublet.

The primary [OSCA QC discussion](https://bioconductor.org/books/release/OSCA.basic/quality-control.html)
supports examining metric distributions and the mostly-good assumption behind
adaptive QC. This implementation compares a bounded set of explicit policies;
it does not reproduce the complete scuttle QC interface.

## Unknown thresholds, empty groups and scientific limits

| Condition | Recorded meaning and executable behavior |
| --- | --- |
| At least 30 finite values and a supported positive MAD for each required metric | The corresponding metric rule can be compared and selected |
| Small group, zero/near-zero MAD, missing or nonfinite required values | Threshold/flag is unknown with a reason; a preset requiring that metric is unavailable |
| Unknown metric threshold | It is stored as `NULL`, never a fabricated zero or infinite bound |
| `keep_all` | Remains the explicit supported fallback for intact input, including groups with unsupported MAD thresholds |
| Group has no prefilter-eligible cells | The group remains in the scope audit with an observed zero; an unavailable metric statistic is not reported as measured zero |
| Approved policy excludes an entire group | Observed post-QC size is zero and its fraction is recorded against the defined starting scope |
| Multimodal/uneven distribution or apparent majority quality concern | A warning for analyst review; no automatic threshold change or biological diagnosis |

The 30-cell minimum and near-zero guard are software support conditions, not
validated biological cutoffs. The numerical guard is
`scaled_MAD <= sqrt(.Machine$double.eps) * max(1, abs(median))` on the metric's
recorded transformed scale. No metric-dependent epsilon is silently tuned.
The panel distinguishes zero counts from unknown
statistics and fractions with no defined denominator. It does not impute a
threshold from another sample, silently switch to a pooled rule, or discard
nonfinite values to make a candidate look valid.
An explicit prefilter that leaves no cells in the entire project cannot yield
an executable final object; validation stops before a whole-project deletion
can be approved. An original group that becomes empty remains an observed
zero-sized scope, while its thresholds remain unavailable.

Relative thresholds cannot establish absolute quality if most cells are poor.
They can also label a valid small/low-RNA or high-mitochondrial population as an
outlier. Multiple metric modes may reflect biological mixtures, depth or
technical effects. Warnings are descriptive heuristics, not cell-quality truth.
Inspect source provenance, distributions, group sizes and the whole impact;
external assay information may justify keeping all cells or a separate manual
investigation. The coordinator does not tune thresholds using retained-cell
counts, cluster labels, known cell types or synthetic planted controls.

## One central choice, with R and browser sharing authority

Start with the main entry and inspect its saved panel. Without a provider or a
supplied complete proposal, the run finishes at an `awaiting_configuration`
boundary; statistics are saved and no analysis node waits for an open browser.
Build a complete strategy from that snapshot, selecting exactly one available
preset by its ID and current `panel_hash`. The typed QC field is:

```r
list(schema = "scagentkit.qc.mad.v1",
  rationale = "Why this explicit policy is appropriate for this comparison",
  risks = list("Remaining scientific uncertainty"),
  preset_id = "keep_all", panel_hash = current_panel_hash)
```

The strategy revision creates a fresh whole review snapshot, including all
group impacts, optional doublet/cycle summaries and analysis settings. Inspect
and approve that snapshot once. There are no separate sample approval dialogs.
A local mock provider can exercise the constrained preset-selection mechanism;
it is not a biological AI decision. Any configured external provider still
requires the existing external-transfer authorization and approved aggregate
payload. Missing, malformed or unsupported output stops recoverably rather
than choosing a fixed rule on the provider's behalf.

Saved input/context/configuration, group assignments, prefilter scope, panel,
rules and proposals have versioned fingerprints. Approval is bound to the
current project, input, revision, proposal and review hashes. A stale browser or
R snapshot cannot approve a changed panel. The atomic journal and lock reject
concurrent or duplicate execution. Continue can run in another R process and
reuse completed evidence without another scorer or model call.

Changing the approved preset before annotation writeback creates a new joint
review and invalidates the QC object and necessary downstream results. The
immutable original/pre-score evidence remains reusable. Rate/capture/scorer or
prefilter changes require a fresh project. An already applied final result also
requires a fresh project. No automatic state migration changes old projects'
scientific meaning.

## Reproducible headless example

The installed `examples/mad-review.R` builds sparse synthetic raw counts with
distinct QC-group, sample, donor and capture labels. Its controls exercise the
mechanism, not biological accuracy. No key, model call, download or automatic
dependency installation is used. Start, inspect the panel, propose a chosen
policy, inspect/approve, Continue, then review unresolved annotations:

```r
library(scAgentKit)
source(system.file("examples", "mad-review.R", package = "scAgentKit"))
input <- mad_example_input()
project <- "/absolute/path/to/a/new/mad-project"
before <- digest::digest(input, algo = "sha256")
mad_example_start(input, project, mad_example_context(), mad_example_options())
shown <- mad_example_inspect(project)
mad_example_propose(project, shown, "keep_all", "analyst",
  "Retain this synthetic comparison while inspecting the measured candidates")
shown <- mad_example_inspect(project)
strategy_example_decide(project, shown, "approve", "analyst",
  "Approve this exact whole synthetic strategy and its displayed impact")
shown <- mad_example_inspect(project)
strategy_example_continue(project, shown)
shown <- mad_example_inspect(project)
strategy_example_unknown(project, shown, "analyst")
shown <- mad_example_inspect(project)
strategy_example_decide(project, shown, "approve", "analyst",
  "Keep the synthetic identity interpretation explicitly unresolved")
shown <- mad_example_inspect(project)
strategy_example_continue(project, shown)
final <- readRDS(sc_run_inspect(project)$output$seurat)
stopifnot(identical(before, digest::digest(input, algo = "sha256")))
```

The example also exposes `Rscript --vanilla mad-review.R PROJECT_DIR MODE` for
separate-process inspection and recovery. The supported mode list is printed
in its header. Every decision uses a displayed snapshot; inspect again after a
revision or Continue. Keep the input and project on the execution machine.
No manual RDS transport or ZIP export/import is needed for these operations.

```sh
mad_example_path=/absolute/path/to/scAgentKit/examples/mad-review.R
mad_example_project=/absolute/path/to/a/new/mad-project
Rscript --vanilla "$mad_example_path" "$mad_example_project" demo
Rscript --vanilla "$mad_example_path" "$mad_example_project" inspect
Rscript --vanilla "$mad_example_path" "$mad_example_project" propose-keep-all
Rscript --vanilla "$mad_example_path" "$mad_example_project" inspect
Rscript --vanilla "$mad_example_path" "$mad_example_project" approve
Rscript --vanilla "$mad_example_path" "$mad_example_project" inspect
Rscript --vanilla "$mad_example_path" "$mad_example_project" continue
```

At the saved annotation configuration boundary, run `inspect`, then
`propose-unknown`, `inspect`, `approve`, `inspect`, `continue`, and `output` with
the same script/project arguments. These manual Unknown/low labels retain
uncertainty; they are not an AI annotation result. To compare a different
available quality policy before annotation writeback, inspect and use
`propose-conservative-and3` or `propose-any-quality3`, then inspect and approve
the fresh whole strategy before Continue. The unchanged statistics and scorer
are reused; necessary downstream analysis is recomputed for the changed IDs.

The optional workbench binds loopback and reads this same `project_dir`. On a
server use the documented SSH tunnel from your own authorized connection; no
public binding, firewall change or scheduler submission is performed by this
example. Headless execution is the primary path.

## Support and verification record

| Supported in this increment | Outside its scope |
| --- | --- |
| Explicit QC-group/sample pooling, sparse raw-count statistics, six saved presets, one whole review, exact cell selection and resumable execution | Inferring donor/sample/capture relationships or selecting a biological best rule |
| Optional minimal prefilter, fixed capture score reference and original-cohort rate provenance | Automatic empty-droplet calling, arbitrary prefilters or quality-driven rate refitting |
| Missing/degenerate-statistic guards and descriptive distribution warnings | Proof that most cells are high quality or that a mode is technical |
| R and the existing loopback workbench sharing approval state | Automatic batch selection or claimed Linux/HPC validation; optional guarded Harmony has a separate [review contract](HARMONY_PC_REVIEW.md) |

MAD is enabled only for `strategy = TRUE` with `start_stage = "qc"`. The existing
explicit [processed-object entry](ANALYSIS_STRATEGY_SUPPORT.md) can reuse a
supplied foundation, but does not apply this new MAD/prefilter path to it.
Leaving `qc_mad = NULL` or `FALSE` preserves the earlier typed range-QC path.
Bare `qc_mad = TRUE` is insufficient because the QC grouping must be declared.

The following is the historical MAD-increment acceptance, not a fresh check of
the release candidate. See the [release checklist](RELEASE_CANDIDATE_CHECKLIST.md)
for the current source and validation status.

Mac acceptance used the private installed package with implementation SHA-256
`aa9a98e9a9e985a886d659f26424f3ded4ac1b1c5efd931e73c486615b9415af`.
The final full `R CMD check --no-manual --ignore-vignettes` returned Status OK:
5,954 assertions passed, with no test failures, warnings or skips. Five missing
optional Suggests and repository-index access warnings remain in the check log.
Python regression passed 231/231 with 62 original fixture files unchanged.
Production-source DOM tests passed MAD 45/45, doublet 39/39, cycle 17/17 and
strategy 34/34; these DOM tests are separate from real browser execution.

The actual synthetic run had 480 cells, two independently declared QC pools
crossed with two captures, and four predeclared zero/199-count controls.
Real capture scoring used the 476 prefilter-eligible cells before MAD quality
selection. Approved keep_all → conservative_and3 → keep_all retained
476 → 464 → 476 cells. Seven separate R processes covered this main loop, fresh output verification
and independent reversal check; restoration reproduced the exact original
selected IDs and PCA.
An independent genuine cell/feature/capture encounter-order reversal reproduced
actual scores/classes/thresholds/seeds, preserved caller RNG and source objects,
and gave the same exact MAD thresholds and candidate cell sets.

The public PBMC3k run used all 2,700 original called cells, one explicitly
sourced QC pool and a separately declared loading unit. The predeclared
high_mt3 software comparison retained 2,607 cells and produced nine clusters,
with a separately approved new Unknown/low annotation column. Original-cohort
expected rate remained .0216; no doublet deletion was requested. Real Chrome
passed 3/3 concentrated review/approval/Continue checks, including a stale
approval HTTP 409 with unchanged scientific bytes. A new readonly Chrome/server
session passed 3/3 completion checks with every project byte unchanged. Input,
prefilter, MAD, cycle and capture-score checkpoints were reused; QC/foundation
ran twice for the two approved quality choices, while annotation/finalize ran
once. Source raw counts and old typed annotations were preserved by exact ID.

Earlier failed test attempts are retained in the local handoff: one Seurat
reordering fixture and two browser-harness expectations were corrected without
changing the final production implementation or hiding prior evidence.
External provider requests, key-file reads and new costs were all zero.
Mock model selection verifies the bounded aggregate interface; these actual
runs do not claim an AI biological decision or validated cell identities.
No mouse dataset or Linux/HPC/server was tested. The PBMC single-pool result
cannot establish sample-aware optimality across biological samples.

Saved projects bind their implementation and foundation versions. Resume with
the matching frozen namespace; this increment does not silently migrate older
project fingerprints. Explicit processed-object entry can reuse an existing
foundation in a new project.
