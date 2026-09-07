#!/usr/bin/env python3
"""Adapt Codex lifecycle and apply_patch to the existing mechanical guards."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    event = sys.argv[1]
    data = json.load(sys.stdin)
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(ROOT))
    phase = env.get("AUTOPORT_PHASE_ID")
    if event == "SessionStart" and env.get("AUTOPORT_ROLE") == "supervisor" and not phase:
        session_id = data.get("session_id")
        if session_id:
            target = ROOT / '.autoport/.supervisor-codex-session'
            tmp = target.with_name(target.name + f'.{os.getpid()}.tmp')
            tmp.write_text(str(session_id) + '\n')
            tmp.replace(target)
            launch_file = env.get('AUTOPORT_SUPERVISOR_SESSION_FILE')
            if launch_file:
                Path(launch_file).write_text(str(session_id) + '\n')
        return 0
    if event == "SubagentStart":
        print("Lis .autoport/codex/roles.md. Rôle borné par le manager. Conserve le périmètre et DIRECTIVES <version>. "
              "Recherche : lecture seule. Implémentation : spec exacte, pas de validateur modifié. "
              "Test : commandes et preuves programmatiques, aucune modification des sources. "
              "Ne lance jamais une autre CLI : utilise les outils de sous-agents Codex.")
        return 0
    if event == "PreToolUse":
        if phase:
            # Claim again before EVERY tool: SessionStart alone only informs a duplicate.
            claim = subprocess.run(["bash", str(ROOT / '.autoport/phase_claim.sh'), "claim", phase],
                                   env=env, capture_output=True, text=True)
            if claim.returncode:
                print("Tâche déjà tenue ou verrou indisponible : " + claim.stdout + claim.stderr, file=sys.stderr)
                return 2
        if data.get("tool_name") == "apply_patch":
            patch = data.get("tool_input", {})
            patch = patch.get("command", patch.get("patch", "")) if isinstance(patch, dict) else patch
            for path in re.findall(r'^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+)$', str(patch), re.M):
                p = Path(path)
                p = (Path(data.get("cwd", str(ROOT))) / p).resolve() if not p.is_absolute() else p.resolve()
                if p.is_relative_to(ROOT / '.autoport/reports') and p.suffix.lower() == '.png':
                    print("Preuve visuelle interdite : produis un compteur via proof_run.sh.", file=sys.stderr)
                    return 2
            return 0
        if data.get("tool_name") in ("exec_command", "shell_command", "shell"):
            data["tool_name"] = "Bash"
            args = data.get("tool_input", {})
            command = args.get("command", args.get("cmd", ""))
            if isinstance(command, list):
                command = " ".join(command)
            data["tool_input"] = {"command": command}
        return subprocess.run(["bash", str(ROOT / '.autoport/hooks/pre-tool.sh')],
                              input=json.dumps(data), text=True, env=env).returncode
    if event == "SessionStart" and phase:
        return subprocess.run(["bash", str(ROOT / '.autoport/hooks/session-start.sh')], env=env).returncode
    if event == "SessionEnd" and phase:
        # Only the root thread ends the process claim. No validator here: orchestrator judges.
        return subprocess.run(["bash", str(ROOT / '.autoport/phase_claim.sh'), "release", phase], env=env).returncode
    return 0


if __name__ == '__main__':
    sys.exit(main())
