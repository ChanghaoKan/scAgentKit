# Analysis workflow

The workflow has three approval points: the analysis plan, measured clustering
and annotation. Each approval records the reviewed decision before the next
computation. This guide covers the browser interface; see the
[R workflow](../R_ANALYSIS_PROTOCOL.md) for the equivalent R operations.

The Project workbench includes an interactive workflow map. Hover a step, focus
it with the keyboard or tap it to show how that step's proposal is formed,
its recorded source and evidence, and the researcher's decision. QC explains
local diagnostic candidates and the current saved rules. ReAct is marked as an
optional annotation-evidence path; a configured model alone is not evidence
that it ran. The detail panel distinguishes simulations and historical traces
and links to saved evidence. Exploring the map makes no scientific decision or
model request. Processed and child entries describe their own review scope.

## 1. Choose input and declare sample information

Choose a new project directory. For one 10x MEX directory, set its sample ID and
whether the matrix is raw or filtered:

```r
input <- "filtered_feature_bc_matrix"
project_dir <- "analysis"
context <- list(species="human", tissue="blood",
  research_goal="Describe cell populations in this study")
service <- sc_start(input, project_dir, context=context,
  sample_id="S1", matrix_kind="filtered")
```

Replace the example context with the study's species, tissue and research
question. Check the import summary, including the cells, feature names and
sample information, before reviewing the plan.

For multiple samples, use a table of paths and study facts instead:

```r
input <- data.frame(sample_id=c("S1", "S2"),
  path=c("counts/control", "counts/treated"),
  matrix_kind=c("filtered", "filtered"),
  donor=c("D1", "D2"), condition=c("control", "treated"))
service <- sc_start(input, project_dir, context=context)
```

Sample IDs must be unique and Gene Expression feature-ID sets must match.
The page displays cell IDs as `sample_id::barcode`. See
[input formats and metadata matching](../TENX_INPUT.md).

For an RDS containing raw counts or a Seurat object, pass the **file path**;
`sc_start()` does not take an in-memory Seurat object:

```r
input <- "a.rds"
service <- sc_start(input, project_dir, context=context)
```

Declare sample, donor, capture and condition roles using verified metadata
columns; leave unknown roles unspecified. The
[operator guide](../SCIENTIFIC_REVIEW_QUICKSTART.md) covers counts/layers and
explicit reuse of an already processed object.

## 2. Review the plan and measured clustering

<a id="gate-strategy"></a>

Check QC distributions, sample comparisons, proposed cell retention and the
complete analysis plan. **Use candidate in local draft** edits the draft.
Choose **Save**, read the updated plan and evidence, then **Approve and continue**.
The approved local analysis runs and the page pauses for measured clustering.

<a id="gate-clustering"></a>

Inspect the computed PC curve, cluster tree, marker contrasts and sample
composition. Choose a resolution included in the scan, save edits, read the
updated review and approve it. Next, the annotation worksheet becomes available.
If a selected method is not ready, revise the choice or satisfy its listed
requirements. [Method definitions](../SCIENTIFIC_METHODS_APPENDIX.md) explain
the plots and PC rule.

## 3. Review annotations

<a id="gate-annotation"></a>

Open the worksheet and inspect each cluster's markers, DotPlot and FeaturePlot
evidence, and reference candidates. The bundled
[ACT reference](../ACT_LOCAL_REFERENCE.md) is available offline and is matched
to the declared species and tissue; candidate records include their source
PMIDs. If no matching reference is available, use the marker evidence and
retain **Unknown** where appropriate.

Optional model assistance can propose a draft from saved marker evidence.
ACT comparisons and read-only
[ReAct checks](../REACT.md) can supply additional evidence. Cell Ontology IDs
come from a versioned exact-name and synonym dictionary; ambiguous or unmapped
labels receive no CLID.

Complete every row with a label or **Unknown**, confidence, a rationale and
supporting markers drawn from the supplied evidence. Selecting a reference
candidate in an untouched row can copy its label and citations; add your own
confidence and interpretation. The bulk Unknown action requires a reason and
preserves rows already edited.

Choose **Save complete proposal**, inspect all populations, then
**Approve annotation and continue**. Expect a completed project and result page.
For request/edit controls, see [annotation assistance](../dev/ANNOTATION_ASSISTANCE.md).

## 4. Retrieve results

After completion, use the same R package environment. The plot line below
requires UMAP to have been included in the plan:

```r
result <- sc_result(project_dir)
Seurat::DimPlot(result, reduction="umap", group.by="sc_annotation", label=TRUE)
table(result$sc_annotation)
sc_open(project_dir)$view$output
```

The project also contains marker tables, metadata, parameters, figures and
review records. Before annotation finishes,
`sc_result(project_dir, stage="analysis")` retrieves the saved provisional object.
Next, use the final Seurat object for your study's follow-up analyses.

## 5. Reopen a saved project

Reopening requires the current project format, including for `sc_open()` and
the read-only `sc_run_open()` viewer. A format mismatch is rejected before
project writes; use the original software environment or create a new project.
See the [format gate](../../workbench/README.md#project-format-and-reopening).
Use the original package environment and reopen the saved project directly:

```r
sc_start(project_dir=project_dir)
```

The protected input checkpoint and saved context supply the original data and
study facts. A changed file at the recorded original path is still rejected to
prevent input confusion. To inspect results, use `sc_open(project_dir)` in R or
`sc_run_open(project_dir)` for the read-only browser. See
[reopening and errors](../SCIENTIFIC_REVIEW_QUICKSTART.md#11-results-reopening-and-errors).


## Reopen, hand off and recover

The manual annotation worksheet is shown directly when markers are ready.
Download an unfinished worksheet before closing the tab, or import it in another
session opened on the same project, evidence and revision. This is draft data,
not an approval. Save the complete proposal and inspect its rebuilt evidence
before using **Approve and continue**. Saved corrections follow the same rule.

The status badge names the next task. Raw engine status, hashes and lifecycle
remain under **Snapshot fingerprints**. The current strategy decision precedes
optional comparisons; expand recommendations and parameter groups as needed.
Earlier completed review records are disclosed below the current task. Plan, measured clustering and annotation remain separate scientific decisions.

If a task stops, the recovery panel distinguishes saved progress from uncertain
model delivery and gives the appropriate explicit next action. See
[recovery controls](TRIAL_CONTROLS.md). A missing credential can be restored in the
existing project. A failed browser response never authorizes an automatic resend.

**Project storage and archiving** is independent of model suggestions. Completed
results include a researcher report and `audit.json`; the Seurat object's
`misc$scAgentKit` contains the same portable audit projection. These are summaries
of actual records, not a replacement project or biological validation.

For independent child analysis, create a separate directory and reopen with
`sc_start(project_dir="analysis", subcluster_workspace="analysis-children")`.
Select cells on **Cell scope**, then fill and review the child's annotation table
on **Review**. Applying completed labels creates a new parent-derived output;
it does not overwrite the parent. Nested child creation remains unsupported.
