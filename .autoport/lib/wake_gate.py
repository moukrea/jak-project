#!/usr/bin/env python3
"""La veille SANS MODELE : elle decide si un reveil du superviseur a lieu d'etre.

LE DEFAUT QU'ELLE CORRIGE. Le superviseur est reveille par un cron interne a sa session,
toutes les 15 a 30 minutes, 44 fois par jour en moyenne. Chaque reveil coute 1,11 $ —
mesure sur 4 063 reveils, `lib/supervisor_cost.py` — parce que le modele doit relire 562 k
jetons de contexte AVANT de pouvoir constater que rien n'a bouge. 50 % de la facture du
superviseur (4 525 $ sur 9 031 $) part la, et un quart de ces reveils n'a RIEN rendu a
l'owner : le modele s'est reveille, a verifie, et s'est rendormi.

CE QU'ELLE FAIT. Branchee sur `UserPromptSubmit`, elle voit le prompt de reveil AVANT qu'il
ne parte au modele. Elle refait elle-meme, en Python, les verifications que le prompt
demandait au modele de faire : la signature du digest (`backlog.signature_digest()`), les
retours de l'owner arrives par Linear, et l'etat de sante (demons, verrou d'orchestrateur,
arbre moteur, APK en ligne). Si RIEN n'a bouge depuis le dernier reveil, elle refuse le
prompt : l'appel API n'a pas lieu du tout. Si quelque chose a bouge, elle laisse passer ET
joint ce qu'elle a mesure, pour que le modele n'ait pas a le relire.

CE QU'ELLE NE FAIT JAMAIS
  * Elle ne touche PAS au memo de `status --changed` : le premier qui lit consomme la
    notification pour tout le monde, et cette notification appartient au superviseur. Elle
    garde son propre memo.
  * Elle ne refuse RIEN qui ne soit pas un reveil automatique. Un message tape par l'owner,
    un prompt d'essai, une notification de fin de tache passent sans etre lus.
  * Elle ne refuse jamais plus de `PLANCHER` d'affilee : au-dela, le superviseur est reveille
    meme si rien n'a bouge. Sans ce plancher, une veille bloquee serait indistinguable d'une
    veille qui marche.
  * En cas de doute, d'erreur, de fichier illisible, elle LAISSE PASSER. Claude Code traite
    tout code de sortie autre que 2 comme un echec non bloquant : un crochet casse ne peut
    pas faire taire le superviseur. C'est aussi pour ca qu'elle tient un journal — une veille
    muette et une veille morte se ressemblent trop.

CONTRAT DE SORTIE (verifie sur le binaire Claude Code 2.1.275)
  code 2 + stderr          le reveil est REFUSE, le prompt est efface, aucun appel API
  code 0 + JSON stdout     le reveil passe, `additionalContext` est joint au prompt
  code 0 sans sortie       ce prompt ne nous regarde pas
"""
import hashlib
import json
from pathlib import Path
import os
import subprocess
import sys
import time

AP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(AP)
MEMO = os.path.join(AP, ".last_wake_gate.json")
JOURNAL = os.path.join(AP, "logs", "wake-gate.jsonl")

# Au-dela de cette duree sans reveil, on reveille meme si rien n'a bouge. L'owner garde un
# point periodique ; la veille garde une preuve de vie.
PLANCHER_S = int(os.environ.get("AUTOPORT_WAKE_FLOOR_S", "7200"))
# LA BORNE EST MESUREE, PAS CHOISIE. Sur la vraie population du superviseur — 2 093 messages
# tapes par l'owner et 4 197 prompts injectes — une borne a 120 caracteres refuse 3 messages
# de l'owner (ses `/loop 30m Monitor the autoport...`, c'est-a-dire les ordres qui CREENT le
# cron : les refuser serait le comble). A 400, l'owner n'est JAMAIS refuse (0 sur 2 093) et
# 4 086 des 4 197 prompts injectes restent reconnus — les 111 autres sont les familles qui ne
# sont pas des reveils (fin de tache, reprise apres compaction, quota). Un prompt de l'owner
# EFFACE est le seul defaut inacceptable de cette veille : la borne se regle sur lui.
LONGUEUR_MIN = 400
# Le temps que la veille s'accorde. Au-dela elle laisse passer : mieux vaut un reveil de trop
# qu'un superviseur qui attend un script.
BUDGET_S = 8.0

SUJET = ("autoport", "orchestrator", "orchestrateur")
ACTE = ("supervision", "progress check", "progress-check", "digest", "monitor the",
        "surveillance", "point periodique", "point périodique")
# Ce qui n'est JAMAIS un reveil, quoi que dise le reste du texte.
JAMAIS = ("directives v", "## cet essai", "<task-notification>",
          "this session is being continued", "usage limit has reset",
          "another claude session sent", "<command-name>", "<command-message>",
          "<local-command")


def est_un_reveil(prompt):
    t = " ".join((prompt or "").split()).lower()
    if len(t) < LONGUEUR_MIN:
        return False
    if any(x in t[:4000] for x in JAMAIS):
        return False
    return any(x in t for x in SUJET) and any(x in t for x in ACTE)


