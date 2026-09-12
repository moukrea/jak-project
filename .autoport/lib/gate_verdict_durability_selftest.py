#!/usr/bin/env python3
"""lib/gate_verdict_durability_selftest.py — LE BANC de `harness-gate-verdict-must-outlive-its-log`.

CE QU'IL FAIT. Il SEME des items dans des backlogs JETABLES — de vrais fichiers, ecrits et relus
par le VRAI `lib/backlog.py`, jamais un dictionnaire fabrique ici — et les fait prononcer, purger
et promouvoir par les VRAIS producteurs, dans les DEUX bras.

  A. L'ECRITURE   `orchestrator.pronounce_gate` ecrit le verdict DANS L'ITEM au moment ou la
                  porte le prononce. On relit le backlog SUR LE DISQUE : resultat, date,
                  empreinte des OCTETS de la preuve jugee — l'empreinte est RECALCULEE ici sur
                  les octets semes, jamais recopiee. Deux controles a laisser : un item qu'on n'a
                  pas prononce n'obtient RIEN, et un prononce SANS preuve sur le disque publie
                  `-` et `-1`, jamais un faux sha. Bras d'AVANT : le geste d'alors,
                  `set_status(iid, "to-test", delivered=...)`, qui ne laisse aucune trace.

  B. LA PURGE     LE STIMULUS EST L'EFFACEMENT DES JOURNAUX, pas un drapeau. Cinq items parques
                  sont semes IDENTIQUEMENT pour les deux bras — champs de verdict poses par le
                  VRAI `pronounce_gate` — puis `machine_proved_to_validated` tourne sur quatre
                  cellules : {bras d'AVANT, bras d'APRES} x {journaux presents, journaux
                  EFFACES}. Ce qui separe les bras est la LECTURE, pas l'etat du monde. Le
                  nombre de fichiers restants sous `logs/` apres la purge est publie : le
                  stimulus est mesure, jamais suppose.

  C. LE PERIMETRE `gate_verdict.scope_decision` rend la decision ET SA SOURCE. Six items semes,
                  un par source, dont deux controles qui decident SEULS de la valeur du
                  chantier : un `code_scope: engine` pose sur un item dont la PROSE dit
                  l'inverse (le champ doit gagner), et une formulation neuve — « n'ajoute aucun
                  C++ » — que les tournures listees ne reconnaissent pas. Bras d'AVANT : le
                  `gate_verdict.py` d'alors, qui ignore le champ et suit la prose.

  D. LA NON-REGRESSION  les quatre termes du chantier precedent sont REJOUES par son propre
                  recensement, bancs semes compris — pas relus dans son `proof.txt`, qui serait
                  une table perimee. Ce terme est calcule par le recensement de CET item, qui
                  seul peut lancer un script shell.

LES DEUX BRAS, PARTOUT. Le code d'AVANT est ancre par MARQUEUR — `git log` remonte jusqu'au
premier commit ou le marqueur est ABSENT — et jamais par `HEAD:` : lu a HEAD, le temoin d'avant
s'accuse lui-meme des le commit ou il nait. Le commit retenu est PUBLIE.

Sortie : des lignes `cle=valeur` sur stdout. Ce script ne juge rien et n'ecrit aucun champ de
proof.txt ; `lib/census/harness-gate-verdict-must-outlive-its-log.sh` fait la somme.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parent.parent
REPO = AP.parent

# Les marqueurs qui datent CE chantier, un par mecanisme.
MARKER_VERDICT = "VERDICT/dans-l-item"         # orchestrator.py + lib/backlog.py + autorite
MARKER_SCOPE = "PERIMETRE/champ-explicite"     # lib/gate_verdict.py

# Le geste de fermeture d'AVANT, tel qu'il s'ecrivait. Si ce litteral n'est pas dans le blob
# d'avant, le temoin est une invention et le banc le DIT au lieu de le rejouer.
SITE_FERMETURE_AVANT = 'bk.set_status(iid, "to-test",'

SANS_CODE = "Ne touche a aucun code du jeu. Ne promeut aucun item existant au passage."
AVEC_CODE = "Ne change pas le shader du ciel. Ne touche pas au pipeline HDR."
NEUVE = "N'ajoute aucun C++. Harnais seulement, rien qui se compile."

VERT = "[{iid} ok] source=x86 sha=0123456789abcdef frames=1234 crash=0 ; k == 0 tenu\n"

PREUVE = b"source=x86\nsha=0123456789abcdef\nframes=1234\ncrash=0\nverdict_durability_defects=0\n"


# UNE VALEUR TRONQUEE LE DIT. Les listes publiees ici — les items dont le perimetre a du etre
# devine, les parques sans verdict — sont precisement ce qu'un compte seul ne montre pas. Coupees
# a 400 octets sans un mot, elles laissaient croire que la liste etait complete : le compte a
# cote disait 13, la liste en portait 12 et le douzieme etait coupe au milieu. On ne coupe plus
# en silence, AU POINT DE PRODUCTION.
LIMITE = 400


def kv(key, value):
    texte = str(value).replace("\n", " ")
    if len(texte) > LIMITE:
        texte = texte[:LIMITE] + "..TRONQUE(%d-octets)" % len(texte)
    print("%s=%s" % (key, texte))


def charger(src: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def before_blob(rel: str, marker: str) -> tuple[str, str]:
    """Le premier commit, en remontant, dont `rel` ne porte PAS `marker`."""
    try:
        hist = subprocess.run(["git", "-C", str(REPO), "log", "--format=%H", "-n", "120",
                               "--", rel], capture_output=True, text=True,
                              timeout=60).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return "", ""
    for commit in hist:
        try:
            blob = subprocess.run(["git", "-C", str(REPO), "show", "%s:%s" % (commit, rel)],
                                  capture_output=True, text=True, timeout=60).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        if blob and marker not in blob:
            return commit, blob
    return "", ""


def semer_backlog(dossier: Path, items: list[dict]) -> Path:
    """Un backlog JETABLE, a cote de ses dossiers `logs/` et `reports/`."""
    dossier.mkdir(parents=True, exist_ok=True)
    (dossier / "logs").mkdir(exist_ok=True)
    (dossier / "reports").mkdir(exist_ok=True)
    chemin = dossier / "backlog.yaml"
    import yaml
    chemin.write_text(yaml.safe_dump({"version": 1, "items": items}, allow_unicode=True,
                                     sort_keys=False), encoding="utf-8")
    return chemin


def semer_preuve(dossier: Path, iid: str, octets: bytes) -> str:
    """La preuve jugee, sur le disque. Rend l'empreinte RECALCULEE ICI sur ces octets."""
    d = dossier / "reports" / iid
    d.mkdir(parents=True, exist_ok=True)
    (d / "proof.txt").write_bytes(octets)
    return hashlib.sha256(octets).hexdigest()[:16]


