#!/usr/bin/env python3
"""Rebuild the pinned public MGI lookup snapshot offline; never fetch/query."""
import argparse
import csv
import hashlib
import json
import re
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input-dir', type=Path, required=True, help='Pinned public source files and receipts; no download is performed')
parser.add_argument('--output-dir', type=Path, required=True, help='New directory for rebuilt artifacts')
args = parser.parse_args()
ROOT = args.input_dir.resolve()
OUTPUT = args.output_dir.resolve()
OUTPUT.mkdir(parents=True, exist_ok=True)
PINNED = {
    "HOM_ProteinCoding.rpt": "2bc350fc189dfd68e2caecebaff0f9a3db18959956e5bb3008981635f87f68c9",
    "HMD_HumanPhenotype.rpt": "3caceb612e6c9054a714044589fb3dd960d84f24bff5cdf0bab2b4381358c0a7",
    "Ptprc.html": "5517d1051c1b835df860c1db4ac9fb1645be12ae2366754b4e78a6d246a7bf68",
    "Lyz2.html": "ea32bc30e7087bebb6f00b4fbf979492d2c6781cc6f03d72243eea45070a43df",
    "Adh1.html": "182e6a1ed8e5afb9437af8b21996558a323bf68157f6a19ac005cf86465b85c2",
}
LICENSE_URL = "https://www.informatics.jax.org/mgihome/other/copyright.shtml"
SOURCES = [
    ("mgi_protein_coding", "HOM_ProteinCoding.rpt", "HOM_ProteinCoding.receipt.json",
     "MGI: Mouse Protein Coding Genes having one-to-one Orthology with Human Genes"),
    ("mgi_hmd", "HMD_HumanPhenotype.rpt", "HMD_HumanPhenotype.receipt.json",
     "MGI: Mouse/Human Orthology with Phenotype Annotations (IDs and symbols only)"),
    ("mgi_marker_Ptprc", "Ptprc.html", "Ptprc.get.receipt.json", "MGI Ptprc mouse gene detail: Summary synonyms"),
    ("mgi_marker_Lyz2", "Lyz2.html", "Lyz2.get.receipt.json", "MGI Lyz2 mouse gene detail: Summary synonyms"),
    ("mgi_marker_Adh1", "Adh1.html", "Adh1.get.receipt.json", "MGI Adh1 mouse gene detail: Summary synonyms and homology"),
]
ENTRY_FIELDS = ["mgi_id", "mouse_symbol", "mouse_ncbi_gene_id", "aliases", "human_candidates", "alias_source_id"]
CANDIDATE_FIELDS = ["human_symbol", "human_ncbi_gene_id", "hgnc_id", "relation", "source_id", "source_line", "source_group_id"]


