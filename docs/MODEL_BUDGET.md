# Model usage and costs

Current requests record actual token usage and available cost **after each call**.
There is no monetary ceiling, input-token pre-count or reservation. The deprecated
`budget` argument does not reinstate a cap. Unknown costs remain unknown, not zero.

ReAct step limits and timeouts bound a session. They are not a currency guarantee.
Cancelling takes effect at a safe boundary; the current request may finish and incur
cost. An uncertain delivery is never automatically resent. Cost reconciliation
alone does not prove whether a request was delivered.

Read [ReAct](REACT.md), [run controls](user/TRIAL_CONTROLS.md) and
[the provider/usage contract](dev/PROVIDER_MODEL_AND_USAGE_CONTRACT.md).
Compare methods using recorded usage and costs with the model and pricing version.
Formal cost comparisons have not yet been completed.
