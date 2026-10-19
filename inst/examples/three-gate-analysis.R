# Public pbmc_small SOFTWARE CONTROL, not a study-parameter recommendation.
# All scripted approvals below are confined to this fixture in a NEW directory.
# Real studies require the researcher's own inspection, labels and decisions.
three_gate_analysis <- function(project_dir) {
  stopifnot(!dir.exists(project_dir))
  e <- new.env(); utils::data("pbmc_small", package="SeuratObject", envir=e)
  input <- e$pbmc_small
  before <- digest::digest(input,algo="sha256",serializeVersion=2L)
  project <- scAgentKit::sc_analyze(input,project_dir,
    context=list(species="human",tissue="Public PBMC software fixture",
      research_goal="Exercise three scientific review gates offline; unresolved identities"),
    plan=list(rationale="Explicit public-fixture software controls, not study recommendations.",
      analysis=list(nfeatures=100,npcs=6),pcs=4,umap=FALSE))
  initial <- scAgentKit::sc_review(project)
  stopifnot(initial$view$stage=="strategy_propose",
    is.null(initial$view$strategy_review$details$cluster_diagnostics),
    length(initial$plan$clustering$diagnostic_resolutions)>0L)
  measured <- scAgentKit::sc_review(initial,"approve",reviewer="fixture-test",
    reason="Reviewed initial fixture QC retention and foundation plan.",continue=TRUE)
  stopifnot(measured$view$pending$kind=="strategy",measured$view$status=="awaiting_review",
    !is.null(measured$view$strategy_review$details$cluster_diagnostics))
  # Gate 2 binds actual scan evidence; retain the already scanned saved choice.
  measured <- scAgentKit::sc_review(measured)
  annotation <- scAgentKit::sc_review(measured,"approve",reviewer="fixture-test",
    reason="Reviewed computed PC evidence and ordinary resolution scan; retain saved fixture resolution.",continue=TRUE)
  stopifnot(annotation$view$stage=="annotation_propose",nrow(annotation$annotations)>0L)
  labels <- annotation$annotations
  labels$label <- "Unknown"; labels$confidence <- "low"
  labels$rationale <- "Software fixture abstention; no biological identity established."
  labels$markers <- ""
  proposal <- scAgentKit::sc_review(annotation,"revise",annotations=labels,
    reviewer="fixture-test",reason="Explicitly retain unresolved fixture populations.")
  done <- scAgentKit::sc_review(proposal,"approve",reviewer="fixture-test",
    reason="Reviewed complete Unknown-only annotation proposal.",continue=TRUE)
  stopifnot(done$view$status=="complete")
  result <- scAgentKit::sc_result(done)
  history <- jsonlite::read_json(file.path(project_dir,"decision_history.json"))$events
  approvals <- Filter(function(x)identical(x$action,"approved"),history)
  kinds <- vapply(approvals,function(x)x$details$kind,"")
  stopifnot(length(kinds)==3L,sum(kinds=="strategy")==2L,sum(kinds=="annotation")==1L,
    all(result$sc_annotation=="Unknown"),ncol(result)==ncol(input),
    identical(digest::digest(input,algo="sha256",serializeVersion=2L),before))
  list(result=result,project=done,receipt=list(status="complete",gates=3L,
    approval_kinds=kinds,cells=ncol(result),provider_calls=0L,input_unchanged=TRUE,
    diagnostic_resolutions=initial$plan$clustering$diagnostic_resolutions))
}
