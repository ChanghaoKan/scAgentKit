# Qualification and freeze records (E0 documentation)

These are field contracts and examples for E1/E5, not executable configuration or an experiment freeze. The approved protocol is [here](../../../docs/dev/EVALUATION_PROTOCOL_V2.md). Unknown required fields remain explicit `unknown` or `null` with a reason; an example never qualifies a dataset/model by itself.

## Model and comparator recommendation

Recommend **DeepSeek + Anthropic** as the primary matrix, with **`claude-opus-5-5`** as the frontier candidate and **CASSIA 1.4.0, commit `c01f573caf25c5ef471e8afefd035c05becfab08` (MIT)** as a same-model annotation comparator. Official sources and an isolated fake-SDK request probe support this recommendation; they do not establish live API, complete dependency installation or full-preset success. See [the dated qualification record](model-qualification.md) for exact source links and limitations.

M1-Anthropic precedes M1-OpenAI and M1-xAI. The latter are descriptive extensions and do not block formal experiments. If primary qualification fails, record the failure and prospectively revise the primary choice before observing formal outcomes; do not silently substitute a model after scoring.

| Field group | Required records |
| --- | --- |
| Identity | provider, exact API model ID, model returned by service, endpoint/protocol, request date, published snapshot/alias semantics and source URL |
| Capability | tool-use support, role/tool-result format, max input/output and counting conventions, supported decoding/thinking fields; source URL and verification date |
| Cost | dated prices/currency and cache/reasoning rules; certified tokenizer/framing bound or conservative official context-limit reservation; live usage status |
| Comparator | official repository, version/commit, license source, exact preset, all participating model IDs, retry/time/cost bounds, inputs and reference access |
| Qualification | source check, offline contract check, complete install, development smoke, full preset, budget/usage verification — each independently pass/pending/fail |
| Leakage disclosure | public training-cutoff source or unknown, data first-public date and evidence; post-cutoff is preferred, not a hard gate |

DeepSeek retains thinking disabled and temperature 0. Claude's candidate adaptive thinking cannot be disabled, and unsupported temperature must be omitted. Candidate effort medium is frozen only after capability/development checks. All model calls participating in a CASSIA preset must share the selected base model. Report differences in actual information access and spending rather than assuming equal prompts or token budgets imply equal methods.

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
  "primary_provider_candidate": "anthropic",
  "primary_model_candidate": "claude-opus-5-5",
  "comparator_commit": "c01f573caf25c5ef471e8afefd035c05becfab08",
  "qualification": {
    "source": "pass",
    "isolated_request_shape": "pass",
    "complete_install": "pending",
    "live_smoke": "pending",
    "formal_experiment": "not_started"
  },
  "dataset_hashes": [],
  "truth_hashes": [],
  "parameter_freeze_commit": null,
  "missing_reason": "E0 records approved design; E5 freezes all experiment inputs."
}
```

For a holdout truth CSV, the accepted planned local format is `cell_id,label_author,label_independent`, with optional `cl_id_author,cl_id_independent`. Both label files, CL mapping and the primary consensus mask are frozen before the first tool run. The framework exports author agreement, independent-label agreement, consensus primary results, annotation disagreement results, and both main/strict accuracy. No local ID or truth label is copied to an external provider.

## Freeze receipt and amendment policy

An E5 receipt references already committed protocol, code and parameter revisions, source hashes, exact model/comparator settings, authorized budget, seeds/RNG, risk detection paths, scoring version, and all prior qualification records. It does not require a file to contain its own future commit hash. Preserve every prior receipt and result. Changes after formal outcomes are seen are a declared amendment/new batch or exploratory analysis; no retroactive tuning of the original main result.

The four user-fixed design decisions, CL distance 3 and 80/80 are approved. N=3 for B1 marker eligibility, diagnostic settings, batch effect/support and biological-retention warning thresholds are development candidates until explicitly frozen using development data. Public post-training-cutoff timing is a preference; unknown cutoffs do not block otherwise qualified primary experiments.
