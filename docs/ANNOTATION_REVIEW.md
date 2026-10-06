# One project, QC and annotation review

`sc_run()` saves the analysis on the machine holding the data. The same project
can be reviewed from R or the optional loopback workbench: inspect QC, approve
its exact impact, explicitly resume analysis, inspect annotation evidence, retain
or correct labels, approve, then explicitly resume to a new Seurat object. The
review process saves decisions and exits; it does not need an R process waiting
for a browser. No manual RDS transfer or ZIP round trip is required.

The unified `sc_run_review()` operation records a review of an inspected
snapshot. It does not run analysis, request a model response, or execute supplied
R text. Use `sc_run_resume()` separately on the analysis machine or in your
scheduled job. Existing headless QC functions remain available; see
[QC-review.md](QC-review.md) and [SERVER_FIRST.md](SERVER_FIRST.md) for input,
context and provider contracts.

## Inspect and decide from R

After QC approval and `sc_run_resume()`, a configured mock/model or a supplied
manual proposal can leave the project at `awaiting_review` for annotation:

```r
current <- sc_run_inspect(project_dir)
stopifnot(current$status == "awaiting_review",
          current$review_node$kind == "annotation")
review <- current$annotation_review
review$details$source                 # saved model/mock/manual provenance
review$details$output_columns         # fresh label, confidence, rationale columns
review$details$annotations[[1]]       # exact scope, suggestion and saved evidence
review$details$limitations

# Bind every action to this inspected snapshot. Do not fetch a newer unseen
# proposal inside a decision function.
submit <- function(action, reason, proposal = NULL, decision_id = NULL) {
  node <- current$review_node
  args <- c(list(project_dir = project_dir, action = action,
                 reviewer = "your analyst ID", reason = reason),
            node[c("kind", "project_id", "input_hash", "proposal_hash",
                   "review_hash", "expected_revision")])
  if (!is.null(proposal)) args$proposal <- proposal
  if (!is.null(decision_id)) args$decision_id <- decision_id
  do.call(sc_run_review, args)
}

# Retain the inspected proposal only after reviewing its evidence and limits.
current <- submit("approve", "Record why these particular labels are acceptable.")
result <- sc_run_resume(project_dir)
stopifnot(result$status == "complete")
final <- readRDS(result$output$seurat)
```

An annotation row contains `clusterId`, `label`, `confidence`, `rationale` and
`markers`. Every saved evidence cluster must occur exactly once, using literal
IDs. Supported confidence strings are `low`, `medium`, `high`: these are
qualitative judgments, **not calibrated probabilities**. A known label requires
at least one citation from that cluster's supplied marker evidence; a citation
is checked for availability, not independently proven sufficient for the label.
`Unknown` or `unannotated` can have an empty marker list.

To make an uncertain label `Unknown`, replace a complete typed proposal, then
inspect its new snapshot before approving it:

```r
current <- sc_run_inspect(project_dir)  # the pending annotation node
replacement <- current$annotation_review$details$canonical_proposal
replacement$annotations[[1]]$label <- "Unknown"
replacement$annotations[[1]]$confidence <- "low"
replacement$annotations[[1]]$markers <- list()
replacement$annotations[[1]]$rationale <-
  "The supplied evidence does not justify a more specific identity."
current <- submit("revise", "Explain the correction and its evidential limits.",
                  proposal = replacement)

# Inspect the replacement, its source and scope. This fresh current snapshot
# has new proposal/review fingerprints; the preceding snapshot is now stale.
current$annotation_review$details$annotations
current <- submit("approve", "Reviewed the replacement; retain this uncertainty.")
result <- sc_run_resume(project_dir)
```

A coarser label uses the same replacement operation. Retain only actual supplied
marker citations supporting that label, set an appropriate qualitative
confidence, and explain what subtype distinctions remain unsupported. Other
clusters stay in the complete proposal. The reviewer reason belongs to the
decision history; each row's rationale is also written to the output object.

