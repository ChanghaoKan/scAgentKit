# scAgentKit

**English** · [简体中文](README.zh-CN.md)

A governed LLM assistant for foundational single-cell RNA-seq analysis.
From counts to an annotated Seurat object, scAgentKit makes QC, batch handling,
clustering and annotation decisions explicit: the model drafts with verifiable
evidence, the researcher reviews and approves, and the project records the result.

**In development.** Use the current `main` source below. Workflow checks do not
establish biological accuracy; formal evaluation is still pending.

## Quick start

Requires **macOS/Linux**, R ≥ 4.2, Seurat ≥ 5 and Python ≥ 3.9. Windows is unsupported.

```r
install.packages("remotes")
remotes::install_github("ChanghaoKan/agentomicsCore@v0.3.0", upgrade = "never")
remotes::install_github("ChanghaoKan/scAgentKit", upgrade = "never")
library(scAgentKit)
# Set your provider's API key in the R environment first.
sc_start("input.rds", "new-project",
  context = list(species = "human", tissue = "blood", research_goal = "Your question"),
  provider = "deepseek")
```

Confirm aggregate transfer once, then review three drafts: **analysis plan →
measured clustering → annotation**. Saving or adopting a draft never approves it.
Inputs can be RDS, 10x MEX or a sample table. Use `provider = "mock"` for an offline
software trial. [Installation and trial](docs/user/INSTALL.md) · [Input formats](docs/TENX_INPUT.md).

## What you can inspect

- Diagnostic QC and batch evidence, with explicit researcher-approved choices.
- Local ACT reference comparisons and read-only ReAct checks for uncertain annotations
  (`react = "auto"`; disable with `"off"`).
- Saved decisions, tool evidence, actual token/cost records and API-free annotation replay.
- An annotated Seurat object, marker tables, figures and project audit records.

Costs are recorded after calls; there is no monetary cap. Step/time limits apply.
Uncertain delivery is never automatically resent. Missing keys or failed model
requests leave rule/manual review available.

## Guides

| Task | Guide |
| --- | --- |
| Review, retrieve results and reopen | [Workflow](docs/user/WORKFLOW.md) |
| Understand annotation checks | [ReAct](docs/REACT.md) · [ACT](docs/ACT_LOCAL_REFERENCE.md) |
| Cancel, resume or set disk allowance | [Run controls](docs/user/TRIAL_CONTROLS.md) |
| Evaluate or replay annotations | [Evaluation and replay](docs/REACT_EVALUATION.md) |
| Run a complete example | [Examples](inst/examples/README.md) |
| Find methods and requirements | [Documentation](docs/README.md) |
| Contribute or inspect validation | [Developer index](docs/dev/README.md) |

Before 1.0, scientific implementation changes can invalidate ongoing projects;
preserve their original software environment. Advanced downstream analyses
(trajectory, communication, regulatory networks and condition comparisons) are
outside this workflow. [Methods and limitations](docs/SCIENTIFIC_METHODS_APPENDIX.md).

[NEWS](NEWS.md) · [License](LICENSE.md) · [Citation](CITATION.cff)
