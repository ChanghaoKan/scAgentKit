# Annotation evidence in the reviewed workflow

After analysis and marker computation stop at annotation preparation, the local
worksheet shows the saved cluster scope, marker facts, reference status and
source. It does not label cells, request a model or approve a scientific plan.
The original complete proposal and separate whole-plan approval remain the only
path to applying annotations. `sc_result()` and its exports remain existing
capabilities; this change adds no new result-export system.

## Facts, candidates and analyst decisions

| Field | Behavior |
| --- | --- |
| Supplied markers | Show saved cluster-specific statistics; full table and citation controls expand locally |
| Reference candidates | Show actual saved scoped matches and their source/version, including coverage numerator and denominator |
| Missing or mismatched scope | Show unavailable status; do not offer inferred labels or substitute another cluster's evidence |
| Candidate selection | Explicitly copy that candidate's label and only its citations present in this cluster's supplied markers, resolving recorded aliases back to original supplied names |
| Confidence and interpretation | Remain blank after candidate selection; the analyst supplies qualitative confidence, reasoning and unresolved alternatives |
| Unknown/coarse label | Valid retained result; Unknown uses an explicitly entered reason and is not hidden from output summaries |
| Local row keeping | Optional protection of a completed manual draft; no saved row-level approval or computation |
| Complete Save | Creates one unapproved typed proposal; the analyst inspects it and approves the complete plan separately |

Candidate order, top-1, coverage, overlap and any combined score do not establish
identity or correctness probability. A single-marker match is weak even at full
reference coverage. Tied best names are shown as evidence conflicts needing
judgement; a lexical tie does not prove a biological contradiction. Unmeasured
genes and genes absent from a top-marker list are not evidence of non-expression.
A coarse interpretation or unresolved identity can be more appropriate than the
reference's most specific name. The page does not invent a human rationale.

No reference is downloaded by the worksheet. New modern projects snapshot the pinned offline ACT reference at creation; existing projects retain their saved reference. The table uses reference
facts already saved through the existing R configuration/update interfaces.
`sc_run_set_reference()` remains the explicit evidence-refresh API before
annotation application and rebuilds bindings/invalidates earlier acceptance.
It does not rerun markers or silently preserve an approval against changed facts.
Sources and license status are displayed as recorded, including unknown license.

This webpage projection is separate from the model's aggregate summary. The
existing default independent branch continues to omit reference labels. Guided
mode still follows its existing explicit configuration and dependency disclosure;
agreement with a reference-guided response is not independent confirmation.

## Compact review and draft protection

The worksheet starts with needs-judgement, evidence-conflict and locally checked
summaries. Saved ties/source inconsistencies are shown before ordinary rows;
marker tables and provenance remain expandable. Labels and confidence are not
preselected. Bulk Unknown acts only on untouched blank rows. Candidate assistance
cannot replace human edits, already cited evidence or a locally kept row; clear
that row explicitly before reconsidering a candidate.

Local drafts are stored in this browser tab under the exact project, original
input, evidence hash and revision. Reloading the same binding restores the draft;
a different revision/input/evidence never receives the old rows automatically.
An older draft is retained in tab storage and is identified as stale. This is
not durable server-side proposal storage and cannot replace Save. Download an unfinished worksheet before closing the tab or handing work to another analyst. Import validates the exact binding, cluster IDs, citations and bounded fields; a foreign or stale file is rejected without replacing current rows. It grants no approval. If tab storage is unavailable, download before leaving.
The explicit discard control affects only the current bound local worksheet.

Unsaved worksheet edits now block model actions and accidental refresh changes.
A model adoption replaces a complete typed proposal for central review; it does
not merge candidates into manual rows. Save the worksheet or explicitly discard
it before switching to the existing model component. Requests retain their
existing revision/request-id, exact-preview consent, ledger and interruption
rules. No automatic resend or new provider channel is introduced.

## Optional configured model

Choose manual mode explicitly for a reproducible offline start:

```r
library(scAgentKit)
sc_start("a.rds", "analysis",
  context=list(species="human", tissue="Peripheral blood",
    research_goal="Inspect the major immune populations."), provider="manual", reference_tissue="Blood")
```

For a project already initialized with a supported immutable provider and the
saved project, `sc_start(project_dir="analysis", model_suggestions="configured")` opens
the existing preview/authorize/request/adopt component in that main workflow.
The runtime passes only the saved provider's named credential to an explicitly
enabled service/request worker. Credentials are never serialized into a launcher
record or browser field. A manual project's missing provider does not block
local annotation. Model/provider setup is R-side and immutable;
see [model review](UNIFIED_MODEL_REVIEW.md). Explicit `"simulate"` requires a
saved mock provider and produces marked zero-model software controls.

No real transfer or paid provider invocation is required by the local tests.
Simulation tests prove software transitions, not model quality, cost estimates
or biological accuracy.

## Verification and comparison

Tests cover aliases, exact cluster scope, stale revisions, protected manual rows,
unknowns, interrupted-tab restoration, explicit discard, complete Save and
separate scientific approval. A public PBMC walkthrough uses the existing raw
input and a small explicitly sourced coarse reference. Its task/reference
provenance is in `benchmark/fixtures/pbmc-evidence-task`; those labels are a
software case rather than held-out truth.

Use the [offline comparison contract](OFFLINE_COMPARISON_CONTRACT.md) for fixed
IDs/settings, truth isolation, complete denominators, known failures/skips,
independent target-library installation and the proposed clean-platform CI.
The CI definition must run before claiming Linux or a clean hosted platform.
A developer replay's evidence-transcription, file-transition and editing counts
are task bookkeeping; they are not real-user time savings or scientific benefit.
