#!/usr/bin/env python3
"""lib/reload_survival_selftest.py — LE BANC de `harness-reload-must-not-kill-the-loop`.

CE QU'IL FAIT. Il rejoue la panne du 12/09 15:33 sur une COPIE JETABLE du harnais, dans les
deux bras, et il regarde qui MEURT.

  LE STIMULUS EST UN VRAI FICHIER INCOHERENT, jamais un drapeau. Deux stimuli, tous deux
  ecrits sur le disque de la copie entre deux tours, comme un worker qui sauvegarde :
    A. LA PANNE DU 12/09, A L'OCTET.  `lib/gate_verdict.py:345` est `PROOF_FILE =
       _noms.arm_name("proof", "")`. On y met le nom NEUF que `impossible` ne porte pas
       encore — exactement ce que le worker de `harness-naming-authority-completion` avait
       a l'ecran a 15:33. `AttributeError` a mi-corps du module.
    B. LE FICHIER A MOITIE ECRIT.  Le meme fichier TRONQUE au milieu d'une signature de
       fonction. `SyntaxError` : le corps ne s'execute pas du tout. Le banc VERIFIE que ce
       texte ne compile pas au lieu de le supposer.

  LES QUATRE JAMBES. {bras d'AVANT, bras d'APRES} x {sans stimulus, avec stimulus}.
    avant_nu    le code d'avant, rien de casse   -> il DOIT survivre. C'est le controle de
                causalite : sans lui, la mort du bras d'avant pourrait venir du bac a sable.
    avant_casse le code d'avant + les stimuli    -> il DOIT mourir, et c'est le DEFAUT mesure.
    apres_nu    le code du disque, rien de casse -> zero refus, zero mot a l'owner. OFF doit
                egaler l'ABSENCE : le filet ne doit rien inventer quand rien ne casse.
    apres_casse le code du disque + les stimuli  -> il DOIT survivre les cinq tours, refuser
                les rechargements, le DIRE a chaque tour, et REPASSER quand le fichier
                redevient coherent.

  LE BRAS D'AVANT EST ANCRE PAR MARQUEUR (`RECHARGEMENT/filet`), jamais par `HEAD:` : lu a
  HEAD, un temoin d'avant s'accuse lui-meme des le commit ou il nait. `lib/safe_reload.py` est
  ABSENT de ce bras — la couche n'est pas la, elle n'est pas juste desarmee. Les commits
  retenus sont publies.

  LA CINQUIEME MESURE, EN PROCESSUS, SANS BRAS : `importlib.reload` execute le code neuf DANS
  le `__dict__` du module existant. Un echec a mi-corps laisse donc un module MUTILE. Cette
  mesure compte les attributs PERDUS par un rechargement nu, puis par le filet : c'est ce qui
  distingue « garder le module » de « garder son NOM dans sys.modules ».

Sortie : des lignes `cle=valeur` sur stdout. Ce script ne juge rien et n'ecrit aucun champ de
proof.txt ; `lib/census/harness-reload-must-not-kill-the-loop.sh` fait la somme.
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parent.parent
REPO = AP.parent

MARQUEUR = "RECHARGEMENT/filet"          # date CE chantier dans orchestrator.py et lib/backlog.py

# LA LIGNE DE LA PANNE, mot pour mot. Si elle n'est plus dans le fichier, le stimulus serait une
# invention : le banc le DIT au lieu de fabriquer une panne qui n'a jamais eu lieu.
LIGNE_345 = 'PROOF_FILE = _noms.arm_name("proof", "")'
LIGNE_345_CASSEE = 'PROOF_FILE = _noms.arm_name_du_bras_livre("proof", "")'

TOURS = 7
LIMITE = 400


def kv(key, value):
    texte = str(value).replace("\n", " ")
    if len(texte) > LIMITE:
        texte = texte[:LIMITE] + "..TRONQUE(%d-octets)" % len(texte)
    print("%s=%s" % (key, texte))


def compte_reloads(source: str, motif: str) -> int:
    """Combien de fois `motif` apparait dans du CODE — jamais dans un commentaire.

    `lib/backlog.py` PARLE de `importlib.reload(backlog)` dans son en-tete pour expliquer
    pourquoi l'autorite voyage avec lui. Compter la prose ferait accuser une phrase."""
    n = 0
    for ligne in source.splitlines():
        code = ligne.split("#", 1)[0]
        if "`" in ligne:                      # une citation entre dos-de-guillemets : de la prose
            continue
        n += code.count(motif)
    return n


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


