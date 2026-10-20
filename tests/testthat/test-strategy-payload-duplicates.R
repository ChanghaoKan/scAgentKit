test_that('strategy requests retain unique diagnostics once with explicit duplicate aliases', {
 biology <- list(diagnostic_only = TRUE, thresholds = lapply(seq_len(200), function(i)
   list(cluster = as.character(i), cells = 30, nCount = list(min=100,max=5000,median=1000,mad=200),
        nFeature = list(min=100,max=2000,median=500,mad=100),percent_mt=list(min=0,max=20,median=5,mad=2))))
 mad <- list(presets = lapply(seq_len(30), function(i) list(id=paste0('group-',i),available=TRUE,min=100,max=5000)))
 evidence <- list(biology=biology,qc_mad=mad,quality=list(biology=biology,mad=mad,cells=6000))
 before <- .sc_run_hash(evidence)
 config <- list(context=list(species='human',tissue='blood'),review=list(allow_external=FALSE))
 request <- .sc_run_request('strategy',evidence,config)
 payload <- jsonlite::fromJSON(request$user_prompt,simplifyVector=FALSE)$evidence
 expect_identical(.sc_run_hash(evidence),before)
 expect_identical(request$evidence_hash,before)
 expect_null(payload$quality$biology);expect_null(payload$quality$mad)
 expect_equal(payload$biology,biology);expect_equal(payload$qc_mad,mad)
 expect_equal(payload$quality$cells,6000)
 expect_length(payload$duplicate_evidence_projection$aliases,2L)
 expect_identical(payload$duplicate_evidence_projection$aliases[[1]]$aggregate_hash,.sc_run_hash(biology))
 expect_identical(payload$duplicate_evidence_projection$aliases[[2]]$aggregate_hash,.sc_run_hash(mad))
 expect_match(payload$duplicate_evidence_projection$notice,'No unique evidence is omitted')
 expect_silent(.sc_run_request_hash(request,'mock'))
 altered <- evidence;altered$quality$biology$thresholds[[1]]$nCount$max <- 4500
 second <- jsonlite::fromJSON(.sc_run_request('strategy',altered,config)$user_prompt,simplifyVector=FALSE)$evidence
 expect_equal(second$quality$biology$thresholds[[1]]$nCount$max,4500)
 expect_equal(second$biology$thresholds[[1]]$nCount$max,5000)
 expect_length(second$duplicate_evidence_projection$aliases,1L)
})

test_that('PC aliases preserve the distinction between all-PC and top-50 evidence', {
 v <- seq_len(50) / sum(seq_len(50)); c <- cumsum(v)
 pcs <- list(fraction_per_pc=v,cumulative_fraction=c,ndim=33,
   top50_candidates=list(fraction_per_pc=v,cumulative_fraction=c,reference_pcs=50),
   all_computed_pc_variance=list(fraction_per_pc=v,cumulative_fraction=c))
 evidence <- list(cluster_diagnostics=list(selected_pcs=pcs))
 config <- list(context=list(species='human',tissue='blood'),review=list(allow_external=FALSE))
 out <- jsonlite::fromJSON(.sc_run_request('strategy',evidence,config)$user_prompt,simplifyVector=FALSE)$evidence
 expect_equal(unlist(out$cluster_diagnostics$selected_pcs$fraction_per_pc),v)
 expect_equal(unlist(out$cluster_diagnostics$selected_pcs$cumulative_fraction),c)
 expect_length(out$duplicate_evidence_projection$aliases,4L)
 expect_equal(out$cluster_diagnostics$selected_pcs$top50_candidates$reference_pcs,50)
 expect_null(out$cluster_diagnostics$selected_pcs$all_computed_pc_variance$fraction_per_pc)
 evidence$cluster_diagnostics$selected_pcs$all_computed_pc_variance$fraction_per_pc <- v / 2
 different <- jsonlite::fromJSON(.sc_run_request('strategy',evidence,config)$user_prompt,simplifyVector=FALSE)$evidence
 expect_equal(unlist(different$cluster_diagnostics$selected_pcs$all_computed_pc_variance$fraction_per_pc),v/2)
 expect_length(different$duplicate_evidence_projection$aliases,3L)
})
