# This helper reads only caller-supplied 10x MEX directories and metadata.
# samples needs sample_id, path and matrix_kind (raw/filtered) per sample.
# cell_metadata joins by exact sample_id + barcode; context declares real roles.
# A filtered matrix alone does not establish capture/donor facts or a complete
# called-cell scoring cohort. The package will disclose missing prerequisites.
tenx_multisample_start <- function(samples,cell_metadata,context,project_dir,
                                   provider=NULL,budget=0,
                                   review=list(allow_external=FALSE),browse=interactive()) {
  scAgentKit::sc_start(samples,project_dir,context=context,cell_metadata=cell_metadata,
    feature_key="id",provider=provider,budget=budget,review=review,browse=browse)
}
# Example shape only; replace all paths and biological facts deliberately:
# samples <- data.frame(sample_id=c("sample_A","sample_B"),
#   path=c("/absolute/A/filtered_feature_bc_matrix","/absolute/B/filtered_feature_bc_matrix"),
#   matrix_kind=c("filtered","filtered"))
# context <- list(species="human",tissue="your tissue",
#   columns=list(sample="sample_id",donor="donor",condition="condition"))
# Keep original barcode/feature identities; no guessed technical-batch role.
