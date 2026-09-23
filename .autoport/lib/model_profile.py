#!/usr/bin/env python3
"""LE PROFIL DE MODELE SE RESOUT ICI, ET UN PROFIL NON RESOLU REFUSE DE PARTIR.

POURQUOI CE FICHIER EXISTE (harness-undeclared-profile-attempts, 2026-09-19).
MARQUEUR: profil-resolu-ou-refus-2026-09-19

VINGT-HUIT ESSAIS SONT PARTIS SANS QU'AUCUN MODELE NE SOIT CHOISI. Releve sur les
journaux, pas sur une impression : `logs/<item>/attempt-NNN.jsonl`, premiere ligne,
`attempt_start.model == ""` ET `attempt_start.subagent_model == ""`. Vingt-huit
occurrences, TOUTES `backend=codex`, TOUTES le 2026-09-07 entre 09:37 et 16:01 UTC,
sur trois items (lighting-census 23, framerate-uncap 3, foliage-wind 2). Aucune n'a
abouti ; 46,4 % ont tourne en boucle. La ligne de commande enregistree dans ces
vingt-huit journaux ne porte NI `--model`, NI `agents.default_subagent_model`.

LA VOIE DE LANCEMENT, NOMMEE : `orchestrator.py --backend codex`
  -> `cli_backend.codex_profile()` lit `.autoport/codex/profiles.json`
  -> profil actif `codex-local`, `manager_model: ""` et `worker_model: ""`
  -> `codex_options()` portait `if profile["manager_model"]:` : une chaine vide etait
     lue comme « laisse la CLI choisir », et rien ne le disait a personne
  -> la banniere de l'orchestrateur affichait `modele=defaut CLI` (28 occurrences de
     `modele=defaut` dans `logs/orchestrator.log`, le meme compte, au meme endroit).

LE CONTROLE NE PORTAIT QUE SUR LA PRESENCE DE LA CLEF : `if key not in profile`. Une
clef PRESENTE et VIDE passait. La donnee a ete corrigee le 2026-09-07 a 18:02:07
(commit 50e9dc5af6, l'owner a nomme Astra) — LA DONNEE SEULEMENT. Le CODE accepte
encore une chaine vide aujourd'hui : reposer `manager_model: ""` dans le profil actif
rendrait les vingt-huit suivants, a l'identique et sans un mot.

DONC : la perte est rendue impossible AU POINT DE PRODUCTION (DIRECTIVES/non-destruction).
Un profil dont un champ est vide n'est plus un profil : `faults()` le dit, `check()` et
`resolve()` LEVENT, et l'appelant refuse de partir au lieu de partir sur un defaut.

CE FICHIER NE CHOISIT AUCUN MODELE et n'en connait aucun nom. Il ne fait qu'une chose :
distinguer « quelqu'un a choisi » de « personne n'a choisi ».
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

# LE FICHIER DE CONFIGURATION UNIQUE (JAK-265, 23/09) : profils, liste des modeles BANNIS et
# essais croises vivent tous dans `.autoport/model-profiles.json`. Le profil Codex (autre
# fichier) est verifie contre la MEME liste de bannis : un seul endroit la porte.
PROFILES_PATH = Path(__file__).resolve().parent.parent / "model-profiles.json"
EFFORTS = ("low", "medium", "high", "xhigh", "max")
# Les champs d'un profil qui NOMMENT un modele. Un modele banni dans l'un d'eux = pas de depart.
MODEL_FIELDS = ("manager_model", "worker_model", "supervisor_model")

# Les trois champs qu'un essai DECLARE dans `attempt_start` et qui voyagent jusqu'a la
# ligne de commande de la CLI. Un seul vide, et l'essai ne sait pas sur quoi il tourne.
TEXT_FIELDS = ("manager_model", "manager_effort", "worker_model")


class ProfileUnresolved(ValueError):
    """Le profil n'est pas resolu : aucun essai ne doit partir.

    Sous-classe de `ValueError` pour que les appelants qui attrapaient deja
    `(ValueError, KeyError, OSError)` autour du chargement la voient sans changer."""


def faults(profile) -> list[str]:
    """Ce qui manque pour qu'un profil soit CHOISI, une phrase par defaut. [] = resolu.

    Rend une LISTE plutot que de lever : `run_attempt` a besoin de nommer les causes dans
    un `Outcome`, et une porte a besoin de les COMPTER. `check()` leve par-dessus."""
    if not isinstance(profile, dict):
        return [f"le profil n'est pas un objet mais un {type(profile).__name__}"]
    out: list[str] = []
    for key in TEXT_FIELDS:
        if key not in profile:
            out.append(f"{key} absent du profil")
            continue
        value = profile[key]
        if not isinstance(value, str):
            out.append(f"{key} n'est pas un texte ({type(value).__name__})")
        elif not value.strip():
            out.append(f"{key} est VIDE — c'est le défaut de la CLI, personne ne l'a choisi")
    efforts = profile.get("worker_efforts")
    if not isinstance(efforts, dict) or not efforts:
        out.append("worker_efforts absent ou vide : aucun effort choisi pour les sous-agents")
    else:
        for agent in sorted(efforts):
            effort = efforts[agent]
            if not isinstance(effort, str) or not effort.strip():
                out.append(f"worker_efforts[{agent}] est VIDE")
    name = profile.get("_active_name")
    if not isinstance(name, str) or not name.strip():
        out.append("aucun nom de profil résolu (_active_name)")
    elif name.startswith("FALLBACK"):
        # Le repli code en dur n'est le choix de personne : il n'a jamais ete ecrit dans
        # `model-profiles.json`, et son nom porte la raison du repli.
        out.append(f"profil de REPLI, choisi par personne : {name}")
    return out


def check(profile, *, source: str):
    """Rend le profil s'il est resolu, leve `ProfileUnresolved` sinon."""
    problems = faults(profile)
    if problems:
        raise ProfileUnresolved(f"{source} : " + " ; ".join(problems))
    return profile


