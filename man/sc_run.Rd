\name{sc_run}
\alias{sc_run}
\alias{sc_run_inspect}
\alias{sc_run_approve}
\alias{sc_run_reject}
\alias{sc_run_resume}
\alias{sc_run_propose}
\alias{sc_run_undo}
\alias{sc_run_unlock}
\alias{sc_run_accept}
\title{Server-side resumable analysis with typed human approvals}
\usage{
sc_run(input, project_dir, context = list(), provider = NULL,
  chat_fn = NULL, budget = 0, review = list(),
  start_stage = c("qc", "processed"), processed_reason = NULL,
  assay = "RNA", counts_layer = "counts", normalized_layer = "data",
  cluster_column = "seurat_clusters", analysis = list(), reference = NULL,
  annotation_column = "sc_annotation", qc_proposal = NULL,
  annotation_proposal = NULL)
sc_run_inspect(project_dir)
sc_run_approve(project_dir, proposal_hash, reviewer, reason = "")
sc_run_reject(project_dir, proposal_hash, reviewer, reason)
sc_run_resume(project_dir, provider = NULL, chat_fn = NULL, retry = FALSE)
sc_run_propose(project_dir, proposal, reviewer, reason)
sc_run_undo(project_dir, decision_id, reviewer, reason)
sc_run_unlock(project_dir, token, reason)
sc_run_accept(project_dir, reviewer, reason)
}
\arguments{
\item{input}{Named genuine raw counts matrix, Seurat object, or local RDS path.}
\item{project_dir}{Server-side directory. Creation requires no existing run.}
\item{context}{Named list with species, tissue, notes, and columns mapping sample, capture, batch, condition and donor roles to actual metadata columns.}
\item{provider}{Provider name or safe configuration list. Built-in DeepSeek and Grok use runtime environment keys.}
\item{chat_fn}{Explicit in-memory function accepting system and user prompts. Never saved.}
\item{budget}{Project USD reservation limit. Default zero. Unknown accounting holds its reservation.}
\item{review}{Named policy: allow_external permits an exact-payload transfer approval node; preapprove_qc explicitly supplies a typed rule.}
\item{start_stage}{qc for raw input, or processed to reuse existing analysis.}
\item{processed_reason}{Required provenance for processed entry and skipped QC/analysis.}
\item{assay, counts_layer, normalized_layer, cluster_column}{Explicit source assay, genuine raw counts, normalized layer and cluster membership. Ambiguous layers fail closed.}
\item{analysis}{Supported settings passed to \code{sc_project_prepare}.}
\item{reference}{Optional supplied local annotation marker reference.}
\item{annotation_column}{Fresh output metadata column. Existing labels are preserved.}
\item{qc_proposal, annotation_proposal, proposal}{Typed QC/annotation data. The propose helper also accepts a local JSON file path.}
\item{proposal_hash}{Exact current review hash returned by inspect.}
\item{reviewer, reason}{Analyst identity and rationale recorded in history.}
\item{retry}{Explicitly retry an incomplete/failed stage. Unknown external delivery is never automatically resent.}
\item{decision_id}{Executed annotation approval ID to undo.}
\item{token}{Exact stopped lock owner's token. Remote owner termination must be independently verified.}
}
\description{Diagnoses raw inputs, persists aggregate QC evidence, obtains a typed proposal and returns at review before filtering or basic analysis. Exact approval permits copy-based QC, standard analysis, markers, independent local-reference and model annotation suggestions, then reviewed new metadata and local outputs. No browser or manual archive transfer is required.}
\details{The authoritative state and hash-chained history are atomically committed locally. Input, evidence, provider settings, relevant configuration and implementation fingerprints bind approvals. Checkpoints and request caches permit a new R process to resume without repeating completed stages. External payloads require an explicit preview approval and transmit aggregate evidence and supplied context, including declared sample/capture labels. Credentials remain in runtime environment or caller memory. Annotation browser review currently operates on the completed evidence bundle separately; QC approvals are headless. Batch integration is skipped. Computed artifacts are EXECUTED, while sc_run_accept records explicit RESULT_ACCEPTED scientific assessment. See docs/SERVER_FIRST.md and installed examples for full workflows and filesystem support limits.}
\value{Status, current stage, revision, diagnostics, proposal and hash when awaiting review, and output paths when complete. Unlock returns invisible TRUE.}
