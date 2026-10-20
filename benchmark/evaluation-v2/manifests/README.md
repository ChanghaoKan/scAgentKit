# Qualification and freeze records (E0 documentation)

These are field contracts and examples for E1/E5, not executable configuration or an experiment freeze. The approved protocol is [here](../../../docs/dev/EVALUATION_PROTOCOL_V2.md). Unknown required fields remain explicit `unknown` or `null` with a reason; an example never qualifies a dataset/model by itself.

## Model and comparator recommendation

The primary matrix is **DeepSeek + Grok**. M1-xAI comes first using Responses;
**grok-4.7** is the documented candidate. **CASSIA 1.4.0, commit
`c01f573caf25c5ef471e8afefd035c05becfab08` (MIT)** is a same-model comparator
candidate. Actual SDK/MockTransport probes verified Flash, V4 Pro and Grok4.7
exact IDs across annotation/validator/formatter; complete installation, live
service and matched presets remain pending. Flash thinking and Grok effort
forwarding gaps are explicit in the [qualification record](model-qualification.md).
Official Grok capability is documented [separately](xai-qualification.md), not
labeled product verification.
The [small offline-probe attachment](cassia-offline-probe/README.md) preserves
the executed script/results and explains how to obtain the pinned source and
dependencies; it does not bundle a CASSIA installation or establish live support.

Product support targets all four providers, selected by the user. Anthropic and
OpenAI formal adapters may follow the paper. Other supported providers receive
public development N=3 accept_drafts usability checks, separate from the main
scientific result and non-blocking. Exact models and presets freeze after
qualification, without a pre-run quote or monetary threshold. If an arm cannot
match its preset, record the limitation and prospective amendment before formal
outcomes; do not silently switch models.

| Field group | Required records |
| --- | --- |
| Identity | provider, exact requested/returned API model, endpoint/protocol, request date, snapshot/alias semantics and source |
| Capability | tool/result formats, supported context/output and reasoning/decoding semantics, complete protocol-history rules, source/date |
| Usage/cost | raw service usage and reported charge; where needed, post-run price-based calculation and dated source; missing fields remain unknown; no pre-send count or price gate |
| Comparator | repository, version/commit, license, exact preset, all participating model IDs, retry/time settings, inputs/reference access and endpoint differences |
| Qualification | source, offline contract, complete installation, development smoke, full preset, actual usage metadata — independently pass/pending/fail |
| Leakage | public cutoff source or unknown, first-public data date; post-cutoff preferred, not mandatory |

DeepSeek product defaults remain Flash, thinking disabled and temperature zero.
Unmodified CASSIA's V4 Pro route can match non-thinking/temperature zero; its
Flash route cannot yet match that thinking setting. Grok4.7 cannot disable
reasoning; default high/temperature .7 is a matching candidate, not a frozen
preset. CASSIA does not forward an effort argument and uses legacy Chat rather
than Responses. Report these differences; same model is not protocol equivalence.
ReAct on/off isolates its effect within a fixed scAgentKit configuration.

## Dataset qualification

No benchmark or maintainer holdout matrix is loaded by E0. The candidate table in the protocol is metadata research, not three qualified datasets. At least three independent public datasets with credible truth must qualify and collectively cover low RNA and proliferating cells. Prior v1/development data cannot be relabeled unseen benchmark data. Multiple tissues from one study are not automatically independent studies.

| Required field | Meaning |
| --- | --- |
| `dataset_id`, `split`, accession/URL | development, public_benchmark or maintainer_holdout; exact study/release |
| `species`, `tissue`, platform, samples/donors | declared metadata, independent biological unit and available design; no inferred replication from cells |
| raw counts | file/version/hash, integer status, raw/filtered scope, original QC and cell selection |
| truth | experimental/orthogonal, independent manual or author labels; date evidence, annotator independence, blind status, label granularity |
| CL mapping | snapshot/hash, map/hash, allowed reporting ancestors/hash, consensus mask/hash, distance≤3 and cluster truth 80/80 |
| scope | low-RNA/proliferation support, minimum evaluable classes, sample/donor selection, license/access conditions |
| isolation | prior development use, no truth in executor input/prompt, holdout unavailable-to-model evidence and maintainer attestation |
| qualification | pass/pending/fail per criterion and source, not a single unsupported “ready” flag |

The unpublished maintainer holdout is a primary E5 result and the main evidence for unavailable raw data, supported by source/date and isolation records. It is not experimental sorting truth: two marker-based manual labels are compared separately and through a pre-frozen meaningful CL consensus. Unmapped/ambiguous/disagreement masks remain visible. Metadata placeholders supplied by the maintainer remain unknown until completed; developers do not request or inspect the data while implementing.

## Documentation-only examples

The following shape describes fields to be implemented and validated in E1/E5. It must not be used to send a model request:

```json
{
  "schema_version": "evaluation-freeze.v1",
  "record_status": "engineering_protocol_only",
  "experiment_freeze_status": "not_frozen",
  "engineering_protocol_commit": "recorded_in_E0_stage_report",
  "experiment_protocol_commit": null,
  "package_commit": null,
  "core_version": "0.2.0",
  "primary_providers": ["deepseek", "xai"],
  "recommended_grok_model": "grok-4.7",
  "frozen_primary_models": null,
  "frozen_generation_presets": null,
  "comparator_commit": "c01f573caf25c5ef471e8afefd035c05becfab08",
  "qualification": {
    "source": "pass",
    "isolated_sdk_http_exact_ids": "pass",
    "matched_generation_presets": "pending",
    "complete_install": "pending",
    "live_smoke": "pending",
    "formal_experiment": "not_started"
  },
  "dataset_hashes": [],
  "truth_hashes": [],
  "parameter_freeze_commit": null,
  "missing_reason": "Engineering design only; E5 freezes qualified models and presets."
}
```

The product list keeps source/offline/live verification separate. Custom IDs
remain unverified configuration; unknown pricing does not prevent a structured
request. New turns report costs after execution without a monetary cap; the
legacy one-shot budget remains compatible. See the [provider contract](../../../docs/dev/PROVIDER_MODEL_AND_USAGE_CONTRACT.md)
and [post-run reporting](E5_COST_REPORTING.md).

For a holdout truth CSV, the accepted planned local format is `cell_id,label_author,label_independent`, with optional `cl_id_author,cl_id_independent`. Both label files, CL mapping and the primary consensus mask are frozen before the first tool run. The framework exports author agreement, independent-label agreement, consensus primary results, annotation disagreement results, and both main/strict accuracy. No local ID or truth label is copied to an external provider.

## Freeze receipt and amendment policy

An E5 receipt references already committed protocol, code and parameter revisions, source hashes, exact model/comparator settings, execution authorization, available cost sources, seeds/RNG, risk detection paths, scoring version, and all prior qualification records. It does not require a file to contain its own future commit hash. Preserve every prior receipt and result. Changes after formal outcomes are seen are a declared amendment/new batch or exploratory analysis; no retroactive tuning of the original main result.

The four user-fixed design decisions, CL distance 3 and 80/80 are approved. N=3 for B1 marker eligibility, diagnostic settings, batch effect/support and biological-retention warning thresholds are development candidates until explicitly frozen using development data. Public post-training-cutoff timing is a preference; unknown cutoffs do not block otherwise qualified primary experiments.
