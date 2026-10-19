test_that("R review printing is bounded while the sealed full evidence stays accessible", {
  global <- list(clusters=lapply(seq_len(30),function(i) list(cluster=as.character(i),
    cell_ids=paste0("CELL_",seq_len(1000)),genes=rep("GENE",1000))),
    rationale=paste(rep("Long evidence with unicode 证据",2000),collapse=" "))
  view <- list(status="awaiting_review",stage="annotation_propose",context=list(tissue="Blood"),
    evidence=list(clusters=list()),annotation_review=list(details=list(
      annotations=lapply(seq_len(30),function(i) list(clusterId=as.character(i),measured_expression=global)),
      full_evidence=global)),pending=list(kind="annotation"))
  x <- .sc_ui_object(tempfile(),view,reviewed=TRUE)
  original <- .sc_run_hash(x); limit <- getOption("max.print")
  text <- capture.output(returned <- print(x))
  expect_lt(nchar(paste(text,collapse="\n"),type="bytes"),18000L)
  expect_true(any(grepl("snapshot\\$view",text)))
  expect_true(any(grepl("supplied marker evidence",text)))
  expect_identical(.sc_run_hash(x),original)
  expect_identical(returned,x)
  expect_identical(getOption("max.print"),limit)
  expect_identical(x$view$annotation_review$details$full_evidence,global)
})
