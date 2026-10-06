#!/usr/bin/env python3
"""Local-only scAgentKit evidence workbench; Python standard library only."""
from __future__ import annotations

import argparse
import json
import mimetypes
import secrets
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs, urlencode
import hashlib

try:
    from .evidence import EvidenceError, EvidenceLoader, canonical, strict_json
    from .store import SessionStore, StoreError
    from .directed_runtime import DirectedRuntime
    from .project import ProjectRegistry, ProjectError
    from .project_store import ProjectStoreError
    from .project_runtime import ProjectRuntime
    from .qc_runtime import QCRuntime
    from .run_review_runtime import RunReviewRuntime
    from .run_continue_runtime import RunContinueRuntime
    from .run_subcluster_runtime import RunSubclusterRuntime
    from .run_suggestion_runtime import RunSuggestionRuntime
    from .run_workbench_runtime import RunWorkbenchRuntime
except ImportError:
    from evidence import EvidenceError, EvidenceLoader, canonical, strict_json
    from store import SessionStore, StoreError
    from directed_runtime import DirectedRuntime
    from project import ProjectRegistry, ProjectError
    from project_store import ProjectStoreError
    from project_runtime import ProjectRuntime
    from qc_runtime import QCRuntime
    from run_review_runtime import RunReviewRuntime
    from run_continue_runtime import RunContinueRuntime
    from run_subcluster_runtime import RunSubclusterRuntime
    from run_suggestion_runtime import RunSuggestionRuntime
    from run_workbench_runtime import RunWorkbenchRuntime

STATIC = Path(__file__).resolve().parent / "static"
MAX_BODY = 32 * 1024 * 1024
CSP = ("default-src 'none'; script-src 'self'; style-src 'self'; frame-src 'self'; "
       "img-src 'self' data:; connect-src 'self'; font-src 'self'; "
       "base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'")
SUGGESTION_ROUTES = {"/api/run-review/suggestion/" + action for action in ("preview", "approve", "request", "adopt", "discard")}


class WorkbenchServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, loader, store, static_dir=STATIC, directed=None, registry=None, qc=None, run_review=None, run_continue=None, run_subcluster=None, run_suggestion=None, model_suggestion_options=None, run_workbench=None):
        if address[0] != "127.0.0.1":
            raise ValueError("Workbench must bind to 127.0.0.1")
        self.loader = loader
        self.store = store
        self.static_dir = Path(static_dir).resolve()
        self.directed = directed
        self.registry = registry
        self.qc = qc
        self.run_review = run_review
        self.run_continue = run_continue
        self.run_subcluster = run_subcluster
        self.run_suggestion = run_suggestion
        self.run_workbench = run_workbench
        self.workbench_contexts = {}
        self.model_suggestion_options = model_suggestion_options
        self.suggestion_contexts = {}
        self.context_lock = threading.RLock()
        self.selected_key = None
        self.selected_context = (loader, store, directed)
        self.project_contexts = {}
        self.verified_evidence = {}
        super().__init__(address, Handler)

    def select_project(self, key):
        if not self.registry:
            raise StoreError("This server is using the legacy PBMC evidence adapter", 409)
        with self.context_lock:
            context = self.project_context(key)
            evidence = context[0].load()
            if evidence["revision"] != key:
                raise ProjectError("Cached project fingerprint changed; import the new snapshot explicitly", 409)
            self.verified_evidence[key] = evidence
            self.selected_context = context
            self.selected_key = key
            return evidence

    def project_context(self, key):
        with self.context_lock:
            if key not in self.project_contexts:
                loader, _, store = self.registry.select(key)
                self.project_contexts[key] = (loader, store, ProjectRuntime(loader))
            return self.project_contexts[key]

    def project_list(self):
        return {"projects": self.registry.list() if self.registry else [],
                "selected": self.selected_key, "legacy": self.registry is None}


