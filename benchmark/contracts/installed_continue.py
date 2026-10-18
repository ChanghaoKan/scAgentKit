#!/usr/bin/env python3
"""Exercise the installed localhost worker only after explicit scientific approval."""
import json
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

service, expected_stage, output = sys.argv[1:]
u = urllib.parse.urlsplit(service)
assert u.scheme == "http" and u.hostname == "127.0.0.1" and u.port
origin = "%s://%s" % (u.scheme, u.netloc)
project_id = urllib.parse.parse_qs(u.query)["project_id"][0]

def get(route):
    try:
        with urllib.request.urlopen(urllib.request.Request(origin + route, headers={"X-ScAgentKit-Run-Project": project_id}), timeout=120) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError("Installed HTTP projection rejected: " + error.read().decode("utf-8", errors="replace")[:2000]) from None

if expected_stage == "result":
    result = get("/api/run-review/workbench?" + urllib.parse.urlencode({"project_id": project_id}))
    assert result["run"]["status"] == "complete"
    assert result["evidence_complete"] is True, result.get("evidence_error")
    Path(output).write_text(json.dumps({"run_status": "complete", "evidence_complete": True})+"\n")
    sys.exit(0)

view = get("/api/run-review/inspect")
run = view["run"]
assert run["status"] == "ready", "A complete scientific proposal must be approved first"
payload = {"project_id": run["project_id"], "input_hash": run["input_hash"],
           "expected_revision": run["revision"], "request_id": "installed-smoke-" + uuid.uuid4().hex,
           "retry": False}
request = urllib.request.Request(origin + "/api/run-review/continue",
    data=json.dumps(payload).encode("utf-8"), method="POST",
    headers={"Content-Type": "application/json", "Origin": origin,
             "X-ScAgentKit-Run-Token": view["csrf_token"], "X-ScAgentKit-Run-Project": project_id})
with urllib.request.urlopen(request, timeout=120) as response:
    accepted = json.load(response)
assert accepted["job"]["status"] in ("queued", "running", "succeeded")
deadline = time.monotonic() + 240
while True:
    status = get("/api/run-review/continuation")
    job = status["job"]
    if job["status"] not in ("queued", "running"):
        break
    assert time.monotonic() < deadline, "Installed background computation timed out"
    time.sleep(.25)
assert job["status"] == "succeeded", job.get("error")
finished = get("/api/run-review/inspect")["run"]
assert finished["stage"] == expected_stage, finished["stage"]
Path(output).write_text(json.dumps({"status": "passed", "worker_status": job["status"],
    "next_stage": finished["stage"], "next_status": finished["status"],
    "provider_calls": 0, "transport": "actual installed loopback HTTP/background worker"}, indent=2)+"\n")
