# Resource controls checkpoint 1 — 2026-10-21

Base: #26 / 733e3ea97639b4944d4408c868a029ea1b625586. This checkpoint exposes existing bounded controls; it does not complete the resource scalability workstream.

`sc_start(react=list(...))` now uses the same strict policy validator and immutable saved project policy as sc_run. Existing auto/all/off calls retain their behavior. `model_timeout` (integer 1–3600 seconds, default 300) reaches both foreground and background suggestion workers. The background launcher identity binds this operator setting, so a differently configured service is not reused. Startup prints ReAct and outer worker limits and explicitly states that the one-shot 100,000-byte guard is independent. No provider request or scientific approval is caused by configuration.

The startup test creates a public pbmc_small manual project, verifies the saved custom policy and the background launcher timeout/identity, and rejects replacing the saved policy on reopen. Invalid bounds fail before input inspection. Existing default startup/posthoc/runtime checks passed together with the new controls tests. Python verifies timeout rejection and saved review reconstruction; its native opener test skipped without the configured R library. The R startup test did execute the background native launcher. No paid calls or private data are used.

## Boundaries and pending work

This is an explicit operator override, not automatic deadline coordination: default outer timeout remains 300 seconds. The whole request may include baseline plus multiple clusters; operators can select a larger bound but it must not be described as a per-cluster timeout. A durable whole-session deadline/reconciliation design remains pending.

Still pending: unified one-shot/scan/conversation capacity policy and model context accounting; browser effective-limit display; marker/ACT pagination; configurable bundle/display/journal limits and pagination/segmentation; storage usage and archival guidance. ZIP protections, source/hash binding, no silent evidence loss, three reviews and no resend on uncertain delivery remain unchanged. Existing posthoc and explicit legacy one-shot cap semantics remain unchanged; a legacy cap is not a ReAct session spending guarantee.

Acceptance: improves standard 1's public controls and operator observability, but does not close 50k scale acceptance or 1.0 readiness. Paper milestone ReAct flow/evaluation progress is unchanged. No new scientific analysis, approval or budget abstraction: reuse policy validation, saved config, launcher identity and worker timeout. Additional report/UI work is deliberately separated from this compatibility-focused checkpoint.
