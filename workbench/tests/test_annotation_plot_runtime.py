import hashlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from run_review_runtime import RunReviewRuntime
from store import StoreError

class AnnotationPlotTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        (self.root/"state.rds").write_bytes(b"opaque fixed R fixture")
        self.runtime=RunReviewRuntime(self.root)
        self.data=b"\x89PNG\r\n\x1a\n"+b"offline immutable PNG transport fixture"
        self.sha=hashlib.sha256(self.data).hexdigest()
        self.relative="review-evidence/annotation/"+"a"*64+"/citations-1.png"
        self.path=self.root/self.relative;self.path.parent.mkdir(parents=True);self.path.write_bytes(self.data)
        self.view={"run":{"annotation_review":{"details":{"plot_evidence":{"plots":[{"sha256":self.sha,"path":self.relative}]}}}}}
    def tearDown(self):self.temp.cleanup()
    def test_only_current_verified_png_bytes_are_served(self):
        with patch.object(self.runtime,"describe",return_value=self.view):
            self.assertEqual(self.runtime.annotation_plot(self.sha),self.data)
            with self.assertRaises(StoreError):self.runtime.annotation_plot("0"*64)
            with self.assertRaises(StoreError):self.runtime.annotation_plot("../file")
            self.path.write_bytes(self.data+b"changed")
            with self.assertRaises(StoreError):self.runtime.annotation_plot(self.sha)
    def test_path_traversal_and_symlink_are_rejected(self):
        with patch.object(self.runtime,"describe",return_value=self.view):
            for bad in ("../../state.rds","/tmp/evidence.png","review-evidence/annotation/../state.png"):
                self.view["run"]["annotation_review"]["details"]["plot_evidence"]["plots"][0]["path"]=bad
                with self.assertRaises(StoreError):self.runtime.annotation_plot(self.sha)
            self.view["run"]["annotation_review"]["details"]["plot_evidence"]["plots"][0]["path"]=self.relative
            self.path.unlink();self.path.symlink_to(self.root/"state.rds")
            with self.assertRaises(StoreError):self.runtime.annotation_plot(self.sha)
    def test_non_png_or_historical_plot_is_rejected(self):
        self.path.write_bytes(b"not PNG")
        with patch.object(self.runtime,"describe",return_value=self.view):
            with self.assertRaises(StoreError):self.runtime.annotation_plot(self.sha)
        with patch.object(self.runtime,"describe",return_value={"run":{}}):
            with self.assertRaises(StoreError):self.runtime.annotation_plot(self.sha)

if __name__=="__main__":unittest.main()
