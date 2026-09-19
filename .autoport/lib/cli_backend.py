"""CLI boundary: launch configuration and Codex's public exec event protocol.

No state migration, quota probes or authentication-file parsing here.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
from pathlib import Path

BACKENDS = ("claude", "codex")


def selected(value=None, root=None):
    from lib import backend_control
    name = value or os.environ.get("AUTOPORT_BACKEND") or (
        backend_control.default(root) if root is not None else backend_control.default())
    if name not in BACKENDS:
        raise ValueError(f"backend inconnu : {name!r} (claude ou codex)")
    return name


def codex_profile(root):
    cfg = json.loads((Path(root) / ".autoport/codex/profiles.json").read_text())
    profile = dict(cfg["profiles"][cfg["active"]])
    profile["_active_name"] = cfg["active"]
    for key in ("manager_model", "manager_effort", "worker_model", "worker_efforts"):
        if key not in profile:
            raise ValueError(f"profil Codex incomplet : {key}")
    if profile.get("sandbox") not in ("read-only", "workspace-write", "danger-full-access"):
        raise ValueError("sandbox Codex invalide")
    return profile


def toml(value):
    """Small encoder for CLI -c values (JSON objects are NOT TOML tables)."""
    if isinstance(value, dict):
        return "{" + ", ".join(f"{json.dumps(k)} = {toml(v)}" for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "[" + ", ".join(map(toml, value)) + "]"
    return json.dumps(value, ensure_ascii=False)


def codex_options(root, profile, effort=None, supervisor=False):
    root = Path(root).resolve()
    opts = ["--sandbox", profile["sandbox"], "-c", 'approval_policy="never"',
            "-c", "model_reasoning_effort=" + toml(effort or profile["manager_effort"]),
            "-c", "features.hooks=true"]
    if profile["manager_model"]:
        opts += ["--model", profile["manager_model"]]
    if profile["worker_model"]:
        opts += ["-c", "agents.default_subagent_model=" + toml(profile["worker_model"])]
    opts += ["-c", "agents.enabled=true", "-c", "agents.max_concurrent_threads_per_session=3"]
    # Scoped to the invocation: no edits of ~/.codex or .codex, no copied credentials.
    # Hooks are the reviewed autoport sources; the CLI flag makes them execute in exec.
    opts += ["--dangerously-bypass-hook-trust"]
    for event, timeout in (("SessionStart", 30), ("SubagentStart", 30),
                           ("PreToolUse", 10), ("SessionEnd", 3)):
        cmd = shlex.join(["python3", str(root / ".autoport/codex/hook.py"), event])
        groups = [{"hooks": [{"type": "command", "command": cmd, "timeout": timeout}]}]
        opts += ["-c", f"hooks.{event}=" + toml(groups)]
    if supervisor:
        contract = (root / ".autoport/SUPERVISOR_PROMPT.md").read_text()
        contract += ("\nCLI active : Codex. Toute relance utilise ./launch.sh --backend codex.\n"
                     "La veille est .autoport/supervisor.sh --backend codex --watch --maintain --notify-supervisor.\n"
                     "Lis .autoport/SWITCH_HANDOFF.md si présent, puis .autoport/SUPERVISOR_CATCHUP.md et autoport status au démarrage.\n")
        opts += ["-c", "developer_instructions=" + toml(contract)]
    return opts


def worker_command(root, backend, profile, effort, max_turns):
    if backend == "claude":
        cmd = ["claude", "-p", "--model", profile["manager_model"], "--effort", effort,
                "--max-turns", str(min(max_turns, 300)), "--output-format", "stream-json",
                "--verbose", "--dangerously-skip-permissions"]
        settings = Path(root) / ".autoport/settings.json"
        local = Path(root) / ".claude/settings.local.json"
        # Existing installations already load this exact symlink. Do not register twice.
        if local.resolve() != settings.resolve():
            cmd += ["--settings", str(settings)]
        return cmd
    return ["codex", "exec", *codex_options(root, profile, effort), "--json", "--color", "never", "-"]


def auth_error():
    try:
        r = subprocess.run(["codex", "login", "status"], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"authentification Codex invérifiable : {e}"
    if r.returncode and not os.environ.get("CODEX_API_KEY"):
        return "Codex non authentifié : exécute codex login dans ton terminal."
    return ""


def codex_error(ev):
    """Only errors emitted by the CLI; never scan tool output or agent prose."""
    if ev.get("type") not in ("error", "turn.failed"):
        return ""
    error = ev.get("error", ev)
    return str(error.get("message", "")) if isinstance(error, dict) else str(error)


def error_kind(message):
    if re.search(r'(?i)\b429\b|usage limit|rate.?limit|quota exceeded|usage_limit_reached', message):
        return "rate"
    if re.search(r'(?i)\b(401|403|404)\b|not authenticated|invalid.*key|model.*(not found|not supported|does not exist)|authentication', message):
        return "config"
    if re.search(r'(?i)\b(500|502|503|504|529)\b|stream disconnected|connection (reset|closed)|server error|service unavailable|error sending request', message):
        return "infra"
    return ""


def update_codex(ev, state):
    """Update live/attempt accounting; return compact text for rendering."""
    kind = ev.get("type")
    if kind == "thread.started":
        state.session_id = ev.get("thread_id", "")
        return "▶ codex session " + state.session_id[:8]
    if kind == "turn.completed":
        state.result_seen = True
        usage = ev.get("usage") or {}
        # `turn.completed` est un DELTA de tour : il s'ajoute, il ne remplace pas. Il passe
        # par `add_live` parce que les totaux de `PrettyState` sont desormais des proprietes
        # (harness-usage-double-counted, 19/09) : plus aucun compteur ne se `+=` a l'aveugle.
        # NOTE : chez OpenAI `input_tokens` INCLUT `cached_input_tokens` — cette ligne compte
        # donc le cache codex deux fois. Hors perimetre de cet item (voir FINDINGS).
        state.add_live(inp=int(usage.get("input_tokens", 0) or 0),
                       out=int(usage.get("output_tokens", 0) or 0),
                       cread=int(usage.get("cached_input_tokens", 0) or 0))
        return f"✓ codex · in {state.tokens_in} out {state.tokens_out} cache {state.cache_read}"
    error = codex_error(ev)
    if error:
        state.cli_error = error
        if kind == "turn.failed":
            state.result_seen = True
            state.cli_failed = True
        if error_kind(error) == "rate":
            state.rate_rejected = True
            data = ev.get("error", ev)
            if isinstance(data, dict):
                reset = data.get("resets_at", data.get("resetsAt"))
                if isinstance(reset, (int, float)):
                    state.rate_reset_at = int(reset)
        return "Codex : " + error
    if kind in ("item.started", "item.completed"):
        item = ev.get("item") or {}
        typ, iid = item.get("type"), item.get("id")
        if typ in ("command_execution", "file_change", "mcp_tool_call", "web_search", "collab_tool_call"):
            key = str(iid) if iid is not None else str(item)
            if key not in state.tool_use_names:
                state.tool_use_names[key] = typ
                state.tool_calls += 1
                state.dirty_since_tick = True
                return "🔧 " + typ + " " + str(item.get("command", item.get("tool", item.get("changes", ""))))[:200]
        if typ == "agent_message" and kind == "item.completed":
            return str(item.get("text", ""))[:200]
    return ""
