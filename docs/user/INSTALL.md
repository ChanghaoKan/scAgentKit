# Install scAgentKit

scAgentKit runs on Linux and macOS with R ≥ 4.2, Seurat ≥ 5 and Python ≥ 3.9.
Windows is unsupported. The browser interface is included in the R package.
Choose a version below, then use its matching guide and a new project for your
first trial. Retain the original software environment for existing projects.

## Download the published preview

The [v0.8.1 release](https://github.com/ChanghaoKan/scAgentKit/releases/tag/v0.8.1)
provides a built R source package. Under **Assets**, download
[`scAgentKit_0.8.1.tar.gz`](https://github.com/ChanghaoKan/scAgentKit/releases/download/v0.8.1/scAgentKit_0.8.1.tar.gz)
and [`SHA256SUMS`](https://github.com/ChanghaoKan/scAgentKit/releases/download/v0.8.1/SHA256SUMS)
into the same directory. Verify the download in a terminal:

```sh
# Linux
sha256sum -c SHA256SUMS
# macOS
shasum -a 256 -c SHA256SUMS
```

After verification, follow the
[installation instructions for v0.8.1](https://github.com/ChanghaoKan/scAgentKit/blob/v0.8.1/README.md#installation).
That experimental preview predates the current source. Its project format,
model interface and cost controls differ from main; use its own manual and
environment. The current source has not been published as a new release.

## Install current source

The commands below install the source on main, including unreleased changes.
They do not require a local repository checkout. Check the system dependencies
below before installing packages that need compilation.

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

For a study using this source, replace `ChanghaoKan/scAgentKit` with
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

## Try the current-source browser workflow

```r
data("pbmc_small", package = "SeuratObject")
saveRDS(pbmc_small, "pbmc-small-trial.rds")
sc_start("pbmc-small-trial.rds", "pbmc-small-trial-project",
  context = list(species = "human", tissue = "blood",
                 research_goal = "Try the review workflow"),
  provider = "mock", doublet = "off")
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

## Installed help

The installed package contains function help, example scripts and a
getting-started vignette:

```r
browseVignettes("scAgentKit")
help("sc_start", package = "scAgentKit")
```

For a source archive built from the current branch, follow the installation
guide included in that archive; its current source is
[inst/INSTALL.md](../../inst/INSTALL.md). For the published v0.8.1 archive,
use its version-matched instructions above.
