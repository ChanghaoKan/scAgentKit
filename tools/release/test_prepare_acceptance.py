import importlib.util
from pathlib import Path
import unittest
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
if __name__=='__main__': unittest.main()
