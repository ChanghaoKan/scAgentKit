# Reviewed-workflow development evaluation

There is one counts-to-result engine. All current workflow experiments use:

```sh
Rscript benchmark/evaluation-v1/run_workflow.R INPUT.rds NEW_OUTPUT PRIVATE_R_LIBRARY after-no-diagnostics REFERENCE.tsv pbmc3k
```

Arguments name the frozen counts/Seurat input, a **new** output directory, the
installed library, a registered variant, a pinned local reference and dataset
(`pbmc3k`, `ifnb` or `baron`). The script uses `sc_analyze()` and three explicit
`sc_review()` approvals; annotation is an Unknown-only software control with
provider=NULL and budget=0. Raw author/reference labels are not read as planning
inputs. Study inference and model A/B execution are separate unpassed gates.

`evaluation-v1/prepare_inputs.R` and `freeze_references.R` describe the public
input/reference preparation. Existing frozen inputs may be reused read-only;
outputs must be new. `evaluation-v1/evaluate.py`, `posthoc_report.py` and the
hash-bound status audit keep denominators, abstention and failures explicit.
The original results and reports remain historical evidence, not recomputed truth.

The older AgentSeurat benchmark drivers and old PBMC preparation drivers were
removed from the development tree after shared-kernel parity checks. They are
available in Git/published history; repository code is updated to the one project
path rather than retained as a compatibility facade. No old analysis environment
or user migration burden is assumed.

- [Protocol and original frozen outcomes](evaluation-v1/README.md)
- [Registered evaluation boundaries](../docs/EVALUATION_PROTOCOL_V1.md)
- [Installed package/runtime contract](contracts/installed_package_smoke.R)
- [Standalone offline comparison contract](contracts/compare_offline.py)
- [Local performance evidence](LOCAL_PERFORMANCE.md)

Do not overwrite baseline data, CSVs, metrics or logs. A new implementation hash
requires new development projects; never edit saved hashes/approvals. No provider
fee, merge or release is authorized by these scripts.
