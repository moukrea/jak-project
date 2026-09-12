#!/usr/bin/env python3
"""lib/safe_reload.py — LE FILET AUTOUR DES RECHARGEMENTS A CHAUD.

MARQUEUR : RECHARGEMENT/filet

POURQUOI CE FICHIER EXISTE. Le 2026-09-12 a 15:33:16 l'orchestrateur est MORT et le harnais
est reste a l'arret dix minutes. La trace : `orchestrator.load_backlog()` fait
`importlib.reload(backlog)` a CHAQUE tour ; `lib/backlog.py` fait a son tour
`importlib.reload(gate_verdict)` ; `gate_verdict.py:345` appelait `_noms.arm_name(...)`. Un
worker etait EN TRAIN de renommer les deux fichiers : l'autorite appelait deja le nom neuf que
`impossible` ne portait pas ENCORE. `AttributeError` a l'import, remontee jusqu'a `main`,
processus mort. Le rechargement qui rend les correctifs vivants rendait donc la boucle tuable
par n'importe quelle edition a moitie ecrite, et il n'y a personne la nuit pour relancer.

CE QU'ON NE FAIT PAS. On ne RETIRE aucun rechargement : sans eux un correctif de harnais ne
prend effet qu'au prochain redemarrage, et c'est exactement la promotion gelee en silence que
ces rechargements corrigeaient. On les PROTEGE.

CE QUE `reload()` GARANTIT, dans l'ordre :

  1. LE MODULE DEJA CHARGE EST CONSERVE — PAR SON CONTENU, pas par son nom.
     `importlib.reload` execute le nouveau code DANS LE `__dict__` DU MODULE EXISTANT. Un
     echec a mi-corps (l'`AttributeError` du 12/09 arrive ligne 345 sur 430) laisse donc un
     module MUTILE : moitie neuf, moitie vieux, et personne ne le voit. Garder
     `sys.modules[nom]` ne suffit pas. On photographie `__dict__` AVANT, on le restitue APRES
     l'echec : l'appelant retrouve EXACTEMENT le module d'avant.

  2. L'ECHEC EST JOURNALISE avec le FICHIER, la LIGNE et l'EXCEPTION. La ligne vient de la
     trace (le cadre le plus profond) ou, pour une `SyntaxError`, de l'exception elle-meme —
     qui ne porte pas de cadre dans le fichier fautif.

  3. LE TOUR CONTINUE. `reload()` rend False ; il ne releve jamais. Seuls `KeyboardInterrupt`
     et `SystemExit` traversent : ce sont les arrets VOULUS, et les avaler rendrait le harnais
     inarretable.

  4. L'ETAT DEGRADE EST DIT, PAS SUBI. Tant qu'un site echoue, `turn_report()` le REPETE a
     chaque tour dans le journal, et `owner_block()` le fait porter au texte rendu a l'owner.
     Un harnais qui tourne sur une autorite VIEILLE doit le DIRE : sinon on retombe sur le gel
     silencieux, cette fois deguise en boucle qui tourne.

L'ETAT VIT DANS UN FICHIER, et pas seulement en memoire, pour deux raisons : recharger un
module EFFACE ses globales (c'est precisement ce qu'on encadre), et `status_report()` est
souvent rendu par un AUTRE processus (`./autoport status`) que la boucle. Le fichier est sous
`.autoport/.last_reload_degraded.json`, deja couvert par `.gitignore` (`.autoport/.last_*`).
UN SEUL ECRIVAIN : ce module, depuis le processus qui recharge. Tout le reste le LIT.
"""
from __future__ import annotations

import importlib
import json
import os
import sys
import tempfile
import time
import traceback

AP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE_PATH = os.path.join(AP, ".last_reload_degraded.json")

# LES SITES COUVERTS, NOMMES. Cette liste est le CONTRAT : un site de rechargement qui n'y
# figure pas n'est pas protege, et le recensement compare cette liste aux appels reellement
# presents dans `orchestrator.py` et `lib/backlog.py`.
SITES = (
    "orchestrator:backlog",       # orchestrator.load_backlog      -> lib/backlog.py
    "orchestrator:directives",    # orchestrator.build_instructions -> lib/directives.py
    "orchestrator:preflight",     # orchestrator.build_instructions -> lib/preflight.py
    "backlog:gate_verdict",       # lib/backlog.py (corps du module) -> lib/gate_verdict.py
)

_refused = 0        # rechargements REFUSES depuis le demarrage de ce processus
_turns = 0          # tours poursuivis MALGRE un etat degrade
_degraded: dict = {}  # site -> ce qu'on sait de son echec


def _atomic_write(path: str, text: str) -> None:
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".reload-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except Exception:                       # noqa: BLE001 — un etat non ecrit ne tue personne
        try:
            os.unlink(tmp)
        except OSError:
            pass


def _persist() -> None:
    _atomic_write(STATE_PATH, json.dumps(
        {"pid": os.getpid(), "refused": _refused, "turns": _turns,
         "sites": _degraded, "at": time.time()}, ensure_ascii=False, indent=0, sort_keys=True))


def _where(exc: BaseException) -> tuple[str, int]:
    """Le FICHIER et la LIGNE du defaut, jamais ceux de l'appelant.

    Une `SyntaxError` ne pose aucun cadre dans le fichier fautif : elle porte ses coordonnees
    elle-meme. Pour tout le reste on prend le cadre le PLUS PROFOND — c'est celui qui a leve."""
    if isinstance(exc, SyntaxError) and exc.filename:
        return exc.filename, int(exc.lineno or 0)
    frames = traceback.extract_tb(exc.__traceback__)
    if frames:
        return frames[-1].filename, int(frames[-1].lineno or 0)
    return "?", 0


