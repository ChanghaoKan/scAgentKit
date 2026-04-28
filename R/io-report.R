#' Generate a self-contained HTML analysis report
#'
#' Produces a single HTML file summarising the entire pipeline: stage
#' progression, decision log, embedded figures, and the full reproducible
#' R script. Figures are base64-embedded so the HTML is portable (no
#' accompanying image folder needed).
#'
#' This is the artifact to hand to a collaborator, stash with a paper
#' submission, or attach to an issue when something unexpected shows up
#' mid-analysis. It renders in any browser, no R or network required.
#'
#' @param obj An AgentSeurat object (any stage).
#' @param path Output HTML path. Default "analysis_report.html".
#' @param title Character, report title shown in the HTML. If NULL,
#'   a default based on the object's stage is used.
#' @param include_script Logical, whether to embed the full reproducible
#'   script inline. Default TRUE.
#' @param include_params Logical, whether to include full parameter
#'   details (can be verbose). Default TRUE.
#'
#' @return Invisibly returns `path`.
#' @export
#'
#' @examples
#' \dontrun{
#'   report_html(obj, path = "report.html",
#'               title = "Ca vs Ctrl scRNA-seq analysis")
#' }
report_html <- function(obj,
                        path           = "analysis_report.html",
                        title          = NULL,
                        include_script = TRUE,
                        include_params = TRUE) {

  stopifnot(methods::is(obj, "AgentSeurat"))

  if (is.null(title)) {
    title <- sprintf("scAgentKit analysis report (stage: %s)", obj@stage)
  }

  # ---- Header and styling (self-contained CSS) -----------------------------
  head <- .report_css(title)

  # ---- Summary banner -----------------------------------------------------
  n_decisions <- length(obj@decisions)
  n_figures   <- nrow(obj@figures)

  overview_rows <- list(
    c("Stage",          .esc(obj@stage)),
    c("Data type",      .esc(obj@data_type)),
    c("Cells (total)",  as.character(.safe_total_cells(obj))),
    c("Genes",          as.character(.safe_genes(obj))),
    c("Decisions",      as.character(n_decisions)),
    c("Figures",        as.character(n_figures)),
    c("Created",        format(obj@created_at, "%Y-%m-%d %H:%M:%S")),
    c("Last updated",   format(obj@updated_at, "%Y-%m-%d %H:%M:%S"))
  )
  overview_html <- paste0(
    '<table class="overview"><tbody>',
    paste(vapply(overview_rows, function(r)
      sprintf('<tr><th>%s</th><td>%s</td></tr>', r[1], r[2]),
      character(1)), collapse = "\n"),
    '</tbody></table>'
  )

  # ---- Decisions table ----------------------------------------------------
  decisions_html <- .render_decisions_html(obj@decisions, include_params)

  # ---- Figure gallery (base64-embedded) -----------------------------------
  gallery_html <- .render_figure_gallery(obj@figures)

  # ---- Recommendations (if present) ---------------------------------------
  rec_html <- .render_recommendations(obj)

  # ---- LLM annotations (if present) ---------------------------------------
  ann_html <- .render_llm_annotations(obj)
  cmp_html <- .render_author_comparison(obj)

  # ---- Reproducible script (if requested) ---------------------------------
  script_html <- if (isTRUE(include_script)) {
    full <- paste(obj@scripts, collapse = "\n\n")
    sprintf(
      '<section><h2>Reproducible script</h2><pre class="script"><code>%s</code></pre></section>',
      .esc(full)
    )
  } else ""

  # ---- Assemble ----------------------------------------------------------
  body <- paste0(
    '<main>',
    sprintf('<h1>%s</h1>', .esc(title)),
    '<section><h2>Overview</h2>', overview_html, '</section>',
    rec_html,
    '<section><h2>Decision log</h2>', decisions_html, '</section>',
    '<section><h2>Figures</h2>', gallery_html, '</section>',
    ann_html,
    cmp_html,
    script_html,
    .report_footer(),
    '</main>'
  )

  html <- paste0('<!DOCTYPE html>\n<html lang="en">\n',
                 head, '\n<body>\n', body, '\n</body>\n</html>\n')

  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  writeLines(html, con = path, useBytes = TRUE)
  message(sprintf("[report_html] wrote %s (%s KB)",
                  path, format(round(file.info(path)$size / 1024, 1))))
  invisible(path)
}

