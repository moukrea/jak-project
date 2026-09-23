#!/usr/bin/env python3
"""`autoport profile` — modele et effort de chaque role, en UN endroit, par une commande.

Livrable 2 de owner-attention-aux-profils-opus-5-5-bouscule-tout : changer un role sans
editer `model-profiles.json` a la main. Toute ecriture passe par `lib.model_profile.resolve`
avant d'etre posee sur disque : un changement qui casserait le profil est refuse, fichier
intact.
"""
from __future__ import annotations

import collections
import datetime
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT = HERE.parents[2]

sys.path.insert(0, str(HERE.parent))
import model_profile  # noqa: E402
import model_ban  # noqa: E402

ROLE_FIELDS = {
    "supervisor": ("supervisor_model", "supervisor_effort"),
    "manager": ("manager_model", "manager_effort"),
}
RESEARCHER_LIKE = {
    "researcher": "autoport-researcher",
    "implementer": "autoport-implementer",
    "tester": "autoport-tester",
}


def _default_profiles_path():
    return ROOT / ".autoport" / "model-profiles.json"


def _default_agents_dir():
    return ROOT / ".claude" / "agents"


def _add_common(ap):
    ap.add_argument("--profiles", default=str(_default_profiles_path()))
    ap.add_argument("--agents-dir", default=str(_default_agents_dir()))


def _load_ordered(path):
    return json.loads(Path(path).read_text(), object_pairs_hook=collections.OrderedDict)


def _sha12(path):
    import hashlib
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()[:12]


def _write_atomic(path, cfg):
    path = Path(path)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


def _run_sync(args):
    return cmd_sync(args)


# ------------------------------------------------------------------ show
def cmd_show(args):
    cfg = _load_ordered(args.profiles)
    try:
        resolved = model_profile.resolve(cfg, source=args.profiles)
    except model_profile.ProfileUnresolved as e:
        print(f"REFUS : {e}")
        return 1

    if args.json:
        print(json.dumps({
            "active": cfg.get("active"),
            "roles": {k: list(v) for k, v in model_profile.roles(resolved).items()},
            "banned_ids": (cfg.get("banned_models") or {}).get("ids", []),
            "banned_aliases": (cfg.get("banned_models") or {}).get("aliases", []),
        }, ensure_ascii=False, indent=2))
        return 0

    print(f"profil actif: {cfg.get('active')}")
    print()
    print("role -> modele / effort (champ)")
    for role, (model, effort, field) in sorted(model_profile.roles(resolved).items()):
        print(f"  {role:<12} {model} / {effort}  ({field})")
    print()
    spec = (cfg.get("banned_models") or {})
    print(f"bannis: ids={spec.get('ids', [])} aliases={spec.get('aliases', [])}")

    trials = cfg.get("trials") or {}
    active_trials = [(n, t) for n, t in trials.items()
                     if not n.startswith("_") and isinstance(t, dict) and t.get("active")]
    print()
    if active_trials:
        print("essais actifs:")
        for name, t in active_trials:
            arms = ", ".join(sorted((t.get("arms") or {}).keys()))
            print(f"  {name} applies_to={t.get('applies_to')} arms=[{arms}]")
    else:
        print("essais actifs: aucun")

    print()
    agents_dir = Path(args.agents_dir)
    worker_efforts = resolved.get("worker_efforts") or {}
    for agent in sorted(worker_efforts):
        expected = worker_efforts[agent]
        p = agents_dir / f"{agent}.md"
        found = None
        if p.is_file():
            text = p.read_text(errors="replace")
            found = _frontmatter_effort(text)
        tag = "DESYNC" if found != expected else "ok"
        print(f"agent {agent}: frontmatter={found!r} profil={expected!r} [{tag}]")

    print()
    if str(Path(args.profiles).resolve()) == str(_default_profiles_path().resolve()):
        n = len(model_ban.scan(ROOT, processes=False))
        print(f"banned_model_paths={n}")
    else:
        print("banned_model_paths=non-mesure (copie)")
    return 0


def _frontmatter_effort(text):
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    body = text[3:end if end > 0 else len(text)]
    for line in body.splitlines():
        line = line.strip()
        if line.startswith("effort:"):
            return line.split(":", 1)[1].strip()
    return None


