#!/usr/bin/env python3
"""LA PORTE DES MODELES BANNIS : tout chemin VIVANT qui peut lancer Opus 5 ou Fable 5.1.

MARQUEUR: modele-banni-refuse-2026-09-23
Owner, 23/09 (JAK-265) : « Claude Opus 5 est a bannir, Fable 5.1 aussi [...] faut etre surs que
rien ne tourne ni sous Opus 5, ni sous Fable 5.1 ». Releve du superviseur le meme jour :
`supervisor.sh` repliait EN DUR sur claude-opus-5 (superviseur ET sous-agents), l'orchestrateur
gardait un repli claude-fable-5-1[1m], six profils sur sept nommaient l'un ou l'autre.

La liste des bannis vit dans UN fichier : `model-profiles.json` -> `banned_models`. Ce module
ne connait aucun nom de modele ; il compte, et NOMME, chaque chemin qui en nomme un :

  profile          un profil SELECTIONNABLE (`profiles`) dont un champ *_model est banni
  trial            un bras d'essai croise (`trials`) qui poserait un modele banni
  codex-profile    idem dans `codex/profiles.json`
  code             un identifiant banni ECRIT dans le code d'un script du harnais (chaines
                   Python hors docstrings, lignes shell hors commentaires). Les tables de
                   DONNEES (tarifs pour chiffrer l'historique) sont exemptees par NOM dans
                   `banned_models.data_only`, et seulement si le fichier ne lance aucune CLI
  agent            `model:` d'un `.claude/agents/*.md` (identifiant ou alias, ex. « fable »)
  settings         `model`, `fallbackModel`, `env.*MODEL*` d'un settings.json lu par la CLI
  subagent-force   un lanceur qui ne pose pas CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 : le
                   parametre `model` d'un appel Agent (« fable ») passerait alors avant le profil
  launch-gate      `model_profile.resolve` ACCEPTE un profil actif banni (la porte de
                   lancement est morte)
  process          un processus `claude` VIVANT dont `--model` ou l'environnement nomme un banni
  unreadable       un fichier de la liste qu'on n'a pas pu lire : INCONNU = DEFAUT

`scan()` rend la liste ; `banned_model_paths` = sa longueur.
"""
from __future__ import annotations

import ast
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import model_profile  # noqa: E402

# Repertoires qui ne LANCENT rien : journaux, rapports, archives, consignes, bancs de preuve.
SKIP_DIRS = {"logs", "reports", "archive", "prompts", "plans", "tests", "census",
             "owner-feedback", "tmp", "worktrees", "__pycache__", "notes", ".git"}
# Lanceurs qui doivent imposer le modele des sous-agents.
FORCE_LAUNCHERS = (".autoport/orchestrator.py", ".autoport/supervisor.sh")
# Lanceurs connus : toujours scannes, meme si la decouverte les ratait.
KNOWN_LAUNCHERS = (".autoport/supervisor.sh", ".autoport/orchestrator.py",
                   ".autoport/lib/cli_backend.py", ".autoport/lib/model_profile.py",
                   ".autoport/codex/supervisor.py", ".autoport/backend_switch.py",
                   ".autoport/supervisor_terminal.py", ".autoport/watch.py",
                   ".autoport/apply-model-profile.sh", ".autoport/autoport",
                   "launch.sh", "run-supervisor.sh", "run-codex.sh")
SETTINGS = (".autoport/settings.json", ".claude/settings.json", ".claude/settings.local.json")
LAUNCH_SH = re.compile(r"(^|[;&|(`]\s*|\bexec\s+|^\s*)claude(\s|$)|--model\b")


def _code_strings_py(text: str):
    """(ligne, chaine) des constantes str du CODE : docstrings et chaines nues exclues."""
    tree = ast.parse(text)
    bare = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant) \
                and isinstance(node.value.value, str):
            bare.add(id(node.value))
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str) and id(node) not in bare:
            yield node.lineno, node.value


def _code_lines_sh(text: str):
    for n, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        yield n, re.sub(r"\s#.*$", "", line)


def _is_python(path: Path, text: str) -> bool:
    return path.suffix == ".py" or text.startswith("#!/usr/bin/env python")


