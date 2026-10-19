test_that("main annotation support requires positive differential and detection direction", {
  marker <- list(gene="G1",avgLog2FC=2,pct1=.8,pct2=.1)
  evidence <- list(summary=list(clusters=list(list(clusterId="0",markers=list(marker)))),
    private=list(input_cells=data.frame(cell_id=c("c1","c2"),cluster="0"),cluster_column="cluster"))
  proposal <- list(schema="scagentkit.annotation.v1",annotations=list(list(clusterId="0",label="Candidate",confidence="low",
    rationale="Software regression",markers=list("G1"))))
  expect_silent(.sc_run_annotation_validate(proposal,evidence))
  evidence$summary$clusters[[1]]$markers[[1]]$avgLog2FC <- -2
  expect_error(.sc_run_annotation_validate(proposal,evidence),"positive saved")
  evidence$summary$clusters[[1]]$markers[[1]]$avgLog2FC <- 2
  evidence$summary$clusters[[1]]$markers[[1]]$pct2 <- .9
  expect_error(.sc_run_annotation_validate(proposal,evidence),"positive saved")
  proposal$annotations[[1]]$label <- "Unknown"
  expect_silent(.sc_run_annotation_validate(proposal,evidence))
})
