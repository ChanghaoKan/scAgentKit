# Evaluation v2 — implementation contract

**E0: approved documents only. No runner, injector, model experiment or formal result is supplied by this PR.** The scientific and scoring contract is [the v2 protocol](../../docs/dev/EVALUATION_PROTOCOL_V2.md); implementation order and the paper/1.0 split are in [the milestone plan](../../docs/dev/PAPER_MILESTONE_PLAN.md).

This repository-only framework is excluded from the R package. Reuse `benchmark/evaluation-v1/prepare_inputs.R`, existing counts-only preparation and label maps, and version the existing evaluator without changing historical results. Package-level `sc_react_eval` and the framework must share one mapping/scoring definition. Do not create a benchmark-only approval function or implement new scientific behavior outside the package.

## Planned entry and output

E1 implements `run_pipeline(input, context, policy, provider, replicate_id, out_dir)`. It uses public suggestion/adoption and `sc_review()` operations for all three approvals, following `inst/examples/three-gate-analysis.R`. Every decision records `reviewer = "benchmark-policy:<policy>"`; this is explicit scripted benchmark approval, not LLM authority or human review time.

Policies are `accept_drafts`, `rule_defaults`, and a pre-frozen `fixed` decision JSON. Unsupported features fail explicitly. A fallback is recorded as fallback, not successful LLM adoption. New repeats use new projects; resuming a project is not a new repeat.

A local `run_summary.json` projects the existing state/checkpoints/events/ledger. It includes retained-cell count/hash and a local cell table, all scientific decisions and their sources, label/CL/ACT outcomes, ReAct configuration/steps/fallbacks, cost/tokens/time and measurement scope. Cell IDs and matrices remain local; they do not enter provider payloads. Evaluation truth remains separate from analysis inputs and tool context.

## Sequence

- E1 runner, E2 stability/external import and E3 injection mechanisms may develop alongside ReAct v1 after E0.
- E4 consumes v1 citation traces and scoring; completion includes a small **development** pilot, N=3 accept_drafts with mock and one validated real primary provider. Real API calls require the configured authorization and hard budget; no real calls run in CI.
- B1/B2 are package features after ReAct v1, with their own deterministic tests and hash/NEWS changes.
- E5 freezes protocol/code/data/model/tool/price/parameter identities before formal public experiments and the maintainer's unpublished final holdout. ReAct v1, B1/B2, E1–E4 and the primary M1 provider must be complete first.
- Primary models are DeepSeek and one qualified frontier model sharing an exact model with an eligible LLM annotation comparator. The other two providers are descriptive extensions and do not block E5.

`manifests/` documents the qualification and freeze fields. Its examples are **non-executable templates**, not model defaults or certified datasets. Unknown or unresolved fields are explicit. The E0 protocol commit is recorded in its stage report; an E5 freeze receipt later records the exact protocol commit for experiments.

## Test and reporting contract

CI uses pbmc_small, mock providers and small synthetic fixtures to test the three approvals, every generator, known-value metrics, CL denominator/depth boundaries, strict accuracy, ID joins, risk enums and replay with network disabled. Small fixtures establish software behavior, not biological effectiveness.

Historical v1 metrics remain available. The new mode reports mapped-only and strict accuracy together; strict accuracy counts unmapped predictions as errors. CL ancestor distance is at most 3, and cluster truth uses the approved 80% coverage / 80% dominant-label rule. Report mapping coverage, Unknown, missing/failure and denominators. Main discovery uses validated structured risk fields; keyword rules are auxiliary.

All random choices use recorded seeds/RNG versions; injected matrices retain integer counts and have hashes. Every stage report records PR/commit, tests/CI, 1.0 criterion changes, positioning evidence, **paper milestone progress**, limitations and departures. No mock or development result is relabeled as formal validation.
