# QC impact review on the data machine

The optional workbench reads an existing `sc_run()` project directly. R and its
server-side state remain the authority. The normal headless inspection,
approval and `sc_run_resume()` workflow remains available without a browser or
manual ZIP transfer.

Start this separate, loopback-only server on the machine that owns the project:

```sh
python3 workbench/server.py --run-project /durable/path/to/project \
  --r-library /path/to/installed/R-library --port 8772
```

Use the newly installed package version that created the project. Existing
libraries can be supplied using the platform path separator, for example
`--r-library '/private/new-library:/private/dependencies'` on macOS/Linux. The
coordinator rejects an implementation change rather than reusing old approvals.
Choose a free port; starting this mode does not modify an existing workbench.

Open `http://127.0.0.1:8772/review` locally. The unified page embeds the QC pane
and later shows the same project's annotation review after explicit R resume.
The legacy `/qc` view and `/api/qc/inspect` remain readable, while legacy QC
POSTs on a unified server are rejected; use `/review` for decisions. On a server, create an SSH tunnel yourself
from the client, for example:

```sh
ssh -N -L 8772:127.0.0.1:8772 your-configured-ssh-host
```

Then open the same localhost URL on the client. The workbench does not log in,
open public interfaces, alter SSH/firewall settings, launch a browser, or submit
scheduler jobs. The server hostname, account and authentication are operator
configuration, not inferred by the package.

Keep the local and remote tunnel port the same, as in `8772:127.0.0.1:8772`.
Remapping the browser to another port is rejected with HTTP 403 by the exact
Host check; the workbench does not loosen that check automatically.

The QC page displays the saved typed ranges, exact retained/removed cell IDs,
sample/capture scopes, independently failing and exclusively failing conditions,
measured overlaps, disjoint failure patterns, measured quantile summaries and
missing measurements. An optional named gene panel discloses feature
availability only; expression, identity, singlet status and biological quality
are not inferred. The page shows only the explicit sensitivity alternatives
saved in the preview; it never generates or automatically chooses a cutoff.

The loopback browser receives exact cell IDs, per-cell QC measurements, declared
sample/capture values and supplied project context. These local review details
are visible to the person accessing this localhost server or SSH tunnel. The
workbench does not serve raw-count/expression matrices, RDS/state files or API
keys. Provider transmission is a separate coordinator action with an approved
aggregate payload; having raw data on a server does not mean that approved
aggregate QC/marker/context requests remain on that server.

This is a trusted local or tunnel review session. Loopback binding,
Host/Origin checks and the review token prevent cross-site writes; they do not
provide per-user authentication. Processes that can reach this node's loopback
port can read the review and token. Authentication isolation on a shared,
multi-user HPC node has not been implemented or validated in this version.

Supply a reviewer and a reason, then choose one of these actions:

- **Approve** the displayed plan. Its revision, proposal, input, parameters and
  preview fingerprints are saved with the decision.
- **Modify** supported typed JSON, then save and rebuild. Review the resulting
  scope again before approving. Editing a draft disables approval.
- **Rebuild alternatives** for the current executable rules, with a small explicit
  list of `{"id":"...","proposal":{...}}` controls and optional named gene arrays.
- **Reject** the plan. The input and evidence remain saved; provide a corrected
  typed proposal in R to reopen review.

Every change appends the reviewer/reason audit. A stale tab, changed input or
concurrent revision is rejected using the R project lock and saved fingerprints.
An identical repeated approval returns the saved result without another journal
write; the page disables further approval once the decision is saved.
Refresh and inspect the current state after a conflict;
the browser does not retry a write automatically. A bounded bridge timeout can
occur after a state commit, so inspect the saved run before submitting again.

Approval pauses at `qc_apply`. Run the next computation explicitly in R:

```r
scAgentKit::sc_run_resume("/durable/path/to/project")
```

The QC pane supports QC preview and decisions. The unified page also supports
typed cluster annotation corrections, approval/rejection and executed annotation
undo; see [the unified review guide](RUN_REVIEW_QUICKSTART.md). The fixed R subprocess has
no provider configuration and drops common provider API-key environment
variables. It accepts typed JSON data only; the browser cannot provide R code,
an executable, an input path or a remote URL. Exact cell IDs and per-cell QC
measurements stay on this local project/tunnel and are excluded from aggregate
provider payloads.

For an offline real-browser check on a fresh, awaiting-QC fixture:

```sh
node workbench/tests/browser_run_review.mjs --project /private/public-mock-qc-fixture \
  --fixture-script /private/frozen-offline-fixture.R \
  --output /private/new-browser-report --r-library /private/new-library
```

The unified driver uses a frozen public/mock fixture, separate project copies
and ephemeral localhost ports. It checks stale decisions, restart recovery,
annotation corrections and undo, and invokes the operator-supplied fixed offline
Rscript for explicit resume and output verification outside HTTP. It preserves
the source fixture and rejects external browser requests. On macOS it defaults to the installed
ChatGPT Playwright module and Google Chrome; pass `--playwright` and `--chrome`
for explicitly installed alternatives. This test does not establish performance
on another OS or a shared HPC filesystem.
