# Scientific review: operator guide

Use 0.8.0 on the data machine. [中文操作指南](RESEARCHER_PROTOCOL_ZH.md).
See [README](../README.md) for installation, pre-1.0 policy and [limitations](../README.md#limitations);
use the [historical protocol](dev/RELEASE_060_PROTOCOL.md) for v0.6.0.

## Model setup in this source build

Configure provider/model, an explicit USD cap and transfer consent directly in
`sc_start()` before opening a new project; follow the [README entry](../README.md#analysis-protocol)
and installed `full-llm-workflow.R`. Existing environment keys only; missing keys
leave a manual workflow. Without project-scope consent, each exact payload needs
separate approval. Draft adoption/Save never approves science. Standard
DeepSeek Flash has a USD1.00 default cap after real-provider calibration;
an explicit `budget=0` still blocks paid requests, and
[data/budget consent and measured limits](MODEL_BUDGET.md) still apply.

New eligible drafts use conservative AND3 QC only when all required group metrics
are available; otherwise keep-all stays explicit. Cell-cycle scoring is attempted
only with eligible species/genes; automatic doublet diagnostics flag eligible
called-cell/capture cohorts and leave other inputs unassessed. Verify saved reasons
for every choice. A condition is not a technical batch, and Harmony design guards
still apply. Measured resolution choices must come from the actual scan grid.

ACT is the default local reference; see [input and provenance](ACT_LOCAL_REFERENCE.md).
No ACT file is bundled or automatically downloaded. Missing/unmatched records have
an explicit notice. Marker-only annotation precedes reference comparison; at most
one guided difference request is allowed. Inspect actual positive marker citations
and immutable PNG evidence. Exact CL mapping may remain missing. Human edits survive
candidate adoption and each whole proposal still requires your approval.

## 1. Know the three controls

| Control | What you do | What happens next |
| --- | --- | --- |
| Edit or adopt a candidate | Edit locally, then Save | Read the rebuilt plan/evidence. |
| Approve a scientific proposal | Read the current proposal; enter reviewer/reason | Approve and continue runs local work to the next review. |
| Optional model request | Preview, approve sending, then Request | Edit/Save the candidate before scientific approval. |

Saving facts/drafts is separate from approval. Read each refreshed review.
Raw counts pause at strategy, measured clustering and annotation.

## 2. Install and confirm the environment

Follow [installation and offline check](../README.md#installation). Verify version/library path.
Use the same environment for R, Rscript and the service on macOS/Linux; see
[runtime requirements](LINUX_RUNTIME_SUPPORT.md).

## 3. Practise with the bundled example

In a fresh session with scAgentKit loaded:

```r
source(system.file("examples", "three-gate-analysis.R", package="scAgentKit"))
tutorial <- three_gate_analysis(tempfile("scagentkit-training-"))
tutorial$receipt
```

Expect complete, 80 cells, three practice approvals and zero provider calls.
The example supplies practice choices; make your study decisions in a new directory.

## 4. Start with your input and sample information

Use a 10x MEX directory, sample table or RDS **file path**. Counts need finite
nonnegative integers and unique gene/cell IDs. The RNA counts layer must cover
all cells. Eligible same-assay split count layers are joined only after exact coverage/count checks; ambiguous layers remain blocked. See [formats/matching](TENX_INPUT.md).

Declare species/tissue/research goal. Map sample/donor/capture/condition/batch
only to verified columns complete for every cell; omit unknown roles.
Review the metadata-role draft: one safe candidate may prefill a role; multiple candidates require your choice. Missing group facts remain explicitly unassessed. For RDS:

```r
context <- list(species="human", tissue="Blood", research_goal="Study question")
service <- sc_start("input.rds", "new-review-project", context=context)
```

Check the import summary and unapproved plan: cells, features and sample facts.
Continue to strategy review. DeepSeek Flash defaults to a USD1.00 cap; choose provider="manual" for local-only review, or see section 6 for model setup.

## 5. Review the plan and measured clustering

### 5.1 Raw-count analysis

Read grouped QC, candidate retention and the whole plan. Revise unsupported
selected methods or leave them off. Save, read and approve/continue. Next: computed
PCs, scanned resolutions, cluster tree, markers and sample composition.

Choose a scanned resolution; Save, read and approve again. Next: annotation.
Plot interpretation is in the [methods appendix](SCIENTIFIC_METHODS_APPENDIX.md).

### 5.2 Reuse an already processed Seurat object

Prepare genuine counts, the normalized layer, clusters and a reuse reason:

```r
processed <- sc_run("processed.rds", "new-annotation-project", context=context,
  start_stage="processed", processed_reason="Reuse documented QC, normalization and clusters.",
  assay="RNA", counts_layer="counts", normalized_layer="data",
  cluster_column="seurat_clusters", provider=NULL, budget=0)
sc_open("new-annotation-project")
```

This reuses processing/clusters, prepares markers and stops for annotation.
Reclustering needs a raw-count project. Continue with the [example](../dev/examples/server_processed.R)
and section 9.

## 6. Optional model assistance

Configure a **new** project directly with sc_start(provider=..., budget=..., review=...)
before opening the page. The saved provider/model/settings/budget stay fixed. Supply the key in the execution environment;
`Rscript --vanilla` inherits it without reading `.Renviron`.
Follow [configuration/consent](dev/UNIFIED_MODEL_REVIEW.md).

Use creation-time project consent only after inspecting its aggregate categories and cap; eligible drafts can then be requested automatically once per evidence snapshot. Without that scope, preview content/destination, approve the exact transfer, then Request. Edit/adopt, Save and separately approve science. For unclear outcomes, inspect saved job/usage
before another request. Use the linked R procedure for external-transfer stops
not offered by the page.

If a configured suggestion fails (including missing key, invalid JSON or budget
stop), its local rule draft and reason are saved without approval or retry.
Complete suitable grouped MAD evidence selects conservative AND3; incomplete
evidence retains keep-all and explicitly unassessed QC. Saved human edits remain
in force; inspect the effective draft. A valid model annotation is not automatically
changed to Unknown. An analyst may make that separate, recorded revision.

## 7. Choose optional methods only when their inputs are ready

| Choice | Required preparation | Details |
| --- | --- | --- |
| Sample-consensus HVGs | ≥2 declared samples, each ≥30 retained cells; set hvg_method=sample_consensus and hvg_column; Save/review | [HVG and diagnostics](SCIENTIFIC_METHODS_APPENDIX.md) |
| Harmony | Verified technical batch, supported design, whole-plan review | [Harmony/PC](dev/HARMONY_PC_REVIEW.md) |
| Doublet scoring | Suitable droplet counts, declared captures, accepted runtime | [Doublet prerequisites](dev/DOUBLET_REVIEW.md) |
| Cell-cycle options | Species, measured/sourced gene set; keep/full/supported difference | [Cell-cycle review](dev/CELL_CYCLE_REVIEW.md) |
| Ambient correction | Separate R API: SoupX needs complete capture, matching raw/filtered counts, ≥20 extra droplets, named clusters; decontX needs preliminary clusters | [Ambient inputs and versions](SCIENTIFIC_METHODS_APPENDIX.md#ambient-estimation-and-correction) |

Extra PC sensitivity, resampling, resolution extension, sample-consensus HVGs,
experimental OR draft comparison and cross-sample/mixed-lineage extensions start off; select
them for a new project. Inspect ambient-corrected counts separately; adopt in a new project.

## 8. Open the page on a remote machine

Use the data machine and same R library/Rscript. Bind 127.0.0.1; forward its
port with existing institution-approved SSH access. See [commands/job setup](../workbench/README.md#remote-access).
The page shows the saved stage; continue its review.

## 9. Enter and approve annotations

Read markers/reference candidates. Fill all rows: label/Unknown, confidence,
reason, supplied markers. Reference selection copies label/citations into an
untouched row; add interpretation. Bulk Unknown needs a reason and preserves edits.
Save complete proposal, inspect all populations, approve/continue. Next: results.
[ACT reference setup](ACT_LOCAL_REFERENCE.md) and [marker definitions](SCIENTIFIC_METHODS_APPENDIX.md#main-annotation-marker-pool)
provide the detailed procedures.

## 10. Optional child analysis and a new parent output

From a completed parent, select actual cluster IDs and inspect cells. A child
needs ≥21 cells and a new directory. Review its raw-count strategy/annotation.
After completion, review the target column/cells and apply to a **new** parent RDS;
outside/QC-excluded cells are NA. Keep the original parent. Child-of-child and
automatic overlapping-child merges are unsupported.

Context edits require a stopped annotation stage before writeback. Save, read
the regenerated proposal and reapprove. See [calls/undo](SUBCLUSTER_REVIEW.md)
and [editable fields](dev/PARAMETER_CONTEXT_CONTROLS.md).

## 11. Results, reopening and errors

After completion, inspect and retrieve the final object:

```r
project_dir <- "new-review-project"
saved <- sc_open(project_dir)
saved$view$output
result <- sc_result(project_dir)
sc_run_open(project_dir)
```

`sc_open()` displays in R; `sc_run_open()` opens a read-only page. Before completion,
use `sc_result(project_dir, stage="analysis")` for the provisional object. Resume
review with the same sc_start input/options/environment; omit context for saved
facts. See [reuse limits](../README.md#limitations).

| What you see | Next action |
| --- | --- |
| awaiting_configuration | Complete the manual plan/annotation, or use the configured model procedure. |
| awaiting_review | Read the current proposal, Save edits, then approve. |
| A busy job or uncertain response | Inspect the saved job/receipt and wait for the worker before submitting again. |
| Input/layer mismatch or changed project environment | Check the input and recorded environment; use the original environment or a new project. |

For help, record versions, input type, stage, exact error and job/receipt.
Remove private data/credentials before sharing.
