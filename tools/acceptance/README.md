# Installed-archive real-browser acceptance

This harness opens **actual Chrome**, calls the installed public `sc_start()` entry,
uses the installed Python service and real R worker, and makes every scientific
choice through the webpage. It never sources repository implementation files,
stubs browser responses, or posts scientific requests outside the browser.

Build and install the frozen source archive into a **private new library** first.
Use existing approved dependencies; the harness installs or downloads nothing.
For example, from the repository root:

```sh
node tools/acceptance/installed-browser.mjs \
  --archive /absolute/path/scAgentKit_VERSION.tar.gz \
  --r-library /absolute/path/private-installed-library \
  --dependency-library /absolute/path/existing-approved-dependencies \
  --output /absolute/path/new-private-evidence-directory
```

Optional arguments are `--chrome`, `--playwright`, and `--rscript`. Defaults use
existing Mac Chrome, the desktop app's bundled Playwright, and `Rscript`. A local
loopback server and Chrome subprocesses must be permitted by the execution
sandbox. Use a **new output directory on every attempt**; failed evidence is
preserved. The supplied archive and installed runtime/function manifest must
match (named entries compared independently of platform ordering).

The public SeuratObject `pbmc_small` object is bundled locally. Two synthetic
sample identifiers exercise grouped QC. The default raw analysis entry ignores
its old processed clustering; this is a software control, not a biological
accuracy experiment. All final annotations deliberately remain `Unknown` with
low qualitative confidence. Provider credential variables are stripped; model
suggestions are off; all non-local browser requests are blocked and fail the
acceptance. No data or paid model is requested.

The checks require the main entry's sample-aware MAD panel, the explicit
`computed_top50` 0.80 policy, multiple resolution candidates, actual measured
cluster tree, author selection of a scanned resolution, incomplete annotation
draft rejection and reload recovery, separate complete-proposal saving and
approval, actual completion, and reopening through the installed public entry.
Two real pointer clicks verify busy-state suppression of duplicate execution.
R independently checks output membership, unresolved labels, saved output and
exactly-once annotation/finalize execution; actual worker PIDs and installed
bridge paths are recorded.

`browser-report.json` records assertions and actual job ownership; screenshots,
R setup/verification/reopen logs, project authority/checkpoints, and browser
request bindings remain in the private output directory. No CSRF headers or
credentials are saved. The service PID created for this private project is
terminated on exit. A red run is not a passed acceptance; inspect its report and
preserve it before fixing the harness or product and rerunning in a fresh folder.
