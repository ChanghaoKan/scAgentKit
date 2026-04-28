# Centralised metadata introspection.
# Used by qc_split, qc_add_metrics, annot_llm_annotate,
# sc_resolution_recommend, sc_select_batch_var, annot_compare_with_reference.

# Detect species by gene-name pattern.
# Returns "human" | "mouse" | NA (NA if uncertain).
.detect_species <- function(seu) {
  genes <- if (inherits(seu, "Seurat")) {
    rownames(seu)
  } else if (is.list(seu) && length(seu) > 0) {
    rownames(seu[[1]])
  } else {
    return(NA_character_)
  }
  if (length(genes) == 0) return(NA_character_)

  # MT genes: human "MT-XXX" (uppercase), mouse "mt-Xxx" (lowercase prefix)
  has_human_mt <- any(grepl("^MT-", genes))
  has_mouse_mt <- any(grepl("^mt-", genes))

  # Fallback: ribosomal protein conventions
  has_human_rp <- sum(grepl("^RP[SL]", genes)) > 30
  has_mouse_rp <- sum(grepl("^Rp[sl]", genes)) > 30

  if (has_human_mt || has_human_rp) return("human")
  if (has_mouse_mt || has_mouse_rp) return("mouse")

  # Last resort: most genes uppercase = human
  upper_frac <- mean(genes == toupper(genes))
  if (upper_frac > 0.9) return("human")
  if (upper_frac < 0.1) return("mouse")
  NA_character_
}

# Detect existing author celltype column.
# Returns the column name or NA. Looks for common variants and validates
# that values look like cell type strings (not numeric clusters).
#
# `exclude` is for cases where the caller wants to find the AUTHOR's
# original celltype column while ignoring our own LLM output column.
# The default excludes "cell_type" precisely because annot_apply() writes
# the LLM annotation there: when comparing LLM vs author, "cell_type" is
# NOT the reference, "celltype" / "annotation" / etc. is.
.detect_celltype_col <- function(meta, exclude = NULL) {
  candidates <- c(
    "celltype", "CellType", "Cell_Type", "cellType",
    "annotation", "Annotation", "annotations", "Annotations",
    "cell_label", "CellLabel", "label", "Label",
    "broad_celltype", "fine_celltype", "manual_annotation",
    # only consider "cell_type" itself last, since that is what
    # annot_apply() writes
    "cell_type"
  )
  if (!is.null(exclude)) {
    candidates <- setdiff(candidates, exclude)
  }
  hits <- intersect(candidates, colnames(meta))
  for (col in hits) {
    vals <- meta[[col]]
    if (is.numeric(vals)) next                 # skip numeric clusters
    n_lev <- length(unique(vals[!is.na(vals)]))
    if (n_lev < 2 || n_lev > 100) next         # not a proper celltype col
    # Heuristic: average string length should be > 1 char (not just "0", "1")
    str_lens <- nchar(as.character(vals))
    if (mean(str_lens, na.rm = TRUE) < 2) next
    return(col)
  }
  NA_character_
}

# Detect a sample / batch column for splitting.
# Reuses sc_select_batch_var's scoring logic but in a cheap form.
.detect_sample_col <- function(meta, prefer = NULL) {
  if (!is.null(prefer) && prefer %in% colnames(meta)) return(prefer)

  batchy <- c("sample", "batch", "donor", "patient", "lib",
              "run", "lane", "chip", "plate", "channel", "well")
  bio    <- c("treatment", "condition", "group", "disease", "genotype",
              "phenotype", "tumor", "normal", "case", "control",
              "stage", "grade", "response", "subtype", "site", "virus")
  exclude <- c("nCount_RNA", "nFeature_RNA", "percent.mt", "percent.ribo",
               "percent.hb", "S.Score", "G2M.Score", "Phase",
               "CC.Difference", "doublet_class", "doublet_score",
               "seurat_clusters", "cell_type", "celltype",
               "orig.ident")

  scored <- list()
  for (col in colnames(meta)) {
    if (col %in% exclude) next
    if (grepl("^RNA_snn_res\\.", col)) next
    vals <- meta[[col]]
    if (is.numeric(vals) && !is.factor(vals)) next
    levs <- unique(vals[!is.na(vals)])
    n_lev <- length(levs)
    if (n_lev < 2 || n_lev > 200) next

    sizes <- as.integer(table(vals))
    median_size <- stats::median(sizes)

    name_lc <- tolower(col)
    name_batch <- any(vapply(batchy, function(p) grepl(p, name_lc), logical(1)))
    name_bio   <- any(vapply(bio,    function(p) grepl(p, name_lc), logical(1)))

    score <- (if (name_batch) 3 else 0) +
             (if (name_bio)  -5 else 0) +
             (if (n_lev >= 2 && n_lev <= 50) 1 else -1) +
             (if (median_size >= 100) 1 else 0)
    scored[[col]] <- score
  }
  if (length(scored) == 0) return(NA_character_)
  scores <- unlist(scored)
  if (max(scores) < 1) return(NA_character_)
  names(scores)[which.max(scores)]
}

