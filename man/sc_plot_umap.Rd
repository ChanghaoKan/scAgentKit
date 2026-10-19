\name{sc_plot_umap}
\alias{sc_plot_umap}
\title{Save UMAP figures from an existing Seurat reduction}
\usage{
sc_plot_umap(obj, group_bys = "sc_annotation", split_by = NULL, out_dir = "figures", tag = NULL, width = 7,
    height = 5, dpi = 150)
}
\arguments{
\item{obj}{Prepared Seurat, for example sc_result(project).}
\item{group_bys}{Explicit metadata columns; cluster/clusters alias seurat_clusters.}
\item{split_by}{Optional explicit faceting metadata column.}
\item{out_dir, tag}{Figure directory and optional filename tag.}
\item{width, height, dpi}{Figure dimensions.}
}
\description{Save UMAP figures from an existing Seurat reduction}
\value{Character vector of saved PNG paths. No fitting, model call or approval.}
