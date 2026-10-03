#' Start a server-side, resumable single-cell analysis
#'
#' The first call diagnoses input and obtains a typed QC proposal, then returns
#' at review. It does not execute provider-generated R. Checkpoints, approvals,
#' aggregate request previews and the local annotation bundle stay in project_dir.
#' @param input Named raw counts matrix, Seurat object, or local RDS path.
#' @param project_dir New server-side project directory.
#' @param context Named list with species, tissue, columns and notes.
#' @param provider Provider configuration list, provider name, or NULL.
#' @param chat_fn Explicit provider function, retained only in caller memory.
#' @param budget Maximum reserved USD for this project. Default zero.
#' @param review Review policy; allow_external permits proposing an external
#'   transfer for exact-payload approval; preapprove_qc is an explicit typed rule.
#' @param start_stage 'qc' for raw counts or 'processed' to reuse analysis.
#' @param processed_reason Required provenance for skipping QC and analysis.
#' @param assay,counts_layer,normalized_layer,cluster_column Explicit source layers and membership.
#' @param analysis Named settings passed to sc_project_prepare.
#' @param reference Optional supplied local annotation reference.
#' @param annotation_column New annotation column; choose a fresh name to preserve existing labels.
#' @param qc_proposal,annotation_proposal Optional typed manual proposals.
#' @return Durable run status. Use sc_run_inspect, sc_run_approve and sc_run_resume.
#' @export
sc_run <- function(input, project_dir, context = list(), provider = NULL, chat_fn = NULL,
                   budget = 0, review = list(), start_stage = c("qc", "processed"),
                   processed_reason = NULL, assay = "RNA", counts_layer = "counts",
                   normalized_layer = "data", cluster_column = "seurat_clusters",
                   analysis = list(), reference = NULL, annotation_column = "sc_annotation", qc_proposal = NULL,
                   annotation_proposal = NULL) {
  start_stage <- match.arg(start_stage)
  if (!is.numeric(budget) || length(budget) != 1L || !is.finite(budget) || budget < 0) stop("budget must be nonnegative USD.", call. = FALSE)
  allowed_review <- c("allow_external", "preapprove_qc")
  if (!is.list(review) || any(!names(review) %in% allowed_review)) stop("Unsupported review policy.", call. = FALSE)
  if (!is.null(review$allow_external) && !identical(review$allow_external, TRUE) && !identical(review$allow_external, FALSE)) stop("allow_external must be logical.", call. = FALSE)
  root <- .sc_run_root(project_dir, create = TRUE)
  owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  if (file.exists(file.path(root, "state.rds"))) stop("Run already exists; use sc_run_resume or choose a new project_dir.", call. = FALSE)
  checked <- .sc_run_input(input, context, assay, counts_layer, start_stage, processed_reason,
                           cluster_column = cluster_column, normalized_layer = normalized_layer)
  spec <- .sc_run_provider_spec(provider, chat_fn)
  config <- list(context = checked$context, assay = assay, counts_layer = counts_layer,
                 normalized_layer = normalized_layer, cluster_column = cluster_column,
                 analysis = analysis, markers = list(), annotation_column = annotation_column,
                 budget = budget, review = review, provider = spec$metadata, start_stage = start_stage,
                 processed_reason = processed_reason)
  .sc_project_json_check(config)
  state <- list(project_id = paste0("run-", substr(.sc_run_hash(list(root, Sys.time())), 1, 16)),
                status = "ready", stage = "qc_evidence", revision = 0L, history = list(),
                config = config, config_hash = .sc_run_hash(config), implementation_hash = .sc_run_implementation(),
                source = checked$source, diagnostics = checked$diagnostics, files = list(),
                approvals = list(), transfer_hashes = character(), pending = NULL, approved = NULL,
                completed = character(), nodes = list(qc_evidence = "PLANNED"), failure = NULL, output = NULL)
  state <- .sc_run_put(root, state, "input", checked$seu)
  state$input_hash <- state$files$input$sha256
  if (!is.null(reference)) state <- .sc_run_put(root, state, "reference", reference)
  if (!is.null(qc_proposal)) state <- .sc_run_put(root, state, "manual_qc", qc_proposal)
  if (!is.null(annotation_proposal)) state <- .sc_run_put(root, state, "manual_annotation", annotation_proposal)
  state <- .sc_run_event(state, "planned", list(input_hash = state$input_hash, config_hash = state$config_hash,
                                              implementation_hash = state$implementation_hash))
  if (start_stage == "processed") {
    state$stage <- "markers"; state <- .sc_run_put(root, state, "analysis", checked$seu)
    state$completed <- c("qc_evidence", "qc_propose", "qc_apply", "analysis")
    state <- .sc_run_event(state, "processed_stage_reused", list(reason = processed_reason, source = checked$source,
                                                                skipped = state$completed))
  }
  .sc_run_save(root, state)
  .sc_run_drive(root, state, provider, chat_fn, retry = FALSE)
}

