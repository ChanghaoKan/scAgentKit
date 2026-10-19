# Shared pure kernels. Extracted verbatim from legacy modules; callers own orchestration.

.validate_annotation_response <- function(parsed, expected_cluster = NULL,
                                          vocabulary = NULL) {
  required <- c("primary_annotation", "confidence", "supporting_markers",
                "contradicting_markers", "alternative_annotations",
                "proportion_assessment", "recommended_action", "reasoning")
  if (!is.list(parsed) || is.null(names(parsed)) ||
      anyNA(names(parsed)) || anyDuplicated(names(parsed)) ||
      (!setequal(names(parsed), required) &&
       !setequal(names(parsed), c(required, "cluster")))) {
    stop("Annotation JSON must be one object with exactly the eight required fields and optional cluster.")
  }
  scalar <- function(value, field) {
    if (!is.character(value) || length(value) != 1L || is.na(value) ||
        !nzchar(trimws(value))) {
      stop(sprintf("Annotation field '%s' must be a non-empty scalar string.", field))
    }
    value
  }
  for (field in c("primary_annotation", "confidence", "proportion_assessment",
                  "recommended_action", "reasoning")) {
    parsed[[field]] <- scalar(parsed[[field]], field)
  }
  enums <- list(confidence = c("high", "medium", "low"),
                proportion_assessment = c("reasonable", "suspicious", "abnormal"),
                recommended_action = c("accept", "flag_for_review", "reject", "mark_unknown"))
  for (field in names(enums)) {
    if (!parsed[[field]] %in% enums[[field]]) {
      stop(sprintf("Annotation field '%s' has an invalid enum value.", field))
    }
  }
  for (field in c("supporting_markers", "contradicting_markers", "alternative_annotations")) {
    value <- parsed[[field]]
    if (!is.list(value) || !is.null(names(value)) ||
        !all(vapply(value, function(x) {
          is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
        }, logical(1)))) {
      stop(sprintf("Annotation field '%s' must be a JSON array of non-empty strings.", field))
    }
    parsed[[field]] <- if (length(value)) unlist(value, use.names = FALSE) else character(0)
  }
  if ("cluster" %in% names(parsed)) {
    parsed$cluster <- scalar(parsed$cluster, "cluster")
    if (!is.null(expected_cluster) && !identical(parsed$cluster, as.character(expected_cluster))) {
      stop("Annotation cluster ID does not match the requested cluster.")
    }
  }
  if (!is.null(vocabulary) &&
      !parsed$primary_annotation %in% c(vocabulary, "Unknown")) {
    stop("Annotation primary_annotation is outside the strict vocabulary.")
  }
  parsed
}

.validate_cited_markers <- function(parsed, cluster_top_genes) {
  cited_support     <- as.character(parsed$supporting_markers    %||% character(0))
  cited_contradict  <- as.character(parsed$contradicting_markers %||% character(0))
  all_cited         <- unique(c(cited_support, cited_contradict))

  if (length(all_cited) == 0) {
    return(list(hallucinated = character(0), rate = NA_real_))
  }

  input_upper  <- toupper(trimws(cluster_top_genes))
  cited_upper  <- toupper(trimws(all_cited))
  is_halluc    <- !(cited_upper %in% input_upper)
  hallucinated <- all_cited[is_halluc]

  # Rate is over supporting_markers (the affirmative claims that matter
  # most). Contradicting hallucinations are still recorded but not
  # counted in the rate.
  rate <- if (length(cited_support) == 0) {
    NA_real_
  } else {
    sup_upper <- toupper(trimws(cited_support))
    mean(!(sup_upper %in% input_upper))
  }

  list(hallucinated = hallucinated, rate = rate)
}

.reference_filter_input <- function(x, name) {
  if (!is.null(x) && (!is.character(x) || !length(x) || anyNA(x) ||
                     any(!nzchar(trimws(x))))) {
    stop("`", name, "` must contain non-empty character values or NULL.")
  }
}

.validate_marker_reference <- function(reference) {
  required <- c("cell_type", "marker")
  if (!is.data.frame(reference) || !all(required %in% names(reference))) {
    stop("Reference must be a data frame containing cell_type and marker columns.")
  }
  for (name in required) {
    x <- reference[[name]]
    if ((length(x) && !is.character(x) && !is.factor(x)) || anyNA(x) ||
        any(!nzchar(trimws(as.character(x))))) {
      stop("Reference ", name, " must contain non-empty character values.")
    }
    reference[[name]] <- trimws(as.character(x))
  }
  reference
}

.empty_reference_matches <- function() {
  data.frame(cluster = character(), cell_type = character(),
             overlap_count = integer(), celltype_size = integer(),
             score = numeric(), matched_markers = character(),
             stringsAsFactors = FALSE)
}

.review_label_normalizer <- function(label_map) {
  if (!is.null(label_map)) {
    if (!is.character(label_map) || !length(label_map) || is.null(names(label_map)) ||
        anyNA(label_map) || anyNA(names(label_map)) ||
        any(!nzchar(trimws(label_map))) || any(!nzchar(trimws(names(label_map))))) {
      stop("`label_map` must be a named character vector with non-empty labels and targets.")
    }
    keys <- tolower(trimws(names(label_map)))
    if (anyDuplicated(keys)) stop("`label_map` names must be unique after normalization.")
    label_map <- stats::setNames(tolower(trimws(label_map)), keys)
  }
  function(x) {
    out <- tolower(trimws(as.character(x)))
    out[is.na(out) | !nzchar(out)] <- NA_character_
    if (!is.null(label_map)) {
      hit <- !is.na(out) & out %in% names(label_map)
      out[hit] <- unname(label_map[out[hit]])
    }
    out
  }
}

