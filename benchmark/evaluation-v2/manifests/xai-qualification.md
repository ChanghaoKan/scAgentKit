# xAI/Grok qualification for the primary comparison

Assessment date: 2026-10-20. The initial E0 assessment used xAI's official
documentation, OpenAPI definition and SDK source. It read no API keys and made
no inference, tokenization or account API calls. At that point, official
capabilities had been checked, but scAgentKit integration, live smoke tests and
formal experiment qualification were incomplete. Later implementation and smoke
test results are recorded at the end of this document.

The maintainer selected DeepSeek and Grok for the primary comparison, with
M1-xAI first and formal Anthropic/OpenAI product support to follow. Costs are
recorded and compared after execution.

## Candidate model and parameters

| Item | Official specification | Qualification limit |
| --- | --- | --- |
| API model | `grok-4.7` | No date-suffixed snapshot was found. Do not assume the ID is immutable; record requested and returned models and the request date. |
| Context | 500,000 tokens | A capacity specification, not a cost ceiling. |
| Knowledge cutoff | May 2026 | The stated cutoff is neither a training-data inventory nor proof that particular data were unseen. |
| Modalities | Text/image input, text output | This project enables text only. |
| Tools | Custom function calling and structured outputs | Connect only the four local read-only tools; do not enable server-side search, code execution or MCP. |
| Reasoning | low, medium, high and xhigh; default high | Thinking cannot be disabled for 4.7. Low effort can still produce reasoning tokens. |
| Sampling | Temperature supports 0–2; official recommendations are .7 and top_p .95 | Freeze provider-specific settings after development qualification rather than applying DeepSeek's temperature 0 setting. |

