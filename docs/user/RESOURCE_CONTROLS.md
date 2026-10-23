# Request capacity and local storage

## Request size

For a new project,
`sc_start(..., react=list(mode="auto", max_payload_bytes=400000L))`
sets the maximum request or conversation size in UTF-8 bytes. The default is
`max_payload_bytes="unlimited"`; an explicit limit must be an integer from
1 to 1,000,000. Saved projects retain their original setting.

Strategy scan summaries use the space left after the other prompt and evidence
content, with a source hash and an inventory of omitted blocks. The complete
request must fit the limit. Oversized requests fall back to local review rather
than silently truncating evidence.

This setting limits application request bytes. Provider token and context
limits still apply, and a larger allowance does not guarantee that a model can
accept the request. Provider-specific context admission is not yet implemented.
Study free text and individual tool responses have separate privacy and size
limits. Provider usage and fees are recorded after calls, without a monetary cap.

## Timeouts and tool pagination

`model_timeout=NULL` derives an outer worker deadline from the saved ReAct
limits and provider timeout, plus time for startup and finalization. An explicit
`model_timeout` can choose 1–86,400 seconds. Automatic values
are capped at 24 hours; unusually large custom policies may still hit that cap.
Inner cluster, tool and provider deadlines remain active. An uncertain delivery
is never automatically resent.

Marker and ACT tools can continue with the returned `next_offset`, keeping the
same query and saved input. Each page records its offset, available count,
returned count and whether it is partial. The full evidence remains local.
Per-call sizes and per-session step limits apply to each request. A later
marker page has the same citation requirements as the first page.

Refinement ends when a final draft passes validation. Repeated tool responses
that supply no new evidence cause a return to the baseline draft. Both outcomes
still require the researcher's review and approval.

## Measure storage and archive a project

The review page has **Project storage and archiving**, independent of optional model suggestions, with **Measure local storage**. It reads local file sizes on
request, does not follow symbolic links, and never removes files. A bounded
scan may report a partial lower bound. Sizes are logical file sizes, not physical
allocated space or available disk space. To set an optional project allowance,
see [disk limits](TRIAL_CONTROLS.md#set-a-project-disk-allowance).

To archive, finish or stop active workers first. Copy the whole project to the
archive destination, including `project-format.json` and `state.rds`, preserve
its layout, and verify copied file hashes before
considering the copy complete. Keep original inputs and a record of the R,
package and dependency environment separately. Retain the source project until
the archive is verified and you explicitly decide to remove it. A review ZIP is
not a substitute for a complete scientific project archive. Copying or restoring
a backup does not upgrade its format; open it with its matching software environment.
Archival is a manual operation; the application does not provide automated
archiving or journal segmentation.

### Verify the copy

1. Stop local and model workers at their safe boundaries. Resolve uncertain
   provider delivery before considering the archive settled.
2. Preserve the complete project and the original package/dependency environment.
   `output/audit.json` contains the verified checkpoint index and loaded package
   versions; it is an index, not an archive of the installed environment.
3. Generate a whole-directory checksum manifest outside the stopped project,
   copy both, and verify every listed file at the destination. For GNU/Linux:

   ```sh
   cd /path/to/stopped-project
   find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > ../project-files.sha256
   # After copying, from the copied project directory:
   sha256sum -c ../project-files.sha256
   ```

   This does not follow symlinks. Preserve and inspect links separately; do not
   treat skipped external targets as archived. Protect this manifest with the
   archive and retain the source until verification succeeds.
4. Open the copy with its matching environment. Original-path bindings remain
   meaningful. Rebinding terminal browser-job metadata after same-path restore
   is an explicit operation described in the workbench restore guide; it does
   not authorize retrying uncertain requests or unlocking a live worker.

No new archive service or checkpoint-pruning process is introduced. The stable
manual stop/copy/hash procedure remains explicit.
