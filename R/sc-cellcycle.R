#' Score cell cycle phase (optional QC step)
#'
#' Runs [Seurat::CellCycleScoring()] using the standard Tirosh S/G2M gene
#' sets (supplied internally by Seurat as `cc.genes`). Adds `S.Score`,
#' `G2M.Score`, `Phase`, and `CC.Difference` columns to the metadata.
#'
#' This is an *optional* step. The standard workflow is:
#'   1. Run `sc_cellcycle_score()` early (after normalization).
#'   2. Cluster the data without regressing out cell cycle.
#'   3. Inspect the UMAP colored by `Phase`. If a cluster is clearly being
#'      driven by proliferation rather than biology, call
#'      `sc_scale(obj, vars_to_regress = c("S.Score", "G2M.Score"))` or
#'      pass `vars_to_regress = "CC.Difference"` to regress out only the
#'      cycling-vs-noncycling signal while preserving proliferating
#'      identity.
#'
#' The Seurat `cc.genes` list is human (HGNC symbols). For mouse data,
#' pass `species = "mouse"` and Title-case conversion will be applied
#' (e.g. `MCM5` -> `Mcm5`), which works for almost all cc genes.
#'
#' @param obj An AgentSeurat object at stage >= "normalized".
#' @param species Character, `"human"` or `"mouse"`. Default `"human"`.
#' @param s_genes Optional character vector of S-phase genes; overrides
#'   the Seurat default.
#' @param g2m_genes Optional character vector of G2/M-phase genes; overrides
#'   the Seurat default.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat. Metadata gains `S.Score`, `G2M.Score`,
#'   `Phase`, `CC.Difference`. Nothing is removed or regressed out.
#' @export
sc_cellcycle_score <- function(obj,
                               species   = c("human", "mouse"),
                               s_genes   = NULL,
                               g2m_genes = NULL,
                               rationale = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat") {
    stop("sc_cellcycle_score expects data_type == 'seurat'. Call qc_merge() first.")
  }
  species <- match.arg(species)

  # Resolve gene lists
  if (is.null(s_genes) || is.null(g2m_genes)) {
    cc <- .load_cc_genes()
    if (is.null(s_genes))   s_genes   <- cc$s.genes
    if (is.null(g2m_genes)) g2m_genes <- cc$g2m.genes
  }
  if (species == "mouse") {
    # Simple case conversion; covers almost all cc.genes. For rigorous
    # orthology use biomaRt or a curated table.
    title_case <- function(x) {
      paste0(toupper(substr(x, 1, 1)),
             tolower(substr(x, 2, nchar(x))))
    }
    s_genes   <- title_case(s_genes)
    g2m_genes <- title_case(g2m_genes)
  }

  # Restrict to genes present in the object (Seurat would warn otherwise)
  present <- rownames(obj@data)
  s_use   <- intersect(s_genes,   present)
  g2m_use <- intersect(g2m_genes, present)
  if (length(s_use) < 5 || length(g2m_use) < 5) {
    warning(sprintf(
      "Few cell cycle genes present after matching (S=%d, G2M=%d). Check species setting.",
      length(s_use), length(g2m_use)
    ))
  }

  seu <- obj@data
  seu <- Seurat::CellCycleScoring(
    seu,
    s.features   = s_use,
    g2m.features = g2m_use,
    set.ident    = FALSE
  )
  seu$CC.Difference <- seu$S.Score - seu$G2M.Score
  obj@data <- seu

  phase_table <- table(obj@data$Phase)
  phase_str <- paste(sprintf("%s=%d", names(phase_table),
                             as.integer(phase_table)),
                     collapse = ", ")

  script <- sprintf(
'# ---- Cell cycle scoring (%s) ----
cc <- Seurat::cc.genes
s_genes   <- cc$s.genes
g2m_genes <- cc$g2m.genes
%sseurat_obj <- CellCycleScoring(seurat_obj,
                                s.features   = s_genes,
                                g2m.features = g2m_genes,
                                set.ident    = FALSE)
seurat_obj$CC.Difference <- seurat_obj$S.Score - seurat_obj$G2M.Score',
    species,
    if (species == "mouse") {
'title_case <- function(x) paste0(toupper(substr(x,1,1)), tolower(substr(x,2,nchar(x))))
s_genes   <- title_case(s_genes)
g2m_genes <- title_case(g2m_genes)
'
    } else ""
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Cell cycle scored (%s): %s. Inspect UMAP by Phase before deciding whether to regress out.",
      species, phase_str
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "sc_cellcycle_score",
    function_name  = "sc_cellcycle_score",
    params         = list(
      species     = species,
      n_s_genes   = length(s_use),
      n_g2m_genes = length(g2m_use),
      phase_counts = as.list(as.integer(phase_table)) |>
        stats::setNames(names(phase_table))
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "cellcycle_scored"
  )
}

