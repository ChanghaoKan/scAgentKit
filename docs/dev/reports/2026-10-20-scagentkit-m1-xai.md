# M1-xAI integration stage report

Status: draft integration on top of 2B; not a released or formally qualified product provider.

## PR / commits

Core [#4](https://github.com/ChanghaoKan/agentomicsCore/pull/4),
`2ccf6a9..bc349db`, supplies native Responses and includes the DeepSeek optional
index compatibility fix from [#5](https://github.com/ChanghaoKan/agentomicsCore/pull/5).
Core full offline suite: 40 cases / 238 assertions passed; R-CMD-check
[39422365746](https://github.com/ChanghaoKan/agentomicsCore/actions/runs/39422365746) passed.
The scAgentKit integration is stacked on [2B #19](https://github.com/ChanghaoKan/scAgentKit/pull/19).
Exact integration head and CI are recorded in its PR description.

## Changes and abstractions

Adds provider-specific native history validation, inspectable privacy projection
and provider-reported cost mapping, using the existing turn envelope, ledger,
checkpoints, consent and worker. The 2B coordinator appends full native output
items and matched function_call_output records. It never replaces encrypted
reasoning or prior items with its convenient assistant projection. No second
scheduler, state database or approval path is added.

The explicit candidate is grok-4.7, native POST /v1/responses, temperature 0,
effort high for development, store=false, local function tools only, complete
history, no response-ID dependency, model fallback or automatic retry. These
are development settings, not a frozen CASSIA comparison preset.

## Validation and acceptance change

Native adapter mock tests cover exact history/ciphertext provenance, complete
visible-content privacy, cost ticks, refusal/incomplete results and uncertain
delivery. A two-cluster loop test executes native tool calls, preserves original
reasoning items, validates the final citations and remains unapproved.

Core's authorized synthetic live protocol test previously passed two calls:
6.107 seconds, input 2928/output 165/total 3093 tokens, service USD ticks
31980000 = $0.003198. It is not a biological experiment or an end-to-end public
dataset test. Subsequent integration smoke receipts, if executed, are recorded
separately rather than relabelling this Core-only result.

Criteria 7/8/9 gain provider protocol integration; no entire new 1.0 criterion
is declared satisfied. Evaluation, public replay, trace UI and the complete
three-gate test remain their planned stages.

## Known limits / deviations

Core is a pinned unreleased development revision. The base 2B PR remains under
review. Full public-data provider qualification and CASSIA live preset validation
are pending, so Grok is not marked officially supported. CASSIA's legacy Chat
endpoint and default effort remain explicit comparison limitations. Native
reasoning is protocol state, never scientific evidence. Cost is posthoc and
unknown values stay unknown. No estimate or monetary cap is introduced.

## Paper milestone

2B is the primary merge path; this parallel M1-xAI change provides the main
matrix's second-provider foundation. After 2B, B1/B2 can run alongside UI/4E.
No formal experiment, annotation-accuracy result or ACT/ReAct benefit is claimed.

## Native engine live smoke follow-up

At integration commit `d1e1ebf`, authorized synthetic one-cluster refinement
completed with grok-4.7: 5 model turns, 4 tool calls, 74.820 seconds. The final
Unknown draft passed schema/risk/citation validation and remained unapproved.
Actual raw usage totals: input 26,476; output 5,117; total 31,593; reasoning
4,534 is a subset in these actual responses and is not added again. Raw USD
ticks sum to 527,420,000 ($0.052742). The committed JSON preserves per-response
raw ticks; rounded JSON summary amounts are not used to reconstruct cost.

No private biological data, held-out data or accuracy experiment was used.
This demonstrates the integrated protocol path, not real-data annotation
quality. The earlier Core-only smoke is separate. The model qualification
status remains pre-release until the public-data/product checks are complete.
