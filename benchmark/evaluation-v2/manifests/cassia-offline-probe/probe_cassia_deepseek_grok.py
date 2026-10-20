"""Run frozen CASSIA source with real SDK serialization and in-memory HTTP only.

No provider API, real environment/key access, package analysis or biological
data download. AST extraction skips module imports/initializers; the actual
resolver, annotation/validator/formatter and usage functions run unchanged.
"""
import ast
import contextlib
import hashlib
import io
import json
import logging
from pathlib import Path
import re
import socket
import sys
import time
from types import SimpleNamespace
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse

import httpx
import openai

ROOT = Path(__file__).resolve().parent
COMMIT = "c01f573caf25c5ef471e8afefd035c05becfab08"
FILES = {
    "settings": ROOT / "CASSIA__CASSIA_python__CASSIA__core__model_settings.py",
    "config": ROOT / "CASSIA__CASSIA_python__CASSIA__data__model_settings.json",
    "llm": ROOT / "CASSIA__CASSIA_python__CASSIA__core__llm_utils.py",
    "engine": ROOT / "CASSIA__engine.py",
    "tools": ROOT / "CASSIA__CASSIA_python__CASSIA__engine__tools_function.py",
}


def forbidden(*args, **kwargs):
    raise AssertionError("Network operation forbidden in offline probe")


socket.socket = forbidden
socket.create_connection = forbidden
original_openai = openai.OpenAI
wire_calls = []
scenario = {"maximal": False}


def fake_response(request):
    payload = json.loads(request.content)
    wire_calls.append({"url": str(request.url), "body": payload})
    number = len(wire_calls)
    if scenario["maximal"]:
        text = ("```json\n{\"main_cell_type\":\"Unknown\",\"sub_cell_types\":[]}\n```"
                if number == 19 else "Needs more evidence.")
    else:
        text = [
            "B cell. FINAL ANNOTATION COMPLETED",
            "VALIDATION PASSED",
            "```json\n{\"main_cell_type\":\"B cell\",\"sub_cell_types\":[]}\n```",
        ][number - 1]
    return httpx.Response(200, request=request, json={
        "id": f"offline-{number}", "object": "chat.completion", "created": 0,
        "model": payload["model"],
        "choices": [{"index": 0, "message": {"role": "assistant", "content": text},
                     "finish_reason": "stop"}],
        "usage": {"prompt_tokens": 100, "completion_tokens": 10, "total_tokens": 110},
    })


def isolated_openai(**kwargs):
    # Test substitutes HTTP transport only; actual SDK validates and serializes.
    return original_openai(**kwargs, max_retries=0,
                           http_client=httpx.Client(transport=httpx.MockTransport(fake_response),
                                                    trust_env=False))


openai.OpenAI = isolated_openai
fake_env = {"DEEPSEEK_API_KEY": "offline-synthetic-key",
            "CUSTOMIZED_API_KEY": "offline-synthetic-key"}
ns = dict(json=json, re=re, time=time, Path=Path, Any=Any, Dict=Dict, List=List,
          Optional=Optional, Tuple=Tuple, urlparse=urlparse,
          os=SimpleNamespace(environ=fake_env),
          logger=logging.getLogger("offline-cassia-probe"), __name__="offline_cassia")


def load_definitions(path, names=None):
    tree = ast.parse(path.read_text())
    selected = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.ClassDef)):
            if names is None or node.name in names:
                selected.append(node)
        elif isinstance(node, ast.Assign) and names is None:
            try:
                ast.literal_eval(node.value)
            except (ValueError, TypeError):
                continue
            selected.append(node)
    exec(compile(ast.Module(selected, type_ignores=[]), str(path), "exec"), ns)


load_definitions(FILES["settings"])
settings = ns["ModelSettings"](str(FILES["config"]))
load_definitions(FILES["llm"])
ns["resolve_model_name"] = settings.resolve_model_name
load_definitions(FILES["engine"])
load_definitions(FILES["tools"], {"_run_core_analysis", "_normalize_reasoning"})

scenarios = [
    ("deepseek_flash_none", "deepseek-flash", "https://api.deepseek.com", 0, "none", False),
    ("deepseek_pro_none", "deepseek-v4-pro", "https://api.deepseek.com", 0, "none", False),
    ("grok_medium", "grok-4.7", "https://api.x.ai/v1", .7, "medium", False),
    ("grok_high", "grok-4.7", "https://api.x.ai/v1", .7, "high", False),
    ("grok_maximal_loop", "grok-4.7", "https://api.x.ai/v1", .7, "high", True),
]
results = []
for name, model, provider, temperature, effort, maximal in scenarios:
    wire_calls.clear()
    scenario["maximal"] = maximal
    resolved_model, resolved_provider = settings.resolve_model_name(model, provider, verbose=False)
    ns["reset_llm_usage_log"]()
    with contextlib.redirect_stdout(io.StringIO()):
        result, history = ns["_run_core_analysis"](
            model=resolved_model, temperature=temperature,
            marker_list=["MS4A1", "CD79A", "CD37"], tissue="blood", species="human",
            additional_info="Synthetic marker fixture for offline transport verification.",
            provider=resolved_provider, validator_involvement="v1",
            reasoning=ns["_normalize_reasoning"](effort))
    assert len(wire_calls) == (19 if maximal else 3)
    assert all(call["body"]["model"] == model for call in wire_calls)
    assert all(call["body"]["temperature"] == temperature for call in wire_calls)
    assert all(call["url"] == provider.rstrip("/") + "/chat/completions"
               for call in wire_calls)
    first = wire_calls[0]["body"]
    expected_disabled = name == "deepseek_pro_none"
    assert (first.get("thinking") == {"type": "disabled"}) == expected_disabled
    assert all("tools" not in call["body"] for call in wire_calls)
    assert "reasoning_effort" not in first
    results.append({
        "scenario": name, "requested_model": model, "resolved_model": resolved_model,
        "provider": provider, "requested_effort": effort, "temperature": temperature,
        "calls": len(wire_calls), "iterations": result["iterations"],
        "all_wire_models_identical": True,
        "wire_keys": sorted(first),
        "wire_max_tokens": first["max_tokens"],
        "wire_thinking": first.get("thinking"),
        "wire_reasoning_effort": first.get("reasoning_effort"),
        "wire_urls": sorted({call["url"] for call in wire_calls}),
        "full_wire_body_hashes": [
            hashlib.sha256(json.dumps(call["body"], sort_keys=True).encode()).hexdigest()
            for call in wire_calls],
        "recorded_usage_requests": ns["get_llm_usage_summary"]()["requests"],
    })

output = {
    "date": "2026-10-20", "cassia_commit": COMMIT,
    "python": sys.version.split()[0], "openai_sdk": openai.__version__,
    "httpx": httpx.__version__, "network_calls": 0, "actual_provider_calls": 0,
    "actual_cost_usd": None,
    "coverage": "Actual resolver, annotation/validator/formatter, SDK JSON serialization; "
                "in-memory HTTP. Does not install full CASSIA, execute batch validation, "
                "test provider acceptance, or establish annotation accuracy.",
    "source_sha256": {key: hashlib.sha256(path.read_bytes()).hexdigest()
                      for key, path in FILES.items()},
    "results": results,
}
destination = ROOT / "probe_cassia_deepseek_grok.json"
destination.write_text(json.dumps(output, indent=2) + "\n")
print(json.dumps(output, indent=2))