# ============================================================ les deux stimuli, sur le disque =
def stimulus_a(source: str) -> str:
    """LA PANNE DU 12/09 : l'autorite appelle un nom que `impossible` ne porte pas encore."""
    return source.replace(LIGNE_345, LIGNE_345_CASSEE, 1)


def stimulus_b(source: str) -> str:
    """LE FICHIER A MOITIE ECRIT : tronque au milieu de la derniere signature de fonction.

    Le meme geste sert pour `backlog.py`, `directives.py` et `preflight.py` : c'est ce que
    laisse un editeur interrompu, et ca ne compile pas — `SyntaxError`, le corps du module ne
    s'execute pas du tout, l'autre moitie des pannes possibles."""
    lignes = source.splitlines(True)
    candidats = [i for i, ln in enumerate(lignes)
                 if (ln.startswith("def ") or ln.startswith("    def ")) and "(" in ln]
    dernier = max(candidats)
    tete = "".join(lignes[:dernier])
    return tete + lignes[dernier].split("(")[0] + "(\n"


DRIVER = r'''
import json, os, sys, importlib, importlib.util
from pathlib import Path

S = Path(__file__).resolve().parent
sys.path.insert(0, str(S))                  # `from lib import ...` -> la COPIE, jamais le vrai
STIM = os.environ.get("BANC_STIM") == "1"

# LES FICHIERS QU'ON CASSE, ET LEUR VERSION SAINE MISE DE COTE PAR LE BANC.
CIBLES = {
    "gate_verdict": S / "lib" / "gate_verdict.py",
    "backlog": S / "lib" / "backlog.py",
    "directives": S / "lib" / "directives.py",
    "preflight": S / "lib" / "preflight.py",
}
SAIN = {k: (S / ("sain.%s.py" % k)).read_text() for k in CIBLES}
STIM_A = (S / "stim_a.gate_verdict.py").read_text()     # AttributeError a mi-corps (12/09)
STIM_B = {k: (S / ("stim_b.%s.py" % k)).read_text() for k in CIBLES}   # fichier TRONQUE

# LE CALENDRIER DES STIMULI, un tour par site. Chaque valeur est ce qu'on ECRIT sur le disque
# AVANT le tour ; tout ce qui n'est pas nomme est remis SAIN.
PLANS = {
    # LE CALENDRIER COMPLET : un site par tour, puis le retour au sain.
    "complet": {
        2: {"gate_verdict": STIM_A},                      # la panne du 12/09, a l'octet
        3: {"gate_verdict": STIM_B["gate_verdict"]},      # le meme fichier, a moitie ecrit
        4: {"backlog": STIM_B["backlog"]},                # le site qui a tue la boucle
        5: {"directives": STIM_B["directives"],
            "preflight": STIM_B["preflight"]},            # les deux sites du prompt
    },
    # LE BRAS D'AVANT MEURT AU PREMIER STIMULUS : pour eprouver un AUTRE site sur ce bras, il
    # faut que ce site soit le PREMIER a casser. D'ou ces deux calendriers a un seul site.
    "backlog": {2: {"backlog": STIM_B["backlog"]},
                3: {"backlog": STIM_B["backlog"]}},
    "prompt": {2: {"directives": STIM_B["directives"], "preflight": STIM_B["preflight"]},
               3: {"directives": STIM_B["directives"], "preflight": STIM_B["preflight"]}},
}
PLAN = PLANS[os.environ.get("BANC_PLAN") or "complet"]

spec = importlib.util.spec_from_file_location("orch_banc", str(S / "orchestrator.py"))
m = importlib.util.module_from_spec(spec)
sys.modules["orch_banc"] = m
spec.loader.exec_module(m)
m.log = lambda msg, style="": print("JOURNAL " + str(msg).replace("\n", " "), flush=True)

FILET = getattr(m, "safe_reload", None)
print("filet_present=%d" % int(FILET is not None), flush=True)

ITEM = {"id": "banc-en-cours", "prompt": "prompts/banc.md", "feature": "banc du filet",
        "effort": "medium", "max_retries": 5, "max_turns": 10, "no_code": True}


def autorite():
    """Le module d'autorite tel que la COPIE le tient, quel que soit son nom d'import."""
    return sys.modules.get("lib.gate_verdict") or sys.modules.get("gate_verdict")


releve = []
for t in range(1, __TOURS__ + 1):
    if STIM:
        pose = PLAN.get(t, {})
        for nom, chemin in CIBLES.items():
            chemin.write_text(pose.get(nom, SAIN[nom]))
        importlib.invalidate_caches()
    print("turn=%d" % t, flush=True)
    bk = m.load_backlog()                   # AUCUN try : c'est le geste qui a tue la boucle
    try:
        prompt = m.build_instructions(dict(ITEM), t)   # recharge `directives` et `preflight`
    except Exception as e:                  # noqa: BLE001 — le banc le DIT, il ne l'avale pas
        prompt = ""
        print("BUILD_INSTRUCTIONS_MORT %s: %s" % (type(e).__name__, e), flush=True)
    if FILET is not None:
        FILET.turn_report(m.log)
    gv = autorite()
    rep = bk.status_report()
    releve.append({
        "tour": t,
        "attrs": len([k for k in vars(gv) if not k.startswith("__")]) if gv else -1,
        "proof_file": getattr(gv, "PROOF_FILE", "-") if gv else "-",
        "owner": int("## Harnais degrade" in rep),
        "items": len(bk.items),
        "prompt": len(prompt),
    })
    print("turn_ok=%d owner_says_degraded=%d attrs=%d prompt=%d"
          % (t, releve[-1]["owner"], releve[-1]["attrs"], releve[-1]["prompt"]), flush=True)

print("RELEVE " + json.dumps(releve), flush=True)
if FILET is not None:
    print("COMPTEURS " + json.dumps(FILET.counters()), flush=True)
print("survived=1", flush=True)
'''.replace("__TOURS__", str(TOURS))