.sc_run_implementation <- function() {
  ns <- environment(.sc_run_drive)
  selected <- sort(grep("^(sc_run|\\.sc_run_)", ls(ns, all.names = TRUE), value = TRUE))
  selected <- unique(c(selected, "sc_project_prepare", ".sc_project_layer", ".sc_project_identity"))
  code <- lapply(selected, function(name) {
    fn <- get(name, envir = ns)
    list(name = name, formals = paste(deparse(formals(fn), width.cutoff = 500L), collapse = "\n"),
         body = paste(deparse(body(fn), width.cutoff = 500L), collapse = "\n"))
  })
  .sc_run_hash(list(code = code, versions = lapply(c("Seurat", "SeuratObject", "agentomicsCore"), function(p) as.character(utils::packageVersion(p)))))
}

.sc_run_crash <- function(point) {
  if (identical(getOption("scAgentKit.run_crash"), point)) stop(paste0("Injected crash at ", point), call. = FALSE)
}
.sc_run_checkpoint <- function(root, state, stage, next_stage) {
  .sc_run_crash(paste0(stage, ":artifact"))
  # Artifacts are complete and checksummed before state references become visible.
  for (record in state$files) if (!identical(record$sha256, .sc_project_sha_file(file.path(root, record$path)))) stop("Artifact verification failed.", call. = FALSE)
  state$completed <- unique(c(state$completed, stage)); state$nodes[[stage]] <- "EXECUTED"
  if (next_stage != "complete") state$nodes[[next_stage]] <- "PLANNED"
  state$stage <- next_stage; state$status <- if (next_stage == "complete") "complete" else "ready"; state$failure <- NULL
  state <- .sc_run_event(state, "executed", list(stage = stage, files = state$files))
  .sc_run_save(root, state)
  .sc_run_crash(paste0(stage, ":checkpoint"))
  state
}

