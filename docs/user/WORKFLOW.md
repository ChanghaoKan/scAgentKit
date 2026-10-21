# Analysis workflow

The workflow has three approval points: the analysis plan, measured clustering
and annotation. Each approval records the reviewed decision before the next
computation. This guide covers the browser interface; see the
[R workflow](../R_ANALYSIS_PROTOCOL.md) for the equivalent R operations.

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

The first model draft uses markers. ACT comparisons and read-only
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
Use the original package environment, input and options. Repeat the relevant
entry call, omitting context to reuse the saved study facts:

```r
# For the single-directory example:
sc_start("filtered_feature_bc_matrix", project_dir,
  sample_id="S1", matrix_kind="filtered")
# For the sample-table example: sc_start(input, project_dir)
# For the RDS example: sc_start("a.rds", project_dir)
```

The page shows the saved stage. To inspect results without the original input
location, use `sc_open(project_dir)` in R or `sc_run_open(project_dir)` for the
read-only browser. See [reopening and errors](../SCIENTIFIC_REVIEW_QUICKSTART.md#11-results-reopening-and-errors).