def semer_journal(dossier: Path, iid: str, verdicts: list[str]) -> None:
    d = dossier / "logs" / iid
    d.mkdir(parents=True, exist_ok=True)
    for i, v in enumerate(verdicts, start=1):
        (d / ("validator-%03d.txt" % i)).write_text(v.format(iid=iid), encoding="utf-8")


def compter_journaux(dossier: Path) -> int:
    """Combien de fichiers restent sous `logs/` : le stimulus se MESURE."""
    racine = dossier / "logs"
    return sum(len(f) for _, _, f in os.walk(racine)) if racine.is_dir() else 0


# ================================================================== A. L'ECRITURE ===========
EC_PRONONCE = "zzz-gvdl-ec-prononce"     # prononce, preuve sur le disque
EC_SANS_PREUVE = "zzz-gvdl-ec-sans"      # prononce, AUCUNE preuve -> sha `-`, octets -1
EC_TEMOIN = "zzz-gvdl-ec-temoin"         # JAMAIS prononce -> LE CONTROLE A LAISSER
EC_IDS = [EC_PRONONCE, EC_SANS_PREUVE, EC_TEMOIN]


def _items_ecriture() -> list[dict]:
    base = {"status": "in-progress", "priority": 1, "game": "jak1", "device": False,
            "owner_test": False, "feature": "banc de l'ecriture", "max_retries": 5}
    return [dict(base, id=i) for i in EC_IDS]


