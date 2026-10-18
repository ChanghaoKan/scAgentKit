\name{sc_start}
\alias{sc_start}
\title{Start or reopen a reviewed analysis in the local browser}
\usage{
sc_start(input, project_dir, context = NULL, checkout = NULL,
  python = NULL, browse = interactive(), reuse_processed = FALSE,
  processed_reason = NULL, cluster_column = "seurat_clusters")
}
\arguments{
\item{input}{Local RDS file containing raw counts or a Seurat object.}
\item{project_dir}{New project path or the same saved project to reopen.}
\item{context}{Declared species, tissue, research_goal and optional notes, columns and design; required for a new project, otherwise saved context is used.}
\item{checkout}{Matching source checkout containing workbench/start_analysis.py. Supply once or set options(scAgentKit.checkout=...). Remembered per project. Browser files are not included in the installed R package.}
\item{python}{Existing Python 3.9+ executable, detected by default.}
\item{browse}{Open the URL in the browser; FALSE returns it without browser dispatch.}
\item{reuse_processed}{Explicitly reuse processed layers and clusters. FALSE by default.}
\item{processed_reason}{Required rationale for processed reuse.}
\item{cluster_column}{Saved cluster column for processed reuse.}
}
\value{Invisibly, the service URL, PID, project ID and reuse status.}
\description{Thin R entry into the existing local launcher and review service. Returns control to R. New projects start at strategy review; explicit processed reuse starts at annotation. Neither startup nor reopening approves labels or starts analysis/provider requests. The service allows bound review writes and explicit local continuation. Existing project authority is never replaced.}
\details{Requires a matching installed R package, source checkout and Python 3.9+. No software or credentials are installed. The current R executable and library paths are passed to the existing launcher. Repeating the call with the same project reuses its matching live service, or restarts a stopped service. Original RDS path/checksum and saved configuration must match. Use \code{sc_run_open()} for a read-only result viewer.}
