guided_action <- function(root,action,...) {
  view<-sc_run_suggest(root)
  sc_run_suggest(root,action,project_id=view$project_id,input_hash=view$input_hash,
    expected_revision=view$revision,suggestion_hash=view$suggestion_hash,...)
}
guided_fixture <- function(strict=FALSE) {
  env<-new.env();utils::data("pbmc_small",package="SeuratObject",envir=env)
  seu<-env$pbmc_small;seu$seurat_clusters<-as.character(SeuratObject::Idents(seu))
  root<-tempfile();on.exit(if(!dir.exists(root))unlink(root,recursive=TRUE))
  confirmation<-if(strict)NULL else list(mode="project",confirmed=TRUE,reviewer="offline-human",reason="Public aggregate fixture scope.",
    categories=c("study_context","aggregate_qc","aggregate_markers","aggregate_design","aggregate_expression"))
  suppressWarnings(sc_run(seu,root,context=list(species="human",tissue="blood"),
    start_stage="processed",processed_reason="Offline public annotation boundary.",
    input_policy=list(preserve_metadata=TRUE),provider=list(name="offline_remote",external=TRUE,model="offline-guidance"),
    review=list(allow_external=TRUE,transfer_consent=confirmation)))
  state<-.sc_run_load(root);evidence<-.sc_run_get(root,state,"annotation_evidence")
  eligible<-Filter(function(row)length(Filter(function(marker)marker$avgLog2FC>0&&marker$pct1>marker$pct2,row$markers))>0L,evidence$summary$clusters)
  stopifnot(length(eligible)>0L)
  cluster<-eligible[[1L]];marker<-Filter(function(marker)marker$avgLog2FC>0&&marker$pct1>marker$pct2,cluster$markers)[[1L]]$gene
  reference<-data.frame(cell_type="Reference B",marker=marker,species="human",tissue="blood")
  sc_run_set_reference(root,reference,state$project_id,state$input_hash,state$revision,"offline-human","Explicit local scope.")
  evidence<-.sc_run_get(root,.sc_run_load(root),"annotation_evidence")
  proposal<-list(schema="scagentkit.annotation.v1",annotations=lapply(evidence$summary$clusters,function(row)
    list(clusterId=row$clusterId,label=if(row$clusterId==cluster$clusterId)"Independent A" else "Unknown",confidence="low",
      rationale="Offline independent marker-only software test.",markers=if(row$clusterId==cluster$clusterId)list(marker)else list())))
  list(root=root,proposal=proposal)
}