def axe_ecriture(prefixe: str, root: Path, O, B, apres: bool) -> None:
    d = root / ("ecr-" + prefixe)
    chemin = semer_backlog(d, _items_ecriture())
    sha_attendu = semer_preuve(d, EC_PRONONCE, PREUVE)
    kv("%s_a_pronounce" % prefixe, 1 if hasattr(O, "pronounce_gate") else 0)
    for iid in (EC_PRONONCE, EC_SANS_PREUVE):
        bk = B.load(str(chemin))
        if apres and hasattr(O, "pronounce_gate"):
            O.pronounce_gate(bk, iid, "to-test", "porte-tenue", 7, "validator-007.txt",
                             delivered="2026-09-12")
        else:
            # LE GESTE D'AVANT, tel quel : le statut, la date de livraison, et rien d'autre.
            bk.set_status(iid, "to-test", delivered="2026-09-12")
    kv("%s_ran" % prefixe, 1)
    bk = B.load(str(chemin))
    rec = (bk.get(EC_PRONONCE) or {}).get("gate_verdict")
    sans = (bk.get(EC_SANS_PREUVE) or {}).get("gate_verdict")
    temoin = (bk.get(EC_TEMOIN) or {}).get("gate_verdict")
    kv("%s_champ" % prefixe, 1 if isinstance(rec, dict) else 0)
    kv("%s_temoin_sans_champ" % prefixe, 0 if isinstance(temoin, dict) else 1)
    kv("%s_statut" % prefixe, (bk.get(EC_PRONONCE) or {}).get("status", "absent"))
    kv("%s_delivered" % prefixe, (bk.get(EC_PRONONCE) or {}).get("delivered", "-"))
    r = rec if isinstance(rec, dict) else {}
    kv("%s_result" % prefixe, r.get("result", "-"))
    kv("%s_date" % prefixe, r.get("date", "-"))
    kv("%s_sha" % prefixe, r.get("proof_sha", "-"))
    kv("%s_sha_attendu" % prefixe, sha_attendu)
    kv("%s_sha_concorde" % prefixe, 1 if r.get("proof_sha") == sha_attendu else 0)
    kv("%s_octets" % prefixe, r.get("proof_bytes", "-"))
    kv("%s_octets_attendus" % prefixe, len(PREUVE))
    kv("%s_essai" % prefixe, r.get("attempt", "-"))
    kv("%s_journal" % prefixe, r.get("journal", "-"))
    s = sans if isinstance(sans, dict) else {}
    kv("%s_sans_preuve_sha" % prefixe, s.get("proof_sha", "-"))
    kv("%s_sans_preuve_octets" % prefixe, s.get("proof_bytes", "-"))
    # ET IL SE RELIT : l'autorite rend le meme verdict, source `item`.
    import gate_verdict as G
    v = G.verdict_from_item(bk.get(EC_PRONONCE) or {})
    kv("%s_relu_source" % prefixe, (v or {}).get("source", "-"))
    kv("%s_relu_vert" % prefixe, 1 if (v or {}).get("green") else 0)