# ---- Internal report helpers -----------------------------------------------

.report_css <- function(title) {
  paste0(
    '<head>\n<meta charset="utf-8">\n',
    sprintf('<title>%s</title>\n', .esc(title)),
    '<style>
      :root {
        --fg: #1e1e1e; --bg: #fafafa; --border: #d9d9d9;
        --accent: #2a6f97; --muted: #666; --code-bg: #f3f3f3;
        --table-head: #eef2f5;
      }
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI",
             Helvetica, Arial, sans-serif; color: var(--fg);
             background: var(--bg); margin: 0; padding: 0; }
      main { max-width: 980px; margin: 0 auto; padding: 2rem 1.5rem 4rem; }
      h1 { color: var(--accent); border-bottom: 2px solid var(--accent);
           padding-bottom: .3em; margin-top: 0; }
      h2 { color: var(--accent); margin-top: 2.2em; border-bottom:
           1px solid var(--border); padding-bottom: .25em; }
      h3 { margin-bottom: .25em; }
      section { margin-bottom: 1.2em; }
      table { border-collapse: collapse; width: 100%; margin: .6em 0; }
      th, td { border: 1px solid var(--border); padding: .45em .7em;
               text-align: left; vertical-align: top; font-size: .92rem; }
      th { background: var(--table-head); font-weight: 600; }
      table.overview th { width: 160px; }
      table.decisions td.params { font-family: ui-monospace, SFMono-Regular,
        Menlo, Consolas, monospace; font-size: .82rem;
        white-space: pre-wrap; word-break: break-word; max-width: 540px; }
      pre.script { background: var(--code-bg); border: 1px solid var(--border);
                   padding: 1em; border-radius: 4px; overflow-x: auto;
                   font-size: .82rem; line-height: 1.4;
                   max-height: 620px; overflow-y: auto; }
      pre.script code { font-family: ui-monospace, SFMono-Regular, Menlo,
                        Consolas, monospace; }
      .fig { margin: 1.5em 0; }
      .fig img { max-width: 100%; border: 1px solid var(--border);
                 border-radius: 3px; }
      .fig .caption { color: var(--muted); font-size: .88rem;
                      margin-top: .3em; }
      .rationale { color: var(--muted); font-size: .9rem; }
      .badge { display: inline-block; padding: 1px 8px; border-radius: 9px;
               font-size: .75rem; font-weight: 600;
               background: #e7f0f7; color: var(--accent); }
      .badge.warn { background: #fff3cd; color: #8a6d0f; }
      .badge.err  { background: #fbe3e4; color: #a12f2f; }
      footer { color: var(--muted); font-size: .85rem; margin-top: 3em;
               border-top: 1px solid var(--border); padding-top: 1em; }
      details { margin-top: .5em; }
      summary { cursor: pointer; font-size: .85rem; color: var(--accent); }
    </style>\n</head>'
  )
}

.report_footer <- function() {
  sprintf(
    '<footer>Generated by <code>scAgentKit::report_html()</code> on %s.</footer>',
    format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )
}

# HTML-escape a string. Internal -- keeps us free of xml2 / htmltools deps.
.esc <- function(x) {
  if (is.null(x)) return("")
  x <- as.character(x)
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;",  x, fixed = TRUE)
  x <- gsub(">", "&gt;",  x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  x
}

.safe_total_cells <- function(obj) {
  tryCatch({
    if (obj@data_type == "seurat") ncol(obj@data)
    else sum(vapply(obj@data, function(s) as.integer(ncol(s)), integer(1)))
  }, error = function(e) NA)
}

.safe_genes <- function(obj) {
  tryCatch({
    if (obj@data_type == "seurat") nrow(obj@data)
    else nrow(obj@data[[1]])
  }, error = function(e) NA)
}

.format_params_html <- function(params) {
  if (length(params) == 0) return("")
  # Pretty-print using jsonlite if available; otherwise fall back to
  # a simple name = value listing.
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    txt <- tryCatch(
      jsonlite::toJSON(params, auto_unbox = TRUE, pretty = TRUE, null = "null"),
      error = function(e) NULL
    )
    if (!is.null(txt)) return(.esc(txt))
  }
  lines <- vapply(names(params), function(nm) {
    val <- params[[nm]]
    repr <- if (length(val) == 0) "<empty>" else paste(val, collapse = ", ")
    sprintf("%s = %s", nm, repr)
  }, character(1))
  .esc(paste(lines, collapse = "\n"))
}

.render_decisions_html <- function(decisions, include_params) {
  if (length(decisions) == 0) {
    return('<p class="rationale">No decisions recorded yet.</p>')
  }
  rows <- vapply(seq_along(decisions), function(i) {
    d <- decisions[[i]]
    badge <- if (isTRUE(d$success)) '<span class="badge">ok</span>'
             else '<span class="badge err">failed</span>'
    params_cell <- if (isTRUE(include_params)) {
      sprintf('<td class="params">%s</td>', .format_params_html(d$params))
    } else ''
    sprintf(
      '<tr><td>%d</td><td>%s</td><td><code>%s</code></td><td>%s</td><td>%s</td>%s</tr>',
      i,
      format(d$timestamp, "%Y-%m-%d %H:%M:%S"),
      .esc(d$function_name),
      badge,
      .esc(d$rationale %||% ""),
      params_cell
    )
  }, character(1))
  params_header <- if (isTRUE(include_params)) '<th>Params</th>' else ''
  paste0(
    '<table class="decisions"><thead><tr>',
    '<th>#</th><th>Time</th><th>Function</th>',
    '<th>Status</th><th>Rationale</th>', params_header,
    '</tr></thead><tbody>',
    paste(rows, collapse = "\n"),
    '</tbody></table>'
  )
}

.render_figure_gallery <- function(figures) {
  if (nrow(figures) == 0) {
    return('<p class="rationale">No figures registered.</p>')
  }
  items <- vapply(seq_len(nrow(figures)), function(i) {
    row <- figures[i, ]
    embedded <- .embed_image(row$path)
    if (is.null(embedded)) {
      sprintf(
        '<div class="fig"><div class="caption"><strong>%s</strong><br>%s<br><em>(image not found: %s)</em></div></div>',
        .esc(row$step), .esc(row$description), .esc(row$path)
      )
    } else {
      sprintf(
        '<div class="fig"><img src="%s" alt="%s" /><div class="caption"><strong>%s</strong> &mdash; %s</div></div>',
        embedded, .esc(row$description),
        .esc(row$step), .esc(row$description)
      )
    }
  }, character(1))
  paste(items, collapse = "\n")
}

.embed_image <- function(path) {
  if (!file.exists(path)) return(NULL)
  ext <- tolower(tools::file_ext(path))
  mime <- switch(ext,
                 png = "image/png",
                 jpg = "image/jpeg", jpeg = "image/jpeg",
                 webp = "image/webp", gif = "image/gif",
                 svg = "image/svg+xml",
                 NULL)
  if (is.null(mime)) return(NULL)
  b64 <- tryCatch({
    if (requireNamespace("base64enc", quietly = TRUE)) {
      base64enc::base64encode(path)
    } else if (requireNamespace("openssl", quietly = TRUE)) {
      openssl::base64_encode(readBin(path, "raw",
                                     n = file.info(path)$size))
    } else {
      return(NULL)
    }
  }, error = function(e) NULL)
  if (is.null(b64)) return(NULL)
  sprintf("data:%s;base64,%s", mime, b64)
}

.render_recommendations <- function(obj) {
  rec <- obj@params$resolution_recommendation
  if (is.null(rec)) return("")
  alts <- if (length(rec$alternatives) > 0) {
    paste(rec$alternatives, collapse = ", ")
  } else "&mdash;"
  clustree_notes <- if (!is.null(rec$clustree_notes) && !is.na(rec$clustree_notes)) {
    sprintf('<p><strong>Clustree notes:</strong> <em>%s</em></p>',
            .esc(rec$clustree_notes))
  } else ""
  paste0(
    '<section><h2>Resolution recommendation</h2>',
    sprintf(
      '<table class="overview"><tbody>
<tr><th>Chosen</th><td>%s</td></tr>
<tr><th>Confidence</th><td>%s</td></tr>
<tr><th>Alternatives</th><td>%s</td></tr>
<tr><th>Mode</th><td>%s</td></tr>
</tbody></table>',
      .esc(rec$chosen), .esc(rec$confidence), alts, .esc(rec$mode)
    ),
    clustree_notes,
    sprintf('<p class="rationale">%s</p>', .esc(rec$reasoning %||% "")),
    '</section>'
  )
}

.render_llm_annotations <- function(obj) {
  ann <- obj@params$llm_annotations
  if (is.null(ann) || !is.data.frame(ann) || nrow(ann) == 0) return("")
  rows <- vapply(seq_len(nrow(ann)), function(i) {
    r <- ann[i, ]
    action <- as.character(r$recommended_action %||% "")
    badge <- switch(
      action,
      accept           = '<span class="badge">accept</span>',
      flag_for_review  = '<span class="badge warn">review</span>',
      reject           = '<span class="badge err">reject</span>',
      mark_unknown     = '<span class="badge warn">unknown</span>',
      sprintf('<span class="badge">%s</span>', .esc(action))
    )
    sprintf(
      '<tr><td>%s</td><td><strong>%s</strong></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
      .esc(r$cluster),
      .esc(r$primary_annotation),
      .esc(r$confidence),
      badge,
      .esc(r$supporting_markers),
      .esc(r$contradicting_markers),
      .esc(r$reasoning)
    )
  }, character(1))
  paste0(
    '<section><h2>LLM annotations</h2>',
    '<table><thead><tr>',
    '<th>Cluster</th><th>Annotation</th><th>Confidence</th>',
    '<th>Action</th><th>Supporting markers</th>',
    '<th>Contradicting markers</th><th>Reasoning</th>',
    '</tr></thead><tbody>',
    paste(rows, collapse = "\n"),
    '</tbody></table></section>'
  )
}

# Render the author-comparison block (confusion + per-class stats).
.render_author_comparison <- function(obj) {
  cmp <- obj@params$author_comparison
  if (is.null(cmp)) return("")

  conf_html <- ""
  if (!is.null(cmp$confusion) && length(cmp$confusion) > 0) {
    cm <- cmp$confusion
    cn <- colnames(cm)
    rn <- rownames(cm)
    head_row <- paste0(
      "<tr><th></th>",
      paste(sprintf("<th>%s</th>", .esc(cn)), collapse = ""),
      "</tr>"
    )
    body_rows <- vapply(seq_len(nrow(cm)), function(i) {
      cells <- vapply(seq_len(ncol(cm)), function(j) {
        val <- cm[i, j]
        is_diag <- !is.na(rn[i]) && !is.na(cn[j]) && rn[i] == cn[j]
        sprintf('<td%s>%d</td>',
                if (is_diag) ' style="background:#e7f0f7;font-weight:600"' else '',
                as.integer(val))
      }, character(1))
      sprintf("<tr><th>%s</th>%s</tr>", .esc(rn[i]),
              paste(cells, collapse = ""))
    }, character(1))
    conf_html <- paste0(
      '<h3>Confusion matrix (LLM rows × Reference columns)</h3>',
      '<table><thead>', head_row, '</thead><tbody>',
      paste(body_rows, collapse = "\n"),
      '</tbody></table>'
    )
  }

  per_class_html <- ""
  if (!is.null(cmp$per_class) && nrow(cmp$per_class) > 0) {
    pc <- cmp$per_class
    rows <- vapply(seq_len(nrow(pc)), function(i) {
      sprintf(
        '<tr><td>%s</td><td>%d</td><td>%d</td><td>%d</td><td>%.1f%%</td><td>%.1f%%</td></tr>',
        .esc(pc$cell_type[i]), pc$n_author[i], pc$n_llm[i],
        pc$correct[i], pc$sensitivity[i], pc$precision[i]
      )
    }, character(1))
    per_class_html <- paste0(
      '<h3>Per-class performance</h3>',
      '<table><thead><tr>',
      '<th>Cell type</th><th>n (reference)</th><th>n (LLM)</th>',
      '<th>Correct</th><th>Sensitivity</th><th>Precision</th>',
      '</tr></thead><tbody>',
      paste(rows, collapse = "\n"),
      '</tbody></table>'
    )
  }

  paste0(
    '<section><h2>Comparison vs reference annotation</h2>',
    sprintf(
      '<p><strong>Reference source:</strong> %s. <strong>Cells compared:</strong> %d. <strong>Overall concordance:</strong> %.1f%%. <strong>Collapse to broad:</strong> %s.</p>',
      .esc(cmp$reference_source %||% "unknown"),
      cmp$n_cells_compared %||% 0L,
      cmp$overall_concordance %||% 0,
      if (isTRUE(cmp$collapse_used)) "yes" else "no"
    ),
    per_class_html,
    conf_html,
    '</section>'
  )
}
