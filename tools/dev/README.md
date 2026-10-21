# Development resources

| Resource | Purpose |
| --- | --- |
| [Examples](examples/README.md) | Synthetic review drivers and a public-data workflow |
| [Provider smoke driver](smoke/README.md) | Explicitly configured model checks |
| [Acceptance tooling](../acceptance/README.md) | Installed browser validation |
| [Environment restoration](../../docs/dev/ENVIRONMENT_RESTORE.md) | Historical source lock and restoration tools |
| [Developer documentation](../../docs/dev/README.md) | Current implementation and validation references |

Current exports are defined in `NAMESPACE` and installed help. Namespace tests
assert the exclusion of retired exports.

`tools/{dev,acceptance,release,environment}` are excluded from the R
source archive. `tools/build-workbench-manifest.R` is included because the
package's configure script invokes it.
