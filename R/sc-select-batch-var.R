#' Score and recommend batch variable(s) for integration
#'
#' Scans all metadata columns and ranks them as candidates for
#' `group.by.vars` in [sc_harmony()] (or any other integration tool).
#' Avoids the common error of either (a) hardcoding `"sample"` when the
#' column has a different name, or (b) silently picking a biological
#' variable (treatment / genotype / disease group) and washing out the
#' signal you want to study.
#'
#' Two modes:
#' \itemize{
#'   \item \code{interactive = FALSE} (default): returns the scored
#'     table without taking action. The caller picks one and passes it to
#'     [sc_harmony()].
#'   \item \code{chat_fn} supplied: an LLM is asked to pick from the
#'     scored table given a tissue / study description. Returns the same
#'     scored table plus a recommendation block.
#' }
#'
#' Scoring heuristics (higher = better candidate for batch correction):
#' \itemize{
#'   \item Name match against batch-y patterns (`batch`, `seq`, `lib`,
#'     `run`, `lane`, `donor`, `sample`, `chip`).
#'   \item Cardinality between 2 and ~30 (too many = ID column,
#'     `1` = nothing to correct).
#'   \item Each level should hold a meaningful chunk of cells (median
#'     level size > 50). Tiny levels suggest noise.
#'   \item Penalises columns that look biological (`treatment`,
#'     `condition`, `group`, `disease`, `genotype`, `phenotype`,
#'     `tumor`, `normal`, `case`, `control`) — these should NOT be the
#'     batch variable.
#' }
#'
#' @param obj An AgentSeurat object containing a single Seurat object.
#' @param chat_fn Optional `function(system_prompt, user_prompt) ->
#'   character` returning a JSON object. If provided, an LLM
#'   recommendation is computed.
#' @param tissue Optional character describing the study (e.g.
#'   `"breast cancer scRNA-seq, multiple donors"`). Only used for the
#'   LLM call.
#' @param max_levels Integer. Columns with more than this many distinct
#'   values are excluded (likely cell-id / barcode columns). Default 200.
#' @param top_n Integer, how many candidates to keep. Default 8.
#' @param max_retries Integer for the LLM call. Default 2.
#'
#' @return Updated AgentSeurat. The scored table is stored at
#'   `obj@params$batch_candidates`; if `chat_fn` was supplied, a
#'   recommendation is stored at `obj@params$batch_recommendation`.
#' @export
sc_select_batch_var <- function(obj,
                                chat_fn     = NULL,
                                tissue      = NULL,
                                max_levels  = 200,
                                top_n       = 8,
                                max_retries = 2) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat") {
    stop("sc_select_batch_var expects a single merged Seurat object.")
  }

  # v0.2.0: snapshot token state at entry for per-step accounting
  .tok_before <- length(.token_state$records)

  meta <- obj@data@meta.data
  n_cells <- nrow(meta)

  # Patterns
  batchy <- c("batch", "seq", "lib", "run", "lane", "donor",
              "sample", "chip", "plate", "channel", "10x", "well")
  bio    <- c("treatment", "condition", "group", "disease", "genotype",
              "phenotype", "tumor", "normal", "case", "control",
              "stage", "grade", "response", "subtype",
              # v0.1.6: explicit cell-state / annotation columns
              "celltype", "cell_type", "cell.type", "annotation",
              "cluster", "state", "phase", "site", "virus",
              "label")
  exclude <- c("nCount_RNA", "nFeature_RNA", "percent.mt", "percent.ribo",
               "percent.hb", "S.Score", "G2M.Score", "Phase",
               "CC.Difference", "doublet_class", "doublet_score",
               "seurat_clusters", "cell_type", "celltype",
               "CellType", "Cell_Type", "annotation", "Annotation")

  candidates <- list()
  for (col in colnames(meta)) {
    if (col %in% exclude) next
    if (grepl("^RNA_snn_res\\.", col)) next
    vals <- meta[[col]]
    if (is.numeric(vals) && !is.factor(vals)) next      # skip QC numerics
    levs <- unique(vals[!is.na(vals)])
    n_lev <- length(levs)
    if (n_lev < 2 || n_lev > max_levels) next

    sizes <- as.integer(table(vals))
    median_size <- stats::median(sizes)
    smallest_size <- min(sizes)

    name_lc <- tolower(col)
    name_batch <- any(vapply(batchy, function(p) grepl(p, name_lc), logical(1)))
    name_bio   <- any(vapply(bio,    function(p) grepl(p, name_lc), logical(1)))

    # Score components (kept transparent so the LLM can see them)
    s_name      <- if (name_batch) 2 else 0
    s_bio_pen   <- if (name_bio)  -3 else 0
    s_levels    <- if (n_lev >= 2 && n_lev <= 30) 1 else if (n_lev <= 50) 0 else -1
    s_size      <- if (median_size >= 100) 1 else if (median_size >= 30) 0 else -1
    s_smallest  <- if (smallest_size >= 30) 1 else if (smallest_size >= 10) 0 else -1
    score <- s_name + s_bio_pen + s_levels + s_size + s_smallest

    candidates[[col]] <- data.frame(
      column         = col,
      n_levels       = n_lev,
      median_size    = as.integer(median_size),
      smallest_size  = smallest_size,
      name_match     = name_batch,
      looks_biological = name_bio,
      score          = score,
      stringsAsFactors = FALSE
    )
  }

  if (length(candidates) == 0) {
    stop("No suitable batch-variable candidates found in metadata.")
  }
  scored <- do.call(rbind, candidates)
  scored <- scored[order(-scored$score, -scored$name_match), , drop = FALSE]
  rownames(scored) <- NULL
  if (nrow(scored) > top_n) scored <- scored[seq_len(top_n), ]

  obj@params$batch_candidates <- scored

  # Optional LLM recommendation
  recommendation <- NULL
  if (!is.null(chat_fn)) {
    if (!requireNamespace("jsonlite", quietly = TRUE)) {
      stop("jsonlite is required for LLM recommendation.")
    }
    recommendation <- .llm_pick_batch_var(scored, chat_fn,
                                          tissue = tissue,
                                          max_retries = max_retries)
    obj@params$batch_recommendation <- recommendation
  }

  rationale <- if (!is.null(recommendation)) {
    sprintf(
      "Scored %d batch-variable candidates; LLM recommended '%s' (confidence: %s).",
      nrow(scored),
      as.character(recommendation$recommended %||% NA),
      as.character(recommendation$confidence %||% NA)
    )
  } else {
    sprintf("Scored %d batch-variable candidates; top: %s (score=%s).",
            nrow(scored), scored$column[1], scored$score[1])
  }

  script <- paste0(
'# ---- Batch variable scoring ----
# Top candidates from metadata (see obj@params$batch_candidates):',
    paste0("\n#   ", apply(scored, 1, function(r) {
      sprintf("%s  (n_levels=%s, median_size=%s, score=%s%s%s)",
              r["column"], r["n_levels"], r["median_size"], r["score"],
              if (as.logical(r["name_match"])) ", name_match" else "",
              if (as.logical(r["looks_biological"])) ", LOOKS_BIOLOGICAL" else "")
    }), collapse = "")
  )

  obj <- .record_step(
    obj            = obj,
    step_name      = "sc_select_batch_var",
    function_name  = "sc_select_batch_var",
    params         = list(
      candidates_top   = scored$column,
      candidates_score = scored$score,
      llm_recommended  = if (!is.null(recommendation)) recommendation$recommended else NA
    ),
    rationale      = rationale,
    script_snippet = script
  )

  # NOTE: .record_step writes its `params` arg into obj@params (overwriting
  # the slot). We re-attach the rich batch_candidates / batch_recommendation
  # fields AFTER recording so callers can inspect them.
  obj@params$batch_candidates <- scored
  if (!is.null(recommendation)) {
    obj@params$batch_recommendation <- recommendation
  }
  obj <- .attach_step_tokens(obj, "sc_select_batch_var", .tok_before)
  obj
}

