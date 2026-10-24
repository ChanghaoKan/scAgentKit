# Shared pure validation kernels; callers own orchestration.

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


.review_genes <- function(x) {
  x <- unlist(x, use.names = FALSE)
  if (!length(x)) return(character())
  genes <- trimws(unlist(strsplit(as.character(x[!is.na(x)]), "[,;]+", perl = TRUE),
                         use.names = FALSE))
  unique(genes[nzchar(genes)])
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
