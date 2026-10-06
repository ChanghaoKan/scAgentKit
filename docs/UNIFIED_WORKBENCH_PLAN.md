# Unified saved-project workbench: implementation scope

Baseline: `2a81b5f914485062b1f9a5b4b5be7db91ab1d9af`. This checkout is
independent from the displayed demo and frozen earlier releases. No analysis
algorithm, paid provider request, credential loading or publication is required.

## Existing gaps

- The central coordinator supports current review and parent/child/output
  navigation. A completed project is not a full navigable history workbench.
- With a child workspace, the completed parent API uses a cropped readiness
  description. Its saved QC/strategy/annotation evidence is not all displayed.
- The generic evidence viewer renders existing UMAP/markers, but its endpoints
  are deliberately unavailable in coordinator mode. Opening `/index.html` in
  that mode cannot supply a working integrated viewer.
- The processed public parent deliberately reuses its foundation and skips
  initial QC. Its completed-stage list must not be interpreted as newly
  executed QC or analysis. There is no current-version, same-input pending QC
  checkpoint to replay as if it belonged to this project.

The immediate demonstration uses two actual services over one saved public
PBMC project: central parent/child/output review, and a separate read-only
bundle viewer. Their distinct origin and scope are disclosed. The previous
24-to-14 click result measures the central journey only.

## Smallest complete implementation

1. Add one `/workbench` entry on the existing coordinator service. Each browser
   tab remains bound to registered parent/child IDs; a page switch cannot approve
   a proposal, dispatch a model, execute local analysis or modify a history.
2. Add a strictly read-only, scoped history/evidence API. Inspect full saved
   coordinator evidence through the existing R authority and read only the
   verified bundle belonging to that same scope. Keep generic writes and their
   separate session journal outside this mode. Do not bypass existing guards.
3. Present navigable overview, QC, strategy, analysis, annotation, children,
   outputs and decision history. Reuse real saved UMAP and marker rendering.
   Missing evidence and processed-entry reuse/skip reasons remain explicit.
   Display actual model/provider facts; simulation and unvalidated biological
   accuracy are visibly identified in this public demo.
4. History views remain read-only. Current review is an explicit link to the
   existing scientific workflow. Revision tools expose only already supported
   operations and require a fresh bound proposal, reviewer/reason and approval;
   an immutable completed parent cannot silently become editable.
5. Validate real browser parent/child switching, refresh/restart, concurrent
   tabs, stale/foreign bindings, changed bundles/inputs and zero actions on
   page load. Use independent fixtures, preserve displayed user sessions and
   saved records, and mechanically bind final source to regression results.

## Limits retained

This adds saved evidence navigation and supported review entry points, not a
new scientific engine, universal importer, automatic biological identity,
ortholog mapping, private-data transmission or a benchmark result. The held-out
benchmark remains incomplete. Mac tests do not establish new Linux browser,
HPC scheduler/shared filesystem or Windows compatibility.