# ---- Internal: LLM picker --------------------------------------------------

.llm_pick_batch_var <- function(scored, chat_fn, tissue = NULL,
                                max_retries = 2) {

  evidence <- paste(
    c("column | n_levels | median_size | smallest_size | name_match | looks_biological | score",
      "-------|----------|-------------|---------------|------------|------------------|------"),
    collapse = "\n"
  )
  rows <- apply(scored, 1, function(r) {
    sprintf("%s | %s | %s | %s | %s | %s | %s",
            r["column"], r["n_levels"], r["median_size"], r["smallest_size"],
            r["name_match"], r["looks_biological"], r["score"])
  })
  evidence <- paste(c(evidence, rows), collapse = "\n")

  system_prompt <- paste0(
    "You select a metadata column to use as the batch variable for ",
    "Harmony integration of single-cell RNA-seq data.\n\n",
    "Return ONE JSON object with exactly these fields, no prose, no fences:\n\n",
    "{\n",
    '  "recommended": "<column_name>",\n',
    '  "confidence": "<high|medium|low>",\n',
    '  "alternatives": ["<column>", "<column>"],\n',
    '  "warnings": ["<short notes about risks; empty list if none>"],\n',
    '  "reasoning": "<2-4 sentences>"\n',
    "}\n\n",
    "Decision rules:\n",
    "- The batch variable should capture TECHNICAL variation across ",
    "samples / runs / lanes / donors. Never pick a column that encodes ",
    "the biological contrast you are studying (treatment vs control, ",
    "tumor vs normal, genotype, disease group, etc.).\n",
    "- If `looks_biological` is TRUE, exclude that column unless you have ",
    "strong reason to override (and explain in `warnings`).\n",
    "- Prefer columns with `name_match = TRUE` and 2-30 levels.\n",
    "- A column with a single level (n_levels=1) is useless. A column ",
    "with hundreds of levels is usually a cell ID, not a batch.\n",
    "- If multiple candidates look equally valid, pick the one with the ",
    "best balance of coverage (median_size > 50) and reasonable level ",
    "count.\n",
    "- The recommended column MUST appear in the table; never invent a ",
    "name.\n"
  )

  user_prompt <- paste0(
    if (!is.null(tissue)) sprintf("Study context: %s.\n\n", tissue) else "",
    "Metadata candidates (sorted by heuristic score, higher = better):\n",
    evidence,
    "\n\nReturn the JSON object now."
  )

  last_err <- NULL
  valid_cols <- scored$column
  for (i in seq_len(max_retries + 1)) {
    raw <- tryCatch(chat_fn(system_prompt, user_prompt),
                    error = function(e) { last_err <<- e; NULL })
    if (is.null(raw)) next
    raw <- sub("^```(?:json)?\\s*", "", raw)
    raw <- sub("\\s*```\\s*$", "", raw)
    raw <- trimws(raw)
    parsed <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = TRUE),
                       error = function(e) { last_err <<- e; NULL })
    if (!is.null(parsed) &&
        !is.null(parsed$recommended) &&
        parsed$recommended %in% valid_cols) {
      return(parsed)
    }
    if (i <= max_retries) {
      user_prompt <- paste0(user_prompt,
        "\n\nYour previous response was invalid. The `recommended` ",
        "field must be exactly one of: ",
        paste(valid_cols, collapse = ", "),
        ". Return ONLY the JSON object.")
    }
  }
  list(
    recommended  = scored$column[1],   # fallback to top-scored
    confidence   = "low",
    alternatives = scored$column[-1][seq_len(min(2, nrow(scored) - 1))],
    warnings     = list("LLM call failed; defaulted to highest-scored candidate."),
    reasoning    = sprintf("LLM error: %s",
                           if (is.null(last_err)) "unknown"
                           else conditionMessage(last_err))
  )
}
