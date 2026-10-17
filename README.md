# scAgentKit

Analyze single-cell counts with Seurat, review the complete strategy and marker
supported annotations, and resume the same saved project after closing R.
Four R functions handle the routine workflow: `sc_analyze()`, `sc_open()`,
`sc_review()` and `sc_result()`.

This experimental development version is **0.5.0.9000**. Analysis settings and
labels remain analyst decisions. A successful run does not validate biological
identity. No provider, external-transfer permission or spending is enabled by default.

## Installation

Requires R >= 4.2, Seurat >= 5 and the Imports in [DESCRIPTION](DESCRIPTION).
The four-function interface is currently a **local development change**; install
this checkout into a private library before using it:

```r
private_lib <- file.path(path.expand("~/R"), "scagentkit-preview")
dir.create(private_lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(private_lib, .libPaths()))
# From the verified source checkout, with its dependencies already installed:
install.packages(".", repos = NULL, type = "source", lib = private_lib)
library(scAgentKit)
```

Use a pinned checkout and library to resume existing projects. See the
[installation and dependency guide](docs/RESEARCHER_PROTOCOL_ZH.md#2-安装与版本确认).

## First analysis

Load a named genes × cells raw count matrix or a Seurat object containing genuine
counts. For the public [PBMC3k tutorial data](https://satijalab.org/seurat/articles/pbmc3k_tutorial),
load the already-downloaded 10x directory:

```r
counts <- Seurat::Read10X("/path/to/filtered_gene_bc_matrices/hg19")
seu <- Seurat::CreateSeuratObject(counts)
x <- sc_analyze(seu, "pbmc-study", context = list(
  species = "human", tissue = "Peripheral blood",
  research_goal = "Describe the major immune populations in this public library.",
  notes = "Donor and capture metadata are unavailable."),
  plan = list(
    rationale = "PBMC starting plan; review the measured QC distributions.",
    qc = list(nFeature = c(200, 2500), percent_mt = c(NA, 5)),
    pcs = 10, resolution = .5))
shown <- sc_review(x)
```

The plan is an editable draft. The PBMC thresholds above are tutorial starting
choices, not recommendations for your experiment. With no supplied plan or
provider, the draft retains count-positive cells and proposes standard analysis
settings; review and revise them before approving. Declare study facts yourself;
Ca/Ctrl is not inferred as batch, and capture is not inferred as donor.

Read the displayed QC impact, normalization/PCA/PC/batch/clustering choices and
limitations. `shown$plan` contains the complete canonical strategy for inspection.
Change only the choices you need; omitted choices preserve the displayed plan:

```r
# Optional: save an edited draft, then inspect its freshly displayed impact.
shown <- sc_review(shown, "revise", plan = list(pcs = 12, resolution = .6),
  reviewer = "your-name", reason = "Explain the evidence for these choices.")
# After reviewing the entire current draft:
next_step <- sc_review(shown, "approve", reviewer = "your-name",
  reason = "Explain why this complete strategy is suitable.", continue = TRUE)
```

This explicit approval runs local computation and stops before annotation.
Approval without `continue = TRUE` saves the decision; use
`next_step <- sc_review(next_step, "continue")` to run it later. Continue never
calls a model. `sc_review(shown, "reject", reviewer=..., reason=...)` stops the
proposal; revise the rejected snapshot to create a new draft.

## Review labels and read results

`next_step` displays the actual cluster markers and an annotation table with
blank labels. Inspect the provisional Seurat object if needed:

```r
analysis <- sc_result(next_step, stage = "analysis")
Seurat::FeaturePlot(analysis, features = c("MS4A1", "CD3D"))
labels <- next_step$annotations
View(labels)
```

Fill each literal `clusterId` exactly once, with `label`, `confidence`
(`low`, `medium` or `high`), a specific `rationale`, and `markers` containing
semicolon-separated gene names actually supplied for that cluster. Use
`Unknown` with a reason when the evidence is unresolved; blanks are never
converted to a biological label. You can edit the data frame in R or round-trip
it through a quoted UTF-8 TSV:

```r
write.table(labels, "annotations.tsv", sep = "\t", quote = TRUE,
  qmethod = "double", row.names = FALSE)
# Edit the file and check the complete marker evidence before submitting:
proposal <- sc_review(next_step, "revise", annotations = "annotations.tsv",
  reviewer = "your-name", reason = "Explain the evidence supporting these drafts.")
done <- sc_review(proposal, "approve", reviewer = "your-name",
  reason = "Explain the review of all provisional annotations.", continue = TRUE)
result <- sc_result(done)
```

Revise stages a draft for fresh review. A model suggestion or saved marker hit
does not approve a label. The final getter requires a completed run and returns
the verified Seurat object; source counts and existing metadata are preserved.
`done$view$output` lists saved artifacts. Finalization is recorded as `EXECUTED`,
not automatic scientific acceptance.

## Reopen and keep confirmations current

```r
x <- sc_open("pbmc-study")       # read only; no analysis or model request
shown <- sc_review(x)             # display a fresh bound snapshot
result <- sc_result(x)            # available after completion
# A displayed snapshot may also survive an R restart:
saveRDS(shown, "reviewed-snapshot.rds")
```

Confirm the object returned by `sc_review()`. If a colleague, another session or
your own revision changes the project, that old snapshot is rejected, including
a duplicate approval. Reopen and review the new version. The interface never
silently transfers an old confirmation to new evidence. Opening, printing and
reading results do not resume a run. Interrupted/failed work uses the existing
[explicit recovery protocol](docs/RESEARCHER_PROTOCOL_ZH.md#11-输出恢复与可复现记录).

## Optional model proposals

Configure a provider, verified model/prices, budget and disclosure policy when
starting the project, as in the preserved [complete model walkthrough](docs/COMPLETE_ANALYSIS_WALKTHROUGH.md).
Pass that same configuration to `sc_analyze(..., provider=provider, budget=budget,
review=list(allow_external=TRUE))` to request a strategy instead of an initial
manual draft. Keys remain in the analysis process environment.

```r
x <- sc_analyze(seu, "pbmc-model-study", context = x$view$context,
  provider = provider, chat_fn = chat_fn, budget = budget,
  review = list(allow_external = TRUE))
transfer <- sc_review(x)  # inspect the exact saved aggregate payload first
consent <- sc_review(transfer, "approve", reviewer = "your-name",
  reason = "Explain consent for this exact payload and provider.")
strategy <- sc_review(consent, "request", chat_fn = chat_fn)
# Inspect strategy, then explicitly approve science and continue locally.
```

Transfer consent and scientific approval remain separate. After local analysis,
`sc_review(next_step, "request", chat_fn=chat_fn)` prepares the next payload;
review and approve that exact payload before a separate request dispatches it.
Reattach in-memory callbacks after restarting R. Requests never automatically
retry failed or unknown paid attempts. Default policy still blocks external
transfer; a wrapper cannot enable it on an existing manual project.

## What became shorter

| Operation | Existing advanced interface | User interface |
| --- | --- | --- |
| Start a reviewed plan | Build strategy/QC schemas and nested settings, then `sc_run()` | `sc_analyze(..., plan=list(qc=..., pcs=10))` |
| Review a proposal | Inspect, copy project/input/proposal/review hashes and revision into `sc_run_review()` | `shown <- sc_review(x)`; `sc_review(shown, "approve", ...)` |
| Submit labels | Build the annotation schema and one record per cluster | Edit `next_step$annotations`; `sc_review(..., "revise", annotations=labels)` |
| Compute after approval | Inspect/copy bindings into `sc_run_continue()` | Explicit `continue=TRUE` or `sc_review(ready, "continue")` |
| Read output | Locate and validate the correct saved artifact | `sc_result(x)` or explicit `stage="analysis"` |

The [before/after runnable examples](inst/examples/simple-analysis.R) run on the
public `pbmc_small` fixture, without a provider, and explicitly retain unresolved
labels as software controls. The [complete previous walkthrough](docs/COMPLETE_ANALYSIS_WALKTHROUGH.md)
is preserved for direct kernel use, typed proposals, model setup and detailed
TSV editing. Function reference: `?sc_analyze`.

For processed Seurat reuse, optional diagnostics, batch methods, child projects,
browser/server review and scientific limits, see the
[full Chinese protocol](docs/RESEARCHER_PROTOCOL_ZH.md),
[documentation index](docs/README.md) and [workbench guide](workbench/README.md).
The advanced APIs remain available. No shared-server authentication changes or
external services are required for this local workflow.
