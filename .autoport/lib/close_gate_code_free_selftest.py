#!/usr/bin/env python3
"""lib/close_gate_code_free_selftest.py — LE BANC de `harness-close-gate-code-free`.

CE QU'IL FAIT. Il SEME des items dans des backlogs JETABLES — de vrais fichiers, lus et ecrits
par le VRAI `lib/backlog.py`, jamais un dictionnaire fabrique ici — puis il joue sur eux le VRAI
lancement et la VRAIE porte de fermeture, dans les DEUX bras :

  1. LANCEMENT  `orchestrator.launch_item` prononce le perimetre AU LANCEMENT et pose
                `no_code: true` dans le backlog. Trois items SEMES : un dont le perimetre
                interdit le code et n'a pas le drapeau (a traiter), un qui l'a deja (a
                journaliser sans rien changer), et un dont le perimetre AUTORISE le code
                (LE CONTROLE A LAISSER : il ne doit surtout pas recevoir le drapeau).
  2. PORTE      `orchestrator.close_gate` sur les MEMES items jetables, bras d'AVANT contre
                bras d'APRES, dans un depot git jetable SANS aucun fichier moteur — donc GATE 1
                n'a rien a se mettre sous la dent, deterministe des deux cotes. Trois cas :
                perimetre sans code (AVANT refuse / APRES passe), perimetre AVEC code (LES DEUX
                refusent — GATE 1 mord toujours, c'est le controle a laisser), drapeau deja pose
                (LES DEUX passent — la parole du superviseur n'a pas change de sens).
  3. PROMOTION  `backlog.machine_proved_to_validated` sur un backlog jetable ou SIX items sont
                semes : porte tenue (doit sortir), porte refusee (doit rester), journal absent
                (doit rester), journal vert PUIS rouge (doit rester : c'est le DERNIER verdict
                qui compte), `owner_test: true` avec porte tenue (doit rester : c'est l'owner
                qui ferme), et `open` (doit rester : on ne promeut que ce qui est parque).
  4. NOM        le nom de la fonction et ce qu'elle fait. Verdict : LE NOM RESTE, la fonction
                verifie desormais ce qu'il promet.

LES DEUX BRAS, PARTOUT. Le code d'AVANT ce chantier est ancre par MARQUEUR — `git log` remonte
jusqu'au premier commit ou le marqueur est ABSENT — et jamais par `HEAD:` : lu a HEAD, le
temoin d'avant s'accuse lui-meme des le commit ou il nait. Le commit retenu est PUBLIE.

Sortie : des lignes `cle=valeur` sur stdout. Ce script ne juge rien et n'ecrit aucun champ de
proof.txt ; `lib/census/harness-close-gate-code-free.sh` fait la somme.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parent.parent
REPO = AP.parent

# Les marqueurs qui datent CE chantier, un par mecanisme.
MARKER_GATE1 = "GATE1/perimetre-sans-code"       # orchestrator.py + lib/gate_verdict.py
MARKER_PROMO = "PROMOTION/relit-le-verdict"      # lib/backlog.py   + lib/gate_verdict.py

# Le geste de lancement d'AVANT, tel qu'il s'ecrivait. Si ce litteral n'est pas dans le blob
# d'avant, le temoin est une invention et le banc le DIT au lieu de le rejouer.
SITE_LANCEMENT_AVANT = 'bk.set_status(iid, "in-progress")'

SANS_CODE = "Ne touche a aucun code du jeu. Ne promeut aucun item existant au passage."
AVEC_CODE = "Ne change pas le shader du ciel. Ne touche pas au pipeline HDR."

VERT = "[{iid} ok] source=x86 sha=0123456789abcdef frames=1234 crash=0 ; k == 0 tenu\n"
ROUGE = ("[{iid} FAIL] frames=12 sous le seuil 300 : rien n'a ete dessine assez longtemps\n"
         "[{iid} FAIL] 1 constat(s) ci-dessus, aucun n'a ete masque par un autre.\n")


def kv(key, value):
    print("%s=%s" % (key, str(value).replace("\n", " ")[:400]))


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


# ======================================================================== semer un backlog ==
def semer_backlog(dossier: Path, items: list[dict]) -> Path:
    """Un backlog JETABLE, ecrit par le vrai dumper, a cote de son dossier `logs/`."""
    dossier.mkdir(parents=True, exist_ok=True)
    (dossier / "logs").mkdir(exist_ok=True)
    chemin = dossier / "backlog.yaml"
    import yaml
    chemin.write_text(yaml.safe_dump({"version": 1, "items": items}, allow_unicode=True,
                                     sort_keys=False), encoding="utf-8")
    return chemin


def semer_journal(dossier: Path, iid: str, verdicts: list[str]) -> None:
    """Les journaux de validation de cet item, dans l'ordre des essais."""
    d = dossier / "logs" / iid
    d.mkdir(parents=True, exist_ok=True)
    for i, v in enumerate(verdicts, start=1):
        (d / ("validator-%03d.txt" % i)).write_text(v.format(iid=iid), encoding="utf-8")


