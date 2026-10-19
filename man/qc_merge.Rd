\name{qc_merge}
\alias{qc_merge}
\title{Merge explicitly prepared Seurat inputs without guessing cell prefixes}
\usage{
qc_merge(obj, add_cell_ids = NULL, join_layers = TRUE, assay = "RNA")
}
\arguments{
\item{obj}{Nonempty Seurat list with matching literal feature IDs.}
\item{add_cell_ids}{Optional explicit unique cell prefixes; NULL preserves IDs.}
\item{join_layers}{Whether to join the selected assay's layers after merging.}
\item{assay}{Explicit assay.}
}
\description{Merge explicitly prepared Seurat inputs without guessing cell prefixes}
\value{New Seurat; original objects are unchanged. No sample-role inference.}
