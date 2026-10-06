# Inspect QC impact before approving analysis

`sc_run()` now saves the impact of its typed QC proposal before changing the
cell set. An `awaiting_review` result is a normal pause: R can exit, and another
R process can inspect, approve or revise the saved proposal. After approval,
`sc_run_resume()` applies that exact plan to a copy and continues the existing
normalization, clustering and marker workflow. The data and review journal stay
in `project_dir`; everyday review requires neither a ZIP transfer nor a browser.

## A small offline example

Install this version of the package on the machine that holds the data. The
self-contained [example](../inst/examples/qc-review.R) creates a sparse,
non-PBMC synthetic epithelial/stromal/endothelial mixture and a new project.
Its fixed cutoffs test the review mechanism; they are not suggested cutoffs for
another study. It uses no provider, permits no external transfer and has a zero
budget.

```sh
Rscript --vanilla inst/examples/qc-review.R /durable/path/to/new-project run
Rscript --vanilla inst/examples/qc-review.R /durable/path/to/new-project inspect
Rscript --vanilla inst/examples/qc-review.R /durable/path/to/new-project approve
Rscript --vanilla inst/examples/qc-review.R /durable/path/to/new-project resume
Rscript --vanilla inst/examples/qc-review.R /durable/path/to/new-project inspect
```

The example's `inspect` mode saves the displayed proposal/preview fingerprints
and revision in `example-reviewed-snapshot.rds`. Its `approve` mode uses that
snapshot: a changed proposal cannot be approved through an older inspection.
The script checks that its source Seurat object did not change. The final
`resume` performs local analysis and returns `awaiting_configuration` at
`annotation_propose`, because this example supplies no annotation provider or
manual annotation. The annotation evidence and analysis checkpoints remain in
the project. Review of annotations is a separate decision.

The supplied example has been run on the development Mac through these four
separate R processes, including an idempotent repeat decision. Its fixed rule
retained 174 of 180 cells and preserved exact raw-count/old-annotation subsets.
With these toy data and analysis settings it produced one cluster and no DE
markers, so it demonstrates saved QC review and recovery rather than biological
annotation performance. Empty marker evidence and unknown identities remain
visible instead of being filled with invented labels.

In an R session, the normal interaction is one start call and a few review calls:

```r
library(scAgentKit)

project_dir <- "/durable/path/to/new-project"
context <- list(
  species = "human", tissue = "your declared tissue",
  columns = list(sample = "sample_id", capture = "capture_id",
                 condition = "condition"),
  notes = "Describe study features and known limitations here."
)

# input is your sparse raw-count matrix, Seurat object or local RDS path.
# This is an explicit analyst rule; choose it for the actual study before use.
rule <- list(
  schema = "scagentkit.qc.v1",
  rationale = "State why these study-specific bounds need review.",
  risks = c("Low-depth cells can be biologically real."),
  filters = list(list(op = "range", metric = "nCount", min = 1L))
)
sc_run(input, project_dir, context = context, provider = NULL, budget = 0,
       review = list(allow_external = FALSE), qc_proposal = rule,
       annotation_column = "new_reviewed_annotation")

current <- sc_run_inspect(project_dir)
impact <- current$qc_preview$details
impact$retention
impact$remove_cells                    # exact literal IDs, in input order
impact$filter_impacts                  # independent, unique and unavailable
impact$overlap                         # overlapping measured exclusions
impact$patterns                        # exact combinations and their cell IDs
impact$distributions                   # before/retained/removed, globally/by group
impact$unavailable
file.path(project_dir, current$qc_preview$plots$distributions)

# Only after inspecting this particular saved snapshot:
sc_run_approve(project_dir, proposal_hash = current$pending$hash,
  preview_hash = current$qc_preview$hash, expected_revision = current$revision,
  reviewer = "analyst name", reason = "Explain why the reviewed impact is acceptable.")
sc_run_resume(project_dir)
```