def statuts(B, chemin: Path, ids: list[str]) -> str:
    """Les statuts RELUS SUR LE DISQUE, jamais l'objet qu'on tenait en memoire."""
    bk = B.load(str(chemin))
    return ",".join("%s:%s" % (i, (bk.get(i) or {}).get("status", "absent")) for i in ids)


def drapeaux(B, chemin: Path, ids: list[str]) -> str:
    bk = B.load(str(chemin))
    return ",".join("%s:%d" % (i, 1 if (bk.get(i) or {}).get("no_code") else 0) for i in ids)


# ================================================================== 1. LE LANCEMENT =========
LANC_SANS = "zzz-ccgf-lanc-sans"      # perimetre sans code, drapeau ABSENT -> a traiter
LANC_AVEC = "zzz-ccgf-lanc-avec"      # perimetre sans code, drapeau DEJA pose
LANC_CODE = "zzz-ccgf-lanc-code"      # perimetre AVEC code -> LE CONTROLE A LAISSER
LANC_IDS = [LANC_SANS, LANC_AVEC, LANC_CODE]


def _items_lancement() -> list[dict]:
    base = {"status": "open", "priority": 1, "game": "jak1", "device": False,
            "owner_test": False, "feature": "banc du lancement", "max_retries": 5}
    a = dict(base, id=LANC_SANS, out_of_scope=SANS_CODE)
    b = dict(base, id=LANC_AVEC, out_of_scope=SANS_CODE, no_code=True)
    c = dict(base, id=LANC_CODE, out_of_scope=AVEC_CODE)
    return [a, b, c]


def axe_lancement(prefixe: str, root: Path, O, B, apres: bool) -> None:
    """Joue le geste de lancement du bras, puis RELIT le backlog sur le disque."""
    d = root / ("lanc-" + prefixe)
    chemin = semer_backlog(d, _items_lancement())
    kv("%s_a_launch_item" % prefixe, 1 if hasattr(O, "launch_item") else 0)
    for iid in LANC_IDS:
        bk = B.load(str(chemin))
        item = bk.get(iid)
        if apres and hasattr(O, "launch_item"):
            O.launch_item(bk, item)
        else:
            # LE GESTE D'AVANT, tel quel : l'item passe `in-progress`, et rien d'autre.
            bk.set_status(iid, "in-progress")
    kv("%s_ran" % prefixe, 1)
    kv("%s_drapeaux" % prefixe, drapeaux(B, chemin, LANC_IDS))
    kv("%s_statuts" % prefixe, statuts(B, chemin, LANC_IDS))
    bk = B.load(str(chemin))
    kv("%s_pose_sans" % prefixe, 1 if (bk.get(LANC_SANS) or {}).get("no_code") else 0)
    kv("%s_pose_avec" % prefixe, 1 if (bk.get(LANC_AVEC) or {}).get("no_code") else 0)
    kv("%s_pose_code" % prefixe, 1 if (bk.get(LANC_CODE) or {}).get("no_code") else 0)
    # LE JOURNAL DES LANCEMENTS : combien de lancements dont le perimetre interdit le code, et
    # combien ont REELLEMENT recu le drapeau ici. C'est le compte que le livrable exige.
    import gate_verdict as G
    lignes, poses = G.launch_journal_counts(str(d / "logs"))
    kv("%s_journal_lignes" % prefixe, lignes)
    kv("%s_journal_poses" % prefixe, poses)
    kv("%s_journal_existe" % prefixe,
       1 if (d / "logs" / G.LAUNCH_JOURNAL).exists() else 0)


