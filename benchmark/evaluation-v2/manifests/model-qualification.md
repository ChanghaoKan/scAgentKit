# CASSIA model-matched comparator qualification: DeepSeek and Grok

Assessment date: 2026-10-20. Scope: official source code, official API
documentation, and offline SDK/HTTP request probes. No real API keys were read,
provider APIs called or annotation experiments run. The maintainer selected
DeepSeek and Grok for the primary comparison, with M1-xAI implementation first
and formal Anthropic/OpenAI product support to follow. Costs are compared after
execution; estimates and reservations are not admission requirements for this
assessment.

This record corrects an earlier overstatement: CASSIA controls DeepSeek thinking
only when the model name contains `deepseek-v4`, not for every DeepSeek model.
The maintainer's later decision also superseded the earlier recommendation to
use Anthropic in the primary comparison.

## Findings

CASSIA 1.4.0 is a candidate for model-matched annotation comparisons. Actual SDK
requests captured offline passed `deepseek-flash`, `deepseek-v4-pro` and
`grok-4.7` unchanged to all three roles: annotation, validation and formatting.
They were not replaced by default models or OpenRouter aliases. Matching model
IDs does not, however, establish matching reasoning settings.

| Candidate | Exact-model forwarding | Relationship to the intended scAgentKit configuration | Qualification status |
| --- | --- | --- | --- |
| `deepseek-v4-pro`, official DeepSeek URL | Passed for all three roles. | `reasoning="none"` produces `thinking.type="disabled"`; temperature 0 is sent unchanged; CASSIA fixes the output parameter at 16384. | The most direct primary-comparison candidate using unmodified CASSIA. Matching scAgentKit model and generation settings must be frozen, and a live development-data smoke test must pass before runtime qualification. |
| `deepseek-flash`, official DeepSeek URL | Passed for all three roles. | `reasoning="none"` does not produce a thinking field. The documented current default is thinking enabled/high, so a transmitted temperature of 0 cannot be treated as an effective non-thinking temperature setting. | The native preset supports a descriptive comparison using the same model with different reasoning settings, not a controlled thinking-off comparison. Keeping Flash in the primary comparison requires an explicitly documented minimal transport patch that sends `thinking.disabled`, retains all scientific prompts and agent steps, and is revalidated before freezing. |
| `grok-4.7`, official xAI URL | Passed for all three roles. | CASSIA uses Chat Completions and ignores both `reasoning="medium"` and `"high"`. The effective setting depends on the documented default, high. Temperature .7 is sent unchanged; the output parameter is fixed at 4096. | A candidate for the primary model-matched comparison. Freeze high and record that effort is not sent explicitly, the date on which the default was verified, and the endpoint difference. If scAgentKit uses medium, an explicit transport patch is needed for an effort-matched comparison; otherwise report different presets descriptively. |

This assessment does not require all methods to use the same endpoint.
CASSIA's Grok Chat Completions route and scAgentKit's proposed Responses route
can support a method comparison using the same underlying model. They do not
establish equivalent multi-turn protocols or attribute all differences to
ReAct. A causal ReAct on/off ablation must hold provider, model, generation
settings and other choices fixed within scAgentKit. Full installation, live
provider acceptance, frozen presets, complete results and failure handling
remain prerequisites for formal experiments; they were not completed here.

## Fixed sources and routing

CASSIA commit: `c01f573caf25c5ef471e8afefd035c05becfab08`. Both the R and Python
packages declare version 1.4.0 and use the MIT license. Qualification was based
on source inspection, not model examples in the README:
[R DESCRIPTION](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_R/DESCRIPTION),
[Python setup](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/setup.py),
and [license](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/LICENSE).

