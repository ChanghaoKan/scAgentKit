\name{sc_run_strategy_revise}
\alias{sc_run_strategy_revise}
\title{Revise an exact stopped strategy with selective checkpoint invalidation}
\usage{
sc_run_strategy_revise(project_dir, proposal, project_id, input_hash,
  expected_revision, reviewer, reason)
}
\arguments{
\item{project_dir}{Durable project directory created with strategy enabled.}
\item{proposal}{Complete typed scagentkit.strategy.v1 object. No paths or executable R text are accepted.}
\item{project_id,input_hash,expected_revision}{Exact inspected project identity, original input SHA256 and current nonnegative revision.}
\item{reviewer,reason}{Nonempty analyst identity and rationale.}
}
\description{Validates the whole replacement against saved local evidence, then returns at one concentrated strategy review without computation or provider dispatch. Resolution changes retain QC, basis PCA and neighbor/UMAP checkpoints; PC changes retain QC and basis; QC changes invalidate downstream active references. Rationale-only changes preserve calculations and unrelated scientific approval. Versioned files, historical decisions and provider ledger remain.}
\details{Revisions require a stopped project before annotation writeback. Applied or completed results require a new project. Manual batch handling is a pending analyst boundary, not an executed integration. Approval is separate from explicit local Continue. Unsupported cycle/doublet/subcluster methods cannot be authorized through this interface. See docs/ANALYSIS_STRATEGY_SUPPORT.md for the supported matrix and limitations.}
\value{Durable status awaiting exact strategy approval.}
