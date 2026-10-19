# Development resources

Developer acceptance drivers, frozen environment/release tooling and retired API inventories are repository resources, not installed runtime requirements. The runtime manifest builder `tools/build-workbench-manifest.R` stays in the source archive because configure invokes it. `dev/` and `tools/{acceptance,release,environment}` are excluded from the R source archive.

The historical `api-contract.json` records the superseded public API. Namespace tests retain the exact frozen retired-name assertions without installing that inventory as a runtime contract. Current exports are defined in NAMESPACE and installed help.
