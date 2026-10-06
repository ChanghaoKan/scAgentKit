\name{sc_review_apply}
\alias{sc_review_apply}
\title{Apply verified human review to new metadata columns}
\usage{
sc_review_apply(object, journal, project, columns = c(type = "review_type"))
}
\arguments{
\item{object}{A Seurat object or AgentSeurat wrapping exactly one Seurat.}
\item{journal}{Path to a generic review-journal JSON file.}
\item{project}{Path to its verified evidence project directory.}
\item{columns}{Named vector mapping \code{type}, \code{state} or \code{QC} dimensions to new metadata column names.}
}
\value{A modified copy of the same object kind. An invalid review raises \code{sc_review_apply_error}, whose \code{report} contains the validation result.}
\description{Revalidates the complete input immediately before applying current accepted human decisions, and aligns by exact cell ID. No files are written. Save the returned object separately with \code{saveRDS} to a new path if desired.}
\details{Existing metadata, factor levels and missing values, active identities, assays, reductions and wrapper history are preserved. Only the new requested label and companion columns are added. An occupied or overlapping target column causes atomic refusal before mutation. Abstained \code{unknown} remains distinct from deferred and unreviewed cells. Human acceptance does not establish biological truth.}
\seealso{\code{\link{sc_review_validate}}, \code{\link{sc_project_export}}}
