# scAgentKit

scAgentKit is an R package for reviewing and analysing single-cell RNA-seq data.
Start with counts and sample information, review quality control and clustering
in a local browser, then inspect markers and approve cell-type annotations.
The result is a Seurat object accompanied by marker tables, figures and a record
of your decisions. Model assistance is optional.

[Latest release](https://github.com/ChanghaoKan/scAgentKit/releases/tag/v0.9.0) ·
[Installation](docs/user/INSTALL.md) ·
[User guide](docs/user/README.md) ·
[Examples](inst/examples/README.md) ·
[Report a problem](https://github.com/ChanghaoKan/scAgentKit/issues)

## Installation

Requires **Linux or macOS, R ≥ 4.2, Seurat ≥ 5 and Python ≥ 3.9**.
The R package includes the browser interface. Windows is unsupported.

| Version | Install | Documentation |
| --- | --- | --- |
| Release: **v0.9.0** | Download `scAgentKit_0.9.0.tar.gz` and `SHA256SUMS` from [Releases](https://github.com/ChanghaoKan/scAgentKit/releases/tag/v0.9.0) | [Manual for that release](https://github.com/ChanghaoKan/scAgentKit/blob/v0.9.0/inst/INSTALL.md#installation) |
| Development source: **0.9.1.9000 on main** | Follow [source installation](docs/user/INSTALL.md#install-current-source) | [Current user guide](docs/user/README.md) |

Use the manual for the version you install. Current development source requires
project format 4; published v0.9.0 uses format 3. Open existing projects in their
original software environment. scAgentKit is experimental; formal evaluation
of biological accuracy is pending.

## Start with a small dataset

After installing current source, run this example in R. It opens the local
workbench with a public PBMC dataset and manual annotation, with no model calls.

```r
library(scAgentKit)
data("pbmc_small", package = "SeuratObject")
example_dir <- tempfile("scagentkit-example-")
dir.create(example_dir)
input <- file.path(example_dir, "pbmc-small.rds")
saveRDS(pbmc_small, input)

sc_start(input, file.path(example_dir, "project"),
  context = list(species = "human", tissue = "blood",
                 research_goal = "Explore the review workflow"),
  provider = "manual", model_suggestions = "off", doublet = "off")
```

The browser guides you through three decisions:

1. Review quality control and the analysis plan.
2. Inspect measured clustering and choose a scanned resolution.
3. Review markers and reference candidates, complete the annotation worksheet,
   and approve the labels.

Saving a draft keeps your edits; approval starts the next local step. Enter
labels or retain Unknown where unresolved. This public software fixture
demonstrates the interface and does not validate cell-type accuracy.
The [workflow guide](docs/user/WORKFLOW.md) explains each decision.

## Analyse your data

Inputs can be an RDS file containing counts or a Seurat object, a 10x MEX
directory, or a table describing multiple samples. Start a new project with
verified species, tissue and sample information. See
[input formats](docs/TENX_INPUT.md) and the [analysis guide](docs/user/WORKFLOW.md).

After completing annotation, retrieve the Seurat object in R:

```r
result <- sc_result(file.path(example_dir, "project"))
table(result$sc_annotation)
```

Keep the complete project directory, original inputs and software environment
with your study. Reopen saved projects using the software that created them.
Model assistance requires provider configuration and permission to send the
selected aggregate data; consult the [model usage guide](docs/MODEL_BUDGET.md).

## Limitations

QC decisions, batch adjustment and cell-type labels require study-specific
assessment. Trajectory inference, cell communication, regulatory networks and
condition comparisons are outside this workflow. Consult the
[methods reference](docs/SCIENTIFIC_METHODS_APPENDIX.md) for interpretation.

## Help and citation

Use the [user guide](docs/user/README.md) for installation, inputs, results and
troubleshooting, and the [methods reference](docs/SCIENTIFIC_METHODS_APPENDIX.md)
for calculations and interpretation. In R, run `browseVignettes("scAgentKit")`
or `help("sc_start", package = "scAgentKit")`.

Report installation or workflow problems in
[GitHub Issues](https://github.com/ChanghaoKan/scAgentKit/issues), with the error
message, software version and `sessionInfo()`. Keep credentials and private
study data out of the report.

Cite the software with `citation("scAgentKit")` and record its source commit or
archive checksum. Also cite the methods and reference resources used in your
study, including [ACT](docs/ACT_LOCAL_REFERENCE.md) when applicable.
scAgentKit is distributed under the [MIT license](LICENSE.md).

<details>
<summary>Contributing and research documentation</summary>

[Contribution guide](CONTRIBUTING.md) · [Developer references](docs/dev/README.md) ·
[Research protocols](docs/research/README.md) · [Changes](NEWS.md)

</details>