def _stderr(message: str, style: str = "") -> None:
    """LE JOURNAL PAR DEFAUT. `lib/backlog.py` recharge l'autorite depuis le CORPS de son
    module : il n'a aucun logger sous la main. Sans ce repli son refus serait muet, et un
    harnais degrade qui se tait est exactement ce que ce chantier interdit."""
    try:
        sys.stderr.write(message + "\n")
        sys.stderr.flush()
    except Exception:                       # noqa: BLE001
        pass


def reload(module, site: str, log=None) -> bool:
    """Recharge `module`. Rend True si le code NEUF est en place, False si l'ANCIEN a ete garde.

    Ne releve JAMAIS pour une edition a moitie ecrite : c'est tout l'objet de ce fichier."""
    global _refused
    name = getattr(module, "__name__", str(module))
    path = getattr(module, "__file__", "?")
    # LA PHOTO. `importlib.reload` ecrit dans CE dictionnaire-ci : sans copie, un echec a
    # mi-corps laisse un module mi-neuf mi-vieux que plus personne ne peut restituer.
    photo = dict(vars(module))
    try:
        importlib.reload(module)
    except (KeyboardInterrupt, SystemExit):
        raise                                   # les arrets VOULUS traversent
    except BaseException as exc:                # noqa: BLE001 — c'est le filet, il prend tout
        fichier, ligne = _where(exc)
        vars(module).clear()
        vars(module).update(photo)
        sys.modules[name] = module              # un echec ne doit pas le desinscrire
        _refused += 1
        rec = _degraded.get(site) or {}
        _degraded[site] = {
            "module": name,
            "path": path,
            "file": fichier,
            "line": ligne,
            "exc": "%s: %s" % (type(exc).__name__, exc),
            "since": rec.get("since") or time.strftime("%Y-%m-%dT%H:%M:%S"),
            "count": int(rec.get("count") or 0) + 1,
        }
        _persist()
        (log or _stderr)(
            "⚠ rechargement REFUSE [%s] : %s ligne %d — %s: %s. Le module DEJA CHARGE est "
            "garde (%s), le tour continue."
            % (site, fichier, ligne, type(exc).__name__, exc, path), "bold yellow")
        return False
    if site in _degraded:
        avant = _degraded.pop(site)
        _persist()
        (log or _stderr)(
            "✓ rechargement [%s] repasse apres %d refus : le code du disque est de nouveau en "
            "vigueur." % (site, int(avant.get("count") or 0)), "bold green")
    return True


def degraded() -> dict:
    """Les sites qui echouent EN CE MOMENT, tels que ce processus les connait."""
    return dict(_degraded)


def counters() -> dict:
    return {"refused": _refused, "turns_continued": _turns, "degraded_sites": len(_degraded)}


def turn_report(log=None) -> int:
    """A APPELER UNE FOIS PAR TOUR. Repete l'etat degrade et compte le tour poursuivi.

    Le compte n'avance que si un site echoue VRAIMENT : « tours poursuivis malgre eux » n'a
    de sens que sous un « eux »."""
    global _turns
    if not _degraded:
        return 0
    _turns += 1
    _persist()
    if log:
        log("⚠ HARNAIS DEGRADE — %d rechargement(s) refuse(s), le harnais tourne sur du code "
            "VIEUX. Tour poursuivi quand meme (%d depuis le premier refus)."
            % (len(_degraded), _turns), "bold yellow")
        for site, rec in sorted(_degraded.items()):
            log("    [%s] %s : %s ligne %s — %s (depuis %s, %d refus)"
                % (site, rec.get("module"), rec.get("file"), rec.get("line"),
                   rec.get("exc"), rec.get("since"), int(rec.get("count") or 0)), "yellow")
    return _turns


def read_state(path: str = STATE_PATH) -> dict:
    """L'etat degrade tel qu'il est SUR LE DISQUE. Lu par qui rend le texte de l'owner."""
    try:
        with open(path, encoding="utf-8") as fh:
            etat = json.load(fh)
    except (OSError, ValueError):
        return {}
    return etat if isinstance(etat, dict) else {}


def owner_block(path: str = STATE_PATH) -> tuple[str, str]:
    """Le bloc rendu a l'owner, et sa version pour le DIGEST.

    Le bloc porte le compte de tours ; le digest, NON. Un texte polle qui embarque une grandeur
    qui bouge a chaque tour reveillerait le digest a chaque tour, et il n'y aurait plus de
    digest du tout : le digest ne porte que l'IDENTITE du defaut (site, fichier, ligne,
    exception), qui ne bouge pas tant qu'il dure."""
    etat = read_state(path)
    sites = etat.get("sites") or {}
    if not sites:
        return "", ""
    lignes = ["## Harnais degrade",
              "Le harnais tourne sur du CODE VIEUX : %d rechargement(s) refuse(s), %d tour(s) "
              "poursuivi(s) quand meme. Un fichier du harnais est reste a moitie ecrit ; la "
              "boucle a survecu, mais elle n'applique pas ce qui est sur le disque."
              % (int(etat.get("refused") or 0), int(etat.get("turns") or 0))]
    digest = []
    for site, rec in sorted(sites.items()):
        rec = rec or {}
        lignes.append("- %s (%s) : %s ligne %s"
                      % (site, rec.get("module", "?"), rec.get("file", "?"), rec.get("line", 0)))
        lignes.append("  %s — depuis %s" % (rec.get("exc", "?"), rec.get("since", "?")))
        digest.append("%s|%s|%s|%s" % (site, rec.get("file"), rec.get("line"), rec.get("exc")))
    return "\n".join(lignes), "\n".join(digest)
