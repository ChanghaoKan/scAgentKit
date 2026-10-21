\name{sc_run_provider_reconcile}
\alias{sc_run_provider_reconcile}
\title{Reconcile a provider ledger entry}
\usage{
sc_run_provider_reconcile(project_dir, request_hash, cost_usd, reviewer, reason, delivery = NULL)
}
\arguments{
\item{project_dir}{Run directory.}
\item{request_hash}{Exact 64-character request hash of the entry with unknown cost, delivery or an accounting issue, as shown in \code{provider/ledger.json}.}
\item{cost_usd}{Actual charge in USD confirmed from the provider's own billing records; 0 when nothing was charged.}
\item{reviewer, reason}{Analyst identity and how cost and any delivery confirmation were verified.}
\item{delivery}{NULL preserves delivery uncertainty. Use \code{"not_sent"} or \code{"received"} only with independent confirmation from the provider.}
}
\description{Records confirmed actual cost without a monetary cap. Cost confirmation alone does not resolve uncertain delivery. An explicit delivery value records the operator's independently verified delivery status.}
\details{Nothing is resent by reconciliation. Exact cached responses remain available. A request without a response remains reconciled_no_response; single requests require an explicit retry to dispatch again after verified delivery reconciliation. Structured turns are not automatically resent. The previous ledger state and operator reason are retained in the audit receipt.}
\value{Invisibly, the reconciled ledger entry.}
