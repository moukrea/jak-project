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
    return check(profile, source=f"{source}, profil « {active} »")
