\name{sc_analyze}
\alias{sc_analyze}
\alias{sc_open}
\alias{sc_review}
\alias{sc_result}
\title{Start, review and read a resumable single-cell analysis}
\usage{
sc_analyze(input, project_dir, context, plan = NULL, provider = NULL,
  chat_fn = NULL, review = list(allow_external = FALSE),
  sample_id = NULL, matrix_kind = NULL, cell_metadata = NULL,
  feature_key = c("name", "id"), doublet = c("auto", "off", "flag", "remove"), ...)
sc_open(project_dir)
sc_review(project,
  action = c("show", "revise", "approve", "reject", "continue", "request"),
  reviewer = NULL, reason = NULL, plan = NULL, annotations = NULL,
  continue = FALSE, chat_fn = NULL)
sc_result(project, stage = c("final", "analysis"))
}
\arguments{
\item{input}{Named raw counts matrix, Seurat object, local RDS path, 10x MEX directory, or sample table data.frame/CSV/TSV.}
\item{sample_id,matrix_kind}{For one 10x MEX directory, explicit sample ID and raw/filtered declaration. Sample tables instead require sample_id, path, matrix_kind columns. Optional donor/condition/batch/capture/treatment/qc_group/group columns declare those metadata roles. Filtered is a user declaration, not independent evidence of empty-droplet processing.}
\item{cell_metadata}{Optional data.frame/CSV/TSV keyed by sample_id and barcode. Must cover every imported barcode exactly once; joins use keys rather than row positions. Extra/missing/duplicate keys and overlapping sample/cell fields are rejected.}
\item{doublet}{Auto/flag attempts eligible called-cell diagnostics while keeping cells; off explicitly leaves the path unassessed. Remove may stage fixed predicted-cell removal only when all prerequisites pass; exact human strategy approval remains required. Missing capture/calling/dependency facts are never inferred.}
\item{feature_key}{Original feature name (default) or compatible ID as analysis row names. ID/name/type and analysis keys are retained in assay metadata. Name mode gives incompatible names neutral technical keys and all duplicate-name members a stable feature-ID hash suffix; the local preapproval import summary lists the exact changes. No gene rows are collapsed. ID keys that Seurat would rename are rejected. ID keys may make symbol-based mitochondrial, cycle and reference evidence unavailable; no mapping is inferred. Across samples, require the same Gene Expression ID set and consistent annotations, then reorder by ID. Other modalities are excluded with counts recorded; no gene intersection/union is applied.}
\item{project_dir}{New durable project directory for analysis; existing project directory for opening. An analysis handle is also accepted by \code{sc_open}.}
\item{context}{Explicit study facts including species, tissue and any verified metadata roles. Only a sole complete whitelisted column may be used as a documented sample grouping fallback. Multiple candidates require author choice; no biological or technical-batch provenance is inferred.}
\item{plan}{Named edits to an initial or displayed strategy. Supported fields: rationale, risks, qc, analysis, pcs, batch, resolution, diagnostic_resolutions, umap, cycle, doublet, choice_reasons. Modern complete strategies retain a reason for each choice; reason edits do not approve the plan. QC is a named list of inclusive ranges, e.g. \code{list(nFeature=c(200,2500), percent_mt=c(NA,5))}; NA is an open bound. Supplying qc replaces the displayed ranges as a whole. Analysis edits merge into the displayed analysis settings. Numeric pcs selects a fixed PC count; a named method list can select the kernel's computed policies. Logical umap changes only whether it runs. Other nested method lists use the existing kernel's validated settings. Omitted fields preserve the displayed plan on revision.}
\item{provider,chat_fn,review}{Provider settings, in-memory callback and immutable review policy used by \code{sc_run}. External transfer is disabled by default. Costs are recorded after calls without a monetary cap. Callbacks must be reattached in each session for explicit new requests. No retry is automatic.}
\item{...}{Other named \code{sc_run} raw-entry settings, such as reference or annotation_column. Use \code{plan} for analysis settings. Processed entries and advanced typed proposals remain available through \code{sc_run}.}
\item{project}{Project path or analysis handle for display/results. Mutations require an unedited handle; approve/reject/revise require the snapshot returned by \code{sc_review}. Paths cannot confirm.}
\item{action}{show reads and displays a fresh snapshot. revise stages a new draft only. approve/reject bind exactly the displayed version. continue runs approved local computation only. request explicitly prepares or dispatches the configured provider at a nonfailed proposal boundary.}
\item{reviewer,reason}{Nonempty analyst identity and actual rationale for a revision or decision.}
\item{annotations}{A data frame of character columns clusterId, label, confidence, rationale and markers, or a quoted UTF-8 TSV path with those exact columns. IDs are literal text; every actual cluster is required exactly once. Confidence is low, medium or high. Markers are semicolon-separated exact supplied gene names. Blank labels are never filled automatically. Unknown/unannotated may abstain without markers.}
\item{continue}{Explicit TRUE on scientific approval to execute approved local work after saving that exact decision. Transfer approval cannot use this option; follow it with a separate request.}
\item{stage}{final requires completion; analysis explicitly retrieves a saved provisional analysis object before annotation.}
}
\description{Four adapters over the existing auditable execution kernel. Normal calls do not require schemas, hashes or revision bookkeeping. Opening and printing never execute computation or contact a provider.}
\details{
With no provider, analysis stages an editable software draft retaining count-positive cells, LogNormalize, up to 2000 features and 30 PCs, up to 10 selected PCs, resolution 0.5 and UMAP. These are unapproved starting settings, not scientifically optimized QC or biological conclusions. A configured provider without a manual plan follows the existing separate payload-consent and scientific-review boundaries.

Always assign the snapshot returned by \code{sc_review} and review its complete study facts, measured evidence, strategy impact and annotation marker evidence before confirming. A changed revision rejects old snapshots, including duplicate confirmations; no stale confirmation is rebound. Approval does not infer biological acceptance. Revisions require a new approval. \code{continue=TRUE} uses the revision returned by that approval, not a new inspection chosen silently.

Provider calls require an explicit request. Exact external payload approval remains separate from strategy/annotation approval. The configured provider and disclosure policy remain bound. Failed/unknown provider attempts require the advanced explicit recovery protocol in \code{sc_run_resume}; these adapters never retry them. Scoped child model suggestions continue to use \code{sc_run_suggest}.

Handles and review snapshots may be saved with saveRDS and reopened in another R session. They contain project paths and displayed aggregate evidence, so treat them as local study artifacts. Old snapshots remain subject to the same stale checks. \code{sc_result} returns a verified copy without saving labels or rewriting exports; it uses a transient project lock for a consistent read.
}
\value{Analysis handles contain project_dir, view, the displayed canonical plan and an editable annotation table when actual cluster evidence exists. \code{sc_review} displays and invisibly returns a bound review snapshot. \code{sc_result} returns a Seurat object.}
\seealso{\code{\link{sc_run}}, \code{\link{sc_run_review}}, \code{\link{sc_run_continue}}, \code{\link{sc_run_suggest}}}
\examples{
\dontrun{
x <- sc_analyze(counts, "study", context = list(species="human", tissue="PBMC"),
  plan = list(qc=list(nFeature=c(200,2500), percent_mt=c(NA,5)), pcs=10))
shown <- sc_review(x)
next_step <- sc_review(shown, "approve", reviewer="analyst",
  reason="Reviewed input QC and complete strategy", continue=TRUE)
labels <- next_step$annotations  # fill actual labels and marker citations
proposal <- sc_review(next_step, "revise", annotations=labels,
  reviewer="analyst", reason="Reviewed each cluster's supplied markers")
done <- sc_review(proposal, "approve", reviewer="analyst",
  reason="Reviewed provisional annotations", continue=TRUE)
seu <- sc_result(done)
}
}
