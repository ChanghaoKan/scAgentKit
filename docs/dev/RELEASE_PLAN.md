# Release gates: 0.8.0 and historical 0.6.0

## Current authorized 0.8.0 release

0.8.0 is an experimental breaking release. It removes 36 function exports and
AgentSeurat at the previously stated earliest removal milestone. Read
[API/type changes](API_CONSOLIDATION.md) and [release notes](RELEASE_NOTES_0.8.0.md).
The standard raw-count workflow requires strategy, measured-clustering and
annotation approvals; a completed workflow does not establish biological accuracy.

1. Complete local full tests, archive and installed-browser checks. Report all
   failures and skips. Merge dependencies only after their exact-head CI passes;
   preserve issue commits. Verify the consolidation tree against its final tested head.
2. Require all four workflows for the final 0.8.0 PR head to succeed. Merge the
   dependent base and final PR without skipping checks. A changed tree needs
   affected verification again. Never move an existing tag or overwrite old assets.
3. Create fresh `v0.8.0` at the actual merge commit. Dispatch release-archive for
   that tag. It verifies ancestry/two-parent merge and uses untouched `R CMD build`
   output with SHA256SUMS and build-receipt.json. Do not edit tar members/metadata.
4. Its clean-install job must anonymously download the public Release asset in
   the pinned rocker container, verify bytes/tag against the build and start with
   empty R libraries/no restored package cache. Execute the installation and offline
   example blocks extracted verbatim from the archive's README. Keep full logs,
   dependency versions, checksums and source receipts. PR-artifact preflight alone
   does not satisfy this public-download acceptance.
5. Publication is incomplete until this post-publication job passes. No paid
   model is used. Old projects keep their original evidence and environment;
   rebuild from original inputs in a new directory and approve again. Never alter
   saved authority/hashes/checkpoints to force resume.

## Historical v0.6.0 procedure (unchanged record)

v0.6.0 was published on 2026-10-18. Its tag and assets are historical; this
document records its gates and informs a future, separately authorized release.
Development edits do not authorize moving that tag, republishing its assets,
deleting the older v0.5.1 draft, or merging/publishing the current branch.

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

## Breaking changes and installation receipt

Future Release text must lead with a visible **Breaking changes** section:
which saved implementations are incompatible, exact-environment restoration or
new-project review, changed schemas and defaults, and the retained legacy API
window. Never present a raw confidence score as calibrated probability or claim
that citation validity proves a biological label. Use the local release-notes
file as the reviewed text; editing it does not edit an existing public Release.

The workflow already automatically writes `clean-install-receipt.json` from
`tools/release/clean-install.R` and retains it with complete install/example logs
in `clean-release-install-logs`, including failure logs. Public Release asset
promotion is a separate step; artifact generation alone is not an accepted
installation or a published asset. A future automatic receipt publisher should
run only after successful public-mode installation, match the tag/merge commit
and trusted archive SHA256, require initial empty libraries/no cache reuse and
successful offline/runtime checks, and upload only a sanitized summary. Failed
or pending runs must not publish a successful receipt; raw logs, credentials and
personal paths must not become Release assets. No such publisher is executed by
this development revision.

CI attribution must name the actual event and commit: installed-runtime-contract
ran on PR head `b51acbb042265713964b24716ac714df8b409d47`; its source tree equals
merge `ad9ec2417e5fbb259d1c4cbf59313d5aa18a92ea`. Push CI on that merge ran
R CMD check and workbench tests. The tag-dispatched release workflow separately
built and accepted the public asset. These are different runs, not three push
checks on the merge.

## Saved-project compatibility

The implementation hash includes selected coordinator functions and dependency
versions. A mismatch rejects resume/approval, including resume of completed runs.
Keep the original environment and exact package build to continue an old
project, or start a new project directory from the original input and review it
again. Never alter hashes or authority/checkpoints to bypass this boundary.
Author-label metadata priors remain off by default. See [NEWS](../../NEWS.md).

The historical 0.6.x/0.7.x retention window ends at the separately documented
0.8.0 removal milestone above. Historical tags and assets remain unchanged.
