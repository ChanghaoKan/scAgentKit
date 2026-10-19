#' Save QC violin plots from a Seurat copy
#' @param obj Seurat object with QC metadata.
#' @param out_dir,tag Explicit figure destination and filename tag.
#' @param group_by Optional explicit metadata column, NULL uses saved identities.
#' @param width,height,dpi Plot dimensions.
#' @return Named existing PNG paths; no model request or project approval.
#' @export
qc_plot <- function(obj,out_dir="figures",tag="qc",group_by=NULL,width=10,height=6,dpi=150) {
  plot_seu<-.ensure_joined(.sc_project_unwrap(obj),"counts")
  if(!is.null(group_by)&&!group_by %in% names(plot_seu[[]]))stop("Explicit grouping column is absent.",call.=FALSE)
  dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
  # Basic metrics panel
  p1_path <- file.path(out_dir, sprintf("%s_counts.png", tag))
  p2_path <- file.path(out_dir, sprintf("%s_percents.png", tag))

  has_group <- !is.null(group_by) && group_by %in% colnames(plot_seu@meta.data)

  # NOTE: VlnPlot on a not-yet-normalized object emits a "data layer not
  # found, falling back to counts" warning. That's expected during QC
  # (which runs BEFORE NormalizeData), so suppress the noise.
  p1 <- if (has_group) {
    suppressWarnings(Seurat::VlnPlot(plot_seu,
                    features = c("nFeature_RNA", "nCount_RNA"),
                    group.by = group_by, pt.size = 0))
  } else {
    suppressWarnings(Seurat::VlnPlot(plot_seu,
                    features = c("nFeature_RNA", "nCount_RNA"),
                    pt.size = 0))
  }
  ggplot2::ggsave(p1_path, p1, width = width, height = height, dpi = dpi)

  pct_features <- intersect(c("percent.mt", "percent.ribo", "percent.hb"),
                            colnames(plot_seu@meta.data))
  p2_registered <- FALSE
  if (length(pct_features) > 0) {
    p2 <- if (has_group) {
      suppressWarnings(Seurat::VlnPlot(plot_seu, features = pct_features,
                      group.by = group_by, pt.size = 0))
    } else {
      suppressWarnings(Seurat::VlnPlot(plot_seu, features = pct_features,
                      pt.size = 0))
    }
    ggplot2::ggsave(p2_path, p2, width = width, height = height, dpi = dpi)
    p2_registered <- TRUE
  }

  paths<-c(counts=p1_path);if(p2_registered)paths<-c(paths,percents=p2_path)
  paths
}
