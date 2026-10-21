# E5 post-run usage and cost reporting

Recorded on 2026-10-20. This document defines result fields and aggregation rules,
not a quotation before execution. The primary comparison includes DeepSeek and
Grok. It does not require an advance total-cost estimate or introduce token
estimation, remaining allowances, monetary caps or reservations. No actual run
costs are available in this record. See the
[provider model and usage contract](../../../docs/dev/PROVIDER_MODEL_AND_USAGE_CONTRACT.md).

## Unit of record

Each actual request is identified by
`run_id + dataset_id + input_hash + method + config_hash + replicate_id + stage + request_id`.
Reuse the existing ledger and events; result tables are projections of those
records, not a separate ledger. Record at least the following:

| Field group | Contents |
| --- | --- |
| Request identity | Provider; requested and returned model; endpoint; time; stage or cluster; payload and response hashes; delivery, completion and failure status. |
| Usage | Raw usage; input, cached, output, reasoning and total counts where mappable; the provider's definitions of which fields include others. Missing values are null. |
| Cost | Service-reported amount and original unit. If absent, a post-run calculation may use actual usage, with price source, date, currency and applicable tier. Indeterminate amounts are unknown. |
| Timing and outcome | Elapsed time, timeouts, refusals, fallback reason, tool-call and turn counts. Distinguish unsent requests from failures after transmission. |
| Evidence | Source record and corresponding ledger or event. Link later billing receipts to the original request and retain the original record. |

A service-reported amount and a usage-based calculation are alternative cost
sources for the same request; do not add them. Verify whether the provider
includes reasoning tokens in output before calculating charges. For xAI, prefer
`usage.cost_in_usd_ticks / 10^10` and retain the raw ticks. Missing cost does not
mean a free request. Some policy refusals before generation may incur $0.05;
this does not justify assigning either $0.05 or zero to every refusal. See the
[xAI qualification record](xai-qualification.md).

## Aggregation and model comparisons

Aggregate separately by dataset, split, method, frozen configuration and actual
model. The main experiment has N=5 runs per configuration; development checks
and availability checks for other providers use N=3 and are reported separately.
Replicate counts are not success counts: report planned, attempted, completed
and failed runs. Values for unrun experiments remain null or not_run, not zero.

- Separate the full scAgentKit workflow into the first review, second review,
  annotation baseline at the third review, and additional ReAct work. The
  annotation-only table also separates baseline and additional ReAct work.
  Report local tool time separately from API charges.
- Include CASSIA annotation, validator, formatter and any additional agents
  explicitly enabled. Include actual retries and preflight requests; one call's
  price does not represent the method's total cost.
- For each run, report the sum of known amounts, coverage by cost source,
  requests with unknown cost, tokens and elapsed time. Across replicates,
  report means, ranges and the contributing denominator. If costs are missing,
  call the sum the *known portion of cost*; do not present it as a complete
  total or use it to conclude that one model is cheaper.
- Compare ReAct on/off and other ablations using frozen paired configurations.
  Count shared controls once and list their run IDs. Attribute the cost of
  preprocessing shared across comparators to avoid omissions or double counting.
- Report public development data, public benchmarks, the maintainer-held
  dataset and product checks for other providers separately. Do not use the
  held-out dataset for development cost estimates; the maintainer supplies
  actual records after the authorized formal run.

Cost is a post-run comparison measure, not a quotation required to select a
model or start a stage. Step and time limits, privacy checks, scientific
approvals and the prohibition on resending requests with uncertain delivery
still apply. Actual experiments require the protocol's data, code and preset
freezes and execution authorization. This document does not authorize API
calls. Neither individual requests nor structured turns have a monetary cap.
