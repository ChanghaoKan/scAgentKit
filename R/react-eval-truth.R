# Consensus is determined before any predictions are read. Only frozen,
# meaningful ancestors may reconcile differently granular human annotations.
.sc_react_eval_truths <- function(table, mapping, cl, allowed_ancestors) {
  dual <- c("label_author", "label_independent") %in% names(table)
  if (!any(dual)) return(list(primary = table))
  if (!all(dual) || !"cell_id" %in% names(table) || "label" %in% names(table))
    stop("Dual truth requires cell_id, label_author and label_independent.", call. = FALSE)
  convert <- function(who) {
    out <- data.frame(cell_id = table$cell_id, label = table[[paste0("label_", who)]],
      stringsAsFactors = FALSE)
    field <- paste0("cl_id_", who)
    if (field %in% names(table)) out$cl_id <- table[[field]]
    out
  }
  author <- convert("author"); independent <- convert("independent")
  # One artificial singleton group per cell reuses the same explicit-ID checks,
  # mapping rules and failure semantics as all other truth imports.
  members <- data.frame(cell_id = table$cell_id, cluster = table$cell_id)
  a <- .sc_react_eval_labels(author, members, mapping, cl, TRUE)
  b <- .sc_react_eval_labels(independent, members, mapping, cl, TRUE)
  consensus <- vapply(seq_len(nrow(a)), function(i) {
    if (a$status[i] != "mapped" || b$status[i] != "mapped") return(NA_character_)
    if (a$cl_id[i] == b$cl_id[i]) return(a$cl_id[i])
    aa <- .sc_react_eval_ancestors(a$cl_id[i], cl)
    bb <- .sc_react_eval_ancestors(b$cl_id[i], cl)
    common <- intersect(intersect(names(aa), names(bb)), allowed_ancestors)
    if (!length(common)) return(NA_character_)
    # Ambiguous equally close common parents are not silently tie-broken.
    distance <- aa[common] + bb[common]
    best <- common[distance == min(distance)]
    if (length(best) == 1L) best else NA_character_
  }, character(1))
  agreement <- data.frame(cell_id = a$cluster_id, author_cl_id = a$cl_id,
    independent_cl_id = b$cl_id, consensus_cl_id = consensus,
    exact = !is.na(consensus) & a$cl_id == b$cl_id,
    hierarchical = !is.na(consensus), disagreement = is.na(consensus),
    stringsAsFactors = FALSE)
  primary <- data.frame(cell_id = a$cluster_id, label = consensus,
    status = ifelse(is.na(consensus), "annotator_disagreement", "truth"),
    stringsAsFactors = FALSE)
  result <- list(primary = primary, author = author, independent = independent)
  attr(result, "agreement") <- agreement
  both_mapped <- a$status == "mapped" & b$status == "mapped"
  attr(result, "agreement_summary") <- list(total = nrow(a),
    denominator = sum(both_mapped), mapping_unavailable = sum(!both_mapped),
    exact = if (any(both_mapped)) mean(agreement$exact[both_mapped]) else NA_real_,
    hierarchical = if (any(both_mapped)) mean(agreement$hierarchical[both_mapped]) else NA_real_,
    disagreements = sum(both_mapped & agreement$disagreement))
  result
}
