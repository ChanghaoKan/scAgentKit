# Installed examples

These scripts are included in the R package. Use the offline tutorial first,
then choose an entry helper for your own data. Sourcing a script defines its
functions; it does not start an analysis. `subcluster-review.R` also loads the
package and checks that the required functions are available.

## Offline tutorial

This example uses SeuratObject's public `pbmc_small` dataset, runs the three
review steps with scripted approvals, and assigns `Unknown` labels. It makes
no external model requests.

```r
library(scAgentKit)
source(system.file("examples", "three-gate-analysis.R",
                   package = "scAgentKit", mustWork = TRUE))
project_dir <- tempfile("scagentkit-example-")
example <- three_gate_analysis(project_dir)
example$receipt
example$result
```

The receipt records completion, 80 cells, three approvals and zero provider
calls. These checks demonstrate software behavior. The scripted choices and
approvals are specific to this dataset; research analyses require the
researcher's own review.

## Available scripts

| Script | Entry point | Purpose |
| --- | --- | --- |
| [three-gate-analysis.R](three-gate-analysis.R) | `three_gate_analysis(project_dir)` | Complete offline tutorial; returns the result, project and receipt |
| [simple-analysis.R](simple-analysis.R) | `simple_analysis_after(project_dir)` | Installation check using the same tutorial; returns the Seurat object |
| [react-three-gate-mock.R](react-three-gate-mock.R) | `react_three_gate_mock(project_dir, input_path)` | Starts a local workbench, exercises mock drafts and ReAct replay, then stops its service |
| [full-llm-workflow.R](full-llm-workflow.R) | `full_llm_start(...)` | Starts model-assisted review after the caller supplies provider settings and confirms the data-transfer scope |
| [tenx-multisample.R](tenx-multisample.R) | `tenx_multisample_start(...)` | Opens caller-supplied 10x MEX samples and joins cell metadata by sample ID and barcode |
| [subcluster-review.R](subcluster-review.R) | `subcluster_example_scope(...)` and related helpers | Reviews a subset of a completed parent project, with separate creation, approval, application and undo operations |

Both offline tutorials require a new project path. The ReAct mock example also
requires an input path that does not already exist. The model-assisted helper
uses credentials from the configured provider's environment variable; it does
not create or store credentials. Its analysis decisions remain separate from
permission to send data.

`subcluster-review.R` also supports command-line operation:
`Rscript --vanilla subcluster-review.R PARENT CHILD MODE [CLUSTER_IDS...]`.
Its source lists the modes and the order in which to inspect and approve them.

Repository-only diagnostic and historical drivers are listed in
[`tools/dev/examples`](../../tools/dev/examples/README.md).