def bac(arm: str, blobs: dict) -> Path:
    """UNE COPIE JETABLE du harnais. Le bac s'appelle `.autoport` : `orchestrator.py` calcule
    `AUTOPORT_DIR` depuis SON propre chemin, et un bac nomme autrement le ferait lire le VRAI
    depot — un test qui promet l'isolation et rend le vrai backlog."""
    racine = Path(tempfile.mkdtemp(prefix="banc-reload-%s-" % arm))
    S = racine / ".autoport"
    (S / "lib").mkdir(parents=True)
    for f in sorted((AP / "lib").glob("*.py")):
        shutil.copy2(f, S / "lib" / f.name)
    shutil.copy2(AP / "orchestrator.py", S / "orchestrator.py")
    for d in ("logs", "reports", "prompts", "validators"):
        (S / d).mkdir(exist_ok=True)
    for rel, blob in blobs.items():
        chemin = S / rel
        if blob is None:
            chemin.unlink(missing_ok=True)
        else:
            chemin.write_text(blob, encoding="utf-8")
    import yaml
    (S / "backlog.yaml").write_text(yaml.safe_dump({"version": 1, "items": [
        {"id": "banc-en-cours", "status": "in-progress", "feature": "banc du filet",
         "priority": 1, "owner_test": False},
        {"id": "banc-a-tester", "status": "to-test", "feature": "quelque chose a regarder",
         "priority": 2, "owner_test": True, "delivered": "2026-09-12",
         "where": "nulle part"},
    ]}, allow_unicode=True, sort_keys=False), encoding="utf-8")
    (S / "prompts" / "banc.md").write_text("consigne du banc\n", encoding="utf-8")
    # LES VERSIONS SAINES ET LES STIMULI, mis de cote HORS de `lib/` : le pilote les recopie
    # sur le disque entre deux tours, comme un worker qui sauvegarde. Les versions saines
    # viennent du bac — donc du BLOB DU BRAS pour `backlog.py` —, jamais du vrai depot : sinon
    # le bras d'AVANT se verrait rendre le code d'APRES au premier tour.
    for nom, rel in (("gate_verdict", "lib/gate_verdict.py"), ("backlog", "lib/backlog.py"),
                     ("directives", "lib/directives.py"), ("preflight", "lib/preflight.py")):
        source = (S / rel).read_text()
        (S / ("sain.%s.py" % nom)).write_text(source, encoding="utf-8")
        (S / ("stim_b.%s.py" % nom)).write_text(stimulus_b(source), encoding="utf-8")
    (S / "stim_a.gate_verdict.py").write_text(
        stimulus_a((S / "lib" / "gate_verdict.py").read_text()), encoding="utf-8")
    (S / "driver.py").write_text(DRIVER, encoding="utf-8")
    return S