.review_genes <- function(x) {
  x <- unlist(x, use.names = FALSE)
  if (!length(x)) return(character())
  genes <- trimws(unlist(strsplit(as.character(x[!is.na(x)]), "[,;]+", perl = TRUE),
                         use.names = FALSE))
  unique(genes[nzchar(genes)])
}

.review_cluster_ids <- function(x, source) {
  if (anyNA(x) || any(!nzchar(trimws(as.character(x))))) {
    stop(source, " cluster IDs must be non-empty and non-missing.")
  }
}

.review_input_alignment <- function(saved, current) {
  if (is.null(saved) || is.null(current)) return("unverified")
  if (!is.data.frame(saved) || !all(c("cell_id", "cluster") %in% names(saved))) {
    return("mismatch")
  }
  saved <- saved[, c("cell_id", "cluster"), drop = FALSE]
  saved$cell_id <- as.character(saved$cell_id)
  saved$cluster <- as.character(saved$cluster)
  if (anyNA(saved) || any(!nzchar(trimws(saved$cell_id))) ||
      any(!nzchar(trimws(saved$cluster))) || anyDuplicated(saved$cell_id)) {
    return("mismatch")
  }
  saved <- saved[order(saved$cell_id), , drop = FALSE]
  current <- current[order(current$cell_id), , drop = FALSE]
  rownames(saved) <- rownames(current) <- NULL
  if (identical(saved, current)) "verified" else "mismatch"
}

.decision_object <- function(parsed, required, optional = character()) {
  if (!is.list(parsed) || is.null(names(parsed)) || any(!nzchar(names(parsed))) ||
      anyDuplicated(names(parsed))) {
    stop("Decision response must be one JSON object with unique field names.")
  }
  missing <- setdiff(required, names(parsed))
  extra <- setdiff(names(parsed), c(required, optional))
  if (length(missing)) stop("Missing decision fields: ", paste(missing, collapse = ", "))
  if (length(extra)) stop("Unexpected decision fields: ", paste(extra, collapse = ", "))
  parsed
}

.decision_string <- function(value, field, choices = NULL) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !nzchar(trimws(value))) {
    stop("`", field, "` must be one non-empty JSON string.")
  }
  if (!is.null(choices) && !value %in% choices) {
    stop("`", field, "` must be one of: ", paste(choices, collapse = ", "))
  }
  value
}

.decision_number <- function(value, field, choices, integer = FALSE) {
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value) ||
      (integer && (value != floor(value) || value > .Machine$integer.max))) {
    stop("`", field, "` must be one finite JSON ", if (integer) "integer." else "number.")
  }
  if (!value %in% choices) {
    stop("`", field, "` must be one of the supplied candidates: ",
         paste(choices, collapse = ", "))
  }
  if (integer) as.integer(value) else value
}

.decision_array <- function(value, field, validate, empty = character()) {
  if (!is.list(value) || !is.null(names(value))) {
    stop("`", field, "` must be a JSON array.")
  }
  if (!length(value)) return(empty)
  out <- lapply(value, validate)
  if (anyDuplicated(unlist(out, use.names = FALSE))) {
    stop("`", field, "` must not contain duplicate entries.")
  }
  unlist(out, use.names = FALSE)
}

.validate_pcs_decision <- function(parsed, candidates) {
  parsed <- .decision_object(parsed, c("chosen_ndim", "confidence", "reasoning"))
  parsed$chosen_ndim <- .decision_number(parsed$chosen_ndim, "chosen_ndim", candidates, integer = TRUE)
  parsed$confidence <- .decision_string(parsed$confidence, "confidence", c("low", "medium", "high"))
  parsed$reasoning <- .decision_string(parsed$reasoning, "reasoning")
  parsed
}

.validate_resolution_decision <- function(parsed, res_values, panels_used = numeric(),
                                          require_visual_notes = FALSE) {
  fields <- c("chosen_resolution", "confidence", "alternatives", "reasoning")
  if (require_visual_notes) fields <- c(fields, "visual_notes")
  parsed <- .decision_object(parsed, fields, c("visual_notes", "clustree_notes"))
  choices <- if (length(panels_used)) panels_used else res_values
  parsed$chosen_resolution <- .decision_number(parsed$chosen_resolution, "chosen_resolution", choices)
  parsed$confidence <- .decision_string(parsed$confidence, "confidence", c("low", "medium", "high"))
  parsed$alternatives <- .decision_array(parsed$alternatives, "alternatives", function(x) {
    .decision_number(x, "alternatives", res_values)
  }, empty = numeric())
  parsed$reasoning <- .decision_string(parsed$reasoning, "reasoning")
  for (field in intersect(c("visual_notes", "clustree_notes"), names(parsed))) {
    parsed[[field]] <- .decision_string(parsed[[field]], field)
  }
  parsed
}

.validate_batch_decision <- function(parsed, valid_cols) {
  parsed <- .decision_object(parsed, c("recommended", "confidence", "alternatives", "warnings", "reasoning"))
  parsed$recommended <- .decision_string(parsed$recommended, "recommended", valid_cols)
  parsed$confidence <- .decision_string(parsed$confidence, "confidence", c("low", "medium", "high"))
  parsed$alternatives <- .decision_array(parsed$alternatives, "alternatives", function(x) {
    .decision_string(x, "alternatives", valid_cols)
  })
  parsed$warnings <- .decision_array(parsed$warnings, "warnings", function(x) {
    .decision_string(x, "warnings")
  })
  parsed$reasoning <- .decision_string(parsed$reasoning, "reasoning")
  parsed
}

