# Installation and trial

[简体中文](INSTALL.zh-CN.md)

Use current main during development. Requires macOS/Linux, R ≥ 4.2,
Seurat ≥ 5 and Python ≥ 3.9. Windows is unsupported. Scientific changes can
invalidate older projects; create a fresh trial and preserve existing environments.

## Install

```r
install.packages("remotes")
remotes::install_github("ChanghaoKan/agentomicsCore@v0.3.0",
                        dependencies = NA, upgrade = "never")
remotes::install_github("ChanghaoKan/scAgentKit",
                        dependencies = NA, upgrade = "never")
library(scAgentKit)
sessionInfo()
```

For repeatable installation replace `scAgentKit` with `scAgentKit@FULL_COMMIT_SHA`.
The package version alone does not identify development revisions. Keep the
source commit and dependency environment with your project.

Source installation requires build tools (Xcode Command Line Tools on macOS).
For Ubuntu/Debian, after installing R ≥ 4.2:

```sh
sudo apt-get update
sudo apt-get install -y git curl python3 ca-certificates build-essential gfortran cmake pkg-config libcurl4-openssl-dev libssl-dev libxml2-dev libpng-dev libjpeg-dev libtiff-dev libfontconfig1-dev libfreetype6-dev libharfbuzz-dev libfribidi-dev libhdf5-dev libglpk-dev libgmp-dev
```

See [optional scientific dependencies](../LINUX_RUNTIME_SUPPORT.md).

## Offline trial

```r
data("pbmc_small", package = "SeuratObject")
saveRDS(pbmc_small, "pbmc-small-trial.rds")
sc_start("pbmc-small-trial.rds", "pbmc-small-trial-project",
  context = list(species = "human", tissue = "blood", research_goal = "Try the review workflow"),
  provider = "mock", react = "all", doublet = "off")
```

Review, save and approve each of the three decisions. Mock labels test software,
not biological accuracy. For real input, set the selected provider's key in the R
environment (for DeepSeek, `DEEPSEEK_API_KEY`), use a new project and select that
provider. Never commit credentials. Confirm the aggregate transfer scope before
sending data. Actual usage and costs are recorded after calls, without a monetary cap.

Reopen using the same input/project and software environment. See
[workflow](WORKFLOW.md), [cancel/resume/disk allowance](TRIAL_CONTROLS.md) and
[complete examples](../../inst/examples/README.md).

For a downloaded build archive, use the [bundled archive installation guide](../../inst/INSTALL.md). CI extracts and executes those commands from the unmodified archive.