def _launches(path: Path, text: str) -> bool:
    """Le fichier lance-t-il une CLI de modele ? (sert a refuser l'exemption « donnees »)."""
    if _is_python(path, text):
        try:
            strs = [s for _, s in _code_strings_py(text)]
        except SyntaxError:
            return True
        return any(s in ("claude", "codex", "--model") or "SUBAGENT_MODEL" in s for s in strs)
    return any(LAUNCH_SH.search(l) for _, l in _code_lines_sh(text))


def harness_code_files(root: Path):
    ap = root / ".autoport"
    seen = set()
    for rel in KNOWN_LAUNCHERS:
        p = root / rel
        if p.is_file():
            seen.add(p)
            yield p
    for dirpath, dirnames, filenames in os.walk(ap):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for f in filenames:
            p = Path(dirpath) / f
            if p in seen or ".bak" in f or "selftest" in f or f.startswith("test_"):
                continue
            if f.endswith((".py", ".sh")):
                seen.add(p)
                yield p
    for p in (ap / "hooks").glob("*"):
        if p.is_file() and p not in seen and p.suffix in (".py", ".sh"):
            yield p


def _rel(root: Path, p: Path) -> str:
    try:
        return str(p.relative_to(root))
    except ValueError:
        return str(p)


def _frontmatter_model(text: str):
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    for line in text[3:end if end > 0 else len(text)].splitlines():
        m = re.match(r"\s*model\s*:\s*['\"]?([^'\"#\s]+)", line)
        if m:
            return m.group(1)
    return None


def _live_processes(spec) -> list[tuple[str, str]]:
    out = []
    for d in Path("/proc").iterdir():
        if not d.name.isdigit():
            continue
        try:
            argv = (d / "cmdline").read_bytes().split(b"\0")
            if not argv or os.path.basename(argv[0].decode(errors="replace")) != "claude":
                continue
            args = [a.decode(errors="replace") for a in argv if a]
            env = dict(e.decode(errors="replace").split("=", 1)
                       for e in (d / "environ").read_bytes().split(b"\0") if b"=" in e)
        except OSError:
            continue
        cands = []
        for i, a in enumerate(args):
            if a == "--model" and i + 1 < len(args):
                cands.append(("--model", args[i + 1]))
            elif a.startswith("--model="):
                cands.append(("--model", a.split("=", 1)[1]))
        for k in ("ANTHROPIC_MODEL", "CLAUDE_CODE_SUBAGENT_MODEL"):
            if env.get(k):
                cands.append((k, env[k]))
        for where, m in cands:
            if model_profile.is_banned(m, spec):
                out.append((f"process:{d.name}", f"{where}={m}"))
    return out