def resolve(cfg, *, source: str):
    """`{active, profiles}` -> le profil ACTIF, verifie. Leve si quoi que ce soit manque.

    C'est le point unique : `orchestrator._load_model_profile` (Claude) et
    `cli_backend.codex_profile` (Codex) passent tous les deux par ici. Deux lectures
    ecrites a deux endroits divergent en silence — celle des vingt-huit essais etait
    exactement cela : Codex verifiait la presence des clefs, Claude aussi, et ni l'un ni
    l'autre ne regardait leur CONTENU."""
    if not isinstance(cfg, dict):
        raise ProfileUnresolved(f"{source} : le fichier ne contient pas un objet JSON")
    active = cfg.get("active")
    if not isinstance(active, str) or not active.strip():
        raise ProfileUnresolved(f"{source} : aucun profil ACTIF nommé (clef `active`)")
    profiles = cfg.get("profiles")
    if not isinstance(profiles, dict):
        raise ProfileUnresolved(f"{source} : aucune table `profiles`")
    if active not in profiles:
        raise ProfileUnresolved(
            f"{source} : le profil actif « {active} » n'existe pas "
            f"(profils connus : {', '.join(sorted(profiles)) or 'aucun'})")
    profile = dict(profiles[active])
    profile["_active_name"] = active
    check(profile, source=f"{source}, profil « {active} »")
    # LE BANNISSEMENT EST ICI, AU POINT UNIQUE (JAK-265, owner 23/09 : « Claude Opus 5 est a
    # bannir, Fable 5.1 aussi »). MARQUEUR: modele-banni-refuse-2026-09-23
    # Orchestrateur, Codex et supervisor.sh passent tous par `resolve` : un profil qui nomme
    # un modele banni n'est plus un profil, il ne part pas — pas de repli, pas de substitution.
    spec = banned_spec(cfg)
    hits = [f"{k}={profile[k]}" for k in MODEL_FIELDS
            if isinstance(profile.get(k), str) and is_banned(profile[k], spec)]
    if hits:
        raise ProfileUnresolved(
            f"{source}, profil « {active} » : modèle BANNI ({', '.join(hits)}) — "
            f"liste `banned_models` de {PROFILES_PATH.name}")
    return profile


# ------------------------------------------------------------------ modeles bannis
def banned_spec(cfg=None) -> dict:
    """{ids, aliases} des modeles bannis. `cfg` sans liste (profil Codex) -> la liste canonique.

    Une liste ABSENTE du fichier canonique LEVE : une porte sans liste serait aveugle et
    rendrait 0 sur tout, c'est exactement le faux vert qu'on refuse."""
    spec = cfg.get("banned_models") if isinstance(cfg, dict) else None
    if not isinstance(spec, dict):
        spec = json.loads(PROFILES_PATH.read_text()).get("banned_models")
    ids = [str(x).strip().lower() for x in (spec or {}).get("ids") or [] if str(x).strip()]
    if not ids:
        raise ProfileUnresolved(f"{PROFILES_PATH} : liste `banned_models.ids` absente ou vide")
    aliases = [str(x).strip().lower() for x in (spec or {}).get("aliases") or [] if str(x).strip()]
    return {"ids": ids, "aliases": aliases}


