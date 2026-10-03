run_fixture <- function() {
  set.seed(81)
  counts <- matrix(rpois(80 * 100, 2), 80, dimnames = list(c("MT-CO1", paste0("GENE", 2:80)), paste0("cell", 1:100)))
  counts[2:12, 1:50] <- counts[2:12, 1:50] + 15L
  counts[13:25, 51:100] <- counts[13:25, 51:100] + 15L
  seu <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE))
  seu$sample <- rep(c("sampleA", "sampleB"), each = 50)
  seu$capture <- rep(c("cap1", "cap2"), 50)
  seu$condition <- rep(c("Ca", "Ctrl"), 50)
  seu$old_annotation <- rep(c("oldA", "oldB"), each = 50)
  seu
}
run_context <- function() list(species = "human", tissue = "synthetic", columns = list(sample = "sample", capture = "capture", condition = "condition"), notes = "Public synthetic data; capture is not donor.")
run_qc_rule <- function(minimum = 1) list(schema = "scagentkit.qc.v1", rationale = "Keep count-positive cells for this synthetic validation.", risks = list("This does not validate a biological QC threshold."), filters = list(list(op = "range", metric = "nCount", min = minimum, max = NULL, group = NULL)))
run_mock <- function(counter) function(system_prompt, user_prompt) {
  counter$calls <- counter$calls + 1L
  payload <- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)
  if (grepl("qc.v1", system_prompt, fixed = TRUE)) value <- run_qc_rule() else {
    value <- list(schema = "scagentkit.annotation.v1", annotations = lapply(payload$evidence$clusters, function(cl) list(clusterId = cl$clusterId, label = "unknown", confidence = "low", rationale = "Synthetic validation; no claim of biological identity.", markers = list())))
  }
  as.character(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null"))
}
run_begin <- function(path, fixture = run_fixture(), crash = NULL) {
  counter <- new.env(); counter$calls <- 0L
  out <- suppressWarnings(sc_run(fixture, path, context = run_context(), provider = list(name = "mock", external = FALSE), chat_fn = run_mock(counter), analysis = list(nfeatures = 60, npcs = 5, run_umap = FALSE)))
  list(out = out, counter = counter)
}
run_approve <- function(path) {
  inspected <- sc_run_inspect(path)
  sc_run_approve(path, inspected$pending$hash, reviewer = "test", reason = "Verified synthetic scope")
}

test_that("mock R headless loop pauses before computation, exact ID writes and source stays unchanged", {
  path <- tempfile(); input <- run_fixture(); hash <- .sc_run_hash(input)
  run <- run_begin(path, input)
  expect_identical(run$out$status, "awaiting_review")
  expect_identical(run$out$pending$kind, "qc")
  expect_false(dir.exists(file.path(path, "bundle")))
  state <- .sc_run_load(path); expect_null(state$files$analysis)
  expect_identical(.sc_run_hash(input), hash)
  expect_equal(run$counter$calls, 1)
  expect_identical(sc_run_resume(path)$status, "awaiting_review")
  expect_equal(run$counter$calls, 1)
  qc_hash <- sc_run_inspect(path)$pending$hash
  run_approve(path)
  expect_identical(sc_run_approve(path, qc_hash, "test")$status, "ready")
  next_out <- suppressWarnings(sc_run_resume(path, chat_fn = run_mock(run$counter)))
  expect_identical(next_out$status, "awaiting_review")
  expect_identical(next_out$pending$kind, "annotation")
  expect_equal(run$counter$calls, 2)
  run_approve(path)
  complete <- suppressWarnings(sc_run_resume(path))
  expect_identical(complete$status, "complete")
  output <- readRDS(complete$output$seurat)
  expect_identical(colnames(output), colnames(input))
  expect_identical(output$old_annotation, input$old_annotation)
  expect_true(all(output$sc_annotation == "unknown"))
  expect_identical(.sc_run_hash(input), hash)
  expect_identical(complete$output$scientific_result, "EXECUTED")
  expect_identical(sc_run_accept(path, "test", "Scientific review of synthetic result")$output$scientific_result, "RESULT_ACCEPTED")
  expect_identical(sc_run_resume(path)$status, "complete")
  expect_equal(run$counter$calls, 2)
  history <- .sc_run_load(path)$history
  approval <- Filter(function(e) e$action == "approved" && e$details$kind == "annotation", history)[[1]]
  undone <- sc_run_undo(path, approval$details$decision_id, "test", "Change review")
  expect_identical(undone$status, "awaiting_configuration")
  expect_true(dir.exists(file.path(path, "versions")))
  expect_error(sc_run_undo(path, approval$details$decision_id, "test", "Repeat"), "No executed|already undone")
  ev <- sc_run_inspect(path)$evidence
  manual <- list(schema = "scagentkit.annotation.v1", annotations = lapply(ev$clusters, function(cl) list(clusterId=cl$clusterId,label="manual",confidence="low",rationale="New review",markers=list(cl$markers[[1]]$gene))))
  sc_run_propose(path, manual, "test", "Replacement")
  run_approve(path); complete <- suppressWarnings(sc_run_resume(path))
  expect_identical(complete$status, "complete")
  expect_true(all(readRDS(complete$output$seurat)$sc_annotation == "manual"))
})

