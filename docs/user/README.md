# User guide

scAgentKit takes single-cell counts and sample information through reviewed
quality control, clustering and annotation. Install the R package, open a local
browser session and retain the resulting Seurat object and project records.

## Version

This manual describes **scAgentKit 0.10.0**, using project format 4.
The earlier [v0.9.0 release](https://github.com/ChanghaoKan/scAgentKit/releases/tag/v0.9.0)
uses format 3 and its own supplied manual. Retain the source commit as well as
the package version. Use the manual supplied with the installed version.
Open existing projects in the environment used to create them.

## First analysis

1. [Install scAgentKit](INSTALL.md) and try the small offline dataset.
2. [Follow the analysis workflow](WORKFLOW.md), including all three review steps.
3. [Retrieve the completed Seurat object](WORKFLOW.md#4-retrieve-results) and
   preserve the project for reopening.

## Common tasks

| Task | Guide |
| --- | --- |
| Import counts, Seurat objects or multiple 10x samples | [Input formats](../TENX_INPUT.md) |
| Review QC, clustering and cell-type labels | [Analysis workflow](WORKFLOW.md) |
| Work entirely from R | [R workflow](../R_ANALYSIS_PROTOCOL.md) |
| Use a complete example or a model-assisted entry helper | [Examples](../../inst/examples/README.md) |
| Analyse a subset of cells | [Subcluster review](../SUBCLUSTER_REVIEW.md) |
| Cancel or continue a run | [Run controls](TRIAL_CONTROLS.md) |
| Manage storage and preserve a project | [Resources and backups](RESOURCE_CONTROLS.md) |
| Reopen a completed or interrupted analysis | [Reopening](WORKFLOW.md#5-reopen-a-saved-project) |
| Configure model requests and understand recorded costs | [Model usage](../MODEL_BUDGET.md) |
| Understand optional methods and their dependencies | [Runtime requirements](../LINUX_RUNTIME_SUPPORT.md) |
| Interpret diagnostics and method limitations | [Methods reference](../SCIENTIFIC_METHODS_APPENDIX.md) |

## Help from the installed package

The package includes a getting-started vignette, function reference and example
scripts. Open them from R:

```r
browseVignettes("scAgentKit")
help("sc_start", package = "scAgentKit")
help("sc_result", package = "scAgentKit")
system.file("examples", package = "scAgentKit")
```

## Troubleshooting

For a missing dependency or unsupported platform, start with the
[installation guide](INSTALL.md). For input, counts/layer or reopening errors,
use the [operator reference](../SCIENTIFIC_REVIEW_QUICKSTART.md).

If you need help, open an
[issue](https://github.com/ChanghaoKan/scAgentKit/issues) with the command that
failed, its error message, the package version and `sessionInfo()`. A small
public or synthetic input helps reproduce the problem. Keep API keys and
private study data out of issue reports.

The [full documentation index](../README.md) contains additional method and
reference material. [Contributing](../../CONTRIBUTING.md) covers source changes
and maintainer checks.
