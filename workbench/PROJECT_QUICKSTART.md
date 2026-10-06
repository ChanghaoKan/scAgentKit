# Review your own Seurat project locally

The R package exports evidence and applies reviewed labels. The optional GUI
reviews local evidence. Python 3's standard library is sufficient; no matrix
upload, provider call or CDN is needed.

Use this checkout's package version: install it into a chosen local R library
with `R CMD INSTALL . --library=/path/to/library`, or use
`pkgload::load_all("/path/to/scAgentKit")` for a development session.

For an already processed Seurat v5 object:

```r
library(scAgentKit)
sc_project_export(seurat, "my-project", project_id = "study-A",
  assay = "RNA", counts_layer = "counts", normalized_layer = "data",
  cluster_column = "seurat_clusters", reduction = "umap", archive = TRUE)
```

This creates a new directory and sibling `my-project.zip`, refusing overwrite.
Directories and ZIPs can move to another local folder. Supply markers, database
candidates and model records explicitly; absent model records mean no model ran.

From this repository, start the GUI and open the localhost URL in a browser:

```sh
sh workbench/run-project.sh /absolute/path/to/my-project
# http://127.0.0.1:8768
```

**Import project** loads another evidence ZIP. The project selector separates
projects and their journals. UMAP and cluster scopes come from each actual export;
`reduction = NULL` explicitly permits reviewing without an embedding. Inspect a
cluster, record a label or `unknown`, and explain the decision. Workflow status
`accepted` records review, not biological truth. Undo appends a compensation event.

**Export project** produces portable evidence. **Export review journal** contains
only decisions and referenced scientific capsules. Import a journal into its
matching project; existing history must remain an identical prefix. A review
journal does not contain the full matrix or original model responses.

Validate and write new columns into a returned copy:

```r
check <- sc_review_validate(seurat, "review-journal.json", "my-project",
  columns = c(type = "review_type"))
stopifnot(check$valid)
reviewed <- sc_review_apply(seurat, "review-journal.json", "my-project",
  columns = c(type = "review_type"))
saveRDS(reviewed, "reviewed-new-object.rds") # a separate explicit destination
```

Writeback aligns by exact cell ID and requires the matching complete cell/feature
set, actual selected expression values and cluster membership. Reordering cells
and features is supported. Changed data needs a new project. All output columns
must be new. Original metadata, factors/NA, active identities, assays and
reductions remain unchanged.

Accepted labels yield `labeled`; accepted unknown yields `abstained`. A current
proposed/reviewed decision yields `deferred` with an NA label; no active decision
yields `unreviewed` with an NA label. Partial review is valid. Type/state/QC stay
separate dimensions.

For a counts-only matrix, explicitly prepare a copy first:

```r
prepared <- sc_project_prepare(counts)
sc_project_export(prepared, "prepared-project", project_id = "study-B", archive = TRUE)
```

Preparation records standard analysis parameters and applies no implicit QC
deletion. Counts and IDs are checked before Seurat can repair feature names.
Export requires genuine counts and exact layers covering every `colnames(object)`
cell. Join split layers or fix mismatched layers explicitly before export. A
single-object AgentSeurat wrapper is supported.

Optional `directed_clusters` exports the T/NK RNA panel only for explicitly
selected, applicable clusters. No other lineage gets that panel automatically.
Missing features stay missing. The GUI replays actual selected RNA measurements;
uncalibrated recommendations remain proposals. Without an exported panel, the
tool is unavailable. No full RDS is deserialized through the GUI.

See [PROJECT_SCHEMA.md](PROJECT_SCHEMA.md) for the file and journal contracts.
Legacy PBMC handoffs have no generic source identity and cannot write back.
