# scAgentKit

scAgentKit takes a single-cell count matrix through QC, PCA, clustering, marker
analysis and annotation with Seurat. The result is a new Seurat object, marker
tables, QC/UMAP figures and a saved record of the analysis settings and labels.
You can choose the settings yourself or ask a model for suggestions, inspect the
results, and continue from a saved project after closing R.

This guide walks through both routes. The examples use human PBMC data; replace
the study background and analysis choices for your experiment. The current
development version is **0.5.0.9000**.

[中文完整指南](docs/RESEARCHER_PROTOCOL_ZH.md) ·
[All documentation](docs/README.md) · [Changes](NEWS.md)

## Installation

Requires R >= 4.2 and Seurat >= 5. Install `remotes` if needed, then:

```r
remotes::install_github("ChanghaoKan/scAgentKit")
library(scAgentKit)
library(Seurat)
source(system.file("examples", "first-run.R", package = "scAgentKit"))
reviewer <- "your-name"
```

The bundled `first_run_*` helpers display saved evidence and pass the identifiers
needed to record your decisions. See the [installation guide](docs/RESEARCHER_PROTOCOL_ZH.md#2-安装与版本确认)
for separate libraries and reproducible environments.

## 1. Load counts and describe the study

Read a 10x filtered matrix directory containing `matrix.mtx[.gz]`, barcodes and
features/genes. For a multi-assay directory, select gene expression:

```r
counts <- Read10X(data.dir = "/path/to/filtered_feature_bc_matrix")
if (is.list(counts)) counts <- counts[["Gene Expression"]]
seu <- CreateSeuratObject(counts = counts, project = "pbmc-study")
dim(seu)
```

Alternatively, use your existing Seurat object or read it with
`seu <- readRDS("/path/to/raw-count-seurat.rds")`. Raw entry needs its RNA counts,
not a normalized matrix. Use the feature names in `rownames(seu)` for later
marker citations; Seurat may replace underscores when constructing the object.
The public [PBMC3k counts used by the Seurat tutorial](https://satijalab.org/seurat/articles/pbmc3k_tutorial)
are one suitable practice input; the small installation test is at the end.

Describe the material, research question and available experimental design:

```r
context <- list(
  species = "human", tissue = "Peripheral blood",
  research_goal = "Describe the major immune populations in this PBMC dataset.",
  notes = "Single public PBMC library; donor and capture metadata are unavailable."
)
```

For your own study, replace that description. If metadata columns exist, declare
their roles rather than treating condition or donor as a technical batch:

<details>
<summary>Optional sample, capture, donor and condition columns</summary>

```r
# Run only with columns that actually exist in seu[[]].
context$columns <- list(sample = "sample_id", capture = "capture_id",
                        donor = "donor_id", condition = "condition")
stopifnot(all(unlist(context$columns) %in% colnames(seu[[]])))
```

Attach metadata by cell ID before creating the project. A sample, a capture and
a donor can represent different experimental units; omit unknown roles.

</details>

Choose either the **manual route** below or the **model-assisted route** later.
Each uses a new project directory. Run the following small helpers once for
local continuation and editable annotation tables:

<details>
<summary>Run once: continuation and base R annotation-sheet helpers</summary>

```r
continue_local <- function(project_dir) {
  current <- sc_run_inspect(project_dir)
  sc_run_continue(project_dir, project_id = current$project_id,
    input_hash = current$input_hash, expected_revision = current$revision)
}

annotation_sheet <- function(view) {
  clusters <- view$evidence$clusters
  stopifnot(length(clusters) > 0L)
  saved <- if (is.null(view$annotation_review)) list() else
    lapply(view$annotation_review$details$annotations, `[[`, "proposal")
  saved_ids <- vapply(saved, `[[`, character(1), "clusterId")
  do.call(rbind, lapply(clusters, function(cl) {
    hit <- match(cl$clusterId, saved_ids)
    p <- if (is.na(hit)) NULL else saved[[hit]]
    data.frame(clusterId = cl$clusterId, cellCount = cl$cellCount,
      label = if (is.null(p)) "" else p$label,
      confidence = if (is.null(p)) "low" else p$confidence,
      rationale = if (is.null(p)) "" else p$rationale,
      markers = paste(unlist(p$markers, use.names = FALSE), collapse = ";"),
      stringsAsFactors = FALSE)
  }))
}

read_annotation_sheet <- function(path, view) {
  sheet <- read.delim(path, colClasses = "character", check.names = FALSE,
    na.strings = character(), comment.char = "", quote = "\"",
    fileEncoding = "UTF-8")
  required <- c("clusterId", "label", "confidence", "rationale", "markers")
  ids <- vapply(view$evidence$clusters, `[[`, character(1), "clusterId")
  stopifnot(!anyDuplicated(names(sheet)), all(required %in% names(sheet)),
    !anyDuplicated(sheet$clusterId), setequal(sheet$clusterId, ids))
  if (any(!nzchar(trimws(sheet$label))) || any(!nzchar(trimws(sheet$rationale))))
    stop("Fill label and rationale for every cluster; use Unknown for unresolved identities.")
  list(schema = "scagentkit.annotation.v1", annotations =
    lapply(seq_len(nrow(sheet)), function(i) {
      genes <- trimws(sheet$markers[i])
      genes <- if (nzchar(genes)) trimws(strsplit(genes, ";", fixed = TRUE)[[1]]) else character()
      list(clusterId = sheet$clusterId[i], label = sheet$label[i],
        confidence = sheet$confidence[i], rationale = sheet$rationale[i],
        markers = as.list(genes))
    }))
}
```

The TSV keeps cluster IDs as text, including leading zeroes. Marker symbols in
one field are separated by `;`. The project API checks them against that
cluster's saved evidence when you submit the proposal.

</details>

## 2. Manual route: set QC and analysis parameters

Create a project and inspect its input/QC summaries:

```r
project_dir <- file.path(getwd(), "pbmc-manual-study")
run <- sc_run(seu, project_dir, context = context, strategy = TRUE,
              provider = NULL, annotation_column = "cell_type_reviewed")
view <- first_run_inspect(project_dir)
view$evidence$input
view$evidence$quality
```

At this point `status` is `awaiting_configuration`: the counts and diagnostics
are saved, and the next step is to supply your plan. The following is a complete
PBMC starting example. Choose its QC cutoffs, feature count, PCs and resolution
after inspecting your data; these are not universal defaults.

<details>
<summary>Define the complete analysis plan</summary>

```r
plan <- list(
  schema = "scagentkit.strategy.v1",
  rationale = "PBMC starting plan, chosen after inspecting input QC distributions.",
  risks = list("Low-RNA populations may be affected by feature-count filtering."),
  inferences = list(),
  qc = list(schema = "scagentkit.qc.v1",
    rationale = "Inspect detected genes and mitochondrial counts before selecting cells.",
    risks = list(), filters = list(
      list(op = "range", metric = "nFeature", min = 200L, max = 2500L),
      list(op = "range", metric = "percent_mt", max = 5))),
  analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
                  nfeatures = 2000L, npcs = 30L, seed = 17L),
  pcs = list(method = "fixed", ndim = 10L),
  batch = list(method = "none", reason = "No technical correction variable is declared."),
  clustering = list(resolution = 0.5, diagnostic_resolutions = c(0.3, 0.5, 0.8)),
  umap = list(run = TRUE, n_neighbors = 30L)
)
```

Counts use literal gene symbols. If mitochondrial genes are not identified,
inspect the unavailable metric and revise the plan rather than using that filter.
Small datasets also need feature/PC settings appropriate to their dimensions.

</details>

Submit the plan, then read its full details and expected retained-cell scope:

```r
sc_run_strategy_revise(project_dir, plan,
  project_id = view$project_id, input_hash = view$input_hash,
  expected_revision = view$revision, reviewer = reviewer,
  reason = "Submit the QC and analysis choices for this study.")
view <- first_run_inspect(project_dir)
print(view$strategy_review$details)
```

If the plan needs changes, edit `plan` and repeat that submission using a fresh
inspection. When satisfied, record your decision and run QC, normalization,
variable-feature selection, PCA, neighbors, clustering, UMAP and markers:

```r
first_run_decide(project_dir, "approve", snapshot = view, reviewer = reviewer,
  reason = "Checked the analysis plan and its expected cell retention.")
run <- continue_local(project_dir)
view <- first_run_inspect(project_dir)
view$computed_diagnostics$stage_counts
view$computed_diagnostics$pc_candidates
view$computed_diagnostics$cluster_candidates
```

The next stop is `stage = "annotation_propose"`, `status = "awaiting_configuration"`.
The analysis is saved; now examine the actual clusters and name them.

## 3. Read markers and submit annotations

Each evidence cluster has its actual `clusterId`, `cellCount` and saved marker
statistics. Inspect them before assigning labels:

```r
clusters <- view$evidence$clusters
data.frame(clusterId = vapply(clusters, `[[`, character(1), "clusterId"),
           cells = vapply(clusters, `[[`, numeric(1), "cellCount"))
marker_rows <- unlist(lapply(clusters, `[[`, "markers"), recursive = FALSE)
markers <- if (length(marker_rows))
  do.call(rbind, lapply(marker_rows, as.data.frame, stringsAsFactors = FALSE)) else
  data.frame(clusterId = character(), gene = character())
head(markers, 20)
write.csv(markers, file.path(project_dir, "cluster-markers.csv"), row.names = FALSE)
```

These are saved top-marker results from `Seurat::FindAllMarkers`:
`avgLog2FC`, `pct1`, `pct2` and `pAdj` describe differential expression and
within/outside-cluster detection. Check several coherent markers and the study
background. Cluster numbers are dataset-specific; an omitted marker is not
proof that a gene is unexpressed. To see the saved UMAP before finalization,
optionally use `sc_run_open()` as described below.

Create a label worksheet, then edit it in a text editor or spreadsheet:

```r
sheet_path <- file.path(project_dir, "annotations.tsv")
write.table(annotation_sheet(view), sheet_path, sep = "\t", quote = TRUE,
            qmethod = "double", row.names = FALSE, fileEncoding = "UTF-8")
# Edit annotations.tsv before running the next block.
```

Fill `label`, `confidence` (`low`, `medium` or `high`), `rationale` and `markers`
for every cluster. Use exact marker symbols from that cluster, separated by `;`.
Keep the actual cluster IDs. If identity remains unresolved, enter `Unknown`,
a reason, and leave markers empty. The worksheet starts blank rather than
assigning cell types from cluster numbers.

```r
view <- sc_run_inspect(project_dir)
proposal <- read_annotation_sheet(sheet_path, view)
sc_run_propose(project_dir, proposal, reviewer = reviewer,
  reason = "Assign labels from the inspected cluster marker evidence.")
view <- first_run_inspect(project_dir)
print(view$annotation_review$details)
```

### Edit an annotation

Before confirming, you can revise the saved proposal. This also works for a
model-generated proposal: export the current labels, edit the TSV, and submit
the corrected version:

<details>
<summary>Optional annotation revision</summary>

```r
sheet_path <- file.path(project_dir, "annotations.tsv")
write.table(annotation_sheet(view), sheet_path, sep = "\t", quote = TRUE,
            qmethod = "double", row.names = FALSE, fileEncoding = "UTF-8")
# Edit the file, then inspect again and submit the revision:
view <- first_run_inspect(project_dir)
replacement <- read_annotation_sheet(sheet_path, view)
first_run_decide(project_dir, "revise", snapshot = view, proposal = replacement,
  reviewer = reviewer, reason = "Correct labels and citations after marker review.")
view <- first_run_inspect(project_dir)
print(view$annotation_review$details)
```

</details>

Confirm the final labels and write the annotated object:

```r
first_run_decide(project_dir, "approve", snapshot = view, reviewer = reviewer,
  reason = "Checked the complete annotation table and its supporting markers.")
done <- continue_local(project_dir)
stopifnot(identical(done$status, "complete"))
```

Continue with **Results and reopening** below. No model is needed for this route.

## Model-assisted route: propose, inspect and refine

Start here instead of the manual route, using the same input, context and helper
setup above. Models can propose the QC/analysis plan and annotation; you can
revise either before running it.

Configure `DEEPSEEK_API_KEY` or `XAI_API_KEY` in the R process through your usual
secret mechanism. The helper checks its presence without printing the key.
Set these non-secret environment values using your provider's current model ID
and verified USD-per-million-token rates. Choose a positive request reservation
and a project budget for both requests; these are your limits, not price quotes:

| Variable | Meaning |
| --- | --- |
| `SC_MODEL_ID` | Model available to your account |
| `SC_INPUT_USD_PER_MILLION` | Input token rate |
| `SC_OUTPUT_USD_PER_MILLION` | Output token rate |
| `SC_CACHED_INPUT_USD_PER_MILLION` | Cached-input token rate |
| `SC_REQUEST_RESERVATION_USD` | Amount to reserve per request |
| `SC_PROJECT_BUDGET_USD` | Your project spending ceiling |

```r
read_usd <- function(name) {
  value <- suppressWarnings(as.numeric(Sys.getenv(name)))
  stopifnot(length(value) == 1L, is.finite(value), value >= 0)
  value
}
provider <- first_run_provider("deepseek",  # or "grok" with XAI_API_KEY
  model = Sys.getenv("SC_MODEL_ID"),
  pricing = list(input_per_million = read_usd("SC_INPUT_USD_PER_MILLION"),
    output_per_million = read_usd("SC_OUTPUT_USD_PER_MILLION"),
    cached_input_per_million = read_usd("SC_CACHED_INPUT_USD_PER_MILLION")),
  reservation_usd = read_usd("SC_REQUEST_RESERVATION_USD"))
project_dir <- file.path(getwd(), "pbmc-model-study")
run <- sc_run(seu, project_dir, context = context, strategy = TRUE,
  provider = provider, budget = read_usd("SC_PROJECT_BUDGET_USD"),
  review = list(allow_external = TRUE), annotation_column = "cell_type_reviewed")
```

**First request: QC and analysis strategy.** Inspect the exact outgoing aggregate
payload, provider and settings. Approve that disclosure only if appropriate;
the following resume makes the request:

```r
view <- first_run_inspect(project_dir)
print(view$pending$proposal)
```

The saved node is `pending$kind = "external_transfer"`. Read the payload, then
record your disclosure decision and resume:

```r
first_run_decide(project_dir, "approve", snapshot = view, reviewer = reviewer,
  reason = "Allow this inspected QC/context payload to the configured provider.")
run <- sc_run_resume(project_dir)
view <- first_run_inspect(project_dir)
print(view$strategy_review$details)
```

Now check the proposed QC scope, PCs, clustering and rationale. To change it,
set `plan <- view$strategy_review$details$canonical_proposal`, edit its fields,
and use the strategy submission block in section 2. Once satisfied:

```r
first_run_decide(project_dir, "approve", snapshot = view, reviewer = reviewer,
  reason = "Checked the proposed analysis settings and cell retention.")
run <- continue_local(project_dir)
view <- first_run_inspect(project_dir)
view$computed_diagnostics$stage_counts
view$evidence$clusters
```

Local computation stops at annotation configuration. **Second request:
annotation from the actual markers and study context.** Resume once to prepare
its separate outgoing preview; that call stops before transmission:

```r
run <- sc_run_resume(project_dir)
view <- first_run_inspect(project_dir)
print(view$pending$proposal)
```

The saved node is `pending$kind = "external_transfer"`. Read the payload, then
record your disclosure decision and resume:

```r
first_run_decide(project_dir, "approve", snapshot = view, reviewer = reviewer,
  reason = "Allow this inspected marker/context payload to the configured provider.")
run <- sc_run_resume(project_dir)
view <- first_run_inspect(project_dir)
print(view$annotation_review$details)
```

Inspect the suggested labels, cited markers and rationale. Keep them or use
**Edit an annotation** above to export and correct the complete table. Then confirm the
saved annotation and finish:

```r
first_run_decide(project_dir, "approve", snapshot = view, reviewer = reviewer,
  reason = "Checked the annotation labels and citations, including any corrections.")
done <- continue_local(project_dir)
stopifnot(identical(done$status, "complete"))
```

These are two separate requests and two analysis decisions, not an approval
loop. A failed request needs inspection before any retry; see
[model review](docs/UNIFIED_MODEL_REVIEW.md) for cache and usage handling.

## Results and reopening

Both routes end with the same outputs:

```r
view <- sc_run_inspect(project_dir)
view$output
final <- readRDS(view$output$seurat)
table(final$cell_type_reviewed)
DimPlot(final, reduction = "umap", group.by = "cell_type_reviewed", label = TRUE)
markers_all <- read.csv(file.path(project_dir, "output", "markers.csv"))
genes <- head(unique(markers_all$gene), 2)
if (length(genes)) FeaturePlot(final, features = genes)
list.files(file.path(project_dir, "output"))
```

The output directory includes `seurat.rds`, `markers.csv`, `metadata.csv`,
`parameters.json`, `strategy_summary.json`, `report.md` and, for this raw-count
UMAP workflow, `qc.png` and `umap.png`. The new annotation column leaves prior
metadata and labels in place. Inspect marker expression in the final object
with Seurat's `FeaturePlot()` or `DotPlot()` using genes present in your data.

After closing R, reload the package and inspect the same durable directory:

```r
library(scAgentKit)
source(system.file("examples", "first-run.R", package = "scAgentKit"))
project_dir <- "/absolute/path/to/your/saved-project"
view <- first_run_inspect(project_dir)
view$status
```

At a saved review step, inspect the relevant `strategy_review$details` or
`annotation_review$details`, decide, then continue. For local computation in a
fresh session, the full call is:

```r
current <- sc_run_inspect(project_dir)
run <- sc_run_continue(project_dir, project_id = current$project_id,
  input_hash = current$input_hash, expected_revision = current$revision)
```

For an explicitly approved provider request, restore the key environment and use
`sc_run_resume(project_dir)`. Completed projects resume without rerunning analysis.
Keep the original checkout/R library for a saved project; inspect a failure before
requesting a retry. Details are in the [recovery guide](docs/RESEARCHER_PROTOCOL_ZH.md#11-输出恢复与可复现记录).

With Python >= 3.9 and a source checkout, you can view saved QC, UMAP, markers
and history in a browser, including the analysis checkpoint before annotation:

```r
sc_run_open(project_dir, checkout = "/path/to/scAgentKit")
# Later sessions remember the checkout:
sc_run_open(project_dir)
```

The [workbench guide](workbench/README.md) explains browser-based decisions,
local computation and remote access. The service binds to loopback; shared-host
access needs appropriate isolation.

## Other starting points and methods

- **Processed Seurat:** use `start_stage = "processed"` and a meaningful
  `processed_reason` to reuse an existing foundation. Set `cluster_column` if
  its clusters use a column other than `seurat_clusters`. See the
  [processed-entry example](docs/RESEARCHER_PROTOCOL_ZH.md#52-已有-processed-seurat不重做基础计算).
- **Subclusters:** `sc_run_subcluster()` creates an independent analysis from
  selected parent clusters; applying labels writes a new parent object.
  See [subcluster analysis](docs/SUBCLUSTER_REVIEW.md).
- **MAD QC, doublets, cell cycle and Harmony:** optional choices with their own
  inputs and applicability. See the [method guides](docs/README.md#analysis-and-review).
- **Local marker references:** add a permitted local reference for annotation
  evidence. See [CellMarker/reference matching](docs/CM2_EVIDENCE_REVIEW.md).

Analysis choices and biological interpretation remain study-specific. Models
receive the approved aggregate payload, which may include sensitive context;
review it before disclosure. The [complete guide](docs/RESEARCHER_PROTOCOL_ZH.md)
covers data handling and the additional methods.

## Installation test without a model

For a quick software check, the bundled 80-cell PBMC example uses an offline mock
and deliberately retains `Unknown` labels. It tests the workflow, not annotation
accuracy. Run these steps separately, inspecting each displayed proposal:

<details>
<summary>Small offline PBMC test</summary>

```r
source(system.file("examples", "researcher-pbmc.R", package = "scAgentKit"))
project_dir <- file.path(getwd(), "pbmc-installation-test")
mock <- make_researcher_pbmc_mock()
run <- researcher_pbmc_start(project_dir, mock)
view <- researcher_pbmc_inspect(project_dir)
print(view$strategy_review$details)
researcher_pbmc_decide(project_dir, view, reviewer = reviewer,
  reason = "Checked the small installation-test plan.")
run <- researcher_pbmc_resume(project_dir, mock)
view <- researcher_pbmc_inspect(project_dir)
print(view$annotation_review$details)
researcher_pbmc_decide(project_dir, view, reviewer = reviewer,
  reason = "Retain unresolved installation-test labels as Unknown.")
done <- researcher_pbmc_resume(project_dir, mock)
stopifnot(identical(done$status, "complete"))
```

</details>
