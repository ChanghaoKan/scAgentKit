# scAgentKit

scAgentKit is an R package for single-cell RNA-seq analysis with Seurat. It
organizes quality control, dimensionality reduction, clustering, marker analysis
and cell-type annotation into a saved project with explicit strategy and
annotation review. Analyses can be continued across R sessions, with optional
model proposals and browser-based review.

The standard workflow accepts a named genes × cells raw-count matrix, a Seurat
object containing RNA counts, or an RDS file containing either. It produces a
new Seurat object, cluster annotations, marker tables, figures and an analysis
record. Processed-object reuse, batch methods and child analyses are described
in the [documentation](docs/README.md).

## Installation

Requires R ≥ 4.2 and Seurat ≥ 5. Browser use also requires Python ≥ 3.9 and a
matching source checkout: browser assets are not included in the installed R
package. Download and unpack this repository, or clone it once:

```sh
git clone https://github.com/ChanghaoKan/scAgentKit.git ~/src/scAgentKit
```

Install the package from that same directory into a separate R library:

```r
lib <- path.expand("~/R/scagentkit")
checkout <- normalizePath("~/src/scAgentKit", mustWork = TRUE)
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib, .libPaths()))
if (!requireNamespace("remotes", quietly = TRUE))
  install.packages("remotes", repos = "https://cloud.r-project.org")
remotes::install_local(checkout, lib = lib,
  dependencies = c("Depends", "Imports"), upgrade = "never", build = FALSE)
library(scAgentKit)
```

