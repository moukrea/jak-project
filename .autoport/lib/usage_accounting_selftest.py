#!/usr/bin/env python3
"""lib/usage_accounting_selftest.py — LE BANC DU COMPTEUR DE JETONS D'UN ESSAI.

MARQUEUR : USAGE-COMPTE-UNE-FOIS/banc

CE QU'IL MESURE, ET RIEN D'AUTRE. Il rejoue des evenements de flux `stream-json` a
travers `orchestrator.pretty_print_event` — le VRAI lecteur, jamais une copie — et publie
ce que l'orchestrateur en conclut. Il ne juge rien : `lib/census/harness-usage-double-
counted.sh` relit ces `cle=valeur` et decide.

TROIS PIEGES DU FLUX, MESURES SUR NOS PROPRES JOURNAUX LE 19/09 :

  1. UN MEME MESSAGE `assistant` REVIENT 3 A 5 FOIS, avec la MEME `usage`. Sur
     `logs/00-harness/attempt-02.jsonl` : 21 republications pour 28 messages distincts, et
     le cache lu passe de 1 455 508 (dedupliques) a 2 602 753 (bruts).
  2. UN ESSAI PORTE PLUSIEURS `result`, chacun republiant un `modelUsage` CUMULE depuis le
     debut : onze sur `ao-indirect-clean/attempt-001`, de 18,8 M a 21,5 M de cache lu. Les
     additionner gonfle le cout de 25 %.
  3. `usage.output_tokens` DES LIGNES `assistant` EST UN ACOMPTE : 7 541 contre 32 646
     reellement factures sur le temoin. La sortie ne se lit que sur `result`.

L'AUTORITE RETENUE EST `result.modelUsage` : les jetons que la CLI dit avoir FACTURES.
Controle de la clef de deduplication : le total deduplique des lignes `assistant` tombe
EXACTEMENT sur ce `modelUsage` pour le cache, sur les trois temoins (1 455 508 = 1 455 508 ;
21 565 137 = 21 565 137 ; 93 272 265 = 93 272 265).
"""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

AUTOPORT = Path(__file__).resolve().parents[1]
ROOT = AUTOPORT.parent
LOGS = AUTOPORT / "logs"

for _p in (str(AUTOPORT), str(AUTOPORT / "lib")):
    if _p not in sys.path:
        sys.path.insert(0, _p)

SEAUX = ("inp", "out", "cread", "cwrite")


# ============================================================ le journal fabrique

def _assistant(mid, inp, out, cread, cwrite, parent=None, sub=None, n=1):
    """Un message `assistant`, republie `n` fois a l'identique — comme le fait la CLI."""
    ev = {
        "type": "assistant",
        "message": {
            "id": mid,
            "model": "claude-opus-5",
            "content": [{"type": "text", "text": "…"}],
            "usage": {"input_tokens": inp, "output_tokens": out,
                      "cache_read_input_tokens": cread,
                      "cache_creation_input_tokens": cwrite},
        },
    }
    if parent:
        ev["parent_tool_use_id"] = parent
        ev["subagent_type"] = sub or "autoport-researcher"
    return [json.loads(json.dumps(ev)) for _ in range(n)]


def _result(cumul, delta_out, cost):
    """Un `result` : `modelUsage` CUMULE depuis le debut, `usage` en delta de ce tour."""
    return {
        "type": "result", "subtype": "success", "num_turns": 3, "duration_ms": 1000,
        "total_cost_usd": cost,
        "usage": {"input_tokens": 2, "output_tokens": delta_out,
                  "cache_read_input_tokens": 111, "cache_creation_input_tokens": 7},
        "modelUsage": {
            "claude-opus-5": {"canonicalModel": "claude-opus-5",
                              "inputTokens": cumul["inp"], "outputTokens": cumul["out"],
                              "cacheReadInputTokens": cumul["cread"],
                              "cacheCreationInputTokens": cumul["cwrite"],
                              "costUSD": cost},
        },
    }


