# Restoring an exact project environment

A saved project is bound to its implementation hash, dependency versions and
approved artifacts. Restore its original environment, or create a new project
from the original input and review it again. Do not edit hashes, approvals or
checkpoints. No cross-version migration is promised. A new version number alone
neither proves nor disproves compatibility.

## Evidence-backed v0.6.0 R source recipe

`tools/environment/v0.6.0-linux.json` freezes the 140 non-base/recommended packages
(including scAgentKit and remotes) actually installed in the successful public
v0.6.0 empty-library acceptance. It records the original logged fixed-date Posit
CRAN snapshot URLs, the initial CRAN remotes URL, the public scAgentKit archive,
and agentomicsCore's exact GitHub commit. BH uses the exact-version official
CRAN source archive after the snapshot download stalled; both the original CI
URL and actual source URL and fallback reason are retained in the lock. Their
archive bytes are not asserted equal. Every archive was subsequently fetched
and its SHA256 and DESCRIPTION package/version verified. These hashes attest to
the newly verified source bytes; the original CI did not hash all dependency
archives, so they cannot prove those earlier dependency bytes were identical.
The receipt and full CI log links are in the lock.

R is exactly 4.5.2 in the digest-pinned official Rocker image recorded in the
lock. The lock also records all 29 base/recommended package versions printed by the
original CI, including Matrix 1.7-4; the installer checks these exact versions.
The image supplies their original installed library and OS base. The source lock is
not a complete OS lock: the original apt build dependencies were not pinned, and
the original acceptance did not record Python's exact executable/package version.
The lock additionally pins official python.org Python 3.9.6 and CRAN R 4.5.2
source archives by SHA256, with their version files independently inspected.
These source archives are not installed by the verification tools. Python 3.9.6
is the existing Mac runtime used for source auditing; browser acceptance is
reported separately and must name its actual interpreter. The
python.org source is an explicit reconstruction source, not a claim that Apple's build or the historical Linux CI used byte-identical executables.
The browser needs Python >=3.9 and uses its standard library; an exact Python
runtime must be preserved separately for an original project's full environment.
Do not claim the original full OS/Python environment can be reconstructed from
this R source lock alone. Source/hash auditing here used the existing Mac Python
3.9.6; it did not install Python or rebuild the Linux container.

There are no Bioconductor packages in this verified base recipe. Optional Bioc
methods are outside this lock: preserve their original Bioconductor release,
package versions, source URLs/hashes and system dependencies before using them.
Do not install the current Bioc release and call it an exact restoration.

### Verify and prepare without installation

From a checkout containing these tools, using an existing Python 3.9+:

```sh
python3 tools/environment/fetch.py /durable/source-cache --runtimes
python3 tools/environment/audit.py /durable/source-cache
python3 tools/environment/test_contract.py
```

Fetching checks cached bytes too and rejects mismatches. Auditing reads archive
DESCRIPTION files without extraction, checks identities and a complete local
Depends/Imports/LinkingTo dependency order. Sources remain separate from the
repository. No model, reference-data download or credential is needed.

### Restore in the preserved Linux environment

Use the digest-pinned official image in the lock, with its required existing
system build libraries. The earlier successful build used make, gcc/g++, gfortran,
libcurl/OpenSSL/XML and the image's standard build stack; consult the linked
original workflow for the full apt list. OS build-library pinning is not claimed.
Mount this checkout and the verified source cache, use an empty target R library,
and run:

```sh
python3 tools/environment/audit.py /durable/source-cache
Rscript --vanilla tools/environment/restore.R /durable/source-cache /durable/restored-library
```

The installer refuses another R version, a nonempty target, or non-base packages
in R's base library. It isolates user/site libraries and startup files, invokes
only `R CMD INSTALL` on local sources in dependency order, checks exact installed
versions, loads the package and runs the installed offline software example.
It does not resolve or download dependencies. Run under disabled outbound network
when enforcing a network-free build, because arbitrary upstream package configure
scripts are executable code. Never use a restored library as evidence that the
original saved implementation hash matches: open/inspect the preserved project
with the restored package and let its normal integrity checks decide.

This revision verified all archive bytes/identities and dependency ordering;
it did not rerun the whole container restore on this Mac (Docker is unavailable).
The cited v0.6.0 acceptance is historical evidence for those versions and the
installed offline example, not a claim that this new restore script was exercised
end to end. A fresh container build must be recorded before claiming this recipe
itself fully rebuilt the original environment.

## Preserve future and optional environments

Keep the exact R/Python executables or immutable environment image, package source
archives/hashes, package versions and GitHub RemoteSha, OS/build libraries,
`sessionInfo()`, `python3 --version`, original input and scAgentKit archive/commit.
Preserve optional CRAN/Bioc/GitHub dependencies as well. Copy the original project
before restoring; never replace its authoritative Seurat/checkpoints with
convenience exports. If restoration cannot reproduce its saved hash, stop and
use a new project with fresh review rather than weakening the checks.

To rebuild the explicit Python source option, fetch with `--runtimes`, verify its
locked SHA256, and use the official source build in a separate user prefix
(`./configure --prefix=/durable/python-3.9.6`, `make`, `make install`). Record
compiler, OpenSSL and other linked system libraries and test the browser again.
This optional runtime build was not executed here and is not a substitute for
preserving the original Python executable and its system dependencies.