def jambe(nom: str, S: Path, stim: bool, plan: str = "complet") -> dict:
    env = dict(os.environ)
    env["BANC_STIM"] = "1" if stim else "0"
    env["BANC_PLAN"] = plan
    env["PYTHONPATH"] = str(S)
    env.pop("PYTHONDONTWRITEBYTECODE", None)
    try:
        out = subprocess.run([sys.executable, str(S / "driver.py")], capture_output=True,
                             text=True, timeout=300, env=env, cwd=str(S))
        rc, texte = out.returncode, (out.stdout or "") + "\n" + (out.stderr or "")
    except subprocess.SubprocessError as e:
        rc, texte = -99, str(e)
    releve = []
    compteurs = {}
    for ligne in texte.splitlines():
        if ligne.startswith("RELEVE "):
            releve = json.loads(ligne[7:])
        elif ligne.startswith("COMPTEURS "):
            compteurs = json.loads(ligne[10:])
    tours_ok = len(releve)
    lances = len(re.findall(r"^turn=\d+$", texte, re.M))
    return {
        "nom": nom, "rc": rc,
        "survecu": int("survived=1" in texte),
        "filet": int("filet_present=1" in texte),
        "tours_lances": lances,
        "tours_aboutis": tours_ok,
        "mort_au_tour": 0 if tours_ok == lances else lances,
        "refus": len(re.findall(r"rechargement REFUSE \[", texte)),
        "refus_sites": ",".join(sorted(set(re.findall(r"rechargement REFUSE \[([a-z:_]+)\]",
                                                      texte)))) or "-",
        "journal_tours": len(re.findall(r"HARNAIS DEGRADE", texte)),
        "reprises": len(re.findall(r"repasse apres \d+ refus", texte)),
        "owner_tours": sum(r["owner"] for r in releve),
        "owner_par_tour": ",".join(str(r["owner"]) for r in releve) or "-",
        "prompt_par_tour": ",".join(str(r["prompt"]) for r in releve) or "-",
        "build_instructions_morts": len(re.findall(r"BUILD_INSTRUCTIONS_MORT", texte)),
        "directives_indispo": len(re.findall(r"bloc directives indisponible", texte)),
        "preflight_indispo": len(re.findall(r"preflight indisponible", texte)),
        "attrs_par_tour": ",".join(str(r["attrs"]) for r in releve) or "-",
        "proof_file_par_tour": ",".join(str(r["proof_file"]) for r in releve) or "-",
        "items_par_tour": ",".join(str(r["items"]) for r in releve) or "-",
        "exc": (re.findall(r"^(\w*Error): .*$", texte, re.M) or ["-"])[-1],
        "compteurs": compteurs,
        "queue": texte.strip().splitlines()[-1][:200] if texte.strip() else "-",
    }


def publier(j: dict) -> None:
    n = j["nom"]
    for cle in ("rc", "survecu", "filet", "tours_lances", "tours_aboutis", "mort_au_tour",
                "refus", "refus_sites", "journal_tours", "reprises", "owner_tours",
                "owner_par_tour", "attrs_par_tour", "proof_file_par_tour", "items_par_tour",
                "prompt_par_tour", "build_instructions_morts", "directives_indispo",
                "preflight_indispo", "exc", "queue"):
        kv("%s_%s" % (n, cle), j[cle])
    c = j.get("compteurs") or {}
    kv("%s_compteur_refus" % n, c.get("refused", -1))
    kv("%s_compteur_tours" % n, c.get("turns_continued", -1))
    kv("%s_compteur_sites" % n, c.get("degraded_sites", -1))


