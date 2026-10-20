# Reviewed workflow

### 1. Choose input and declare sample facts

Choose a new project directory. For one 10x MEX directory, set its sample ID and
whether the matrix is raw or filtered:

```r
input <- "filtered_feature_bc_matrix"
project_dir <- "analysis"
context <- list(species="human", tissue="Actual tissue",
  research_goal="Actual study question")
service <- sc_start(input, project_dir, context=context,
  sample_id="S1", matrix_kind="filtered")
```

You will see the import summary and an unapproved plan. Check the imported
cells, feature names and sample information, then move to step 2.

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

Declare verified sample/donor/capture/condition roles using existing metadata
columns. Leave unknown roles unspecified. The
[operator guide](../SCIENTIFIC_REVIEW_QUICKSTART.md) covers counts/layers and
explicit reuse of an already processed object.

### 2. Review the plan, then measured clustering

<a id="gate-strategy"></a>

Check QC distributions, sample comparisons, proposed cell retention and the
complete analysis plan. **Use candidate in local draft** edits the draft.
Choose **Save**, read the updated plan and evidence, then **Approve and continue**.
The approved local analysis runs and the page pauses for measured clustering.

<a id="gate-clustering"></a>

Inspect the computed PC curve, cluster tree, marker contrasts and sample
composition. Choose an **actually scanned resolution**, save edits, read the
updated review and approve it. Next, the annotation worksheet becomes available.
If a selected method is not ready, revise the choice or satisfy its listed
requirements. [Method definitions](../SCIENTIFIC_METHODS_APPENDIX.md) explain
the plots and PC rule.

### 3. Review annotations

<a id="gate-annotation"></a>

Open the worksheet and read each cluster's markers, DotPlot/FeaturePlot evidence
and reference candidates. This build loads its pinned ACT snapshot offline for new modern projects,
with exact declared species/tissue and original PMIDs. [Source and usage](../ACT_LOCAL_REFERENCE.md). Missing or unmatched ACT data is visibly
unavailable and leaves marker/Unknown review usable. The first model draft is
marker-only; ACT comparison and bounded read-only ReAct checks can follow; see the ReAct guide.
Cell Ontology IDs use the pinned exact-name/synonym dictionary; ambiguous or
unmapped labels retain a missing CLID.
Fill every row with a label or **Unknown**, confidence, a reason and supplied
supporting markers. In an untouched row, selecting a reference candidate can
copy its label and citations; fill in your own confidence and interpretation.
The bulk Unknown action asks for a reason and preserves edited rows.

Choose **Save complete proposal**, inspect all populations, then
**Approve annotation and continue**. Expect a completed project and result page.
For request/edit controls, see [annotation assistance](../dev/ANNOTATION_ASSISTANCE.md).

### 4. Retrieve results

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

### 5. Reopen a saved project

Use its original package environment, input and options. Repeat the relevant
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