# Resolve Tirosh cc.genes across Seurat versions.
# Seurat v4 exported cc.genes; Seurat v5 stopped exporting it but the data
# object still ships in the package data dir. Try in order:
#   1) :: namespace access (works on v4 and old v5 builds)
#   2) data(cc.genes, package="Seurat") into a local env
#   3) hardcoded Tirosh 2016 lists (fallback if all else fails)
.load_cc_genes <- function() {
  # 1) Try direct namespace access
  out <- tryCatch(
    get("cc.genes", envir = asNamespace("Seurat"), inherits = FALSE),
    error = function(e) NULL
  )
  if (!is.null(out) && is.list(out) &&
      !is.null(out$s.genes) && !is.null(out$g2m.genes)) return(out)

  # 2) Try data() into a private environment
  e <- new.env()
  ok <- tryCatch({
    utils::data(list = "cc.genes", package = "Seurat", envir = e)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (ok && exists("cc.genes", envir = e, inherits = FALSE)) {
    out <- get("cc.genes", envir = e, inherits = FALSE)
    if (is.list(out) && !is.null(out$s.genes) && !is.null(out$g2m.genes)) {
      return(out)
    }
  }

  # 3) Hardcoded Tirosh et al. 2016 list (HGNC symbols, human)
  warning("Could not load cc.genes from Seurat; falling back to ",
          "hardcoded Tirosh 2016 list.")
  list(
    s.genes = c(
      "MCM5", "PCNA", "TYMS", "FEN1", "MCM2", "MCM4", "RRM1", "UNG",
      "GINS2", "MCM6", "CDCA7", "DTL", "PRIM1", "UHRF1", "MLF1IP",
      "HELLS", "RFC2", "RPA2", "NASP", "RAD51AP1", "GMNN", "WDR76",
      "SLBP", "CCNE2", "UBR7", "POLD3", "MSH2", "ATAD2", "RAD51",
      "RRM2", "CDC45", "CDC6", "EXO1", "TIPIN", "DSCC1", "BLM",
      "CASP8AP2", "USP1", "CLSPN", "POLA1", "CHAF1B", "BRIP1", "E2F8"
    ),
    g2m.genes = c(
      "HMGB2", "CDK1", "NUSAP1", "UBE2C", "BIRC5", "TPX2", "TOP2A",
      "NDC80", "CKS2", "NUF2", "CKS1B", "MKI67", "TMPO", "CENPF",
      "TACC3", "FAM64A", "SMC4", "CCNB2", "CKAP2L", "CKAP2", "AURKB",
      "BUB1", "KIF11", "ANP32E", "TUBB4B", "GTSE1", "KIF20B", "HJURP",
      "CDCA3", "HN1", "CDC20", "TTK", "CDC25C", "KIF2C", "RANGAP1",
      "NCAPD2", "DLGAP5", "CDCA2", "CDCA8", "ECT2", "KIF23", "HMMR",
      "AURKA", "PSRC1", "ANLN", "LBR", "CKAP5", "CENPE", "CTCF",
      "NEK2", "G2E3", "GAS2L3", "CBX5", "CENPA"
    )
  )
}
