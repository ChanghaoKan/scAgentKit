"""Portable local project and hostile ZIP boundaries, using synthetic JSON only."""
import copy
import hashlib
import io
import json
import os
import shutil
import stat
import sys
import tempfile
import unittest
import warnings
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import project as module
from project import ProjectError, ProjectLoader, ProjectRegistry, zip_bytes


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")


def project_fixture(project_id="Study ../A 中文", embedded=True):
    cells = [{"cellId": "NA", "clusterId": "T alpha", "qc": {}},
             {"cellId": "001", "clusterId": "T alpha", "qc": {"nCount_RNA": 1234}},
             {"cellId": "1", "clusterId": "NA", "qc": {}},
             {"cellId": "cell 中文", "clusterId": "NA", "qc": {}}]
    return {"schema": module.PROJECT_SCHEMA, "projectId": project_id, "displayName": "Local study",
            "identity": {"algorithm": "scagentkit.source.v1", "fingerprint": "a" * 64,
                         "assay": "RNA", "countsLayer": "counts", "normalizedLayer": "data",
                         "clusterColumn": "seurat_clusters", "cellCount": 4, "featureCount": 100,
                         "cellsHash": "b" * 64, "featuresHash": "c" * 64,
                         "membershipHash": "d" * 64, "countsHash": "e" * 64, "dataHash": "f" * 64},
            "cells": cells, "clusters": [{"id": "T alpha", "cellIds": ["NA", "001"]},
                                          {"id": "NA", "cellIds": ["1", "cell 中文"]}],
            "embedding": {"name": "my embedding", "points": [
                {"cellId": row["cellId"], "x": index + 0.2, "y": -index}
                for index, row in enumerate(cells)]} if embedded else None,
            "markers": [], "candidates": [], "models": [], "parameters": {}, "provenance": {},
            "directed": {"panel": "T_NK.v1", "clusters": {}},
            "sourceAnnotation": {"column": "original_annotation", "role": "source_context",
                "values": [{"cellId": row["cellId"], "value": None if index == 0 else "Original A"}
                           for index, row in enumerate(cells)]}}


def asset_fixture(value):
    ids = ["001", "NA"]
    def distribution(measurements):
        measurements = sorted(measurements)
        def quantile(p):
            position = (len(measurements) - 1) * p
            low = int(position)
            return measurements[low] + (measurements[min(low + 1, len(measurements) - 1)] - measurements[low]) * (position - low)
        return {"n": len(measurements), "mean": sum(measurements) / len(measurements) if measurements else None,
                **{field: quantile(p) if measurements else None for field, p in
                   (("q0", 0), ("q25", .25), ("q50", .5), ("q75", .75), ("q90", .9), ("max", 1))}}
    panel = []
    for gene in module.PANEL_GENES:
        measured = gene != "TRAC"
        counts = [0, 1] if gene == "CD3D" else [0, 0]
        normalized = [item * .25 for item in counts]
        panel.append({"gene": gene, "panel_group": "test", "measurement_status": "measured" if measured else "missing",
                      "counts_status": "measured" if measured else "missing", "normalized_status": "measured" if measured else "missing",
                      "assay": "RNA", "detection_layer": "counts", "normalized_layer": "data", "n_cells": 2,
                      "detected_n": sum(item > 0 for item in counts) if measured else None,
                      "detected_fraction": sum(item > 0 for item in counts) / 2 if measured else None,
                      "raw_counts": distribution(counts) if measured else None,
                      "normalized": {"all": distribution(normalized) if measured else None,
                                     "detected": distribution([item for item in normalized if item > 0]) if measured else None}})
    return {"schema_version": module.EXPRESSION_SCHEMA, "rule_version": "rna-observed-panel-v1",
            "source": {"object_fingerprint": value["identity"]["fingerprint"], "identity_algorithm": "scagentkit.source.v1", "assay": "RNA",
                       "layers": {"counts": value["identity"]["countsLayer"], "data": value["identity"]["normalizedLayer"]},
                       "n_features_counts": 100, "n_features_data": 100, "counts_integer_nonnegative_validated": True,
                       "cell_join": "Exact cell_id", "normalization": {"method": None, "scale_factor": None, "provenance": "Existing values"}},
            "inventory": {"n_cells": 4, "n_input_cells": 4, "n_clusters": 2, "counts_by_cluster": {"T alpha": 2, "NA": 2}},
            "scope": {"cluster_id": "T alpha", "n_cells": 2, "cell_ids": ids, "cell_ids_sha256": sha(encoded(ids))},
            "coverage": {"panel_gene_n": 24, "measured_gene_n": 23, "missing_genes": ["TRAC"], "scope_n_cells": 2},
            "panel": panel, "coexpression": {"n_cells": 2, "threshold_n": 2, "counts": {"t_only": 0, "nk_only": 0, "both": 0, "neither": 2}},
            "identity_threshold_sensitivity": [], "qc": {}, "candidate_controls": [], "comparisons": {}, "limitations": [], "package_id": "7" * 64,
            "cells": [{"cell_id": cell_id, "cluster_id": "T alpha",
                       "counts": {gene: None if gene == "TRAC" else index if gene == "CD3D" else 0 for gene in module.PANEL_GENES},
                       "normalized": {gene: None if gene == "TRAC" else index * .25 if gene == "CD3D" else 0 for gene in module.PANEL_GENES}, "qc": {}}
                      for index, cell_id in enumerate(ids)]}


