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
\description{Starts or reuses a read-only localhost viewer without resuming analysis or calling a model. Uses the current R executable and library paths. Requires an existing Python 3 and public source checkout on macOS or Linux.}
