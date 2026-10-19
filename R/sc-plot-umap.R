#' Save UMAP figures from an existing Seurat reduction
#' @param obj Prepared Seurat, for example sc_result(project).
#' @param group_bys Explicit metadata columns; cluster/clusters alias seurat_clusters.
#' @param split_by Optional explicit faceting metadata column.
#' @param out_dir,tag Figure directory and optional filename tag.
#' @param width,height,dpi Figure dimensions.
#' @return Character vector of saved PNG paths. No fitting, model call or approval.
#' @export
sc_plot_umap <- function(obj,group_bys="sc_annotation",split_by=NULL,out_dir="figures",
  tag=NULL,width=7,height=5,dpi=150) {
  obj<-.sc_project_unwrap(obj)
  if (!"umap" %in% names(obj@reductions)) {
    stop("No UMAP reduction found; prepare an explicit UMAP first.")
  }

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # Normalize aliases
  group_bys <- vapply(group_bys, function(g) {
    if (g %in% c("cluster", "clusters")) "seurat_clusters" else g
  }, character(1))

  paths <- character(0)
  for (g in group_bys) {
    suffix <- if (is.null(tag)) g else sprintf("%s_%s", tag, g)
    path <- file.path(out_dir, sprintf("umap_%s.png", suffix))
    seu <- obj
    p <- if (is.null(split_by)) {
      Seurat::DimPlot(seu, reduction = "umap", group.by = g,
                      pt.size = 0.3, label = g == "seurat_clusters")
    } else {
      Seurat::DimPlot(seu, reduction = "umap", group.by = g,
                      split.by = split_by,
                      pt.size = 0.3, label = g == "seurat_clusters")
    }
    p <- p + ggplot2::theme_classic()
    ggplot2::ggsave(path, p, width = width, height = height, dpi = dpi)
    paths <- c(paths, path)


  }

  paths
}
