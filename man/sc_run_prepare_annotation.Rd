\name{sc_run_prepare_annotation}
\alias{sc_run_prepare_annotation}
\title{Submit a first manual annotation proposal from inspected evidence}
\usage{
sc_run_prepare_annotation(project_dir, project_id, input_hash,
  expected_revision, evidence_hash, proposal, reviewer, reason, request_id)
}
\arguments{
\item{project_dir}{Saved project directory.}
\item{project_id, input_hash, expected_revision, evidence_hash}{Exact inspected project, input, revision and annotation evidence binding.}
\item{proposal}{Complete typed scagentkit.annotation.v1 proposal.}
\item{reviewer, reason}{Analyst identity and submission rationale.}
\item{request_id}{Stable identifier for retrying this exact submission.}
}
\value{Fresh inspection awaiting annotation review.}
\description{Saves a complete first manual proposal under the existing project lock and validation rules. Does not approve annotations, execute analysis or call a provider. Inspect the saved proposal before separately approving and continuing.}