# ======================================================================= 2. LA PORTE ========
PORTE_SANS = "zzz-ccgf-porte-sans"        # perimetre sans code, drapeau ABSENT
PORTE_CODE = "zzz-ccgf-porte-code"        # perimetre AVEC code -> LE CONTROLE A LAISSER
PORTE_DRAP = "zzz-ccgf-porte-drapeau"     # drapeau pose, perimetre muet
PORTE_IDS = [PORTE_SANS, PORTE_CODE, PORTE_DRAP]


def _items_porte() -> list[dict]:
    base = {"status": "in-progress", "priority": 1, "game": "jak1", "device": False,
            "owner_test": False, "owner_verify": False, "feature": "banc de la porte"}
    return [dict(base, id=PORTE_SANS, out_of_scope=SANS_CODE),
            dict(base, id=PORTE_CODE, out_of_scope=AVEC_CODE),
            dict(base, id=PORTE_DRAP, out_of_scope="", no_code=True)]


def faux_depot(root: Path) -> Path:
    """Un depot git jetable SANS un seul fichier moteur, avec deux commits : `HEAD~1` existe,
    et GATE 1 n'y trouvera JAMAIS de code de portage. La porte est donc deterministe des deux
    cotes — ce qui les separe est la decision, pas l'etat du depot de travail."""
    d = root / "faux-depot"
    d.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "GIT_AUTHOR_NAME": "banc", "GIT_AUTHOR_EMAIL": "banc@local",
           "GIT_COMMITTER_NAME": "banc", "GIT_COMMITTER_EMAIL": "banc@local"}
    subprocess.run(["git", "init", "-q", "."], cwd=d, capture_output=True, timeout=60)
    for i in (1, 2):
        (d / "LISEZMOI.txt").write_text("banc %d\n" % i, encoding="utf-8")
        subprocess.run(["git", "add", "LISEZMOI.txt"], cwd=d, capture_output=True, timeout=60)
        subprocess.run(["git", "commit", "-q", "-m", "banc %d" % i], cwd=d, env=env,
                       capture_output=True, timeout=60)
    return d


def axe_porte(prefixe: str, root: Path, O, depot: Path, faux_ap: Path) -> None:
    O.REPO_ROOT = depot
    O.AUTOPORT_DIR = faux_ap
    O.BACKLOG_PATH = faux_ap / "backlog.yaml"
    O.log = lambda *a, **k: None
    for iid in PORTE_IDS:
        item = next(x for x in _items_porte() if x["id"] == iid)
        try:
            st, raison = O.close_gate(item, [], validator_ok=True, since=time.time())
        except Exception as exc:                                      # noqa: BLE001
            st, raison = "exception:%s" % type(exc).__name__, str(exc)
        court = iid.rsplit("-", 1)[1]
        kv("%s_%s_statut" % (prefixe, court), st)
        kv("%s_%s_code" % (prefixe, court), 1 if "CLOSE-GATE/code" in (raison or "") else 0)
        kv("%s_%s_raison" % (prefixe, court), (raison or "-")[:180])
    kv("%s_ran" % prefixe, 1)


