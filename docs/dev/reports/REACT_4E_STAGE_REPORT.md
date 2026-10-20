# 4E evaluation and offline replay candidate

Development candidate, not formal biological validation or release readiness.
Stacked on trace UI PR #22 at `4e9be39cf1f1e75c8e54332c3562d15ae65833b5`.
The PR description records the submitted head and commit range.

## Delivered and reused mechanisms

`sc_react_eval` compares saved baseline/ReAct drafts and external cell/cluster
predictions. It exports all/difficult scopes, cell and cluster outcomes, CL exact
and directed parent scores, primary/strict denominators, mapping coverage,
Unknown fractions, steps, fallback distribution, recorded usage/cost and
configuration. Parent distance is bounded at three; meaningful ancestors must
be frozen explicitly. Cell-to-cluster aggregation uses 80/80 thresholds.

Dual human truth is resolved before reading predictions. Exact or unique nearest
allowed common-parent consensus defines primary truth; disagreements and
comparisons to each annotator remain separate. Agreement rates include mapping
coverage and denominators.

`sc_react_replay` reconstructs append-only saved histories, including native
xAI output, reruns read-only tools and invokes the production citation validator.
No API key, request or approval is used. It compares original drafts, not later
human edits. Committed checkpoint, receipt, ledger and history inconsistencies
block replay; computed differences are returned explicitly.

New abstractions are a versioned scoring consumer and a replay consumer. They
reuse existing CL mapping, ontology loading, state checkpoints, ledger receipts,
tool workers, hashes and citation validation. No new store, approval mechanism,
provider protocol or scientific analysis engine is added. The benchmark adapter
calls the package scorer and consumes existing v1 preparation/label-map sections;
historical v1 scoring and results remain unchanged.

English and Chinese user guides describe scoring, denominator choices,
external imports, provenance, cost scope and replay limitations.

## Validation

Installed-package tests: 179 assertions passed, zero failures, warnings or skips
across evaluation, replay, native xAI sessions, audit projections and ReAct loops.
This includes saved mock projects, dual truth, external predictions, empty
fallback distributions, full native history, fallback/invalid-tool trajectories,
changed computed evidence and the completed-state replay guard. Tests use mock
providers; no new paid calls or held-out data were used.

CI is pending on the submitted head. Full three-gate `sc_start` acceptance is
the following integration stage, not established by these component tests.

## Acceptance status and paper milestone

Standard 11 gains the mandatory software hook, hierarchy, external imports and
ablation configuration exports. Three public truth datasets and formal
performance results are still outstanding. Standard 12 gains API-free replay
with explicit mismatch reporting. Standards 13/14 and release compatibility
remain separate work.

Paper milestone: 2B and M1-xAI are merged. Stage 3 UI (#22), B1/B2 (#23) and this
4E candidate are submitted for review independently. User startup defaults,
integrated documentation/example and full mock three-gate acceptance are next.
E1–E5 and formal biological calibration remain required before paper claims.

## Known limits and deviations

- Baseline accounting currently includes all annotation-purpose calls in the
  project; ReAct increment is session-specific. Unknown costs are counted as
  unknown, not invented. External CSVs do not establish runtime or cost.
- Parent allowlists and dataset label maps need scientific freeze; the evaluator
  does not infer them from predictions. Unmapped historical coarse labels remain
  unmapped until an explicit CL bridge is frozen.
- Timing-dependent tool failures may differ on replay. A saved preflight
  rejection without a dispatched receipt is reported as unverifiable, not a
  successful exact replay.
- Replay requires matching scientific code and checkpoints. This PR changes the
  implementation hash; it does not implement future 1.0 compatibility migration.
- Evaluation is local and may contain cell IDs. Those files never enter model
  payloads. No formal experiments, private data or new paid smoke tests ran.
