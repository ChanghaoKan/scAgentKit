# Literal ribosomal-symbol conventions shared by measured QC and its standalone utility.
.sc_run_ribo_pattern <- function(species) {
  switch(species, human="^(RP[SL][0-9]+[ALXY]?[0-9]*|RPSA|RPLP[012]|RPL36AL)$",
    mouse="^(Rp[sl][0-9]+[alxy]?[0-9]*|Rpsa|Rplp[012]|Rpl36al)$", NULL)
}
