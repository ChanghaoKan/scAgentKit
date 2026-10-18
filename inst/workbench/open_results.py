#!/usr/bin/env python3
"""Reopen saved results using a verified, read-only localhost service."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import http.client
import json
import os
import subprocess
import sys
import time
import webbrowser
from pathlib import Path
from urllib.parse import urlencode, urlsplit

from run_workbench_runtime import RunWorkbenchRuntime
from run_review_runtime import RunReviewRuntime
from run_continue_runtime import RunContinueRuntime
from run_suggestion_runtime import RunSuggestionRuntime, _environment
from server import WorkbenchServer, Handler
from store import scrub_secrets

ROOT = Path(__file__).resolve().parent
_LAUNCHED = {}  # Retain child handles while this launcher process is alive.


def code_hash():
    result = hashlib.sha256()
    for path in sorted(ROOT.glob("*.py")) + sorted(ROOT.glob("*.R")):
        result.update(path.name.encode())
        result.update(path.read_bytes())
    return result.hexdigest()


def atomic(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    temporary.chmod(0o600)
    os.replace(temporary, path)


def probe(record, identity):
    """A stale port or another project's service is never silently reused."""
    connection = None
    try:
        port = record["port"]
        if isinstance(port, bool) or not isinstance(port, int) or not 0 < port < 65536:
            return False
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
        connection.request("GET", "/launcher-status")
        response = connection.getresponse()
        answer = json.loads(response.read(8192))
        return response.status == 200 and answer == identity
    except (KeyError, TypeError, ValueError, OSError, http.client.HTTPException):
        return False
    finally:
        if connection:
            connection.close()


class SavedReview:
    def __init__(self, runtime, project_id):
        self.runtime = runtime
        self.project = runtime.project
        self.library = runtime.library
        self.rscript = runtime.rscript
        self.project_id = project_id

    def describe(self):
        return {"run": self.runtime.describe()["run"]}


class ResultsHandler(Handler):
    def do_GET(self):
        if urlsplit(self.path).path == "/launcher-status":
            try:
                self._trusted_request()
                self._respond(200, self.server.launch_identity)
            except Exception:
                self._respond(403, {"error": "Local result service identity unavailable"})
        elif urlsplit(self.path).path == "/review":
            self.send_response(302)
            self.send_header("Location", self.server.results_url)
            self.end_headers()
        else:
            super().do_GET()

    def do_POST(self):
        self._respond(403, {"error": "This result viewer is read-only; review/resume in R."})

    def _workbench(self):
        value = super()._workbench()
        value["navigation"].update(can_review=False, can_revise=False, can_undo=False)
        return value


class ReviewHandler(Handler):
    def do_GET(self):
        if urlsplit(self.path).path == "/launcher-status":
            try:
                self._trusted_request()
                self._respond(200, self.server.launch_identity)
            except Exception:
                self._respond(403, {"error": "Local review service identity unavailable"})
        else:
            super().do_GET()


def serve(config_path):
    config_path = Path(config_path)
    config = json.loads(config_path.read_text())
    runtime = RunWorkbenchRuntime(config["project"], config.get("library"), config["rscript"])
    view = runtime.describe()
    if view["run"]["project_id"] != config["identity"]["project_id"]:
        raise ValueError("Saved project identity changed before opening")
    editable = config.get("review_mode") is True
    review = RunReviewRuntime(config["project"], config.get("library"), config["rscript"]) if editable else SavedReview(runtime, view["run"]["project_id"])
    continuation = RunContinueRuntime(config["project"], config.get("library"), config["rscript"]) if editable else None
    mode = config.get("model_mode", "off")
    model_options = {"simulate": mode == "simulate"} if editable and mode != "off" else None
    suggestion = RunSuggestionRuntime(config["project"], config.get("library"), config["rscript"], **model_options) if model_options else None
    server = WorkbenchServer(("127.0.0.1", 0), None, None, run_review=review, run_workbench=runtime, run_continue=continuation, run_suggestion=suggestion, model_suggestion_options=model_options)
    server.RequestHandlerClass = ReviewHandler if editable else ResultsHandler
    server.launch_identity = config["identity"]
    server.results_url = "/workbench?" + urlencode({"project_id": review.project_id})
    atomic(config_path.with_name("service.json"),
           {"port": server.server_address[1], "pid": os.getpid()})
    try:
        server.serve_forever()
    finally:
        server.server_close()


def open_results(project, rscript="Rscript", library=None, browse=True, timeout=90, review_mode=False, model_mode="off", key_env=None):
    if model_mode not in {"off", "configured", "simulate"} or not review_mode and model_mode != "off":
        raise ValueError("Model workflow requires an explicit supported review mode")
    project = Path(project).expanduser()
    if project.is_symlink():
        raise ValueError("Saved project directory must not be a symlink")
    project = project.resolve(strict=True)
    runtime = RunWorkbenchRuntime(project, library, rscript)
    view = runtime.describe()
    identity = {"schema": "scagentkit.results-launcher.v1", "project_id": view["run"]["project_id"],
                "input_hash": view["run"]["input_hash"],
                "directory": [project.stat().st_dev, project.stat().st_ino],
                "code_hash": code_hash(), "rscript": str(rscript), "library": library}
    if review_mode:
        identity["schema"] = "scagentkit.review-launcher.v1"
        identity["review_mode"] = True
        identity["model_mode"] = model_mode
    base = project / (".workbench-review-launcher" if review_mode else ".workbench-launcher")
    base.mkdir(mode=0o700, exist_ok=True)
    if base.is_symlink():
        raise ValueError("Launcher directory must not be a symlink")
    with (base / "launch.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        record = None
        try:
            record = json.loads((base / "service.json").read_text())
        except (OSError, ValueError):
            pass
        reused = record is not None and probe(record, identity)
        if not reused:
            config = {"project": str(project), "rscript": str(rscript), "library": library, "identity": identity, "review_mode": review_mode, "model_mode": model_mode}
            atomic(base / "config.json", config)
            launch_env = _environment(library, key_name=key_env if model_mode == "configured" else None)
            if model_mode != "configured" and isinstance(key_env, str):
                launch_env.pop(key_env, None)
            with (base / "server.log").open("ab") as log:
                process = subprocess.Popen([sys.executable, str(ROOT / "open_results.py"), "--serve", str(base / "config.json")],
                    env=launch_env, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                    start_new_session=True, close_fds=True)
            _LAUNCHED[process.pid] = process
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                try:
                    record = json.loads((base / "service.json").read_text())
                except (OSError, ValueError):
                    record = None
                if record and probe(record, identity):
                    break
                if process.poll() is not None:
                    raise RuntimeError("Local viewer did not start; inspect " + str(base / "server.log"))
                time.sleep(0.1)
            else:
                raise TimeoutError("Local viewer is not ready; inspect " + str(base / "server.log"))
        url = "http://127.0.0.1:%s/%s?%s" % (record["port"], "review" if review_mode else "workbench", urlencode({"project_id": identity["project_id"]}))
    if browse:
        webbrowser.open(url)
    return {"url": url, "reused": reused, "pid": record["pid"], "project_id": identity["project_id"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", nargs="?")
    parser.add_argument("--rscript", default="Rscript")
    parser.add_argument("--r-library")
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument("--serve", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.serve:
        serve(args.serve)
    else:
        if not args.project:
            parser.error("Supply an existing saved run directory")
        print(json.dumps(open_results(args.project, args.rscript, args.r_library, not args.no_browser)))


if __name__ == "__main__":
    main()
