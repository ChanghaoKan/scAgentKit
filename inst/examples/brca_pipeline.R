# Study-specific context enters the same project engine; no disease-specific tuning.
# Supply genuine counts/Seurat and explicit study facts. This stops for review.
brca_pipeline <- function(input,project_dir,context) {
  if(is.null(context$species)||is.null(context$tissue))
    stop("Declare the actual species and tissue; no disease or batch is inferred.",call.=FALSE)
  scAgentKit::sc_review(scAgentKit::sc_analyze(input,project_dir,context=context))
}