# ----------------------------------------------------------------- les grandeurs lues
def _vivant(pid):
    """Vivant veut dire vivant : `kill -0` REUSSIT sur un zombie. On lit l'etat dans /proc."""
    try:
        with open("/proc/%d/stat" % int(pid), encoding="utf-8") as fh:
            return fh.read().rsplit(")", 1)[1].split()[0] != "Z"
    except (OSError, ValueError, IndexError):
        return False


def _pid_du_fichier(nom):
    try:
        with open(os.path.join(AP, nom), encoding="utf-8") as fh:
            t = fh.read().split()
        for mot in t:
            if mot.startswith("pid="):
                mot = mot[4:]
            if mot.isdigit():
                return int(mot)
    except OSError:
        pass
    return 0


def etat_sante():
    """Ce que le prompt de reveil demandait au modele de verifier, fait ici sans modele."""
    out = {}
    for cle, fichier in (("apk", ".auto_build_apk.pid"), ("push", ".auto_push_builds.pid"),
                         ("linear", ".linear_watch.pid"), ("orch", ".orchestrator.lock")):
        pid = _pid_du_fichier(fichier)
        out[cle] = 1 if (pid and _vivant(pid)) else 0
    try:
        r = subprocess.run(["git", "status", "--porcelain", "--",
                            "game", "goal_src", "android", "common", "goalc"],
                           cwd=ROOT, capture_output=True, text=True, timeout=5)
        out["arbre_moteur_sale"] = 1 if r.stdout.strip() else 0
    except (OSError, subprocess.SubprocessError):
        out["arbre_moteur_sale"] = -1
    try:
        with open(os.path.join(AP, ".last_apk_build_commit"), encoding="utf-8") as fh:
            bati = fh.read().strip()
        r = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                           text=True, timeout=5)
        tete = r.stdout.strip()
        out["apk_a_jour"] = 1 if (bati and tete and tete.startswith(bati[:10])) else 0
    except (OSError, subprocess.SubprocessError):
        out["apk_a_jour"] = -1
    return out


def empreinte_owner(bk):
    """Ce que l'owner a dit depuis Linear. `linear_sync.py` recopie ses commentaires dans le
    backlog ; leur NOMBRE et leur DERNIERE date suffisent a dire qu'il a parle. Prendre le
    fichier entier reveillerait a chaque ecriture de l'orchestrateur."""
    n = 0
    dernier = ""
    for it in getattr(bk, "items", []) or []:
        fb = it.get("owner_feedback")
        if not fb:
            continue
        if isinstance(fb, str):
            fb = [fb]
        for x in fb:
            n += 1
            s = x if isinstance(x, str) else json.dumps(x, sort_keys=True)
            dernier = max(dernier, s[:32])
    return "%d|%s" % (n, dernier)


def signature(bk):
    sante = etat_sante()
    parts = [bk.signature_digest(), empreinte_owner(bk),
             "|".join("%s=%s" % (k, sante[k]) for k in sorted(sante))]
    brut = "\n".join(parts)
    return hashlib.sha256(brut.encode("utf-8")).hexdigest(), sante


