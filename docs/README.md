# Documentation

For a first project, follow the [README analysis walkthrough](../README.md#first-analysis).
Then use the [完整中文操作指南](RESEARCHER_PROTOCOL_ZH.md) for installation,
your own data, approvals, results, recovery and server use. The README uses the four high-level R entries; the protocol retains the
advanced `sc_run()` workflow. The [complete previous walkthrough](COMPLETE_ANALYSIS_WALKTHROUGH.md)
is preserved for manual schemas, model setup and detailed editing. The [workbench guide](../workbench/README.md)
explains optional browser review and local computation.

## Analysis and review

| Topic | Guide |
| --- | --- |
| Typed strategy, raw counts, PCs and clustering | [Analysis strategy](ANALYSIS_STRATEGY_SUPPORT.md) |
| Range-based QC and impact review | [QC review](QC-review.md) |
| Sample-aware MAD candidates | [MAD review](MAD_REVIEW.md) |
| Capture-aware doublet diagnostics | [Doublet review](DOUBLET_REVIEW.md) |
| Cell-cycle evidence and regression choices | [Cell-cycle review](CELL_CYCLE_REVIEW.md) |
| Harmony design and PC policies | [Harmony and PCs](HARMONY_PC_REVIEW.md) |
| Parameter edits, processed reuse and child context | [Parameter controls](PARAMETER_CONTEXT_CONTROLS.md) |
| Whole-plan annotation and undo | [Annotation review](ANNOTATION_REVIEW.md) |
| Local CellMarker evidence and provenance | [Reference evidence](CM2_EVIDENCE_REVIEW.md) |
| Model payload consent, requests and candidates | [Model review](UNIFIED_MODEL_REVIEW.md) |
| Incomplete model responses and new-project recovery | [Response recovery](annotation-response-recovery.md) |
| Child analysis, exact-ID application and undo | [Subcluster review](SUBCLUSTER_REVIEW.md) |
| Click-only external gene links | [Gene lookups](GENE_LOOKUPS.md) |
| Optional dependency versions and deployment scope | [Runtime support](LINUX_RUNTIME_SUPPORT.md) |

## Package and development reference

Installed function documentation is available through `help(package = "scAgentKit")`.
[Installed examples](../inst/examples) include the PBMC tutorial and focused
R/CLI workflows. The [package vignette](../vignettes/scAgentKit-pbmc3k.Rmd)
uses the same offline tutorial.

[Workbench technical references](../workbench/README.md#technical-reference)
describe the separate export adapters and tests. They are not alternative
first-project instructions. [Benchmark scaffolding](../benchmark/README.md)
and the [scientific benchmark protocol draft](BENCHMARK_PROTOCOL_DRAFT.md)
describe planned evaluations, not validated comparative results.

Version history remains in [NEWS](../NEWS.md), Git history, tags and GitHub
Releases. Development-session test receipts are not user instructions; current
checks are defined in [.github/workflows](../.github/workflows).