#' Resume a saved run in a new R process
#' @param project_dir Server-side project directory.
#' @param provider,chat_fn Provider configuration/function for new requests only.
#' @param retry Explicitly retry a failed computation; uncertain external requests
#'   remain held and require provider reconciliation rather than automatic replay.
#' @return Updated durable status.
#' @export
sc_run_resume <- function(project_dir, provider = NULL, chat_fn = NULL, retry = FALSE) {
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  if (!identical(state$config_hash, .sc_run_hash(state$config)) || !identical(state$implementation_hash, .sc_run_implementation()))
    stop("Configuration or implementation changed. Existing approvals are stale; start a new project.", call. = FALSE)
  state <- .sc_run_cleanup(root, state)
  if (state$status == "complete" || state$status %in% c("awaiting_review", "rejected")) return(.sc_run_public(state))
  if (state$status %in% c("failed", "running") && !isTRUE(retry)) return(.sc_run_public(state))
  if (is.null(provider)) provider <- state$config$provider
  if (!identical(.sc_run_provider_spec(provider, chat_fn)$metadata, state$config$provider)) stop("Provider/model/settings changed; start a new project or restore the approved provider configuration.", call. = FALSE)
  if (state$status %in% c("failed", "running")) {
    state <- .sc_run_event(state, "retry_requested", list(stage = state$stage))
    state$status <- "ready"; state$failure <- NULL; .sc_run_save(root, state)
  }
  .sc_run_drive(root, state, provider, chat_fn, retry)
}
.sc_run_request <- function(kind, evidence, config) {
  schema <- if (kind == "qc") {
    "Return only JSON: {\"schema\":\"scagentkit.qc.v1\",\"rationale\":\"...\",\"risks\":[\"...\"],\"filters\":[{\"op\":\"range\",\"metric\":\"nFeature\",\"min\":0,\"max\":5000,\"group\":null}]}. Supported metrics: nCount,nFeature,percent_mt. Optional group only literal sample and/or capture in evidence. Thresholds must follow actual quantiles and context; no arbitrary code, batch selection or unsupported actions. Acknowledge uncertainty; no fixed universal threshold."
  } else {
    "Return only JSON: {\"schema\":\"scagentkit.annotation.v1\",\"annotations\":[{\"clusterId\":\"literal ID\",\"label\":\"unknown or type\",\"confidence\":\"low|medium|high\",\"rationale\":\"...\",\"markers\":[\"GENE\"]}]}. Cite only marker genes actually provided for each cluster. Preserve unknown when uncertain. These are independent suggestions for human review, not automatic scientific acceptance."
  }
  list(system_prompt = paste("You assist a single-cell analyst using only supplied aggregate evidence.", schema),
       user_prompt = .sc_project_json(list(context = config$context, evidence = evidence)),
       purpose = kind, evidence_hash = .sc_run_hash(evidence))
}
.sc_run_get_proposal <- function(root, state, kind, evidence, provider, chat_fn, retry) {
  manual <- paste0("manual_", kind)
  if (!is.null(state$files[[manual]])) return(list(state = state, proposal = .sc_run_get(root, state, manual)))
  spec <- .sc_run_provider_spec(provider, chat_fn)
  if (is.null(spec$metadata) || identical(spec$metadata$name, "manual")) {
    state$status <- "awaiting_configuration"
    state <- .sc_run_event(state, "manual_configuration_needed", list(stage = state$stage, kind = kind))
    .sc_run_save(root, state); return(list(state = state, proposal = NULL))
  }
  request <- .sc_run_request(kind, evidence, state$config)
  request_hash <- .sc_run_request_hash(request, provider, chat_fn)
  state <- .sc_run_put(root, state, paste0(kind, "_request"), request)
  external <- isTRUE(spec$metadata$external)
  if (external && !request_hash %in% state$transfer_hashes) {
    if (!isTRUE(state$config$review$allow_external)) {
      state$status <- "awaiting_configuration"
      state <- .sc_run_event(state, "external_transfer_disabled", list(request_hash = request_hash))
    } else {
      state <- .sc_run_pending(state, "external_transfer", list(request_hash = request_hash,
        payload = list(system_prompt = request$system_prompt, user_prompt = request$user_prompt),
        provider = spec$metadata, notice = "Aggregate QC/markers and supplied context leave this machine. Raw matrices, cell IDs and per-cell metadata are excluded; declared aggregate sample/capture labels and supplied context are transmitted."), request$evidence_hash)
    }
    .sc_run_save(root, state); return(list(state = state, proposal = NULL))
  }
  request$approved_payload_hash <- if (external) request_hash else NULL
  local_evidence <- .sc_run_get(root, state, paste0(kind, "_evidence"))
  request$validator <- if (kind == "qc") function(x) .sc_run_qc_validate(x, local_evidence)$proposal else function(x) { value <- .sc_run_annotation_validate(x, local_evidence); list(schema = value$schema, annotations = value$annotations) }
  .sc_run_save(root, state)
  answer <- .sc_run_call(root, request, provider, chat_fn, state$config$budget,
                         allow_external = external, retry = retry)
  if (!identical(answer$status, "ok")) stop(paste0("Provider request stopped: ", answer$status), call. = FALSE)
  state <- .sc_run_put(root, state, paste0(kind, "_response"), answer)
  state <- .sc_run_event(state, "proposal_received", list(request_hash = request_hash,
                                                        provider = answer$provider, cost = answer$cost_usd))
  list(state = state, proposal = answer$content)
}
.sc_run_drive <- function(root, state, provider, chat_fn, retry) {
  repeat {
    stage <- state$stage
    if (state$status %in% c("awaiting_review", "rejected", "complete")) return(.sc_run_public(state))
    before <- state
    state$status <- "running"; state$nodes[[stage]] <- "RUNNING"
    state <- .sc_run_event(state, "running", list(stage = stage)); .sc_run_save(root, state)
    result <- tryCatch({
      if (stage == "qc_evidence") {
        evidence <- .sc_run_qc_evidence(.sc_run_get(root, state, "input"), state$config$context, state$config$assay, state$config$counts_layer)
        state <- .sc_run_put(root, state, "qc_evidence", evidence)
        state <- .sc_run_checkpoint(root, state, stage, "qc_propose")
      } else if (stage == "qc_propose") {
        evidence <- .sc_run_get(root, state, "qc_evidence")
        proposed <- .sc_run_get_proposal(root, state, "qc", evidence$summary, provider, chat_fn, retry)
        state <- proposed$state
        if (is.null(proposed$proposal)) return(.sc_run_public(state))
        validated <- .sc_run_qc_validate(proposed$proposal, evidence)
        state <- .sc_run_put(root, state, "qc_validated", validated)
        state$nodes[[stage]] <- "PROPOSED"
        state <- .sc_run_pending(state, "qc", list(rules = validated$proposal, retention = validated$retention), .sc_run_hash(evidence), "qc_apply")
        if (!is.null(state$config$review$preapprove_qc) && identical(validated$proposal, .sc_run_qc_validate(state$config$review$preapprove_qc, evidence)$proposal)) {
          hash <- state$pending$hash
          state <- .sc_run_event(state, "approved", list(kind = "qc", proposal_hash = hash, reviewer = "explicit_preapproved_rule", input_hash = state$input_hash, config_hash = state$config_hash))
          state$approvals[[hash]] <- tail(state$history, 1)[[1]]$details
          state$approved <- state$pending; state$pending <- NULL; state$stage <- "qc_apply"; state$status <- "ready"
        }
        .sc_run_save(root, state)
      } else if (stage == "qc_apply") {
        .sc_run_require_approval(state, "qc")
        seu <- .sc_run_qc_apply(.sc_run_get(root, state, "input"), .sc_run_get(root, state, "qc_validated"), .sc_run_get(root, state, "qc_evidence"))
        state <- .sc_run_put(root, state, "qc_object", seu)
        state <- .sc_run_checkpoint(root, state, stage, "analysis")
      } else if (stage == "analysis") {
        seu <- .sc_run_analyze(.sc_run_get(root, state, "qc_object"), state$config)
        state <- .sc_run_put(root, state, "analysis", seu)
        state <- .sc_run_checkpoint(root, state, stage, "markers")
      } else if (stage == "markers") {
        markers <- .sc_run_markers(.sc_run_get(root, state, "analysis"), state$config)
        state <- .sc_run_put(root, state, "markers", markers)
        state <- .sc_run_checkpoint(root, state, stage, "annotation_evidence")
      } else if (stage == "annotation_evidence") {
        reference <- if (is.null(state$files$reference)) NULL else .sc_run_get(root, state, "reference")
        evidence <- .sc_run_annotation_evidence(.sc_run_get(root, state, "analysis"), .sc_run_get(root, state, "markers"), state$config$context, reference, cluster_column = state$config$cluster_column)
        state <- .sc_run_put(root, state, "annotation_evidence", evidence)
        state <- .sc_run_checkpoint(root, state, stage, "annotation_propose")
      } else if (stage == "annotation_propose") {
        evidence <- .sc_run_get(root, state, "annotation_evidence")
        proposed <- .sc_run_get_proposal(root, state, "annotation", evidence$summary, provider, chat_fn, retry)
        state <- proposed$state
        if (is.null(proposed$proposal)) return(.sc_run_public(state))
        validated <- .sc_run_annotation_validate(proposed$proposal, evidence)
        state <- .sc_run_put(root, state, "annotation_validated", validated)
        state$nodes[[stage]] <- "PROPOSED"
        state <- .sc_run_pending(state, "annotation", validated, .sc_run_hash(evidence), "annotation_apply")
        .sc_run_save(root, state)
      } else if (stage == "annotation_apply") {
        .sc_run_require_approval(state, "annotation")
        seu <- .sc_run_annotation_apply(.sc_run_get(root, state, "analysis"), .sc_run_get(root, state, "annotation_validated"), state$config$annotation_column)
        state <- .sc_run_put(root, state, "annotated", seu)
        state <- .sc_run_checkpoint(root, state, stage, "finalize")
      } else if (stage == "finalize") {
        state <- .sc_run_finish(root, state)
        state <- .sc_run_checkpoint(root, state, stage, "complete")
        state$status <- "complete"; .sc_run_save(root, state)
      } else stop("Unknown coordinator stage.", call. = FALSE)
      list(ok = TRUE)
    }, error = function(e) list(ok = FALSE, error = conditionMessage(e)))
    if (!result$ok) {
      # If publication succeeded before an injected crash, recover its committed state.
      published <- .sc_run_load(root)
      if (stage %in% published$completed && published$stage != stage) return(.sc_run_public(published))
      state <- before; state$status <- "failed"; state$nodes[[stage]] <- "FAILED"
      state$failure <- list(stage = stage, message = result$error, retry = "Explicit retry only; external uncertain dispatches retain their reservations.")
      state <- .sc_run_event(state, "failed", state$failure); .sc_run_save(root, state)
      return(.sc_run_public(state))
    }
  }
}
.sc_run_require_approval <- function(state, kind) {
  if (is.null(state$approved) || state$approved$kind != kind || is.null(state$approvals[[state$approved$hash]]) || !isTRUE(.sc_run_check_binding(state, state$approved)))
    stop("Required exact proposal approval is absent.", call. = FALSE)
}
.sc_run_finish <- function(root, state) {
  nFeature <- NULL
  seu <- .sc_run_get(root, state, "annotated"); markers <- .sc_run_get(root, state, "markers")
  evidence <- .sc_run_get(root, state, "annotation_evidence")
  bundle <- .sc_run_bundle(seu, markers, evidence$private$candidates, root, state$config)
  dir.create(file.path(root, "output"), showWarnings = FALSE)
  .sc_run_atomic(seu, file.path(root, "output", "seurat.rds"))
  utils::write.csv(markers$markers, file.path(root, "output", "markers.csv"), row.names = FALSE)
  utils::write.csv(seu[[]], file.path(root, "output", "metadata.csv"), row.names = TRUE)
  .sc_run_atomic(state$config, file.path(root, "output", "parameters.json"), json = TRUE)
  if ("umap" %in% names(seu@reductions)) ggplot2::ggsave(file.path(root, "output", "umap.png"), Seurat::DimPlot(seu, reduction = "umap", group.by = state$config$annotation_column), width = 7, height = 5)
  if (!is.null(state$files$qc_evidence)) {
    qc <- .sc_run_get(root, state, "qc_evidence")$metrics
    plot <- ggplot2::ggplot(qc, ggplot2::aes(x = nFeature)) + ggplot2::geom_histogram(bins = 40) + ggplot2::theme_minimal()
    ggplot2::ggsave(file.path(root, "output", "qc.png"), plot, width = 7, height = 4)
  }
  writeLines(c("library(scAgentKit)", sprintf("project_dir <- %s", deparse(root)), "sc_run_inspect(project_dir)", "# Reattach your provider only if new calls are needed.", "sc_run_resume(project_dir)"), file.path(root, "resume.R"))
  report <- c("# scAgentKit server-side analysis", paste("Project:", state$project_id), paste("Input SHA256:", state$input_hash), paste("Config SHA256:", state$config_hash), paste("Implementation SHA256:", state$implementation_hash),
              paste("Cells:", ncol(seu), "Features:", nrow(seu)), "QC and annotation approvals are recorded in decision_history.json.",
              "Computed artifacts are EXECUTED; overall scientific conclusions require separate analyst acceptance.",
              "Batch integration skipped. Condition and capture were not inferred as batch/donor.",
              "Local annotation evidence bundle is in bundle/. No manual archive transfer is required.",
              "External request and usage accounting is in provider/ when a provider was used.")
  writeLines(report, file.path(root, "output", "report.md"))
  paths <- list.files(file.path(root, "output"), full.names = TRUE)
  for (path in c(paths, file.path(root, "resume.R"), list.files(file.path(root, "bundle"), recursive = TRUE, full.names = TRUE))) {
    relative <- substring(path, nchar(root) + 2L)
    state$files[[paste0("output:", relative)]] <- list(path = relative, sha256 = .sc_project_sha_file(path))
  }
  state$output <- list(seurat = file.path(root, "output", "seurat.rds"), bundle = bundle$path,
                       report = file.path(root, "output", "report.md"), scientific_result = "EXECUTED")
  state
}

