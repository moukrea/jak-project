#!/usr/bin/env python3
"""
REPRISE DU 19/09 — comparer Fable a Opus 5 A EGALITE DE CHANCES.

Owner, 19/09 : « comment ca se fait que fable ne soit pas reellement envisage ?
T'as fais une evaluation de merde sur notre historique, c'est eclate ». Il a raison, et
ce fichier est la reponse mesuree, pas l'excuse.

CE QUI ETAIT FAUX. La premiere etude a mis dans un meme tableau « Fable 5.1 : 46 essais,
46,1 % de verts » et « Opus 5 : 278 essais, 55,8 % ». Deux populations qui n'ont
NI LES MEMES TACHES NI LES MEMES CONDITIONS :

  * les items ne sont pas les memes (chaque profil a tourne sur le backlog du moment) ;
  * une partie des essais Fable n'a jamais TOURNE — l'API les a refuses (plus de credits,
    429) ou l'orchestrateur les a tues. Ils comptaient pourtant comme des ECHECS DU MODELE.
    Trois essais de `Gcine-cut` sont morts a 7 appels d'outil, sans un seul jeton facture,
    et pesaient « rouge » contre Fable.

CE QUE FAIT CE FICHIER. Deux corrections, toutes deux SYMETRIQUES (appliquees aux deux
bras, jamais au seul bras qu'on veut faire gagner) :

  1. APPARIEMENT PAR ITEM — on ne garde que les items sur lesquels LES DEUX bras ont
     au moins un essai exploitable. La difficulte de la tache cesse d'etre confondue
     avec le modele.
  2. EXCLUSION DES ESSAIS QUI N'ONT PAS EU LIEU — et le motif est lu sur un champ que
     L'OUTIL ou LE SERVEUR ecrit, jamais devine :
       `refus-api`   : `result.terminal_reason == "api_error"` (le CLI nomme son erreur,
                       ex. `api_error_status=429`, « You're out of usage credits »), ou un
                       `rate_limit_event` dont le SERVEUR dit `status=="rejected"`, sans
                       qu'un essai productif suive.
       `interrompu`  : aucun evenement `result` dans tout le journal — la session a ete
                       tuee (SIGTERM/SIGKILL) avant de rendre quoi que ce soit.

CE QUI EMPECHE CE FICHIER DE MENTIR A SON TOUR :

  * L'exclusion est publiee des DEUX cotes, et on publie AUSSI le resultat SANS exclusion
    (`sensibilite`). Si le verdict ne tient que grace a l'exclusion, ca se voit sur la
    meme ligne. Une porte qui mesure son propre seuil ne prouve rien (defaut connu).
  * Le verdict n'est pas un point, c'est un INTERVALLE (Wilson 95 %). Avec 30 essais, un
    ecart de 10 points ne veut rien dire, et le mot publie est alors `indiscernable` —
    pas un gagnant. C'est la demande explicite de l'item : « dire honnetement quand la
    population est trop petite pour trancher (intervalle, pas un verdict) ».
  * Les « boucles » sont comptees deux fois : celle du harnais (suite de >= 3 memes
    empreintes d'echec, tous modeles confondus) et une variante PROPRE ou toute la suite
    appartient au meme bras. La premiere peut attribuer a Fable une boucle commencee par
    Opus ; la seconde ne le peut pas. On publie les deux.
"""

import math
from collections import defaultdict

STUCK = 3  # aligne sur STUCK_REPEAT_THRESHOLD du harnais


def family(model: str) -> str:
    """Le modele, sans la marque de contexte long. `[1m]` est un REGLAGE de la meme
    famille, pas un autre modele : Fable 5.1 et Fable 5.1[1m] sont le meme poids."""
    m = model or ""
    if m.startswith("claude-fable-5-1"):
        return "fable-5-1"
    if m.startswith("claude-fable-5"):
        return "fable-5"
    if m.startswith("claude-opus-5"):
        return "opus-5"
    if m.startswith("claude-opus-4-8"):
        return "opus-4-8"
    if m.startswith("claude-opus-4-7"):
        return "opus-4-7"
    if m.startswith("gpt-"):
        return "codex"
    return "(non-declare)"