Model and date sources:
[developer guide](https://docs.x.ai/developers/grok-4-7) and
[model page](https://docs.x.ai/developers/models/grok-4.7).
Generation settings:
[reasoning](https://docs.x.ai/developers/model-capabilities/text/reasoning) and
[best practices](https://docs.x.ai/developers/model-capabilities/text/best-practices).
The official API did not list `grok-4.7-fast`; a fast model name in another
product does not establish an available API ID.

Unmodified CASSIA does not send Grok effort and relies on the documented default,
high. Temperature .7 was confirmed in its captured offline HTTP requests. High
is therefore a candidate for matching without a patch. Low or medium may be
used to assess development latency, but a formal preset must also verify the
comparator's setting before it is considered frozen. See the
[model-matched comparator record](model-qualification.md).

The vendor recommends long request timeouts and streaming, but the project's
existing **180-second per-cluster** limit applies. Development runs must report
observed timeout rates. Do not automatically extend that limit or let general
retry advice override the rule against resending requests with uncertain
delivery.

## Responses protocol and complete history

Use `POST https://api.x.ai/v1/responses`. Chat Completions is marked legacy and
was not selected as the default protocol for the new M1-xAI implementation.
The native SDK/gRPC route can also handle encrypted history, but it does not
justify an additional dependency here; R/Core can use native REST.
[Interface comparison](https://docs.x.ai/developers/model-capabilities/text/comparison);
[legacy Chat](https://docs.x.ai/developers/model-capabilities/legacy/chat-completions).

Send `store=false` and `include=["reasoning.encrypted_content"]` explicitly.
Although 4.7 currently returns encrypted reasoning without the include setting,
recording it makes the intended protocol explicit. `store=false` avoids relying
on a service-stored response ID for continuation; it does not promise zero
retention across all service logs.
[Responses reference](https://docs.x.ai/developers/rest-api-reference/inference/responses.md);
[encrypted reasoning](https://docs.x.ai/developers/model-capabilities/text/reasoning).

Save the complete `response.output` from each turn. On the next turn, retain
all item content and ordering, then append the matching `function_call_output`.
Do not reduce reasoning, message and function-call items to assistant text.
Each call_id must have one result. Set `parallel_tool_calls=false` and still
validate unexpected multiple calls. Do not silently discard unknown items.
A fixed session `prompt_cache_key` may help routing but does not establish a
cache hit.

Opaque reasoning must be the original protocol record from the same session,
with source, hash, size and preceding-response binding retained. Do not decrypt
it, publish it as biological evidence or accept arbitrary fabricated ciphertext.
Plaintext still undergoes complete outbound privacy and size checks. The E0
design proposed extending Core's versioned provider envelope while retaining
the existing turn and text interfaces, reusing the ledger, state and checkpoints
without a new execution framework. Remote history, automatic compaction and
background agents must not replace the local audit record.

## Tool format and deterministic checks

Responses defines tools as `{type:"function", name, description, parameters}`,
model calls as `{type:"function_call", call_id, name, arguments,...}`, and local
results as `{type:"function_call_output", call_id, output}`. Use
`tool_choice="auto"` in the first implementation. The official forced-tool
example and OpenAPI definition differ in the nesting of name, so the unqualified
forced-tool branch is excluded.
[Function calling](https://docs.x.ai/developers/tools/function-calling).

OpenAPI marks `FunctionDefinition.strict` as an unsupported compatibility field.
Its object-schema grammar description also does not replace local strict
validation. R validators enforce arguments, read-only access, aggregate-data
privacy and result sizes for all four tools.
[Official OpenAPI](https://docs.x.ai/openapi.json).

## Usage and cost after execution

Responses `max_output_tokens` and legacy Chat `max_completion_tokens` limit
visible output only; reasoning and function-call tokens are excluded. These
parameters are not total-token or cost ceilings. The inability to disable
thinking is not an integration blocker because structured turns have no
monetary cap. Output-length, step and time controls still apply.
[Responses parameters](https://docs.x.ai/developers/rest-api-reference/inference/responses.md);
[Chat parameters](https://docs.x.ai/developers/rest-api-reference/inference/chat-completions.md).

At the assessment date, standard global pricing in USD per million tokens was:

| Prompt size | Uncached input | Cached input | Output |
| --- | ---: | ---: | ---: |
| <200,000 | 2.00 | 0.50 | 6.00 |
| ≥200,000 | 4.00 | 1.00 | 12.00 |

The applicable tier covers the whole request when the threshold is crossed.
The US regional endpoint has a 10% premium; do not switch regions implicitly.
Reasoning and generated tool-call text are billed, whereas local tool execution
has no server-side tool-call fee. Some policy refusals before generation may
cost $0.05/request, and refusals after generation may still incur generation
charges. Neither a fixed fee nor zero applies to every refusal.
[Pricing](https://docs.x.ai/developers/pricing);
[regional endpoints](https://docs.x.ai/developers/advanced-api-usage/regions).
These prices help interpret post-run records; they are not prerequisites for
sending requests or selecting a model.

Prefer service-reported `usage.cost_in_usd_ticks / 10^10`. Retain the original
integer unit without losing precision or confusing it with the separate
`cost_in_nano_usd` field. The official definition includes applicable discounts
and tool charges. If absent, calculate cost after the run from actual usage and
verifiable unit prices; if those are insufficient, record unknown.
[Cost tracking](https://docs.x.ai/developers/cost-tracking).

Retain raw usage before mapping provider fields. Do not assume that output
always includes reasoning or mechanically apply input+output=total. The official
Responses example gives input=32, output=9, reasoning=110 and total=151,
illustrating why field relationships must be checked. `context_details`
describes context, not billing. Actual 4.7 field relationships still required
live-smoke verification at E0.
[Responses return structure](https://docs.x.ai/developers/rest-api-reference/inference/responses.md).

Do not add a counting API, local tokenizer, input estimate, multiplier or
reservation as a prerequisite. Unknown prices or usage do not prevent new
structured requests. Report known costs and the number of requests with unknown
cost separately; an incomplete sum is not total expenditure. A timeout does
not establish zero cost, and uncertain delivery still prevents resending. See
the [E5 cost-reporting rules](E5_COST_REPORTING.md).

## Remaining qualification and fixed sources

M1-xAI mock acceptance must cover complete item order and continuation, call_id
matching, invalid arguments, unknown items, usage variants and ticks, refusals,
truncation or interrupted streams, uncertain delivery, privacy and size limits
across the full history, and offline replay without remote history. Live
qualification must additionally verify account-level model availability, at
least two rounds of tool calls followed by valid final JSON, actual usage and
billing fields, and elapsed time and timeout rates for fixed workloads. Live
calls are excluded from CI. None were performed in the initial E0 assessment.

Public OpenAPI snapshot SHA256:
`ee418da1de9d6b66648250e1ecb9fdd98cef472dde7b05c66cc9d0db8dad7f1f`.
The official SDK source was inspected at commit
`1d9e1dffc9a0521ede0e6bc7f2b906177b940d34`:
[fixed chat.py source](https://github.com/xai-org/xai-sdk-python/blob/1d9e1dffc9a0521ede0e6bc7f2b906177b940d34/src/xai_sdk/chat.py).
These references identify inspected sources and interface declarations; they
do not establish live service behavior or single-cell performance. Product
inventories and formal experiment records must distinguish source inspection,
offline checks, live checks and complete preset qualification.

## Subsequent implementation and protocol smoke tests, 2026-10-20

The preceding sections record the initial E0 assessment. Core #4 subsequently
implemented native Responses. Commit `bc349db` passed 238 offline assertions
and a complete R-CMD-check. A maintainer-authorized two-turn protocol smoke test
using synthetic aggregate data passed on `8a48825`: grok-4.7, temperature 0,
effort high, visible-output limit 512 per turn, and timeout 60 seconds. A tool
call was followed by valid JSON, with complete output and encrypted reasoning
continued unchanged. Elapsed time was 6.107 seconds; input 2928, output 165,
total 3093, and reasoning 134, which is not added to total again. The service
reported a cost of $0.003198 in ticks. No private data, held-out data or
biological-performance experiment was involved.

At that stage, the scAgentKit M1 native session and 2B integration remained
separate drafts. Full public-data acceptance and the live CASSIA preset were
incomplete. These results did not establish formal product support or freeze
development parameters for formal experiments.

A subsequent synthetic smoke test of the scAgentKit native engine passed at
`d1e1ebf`: 5 turns, 4 local tool calls, 74.820 seconds, and a valid Unknown draft
that was not approved. Input was 26476, output 5117 and total 31593. The returned
reasoning count, 4534, was included in output and must not be added again. Raw
ticks totaled 527420000, equivalent to $0.052742.
[Per-turn record](../../../docs/dev/benchmarks/provider-smoke/grok-engine-2026-10-20.json).
This adds protocol evidence from the product engine; it does not complete
validation on real public data or qualification for formal experiments.