# ------------------------------------------------------------------ set
def cmd_set(args):
    if args.model is None and args.effort is None:
        print("REFUS : indique --model et/ou --effort")
        return 2

    cfg = _load_ordered(args.profiles)
    active = cfg.get("active")
    profiles = cfg.get("profiles") or {}
    if active not in profiles:
        print(f"REFUS : profil actif « {active} » introuvable")
        return 2
    prof = profiles[active]
    spec = model_profile.banned_spec(cfg)

    changes = []  # (field, old, new)

    if args.role == "subagents":
        if args.model is not None:
            if not args.model.strip() or model_profile.is_banned(args.model, spec):
                print(f"REFUS : {args.model} est BANNI (banned_models de model-profiles.json)")
                return 2
            old = prof.get("worker_model")
            prof["worker_model"] = args.model
            changes.append(("worker_model", old, args.model))
        if args.effort is not None:
            if args.effort not in model_profile.EFFORTS:
                print(f"REFUS : effort inconnu « {args.effort} » (attendu: {', '.join(model_profile.EFFORTS)})")
                return 2
            efforts = prof.setdefault("worker_efforts", collections.OrderedDict())
            for agent in list(efforts.keys()):
                old = efforts[agent]
                if old != args.effort:
                    efforts[agent] = args.effort
                    changes.append((f"worker_efforts.{agent}", old, args.effort))
    elif args.role in RESEARCHER_LIKE:
        if args.model is not None:
            print("REFUS : un seul modele pour tous les sous-agents "
                  "(CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1) : utilise « profile set subagents --model M »")
            return 2
        if args.effort is not None:
            if args.effort not in model_profile.EFFORTS:
                print(f"REFUS : effort inconnu « {args.effort} » (attendu: {', '.join(model_profile.EFFORTS)})")
                return 2
            agent = RESEARCHER_LIKE[args.role]
            efforts = prof.setdefault("worker_efforts", collections.OrderedDict())
            old = efforts.get(agent)
            efforts[agent] = args.effort
            changes.append((f"worker_efforts.{agent}", old, args.effort))
    elif args.role in ROLE_FIELDS:
        model_field, effort_field = ROLE_FIELDS[args.role]
        if args.model is not None:
            if not args.model.strip() or model_profile.is_banned(args.model, spec):
                print(f"REFUS : {args.model} est BANNI (banned_models de model-profiles.json)")
                return 2
            old = prof.get(model_field)
            prof[model_field] = args.model
            changes.append((model_field, old, args.model))
        if args.effort is not None:
            if args.effort not in model_profile.EFFORTS:
                print(f"REFUS : effort inconnu « {args.effort} » (attendu: {', '.join(model_profile.EFFORTS)})")
                return 2
            old = prof.get(effort_field)
            prof[effort_field] = args.effort
            changes.append((effort_field, old, args.effort))
    else:
        print(f"REFUS : role inconnu « {args.role} »")
        return 2

    if not changes:
        print("rien a changer")
        return 0

    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    history = prof.setdefault("_history", [])
    for field, old, new in changes:
        history.append({"date": now, "role": args.role, "field": field, "old": old,
                        "new": new, "by": "autoport profile set"})

    # Verify resolve BEFORE writing.
    try:
        model_profile.resolve(cfg, source=args.profiles)
    except model_profile.ProfileUnresolved as e:
        print(f"REFUS : {e}")
        return 2

    _write_atomic(args.profiles, cfg)
    rc = _run_sync(args)
    for field, old, new in changes:
        print(f"{args.role} : {field} {old} -> {new}")
    new_sha = _sha12(args.profiles)
    print(f"Appliqué à la prochaine frontière d'item : l'orchestrateur relit ce fichier "
          f"avant chaque essai (bannière « profil relu sha={new_sha} »). "
          f"Superviseur : au prochain ./run-supervisor.sh.")
    return 0 if rc == 0 else rc


