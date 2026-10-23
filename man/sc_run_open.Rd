\name{sc_run_open}
\alias{sc_run_open}
\title{Reopen saved project results in the local browser}
\usage{sc_run_open(project_dir, checkout = NULL, python = NULL, browse = interactive())}
\arguments{
\item{project_dir}{Existing saved sc_run directory.}
\item{checkout}{Source checkout containing workbench/open_results.py, remembered after first use.}
\item{python}{Existing Python 3 executable, automatically detected by default.}
\item{browse}{Open the local URL in the browser; FALSE prints and returns it.}}
\value{Invisibly, the local URL, process ID and reuse status.}
\description{Starts or reuses a read-only localhost viewer without resuming analysis or calling a model. Uses the current R executable and library paths. Requires Python 3.9+ and the installed package resources or a matching source checkout on macOS or Linux. The format marker and authoritative state must match project format version 4 before project writes or write locks. Missing, damaged or mismatched formats are rejected; use the original software environment or create a new project. A read-only R preflight may run; no scientific analysis or model request starts.}
