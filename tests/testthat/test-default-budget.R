test_that("provider defaults have no monetary reservation or cap", {
 p <- .sc_run_new_budget("deepseek")
 expect_equal(p$budget,0); expect_equal(p$provider$reservation_usd,0)
 expect_equal(p$provider$pricing$input_per_million,.30)
 expect_equal(.sc_run_new_budget("deepseek",.07)$budget,0)
 withr::local_envvar(c(DEEPSEEK_API_KEY="",XAI_API_KEY=""))
 x <- suppressMessages(.sc_start_provider_setup("deepseek"))
 expect_identical(x$provider$name,"deepseek"); expect_equal(x$budget,0)
 expect_identical(x$cost_mode,"posthoc"); expect_false(x$review$allow_external)
 consent <- list(mode="project",confirmed=TRUE,reviewer="offline",reason="Review aggregate transfer.",categories=c("study_context","aggregate_qc"))
 approved <- suppressMessages(.sc_start_provider_setup("deepseek",review=list(allow_external=TRUE,transfer_consent=consent)))
 expect_equal(approved$budget,0); expect_true(approved$review$allow_external)
})

test_that("shared provider defaults preserve custom callbacks and validate deprecated numeric input", {
 callback <- function(system_prompt,user_prompt) "offline callback"
 selected <- .sc_run_new_budget(callback)
 expect_identical(selected$chat_fn,callback); expect_identical(selected$provider$name,"custom")
 expect_equal(selected$budget,0)
 for(value in list(-1,NA_real_,NaN,Inf,-Inf,"1",TRUE,c(1,2)))
   expect_error(.sc_run_new_budget("deepseek",value),"budget")
})

test_that("transfer consent binds recipient and data scope rather than deprecated amounts", {
 provider <- .sc_run_new_budget("deepseek")$provider
 consent <- list(mode="project",confirmed=TRUE,reviewer="offline",reason="Confirm aggregate scope.",
   categories=c("study_context","aggregate_qc","aggregate_markers","aggregate_design","aggregate_expression"))
 config <- list(provider=provider,budget=0,review=list(allow_external=TRUE,
   transfer_consent=.sc_run_transfer_options(consent,provider,0)))
 request <- .sc_run_request("strategy",list(),config)
 expect_true(.sc_run_transfer_authorized(request,config))
 config$budget <- 10
 expect_true(.sc_run_transfer_authorized(request,config))
 config$provider$model <- "other-model"
 expect_false(.sc_run_transfer_authorized(request,config))
})
