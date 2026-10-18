"""Installed R entry exercises real localhost startup, not provider or remote data."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class TenxEntryTests(unittest.TestCase):
    def test_native_single_multi_reopen_and_exact_binding(self):
        rscript = shutil.which("Rscript")
        if not rscript:
            self.skipTest("Rscript unavailable")
        env = dict(os.environ)
        # This test never needs credentials; the launcher applies its allowlist too.
        import re
        env = {k: v for k, v in env.items() if not re.search(
            r"API_?KEY|ACCESS_?KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL", k, re.I)}
        ready = subprocess.run([rscript, "--vanilla", "-e",
            'quit(status=if(requireNamespace("scAgentKit",quietly=TRUE)&&"matrix_kind" %in% names(formals(scAgentKit::sc_start)))0L else 42L)'],
            env=env, capture_output=True, timeout=30)
        if ready.returncode == 42:
            self.skipTest("Current 10x entry package not installed")
        self.assertEqual(ready.returncode, 0, ready.stderr)
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run([rscript, "--vanilla",
                str(Path(__file__).with_suffix(".R")), str(Path(temporary) / "fixtures")],
                env=env, capture_output=True, timeout=180)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertIn(b"PASS native 10x entry", result.stdout)


if __name__ == "__main__":
    unittest.main()
