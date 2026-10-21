react_loop_fixture <- function(policy = list(mode = "all")) {
  f <- react_tool_fixture()
  state <- .sc_run_load(f$root)
  state$config$provider <- .sc_run_provider_spec("mock")$metadata
  state$config$review <- list(allow_external = FALSE)
  state$config$react <- .sc_run_turn_policy(policy)
  state$config_hash <- .sc_run_hash(state$config)
  evidence <- .sc_run_get(f$root, state, "annotation_evidence")
  evidence$private$cluster_column <- "seurat_clusters"
  evidence$summary$clusters <- lapply(c("0", "1"), function(cluster)
    list(clusterId = cluster, cellCount = 6L, markers = lapply(f$genes[1:30], function(gene)
      list(gene = gene, avgLog2FC = 1, pct1 = .8, pct2 = .1, pAdj = .001))))
  state <- .sc_run_put(f$root, state, "annotation_evidence", evidence)
  .sc_run_save(f$root, state)
  f$baseline <- list(schema = "scagentkit.annotation.v1", annotations = lapply(c("0", "1"),
    function(cluster) list(clusterId = cluster, label = "Unknown", confidence = "low",
      rationale = "Insufficient evidence.", markers = list())))
  f
}

react_final <- function(cluster, gene = "G31", source = "tool:1") {
  risks <- .sc_run_react_unassessed_risks(cluster)
  risks$fields <- lapply(risks$fields, function(x) { x$source <- "model"; x })
  list(schema = "scagentkit.react-draft.v1",
    proposal = list(schema = "scagentkit.annotation.v1", annotations = list(
      list(clusterId = cluster, label = "T cell", confidence = "medium",
        rationale = "Supported by tool:1 tested markers.", markers = list(gene)))),
    citations = list(list(cluster_id = cluster, gene = gene, source = source)), risk_flags = risks)
}

react_mock <- function(mode = "normal") {
  function(messages, ...) {
    cluster <- jsonlite::fromJSON(messages[[2]]$content, simplifyVector = FALSE)$cluster_id
    calls <- sum(vapply(messages, function(x) identical(x$role, "assistant"), logical(1)))
    if (calls == 0L || mode == "forever") {
      out <- turn_reply(tool = TRUE)
      out$message$tool_calls[[1]]$id <- paste0("call_", cluster, "_", calls)
      out$message$tool_calls[[1]]$`function`$arguments <-
        .sc_project_json(list(cluster_id = cluster, n = 50L))
      if (mode == "unknown_then_retry" && calls == 0L)
        out$message$tool_calls[[1]]$`function`$name <- "unknown_tool"
      return(out)
    }
    if (mode == "unknown_then_retry" && calls == 1L) {
      out <- turn_reply(tool = TRUE)
      out$message$tool_calls[[1]]$id <- paste0("retry_", cluster)
      out$message$tool_calls[[1]]$`function`$arguments <- .sc_project_json(list(cluster_id = cluster, n = 50L))
      return(out)
    }
    turn_reply(content = .sc_project_json(react_final(cluster,
      gene = if (mode == "invalid") "G32" else "G31",
      source = if (mode == "unknown_then_retry") "tool:2" else "tool:1")))
  }
}
