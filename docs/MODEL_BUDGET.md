# Model usage and costs

Current requests record actual token usage and available cost **after each call**.
There is no monetary ceiling, input-token pre-count or reservation. Unknown costs
remain unknown, not zero. The ledger records each request’s `cost_state` and
`cost_usd`; previews report `known_cost_usd` and `unknown_cost_count` separately.
A sum of known costs is not a complete total when some requests have unknown cost.

ReAct step limits and timeouts bound a session. They are not a currency guarantee.
Cancelling takes effect at a safe boundary; the current request may finish and incur
cost. An uncertain delivery is never automatically resent. Cost reconciliation
alone does not prove whether a request was delivered.

Read [ReAct](REACT.md), [run controls](user/TRIAL_CONTROLS.md) and
[the provider/usage contract](dev/PROVIDER_MODEL_AND_USAGE_CONTRACT.md).
Compare methods using recorded usage and costs with the model and pricing version.
Formal cost comparisons have not yet been completed.

## Standalone provider utilities

Generic chat factories and process-wide token utilities belong to agentomicsCore
and are not exported by scAgentKit. For standalone use, call them explicitly,
for example `agentomicsCore::make_chat_fn_openai_compatible()`. These utilities
do not replace the saved project transfer policy or its usage ledger. Use the
reviewed scAgentKit workflow for project model requests and their audit records.
