# A failed provider is not an approval. Save a separately identified local draft
# using the same eligibility policy as creation, and retain explicit human edits.
.sc_run_suggestion_fallback <- function(root, state, context, answer) {
  kind <- context$kind
  name <- paste0('manual_', kind)
  if (is.null(state$files[[name]])) return(state)
  proposal <- .sc_run_get(root, state, name)
  qc <- if (kind == 'strategy') context$evidence$qc else context$evidence
  choice <- .sc_run_default_mad_choice(qc$mad_record)
  if (kind %in% c('strategy', 'qc') && is.null(context$cluster_scan) &&
      !identical(state$config$start_stage, 'processed')) {
    local_qc <- list(schema='scagentkit.qc.rules.v1', rationale=choice$reason,
      risks=list('QC remains unassessed; local rule draft requires scientific approval.'),
      remove_if='any', rules=if (!is.null(qc$mad_record))
        list(list(op='mad_preset', preset_id=choice$preset_id, panel_hash=qc$mad_record$panel_hash)) else list())
    if (kind == 'strategy') proposal$qc <- local_qc else proposal <- local_qc
  }
  # Annotation already has a saved local worksheet; do not rewrite its rows on a failed optional request.
  merged <- .sc_run_merge_model_draft(root, state, kind, proposal)
  # Direct QC projects have no per-field merge: retain their saved analyst draft.
  if (kind == 'qc') merged$proposal <- .sc_run_get(root, state, name)
  retained_scope <- if (kind %in% c('qc', 'strategy'))
    .sc_run_qc_retained_scope_for_proposal(root, state, merged$proposal, context$evidence, kind) else NULL
  proposal <- .sc_run_suggestion_validator(kind, context$evidence, state, context$cluster_scan,
    retained_scope=retained_scope)(merged$proposal)
  receipt <- list(schema='scagentkit.suggestion-rule-fallback.v1', saved=TRUE,
    kind=kind, trigger_status=answer$status, request_hash=context$request_hash,
    preset_id=choice$preset_id, reason=paste('Provider suggestion failed.',choice$reason,
      'Saved human fields are preserved; review the effective draft. No approval or retry.'),
    preserved_human_fields=merged$preserved, effective_qc=if(kind=='strategy')proposal$qc else if(kind=='qc')proposal else NULL,
    scientific_approval=FALSE, source='local_rule_fallback')
  state$suggestion$fallback <- receipt
  state <- .sc_run_event(state,'suggestion_rule_fallback_saved',receipt)
  if (identical(proposal, .sc_run_get(root,state,name))) return(state)
  .sc_run_propose_locked(root,state,proposal,'local-rule-fallback',receipt$reason,drive=FALSE,
    review_binding=list(source='local_rule_fallback',request_hash=context$request_hash), retained_scope=retained_scope)
  .sc_run_load(root)
}
