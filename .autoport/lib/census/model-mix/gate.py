#!/usr/bin/env python3
"""
Juge l'etude « dosage de modeles » et publie ses grandeurs.

`model_mix_defects` = NOMBRE DE TERMES DE LA PORTE QUI NE SONT PAS MESURES, sur les DIX
que l'item enonce : les six du cadrage du 19/09 03:10, plus les quatre de la REPRISE du
19/09 (termes 7 a 10) apres le retour de l'owner « comment ca se fait que fable ne soit
pas reellement envisage ? T'as fais une evaluation de merde sur notre historique ».
UN TERME NON MESURE COMPTE 1 : c'est la regle de l'item, et c'est ce
qui empeche une somme verte obtenue en ne regardant rien (cf. le defaut « porte AGREGEE
qui compte 1 par terme NON MESURE »). Chaque terme publie AUSSI son propre etat, pour
qu'on puisse lire QUEL terme manque sans relire ce fichier.

Ce script ne mesure rien lui-meme : il relit le digest produit par `collect.py` (nos
journaux) et `sources.json` (la recherche externe), et il compare.
"""

import bisect
import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

AUTOPORT = Path(__file__).resolve().parents[3]
ITEM = "owner-se-renseigner-sur-le-combo-le-plus-efficient-tou"
REPORT_DIR = AUTOPORT / "reports" / ITEM
MEAS = REPORT_DIR / "measures"
# `.autoport/reports/` EST GITIGNORE. Une porte qui lit sa preuve la-dedans est verte ici
# et rouge dans tout arbre neuf — elle accuse alors un innocent (defaut connu : « test qui
# lit un fichier GITIGNORE »). Les deux ENTREES du jugement — la recherche externe et le
# rapport — vivent donc a cote de ce script, versionnees ; `reports/` n'en recoit qu'une
# copie de confort pour l'owner, et sert de repli si la versionnee manque.
HERE = Path(__file__).resolve().parent

sys.path.insert(0, str(Path(__file__).resolve().parent))
import paired  # noqa: E402  — l'appariement par item de la reprise du 19/09

MIN_ATTEMPTS = 10          # seuil de l'item : « chaque profil ayant >= 10 essais »
MIN_DECIDED = 5            # sous ce nombre de verdicts, une part de verts ne veut rien dire
MIN_VERDICT_COVERAGE = 0.50
MIN_STAGE_COVERAGE = 0.95
RECOMMENDED_PROFILE = "panel-sobre"
CHALLENGER_PROFILE = "panel-fable"     # le bras Fable, propose a egalite (reprise 19/09)
# Les DEUX bras Fable que l'item ordonne de reprendre a egalite de chances.
FABLE_ARMS = ("fable-5-1", "fable-5")
MIN_PAIR_ITEMS = 3         # sous 3 items communs, un appariement ne vaut rien
MIN_PAIR_ATTEMPTS = 10     # essais EXPLOITABLES par bras sur les items communs
PROTOCOL_FILE = "protocole-essai-croise.md"


def out(k, v):
    """Une cle de recensement. JAMAIS d'espace dans la valeur : `proof.txt` la jetterait
    silencieusement (defaut connu, 2026-09). On les remplace au POINT DE PUBLICATION."""
    s = str(v).replace(" ", "_")
    print(f"{k}={s}")


def pct(a, b):
    return 0.0 if not b else round(100.0 * a / b, 2)


def canon(model):
    return (model or "").replace("[1m]", "")


