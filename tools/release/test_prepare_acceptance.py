import importlib.util
from pathlib import Path
import unittest
import tempfile
import tarfile
import io
import hashlib
import subprocess
import sys
import urllib.error

spec = importlib.util.spec_from_file_location('prepare_acceptance', Path(__file__).with_name('prepare-acceptance.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Response:
    status = 200
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def read(self): return b'exact archive bytes'

class DownloadTests(unittest.TestCase):
    def test_transient_failure_retries_exact_bytes_and_long_timeout(self):
        calls=[]; pauses=[]
        def opening(request, timeout):
            calls.append(timeout)
            if len(calls)<3: raise urllib.error.URLError('transient')
            return Response()
        self.assertEqual(module.read('https://example.org/a', opener=opening, sleep=pauses.append), b'exact archive bytes')
        self.assertEqual(calls,[1800,1800,1800]); self.assertEqual(pauses,[1,2])
    def test_permanent_http_error_does_not_retry(self):
        calls=[]
        def opening(*args, **kwargs):
            calls.append(1)
            raise urllib.error.HTTPError('https://example.org/a',404,'missing',{},None)
        with self.assertRaises(urllib.error.HTTPError): module.read('https://example.org/a',opener=opening)
        self.assertEqual(len(calls),1)
    def test_exhaustion_is_bounded_and_reports_original_error(self):
        calls=[]
        def opening(*args,**kwargs):
            calls.append(1); raise TimeoutError('still timed out')
        with self.assertRaisesRegex(TimeoutError,'still timed out'):
            module.read('https://example.org/a',opener=opening,sleep=lambda _:None)
        self.assertEqual(len(calls),4)
    def test_rate_limit_is_transient_but_auth_is_not(self):
        for status,expected in [(429,4),(503,4),(401,1),(403,1)]:
            calls=[]
            def opening(*args,**kwargs):
                calls.append(1); raise urllib.error.HTTPError('https://example.org/a',status,'error',{},None)
            with self.assertRaises(urllib.error.HTTPError):
                module.read('https://example.org/a',opener=opening,sleep=lambda _:None)
            self.assertEqual(len(calls),expected)
class ArtifactVersionTests(unittest.TestCase):
    def artifact(self, root, version="0.8.0.9001"):
        name="scAgentKit_"+version+".tar.gz"
        with tarfile.open(root/name,"w:gz") as archive:
            files={"DESCRIPTION":"Package: scAgentKit\nVersion: "+version+"\nPackaged: source build\n",
                   "README.md":(Path(__file__).resolve().parents[2]/"README.md").read_text()}
            for filename,text in files.items():
                raw=text.encode();info=tarfile.TarInfo("scAgentKit/"+filename);info.size=len(raw)
                archive.addfile(info,io.BytesIO(raw))
        sha=hashlib.sha256((root/name).read_bytes()).hexdigest()
        (root/"SHA256SUMS").write_text(sha+"  "+name+"\n")
        return sha
    def run_preflight(self, root, mode, sha, version):
        return subprocess.run([sys.executable,str(Path(module.__file__).resolve()),mode,"source-commit",sha,"--version",version],cwd=root,capture_output=True,text=True)
    def test_development_artifact_uses_exact_version_and_verbatim_current_readme(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);sha=self.artifact(root)
            result=self.run_preflight(root,"artifact",sha,"0.8.0.9001")
            self.assertEqual(result.returncode,0,result.stderr)
            receipt=module.json.loads((root/"download-receipt.json").read_text())
            self.assertEqual(receipt["version"],"0.8.0.9001");self.assertIsNone(receipt["tag"])
            self.assertIn('scAgentKit_0.8.0.9001.tar.gz',(root/"README-install.R").read_text())
    def test_wrong_source_version_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);sha=self.artifact(root)
            result=self.run_preflight(root,"artifact",sha,"0.8.0")
            self.assertNotEqual(result.returncode,0)
    def test_changed_archive_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);self.artifact(root)
            result=self.run_preflight(root,"artifact","0"*64,"0.8.0.9001")
            self.assertNotEqual(result.returncode,0);self.assertIn("Downloaded bytes differ",result.stderr)
    def test_public_mode_remains_pinned_and_invalid_version_fails_before_network(self):
        with tempfile.TemporaryDirectory() as directory:
            for mode,version in [("public","0.8.0.9001"),("artifact","../unsafe")]:
                result=self.run_preflight(Path(directory),mode,"0"*64,version)
                self.assertEqual(result.returncode,2);self.assertIn("error:",result.stderr)

if __name__=='__main__': unittest.main()
