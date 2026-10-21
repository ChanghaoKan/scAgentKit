turn_fixture <- function(external = FALSE, project_consent = TRUE, policy = NULL, priced = TRUE) {
  root <- tempfile("turn-project-"); .sc_project_format_create(root)
  cells <- paste0("private-cell-", 1:8)
  counts <- Matrix::Matrix(matrix(rep(c(1, 3, 0, 4), 40), nrow = 20,
    dimnames = list(paste0("G", 1:20), cells)), sparse = TRUE)
  seu <- Seurat::CreateSeuratObject(counts = counts)
  SeuratObject::LayerData(seu, layer = "data") <- log1p(counts)
  seu$seurat_clusters <- rep(c("0", "1"), each = 4)
  markers <- data.frame(cluster = rep(c("0", "1"), each = 20), gene = rep(rownames(seu), 2),
    avg_log2FC = 1, pct.1 = .8, pct.2 = .2, p_val_adj = .001)
  provider <- .sc_run_provider_spec(list(name = if (external) "deepseek" else "mock",
    generation = list(max_tokens = 64L), pricing = if (external && priced)
      list(input_per_million = .3, output_per_million = 1.2) else NULL))$metadata
  consent <- if (project_consent) .sc_run_transfer_options(list(mode = "project", confirmed = TRUE,
    reviewer = "fixture", reason = "Approve aggregate session scope.",
    categories = c("study_context", "aggregate_qc", "aggregate_markers", "aggregate_design", "aggregate_expression"),
    react = policy), provider) else NULL
  config <- list(assay = "RNA", counts_layer = "counts", normalized_layer = "data",
    cluster_column = "seurat_clusters", context = list(species = "human", tissue = "blood"),
    provider = provider, review = list(allow_external = external, transfer_consent = consent))
  state <- list(project_format_version = .sc_project_format_version(), project_id = "turn-fixture", input_hash = .sc_run_hash(seu), config = config,
    config_hash = .sc_run_hash(config), implementation_hash = .sc_run_implementation(),
    files = list(), history = list(), revision = 0L, stage = "annotation_propose", pending = NULL)
  for (name in c("input", "analysis")) state <- .sc_run_put(root, state, name, seu)
  state <- .sc_run_put(root, state, "markers", list(markers = markers, marker_summary = markers,
    parameters = list(), cluster_column = "seurat_clusters"))
  state <- .sc_run_put(root, state, "annotation_evidence", list(summary = list(),
    private = list(input_cells = data.frame(cell_id = cells, cluster = as.character(seu$seurat_clusters)))))
  .sc_run_save(root, state)
  session <- .sc_run_turn_session(root, "turn-fixture.v1", strrep("a", 64), policy)
  request <- .sc_run_turn_request(session, list(list(role = "system", content = "Use aggregate evidence only."),
    list(role = "user", content = "Cluster 0: 4 cells, G1 positive.")), "0", 1L)
  list(root = root, cells = cells, provider = provider, session = session, request = request)
}
turn_reply <- function(content = '{"draft":true}', tool = FALSE, input = 100, output = 10) {
  message <- if (tool) list(role = "assistant", content = NULL, tool_calls = list(
    list(id = "call_1", type = "function", `function` = list(name = "cluster_markers",
      arguments = '{"cluster_id":"0","n":5}')))) else list(role = "assistant", content = content)
  list(schema_version = "agentomics.turn.v1", message = message,
    finish_reason = if (tool) "tool_calls" else "stop", usage = list(input_tokens = input, output_tokens = output),
    raw_usage = list(prompt_tokens = input, completion_tokens = output, total_tokens = input + output),
    metadata = list(http_status = 200, request_id = "safe-request", model = "deepseek-flash"))
}
turn_call <- function(f, request = f$request, fn = function(...) turn_reply(), ...) {
  .sc_run_call(f$root, request, f$provider, fn, allow_external = f$provider$external, ...)
}
