\name{sc_run_set_child_context}
\alias{sc_run_set_child_context}
\title{Correct soft child annotation context without rerunning analysis}
\usage{
sc_run_set_child_context(project_dir, context, project_id, input_hash,
  expected_revision, expected_context_hash, reviewer, reason, request_id)
}
\arguments{
\item{project_dir}{Scoped child run directory.}
\item{context}{Named edit list: \code{enabled}, \code{lineage_hint},
\code{identity_status} (labeled/unknown/mixed/unreviewed), \code{tissue}
and/or \code{notes}. Unspecified fields retain their values. Explicit NULL
clears a hint, tissue override or notes. A labeled correction to an unresolved
parent scope requires an explicit lineage hint.}
\item{project_id, input_hash}{Exact current inspected project/input bindings.}
\item{expected_revision}{Exact inspected run revision; required, never NULL.}
\item{expected_context_hash}{Exact inspected \code{child_context$hash}.}
\item{reviewer, reason}{Analyst identity and nonempty correction rationale.}
\item{request_id}{Stable literal identifier for idempotent correction retry.}
}
\value{Fresh inspection awaiting a new annotation proposal.}
\description{Supports fresh scoped children stopped at annotation_propose or
annotation_apply before annotation writeback. Frozen parent facts and literal
selection stay unchanged. Parent approved labels and analyst corrections are
soft hypotheses, not child identity truth or a label whitelist.}
\details{Inspection exposes aggregate parent labels/status, tissue, literal
cluster IDs/counts, provenance hashes and a monotonically increasing context
generation. Unknown, mixed and unreviewed parent scopes remain explicit.
Context corrections invalidate current annotation proposals, model response
pointers, adoption receipts, scientific approval and exact outgoing-payload
consents. New proposals and fresh approvals are required. Even A to B to A
has a new request identity. Historical checkpoints, decisions, calculation
artifacts and the complete usage ledger remain unchanged.

Database scores and ranking remain based on current expression-marker
coverage; context relations are nonblocking hints. Cross-lineage claims
require explicit label relations. Absence from top markers does not show
absence of expression. Correcting annotation tissue refreshes only scoped
reference evidence; species, input/metadata roles and selected cell scope
cannot be edited here. Undo an executed annotation before correcting context.
This R operation does not call a provider, recompute analysis/markers or open
a browser. Exact aggregate previews/consent govern any subsequent external
request; generated context does not include cell IDs, local paths or reviewers.}
\examples{
\dontrun{
view <- sc_run_inspect(child_project)
sc_run_set_child_context(child_project,
  context = list(lineage_hint = "T cell", identity_status = "labeled",
                 notes = "Parent label may be wrong; assess current markers."),
  project_id = view$project_id, input_hash = view$input_hash,
  expected_revision = view$revision,
  expected_context_hash = view$child_context$hash,
  reviewer = "analyst", reason = "Correct the annotation hypothesis",
  request_id = "context-correction-1")
# Inspect new evidence, propose/request annotations, and approve the new review.
}}
