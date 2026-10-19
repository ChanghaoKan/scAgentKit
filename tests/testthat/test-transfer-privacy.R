transfer_privacy_input <- function() {
  env <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = env)
  env$pbmc_small
}

test_that("rare declared groups and cell-ID-like values cannot enter a provider request", {
  seu <- transfer_privacy_input()
  seu$sample <- c(rep("common", 76), rep("private-rare", 4))
  context <- list(species = "human", columns = list(sample = "sample"))
  policy <- .sc_run_metadata_transfer_policy(seu, context)
  expect_true(policy$blocked); expect_identical(policy$rare_role_columns, "sample")
  expect_false(grepl("private-rare", .sc_run_provider_json(policy)))
  expect_error(.sc_run_request("strategy", list(), list(context = context, metadata_transfer_policy = policy)), "No model request")
  seu$sample <- rep(colnames(seu)[[1L]], ncol(seu))
  policy <- .sc_run_metadata_transfer_policy(seu, context)
  expect_true(policy$blocked); expect_identical(policy$cell_id_role_columns, "sample")
  expect_length(policy$rare_role_columns, 0L)
  expect_true(.sc_run_metadata_transfer_policy(seu, list(species = "human", notes = paste("Inspect", colnames(seu)[[2L]])))$context_mentions_cell_ids)
})

test_that("a privacy block preserves the local modern strategy and cannot dispatch", {
  seu <- transfer_privacy_input(); seu$sample <- c(rep("common", 76), rep("private-rare", 4))
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  sc_analyze(seu, root, context = list(species = "human", columns = list(sample = "sample")), provider = "mock",
    plan = list(analysis = list(nfeatures = 100, npcs = 6), pcs = 4, umap = FALSE))
  view <- sc_run_inspect(root); before <- .sc_run_load(root)$pending
  preview <- sc_run_suggest(root)
  expect_false(preview$available)
  expect_match(preview$blocked_reason, "No model request")
  expect_identical(view$status, "awaiting_review")
  expect_identical(.sc_run_load(root)$pending, before)
  expect_false(file.exists(file.path(root, "provider", "ledger.json")))
  expect_length(.sc_run_load(root)$approvals, 0L)
})

test_that("a model cannot disable the standard raw project's measured review gate", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  sc_analyze(transfer_privacy_input(), root, list(species = "human"),
    plan = list(analysis = list(nfeatures = 100, npcs = 6), pcs = 4, umap = FALSE))
  state <- .sc_run_load(root); evidence <- .sc_run_get(root, state, "strategy_evidence")
  proposal <- .sc_run_get(root, state, "manual_strategy")
  expect_true(evidence$summary$require_three_gates)
  proposal$clustering$diagnostic_resolutions <- NULL
  expect_error(.sc_run_strategy_validate(proposal, evidence), "cannot remove the second")
  expect_length(state$approvals, 0L)
})

test_that("privacy suppression leaves a complete local rule path through three explicit approvals", {
  seu<-transfer_privacy_input(); seu$sample<-c(rep("common",76),rep(colnames(seu)[[1L]],4))
  root<-tempfile();on.exit(unlink(root,recursive=TRUE))
  source_hash<-.sc_run_hash(seu)
  confirmation<-list(mode="project",confirmed=TRUE,reviewer="offline-human",reason="Public aggregate test scope only.",
    categories=c("study_context","aggregate_qc","aggregate_markers","aggregate_design","aggregate_expression"))
  x<-sc_analyze(seu,root,context=list(species="human",tissue="blood",columns=list(sample="sample")),
    provider=list(name="offline_remote",external=TRUE,model="never-dispatched",reservation_usd=.01),budget=.1,
    review=list(allow_external=TRUE,transfer_consent=confirmation),qc_mad=FALSE,cycle_diagnostics=FALSE,doublet_diagnostics=FALSE,
    plan=list(qc=list(nCount=c(0,NA)),analysis=list(nfeatures=100,npcs=6),pcs=4,diagnostic_resolutions=c(.4,.6),umap=FALSE))
  original<-.sc_run_load(root)$files$input
  before<-sc_run_suggest(root)
  expect_false(before$available);expect_false(before$can_auto_request)
  preview<-.sc_run_provider_json(before)
  expect_false(grepl(colnames(seu)[[1L]],preview,fixed=TRUE))
  expect_false(grepl('"common"',preview,fixed=TRUE))
  reviewed<-function(x,...) {invisible(capture.output(out<-sc_review(x,...)));out}
  x<-suppressWarnings(reviewed(reviewed(x),"approve",reviewer="offline-human",reason="Explicit local keep-all software control.",continue=TRUE))
  expect_identical(x$view$pending$kind,"strategy")
  expect_length(.sc_run_load(root)$approvals,1L)
  x<-suppressWarnings(reviewed(reviewed(x),"approve",reviewer="offline-human",reason="Inspect and retain the actual scanned resolution.",continue=TRUE))
  expect_identical(x$view$stage,"annotation_propose");expect_length(.sc_run_load(root)$approvals,2L)
  labels<-x$annotations;expect_true(is.data.frame(labels)&&nrow(labels)>0L)
  labels$label<-"Unknown";labels$confidence<-"low";labels$rationale<-"Rule fallback abstains from biological identity.";labels$markers<-""
  x<-reviewed(reviewed(x),"revise",annotations=labels,reviewer="offline-human",reason="Complete local Unknown draft.")
  expect_false(sc_run_suggest(root)$available)
  done<-suppressWarnings(reviewed(reviewed(x),"approve",reviewer="offline-human",reason="Approve explicit local abstention after review.",continue=TRUE))
  expect_identical(done$view$status,"complete")
  state<-.sc_run_load(root)
  expect_length(state$approvals,3L);expect_identical(state$files$input,original)
  expect_false(file.exists(file.path(root,"provider","ledger.json")))
  expect_identical(.sc_run_hash(seu),source_hash)
  result<-sc_result(done)
  expect_identical(colnames(result),colnames(seu));expect_identical(result$sample,seu$sample)
  expect_true(all(result$sc_annotation=="Unknown"));expect_identical(ncol(result),80L)
})