def exclusion(rec):
    """Motif d'exclusion, NOMME, ou None si l'essai a reellement eu lieu.

    PIEGE MESURE PENDANT L'ECRITURE DE CE FICHIER : `api_error_status` seul EXCLUT TROP.
    22 essais portent un 429/529 transitoire et se terminent quand meme (`terminal_reason
    == "completed"`) — l'un d'eux apres 227 appels d'outil et 40 $. Ceux-la ONT eu lieu :
    les exclure aurait jete de vraies donnees, dont 8 essais d'Opus. Seul compte l'etat
    TERMINAL : le CLI s'est-il ARRETE sur l'erreur, ou l'a-t-il traversee ?"""
    if rec.get("terminal_reason") == "api_error":
        return "refus-api"                      # le CLI s'est arrete la-dessus
    rejected = (rec.get("rate_limit_rejected") or 0) > 0
    if not rec.get("result_seen"):
        # La session n'a jamais rendu de `result` : elle a ete tuee. Si le serveur avait
        # deja prononce un refus, c'est LUI qu'on nomme ; sinon c'est une interruption.
        return "refus-api" if rejected else "interrompu"
    productive = bool(rec.get("model_usage")) and (rec.get("tool_calls") or 0) > 0
    if rejected and not productive:
        return "refus-api"
    return None


def cost_of(rec):
    """Le cout que L'OUTIL a calcule (base tarif public), jamais le notre."""
    return sum(mu.get("cost_usd") or 0.0 for mu in (rec.get("model_usage") or {}).values())


def wilson(succ, n, z=1.96):
    """Intervalle de Wilson : le bon intervalle pour une proportion sur petit effectif.
    A 3 verts sur 5, l'intervalle normal deborde de [0,1] ; celui-ci non."""
    if n <= 0:
        return (0.0, 1.0)
    p = succ / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def clean_loops(recs_of_item, arm_fam):
    """Essais du bras pris dans une suite de >= 3 memes empreintes d'echec DONT TOUS LES
    MEMBRES sont du bras. Une boucle commencee par un autre modele ne compte pas ici."""
    # Un essai que l'API a refuse en 864 ms porte quand meme un verdict « rouge » et donc
    # une empreinte : trois refus d'affilee fabriquaient une « boucle » qui n'a jamais eu
    # lieu. On ne compte donc que les essais qui ONT tourne.
    rs = sorted((r for r in recs_of_item if not exclusion(r)),
                key=lambda r: r["attempt"])
    n_loop = 0
    i = 0
    while i < len(rs):
        fp = rs[i].get("fingerprint")
        if not fp:
            i += 1
            continue
        j = i
        while j + 1 < len(rs) and rs[j + 1].get("fingerprint") == fp:
            j += 1
        streak = rs[i:j + 1]
        if len(streak) >= STUCK and all(family(r["model"]) == arm_fam for r in streak):
            n_loop += len(streak)
        i = j + 1
    return n_loop


def _arm_stats(recs, arm_fam, all_by_item):
    g = sum(1 for r in recs if r["verdict"] == "vert")
    rd = sum(1 for r in recs if r["verdict"] == "rouge")
    nv = sum(1 for r in recs if r["verdict"] == "sans-verdict")
    cost = sum(cost_of(r) for r in recs)
    loops_h = sum(1 for r in recs if r.get("in_loop"))
    loops_c = 0
    for item, rs in all_by_item.items():
        if any(r["item"] == item for r in recs):
            loops_c += clean_loops(rs, arm_fam)
    lo, hi = wilson(g, g + rd)
    return {
        "n": len(recs), "vert": g, "rouge": rd, "sans_verdict": nv,
        "decided": g + rd,
        "green_pct": round(100 * g / (g + rd), 1) if (g + rd) else None,
        "green_lo_pct": round(100 * lo, 1), "green_hi_pct": round(100 * hi, 1),
        "loop_harness": loops_h, "loop_clean": loops_c,
        "loop_clean_pct": round(100 * loops_c / len(recs), 1) if recs else 0.0,
        "usd_total": round(cost, 2),
        "usd_per_attempt": round(cost / len(recs), 2) if recs else None,
        "usd_per_green": round(cost / g, 2) if g else None,
    }


