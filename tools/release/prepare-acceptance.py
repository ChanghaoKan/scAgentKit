"""Read an untouched R build archive; public mode downloads without credentials."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("mode", choices=["artifact", "public"])
parser.add_argument("commit")
parser.add_argument("sha256", help="Trusted SHA256 from this workflow's build job")
args = parser.parse_args()
version = "0.6.0"
tag = "v" + version
name = "scAgentKit_" + version + ".tar.gz"

def read(url):
    request = urllib.request.Request(url, headers={"User-Agent": "scAgentKit-public-release-check"})
    with urllib.request.urlopen(request, timeout=180) as response:
        assert response.status == 200
        return response.read()

if args.mode == "public":
    base = "https://github.com/ChanghaoKan/scAgentKit/releases/download/" + tag + "/"
    for asset in [name, "SHA256SUMS"]:
        Path(asset).write_bytes(read(base + asset))
    # Public smart HTTP avoids the unrelated anonymous REST API quota. Explicitly
    # clear checkout's auth headers/helpers; both downloads and ref reads are public.
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="/bin/false")
    output = subprocess.check_output(["git", "-c", "http.extraheader=", "-c",
        "http.https://github.com/.extraheader=", "-c", "credential.helper=",
        "ls-remote", "https://github.com/ChanghaoKan/scAgentKit.git",
        "refs/tags/" + tag, "refs/tags/" + tag + "^{}"], env=env, text=True)
    refs = {ref: sha for sha, ref in (line.split() for line in output.splitlines())}
    assert refs.get("refs/tags/" + tag + "^{}", refs.get("refs/tags/" + tag)) == args.commit

sha = hashlib.sha256(Path(name).read_bytes()).hexdigest()
assert sha == args.sha256, "Downloaded bytes differ from this run's accepted build"
assert Path("SHA256SUMS").read_text().split() == [sha, name]
with tarfile.open(name) as archive:
    description = archive.extractfile("scAgentKit/DESCRIPTION").read().decode()
    assert "Version: " + version + "\n" in description
    assert "Packaged:" in description, "Use ordinary, unmodified R CMD build output"
    readme = archive.extractfile("scAgentKit/README.md").read().decode()

def block(heading):
    section = readme.split(heading, 1)[1]
    return section.split("```r\n", 1)[1].split("```", 1)[0]

Path("README-install.R").write_text(block("## Installation"))
Path("README-offline.R").write_text(block("## Offline installation check"))
receipt = dict(status="passed", mode=args.mode, anonymous_public_download=args.mode == "public",
               tag=tag, source_commit=args.commit, sha256=sha, checksum_matches=True,
               archive_modified=False, build_sha256_matches=True,
               readme_commands_extracted_verbatim=True)
Path("download-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt))