def _memo():
    try:
        with open(MEMO, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:                                      # noqa: BLE001
        return {}


def _ecris_memo(d):
    tmp = MEMO + ".%d.tmp" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(d, fh)
    os.replace(tmp, MEMO)


def _journal(ligne):
    try:
        os.makedirs(os.path.dirname(JOURNAL), exist_ok=True)
        with open(JOURNAL, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(ligne, sort_keys=True) + "\n")
    except OSError:
        pass


_SESSION_ID = "-"


def decide(prompt, maintenant=None, ecrire=True):
    """Rend (decision, raison, texte). `decision` vaut 'ignore', 'passe' ou 'refuse'."""
    t0 = time.time()
    maintenant = maintenant if maintenant is not None else t0
    # LE SUPERVISEUR TRAITE UN PROMPT, MAINTENANT — et c'est le seul endroit du depot qui le
    # sait. Le 22/09, le reveil de 10:20:48 est reste EN FILE : ce crochet n'a jamais tourne,
    # la derniere reponse est restee datee de 09:50:56, et le processus a survecu 77 minutes
    # de plus. Un controle qui ne lit que le pid serait reste muet tout ce temps ; celui-ci
    # ancre sur l'horodatage que l'oracle pose QUAND IL TOURNE.
    # AVANT le tri des reveils, et gate sur l'ASCENDANCE : ce crochet voit les prompts de
    # TOUTES les sessions du depot. Dater sur la forme du prompt laisserait un worker dater
    # le superviseur, et un superviseur pilote a la main par l'owner ne se daterait jamais.
    if ecrire:
        try:
            sys.path.insert(0, AP)
            from lib import supervisor_alive as _sa     # noqa: PLC0415
            if _sa.in_supervisor_tree():
                _sa.stamp_seen()
            else:
                # HORS REGISTRE (22/09) : une session superviseur ouverte sans
                # `run-supervisor.sh` lisait les retours et passait pour MORTE. Elle se declare
                # ici, par son propre pid de session ; un worker ne se declare jamais.
                _sa.self_declare(session_id=_SESSION_ID)
        except Exception:                               # noqa: BLE001 — jamais bloquant
            pass
    if not est_un_reveil(prompt):
        return "ignore", "pas-une-veille", ""
    memo = _memo()
    try:
        sys.path.insert(0, AP)
        from lib import backlog                            # noqa: PLC0415
        bk = backlog.load()
        sig, sante = signature(bk)
    except Exception as exc:                               # noqa: BLE001 — on laisse passer
        d = ("passe", "veille-en-erreur:%s" % type(exc).__name__, "")
        if ecrire:
            _journal({"ts": int(maintenant), "decision": d[0], "raison": d[1],
                      "ms": int((time.time() - t0) * 1000)})
        return d
    if time.time() - t0 > BUDGET_S:
        d = ("passe", "veille-trop-lente", "")
        if ecrire:
            _journal({"ts": int(maintenant), "decision": d[0], "raison": d[1],
                      "ms": int((time.time() - t0) * 1000)})
        return d
    precedent = memo.get("signature")
    depuis = maintenant - float(memo.get("dernier_reveil") or maintenant)
    if precedent is None:
        raison = "premier-passage"
    elif sig != precedent:
        raison = "etat-change"
    elif depuis >= PLANCHER_S:
        raison = "echeance-%dh" % int(PLANCHER_S / 3600)
    else:
        raison = "rien-n-a-bouge"
    refuse = raison == "rien-n-a-bouge"
    neuf = dict(memo)
    neuf["signature"] = sig
    neuf["derniere_decision"] = "refuse" if refuse else "passe"
    neuf["refus_consecutifs"] = (int(memo.get("refus_consecutifs") or 0) + 1) if refuse else 0
    if not refuse:
        neuf["dernier_reveil"] = maintenant
    if ecrire:
        _ecris_memo(neuf)
        _journal({"ts": int(maintenant), "decision": "refuse" if refuse else "passe",
                  "raison": raison, "ms": int((time.time() - t0) * 1000),
                  "refus_consecutifs": neuf["refus_consecutifs"],
                  "depuis_s": int(depuis)})
    if refuse:
        return ("refuse", raison,
                "Veille autoport (script, sans modele) : rien n'a bouge depuis %d min — "
                "ni le backlog, ni Linear, ni la sante du harnais. Reveil refuse ; "
                "prochain reveil garanti dans %d min. Journal : .autoport/logs/wake-gate.jsonl"
                % (depuis / 60, max(0, (PLANCHER_S - depuis) / 60)))
    lignes = ["La veille sans modele a deja fait les verifications de sante que ce reveil "
              "demande — inutile de les refaire :",
              "  raison du reveil : %s" % raison,
              "  demons (1 = vivant, lu dans /proc, pas `kill -0`) : "
              + " ".join("%s=%s" % (k, v) for k, v in sorted(sante.items())),
              "  refus consecutifs avant ce reveil : %d" % int(memo.get("refus_consecutifs") or 0)]
    try:
        lignes.append("")
        lignes.append(bk.status_report())
    except Exception:                                      # noqa: BLE001
        pass
    # 19/09, owner : « Tu surveilles plus les tickets c'est pas possible ! Je commente je commente et j'ai
    # aucun retour ». Le digest ne regardait que « A tester » ; les retours en attente vivaient dans le
    # journal de la synchro, que personne ne relisait. Ils sont desormais EN TETE de chaque reveil, avec
    # la consigne : y repondre d'abord. Lecture du dernier tour de linear_watch, aucune requete reseau.
    try:
        import re as _re
        log = Path(__file__).resolve().parent.parent / "logs" / "linear_sync.txt"
        txt = log.read_text(encoding="utf-8", errors="replace")[-40000:]
        tours = txt.split("Linear : ")
        dernier = tours[-2] if len(tours) >= 2 else txt
        attente = sorted(set(_re.findall(r"À TRAITER : (JAK-\d+ \S+)", dernier)))
        if attente:
            lignes.insert(0, "## RETOURS DE L'OWNER SANS REPONSE — REPONDRE A CHACUN AVANT TOUT DIGEST\n"
                          + "\n".join("- " + a for a in attente)
                          + "\n(le texte de chaque retour est dans `owner_feedback` de l'item ; poster par "
                            "`python3 .autoport/linear_sync.py --comment <id> --body \"…\"`)\n")
    except Exception:                                      # noqa: BLE001
        pass
    return "passe", raison, "\n".join(lignes)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--prompt" in argv:
        prompt = argv[argv.index("--prompt") + 1]
    else:
        try:
            charge = json.load(sys.stdin)
            prompt = charge.get("prompt") or ""
            global _SESSION_ID
            _SESSION_ID = str(charge.get("session_id") or "-")
        except Exception:                                  # noqa: BLE001 — jamais bloquant
            return 0
    try:
        decision, raison, texte = decide(prompt)
    except Exception:                                      # noqa: BLE001 — jamais bloquant
        return 0
    if decision == "ignore":
        return 0
    if decision == "refuse":
        sys.stderr.write(texte + "\n")
        return 2
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                             "additionalContext": texte}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
