# Explicit standalone label coarsening dictionary; never applied by the reviewed engine.
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
