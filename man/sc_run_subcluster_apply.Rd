\name{sc_run_subcluster_apply}
\alias{sc_run_subcluster_apply}
\alias{sc_run_subcluster_unknown}
\alias{sc_run_subcluster_undo}
\title{Propose unresolved child labels, apply exact reviewed subtypes and undo an application}
\usage{
sc_run_subcluster_unknown(child_project, project_id, input_hash,
  expected_revision, reviewer, reason, request_id)

sc_run_subcluster_apply(child_project, project_id, input_hash,
  expected_revision, parent_scope_hash, expected_parent_revision,
  annotation_hash, apply_hash, column, reviewer, reason, request_id,
  outside = "NA", supersedes = NULL)

sc_run_subcluster_undo(child_project, application_id, project_id,
  input_hash, expected_revision, integration_revision,
  reviewer, reason, request_id)
}
\arguments{
\item{child_project}{Independent child project directory created by \code{sc_run_subcluster}.}
\item{project_id, input_hash, expected_revision}{Exact child identity, input fingerprint and revision from the displayed current child inspection. Changed or mismatched snapshots are rejected.}
\item{parent_scope_hash, expected_parent_revision}{Exact unchanged parent binding and revision from the displayed apply snapshot. Parent output, cluster membership, input, raw counts and revision are revalidated.}
\item{annotation_hash, apply_hash}{Exact reviewed child annotation and full apply-evidence fingerprints from \code{sc_run_subcluster_inspect}.}
\item{column}{Fresh label column in the new derived parent object. Related confidence, rationale, source-child and child-cluster columns are also fresh. Original parent annotation columns are never overwritten.}
\item{outside}{Literal \code{"NA"}, the sole supported policy. Parent cells outside the approved retained child scope receive actual NA values in the new columns.}
\item{supersedes}{Optional current active application ID from this child to this target column, inspected as part of the apply snapshot. A replacement creates a new linked immutable output version. An undone application is inactive and cannot be superseded.}
\item{application_id}{Exact recorded application to withdraw. Undo does not delete or rewrite original/derived RDS files.}
\item{integration_revision}{Exact child integration-history revision from the displayed child inspection, binding undo to that history.}
\item{reviewer, reason}{Nonempty analyst identity and explanation for the specific action.}
\item{request_id}{Stable literal action identifier. Reusing the same request and payload reuses its saved receipt; a different payload with that identifier is rejected. Use a new identifier for a deliberate new action or revision.}
}
\description{Uses the existing typed annotation review for manual unresolved labels, and applies completed reviewed child labels to a new copy of the completed parent by literal cell ID. Original parent projects and outputs remain unchanged.}
\details{\code{sc_run_subcluster_unknown} derives actual child cluster IDs from saved current evidence and prepares a manual Unknown/low proposal. It does not invent biological identities, approve that proposal, run analysis or call a provider. Empty marker evidence can be reviewed as unresolved. Inspect, approve and Continue through the usual coordinator before applying the result.

Apply verifies unique literal IDs and exactly the retained child scope authorized by its approved QC. Explicitly approved QC exclusions remain recorded separately from the frozen original parent selection and receive NA; unexpected missing/extra/duplicate IDs are rejected. Child ordering may differ because alignment uses exact IDs. Numeric child cluster labels are saved as provenance, never used as parent cell mappings.

Under locks, apply rechecks parent/child authority, output hashes, current annotation evidence, new-column conflicts and the apply fingerprint. It writes a new derived parent object and immutable linked application receipt; it does not rewrite the parent, merge overlapping children or silently accept stale revisions. Repeated clicks with the same bound request do not create another application.

Undo withdraws an exact active application in integration history and writes a new restored derived RDS while preserving immutable output files and audit records. Undo of the first application restores a copy of the original parent; undo of a replacement restores and reactivates its linked earlier application. Reannotation/reapplication requires a fresh inspected annotation and apply snapshot. Same-column replacement must explicitly identify its own current active application with \code{supersedes}; cross-child replacement is rejected. Use \code{sc_run_subcluster_inspect} to see the current integration history and valid apply evidence.

All actions are local and headless-capable. Provider dispatch, automatic retries, arbitrary R text and scheduler submission are absent from this scoped increment. The legacy \code{annot_subcluster} positional/fallback path is not called.}
\value{Current child inspection augmented with the saved proposal, application or undo receipt as applicable. An application includes its immutable ID, output path and SHA256. No action establishes biological annotation accuracy.}
\seealso{\code{sc_run_subcluster}, \code{sc_run_subcluster_scope}, \code{sc_run_subcluster_inspect}, \code{sc_run_review}, \code{sc_run_continue}}
