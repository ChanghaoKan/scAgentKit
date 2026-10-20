# Reproducible CASSIA request-shape qualification

This small attachment preserves the **already executed 2026-10-20 offline probe** and its result. It is not a CASSIA installation, live provider smoke, accuracy experiment or ReAct implementation. The [qualification report](../model-qualification.md) explains its conclusions and limitations. No real API/key was used: five scenarios produced 31 in-memory HTTP requests and zero provider requests.

Files:

- [Probe](probe_cassia_deepseek_grok.py): original script, unchanged. It AST-loads frozen CASSIA definitions and runs the actual resolver/three agents with real SDK JSON serialization, synthetic credentials, disabled sockets and `httpx.MockTransport`.
- [Recorded result](probe_cassia_deepseek_grok.json): original result, unchanged, including complete request-body hashes, source hashes, wire parameter summaries and environment versions.
- [Dependency freeze](probe_cassia_deepseek_grok_requirements.txt): original Python dependency versions; Python 3.9.6 was used. Newer Python/platform compatibility has not been established by this probe.
- [Manifest](manifest.json): checksums for the three artifacts and exact URLs/hashes of the five required CASSIA source files at commit `c01f573caf25c5ef471e8afefd035c05becfab08` (MIT).

No third-party source tree, SDK installation, biological matrix or model weight is included. This entire `benchmark/` directory is excluded from the R package by the existing `.Rbuildignore`.

## Reproduce in a scratch directory

Run from the scAgentKit repository root. The preparation step downloads **public source/dependency files only**; the subsequent probe is offline. No key or environment credential setup is needed. Copy first so a rerun cannot overwrite the committed result:

```sh
mkdir -p work/cassia-offline-recheck
cp benchmark/evaluation-v2/manifests/cassia-offline-probe/* work/cassia-offline-recheck/
python3 -m venv work/cassia-offline-recheck/venv
work/cassia-offline-recheck/venv/bin/python -m pip install -r work/cassia-offline-recheck/probe_cassia_deepseek_grok_requirements.txt
```

Fetch only the five manifest-listed files and check their bytes before execution:

```sh
python3 - <<'PY'
from pathlib import Path
import hashlib, json, urllib.request
folder = Path('work/cassia-offline-recheck')
manifest = json.loads((folder / 'manifest.json').read_text())
for name, expected in manifest['artifacts_sha256'].items():
    assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == expected, name
for item in manifest['sources']:
    data = urllib.request.urlopen(item['url'], timeout=60).read()
    assert hashlib.sha256(data).hexdigest() == item['sha256'], item['filename']
    (folder / item['filename']).write_bytes(data)
PY
work/cassia-offline-recheck/venv/bin/python work/cassia-offline-recheck/probe_cassia_deepseek_grok.py
```

The script reads those filenames beside itself and writes its new result there. It does not download or install anything at runtime. The five scenarios should show counts 3, 3, 3, 3 and 19; exact IDs remain unchanged, only the Pro route includes `thinking.disabled`, and Grok medium/high request hashes are equal. Compare the rerun against the recorded evidence:

```sh
python3 - <<'PY'
from pathlib import Path
import json
saved = json.loads(Path('benchmark/evaluation-v2/manifests/cassia-offline-probe/probe_cassia_deepseek_grok.json').read_text())
rerun = json.loads(Path('work/cassia-offline-recheck/probe_cassia_deepseek_grok.json').read_text())
for field in ('cassia_commit', 'source_sha256', 'results', 'network_calls', 'actual_provider_calls'):
    assert rerun[field] == saved[field], field
assert rerun['results'][2]['full_wire_body_hashes'] == rerun['results'][3]['full_wire_body_hashes']
print('Offline request evidence matches; no provider acceptance or accuracy claim.')
PY
```

The AST probe skips full module initialization/dependencies and batch entry validation. SDK retries are set to zero **inside this probe only**; that does not establish upstream CASSIA retry behavior. Its synthetic usage is not a real bill. Matching request hashes establish transport behavior, not live service acceptance, equivalent Responses/Chat history, matched thinking settings, or completed formal support. Real smoke and the complete comparator preset remain pending.
