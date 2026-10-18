# scAgentKit 0.6.0 (experimental)

This release follows the scientific and compatibility audit while retaining all
exported APIs. It fixes ribosomal gene matching, committed-cluster marker
grouping, derived-cache invalidation, NULL provider resend, grounded subcluster
failure auditing, saved UMAP parameter equivalence and unsupported doublet
version diagnostics. Confidence scoring policy is unchanged.

## Compatibility and metadata priors

Implementation hashes changed relative to earlier code. Projects whose saved
implementation hash differs from the current functions or fingerprinted
dependency versions cannot resume execution or approve/review stale proposals.
`sc_run_resume()` checks this even for a completed run. Package version alone
does not decide compatibility.

Preserve the original project, raw input, package build and dependency versions.
Restore that exact environment to continue the original project, or create a new
project directory from the original input and review the analysis again. Never
edit saved hashes, approvals, checkpoints or authoritative Seurat files to force
continuation. Existing final files remain subject to their recorded integrity
checks.

Author-label metadata priors are **off by default**. Legacy annotation and
resolution recommendation use them only with explicit `use_metadata_prior=TRUE`;
independent annotation excludes them. Legacy workflow exports remain available
through 0.6.x and 0.7.x; removal is planned no earlier than 0.8.0 with a migration
notice. Current coordinator calls remain supported.

## Install and verification

Download `scAgentKit_0.6.0.tar.gz` and `SHA256SUMS`, verify the checksum, and follow
the [README](https://github.com/ChanghaoKan/scAgentKit/blob/v0.6.0/README.md#installation).
CI builds the archive directly from this tag using ordinary `R CMD build`;
archive metadata and DESCRIPTION are not manually changed.

The release workflow then anonymously downloads the public asset in a fresh
`rocker/r-ver` container, installs required dependencies and the package using the
README commands, and runs the installed offline example and runtime entry checks.
Full install/example logs are retained with the workflow. **Public installation
acceptance remains pending until that job succeeds**; publication alone does
not complete installation audit item #13.

The offline example is a software control, makes no provider request, and is not
biological accuracy evidence. No Windows, real-browser or development Docker
image verification is claimed. Private data, credentials, personal paths and raw
provider responses are not release assets.
