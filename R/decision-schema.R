# Strict JSON schemas for analysis decisions. Validators receive unsimplified
# jsonlite objects so JSON arrays, objects, strings and numbers stay distinct.







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
    warning("PC decision failed validation; the median candidate is reported only as a fallback and is not applied as ndim.", call. = FALSE)
    audit$status <- "fallback"
    return(c(list(chosen_ndim = candidates[ceiling(length(candidates) / 2)],
                  confidence = "low",
                  reasoning = paste("Median candidate fallback;", parsed$reasoning)), audit))
  }
  c(parsed[c("chosen_ndim", "confidence", "reasoning")], audit)
}