def bundle_blobs(value=None, assets=None, project_bytes=None):
    value = copy.deepcopy(value if value is not None else project_fixture())
    assets = assets or {}
    blobs = {name: encoded(asset) if not isinstance(asset, bytes) else asset for name, asset in assets.items()}
    blobs["project.json"] = encoded(value) if project_bytes is None else project_bytes
    manifest = {"schema": module.BUNDLE_SCHEMA, "projectId": value["projectId"],
                "sourceFingerprint": value["identity"]["fingerprint"], "bundleDigest": sha(blobs["project.json"]),
                "files": [{"path": name, "bytes": len(data), "sha256": sha(data)} for name, data in sorted(blobs.items())]}
    blobs["manifest.json"] = encoded(manifest)
    return blobs


def write_bundle(root, value=None, assets=None, project_bytes=None):
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    for name, data in bundle_blobs(value, assets, project_bytes).items():
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    return root


def make_zip(blobs, additions=(), compression=zipfile.ZIP_DEFLATED):
    stream = io.BytesIO()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(stream, "w", compression=compression) as archive:
            for name, data in list(blobs.items()) + list(additions):
                archive.writestr(name, data)
    return stream.getvalue()


class ProjectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bundle = self.root / "evidence"

    def tearDown(self):
        self.temp.cleanup()

    def load(self, value=None, assets=None, project_bytes=None):
        write_bundle(self.bundle, value, assets, project_bytes)
        return ProjectLoader(self.bundle).load()

    def test_dynamic_exact_literal_ids_and_real_embedding_projection(self):
        evidence = self.load()
        self.assertEqual(evidence["dataset"]["id"], "Study ../A 中文")
        self.assertEqual(evidence["dataset"]["clusterCount"], 2)
        self.assertEqual([row["id"] for row in evidence["clusters"]], ["NA", "T alpha"])
        self.assertEqual(evidence["clusters"][1]["cellIds"], ["001", "NA"])
        self.assertEqual(len(evidence["umap"]), 4)
        self.assertEqual(evidence["umap"][0]["cellId"], "NA")
        self.assertEqual(evidence["umap"][0]["clusterId"], "T alpha")
        self.assertEqual(evidence["summary"]["modelCalls"], 0)
        self.assertEqual(evidence["summary"]["modelStatus"], "not_run")
        self.assertEqual(evidence["clusters"][1]["sourceLabelStatus"], "source_context")
        self.assertIsNone(evidence["sourceAnnotation"]["values"][0]["value"])
        self.assertNotIn(str(self.root), json.dumps(evidence))

    def test_null_embedding_counts_only_and_missing_results_stay_unavailable(self):
        value = project_fixture(embedded=False)
        value["identity"].update(normalizedLayer=None, dataHash=None)
        evidence = self.load(value)
        self.assertEqual(evidence["umap"], [])
        self.assertIsNone(evidence["embeddingName"])
        self.assertIsNone(evidence["identity"]["normalizedLayer"])
        for row in evidence["clusters"]:
            self.assertEqual((row["markers"], row["candidates"], row["models"]), ([], [], []))
        value["identity"]["dataHash"] = "f" * 64
        with self.assertRaises(ProjectError):
            self.load(value)

    def test_supplied_rows_keep_strict_posthoc_and_plain_text_separate(self):
        value = project_fixture()
        text = '<img src=x onerror="fetch(\'https://example.invalid\')">'
        value["markers"] = [{"clusterId": "NA", "gene": "CD3D", "avgLog2FC": 1.2,
                             "pct1": 0.8, "pct2": 0.2, "pAdj": 1e-12, "source": "actual table"}]
        value["candidates"] = [{"clusterId": "NA", "label": "T cell", "score": 0.7, "overlap": 2,
                                "referenceSize": 3, "markers": ["CD3D", "CD3E"], "source": "local DB"}]
        value["models"] = [{"clusterId": "NA", "callId": "c1", "provider": "cached provider", "mode": "guided",
                            "strictStatus": "format_rejected", "strict": {"label": None},
                            "posthoc": {"label": "T cell"}, "rawText": text, "source": "supplied cache"}]
        evidence = self.load(value)
        row = evidence["clusters"][0]
        self.assertAlmostEqual(row["markers"][0]["pctDiff"], 0.6)
        self.assertEqual(row["candidates"][0]["rank"], 1)
        self.assertEqual(row["models"][0]["strict"]["status"], "format_rejected")
        self.assertIsNone(row["models"][0]["strict"]["label"])
        self.assertEqual(row["models"][0]["posthoc"]["label"], "T cell")
        self.assertEqual(row["models"][0]["rawText"], text)
        self.assertEqual(evidence["summary"]["strictValid"], 0)

    def test_explicit_not_run_nullable_model_results_are_zero_actual_calls(self):
        value = project_fixture()
        value["models"] = [{"clusterId": "NA", "callId": "not-executed", "provider": "local", "mode": "independent",
                            "strictStatus": "not_run", "strict": None, "posthoc": None, "rawText": None, "source": "provided"}]
        evidence = self.load(value)
        self.assertEqual(evidence["summary"]["modelCalls"], 0)
        self.assertEqual(evidence["summary"]["modelStatus"], "not_run")
        row = evidence["clusters"][0]["models"][0]
        self.assertFalse(row["strictProvided"])
        self.assertFalse(row["posthocProvided"])
        self.assertEqual(row["strict"], {"status": "not_run"})
        self.assertEqual(row["posthoc"], {})
        self.assertIsNone(ProjectLoader(self.bundle).load()["clusters"][0]["models"][0]["rawText"])
        value["models"][0]["strictStatus"] = "valid"
        with self.assertRaises(ProjectError):
            self.load(value)

    def test_actual_missing_duplicate_foreign_ids_and_types_fail_closed(self):
        changes = [lambda p: p["cells"][0].update(clusterId=None),
                   lambda p: p["cells"][0].update(cellId=""),
                   lambda p: p["cells"][0].update(cellId="001"),
                   lambda p: p["clusters"][0].update(id=[]),
                   lambda p: p["clusters"][0].update(cellIds=["001", "1"]),
                   lambda p: p["embedding"]["points"][0].update(cellId=[]),
                   lambda p: p["embedding"]["points"][0].update(x=True),
                   lambda p: p.update(models=None),
                   lambda p: p.update(schema="scagentkit.project.v99"),
                   lambda p: p["identity"].update(cellCount=5),
                   lambda p: p["identity"].update(fingerprint="invalid")]
        for change in changes:
            value = project_fixture()
            change(value)
            with self.subTest(change=change), self.assertRaises(ProjectError):
                zip_bytes(make_zip(bundle_blobs(value)))

    def test_duplicate_json_keys_unknown_manifest_and_actual_hash_change_reject(self):
        raw = encoded(project_fixture()).replace(b'"schema":', b'"schema":"duplicate","schema":', 1)
        with self.assertRaisesRegex(ProjectError, "Duplicate"):
            zip_bytes(make_zip(bundle_blobs(project_bytes=raw)))
        blobs = bundle_blobs()
        blobs["project.json"] += b"\n"
        with self.assertRaisesRegex(ProjectError, "SHA256"):
            zip_bytes(make_zip(blobs))
        for manifest in ([], None, {"schema": "scagentkit.project-bundle.v2"}):
            blobs = bundle_blobs()
            blobs["manifest.json"] = encoded(manifest)
            with self.subTest(manifest=manifest), self.assertRaises(ProjectError):
                zip_bytes(make_zip(blobs))

    def test_directed_asset_exact_scope_source_hash_and_missing_vs_zero(self):
        value = project_fixture()
        asset = asset_fixture(value)
        name = "evidence/tnk.json"
        value["directed"]["clusters"] = {"T alpha": {"path": name, "sha256": sha(encoded(asset))}}
        self.load(value, {name: asset})
        loader = ProjectLoader(self.bundle)
        evidence = loader.load()
        observation = loader.directed_asset("T alpha")["cells"][0]
        self.assertEqual(observation["counts"]["CD3D"], 0)
        self.assertIsNone(observation["counts"]["TRAC"])
        self.assertEqual(evidence["directedAssets"]["T alpha"], asset)
        self.assertIsNone(loader.directed_asset("NA"))
        changes = [lambda a: a["source"].update(object_fingerprint="0" * 64),
                   lambda a: a["source"].update(assay="ADT"),
                   lambda a: a["source"].update(layers={"counts": "scale.data", "data": "data"}),
                   lambda a: a["scope"].update(cell_ids=["NA", "001"]),
                   lambda a: a["cells"][0].update(cell_id="foreign"),
                   lambda a: a["cells"][0]["counts"].update(CD3D=-1),
                   lambda a: a["cells"][0]["counts"].update(CD3D=0.5),
                   lambda a: a["cells"][0]["counts"].update(TRAC=0),
                   lambda a: a["cells"][0]["normalized"].update(CD3D=0.5),
                   lambda a: a["panel"].pop(),
                   lambda a: a["panel"][0].update(detected_n=2),
                   lambda a: a["panel"][0]["normalized"]["all"].update(mean=99),
                   lambda a: a["coverage"].update(missing_genes=[]),
                   lambda a: a["inventory"].update(n_cells=True),
                   lambda a: a["coexpression"]["counts"].update(both=2),
                   lambda a: a.update(schema_version="scAgentKit.directed_expression.v1")]
        for change in changes:
            bad = copy.deepcopy(asset)
            change(bad)
            p = copy.deepcopy(value)
            p["directed"]["clusters"]["T alpha"]["sha256"] = sha(encoded(bad))
            with self.subTest(change=change), self.assertRaises(ProjectError):
                zip_bytes(make_zip(bundle_blobs(p, {name: bad})))
        p = copy.deepcopy(value)
        p["identity"].update(normalizedLayer=None, dataHash=None)
        with self.assertRaisesRegex(ProjectError, "Counts-only"):
            zip_bytes(make_zip(bundle_blobs(p, {name: asset})))

    def test_overflow_numbers_in_free_context_fail_before_cache_mutation(self):
        for numeric in (b"1e999", b"9007199254740993"):
            value = project_fixture()
            raw = encoded(value).replace(b'"parameters":{}', b'"parameters":{"x":' + numeric + b'}')
            registry = ProjectRegistry(self.root / "cache", self.root / "journals")
            with self.subTest(numeric=numeric), self.assertRaises(ProjectError):
                registry.import_zip(make_zip(bundle_blobs(value, project_bytes=raw)))
            self.assertEqual(registry.list(), [])
            self.assertFalse((self.root / "cache").exists())

    def test_hostile_zip_paths_duplicates_symlinks_and_unlisted_members(self):
        blobs = bundle_blobs()
        for name in ("../outside", "/absolute", "C:/drive", "folder\\file", "a/../b", "./project.json", "a//b"):
            with self.subTest(name=name), self.assertRaises(ProjectError):
                zip_bytes(make_zip(blobs, [(name, b"x")]))
        for addition in ([('project.json', blobs['project.json'])], [('PROJECT.json', b'x')],
                         [('extra.txt', b'x')], [('empty/', b'')]):
            with self.subTest(addition=addition), self.assertRaises(ProjectError):
                zip_bytes(make_zip(blobs, addition))
        info = zipfile.ZipInfo("symlink")
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaisesRegex(ProjectError, "symlink"):
            zip_bytes(make_zip(blobs, [(info, b"/private/sensitive")]))
        # zipfile truncates NUL names internally; tamper both header names in the bytes.
        data = make_zip(blobs, [("evilXname", b"x")], compression=zipfile.ZIP_STORED)
        with self.assertRaisesRegex(ProjectError, "NUL"):
            zip_bytes(data.replace(b"evilXname", b"evil\x00name"))
        with self.assertRaises(ProjectError):
            zip_bytes(make_zip(blobs, [("caf\u00e9", b"x"), ("cafe\u0301", b"x")]))

    def test_limits_apply_before_cache_mutation_and_to_actual_expansion(self):
        data = make_zip(bundle_blobs())
        for constant, bound in (("MAX_UPLOAD_BYTES", len(data) - 1), ("MAX_MEMBERS", 1), ("MAX_EXPANDED_BYTES", 8)):
            with self.subTest(constant=constant), patch.object(module, constant, bound), self.assertRaises(ProjectError):
                zip_bytes(data)
        bomb = make_zip(bundle_blobs(), [("bomb", b"0" * 100000)])
        with self.assertRaisesRegex(ProjectError, "compression ratio"):
            zip_bytes(bomb)
        registry = ProjectRegistry(self.root / "cache", self.root / "journals")
        with self.assertRaises(ProjectError):
            registry.import_zip(bomb)
        self.assertEqual(registry.list(), [])
        self.assertFalse((self.root / "cache").exists())

    def test_directory_symlinks_and_unlisted_files_reject(self):
        write_bundle(self.bundle)
        (self.bundle / "outside").symlink_to(self.root / "unavailable")
        with self.assertRaisesRegex(ProjectError, "regular files"):
            ProjectLoader(self.bundle).load()
        (self.bundle / "outside").unlink()
        (self.bundle / "extra.txt").write_text("extra")
        with self.assertRaisesRegex(ProjectError, "Unlisted"):
            ProjectLoader(self.bundle).load()
        (self.bundle / "extra.txt").unlink()
        alias = self.root / "alias"
        alias.symlink_to(self.bundle, target_is_directory=True)
        with self.assertRaisesRegex(ProjectError, "symlink"):
            ProjectLoader(alias).load()

    def test_unreadable_unlisted_directory_cannot_be_silently_skipped(self):
        write_bundle(self.bundle)
        inaccessible = self.bundle / "unreadable"
        inaccessible.mkdir()
        (inaccessible / "unlisted.txt").write_text("must enumerate or reject")
        inaccessible.chmod(0)
        try:
            with self.assertRaises(ProjectError):
                ProjectLoader(self.bundle).load()
        finally:
            inaccessible.chmod(0o700)

    def test_reading_actual_file_growth_stops_at_declared_bound(self):
        write_bundle(self.bundle)
        actual_open = os.open
        manifest = self.bundle / "manifest.json"
        original = manifest.read_bytes()
        def grow_after_stat(path, flags, *args, **kwargs):
            if path == "manifest.json":
                manifest.write_bytes(original + b" " * 100000)
            return actual_open(path, flags, *args, **kwargs)
        with patch.object(module.os, "open", side_effect=grow_after_stat), self.assertRaisesRegex(ProjectError, "grew"):
            ProjectLoader(self.bundle).load()

    def test_registry_roundtrip_move_and_project_journal_isolation(self):
        write_bundle(self.bundle)
        registry = ProjectRegistry(self.root / "cache", self.root / "journals", self.bundle)
        first = registry.initial_key
        exported = registry.export_zip(first)
        second_bundle = self.root / "second"
        write_bundle(second_bundle, project_fixture("Other study", embedded=False))
        second = registry.add_directory(second_bundle)["key"]
        shutil.rmtree(self.bundle)
        self.assertEqual(registry.select(first)[1]["dataset"]["retainedCells"], 4)
        self.assertEqual(registry.select(second)[1]["projectId"], "Other study")
        self.assertNotEqual(registry.select(first)[2].path, registry.select(second)[2].path)
        self.assertIs(registry.select(first)[2], registry.select(first)[2])
        self.assertEqual(len(registry.list()), 2)
        moved = ProjectRegistry(self.root / "moved-cache", self.root / "moved-journals")
        self.assertEqual(moved.import_zip(exported)["key"], first)
        self.assertEqual(moved.export_zip(first), exported)
        self.assertEqual(ProjectRegistry(registry.cache_dir, registry.journal_dir).list(), registry.list())
        with self.assertRaises(ProjectError):
            registry.select("../outside")

    def test_parallel_imports_keep_digest_cache_immutable(self):
        data = make_zip(bundle_blobs())
        registries = [ProjectRegistry(self.root / "cache", self.root / "journals") for _ in range(4)]
        with ThreadPoolExecutor(max_workers=4) as pool:
            keys = list(pool.map(lambda registry: registry.import_zip(data)["key"], registries))
        self.assertEqual(len(set(keys)), 1)
        self.assertEqual(len(list((self.root / "cache").glob("[a-f0-9]" * 64))), 1)
        self.assertEqual(list((self.root / "cache").glob(".import-*")), [])
        cached = self.root / "cache" / keys[0] / "project.json"
        cached.write_bytes(cached.read_bytes() + b"\n")
        with self.assertRaises(ProjectError):
            registries[0].select(keys[0])
        with self.assertRaises(ProjectError):
            registries[0].import_zip(data)

    def test_resigned_foreign_bundle_at_digest_cache_path_is_rejected(self):
        registry = ProjectRegistry(self.root / "cache", self.root / "journals")
        original = registry.import_zip(make_zip(bundle_blobs()))["key"]
        destination = registry.cache_dir / original
        shutil.rmtree(destination)
        write_bundle(destination, project_fixture("Foreign bundle"))
        with self.assertRaisesRegex(ProjectError, "changed"):
            registry.select(original)
        with self.assertRaisesRegex(ProjectError, "changed"):
            registry.list()

    def test_legitimate_repeated_json_export_obeys_import_ratio_limit(self):
        value = project_fixture()
        value["parameters"]["repeated_note"] = "0" * 1000000
        registry = ProjectRegistry(self.root / "cache", self.root / "journals")
        key = registry.import_zip(make_zip(bundle_blobs(value), compression=zipfile.ZIP_STORED))["key"]
        exported = registry.export_zip(key)
        self.assertEqual(zip_bytes(exported), bundle_blobs(value))
        with zipfile.ZipFile(io.BytesIO(exported)) as archive:
            self.assertEqual(archive.getinfo("project.json").compress_type, zipfile.ZIP_STORED)


if __name__ == "__main__":
    unittest.main()
