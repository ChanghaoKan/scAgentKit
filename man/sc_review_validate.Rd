\name{sc_review_validate}
\alias{sc_review_validate}
\title{Validate portable human review against its original object}
\usage{
sc_review_validate(object, journal, project, columns = c(type = "review_type"))
}
\arguments{
\item{object}{A Seurat object or AgentSeurat wrapping exactly one Seurat.}
\item{journal}{Path to a \code{scagentkit.review-journal.v1} JSON file.}
\item{project}{Path to the verified project directory. Import ZIP files safely through the local workbench first.}
\item{columns}{Named character vector mapping \code{type}, \code{state} or \code{QC} dimensions to new metadata column names.}
}
\value{A list with \code{valid}, structured \code{errors} and \code{warnings} tables, a per-cell \code{mapping}, \code{coverage}, target \code{columns}, and the computed source \code{identity}. Invalid input returns \code{valid = FALSE}; no object or file is changed.}
\description{Checks project and asset hashes, complete expression identity, exact literal cell-ID and cluster scopes, original JSON event payload hashes, workflow status and undo history before deriving any writeback. Different cell or gene order is permitted; changed values, membership, features or cell sets are refused. Legacy PBMC handoffs cannot acquire a generic source identity.}
\details{The latest active accepted ordinary label is \code{labeled}; accepted \code{unknown} is \code{abstained}. Proposed or reviewed decisions are \code{deferred} and leave labels missing. No decision is \code{unreviewed}. Undo restores the preceding active decision. Partial review is legal and reported explicitly. Human acceptance is a workflow state, not biological truth.

For each requested label column, companion columns append \code{_review_state}, \code{_workflow_status}, \code{_decision_id}, \code{_source_fingerprint}, and \code{_bundle_digest}. Every target name must be new and mutually distinct. Validation performs no model call, object serialization or file write.}
\seealso{\code{\link{sc_review_apply}}, \code{\link{sc_project_export}}}