# ===================================================================== B. LA PURGE ==========
PU_VERT = "zzz-gvdl-pu-vert"        # champ porte-tenue + journal vert  -> SORT, purge ou non
PU_ROUGE = "zzz-gvdl-pu-rouge"      # champ porte-refusee + journal VERT -> RESTE (le champ fait foi)
PU_JOURNAL = "zzz-gvdl-pu-journal"  # AUCUN champ + journal vert        -> REPLI : sort, puis gele
PU_OWNER = "zzz-gvdl-pu-owner"      # champ porte-tenue, owner_test true -> RESTE des deux cotes
PU_RIEN = "zzz-gvdl-pu-rien"        # ni champ ni journal               -> RESTE partout
PU_IDS = [PU_VERT, PU_ROUGE, PU_JOURNAL, PU_OWNER, PU_RIEN]


def semer_purge(root: Path, nom: str, O, B) -> Path:
    """LE MEME SEMIS POUR LES DEUX BRAS : les champs de verdict sont poses par le VRAI
    `pronounce_gate`, jamais ecrits a la main ici. Ce qui separera les bras est la LECTURE."""
    base = {"priority": 1, "game": "jak1", "device": False, "feature": "banc de la purge"}
    items = [
        dict(base, id=PU_VERT, status="in-progress", owner_test=False),
        dict(base, id=PU_ROUGE, status="in-progress", owner_test=False),
        dict(base, id=PU_JOURNAL, status="to-test", owner_test=False),
        dict(base, id=PU_OWNER, status="in-progress", owner_test=True),
        dict(base, id=PU_RIEN, status="to-test", owner_test=False),
    ]
    d = root / nom
    chemin = semer_backlog(d, items)
    for iid in (PU_VERT, PU_ROUGE, PU_OWNER):
        semer_preuve(d, iid, PREUVE)
    bk = B.load(str(chemin))
    O.pronounce_gate(bk, PU_VERT, "to-test", "porte-tenue", 3, "validator-003.txt")
    bk = B.load(str(chemin))
    O.pronounce_gate(bk, PU_ROUGE, "to-test", "porte-refusee", 3, "validator-003.txt")
    bk = B.load(str(chemin))
    O.pronounce_gate(bk, PU_OWNER, "to-test", "porte-tenue", 3, "validator-003.txt")
    # Les journaux : le ROUGE en porte un VERT, pour que « le champ passe devant » se mesure.
    for iid in (PU_VERT, PU_ROUGE, PU_JOURNAL, PU_OWNER):
        semer_journal(d, iid, [VERT])
    return chemin


def axe_purge(prefixe: str, root: Path, O, B, purge: bool) -> None:
    d = root / ("purge-" + prefixe)
    chemin = semer_purge(root, "purge-" + prefixe, O, B)
    if purge:
        # LE STIMULUS : les journaux disparaissent, comme sur un clone neuf ou apres un menage.
        shutil.rmtree(d / "logs", ignore_errors=True)
    kv("%s_logs_restants" % prefixe, compter_journaux(d))
    bk = B.load(str(chemin))
    if hasattr(bk, "machine_promotion_plan"):
        plan = bk.machine_promotion_plan()
        kv("%s_plan" % prefixe,
           ",".join("%s:%s:%d" % (e["id"].rsplit("-", 1)[1], e["verdict"], e["promote"])
                    for e in plan) or "-")
        kv("%s_sources" % prefixe,
           ",".join("%s:%s" % (e["id"].rsplit("-", 1)[1], e.get("source", "-"))
                    for e in plan) or "-")
        # -1, jamais 0 : le plan d'AVANT ne porte PAS de cle `source`, et publier zero la ferait
        # lire « aucun repli » alors que la bonne lecture est « non mesure de ce cote ».
        kv("%s_replis" % prefixe,
           sum(1 for e in plan if e.get("source") == "journal")
           if any("source" in e for e in plan) else -1)
    else:
        kv("%s_plan" % prefixe, "-")
        kv("%s_sources" % prefixe, "-")
        kv("%s_replis" % prefixe, -1)
    promus = bk.machine_proved_to_validated()
    kv("%s_ran" % prefixe, 1)
    kv("%s_promus_n" % prefixe, len(promus))
    kv("%s_promus" % prefixe, ",".join(i.rsplit("-", 1)[1] for i in promus) or "-")
    relu = B.load(str(chemin))
    for iid in PU_IDS:
        kv("%s_st_%s" % (prefixe, iid.rsplit("-", 1)[1]),
           (relu.get(iid) or {}).get("status", "absent"))


