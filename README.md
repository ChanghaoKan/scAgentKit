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

Run these examples one block at a time. Stop at each displayed review, read the
evidence, and decide whether to revise, reject or approve. Replace the example
reviewer and reasons with your actual decision. Do not run all approval blocks
as an automatic script.

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

This independent route creates a new project and does not use the manual
project above. Run each block separately and read its output before moving on.
There are two exact-payload disclosure decisions and two scientific decisions;
none should be approved automatically. Default policy still blocks external
transfer. Enable it only for a new project whose disclosure you have reviewed.

<details>
<summary>Configure independent input, study facts, provider and budget</summary>

Configure `DEEPSEEK_API_KEY` in the analysis R process using your usual secret
mechanism (`XAI_API_KEY` for Grok). Set the six non-secret environment values
below using your verified model ID, current USD-per-million-token rates and
chosen spending limits. The helper reads the key's presence but returns only
its environment variable name. This block makes no model request.

```r
library(scAgentKit)
source(system.file("examples", "first-run.R", package = "scAgentKit"))

model_counts <- Seurat::Read10X("/path/to/filtered_gene_bc_matrices/hg19")
model_input <- Seurat::CreateSeuratObject(model_counts)
model_context <- list(
  species = "human", tissue = "Peripheral blood",
  research_goal = "Describe the major immune populations in this public library.",
  notes = "Donor and capture metadata are unavailable."
)
read_usd <- function(name) {
  value <- suppressWarnings(as.numeric(Sys.getenv(name)))
  stopifnot(length(value) == 1L, is.finite(value), value >= 0)
  value
}
model_provider <- first_run_provider("deepseek", # or "grok" with XAI_API_KEY
  model = Sys.getenv("SC_MODEL_ID"),
  pricing = list(
    input_per_million = read_usd("SC_INPUT_USD_PER_MILLION"),
    output_per_million = read_usd("SC_OUTPUT_USD_PER_MILLION"),
    cached_input_per_million = read_usd("SC_CACHED_INPUT_USD_PER_MILLION")
  ),
  reservation_usd = read_usd("SC_REQUEST_RESERVATION_USD")
)
model_budget <- read_usd("SC_PROJECT_BUDGET_USD")
stopifnot(model_provider$reservation_usd > 0, model_budget > 0)
model_chat_fn <- NULL # use the configured built-in provider
model_project <- file.path(getwd(), "pbmc-model-study") # must be new
model_reviewer <- "your-name"
```

An explicit offline callback can instead be supplied through `model_chat_fn`
with its matching provider configuration. Validation of this interface used
offline callbacks, not a live DeepSeek/Grok request. Model responses can be
invalid or require parameter edits; review the returned state before proceeding.

</details>

Start with no manual plan to ask the configured provider for a strategy. This
first block saves and displays the exact outgoing QC/context aggregate payload;
it stops before sending it:

```r
model_run <- sc_analyze(model_input, model_project, context = model_context,
  provider = model_provider, chat_fn = model_chat_fn, budget = model_budget,
  review = list(allow_external = TRUE))
model_transfer <- sc_review(model_run)
```

Read that payload, provider, model and budget. If you consent to this exact
disclosure, record the first transfer approval and explicitly request the
response. Stop to read the returned complete strategy and projected QC impact:

```r
model_consent <- sc_review(model_transfer, "approve", reviewer = model_reviewer,
  reason = "Explain consent for this exact QC/context payload and provider.")
model_strategy <- sc_review(model_consent, "request", chat_fn = model_chat_fn)
```

Revise or reject an unsuitable plan. Once you have reviewed the entire current
strategy, this separate scientific approval runs only local computation and
stops at annotation configuration:

```r
model_next <- sc_review(model_strategy, "approve", reviewer = model_reviewer,
  reason = "Explain why this complete strategy and QC scope suit the study.",
  continue = TRUE)
```

Prepare the second outgoing payload from the actual saved markers and study
context. This block displays that new preview without transmitting it:

```r
model_transfer <- sc_review(model_next, "request", chat_fn = model_chat_fn)
```

Read the second payload. If you consent, record its own transfer approval, then
explicitly request the annotation response. Stop to inspect every proposed
label, confidence, rationale and supplied marker citation:

```r
model_consent <- sc_review(model_transfer, "approve", reviewer = model_reviewer,
  reason = "Explain consent for this exact marker/context payload and provider.")
model_annotation <- sc_review(model_consent, "request", chat_fn = model_chat_fn)
```

If needed, edit `model_annotation$annotations` and submit it with
`sc_review(model_annotation, "revise", annotations=labels, reviewer=..., reason=...)`;
use the newly returned snapshot for the next decision. A model suggestion does
not itself approve a label. After reviewing the complete current annotation,
the second scientific approval finishes the local work, and the getter returns
the verified final Seurat object:

```r
model_done <- sc_review(model_annotation, "approve", reviewer = model_reviewer,
  reason = "Explain the review of every provisional annotation and citation.",
  continue = TRUE)
model_result <- sc_result(model_done)
model_done$view$output
```

Transfer consent and scientific approval remain separate. Reattach in-memory
callbacks after restarting R. Requests never automatically retry failed or
unknown paid attempts. An existing manual project's immutable configuration
cannot be changed by this wrapper. See the [complete model walkthrough](docs/COMPLETE_ANALYSIS_WALKTHROUGH.md)
for provider setup, failure handling and advanced edits.

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

Counting workflow calls only (excluding installation, data loading, standalone print/plot calls,
label/file editing, provider setup and optional revisions), the runnable manual
before/after example goes from 11 calls to 6. The previous complete README's
manual route used 14 calls plus two label-conversion helper calls; the new route
uses 6. The external model route goes from 17 to 10 calls. Both routes retain
two scientific approvals; the external route also retains two transfer
approvals. Scientific judgments and the four per-cluster annotation fields have
not been removed. The new blank confidence field must also be filled; the old
worksheet helper defaulted it to low.
