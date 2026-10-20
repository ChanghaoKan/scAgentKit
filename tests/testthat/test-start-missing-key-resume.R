test_that('missing-key fallback allows an explicit same-provider request without automatic retry', {
  e <- new.env(); utils::data('pbmc_small',package='SeuratObject',envir=e)
  root <- tempfile('missing-key-resume-'); on.exit(unlink(root,recursive=TRUE))
  sc_analyze(e$pbmc_small,root,context=list(species='human',tissue='blood'),provider='mock',
    qc_mad=FALSE,cycle_diagnostics=FALSE,doublet='off',
    plan=list(analysis=list(nfeatures=100,npcs=6),pcs=4,umap=FALSE))
  act <- function(action,...) {
    v <- sc_run_suggest(root)
    sc_run_suggest(root,action,project_id=v$project_id,input_hash=v$input_hash,
      expected_revision=v$revision,suggestion_hash=v$suggestion_hash,
      reviewer='test',reason='Explicit same-provider retry.',...)
  }
  provider <- .sc_run_load(root)$config$provider
  act('approve')
  answer <- act('request')
  expect_identical(answer$response$status,'needs_provider')
  preview <- sc_run_suggest(root)
  expect_true(preview$can_request || preview$can_approve)
  expect_false(preview$can_auto_request)
  if (preview$can_approve) act('approve')
  calls <- 0L
  expect_no_error(act('request',chat_fn=function(...) {
    calls <<- calls + 1L
    "{invalid"
  }))
  expect_equal(calls,1L)
  expect_identical(.sc_run_load(root)$config$provider,provider)
  expect_length(.sc_run_load(root)$approvals,0L)
})