# ================================================================= C. LE PERIMETRE ==========
SC_CAS = [
    # (suffixe, champs semes, decision attendue cote APRES, source attendue)
    ("champnone", {"code_scope": "none"}, 1, "champ-explicite"),
    ("champengine", {"code_scope": "engine", "out_of_scope": SANS_CODE}, 0, "champ-explicite"),
    ("drapeau", {"no_code": True}, 1, "drapeau-no_code"),
    ("prose", {"out_of_scope": SANS_CODE}, 1, "prose-devinee"),
    ("neuve", {"out_of_scope": NEUVE}, 0, "perimetre-muet"),
    ("conflit", {"code_scope": "engine", "no_code": True}, 0, "champ-explicite"),
]


def axe_perimetre(prefixe: str, G, apres: bool) -> None:
    kv("%s_a_decision" % prefixe, 1 if hasattr(G, "scope_decision") else 0)
    decisions, sources = [], []
    for suffixe, champs, _, _ in SC_CAS:
        item = dict(champs, id="zzz-gvdl-sc-" + suffixe, status="open")
        libre, _raison = G.code_free_item(item)
        decisions.append("%s:%d" % (suffixe, 1 if libre else 0))
        if apres and hasattr(G, "scope_decision"):
            sources.append("%s:%s" % (suffixe, G.scope_decision(item)["source"]))
    kv("%s_decisions" % prefixe, ",".join(decisions))
    kv("%s_sources" % prefixe, ",".join(sources) or "-")
    kv("%s_ran" % prefixe, 1)