# =================================================================== 3. LA PROMOTION ========
PR_VERT = "zzz-ccgf-pr-vert"        # porte TENUE                       -> doit SORTIR
PR_ROUGE = "zzz-ccgf-pr-rouge"      # porte REFUSEE                     -> doit RESTER
PR_MUET = "zzz-ccgf-pr-muet"        # aucun journal                     -> doit RESTER
PR_REGRESSE = "zzz-ccgf-pr-regresse"  # vert PUIS rouge                 -> doit RESTER
PR_OWNER = "zzz-ccgf-pr-owner"      # porte tenue, owner_test true      -> doit RESTER
PR_OUVERT = "zzz-ccgf-pr-ouvert"    # porte tenue mais pas parque       -> doit RESTER
PR_IDS = [PR_VERT, PR_ROUGE, PR_MUET, PR_REGRESSE, PR_OWNER, PR_OUVERT]


def semer_promotion(root: Path, nom: str) -> Path:
    base = {"priority": 1, "game": "jak1", "device": False, "feature": "banc de la promotion"}
    items = [
        dict(base, id=PR_VERT, status="to-test", owner_test=False),
        dict(base, id=PR_ROUGE, status="to-test", owner_test=False),
        dict(base, id=PR_MUET, status="to-test", owner_test=False),
        dict(base, id=PR_REGRESSE, status="to-test", owner_test=False),
        dict(base, id=PR_OWNER, status="to-test", owner_test=True),
        dict(base, id=PR_OUVERT, status="open", owner_test=False),
    ]
    d = root / nom
    chemin = semer_backlog(d, items)
    # Le VERT porte DEUX journaux, rouge puis vert : c'est le DERNIER qui doit compter.
    semer_journal(d, PR_VERT, [ROUGE, VERT])
    semer_journal(d, PR_ROUGE, [ROUGE])
    semer_journal(d, PR_REGRESSE, [VERT, ROUGE])
    semer_journal(d, PR_OWNER, [VERT])
    semer_journal(d, PR_OUVERT, [VERT])
    return chemin


def axe_promotion(prefixe: str, root: Path, B, apres: bool) -> None:
    chemin = semer_promotion(root, "promo-" + prefixe)
    bk = B.load(str(chemin))
    kv("%s_a_plan" % prefixe, 1 if hasattr(bk, "machine_promotion_plan") else 0)
    if apres and hasattr(bk, "machine_promotion_plan"):
        plan = bk.machine_promotion_plan()
        kv("%s_plan" % prefixe,
           ",".join("%s:%s:%d" % (e["id"].rsplit("-", 1)[1], e["verdict"], e["promote"])
                    for e in plan))
    promus = bk.machine_proved_to_validated()
    kv("%s_ran" % prefixe, 1)
    kv("%s_promus_n" % prefixe, len(promus))
    kv("%s_promus" % prefixe, ",".join(i.rsplit("-", 1)[1] for i in promus) or "-")
    kv("%s_refuses" % prefixe,
       ",".join("%s:%s" % (i.rsplit("-", 1)[1], r)
                for i, r, _j, _o in getattr(bk, "machine_promotion_refused", [])) or "-")
    # L'ORIGINE DU VERDICT, A COTE ET JAMAIS A LA PLACE (signalement 9 du 12/09).
    kv("%s_refuses_origines" % prefixe,
       ",".join("%s:%s" % (i.rsplit("-", 1)[1], o)
                for i, _r, _j, o in getattr(bk, "machine_promotion_refused", [])) or "-")
    kv("%s_statuts" % prefixe, statuts(B, chemin, PR_IDS))
    for iid in PR_IDS:
        court = iid.rsplit("-", 1)[1]
        kv("%s_st_%s" % (prefixe, court),
           (B.load(str(chemin)).get(iid) or {}).get("status", "absent"))


