test_that("complete choice reasons are bounded, plain and required for modern strategies", {
  value <- .sc_run_default_choice_reasons("Keep all until quality is assessed.")
  expect_identical(.sc_run_choice_reasons(value, TRUE), value)
  expect_error(.sc_run_choice_reasons(NULL, TRUE), "reason for every")
  expect_null(.sc_run_choice_reasons(NULL, FALSE))
  incomplete <- value; incomplete$cycle <- NULL
  expect_error(.sc_run_choice_reasons(incomplete, TRUE), "exactly")
  blank <- value; blank$qc <- ""
  expect_error(.sc_run_choice_reasons(blank, TRUE), "nonempty")
  long <- value; long$hvg <- paste(rep("x", 701), collapse = "")
  expect_error(.sc_run_choice_reasons(long, TRUE), "700")
  private <- new.env(); private$marker <- "private attribute"
  attributed <- value; attr(attributed$qc, "private") <- private
  expect_null(attr(.sc_run_choice_reasons(attributed)$qc, "private"))
})

test_that("one reason revision preserves all other saved draft choices", {
  draft <- .sc_ui_plan(dimensions = c(100, 80))
  before <- draft
  reasons <- draft$choice_reasons; reasons$cycle <- "Keep proliferation biology for this study; no regression."
  changed <- .sc_ui_plan(list(choice_reasons = reasons), base = draft)
  before$choice_reasons$cycle <- reasons$cycle
  expect_identical(changed, before)
})
