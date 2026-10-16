# The alias layer in R/imports.R binds live dependency token state in .onLoad.
# The
# single-cell ggplot2 NSE variable declarations live here to silence
# R CMD check NOTEs.
utils::globalVariables(c(
  "cc_frac", "doublet_class", "genes",
  "nCount_RNA", "nFeature_RNA", "output", "percent.mt"
))