test_that("independent annotation precedes one bounded guided request in project and strict modes", {
  for(strict in c(FALSE,TRUE)) {
    fixture<-guided_fixture(strict);root<-fixture$root;on.exit(unlink(root,recursive=TRUE),add=TRUE)
    if(strict)guided_action(root,"approve",reviewer="offline-human",reason="Exact independent payload only.")
    calls<-0L
    first<-guided_action(root,"request",chat_fn=function(system_prompt,user_prompt) {
      calls<<-calls+1L;payload<-jsonlite::fromJSON(user_prompt,simplifyVector=FALSE)
      expect_identical(payload$evidence$reference_mode,"independent")
      expect_false(grepl("Reference B",user_prompt,fixed=TRUE))
      list(content=.sc_run_provider_json(fixture$proposal),cost_usd=.01)
    })
    expect_true(first$can_review_conflicts);expect_identical(calls,1L)
    initial<-.sc_run_load(root)$suggestion
    next_view<-guided_action(root,"review_conflicts",reviewer="offline-human",reason="Prepare one optional descriptive difference review.")
    expect_identical(calls,1L);expect_identical(next_view$reference_mode,"guided")
    expect_false(identical(next_view$preview$request_hash,first$preview$request_hash))
    expect_identical(.sc_run_get(root,.sc_run_load(root),"annotation_independent_suggestion"),initial)
    if(strict) {
      expect_false(next_view$can_request);expect_true(next_view$can_approve)
      expect_error(guided_action(root,"request",chat_fn=function(...)stop("must not send")),"Approve the exact")
      guided_action(root,"approve",reviewer="offline-human",reason="Separately approve the exact guided payload.")
    }
    second<-guided_action(root,"request",chat_fn=function(system_prompt,user_prompt) {
      calls<<-calls+1L;payload<-jsonlite::fromJSON(user_prompt,simplifyVector=FALSE)
      expect_identical(payload$evidence$reference_mode,"guided")
      expect_match(user_prompt,"Reference B")
      expect_identical(payload$evidence$independent_candidate$annotations[[1L]]$clusterId,fixture$proposal$annotations[[1L]]$clusterId)
      value<-fixture$proposal;value$annotations<-lapply(value$annotations,function(row){row$label<-"Unknown";row$markers<-list();row})
      list(content=.sc_run_provider_json(value),cost_usd=.01)
    })
    expect_identical(second$status,"candidate");expect_identical(calls,2L)
    expect_false(second$can_request);expect_false(second$can_review_conflicts)
    expect_error(guided_action(root,"request",chat_fn=function(...)stop("must not retry")),"already attempted")
    expect_error(guided_action(root,"review_conflicts",reviewer="offline-human",reason="Must not stage twice."),"Only one")
    guided_action(root,"adopt",reviewer="offline-human",reason="Adopt complete Unknown recheck for separate human scientific review.")
    view<-sc_run_inspect(root)
    expect_identical(view$annotation_review$details$source$reference_prompt$mode,"guided")
    expect_length(.sc_run_load(root)$approvals,0L)
    expect_equal(sc_run_suggest(root)$preview$known_cost_usd,.02)
  }
})

test_that("literal cell IDs in an aggregate are blocked before transfer", {
  evidence<-list(private=list(input_cells=data.frame(cell_id=c("sample::ACGT-1","private-cell-2"))))
  expect_error(.sc_run_transfer_check_literal_ids(list(user_prompt='{"label":"private-cell-2"}'),evidence),"literal input cell ID")
  expect_error(.sc_run_transfer_check_literal_ids(list(user_prompt='{"marker":"ACGT-1"}'),evidence),"literal input cell ID")
  expect_silent(.sc_run_transfer_check_literal_ids(list(user_prompt='{"label":"Unknown"}'),evidence))
})

test_that("guided invalid responses and uncertain delivery never unlock retries", {
  for(mode in c("invalid","uncertain")) {
    fixture<-guided_fixture();root<-fixture$root
    on.exit(unlink(root,recursive=TRUE),add=TRUE)
    guided_action(root,"request",chat_fn=function(...)list(content=.sc_run_provider_json(fixture$proposal),cost_usd=.01))
    guided_action(root,"review_conflicts",reviewer="offline-human",reason="One bounded optional follow-up.")
    calls<-0L
    result<-guided_action(root,"request",chat_fn=function(...) {
      calls<<-calls+1L
      if(mode=="uncertain")stop("Simulated uncertain delivery; no real network.")
      list(content="{invalid",cost_usd=.002)
    })
    expect_identical(result$status,"failed");expect_false(result$can_request);expect_false(result$can_auto_request)
    expect_identical(calls,1L)
    expect_error(guided_action(root,"request",chat_fn=function(...)stop("must not retry")),"already attempted")
    expect_true(.sc_run_load(root)$annotation_guided_attempted)
    expect_length(.sc_run_load(root)$approvals,0L)
    if(mode=="invalid")expect_identical(result$response$status,"invalid_response")
    if(mode=="uncertain")expect_identical(result$response$status,"delivery_uncertain")
  }
})

test_that("modern entry cannot replace the first independent annotation with a guided draft", {
  env<-new.env();utils::data("pbmc_small",package="SeuratObject",envir=env)
  expect_error(sc_analyze(env$pbmc_small,tempfile(),list(species="human"),reference_review=list(ai_mode="guided")),"first modern annotation draft must be independent")
})