# Default cell-type vocabulary mapping: fine -> broad.
# Used by annot_collapse_to_broad. Users can extend via the `extra_map`
# argument.
.default_broad_map <- function() {
  c(
    # T/NK lineage
    "T cell"           = "T/NK",
    "T cells"          = "T/NK",
    "CD4 T cell"       = "T/NK",
    "CD8 T cell"       = "T/NK",
    "CD4 T"            = "T/NK",
    "CD8 T"            = "T/NK",
    "Treg"             = "T/NK",
    "Regulatory T cell"= "T/NK",
    "MAIT"             = "T/NK",
    "MAIT cell"        = "T/NK",
    "gd T cell"        = "T/NK",
    "Gamma delta T"    = "T/NK",
    "NK cell"          = "T/NK",
    "NK"               = "T/NK",
    "NKT"              = "T/NK",
    "ILC"              = "T/NK",
    "Proliferating T cell"   = "T/NK",
    "Cytotoxic T cell" = "T/NK",
    "Naive T cell"     = "T/NK",
    "Memory T cell"    = "T/NK",
    "Exhausted T cell" = "T/NK",

    # B / Plasma lineage
    "B cell"           = "B",
    "B cells"          = "B",
    "Naive B cell"     = "B",
    "Memory B cell"    = "B",
    "Activated B cell" = "B",
    "Plasma cell"      = "B",
    "Plasmablast"      = "B",

    # Myeloid lineage
    "Macrophage"       = "Myeloid",
    "Macrophages"      = "Myeloid",
    "Monocyte"         = "Myeloid",
    "Monocytes"        = "Myeloid",
    "Dendritic cell"   = "Myeloid",
    "DC"               = "Myeloid",
    "cDC"              = "Myeloid",
    "pDC"              = "Myeloid",
    "Conventional dendritic cell" = "Myeloid",
    "Plasmacytoid dendritic cell" = "Myeloid",
    "Kupffer cell"     = "Myeloid",
    "Neutrophil"       = "Myeloid",
    "MDSC"             = "Myeloid",
    "Mast cell"        = "Myeloid",
    "Basophil"         = "Myeloid",
    "Eosinophil"       = "Myeloid",
    "Microglia"        = "Myeloid",
    "TAM"              = "Myeloid",

    # Stromal: fibroblast lineage
    "Fibroblast"       = "Fibroblast",
    "Fibroblasts"      = "Fibroblast",
    "CAF"              = "Fibroblast",
    "Hepatic stellate cell" = "Fibroblast",
    "Stellate cell"    = "Fibroblast",
    "Pericyte"         = "Fibroblast",
    "Smooth muscle cell" = "Fibroblast",
    "Myofibroblast"    = "Fibroblast",

    # Endothelial
    "Endothelial cell" = "Endothelial",
    "Endothelial"      = "Endothelial",
    "LSEC"             = "Endothelial",
    "Lymphatic endothelial cell" = "Endothelial",
    "Vascular endothelial cell"  = "Endothelial",

    # Epithelial / parenchymal (organ-specific overrides expected)
    "Hepatocyte"       = "Hepatocyte",
    "Malignant hepatocyte" = "Hepatocyte",
    "Tumor cell"       = "Hepatocyte",
    "Cancer cell"      = "Hepatocyte",
    "Cholangiocyte"    = "Hepatocyte",

    # Other epithelial (will pass through if user task is non-liver)
    "Enterocyte"       = "Epithelial",
    "Goblet cell"      = "Epithelial",
    "Secretory epithelial" = "Epithelial",
    "Ciliated cell"    = "Epithelial",
    "Basal cell"       = "Epithelial",
    "Club cell"        = "Epithelial",

    # Misc
    "Erythrocyte"      = "Erythrocyte",
    "RBC"              = "Erythrocyte",
    "Platelet"         = "Platelet",
    "Megakaryocyte"    = "Platelet",
    "Enteric glial cell" = "Glial"
  )
}