- Use the public `runCASSIA` entry with `provider` set to the complete HTTPS
  base URL, `model` to the exact ID, an explicit `temperature`, and
  `use_reference=FALSE`. Do not treat `provider="deepseek"` or `"grok"` as
  supported standard provider names. `_run_core_analysis()` passes the URL,
  model and reasoning setting to the custom wrapper. Its annotation,
  validation and formatting agents use the same model and URL.
  [tools_function.py:222–265 and 346–429](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/tools_function.py#L222-L265);
  [main_function_code.py:588–632](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/main_function_code.py#L588-L632).
- For HTTP providers, the resolver checks global aliases before passing through
  an exact ID. Qualification therefore requires running the actual resolver,
  not relying on its pass-through comment. All three tested IDs were unchanged.
  [model_settings.py:115–176](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/core/model_settings.py#L115-L176);
  [frozen alias configuration](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/data/model_settings.json).
- The custom route creates `openai.OpenAI(base_url=provider)` and calls
  `chat.completions.create(model=model, ...)`. Thinking conversion applies only
  to the official DeepSeek endpoint with a model name containing `deepseek-v4`.
  This excludes the canonical Flash name. The Grok custom route has no effort
  conversion.
  [llm_utils.py:519–579](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/core/llm_utils.py#L519-L579).
- At the assessment date, DeepSeek documentation mapped `deepseek-flash` to
  DeepSeek-V4.1-Flash-1017 and `deepseek-v4-pro` to DeepSeek-V4-Pro-0813; the old
  Flash name had been redirected. Do not substitute an old alias merely to
  trigger CASSIA's string check. The frozen manifest must retain the requested
  ID, officially mapped version, request date and returned model.
  [Model documentation](https://api-docs.deepseek.com/quick_start/pricing/);
  [thinking defaults and parameter semantics](https://api-docs.deepseek.com/guides/thinking_mode/).
- The current exact Grok ID was `grok-4.7`, with default effort high. Responses
  returns encrypted reasoning that can be continued; CASSIA's legacy Chat route
  retains text history only. Report this method difference in the main results
  rather than claiming equivalent multi-turn memory.
  [Grok 4.7](https://docs.x.ai/developers/grok-4-7);
  [legacy Chat Completions](https://docs.x.ai/developers/model-capabilities/legacy/chat-completions);
  [reasoning](https://docs.x.ai/developers/model-capabilities/text/reasoning).

## Executed offline probes

The [probe attachments](cassia-offline-probe/README.md) contain the original
script, results, dependency versions, and download and hash manifest for five
fixed source files. The script and results are retained as executed; third-party
source and dependencies are not bundled. Rerun in a scratch directory without
overwriting the committed results.

The probe used Python 3.9.6, OpenAI SDK **2.48.0** (satisfying CASSIA's
`openai>=2.0.0` requirement), and httpx **0.28.1**.

AST extraction loaded the actual ModelSettings, alias JSON, `call_llm`,
annotation/validator/formatter functions, `_run_core_analysis` and usage code
from the frozen source, skipping third-party imports and module initialization.
The real SDK serialized request JSON. An in-memory httpx MockTransport captured
requests and returned fixed responses. Sockets were disabled and the key was
synthetic; no real credentials were read. Synthetic HTTP responses do not
establish provider acceptance.

| Executed scenario | In-memory HTTP requests | Result |
| --- | ---: | --- |
| Flash with requested none | 3 | Exact Flash ID throughout; no thinking field; max_tokens=4096. |
| V4 Pro with requested none | 3 | Exact Pro ID throughout; thinking.disabled; max_tokens=16384. |
| Grok 4.7 with requested medium | 3 | Exact Grok ID throughout; no effort field; max_tokens=4096. |
| Grok 4.7 with requested high | 3 | The three request-body hashes were individually identical to those in the medium scenario, demonstrating that the parameter was not forwarded. |
| Grok without a completion phrase and with failed validation | 19 | Formatting after three outer iterations; exact Grok ID throughout, with no model switch among the three roles. |

All assertions passed. There were **0 actual provider requests**, no paid costs
and no measured annotation accuracy. The probe recorded source SHA256 values
and hashes of each complete request body. SDK retries=0 was a probe-isolation
setting; it does not establish that unmodified CASSIA disables retries.

## Proposed frozen CASSIA preset and limits

The proposed name is `cassia-1.4.0-annotation-validator-v1-no-reference`, using
the public `runCASSIA` annotation, validator v1 and formatter workflow. Supply
the same frozen marker input, species, tissue and permitted study context.
Set `use_reference=FALSE`, use no proxy, and specify the complete direct URL,
exact model and temperature. Do not use mixed-model pipeline defaults, add
score/annotationboost/merge, or supply ACT evidence or ground truth. Comparing
those capabilities requires a separately frozen preset that records every
participating model and external evidence source.
[Pipeline defaults](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/pipeline/pipeline.py#L134-L160).

This is not a single-call baseline. The normal synthetic path used 3 calls.
The source permits up to 5 annotation calls per iteration and up to 3 validator
outer iterations, followed by 1 formatter call: at most **19 logical calls**
per core analysis. SDK retries, batch retries and API-key preflight requests are
additional and are excluded from the 19-call count.
[Annotation loop](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/main_function_code.py#L161-L185);
[outer loop](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/main_function_code.py#L400-L454).

Batch defaults are n_genes=50, max_workers=10 and max_retries=1 (the initial
attempt plus at most one full-cluster retry), with API validation and automatic
gene-ID conversion enabled. Freeze these parameters explicitly for the formal
adapter. Prefer the existing marker and label-map preparation so automatic
conversion and default marker counts do not alter the input. The external
runner sets call-count and time limits and records every retry and failure.
Aggregate cost and tokens after execution, retaining unknown usage as unknown.
The source does not set SDK timeout or retries explicitly; the tested SDK
defaults were retries=2 and a 600-second read timeout. These are not live-provider
measurements.
[Batch parameters](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/tools_function.py#L557-L625);
[batch retries](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/tools_function.py#L895-L968).

CASSIA's LLM validator is not claimed to be a deterministic evidence validator.
Comparator scoring still uses the scAgentKit evaluator's Cell Ontology mapping,
hierarchical metrics and denominator rules.

## Alternative comparator

mLLMCelltype at commit `26bda564459257a47dd75f8ed321ad81cb306bca` (R 2.0.8,
Python 2.0.9, MIT) has DeepSeek and Grok modules. The DeepSeek module explicitly
disables thinking but hardcodes temperature .7; the Grok module uses native
Chat and forwards the model. It is a candidate for later assessment. This work
did not probe its public entry point, consensus-model selection or actual SDK
requests, so static inspection of provider functions does not establish full
comparator qualification. A multi-model consensus is also not a single-model
control.
[DeepSeek module](https://github.com/cafferychen777/mLLMCelltype/blob/26bda564459257a47dd75f8ed321ad81cb306bca/python/mllmcelltype/providers/deepseek.py);
[Grok module](https://github.com/cafferychen777/mLLMCelltype/blob/26bda564459257a47dd75f8ed321ad81cb306bca/python/mllmcelltype/providers/grok.py).

## Remaining qualification work

1. Retain DeepSeek and Grok4.7 in the primary comparison, implement M1-xAI first,
   and compare costs only after execution.
2. For unmodified CASSIA, the clearest controlled candidates are DeepSeek V4 Pro
   with non-thinking/temperature 0 and Grok4.7 high. Final model selection remains
   the maintainer's decision; this assessment does not change the project's
   default Flash model.
3. If Flash is retained, document and verify a minimal transport correction
   before freezing the preset. Until then, disclose the native Flash preset's
   reasoning difference. The same requirement applies if Grok medium is needed.
4. Before formal experiments, complete a small live smoke test on development
   data and verify full CASSIA installation and result export. Without those
   results, qualification stays pending. No advance cost ceiling or token
   estimation system is required.

Aggregate costs under the [E5 reporting rules](E5_COST_REPORTING.md), and follow
the [provider contract](../../../docs/dev/PROVIDER_MODEL_AND_USAGE_CONTRACT.md)
for request and model status. The [xAI record](xai-qualification.md) documents
its official capabilities, protocol and usage definitions. The historical E0
stage report is retained separately.
