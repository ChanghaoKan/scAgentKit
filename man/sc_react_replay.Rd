\name{sc_react_replay}
\alias{sc_react_replay}
\title{Replay saved annotation evidence without a provider}
\usage{sc_react_replay(project, output_dir = NULL)}
\arguments{
\item{project}{Saved project directory with a completed ReAct session.}
\item{output_dir}{Optional new directory for a JSON report. NULL returns the report.}
}
\description{Rebuilds the saved append-only conversation, reruns read-only tools and validates citations using the original scientific checkpoints. No API key or provider call is used.}
\value{Versioned report with reconstructed original draft, per-cluster matches and differences. Later human edits and approvals are not replayed.}
\details{The scientific implementation and inputs must match the saved session. Integrity errors block replay. Cache-hit flags are ignored when comparing tool evidence. Timing-dependent failures may differ and are reported. Project state is not modified.}
