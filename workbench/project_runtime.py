"""Read-only replay of explicitly exported, applicable targeted RNA evidence."""
from __future__ import annotations

import copy
import hashlib
import types
from pathlib import Path

try:
    from .evidence import canonical, digest
    from .store import StoreError, portable_content
except ImportError:
    from evidence import canonical, digest
    from store import StoreError, portable_content

ROOT = Path(__file__).resolve().parent


class ProjectRuntime:
    """A portable project needs no RDS, subprocess, network or provider transport."""

    def __init__(self, loader):
        self.loader = loader
        self.rules = (ROOT / "directed.py").read_bytes()
        self.rule_hash = hashlib.sha256(self.rules).hexdigest()
        self.taxonomy_hash = hashlib.sha256((ROOT / "taxonomy.v1.json").read_bytes()).hexdigest()
        domain = types.ModuleType("project_directed_rules")
        domain.__file__ = str(ROOT / "directed.py")
        domain.__package__ = "workbench" if __package__ else ""
        exec(compile(self.rules, domain.__file__, "exec"), domain.__dict__)
        self.domain = domain

    def _fresh_rules(self):
        if ((ROOT / "directed.py").read_bytes() != self.rules
                or hashlib.sha256((ROOT / "taxonomy.v1.json").read_bytes()).hexdigest() != self.taxonomy_hash):
            raise StoreError("RNA rules or taxonomy changed; restart the server before replaying evidence", 409)

    def describe(self, evidence, cluster_id=None, session=None):
        self._fresh_rules()
        cluster_id = cluster_id or evidence["clusters"][0]["id"]
        cluster = self.domain._cluster(evidence, cluster_id)
        bundle = self.loader.directed_asset(cluster_id)
        normalized_unavailable = evidence["identity"].get("normalizedLayer") is None
        if normalized_unavailable:
            bundle = None
        plan = self.domain.make_plan(evidence, cluster_id, bundle)
        # The asset is an explicit export, never an implicit request to query a matrix.
        available = bundle is not None
        identity = evidence["identity"]
        for step in plan["steps"]:
            step["availability"] = "portable_export_available" if available else "unavailable"
            if "assay" in step["parameters"]:
                step["parameters"]["assay"] = identity["assay"]
            if "layers" in step["parameters"]:
                step["parameters"]["layers"] = [identity["countsLayer"], identity["normalizedLayer"]]
            if "layer" in step["parameters"]:
                step["parameters"]["layer"] = identity["countsLayer"]
            step.pop("id", None)
            step["id"] = "step:" + digest(step)
        plan.pop("id", None)
        plan["id"] = "plan:" + digest(plan)
        plan_hash = digest({"plan": plan, "revision": evidence["revision"],
                            "sourceFingerprint": evidence["sourceFingerprint"],
                            "rulesHash": self.rule_hash, "taxonomyHash": self.taxonomy_hash,
                            "expressionHash": digest(bundle) if available else None})
        proposal = self.domain.propose(evidence, cluster_id, bundle, session)
        reason = ("The project explicitly has no normalized RNA layer. Normalization-dependent directed inspection is unavailable; counts and manual review remain usable."
                  if normalized_unavailable else "No applicable targeted RNA panel was explicitly exported for this cluster. Re-export with an applicable directed_clusters selection to inspect it.")
        if not available:
            proposal["stopReason"] = reason
            proposal["nextSteps"] = []
        artifact = None
        if available:
            scientific = copy.deepcopy(proposal)
            scientific.pop("humanDecision", None)
            content = portable_content({"schemaVersion": 1, "clusterId": cluster_id,
                "revision": evidence["revision"], "sourceFingerprint": evidence["sourceFingerprint"],
                "sourceHash": evidence["sourceFingerprint"], "bundleHash": digest(bundle),
                "ruleHash": self.rule_hash, "taxonomyHash": self.taxonomy_hash,
                "planHash": plan_hash, "provisional": scientific})
            raw = canonical(content)
            capsule_hash = hashlib.sha256(raw.encode("utf-8")).hexdigest()
            artifact = {"kind": "directed_proposal", "id": capsule_hash, "sha256": capsule_hash,
                        "payload": raw, "content": content}
        return {"schemaVersion": 1, "clusterId": cluster_id,
            "triage": self.domain.triage(evidence, session), "plan": plan, "planHash": plan_hash,
            "expression": bundle, "proposal": proposal, "artifact": artifact,
            "evidenceFingerprint": {"coreRevision": evidence["revision"],
                "sourceHash": evidence["sourceFingerprint"], "bundleHash": digest(bundle) if available else None,
                "taxonomyHash": self.taxonomy_hash, "rulesHash": self.rule_hash},
            "execution": {"status": "cached" if available else "unavailable", "available": available,
                "error": None if available else reason, "readonly": True,
                "scope": "Exact exported cell ID set for cluster " + cluster["id"],
                "stopReason": "Replaying the verified portable RNA export; no extraction or external model call is needed." if available else reason},
            "modelReview": {"enabled": False, "calls": 0, "incrementalCostUSD": 0,
                "stopReason": "No provider transport is configured."}}

    def augment(self, evidence):
        result = dict(evidence)
        artifacts = {}
        for cluster in evidence["clusters"]:
            if self.loader.directed_asset(cluster["id"]) is not None:
                artifact = self.describe(evidence, cluster["id"])["artifact"]
                if artifact:
                    artifacts[artifact["id"]] = artifact
        result["directedArtifacts"] = artifacts
        return result

    def execute(self, evidence, payload):
        if not isinstance(payload, dict) or set(payload) != {"clusterId", "revision", "planHash", "requestId"}:
            raise StoreError("Replay requires exactly clusterId, revision, planHash and requestId")
        if not isinstance(payload["requestId"], str) or not payload["requestId"].strip() or len(payload["requestId"]) > 160:
            raise StoreError("A valid requestId is required")
        view = self.describe(evidence, payload["clusterId"])
        if payload["revision"] != evidence["revision"] or payload["planHash"] != view["planHash"]:
            raise StoreError("Project or plan changed; refresh before replaying evidence", 409)
        if not view["execution"]["available"]:
            raise StoreError(view["execution"]["error"], 409)
        view["execution"]["cacheHit"] = True
        return view
