#!/usr/bin/env python3
"""Start a local reviewed analysis from an RDS file in an existing environment."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile

from server import main as serve
from store import scrub_secrets

ROOT = Path(__file__).resolve().parent


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="Local RDS containing raw counts or a Seurat object")
    parser.add_argument("--project", required=True, help="New output directory; existing paths are never overwritten")
    parser.add_argument("--species", required=True, help="Declared species, not inferred from gene symbols")
    parser.add_argument("--tissue", required=True)
    parser.add_argument("--research-goal", required=True)
    parser.add_argument("--notes", default="")
    parser.add_argument("--reuse-processed", action="store_true", help="Explicitly reuse supplied normalized layers and clusters instead of raw-count analysis")
    parser.add_argument("--processed-reason", default="")
    parser.add_argument("--cluster-column", default="seurat_clusters")
    parser.add_argument("--rscript", default="Rscript")
    parser.add_argument("--r-library")
    parser.add_argument("--port", type=int, default=0, help="Loopback port; default chooses an available port")
    args = parser.parse_args(argv)
    if sys.version_info < (3, 9):
        parser.error("Python 3.9 or later is required")
    if not 0 <= args.port <= 65535:
        parser.error("port must be between 0 and 65535")
    if not all(value.strip() for value in (args.species, args.tissue, args.research_goal)):
        parser.error("Declare species, tissue and research goal")
    if args.reuse_processed and not args.processed_reason.strip():
        parser.error("Processed reuse requires --processed-reason")
    input_path = Path(args.input).expanduser().resolve(strict=True)
    project = Path(args.project).expanduser().absolute()
    if not input_path.is_file() or project.exists() or project.is_symlink():
        parser.error("Supply an RDS file and a new project path")
    rscript = shutil.which(args.rscript)
    if not rscript:
        parser.error("An installed Rscript is required; no software is installed by this launcher")
    # Fail before creating a project when localhost cannot be bound.
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", args.port))
    request = {"input": str(input_path), "project": str(project), "checkout": str(ROOT.parent),
               "context": {"species": args.species, "tissue": args.tissue,
                           "research_goal": args.research_goal, "notes": args.notes},
               "entry": "processed" if args.reuse_processed else "raw",
               "processed_reason": args.processed_reason, "cluster_column": args.cluster_column}
    env = scrub_secrets(dict(os.environ))
    library = args.r_library or env.get("R_LIBS_USER")
    if library:
        env["R_LIBS_USER"] = library
    with tempfile.TemporaryDirectory(prefix="scagentkit-start-") as temporary:
        config, result = Path(temporary) / "request.json", Path(temporary) / "result.json"
        config.write_text(json.dumps(request), encoding="utf-8")
        config.chmod(0o600)
        subprocess.run([rscript, "--vanilla", str(ROOT / "start_analysis.R"), str(config), str(result)],
                       env=env, check=True, shell=False)
        identity = json.loads(result.read_text())
    print("Project prepared: %s · %s / %s. Review and continue in the browser; Ctrl-C closes this service." %
          (identity["project_id"], identity["status"], identity["stage"]), flush=True)
    options = ["--run-project", str(project), "--local-continue", "--rscript", rscript, "--port", str(args.port)]
    if library:
        options += ["--r-library", library]
    serve(options)


if __name__ == "__main__":
    main()
