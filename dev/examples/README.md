# Development examples

These scripts exercise individual parts of the project engine. They are
repository resources and are excluded from R package archives. For a first
analysis, use the [installed tutorials](../../inst/examples/README.md).

Install the current checkout in the R library used by `Rscript`, then run
drivers from the repository root. Several scripts load shared helpers from
`dev/examples`; when sourcing them elsewhere, set
`options(scAgentKit.dev_examples = "/absolute/path/to/scAgentKit/dev/examples")`.

## Synthetic review drivers

The command-line drivers below create synthetic data or inspect projects they
have created. Their approval commands record decisions for those fixtures.
They do not establish suitable analysis settings or biological accuracy.

| Script | Entry point | Focus |
| --- | --- | --- |
| [analysis-strategy.R](analysis-strategy.R) | `strategy_example_main()` | Analysis-plan review, revision and continuation; shared helper functions for several other drivers |
| [qc-review.R](qc-review.R) | `qc_review_main()` | QC-rule review and cell retention |
| [mad-review.R](mad-review.R) | `mad_example_main()` | Grouped MAD evidence and QC-rule combinations |
| [cell-cycle-review.R](cell-cycle-review.R) | `cycle_example_main()` | Cell-cycle scoring and regression choices |
| [harmony-pc-review.R](harmony-pc-review.R) | `harmony_pc_example_main()` | Batch adjustment and PC-selection review |
| [doublet-review.R](doublet-review.R) | `doublet_example_main()` | The supported doublet-scoring adapter on synthetic counts |
| [annotation-review.R](annotation-review.R) | `annotation_review_main()` | Annotation review of a processed synthetic object |
| [cm2-evidence-review.R](cm2-evidence-review.R) | `cm2_evidence_main()` | Reference comparison and annotation-history evidence |
| [parameter-context-demo.R](parameter-context-demo.R) | `parameter_context_demo_main()` | Parameter review and child-project context |
| [unified-model-review.R](unified-model-review.R) | `unified_review_main()` | Model preview, simulated requests, draft adoption and scientific review |
| [first-run.R](first-run.R) | `first_run_main()` | Saved review snapshots and separate decision/resume commands |
| [server_first.R](server_first.R) | `server_demo_main()` | Stepwise execution across separate R processes |
| [server_processed.R](server_processed.R) | `server_processed_main()` | Reuse of a synthetic processed object or a caller-supplied local RDS |

The `*_main()` functions run when their files are invoked with `Rscript`.
Sourcing defines helpers and checks package requirements without starting the
command-line workflow. Read the usage comment in each file for its modes. For
example, from the repository root:

```sh
Rscript --vanilla dev/examples/analysis-strategy.R /path/to/new-project demo
Rscript --vanilla dev/examples/analysis-strategy.R /path/to/new-project inspect
```

Inspect the result before issuing a decision or continuation command.
Harmony and doublet drivers require the supported optional dependencies
described in the [runtime requirements](../../docs/LINUX_RUNTIME_SUPPORT.md).
The unified-model command-line driver uses simulation; its sourced functions
can accept an explicitly configured external provider.

## Public-data workflow

[`researcher-pbmc.R`](researcher-pbmc.R) defines `researcher_pbmc_start(...)`,
`researcher_pbmc_inspect(...)`, `researcher_pbmc_decide(...)` and
`researcher_pbmc_resume(...)`. It uses `pbmc_small`, separate manual decisions
and mock responses. Sourcing the file defines these functions without starting
an analysis.

For the complete scripted three-review fixture, call the installed tutorial
directly, as documented in the [installed example guide](../../inst/examples/README.md):

```r
source(system.file("examples", "three-gate-analysis.R",
                   package = "scAgentKit", mustWork = TRUE))
trial <- three_gate_analysis(tempfile("scagentkit-fixture-"))
```

This tutorial records fixture approvals and makes no external model requests.

## Scheduler template

[`slurm_sc_run.sh`](slurm_sc_run.sh) is a site-specific submission template.
It requires a project directory and a reviewed R driver, and executes that
driver with `Rscript`; it does not submit a job itself. Adapt its resource
requests and environment activation to the cluster before use.
