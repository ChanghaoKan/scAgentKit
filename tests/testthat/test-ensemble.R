# .ensemble_annotate calls chat_fn n_samples times and aggregates. We
# inject a stub chat_fn that returns canned responses so the test
# doesn't depend on any LLM provider.

make_stub <- function(responses) {
  i <- 0
  function(system_prompt, user_prompt, image_path = NULL) {
    i <<- i + 1
    responses[[min(i, length(responses))]]
  }
}

test_that(".ensemble_annotate picks the modal label and reports agreement", {
  # 4 of 5 calls say "T cell", 1 says "NK cell"
  json_t  <- '{"primary_annotation":"T cell","confidence":"high","supporting_markers":["CD3D","CD8A"],"contradicting_markers":[],"alternative_annotations":[],"proportion_assessment":"reasonable","recommended_action":"accept","reasoning":"T markers"}'
  json_nk <- '{"primary_annotation":"NK cell","confidence":"medium","supporting_markers":["NKG7","KLRD1"],"contradicting_markers":[],"alternative_annotations":[],"proportion_assessment":"reasonable","recommended_action":"accept","reasoning":"NK markers"}'
  chat_fn <- make_stub(list(json_t, json_t, json_t, json_t, json_nk))

  out <- scAgentKit:::.ensemble_annotate(
    chat_fn, "sys", "user", n_samples = 5, max_retries = 0
  )
  expect_equal(tolower(out$primary_annotation), "t cell")
  expect_equal(out$ensemble_n, 5L)
  expect_equal(out$ensemble_agreement, 0.8)
  expect_equal(out$recommended_action, "accept")
})

test_that(".ensemble_annotate escalates to flag_for_review on low agreement", {
  # 50/50 split: 2 T cell, 2 B cell
  json_t <- '{"primary_annotation":"T cell","confidence":"high","supporting_markers":[],"contradicting_markers":[],"alternative_annotations":[],"proportion_assessment":"reasonable","recommended_action":"accept","reasoning":"T"}'
  json_b <- '{"primary_annotation":"B cell","confidence":"high","supporting_markers":[],"contradicting_markers":[],"alternative_annotations":[],"proportion_assessment":"reasonable","recommended_action":"accept","reasoning":"B"}'
  chat_fn <- make_stub(list(json_t, json_b, json_t, json_b))

  out <- scAgentKit:::.ensemble_annotate(
    chat_fn, "sys", "user", n_samples = 4, max_retries = 0
  )
  expect_equal(out$ensemble_agreement, 0.5)
  expect_equal(out$recommended_action, "flag_for_review")
})

test_that(".ensemble_annotate unions supporting_markers from modal responses", {
  # Two T cell calls cite different supporting markers; union should
  # include both sets
  json_t1 <- '{"primary_annotation":"T cell","confidence":"high","supporting_markers":["CD3D","CD8A"],"contradicting_markers":[],"alternative_annotations":[],"proportion_assessment":"reasonable","recommended_action":"accept","reasoning":"T1"}'
  json_t2 <- '{"primary_annotation":"T cell","confidence":"high","supporting_markers":["CD3E","TRBC1"],"contradicting_markers":[],"alternative_annotations":[],"proportion_assessment":"reasonable","recommended_action":"accept","reasoning":"T2"}'
  chat_fn <- make_stub(list(json_t1, json_t2))

  out <- scAgentKit:::.ensemble_annotate(
    chat_fn, "sys", "user", n_samples = 2, max_retries = 0
  )
  expect_setequal(out$supporting_markers,
                  c("CD3D", "CD8A", "CD3E", "TRBC1"))
})

test_that(".ensemble_annotate worst-case action priority: reject > flag > accept", {
  json_accept <- '{"primary_annotation":"T cell","confidence":"high","supporting_markers":[],"contradicting_markers":[],"alternative_annotations":[],"proportion_assessment":"reasonable","recommended_action":"accept","reasoning":""}'
  json_reject <- '{"primary_annotation":"T cell","confidence":"low","supporting_markers":[],"contradicting_markers":[],"alternative_annotations":[],"proportion_assessment":"reasonable","recommended_action":"reject","reasoning":""}'
  chat_fn <- make_stub(list(json_accept, json_accept, json_reject))

  out <- scAgentKit:::.ensemble_annotate(
    chat_fn, "sys", "user", n_samples = 3, max_retries = 0
  )
  expect_equal(out$recommended_action, "reject")
})

test_that(".ensemble_annotate handles all-failed gracefully", {
  # Non-parseable strings — .call_with_retry returns a structured failure
  bad <- "this is not JSON"
  chat_fn <- make_stub(list(bad, bad, bad))
  out <- scAgentKit:::.ensemble_annotate(
    chat_fn, "sys", "user", n_samples = 3, max_retries = 0
  )
  # Either all failed (NA primary) — agreement should be 0 / ensemble_n 0
  expect_equal(out$ensemble_n, 0L)
})
