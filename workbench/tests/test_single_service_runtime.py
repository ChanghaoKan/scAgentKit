"""Readiness uses verified fixed IPC and a one-way parent binding; mocked R only."""
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evidence import canonical
from run_subcluster_runtime import RunSubclusterRuntime
from store import StoreError


def lifecycle(ready=False):
    run = {"schema": "scagentkit.run.v1", "project_id": "parent", "input_hash": "a" * 64,
           "revision": 10, "status": "complete" if ready else "ready",
           "stage": "complete" if ready else "strategy_apply", "output": None}
    parent = {"schema": "scagentkit.subcluster.parent.v1" if ready else "scagentkit.subcluster.parent-waiting.v1",
              "parent_project_id": "parent", "expected_parent_revision": 10}
    if ready: parent.update(input_hash="a" * 64, parent_scope_hash="b" * 64)
    return {"schema": "scagentkit.subcluster.bridge.v1", "ready": ready,
            "parent_run": run, "parent": parent, "children": [], "child": None, "child_path": None}


class SingleServiceRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.root = Path(self.temporary.name)
        self.parent = self.root / "parent"; self.parent.mkdir(); (self.parent / "state.rds").write_bytes(b"Never loaded by R")
        self.workspace = self.root / "children"; self.workspace.mkdir()
        self.runtime = RunSubclusterRuntime(self.parent, self.workspace)
    def tearDown(self): self.temporary.cleanup()
    def process(self, value):
        def call(argv, **kwargs):
            self.assertEqual(argv[3], "readiness"); self.assertFalse(kwargs["shell"])
            self.assertEqual(json.loads(Path(argv[-2]).read_text()), {})
            Path(argv[-1]).write_text(canonical({"ok": True, "result": value, "error": None}))
            return subprocess.CompletedProcess(argv, 0, b"private", b"private")
        return call
    def inspect(self, value):
        with patch("run_subcluster_runtime.subprocess.run", side_effect=self.process(value)):
            return self.runtime.readiness()
    def test_waiting_to_complete_is_a_one_way_freeze_without_parent_writes(self):
        original = (self.parent / "state.rds").read_bytes()
        view = self.inspect(lifecycle()); self.assertFalse(view["ready"]); self.assertFalse(view["frozen"])
        view = self.inspect(lifecycle(True)); self.assertTrue(view["ready"]); self.assertTrue(view["frozen"])
        self.assertEqual((self.parent / "state.rds").read_bytes(), original)
        self.assertNotIn("child_path", view)
        with self.assertRaisesRegex(StoreError, "Frozen parent changed"): self.inspect(lifecycle())
    def test_frozen_parent_revision_or_input_or_scope_change_rejected(self):
        self.inspect(lifecycle(True))
        for field, changed in (("revision", 11), ("input_hash", "c" * 64)):
            value = lifecycle(True); value["parent_run"][field] = changed
            if field == "revision": value["parent"]["expected_parent_revision"] = changed
            else: value["parent"][field] = changed
            with self.subTest(field=field), self.assertRaisesRegex(StoreError, "Frozen parent changed"): self.inspect(value)
        value = lifecycle(True); value["parent"]["parent_scope_hash"] = "c" * 64
        with self.assertRaisesRegex(StoreError, "Frozen parent changed"): self.inspect(value)
    def test_mismatched_or_unbounded_lifecycle_never_grants_authority(self):
        for field, changed in (("schema", "unknown"), ("project_id", "other"),
                               ("input_hash", "bad"), ("revision", True), ("stage", "strategy_apply")):
            value = lifecycle(True); value["parent_run"][field] = changed
            with self.subTest(field=field), self.assertRaises(StoreError): self.inspect(value)
        value = lifecycle(True); value["parent"]["expected_parent_revision"] = 11
        with self.assertRaisesRegex(StoreError, "changed while inspecting"): self.inspect(value)
    def test_convenience_status_json_never_controls_freeze(self):
        (self.parent / "status.json").write_text('{"status":"complete","project_id":"foreign"}')
        self.assertFalse(self.inspect(lifecycle())["frozen"])
        (self.parent / "status.json").write_text('{"status":"ready"}')
        self.assertTrue(self.inspect(lifecycle(True))["frozen"])


if __name__ == "__main__": unittest.main()
