#' Violin plots of QC metrics, saved to disk and registered in the object
#'
#' Produces violin plots for the standard QC metrics at the current stage
#' and saves them as PNG files for the agent (or human) to inspect.
#' The file paths are recorded in `@@figures`, allowing a vision-capable
#' LLM to load them later for decision-making (e.g. when selecting
#' thresholds for [qc_threshold()] or [qc_mad()]).
#'
#' @param obj An AgentSeurat object with QC metrics already computed.
#' @param out_dir Directory where figures will be saved. Created if absent.
#' @param tag Short descriptor included in the filename (e.g. "before", "after").
#' @param group_by Metadata column for x-axis grouping. Default "sample".
#' @param width,height Output dimensions in inches. Defaults 10 x 6.
#' @param dpi Resolution for PNG output. Default 150.
#'
#' @return Updated AgentSeurat object with figures registered in `@@figures`.
#' @export
qc_plot <- function(obj,
                    out_dir  = "figures",
                    tag      = "qc",
                    group_by = "sample",
                    width    = 10,
                    height   = 6,
                    dpi      = 150) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # Assemble a single Seurat for plotting without mutating the stored data.
  # Seurat v5 note: after merge(), an Assay5 object retains split counts
  # layers (counts.1, counts.2, ...); VlnPlot refuses to work until
  # JoinLayers is called. .ensure_joined() is a no-op on v3.
  plot_seu <- if (obj@data_type == "seurat_list") {
    merged <- merge(obj@data[[1]], y = obj@data[-1],
                    add.cell.ids = names(obj@data))
    .ensure_joined(merged, "counts")
  } else {
    .ensure_joined(obj@data, "counts")
  }

  # Basic metrics panel
  p1_path <- file.path(out_dir, sprintf("%s_counts.png", tag))
  p2_path <- file.path(out_dir, sprintf("%s_percents.png", tag))

  has_group <- group_by %in% colnames(plot_seu@meta.data)

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

  script <- sprintf(
'# ---- QC violin plots (%s) ----
VlnPlot(seurat_obj, features = c("nFeature_RNA", "nCount_RNA"),
        group.by = "%s", pt.size = 0)
VlnPlot(seurat_obj, features = c("percent.mt", "percent.ribo", "percent.hb"),
        group.by = "%s", pt.size = 0)',
    tag, group_by, group_by
  )

  rationale <- sprintf(
    "Generated QC violin plots (tag = %s) and saved to %s.",
    tag, out_dir
  )

  obj <- .record_step(
    obj            = obj,
    step_name      = "qc_plot",
    function_name  = "qc_plot",
    params         = list(out_dir = out_dir, tag = tag, group_by = group_by),
    rationale      = rationale,
    script_snippet = script
  )

  obj <- .record_figure(obj, step = "qc_plot", path = p1_path,
                        description = sprintf("nFeature_RNA / nCount_RNA violin (%s)", tag))
  if (p2_registered) {
    obj <- .record_figure(obj, step = "qc_plot", path = p2_path,
                          description = sprintf("percent.mt/ribo/hb violin (%s)", tag))
  }
  obj
}