# ================================================================ LES TEMOINS DE SOURCE =====
def temoins_source() -> None:
    orch = (AP / "orchestrator.py").read_text(encoding="utf-8")
    bkl = (AP / "lib" / "backlog.py").read_text(encoding="utf-8")
    gv = (AP / "lib" / "gate_verdict.py").read_text(encoding="utf-8")
    kv("src_marker_gate1_orch", 1 if MARKER_GATE1 in orch else 0)
    kv("src_marker_gate1_autorite", 1 if MARKER_GATE1 in gv else 0)
    kv("src_marker_promo_backlog", 1 if MARKER_PROMO in bkl else 0)
    kv("src_marker_promo_autorite", 1 if MARKER_PROMO in gv else 0)
    # UNE SEULE AUTORITE, LUE AUX DEUX ENDROITS : la porte de fermeture et le lancement.
    kv("src_gate1_lit_autorite", orch.count("gate_verdict.code_free_item("))
    kv("src_promotion_lit_verdict", bkl.count("_gate_verdict.validator_verdict("))
    kv("src_boucle_appelle_launch", orch.count("launch_item(bk, item)"))
    kv("src_promotion_dit_ses_refus", orch.count("machine_promotion_refused"))
    # 4. LE NOM ET CE QU'ELLE FAIT. Le nom RESTE ; c'est la fonction qui verifie ce qu'il promet.
    kv("nm_fonction_existe", 1 if "def machine_proved_to_validated(self):" in bkl else 0)
    kv("nm_decision", "le-nom-reste-la-fonction-verifie-ce-qu-il-promet")
    deb = bkl.find("def machine_proved_to_validated(self):")
    fin = bkl.find("def no_device_marker(self):", deb)
    corps = bkl[deb:fin] if 0 <= deb < fin else ""
    kv("nm_corps_lu", 1 if corps else 0)
    kv("nm_docstring_promet_la_porte", 1 if "porte tenue" in corps else 0)
    kv("nm_corps_appelle_le_plan", corps.count("self.machine_promotion_plan()"))
    kv("nm_corps_sans_garde_nue", 0 if "if not owner_test:" in corps else 1)
    # HORS PERIMETRE : le jeu n'est pas touche.
    r = subprocess.run(["git", "-C", str(REPO), "status", "--porcelain", "--",
                        "game/", "common/", "android/", "goal_src/", "goalc/"],
                       capture_output=True, text=True, timeout=120)
    sales = [x[3:] for x in r.stdout.splitlines() if x.strip()]
    kv("src_engine_dirty", len(sales))
    kv("src_engine_dirty_list", ",".join(sales[:12]) or "-")


# ======================================================= LE DEPOT, MAINTENANT ================
def depot_maintenant() -> None:
    """Le backlog LIVRE, relu par l'autorite : l'etalonnage du detecteur de perimetre.

    Publie, jamais compte : exiger un item mal etiquete pour fermer serait exiger une faute.
    Le denominateur publie a cote dit que quelque chose a bien ete regarde.
    """
    sys.path.insert(0, str(AP / "lib"))
    import gate_verdict as G
    import yaml
    try:
        items = (yaml.safe_load((AP / "backlog.yaml").read_text(encoding="utf-8"))
                 or {}).get("items") or []
    except Exception:                                                 # noqa: BLE001
        items = []
    c = G.code_free_census(items)
    kv("live_items", len(items))
    kv("live_exige_sans_code", len(c["exige"]))
    kv("live_exige_sans_drapeau", len(c["exige_sans_drapeau"]))
    kv("live_exige_sans_drapeau_liste", ",".join(c["exige_sans_drapeau"]) or "-")
    kv("live_drapeau_sans_raison", len(c["drapeau_sans_exigence"]))
    kv("live_drapeau_sans_raison_liste", ",".join(c["drapeau_sans_exigence"]) or "-")
    lignes, poses = G.launch_journal_counts(str(AP / "logs"))
    kv("live_journal_lancements", lignes)
    kv("live_journal_poses", poses)
    # Les `to-test` du depot et ce que la promotion machine en ferait AUJOURD'HUI.
    try:
        import backlog as BK
        bk = BK.load(str(AP / "backlog.yaml"))
        plan = bk.machine_promotion_plan()
        kv("live_parques", len(plan))
        kv("live_plan", ",".join("%s:%s:%d" % (e["id"], e["verdict"], e["promote"])
                                 for e in plan) or "-")
        kv("live_promouvables", sum(1 for e in plan if e["promote"]))
    except Exception as exc:                                          # noqa: BLE001
        kv("live_parques", -1)
        kv("live_plan", "exception:%s" % type(exc).__name__)
        kv("live_promouvables", -1)


