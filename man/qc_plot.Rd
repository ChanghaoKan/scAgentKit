\name{qc_plot}
\alias{qc_plot}
\title{Save QC violin plots from a Seurat copy}
\usage{
qc_plot(obj, out_dir = "figures", tag = "qc", group_by = NULL, width = 10, height = 6, dpi = 150)
}
\arguments{
\item{obj}{Seurat object with QC metadata.}
\item{out_dir, tag}{Explicit figure destination and filename tag.}
\item{group_by}{Optional explicit metadata column, NULL uses saved identities.}
\item{width, height, dpi}{Plot dimensions.}
}
\description{Save QC violin plots from a Seurat copy}
\value{Named existing PNG paths; no model request or project approval.}