test_that("manual no provider diagnostics and reject/replace invalidate prior proposal", {
  path <- tempfile()
  out <- sc_run(run_fixture(), path, context = run_context(), analysis = list(run_umap = FALSE))
  expect_identical(out$status, "awaiting_configuration")
  expect_false(dir.exists(file.path(path, "provider")))
  out <- sc_run_propose(path, run_qc_rule(), "test", "Manual threshold")
  old <- out$pending$hash
  sc_run_reject(path, old, "test", "Replace with stricter rule")
  new <- sc_run_propose(path, run_qc_rule(2), "test", "Updated threshold")
  expect_false(identical(old, new$pending$hash))
  expect_error(sc_run_approve(path, old, "test"), "Stale")
})

test_that("saved input, config, implementation and original RDS changes fail closed", {
  path <- tempfile(); run_begin(path); hash <- sc_run_inspect(path)$pending$hash
  file <- file.path(path, .sc_run_load(path)$files$input$path)
  saveRDS(run_fixture()[, -1], file)
  expect_error(sc_run_approve(path, hash, "test"), "changed")
  path <- tempfile(); run_begin(path); state <- .sc_run_load(path)
  state$config$analysis$npcs <- 4
  .sc_run_save(path, state)
  expect_error(sc_run_approve(path, state$pending$hash, "test"), "Configuration|hashes changed")
  expect_error(sc_run_resume(path), "Configuration|hashes changed")
  path <- tempfile(); inputfile <- tempfile(fileext = ".rds"); saveRDS(run_fixture(), inputfile)
  counter <- new.env(); counter$calls <- 0L
  sc_run(inputfile, path, context = run_context(), provider = list(name="mock"), chat_fn = run_mock(counter))
  saveRDS(run_fixture()[, -1], inputfile)
  expect_error(sc_run_resume(path), "Original input RDS changed")
})

test_that("missing approval cannot execute QC even if stage is tampered", {
  path <- tempfile(); run_begin(path); state <- .sc_run_load(path)
  state$stage <- "qc_apply"; state$pending <- NULL; state$status <- "ready"
  .sc_run_save(path, state)
  out <- sc_run_resume(path)
  expect_identical(out$status, "failed")
  expect_match(out$failure$message, "approval is absent")
  expect_null(.sc_run_load(path)$files$qc_object)
})

test_that("artifact/checkpoint crashes recover completed upstream without repeated API", {
  for (point in c("qc_apply:artifact", "qc_apply:checkpoint", "analysis:artifact", "analysis:checkpoint")) {
    path <- tempfile(); run <- run_begin(path); run_approve(path)
    options(scAgentKit.run_crash = point)
    out <- suppressWarnings(sc_run_resume(path, chat_fn = run_mock(run$counter)))
    options(scAgentKit.run_crash = NULL)
    expect_true(out$status %in% c("failed", "ready"))
    calls <- run$counter$calls
    out <- suppressWarnings(sc_run_resume(path, chat_fn = run_mock(run$counter), retry = TRUE))
    expect_identical(out$status, "awaiting_review")
    expect_identical(out$pending$kind, "annotation")
    expect_equal(run$counter$calls, calls + 1L)
    expect_true(all(c("qc_apply", "analysis") %in% .sc_run_load(path)$completed))
  }
  options(scAgentKit.run_crash = NULL)
})

test_that("single writer lock rejects operation and never silently steals", {
  path <- tempfile(); run_begin(path); owner <- .sc_run_lock(path)
  expect_error(sc_run_resume(path), "locked")
  expect_error(sc_run_approve(path, sc_run_inspect(path)$pending$hash, "test"), "locked")
  expect_error(sc_run_unlock(path, owner$token, "Test"), "still alive")
  .sc_run_release(path, owner)
})

