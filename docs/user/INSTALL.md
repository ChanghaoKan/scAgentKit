# Installation and offline trial

scAgentKit runs on Linux and macOS with R ≥ 4.2, Seurat ≥ 5 and Python ≥ 3.9.
Windows is unsupported. The commands below install the current development
source. Use a new project for the trial; retain the software environment used
to create any existing research project.

## Install

```r
install.packages(c("remotes", "httr2"))
remotes::install_github("ChanghaoKan/agentomicsCore@v0.3.0",
                        dependencies = NA, upgrade = "never")
remotes::install_github("ChanghaoKan/scAgentKit",
                        dependencies = NA, upgrade = "never")
library(scAgentKit)
sessionInfo()
```

`httr2` supports the provider interface, including the structured-turn client
used by the mock ReAct example.

For a study, replace `ChanghaoKan/scAgentKit` with
`ChanghaoKan/scAgentKit@FULL_COMMIT_SHA` and record that commit with the project.
Also retain `sessionInfo()` and the dependency environment: a package version
alone does not identify a development revision or reproduce its dependencies.

Source installation requires build tools (Xcode Command Line Tools on macOS).
For Ubuntu/Debian, after installing R ≥ 4.2:

```sh
sudo apt-get update
sudo apt-get install -y git curl python3 ca-certificates build-essential \
  gfortran cmake pkg-config libcurl4-openssl-dev libssl-dev libxml2-dev \
  libpng-dev libjpeg-dev libtiff-dev libfontconfig1-dev libfreetype6-dev \
  libharfbuzz-dev libfribidi-dev libhdf5-dev libglpk-dev libgmp-dev
```

Install the system libraries before retrying an R package installation that
requires them. Harmony and doublet analysis have additional
[version requirements](../LINUX_RUNTIME_SUPPORT.md); they are not needed for
the offline trial below.

## Offline trial

```r
data("pbmc_small", package = "SeuratObject")
saveRDS(pbmc_small, "pbmc-small-trial.rds")
sc_start("pbmc-small-trial.rds", "pbmc-small-trial-project",
  context = list(species = "human", tissue = "blood",
                 research_goal = "Try the review workflow"),
  provider = "mock", react = "all", doublet = "off")
```

The workbench opens an analysis plan for review. Continue through the three
decisions: the initial plan, measured clustering and annotation. Saving a draft
does not approve it. This trial makes no external model calls; its mock labels
demonstrate software operation and do not validate biological accuracy.

For model-assisted analysis, set the selected provider's API key in the R
environment (for example, `DEEPSEEK_API_KEY`), select that provider and create a
new project. Confirm the aggregate data transfer scope before requesting a
draft. Keep credentials outside the repository. Provider usage and costs are
recorded after calls; there is no monetary cap.

Reopen using the same input/project and software environment. See
[workflow](WORKFLOW.md), [cancel/resume/disk allowance](TRIAL_CONTROLS.md) and
[complete examples](../../inst/examples/README.md).

For a downloaded source archive, follow the
[archive installation and checksum instructions](../../inst/INSTALL.md).