# ------------------------------------------------------------------ use
def cmd_use(args):
    cfg = _load_ordered(args.profiles)
    name = args.name
    retired = cfg.get("retired_profiles") or {}
    profiles = cfg.get("profiles") or {}
    if name in retired:
        note = str((retired[name] or {}).get("_note", ""))[:200]
        print(f"REFUS : profil RETIRE" + (f" : {note}" if note else ""))
        return 2
    if name not in profiles:
        print(f"REFUS : profil inconnu « {name } » (connus : {', '.join(sorted(profiles)) or 'aucun'})")
        return 2

    old_active = cfg.get("active")
    new_cfg = json.loads(json.dumps(cfg))
    new_cfg["active"] = name
    try:
        model_profile.resolve(new_cfg, source=args.profiles)
    except model_profile.ProfileUnresolved as e:
        print(f"REFUS : {e}")
        return 2

    cfg["active"] = name
    _write_atomic(args.profiles, cfg)
    rc = _run_sync(args)
    print(f"active : {old_active} -> {name}")
    new_sha = _sha12(args.profiles)
    print(f"Appliqué à la prochaine frontière d'item : l'orchestrateur relit ce fichier "
          f"avant chaque essai (bannière « profil relu sha={new_sha} »). "
          f"Superviseur : au prochain ./run-supervisor.sh.")
    return 0 if rc == 0 else rc


# ------------------------------------------------------------------ check
def cmd_check(args):
    found = model_ban.scan(ROOT, processes=True)
    for f in found:
        print(f"BANNI [{f['kind']}] {f['where']} : {f['detail']}")
    print(f"banned_model_paths={len(found)}")
    return 1 if found else 0


# ------------------------------------------------------------------ sync
def cmd_sync(args):
    cfg = _load_ordered(args.profiles)
    active = cfg.get("active")
    profiles = cfg.get("profiles") or {}
    prof = profiles.get(active) or {}
    efforts = prof.get("worker_efforts") or {}
    agents_dir = Path(args.agents_dir)

    for agent in ("autoport-researcher", "autoport-implementer", "autoport-tester"):
        eff = efforts.get(agent)
        if not eff:
            print(f"  skip {agent} (no effort in profile)")
            continue
        p = agents_dir / f"{agent}.md"
        if not p.is_file():
            print(f"  WARN: {p} missing")
            continue
        text = p.read_text()
        if not text.startswith("---"):
            print(f"  WARN: no frontmatter in {p}")
            continue
        end = text.find("\n---", 3)
        if end < 0:
            print(f"  WARN: no effort: line in {p} (frontmatter manual)")
            continue
        head, tail = text[:end], text[end:]
        lines = head.splitlines(keepends=True)
        new_lines = []
        replaced = False
        for line in lines:
            if not replaced and line.lstrip().startswith("effort:"):
                nl = "\n" if line.endswith("\n") else ""
                new_lines.append(f"effort: {eff}{nl}")
                replaced = True
            else:
                new_lines.append(line)
        if not replaced:
            print(f"  WARN: no effort: line in {p} (frontmatter manual)")
            continue
        new_text = "".join(new_lines) + tail
        if new_text != text:
            p.write_text(new_text)
            print(f"{agent} -> effort: {eff}")
        else:
            print(f"{agent} -> effort: {eff} (inchangé)")
    return 0


# ------------------------------------------------------------------ main
def main(argv=None) -> int:
    import argparse
    ap = argparse.ArgumentParser(prog="autoport profile")
    sub = ap.add_subparsers(dest="subcmd")

    sh = sub.add_parser("show")
    _add_common(sh)
    sh.add_argument("--json", action="store_true")
    sh.set_defaults(func=cmd_show)

    st = sub.add_parser("set")
    _add_common(st)
    st.add_argument("role", choices=["supervisor", "manager", "subagents",
                                     "researcher", "implementer", "tester"])
    st.add_argument("--model", default=None)
    st.add_argument("--effort", default=None)
    st.set_defaults(func=cmd_set)

    us = sub.add_parser("use")
    _add_common(us)
    us.add_argument("name")
    us.set_defaults(func=cmd_use)

    ch = sub.add_parser("check")
    _add_common(ch)
    ch.set_defaults(func=cmd_check)

    sy = sub.add_parser("sync")
    _add_common(sy)
    sy.set_defaults(func=cmd_sync)

    args = ap.parse_args(argv)
    if args.subcmd is None:
        args = ap.parse_args(["show"] + (argv or []))
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
