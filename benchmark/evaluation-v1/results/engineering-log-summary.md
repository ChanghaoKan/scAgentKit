# Engineering validation and preserved failures

All entries below concern this repository's public benchmark or synthetic software controls. These are curated log summaries, not raw terminal transcripts. Absolute local paths, process arguments, environment values, per-cell exports and matrices are not published. No CI run is presented as scientific validation.

| Scope | Observed failure or boundary | Resolution / terminal evidence |
| --- | --- | --- |
| Original audit CI run [38799681397](https://github.com/ChanghaoKan/scAgentKit/actions/runs/38799681397) | Python357 total: missing R digest in expression export;1fail,16skip; Node skipped after fail-fast | Workflow installs jsonlite+digest. Completed recovery assertions require outputs and exercise approved completion/resume. Later CI and native recovery are recorded separately. |
| Completed convenience-export recovery | CSV/summary/bundle damage used to block display | Native R/Python tests modify/delete exports; inspect/resume/result reads remain consistent; Seurat/checkpoint tamper is rejected. |
| Original ifnb and Baron QC-OR attempts | Each exited1 because all5000 MT fractions are unavailable | Original red attempts retained; corrected bookkeeping marks QC-OR ineligible. No zero imputation or2-metric substitute; remaining eligible workflows finish. |
| PBMC original collector | Growing in-memory capture.output caused expensive recursive review rendering; first wrapper also lacked a comparable RSS measurement | Original receipts retained. Stopped only the owned collector, normal lock release;23 saved checkpoints unchanged. Resumed from them, no numerical rerun.131.385s is resume-only, not whole-pipeline runtime. Snapshot is not a biological repeat. |
| PBMC ambient post-fit harness | Native fits completed, then order comparison incorrectly compared native vs canonical ID order | Retained failed harness; verified/reused the saved native fits by literal IDs without refitting. SoupX/decontX remain optional, R-only. |
| Reference dependency | Newer celldex link/install failed | Failed record retained; official celldex1.12.0 reference was frozen before outcomes. No outcome-driven reference replacement. |
| Scientific suggestion boundary | Intermediate archive R check had9440PASS/2SKIP/1ERROR for an oversized request; one source-test attempt raced an edit | Fixed bounded unavailable behavior without enlarging request limit. Final scientific R archive StatusOK9469PASS/2SKIP; stale attempt is not counted as passing. |
| Baron completed result page | Actual browser HTTP409: saved display exceeds16MiB |51cc4c9 shares identical repeated records once. Actual installed archive GET20012,342,881bytes;40/40history; original48files unchanged. No limit/hash/security weakening. |
| Large-display regression | New tests fail before fix:2 failures in15runtime cases | After fix15/15runtime cases pass; included in full376 Python suite. |
| Acceptance harness attempts | Collapsed-editor expectation, synthetic zero-variance HVG refusal, relocated completed-scope refusal, Chrome debugging-cache eviction and wrong panel-name expectation | Attempts retained as failures, not software passes. Final160-cell elbow control and actual Baron completed page pass; production data and integrity checks were not altered to satisfy the harness. |

## Latest local installed-archive acceptance

`51cc4c9` ordinary R CMD build (including vignettes)/install passed. Archive SHA256:
`215b7184c632658af832338de04edca25654e1c34ff9897e6986d15a1de48a5d`.
46 runtime assets match the source/archive/installation; scientific R function hashes are unchanged. Full Python376=361PASS+15external-fixtureSKIP,0FAIL; Node21files pass, including125 workbench DOM assertions. No full R CMD check repeat for this display/documentation-only commit. Existing current-engine native R fixtures execute in the Python suite.

Actual installed Chrome155 reads the existing Baron5000-cell/14-cluster completed run. Expression mean/detection/missing genes/cross-sample records, Fisher/BH/background, saved strategy diagnostics and all40history events open.8screenshots include viewport-bound assertions for actual p_adjusted, mean_log_normalized and cross_sample_consistency values. No POST or external request. [Browser receipt](baron-browser.json), [visible fields](baron-visible-fields.json), [lossless comparison](display-lossless-proof.json) and [archive receipt](archive-receipt.json) are aggregate records; raw screenshots/native files stay outside this public bundle.

The before display encoded27,631,488bytes because reviews appeared twice and each cluster carried the same whole-cohort label table. The fixed HTTP payload is12,342,881bytes under the unchanged16MiB bound. Reconstructing shared paths yields exactly the same complete run,14annotation rows,5000label rows, scientific evidence and history. This fix does not guarantee every future unique payload will fit a finite bound.

## Historical hosted CI and final-head checks

Historical `1c9c4ca` runs all succeeded:

- [R-CMD-check39173569885](https://github.com/ChanghaoKan/scAgentKit/actions/runs/39173569885): StatusOK; hosted logs do not inline the local9469 assertion count.
- [Workbench39173569969](https://github.com/ChanghaoKan/scAgentKit/actions/runs/39173569969):373total352PASS21SKIP (15external+6no-full-R-package), Node21files executed.
- [Installed runtime39173569874](https://github.com/ChanghaoKan/scAgentKit/actions/runs/39173569874):Ubuntu/macOS contracts succeeded.
- [Release archive39173569880](https://github.com/ChanghaoKan/scAgentKit/actions/runs/39173569880):build and fresh empty-library Linux README/offline checks succeeded; publish skipped.

These are historical results for that SHA, not the final report head. See [PR11 Checks](https://github.com/ChanghaoKan/scAgentKit/pull/11/checks) and verify the matching commit SHA for the final push; PR metadata carries final run links after observation. This draft does not merge, publish a release, delete old drafts or change server credentials.

## Remaining scientific and interface boundaries

Compatible independent pancreatic fine-type validation did not pass in V1, human effort/accuracy benefits are unmeasured, and no default scientific benefit gate passed. Sample-outlier gates need at least5actual samples; these public cohorts do not qualify. Tests cover supported synthetic positive/negative gates, not fabricated biological replicates. SoupX/decontX have an R API and documented templates, not a browser correction flow. The actual5000-cell browser receipt covers the completed after-1 result, not an editable/HVG5000 run. Independent V2 reference work is metadata feasibility only, not a new model run.