def scan(root, *, home=None, processes=True) -> list[dict]:
    root = Path(root).resolve()
    ap = root / ".autoport"
    found: list[dict] = []

    def add(kind, where, detail):
        found.append({"kind": kind, "where": where, "detail": detail})

    cfg_path = ap / "model-profiles.json"
    try:
        cfg = json.loads(cfg_path.read_text())
        spec = model_profile.banned_spec(cfg if isinstance(cfg.get("banned_models"), dict)
                                         else {"banned_models": {}})
    except (OSError, ValueError) as e:
        add("unreadable", _rel(root, cfg_path), f"liste des bannis illisible : {e}")
        return found
    lit = model_profile.literal_regex(spec)
    data_only = set((cfg.get("banned_models") or {}).get("data_only") or {})

    # -- profils selectionnables, bras d'essai, profils Codex
    for name, prof in (cfg.get("profiles") or {}).items():
        for k, v in (prof or {}).items():
            if k.endswith("_model") and isinstance(v, str) and model_profile.is_banned(v, spec):
                add("profile", f"model-profiles.json:profiles.{name}.{k}", v)
    for tname, t in (cfg.get("trials") or {}).items():
        if tname.startswith("_") or not isinstance(t, dict):
            continue
        for arm, over in (t.get("arms") or {}).items():
            for k, v in (over or {}).items():
                if k.endswith("_model") and model_profile.is_banned(v, spec):
                    add("trial", f"model-profiles.json:trials.{tname}.{arm}.{k}", v)
    cp = ap / "codex" / "profiles.json"
    if cp.is_file():
        try:
            for name, prof in (json.loads(cp.read_text()).get("profiles") or {}).items():
                for k, v in (prof or {}).items():
                    if k.endswith("_model") and isinstance(v, str) \
                            and model_profile.is_banned(v, spec):
                        add("codex-profile", f"codex/profiles.json:{name}.{k}", v)
        except (OSError, ValueError) as e:
            add("unreadable", _rel(root, cp), str(e))

    # -- la porte de lancement elle-meme : un profil actif banni doit etre REFUSE
    probe = json.loads(json.dumps(cfg))
    act = probe.get("active")
    if act in (probe.get("profiles") or {}):
        probe["profiles"][act]["manager_model"] = spec["ids"][0]
        try:
            model_profile.resolve(probe, source="sonde")
            add("launch-gate", "lib/model_profile.py:resolve",
                f"profil actif a {spec['ids'][0]} ACCEPTE")
        except model_profile.ProfileUnresolved:
            pass

    # -- code du harnais
    for p in harness_code_files(root):
        rel = _rel(root, p)
        try:
            text = p.read_text(errors="replace")
        except OSError as e:
            add("unreadable", rel, str(e))
            continue
        try:
            items = list(_code_strings_py(text)) if _is_python(p, text) else list(_code_lines_sh(text))
        except SyntaxError as e:
            add("unreadable", rel, f"Python illisible : {e}")
            continue
        hits = [(n, m.group(0)) for n, s in items for m in lit.finditer(s)]
        if not hits:
            continue
        if rel in data_only and not _launches(p, text):
            continue
        for n, h in hits:
            add("code", f"{rel}:{n}", h)

    # -- frontmatter des sous-agents
    for p in sorted((root / ".claude" / "agents").glob("*.md")):
        try:
            m = _frontmatter_model(p.read_text(errors="replace"))
        except OSError as e:
            add("unreadable", _rel(root, p), str(e))
            continue
        if m and model_profile.is_banned(m, spec):
            add("agent", _rel(root, p), f"model: {m}")

    # -- settings lus par la CLI
    paths = [root / s for s in SETTINGS]
    home = Path(home) if home is not None else Path.home()
    paths.append(home / ".claude" / "settings.json")
    for p in paths:
        if not p.is_file():
            continue
        try:
            st = json.loads(p.read_text())
        except (OSError, ValueError) as e:
            add("unreadable", str(p), str(e))
            continue
        cands = [(k, st.get(k)) for k in ("model", "fallbackModel")]
        cands += [(f"env.{k}", v) for k, v in (st.get("env") or {}).items() if "MODEL" in k]
        for k, v in cands:
            if isinstance(v, str) and model_profile.is_banned(v, spec):
                add("settings", f"{p}:{k}", v)

    # -- le modele des sous-agents est-il IMPOSE par chaque lanceur ?
    for rel in FORCE_LAUNCHERS:
        p = root / rel
        try:
            text = p.read_text(errors="replace")
        except OSError as e:
            add("unreadable", rel, str(e))
            continue
        if _is_python(p, text):
            ok = any(s == "CLAUDE_CODE_SUBAGENT_MODEL_FORCE" for _, s in _code_strings_py(text))
        else:
            ok = any(re.search(r"CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1\b", l)
                     for _, l in _code_lines_sh(text))
        if not ok:
            add("subagent-force", rel, "CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 absent")

    if processes:
        for where, detail in _live_processes(spec):
            add("process", where, detail)
    return found


def main(argv=None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    ap.add_argument("--home", default=None)
    ap.add_argument("--no-processes", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    found = scan(a.root, home=a.home, processes=not a.no_processes)
    if a.json:
        print(json.dumps({"banned_model_paths": len(found), "paths": found},
                         ensure_ascii=False, indent=2))
    else:
        for f in found:
            print(f"BANNI [{f['kind']}] {f['where']} : {f['detail']}")
        print(f"banned_model_paths={len(found)}")
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main())