def journal_fabrique():
    """Le flux a doublons, et le total qu'un compteur juste DOIT rendre.

    Le total attendu n'est pas une somme que ce fichier recalcule : c'est le DERNIER
    `modelUsage`, ecrit en clair ici. Un banc qui recalculerait l'attendu avec la meme
    regle que le code juge ne prouverait que sa propre coherence.
    """
    ev = []
    ev += _assistant("msg_a", 10, 40, 1000, 300, n=4)          # republie 4 fois
    ev += _assistant("msg_b", 12, 55, 2000, 100, n=3)
    ev += _assistant("msg_s1", 9, 30, 5000, 50,
                     parent="toolu_1", sub="autoport-researcher", n=5)
    ev.append(_result({"inp": 500, "out": 4000, "cread": 8000, "cwrite": 450}, 4000, 1.25))
    ev += _assistant("msg_c", 11, 60, 3000, 80, n=3)
    ev.append(_result({"inp": 700, "out": 6500, "cread": 11000, "cwrite": 530}, 2500, 1.90))
    ev.append(_result({"inp": 740, "out": 6800, "cread": 11400, "cwrite": 540}, 300, 2.05))
    attendu = {"inp": 740, "out": 6800, "cread": 11400, "cwrite": 540}
    return ev, attendu, 2.05


def journal_sans_result():
    """Un essai tue avant tout `result` : le total deduplique des lignes `assistant` est
    le seul chiffre qui existe. 18 essais d'avant mai 2026 sont dans ce cas."""
    ev = []
    ev += _assistant("msg_a", 10, 40, 1000, 300, n=4)
    ev += _assistant("msg_b", 12, 55, 2000, 100, n=3)
    ev += _assistant("msg_s1", 9, 30, 5000, 50, parent="toolu_1", n=5)
    attendu = {"inp": 31, "out": 125, "cread": 8000, "cwrite": 450}
    return ev, attendu


def journal_legacy():
    """Un `result` SANS `modelUsage` (vieille CLI) : sa `usage` est le DELTA du tour.
    L'entree et le cache restent au total deduplique ; seule la sortie vient des `result`."""
    ev = []
    ev += _assistant("msg_a", 10, 40, 1000, 300, n=3)
    ev.append({"type": "result", "subtype": "success", "num_turns": 1, "duration_ms": 10,
               "total_cost_usd": 0.5,
               "usage": {"input_tokens": 3, "output_tokens": 900,
                         "cache_read_input_tokens": 999, "cache_creation_input_tokens": 9}})
    ev += _assistant("msg_b", 12, 55, 2000, 100, n=2)
    ev.append({"type": "result", "subtype": "success", "num_turns": 1, "duration_ms": 10,
               "total_cost_usd": 0.8,
               "usage": {"input_tokens": 3, "output_tokens": 350,
                         "cache_read_input_tokens": 999, "cache_creation_input_tokens": 9}})
    attendu = {"inp": 22, "out": 1250, "cread": 3000, "cwrite": 400}
    return ev, attendu


# ============================================================ le rejeu

def rejouer(module, evenements):
    """Le flux passe par le VRAI lecteur du module donne. Rend ses quatre totaux."""
    quiet_avant, backend_avant = module.QUIET, module.BACKEND
    module.QUIET, module.BACKEND = True, "claude"
    try:
        st = module.PrettyState(t0=0.0)
        for ev in evenements:
            module.pretty_print_event(ev, st)
        return {"inp": st.tokens_in, "out": st.tokens_out,
                "cread": st.cache_read, "cwrite": st.cache_creation}, st
    finally:
        module.QUIET, module.BACKEND = quiet_avant, backend_avant


