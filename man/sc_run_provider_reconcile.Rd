\name{sc_run_provider_reconcile}
\alias{sc_run_provider_reconcile}
\title{Reconcile a held provider ledger entry}
\usage{
sc_run_provider_reconcile(project_dir, request_hash, cost_usd, reviewer, reason)
}
\arguments{
\item{project_dir}{Run directory.}
\item{request_hash}{Exact 64-character request hash of the held entry, as shown in \code{provider/ledger.json} or an accounting-hold message.}
\item{cost_usd}{Actual charge in USD confirmed from the provider's own billing records; 0 when nothing was charged.}
\item{reviewer, reason}{Analyst identity and how the charge was verified.}
}
\description{An external dispatch whose delivery or cost is unknown (an interrupted request, a provider without pricing, or usage beyond its reservation) pauses every new external request to that provider. This records the verified charge, clears the hold and appends a \code{provider_reconciled} event to the project history.}
\details{Nothing is resent. An entry that never produced a response becomes \code{reconciled_no_response}; it can be dispatched again only by an explicit \code{sc_run_resume(retry = TRUE)}. An over-budget entry that did return a response keeps it as a cached result, which must still pass the stage validator and normal scientific review. Only external entries with unknown cost or an accounting issue can be reconciled.}
\value{Invisibly, the reconciled ledger entry.}
