# scAgentKit has no special package-load side effects beyond what the
# alias layer in R/imports.R sets up at namespace-build time. The
# single-cell ggplot2 NSE variable declarations live here to silence
# R CMD check NOTEs.
utils::globalVariables(c(
  "cc_frac", "doublet_class", "genes",
  "nCount_RNA", "nFeature_RNA", "output", "percent.mt"
))
