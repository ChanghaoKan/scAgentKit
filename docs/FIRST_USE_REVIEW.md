# First-use review with fewer mechanical actions

Keep one service attached to the parent project and its registered child
workspace. Files, jobs and approval journals stay on the analysis machine;
normal review requires no RDS transport or ZIP export/import. Initialize the
project with `sc_run()` as described in [First run](FIRST_RUN.md), then start the
service using the command in [single-service review](SINGLE_SERVICE_REVIEW.md).

## Review sequence

1. Read the saved scientific evidence and the expanded exact model payload.
   Enter your reviewer name and reason. **Approve and request** saves consent
   and starts only this request. An external provider receives the displayed
   aggregate; keeping raw data on the server does not prevent this transmission.
2. Read the validated candidate. Accept or modify it to prepare a scientific
   proposal. This remains a separate explicit action. Approve the displayed
   whole proposal and Continue locally only after reviewing it.
3. After parent completion, select literal parent clusters in the workspace and
   explicitly create a child. The saved child opens directly in central review.
   It has its own raw-count input, proposals, approvals, jobs and provenance.
4. Complete the child's independent scientific review. **Review exact child
   labels and save a new parent object** opens that child's application preview.
   Inspect the exact scope, target column and outside-NA policy; explicitly
   approve the apply. A matching durable receipt returns to the parent with its
   active derived result expanded.
5. Load the new object in R using the saved local output path. The original
   parent and its old annotations remain saved. A derived object is an output,
   not an automatically opened executable project.

The transfer, scientific, selection and apply decisions remain explicit.
Opening a page, changing tabs, refreshing or returning to a saved result cannot
approve a proposal, resubmit a model request or execute local work. When a
combined approval/request response is lost or the binding changes, the chain
stops. Refresh inspects saved state; it does not replay the interrupted intent.
An already approved exact preview retains a separate explicit request button.
The request/cache/unknown-usage policy is in
[unified model review](UNIFIED_MODEL_REVIEW.md).

Marker and citation genes offer [click-only external links](GENE_LOOKUPS.md): exact-symbol human GeneCards, or separate mouse MGI and all official human candidates from a pinned local snapshot. Only a click discloses the chosen symbol/ID; no list or expression is uploaded. Original symbols remain literal; missing species and unmatched mouse symbols stay inert, without an inferred absence of orthology.
Initial context notes and saved scientific reasons meet this release's notes
scope; this change adds no notes editor or AI gene-explanation chat.

## What the click comparison measures

The paired Mac Chrome acceptance starts two independent projects from the same
already processed public PBMC object, declares why its PCA/UMAP foundation is
reused, and uses the same literal child selection and explicit local mock
provider. Parent annotation, child strategy, child annotation, local Seurat
computation and exact-ID derived apply are real coordinator operations. Mock
annotations remain `Unknown`/low; the experiment tests workflow integrity,
not annotation accuracy or threshold quality.

Normal-path button, checkbox, navigation and disclosure clicks are counted.
Text entry, scrolling and a declared reference dropdown are listed separately.
Refreshes, cache replays, duplicate/negative probes, extra tabs, server restart
and GeneCards link checks are validation actions and are excluded from the
normal-path count. Necessary navigation uses actual UI links, not programmatic
URL opens. The final derived receipt must be visibly expanded to finish the
journey.

The older single-service record's 16 mechanical clicks came from a 476-cell
synthetic fixture and included four validation round trips. It also omitted
one result disclosure and used a programmatic URL open for application
navigation. It is retained as historical evidence, not used as the paired
public-PBMC baseline.

### Measured paired normal path

The processed parent has 2,700 cells. Both projects select literal cluster `"5"`,
containing the same 203 cell IDs, and complete three simulated suggestion jobs
and three real local continuation jobs. Both retain the processed parent's
foundation and independently compute the child's foundation.

| Required normal-path action | f9 baseline | This increment |
| --- | ---: | ---: |
| Scientific approval, literal scope selection, create and apply | 6 | 6 |
| Exact simulated-request preview consent | 3 | 3 |
| Mechanical adoption, navigation and disclosure | 15 | 5 |
| **Total physical clicks** | **24** | **14** |

