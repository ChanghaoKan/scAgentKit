\name{sc_run_set_reference}
\alias{sc_run_set_reference}
\title{Rebuild local annotation reference evidence before application}
\usage{
sc_run_set_reference(project_dir, reference, project_id, input_hash,
  expected_revision, reviewer, reason, reference_review = NULL,
  annotation_history = NULL)
}
\arguments{
\item{project_dir}{Existing server-side project directory.}
\item{reference}{Local reference data frame/path, or NULL to remove it.}
\item{project_id, input_hash, expected_revision}{Exact current inspected identities and revision.}
\item{reviewer, reason}{Analyst identity and explanation saved in decision history.}
\item{reference_review}{Explicit replacement reference options; NULL keeps saved options.}
\item{annotation_history}{Readonly historical import. Omit to keep it; explicit NULL removes it.}
}
\description{Rebuilds reference evidence using saved analysis and markers under the project lock. It invalidates the prior annotation approval and review snapshot. It never invokes a provider, reruns markers, applies labels or changes cells.}
\details{Allowed only at annotation_propose or annotation_apply before annotation application. Requested evidence is validated before state publication. An existing typed manual proposal is rebuilt for whole-plan review; otherwise the run stops for explicit configuration. Evidence includes scoped database coverage, symbol and label mapping, provenance and optional historical suggestions. Overlap scores are not calibrated probabilities; missing top-marker genes are not counterevidence.}
\value{Durable run status with a new annotation review or awaiting_configuration.}
