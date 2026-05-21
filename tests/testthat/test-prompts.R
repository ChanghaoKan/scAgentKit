test_that(".build_system_prompt: tissue and condition appear in output", {
  prompt <- scAgentKit:::.build_system_prompt(
    tissue             = "HCC tumor",
    condition          = "tumor vs adjacent",
    expected_celltypes = NULL,
    strict_vocabulary  = FALSE
  )
  expect_match(prompt, "HCC tumor", fixed = TRUE)
  expect_match(prompt, "tumor vs adjacent", fixed = TRUE)
})

test_that(".build_system_prompt: contradicting_markers field required", {
  prompt <- scAgentKit:::.build_system_prompt(
    tissue             = "PBMC",
    condition          = NULL,
    expected_celltypes = NULL,
    strict_vocabulary  = FALSE
  )
  expect_match(prompt, "contradicting_markers", fixed = TRUE)
})

test_that(".build_system_prompt: strict_vocabulary FALSE is a 'prefer' prior", {
  prompt <- scAgentKit:::.build_system_prompt(
    tissue             = "PBMC",
    condition          = NULL,
    expected_celltypes = c("T cell", "B cell", "NK cell"),
    strict_vocabulary  = FALSE
  )
  expect_match(prompt, "prefer these", fixed = TRUE)
  expect_no_match(prompt, "VOCABULARY (strict)")
})

test_that(".build_system_prompt: strict_vocabulary TRUE forces verbatim match", {
  prompt <- scAgentKit:::.build_system_prompt(
    tissue             = "HCC",
    condition          = NULL,
    expected_celltypes = c("Hepatocyte", "T_NK"),
    strict_vocabulary  = TRUE
  )
  expect_match(prompt, "VOCABULARY (strict)", fixed = TRUE)
  expect_match(prompt, "verbatim", fixed = TRUE)
})
