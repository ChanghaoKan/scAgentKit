test_that(".adaptive_n_hvg scales with cell count and clamps", {
  expect_equal(scAgentKit:::.adaptive_n_hvg(100), 800L)
  # large subset gets capped near 2000, not blown out
  expect_lte(scAgentKit:::.adaptive_n_hvg(1e6), 2000L)
  # monotone in n
  smaller <- scAgentKit:::.adaptive_n_hvg(500)
  larger  <- scAgentKit:::.adaptive_n_hvg(20000)
  expect_gt(larger, smaller)
})

test_that(".adaptive_n_hvg respects n_genes ceiling", {
  # If gene panel is tiny, n_hvg can't exceed half of it
  expect_lte(scAgentKit:::.adaptive_n_hvg(10000, n_genes = 1000), 500L)
})

test_that(".adaptive_n_pcs scales with cell count and clamps", {
  expect_gte(scAgentKit:::.adaptive_n_pcs(100), 10L)
  expect_lte(scAgentKit:::.adaptive_n_pcs(1e6), 30L)
  expect_gt(scAgentKit:::.adaptive_n_pcs(20000),
            scAgentKit:::.adaptive_n_pcs(500))
})

test_that(".adaptive_n_hvg returns integer", {
  expect_type(scAgentKit:::.adaptive_n_hvg(5000), "integer")
})

test_that(".adaptive_n_pcs returns integer", {
  expect_type(scAgentKit:::.adaptive_n_pcs(5000), "integer")
})