# ============================================== D-bis. L'AUTORITE VOYAGE AVEC backlog.py ====
# `orchestrator.load_backlog` fait `importlib.reload(backlog)` a chaque tour — c'est ce qui
# permet a `lib/backlog.py` de corriger la file sans redemarrer la boucle. Recharger CE module ne
# recharge PAS `gate_verdict` : l'import y retrouve l'objet deja pose dans `sys.modules`, celui
# du demarrage. Un orchestrateur lance AVANT ce chantier aurait donc joue le
# `machine_promotion_plan` NEUF contre une autorite VIEILLE, sans `verdict_from_item` :
# `AttributeError` avale par le `try` de `free_machine_proved`, et la promotion machine
# s'arretait EN SILENCE — le gel meme que ce chantier corrige, refabrique par lui.
#
# LA SITUATION EST EMULEE FIDELEMENT : un module dont le SPEC pointe le vrai
# `lib/gate_verdict.py` mais dont on a execute la source d'AVANT. C'est exactement un
# orchestrateur en vol : l'objet en memoire est d'hier, le fichier sur le disque est d'aujourd'hui.
def axe_rechargement(root: Path, vieux_gv_source: str, vieux_bk_path) -> None:
    import importlib
    # `from lib import gate_verdict` NE LIT PAS `sys.modules` : il fait un `getattr` sur l'objet
    # paquet `lib`. Poser la seule entree de `sys.modules` laissait le bras d'AVANT voir
    # l'autorite NEUVE, et le temoin rendait 1 la ou il devait rendre 0. L'ATTRIBUT DU PAQUET
    # FAIT PARTIE DE L'ETAT A EMULER.
    sauve = {n: sys.modules.get(n) for n in ("gate_verdict", "lib.gate_verdict")}
    paquet = sys.modules.get("lib")
    sauve_attr = getattr(paquet, "gate_verdict", None) if paquet is not None else None
    reel = AP / "lib" / "gate_verdict.py"
    try:
        spec = importlib.util.spec_from_file_location("lib.gate_verdict", reel)
        perime = importlib.util.module_from_spec(spec)
        exec(compile(vieux_gv_source, str(reel), "exec"), perime.__dict__)   # noqa: S102
        sys.modules["lib.gate_verdict"] = perime
        sys.modules["gate_verdict"] = perime
        if paquet is not None:
            paquet.gate_verdict = perime
        # LE CONTROLE DE NON-VACUITE : l'autorite d'AVANT n'a VRAIMENT pas la fonction neuve.
        kv("rl_perimee_a_le_champ", 1 if hasattr(perime, "verdict_from_item") else 0)
        # BRAS D'AVANT : `lib/backlog.py` tel qu'il etait, qui importe sans recharger.
        if vieux_bk_path:
            M = charger(vieux_bk_path, "bk_rl_avant_gvdl")
            kv("rl_avant_autorite_fraiche",
               1 if hasattr(M._gate_verdict, "verdict_from_item") else 0)
        # BRAS D'APRES : celui du disque. Son import recharge l'autorite depuis le VRAI fichier.
        N = charger(AP / "lib" / "backlog.py", "bk_rl_apres_gvdl")
        kv("rl_apres_autorite_fraiche",
           1 if hasattr(N._gate_verdict, "verdict_from_item") else 0)
        # ET CA MARCHE POUR DE VRAI : memes semis que l'axe B, journaux EFFACES.
        O = sys.modules["orch_neuf_gvdl"]
        d = root / "purge-rl_apres"
        chemin = semer_purge(root, "purge-rl_apres", O, N)
        shutil.rmtree(d / "logs", ignore_errors=True)
        promus = N.load(str(chemin)).machine_proved_to_validated()
        kv("rl_apres_promus_n", len(promus))
        kv("rl_apres_promus", ",".join(i.rsplit("-", 1)[1] for i in promus) or "-")
        kv("rl_ran", 1)
    finally:
        for nom, mod in sauve.items():
            if mod is None:
                sys.modules.pop(nom, None)
            else:
                sys.modules[nom] = mod
        if paquet is not None and sauve_attr is not None:
            paquet.gate_verdict = sauve_attr


# ======================================================= LE DEPOT, MAINTENANT ===============
def depot_maintenant() -> None:
    """Le backlog LIVRE, relu par l'autorite. Publie, JAMAIS compte : un item mal etiquete
    aujourd'hui n'est pas une faute de ce chantier, et exiger sa correction pour fermer serait
    exiger qu'on reecrive le perimetre de 12 items d'autrui. Le compte, lui, le DIT."""
    sys.path.insert(0, str(AP / "lib"))
    import gate_verdict as G
    import yaml
    try:
        items = (yaml.safe_load((AP / "backlog.yaml").read_text(encoding="utf-8"))
                 or {}).get("items") or []
    except Exception:                                                 # noqa: BLE001
        items = []
    kv("live_items", len(items))
    c = G.verdict_field_census(items)
    kv("live_parques", len(c["porteurs"]) + len(c["absents"]) + len(c["illisibles"]))
    kv("live_verdict_porteurs", len(c["porteurs"]))
    kv("live_verdict_porteurs_liste", ",".join(c["porteurs"]) or "-")
    kv("live_verdict_absents", len(c["absents"]))
    kv("live_verdict_absents_liste", ",".join(c["absents"]) or "-")
    kv("live_verdict_illisibles", len(c["illisibles"]))
    s = G.scope_census(items)
    kv("live_scope_explicite", len(s["explicite"]))
    kv("live_scope_devine", len(s["devine"]))
    kv("live_scope_devine_liste", ",".join(s["devine"]) or "-")
    kv("live_scope_muet", len(s["muet"]))
    kv("live_scope_illisible", len(s["illisible"]))
    kv("live_scope_drapeaux", len(s["drapeaux"]))
    try:
        import backlog as BK
        bk = BK.load(str(AP / "backlog.yaml"))
        plan = bk.machine_promotion_plan()
        kv("live_plan", ",".join("%s:%s:%s:%d" % (e["id"], e["verdict"], e.get("source", "-"),
                                                  e["promote"]) for e in plan) or "-")
        kv("live_promouvables", sum(1 for e in plan if e["promote"]))
        kv("live_replis_journal", sum(1 for e in plan if e.get("source") == "journal"))
    except Exception as exc:                                          # noqa: BLE001
        kv("live_plan", "exception:%s" % type(exc).__name__)
        kv("live_promouvables", -1)
        kv("live_replis_journal", -1)


