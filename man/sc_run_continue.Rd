\name{sc_run_continue}
\alias{sc_run_continue}
\title{Continue approved local computation without a provider call}
\usage{
sc_run_continue(project_dir, project_id, input_hash, expected_revision,
  retry = FALSE)
}
\arguments{
\item{project_dir}{Durable project directory on the analysis machine.}
\item{project_id, input_hash}{Exact project identity and input SHA256 returned by \code{sc_run_inspect}.}
\item{expected_revision}{Required exact nonnegative inspected state revision. Stale revisions are rejected before writing.}
\item{retry}{Explicit TRUE to retry a failed or interrupted local computation stage. Provider/proposal failures require explicit R configuration or resume.}
}
\description{Runs supported local stages under the existing project lock. Scientific changes still require their saved exact approvals; generating local QC summaries requires no new approval. Never creates a provider function, invokes a callback, requests a model response, or transmits an external payload.}
\details{Configuration, implementation, source files, registered artifacts and current approvals are checked before continuation. Existing awaiting-review, rejected and completed runs return without rewriting their files. Local stages may continue through QC application, standard analysis, markers, annotation evidence, approved annotation application and output finalization. A saved typed manual proposal can be validated and published for review. Missing proposals stop at awaiting_configuration and record a local_continue_boundary diagnostic and history event. Use headless typed review or \code{sc_run_resume} explicitly in R when a new provider response is needed. This function does not approve scientific decisions or mark a computed result scientifically accepted.}
\value{Durable run status, current stage and revision, diagnostics, pending review and output paths when available.}
\seealso{\code{sc_run}, \code{sc_run_inspect}, \code{sc_run_review}, \code{sc_run_resume}}
