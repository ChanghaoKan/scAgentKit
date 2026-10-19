test_that('measured Flash gets a small cap without granting transfer or reading credentials',{
 p<-.sc_run_new_budget('deepseek')
 expect_equal(p$budget,1);expect_equal(p$provider$reservation_usd,.05)
 expect_equal(p$provider$pricing$input_per_million,.30)
 expect_equal(.sc_run_new_budget('deepseek',0)$budget,0)
 expect_equal(.sc_run_new_budget('deepseek',.07)$budget,.07)
 expect_equal(.sc_run_new_budget('manual')$budget,0)
 expect_equal(.sc_run_new_budget('grok')$budget,0)
 expect_equal(.sc_run_new_budget('deepseek',chat_fn=function(...)NULL)$budget,0)
 expect_equal(.sc_run_new_budget(list(name='deepseek',generation=list(max_tokens=8192)))$budget,0)
 expect_equal(.sc_run_new_budget(list(name='deepseek',reservation_usd=.35))$budget,0)
 expect_lt((100000*.30+4096*1.20)/1e6,.05)
 expect_equal(20*.05,p$budget)
 withr::local_envvar(c(DEEPSEEK_API_KEY='',XAI_API_KEY=''))
 x<-suppressMessages(.sc_start_provider_setup('deepseek'))
 expect_identical(x$provider$name,'manual');expect_equal(x$budget,0);expect_false(x$review$allow_external)
 withr::local_envvar(c(DEEPSEEK_API_KEY='offline-synthetic-key'))
 x<-suppressMessages(.sc_start_provider_setup('deepseek'))
 expect_equal(x$budget,1);expect_false(x$review$allow_external);expect_null(x$review$transfer_consent)
 consent<-list(mode='project',confirmed=TRUE,reviewer='offline',reason='Review data and cap.',categories=c('study_context','aggregate_qc'))
 expect_error(.sc_start_provider_setup('deepseek',review=list(allow_external=TRUE,transfer_consent=consent)),'explicit USD cap')
 approved<-.sc_start_provider_setup('deepseek',budget=.73,review=list(allow_external=TRUE,transfer_consent=consent))
 expect_equal(approved$budget,.73)
})


test_that('budget setup preserves the existing R provider-function callback',{
 callback<-function(system_prompt,user_prompt) 'offline callback'
 selected<-.sc_run_new_budget(callback)
 expect_identical(selected$chat_fn,callback)
 expect_identical(selected$provider$name,'custom')
 expect_equal(selected$budget,0)
 selected<-.sc_run_new_budget('deepseek',chat_fn=callback)
 expect_identical(selected$chat_fn,callback)
 expect_false(selected$calibrated)
})


test_that('custom caps reject nonfinite or nonnumeric values without provider dispatch',{
 for(value in list(-1,NA_real_,NaN,Inf,-Inf,"1",TRUE,c(1,2))) {
  expect_error(.sc_run_new_budget('deepseek',value),'budget')
  expect_error(.sc_start_provider_setup('deepseek',budget=value),'budget')
 }
 expect_equal(.sc_run_new_budget('deepseek',.73)$budget,.73)
 expect_equal(.sc_run_new_budget('grok',.73)$budget,.73)
})


test_that('custom cap is bound to consent and cannot be raised by changing request config',{
 provider<-.sc_run_new_budget('deepseek')$provider
 consent<-list(mode='project',confirmed=TRUE,reviewer='offline',reason='Confirm chosen USD0.73 cap.',
  categories=c('study_context','aggregate_qc','aggregate_markers','aggregate_design','aggregate_expression'))
 config<-list(provider=provider,budget=.73,review=list(allow_external=TRUE,
  transfer_consent=.sc_run_transfer_options(consent,provider,.73)))
 expect_equal(config$review$transfer_consent$budget_usd,.73)
 request<-.sc_run_request('strategy',list(),config)
 expect_true(.sc_run_transfer_authorized(request,config))
 raised<-config;raised$budget<-1
 expect_false(.sc_run_transfer_authorized(request,raised))
 raised$review$transfer_consent$budget_usd<-1
 expect_false(.sc_run_transfer_authorized(request,raised))
})


test_that('native preview shows chosen frozen cap separately from new-project default',{
 e<-new.env();utils::data('pbmc_small',package='SeuratObject',envir=e)
 for(cap in c(.20,.73,1)) {
  root<-tempfile('chosen-cap-');on.exit(unlink(root,recursive=TRUE),add=TRUE)
  sc_analyze(e$pbmc_small,root,context=list(species='human',tissue='blood'),provider='deepseek',budget=cap,review=list(allow_external=TRUE),
   qc_mad=FALSE,cycle_diagnostics=FALSE,doublet='off',
   plan=list(analysis=list(nfeatures=100,npcs=6),pcs=4,umap=FALSE))
  before<-.sc_project_sha_file(file.path(root,'state.rds'))
  preview<-sc_run_suggest(root)
  expect_equal(preview$new_project_budget_default,1)
  expect_equal(preview$preview$budget,cap)
  expect_equal(preview$preview$remaining_usd,cap)
  expect_identical(.sc_project_sha_file(file.path(root,'state.rds')),before)
  saved<-.sc_run_load(root)$config
  expect_equal(.sc_start_provider_setup(saved=saved)$budget,cap)
  expect_false(file.exists(file.path(root,'provider','ledger.json')))
 }
})
