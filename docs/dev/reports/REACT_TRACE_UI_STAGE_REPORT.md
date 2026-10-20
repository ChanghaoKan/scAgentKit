# Stage 3 audit and workbench candidate

Status: draft PR; not a release or completed browser acceptance. The PR records
the exact commit range against main after Core v0.3.0 and PRs #19/#20.

## Changes and reuse

The existing ReAct checkpoints remain authoritative. A read-only display
projection exposes tool arguments, bounded result previews, result hashes,
recorded usage/cost, original checked conclusions, risk fields and current
retained citations. Full native provider history is unchanged.

Existing atomic writes export `annotation/react/<cluster>.json` and an index.
Non-numeric cluster IDs use hashed filenames to avoid traversal, case aliases
and index collisions. Existing decision-history events reference export hashes
and authoritative checkpoint hashes. Exports are not a second recovery store.

The workbench shows an aggregate summary, fallback reasons and per-cluster
expandable steps. Active citation links open their corresponding step.
`gene_expression` is marked untested background evidence. Unknown cost is
reported separately from recorded cost. No new approval or mutation endpoint.

New abstraction: one versioned audit projection and its disposable JSON export.
Checkpoint, hash, event, atomic-write and UI rendering mechanisms are reused.

## Validation

- Installed worker plus local ReAct loop/audit/manual regression: 96 assertions,
  zero failures, warnings or skips.
- Production workbench source in the DOM harness: 126 checks passed, including
  active citation links, deleted historical citations and untrusted preview text.
- Workbench runtime/projection HTTP and R bridge tests: 42 passed. The initial
  run lacked the local R library path; rerunning with installed dependencies
  passed. This was an environment issue, not a relaxed assertion.
- Full PR CI is pending. No real browser acceptance or new paid API call is
  claimed by these checks.

## Acceptance and paper milestone

Standards 7 and 8 gain visible evidence and retained citation provenance while
the existing human approval boundary is unchanged. Standard 9's object-embedded
audit and standards 11–14 are not completed by this PR.

Paper milestone: 2B and M1-xAI are merged; this is the stage 3 candidate.
B1/B2 continue independently. 4E evaluation, offline replay, user guides and
formal experiments remain outstanding.

## Limits and deviations

The display exposes saved evidence and draft rationales, not hidden reasoning.
JSON previews are truncated; complete results remain in the checkpoint.
The interface is the existing read-only workbench; editing and approval still
use the existing review flow. Browser acceptance and release documentation
remain required before marking this stage finished.
