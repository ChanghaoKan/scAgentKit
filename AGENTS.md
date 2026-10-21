# Development contract

scAgentKit is a pre-1.0 research package. Keep names, documentation and public
interfaces aligned with their actual behavior. Inspect call paths before
removing code or changing an interface.

## Scientific and project contracts

1. Do not add compatibility shims, deprecated aliases, project migrations or
   support for superseded schemas. Validate the project format before any write
   or write lock. Open older projects with their original environment.
2. Record model usage and costs after calls. Do not add monetary caps,
   reservations or budget modes. Retain the step, time and byte limits.
3. Do not change scientific thresholds or analysis methods during maintenance.
   Record unresolved interface or scientific questions and continue independent
   work when their callers or effects cannot be established.
4. Files under `benchmark/evaluation-v1/` are frozen scientific evidence. Do not
   edit or delete them. Preserve the workbench symbolic links; canonical runtime
   files are under `inst/workbench/`.
5. Paid provider experiments require explicit user authorization.

## Documentation and repository maintenance

Write maintained documentation, user-visible messages and new commit subjects
in English. Preserve Unicode test inputs and original scientific data verbatim.
Keep historical reports at their recorded Git revisions, with immutable links
from the archive index. Describe current behavior and record changes in NEWS.

Follow the current user task when older plans or reports conflict with it.
Do not rewrite shared Git history to change historical commit messages.
Use short-lived branches for active work. Delete merged remote branches after
verification; preserve unmerged work with a recorded archive tag before removing
its branch. Keep main as the publication branch.

## Validation and release delivery

Run checks appropriate to the change and record failures, skips and incomplete
runs accurately. Build and install from a temporary source copy because configure
generates the runtime manifest. Regenerate the tracked manifest deliberately
when runtime files or the selected R functions change.

Use a distinct package version and tag for each release. Publish the exact
built archive with its checksum and source record after CI, clean installation
and the offline workflow succeed. Do not replace an existing release archive.
Follow the user's authorized delivery scope for commits, pushes and merges.
