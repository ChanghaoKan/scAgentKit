fallback_project <- function() {
 e<-new.env();utils::data('pbmc_small',package='SeuratObject',envir=e)
 root<-tempfile('fallback-')
 sc_analyze(e$pbmc_small,root,context=list(species='human',tissue='blood'),provider='mock',qc_mad=FALSE,
  cycle_diagnostics=FALSE,doublet='off',plan=list(analysis=list(nfeatures=100,npcs=6),pcs=4,umap=FALSE))
 root
}
fallback_action <- function(root,action,...) {
 v<-sc_run_suggest(root)
 sc_run_suggest(root,action,project_id=v$project_id,input_hash=v$input_hash,expected_revision=v$revision,
 suggestion_hash=v$suggestion_hash,reviewer='mock-test',reason='Inspect local failure fallback.',...)
}
test_that('unsupported QC operations save a local draft without approval',{
 root<-fallback_project();on.exit(unlink(root,recursive=TRUE))
 before<-sc_open(root)$plan
 bad<-before;bad$qc<-list(schema='scagentkit.qc.rules.v1',rationale='Keep all.',risks=list('Unassessed.'),remove_if='any',rules=list(list(op='unsupported_filter')))
 fallback_action(root,'approve')
 dispatched<-sc_run_suggest(root)
 answer<-fallback_action(root,'request',chat_fn=function(...) .sc_run_provider_json(bad))
 state<-.sc_run_load(root)
 expect_identical(answer$status,'failed')
 expect_identical(answer$suggestion_hash,dispatched$suggestion_hash)
 expect_false(answer$can_approve)
 expect_false(answer$can_discard)
 expect_identical(answer$fallback$preset_id,'keep_all')
 expect_match(answer$fallback$reason,'unassessed')
 expect_true(answer$fallback$saved)
 expect_length(state$approvals,0)
 expect_null(state$files$analysis)
 expect_true('suggestion_rule_fallback_saved'%in%vapply(state$history,`[[`,character(1),'action'))
 expect_identical(sc_open(root)$plan$analysis,before$analysis)
 expect_false(sc_run_suggest(root)$can_auto_request)
})

test_that('failed dispatch modes save drafts and retain explicit human QC edits',{
  local_mocked_bindings(.sc_run_call=function(...)list(status=status,error='Offline injected failure; no HTTP.',request_hash='offline'),.package='scAgentKit')
 for(status in c('needs_provider','invalid_response','delivery_uncertain')) {
  root<-fallback_project()
  invisible(capture.output(x<-sc_review(sc_open(root))))
  invisible(capture.output(sc_review(x,'revise',plan=list(qc=list(nCount=c(1,NA))),reviewer='human',reason='Retain edited QC.')))
  before<-sc_open(root)$plan
  fallback_action(root,'approve')
  answer<-fallback_action(root,'request')
  expect_true(answer$fallback$saved,info=status)
  expect_identical(answer$fallback$trigger_status,status)
  expect_true('qc'%in%answer$fallback$preserved_human_fields)
  expect_identical(sc_open(root)$plan$qc,before$qc)
  expect_identical(sc_open(root)$plan$analysis,before$analysis)
  expect_length(.sc_run_load(root)$approvals,0)
  expect_false(sc_run_suggest(root)$can_auto_request)
  unlink(root,recursive=TRUE)
 }
})

test_that('a complete measured MAD panel stages AND3 after malformed JSON',{
 genes<-c('MT-CO1',paste0('Gene',2:100));cells<-paste0('cell',1:120)
 counts<-outer(1:100,1:120,function(g,c) as.numeric(((g+3*c)%%80)<(35+c%%24))*(1+(g*c+c^2)%%13))
 counts[,61:120]<-counts[,61:120]*4;counts[1,]<-1+(1:120)%%3
 dimnames(counts)<-list(genes,cells)
 seu<-Seurat::CreateSeuratObject(Matrix::Matrix(counts,sparse=TRUE));seu$sample<-rep(c('A','B'),each=60)
 root<-tempfile('fallback-complete-mad-');on.exit(unlink(root,recursive=TRUE))
 sc_analyze(seu,root,context=list(species='human',tissue='synthetic',columns=list(sample='sample')),
 provider='mock',cycle_diagnostics=FALSE,doublet='off',
 plan=list(analysis=list(nfeatures=80,npcs=6),pcs=4,umap=FALSE))
 state<-.sc_run_load(root);ev<-.sc_run_get(root,state,'strategy_evidence')
 expect_identical(.sc_run_default_mad_choice(ev$qc$mad_record)$preset_id,'conservative_and3')
 fallback_action(root,'approve')
 answer<-fallback_action(root,'request',chat_fn=function(...)'{broken')
 expect_identical(answer$fallback$preset_id,'conservative_and3')
 expect_true(answer$fallback$saved)
 expect_identical(sc_open(root)$plan$qc$rules[[1L]]$preset_id,'conservative_and3')
 expect_length(.sc_run_load(root)$approvals,0)
 expect_null(.sc_run_load(root)$files$analysis)
})

test_that('configured provider without explicit plan still starts with a saved rule draft and no dispatch',{
 e<-new.env();utils::data('pbmc_small',package='SeuratObject',envir=e)
 root<-tempfile('provider-no-plan-');on.exit(unlink(root,recursive=TRUE))
 sc_analyze(e$pbmc_small,root,context=list(species='human',tissue='blood'),provider='mock',
  qc_mad=FALSE,cycle_diagnostics=FALSE,doublet='off')
 state<-.sc_run_load(root)
 expect_false(is.null(state$files$manual_strategy))
 expect_identical(state$status,'awaiting_review')
 expect_length(state$approvals,0)
 expect_false(file.exists(file.path(root,'provider','ledger.json')))
 expect_match(sc_open(root)$plan$qc$rationale,'unassessed')
})



test_that('empty QC suggestions are valid drafts without automatic approval or execution', {
 root <- fallback_project(); on.exit(unlink(root, recursive=TRUE))
 before <- .sc_run_load(root)
 draft <- sc_open(root)$plan
 draft$qc <- list(schema='scagentkit.qc.rules.v1', rationale='Defer additional filtering.',
   risks=list('Quality remains unassessed; prior exclusions stay excluded.'), remove_if='all', rules=list())
 fallback_action(root,'approve')
 answer <- fallback_action(root,'request',chat_fn=function(...) .sc_run_provider_json(draft))
 expect_identical(answer$status,'candidate')
 expect_null(answer$fallback)
 expected <- .sc_run_qc_retained_scope_for_proposal(root, .sc_run_load(root), draft,
   .sc_run_get(root, .sc_run_load(root), 'strategy_evidence'), 'strategy')
 fallback_action(root,'adopt')
 state <- .sc_run_load(root)
 validated <- .sc_run_get(root,state,'strategy_validated')
 expect_identical(validated$proposal$qc$rules,list())
 expect_identical(validated$proposal$qc$remove_if,'all')
 expect_identical(validated$qc_validated$retained_scope,expected)
 expect_length(state$approvals,0L)
 expect_null(state$files$analysis)
 expect_null(state$files$qc_object)
 executed <- function(value) Filter(function(event) identical(event$action,'executed'),value$history)
 expect_identical(executed(state),executed(before))
})
