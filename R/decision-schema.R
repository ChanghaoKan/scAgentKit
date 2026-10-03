# Strict JSON schemas for analysis decisions. Validators receive unsimplified
# jsonlite objects so JSON arrays, objects, strings and numbers stay distinct.
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

# Keep the retry audit in each recommendation without leaking annotation-only
# failure fields into unrelated decisions.
.decision_audit <- function(parsed) {
  list(status = parsed$annotation_status,
       error = parsed$annotation_error,
       attempts = parsed$annotation_attempts,
       response_audit = attr(parsed, "response_audit"))
}

.pcs_call_with_retry <- function(chat_fn, system_prompt, user_prompt,
                                 candidates, max_retries = 1, image_path = NULL) {
  parsed <- .call_with_retry(chat_fn, system_prompt, user_prompt,
                            max_retries = max_retries, image_path = image_path,
                            validator = function(x) .validate_pcs_decision(x, candidates))
  audit <- .decision_audit(parsed)
  if (!identical(audit$status, "ok")) {
    warning("PC decision failed validation; falling back to the median candidate.", call. = FALSE)
    audit$status <- "fallback"
    return(c(list(chosen_ndim = candidates[ceiling(length(candidates) / 2)],
                  confidence = "low",
                  reasoning = paste("Median candidate fallback;", parsed$reasoning)), audit))
  }
  c(parsed[c("chosen_ndim", "confidence", "reasoning")], audit)
}
