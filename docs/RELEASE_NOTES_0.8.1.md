# scAgentKit 0.8.1 (experimental prerelease)

Version 0.8.1 provides one current researcher installation and operating path in the English and Chinese READMEs. Older protocols and plans remain in the developer archive, while NEWS and Git history retain the actual development record.

## Reviewed analysis

- Three separate scientific approvals: initial strategy, measured clustering and annotation. Preparing or adopting a draft does not approve a scientific decision.
- Original counts, cell IDs and metadata are preserved. Same-assay split count layers are joined with identity checks and a saved receipt.
- Conservative QC drafts, editable reasons, measured resolution evidence and protected human choices remain visible. Optional cycle/doublet handling follows the saved policy.
- First annotation uses independent marker evidence. Reference comparison follows it; at most one explicit, budgeted guided difference review is available.

## References and optional models

- A pinned Human/Mouse ACT snapshot loads offline for new projects using explicit species and exact tissue matching. Source URLs, original PMIDs, download date and original/compressed SHA256 are retained. Existing projects keep saved references; custom references take precedence and explicit `reference=NULL` opts out.
- ACT: Quan F et al. *Annotation of cell types (ACT): a convenient web server for cell type annotation.* Genome Medicine 15, 91 (2023). DOI: https://doi.org/10.1186/s13073-023-01249-5, PMID 37924118. Full attribution is included in `citation("scAgentKit")`.
- Standard new DeepSeek Flash projects use the user-selected USD1 cap. Explicit finite nonnegative custom caps take precedence; existing project caps stay frozen. Exact payload and fee consent remain required under the chosen transfer policy.
- Missing credentials leave a manual path. Failed suggestions save a local rule draft without approval or automatic retry. Original numeric usage is retained with integrity hashes. Workflow completion does not establish biological accuracy.

## Installation and compatibility

Use the version 0.8.1 archive and SHA256SUMS linked in README. CI builds the untouched archive from the merged `v0.8.1` tag, verifies its source/byte hashes, and performs an anonymous download and README installation into empty R libraries. The release remains an experimental prerelease. Logs and receipts identify the exact tested archive.

macOS and Linux are supported; Windows is not supported by the Unix process-lock implementation. Use Seurat 5 and the documented dependencies. Reopening an existing project preserves its configuration and implementation checks; keep its original matching library where its saved environment requires it.

Local implementation acceptance includes a complete R suite at ACT implementation commit 274b87d (585 test blocks, 9470 passed assertions, one unavailable exact legacy dependency-pair skip), Python/Node tests, installed-package browser and three-approval checks. The linked PR and workflow receipts provide validation for the final 0.8.1 source and tag. No new paid model requests or repeat 50k benchmark are required for this release.
