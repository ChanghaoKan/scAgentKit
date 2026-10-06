# One saved-project workbench

Open `/workbench` on the existing coordinator service to browse a project's
overview, QC, strategy, analysis, annotation, children, outputs and history.
The selected parent or registered child stays bound to that tab. UMAP points
and markers come from that project's verified saved analysis checkpoints while
annotation is pending, or its fixed output bundle after finalization. No
export/import ZIP or transfer of the source RDS is required.

Historical views are read-only. **Review current step** opens the existing
review tools for that exact project. Scientific approval, aggregate-transfer
consent, model requests, local Continue, child creation and derived apply remain
explicit actions there. Refreshing or opening a section performs none of them.

## Start on the analysis machine

Initialize a project with the [R entry example](FIRST_RUN.md), or use an
existing coordinator project. Use the same compatible installed scAgentKit
library that created it. From this checkout:

```sh
python3 workbench/server.py \
  --run-project /absolute/path/to/parent-project \
  --subcluster-workspace /absolute/path/to/child-workspace \
  --rscript /absolute/path/to/Rscript \
  --r-library /absolute/path/to/private-r-library \
  --local-continue --port 8775
```

Open `http://127.0.0.1:8775/workbench`. The listener is loopback only. If using
an already authorized remote machine, forward the same loopback port with your
existing SSH configuration:

```sh
ssh -N -L 8775:127.0.0.1:8775 your-existing-ssh-host
```

The service starts no scheduler job and changes no login, firewall or browser
setting. Without a browser, the [headless R workflow](SINGLE_SERVICE_REVIEW.md#the-same-workflow-without-a-browser)
remains available. On a shared machine, loopback binding alone is not multiuser
authentication.

The command needs no provider. `--model-mock` is optional for an existing
immutable mock configuration; `--subcluster-inherit-model` explicitly makes
that safe configuration available to new children. Real-provider setup and
aggregate-payload consent are described in [model review](UNIFIED_MODEL_REVIEW.md).
The page displays the saved configuration, including a visible mock indicator.
It never receives a key or chooses a provider, endpoint, model or budget.

## What the sections show

| Section | Saved facts and boundaries |
| --- | --- |
| Overview | Declared study context, input diagnostics, stages and exact snapshot binding. |
| QC | Actual aggregate QC evidence and saved proposal/impact, when present. A processed entry explicitly displays its saved reuse reason. |
| Strategy | Saved whole-plan proposal, rationale, applicability and lifecycle. An estimated retention count stays a preview. |
| Analysis | Recorded parameters and diagnostics; real saved coordinates and cluster markers. Pending annotation is explicitly labeled as a saved analysis checkpoint, without final annotation labels. Reused foundations are labeled as reused. |
| Annotation | Saved database/model evidence, proposal rationale, cited markers and human review lifecycle. Qualitative confidence remains uncalibrated. |
| Children | Registered independent children and actual derived-output receipts. Their exact scope is separate from the parent. |
| Outputs | Saved artifact paths and hashes, original output references and separate derived parent objects. RDS files are read locally in R. |
| History | Verified original run event headers and allowed scientific details; a child's separate derived-apply/undo journal is labeled separately. Superseded approvals do not become new authority. |

Selecting a cluster changes only the local plot and marker display. [Gene links](GENE_LOOKUPS.md) preserve literal marker/citation symbols: explicit human context has exact GeneCards links; explicit mouse context has separate MGI and every official human candidate from a pinned local snapshot. Only an active click sends the selected symbol/ID outward; rendering makes no external request. Missing species and unmatched mouse records remain inert; no uppercasing or biological inference occurs.

## Evidence and recovery limits

Every saved-view request rechecks the registered workspace, run state, history
and the declared checkpoint or fixed bundle. Query IDs and the run-project
header must agree. A changed
input, checkpoint, bundle or scope fails closed. The workbench has no separate
mutable generic-review journal and cannot select an arbitrary filesystem path.

All original event headers are supplied when the view fits its explicit
16 MiB display bound. Scientific details are an allowlisted projection;
secret-bearing and private per-cell metadata are excluded. An oversized view
is refused without silently truncating history or plots. Inspect the original
saved artifacts in R when a view cannot be supplied.

A project awaiting annotation may not have a completed output bundle yet.
After analysis and markers are saved, the page reads the verified `analysis`,
`markers` and `annotation_evidence` checkpoints. The existing public exporter
and bundle validator build a temporary display snapshot; the project directory
is unchanged. Its receipt binds the state, input, configuration, implementation,
revision, history, checkpoint bytes and exact cells. This display runs no
analysis or model request and does not approve labels. It is labeled **saved
analysis checkpoint; annotation pending**, and Outputs remains incomplete.

When those checkpoints are unavailable, available QC/proposal/history remain
visible and missing plots are reported as unavailable. This page does not
recreate earlier full snapshots or manufacture missing plots. Older completed source records can be shown
only after the existing immutable source-scope validation; their old approvals
are not reopened under current rules.

The completed source parent is frozen in a child workspace. Approved child
apply creates a separate parent object and receipt, preserving the original
parent and its previous annotation columns. Returning to the parent or
refreshing reads fresh child/application records even if the parent revision
has not changed. See [subcluster review](SUBCLUSTER_REVIEW.md) for conflicts,
supersession and undo.

This increment adds navigation over existing evidence. It does not establish
biological accuracy, supply an independent held-out benchmark, add an analysis
algorithm or verify a new live provider. Earlier click-count comparisons in
[first-use review](FIRST_USE_REVIEW.md) measure the central review journey;
they are not a measurement of this complete workbench.
