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
from open_results import open_results
from store import scrub_secrets
from evidence import strict_json

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
    parser.add_argument("--background", action="store_true", help="Reuse the existing local service launcher and return its identity")
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument("--reopen", action="store_true", help="Open an existing project after verifying its original RDS binding")
    parser.add_argument("--tenx-import", action="store_true", help="Internal R adapter: input RDS contains an exact 10x import receipt")
    parser.add_argument("--context-file", help="Local JSON study context, including explicitly declared metadata roles/design")
    parser.add_argument("--scientific-review-file", help="Explicit local optional diagnostic settings for a new raw project")
    parser.add_argument("--model-config-file", help="Local creation-time provider, budget and transfer policy; never credentials")
    parser.add_argument("--source-checkout", help="Explicit matching developer source tree")
    model = parser.add_mutually_exclusive_group()
    model.add_argument("--model-suggestions", action="store_true", help="Enable existing exact-preview model workflow for the saved provider")
    model.add_argument("--model-mock", action="store_true", help="Explicit offline simulation for a saved mock project")
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
    if not input_path.is_file() or project.is_symlink() or (project.exists() and not args.reopen):
        parser.error("Supply an RDS file and a new project path")
    rscript = shutil.which(args.rscript)
    if not rscript:
        parser.error("An installed Rscript is required; no software is installed by this launcher")
    # Fail before creating a project when localhost cannot be bound.
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", args.port))
    checkout = args.source_checkout
    if checkout is None and ROOT.parent.name == "inst" and (ROOT.parent.parent / "R").is_dir():
        checkout = str(ROOT.parent.parent)
    request = {"input": str(input_path), "project": str(project), "runtime": str(ROOT), "checkout": checkout,
               "context": {"species": args.species, "tissue": args.tissue,
                           "research_goal": args.research_goal},
               "entry": "processed" if args.reuse_processed else "raw",
               "processed_reason": args.processed_reason, "cluster_column": args.cluster_column,
               "reopen": args.reopen, "tenx_import": args.tenx_import}
    if args.notes.strip():
        request["context"]["notes"] = args.notes
    if args.context_file:
        context_path = Path(args.context_file)
        if context_path.stat().st_size > 1024 * 1024:
            parser.error("Study context exceeds 1 MB")
        context = strict_json(context_path.read_text(encoding="utf-8"))
        if not isinstance(context, dict) or any(context.get(key) != request["context"][key] for key in ("species", "tissue", "research_goal")):
            parser.error("Context file must match the declared species, tissue and research goal")
        if context.get("notes") == "": context.pop("notes")
        request["context"] = context
    if args.scientific_review_file:
        science_path = Path(args.scientific_review_file)
        if science_path.stat().st_size > 1024 * 1024:
            parser.error("Scientific review settings exceed 1 MB")
        science = strict_json(science_path.read_text(encoding="utf-8"))
        if not isinstance(science, dict) or args.reuse_processed:
            parser.error("Scientific review settings require a JSON object and raw entry")
        request["scientific_review"] = science
    if args.model_config_file:
        if args.reopen:
            parser.error("Reopening uses the saved provider policy; omit --model-config-file")
        setup_path = Path(args.model_config_file)
        if setup_path.stat().st_size > 65536:
            parser.error("Provider configuration exceeds 64 KB")
        setup = strict_json(setup_path.read_text(encoding="utf-8"))
        if not isinstance(setup, dict) or set(setup) != {"provider", "budget", "review"}:
            parser.error("Provider configuration requires provider, budget and review")
        request["model_setup"] = setup
    env = scrub_secrets(dict(os.environ))
    library = args.r_library or env.get("R_LIBS_USER")
    if library:
        env["R_LIBS_USER"] = library
    with tempfile.TemporaryDirectory(prefix="scagentkit-start-") as temporary:
        config, result = Path(temporary) / "request.json", Path(temporary) / "result.json"
        config.write_text(json.dumps(request), encoding="utf-8")
        config.chmod(0o600)
        created = subprocess.run([rscript, "--vanilla", str(ROOT / "start_analysis.R"), str(config), str(result)],
                                 env=env, capture_output=args.background, check=False, shell=False)
        if created.returncode:
            if args.background:
                sys.stderr.buffer.write(created.stderr)
            raise RuntimeError("Analysis startup failed; inspect the R error and preserve any saved project")
        identity = json.loads(result.read_text())
    if args.background:
        print(json.dumps(open_results(project, rscript, library, not args.no_browser, review_mode=True,
            model_mode="simulate" if args.model_mock else "configured" if args.model_suggestions else "off",
            key_env=identity.get("provider", {}).get("api_key_env"))))
        return
    print("Project prepared: %s · %s / %s. Review and continue in the browser; Ctrl-C closes this service." %
          (identity["project_id"], identity["status"], identity["stage"]), flush=True)
    options = ["--run-project", str(project), "--local-continue", "--rscript", rscript, "--port", str(args.port)]
    if library:
        options += ["--r-library", library]
    if args.model_suggestions: options += ["--model-suggestions"]
    if args.model_mock: options += ["--model-mock"]
    serve(options)


if __name__ == "__main__":
    main()