def temoins_source() -> None:
    orch = (AP / "orchestrator.py").read_text(encoding="utf-8")
    bkl = (AP / "lib" / "backlog.py").read_text(encoding="utf-8")
    gv = (AP / "lib" / "gate_verdict.py").read_text(encoding="utf-8")
    kv("src_marker_verdict_orch", 1 if MARKER_VERDICT in orch else 0)
    kv("src_marker_verdict_backlog", 1 if MARKER_VERDICT in bkl else 0)
    kv("src_marker_verdict_autorite", 1 if MARKER_VERDICT in gv else 0)
    kv("src_marker_scope_autorite", 1 if MARKER_SCOPE in gv else 0)
    # LE CHAMP EST LU EN PREMIER, LE JOURNAL EN REPLI : l'ordre se lit dans le source.
    corps = bkl[bkl.find("def machine_promotion_plan(self):"):
                bkl.find("def machine_proved_to_validated(self):")]
    kv("src_plan_lu", 1 if corps else 0)
    kv("src_plan_lit_le_champ", corps.count("_gate_verdict.verdict_from_item("))
    kv("src_plan_lit_le_journal", corps.count("_gate_verdict.validator_verdict("))
    kv("src_champ_avant_journal",
       1 if (corps.find("verdict_from_item(") >= 0
             and corps.find("verdict_from_item(") < corps.find("validator_verdict(")) else 0)
    # LA PORTE PRONONCE AUX DEUX SORTIES VERTES, et plus une seule ne pose le statut nu.
    kv("src_backlog_reloads_authority", bkl.count("importlib.reload(_gate_verdict)"))
    kv("src_orch_prononce", orch.count("pronounce_gate(bk, iid,"))
    kv("src_orch_to_test_nu", orch.count('bk.set_status(iid, "to-test"'))
    kv("src_orch_valide_nu", orch.count('bk.set_status(iid, "validated")'))
    # HORS PERIMETRE : le jeu n'est pas touche.
    r = subprocess.run(["git", "-C", str(REPO), "status", "--porcelain", "--",
                        "game/", "common/", "android/", "goal_src/", "goalc/"],
                       capture_output=True, text=True, timeout=120)
    sales = [x[3:] for x in r.stdout.splitlines() if x.strip()]
    kv("src_engine_dirty", len(sales))
    kv("src_engine_dirty_list", ",".join(sales[:12]) or "-")


