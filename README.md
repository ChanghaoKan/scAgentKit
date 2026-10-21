# scAgentKit

scAgentKit is an R package for single-cell RNA-seq analysis with researcher review
and optional language-model assistance. It uses Seurat for data processing and
provides an R interface and a local browser workbench for reviewing quality
control, clustering and cell-type annotations.

The package is under active development. Formal evaluation of its biological
performance is pending.

## Installation

Requires Linux or macOS, R ≥ 4.2, Seurat ≥ 5 and Python ≥ 3.9. Windows is unsupported.
Install the current development source and its shared core:

```r
install.packages(c("remotes", "httr2"))
remotes::install_github("ChanghaoKan/agentomicsCore@v0.3.0", upgrade = "never")
remotes::install_github("ChanghaoKan/scAgentKit", upgrade = "never")
```

See the [installation guide](docs/user/INSTALL.md) for system dependencies and
source-version pinning.

## Try the workflow

This example opens the workbench with the bundled PBMC dataset and a mock
provider. It needs no API key and makes no external model requests.

```r
library(scAgentKit)
data("pbmc_small", package = "SeuratObject")
trial <- tempfile("scagentkit-trial-")
dir.create(trial)
input <- file.path(trial, "pbmc-small.rds")
saveRDS(pbmc_small, input)

sc_start(input, file.path(trial, "project"),
  context = list(species = "human", tissue = "blood",
                 research_goal = "Explore the review workflow"),
  provider = "mock", doublet = "off")
```

For research data, inputs can be an RDS file, a 10x MEX directory or a sample
table. The workflow pauses for three decisions:

1. Review the quality-control and analysis plan before computation.
2. Inspect the measured clustering diagnostics and select a scanned resolution.
3. Review and approve the complete annotation proposal.

Saving a draft does not approve it. The completed project contains an annotated
Seurat object, marker tables, figures, parameters and review records. Follow the
[workflow guide](docs/user/WORKFLOW.md) or a [complete example](inst/examples/README.md).

## Reproducibility

For a study, pin the scAgentKit source commit and retain `sessionInfo()`, input
provenance, analysis settings and the complete project directory. A development
version number alone does not identify the source used. Reopen a project with
its original software environment; incompatible project formats are rejected.

External model assistance requires a configured provider and consent to send
the selected aggregate data. Projects record available token usage and costs
after requests; there is no spending cap. See [model usage](docs/MODEL_BUDGET.md)
and [project preservation](docs/user/RESOURCE_CONTROLS.md).

## Limitations

Mock examples and software tests verify workflow behavior, not cell-type
accuracy. Quality-control decisions, batch adjustment and annotation labels
require study-specific assessment. Trajectory inference, cell communication,
regulatory networks and condition comparisons are outside this package's
workflow. Method definitions and interpretation are documented in the
[methods reference](docs/SCIENTIFIC_METHODS_APPENDIX.md).

## Documentation and citation

The [documentation index](docs/README.md) covers inputs, methods, model
assistance and operation. [Developer documentation](docs/dev/README.md) describes
implementation and validation; [NEWS](NEWS.md) records changes.

Use `citation("scAgentKit")` or [CITATION.cff](CITATION.cff) to cite the software,
and report the source commit used in the analysis. Cite the underlying methods
and reference resources used in your study, including
[ACT](docs/ACT_LOCAL_REFERENCE.md) when applicable.
The software is distributed under the [MIT license](LICENSE.md).
