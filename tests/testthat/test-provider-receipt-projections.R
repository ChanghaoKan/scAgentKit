test_that("ordinary cache projections cannot replace committed raw content or finish metadata", {
  for (field in c("raw", "metadata")) {
    f <- turn_fixture(); on.exit(unlink(f$root, recursive = TRUE), add = TRUE)
    request <- list(system_prompt = "Return JSON.", user_prompt = "Synthetic aggregate.", purpose = "annotation")
    calls <- 0L
    fn <- function(...) {
      calls <<- calls + 1L
      list(content = '{"draft":"original"}', response_metadata = list(
        finish_reason = if (field == "metadata") "length" else "stop"))
    }
    .sc_run_call(f$root, request, f$provider, fn)
    path <- file.path(f$root, "provider", "ledger.json"); ledger <- .sc_run_provider_read(path)
    if (field == "raw") {
      ledger$entries[[1L]]$raw <- '{"draft":"changed"}'
      ledger$entries[[1L]]$response_hash <- .sc_run_provider_hash(ledger$entries[[1L]]$raw)
    } else {
      ledger$entries[[1L]]$response_metadata$finish_reason <- "stop"
      ledger$entries[[1L]]$response_metadata_hash <- .sc_run_provider_hash(ledger$entries[[1L]]$response_metadata)
    }
    .sc_run_provider_write(ledger, path)
    expect_error(.sc_run_call(f$root, request, f$provider, fn), "committed receipt")
    expect_equal(calls, 1L)
  }
})

test_that("repeated privacy scrubbing and invoice reconciliation preserve the receipt witness", {
  for (structured in c(FALSE, TRUE)) {
    withr::local_envvar(c(DEEPSEEK_API_KEY = ""))
    f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE), add = TRUE)
    request <- if (structured) f$request else list(system_prompt = "Return JSON.",
      user_prompt = "Synthetic aggregate.", purpose = "annotation")
    request$approved_payload_hash <- .sc_run_request_hash(request, f$provider)
    calls <- 0L
    fn <- function(...) {
      calls <<- calls + 1L
      if (!structured) return('{"draft":"future-protected-fixture-value"}')
      reply <- turn_reply('{"draft":"future-protected-fixture-value"}')
      reply$usage <- reply$raw_usage <- NULL
      reply
    }
    call <- function() .sc_run_call(f$root, request, f$provider, fn, allow_external = TRUE)
    first <- call()
    expect_identical(first$status, "ok"); expect_identical(first$cost_state, "unknown")
    withr::local_envvar(c(DEEPSEEK_API_KEY = "future-protected-fixture-value"))
    for (i in 1:3) {
      scrubbed <- call()
      expect_identical(scrubbed$status, if (structured) "private_payload" else "secret_detected")
      expect_null(scrubbed$content)
    }
    sc_run_provider_reconcile(f$root, first$request_hash, 1, "reviewer", "Synthetic confirmed invoice.")
    final <- call()
    expect_null(final$content); expect_equal(final$cost_usd, 1)
    expect_equal(calls, 1L)
    expect_match(final$withheld_response_hash, "^[a-f0-9]{64}$")
  }
})