class Handler(BaseHTTPRequestHandler):
    server_version = "scAgentKitLocal/1"

    def log_message(self, format, *args):
        # Log routes and status only; never bodies, labels, reasons or source data.
        if getattr(self.server, "verbose", False):
            sys.stderr.write("%s %s\n" % (self.command, self.path.split("?")[0]))

    def _trusted_request(self):
        port = self.server.server_address[1]
        hosts = {"127.0.0.1:%s" % port, "localhost:%s" % port}
        if port == 80:
            hosts |= {"127.0.0.1", "localhost"}
        if self.headers.get("Host", "").lower() not in hosts:
            raise StoreError("Only this localhost Host is accepted", 403)
        origin = self.headers.get("Origin")
        if origin is not None and origin.lower() not in {"http://" + host for host in hosts}:
            raise StoreError("Only the same localhost Origin is accepted", 403)
        if self.headers.get("Sec-Fetch-Site") == "cross-site":
            raise StoreError("Cross-site requests are rejected", 403)

    def _respond(self, status, body, content_type="application/json; charset=utf-8", extra=None):
        if isinstance(body, (dict, list)):
            body = canonical(body).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        csp = CSP.replace("frame-ancestors 'none'", "frame-ancestors 'self'") if urlsplit(self.path).path == "/review-qc" else CSP
        self.send_header("Content-Security-Policy", csp)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _capture_context(self):
        # Each request retains one project/store pair even if another tab switches.
        with self.server.context_lock:
            key = self.headers.get("X-ScAgentKit-Project")
            route = urlsplit(self.path).path
            if key is not None and route not in ("/api/projects", "/api/project/select", "/api/project/import"):
                if not self.server.registry:
                    raise StoreError("A legacy PBMC server cannot bind a generic project", 409)
                self.loader, self.store, self.directed = self.server.project_context(key)
                self.project_key = key
            else:
                self.loader, self.store, self.directed = self.server.selected_context
                self.project_key = self.server.selected_key

    def _evidence(self):
        if self.loader is None:
            raise StoreError("Import or select an evidence project first", 409)
        evidence = self.loader.load()
        if self.server.registry:
            if evidence["revision"] != self.project_key:
                raise ProjectError("Cached project fingerprint changed; import the new snapshot explicitly", 409)
            self.server.verified_evidence[self.project_key] = evidence
        return self.directed.augment(evidence) if self.directed else evidence

    def _error(self, error, status=422):
        self._respond(status, {"error": str(error), "readOnly": isinstance(error, (EvidenceError, ProjectError))})

    def _parent_lifecycle(self):
        if not self.server.run_subcluster:
            return None
        if not hasattr(self, "parent_lifecycle"):
            self.parent_lifecycle = self.server.run_subcluster.readiness()
        return self.parent_lifecycle

    def _bound_project(self, selected, payload=None, query_project=None):
        header = self.headers.get("X-ScAgentKit-Run-Project")
        for name, value in (("header", header), ("query", query_project)):
            if value is not None and (not isinstance(value, str) or not value.strip()
                    or len(value) > 200 or any(ord(char) < 32 for char in value)):
                raise StoreError("Run project %s must be a bounded literal ID" % name)
            if value is not None and value != selected:
                raise StoreError("Run project %s differs from the selected registered scope" % name, 409)
        if isinstance(payload, dict) and "project_id" in payload and payload["project_id"] != selected:
            raise StoreError("Request body project differs from the selected registered scope", 409)

    def _run_context(self, payload=None):
        query = parse_qs(urlsplit(self.path).query, keep_blank_values=True)
        if set(query) - {"child_id", "project_id"} or any(len(values) != 1 or not values[0] for values in query.values()):
            raise StoreError("Only one registered child_id and exact project_id may scope this run request")
        child_id = query.get("child_id", [None])[0]
        expected = query.get("project_id", [None])[0]
        if child_id is not None:
            if not self.server.run_subcluster:
                raise StoreError("Child selection requires an operator-configured workspace")
            self._bound_project(child_id, payload, expected)
            return self.server.run_subcluster.child_context(child_id)
        context = (self.server.run_review, self.server.run_continue, self.server.qc)
        if self.server.run_subcluster:
            lifecycle = self._parent_lifecycle()
            self._bound_project(lifecycle["parent_run"]["project_id"], payload, expected)
        elif (self.headers.get("X-ScAgentKit-Run-Project") is not None or expected is not None
              or isinstance(payload, dict) and "project_id" in payload):
            review = self.server.run_review or self.server.qc
            if review is None:
                raise StoreError("No configured run is available", 409)
            selected = getattr(review, "project_id", None)
            if not isinstance(selected, str): selected = review.describe()["run"]["project_id"]
            self._bound_project(selected, payload, expected)
        return context

    def _subcluster_query(self):
        query = parse_qs(urlsplit(self.path).query, keep_blank_values=True)
        if set(query) - {"child_id", "column", "supersedes", "project_id"} or any(len(values) != 1 or not values[0] for values in query.values()):
            raise StoreError("Only a registered child_id and bounded target column/supersedes may be inspected")
        if ("column" in query or "supersedes" in query) and "child_id" not in query:
            raise StoreError("Target column previews require a registered child_id")
        expected = query.pop("project_id", [None])[0]
        selected = query.get("child_id", [self._parent_lifecycle()["parent_run"]["project_id"]])[0]
        self._bound_project(selected, query_project=expected)
        return {key: values[0] for key, values in query.items()}

    def _suggestion_context(self, review=None):
        if review is None:
            review, _, _ = self._run_context()
        if self.server.run_subcluster and review is self.server.run_review and self._parent_lifecycle()["frozen"]:
            return None  # Completed source parent remains read-only.
        if review is self.server.run_review:
            return self.server.run_suggestion
        options = self.server.model_suggestion_options
        if review is None or options is None:
            return None
        # Only an authoritative registered child context supplies this path.
        with self.server.context_lock:
            key = str(review.project)
            if key not in self.server.suggestion_contexts:
                self.server.suggestion_contexts[key] = RunSuggestionRuntime(
                    review.project, review.library, review.rscript, **options)
            return self.server.suggestion_contexts[key]

    def _workbench(self):
        query = parse_qs(urlsplit(self.path).query, keep_blank_values=True)
        if (set(query) - {"child_id", "project_id"} or "project_id" not in query
                or any(len(values) != 1 or not values[0] for values in query.values())):
            raise StoreError("Saved workbench requires one exact registered project_id and optional child_id")
        expected = query["project_id"][0]
        if self.headers.get("X-ScAgentKit-Run-Project") != expected:
            raise StoreError("Saved workbench requires matching query and run-project header", 409)
        review, _, _ = self._run_context()
        if review is None:
            raise StoreError("Saved workbench requires an operator-configured run", 409)
        lifecycle = self._parent_lifecycle()
        is_parent = review is self.server.run_review
        frozen = bool(is_parent and lifecycle and lifecycle["frozen"])
        with self.server.context_lock:
            key = str(review.project)
            if is_parent and self.server.run_workbench is not None:
                runtime = self.server.run_workbench
            else:
                if key not in self.server.workbench_contexts:
                    self.server.workbench_contexts[key] = RunWorkbenchRuntime(review.project, review.library, review.rscript)
                runtime = self.server.workbench_contexts[key]
        view = runtime.describe()
        if not isinstance(view, dict) or view.get("schema") != "scagentkit.workbench.v1":
            raise StoreError("Saved workbench returned no verified scope", 409)
        run, project, binding = view.get("run"), view.get("project"), view.get("binding")
        if not all(isinstance(item, dict) for item in (run, project, binding)):
            raise StoreError("Saved workbench returned incomplete identity bindings", 409)
        if (project.get("project_id") != expected or run.get("project_id") != expected
                or binding.get("project_id") != expected):
            raise StoreError("Saved workbench differs from the selected registered project", 409)
        for field in ("input_hash", "revision", "history_head"):
            if project.get(field) != run.get(field) or binding.get(field) != run.get(field):
                raise StoreError("Saved workbench run, evidence and history bindings differ", 409)
        if lifecycle:
            if is_parent:
                fields = ["project_id", "input_hash", "revision"]
                if "history_head" in lifecycle["parent_run"]: fields.append("history_head")
                for field in fields:
                    if run.get(field) != lifecycle["parent_run"].get(field):
                        raise StoreError("Saved parent changed from its workspace binding; refresh", 409)
            # No response cache: this also rejects registry/application changes
            # while the saved projection was being loaded.
            refreshed = self.server.run_subcluster.readiness()
            if canonical(refreshed) != canonical(lifecycle):
                raise StoreError("Registered workspace changed during inspection; refresh", 409)
            binding["workspace_fingerprint"] = hashlib.sha256(canonical(lifecycle).encode("utf-8")).hexdigest()
            binding["parent_scope_hash"] = lifecycle.get("parent", {}).get("parent_scope_hash")
        else:
            binding["workspace_fingerprint"] = None
        project.update(scope="parent" if is_parent else "child", frozen=frozen)
        view["readonly"] = True
        view["children"] = lifecycle.get("children", []) if lifecycle else []
        scope_query = {"project_id": expected}
        if not is_parent: scope_query["child_id"] = expected
        suffix = "?" + urlencode(scope_query)
        node = run.get("review_node") or {}
        view["navigation"] = {"review_url": "/review" + suffix,
            "subclusters_url": "/subclusters" + suffix if lifecycle else None,
            "can_review": not frozen and node.get("can_decide") is True,
            "can_revise": not frozen and node.get("can_revise") is True,
            "can_undo": not frozen and node.get("can_undo") is True, "frozen": frozen}
        if len(canonical(view).encode("utf-8")) > 16 * 1024 * 1024:
            raise StoreError("Saved display exceeds 16 MiB. No history or evidence was truncated; inspect fixed artifacts in R", 409)
        return view

    def do_GET(self):
        try:
            if hasattr(self, "parent_lifecycle"): del self.parent_lifecycle
            self._trusted_request()
            self._capture_context()
            route = urlsplit(self.path).path
            if self.server.run_review and route.startswith("/api/") and route not in ("/api/qc/inspect", "/api/run-review/inspect", "/api/run-review/continuation", "/api/subcluster/inspect", "/api/run-review/suggestion", "/api/run-review/scopes", "/api/run-review/workbench"):
                raise StoreError("This server reviews its configured run only", 409)
            if self.server.qc and not self.server.run_review and route.startswith("/api/") and route != "/api/qc/inspect":
                raise StoreError("This server reviews its configured QC run only", 409)
            if route == "/api/projects":
                self._respond(200, self.server.project_list())
            elif route == "/api/run-review/workbench":
                self._respond(200, self._workbench())
            elif route == "/api/run-review/scopes":
                query = parse_qs(urlsplit(self.path).query, keep_blank_values=True)
                if set(query) - {"project_id"} or any(len(v) != 1 or not v[0] for v in query.values()):
                    raise StoreError("Scope listing accepts only an exact project_id binding")
                if self.server.run_subcluster:
                    lifecycle = self._parent_lifecycle()
                    parent = dict(lifecycle["parent_run"])
                    parent.update(ready=lifecycle["ready"], frozen=lifecycle["frozen"])
                    children = lifecycle["children"]
                elif self.server.run_review:
                    parent = self.server.run_review.describe()["run"]
                    parent = {key: parent.get(key) for key in ("project_id", "input_hash", "status", "stage", "revision", "output")}
                    parent.update(ready=parent["status"] == "complete", frozen=False)
                    children = []
                else:
                    raise StoreError("Scope listing requires a configured run", 409)
                expected = query.get("project_id", [self.headers.get("X-ScAgentKit-Run-Project")])[0]
                allowed = {parent["project_id"]} | {item["project_id"] for item in children}
                if expected is not None and expected not in allowed:
                    raise StoreError("Project is not registered to this service", 409)
                if expected is not None: self._bound_project(expected, query_project=query.get("project_id", [None])[0])
                self._respond(200, {"schema": "scagentkit.run-scopes.workbench.v1", "parent": parent,
                                    "children": children, "workspace_enabled": self.server.run_subcluster is not None})
            elif route == "/api/subcluster/inspect":
                if not self.server.run_subcluster:
                    raise StoreError("Start --run-project with --subcluster-workspace", 409)
                query = self._subcluster_query()
                lifecycle = self._parent_lifecycle()
                if not lifecycle["ready"]:
                    if query: raise StoreError("Registered child review becomes available after the parent completes", 409)
                    self._respond(200, lifecycle)
                else:
                    view = self.server.run_subcluster.describe(**query)
                    view.update(ready=True, frozen=True, parent_run=lifecycle["parent_run"])
                    self._respond(200, view)
            elif route == "/api/run-review/inspect":
                review, continuation, _ = self._run_context()
                if not review:
                    raise StoreError("Start an explicit --run-project server for unified review", 409)
                lifecycle = self._parent_lifecycle() if review is self.server.run_review else None
                if lifecycle and lifecycle["frozen"]:
                    run = dict(lifecycle["parent_run"])
                    run["context"] = dict(lifecycle.get("parent", {}).get("context") or {})
                    view = {"schema": "scagentkit.run-review.workbench.v1", "run": run,
                            "csrf_token": review.csrf_token, "effective_readonly": True,
                            "boundary": "Completed parent is frozen in this workspace service. Inspect original and derived outputs or select a registered child."}
                else:
                    view = review.describe()
                    view["effective_readonly"] = False
                view["suggestion_enabled"] = self._suggestion_context(review) is not None
                if continuation:
                    view["continuation"] = continuation.describe(view["run"])
                    view["boundary"] = "Bound QC/annotation review and explicitly requested approved local computation. Model/provider stages require R; Continue never dispatches a provider."
                self._respond(200, view)
            elif route == "/api/run-review/suggestion":
                suggestion = self._suggestion_context()
                if not suggestion:
                    raise StoreError("Model suggestions require operator --model-suggestions or --model-mock and an executable registered scope", 409)
                self._respond(200, suggestion.describe())
            elif route == "/api/run-review/continuation":
                _, continuation, _ = self._run_context()
                if not continuation:
                    raise StoreError("Local Continue requires --local-continue and an executable child scope in subanalysis mode", 409)
                self._respond(200, continuation.describe())
            elif route == "/api/qc/inspect":
                _, _, qc = self._run_context()
                if not qc:
                    raise StoreError("Start an explicit --run-project server to review live QC", 409)
                self._respond(200, qc.describe())
            elif route == "/api/project/export":
                if not self.server.registry or not self.project_key:
                    raise StoreError("Select a generic evidence project before exporting", 409)
                self._respond(200, self.server.registry.export_zip(self.project_key), "application/zip",
                              {"Content-Disposition": 'attachment; filename="scagentkit-project.zip"'})
            elif route == "/api/evidence":
                self._respond(200, self._evidence())
            elif route == "/api/directed":
                if not self.directed:
                    raise StoreError("Directed expression tools are not configured; supply --directed-source", 409)
                query = parse_qs(urlsplit(self.path).query)
                if set(query) - {"clusterId"} or len(query.get("clusterId", [""])) != 1:
                    raise StoreError("Only one clusterId may be selected")
                evidence = self._evidence()
                cluster_id = query.get("clusterId", [evidence["clusters"][0]["id"]])[0]
                if cluster_id not in {cluster["id"] for cluster in evidence["clusters"]}:
                    raise StoreError("Unknown cluster scope")
                session = self.store.session(evidence)
                self._respond(200, self.directed.describe(evidence, cluster_id, session))
            elif route == "/api/session":
                try:
                    evidence = self._evidence()
                    error = None
                except (EvidenceError, ProjectError) as problem:
                    evidence = (self.server.verified_evidence.get(self.project_key)
                                if self.server.registry else getattr(self.loader, "latest", None))
                    error = str(problem)
                self._respond(200, self.store.session(evidence, error))
            elif route == "/api/export":
                self._respond(200, self.store.export(self._evidence()),
                              extra={"Content-Disposition": 'attachment; filename="scagentkit-handoff.json"'})
            elif route.startswith("/api/"):
                self._error("Route does not exist", 404)
            else:
                # A fixed asset allowlist avoids any file traversal or source exposure.
                asset = {"/": "review.html" if self.server.run_review else "qc.html" if self.server.qc else "index.html", "/index.html": "index.html", "/app.js": "app.js",
                         "/styles.css": "styles.css", "/favicon.svg": "favicon.svg", "/gene-links.js": "gene-links.js", "/ortholog-map.js": "ortholog-map.js",
                         "/qc": "qc.html", "/qc.html": "qc.html", "/qc.js": "qc.js", "/qc.css": "qc.css",
                         "/review-qc": "qc.html",
                         "/review": "review.html", "/review.html": "review.html", "/review.js": "review.js", "/review.css": "review.css",
                         "/workbench": "workbench.html", "/workbench.html": "workbench.html", "/workbench.js": "workbench.js", "/workbench.css": "workbench.css", "/evidence-display.js": "evidence-display.js",
                         "/subclusters": "subcluster.html", "/subcluster.js": "subcluster.js", "/subcluster.css": "subcluster.css"}.get(route)
                if asset is None:
                    self._error("Asset does not exist", 404)
                    return
                target = self.server.static_dir / asset
                if target.is_symlink() or not target.is_file():
                    self._error("Asset does not exist", 404)
                    return
                content_type = mimetypes.guess_type(asset)[0] or "application/octet-stream"
                content = target.read_bytes()
                if route == "/review-qc":
                    content = content.replace(b"<body>", b'<body data-run-review="true">', 1)
                self._respond(200, content, content_type + "; charset=utf-8")
        except (StoreError, ProjectStoreError) as error:
            self._error(error, error.status)
        except (EvidenceError, ProjectError) as error:
            self._error(error, getattr(error, "status", 422))
        except (ValueError, KeyError, TypeError, OSError, RecursionError) as error:
            self._error("Invalid local input: %s" % error)

    def do_POST(self):
        try:
            if hasattr(self, "parent_lifecycle"): del self.parent_lifecycle
            self._trusted_request()
            self._capture_context()
            route = urlsplit(self.path).path
            if self.server.run_review and route not in {"/api/run-review/decision", "/api/run-review/continue", "/api/subcluster/operation"} | SUGGESTION_ROUTES:
                raise StoreError("This server accepts fully bound unified review decisions only; use /review", 409)
            if self.server.qc and not self.server.run_review and route != "/api/qc/decision":
                raise StoreError("This server accepts typed QC decisions only", 409)
            if route not in {"/api/decision", "/api/undo", "/api/import", "/api/directed/execute", "/api/project/select", "/api/project/import", "/api/qc/decision", "/api/run-review/decision", "/api/run-review/continue", "/api/subcluster/operation"} | SUGGESTION_ROUTES:
                raise StoreError("Route does not exist", 404)
            expected_type = "application/zip" if route == "/api/project/import" else "application/json"
            if self.headers.get("Content-Type", "").split(";")[0].strip().lower() != expected_type:
                raise StoreError("Requests require " + expected_type, 415)
            if self.headers.get("Transfer-Encoding"):
                raise StoreError("Chunked requests are not accepted", 400)
            try:
                length = int(self.headers.get("Content-Length", ""))
            except ValueError:
                raise StoreError("Content-Length is required", 411) from None
            if not 0 < length <= (64 * 1024 * 1024 if route == "/api/project/import" else MAX_BODY):
                raise StoreError("Request body is empty or exceeds the size limit", 413)
            self.connection.settimeout(10)
            body = self.rfile.read(length)
            if len(body) != length:
                raise StoreError("Request body was incomplete", 400)
            if route == "/api/project/import":
                if not self.server.registry:
                    raise StoreError("Use a generic project server to import portable evidence", 409)
                metadata = self.server.registry.import_zip(body)
                self.server.select_project(metadata["key"])
                self._respond(200, metadata)
                return
            payload = strict_json(body.decode("utf-8"))
            if not isinstance(payload, dict):
                raise StoreError("Request body must be an object")
            if route in SUGGESTION_ROUTES:
                review, continuation, _ = self._run_context(payload)
                suggestion = self._suggestion_context(review)
                if not suggestion:
                    raise StoreError("Model suggestions require an operator-enabled executable scope", 409)
                if continuation and (continuation.describe().get("job") or {}).get("status") in {"queued", "running"}:
                    raise StoreError("Local work is running; inspect its saved job before requesting a suggestion", 409)
                action = route.rsplit("/", 1)[1]
                self._respond(202 if action == "request" else 200, suggestion.operate(
                    action, payload, self.headers.get("X-ScAgentKit-Suggestion-Token")))
                return
            if route == "/api/subcluster/operation":
                if not self.server.run_subcluster:
                    raise StoreError("Start --run-project with --subcluster-workspace", 409)
                if urlsplit(self.path).query: raise StoreError("Subanalysis operations carry their exact child ID in typed JSON only")
                lifecycle = self._parent_lifecycle()
                if not lifecycle["ready"]:
                    raise StoreError("Finish the configured parent before creating or applying a registered child", 409)
                selected = lifecycle["parent_run"]["project_id"] if payload.get("action") == "create" else payload.get("child_id")
                self._bound_project(selected, payload)
                self._respond(200, self.server.run_subcluster.operate(payload, self.headers.get("X-ScAgentKit-Subcluster-Token")))
                return
            if route == "/api/run-review/decision":
                review, continuation, _ = self._run_context(payload)
                if not review:
                    raise StoreError("Start an explicit --run-project server for unified review", 409)
                if self.server.run_subcluster and review is self.server.run_review:
                    if payload.get("action") == "undo" or self._parent_lifecycle()["frozen"]:
                        raise StoreError("Completed parent science is read-only in this workspace service; select a registered child", 409)
                if continuation and (continuation.describe().get("job") or {}).get("status") in {"queued", "running"}:
                    raise StoreError("Local work is running; inspect its saved job before changing a decision", 409)
                suggestion = self._suggestion_context(review)
                if suggestion and (suggestion.job_status() or {}).get("status") in {"queued", "running"}:
                    raise StoreError("A model suggestion is running; inspect its saved job before changing a decision", 409)
                view = review.decide(payload, self.headers.get("X-ScAgentKit-Run-Token"))
                view["suggestion_enabled"] = suggestion is not None
                if continuation:
                    view["continuation"] = continuation.describe(view["run"])
                    view["boundary"] = "Bound QC/annotation review and explicitly requested approved local computation. Model/provider stages require R; Continue never dispatches a provider."
                self._respond(200, view)
                return
            if route == "/api/run-review/continue":
                review, continuation, _ = self._run_context(payload)
                if self.server.run_subcluster and review is self.server.run_review and self._parent_lifecycle()["frozen"]:
                    raise StoreError("Completed parent computation is read-only in this workspace service", 409)
                if not review or not continuation:
                    raise StoreError("Local Continue requires --local-continue and an executable child scope in subanalysis mode", 409)
                token = self.headers.get("X-ScAgentKit-Run-Token")
                if not isinstance(token, str) or not secrets.compare_digest(token, review.csrf_token):
                    raise StoreError("Local Continue requires this server's same-origin review token", 403)
                suggestion = self._suggestion_context(review)
                if suggestion and (suggestion.job_status() or {}).get("status") in {"queued", "running"}:
                    raise StoreError("A model suggestion is running; inspect its saved job before local Continue", 409)
                self._respond(202, continuation.submit(payload))
                return
            if route == "/api/qc/decision":
                _, _, qc = self._run_context(payload)
                if not qc:
                    raise StoreError("Start an explicit --run-project server to review live QC", 409)
                if self.server.run_subcluster and qc is self.server.qc and self._parent_lifecycle()["frozen"]:
                    raise StoreError("Original parent is read-only in subanalysis mode", 409)
                self._respond(200, qc.decide(payload, self.headers.get("X-ScAgentKit-QC-Token")))
                return
            if route == "/api/project/select":
                if set(payload) != {"key"}:
                    raise StoreError("Project selection requires exactly key")
                self.server.select_project(payload["key"])
                self._respond(200, self.server.project_list())
                return
            evidence = self._evidence()
            if route == "/api/decision":
                result = self.store.decision(payload, evidence)
            elif route == "/api/undo":
                result = self.store.undo(payload, evidence)
            elif route == "/api/directed/execute":
                if not self.directed:
                    raise StoreError("Directed expression tools are not configured", 409)
                if self.store.session(evidence)["readOnly"]:
                    raise StoreError("Session integrity failed; preserve history before proceeding", 409)
                self._respond(200, self.directed.execute(evidence, payload))
                return
            else:
                if set(payload) == {"package"}:
                    incoming = payload["package"]
                elif set(payload) in ({"format", "datasetId", "revisions", "events"}, {"format", "datasetId", "revisions", "events", "artifacts"}):
                    incoming = payload
                elif payload.get("schema") == "scagentkit.review-journal.v1":
                    incoming = payload
                else:
                    raise StoreError("Import requires a direct handoff package or exactly one package field")
                result = self.store.import_package(incoming, evidence)
            self._respond(200, result)
        except (StoreError, ProjectStoreError) as error:
            self._error(error, error.status)
        except (EvidenceError, ProjectError) as error:
            self._error(error, getattr(error, "status", 422))
        except (ValueError, KeyError, TypeError, UnicodeError, OSError, RecursionError) as error:
            self._error("Invalid local input: %s" % error)

    def do_OPTIONS(self):
        self._error("Cross-origin access is not enabled", 403)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results-root", help="Legacy PBMC phase-one results root; explicit evidence allowlist only")
    parser.add_argument("--project", action="append", help="Verified portable project directory; repeat to register multiple projects")
    parser.add_argument("--run-project", help="Existing server-side sc_run directory; unified QC/annotation review, no ZIP or browser provider")
    parser.add_argument("--subcluster-workspace", help="Separate existing directory for registered child projects; parent review stays available until completion, then becomes read-only")
    parser.add_argument("--local-continue", action="store_true", help="Enable explicit asynchronous approved local computation; provider/model stages remain in R")
    parser.add_argument("--model-suggestions", action="store_true", help="Enable explicit async requests to the project's saved DeepSeek/Grok provider; keys only from runtime environment")
    parser.add_argument("--model-mock", action="store_true", help="Enable explicitly simulated suggestions for an immutable mock-provider project; zero API calls")
    parser.add_argument("--model-timeout", type=int, default=300, help="Operator bound for each dedicated suggestion worker, 1–3600 seconds; timeout requires R reconciliation")
    parser.add_argument("--subcluster-inherit-model", action="store_true", help="Explicitly inherit the completed parent's safe provider/budget/transfer policy when creating a child; no keys are copied")
    parser.add_argument("--project-cache", default=str(STATIC.parent / ".local" / "projects"), help="Private local imported evidence cache")
    parser.add_argument("--journal-root", default=str(STATIC.parent / ".local" / "reviews"), help="Private per-project append-only review journals")
    parser.add_argument("--session", default=str(Path(__file__).resolve().parent / ".local" / "session.json"), help="Local append-only session file")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--verbose", action="store_true", help="Log local route names only")
    parser.add_argument("--directed-source", help="Explicit local frozen Seurat RDS for read-only RNA evidence; no generic upload")
    parser.add_argument("--directed-cache", help="Separate immutable local expression cache directory")
    parser.add_argument("--r-library", help="Existing R package library for the allowlisted expression tool")
    parser.add_argument("--rscript", default="Rscript", help="Existing Rscript executable")
    args = parser.parse_args(argv)
    if not 0 <= args.port <= 65535:
        parser.error("port must be between 0 and 65535")
    if sum(map(bool, (args.project, args.results_root, args.run_project))) != 1:
        parser.error("Supply exactly one of --project, --results-root or --run-project")
    if args.local_continue and not args.run_project:
        parser.error("--local-continue requires --run-project")
    if args.subcluster_workspace and not args.run_project:
        parser.error("--subcluster-workspace requires --run-project")
    if (args.model_suggestions or args.model_mock) and not args.run_project:
        parser.error("Model suggestions require --run-project")
    if args.model_suggestions and args.model_mock:
        parser.error("Choose either --model-suggestions or explicit --model-mock")
    if not 1 <= args.model_timeout <= 3600:
        parser.error("--model-timeout must be from 1 to 3600 seconds")
    if args.subcluster_inherit_model and not args.subcluster_workspace:
        parser.error("--subcluster-inherit-model requires --subcluster-workspace")
    try:
        if args.run_project:
            if args.directed_source:
                parser.error("Live run review does not accept --directed-source")
            qc = QCRuntime(args.run_project, args.r_library, args.rscript)
            run_review = RunReviewRuntime(args.run_project, args.r_library, args.rscript)
            inherit_options = {"inherit_model": True} if args.subcluster_inherit_model else {}
            subcluster = RunSubclusterRuntime(args.run_project, args.subcluster_workspace, args.r_library, args.rscript, args.local_continue, **inherit_options) if args.subcluster_workspace else None
            if subcluster:
                scoped = subcluster.readiness()
                view = {"run": scoped["parent_run"]}
                frozen = scoped["frozen"]
            else:
                view = run_review.describe()
                frozen = False
            run_continue = RunContinueRuntime(args.run_project, args.r_library, args.rscript) if args.local_continue and not frozen else None
            model_options = {"simulate": args.model_mock, "worker_timeout": args.model_timeout} if args.model_suggestions or args.model_mock else None
            run_suggestion = RunSuggestionRuntime(args.run_project, args.r_library, args.rscript, **model_options) if model_options is not None and not frozen else None
            server = WorkbenchServer(("127.0.0.1", args.port), None, None, qc=qc, run_review=run_review, run_continue=run_continue, run_subcluster=subcluster, run_suggestion=run_suggestion, model_suggestion_options=model_options)
            evidence = None
        elif args.project:
            if args.directed_source:
                parser.error("Generic projects replay explicitly exported RNA assets; --directed-source belongs to the legacy adapter")
            registry = ProjectRegistry(args.project_cache, args.journal_root, initial_project=args.project[0])
            for path in args.project[1:]:
                registry.add_directory(path)
            server = WorkbenchServer(("127.0.0.1", args.port), None, None, registry=registry)
            evidence = server.select_project(registry.initial_key or registry.list()[0]["key"])
        else:
            loader = EvidenceLoader(args.results_root)
            evidence = loader.load()
            directed = DirectedRuntime(args.results_root, args.directed_source, args.directed_cache, args.r_library, args.rscript) if args.directed_source else None
            server = WorkbenchServer(("127.0.0.1", args.port), loader, SessionStore(args.session), directed=directed)
    except (EvidenceError, StoreError, OSError, ValueError) as error:
        parser.exit(2, "Evidence rejected: %s\n" % error)
    server.verbose = args.verbose
    print("scAgentKit workbench: http://127.0.0.1:%s" % server.server_address[1], flush=True)
    if args.run_project:
        execution = ("parent review until completion, then frozen source; registered child review in this same service" if args.subcluster_workspace else
                     "explicit local Continue and separately approved model suggestions" if args.local_continue and model_options is not None else
                     "separately approved model suggestions; computation resumes in R" if model_options is not None else
                     "explicit local Continue enabled; provider stages require R" if args.local_continue else "explicit R resume required")
        print("Run review · %s · revision %s · %s" % (view["run"]["status"], view["run"]["revision"], execution), flush=True)
        if args.model_mock:
            print("Model suggestions: explicitly SIMULATED mock; zero external API calls", flush=True)
        elif args.model_suggestions:
            print("Model suggestions: saved provider only; exact aggregate preview and explicit transfer approval required", flush=True)
    else:
        print("%s cells · %s clusters · evidence %s" % (sum(c["cellCount"] for c in evidence["clusters"]), len(evidence["clusters"]), evidence["revision"][:12]), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