# ===================================================================================== main =
def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="gvdl-banc-"))
    try:
        c_orch, b_orch = before_blob(".autoport/orchestrator.py", MARKER_VERDICT)
        c_bk, b_bk = before_blob(".autoport/lib/backlog.py", MARKER_VERDICT)
        c_gv, b_gv = before_blob(".autoport/lib/gate_verdict.py", MARKER_SCOPE)
        # L'autorite d'AVANT LE VERDICT — celle qui n'a pas `verdict_from_item`. Marqueur
        # different du precedent : les deux mecanismes ne sont pas nes au meme commit.
        c_gv_v, b_gv_verdict = before_blob(".autoport/lib/gate_verdict.py", MARKER_VERDICT)
        kv("before_orch_commit", c_orch[:12] or "-")
        kv("before_backlog_commit", c_bk[:12] or "-")
        kv("before_gate_verdict_commit", c_gv[:12] or "-")
        kv("before_authority_verdict_commit", c_gv_v[:12] or "-")
        kv("before_orch_marker_absent", 1 if (b_orch and MARKER_VERDICT not in b_orch) else 0)
        kv("before_backlog_marker_absent", 1 if (b_bk and MARKER_VERDICT not in b_bk) else 0)
        kv("before_gv_marker_absent", 1 if (b_gv and MARKER_SCOPE not in b_gv) else 0)
        kv("before_orch_site_fermeture",
           1 if (b_orch and SITE_FERMETURE_AVANT in b_orch) else 0)
        kv("marker_verdict_live",
           1 if MARKER_VERDICT in (AP / "orchestrator.py").read_text(encoding="utf-8") else 0)
        kv("marker_scope_live",
           1 if MARKER_SCOPE in (AP / "lib" / "gate_verdict.py").read_text(encoding="utf-8")
           else 0)

        sys.path.insert(0, str(AP))
        sys.path.insert(0, str(AP / "lib"))

        vieux_orch = vieux_bk = vieux_gv = None
        if b_orch:
            vieux_orch = root / "vieux_orchestrator.py"
            vieux_orch.write_text(b_orch, encoding="utf-8")
        if b_bk:
            vieux_bk = root / "vieux_backlog.py"
            vieux_bk.write_text(b_bk, encoding="utf-8")
        if b_gv:
            vieux_gv = root / "vieux_gate_verdict.py"
            vieux_gv.write_text(b_gv, encoding="utf-8")

        B_neuf = charger(AP / "lib" / "backlog.py", "bk_neuf_gvdl")
        B_vieux = charger(vieux_bk, "bk_vieux_gvdl") if vieux_bk else None
        O_neuf = charger(AP / "orchestrator.py", "orch_neuf_gvdl")
        O_vieux = charger(vieux_orch, "orch_vieux_gvdl") if vieux_orch else None
        G_neuf = charger(AP / "lib" / "gate_verdict.py", "gv_neuf_gvdl")
        G_vieux = charger(vieux_gv, "gv_vieux_gvdl") if vieux_gv else None
        O_neuf.log = lambda *a, **k: None
        if O_vieux:
            O_vieux.log = lambda *a, **k: None

        # A. L'ECRITURE, les deux bras.
        axe_ecriture("ec_apres", root, O_neuf, B_neuf, True)
        if O_vieux:
            axe_ecriture("ec_avant", root, O_vieux, B_neuf, False)

        # B. LA PURGE — MEME semis, quatre cellules : deux lecteurs x deux regimes.
        axe_purge("pu_apres_avec", root, O_neuf, B_neuf, False)
        axe_purge("pu_apres_purge", root, O_neuf, B_neuf, True)
        if B_vieux:
            axe_purge("pu_avant_avec", root, O_neuf, B_vieux, False)
            axe_purge("pu_avant_purge", root, O_neuf, B_vieux, True)

        # C. LE PERIMETRE, les deux bras.
        axe_perimetre("sc_apres", G_neuf, True)
        if G_vieux:
            axe_perimetre("sc_avant", G_vieux, False)

        temoins_source()
        depot_maintenant()
        # EN DERNIER : cet axe pose une autorite PERIMEE dans `sys.modules` avant de la rendre.
        axe_rechargement(root, b_gv_verdict or "", vieux_bk)

        for rel in ("orchestrator.py", "lib/backlog.py", "lib/gate_verdict.py",
                    "lib/gate_verdict_durability_selftest.py",
                    "lib/close_gate_code_free_selftest.py",
                    "lib/census/harness-gate-verdict-must-outlive-its-log.sh",
                    "validators/generic.sh"):
            try:
                h = hashlib.sha256((AP / rel).read_bytes()).hexdigest()[:16]
            except OSError:
                h = "-"
            kv("sha_" + rel.replace("/", "_").replace(".", "_").replace("-", "_"), h)
        return 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