def main():
    digest = json.loads((MEAS / "digest.json").read_text())
    timeline = json.loads((MEAS / "supervisor-timeline.json").read_text())
    attempts = digest["attempts"]

    def read_first(name):
        for p in (HERE / name, REPORT_DIR / name):
            if p.exists():
                return p.read_text(errors="replace")
        return None

    raw = read_first("sources.json")
    try:
        sources = json.loads(raw) if raw else None
    except Exception:
        sources = None
    try:
        profiles = json.loads((AUTOPORT / "model-profiles.json").read_text())
    except Exception:
        profiles = None
    rapport = read_first("RAPPORT.md") or ""

    pricing = (sources or {}).get("pricing", {}) or {}

    def price(model, inp, cread, cw5, cw1h, o):
        p = pricing.get(canon(model))
        if not p or p.get("input_per_mtok") is None:
            return None
        g = lambda k: p.get(k) or 0.0
        return (inp * g("input_per_mtok") + cread * g("cache_read_per_mtok")
                + cw5 * g("cache_write_5m_per_mtok") + cw1h * g("cache_write_1h_per_mtok")
                + o * g("output_per_mtok")) / 1e6

    # ---------------------------------------------------------- profils
    key = lambda a: (a["model"] or "(non-declare)", a["effort"] or "(non-declare)")
    counts = Counter(key(a) for a in attempts)
    big = [k for k, n in counts.most_common() if n >= MIN_ATTEMPTS]

    table = {}
    for k in big:
        rs = [a for a in attempts if key(a) == k]
        n = len(rs)
        verd = Counter(a["verdict"] for a in rs)
        decided = verd["vert"] + verd["rouge"]
        tok = Counter()
        for a in rs:
            for s in a["stages"].values():
                for b in ("inp", "cread", "cwrite", "cw5", "cw1h"):
                    tok[b] += s[b]
        with_res = [a for a in rs if a["model_usage"]]
        o_tot = sum(mu["out"] for a in with_res for mu in a["model_usage"].values())
        cost_meas = sum(mu["cost_usd"] for a in with_res for mu in a["model_usage"].values())
        cost_tar, n_tar = 0.0, 0
        for a in with_res:
            c = 0.0
            ok = True
            # Le partage 5 min / 1 h n'existe que par etage : on l'applique au prorata.
            tot_cw = sum(s["cwrite"] for s in a["stages"].values()) or 1
            r5 = sum(s["cw5"] for s in a["stages"].values()) / tot_cw
            for m, mu in a["model_usage"].items():
                v = price(m, mu["inp"], mu["cread"], mu["cwrite"] * r5,
                          mu["cwrite"] * (1 - r5), mu["out"])
                if v is None:
                    ok = False
                    break
                c += v
            if ok:
                cost_tar += c
                n_tar += 1
        table[k] = {
            "n": n, "decided": decided,
            "vert": verd["vert"], "rouge": verd["rouge"],
            "sans_verdict": verd["sans-verdict"], "inconnu": verd["inconnu"],
            "green_pct": pct(verd["vert"], decided),
            "loop": sum(1 for a in rs if a.get("in_loop")),
            "loop_pct": pct(sum(1 for a in rs if a.get("in_loop")), n),
            "cread_per": round(tok["cread"] / n),
            "cwrite_per": round(tok["cwrite"] / n),
            "inp_per": round(tok["inp"] / n),
            "out_per": round(o_tot / len(with_res)) if with_res else 0,
            "cost_measured": round(cost_meas / len(with_res), 2) if with_res else None,
            "cost_tariff": round(cost_tar / n_tar, 2) if n_tar else None,
            "n_result": len(with_res),
            "plomberie": sum(1 for a in rs if a.get("cause") == "plomberie"),
            "substance": sum(1 for a in rs if a.get("cause") == "substance"),
        }
        t = table[k]
        t["cost_per_green"] = (round(t["cost_measured"] / (t["green_pct"] / 100), 2)
                               if t["cost_measured"] and t["green_pct"] else None)

    # ---------------------------------------------------------- etages + superviseur
    top2 = [k for k, _ in counts.most_common() if k in big][:2]
    stages = {}
    for k in top2:
        rs = [a for a in attempts if key(a) == k]
        n = len(rs)
        agg = defaultdict(Counter)
        for a in rs:
            for s, v in a["stages"].items():
                for b in ("inp", "cread", "cwrite", "msgs"):
                    agg[s][b] += v[b]
        tot = sum(agg[s]["cread"] + agg[s]["cwrite"] + agg[s]["inp"] for s in agg) or 1
        stages[k] = {s: {"share_pct": pct(agg[s]["cread"] + agg[s]["cwrite"] + agg[s]["inp"], tot),
                         "cread_per": round(agg[s]["cread"] / n),
                         "msgs_per": round(agg[s]["msgs"] / n, 1)}
                     for s in agg}

    # Le superviseur n'a pas de profil a lui : on lui attribue celui qui TOURNAIT au
    # moment ou il a parle (dernier essai demarre avant l'horodatage du message).
    starts = sorted((a["started_at"], key(a)) for a in attempts if a["started_at"])
    skeys = [s[0] for s in starts]
    sup = defaultdict(Counter)
    for ts, inp, cread, cwrite, o in timeline:
        i = bisect.bisect_right(skeys, ts) - 1
        if i < 0:
            continue
        p = starts[i][1]
        sup[p]["cread"] += cread
        sup[p]["cwrite"] += cwrite
        sup[p]["out"] += o
        sup[p]["inp"] += inp
        sup[p]["msgs"] += 1

    # couverture d'attribution par etage (cf. residu de 1,3 % explique dans collect.py)
    with_res = [a for a in attempts if a["model_usage"]]
    st_sum = sum(v["cread"] for a in with_res for v in a["stages"].values())
    mu_sum = sum(mu["cread"] for a in with_res for mu in a["model_usage"].values()) or 1
    stage_coverage = st_sum / mu_sum

    # ---------------------------------------------------------- routage reellement applique
    conform = ignored = 0
    for a in attempts:
        want = canon(a.get("subagent_model"))
        if not want or canon(a["model"]) == want:
            continue
        for s, v in a["stages"].items():
            if s in ("principal", "codex-agrege"):
                continue
            for m in v.get("models", {}):
                if m == "<synthetic>":
                    continue
                if m == want:
                    conform += 1
                else:
                    ignored += 1

    # ---------------------------------------------------------- projections
    base = top2[0] if top2 else None
    proj = {}
    if base:
        rs = [a for a in attempts if key(a) == base]
        n = len(rs)
        agg = defaultdict(Counter)
        for a in rs:
            for s, v in a["stages"].items():
                for b in ("inp", "cread", "cwrite", "cw5", "cw1h", "msgs"):
                    agg[s][b] += v[b]
        msgs = sum(agg[s]["msgs"] for s in agg) or 1
        wres = [a for a in rs if a["model_usage"]]
        o_per = sum(mu["out"] for a in wres for mu in a["model_usage"].values()) / (len(wres) or 1)

        def mix(mgr, sub):
            tot = 0.0
            for s, v in agg.items():
                m = mgr if s == "principal" else sub
                # La sortie n'est pas attribuable a un etage (piege 2 de collect.py) : on
                # la repartit au prorata des messages, et on publie AUSSI la borne haute
                # « tout au manager ». La recommandation doit tenir dans les deux cas.
                c = price(m, v["inp"] / n, v["cread"] / n, v["cw5"] / n, v["cw1h"] / n,
                          o_per * v["msgs"] / msgs)
                if c is None:
                    return None
                tot += c
            return round(tot, 2)

        def mix_hi(mgr, sub):
            tot = 0.0
            for s, v in agg.items():
                m = mgr if s == "principal" else sub
                c = price(m, v["inp"] / n, v["cread"] / n, v["cw5"] / n, v["cw1h"] / n,
                          o_per if s == "principal" else 0)
                if c is None:
                    return None
                tot += c
            return round(tot, 2)

        for lab, mgr, sub in [
                ("actuel_opus5_opus5", "claude-opus-5", "claude-opus-5"),
                ("opus5_sonnet5", "claude-opus-5", "claude-sonnet-5"),
                ("opus5_haiku45", "claude-opus-5", "claude-haiku-4-5"),
                ("fable51_sonnet5", "claude-fable-5-1", "claude-sonnet-5"),
                ("sonnet5_haiku45", "claude-sonnet-5", "claude-haiku-4-5")]:
            proj[lab] = {"prorata": mix(mgr, sub), "borne_haute": mix_hi(mgr, sub)}

        # Le profil recommande n'est pas « un modele pour les sous-agents » : chaque etage
        # recoit le sien, selon la PART DE JETONS qu'il pese et la nature de son travail.
        PER_STAGE = {
            "principal": "claude-opus-5",
            "autoport-researcher": "claude-sonnet-5",
            "autoport-implementer": "claude-haiku-4-5",
            "autoport-tester": "claude-haiku-4-5",
        }

        def mix_stages(mapping, out_to_manager):
            tot = 0.0
            for s, v in agg.items():
                m = mapping.get(s, mapping["principal"])
                o = (o_per if s == "principal" else 0) if out_to_manager \
                    else o_per * v["msgs"] / msgs
                c = price(m, v["inp"] / n, v["cread"] / n, v["cw5"] / n, v["cw1h"] / n, o)
                if c is None:
                    return None
                tot += c
            return round(tot, 2)

        proj["recommande_panel_sobre"] = {
            "prorata": mix_stages(PER_STAGE, False),
            "borne_haute": mix_stages(PER_STAGE, True),
            "par_etage": PER_STAGE,
        }

        # REPRISE 19/09 — le meme calcul avec Fable 5.1 au manager. Il n'est PAS un
        # repoussoir : sa lecture de cache vaut 0,25 $/M contre 0,50 $/M a Opus 5, et le
        # cache fait 99 % du volume ; son entree et sa sortie valent le double. Les deux
        # effets se compensent presque exactement, et c'est ce que le chiffre doit montrer
        # au lieu d'un adjectif.
        PER_STAGE_FABLE = dict(PER_STAGE, principal="claude-fable-5-1")
        proj["challenger_panel_fable"] = {
            "prorata": mix_stages(PER_STAGE_FABLE, False),
            "borne_haute": mix_stages(PER_STAGE_FABLE, True),
            "par_etage": PER_STAGE_FABLE,
        }

    # ------------------------------------------- REPRISE 19/09 : Fable a egalite
    # « T'as fais une evaluation de merde sur notre historique, c'est eclate » (owner).
    # Les quatre termes qui suivent (7 a 10) sont la reponse MESUREE : appariement par
    # item, exclusions nommees et symetriques, verdict borne par un intervalle, et un
    # protocole d'essai croise dont on VERIFIE qu'il est lancable.
    pairs = {fam: paired.compare(attempts, fam) for fam in FABLE_ARMS}
    excl_census = paired.exclusion_census(attempts)

    # La PHRASE de verdict est construite ICI, a partir des chiffres, et le rapport DOIT
    # la porter telle quelle (terme 9). C'est ce qui empeche le rapport d'affirmer plus
    # que la mesure — la faute exacte que l'owner a relevee (« ecarte » sans mesure).
    def verdict_sentence(fam):
        c = pairs[fam]
        f, r = c["fable"], c["ref_stats"]
        lbl = {"fable-5-1": "Fable 5.1", "fable-5": "Fable 5"}[fam]
        fr = lambda x: str(x).replace(".", ",")   # le rapport est ecrit pour l'owner
        return (f"{lbl} est {c['verdict']} d'Opus 5 sur les {c['n_shared_items']} tâches "
                f"que les deux ont réellement traitées : {f['vert']} portes tenues sur "
                f"{f['decided']} ({fr(f['green_pct'])} %, intervalle "
                f"{fr(f['green_lo_pct'])} à {fr(f['green_hi_pct'])} %) contre {r['vert']} "
                f"sur {r['decided']} ({fr(r['green_pct'])} %, intervalle "
                f"{fr(r['green_lo_pct'])} à {fr(r['green_hi_pct'])} %).")

    sentences = {fam: verdict_sentence(fam) for fam in FABLE_ARMS}

    # ------------------------------------------- protocole d'essai croise
    # Un protocole qui nomme des items inexistants ou bloques n'est pas un protocole,
    # c'est une intention. On relit donc le backlog et on VERIFIE chaque item nomme.
    proto_txt = read_first(PROTOCOL_FILE) or ""
    proto = {"file": bool(proto_txt), "items": [], "ok_items": [], "profiles": [],
             "bad": []}
    try:
        import yaml
        bl = yaml.safe_load((AUTOPORT / "backlog.yaml").read_text())
        blitems = bl["items"] if isinstance(bl, dict) and "items" in bl else bl
        by_id = {i["id"]: i for i in blitems}
    except Exception:
        by_id = {}
    proto["items"] = re.findall(r"^- item `([a-z0-9][a-z0-9-]+)`", proto_txt, re.M)
    proto["profiles"] = re.findall(r"^- profil `([a-z0-9][a-z0-9-]+)`", proto_txt, re.M)
    closed = ("validated", "archived", "to-test")
    for iid in proto["items"]:
        it = by_id.get(iid)
        why = None
        if not it:
            why = "inconnu-du-backlog"
        elif it.get("status") != "open":
            why = f"statut={it.get('status')}"
        elif it.get("device"):
            why = "exige-l-appareil"     # la plomberie appareil noierait le signal modele
        elif not all((by_id.get(d) or {}).get("status") in closed
                     for d in (it.get("depends_on") or [])):
            why = "dependance-non-close"
        if why:
            proto["bad"].append(f"{iid}:{why}")
        else:
            proto["ok_items"].append(iid)
    proto["profiles_ok"] = [x for x in proto["profiles"]
                            if x in ((profiles or {}).get("profiles") or {})]

    # ---------------------------------------------------------- les termes
    terms = {}

    t1_bad = [k for k, v in table.items()
              if v["cread_per"] <= 0 or v["decided"] < MIN_DECIDED]
    terms[1] = (len(big) >= 2 and not t1_bad)

    t2_bad = [k for k, v in table.items()
              if v["n"] and (v["decided"] / v["n"]) < MIN_VERDICT_COVERAGE]
    terms[2] = (bool(table) and not t2_bad)

    sup_ok = all(sup.get(k, Counter())["cread"] > 0 for k in top2)
    terms[3] = (len(top2) == 2
                and all(len(stages[k]) >= 3 for k in top2)
                and stage_coverage >= MIN_STAGE_COVERAGE
                and sup_ok)

    # 4 — LA RECOMMANDATION EST UN PROFIL CONCRET, CHIFFRE, ET NON ACTIVE. Depuis la
    #     reprise du 19/09, ils sont DEUX : le profil sobre et son challenger Fable, parce
    #     qu'affirmer un gagnant que la mesure ne separe pas serait refaire la faute.
    #     Aucun des deux n'est actif : le geste est a l'owner, jamais au worker.
    prof_ok = False
    if profiles:
        ps = [(profiles.get("profiles") or {}).get(x)
              for x in (RECOMMENDED_PROFILE, CHALLENGER_PROFILE)]
        prof_ok = (all(ps)
                   and profiles.get("active") not in (RECOMMENDED_PROFILE, CHALLENGER_PROFILE)
                   and all(x.get("_cout_attendu_usd_par_essai") is not None for x in ps))
    terms[4] = prof_ok

    plomb = sum(v["plomberie"] for v in table.values())
    subst = sum(v["substance"] for v in table.values())
    biais = len(re.findall(r"^- \*\*BIAIS", rapport, re.M))
    terms[5] = (biais >= 6 and plomb > 0 and subst > 0)

    t6 = False
    if sources:
        srcs = sources.get("sources") or []
        cats = {s.get("category") for s in srcs}
        allurl = all(str(s.get("url", "")).startswith("https://") for s in srcs)
        alldate = all(s.get("date_consulted") for s in srcs)
        priced = sum(1 for v in pricing.values() if v.get("input_per_mtok") is not None)
        t6 = (len(srcs) >= 12 and len(cats) >= 5 and allurl and alldate and priced >= 4)
    terms[6] = t6

    # 7 — L'APPARIEMENT EXISTE ET PORTE. Les deux bras Fable sont compares a Opus 5 sur
    #     les MEMES items, avec assez d'essais exploitables de chaque cote pour que la
    #     comparaison ne soit pas une anecdote, et le detail PAR ITEM est publie.
    terms[7] = all(
        pairs[f]["n_shared_items"] >= MIN_PAIR_ITEMS
        and pairs[f]["fable"]["n"] >= MIN_PAIR_ATTEMPTS
        and pairs[f]["ref_stats"]["n"] >= MIN_PAIR_ATTEMPTS
        and len(pairs[f]["per_item"]) == pairs[f]["n_shared_items"]
        for f in FABLE_ARMS)

    # 8 — LES EXCLUSIONS SONT NOMMEES, CHIFFREES ET SYMETRIQUES. Chaque essai du
    #     recensement tombe dans un motif nomme (rien en reste), la regle mord AUSSI le
    #     bras de reference — sinon elle serait taillee pour faire gagner Fable — et le
    #     resultat SANS exclusion est publie pour qu'on voie si elle a fabrique le verdict.
    census_total_ok = all(
        v["total"] == v.get("abouti", 0) + v.get("refus-api", 0) + v.get("interrompu", 0)
        for v in excl_census.values())
    ref_excluded = (excl_census.get("opus-5", {}).get("total", 0)
                    - excl_census.get("opus-5", {}).get("abouti", 0))
    terms[8] = (census_total_ok and ref_excluded > 0
                and all(pairs[f]["exclusions"].get(f) for f in FABLE_ARMS)
                and all(pairs[f]["sensibilite"]["verdict"] != "non-mesurable"
                        for f in FABLE_ARMS))

    # 9 — LE VERDICT EST BORNE, ET LE RAPPORT NE DIT PAS PLUS QUE LA MESURE. Chaque bras
    #     a un intervalle de Wilson, le mot publie sort de l'intervalle et non de l'ecart
    #     des points, et le rapport porte la phrase construite ici, MOT POUR MOT.
    terms[9] = all(
        pairs[f]["verdict"] in ("meilleur", "pire", "indiscernable")
        and pairs[f]["fable"]["green_hi_pct"] > pairs[f]["fable"]["green_lo_pct"]
        and sentences[f] in rapport
        for f in FABLE_ARMS)

    # 10 — LE PROTOCOLE D'ESSAI CROISE EST LANCABLE. Trois items qui EXISTENT, ouverts,
    #      juges sur x86 (pas d'appareil : sa plomberie est 4 echecs sur 5) et dont aucune
    #      dependance ne bloque ; deux profils qui existent dans model-profiles.json.
    terms[10] = (proto["file"] and len(proto["ok_items"]) == 3
                 and not proto["bad"] and len(proto["profiles_ok"]) == 2)

    defects = sum(0 if ok else 1 for ok in terms.values())

    # ---------------------------------------------------------- publication
    out("model_mix_defects", defects)
    out("model_mix_terms_total", len(terms))
    out("model_mix_terms_measured", sum(1 for ok in terms.values() if ok))
    for i in sorted(terms):
        out(f"model_mix_term{i}_ok", 1 if terms[i] else 0)

    out("model_mix_attempts_scanned", len(attempts))
    out("model_mix_attempt_files", digest["attempt_files_found"])
    out("model_mix_validators", digest["validator_files_found"])
    out("model_mix_profiles_ge10", len(big))
    out("model_mix_verdict_green", sum(1 for a in attempts if a["verdict"] == "vert"))
    out("model_mix_verdict_red", sum(1 for a in attempts if a["verdict"] == "rouge"))
    out("model_mix_verdict_none", sum(1 for a in attempts if a["verdict"] == "sans-verdict"))
    out("model_mix_verdict_unknown", sum(1 for a in attempts if a["verdict"] == "inconnu"))
    out("model_mix_loop_attempts", sum(1 for a in attempts if a.get("in_loop")))
    out("model_mix_stuck_threshold", digest["stuck_threshold"])
    out("model_mix_cause_plumbing", plomb)
    out("model_mix_cause_substance", subst)
    out("model_mix_stage_coverage_pct", round(100 * stage_coverage, 2))
    out("model_mix_routing_conform", conform)
    out("model_mix_routing_ignored", ignored)
    out("model_mix_supervisor_sessions", digest["supervisor"]["files"])
    out("model_mix_supervisor_worker_sessions_excluded", digest["supervisor"]["worker_files"])
    out("model_mix_supervisor_cread_total", digest["supervisor"]["cread"])
    out("model_mix_biases_named", biais)
    out("model_mix_sources", len((sources or {}).get("sources", [])))
    out("model_mix_sources_categories", len({s.get("category") for s in (sources or {}).get("sources", [])}))
    out("model_mix_priced_models", sum(1 for v in pricing.values() if v.get("input_per_mtok") is not None))
    out("model_mix_recommended_profile", RECOMMENDED_PROFILE)
    out("model_mix_recommended_active", 1 if (profiles or {}).get("active") == RECOMMENDED_PROFILE else 0)
    out("model_mix_challenger_profile", CHALLENGER_PROFILE)
    out("model_mix_challenger_active", 1 if (profiles or {}).get("active") == CHALLENGER_PROFILE else 0)

    # --- reprise 19/09 : Fable a egalite de chances
    for fam in FABLE_ARMS:
        c = pairs[fam]
        sl = fam.replace("-", "_")
        f, r = c["fable"], c["ref_stats"]
        out(f"model_mix_pair_{sl}_verdict", c["verdict"])
        out(f"model_mix_pair_{sl}_shared_items", c["n_shared_items"])
        out(f"model_mix_pair_{sl}_n", f["n"])
        out(f"model_mix_pair_{sl}_green_pct", f["green_pct"])
        out(f"model_mix_pair_{sl}_green_ci", f"{f['green_lo_pct']}-{f['green_hi_pct']}")
        out(f"model_mix_pair_{sl}_loop_clean", f["loop_clean"])
        out(f"model_mix_pair_{sl}_usd_per_attempt", f["usd_per_attempt"])
        out(f"model_mix_pair_{sl}_usd_per_green", f["usd_per_green"])
        out(f"model_mix_pair_{sl}_ref_n", r["n"])
        out(f"model_mix_pair_{sl}_ref_green_pct", r["green_pct"])
        out(f"model_mix_pair_{sl}_ref_green_ci", f"{r['green_lo_pct']}-{r['green_hi_pct']}")
        out(f"model_mix_pair_{sl}_ref_loop_clean", r["loop_clean"])
        out(f"model_mix_pair_{sl}_ref_usd_per_green", r["usd_per_green"])
        out(f"model_mix_pair_{sl}_excluded", sum(c["exclusions"].get(fam, {}).values()))
        out(f"model_mix_pair_{sl}_ref_excluded",
            sum(c["exclusions"].get(c["ref"], {}).values()))
        out(f"model_mix_pair_{sl}_verdict_sans_exclusion", c["sensibilite"]["verdict"])
        # le detail PAR ITEM, que l'item reclame nommement
        for pi in c["per_item"]:
            slug = re.sub(r"[^A-Za-z0-9]+", "_", pi["item"]).strip("_").lower()[:46]
            a, b = pi["fable"], pi["ref"]
            out(f"model_mix_pair_{sl}_i_{slug}",
                f"fab:n{a['n']},v{a['vert']},b{a['loop_clean']},{a['usd_per_attempt']}usd;"
                f"ref:n{b['n']},v{b['vert']},b{b['loop_clean']},{b['usd_per_attempt']}usd")

    for fam, v in sorted(excl_census.items()):
        sl = fam.replace("-", "_").replace("(", "").replace(")", "")
        out(f"model_mix_excl_{sl}",
            f"total{v['total']},abouti{v.get('abouti', 0)},"
            f"refusapi{v.get('refus-api', 0)},interrompu{v.get('interrompu', 0)}")

    out("model_mix_protocol_items", ",".join(proto["ok_items"]) or "(aucun)")
    out("model_mix_protocol_items_ok", len(proto["ok_items"]))
    out("model_mix_protocol_items_bad", ",".join(proto["bad"]) or "(aucun)")
    out("model_mix_protocol_profiles_ok", len(proto["profiles_ok"]))

    for (m, e), v in table.items():
        slug = re.sub(r"[^A-Za-z0-9]+", "_", f"{m}_{e}").strip("_").lower()
        out(f"model_mix_p_{slug}_n", v["n"])
        out(f"model_mix_p_{slug}_green_pct", v["green_pct"])
        out(f"model_mix_p_{slug}_loop_pct", v["loop_pct"])
        out(f"model_mix_p_{slug}_cost_usd", v["cost_measured"] if v["cost_measured"] is not None else -1)
        out(f"model_mix_p_{slug}_cread_per_attempt", v["cread_per"])

    (MEAS / "tables.json").write_text(json.dumps({
        "profiles": {f"{m}/{e}": v for (m, e), v in table.items()},
        "stages": {f"{m}/{e}": v for (m, e), v in stages.items()},
        "supervisor_by_profile": {f"{m}/{e}": dict(v) for (m, e), v in sup.items()},
        "supervisor_total": digest["supervisor"],
        "projections": proj,
        "stage_coverage_pct": round(100 * stage_coverage, 2),
        "routing": {"conform": conform, "ignored": ignored},
        "terms": {str(i): bool(v) for i, v in terms.items()},
        "defects": defects,
        "top2": [f"{m}/{e}" for m, e in top2],
        "paired": pairs,
        "exclusion_census": excl_census,
        "verdict_sentences": sentences,
        "protocole": proto,
    }, indent=1, ensure_ascii=False))

    print(f"[model-mix] {defects} terme(s) non mesure(s) sur {len(terms)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
