# Request capacity and local storage

For a new project, `sc_start(..., react=list(mode="auto", max_payload_bytes=400000L))`
sets a bounded request/conversation size. New projects default to `max_payload_bytes="unlimited"`, disabling the application
byte quota. An explicit finite quota accepts 1–1,000,000 UTF-8 bytes. Strategy scan
summaries use the space remaining after the actual other prompt/evidence bytes,
retaining a source hash and an inventory of omitted split blocks. Other evidence and prompts
must fit the complete request. An oversized request falls back to local review;
it is never silently cut to fit. Saved projects retain their original settings.

This is an application resource guard, not a provider token/context limit and
not a spending cap. A larger allowance does not guarantee that a model can
accept the request. Provider-specific context admission is not yet implemented.
Study free text and individual tool responses retain separate privacy/resource
limits. Fees use post-call accounting across entry points; the deprecated `budget` argument does not limit dispatch.

`model_timeout=NULL` derives an outer worker deadline from the saved ReAct
limits and provider timeout, plus startup/finalization allowance. It avoids the
old unconditional 300-second outer cutoff. An explicit `model_timeout` can
choose 1–86,400 seconds, including a shorter operator limit. Automatic values
are capped at 24 hours; unusually large custom policies may still hit that cap.
Inner cluster, tool and provider deadlines remain active. An uncertain delivery
is never automatically resent.

Marker and ACT tools can continue with the returned `next_offset`, keeping the
same query and saved input. Each page records its offset, available count,
returned count and whether it is partial. The full evidence remains local.
The existing per-call sizes and per-session step limits still apply. A later
marker page has the same citation requirements as the first page.

The review page has **Measure local storage**. It reads local file sizes on
request, does not follow symbolic links, and never removes files. A bounded
scan may report a partial lower bound. Sizes are logical file sizes, not physical
allocated space or a guarantee of available disk space.

To archive, finish or stop active workers first. Copy the whole project to the
archive destination, preserve its layout, and verify copied file hashes before
considering the copy complete. Keep original inputs and a record of the R,
package and dependency environment separately. Retain the source project until
the archive is verified and you explicitly decide to remove it. A review ZIP is
not a substitute for a complete scientific project archive. Automated archival,
journal segmentation and review-bundle/display limit configuration are not
implemented by this checkpoint.