#' Supply or replace a typed manual QC/annotation proposal
#' @param project_dir Run directory.
#' @param proposal Typed QC or annotation proposal, never executable code.
#' @param reviewer,reason Analyst identity and rationale.
#' @return Updated status, awaiting exact proposal approval.
#' @export
sc_run_propose <- function(project_dir, proposal, reviewer, reason) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_cleanup(root, .sc_run_load(root))
  if (is.character(proposal) && length(proposal) == 1L) {
    raw <- rawToChar(.sc_review_read(proposal, limit = 100000L))
    parsed <- .sc_run_provider_parse(raw)
    if (parsed$status != "ok") stop("Invalid typed proposal file.", call. = FALSE)
    proposal <- parsed$content
  }
  if (!state$stage %in% c("qc_propose", "annotation_propose")) stop("Manual proposals are only accepted at a proposal stage.", call. = FALSE)
  kind <- if (state$stage == "qc_propose") "qc" else "annotation"
  evidence <- .sc_run_get(root, state, paste0(kind, "_evidence"))
  if (kind == "qc") .sc_run_qc_validate(proposal, evidence) else .sc_run_annotation_validate(proposal, evidence)
  state <- .sc_run_put(root, state, paste0("manual_", kind), proposal)
  state$pending <- NULL; state$approved <- NULL; state$status <- "ready"
  state <- .sc_run_event(state, "manual_proposal", list(kind = kind, reviewer = reviewer, reason = reason, hash = .sc_run_hash(proposal)))
  .sc_run_save(root, state)
  .sc_run_drive(root, state, state$config$provider, NULL, FALSE)
}

