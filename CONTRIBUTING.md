# Contributing to scAgentKit

scAgentKit is a research package under active development. Read the
[development contract](AGENTS.md) before changing public interfaces or project
formats. Installation instructions are in the [user guide](docs/user/INSTALL.md).

## Repository layout

| Directory | Purpose |
| --- | --- |
| `R/`, `man/`, `vignettes/` | R implementation, function reference and package vignette |
| `inst/examples/` | Installed tutorials for users |
| `inst/workbench/` | Canonical Python service and browser assets |
| `workbench/` | Service documentation, tests and symbolic links to the installed runtime |
| `docs/user/` | Installation, workflow and run controls |
| `docs/dev/` | Implementation contracts and recorded development checks |
| `docs/research/` | Research scope, evaluation protocol and milestones |
| `docs/archive/` | Earlier designs, protocols and translations |
| `dev/` | Focused development fixtures and manual smoke drivers |
| `tests/`, `benchmark/`, `tools/` | Package tests, evaluation resources and maintenance tools |

Keep the `workbench/` symbolic links. Edit runtime code in `inst/workbench/`.
Files under `benchmark/evaluation-v1/` are frozen scientific evidence; do not
edit or remove them during maintenance.

## Development checks

Install the required dependencies and the declared `agentomicsCore` release.
Package checks also use `testthat`, `knitr`, `rmarkdown` and `httr2`. Python 3.9+
is required for the workbench; its runtime uses the standard library. CI uses
Node 20 for JavaScript tests.

Build and check from a temporary copy. The package's `configure` script
generates a runtime manifest, so this keeps generated files out of the checkout.

```sh
scagentkit_stage=$(mktemp -d)
cp -R "$PWD" "$scagentkit_stage/scAgentKit"
(
  cd "$scagentkit_stage"
  R CMD build scAgentKit
  _R_CHECK_FORCE_SUGGESTS_=false R CMD check --no-manual scAgentKit_*.tar.gz
)
```

From the repository root, run the workbench and offline contract suites:

```sh
python3 -B -m unittest discover -s workbench/tests -p 'test_*.py' -v
python3 -B -m unittest discover -s benchmark/tests -p 'test_*.py' -v
python3 -B -m unittest discover -s benchmark/evaluation-v1 -p 'test_*.py' -v
```

```sh
set -e
for test_file in workbench/tests/test_*.mjs workbench/tests/*_dom.cjs; do
  node "$test_file"
done
```

The [installed-runtime contract](docs/dev/OFFLINE_COMPARISON_CONTRACT.md)
checks an installed archive outside its checkout. Browser acceptance and
real-provider experiments have separate fixtures and requirements. Report
which checks ran, including failures and skips; do not count missing-data or
missing-dependency skips as passes. Optional scientific methods must satisfy
their [runtime contracts](docs/LINUX_RUNTIME_SUPPORT.md).

## Documentation and examples

Write maintained documentation in English. Describe current behavior with
specific inputs, outputs and examples. Keep setup instructions in the
installation guide, user tasks in the user guides, implementation details in
developer references, and prospective experiments in research protocols.
Link to the authoritative explanation instead of copying it into several pages.

Distinguish implemented features, completed checks and planned experiments.
Give each scientific claim a source or an explicit limitation. Historical
reports retain their original scope and revision; they do not establish the
behavior of later versions. Add a concise entry to [NEWS.md](NEWS.md) for
user-visible changes.

Examples should identify their input, dependencies, entry point and expected
output. State whether they make external model calls. Keep scripted fixture
approvals separate from instructions for reviewing a study. Explain unfamiliar
parameters in terms of the analysis rather than the implementation history.

## Reproducible reports

For an analysis or benchmark, retain the source commit, package versions,
`sessionInfo()`, input and reference provenance, seeds, model identifiers,
reviewed parameters and output records. Record unavailable information as
unknown. A software test, reference match or agreement score is not by itself
evidence of biological accuracy.

Use [CITATION.cff](CITATION.cff) or `citation("scAgentKit")` to cite the software.
Also cite the methods, datasets and reference resources used in the study,
including [ACT](docs/ACT_LOCAL_REFERENCE.md) when applicable.