The ten saved mechanical clicks come from three already-expanded previews,
three explicit approval/request combinations, direct navigation to the created
child, the completed child's exact apply link, and direct return to the expanded
parent receipt. The API approval and request remain separate, sequential,
fingerprint-bound operations. Candidate adoption and scientific approval remain
separate decisions. Each project records one active derived application; extra
validation actions are outside the table.

These counts include saved-state resumption, not uninterrupted browser sessions
or a time-performance comparison. The baseline first session's five-second
status GET aborted while R completed the saved child; a fresh service/browser
inspected that same job and finished without another computation or model
request. The increment raises only the read deadline to 125 seconds, matching
the existing bounded R bridge; POST remains 15 seconds and no retry is added.

The first increment session stopped after an extra GeneCards test incorrectly
expected the legacy query route instead of the implemented official `/card/`
route. It resumed the saved adopted parent proposal without requesting again.
After the 14-click journey, a separate slow-read test called the client before
page initialization and failed in the test helper. Original reports and
screenshots are retained. A further validation session waits for initialization
and inspects existing saved work; it does not count toward the normal journey.
The evidence distinguishes these helper failures from the baseline status-read
failure and records every owned service/browser cleanup.

Both normal journeys use two Chrome sessions. The increment adds two separate
validation sessions: existing-job/rejection/restart/application replay checks,
then a fully initialized parent-page screenshot. The latter confirms the exact
parent's `complete / complete` status and expanded active derived receipt, with
zero POSTs or external navigations. The earlier loading-page screenshot is
retained and is not used to prove initialization complete.

### Final implementation and checks

The baseline is `f9cd7d1dfce21351dd7e9e8f5666e204040ef76a`. The final 316
non-Markdown source/test files have canonical SHA256
`3c1675cb64dcb59f719f910ce5e904f7137426d00f7e4db7bdf7d5ccd565f729`.
The manifest maps each Git source path to its SHA256, then hashes sorted compact
JSON. The regression seal and native browser component hashes match this
implementation; subsequent changes are documentation only. All 71 R source
files and 53 testthat files, including the runner, match the f9 baseline and the
separately audited installed R namespace.

| Validation on Mac | Executed result |
| --- | --- |
| Full Python regression with actual R fixtures enabled | 303 passes, zero failures/errors/skips |
| Eleven offline client suites | 372 cases: 340 DOM plus 32 response cases; all pass |
| Public PBMC paired Chrome journey and saved-work probes | Six accepted checks for each pair; six saved jobs per project journey |
| Initialized parent output page | Exact completed parent and expanded active derived receipt; zero POST/external navigation |
| Separate native GeneCards controls | Eight checks; external destinations intercepted locally, no page content fetched |
| One fresh R process over both saved pairs | 80 assertions pass: sparse counts, literal IDs, old metadata, reused parent foundation, fresh child foundation, five scoped derived fields, zero-cost ledgers, one active receipt and stale-approval rejection |
| Existing public regression fixtures | All 554 files byte-identical after checks |

The two children have identical literal cell order, raw counts, cluster
membership, mock `Unknown` labels, PCA embeddings and UMAP embeddings in this
runtime. Removing all five new derived fields restores every parent slot;
outside-scope values are `NA`. All parent/child files, source objects and bound
evidence reports are unchanged after the independent inspection. These are
fidelity and persistence observations, not biological validation.

The first full Python attempt retained loopback permission failures under the
default sandbox. One approved loopback rerun passed; the final read-deadline
change then received a fresh complete 303-pass run and expanded DOM coverage.
These earlier attempts remain evidence, not silently discarded test results.
The controlled slow-read probe delayed exactly one existing-job GET by 6.5
seconds, returned the same saved job in 15.8914 seconds including bridge work,
and added no POST. It is a deadline/recovery check, not a runtime benchmark.

## Scientific validation boundary

[BENCHMARK_PROTOCOL_DRAFT](BENCHMARK_PROTOCOL_DRAFT.md) remains a plan. Independent
human/mouse pancreas provisioning, label-isolated evaluation, matched native
Seurat comparison, provider comparison and held-out biological accuracy
measurement have not been completed. Faster navigation, marker agreement,
valid typed responses and `Unknown` output do not establish biological identity
or an optimal QC/PC/resolution choice.

This experience increment is tested on Mac. The unchanged R engine has separate
f9 Linux closure evidence; this page does not claim new Linux browser, HPC
scheduler, shared-filesystem, Windows or live-provider validation. New paid API
calls and credential reads in this increment are zero.
