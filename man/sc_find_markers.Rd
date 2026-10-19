\name{sc_find_markers}
\alias{sc_find_markers}
\title{Find markers from explicit prepared Seurat clusters}
\usage{
sc_find_markers(obj, only_pos = FALSE, min_pct = 0.25, logfc_threshold = 0)
}
\arguments{
\item{obj}{Prepared Seurat with seurat_clusters metadata and normalized data.}
\item{only_pos, min_pct, logfc_threshold}{Native Seurat marker options.}
}
\description{Find markers from explicit prepared Seurat clusters}
\value{Full marker data.frame; no labels, review or project mutation.}
