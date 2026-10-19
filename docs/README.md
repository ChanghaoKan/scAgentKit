# Documentation

For a first project, use the [README](../README.md#analysis-protocol),
[English operator guide](SCIENTIFIC_REVIEW_QUICKSTART.md),
[中文操作指南](SCIENTIFIC_REVIEW_QUICKSTART_ZH.md) or [three-gate R protocol](R_ANALYSIS_PROTOCOL.md).
R and browser clients share one saved-project engine. The high-level interface
is `sc_start`/`sc_analyze`/`sc_open`/`sc_review`/`sc_result`; advanced `sc_run_*`
operations use the same state, approvals and integrity checks.

[Development API consolidation](API_CONSOLIDATION.md) records the removed
orchestration, retained Seurat/table utilities and changed object types.
Published v0.6.0 uses its [version-matched protocol](RELEASE_060_PROTOCOL.md).
The [workbench guide](../workbench/README.md) explains the same project's local
browser and computation workers.

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
| Model-assisted workflow with the high-level R interface | [Model workflow](COMPLETE_ANALYSIS_WALKTHROUGH.md#model-assisted-workflow-with-the-r-interface) |
| Model payload consent, requests and candidates | [Model review](UNIFIED_MODEL_REVIEW.md) |
| Incomplete model responses and new-project recovery | [Response recovery](annotation-response-recovery.md) |
| Child analysis, exact-ID application and undo | [Subcluster review](SUBCLUSTER_REVIEW.md) |
| Click-only external gene links | [Gene lookups](GENE_LOOKUPS.md) |
| Optional dependency versions and deployment scope | [Runtime support](LINUX_RUNTIME_SUPPORT.md) |

## Package and development reference

Installed function documentation is available through `help(package = "scAgentKit")`.
[Installed examples](../inst/examples) include the PBMC tutorial and focused
R/CLI workflows. The [package vignette](../vignettes/scAgentKit-pbmc_small.Rmd)
uses the same offline tutorial.

[Workbench technical references](../workbench/README.md#technical-reference)
describe the separate export adapters and tests. They are not alternative
first-project instructions. [Benchmark scaffolding](../benchmark/README.md)
and the [scientific benchmark protocol draft](BENCHMARK_PROTOCOL_DRAFT.md)
describe planned evaluations, not validated comparative results.

Version history remains in [NEWS](../NEWS.md), Git history, tags and GitHub
Releases. Development-session test receipts are not user instructions; current
checks are defined in [.github/workflows](../.github/workflows).

- [Annotation evidence assistance](ANNOTATION_ASSISTANCE.md): local facts, explicit candidates, protected drafts and complete-proposal review.
- [Offline comparison contract](OFFLINE_COMPARISON_CONTRACT.md): public cases, synthetic controls, installation/platform gates and benchmark prerequisites.

- [Direct 10x MEX input and sample tables](TENX_INPUT.md): explicit source class, unique cell IDs, feature identity and exact metadata alignment.

- [R-only public PBMC3k protocol](R_ANALYSIS_PROTOCOL.md): full manual strategy, annotation and result sequence.

- [科学诊断一页指南](SCIENTIFIC_REVIEW_QUICKSTART_ZH.md) and [method appendix](SCIENTIFIC_METHODS_APPENDIX.md): optional development capabilities and limitations.
- [Prospective evaluation v1](EVALUATION_PROTOCOL_V1.md): frozen baseline, mappings, metrics and no-help/regression gates.
