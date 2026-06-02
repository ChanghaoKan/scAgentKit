# Seurat v5 compatibility helpers (scAgentKit-internal).
#
# Moved here from agentomicsCore: these call Seurat:: / SeuratObject::
# and are therefore single-cell specific. agentomicsCore deliberately
# does not depend on Seurat.
#
# Seurat v5 splits counts/data/scale.data into "layers" on the Assay5
# object, and a merged object can hold multiple counts layers (counts.1,
# counts.2, ...) until `JoinLayers()` is called. Many Seurat verbs refuse
# to work on unjoined multi-layer objects (VlnPlot, as.SingleCellExperiment,
# subset with features=, etc.). The helpers below centralise the
# "join if v5 and multi-layer" logic so every tool can be v5-safe with
# one line.

# Return TRUE iff the object's default assay is Seurat v5 (Assay5).
.is_v5_assay <- function(seu) {
  default <- Seurat::DefaultAssay(seu)
  methods::is(seu[[default]], "Assay5")
}

# Return TRUE iff the v5 assay currently holds more than one layer for
# the given `layer_type` (one of "counts", "data", "scale.data"). On v3
# objects, always returns FALSE.
.has_split_layers <- function(seu, layer_type = "counts") {
  if (!.is_v5_assay(seu)) return(FALSE)
  default <- Seurat::DefaultAssay(seu)
  layers  <- SeuratObject::Layers(seu[[default]])
  matches <- grep(sprintf("^%s(\\.|$)", layer_type), layers, value = TRUE)
  length(matches) > 1
}

# Ensure the given layer is joined. For v5 with split layers, call
# JoinLayers on the default assay. No-op otherwise.
.ensure_joined <- function(seu, layer_type = "counts") {
  if (.has_split_layers(seu, layer_type)) {
    default <- Seurat::DefaultAssay(seu)
    seu[[default]] <- SeuratObject::JoinLayers(seu[[default]])
  }
  seu
}