def evenements_du_journal(path: Path):
    """Les evenements d'un journal d'essai reel, dans l'ordre."""
    out = []
    with path.open(errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if isinstance(d, dict) and d.get("type") in ("assistant", "result", "user"):
                out.append(d)
    return out


def autorite_du_journal(path: Path):
    """LA GRANDEUR DE REFERENCE, relue independamment du code juge : le `modelUsage` du
    DERNIER `result`. None si l'essai n'en porte aucun."""
    snap = None
    with path.open(errors="replace") as fh:
        for line in fh:
            if '"result"' not in line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") != "result":
                continue
            mu = d.get("modelUsage")
            if not isinstance(mu, dict) or not mu:
                continue
            acc = dict.fromkeys(SEAUX, 0)
            for m in mu.values():
                if not isinstance(m, dict):
                    continue
                acc["inp"] += int(m.get("inputTokens") or 0)
                acc["out"] += int(m.get("outputTokens") or 0)
                acc["cread"] += int(m.get("cacheReadInputTokens") or 0)
                acc["cwrite"] += int(m.get("cacheCreationInputTokens") or 0)
            snap = acc
    return snap


def ecart_pour_mille(mesure, reference):
    """Le pire ecart relatif, en pour mille, sur les quatre seaux."""
    pire = 0
    for k in SEAUX:
        r = reference.get(k, 0)
        m = mesure.get(k, 0)
        if r == 0:
            pire = max(pire, 0 if m == 0 else 1000)
        else:
            pire = max(pire, abs(m - r) * 1000 // r)
    return int(pire)


# ============================================================ le bras d'AVANT

def module_avant():
    """L'orchestrateur du dernier commit SANS ce correctif, importe tel quel.

    Ancre par MARQUEUR (`lib/ablation_anchor.sh`), jamais par `HEAD:` ni par un nombre de
    commits : une fois ce chantier commite, `HEAD` porte le correctif et le bras d'avant
    s'accuserait lui-meme. Rend (module, commit, methode) ou (None, '', methode)."""
    try:
        sortie = subprocess.run(
            ["bash", str(AUTOPORT / "lib" / "ablation_anchor.sh"), str(ROOT),
             ".autoport/orchestrator.py", "_adopt_result_totals", "kv"],
            capture_output=True, text=True, timeout=180).stdout
    except Exception:  # noqa: BLE001
        return None, "", "erreur"
    champs = dict(l.split("=", 1) for l in sortie.splitlines() if "=" in l)
    commit = champs.get("anchor_commit", "") or ""
    methode = champs.get("anchor_method", "absent")
    if not commit or commit == "-":
        return None, "", methode
    try:
        blob = subprocess.run(["git", "-C", str(ROOT), "show",
                               f"{commit}:.autoport/orchestrator.py"],
                              capture_output=True, text=True, timeout=60).stdout
    except Exception:  # noqa: BLE001
        return None, commit, methode
    if not blob:
        return None, commit, methode
    import tempfile
    fd, chemin = tempfile.mkstemp(prefix="orchestrateur_avant_", suffix=".py")
    with os.fdopen(fd, "w") as fh:
        fh.write(blob)
    nom = "orchestrateur_avant"
    try:
        spec = importlib.util.spec_from_file_location(nom, chemin)
        mod = importlib.util.module_from_spec(spec)
        # INSCRIT AVANT L'EXECUTION : `@dataclass` relit `sys.modules[cls.__module__]` pour
        # reconnaitre `KW_ONLY`, et meurt en AttributeError si le module n'y est pas encore.
        # Sans cette ligne le bras d'avant etait MUET — un zero qui ressemble a un succes.
        sys.modules[nom] = mod
        spec.loader.exec_module(mod)
    except Exception:  # noqa: BLE001
        sys.modules.pop(nom, None)
        return None, commit, methode
    finally:
        try:
            os.unlink(chemin)
        except OSError:
            pass
    return mod, commit, methode


# ============================================================ la publication

def journaux_reels(exclure_item: str = ""):
    """Le temoin choisi, puis les trois essais les plus RECENTS qui portent une autorite.

    Le temoin (`00-harness/attempt-02`) est un essai SANS sous-agent : son total de session
    doit tomber au jeton pres. Les trois derniers sont la population qui bouge."""
    choisis = []
    # DEUX TEMOINS CHOISIS, parce que le defaut a deux moitiés et qu'un essai a `result`
    # UNIQUE n'en montre qu'une. `00-harness/attempt-02` : un seul `result`, aucun
    # sous-agent — le total de session doit tomber au jeton pres. `ao-indirect-clean/
    # attempt-001` : ONZE `result` republiant un `modelUsage` cumule (18,8 M -> 21,5 M),
    # le seul regime ou l'addition des `result` se voyait.
    for temoin in (LOGS / "00-harness" / "attempt-02.jsonl",
                   LOGS / "ao-indirect-clean" / "attempt-001.jsonl"):
        if temoin.exists():
            choisis.append(temoin)
    cands = []
    for p in LOGS.glob("*/attempt-*.jsonl"):
        if exclure_item and p.parent.name == exclure_item:
            continue
        if p in choisis:
            continue
        cands.append(p)
    cands.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    pris = 0
    for p in cands:
        if pris >= 3:
            break
        if autorite_du_journal(p) is None:
            continue          # essai tue avant tout `result` : aucune autorite a comparer
        choisis.append(p)
        pris += 1
    return choisis


def main() -> int:
    import orchestrator as neuf  # noqa: PLC0415

    pub = {}

    # ---- 1. LE JOURNAL FABRIQUE : le total attendu est ecrit, pas recalcule.
    ev, attendu, cost = journal_fabrique()
    got, st = rejouer(neuf, ev)
    pub["fixture_ok"] = int(got == attendu)
    pub["fixture_ecart_pm"] = ecart_pour_mille(got, attendu)
    for k in SEAUX:
        pub[f"fixture_{k}"] = got[k]
        pub[f"fixture_attendu_{k}"] = attendu[k]
    pub["fixture_dup_msgs"] = st.dup_msgs
    pub["fixture_msgs"] = len(st.seen_msg)
    pub["fixture_results"] = st.n_results
    pub["fixture_source"] = st.usage_source
    pub["fixture_cost_usd_x100"] = int(round(st.cost_usd * 100))
    pub["fixture_cost_attendu_x100"] = int(round(cost * 100))

    ev2, attendu2 = journal_sans_result()
    got2, st2 = rejouer(neuf, ev2)
    pub["sansresult_ok"] = int(got2 == attendu2)
    pub["sansresult_source"] = st2.usage_source
    pub["sansresult_cread"] = got2["cread"]

    ev3, attendu3 = journal_legacy()
    got3, st3 = rejouer(neuf, ev3)
    pub["legacy_ok"] = int(got3 == attendu3)
    pub["legacy_source"] = st3.usage_source
    pub["legacy_out"] = got3["out"]

    # ---- 2. LE BRAS D'AVANT : le meme journal fabrique, lu par le code SANS le correctif.
    # Sans lui, « le total est juste » ne dirait pas si le journal porte vraiment le defaut.
    avant, commit, methode = module_avant()
    pub["ablation_methode"] = methode
    pub["ablation_commit"] = (commit or "-")[:12]
    if avant is None:
        pub["ablation_ran"] = 0
        pub["ablation_ok"] = -1
        pub["ablation_gonflement_pm"] = -1
    else:
        vieux, _ = rejouer(avant, ev)
        pub["ablation_ran"] = 1
        pub["ablation_ok"] = int(vieux == attendu)   # 1 = le vieux code passe : fixture MUETTE
        pub["ablation_gonflement_pm"] = ecart_pour_mille(vieux, attendu)
        for k in SEAUX:
            pub[f"ablation_{k}"] = vieux[k]
        # ET SUR UN VRAI JOURNAL, pas seulement sur le fabrique : le temoin a ONZE `result`.
        # C'est ce qui dit que la population REELLE de la porte est discriminante — un zero
        # mesure sur un flux que le vieux code passait aussi ne prouverait rien.
        temoin = LOGS / "ao-indirect-clean" / "attempt-001.jsonl"
        ref = autorite_du_journal(temoin) if temoin.exists() else None
        if ref:
            vr, _ = rejouer(avant, evenements_du_journal(temoin))
            pub["ablation_reel_ecart_pm"] = ecart_pour_mille(vr, ref)
            pub["ablation_reel_cread"] = vr["cread"]
            pub["ablation_reel_ref_cread"] = ref["cread"]
        else:
            pub["ablation_reel_ecart_pm"] = -1

    # ---- 3. LES JOURNAUX REELS : ce que l'orchestrateur conclut contre l'autorite.
    exclure = os.environ.get("AUTOPORT_CENSUS_ID", "")
    fichiers = journaux_reels(exclure)
    pub["reels_n"] = len(fichiers)
    pire = 0
    hors = 0
    dup_total = 0
    noms = []
    for i, p in enumerate(fichiers):
        ref = autorite_du_journal(p)
        got, st = rejouer(neuf, evenements_du_journal(p))
        e = ecart_pour_mille(got, ref)
        pire = max(pire, e)
        dup_total += st.dup_msgs
        if e > 10:                       # 1 % : le seuil que la porte de l'item fixe
            hors += 1
        noms.append(f"{p.parent.name}/{p.name.split('.')[0]}:{e}")
        pub[f"reel{i}_ecart_pm"] = e
        pub[f"reel{i}_dup"] = st.dup_msgs
        pub[f"reel{i}_msgs"] = len(st.seen_msg)
        pub[f"reel{i}_results"] = st.n_results
        pub[f"reel{i}_cread"] = got["cread"]
        pub[f"reel{i}_ref_cread"] = ref["cread"]
        pub[f"reel{i}_out"] = got["out"]
        pub[f"reel{i}_ref_out"] = ref["out"]
        pub[f"reel{i}_nom"] = f"{p.parent.name}/{p.name.split('.')[0]}"
    # COMBIEN D'ESSAIS DE LA POPULATION PORTENT PLUSIEURS `result` : sans au moins un, la
    # moitie « cumul republie » de la porte n'est jamais executee et son zero ne vaut rien.
    pub["reels_multi_results"] = sum(
        1 for i in range(len(fichiers)) if pub.get(f"reel{i}_results", 0) > 1)
    pub["reels_pire_ecart_pm"] = pire
    pub["reels_hors_seuil"] = hors
    pub["reels_dup_ignores"] = dup_total
    pub["reels_liste"] = ",".join(noms) or "-"

    for k, v in pub.items():
        print(f"{k}={v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
