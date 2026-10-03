\name{sc_project_prepare}
\alias{sc_project_prepare}
\title{Explicitly prepare a copy for project export}
\usage{
sc_project_prepare(
  object,
  assay = "RNA",
  counts_layer = "counts",
  cluster_column = "seurat_clusters",
  normalization_method = "LogNormalize",
  scale_factor = 10000,
  nfeatures = 2000,
  npcs = 30,
  dims = NULL,
  resolution = 0.5,
  seed = 1,
  run_umap = TRUE,
  umap_neighbors = 30
)
}
\arguments{
\item{object}{A Seurat object, an AgentSeurat containing exactly one Seurat
object, or a counts matrix with unique, nonempty cell and feature names.
Dense and sparse matrices are supported. Matrix inputs are validated before
Seurat construction can rename duplicate features.}
\item{assay}{Assay to prepare; also the assay name for a matrix input.}
\item{counts_layer}{Exact existing layer containing genuine finite,
nonnegative integer counts.}
\item{cluster_column}{Metadata column in which to store the computed cluster
membership.}
\item{normalization_method}{Seurat normalization method; defaults to
\code{"LogNormalize"}.}
\item{scale_factor}{Scale factor passed to normalization.}
\item{nfeatures}{Requested number of variable features.}
\item{npcs}{Requested number of principal components.}
\item{dims}{Principal components used for neighbors and UMAP. If \code{NULL},
use the available prepared components.}
\item{resolution}{Seurat clustering resolution.}
\item{seed}{Random seed for reproducible preparation.}
\item{run_umap}{Whether to compute a UMAP embedding.}
\item{umap_neighbors}{Requested number of UMAP neighbors.}
}
\value{
A prepared copy. Seurat inputs return a Seurat object; AgentSeurat inputs
return an AgentSeurat with the prepared Seurat in its data slot. Matrix inputs
return a Seurat object. Preparation parameters are recorded in the Seurat
\code{misc$sc_project_prepare} entry and, for AgentSeurat, the
\code{params$project_prepare} entry.
}
\description{
Explicitly performs normalization, variable feature selection, scaling,
principal component analysis, neighbor finding, clustering, and optionally
UMAP on a copy of the input. This is an optional preparation step before
\code{sc_project_export()}; export itself does not run analysis.
}
\details{
All input cells are retained. Preparation applies no implicit QC threshold,
doublet removal, or other cell filter. The input object is preserved, and
unrelated metadata remains available in the returned object. Requested
analysis sizes are limited by the available features, cells, and components.

The selected counts layer must cover the complete object cell universe.
Missing or split layers, duplicate or missing matrix IDs, and counts that
are fractional, negative, or nonfinite are rejected before analysis.
An AgentSeurat containing multiple Seurat objects must first be reduced to
one explicitly chosen or merged object.
}
\seealso{\code{\link{sc_project_export}}}
