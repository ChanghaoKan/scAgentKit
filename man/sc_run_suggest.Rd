\name{sc_run_suggest}
\alias{sc_run_suggest}
\title{Stage a typed model suggestion with exact transfer authority}
\usage{
sc_run_suggest(project_dir,
  action = c("preview", "approve", "request", "adopt", "discard"),
  project_id = NULL, input_hash = NULL, expected_revision = NULL,
  suggestion_hash = NULL, reviewer = NULL, reason = NULL,
  chat_fn = NULL, simulate = FALSE)
}
\arguments{
\item{project_dir}{Durable project directory on the analysis machine.}
\item{action}{Read-only preview, exact outgoing-payload approval, stage-only request, typed candidate adoption, or discard.}
\item{project_id, input_hash, expected_revision}{Exact inspected project identity, input hash and revision, required for every mutation.}
\item{suggestion_hash}{Exact outgoing suggestion binding returned by preview; required for mutations.}
\item{reviewer, reason}{Nonempty analyst identity and rationale for approve, adopt and discard.}
\item{chat_fn}{Optional runtime callback for request in R only. Never persisted or accepted from the browser.}
\item{simulate}{Explicit offline simulation for an immutable mock provider. Strategy simulation replays an explicitly supplied typed starting proposal; annotation simulation produces Unknown. Simulated requests use a separate cache identity.}
}
\description{Uses only saved aggregate evidence, declared context and the project's immutable provider configuration. Browser callers cannot choose providers, keys, endpoints, generation settings, budgets or executable R. No action runs scientific computation.}
\details{Preview discloses the exact outgoing system/user text, model settings, hashes, external transfer notice, per-project budget and known charges/holds. Approval authorizes that exact payload only. Request uses the existing write-ahead usage ledger, conservative unknown-usage holds, strict JSON/type validation and cache; dispatched failures are never automatically retried. Scientific proposals and approvals remain unchanged until explicit adoption. Adoption creates a new typed centralized scientific review; approve it separately before local Continue. A configured manual project cannot acquire a model from its browser; create a configured project in R. Scoped children may explicitly inherit the parent's safe model configuration at creation, without keys or runtime callbacks.}
\value{Safe suggestion view with identities, revision, suggestion hash, exact outgoing preview, safe accounting result, typed candidate and action flags. Adopt returns a fresh project inspection with the central review node.}
\seealso{\code{sc_run}, \code{sc_run_review}, \code{sc_run_continue}, \code{sc_run_subcluster}}
