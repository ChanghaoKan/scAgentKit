# Developer documentation

For installation and analysis, start with the [user documentation](../README.md).
For source changes and validation commands, read [Contributing](../../CONTRIBUTING.md)
and the repository [development contract](../../AGENTS.md).

## Analysis and review

| Topic | Reference |
| --- | --- |
| Foundation analysis and clustering | [Analysis strategy](ANALYSIS_STRATEGY_SUPPORT.md) |
| QC rules and measured evidence | [QC review](QC-review.md), [MAD review](MAD_REVIEW.md) |
| Biological diagnostics | [Diagnostic contracts](BIOLOGICAL_DIAGNOSTICS.md) |
| Batch correction and PC selection | [Harmony review](HARMONY_PC_REVIEW.md) |
| Doublet and cell-cycle methods | [Doublet review](DOUBLET_REVIEW.md), [cell-cycle review](CELL_CYCLE_REVIEW.md) |
| Annotation and reference evidence | [Annotation review](ANNOTATION_REVIEW.md), [annotation assistance](ANNOTATION_ASSISTANCE.md), [CellMarker evidence](CM2_EVIDENCE_REVIEW.md) |
| Context and parameter revisions | [Parameter controls](PARAMETER_CONTEXT_CONTROLS.md) |

## Model requests and evidence retrieval

- [Model-assisted review](UNIFIED_MODEL_REVIEW.md)
- [Provider, model and usage contract](PROVIDER_MODEL_AND_USAGE_CONTRACT.md)
- [Structured provider turns](STRUCTURED_PROVIDER_TURNS.md)
- [ReAct loop](REACT_LOOP.md) and [tool benchmark](REACT_TOOLS_BENCHMARK.md)
- [Annotation response recovery](annotation-response-recovery.md)

## Development and validation

- [Current R analysis workflow](../R_ANALYSIS_PROTOCOL.md)
- [Developer example inventory](../../tools/dev/examples/README.md)
- [Installed-runtime comparison contract](OFFLINE_COMPARISON_CONTRACT.md)
- [Environment records and the historical restoration recipe](ENVIRONMENT_RESTORE.md)
- [Browser tests](../../workbench/tests/TEST_PLAN.md)
- [Research protocols and milestones](../research/README.md)

## Historical material

[Implementation reports](reports/README.md) retain the observations and commits
from their original checks. [Archived design documents and translations](../archive/README.md)
provide historical context. Use current source and tests to establish present
behavior; a past report is evidence only for its recorded revision.
