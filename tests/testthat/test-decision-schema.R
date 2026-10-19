decision_parse <- function(raw) jsonlite::fromJSON(raw, simplifyVector = FALSE)

decision_provider <- function(replies) {
  i <- 0L
  function(system_prompt, user_prompt, image_path = NULL) {
    i <<- i + 1L
    replies[[min(i, length(replies))]]
  }
}

test_that("PC decisions require an integer candidate and the full schema", {
  withr::local_options(lifecycle_verbosity="quiet")
  validate <- function(raw) scAgentKit:::.validate_pcs_decision(decision_parse(raw), c(10L, 20L))
  good <- '{"chosen_ndim":20,"confidence":"medium","reasoning":"The second panel separates major groups."}'
  expect_identical(validate(good)$chosen_ndim, 20L)
  invalid <- c(
    '{"chosen_ndim":"20","confidence":"medium","reasoning":"x"}',
    '{"chosen_ndim":20.9,"confidence":"medium","reasoning":"x"}',
    '{"chosen_ndim":15,"confidence":"medium","reasoning":"x"}',
    '{"chosen_ndim":[20],"confidence":"medium","reasoning":"x"}',
    '{"chosen_ndim":null,"confidence":"medium","reasoning":"x"}',
    '{"chosen_ndim":20,"confidence":"certain","reasoning":"x"}',
    '{"chosen_ndim":20,"confidence":"medium","reasoning":" "}',
    '{"chosen_ndim":20,"confidence":"medium"}',
    '{"chosen_ndim":20,"confidence":"medium","reasoning":"x","chosen":10}',
    '{"chosen_ndim":10,"chosen_ndim":20,"confidence":"medium","reasoning":"x"}',
    '[{"chosen_ndim":20,"confidence":"medium","reasoning":"x"}]'
  )
  for (raw in invalid) expect_error(validate(raw))
  for (bad in c(NA_real_, NaN, Inf, -Inf)) {
    parsed <- decision_parse(good)
    parsed$chosen_ndim <- bad
    expect_error(scAgentKit:::.validate_pcs_decision(parsed, c(10L, 20L)), "finite")
  }
})


test_that("resolution decisions are restricted to swept and visible candidates", {
  withr::local_options(lifecycle_verbosity="quiet")
  validate <- function(raw, panels = numeric(), vision = FALSE) {
    scAgentKit:::.validate_resolution_decision(decision_parse(raw), c(0.2, 0.4, 0.6), panels, vision)
  }
  good <- '{"chosen_resolution":0.4,"confidence":"high","alternatives":[0.2,0.6],"reasoning":"ARI is stable at 0.4."}'
  expect_equal(validate(good)$alternatives, c(0.2, 0.6))
  invalid <- c(
    '{"chosen_resolution":"0.4","confidence":"high","alternatives":[],"reasoning":"x"}',
    '{"chosen_resolution":0.35,"confidence":"high","alternatives":[],"reasoning":"x"}',
    '{"chosen_resolution":0.4,"confidence":["high"],"alternatives":[],"reasoning":"x"}',
    '{"chosen_resolution":0.4,"confidence":"high","alternatives":["0.2"],"reasoning":"x"}',
    '{"chosen_resolution":0.4,"confidence":"high","alternatives":[0.9],"reasoning":"x"}',
    '{"chosen_resolution":0.4,"confidence":"high","alternatives":0.2,"reasoning":"x"}',
    '{"chosen_resolution":0.4,"confidence":"high","alternatives":null,"reasoning":"x"}'
  )
  for (raw in invalid) expect_error(validate(raw))
  expect_error(validate(good, c(0.2, 0.6)), "supplied candidates")
  expect_error(validate(good, vision = TRUE), "Missing decision fields")
  with_notes <- sub('"reasoning":', '"visual_notes":"Panels show coherent groups.","reasoning":', good, fixed = TRUE)
  expect_equal(validate(with_notes, c(0.2, 0.4), TRUE)$chosen_resolution, 0.4)
  expect_error(validate(sub("Panels show coherent groups.", " ", with_notes, fixed = TRUE), vision = TRUE), "non-empty")
  for (bad in c(NA_real_, NaN, Inf, -Inf)) {
    parsed <- decision_parse(good)
    parsed$chosen_resolution <- bad
    expect_error(scAgentKit:::.validate_resolution_decision(parsed, c(0.2, 0.4, 0.6)), "finite")
  }
})


test_that("batch decisions validate all fields and refuse invented metadata columns", {
  withr::local_options(lifecycle_verbosity="quiet")
  validate <- function(raw) scAgentKit:::.validate_batch_decision(decision_parse(raw), c("sample", "donor"))
  good <- '{"recommended":"sample","confidence":"medium","alternatives":["donor"],"warnings":[],"reasoning":"Samples capture technical variation."}'
  expect_identical(validate(good)$alternatives, "donor")
  expect_identical(validate(good)$warnings, character())
  invalid <- c(
    '{"recommended":["sample"],"confidence":"medium","alternatives":[],"warnings":[],"reasoning":"x"}',
    '{"recommended":"invented","confidence":"medium","alternatives":[],"warnings":[],"reasoning":"x"}',
    '{"recommended":"sample","confidence":"sure","alternatives":[],"warnings":[],"reasoning":"x"}',
    '{"recommended":"sample","confidence":"medium","alternatives":["invented"],"warnings":[],"reasoning":"x"}',
    '{"recommended":"sample","confidence":"medium","alternatives":"donor","warnings":[],"reasoning":"x"}',
    '{"recommended":"sample","confidence":"medium","alternatives":[],"warnings":{"risk":"x"},"reasoning":"x"}',
    '{"recommended":"sample","confidence":"medium","alternatives":[],"warnings":[false],"reasoning":"x"}',
    '{"recommended":"sample","confidence":"medium","alternatives":[],"reasoning":"x"}'
  )
  for (raw in invalid) expect_error(validate(raw))
})