# ================================================== la mesure du `__dict__` mutile, en direct =
def mesure_photo() -> None:
    """UN RECHARGEMENT NU LAISSE UN MODULE MUTILE — combien d'attributs PERDUS, mesure.

    C'est la difference entre garder le module et garder son NOM. Sans cette mesure, la
    restitution du `__dict__` serait une precaution dont personne ne connait l'effet.

    Le cobaye est IMPORTE PAR LE CHEMIN, pas fabrique par `spec_from_file_location` : un module
    hors `sys.path` n'a plus de spec trouvable et `importlib.reload` y meurt en
    `ModuleNotFoundError` — on mesurerait alors la faute du banc, pas celle du rechargement."""
    import importlib as _il
    racine = Path(tempfile.mkdtemp(prefix="banc-photo-"))
    src = racine / "cobaye_banc.py"
    SAIN = "A = 1\nB = 2\nC = 3\nD = 4\n"
    CASSE = ("A = 99\nraise AttributeError(\"module 'impossible' has no attribute "
             "'arm_name_du_bras_livre'\")\nB = 2\nC = 3\nD = 4\n")

    def ecrire(texte):
        src.write_text(texte, encoding="utf-8")
        _il.invalidate_caches()

    sys.path.insert(0, str(racine))
    sys.dont_write_bytecode = True
    ecrire(SAIN)
    mod = _il.import_module("cobaye_banc")
    avant = sorted(k for k in vars(mod) if not k.startswith("__"))
    kv("photo_attrs_avant", len(avant))

    # LE RECHARGEMENT NU. Le fichier pose A, puis il explose AVANT B, C et D : le code neuf
    # s'execute DANS le `__dict__` du module existant, et personne ne peut plus le restituer.
    ecrire(CASSE)
    nu_exc = "-"
    try:
        _il.reload(mod)
    except Exception as e:                   # noqa: BLE001 — le rechargement NU, sans filet
        nu_exc = type(e).__name__
    nu = sorted(k for k in vars(mod) if not k.startswith("__"))
    kv("photo_nu_exc", nu_exc)
    kv("photo_nu_attrs", len(nu))
    kv("photo_nu_perdus", len(set(avant) - set(nu)))
    kv("photo_nu_A", getattr(mod, "A", -1))
    kv("photo_nu_dans_sys_modules", int(sys.modules.get("cobaye_banc") is mod))

    # LE MEME FICHIER CASSE, REPASSE PAR LE FILET : rien ne doit avoir bouge.
    ecrire(SAIN)
    _il.reload(mod)                          # on repart d'un module sain
    sys.path.insert(0, str(AP / "lib"))
    import safe_reload as filet
    # LE BANC N'ECRIT PAS DANS L'ETAT DE PRODUCTION. Sans cette ligne, mesurer le filet POSAIT
    # un site degrade dans `.autoport/.last_reload_degraded.json`, et le prochain
    # `status_report()` aurait annonce a l'owner un harnais degrade par un banc d'essai. On le
    # rend impossible AU POINT DE PRODUCTION, pas detectable au point de controle.
    prod = Path(filet.STATE_PATH)
    avant_prod = prod.read_bytes() if prod.exists() else b""
    filet.STATE_PATH = str(racine / "etat-du-banc.json")
    ecrire(CASSE)
    rendu = filet.reload(mod, "banc:cobaye", log=lambda *a, **k: None)
    filet_attrs = sorted(k for k in vars(mod) if not k.startswith("__"))
    kv("photo_filet_rendu", int(rendu))
    kv("photo_filet_attrs", len(filet_attrs))
    kv("photo_filet_perdus", len(set(avant) - set(filet_attrs)))
    kv("photo_filet_A", getattr(mod, "A", -1))
    kv("photo_filet_dans_sys_modules", int(sys.modules.get("cobaye_banc") is mod))
    # ET IL REPASSE QUAND LE FICHIER REDEVIENT COHERENT : le filet ne gele pas le module.
    ecrire(SAIN)
    kv("photo_filet_reprise", int(filet.reload(mod, "banc:cobaye", log=lambda *a, **k: None)))
    kv("photo_filet_degrade_final", len(filet.degraded()))
    kv("photo_etat_du_banc_ecrit", int(Path(filet.STATE_PATH).exists()))
    kv("photo_etat_production_intact",
       int((prod.read_bytes() if prod.exists() else b"") == avant_prod))
    sys.modules.pop("cobaye_banc", None)
    shutil.rmtree(racine, ignore_errors=True)


