"""Read an untouched R build archive; public mode downloads without credentials."""
import argparse
import hashlib
import json
from pathlib import Path
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
    api = "https://api.github.com/repos/ChanghaoKan/scAgentKit/"
    release = json.loads(read(api + "releases/tags/" + tag))
    assert not release["draft"] and release["tag_name"] == tag
    obj = json.loads(read(api + "git/ref/tags/" + tag))["object"]
    while obj["type"] == "tag":
        obj = json.loads(read(api + "git/tags/" + obj["sha"]))["object"]
    assert obj["type"] == "commit" and obj["sha"] == args.commit

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
