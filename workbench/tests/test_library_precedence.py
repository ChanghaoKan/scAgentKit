"""An explicit worker library must win over a conflicting inherited R_LIBS."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_suggestion_runtime import _environment


class LibraryPrecedenceTests(unittest.TestCase):
    def test_real_r_selects_the_explicit_copy_when_two_libraries_contain_the_package(self):
        rscript = shutil.which("Rscript")
        if not rscript:
            self.skipTest("Rscript unavailable")
        found = subprocess.run([rscript, "--vanilla", "-e",
            'cat(find.package("jsonlite", quiet=TRUE))'],
            capture_output=True, text=True, timeout=30, check=True).stdout.strip()
        if not found:
            self.skipTest("jsonlite unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            selected, inherited = base / "selected", base / "inherited"
            for library in (selected, inherited):
                shutil.copytree(found, library / "jsonlite")
            with patch.dict(os.environ, {"R_LIBS": str(inherited)}):
                env = _environment(str(selected))
            result = subprocess.run([rscript, "--vanilla", "-e",
                'cat(find.package("jsonlite"))'], env=env,
                capture_output=True, text=True, timeout=30, check=True)
            self.assertEqual(Path(result.stdout.strip()).resolve(), selected / "jsonlite")


if __name__ == "__main__":
    unittest.main()