def compare(attempts, fable_fam, ref_fam="opus-5"):
    """Le bras `fable_fam` contre `ref_fam`, sur les SEULS items que les deux ont touches."""
    for r in attempts:
        r["_excl"] = exclusion(r)
        r["_fam"] = family(r["model"])

    all_by_item = defaultdict(list)
    for r in attempts:
        all_by_item[r["item"]].append(r)

    usable = defaultdict(lambda: defaultdict(list))   # item -> fam -> [rec]
    raw = defaultdict(lambda: defaultdict(list))
    for r in attempts:
        if r["_fam"] in (fable_fam, ref_fam):
            raw[r["item"]][r["_fam"]].append(r)
            if not r["_excl"]:
                usable[r["item"]][r["_fam"]].append(r)

    shared = sorted(i for i, d in usable.items()
                    if d.get(fable_fam) and d.get(ref_fam))

    per_item = []
    fa, re_ = [], []
    for item in shared:
        f = usable[item][fable_fam]
        o = usable[item][ref_fam]
        fa += f
        re_ += o
        per_item.append({
            "item": item,
            "fable": _arm_stats(f, fable_fam, {item: all_by_item[item]}),
            "ref": _arm_stats(o, ref_fam, {item: all_by_item[item]}),
        })

    A = _arm_stats(fa, fable_fam, all_by_item)
    B = _arm_stats(re_, ref_fam, all_by_item)

    # Le mot publie vient de l'INTERVALLE, pas de l'ecart des points.
    if A["decided"] and B["decided"]:
        if A["green_lo_pct"] > B["green_hi_pct"]:
            verdict = "meilleur"
        elif A["green_hi_pct"] < B["green_lo_pct"]:
            verdict = "pire"
        else:
            verdict = "indiscernable"
    else:
        verdict = "non-mesurable"

    # SENSIBILITE : le meme calcul SANS exclure quoi que ce soit. Si le verdict change
    # ici, c'est l'exclusion qui parle, et le rapport doit le dire.
    shared_raw = sorted(i for i, d in raw.items() if d.get(fable_fam) and d.get(ref_fam))
    fa_r = [r for i in shared_raw for r in raw[i][fable_fam]]
    re_r = [r for i in shared_raw for r in raw[i][ref_fam]]
    Ar = _arm_stats(fa_r, fable_fam, all_by_item)
    Br = _arm_stats(re_r, ref_fam, all_by_item)
    if Ar["decided"] and Br["decided"]:
        if Ar["green_lo_pct"] > Br["green_hi_pct"]:
            v_raw = "meilleur"
        elif Ar["green_hi_pct"] < Br["green_lo_pct"]:
            v_raw = "pire"
        else:
            v_raw = "indiscernable"
    else:
        v_raw = "non-mesurable"

    excl = defaultdict(lambda: defaultdict(int))
    for r in attempts:
        if r["_fam"] in (fable_fam, ref_fam) and r["_excl"]:
            excl[r["_fam"]][r["_excl"]] += 1

    return {
        "arm": fable_fam, "ref": ref_fam,
        "shared_items": shared,
        "n_shared_items": len(shared),
        "per_item": per_item,
        "fable": A, "ref_stats": B,
        "verdict": verdict,
        "sensibilite": {"fable": Ar, "ref": Br, "verdict": v_raw,
                        "n_shared_items": len(shared_raw)},
        "exclusions": {k: dict(v) for k, v in excl.items()},
    }


def exclusion_census(attempts):
    """Combien d'essais n'ont pas eu lieu, par famille et par motif — TOUTES familles,
    pour qu'on voie que la regle ne vise pas Fable."""
    out = defaultdict(lambda: defaultdict(int))
    for r in attempts:
        fam = family(r["model"])
        out[fam]["total"] += 1
        e = exclusion(r)
        out[fam][e or "abouti"] += 1
    return {k: dict(v) for k, v in out.items()}
