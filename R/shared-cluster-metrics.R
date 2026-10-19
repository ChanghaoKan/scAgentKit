# Shared pure kernels. Extracted verbatim from legacy modules; callers own orchestration.

.adjusted_rand_index <- function(a, b) {
  a <- as.character(a); b <- as.character(b)
  tab <- table(a, b)
  n <- sum(tab)
  if (n < 2) return(NA_real_)
  sum_comb <- function(x) sum(choose(x, 2))
  a_sum <- sum_comb(rowSums(tab))
  b_sum <- sum_comb(colSums(tab))
  t_sum <- sum_comb(as.vector(tab))
  expected <- a_sum * b_sum / choose(n, 2)
  max_val  <- (a_sum + b_sum) / 2
  if (max_val == expected) return(1)
  (t_sum - expected) / (max_val - expected)
}

