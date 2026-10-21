library(scAgentKit)
data("pbmc_small", package="SeuratObject")
root <- commandArgs(TRUE)[1]
stopifnot(!dir.exists(root))
proposal <- list(schema = "scagentkit.strategy.v1", rationale = "Software control.",
    risks = list("No biological validation."), inferences = list(),
    qc = list(schema = "scagentkit.qc.rules.v1", remove_if = "any", rationale = "Keep positive-count fixture cells.",
      risks = list(), rules = list(list(op = "range", metric = "nCount", min = 1L))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 50L, npcs = 10L, seed = 1L),
    pcs = list(method = "fixed", ndim = 5L),
    batch = list(method = "none", reason = "No technical design supplied."),
    clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .4)),
    umap = list(run = FALSE, n_neighbors = 10L))
  out <- suppressWarnings(sc_run(pbmc_small, root, context = list(species = "human", tissue = "blood"),
    strategy = TRUE, biological_diagnostics = TRUE, strategy_proposal = proposal))

stopifnot(out$status == "awaiting_review")
