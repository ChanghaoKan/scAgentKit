# Fisher is conditional on a documented pre-test eligible gene universe.
.sc_run_marker_enrichment <- function(query, reference_sets, universe = NULL) {
  if(is.null(universe) || !length(universe)) return(list(status="unavailable",reason="The actual pre-test eligible gene universe was not recorded; assayed or significant genes are not substituted."))
  if(!is.character(universe) || anyNA(universe) || any(!nzchar(universe)) || anyDuplicated(universe) || !length(universe))
    stop("Fisher background requires a nonempty unique literal eligible gene universe.",call.=FALSE)
  query <- intersect(unique(query),universe)
  records <- lapply(sort(names(reference_sets),method="radix"),function(label) {
    reference <- intersect(unique(reference_sets[[label]]),universe)
    a <- length(intersect(query,reference)); b <- length(setdiff(query,reference))
    c <- length(setdiff(reference,query)); d <- length(setdiff(universe,union(query,reference)))
    valid <- length(query)>0L && length(reference)>0L && length(query)<length(universe) && length(reference)<length(universe)
    list(label=label,status=if(valid) "tested" else "uninformative",a=a,b=b,c=c,d=d,
      p_value=if(valid) stats::fisher.test(matrix(c(a,b,c,d),nrow=2,byrow=TRUE),alternative="greater")$p.value else NULL,
      reference_in_background=length(reference),query_in_background=length(query),universe_size=length(universe))
  })
  valid <- which(vapply(records,function(x) identical(x$status,"tested"),logical(1)))
  adjusted <- stats::p.adjust(vapply(records[valid],`[[`,numeric(1),"p_value"),method="BH")
  for(i in seq_along(valid)) records[[valid[i]]]$p_adjusted <- unname(adjusted[i])
  list(status="measured",universe=universe,universe_hash=.sc_run_hash(universe),records=records,
    multiplicity="BH across all tested labels in this cluster, before top-N display",
    interpretation="Descriptive over-representation conditional on eligible measured genes; marker dependencies and reference selection limit inference. Not cell-label probability, independent validation or ranking replacement.")
}
