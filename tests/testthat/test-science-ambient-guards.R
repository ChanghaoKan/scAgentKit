test_that("ambient adapters require explicit capture, matched counts and adequate background before dependency use", {
  x <- Matrix::Matrix(matrix(1,3,4,dimnames=list(c("G1","G2","G3"),letters[1:4])),sparse=TRUE)
  clusters <- c(a="0",b="0",c="1",d="1")
  capture <- list(id="capture1",source="Synthetic test only",complete=TRUE)
  expect_error(sc_run_ambient_correction(x,"SoupX",capture,clusters),"raw\\+filtered")
  bad <- capture; bad$complete <- FALSE
  expect_error(sc_run_ambient_correction(x,"decontX",bad,clusters),"complete")
  expect_error(sc_run_ambient_correction(x,"decontX",capture,unname(clusters)),"exact cell")
  raw <- cbind(x,x); colnames(raw) <- letters[1:8]; raw[1,1] <- 2
  expect_error(sc_run_ambient_correction(x,"SoupX",capture,clusters,raw),"disagree")
  expect_identical(x[1,1],1)
})
