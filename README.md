# scAgentKit

scAgentKit is an R package for single-cell RNA-seq analysis with Seurat: quality
control, dimensionality reduction, clustering, annotation and subcluster analysis.
It produces a new Seurat object, marker tables, figures and a record of the
parameters and decisions used along the way.

Analyses live in project directories, so you can save progress, inspect results
and continue in a later R session. You check analysis settings and annotations
before applying them. Model suggestions and a local web interface are optional.
The current development version is **0.5.0.9000**.

[中文完整操作指南](docs/RESEARCHER_PROTOCOL_ZH.md) ·
[Documentation](docs/README.md) · [Changes](NEWS.md)

## Installation

Requires R >= 4.2 and Seurat >= 5. Install `remotes` first if needed, then:

```r
remotes::install_github("ChanghaoKan/scAgentKit")
library(scAgentKit)
```

See the [installation guide](docs/RESEARCHER_PROTOCOL_ZH.md#2-安装与版本确认)
for dependencies, separate R libraries and reproducible environments.

## Start an analysis

With your Seurat object in `seu`, create a project on the machine holding the data:

```r
run <- sc_run(seu, project_dir = "my-study",
  context = list(species = "human", tissue = "Peripheral blood"),
  strategy = TRUE)
view <- sc_run_inspect("my-study")
```

This saves initial diagnostics. Add your study's analysis plan or configure a
model to suggest one, inspect the plan, and continue. With neither supplied,
the project pauses at `awaiting_configuration`.

You can also supply a named genes × cells raw-count matrix or a local RDS path.
For your study, set the species, tissue and sample/capture metadata as appropriate.
An existing processed Seurat object can reuse its analysis through
`start_stage = "processed"` with a reuse reason. The
[researcher guide](docs/RESEARCHER_PROTOCOL_ZH.md) covers these inputs, parameter
choices, model setup and annotation; [strategy](docs/ANALYSIS_STRATEGY_SUPPORT.md)
and [annotation](docs/ANNOTATION_REVIEW.md) guides include R examples.

## Try a complete run without an API

This small example runs the full workflow on SeuratObject's public `pbmc_small`
counts (230 genes, 80 cells). An offline mock supplies the settings and labels,
so no API key is needed. It deliberately uses `Unknown`: this is a workflow
demonstration, not biological annotation. In a real project, annotations come
from your marker/reference evidence and manual or model-assisted proposals.

```r
source(system.file("examples", "researcher-pbmc.R", package = "scAgentKit"))
project_dir <- file.path(getwd(), "pbmc-tutorial")  # choose a new directory
mock <- make_researcher_pbmc_mock()
run <- researcher_pbmc_start(project_dir, mock)

view <- researcher_pbmc_inspect(project_dir)
view$strategy_review$details
researcher_pbmc_decide(project_dir, view, reviewer = "analyst",
  reason = "Checked the tutorial settings and retained cells.")
run <- researcher_pbmc_resume(project_dir, mock)

view <- researcher_pbmc_inspect(project_dir)
view$annotation_review$details
researcher_pbmc_decide(project_dir, view, reviewer = "analyst",
  reason = "Keep the tutorial's unresolved labels as Unknown.")
done <- researcher_pbmc_resume(project_dir, mock)
stopifnot(identical(done$status, "complete"))
final_object <- readRDS(done$output$seurat)
done$output
```

The helpers use the same `sc_run()` project workflow as the study example above:
inspect, record your decision, then resume to the next step.

## Results and reopening

`done$output` lists the Seurat object, tables, figures and project records.
Use `sc_run_inspect(project_dir)` to inspect saved status and history, and
`sc_run_resume(project_dir)` to continue later. A completed project reopens
without repeating its analysis.

To browse saved results, use a source checkout with Python >= 3.9:

```r
sc_run_open(project_dir, checkout = "/path/to/scAgentKit")
# Later sessions remember the checkout:
sc_run_open(project_dir)
```

The [workbench guide](workbench/README.md) covers browser-based decisions,
local computation, parent/child projects and remote access.

## Notes for research use

Analysis choices and cell identities need study-specific judgment. External
models receive aggregate evidence only after you approve its disclosure; that
evidence may still contain sensitive study information. The web service binds
to loopback, and shared-host access needs appropriate isolation. See
[model and data handling](docs/UNIFIED_MODEL_REVIEW.md) and the
[complete guide](docs/RESEARCHER_PROTOCOL_ZH.md) for details.
