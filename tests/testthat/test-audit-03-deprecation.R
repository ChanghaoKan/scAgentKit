test_that("legacy workflow entry emits a lifecycle warning with a real migration route", {
  old <- options(lifecycle_verbosity="warning")
  obj <- AgentSeurat(SeuratObject::pbmc_small)
  warnings <- character()
  tryCatch(withCallingHandlers(qc_add_metrics(obj,species="human"),warning=function(w) {
    if(inherits(w,"lifecycle_warning_deprecated")) {warnings <<- c(warnings,conditionMessage(w));invokeRestart("muffleWarning")}
  }),finally=options(old))
  expect_length(warnings,1)
  expect_match(paste(warnings,collapse=" "),"sc_run_qc_review",fixed=TRUE)
  expect_match(paste(warnings,collapse=" "),"sc_run",fixed=TRUE)
})

test_that("every deprecated workflow keeps its export and a concrete path", {
  routes <- scAgentKit:::.legacy_workflow_routes()
  for (name in names(routes)) {
    expect_true(name %in% getNamespaceExports("scAgentKit"),info=name)
    fn <- getExportedValue("scAgentKit",name)
    expect_match(paste(deparse(body(fn)),collapse=" "),paste0('.legacy_workflow_warn("',name,'")'),fixed=TRUE)
    expect_match(routes[[name]],"sc_run",fixed=TRUE)
  }
})
