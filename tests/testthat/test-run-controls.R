test_that("project cancellation preserves checkpoints and resumes explicitly", {
 f <- react_loop_fixture(); on.exit(unlink(f$root,recursive=TRUE))
 before <- .sc_run_load(f$root)
 sc_run_control(f$root,cancel=TRUE,reason="Stop this project")
 expect_error(.sc_run_react_refine(f$root,f$baseline,react_mock()),class="sc_run_cancelled")
 expect_identical(.sc_run_load(f$root)$config_hash,before$config_hash)
 sc_run_control(f$root,cancel=FALSE)
 out <- .sc_run_react_refine(f$root,f$baseline,react_mock())
 expect_identical(out$status,"completed")
 expect_true(length(list.files(file.path(f$root,"controls"))) >= 2L)
})

test_that("disk allowance refuses a new checkpoint without deleting previous results", {
 f <- react_loop_fixture(); on.exit(unlink(f$root,recursive=TRUE))
 state <- .sc_run_load(f$root); before <- state$files
 sc_run_control(f$root,disk_limit_bytes=1)
 expect_error(.sc_run_put(f$root,state,"extra",runif(1000)),class="sc_run_disk_limit")
 expect_identical(.sc_run_load(f$root)$files,before)
 expect_false(any(grepl("extra-",list.files(file.path(f$root,"checkpoints")))))
 sc_run_control(f$root,disk_limit_bytes=NULL)
 expect_no_error(.sc_run_put(f$root,state,"extra",1L))
})

test_that("repeated evidence ends without claiming a validated refinement", {
 f <- react_loop_fixture(list(mode="all",max_steps_per_cluster=10L)); on.exit(unlink(f$root,recursive=TRUE))
 out <- .sc_run_react_refine(f$root,f$baseline,react_mock("forever"))
 trace <- readRDS(file.path(f$root,out$traces[["0"]]$path))
 expect_identical(trace$fallback_reason,"no_progress")
 expect_identical(out$proposal,f$baseline)
})


test_that("prepared undelivered turn resumes with saved time and without model change", {
 f <- react_loop_fixture(); on.exit(unlink(f$root,recursive=TRUE))
 withr::local_options(scAgentKit.run_crash="react:prepared")
 expect_error(.sc_run_react_refine(f$root,f$baseline,react_mock()),"Injected crash")
 options(scAgentKit.run_crash=NULL)
 state <- .sc_run_load(f$root)
 run <- .sc_run_get(f$root,state,"annotation_react_run")
 trace <- readRDS(file.path(f$root,run$traces[["0"]]$path))
 trace$pending_request$deadline <- 1
 trace$pending_request$approved_payload_hash <- .sc_run_request_hash(trace$pending_request,state$config$provider)
 trace$deadline <- as.numeric(Sys.time()) + 30
 .sc_run_react_save(f$root,run,trace)
 calls <- 0L; fn <- react_mock()
 out <- .sc_run_react_refine(f$root,f$baseline,function(...) {calls <<- calls+1L; fn(...)})
 expect_identical(out$status,"completed")
 expect_equal(calls,4)
 expect_identical(.sc_run_load(f$root)$config$provider,state$config$provider)
})