class PublicHTML(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text = []
        self.links = []

    def handle_data(self, text):
        self.text.append(text)

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.links.append(dict(attrs).get("href", ""))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def dump(name, value):
    data = (json.dumps(value, ensure_ascii=True, separators=(",", ":")) + "\n").encode()
    (OUTPUT / name).write_bytes(data)
    return {"file": name, "bytes": len(data), "sha256": sha(data)}


def main():
    for name, expected in PINNED.items():
        assert sha((ROOT / name).read_bytes()) == expected, (name, "source changed")
    sources = []
    for source_id, filename, receipt, title in SOURCES:
        r = json.loads((ROOT / receipt).read_text())
        assert r["sha256"] == PINNED[filename]
        headers = {k.lower(): v for k, v in r.get("get_headers", {}).items()}
        sources.append({"id": source_id, "title": title, "url": r["url"],
                        "last_modified": headers.get("last-modified"),
                        "fetched_at_utc": r["fetched_at_utc"],
                        "sha256": PINNED[filename], "bytes": r["bytes"],
                        "license": "CC-BY-4.0", "license_url": LICENSE_URL})

    by_id = {}
    symbol_ids = {}
    human_ncbi_ids = {}
    for line, row in enumerate(csv.reader((ROOT / "HMD_HumanPhenotype.rpt").open(), delimiter="\t"), 1):
        assert len(row) == 6 and row[5] == "", (line, "unexpected HMD fields")
        human_symbol, human_id, mouse_symbol, mgi_id = row[:4]
        assert re.fullmatch(r"MGI:[1-9][0-9]*", mgi_id)
        assert re.fullmatch(r"[1-9][0-9]*", human_id)
        assert mouse_symbol and human_symbol and len(mouse_symbol) < 128 and len(human_symbol) < 128
        e = by_id.setdefault(mgi_id, {"mgi_id": mgi_id, "mouse_symbol": mouse_symbol,
                                  "mouse_ncbi_gene_id": None, "aliases": [],
                                  "human_candidates": {}, "alias_source_id": None})
        assert e["mouse_symbol"] == mouse_symbol, (mgi_id, "conflicting mouse symbol")
        assert symbol_ids.setdefault(mouse_symbol, mgi_id) == mgi_id
        assert human_ncbi_ids.setdefault(human_symbol, human_id) == human_id
        c = {"human_symbol": human_symbol, "human_ncbi_gene_id": human_id,
             "hgnc_id": None, "relation": "homology_group_candidate",
             "source_id": "mgi_hmd", "source_line": line, "source_group_id": None}
        assert human_symbol not in e["human_candidates"], (line, "duplicate HMD pair")
        e["human_candidates"][human_symbol] = c
    assert len(by_id) == 20183

    n_one_to_one = 0
    mouse_identifiers = {}
    for line, row in enumerate(csv.reader((ROOT / "HOM_ProteinCoding.rpt").open(), delimiter="\t"), 1):
        assert len(row) == 6, (line, "unexpected protein coding fields")
        mgi_id, mouse_symbol, mouse_id, hgnc_id, human_symbol, human_id = row
        assert re.fullmatch(r"HGNC:[1-9][0-9]*", hgnc_id)
        assert re.fullmatch(r"[1-9][0-9]*", mouse_id)
        e = by_id[mgi_id]
        assert e["mouse_symbol"] == mouse_symbol
        assert len(e["human_candidates"]) == 1, (line, "one-to-one source disagrees with HMD")
        c = e["human_candidates"][human_symbol]
        assert c["human_ncbi_gene_id"] == human_id
        mouse_identifiers.setdefault(mgi_id, []).append((mouse_id, line))
        e["mouse_ncbi_gene_id"] = mouse_id if len({v[0] for v in mouse_identifiers[mgi_id]}) == 1 else None
        if c["relation"] == "one_to_one_ortholog":
            assert c["hgnc_id"] == hgnc_id and c["human_ncbi_gene_id"] == human_id
            continue
        assert c["relation"] == "homology_group_candidate"
        c.update(hgnc_id=hgnc_id, relation="one_to_one_ortholog",
                 source_id="mgi_protein_coding", source_line=line)
        n_one_to_one += 1
    assert n_one_to_one == 16536
    identifier_conflicts = [{"mgi_id": mgi_id, "field": "mouse_ncbi_gene_id",
                             "values": sorted({v[0] for v in vals}), "source_id": "mgi_protein_coding",
                             "source_lines": [v[1] for v in vals], "resolution": "field retained as null; MGI/symbol/human mapping agree"}
                            for mgi_id, vals in mouse_identifiers.items() if len({v[0] for v in vals}) > 1]
    assert len(identifier_conflicts) == 1 and identifier_conflicts[0]["mgi_id"] == "MGI:2444426"

    alias_assertions = []
    group_assertions = []
    aliases_expected = {
        "Ptprc": ["B220", "CD45", "Ly-5", "Lyt-4", "T200"],
        "Lyz2": ["Lys", "Lysm", "Lyzs", "Lzm", "Lzm-s1", "Lzp"],
        "Adh1": ["Adh-1", "Adh1-e", "Adh-1e", "Adh-1-t", "Adh1-t", "Adh-1t", "Adh1tl", "ADH-AA", "class I alcohol dehydrogenase"],
    }
    for mouse_symbol, expected in aliases_expected.items():
        parser = PublicHTML()
        parser.feed((ROOT / (mouse_symbol + ".html")).read_text(encoding="latin1"))
        text = " ".join(" ".join(parser.text).split())
        summary = text.split(mouse_symbol + " Gene Detail Summary Symbol " + mouse_symbol + " Name ", 1)[1]
        synonyms = summary.split(" Synonyms ", 1)[1].split(" Feature Type ", 1)[0]
        aliases = [s.strip() for s in synonyms.split(",")]
        assert aliases == expected, (mouse_symbol, "official mouse Summary synonyms changed")
        e = by_id[symbol_ids[mouse_symbol]]
        assert (" IDs " + e["mgi_id"] + " NCBI Gene: ") in summary
        mouse_ncbi = summary.split(" IDs " + e["mgi_id"] + " NCBI Gene: ", 1)[1].split(" ", 1)[0]
        assert re.fullmatch(r"[1-9][0-9]*", mouse_ncbi)
        assert e["mouse_ncbi_gene_id"] in (None, mouse_ncbi)
        e["mouse_ncbi_gene_id"] = mouse_ncbi
        e["aliases"] = aliases
        e["alias_source_id"] = "mgi_marker_" + mouse_symbol
        alias_assertions.append({"mgi_id": e["mgi_id"], "mouse_symbol": mouse_symbol,
                                 "aliases": aliases, "source_id": e["alias_source_id"],
                                 "source_locator": "Mouse Summary > Synonyms (before Homology)",
                                 "human_synonyms_excluded": True})
        group_urls = [url for url in parser.links if re.fullmatch(r"https://www\.informatics\.jax\.org/homology/cluster/key/[1-9][0-9]*", url)]
        assert len(group_urls) == 1
        group_assertions.append({"mgi_id": e["mgi_id"], "source_group_id": group_urls[0].rsplit("/", 1)[1],
                                 "source_id": e["alias_source_id"], "source_locator": "Homology > MGI Vertebrate Homology",
                                 "url": group_urls[0]})
        # The HMD file does not contain group IDs. Only separately verified example pages
        # may supply an exact group key; this never changes the relationship classification.
        for c in e["human_candidates"].values():
            c["source_group_id"] = group_urls[0].rsplit("/", 1)[1]

    records = []
    for e in sorted(by_id.values(), key=lambda e: e["mouse_symbol"]):
        e = dict(e)
        e["human_candidates"] = sorted(e["human_candidates"].values(), key=lambda c: c["human_symbol"])
        records.append(e)
    relations = Counter(c["relation"] for e in records for c in e["human_candidates"])
    common = {
        "schema": "scagentkit.mouse-ortholog-map.v1", "snapshot_id": "mgi-mouse-human-2026-10-05.v1",
        "source_taxon": 10090, "target_taxon": 9606,
        "entry_fields": ENTRY_FIELDS, "candidate_fields": CANDIDATE_FIELDS,
        "sources": sources,
        "attribution": "Mouse Genome Informatics (MGI), The Jackson Laboratory; orthology information from the Alliance of Genome Resources. Derived ID/symbol lookup, CC-BY-4.0. Retrieved 2026-10-05.",
        "license_url": LICENSE_URL,
        "mgi_link_documentation": "https://www.informatics.jax.org/mgihome/other/link_instructions.shtml",
        "alias_assertions": alias_assertions, "group_assertions": group_assertions,
        "identifier_conflicts": identifier_conflicts,
        "coverage": {"mouse_records": len(records), "human_candidate_pairs": sum(relations.values()),
                     "one_to_one_pairs": relations["one_to_one_ortholog"], "one_to_one_source_rows": 16537,
                     "group_candidate_pairs": relations["homology_group_candidate"],
                     "mouse_records_with_aliases": len(alias_assertions),
                     "alias_strings": sum(len(a["aliases"]) for a in alias_assertions),
                     "multiple_human_candidate_records": sum(len(e["human_candidates"]) > 1 for e in records)},
        "limitations": [
            "Only the HOM_ProteinCoding report certifies one-to-one protein-coding orthology; HMD-only pairs remain homology group candidates.",
            "HMD has no DB class/group ID field. source_group_id is null except three separately verified public mouse example pages; group_assertions record their sources.",
            "Only Ptprc, Lyz2 and Adh1 mouse Summary aliases are included; alias spelling and case are exact. Human synonyms are excluded.",
            "The source report supplies two mouse NCBI IDs for Slc35f3 (MGI:2444426); mouse_ncbi_gene_id is null for that entry and identifier_conflicts preserves both published values and source lines.",
            "This static snapshot is not a live nomenclature service and does not cover every mouse feature or every historical alias; absence means not found in this snapshot, not absence of orthology.",
            "Multiple candidates remain visible for user selection. No candidate is chosen automatically and no capitalization, orthology prediction, expression transfer or biological label inference is performed.",
            "Only source IDs, symbols and provenance are derived. Phenotype, OMIM, images, expression, raw counts and per-cell information are excluded.",
        ],
    }
    compact = dict(common)
    compact["entries"] = [[e[f] if f != "human_candidates" else [[c[k] for k in CANDIDATE_FIELDS] for c in e[f]] for f in ENTRY_FIELDS] for e in records]
    expanded = dict(common)
    expanded["records"] = records
    receipt = {"snapshot_id": common["snapshot_id"], "coverage": common["coverage"], "artifacts": []}
    receipt["artifacts"].append(dump("mouse-orthologs.v1.json", compact))
    receipt["artifacts"].append(dump("mouse-orthologs.expanded.v1.json", expanded))
    payload = ("/* Public MGI ID/symbol snapshot; CC-BY-4.0. See embedded sources and attribution. No requests or executable gene expressions. */\n" +
               "globalThis.ScMouseOrthologData = " + json.dumps(compact, ensure_ascii=True, separators=(",", ":")) + ";\n").encode()
    (OUTPUT / "mouse-orthologs.v1.js").write_bytes(payload)
    receipt["artifacts"].append({"file": "mouse-orthologs.v1.js", "bytes": len(payload), "sha256": sha(payload)})
    dump("snapshot-build-receipt.json", receipt)
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