#' Undo accepted annotation writeback while retaining decision history
#' @param project_dir Run directory.
#' @param decision_id Annotation approval ID returned in decision history.
#' @param reviewer,reason Analyst identity and reason.
#' @return Status ready for a new annotation proposal. Previous versioned artifacts remain.
#' @export
sc_run_undo <- function(project_dir, decision_id, reviewer, reason) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  matches <- Filter(function(x) identical(x$decision_id, decision_id) && identical(x$kind, "annotation"), state$approvals)
  if (!length(matches) || !"annotation_apply" %in% state$completed) stop("No executed annotation decision matches this ID.", call. = FALSE)
  if (any(vapply(state$history, function(e) e$action == "annotation_undone" && identical(e$details$decision_id, decision_id), logical(1)))) stop("Decision already undone.", call. = FALSE)
  state <- .sc_run_event(state, "annotation_undone", list(decision_id = decision_id, reviewer = reviewer, reason = reason))
  # Archive convenience outputs; immutable checkpoint versions and history remain.
  archive <- file.path(root, "versions", paste0("undo-", state$revision)); dir.create(archive, recursive = TRUE, showWarnings = FALSE)
  for (name in c("output", "bundle")) if (dir.exists(file.path(root, name))) {
    if (!file.copy(file.path(root, name), archive, recursive = TRUE)) stop("Cannot archive previous outputs.", call. = FALSE)
    original <- list.files(file.path(root, name), recursive = TRUE, full.names = TRUE)
    for (file in original) {
      copy <- file.path(archive, substring(file, nchar(root) + 2L))
      if (!identical(.sc_project_sha_file(file), .sc_project_sha_file(copy))) stop("Archive checksum mismatch.", call. = FALSE)
    }
  }
  .sc_run_crash("undo:archive")
  state$cleanup <- c("output", "bundle")
  state$files <- state$files[!startsWith(names(state$files), "output:")]
  state$files$annotated <- NULL; state$files$annotation_validated <- NULL; state$files$manual_annotation <- NULL
  state$stage <- "annotation_propose"; state$status <- "awaiting_configuration"; state$pending <- NULL; state$approved <- NULL; state$output <- NULL
  state$completed <- setdiff(state$completed, c("annotation_apply", "finalize"))
  .sc_run_save(root, state)
  .sc_run_crash("undo:checkpoint")
  state <- .sc_run_cleanup(root, state)
  .sc_run_public(state)
}

.sc_run_cleanup <- function(root, state) {
  if (length(state$cleanup)) {
    for (name in state$cleanup) unlink(file.path(root, name), recursive = TRUE)
    state$cleanup <- NULL; .sc_run_save(root, state)
  }
  state
}

#' Record analyst acceptance of the completed scientific result
#' @param project_dir Run directory.
#' @param reviewer,reason Analyst identity and scientific assessment.
#' @return Completed run status with RESULT_ACCEPTED.
#' @export
sc_run_accept <- function(project_dir, reviewer, reason) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  if (state$status != "complete") stop("Only a completed result can be accepted.", call. = FALSE)
  state$output$scientific_result <- "RESULT_ACCEPTED"
  state <- .sc_run_event(state, "result_accepted", list(reviewer = reviewer, reason = reason, output = state$output))
  .sc_run_save(root, state); .sc_run_public(state)
}
