# Provider models, protocols, and usage reporting

Date: 2026-10-20. The paper's primary model comparison is **DeepSeek + Grok**. Costs are recorded and compared after execution. This document specifies implementation requirements and dated qualification evidence; it does not establish formal scientific validation. The original E0 stage report is a historical record. See the [evaluation protocol](../research/EVALUATION_PROTOCOL_V2.md) for scientific definitions and the [paper milestone plan](../research/PAPER_MILESTONE_PLAN.md) for dependencies.

## Support targets and implementation order

The product aims to support DeepSeek, xAI Grok, Anthropic Claude, and OpenAI, with the provider selected by the user. Each provider has a separate M1 pull request and each model requires qualification. **M1-xAI, using the native Responses API, comes first** because the paper requires it. Formal Anthropic and OpenAI support follows and may be completed after the paper. Other providers supported by then each receive N=3 `accept_drafts` usability runs on public development data. These checks are separate from the paper's accuracy and stability experiments and do not block its primary model comparison.

The initial DeepSeek product configuration is Flash, thinking disabled, temperature 0. The recommended Grok candidate is `grok-4.7`: official custom-tool support has been verified, and synthetic live smoke tests of Core and the scAgentKit engine have passed. Product validation on real public data is still incomplete. Exact model IDs and generation settings must be frozen together with the comparator presets after qualification. Model selection does not depend on prices or a pre-execution estimate of total cost.

Tests with the actual CASSIA 1.4.0 SDK and in-memory HTTP probes confirmed exact forwarding of the Flash, V4 Pro, and Grok4.7 model IDs through its three agents. Flash's requested `none` did not disable thinking; Grok's requested effort was not forwarded. V4 Pro with thinking disabled and temperature 0, and Grok4.7 with its default high effort and temperature .7, are candidates for matching configurations without a patch. They are not yet formal experimental presets. Transport-parameter fixes or changes to affected arms must be documented before freezing. They must not silently change product defaults, and identical model IDs must not be treated as evidence of identical protocols. See [comparator qualification](../../benchmark/evaluation-v2/manifests/model-qualification.md).

## Costs are reported after execution

Individual requests and structured turns have **no monetary cap**. Each ledger entry records returned usage, available costs, time, and status. Requests do not use pre-execution token counting, input-cost estimates, or monetary reservations. Unknown prices or costs do not prevent sending. Known costs and the number of requests with unknown costs are reported separately; unknown is not zero.

Prefer charges reported by the service. When actual usage and an applicable unit price are available, calculate cost after execution and label it as usage-derived. Record the currency, price source and date, and the treatment of cached and reasoning tokens. Otherwise, report unknown. Cost reports distinguish service-reported charges, usage-derived costs, and requests with unknown costs. An incomplete sum is not a complete total. Model comparisons aggregate costs after execution over the same datasets, methods, and replicates; field definitions are in [E5 cost reporting](../../benchmark/evaluation-v2/manifests/E5_COST_REPORTING.md).

A request with uncertain delivery must not be resent automatically. Save returned usage, refusals, and failure status even when no valid draft is produced. A timeout does not establish that no charge occurred. Later billing evidence is appended as a receipt without rewriting the original event. A new turn is not stopped because costs exceed an estimate: no such estimate or monetary threshold governs turns.

## Authorization, read-only tools, and approval

Project-level session consent includes default ReAct use; strict mode requires confirmation of each exact payload. The complete outgoing history, tool definitions, arguments, results, and errors pass the existing privacy and size checks. Every turn records payload and response hashes, delivery status, and an event. The existing state, ledger, and checkpoints remain authoritative; no additional ledger or session-state store is introduced.

Tools are read-only and return aggregate statistics. Default limits are 6 turns per cluster, 60 turns per annotation, 180 seconds per cluster, and 60 seconds per tool. A provider's recommendation for longer request timeouts does not increase these limits. Model, tool, format, or timeout failures fall back to a valid baseline; absence of a baseline is recorded as `baseline_unavailable`. Integrity failures block execution. Saving a draft does not approve it, and a model cannot grant approval.

## M1-xAI protocol requirements

Use `POST https://api.x.ai/v1/responses` with `store=false`, explicit `include=["reasoning.encrypted_content"]`, `tool_choice="auto"`, and `parallel_tool_calls=false`. Save and resend the complete `response.output` in order, appending the paired `function_call_output`. Do not flatten history into plain text or depend on a remote response ID as the only means of recovery. `store=false` is not a promise that the service retains no logs.

Required encrypted reasoning is retained as a private protocol artifact in a versioned provider envelope, bound to the current session and response hash. It is not decrypted, presented as biological evidence, or included in public previews. Unknown item types must not be silently discarded. Plaintext content passes the complete privacy checks. The envelope uses Core turns and the existing audit records without introducing another execution framework.

Grok4.7 reasoning cannot be disabled; default effort is high. Use of other effort settings in experiments requires qualification together with the CASSIA preset. The visible-output length field does not cover all reasoning and function-call tokens and must not be described as a cost limit. The official OpenAPI lists tool `strict` as accepted for compatibility but unsupported; R argument validation performs the deterministic checks. Sources, model limitations, and current prices are recorded in the [xAI qualification record](../../benchmark/evaluation-v2/manifests/xai-qualification.md).

Server-side web/X/code tools, automatic context compaction, background agents, and unreviewed model switching are not enabled. CASSIA's Chat API path can serve as a method comparator using the same model, provided the report discloses that it does not retain Responses encrypted reasoning. Single-factor conclusions about ReAct come from paired on/off ablations within scAgentKit.

## Model registry and qualification

The registry records the provider, exact API ID, returned model, endpoint, date and alias semantics, supported parameters, tool capabilities, source/offline/live verification status, and supporting sources. Official documentation, offline mocks, live development smoke tests, and complete presets have separate statuses. A capability is described as validated only after its corresponding qualification succeeds. Users may configure models outside the registry with an explicit `unverified` status. Unimplemented providers return unsupported. Unknown prices do not prevent sending, but unknown tool protocols must not be presented as supported.

Qualification uses the existing test mechanisms: complete tool history and opaque-item ordering; parameter, size, and privacy checks; no resend after uncertain delivery; refusals and missing usage; mapping of actual usage fields; and offline replay. Live smoke tests run outside CI and retain their results. Work on this contract did not call a provider API or produce real cost or accuracy measurements.

The current M1-xAI native Responses adapter covers structured ReAct turns. One-shot drafts use the existing text-provider path. This stage does not migrate every call at the three approval stages to Responses and does not establish complete product support. The session capability record includes the synthetic smoke-test date and `formal_support=false`. Formal qualification requires complete product and public-data validation.
