# scAgentKit 0.8.0 (experimental)

## Breaking changes

This release removes 36 direct orchestration/helper exports and the AgentSeurat
class at the previously documented earliest removal milestone, 0.8.0. It keeps
one reviewed project engine and useful Seurat/table utilities. See
[the full API and return-type inventory](https://github.com/ChanghaoKan/scAgentKit/blob/v0.8.0/docs/API_CONSOLIDATION.md)
and `inst/api-contract.json`. Scripts using the deleted APIs must be rewritten;
there is no compatibility facade or automatic project migration.

Preserve original inputs, project folders, checkpoints, package build and exact
dependency environment. Restore that environment to inspect/continue an old
implementation, or create a new project from original inputs and independently
review strategy, measured clustering and annotation. Development test projects
may be rebuilt. Never edit saved hashes, approvals or authority to force resume.
Published old tags/assets and frozen baseline evidence remain unchanged.

## Resulting workflow

The raw-count entry requires three scientific approvals. Measured QC, PC,
resolution-tree and annotation evidence supports review; candidate adoption and
saving remain separate from approval. Shared validation/ARI/marker/reference
kernels avoid duplicated orchestration. Counts, normalization, HVGs, PCA,
membership and annotation evidence are checked against frozen public controls.
Useful marker, plotting, reference and ontology tools use explicit Seurat/table
inputs. Optional costly scientific diagnostics remain off by default. Original
counts and authoritative checkpoints retain their integrity checks.

Software completion, numerical parity, reference overlap, raw heuristic confidence
and citation validity do not establish biological accuracy or optimal settings.
Unknown controls remain Unknown; there is no paid-model call or new accuracy claim.

## Installation and provenance

Follow the [versioned README](https://github.com/ChanghaoKan/scAgentKit/blob/v0.8.0/README.md#installation).
CI builds `scAgentKit_0.8.0.tar.gz` directly from the merged tag with ordinary
`R CMD build`, then publishes those exact bytes, SHA256SUMS and build-receipt.json.
No archive members or metadata are manually normalized.

Public installation acceptance remains pending until the same workflow's
clean-install job succeeds: a pinned clean rocker container anonymously downloads
the published assets, verifies the trusted checksum/tag, installs dependencies
into an empty R library using the README commands and runs the installed offline
example. Complete logs and receipts remain CI artifacts. Publication alone is
not successful public-install acceptance. Windows and biological effectiveness
are not claimed.
