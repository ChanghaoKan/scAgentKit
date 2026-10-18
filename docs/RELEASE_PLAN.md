# Release gates: 0.6.0

The target is **v0.6.0**, package **0.6.0**, and the GitHub Release asset
**scAgentKit_0.6.0.tar.gz**. The unpublished previous draft and its historical
assets are retained; its manually normalized archive must not be published.

1. Push the revision branch and create a draft PR. Its description must show the
   confidence fixture calculation: reference overlap 0.85 (weight 0.3), median
   marker specificity 0.85 (weight 0.3), non-hallucination 0 (weight 0.2), and
   proportion plausibility 1 (weight 0.2). The pct differences are 0.90 and 0.80,
   so their median is 0.85, not 0.9. The hand sum is
   `0.3*0.85 + 0.3*0.85 + 0.2*0 + 0.2*1 = 0.710`.
2. Require every remote CI workflow at the exact final head to pass. Report all
   failures and skips; fix failures in separate scoped commits and rerun. Keep
   the per-issue history when merging. A moved main or changed code requires
   affected verification again; never bypass a check.
3. After merge, create `v0.6.0` at the actual merged commit. Dispatch the
   `release-archive` workflow with that tag. CI checks out and verifies the tag,
   uses ordinary `R CMD build`, and publishes those exact archive bytes with
   `SHA256SUMS` and a sanitized build receipt. Do not rewrite tar metadata,
   DESCRIPTION, or generated members after the build.
4. The same workflow's acceptance job uses a fresh official `rocker/r-ver`
   container. It verifies the selected R libraries initially contain no
   non-base/recommended packages, anonymously downloads the public Release
   archive and checksum, and executes the README installation block verbatim.
   No dependency library or R package cache is mounted or restored. It then
   runs the installed offline example, basic load/runtime/entry checks, and
   records the installed package versions. Full installation and example logs
   are retained as CI artifacts even on failure.
5. Only successful public download, checksum, fresh dependency/package install
   and offline-example acceptance completes installation audit item #13. A
   published Release with a failed or pending acceptance job is incomplete.

PR runs exercise the same clean-container installer using the PR build artifact
before merge; that is a preflight and does not replace public-download acceptance.
Windows, real-browser and development Docker-image support are not implied by
this Linux release acceptance.

## Saved-project compatibility

The implementation hash includes selected coordinator functions and dependency
versions. A mismatch rejects resume/approval, including resume of completed runs.
Keep the original environment and exact package build to continue an old
project, or start a new project directory from the original input and review it
again. Never alter hashes or authority/checkpoints to bypass this boundary.
Author-label metadata priors remain off by default. See [NEWS](../NEWS.md).

Legacy APIs remain exported through 0.6.x and 0.7.x, with removal planned no
earlier than 0.8.0 and subject to a migration notice.
