# Evaluation v2 — implementation contract

**E0 is approved; the 4E scoring adapter is available in development. No runner, injector or formal model result is supplied yet.** The scientific and scoring contract is [the v2 protocol](../../docs/dev/EVALUATION_PROTOCOL_V2.md); implementation order and the paper/1.0 split are in [the milestone plan](../../docs/dev/PAPER_MILESTONE_PLAN.md).

`evaluate_react.R` is a thin adapter to the package's versioned `sc_react_eval`.
Use prepared inputs and named sections from `evaluation-v1/label-map.json`;
historical `evaluation-v1/evaluate.py` and its outputs are unchanged. Coarse
historical names that do not map exactly to CL remain unmapped until a
dataset-specific mapping is frozen. Do not silently invent subtype mappings.
See the [user guide](../../docs/REACT_EVALUATION.md) for denominators, dual truth,
external predictions and API-free replay.

This repository-only framework is excluded from the R package. Reuse `benchmark/evaluation-v1/prepare_inputs.R`, existing counts-only preparation and label maps, and version the existing evaluator without changing historical results. Package-level `sc_react_eval` and the framework must share one mapping/scoring definition. Do not create a benchmark-only approval function or implement new scientific behavior outside the package.

## Planned entry and output

E1 implements `run_pipeline(input, context, policy, provider, replicate_id, out_dir)`. It uses public suggestion/adoption and `sc_review()` operations for all three approvals, following `inst/examples/three-gate-analysis.R`. Every decision records `reviewer = "benchmark-policy:<policy>"`; this is explicit scripted benchmark approval, not LLM authority or human review time.

Policies are `accept_drafts`, `rule_defaults`, and a pre-frozen `fixed` decision JSON. Unsupported features fail explicitly. A fallback is recorded as fallback, not successful LLM adoption. New repeats use new projects; resuming a project is not a new repeat.

A local `run_summary.json` projects the existing state/checkpoints/events/ledger. It includes retained-cell count/hash and a local cell table, all scientific decisions and their sources, label/CL/ACT outcomes, ReAct configuration/steps/fallbacks, cost/tokens/time and measurement scope. Cell IDs and matrices remain local; they do not enter provider payloads. Evaluation truth remains separate from analysis inputs and tool context.

## Sequence

- E1 runner, E2 stability/external import and E3 injection mechanisms may develop alongside ReAct v1 after E0. E3 primary discovery scoring depends on B1/B2 production risk fields for gate 1 and the 2B outer draft risk fields for gate 3; unsupported parts remain explicit until integrated, not replaced by keyword scoring.
- E4 consumes v1 citation traces and scoring; completion includes a small **development** pilot, N=3 accept_drafts with mock and one validated real primary provider. Real API calls require the existing authorization; usage and costs are reported afterwards. No real calls run in CI.
- After 2B merges, B1/B2 develop in parallel with stage 3 UI, 4E evaluation/replay and documentation; they do not wait for all ReAct v1 stages. B2 integration needs the shared B1 diagnostic checkpoint. Their package tests and hash/NEWS changes remain required.
- E5 freezes protocol/code/data/model/tool/parameter identities and the available sources for post-run cost reporting before formal public experiments and the maintainer's unpublished final holdout. ReAct v1, B1/B2, E1–E4 and the primary M1 provider must be complete first.
- Primary providers are DeepSeek and Grok. M1-xAI goes first using Responses, with grok-4.7 as the documented candidate. Exact models and comparator presets require development qualification; no cost quote gates model selection. CASSIA exact-model forwarding passed offline SDK/HTTP probes, while thinking/effort differences and live qualification remain explicit in the model record.
- Product support targets DeepSeek, OpenAI, Anthropic and xAI, selected by the user. Provider M1 PRs qualify exact models individually; Anthropic/OpenAI product support may follow the paper. Every other supported provider receives a public development N=3 accept_drafts usability check, separate from main scientific conclusions and non-blocking for E5.
- The [provider contract](../../docs/dev/PROVIDER_MODEL_AND_USAGE_CONTRACT.md) defines authorization, protocol history, verified/unverified models and post-run usage. [E5 cost reporting](manifests/E5_COST_REPORTING.md) separates datasets, methods, repeats, ablations and CASSIA calls. Single requests and structured turns have no monetary cap or counting/reservation prerequisites. Missing costs are unknown, not zero.

`manifests/` documents the qualification and freeze fields. Its examples are **non-executable templates**, not model defaults or certified datasets. Unknown or unresolved fields are explicit. The E0 protocol commit is recorded in its stage report; an E5 freeze receipt later records the exact protocol commit for experiments.

## Test and reporting contract

CI uses pbmc_small, mock providers and small synthetic fixtures to test the three approvals, every generator, known-value metrics, CL denominator/depth boundaries, strict accuracy, ID joins, risk enums and replay with network disabled. Small fixtures establish software behavior, not biological effectiveness.

Historical v1 metrics remain available. The new mode reports mapped-only and strict accuracy together; strict accuracy counts unmapped predictions as errors. CL ancestor distance is at most 3, and cluster truth uses the approved 80% coverage / 80% dominant-label rule. Report mapping coverage, Unknown, missing/failure and denominators. Main discovery uses validated structured risk fields; keyword rules are auxiliary.

All random choices use recorded seeds/RNG versions; injected matrices retain integer counts and have hashes. Every stage report records PR/commit, tests/CI, 1.0 criterion changes, positioning evidence, **paper milestone progress**, limitations and departures. No mock or development result is relabeled as formal validation.
