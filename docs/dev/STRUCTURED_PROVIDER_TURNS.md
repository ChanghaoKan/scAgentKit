# Structured provider turns (2A)

This is the transport foundation for annotation ReAct. It does not run a loop,
execute a model-requested tool, generate an approvable ReAct draft, or grant any
scientific approval. It uses released `agentomicsCore` v0.2.0 and preserves the
existing text interface. The structured adapter currently covers DeepSeek Flash
and an offline mock; xAI, Anthropic and OpenAI adapters remain separate M1 work.
Mock success does not constitute a real-provider smoke test.

## Existing mechanisms reused

The internal turn adapter uses the existing project lock, immutable checkpoints,
state history events, transfer consent and single provider ledger. There is no
second approval or accounting service and no generic conversation framework.
`react-session.v1` is a checkpointed scope/binding record; `provider-turn.v1`
selects one cluster and one global ordinal in it.

A session binds scientific checkpoints, cluster membership, provider/model,
prompt version/hash, read-only tool schemas, policy and adapter capability
profile. Dispatch reconstructs bindings from authoritative state; a caller's
self-generated hash is not authorization. The project lock spans validation,
durable dispatch recording, one provider call and response recording. A later
coordinator already holding this lock must supply its current owner token.
Integrity errors block rather than being treated as provider fallback failures.
The existing implementation fingerprint includes the new package-local helpers;
existing projects and approvals are not silently migrated.

## Consent, sequence and privacy

Creation-time `transfer-consent.v2` explicitly describes bounded read-only tools,
ACT scope, turn/time/byte limits and `cost_mode=posthoc`. It states that ReAct
costs are recorded after the call and have no monetary cap. Old v1 consent is
valid only for its original text path. Strict mode requires the exact outgoing
hash in a saved `suggestion_transfer_approved` state event matching session,
cluster, ordinal and inspected revision. A hash on the request alone cannot
provide authorization. Saving evidence or a draft never approves science.

One session has a global ordinal and per-cluster message histories. A new cluster
starts with system/user aggregate evidence. Later turns retain that cluster's
entire previous wire history and exact assistant response, then append only tool
results or user follow-up. Switching clusters cannot reset an existing cluster
or its step limit. Core validates tool-call/result pairing. The global link uses
the response hash or a safe outcome receipt when a received invalid response has
no assistant message. Such a failure may advance to a different cluster; it
cannot create a missing assistant prefix for the failed cluster.

Whole-wire inspection covers every message, tool schema, argument and result,
including nested JSON strings. Private identifiers come from bound checkpoints.
Cell IDs, local paths, credentials, cell-level fields, matrix-shaped data and
oversized payloads are rejected. The response undergoes shape/privacy/size
validation again on cache reads. Unsafe cached projections are withheld while
hashes and accounting remain. Canonical safe messages support audit; HTTP
objects, headers, keys, closures and raw error bodies are not retained.

Each transport timeout is at most the session's per-cluster time allowance.
The later loop owns cumulative cluster timing, tool execution and worker limits.

## Post-call accounting and recovery

Structured turns and single requests use post-call accounting. They do not
estimate input tokens, invoke a tokenizer, reserve funds, require pricing before
sending, enforce a monetary cap, or stop because a known cost exceeds an estimate.
The request API has no monetary budget or reservation policy.

Each response records available normalized and original numeric usage. The
existing `.sc_run_provider_cost()` records a supplied charge, or calculates a
post-call estimate from available usage and configured prices. Such a calculation
is marked as an estimate, not an invoice. Missing/contradictory usage or absent
pricing remains unknown; it is not represented as a zero cost and does not block
a later received-response continuation. A confirmed `not_sent` request and an
offline mock have zero cost. Uncertain **delivery** still prevents automatic
resending, even after process restart. This transport enforces dispatch step,
per-call timeout, byte and output limits independently of money. Tool execution
and cumulative cluster deadlines belong to 2B. Transfer consent and scientific
approval are independent boundaries.

`provider_turn_dispatched` and `provider_turn_completed` reuse existing state
history. The durable dispatch entry is written before calling the provider. A
completed turn is first saved as an immutable checkpoint, then committed by a
state event, then projected into the ledger. Cache reads check that authoritative
receipt, not only self-generated hashes. A crash after state commit restores the
saved response without calling the API; before commit, delivery remains unknown.

Manual reconciliation reuses `sc_run_provider_reconcile()` to record a confirmed
invoice and a new immutable receipt. It never resends a structured turn. The exact
previous ledger-entry hash permits recovery if reconciliation is interrupted
between its state commit and ledger write; unrelated changes are rejected.
Single-request reconciliation also records charges after the call.
