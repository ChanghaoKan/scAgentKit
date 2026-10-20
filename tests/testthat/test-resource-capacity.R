test_that('one-shot capacity is explicit, bounded and hash-bound', {
  request <- list(system_prompt='JSON',user_prompt=paste(rep('a',150000),collapse=''),purpose='strategy')
  expect_no_error(.sc_run_provider_request(request))
  request$max_payload_bytes <- 100000L
  expect_error(.sc_run_provider_request(request),class='sc_run_payload_too_large')
  request$max_payload_bytes <- 200000L
  expect_equal(.sc_run_provider_request(request)$max_payload_bytes,200000)
  before <- .sc_run_request_hash(request,'mock')
  request$max_payload_bytes <- 210000L
  expect_false(identical(before,.sc_run_request_hash(request,'mock')))
  request$max_payload_bytes <- 1000001L
  expect_error(.sc_run_provider_request(request),'max_payload_bytes')
})

test_that('marker and ACT pages retain full order without duplicate rows', {
  f <- react_tool_fixture(); on.exit(unlink(f$root,recursive=TRUE))
  first <- react_local(f,'cluster_markers',list(cluster_id='0',n=50))$result
  second <- react_local(f,'cluster_markers',list(cluster_id='0',n=50,offset=first$next_offset))$result
  genes <- vapply(c(first$markers,second$markers),`[[`,character(1),'gene')
  expect_length(genes,first$rows_available)
  expect_false(anyDuplicated(genes)>0)
  expect_null(second$next_offset)
  expect_true(second$truncated)
  a <- react_local(f,'act_lookup',list(genes=c('G01','G02'),n=1))$result
  b <- react_local(f,'act_lookup',list(genes=c('G01','G02'),n=1,offset=a$next_offset))$result
  expect_equal(a$rows_available,2)
  expect_null(b$next_offset)
  expect_false(identical(a$entries,b$entries))
  expect_error(.sc_run_react_arguments(.sc_run_react_tools()$act_lookup,list(genes='G01',offset=-1)),class='sc_run_react_error')
})

 test_that('unlimited is explicit and does not masquerade as a model token budget', {
  request <- list(system_prompt='JSON', user_prompt=paste(rep('a',1100000),collapse=''), purpose='strategy',max_payload_bytes='unlimited')
  expect_identical(.sc_run_provider_request(request)$max_payload_bytes,'unlimited')
  expect_identical(.sc_run_turn_policy()$max_payload_bytes,'unlimited')
  expect_true(is.infinite(.sc_run_capacity_bytes('unlimited')))
  expect_error(.sc_run_capacity_bytes(Inf),'max_payload_bytes')
})

test_that('three-gate prompt makes required resolution review explicit', {
 config <- list(context=list(species='human',tissue='blood'))
 required <- .sc_run_request('strategy',list(require_three_gates=TRUE),config)
 expect_match(required$system_prompt,'clustering.diagnostic_resolutions is REQUIRED',fixed=TRUE)
 expect_match(required$system_prompt,'Never omit it or set it to null/empty',fixed=TRUE)
 ordinary <- .sc_run_request('strategy',list(require_three_gates=FALSE),config)
 expect_false(grepl('PROJECT REQUIREMENT',ordinary$system_prompt,fixed=TRUE))
})