For a plain matrix without metadata, omit `context$columns`; the coordinator
then discloses that separate sample/capture assessment is unavailable. For a
Seurat object, declared columns must already exist. Provider setup and the
processed-object entry point are described in [SERVER_FIRST.md](SERVER_FIRST.md).
If neither a provider nor a manual rule is supplied, the run diagnoses the data
and pauses for configuration rather than inventing an AI decision.

## Input and rule contract

| Item | Supported contract |
|---|---|
| Counts | Named matrix, sparse Matrix, Seurat, or local RDS. Finite, nonnegative integer raw counts with unique literal feature/cell IDs. |
| Layer | Exact `assay`/`counts_layer`; Seurat 5 public layer API. Normalized or scaled layers cannot stand in for raw counts. Ambiguous/split or incomplete cell coverage fails closed. |
| Feature universe | Matrix input keeps all supplied genes (`min.cells=0`, `min.features=0`). Changing the gene universe changes QC evidence and requires a new review. |
| Grouping | Only explicitly declared sample/capture columns. A filter can select literal values such as `group=list(sample="sample A", capture="capture 1")`. Scope is recorded as exact cell IDs. |
| Biological context | Species, tissue, free-text notes, and declared condition/donor/batch roles. Condition is not inferred as batch, capture is not inferred as donor, and the default typed-range path skips integration; optional strategy Harmony has a separate reviewed contract. |
| Operations | Only `op="range"` on `nCount`, `nFeature`, `percent_mt`. Bounds are inclusive; at least one finite nonnegative bound is required. Count/feature bounds are integers and mitochondrial bounds lie in 0–100. |
| Execution | All filters are combined with AND; cells outside a group's scope are unaffected by that filter. No arbitrary R or model-generated code is executed. |

`nCount` is the raw-count column total and `nFeature` is the number of features
with positive raw counts. Matrix feature IDs that Seurat would automatically
rename must be renamed explicitly before input; the coordinator does not repair
them silently. Literal cell IDs such as `"001"`, `"1"` and `"NA"` remain distinct.

The current mitochondrial calculation recognizes human `^MT-` and mouse `^mt-`
feature conventions. Unspecified/unsupported species or no matching genes means
the percentage is unavailable, not zero. Zero total counts also makes the
percentage unavailable. A proposal cannot retain a cell with an unavailable
measurement required by its filters. Missing values may be disclosed on a cell
already excluded by another measured condition; they do not themselves become
a removal rule. If mitochondrial percentage cannot be measured, omit that rule
or prepare a correctly identified input and start a fresh project.

Independent filter counts overlap. For example, six cells failing both a count
and a feature lower bound means six removals, not twelve. `filter_impacts`
reports low/high exclusions, unavailable values and exclusive removals;
`patterns` records exact combinations; `overlap` counts co-failing measured
conditions. Distribution summaries retain separate measured and unavailable
counts. The saved plot shows measured before/retained/removed distributions;
neither the plot nor its quantiles establishes an optimal threshold.

## Explicit comparisons, then a fresh decision

At the initial call, add a small prespecified comparison set:

```r
comparison_rule <- rule
comparison_rule$filters[[1]]$min <- 2L
preview_options <- list(
  sensitivity = list(list(id = "explicit count comparison", proposal = comparison_rule)),
  gene_panels = list(epithelial = c("EPCAM", "KRT8"))
)
# Supply qc_preview=preview_options to sc_run(...).
```

At most six explicit `{id, proposal}` candidates are accepted. Every candidate
uses the same typed validator as the main rule; an invalid candidate fails the
preview rather than being silently ignored. Each comparison records the exact
intersection with the primary retained set, cells added/removed, Jaccard
overlap, group changes and a cell-set fingerprint. Comparisons do not become
executable rules and never relax cutoffs automatically. To choose different
cutoffs, explicitly revise the primary proposal and review its new impact:

