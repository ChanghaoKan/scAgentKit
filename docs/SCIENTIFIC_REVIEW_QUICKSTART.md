# Scientific review: operator guide

Use the 0.8.0 workflow on the machine holding your data. [中文操作指南](RESEARCHER_PROTOCOL_ZH.md).
The [README](../README.md) gives installation, the pre-1.0 compatibility policy
and [limitations](../README.md#limitations). Historical v0.6.0 has its own
[protocol](RELEASE_060_PROTOCOL.md).

## 1. Know the three controls

| Control | What you do | What happens next |
| --- | --- | --- |
| Edit or adopt a candidate | Change the local draft, then Save | The page rebuilds the plan and its evidence for you to read. |
| Approve a scientific proposal | Read the whole current proposal; enter reviewer and reason | Approve and continue executes the approved local work until the next review. |
| Optional model request | Preview the exact content, approve sending it, then Request | A candidate appears for you to edit and save before scientific approval. |

Saving facts or a draft is separate from approval. Read the refreshed review
after each edit. The raw-count path pauses for initial strategy, measured
clustering and annotation.

## 2. Install and confirm the environment

Follow [README installation](../README.md#installation) and its offline check.
Confirm the package version and library path before starting your study. Use the
same package environment for R, Rscript and the local service. Supported
platforms are macOS/Linux; see [runtime requirements](LINUX_RUNTIME_SUPPORT.md).

## 3. Practise with the bundled example

In a new R session with scAgentKit loaded, run:

```r
source(system.file("examples", "three-gate-analysis.R", package="scAgentKit"))
tutorial <- three_gate_analysis(tempfile("scagentkit-training-"))
tutorial$receipt
```

Expect complete, 80 cells, three practice approvals and zero provider calls.
The example supplies its own practice choices. Then prepare a new directory
for your study and make the decisions below yourself.

## 4. Start with your input and sample information

For the browser, use a 10x MEX directory, a sample table or an RDS **file path**.
Counts must be finite nonnegative integers with unique gene/cell IDs. Confirm
the RNA counts layer covers every cell; prepare split layers explicitly before
entry. Formats and feature/metadata matching are in [10x input](TENX_INPUT.md).

Declare species, tissue and research goal. Map sample, donor, capture, condition
or batch roles only to verified metadata columns with a value for every cell;
omit unknown roles. Unspecified QC grouping stays pooled or unavailable.
For an RDS input:

```r
context <- list(species="human", tissue="Blood", research_goal="Study question")
service <- sc_start("input.rds", "new-review-project", context=context)
```

You will see an import summary and an unapproved plan. Check cell counts,
feature names and sample facts, then open the strategy review. The default is
manual, with no provider and zero model budget; model setup is in section 6.

## 5. Review the plan and measured clustering

### 5.1 Raw-count analysis

Read the per-group QC distributions, candidate retention and complete plan.
Check optional methods' prerequisites; revise an unsupported selected method
or leave it off. Save changes, read the refreshed review, then approve and
continue. You will next see computed PCs, the scanned resolution grid, cluster
tree, marker contrasts and sample composition.

Select an actually scanned resolution. Save any edit, read the new review and
approve again. Next, open the annotation worksheet. Calculations and plot
interpretation are in the [methods appendix](SCIENTIFIC_METHODS_APPENDIX.md).

### 5.2 Reuse an already processed Seurat object

Prepare genuine counts, a selected normalized layer, existing clusters and a
reason for reusing the previous processing. Use the explicit R entry:

```r
processed <- sc_run("processed.rds", "new-annotation-project", context=context,
  start_stage="processed", processed_reason="Reuse documented QC, normalization and clusters.",
  assay="RNA", counts_layer="counts", normalized_layer="data",
  cluster_column="seurat_clusters", provider=NULL, budget=0)
sc_open("new-annotation-project")
```

This reuses the supplied processing and clusters, prepares markers and stops
for annotation; to recompute clustering, start a raw-count project instead.
Continue with the [processed-object example](../inst/examples/server_processed.R)
and annotation review in section 9.

## 6. Optional model assistance

Before opening the page, initialize a **new** project in R with its provider,
model, generation settings and budget. These settings stay fixed for that
project. Supply its key through the actual execution process's environment.
`Rscript --vanilla` needs an inherited environment; it does not read `.Renviron`.
Follow [configuration and consent](UNIFIED_MODEL_REVIEW.md).

Preview the content and destination, approve that transfer, then explicitly
request the candidate. Inspect/adopt/edit it, Save, and separately approve the
scientific proposal. If a request's outcome is unclear, inspect its saved job
and usage record before requesting again. Use the R procedure in the linked
guide for an external-transfer stop not offered by the page.

## 7. Choose optional methods only when their inputs are ready

| Choice | Required preparation | Details |
| --- | --- | --- |
| Sample-consensus HVGs | At least 2 declared samples, each with at least 30 retained cells; set hvg_method=sample_consensus and hvg_column, Save and review | [HVG and diagnostics](SCIENTIFIC_METHODS_APPENDIX.md) |
| Harmony | A verified technical-batch column and a design meeting the supported checks; review the complete plan | [Harmony/PC](HARMONY_PC_REVIEW.md) |
| Doublet scoring | Appropriate droplet raw counts, declared capture units and an accepted runtime version | [Doublet prerequisites](DOUBLET_REVIEW.md) |
| Cell-cycle options | Declared species and a measured, sourced gene set; select keep/full/supported difference | [Cell-cycle review](CELL_CYCLE_REVIEW.md) |
| Ambient correction | Separate R API; SoupX needs a complete capture, matching raw/filtered counts, ≥20 extra droplets and named clusters; decontX needs explicit preliminary clusters | [Ambient inputs and versions](SCIENTIFIC_METHODS_APPENDIX.md#ambient-estimation-and-correction) |

Extra PC sensitivity, resampling, resolution extension, sample-consensus HVGs,
automatic QC draft preselection and cross-sample/mixed-lineage extensions are
initially off. Choose them explicitly for a new project. For ambient correction,
inspect the separate returned counts and start a new project if adopting them.

## 8. Open the page on a remote machine

Run on the machine holding the data, using the same R library/Rscript. Keep the
service on 127.0.0.1 and use your existing institution-approved SSH access to
forward its port. Follow [remote access](../workbench/README.md#remote-access)
for the commands and job setup. The page shows the saved project; next, resume
the review at its displayed stage.

## 9. Enter and approve annotations

Read each cluster's markers and any configured reference candidates. Fill all
rows with a label or Unknown, confidence, reason and supplied supporting markers.
Selecting a reference in an untouched row copies its label/citations; fill in
your interpretation. Bulk Unknown asks for a reason and preserves edited rows.
Save complete proposal, read all populations together, then approve annotation
and continue. You will see the completed result page.
[Reference setup](CM2_EVIDENCE_REVIEW.md) and [marker definitions](SCIENTIFIC_METHODS_APPENDIX.md#main-annotation-marker-pool)
provide the detailed procedures.

## 10. Optional child analysis and a new parent output

Start from a completed parent. Select the actual cluster IDs and inspect the
selected cells; the child currently needs at least 21 cells and its own new
directory. Review its new raw-count strategy and annotation. After completion,
review the target column and selected cells, then explicitly apply the labels
into a **new** parent RDS. Outside cells and child-QC exclusions are NA in the
new column. The original parent file stays in place. Child-of-child creation
and automatic merging of overlapping children are unsupported.

Context edits are offered only at the stopped annotation stages before
writeback; save an offered edit, read the regenerated proposal and approve it
again. Exact R calls, edit prerequisites and undo are in [child review](SUBCLUSTER_REVIEW.md)
and [context controls](PARAMETER_CONTEXT_CONTROLS.md).

## 11. Results, reopening and errors

After completion, inspect and retrieve the final object:

```r
project_dir <- "new-review-project"
saved <- sc_open(project_dir)
saved$view$output
result <- sc_result(project_dir)
sc_run_open(project_dir)
```

`sc_open()` shows saved results in R; `sc_run_open()` opens a read-only browser.
Before completion, use `sc_result(project_dir, stage="analysis")` for the saved
provisional object. To continue review, repeat the original `sc_start()` call
with the same input/options and project environment, omitting context to reuse
saved facts. See [project reuse limits](../README.md#limitations).

| What you see | Next action |
| --- | --- |
| awaiting_configuration | Complete the manual plan/annotation, or use the configured model procedure. |
| awaiting_review | Read the current proposal, Save edits, then approve. |
| A busy job or uncertain response | Inspect the saved job/receipt and wait for the worker before submitting again. |
| Input/layer mismatch or changed project environment | Check the input and recorded environment; use the original environment or a new project. |

For help, retain the package/OS versions, input type, displayed stage, exact
error and job/receipt. Remove private data and credentials from shared reports.