`submit("reject", "Explain why the proposal should not be applied.")` saves a
rejection and stops progression. It does not ask a model for a replacement. At a
rejected annotation node, a deliberate `revise` operation can supply a new typed
proposal for fresh review. When no proposal exists yet, `sc_run_review()` cannot
approve or revise an invented snapshot: supply an initial manual proposal with
`sc_run_propose()` as shown below, or explicitly configure a provider through the
existing run contract.

## Existing processed Seurat, no external request

This example uses an already processed object and an explicit manual `Unknown`
proposal. Change the context, selected layers, cluster column and provenance to
the verified values for the study. `start_stage="processed"` reuses its
normalization, clusters and available reductions; it still computes the saved
marker evidence needed for annotation. It does not redo QC or base analysis.

```r
library(scAgentKit)
processed <- readRDS("/data/verified-processed-seurat.rds")
project_dir <- "/durable/path/to/fresh-annotation-project"
context <- list(species = "human", tissue = "declare the actual tissue",
  columns = list(sample = "sample_id", capture = "capture_id",
                 condition = "condition"),
  notes = "State study design, expected populations and evidence limitations.")
sc_run(processed, project_dir, context = context, start_stage = "processed",
  processed_reason = "State the verified prior QC, normalization and clustering pipeline.",
  assay = "RNA", counts_layer = "counts", normalized_layer = "data",
  cluster_column = "seurat_clusters", annotation_column = "reviewed_identity",
  provider = NULL, budget = 0, review = list(allow_external = FALSE))

current <- sc_run_inspect(project_dir)
stopifnot(current$status == "awaiting_configuration",
          current$stage == "annotation_propose")
manual <- list(schema = "scagentkit.annotation.v1",
  annotations = lapply(current$evidence$clusters, function(cluster)
    list(clusterId = cluster$clusterId, label = "Unknown", confidence = "low",
         rationale = "Initial manual placeholder pending study-specific review.",
         markers = list())))
sc_run_propose(project_dir, manual, reviewer = "your analyst ID",
               reason = "Supply a manual proposal without external transmission.")
current <- sc_run_inspect(project_dir)
# Inspect/correct/approve with submit above; then explicitly sc_run_resume().
```

Omit context column roles that do not exist; do not guess a donor from capture
or a technical batch from a biological condition. Choose a new annotation
column: all three output columns must be absent. Previous labels and the source
object are preserved. A matrix cannot claim the processed entry point; provide
the actual Seurat object with an explicit normalized layer and cluster column.

The included [annotation-review.R](../inst/examples/annotation-review.R) supplies
a small self-contained synthetic processed object and a fresh-process CLI.
It demonstrates an initial manual `Unknown`, correction to a toy program label,
approval, output and optional undo with no provider, secret or API charge:

```sh
Rscript --vanilla inst/examples/annotation-review.R /durable/path/to/toy run
Rscript --vanilla inst/examples/annotation-review.R /durable/path/to/toy inspect
Rscript --vanilla inst/examples/annotation-review.R /durable/path/to/toy revise
Rscript --vanilla inst/examples/annotation-review.R /durable/path/to/toy inspect
Rscript --vanilla inst/examples/annotation-review.R /durable/path/to/toy approve
Rscript --vanilla inst/examples/annotation-review.R /durable/path/to/toy resume
Rscript --vanilla inst/examples/annotation-review.R /durable/path/to/toy output
```

Its fixed revision and reason are for the synthetic mechanism example. Use the
explicit R decisions above for a study; the script does not assign toy labels to
an arbitrary local RDS. `inspect` saves the displayed snapshot; the subsequent
action uses those exact identities, so a changed project requires another
inspection. Install the same package version in every process used for a saved
project, including its optional workbench.

## What the evidence means

Each annotation row displays the saved cluster's exact cells, proposal,
supporting citations and supplied differential-marker statistics. Where
recorded, `avgLog2FC`, `pct1`, `pct2` and `pAdj` show saved fold change, within/
outside-cluster detection fractions and adjusted p-values from that test. These
are limited aggregate evidence: absence from a top-marker list does **not** mean
absent expression. This screen performs no new per-cell expression assessment or
independent negative-expression/counterevidence test.

