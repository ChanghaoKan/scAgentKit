# Development contract

scAgentKit is a pre-1.0 internal research product. Keep current names and
structures aligned with their actual behavior. Decisions follow call paths,
not keyword matches.

1. Do not provide backward compatibility. Remove old parameters, schemas,
   project formats, deprecated aliases and compatibility shims. Do not add
   `legacy`, `compat` or `deprecated` branches or options such as `legacy = TRUE`.
2. Model costs have no monetary cap and are recorded only after calls
   (posthoc). Do not add budgets, reservations or monetary limits. Retain step,
   time and byte limits.
3. Reject old projects at the project-format gate. Do not write migrations.
   Check the format before writing any project files or acquiring write locks.
4. Documentation describes current behavior. Do not add statements such as
   "remains unchanged" or "preserved for compatibility". Record changes in
   `NEWS.md`.
5. The only exception is `benchmark/evaluation-v1/`: its frozen inputs, results
   and reports are scientific evidence. Do not modify or delete anything there.
6. If a plan or report under `docs/dev/` conflicts with this contract or the
   current user task, follow this contract and the current user task.
7. When uncertain, do not delete and do not add compatibility. Keep the current
   implementation, describe its location, behavior and suggested resolution in
   the pull request's "待确认" section, and continue independent work.

## Decision criteria

- Delete code that serves only old parameters, schemas or project formats and
  has no current entry-point callers, based on the call graph.
- Rename or correct comments when a name contains `legacy` but implements a
  current function.
- List an item under "待确认" if removing it would change a public interface or
  scientific behavior, or its callers cannot be established.

## Validation and delivery

Do not change scientific analysis thresholds, run paid experiments or redeem
usage resets during contract cleanup. Keep the `workbench/` symbolic links.
Perform phases 1 through 5 in order on one branch, with separate commits whose
subjects start with `阶段 N：` (phase 5 may use two commits). Validate each phase
with R CMD check and the workbench suites on that phase's exact source, record
its commit and `legacy|deprecat` match count under `R` and `inst/workbench`, and
open one draft pull request. Do not merge it.