test_that("processed source reuse records reason and preserves basic analysis", {
  seu <- run_fixture(); SeuratObject::LayerData(seu, assay="RNA", layer="data") <- log1p(SeuratObject::LayerData(seu, assay="RNA",layer="counts"))
  seu$seurat_clusters <- rep(c("A", "B"), each = 50)
  path <- tempfile(); counter <- new.env(); counter$calls <- 0L
  out <- suppressWarnings(sc_run(seu, path, context=run_context(),provider=list(name="mock"),chat_fn=run_mock(counter),start_stage="processed",processed_reason="Supplied normalized and clustered public object"))
  expect_identical(out$status, "awaiting_review")
  expect_identical(out$pending$kind, "annotation")
  expect_equal(counter$calls,1)
  expect_null(.sc_run_load(path)$files$qc_object)
  expect_identical(.sc_run_get(path,.sc_run_load(path),"analysis"),seu)
  expect_error(sc_run(seu,tempfile(),start_stage="processed"),"processed_reason")
})

test_that("typed invalid provider response can be explicitly retried without redoing upstream", {
  path <- tempfile(); calls <- 0L
  bad <- function(system_prompt,user_prompt) { calls <<- calls+1L; value <- run_qc_rule(); value$filters[[1]]$op <- "eval"; jsonlite::toJSON(value,auto_unbox=TRUE,null="null") }
  out <- sc_run(run_fixture(),path,context=run_context(),provider=list(name="mock"),chat_fn=bad)
  expect_identical(out$status,"failed"); expect_equal(calls,1L)
  good <- function(system_prompt,user_prompt) { calls <<- calls+1L; jsonlite::toJSON(run_qc_rule(),auto_unbox=TRUE,null="null") }
  expect_identical(sc_run_resume(path,chat_fn=good)$status,"failed"); expect_equal(calls,1L)
  expect_identical(sc_run_resume(path,chat_fn=good,retry=TRUE)$status,"awaiting_review"); expect_equal(calls,2L)
})

test_that("external payload must be previewed and approved before dispatch or QC execution", {
  counter <- new.env(); counter$calls <- 0L
  provider <- list(name="custom",external=TRUE,model="test",reservation_usd=.01)
  known <- function(system_prompt,user_prompt) list(content=run_mock(counter)(system_prompt,user_prompt),cost_usd=.001,usage=list(input_tokens=100,output_tokens=100))
  path <- tempfile(); out <- sc_run(run_fixture(),path,context=run_context(),provider=provider,chat_fn=known,budget=.02)
  expect_identical(out$status,"awaiting_configuration"); expect_equal(counter$calls,0)
  path <- tempfile(); out <- sc_run(run_fixture(),path,context=run_context(),provider=provider,chat_fn=known,budget=.02,review=list(allow_external=TRUE))
  expect_identical(out$pending$kind,"external_transfer"); expect_equal(counter$calls,0)
  expect_false(grepl('cell[0-9]',out$pending$proposal$payload$user_prompt))
  run_approve(path); out <- sc_run_resume(path,chat_fn=known)
  expect_identical(out$pending$kind,"qc"); expect_equal(counter$calls,1)
  expect_null(.sc_run_load(path)$files$qc_object)
  expect_identical(sc_run_resume(path)$pending$kind,"qc"); expect_equal(counter$calls,1)
})

test_that("terminal and undo crash points leave usable committed state", {
  for (point in c("finalize:artifact","finalize:checkpoint","undo:archive","undo:checkpoint")) {
    path <- tempfile(); run <- run_begin(path); run_approve(path)
    out <- suppressWarnings(sc_run_resume(path,chat_fn=run_mock(run$counter))); run_approve(path)
    if (startsWith(point,"finalize")) {
      options(scAgentKit.run_crash=point); out <- suppressWarnings(sc_run_resume(path)); options(scAgentKit.run_crash=NULL)
      expect_true(out$status %in% c("failed","complete"))
      expect_identical(suppressWarnings(sc_run_resume(path,retry=TRUE))$status,"complete")
    } else {
      suppressWarnings(sc_run_resume(path))
      history <- .sc_run_load(path)$history
      decision <- Filter(function(e) e$action=="approved" && e$details$kind=="annotation",history)[[1]]$details$decision_id
      options(scAgentKit.run_crash=point); expect_error(sc_run_undo(path,decision,"test","Undo crash test"),"Injected crash"); options(scAgentKit.run_crash=NULL)
      expect_true(sc_run_inspect(path)$status %in% c("complete","awaiting_configuration"))
      if (point=="undo:archive") sc_run_undo(path,decision,"test","Retry undo") else sc_run_resume(path)
      expect_true(sc_run_inspect(path)$status %in% c("awaiting_configuration","awaiting_review"))
    }
  }
  options(scAgentKit.run_crash=NULL)
})