def main() -> int:
    kv("banc_ran", 1)

    # --------------------------------------------------- le code d'AVANT, ancre par MARQUEUR
    c_orch, b_orch = before_blob(".autoport/orchestrator.py", MARQUEUR)
    c_bk, b_bk = before_blob(".autoport/lib/backlog.py", MARQUEUR)
    kv("avant_orch_commit", c_orch or "-")
    kv("avant_backlog_commit", c_bk or "-")
    kv("avant_orch_a_le_filet", int(MARQUEUR in (b_orch or "")))
    kv("avant_backlog_a_le_filet", int(MARQUEUR in (b_bk or "")))
    # LA COUCHE EST ABSENTE DU BRAS D'AVANT, pas desarmee : `safe_reload.py` n'existait pas.
    kv("avant_filet_fichier_absent", 1)
    vivant_orch = (AP / "orchestrator.py").read_text()
    vivant_bk = (AP / "lib" / "backlog.py").read_text()
    kv("vivant_orch_a_le_filet", int(MARQUEUR in vivant_orch))
    kv("vivant_backlog_a_le_filet", int(MARQUEUR in vivant_bk))

    # ------------------- AUCUN RECHARGEMENT N'A ETE RETIRE : on les protege, on ne les supprime
    # pas. Le compte d'AVANT (rechargements NUS) doit egaler le compte d'APRES (sites du filet),
    # et il ne doit plus rester un seul rechargement nu dans le code de production.
    kv("avant_orch_reloads", compte_reloads(b_orch or "", "importlib.reload("))
    kv("avant_backlog_reloads", compte_reloads(b_bk or "", "importlib.reload("))
    kv("vivant_orch_reloads_bruts", compte_reloads(vivant_orch, "importlib.reload("))
    kv("vivant_backlog_reloads_bruts", compte_reloads(vivant_bk, "importlib.reload("))
    kv("vivant_orch_sites_filet", compte_reloads(vivant_orch, "safe_reload.reload("))
    kv("vivant_backlog_sites_filet", compte_reloads(vivant_bk, "_safe_reload.reload("))
    kv("vivant_orch_battement", compte_reloads(vivant_orch, "safe_reload.turn_report("))
    kv("vivant_backlog_texte_owner", compte_reloads(vivant_bk, "_safe_reload.owner_block("))

    # ------------------------------------------------- le stimulus est VERIFIE, pas suppose
    sain = (AP / "lib" / "gate_verdict.py").read_text()
    kv("stimulus_ligne_345_presente", int(LIGNE_345 in sain))
    a = stimulus_a(sain)
    b = stimulus_b(sain)
    kv("stimulus_a_change_le_fichier", int(a != sain))
    kv("stimulus_a_octets_delta", len(a) - len(sain))
    try:
        compile(a, "a", "exec")
        a_compile = 1
    except SyntaxError:
        a_compile = 0
    try:
        compile(b, "b", "exec")
        b_compile = 1
    except SyntaxError:
        b_compile = 0
    kv("stimulus_a_compile", a_compile)          # A compile : il explose a l'EXECUTION
    kv("stimulus_b_compile", b_compile)          # B ne compile pas : SyntaxError
    kv("stimulus_b_octets", len(b))
    kv("stimulus_b_octets_sain", len(sain))

    if not (c_orch and c_bk):
        kv("banc_bras_avant_introuvable", 1)
        return 1
    kv("banc_bras_avant_introuvable", 0)

    avant = {"orchestrator.py": b_orch, "lib/backlog.py": b_bk, "lib/safe_reload.py": None}
    apres: dict = {}
    # LES SIX JAMBES. `avant_casse_backlog` et `avant_casse_prompt` existent parce que le bras
    # d'AVANT MEURT au premier stimulus : sans un calendrier par site, `orchestrator:backlog`,
    # `orchestrator:directives` et `orchestrator:preflight` ne seraient jamais eprouves de ce
    # cote-la, et la porte se contenterait de la survie d'UN site.
    for nom, blobs, stim, plan in (
            ("avant_nu", avant, False, "complet"),
            ("avant_casse", avant, True, "complet"),
            ("avant_casse_backlog", avant, True, "backlog"),
            ("avant_casse_prompt", avant, True, "prompt"),
            ("apres_nu", apres, False, "complet"),
            ("apres_casse", apres, True, "complet")):
        S = bac(nom, blobs)
        try:
            publier(jambe(nom, S, stim, plan))
        finally:
            shutil.rmtree(S.parent, ignore_errors=True)

    mesure_photo()

    # ------------------------------------------------- les sites couverts, lus dans le SOURCE
    sys.path.insert(0, str(AP / "lib"))
    import safe_reload as filet
    kv("sites_declares", ",".join(filet.SITES))
    kv("sites_declares_n", len(filet.SITES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