# ===================================================================================== main =
def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="ccgf-banc-"))
    try:
        c_orch, b_orch = before_blob(".autoport/orchestrator.py", MARKER_GATE1)
        c_bk, b_bk = before_blob(".autoport/lib/backlog.py", MARKER_PROMO)
        kv("before_orch_commit", c_orch[:12] or "-")
        kv("before_backlog_commit", c_bk[:12] or "-")
        kv("before_orch_marker_absent", 1 if (b_orch and MARKER_GATE1 not in b_orch) else 0)
        kv("before_backlog_marker_absent", 1 if (b_bk and MARKER_PROMO not in b_bk) else 0)
        kv("before_orch_site_lancement",
           1 if (b_orch and SITE_LANCEMENT_AVANT in b_orch) else 0)
        kv("marker_gate1_live",
           1 if MARKER_GATE1 in (AP / "orchestrator.py").read_text(encoding="utf-8") else 0)
        kv("marker_promo_live",
           1 if MARKER_PROMO in (AP / "lib" / "backlog.py").read_text(encoding="utf-8") else 0)

        sys.path.insert(0, str(AP))
        sys.path.insert(0, str(AP / "lib"))

        vieux_orch = vieux_bk = None
        if b_orch:
            vieux_orch = root / "vieux_orchestrator.py"
            vieux_orch.write_text(b_orch, encoding="utf-8")
        if b_bk:
            vieux_bk = root / "vieux_backlog.py"
            vieux_bk.write_text(b_bk, encoding="utf-8")

        B_neuf = charger(AP / "lib" / "backlog.py", "bk_neuf_ccgf")
        B_vieux = charger(vieux_bk, "bk_vieux_ccgf") if vieux_bk else None
        O_neuf = charger(AP / "orchestrator.py", "orch_neuf_ccgf")
        O_vieux = charger(vieux_orch, "orch_vieux_ccgf") if vieux_orch else None
        O_neuf.log = lambda *a, **k: None
        if O_vieux:
            O_vieux.log = lambda *a, **k: None

        # 1. LE LANCEMENT, les deux bras.
        axe_lancement("lc_apres", root, O_neuf, B_neuf, True)
        if O_vieux:
            axe_lancement("lc_avant", root, O_vieux, B_neuf, False)

        # 2. LA PORTE, les deux bras, MEME depot jetable, MEMES items.
        depot = faux_depot(root)
        faux_ap = root / "faux-autoport"
        faux_ap.mkdir(parents=True, exist_ok=True)
        semer_backlog(faux_ap, _items_porte())
        axe_porte("lp_apres", root, O_neuf, depot, faux_ap)
        if O_vieux:
            axe_porte("lp_avant", root, O_vieux, depot, faux_ap)

        # 3. LA PROMOTION, les deux bras, MEME semis.
        axe_promotion("pm_apres", root, B_neuf, True)
        if B_vieux:
            axe_promotion("pm_avant", root, B_vieux, False)

        temoins_source()
        depot_maintenant()

        for rel in ("orchestrator.py", "lib/backlog.py", "lib/gate_verdict.py",
                    "lib/close_gate_code_free_selftest.py",
                    "lib/census/harness-close-gate-code-free.sh", "validators/generic.sh"):
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
