# Runtime support

The required R packages and minimum versions are declared in
[DESCRIPTION](../DESCRIPTION). Install optional dependencies only for methods
you intend to use. An installed package is not evidence that its version or
source is accepted by an adapter.

## Optional method guards

| Method | Runtime contract in the current source |
| --- | --- |
| Modern doublet adapter | scDblFinder exactly 1.26.7, xgboost >= 3.1, and accepted canonical classifier function hashes |
| Additional doublet adapter | scDblFinder exactly 1.22.0 paired with xgboost exactly 1.7.11.1, and its accepted canonical hashes |
| Other scDblFinder versions, including 1.26.9 | Unsupported. Dependency preflight reports the actual installed version and stops before classifier execution; it never silently skips detection. |
| Harmony | Harmony 2.0.x with the exact supported modern public method signatures and options object; runtime function identities are recorded and checked during execution |

The legacy `qc_doublet()` entry also checks the supported version pair. For an
unsupported installation, use a separately verified isolated R library with a
supported pair and the accepted adapter sources, or explicitly disable optional
doublet analysis in a new reviewed plan. Do not replace packages in a shared
global environment to bypass this guard. A newer official release is not
automatically an accepted adapter; acceptance requires independent verification.

The doublet pairs are selected in `R/run-doublet.R`; the Harmony API guard is in
`R/run-harmony.R`. A generic latest-version install is not a compatibility check.
Unknown versions, altered classifier functions and incompatible backends are
rejected. Do not disable a guard to make an installation appear supported.
See [doublet prerequisites](DOUBLET_REVIEW.md) and
[Harmony design requirements](HARMONY_PC_REVIEW.md) before enabling either.

The supported runtime contract is distinct from scientific performance. It does
not establish calibrated doublet probabilities, preservation of treatment effects
or valid cell identities.

## Installation and environment records

Use a private library for the checkout and approved dependencies. With dependencies
already available, install the local source as follows:

```sh
sc_checkout=/absolute/path/to/verified/scAgentKit-checkout
sc_r_library=/absolute/path/to/private-r-library
mkdir -p "$sc_r_library"
cd "$sc_checkout"
R_LIBS_USER="$sc_r_library" R CMD INSTALL --library="$sc_r_library" .
```

This command does not download or repair dependencies. For repository installation,
use the [README](../README.md#installation). Record the source commit, R executable,
`.libPaths()`, installed package versions and `sessionInfo()`. Preserve the project's
original environment when resuming; changing implementation can invalidate approvals.
Saved doublet evidence uses its recorded runtime provenance rather than the optional
package currently installed in the reviewing R process.

## Web service and deployment

The local service needs Python >= 3.9 and the runtime bundled in the installed R package. A matching checkout is an explicit developer option, not a normal installation requirement.
R-backed operations also require the project's compatible R environment;
the expression bridge uses SeuratObject, Matrix, jsonlite and digest.
Node is needed only for DOM tests. Browser smoke tests need an existing
Playwright/Chrome installation and their documented fixtures.

The browser worker needs POSIX `flock`. This installation CI targets Linux and macOS. Windows browser/background-worker support is not validated; the presence of `configure.win` is not a Windows execution claim. Use headless R where POSIX workers are unavailable and validate that platform separately.
Run computation on a suitable machine or allocated compute node, with local
filesystem semantics supporting locks and atomic replacement. Shared filesystems,
scheduler integration and multiuser isolation require site-specific verification.
The service neither submits jobs nor supplies multiuser authentication.

The repository CI workflows define their checked environments. Previous Mac or
Linux checks do not establish compatibility with every OS/dependency combination,
shared filesystem or HPC deployment. Consult the check result for the exact source
commit being used, and test the intended deployment separately. See the
[workbench guide](../workbench/README.md#remote-access) for loopback access.
