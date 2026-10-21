# Runtime requirements

The required R packages and minimum versions are declared in
[DESCRIPTION](../DESCRIPTION). Install optional dependencies only for methods
you intend to use. An installed package is not evidence that its version or
source is accepted by an adapter.

## Optional analysis methods

| Method | Runtime contract in the current source |
| --- | --- |
| Doublet detection with scDblFinder 1.26.7 | xgboost >= 3.1 and accepted classifier function hashes |
| Doublet detection with scDblFinder 1.22.0 | xgboost exactly 1.7.11.1 and accepted classifier function hashes |
| Other scDblFinder versions | Unsupported; dependency preflight stops before classifier execution. |
| Harmony | Harmony 2.0.x with the supported public method signatures and options object; runtime function identities are recorded and checked during execution. |

The reviewed doublet adapter checks its supported version pair. For an
unsupported installation, use a separately verified isolated R library with a
supported pair and the accepted adapter sources, or explicitly disable optional
doublet analysis in a new reviewed plan. Do not replace packages in a shared
global environment to bypass this guard. A newer official release is not
automatically an accepted adapter; acceptance requires independent verification.

The accepted doublet pairs are defined in `R/run-doublet.R`; the Harmony API
check is in `R/run-harmony.R`. Unknown versions, altered classifier functions
and unsupported backends are rejected.
See [doublet prerequisites](dev/DOUBLET_REVIEW.md) and
[Harmony design requirements](dev/HARMONY_PC_REVIEW.md) before enabling either.

The supported runtime contract is distinct from scientific performance. It does
not establish calibrated doublet probabilities, preservation of treatment effects
or valid cell identities.

## Installation and environment records

Follow the [installation guide](user/INSTALL.md) for the current development
source. Pin a full commit SHA for a study and retain the dependency environment.
For a downloaded source archive, verify its checksum and follow the
[bundled installation guide](../inst/INSTALL.md).

Record the source commit, archive SHA256 when applicable, R executable,
`.libPaths()`, installed package versions and `sessionInfo()`.
Preserve the project's original environment when resuming;
changing implementation can invalidate approvals.
Saved doublet evidence uses its recorded runtime provenance rather than the optional
package currently installed in the reviewing R process.

## Web service and deployment

The local service needs Python >= 3.9 and the runtime bundled in the installed
R package. A source checkout is only needed when explicitly developing against
that checkout.
R-backed operations also require the project's compatible R environment;
the expression bridge uses SeuratObject, Matrix, jsonlite and digest.
Node is needed only for DOM tests. Browser smoke tests need an existing
Playwright/Chrome installation and their documented fixtures.

The browser worker needs POSIX `flock`. Installation CI targets Linux and macOS;
Windows browser and background-worker support is not validated. Other
platforms require separate testing, including for headless R use.
Run computation on a suitable machine or allocated compute node, with local
filesystem semantics supporting locks and atomic replacement. Shared filesystems,
scheduler integration and multiuser isolation require site-specific verification.
The service neither submits jobs nor supplies multiuser authentication.

The repository CI workflows define their checked environments. Previous Mac or
Linux checks do not establish compatibility with every OS/dependency combination,
shared filesystem or HPC deployment. Consult the check result for the exact source
commit being used, and test the intended deployment separately. See the
[workbench guide](../workbench/README.md#remote-access) for loopback access.
