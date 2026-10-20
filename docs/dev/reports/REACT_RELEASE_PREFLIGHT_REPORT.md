# ReAct release preflight checkpoint — 2026-10-21

Base: PR #25, ad9704dcb15429c1b3a4b5244fb9cd303a62c11a. This is a stacked candidate checkpoint, not a merge or a release approval.

## Changes and evidence

Public 10x PBMC3k (2,700 input cells, SHA256 847d6ebd9a1ec9a768f2be7e40ca42cbfe75ebeb6d76a4c24167041699dc28b5) exposed duplicated aggregate evidence in both strategy requests. Exact duplicates now use explicit canonical aliases with hashes. Unique evidence, local review and the original evidence hash are preserved. Prompt version changes to aggregate-review.v3; implementation hash changes. Tests deliberately retain nonidentical nested evidence.

The manual driver in dev/smoke/react-real.R reuses evaluation-v1's frozen input manifest and existing sc_start/sc_review/replay APIs. It verifies the archive and MEX members, requires explicit scripted accept_drafts policy, and never retries an interrupted project. It introduces no package approval API. Each draft is saved, adopted and separately approved with benchmark-policy:accept_drafts. Real provider mode requires explicit confirmation and an existing process key.

The third PBMC3k mock attempt completed all three approvals: 2,683 retained cells, 8 ReAct clusters, 8 tool calls, 16 model turns, no fallbacks, replay matches, 254.3349 seconds, zero external API calls. Implementation hash at execution: c2ec281ac24b87ae6a82aa5849c949e7449caa432c01c1999589a4448276f37d. Earlier attempts stopped safely at gates 1 and 2 because of duplicate evidence exceeding the request bound; they are not counted as passes. A subsequent ACT provenance wording update changes the manifest/implementation binding; the retained receipt identifies the exact tested code. Final-head automated tests and CI provide the final candidate check.

ACT's four bundled assets match their stored compressed and original hashes; 3,767 human and 2,721 mouse records and 498 download receipt entries were checked. Publisher version, release date and snapshot licence are explicitly unknown, not empty. Direct HTTP download pages were retrieved and contain a copyright footer, but no snapshot-specific licence/version was identified. The publisher article's rights are not assigned to the separate database download: https://link.springer.com/article/10.1186/s13073-023-01249-5 . No biological accuracy is inferred from integrity checks.

## Validation and CI

Local checks: ACT 88 assertions; request projection and scan 34 assertions; integration 390 assertions (before the final PC duplicate extension, which the 34-assertion run and full PBMC3k execution cover). Manual driver guard checks passed without API use. Final candidate targeted ACT/projection/scan/three-gate E2E tests passed after the ACT wording update; the initial devtools invocation was unavailable, and the actual successful run used pkgload plus testthat. No paid calls or holdout data were used in this checkpoint.

PR #22–24: all four workflows passed on their recorded heads. PR #25: installed-runtime-contract, workbench-tests and release-archive passed; R-CMD-check still running at this report checkpoint. This is not a claim that final-head CI has passed for this new PR.

## Request capacity: limitation and next checkpoint

100,000 bytes is an application guard, not a provider API limit. R/run-provider.R applies a hard-coded total UTF-8 system/user limit to one-shot requests. Advanced sc_run(..., react=list(max_payload_bytes=...)) configures the complete ReAct conversation bound, default 100,000 and validation ceiling 1,000,000. sc_start only exposes auto/all/off. R/run-transfer-privacy.R independently bounds free-text study context at 100,000 bytes; that is not the aggregate request limit. Review JSON file limits are also separate.

The second PBMC3k strategy request measures 99,565 bytes after deduplication. Its narrow margin is a functional pass for this fixture, **not scalability acceptance**. No bound was raised and no unique evidence silently removed. More samples/diagnostic clusters add aggregates even when cell-level data never leave the machine.

The next capacity checkpoint should separate (1) configurable byte/resource guards, (2) provider/model context capacity including output allowance, and (3) post-hoc monetary accounting. Token capacity is not a spending cap and does not reinstate monetary reservations. Use versioned global/sample/diagnostic-cluster summaries with declared scope, source hashes, omitted-field/count manifests and local full evidence; preserve safety-critical exceptions and per-sample/cluster outliers. If relevant evidence cannot fit, use explicit read-only on-demand retrieval or manual fallback, never silent truncation or changed scientific groups. Existing authorization and request-hash checks must bind the selected policy. Context capacity for an unverified model must not be guessed.

Validation must cover scaling sample/cluster counts, long and multibyte labels, large unique evidence, byte boundaries, full conversation growth and provider context/output bounds. Check that safety flags remain visible and every projection can be traced to frozen evidence. This design remains pending implementation/review; this PR only fixes exact duplication and documents the gap.

## Acceptance and paper milestone

Standards 1/7/8/12/13 gain a public-input mock integration receipt in addition to the prior pbmc_small CI/browser acceptance. Standard 11 (truth benchmarks), 14 (50k complete pipeline), real-provider PBMC3k smoke and formal E1–E5 experiments remain incomplete. ACT licensing is unknown, explicitly recorded. No claim of 1.0 readiness or annotation accuracy.

Complexity: one versioned duplicate-alias record is added to the existing request projection; existing checkpoints, ledger, event/review/replay mechanisms are reused. The manual driver is outside the package. No new coordinator, approval abstraction, budget reservation or analysis type is introduced.

Deviation: public smoke found a real default request-size failure, so a lossless projection fix precedes release validation. Capacity policy needs a separate stable checkpoint; a successful small dataset does not close it. New PRs remain unmerged pending review.