This installs the required dependencies, including `agentomicsCore` from its
declared GitHub source. Optional methods have additional requirements. For
version pinning, managed environments and platform support, see
[installation](docs/RESEARCHER_PROTOCOL_ZH.md#2-安装与版本确认) and
[runtime support](docs/LINUX_RUNTIME_SUPPORT.md).

## Start from an RDS file

In R, start a new project from a local RDS containing raw counts or a Seurat
object. Declare the study facts; they are not inferred from the input:

```r
sc_start("a.rds", "analysis",
  context = list(species = "human", tissue = "Peripheral blood",
    research_goal = "Characterize the major immune populations."),
  checkout = checkout)
```

The function opens the local browser and returns control to R. Inspect and edit
the strategy, then approve and continue. At annotation, prepare the blank table,
enter interpretations and supporting markers, save the complete proposal, and
review it before approving and continuing to the result. An explicit bulk action
can retain unfilled populations as `Unknown` with a shared reason; unresolved
population and cell counts remain visible.

The project remembers the checkout. Repeating the call reuses its matching live
service or restarts a stopped service, preserving the saved analysis:

```r
sc_start("a.rds", "analysis")
```

The original RDS must retain the same path and content for this entry. Use
`sc_run_open("analysis")` for a read-only saved-result viewer. See the
[workbench guide](workbench/README.md#start-from-r) for environment setup,
processed-object reuse and server access. No R/terminal switching is required
between strategy review, annotation and results.

## First analysis

The example uses the public 10x Genomics PBMC3k counts introduced in the
[Seurat tutorial](https://satijalab.org/seurat/articles/pbmc3k_tutorial).
Work through each review step in sequence, recording your reviewer identity
and the rationale for each decision.

### 1. Load the data

```r
data_dir <- file.path(getwd(), "pbmc3k-data")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
archive <- file.path(data_dir, "pbmc3k_filtered_gene_bc_matrices.tar.gz")
download.file(
  "https://cf.10xgenomics.com/samples/cell/pbmc3k/pbmc3k_filtered_gene_bc_matrices.tar.gz",
  archive, mode = "wb")
untar(archive, exdir = data_dir)
counts <- Seurat::Read10X(file.path(data_dir, "filtered_gene_bc_matrices", "hg19"))
seu <- Seurat::CreateSeuratObject(counts = counts, project = "PBMC3k")
project_dir <- file.path(getwd(), "pbmc3k-analysis")
```

For your own study, replace the input and describe its species, tissue,
research question and available experimental design. Use a new project
directory for a new analysis.

### 2. Review the analysis strategy

`sc_analyze()` prepares a strategy and its projected QC impact. Here, the
feature-count and mitochondrial thresholds follow the PBMC tutorial's starting
choices; select settings appropriate to the observed distributions and study.

```r
project <- sc_analyze(seu, project_dir,
  context = list(
    species = "human", tissue = "Peripheral blood",
    research_goal = "Characterize the major immune populations in this PBMC library.",
    notes = "Single public library; donor and capture metadata are unavailable."),
  plan = list(
    rationale = "PBMC starting strategy for review against measured QC distributions.",
    qc = list(nFeature = c(200, 2500), percent_mt = c(NA, 5)),
    pcs = 10, resolution = 0.5))
strategy <- sc_review(project)
```

Review cell retention, normalization, PC selection, batch handling and
clustering in the displayed plan. To change a choice, save a revision with
`sc_review(strategy, "revise", plan = list(...), reviewer = ..., reason = ...)`
and inspect the returned plan. For example, `plan = list(pcs = 12)` changes PC
selection while preserving the other displayed settings.

Approve the reviewed strategy to run the local analysis through clustering and
marker detection:

```r
annotation <- sc_review(strategy, "approve", reviewer = "researcher",
  reason = "Reviewed QC retention and the analysis strategy for this PBMC library.",
  continue = TRUE)
```

### 3. Review and submit cluster annotations

The returned review contains the cluster markers and an annotation worksheet.
Inspect expression and the embedding alongside the supplied marker evidence:

```r
analysis <- sc_result(annotation, stage = "analysis")
Seurat::DimPlot(analysis, reduction = "umap", label = TRUE)
Seurat::FeaturePlot(analysis, features = c("CD3D", "MS4A1", "LYZ", "NKG7"))
annotations <- utils::edit(annotation$annotations)
```

In the R data editor, retain each `clusterId` and complete the remaining fields
for every cluster:

| Field | Content |
| --- | --- |
| `label` | The reviewed cell type or population description |
| `confidence` | `low`, `medium` or `high`, as a qualitative assessment |
| `rationale` | Evidence supporting the assignment and any unresolved alternatives |
| `markers` | Semicolon-separated gene names from that cluster's supplied marker evidence |

For example, concordant CD79A and MS4A1 evidence can support a B-cell assignment;
its worksheet entry would cite `CD79A;MS4A1` and explain that interpretation.
Use `Unknown` with a rationale for unresolved populations. Cluster IDs and
annotations depend on the data and analysis settings. For file-based editing,
see the [detailed walkthrough](docs/COMPLETE_ANALYSIS_WALKTHROUGH.md#3-read-markers-and-submit-annotations).
The [annotation guide](docs/ANNOTATION_REVIEW.md) describes evidence and review decisions.

Save the completed worksheet, inspect the full annotation proposal returned by
`sc_review()`, and approve it to apply the labels:

```r
proposal <- sc_review(annotation, "revise", annotations = annotations,
  reviewer = "researcher",
  reason = "Prepared cluster annotations from the supplied markers and expression plots.")
completed <- sc_review(proposal, "approve", reviewer = "researcher",
  reason = "Reviewed the complete annotation proposal and supporting evidence.",
  continue = TRUE)
```

### 4. Retrieve results and reopen the project

```r
result <- sc_result(completed)
Seurat::DimPlot(result, reduction = "umap", group.by = "sc_annotation", label = TRUE)
table(result$sc_annotation)
completed$view$output
```

`result` is the final Seurat object with the reviewed annotations. The project
also retains marker tables, figures and the analysis record. `sc_result(...,
stage = "analysis")` retrieves the earlier analysis object when annotation is
still in progress.

In a later R session, load the same package environment and reopen the project:

```r
library(scAgentKit)
project <- sc_open("pbmc3k-analysis")
review <- sc_review(project)
result <- sc_result(project)
```

For an unfinished project, `sc_review()` displays the current stage so you can
continue its review and execution. Opening a project does not resume work.
See [recovery and saved results](docs/RESEARCHER_PROTOCOL_ZH.md#11-输出恢复与可复现记录)
for interrupted runs and environment changes.

## Optional model assistance

A configured provider can propose analysis strategies and cluster annotations.
The [model-assisted R workflow](docs/COMPLETE_ANALYSIS_WALKTHROUGH.md#model-assisted-workflow-with-the-r-interface)
covers provider setup, budget configuration and the complete request sequence
using the same R interface. Review the outgoing evidence before authorizing a
request, then review the returned scientific proposal before local execution.
Model use is optional; the workflow above does not require a provider.

For model requests in the optional browser, see [model review](docs/UNIFIED_MODEL_REVIEW.md).

## Browser review

The [local workbench](workbench/README.md) displays saved embeddings, labels and
proportions, marker evidence and questions requiring review. It also provides
annotation editing and supported review controls. It requires Python ≥ 3.9 and
a source checkout in addition to the R package; follow the workbench guide for
local and remote setup.

## Documentation

| Topic | Reference |
| --- | --- |
| Complete operating guide, including installation and recovery | [Researcher protocol — 中文](docs/RESEARCHER_PROTOCOL_ZH.md) |
| Analysis settings, QC and supported methods | [Strategy guide](docs/ANALYSIS_STRATEGY_SUPPORT.md) |
| Annotation evidence and decisions | [Annotation review](docs/ANNOTATION_REVIEW.md) |
| Model configuration and requests | [Model-assisted workflow](docs/COMPLETE_ANALYSIS_WALKTHROUGH.md#model-assisted-workflow-with-the-r-interface) |
| Browser use and server setup | [Workbench guide](workbench/README.md) |
| Advanced workflows and additional methods | [Documentation index](docs/README.md) |

R function documentation is available through `?sc_analyze` and
`help(package = "scAgentKit")`. The [detailed walkthrough](docs/COMPLETE_ANALYSIS_WALKTHROUGH.md)
retains the advanced R workflows and examples.

## Project status

The current version, **0.5.0.9000**, is experimental. Method selection,
annotations and biological interpretation require study-specific review.
Supported runtime combinations and deployment scope are documented in the
[runtime guide](docs/LINUX_RUNTIME_SUPPORT.md).

[Version history](NEWS.md) · [License](LICENSE.md)
