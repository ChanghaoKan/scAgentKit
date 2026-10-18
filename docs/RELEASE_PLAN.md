# Release preparation: 0.5.1

The selected package version is **0.5.1**, with planned tag **v0.5.1** and
asset **scAgentKit_0.5.1.tar.gz**. This document prepares a release; it does not
create a tag, publish an asset or claim the download already exists.

The only user installation route is the versioned source archive attached to
[the planned GitHub Release](https://github.com/ChanghaoKan/scAgentKit/releases/tag/v0.5.1).
Its eventual asset URL is
`https://github.com/ChanghaoKan/scAgentKit/releases/download/v0.5.1/scAgentKit_0.5.1.tar.gz`.
Use `remotes::install_local()` and a private target library as shown in the
[README](../README.md#installation). Do not silently substitute mutable `main`,
an older tag or a source checkout when the asset is unavailable.

Before publication, the release owner must:

1. Resolve the final approved commit and verify its clean source tree, retained
   exports, runtime manifest, package/citation version and README installation.
2. Build the source archive from that exact commit in a clean staging directory;
   retain the commit and archive SHA256 together. Do not package an unrelated
   dirty checkout or add patient data, credentials, local logs or private paths.
3. Install the archive using the README entry into a fresh target library, record
   the dependency libraries and `sessionInfo()`, and complete the installed
   review/background/result-reopening controls. Existing dependency reuse must
   be disclosed; it is not a hermetic installation claim.
4. Finish the final full R tests, Python/Node suites, static documentation checks
   and local full `R CMD check`; report skips and untested platforms explicitly.
5. Only after the release owner's publication approval, create `v0.5.1` at that
   final commit and attach the verified archive plus a SHA256 text receipt to a
   GitHub Release. Recheck that the public download bytes match the approved hash.

This local repair task is authorized to prepare and validate these materials.
It does not push, merge, create a tag or publish a Release. Any historical
installation commands in older NEWS entries describe their original releases;
they are not current installation instructions.
