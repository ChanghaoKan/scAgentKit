#!/usr/bin/env python3
"""Local-only scAgentKit evidence workbench; Python standard library only."""
from __future__ import annotations

import argparse
import json
import mimetypes
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

try:
    from .evidence import EvidenceError, EvidenceLoader, canonical, strict_json
    from .store import SessionStore, StoreError
    from .directed_runtime import DirectedRuntime
    from .project import ProjectRegistry, ProjectError
    from .project_store import ProjectStoreError
    from .project_runtime import ProjectRuntime
except ImportError:
    from evidence import EvidenceError, EvidenceLoader, canonical, strict_json
    from store import SessionStore, StoreError
    from directed_runtime import DirectedRuntime
    from project import ProjectRegistry, ProjectError
    from project_store import ProjectStoreError
    from project_runtime import ProjectRuntime

STATIC = Path(__file__).resolve().parent / "static"
MAX_BODY = 32 * 1024 * 1024
CSP = ("default-src 'none'; script-src 'self'; style-src 'self'; "
       "img-src 'self' data:; connect-src 'self'; font-src 'self'; "
       "base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'")


class WorkbenchServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, loader, store, static_dir=STATIC, directed=None, registry=None):
        if address[0] != "127.0.0.1":
            raise ValueError("Workbench must bind to 127.0.0.1")
        self.loader = loader
        self.store = store
        self.static_dir = Path(static_dir).resolve()
        self.directed = directed
        self.registry = registry
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
        self.send_header("Content-Security-Policy", CSP)
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

    def do_GET(self):
        try:
            self._trusted_request()
            self._capture_context()
            route = urlsplit(self.path).path
            if route == "/api/projects":
                self._respond(200, self.server.project_list())
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
                asset = {"/": "index.html", "/index.html": "index.html", "/app.js": "app.js",
                         "/styles.css": "styles.css", "/favicon.svg": "favicon.svg"}.get(route)
                if asset is None:
                    self._error("Asset does not exist", 404)
                    return
                target = self.server.static_dir / asset
                if target.is_symlink() or not target.is_file():
                    self._error("Asset does not exist", 404)
                    return
                content_type = mimetypes.guess_type(asset)[0] or "application/octet-stream"
                self._respond(200, target.read_bytes(), content_type + "; charset=utf-8")
        except (StoreError, ProjectStoreError) as error:
            self._error(error, error.status)
        except (EvidenceError, ProjectError) as error:
            self._error(error, getattr(error, "status", 422))
        except (ValueError, KeyError, TypeError, OSError, RecursionError) as error:
            self._error("Invalid local input: %s" % error)

    def do_POST(self):
        try:
            self._trusted_request()
            self._capture_context()
            route = urlsplit(self.path).path
            if route not in ("/api/decision", "/api/undo", "/api/import", "/api/directed/execute", "/api/project/select", "/api/project/import"):
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
    if bool(args.project) == bool(args.results_root):
        parser.error("Supply --project for generic evidence or --results-root for legacy PBMC evidence")
    try:
        if args.project:
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
    print("%s cells · %s clusters · evidence %s" % (sum(c["cellCount"] for c in evidence["clusters"]), len(evidence["clusters"]), evidence["revision"][:12]), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
