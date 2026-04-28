#' Save UMAP plots and register them in @@figures
#'
#' Convenience wrapper that draws UMAPs colored by one or more metadata
#' columns (and optionally by `seurat_clusters`), saves them to disk, and
#' registers the paths. Having plots on disk lets a vision-capable LLM
#' inspect the embedding when deciding next steps (e.g. whether integration
#' succeeded, whether clusters make sense).
#'
#' @param obj An AgentSeurat object after [sc_umap()].
#' @param group_bys Character vector of metadata columns to plot. If any
#'   of "cluster" / "clusters" / "seurat_clusters" is requested it is
#'   mapped to `seurat_clusters`.
#' @param split_by Optional metadata column for facetted plots.
#' @param out_dir Directory for PNG output. Default "figures".
#' @param tag Optional filename suffix.
#' @param width,height,dpi Plot dimensions / resolution.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat.
#' @export
sc_plot_umap <- function(obj,
                         group_bys = "seurat_clusters",
                         split_by  = NULL,
                         out_dir   = "figures",
                         tag       = NULL,
                         width     = 7,
                         height    = 5,
                         dpi       = 150,
                         rationale = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (!"umap" %in% names(obj@data@reductions)) {
    stop("No UMAP reduction found; run sc_umap() first.")
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
    seu <- obj@data
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

    obj <- .record_figure(
      obj, step = "sc_plot_umap", path = path,
      description = sprintf("UMAP colored by %s%s",
                            g,
                            if (is.null(split_by)) "" else sprintf(" (split: %s)", split_by))
    )
  }

  group_vec_str <- paste0('c("', paste(group_bys, collapse = '", "'), '")')
  script <- sprintf(
'# ---- UMAP plots (%s) ----
for (g in %s) {
  p <- DimPlot(seurat_obj, reduction = "umap", group.by = g,
               pt.size = 0.3, label = (g == "seurat_clusters"))
  print(p)
}',
    paste(group_bys, collapse = "/"), group_vec_str
  )

  if (is.null(rationale)) {
    rationale <- sprintf("Saved %d UMAP(s) for group(s): %s.",
                         length(paths), paste(group_bys, collapse = ", "))
  }

  .record_step(
    obj            = obj,
    step_name      = "sc_plot_umap",
    function_name  = "sc_plot_umap",
    params         = list(group_bys = group_bys, split_by = split_by,
                          paths = paths),
    rationale      = rationale,
    script_snippet = script
  )
}
