"""Allowlisted local evidence execution and immutable proposal capsules. No providers."""
from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import tempfile
import threading
import types
from pathlib import Path

try:
    from .evidence import EvidenceLoader, canonical, digest, strict_json
    from .store import StoreError, portable_content
except ImportError:
    from evidence import EvidenceLoader, canonical, digest, strict_json
    from store import StoreError, portable_content

ROOT = Path(__file__).resolve().parent


def file_hash(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


class DirectedRuntime:
    def __init__(self, results_root, source=None, cache=None, library=None, rscript="Rscript", evidence_reader=None):
        self.results = Path(results_root).resolve()
        self.source = Path(source).expanduser().resolve() if source else None
        self.cache = Path(cache or ROOT / ".local" / "directed").expanduser().resolve()
        self.library = str(Path(library).expanduser().resolve()) if library else None
        self.rscript = rscript
        self.evidence_reader = evidence_reader or EvidenceLoader(self.results).load
        self.lock = threading.RLock()
        rules_bytes = (ROOT / "directed.py").read_bytes()
        self.rules_hash = hashlib.sha256(rules_bytes).hexdigest()
        # Compile the exact bytes being fingerprinted, without import/pyc caches.
        self.domain = types.ModuleType("_scagentkit_directed_" + self.rules_hash)
        self.domain.__file__ = str(ROOT / "directed.py")
        self.domain.__package__ = ""
        exec(compile(rules_bytes, self.domain.__file__, "exec"), self.domain.__dict__)

    def context(self, evidence):
        domain = self.domain
        if file_hash(ROOT / "directed.py") != self.rules_hash:
            raise StoreError("The running rule implementation changed on disk. Restart the local server before using directed evidence", 409)
        plan = copy.deepcopy(domain.make_plan(evidence, "6"))
        taxonomy_hash = digest({"dictionary": file_hash(ROOT / "taxonomy.v1.json"), "rules": self.rules_hash})
        extractor_hash = file_hash(ROOT / "extract_directed.R")
        source_hash = None
        source_error = None
        if self.source:
            try:
                if not self.source.is_file():
                    raise ValueError("Configured expression source is not a file")
                source_hash = file_hash(self.source)
            except (OSError, ValueError) as error:
                source_error = str(error)
        else:
            source_error = "A local RNA source must be supplied with --directed-source before execution"
        plan["inputFingerprint"] = {"revision": evidence["revision"], "sourceHash": source_hash,
                                    "extractorHash": extractor_hash, "taxonomyHash": taxonomy_hash}
        plan_hash = digest(plan)
        return domain, plan, plan_hash, source_hash, extractor_hash, taxonomy_hash, source_error

    @staticmethod
    def _bundle_from(path):
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 16 * 1024 * 1024:
            raise ValueError("Invalid directed bundle file")
        return strict_json(path.read_text(encoding="utf-8"))

    @staticmethod
    def _validate_bundle(bundle, evidence, domain, source_hash, extractor_hash):
        if not isinstance(bundle, dict) or bundle.get("schema_version") != "scAgentKit.directed_expression.v1":
            raise ValueError("Invalid directed expression schema")
        scope = bundle.get("scope", {})
        expected = next(cluster["cellIds"] for cluster in evidence["clusters"] if cluster["id"] == "6")
        source = bundle.get("source", {})
        if (source.get("rds_sha256") != source_hash or source.get("extractor_sha256") != extractor_hash
                or source.get("input_evidence_revision") != evidence["revision"]
                or scope.get("cluster_id") != "6" or scope.get("cell_ids") != expected
                or scope.get("cell_ids_sha256") != digest(expected)
                or scope.get("n_cells") != len(expected)):
            raise ValueError("Directed bundle source fingerprint or exact cell scope does not match")
        # Apply the scientific schema/count/normalized/QC consistency checks before promotion.
        domain.propose(evidence, "6", bundle)

    def _read(self, evidence):
        domain, plan, plan_hash, source_hash, extractor_hash, taxonomy_hash, source_error = self.context(evidence)
        directory = self.cache / plan_hash
        bundle = None
        error = source_error
        if not error and (directory / "expression.json").exists():
            try:
                path = directory / "expression.json"
                bundle = self._bundle_from(path)
                self._validate_bundle(bundle, evidence, domain, source_hash, extractor_hash)
                manifest = strict_json((directory / "runtime-manifest.json").read_text(encoding="utf-8"))
                if manifest != {"planHash": plan_hash, "bundleHash": digest(bundle)}:
                    raise ValueError("Directed bundle content hash does not match its immutable manifest")
            except (OSError, ValueError, AttributeError, TypeError) as problem:
                bundle = None
                error = str(problem)
        return domain, plan, plan_hash, source_hash, extractor_hash, taxonomy_hash, bundle, error

    def describe(self, evidence, cluster_id="6", session=None):
        domain, plan, plan_hash, source_hash, extractor_hash, taxonomy_hash, bundle, error = self._read(evidence)
        all_triage = domain.triage(evidence, session)
        proposal = domain.propose(evidence, cluster_id, bundle if cluster_id == "6" else None, session)
        artifact = None
        if bundle is not None and cluster_id == "6":
            # Human review/model labels are display context, not inputs to this capsule.
            scientific = copy.deepcopy(proposal)
            for key in ("humanDecision", "human_decision", "triage", "strictLabels", "posthocLabels"):
                scientific.pop(key, None)
            content = {"schemaVersion": 1, "clusterId": "6", "revision": evidence["revision"],
                       "sourceHash": source_hash, "extractorHash": extractor_hash, "taxonomyHash": taxonomy_hash,
                       "bundleHash": digest(bundle), "planHash": plan_hash, "provisional": scientific}
            content = portable_content(content)
            identity = digest(content)
            artifact = {"kind": "directed_proposal", "id": identity, "sha256": identity, "content": content}
        return {"schemaVersion": 1, "clusterId": cluster_id, "triage": all_triage, "plan": plan,
                "planHash": plan_hash, "expression": bundle if cluster_id == "6" else None,
                "proposal": proposal, "artifact": artifact,
                "evidenceFingerprint": {"coreRevision": evidence["revision"], "sourceHash": source_hash,
                                        "bundleHash": digest(bundle) if bundle else None, "taxonomyHash": taxonomy_hash},
                "execution": {"status": "cached" if bundle else "not_run", "available": not bool(error),
                              "error": error, "readonly": True, "scope": "cluster 6 only; original Seurat unchanged",
                              "stopReason": "Evidence is cached; no repeated extraction or model call is needed" if bundle else "Review the plan before executing local evidence tools"},
                "modelReview": {"enabled": False, "calls": 0, "incrementalCostUSD": 0,
                                "stopReason": "The deterministic evidence workflow stops here. No provider transport is configured."}}

    def augment(self, evidence):
        augmented = dict(evidence)
        described = self.describe(evidence)
        artifact = described["artifact"]
        augmented["directedArtifacts"] = {artifact["id"]: artifact} if artifact else {}
        return augmented

    def execute(self, evidence, payload):
        if not isinstance(payload, dict) or set(payload) != {"clusterId", "revision", "planHash", "requestId"}:
            raise StoreError("Execution requires exactly clusterId, revision, planHash and requestId")
        if payload["clusterId"] != "6":
            raise StoreError("This plan only permits targeted execution for cluster 6")
        if not isinstance(payload["requestId"], str) or not payload["requestId"].strip() or len(payload["requestId"]) > 160:
            raise StoreError("A valid requestId is required")
        with self.lock:
            view = self.describe(evidence)
            if payload["revision"] != evidence["revision"] or payload["planHash"] != view["planHash"]:
                raise StoreError("The input or plan fingerprint changed. Refresh the plan before execution", 409)
            if view["execution"]["status"] == "cached":
                view["execution"]["cacheHit"] = True
                return view
            if not view["execution"]["available"]:
                raise StoreError(view["execution"]["error"] or "Local evidence execution is unavailable")
            self.cache.mkdir(parents=True, exist_ok=True)
            target = self.cache / view["planHash"]
            if target.exists():
                raise StoreError("A damaged immutable cache already exists for this fingerprint; preserve it and use a separate cache directory", 409)
            temporary = Path(tempfile.mkdtemp(prefix=".extract-", dir=str(self.cache)))
            args = [self.rscript, "--vanilla", str(ROOT / "extract_directed.R"), "--rds", str(self.source),
                    "--cells", str(self.results / "pbmc3k_reference_inputs/input_cells.csv"),
                    "--labels", str(self.results / "pbmc3k_verified/scagentkit_fixed_labels.csv"),
                    "--umap", str(self.results / "pbmc3k_verified/scagentkit_fixed_umap.csv"),
                    "--output-dir", str(temporary), "--input-evidence-revision", evidence["revision"], "--cluster", "6"]
            env = dict(os.environ)
            if self.library:
                env["R_LIBS_USER"] = self.library
            try:
                result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=120, shell=False)
                if result.returncode:
                    raise StoreError("Read-only expression tool failed: " + result.stderr[-1600:])
                bundle = self._bundle_from(temporary / "expression.json")
                current = self.evidence_reader()
                domain, _, current_plan_hash, source_hash, extractor_hash, _, problem = self.context(current)
                if problem or current_plan_hash != view["planHash"]:
                    raise StoreError("Expression input, core evidence or tool/rule fingerprint changed during execution; results were not installed", 409)
                self._validate_bundle(bundle, current, domain, source_hash, extractor_hash)
                (temporary / "runtime-manifest.json").write_text(canonical({"planHash": view["planHash"], "bundleHash": digest(bundle)}) + "\n", encoding="utf-8")
                temporary.rename(target)
                completed = self.describe(current)
                if completed["expression"] is None:
                    raise StoreError(completed["execution"]["error"] or "Generated evidence failed validation")
                completed["execution"]["cacheHit"] = False
                return completed
            except subprocess.TimeoutExpired as problem:
                raise StoreError("Read-only expression execution exceeded its bounded time limit") from problem
            finally:
                # Failed artifacts are retained for inspection, never overwritten or treated as valid.
                if temporary.exists():
                    (temporary / "FAILED.txt").write_text("Not installed as a verified cache; inspect the tool error.\n")
