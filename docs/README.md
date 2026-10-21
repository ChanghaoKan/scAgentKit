# Documentation

The [user guide](user/README.md) is the starting point for downloading,
installing and using scAgentKit. Follow the
[workflow guide](user/WORKFLOW.md) from input through reviewed annotations.
The [repository README](../README.md) provides a short offline example. Guides
on this branch describe the current source; published-preview users should
follow the [matching manual](https://github.com/ChanghaoKan/scAgentKit/blob/v0.8.1/README.md).

## Analysis guides

| Guide | Contents |
| --- | --- |
| [Workflow](user/WORKFLOW.md) | Input, the three review steps, results and reopening |
| [Input formats](TENX_INPUT.md) | RDS, 10x MEX, sample tables and cell metadata |
| [Operator reference](SCIENTIFIC_REVIEW_QUICKSTART.md) | Study setup, optional methods and troubleshooting |
| [R analysis](R_ANALYSIS_PROTOCOL.md) | Review and run an analysis without the browser |
| [Examples](../inst/examples/README.md) | Offline trials, model-assisted analysis and multi-sample inputs |
| [Subcluster analysis](SUBCLUSTER_REVIEW.md) | Review a selected cell subset and return annotations to its parent |

## Methods and model assistance

| Reference | Contents |
| --- | --- |
| [Scientific methods](SCIENTIFIC_METHODS_APPENDIX.md) | Calculations, eligibility rules and interpretation limits |
| [ACT reference](ACT_LOCAL_REFERENCE.md) | Reference matching, source provenance and attribution |
| [ReAct](REACT.md) | Model-assisted inspection of annotation evidence |
| [Evaluation and replay](REACT_EVALUATION.md) | Inspect recorded annotations and replay them without API calls |
| [Model usage and costs](MODEL_BUDGET.md) | Token records, cost accounting and uncertain requests |
| [Gene links](GENE_LOOKUPS.md) | External gene-information links available in the workbench |

## Operation and reproducibility

- [Runtime requirements](LINUX_RUNTIME_SUPPORT.md): operating systems and optional scientific dependencies.
- [Run controls](user/TRIAL_CONTROLS.md): cancellation, continuation and disk allowance.
- [Resource controls](user/RESOURCE_CONTROLS.md): request limits, storage and project backups.
- [Workbench operation](../workbench/README.md): service startup and remote access.

Keep the source commit, dependency environment and input provenance with each
analysis. Preserve the complete project directory to retain its data, decisions
and execution records. Use [CITATION.cff](../CITATION.cff) for the software citation.

<details>
<summary>For contributors and research evaluation</summary>

The [developer index](dev/README.md) separates implementation references,
validation procedures and historical records. The [research index](research/README.md)
lists study protocols and planned evaluations. [NEWS](../NEWS.md) describes
version changes. Software test results and research-performance evaluation
answer different questions; consult each report's methods, source revision and
stated scope before using it as evidence.

</details>
