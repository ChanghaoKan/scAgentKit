#' Score cell cycle phase without filtering cells
#'
#' Runs [Seurat::CellCycleScoring()] on the object's normalized data using
#' literal gene symbols. Human defaults load the installed Seurat
#' `cc.genes.updated.2019` package data. Mouse requires both explicit lists
#' with their source and version; no capitalization or ortholog conversion is
#' performed. Custom human lists also require a source and version.
#'
#' Score first, inspect phase and lineage evidence, and then explicitly choose
#' whether to regress. Full regression uses `S.Score` and `G2M.Score`.
#' Difference regression uses `CC.Difference` to reduce S-versus-G2M phase
#' effects while preserving the distinction between cycling and noncycling
#' cells. Neither scoring nor regression deletes cycling cells.
#'
#' Literal matching can be insufficient for Ensembl identifiers, aliases, or
#' another species' symbols. Supply an explicit one-to-one `symbol_mapping`
#' instead of inferring capitalization or orthology. Fewer than five expressed
#' matching genes in either set fail before metadata mutation. Existing score
#' columns are protected; use `sc_run()` diagnostics with a fresh prefix when
#' prior scores must coexist.
#'
#' @param obj An AgentSeurat with a single Seurat object and normalized data.
#' @param species Human or mouse, including their explicit scientific-name
#'   aliases. Default `"human"`.
#' @param s_genes,g2m_genes Both literal custom phase-gene vectors, or both NULL
#'   for the human Seurat default.
#' @param rationale Optional rationale for the audit record.
#' @param source,version Required provenance strings for custom gene lists.
#' @param symbol_mapping Optional complete one-to-one canonical-to-input symbol
#'   mapping; see [sc_cycle_gene_set()].
#' @return Updated AgentSeurat with `S.Score`, `G2M.Score`, `Phase`, and
#'   `CC.Difference`. No cells are removed and no regression is performed.
#' @export
sc_cellcycle_score <- function(obj, species = "human", s_genes = NULL,
                               g2m_genes = NULL, rationale = NULL,
                               source = NULL, version = NULL,
                               symbol_mapping = NULL) {
  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat")
    stop("sc_cellcycle_score expects data_type == 'seurat'. Call qc_merge() first.", call. = FALSE)
  species <- .sc_run_species(species, allow_missing = FALSE)
  genes <- sc_cycle_gene_set(species, s_genes = s_genes, g2m_genes = g2m_genes,
                             source = source, version = version,
                             symbol_mapping = symbol_mapping)
  seu <- obj@data
  assay <- SeuratObject::DefaultAssay(seu)
  normalized <- .sc_project_layer(seu, assay, "data")
  expressed <- rownames(normalized)[as.numeric(Matrix::rowSums(normalized)) > 0]
  s_use <- intersect(genes$s_genes, expressed)
  g2m_use <- intersect(genes$g2m_genes, expressed)
  if (length(s_use) < 5L || length(g2m_use) < 5L)
    stop(sprintf("Insufficient literal expressed cell-cycle genes (S=%d, G2M=%d); at least five per set are required before scoring. Check the supplied species, symbols, or explicit mapping.",
                 length(s_use), length(g2m_use)), call. = FALSE)
  protected <- c("S.Score", "G2M.Score", "Phase", "CC.Difference")
  if (any(protected %in% names(seu[[]])) || length(grep("Cell.Cycle", names(seu[[]]))))
    stop("Cell-cycle output columns already exist; use sc_run() diagnostics with a fresh column_prefix to preserve them.", call. = FALSE)
  cells <- colnames(seu); metadata <- seu[[]]
  seu <- Seurat::CellCycleScoring(seu, s.features = s_use, g2m.features = g2m_use,
                                 assay = assay, pool = expressed, slot = "data",
                                 search = FALSE, set.ident = FALSE)
  if (!identical(colnames(seu), cells) ||
      !identical(seu[[]][, names(metadata), drop = FALSE], metadata) ||
      any(!is.finite(seu$S.Score)) || any(!is.finite(seu$G2M.Score)))
    stop("Cell-cycle scoring did not preserve source metadata and finite exact-cell scores; no update was returned.", call. = FALSE)
  seu$CC.Difference <- seu$S.Score - seu$G2M.Score
  obj@data <- seu
  phase_table <- table(as.character(seu$Phase))
  if (is.null(rationale)) rationale <- sprintf(
    "Cell cycle scored with literal %s symbols (%s version %s); inspect lineage evidence before choosing regression. No cells removed.",
    species, genes$source, genes$version)
  script <- paste0(
    "# ---- Cell cycle scoring: literal versioned symbols; no filtering ----\n",
    "s_genes <- ", paste(utils::capture.output(dput(s_use)), collapse = "\n"), "\n",
    "g2m_genes <- ", paste(utils::capture.output(dput(g2m_use)), collapse = "\n"), "\n",
    "seurat_obj <- CellCycleScoring(seurat_obj, s.features = s_genes,\n",
    "  g2m.features = g2m_genes, assay = ", deparse(assay),
    ", pool = rownames(seurat_obj)[Matrix::rowSums(GetAssayData(seurat_obj, layer = 'data')) > 0],\n",
    "  slot = 'data', search = FALSE, set.ident = FALSE)\n",
    "seurat_obj$CC.Difference <- seurat_obj$S.Score - seurat_obj$G2M.Score")
  .record_step(obj = obj, step_name = "sc_cellcycle_score", function_name = "sc_cellcycle_score",
    params = list(species = species, source = genes$source, version = genes$version,
                  gene_set_hash = genes$gene_set_hash, symbol_mapping = genes$symbol_mapping,
                  n_s_genes = length(s_use), n_g2m_genes = length(g2m_use),
                  phase_counts = stats::setNames(as.list(as.integer(phase_table)), names(phase_table))),
    rationale = rationale, script_snippet = script, new_stage = "cellcycle_scored")
}

# Kept for internal compatibility; no hardcoded or old-list fallback is used.
.load_cc_genes <- function() {
  declaration <- sc_cycle_gene_set("human")
  list(s.genes = declaration$s_genes, g2m.genes = declaration$g2m_genes)
}
