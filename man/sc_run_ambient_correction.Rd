\name{sc_run_ambient_correction}
\alias{sc_run_ambient_correction}
\title{Optional ambient correction preserving original counts}
\usage{
sc_run_ambient_correction(input, method = c("SoupX", "decontX"), capture,
  clusters, raw_counts = NULL, assay = "RNA", counts_layer = "counts",
  seed = 42L, round_counts = FALSE, output_dir = NULL)
}
\arguments{
\item{input}{Seurat object or named sparse original integer counts.}
\item{method}{Optional SoupX or decontX estimator.}
\item{capture}{Explicit id, source and complete=TRUE declaration for one capture.}
\item{clusters}{Preliminary clusters named by exact cell IDs.}
\item{raw_counts}{Matched raw droplets; required for SoupX.}
\item{assay,counts_layer}{Explicit raw source layers.}
\item{seed}{Numerical seed.}
\item{round_counts}{Explicit rounding of corrected output; FALSE preserves estimates.}
\item{output_dir}{Optional new directory for separate corrected counts and receipt.}
}
\description{Runs an optional estimator on a copy and preserves original counts.
SoupX requires matched raw and filtered input. decontX without raw background
infers contamination from other clusters; this assumption can remove native RNA.
No method is enabled by default and no existing project or checkpoint is changed.}
\value{Corrected counts and before/after comparison receipt.}
