# scAgentKit-specific HTML report section renderers
#
# These are passed to agentomicsCore::render_report() via the `extras`
# argument by the [report_html()] wrapper in this package. They read
# scRNA-seq-specific entries from obj@params and produce <section> blocks.

#' Render the resolution-recommendation section (scAgentKit extra)
#'
#' Reads `obj@params$resolution_recommendation` (set by
#' [sc_resolution_recommend()]). Returns `""` if absent so that
#' agentomicsCore's renderer skips it.
#'
#' @param obj An AgentOmics (typically AgentSeurat) object.
#' @return Character HTML, or "".
#' @keywords internal
.render_recommendations <- function(obj) {
  rec <- obj@params$resolution_recommendation
  if (is.null(rec)) return("")
  alts <- if (length(rec$alternatives) > 0) {
    paste(rec$alternatives, collapse = ", ")
  } else "&mdash;"
  clustree_notes <- if (!is.null(rec$clustree_notes) &&
                        !is.na(rec$clustree_notes)) {
    sprintf('<p><strong>Clustree notes:</strong> <em>%s</em></p>',
            agentomicsCore::esc_html(rec$clustree_notes))
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
      agentomicsCore::esc_html(rec$chosen),
      agentomicsCore::esc_html(rec$confidence),
      alts,
      agentomicsCore::esc_html(rec$mode)
    ),
    clustree_notes,
    sprintf('<p class="rationale">%s</p>',
            agentomicsCore::esc_html(rec$reasoning %||% "")),
    '</section>'
  )
}


#' Render the LLM-annotation section (scAgentKit extra)
#'
#' Reads `obj@params$llm_annotations` (set by [annot_llm_annotate()]).
#' Renders one row per cluster with confidence (LLM + hybrid),
#' supporting / hallucinated / contradicting markers, ensemble agreement,
#' and a flag column highlighting problematic clusters.
#'
#' @param obj An AgentOmics (typically AgentSeurat) object.
#' @return Character HTML, or "".
#' @keywords internal
.render_llm_annotations <- function(obj) {
  ann <- obj@params$llm_annotations
  if (is.null(ann) || !is.data.frame(ann) || nrow(ann) == 0) return("")

  .esc <- agentomicsCore::esc_html

  has_hybrid    <- "hybrid_confidence"       %in% colnames(ann)
  has_disagree  <- "confidence_disagreement" %in% colnames(ann)
  has_halluc    <- "hallucinated_markers"    %in% colnames(ann)
  has_ensemble  <- "ensemble_agreement"      %in% colnames(ann)

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

    flags <- character(0)
    if (has_disagree && isTRUE(r$confidence_disagreement)) {
      flags <- c(flags,
                 '<span class="badge err">confidence&nbsp;mismatch</span>')
    }
    if (has_halluc && nzchar(as.character(r$hallucinated_markers %||% ""))) {
      flags <- c(flags,
                 '<span class="badge err">hallucinated&nbsp;genes</span>')
    }
    contradicting <- as.character(r$contradicting_markers %||% "")
    if (nzchar(contradicting)) {
      flags <- c(flags,
                 '<span class="badge warn">contradictions</span>')
    }
    if (has_ensemble &&
        !is.na(r$ensemble_agreement) &&
        as.numeric(r$ensemble_agreement) < 0.6 &&
        as.integer(r$ensemble_n %||% 1) > 1) {
      flags <- c(flags,
                 '<span class="badge warn">ensemble&nbsp;split</span>')
    }
    flags_html <- if (length(flags) == 0) "&mdash;"
                  else paste(flags, collapse = " ")

    row_class <- if (action == "reject") "row-err"
                 else if (action %in% c("flag_for_review", "mark_unknown") ||
                          (has_disagree && isTRUE(r$confidence_disagreement)) ||
                          (has_halluc &&
                             nzchar(as.character(r$hallucinated_markers %||% "")))) {
                   "row-warn"
                 } else ""
    tr_open <- if (nzchar(row_class)) sprintf('<tr class="%s">', row_class)
               else "<tr>"

    conf_html <- if (has_hybrid && !is.na(r$hybrid_confidence)) {
      hybrid_label <- as.character(r$hybrid_confidence_label %||% "")
      sprintf('%s<br/><small>hybrid: %s (%.2f)</small>',
              .esc(r$confidence), .esc(hybrid_label),
              as.numeric(r$hybrid_confidence))
    } else {
      .esc(r$confidence)
    }

    sup_html <- .esc(r$supporting_markers)
    if (has_halluc && nzchar(as.character(r$hallucinated_markers %||% ""))) {
      sup_html <- sprintf(
        '%s<br/><small style="color:#c0392b">not&nbsp;in&nbsp;input:&nbsp;%s</small>',
        sup_html, .esc(r$hallucinated_markers)
      )
    }

    sprintf(
      paste0(
        '%s<td>%s</td><td><strong>%s</strong></td><td>%s</td>',
        '<td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>'
      ),
      tr_open,
      .esc(r$cluster),
      .esc(r$primary_annotation),
      conf_html,
      badge,
      flags_html,
      sup_html,
      .esc(r$contradicting_markers),
      .esc(r$reasoning)
    )
  }, character(1))

  paste0(
    '<section><h2>LLM annotations</h2>',
    '<table><thead><tr>',
    '<th>Cluster</th><th>Annotation</th><th>Confidence</th>',
    '<th>Action</th><th>Flags</th><th>Supporting markers</th>',
    '<th>Contradicting markers</th><th>Reasoning</th>',
    '</tr></thead><tbody>',
    paste(rows, collapse = "\n"),
    '</tbody></table></section>'
  )
}


#' Render the author-comparison section (scAgentKit extra)
#'
#' Reads `obj@params$author_comparison` (set by
#' [annot_compare_with_reference()]). Confusion matrix + per-class
#' sensitivity / precision.
#'
#' @param obj An AgentOmics (typically AgentSeurat) object.
#' @return Character HTML, or "".
#' @keywords internal
.render_author_comparison <- function(obj) {
  cmp <- obj@params$author_comparison
  if (is.null(cmp)) return("")
  .esc <- agentomicsCore::esc_html

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
      '<h3>Confusion matrix (LLM rows x Reference columns)</h3>',
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


#' Generate a self-contained HTML analysis report (scAgentKit wrapper)
#'
#' Thin wrapper around [agentomicsCore::render_report()] that registers
#' scAgentKit's scRNA-seq-specific section renderers (resolution
#' recommendation, LLM annotations with hallucination flags, author
#' comparison).
#'
#' @inheritParams agentomicsCore::render_report
#'
#' @return Invisibly returns `path`.
#' @export
#'
#' @examples
#' \dontrun{
#'   report_html(obj, path = "report.html",
#'               title = "PBMC 3k scRNA-seq analysis")
#' }
report_html <- function(obj,
                        path           = "analysis_report.html",
                        title          = NULL,
                        include_script = TRUE,
                        include_params = TRUE) {
  agentomicsCore::render_report(
    obj,
    path                = path,
    title               = title,
    include_script      = include_script,
    include_params      = include_params,
    extras              = list(
      resolution_recommendation = .render_recommendations,
      llm_annotations           = .render_llm_annotations,
      author_comparison         = .render_author_comparison
    ),
    header_title_prefix = "scAgentKit analysis report"
  )
}