```r
current <- sc_run_inspect(project_dir)
replacement <- current$qc_preview$details$canonical_parameters$proposal
replacement$filters[[1]]$min <- 2L     # explicit analyst edit, not an optimizer
current <- sc_run_qc_review(project_dir, action = "revise",
  proposal_hash = current$pending$hash, preview_hash = current$qc_preview$hash,
  expected_revision = current$revision,
  reviewer = "analyst name", reason = "Record the scientific reason for changing this bound.",
  proposal = replacement)
current$qc_preview$details$retention
# Inspect the fresh preview, then approve using current's fresh hashes/revision.
```

`sc_run_qc_preview(project_dir)` reads the saved record. Passing explicit
`sensitivity` or `gene_panels` settings plus reviewer/reason updates comparison
settings at the current QC review node; this also appends history, regenerates
the preview and invalidates the previous review snapshot. `sc_run_qc_review`
supports `approve`, `reject`, `revise`, and `preview` under one project lock.
Approve/reject cannot carry silent parameter changes. A rejection stops the run;
it does not trigger analysis or a replacement model request. A later explicit
`sc_run_propose(..., reviewer=..., reason=...)` can supply a fresh typed plan.

Gene panels in this increment disclose exact feature availability only.
Missing genes are unavailable measurements, not zeros, and a missing feature
list yields unknown availability. **Expression and co-detection are not
assessed here**, and neither gene availability nor positive expression is a QC
gold standard. There is no quality score, identity truth, doublet detection,
ambient-RNA correction or automatic biological optimization.

## Saved review and optional browser

The durable preview binds the saved input, evidence, canonical rule, comparison
parameters, implementation and exact cell scope. Approval history records
these fingerprints, reviewer, reason and reviewed revision. Checkpoint/plot
checksums are verified when reading or resuming. Changed inputs or stale hashes
are rejected; repeat decisions cannot execute a stage twice. Use the same
package version for a saved run: implementation changes require an explicit
new project rather than silently reinterpreting an old approval. Approval and
computation are separate; after the decision the operator calls
`sc_run_resume()` in R or an appropriate scheduled job.

The optional workbench can point directly at the same `project_dir`:

```sh
python3 workbench/server.py --run-project /absolute/path/to/project --port 8772
# If the package is in a private library, also supply --r-library /path/to/R-library.
```

It binds to `127.0.0.1`; choose an unused port. On a remote machine, use your own
already authorized SSH connection to forward that port, then open the local
URL. No public binding, firewall change, login-node submission or browser launch
is required. QC actions go through the same R lock and fingerprint checks; the
browser does not execute R text. The command above enables review only; add
`--local-continue` for explicit approved local computation. The current `/review`
page also handles live annotation approval. Separately enabled model suggestions
have their own exact preview, consent and request action; Continue never makes
a provider request. See [unified startup](../workbench/RUN_REVIEW_QUICKSTART.md)
and [single-service review](SINGLE_SERVICE_REVIEW.md). The separate completed
annotation evidence-bundle mode does not approve a pending coordinator node.
Browser test results are reported separately from this usage contract.

## Scope of this increment and remaining validation

This section describes the historical QC increment. Current optional modules
and final-source checks are listed in the
[release checklist](RELEASE_CANDIDATE_CHECKLIST.md); historical example checks
are not a fresh release-candidate run.

This increment addresses the first decision in the larger diagnosis → analysis
→ annotation workflow: inspect QC consequences, edit with a reason, approve
the exact plan, and resume without requiring a website. It keeps the existing
analysis and annotation machinery. It does not claim that one set of thresholds
or a marker panel is correct for arbitrary species, tissues or technologies.

Before treating a later release as a general analysis coordinator, retain the
offline mechanism tests and validate additional datasets with different depth,
feature conventions, sample/capture structures and processed starting points.
Extend study-specific evidence and annotation review separately, preserving
unknowns, independent evidence and fresh approvals. Scheduler and broader HPC
behavior need actual testing in each intended environment; a loopback browser
test or a small VM run alone does not establish that compatibility. No API call,
publication or change to an existing completed project is required by this
example or contract.
