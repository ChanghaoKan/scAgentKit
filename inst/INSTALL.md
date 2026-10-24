# Install and check a source archive

For GitHub source installation, see the repository's `docs/user/INSTALL.md`.
This guide accompanies scAgentKit 0.10.0 and project format 4. Follow the
instructions supplied with the archive you downloaded, and keep its version,
source commit and checksum
with the analysis.

Download the archive and its checksum from the same build. Verify SHA256 before
running R (`shasum -a 256 -c SHA256SUMS` on macOS, `sha256sum -c SHA256SUMS` on Linux).
Use a new R session in that directory, with exactly one scAgentKit archive.

## Installation

```r
options(timeout = max(1800, getOption("timeout", 60)))
lib <- path.expand("~/R/scagentkit-library")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib, .libPaths()))
install.packages(c("remotes", "httr2"), lib = lib)
archives <- list.files(pattern = "^scAgentKit_[0-9][0-9.-]*[.]tar[.]gz$")
stopifnot(length(archives) == 1L)
remotes::install_local(archives[[1L]], lib = lib,
  dependencies = c("Depends", "Imports"), upgrade = "never", build = FALSE)
library(scAgentKit, lib.loc = lib)
stopifnot(identical(normalizePath(find.package("scAgentKit")),
  normalizePath(file.path(lib, "scAgentKit"))))
packageVersion("scAgentKit")
```

Record the source commit, checksum and `sessionInfo()`. A development package's
version string does not identify its source commit.

## Offline installation check

```r
source(system.file("examples", "simple-analysis.R", package = "scAgentKit"))
result <- simple_analysis_after(tempfile("scagentkit-offline-"))
stopifnot(inherits(result, "Seurat"), ncol(result) > 0)
```

This uses scripted approvals on a public software fixture, makes no provider
calls and does not establish biological accuracy. Research projects require your
own review of the three scientific decisions.

## Start using the package

Open the getting-started vignette and function reference from R:

```r
browseVignettes("scAgentKit")
help("sc_start", package = "scAgentKit")
help("sc_result", package = "scAgentKit")
```

The vignette covers opening the browser, the three review decisions, retrieving
results and reopening a project. Installed examples are in
`system.file("examples", package = "scAgentKit")`.
