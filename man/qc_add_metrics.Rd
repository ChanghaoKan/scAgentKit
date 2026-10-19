\name{qc_add_metrics}
\alias{qc_add_metrics}
\title{Add explicitly declared count-based QC measurements to a Seurat copy}
\usage{
qc_add_metrics(obj, species = NULL, mt_pattern = NULL, ribo_pattern = NULL, hb_pattern = NULL, assay = "RNA",
    counts_layer = "counts")
}
\arguments{
\item{obj}{Seurat object with a single explicit counts layer.}
\item{species}{Declared human/mouse; required unless all patterns are explicit.}
\item{mt_pattern, ribo_pattern, hb_pattern}{Optional explicit gene regexes.}
\item{assay, counts_layer}{Exact source assay/layer.}
}
\description{Add explicitly declared count-based QC measurements to a Seurat copy}
\value{Seurat copy with percent.mt, percent.ribo and percent.hb; no filtering.}
