"""Explicit mechanism-test doubles; real RDS gate coverage is separate."""
from unittest.mock import patch
from pathlib import Path
import os
import shutil
import subprocess
import sys


def mock_format_authority(case):
    """Keep marker admission real; opaque IPC fixtures do not model R authority.

    test_project_format exercises actual source RDS checks. R CMD check verifies
    the installed bridge. This mock is only for transport/job mechanism units.
    """
    gate = patch("qc_runtime._check_project_state", return_value=None)
    gate.start()
    case.addCleanup(gate.stop)


class SourceFormatContract:
    """Real serialization/current source gate, without installing scAgentKit."""
    def __init__(self, directory, trace=None):
        self.rscript = shutil.which("Rscript")
        if self.rscript is None:
            raise RuntimeError("The project-format contract tests require Rscript, jsonlite and digest")
        self.helper = Path(__file__).with_name("project_format_contract.R")
        self.repo = Path(__file__).resolve().parents[2]
        self.executable = Path(directory) / "source-format-rscript"
        self.executable.write_text(
            "#!" + sys.executable + "\n"
            "import os, pathlib, sys\n"
            "if len(sys.argv)!=4 or sys.argv[1]!='--vanilla' or pathlib.Path(sys.argv[2]).name!='project_format_bridge.R': sys.exit(2)\n"
            + ("pathlib.Path(" + repr(str(trace)) + ").write_text(sys.argv[2])\n" if trace is not None else "")
            +
            "os.execv(" + repr(self.rscript) + ", " + repr([self.rscript, "--vanilla", str(self.helper), str(self.repo), "check"]) + " + [sys.argv[3]])\n",
            encoding="utf-8")
        self.executable.chmod(0o700)

    def state(self, project, version, parent=None, bad_hash=False):
        result = subprocess.run([self.rscript, "--vanilla", str(self.helper), str(self.repo),
            "state", str(project), "missing" if version is None else str(version),
            str(parent) if parent is not None else "", "bad" if bad_hash else "valid"],
            capture_output=True, timeout=30, env=dict(os.environ, R_PROFILE_USER=os.devnull,
                R_ENVIRON_USER=os.devnull))
        if result.returncode:
            raise AssertionError("Real R format fixture failed: " + result.stderr.decode("utf-8", "replace"))
