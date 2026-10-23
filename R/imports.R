# Single package-wide NULL-coalescing helper. Missing means NULL, a
# zero-length value, or a scalar NA. Callers use these three fallbacks.
# Do not redefine it elsewhere: without a Collate field the
# alphabetically last definition silently wins for the whole namespace.
`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.atomic(a) && is.na(a))) b else a
}