An optional local reference is shown independently with its saved provenance,
candidate matches and overlap score. A score is not a calibrated probability.
When no reference was supplied, the screen says `not_supplied`; it does not
invent database support, counterevidence, a tissue-specific authority or a
biological ground truth. The model's evidence branch and any supplied local
reference remain separate suggestions for an analyst to assess.

Source metadata comes from the saved proposal/response artifacts. A configured
model name alone does not prove an API call. A manual replacement is recorded as
manual, while any earlier mock/model response remains historical and may differ
from the current proposal. Replaying or observing a previously saved response
does not constitute a new model run. This example uses **manual proposals only**;
it makes zero model/API requests and costs zero.

## Unified optional workbench

From this checkout, on the machine with the project and installed package:

```sh
python3 workbench/server.py --run-project /absolute/path/to/project --port 8772
# For a private R package library, add --r-library /path/to/R-library.
# Colon-separated R library paths are supported where R uses that separator.
```

Open `http://127.0.0.1:8772/review`. The same route shows the current QC or
annotation node and updates when the operator explicitly resumes the run in R.
Choose a free port. On a server use an already authorized SSH connection to
forward the loopback port; no public listener or firewall change is required.
The server binds to loopback and passes allowlisted typed JSON through its fixed
R bridge. Project, input, scope, evidence, proposal and review fingerprints are
validated under the same R lock as headless decisions. A stale tab or a foreign
project request cannot silently replace the current review.

Editing a label is a revision first. Saving the replacement creates a fresh
review snapshot; inspect it before approval. Retaining a suggestion, setting a
coarser label or `Unknown`, rejecting, and recording a reason use the same R
authority. A duplicate decision is idempotent and cannot apply annotations twice.
After approval, explicitly call `sc_run_resume(project_dir)` in R, then refresh
the page to see the completion and output paths. The browser does not configure
providers, run computation or expose a resume endpoint.

This live-project route approves coordinator nodes. The separate completed
annotation `bundle/` workbench and `sc_review_validate()` / `sc_review_apply()`
remain the explicit route for a portable refinement journal; that older bundle
journal is not silently imported as a coordinator approval.

## Undo and fresh annotation review

Only an **executed** current annotation approval can be undone. QC and earlier
base computation are not undone. Inspect the completed project, verify
`review_node$can_undo`, and use its exact decision ID and snapshot:

```r
current <- sc_run_inspect(project_dir)
stopifnot(current$review_node$can_undo)
current <- submit("undo", "Record why executed labels need another review.",
                  decision_id = current$review_node$decision_id)
# Old convenience output/bundle are archived under versions/; immutable
# checkpoints and approval/undo history remain. New computation is not run.
manual <- current$annotation_review$details$canonical_proposal
manual$annotations[[1]]$label <- "Unknown"
manual$annotations[[1]]$confidence <- "low"
manual$annotations[[1]]$markers <- list()
manual$annotations[[1]]$rationale <- "Reopened review retains unresolved identity."
current <- submit("revise", "Provide a fresh proposal after the audited undo.",
                  proposal = manual)
# Inspect this fresh snapshot, approve it, then explicitly resume again.
```

The completed decision cannot be approved again after undo. The current output
path becomes valid again only after a new approved annotation has been resumed
and finalized; previous versions are history, not the current final object.
The synthetic CLI's optional sequence is `inspect → undo → inspect → renew →
inspect → approve → resume → output`. `renew` submits fresh manual `Unknown`
labels for the toy's reopened node.

## Scope

This increment joins the existing QC and annotation review nodes through one
headless authority and a loopback interface. It supports complete typed label
replacement, exact-snapshot decisions, audit reasons and the existing annotation
undo route. It does not calibrate model confidence, discover unsupported
biological identities, add expression/counterevidence assays, select an optimal
QC threshold, or validate arbitrary studies scientifically. Shared-filesystem,
scheduler and intended HPC behavior require actual environment-specific tests;
the optional interface alone does not establish them. Dataset, model and browser
acceptance evidence belongs to the delivery report, with mock/manual/history
clearly distinguished from actual new model requests.