def canon(model: str) -> str:
    """claude-opus-5[1m] / claude-opus-5-20260101 -> claude-opus-5 (casse ignoree)."""
    m = str(model or "").strip().lower()
    m = re.sub(r"\[1m\]$", "", m)
    return re.sub(r"-\d{8}$", "", m)


def is_banned(model: str, spec: dict) -> bool:
    c = canon(model)
    return bool(c) and (c in spec["ids"] or c in spec["aliases"])


def literal_regex(spec: dict) -> "re.Pattern":
    """Un identifiant banni ECRIT dans du texte. `claude-opus-5-5` ne matche PAS `claude-opus-5` :
    la borne de fin refuse un tiret ou un chiffre qui suit."""
    ids = sorted(spec["ids"], key=len, reverse=True)
    alt = "|".join(re.escape(i) for i in ids)
    # Borne de DEBUT sans tiret : `${SUP_MODEL:-claude-opus-5}` (le repli du 23/09) doit matcher.
    return re.compile(r"(?<![A-Za-z0-9_])(" + alt + r")(?:-\d{8})?(?:\[1m\])?(?![A-Za-z0-9_-])",
                      re.I)


# ------------------------------------------------------------------ roles
def roles(profile: dict) -> dict:
    """role -> (modele, effort, champ qui le porte). Le superviseur a son propre couple ; absent,
    il prend celui du manager (c'etait le comportement de supervisor.sh avant le 23/09)."""
    efforts = profile.get("worker_efforts") or {}
    out = {
        "supervisor": (profile.get("supervisor_model") or profile.get("manager_model"),
                       profile.get("supervisor_effort") or profile.get("manager_effort"),
                       "supervisor_model" if profile.get("supervisor_model") else "manager_model"),
        "manager": (profile.get("manager_model"), profile.get("manager_effort"), "manager_model"),
    }
    for agent in sorted(efforts):
        out[agent.replace("autoport-", "")] = (profile.get("worker_model"), efforts[agent],
                                               "worker_model")
    return out


# ------------------------------------------------------------------ essais croises
def trial_arms(cfg: dict, item: dict) -> list[tuple[str, str, dict]]:
    """[(essai, bras, surcharges)] pour cet item. Bras STABLE par item : sha256(essai:id)."""
    out = []
    trials = (cfg or {}).get("trials") or {}
    for name in sorted(k for k in trials if not k.startswith("_")):
        t = trials[name]
        if not isinstance(t, dict) or not t.get("active"):
            continue
        cond = t.get("applies_to") or {}
        if any(str(item.get(k)) != str(v) for k, v in cond.items()):
            continue
        arms = [(k, v) for k, v in (t.get("arms") or {}).items() if not k.startswith("_")]
        if not arms:
            continue
        h = int(hashlib.sha256(f"{name}:{item.get('id', '')}".encode()).hexdigest(), 16)
        label, over = arms[h % len(arms)]
        out.append((name, label, dict(over)))
    return out


def load(path=None) -> dict:
    return json.loads(Path(path or PROFILES_PATH).read_text())


def _main(argv=None) -> int:
    """`model_profile.py supervisor-env [--file F]` : les variables du superviseur, en shell.

    supervisor.sh n'a PLUS de modele en dur : il evalue cette sortie, ou refuse de partir."""
    import argparse
    import shlex
    import sys
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=("supervisor-env",))
    ap.add_argument("--file", default=str(PROFILES_PATH))
    a = ap.parse_args(argv)
    try:
        prof = resolve(load(a.file), source=a.file)
    except (ProfileUnresolved, OSError, ValueError) as e:
        print(f"REFUS : {e}", file=sys.stderr)
        return 1
    model, effort, field = roles(prof)["supervisor"]
    for k, v in (("SUP_PROFILE", prof["_active_name"]), ("SUP_MODEL", model),
                 ("SUP_EFFORT", effort), ("SUP_MODEL_FIELD", field),
                 ("SUB_MODEL", prof["worker_model"])):
        print(f"{k}={shlex.quote(str(v))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
