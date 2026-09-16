#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""lib/judge_measure_selftest.py — LE BANC DE `harness-judge-runs-the-proof-when-the-worker-left-none`.

CE QU'IL MESURE. Sur les 339 verdicts rendus par `validators/generic.sh` et archives sous
`logs/<id>/validator-*.txt`, 186 sont des refus, et 87 d'entre eux ont pour PREMIER constat une
preuve ABSENTE, PERIMEE, ou portant l'identite d'un AUTRE essai. Aucun de ces 87 ne decrit un
defaut du travail juge : le worker n'a pas laisse de mesure NEUVE. Le juge refusait la vieille
preuve, et l'essai etait COMPTE.

ONZE JAMBES, DE VRAIS PROCESSUS, DE VRAIS DEPOTS. Chaque jambe monte un depot jetable — un `git
init`, les fichiers que `lib/verdict_sources.sh` DECLARE lui-meme, un faux `gk`, un faux
`proof_run.sh` qui prend le verrou d'ecriture, dort, ecrit (ou pas) et sort avec le code qu'on
lui demande. La boucle du banc porte, TEL QUEL, le bloc de decision leve de `orchestrator.py`
entre `# JUGEMENT/debut` et `# JUGEMENT/fin` :

  * bras d'APRES = ce bloc entier ;
  * bras d'AVANT = le MEME bloc prive de sa region `# MESURE-DU-JUGE/`, c'est-a-dire le code qui
                   tournait le 16/09. La couche n'est pas desarmee : elle est ABSENTE.

Le banc REFUSE de tourner si un marqueur manque ou si la region d'avant nomme encore la couche :
un bras d'ablation qui contient ce qu'il ablate mesure zero et ne le dit pas.

LA JAMBE DE CONTROLE COMPTE AUTANT QUE LES AUTRES. Une couche qui mesurerait a CHAQUE essai
serait verte sur toutes les jambes de declenchement et couterait une course par essai. La jambe
`neuve` pose une preuve qui EST celle de l'essai : le juge ne doit RIEN lancer, et le faux
`proof_run.sh` ne doit pas avoir ete appele une seule fois.

CE QU'IL NE FAIT PAS. Il ne lance JAMAIS le vrai `lib/proof_run.sh` : `AUTOPORT_DIR` et
`REPO_ROOT` du module sont deplaces sur le depot jetable le temps de chaque jambe, et le banc
PUBLIE le temoin qui le prouve (`banc_vraie_course_lancee`). Il n'ecrit ni dans `reports/`, ni
dans `logs/`, ni dans `state.json` — `save_state` est remplace par un compteur. Il ne tue que
des PID qu'il a lui-meme crees (DIRECTIVES : PID exacts, jamais de motif).

SORTIE : des lignes `cle=valeur` sans espace, lues par
`lib/census/harness-judge-runs-the-proof-when-the-worker-left-none.sh`. Une cle absente vaut -1
cote recensement, jamais 0 : un zero passerait une porte `== 0`.
"""
from __future__ import annotations

import ast
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

AP = Path(__file__).resolve().parent.parent
ROOT = AP.parent
sys.path.insert(0, str(AP))
import orchestrator as orch              # noqa: E402 — le chemin doit preceder l'import

SRC = (AP / "orchestrator.py").read_text(encoding="utf-8")
GEN = (AP / "validators" / "generic.sh").read_text(encoding="utf-8")
SORTIE: dict[str, object] = {}
# UN ID D'ITEM UNIQUE PAR INVOCATION, ET C'EST UNE MESURE, PAS UNE PRECAUTION. Le 16/09 une
# course du banc coupee en plein vol (un `| head` qui ferme le tube, SIGPIPE) a laisse deux faux
# `proof_run.sh` orphelins portant l'id FIXE du bac a sable. La course SUIVANTE les a vus — a
# juste titre : `inflight_proof_run` fait son travail — et huit jambes sur dix ont refuse de
# mesurer pour une course qui appartenait a un banc mort. Un id unique rend la collision
# impossible AU POINT DE PRODUCTION, au lieu de la detecter au point de controle.
ITEM = f"sandbox-judge-measure-{os.getpid()}"

# LE JOURNAL QUE L'ORCHESTRATEUR TIENT, CAPTE. Sa sortie riche polluerait les lignes
# `cle=valeur`, et surtout le contrat demande que le journal DISE qui a mesure : le publier,
# c'est prouver que la ligne existe, pas jurer qu'on l'a ecrite.
JOURNAL: list[str] = []
orch.log = lambda msg, *a, **k: JOURNAL.append(str(msg))


class BancCasse(RuntimeError):
    """Le banc ne peut pas mesurer. Ce n'est pas un verdict, c'est une panne d'instrument."""


def pub(cle: str, val) -> None:
    if isinstance(val, float):
        val = round(val, 1)
    SORTIE[cle] = val


# ============================================================ LE CODE DE PRODUCTION, LEVE ====
def region(marque: str, texte: str = SRC) -> tuple[int, int, list[str]]:
    """(premiere ligne, derniere ligne, contenu) de la region `<marque>/debut .. /fin`.

    LE MARQUEUR EST CHERCHE DANS LA LIGNE, pas en tete : celui de `validators/generic.sh` est
    encadre de `=` sur toute la largeur, et un `startswith` ne le voyait pas — le banc rendait
    alors « region introuvable » sur un fichier qui la PORTE.

    ANCRE SUR UN MARQUEUR, JAMAIS SUR `HEAD:`. Un temoin d'AVANT lu a `git show HEAD:` s'accuse
    lui-meme des le commit : il devient le code d'apres sans que rien ne le dise."""
    lignes = texte.splitlines()
    d = [n for n, l in enumerate(lignes) if f"{marque}/debut" in l]
    f = [n for n, l in enumerate(lignes) if f"{marque}/fin" in l]
    if len(d) != 1 or len(f) != 1 or f[0] <= d[0] + 1:
        raise BancCasse(f"marqueur {marque} : {len(d)} debut, {len(f)} fin — region introuvable")
    return d[0], f[0], lignes[d[0] + 1:f[0]]


def reindente(lignes: list[str], vers: int) -> list[str]:
    marge = min((len(l) - len(l.lstrip()) for l in lignes if l.strip()), default=0)
    return [(" " * vers + l[marge:]) if l.strip() else "" for l in lignes]


def code_nu(lignes: list[str]) -> list[str]:
    """Le code, sans les commentaires ni l'indentation : deux blocs identiques doivent l'etre
    meme si l'un est indente de vingt colonnes et l'autre de quatre."""
    return [l.strip() for l in lignes if l.strip() and not l.strip().startswith("#")]


BORNES: tuple[int, int] = (0, 0)
BLOC_APRES: list[str] = []
BLOC_AVANT: list[str] = []


def decoupe() -> None:
    """Les deux bras, leves du fichier de production. UN COMMENTAIRE N'EST PAS DU CODE : la
    prose du bloc NOMME la couche et le banc — c'est son role — et la juger reviendrait a
    refuser l'ablation a cause de sa propre explication."""
    global BLOC_APRES, BLOC_AVANT, BORNES
    d_jug, f_jug, BLOC_APRES = region("JUGEMENT")
    BORNES = (d_jug + 1, f_jug + 1)           # en numeros de ligne, comme l'AST les compte
    d_mes, f_mes, _ = region("MESURE-DU-JUGE")
    if not (d_jug < d_mes and f_mes < f_jug):
        raise BancCasse("la region MESURE-DU-JUGE n'est pas DANS la region JUGEMENT")
    BLOC_AVANT = BLOC_APRES[:d_mes - (d_jug + 1)] + BLOC_APRES[f_mes - (d_jug + 1) + 1:]

    avant = "\n".join(code_nu(BLOC_AVANT))
    apres = "\n".join(code_nu(BLOC_APRES))
    pub("bloc_apres_lignes", len(BLOC_APRES))
    pub("bloc_avant_lignes", len(BLOC_AVANT))
    pub("bloc_apres_nomme_la_couche",
        int("judge_measure" in apres and "proof_freshness" in apres))
    pub("bloc_avant_nomme_la_couche",
        int("judge_measure" in avant or "proof_freshness" in avant or "judge" in avant))
    # LES DEUX BRAS JUGENT ET COMPTENT : ce qui differe est la MESURE, pas le jugement.
    pub("bloc_avant_juge", int("GENERIC_VALIDATOR" in avant))
    pub("bloc_apres_juge", int("GENERIC_VALIDATOR" in apres))
    pub("bloc_avant_compte", int('state["retries"][iid]' in avant))
    pub("bloc_apres_compte", int('state["retries"][iid]' in apres))
    if SORTIE["bloc_avant_nomme_la_couche"]:
        raise BancCasse("le bras d-AVANT nomme encore la couche : l-ablation serait vide")
    if not SORTIE["bloc_apres_nomme_la_couche"]:
        raise BancCasse("le bras d-APRES ne nomme pas la couche : marqueur au mauvais endroit")
    if not SORTIE["bloc_avant_juge"] or not SORTIE["bloc_avant_compte"]:
        raise BancCasse("le bras d-AVANT ne juge plus ou ne compte plus : ce n-est pas le "
                        "code du 16/09, et les deux verdicts ne seraient pas comparables")


GABARIT = r'''
def jugement(ctx):
    iid = ctx["iid"]; item = ctx["item"]; state = ctx["state"]; seq = ctx["seq"]
    rc = ctx["rc"]; started_at = ctx["started_at"]; attempt_token = ctx["attempt_token"]
    log = ctx["log"]; save_state = ctx["save_state"]; BACKEND = ctx["BACKEND"]
    validator_log = ctx["validator_log"]; attempt_log = ctx["attempt_log"]
    log_dir = ctx["log_dir"]; GENERIC_VALIDATOR = ctx["GENERIC_VALIDATOR"]
    REPO_ROOT = ctx["REPO_ROOT"]
    wait_for_proof_writer = ctx["wait_for_proof_writer"]
    proof_freshness = ctx["proof_freshness"]; judge_measure = ctx["judge_measure"]
    _aborted_record = ctx["_aborted_record"]
    v = None; judge = None
{BLOC}
    ctx["v"] = v
    ctx["judge"] = judge
    return ctx
'''


def compile_bloc(bloc: list[str]):
    source = GABARIT.replace("{BLOC}", "\n".join(reindente(bloc, 4)))
    espace: dict = {"os": os, "json": json, "subprocess": subprocess, "time": time,
                    "Path": Path, "datetime": orch.datetime, "timezone": orch.timezone}
    exec(compile(source, "<jugement-du-banc>", "exec"), espace)   # noqa: S102 — c'est le sujet
    return espace["jugement"], source


BRAS: dict = {}


# =============================================================== LE DEPOT JETABLE, ET SES FAUX
FAUX_RUN = r'''#!/usr/bin/env bash
# faux proof_run.sh du banc. Il imite ce que le vrai fait AVANT tout : prendre le verrou
# d'ecriture (pour que le juge le VOIE vivant), puis dormir, puis ecrire — ou pas.
set -uo pipefail
ID="${1:-}"; MODE="${2:-x86}"
D="$(dirname "$0")/../reports/$ID"
mkdir -p "$D"
echo "$$ $ID $MODE $(date +%s)" >> "$D/faux-run-appels.txt"
printf 'pid=%s\nat=%s\nitem=%s\narm=livre\n' "$$" "$(date -Is)" "$ID" > "$D/proof-writer.lock"
nettoie(){ rm -f "$D/proof-writer.lock"; }
trap nettoie EXIT
sleep "__DORT__"
if [ "__ECRIT__" = 1 ]; then
  {
    echo "source=x86"
    echo "binary=build/game/gk"
    echo "sha=__SHA__"
    echo "crash=0"
    echo "frames=1800"
    echo "proof_attempt_id=$(printf '%s' "${AUTOPORT_ATTEMPT_ID:--}" | tr -s '[:space:]' '_')"
  } > "$D/proof.txt"
fi
exit __RC__
'''


def faux_run(sb: Path, rc: int = 0, dort: float = 0.0, ecrit: int = 1, sha: str = "") -> None:
    """Poser le faux `proof_run.sh` du depot jetable, regle pour cette jambe."""
    texte = (FAUX_RUN.replace("__RC__", str(rc)).replace("__DORT__", str(dort))
             .replace("__ECRIT__", str(ecrit)).replace("__SHA__", sha or "0" * 16))
    cible = sb / ".autoport" / "lib" / "proof_run.sh"
    cible.write_text(texte, encoding="utf-8")
    cible.chmod(0o755)


def sha_du_gk(sb: Path) -> str:
    import hashlib
    with open(sb / "build" / "game" / "gk", "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()[:16]


def monte(nom: str) -> Path:
    """Un depot jetable que le juge peut lire : les fichiers que `verdict_sources.sh` DECLARE
    lui-meme, plus ceux que la couche APPELLE. Un bac a sable qui ne copie pas ce que le juge
    importe rend rc=1 partout, controle positif compris — et ce n'est pas un defaut, c'est un
    banc casse."""
    sb = Path(tempfile.mkdtemp(prefix=f"judgemeasure-{nom}-"))
    for d in (".autoport/lib", ".autoport/reports/" + ITEM, ".autoport/logs/" + ITEM,
              ".autoport/validators", "build/game", "game", "common", "android", "goal_src"):
        (sb / d).mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q"], cwd=sb, capture_output=True)   # git-sandbox-ok
    (sb / "build" / "game" / "gk").write_text("faux gk du banc de la mesure du juge\n")
    (sb / "game" / "sonde_origine.cpp").write_text("// source moteur du depot jetable\n")
    (sb / ".autoport" / "backlog.yaml").write_text(
        "version: 1\nitems:\n"
        f"  - id: {ITEM}\n"
        '    feature: "banc de la mesure lancee par le juge"\n'
        "    device: false\n"
        "    proof_timeout: 30\n"
        '    gate: {key: stale_proof_verdicts, op: "==", value: 0}\n', encoding="utf-8")
    liste = subprocess.run(["bash", str(AP / "lib" / "verdict_sources.sh"), ITEM, "list"],
                           cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
    for rel in [l.strip() for l in liste if l.strip()]:
        src = ROOT / rel
        if not src.is_file():
            continue
        (sb / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, sb / rel)
    # CE QUE LA COUCHE APPELLE, en plus de ce que le verdict declare.
    for rel in ("lib/impossible.py", "lib/stale_precheck.sh", "lib/proof_impossible.sh",
                "lib/verdict_sources.sh", "lib/freshness.py", "lib/backlog.py",
                "validators/generic.sh"):
        src = AP / rel
        if src.is_file():
            (sb / ".autoport" / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, sb / ".autoport" / rel)
    faux_run(sb, sha=sha_du_gk(sb))
    return sb


# ============================================================= LE JUGE DU BAC A SABLE =========
# LES DEUX REGLES QUE LE VRAI JUGE APPLIQUERAIT ICI, LEVEES DE SON TEXTE. On ne les recopie pas :
# une recopie mesurerait la recopie. La presence vient de son test `[ ! -s "$PF" ]`, l'identite
# de son bloc `IDENTITE-DE-LA-COURSE`, pris entre ses marqueurs — le meme geste que
# `lib/proof_writer_selftest.sh` fait depuis le 12/09.
def faux_juge(sb: Path) -> Path:
    _, _, ident = region("IDENTITE-DE-LA-COURSE", GEN)
    corps = "\n".join(l for l in ident if l.strip())
    pub("juge_bloc_identite_lignes", len([l for l in ident if l.strip()]))
    pub("juge_bloc_identite_octets", len(corps))
    script = (
        '#!/usr/bin/env bash\n'
        'set -uo pipefail\n'
        'P="${AUTOPORT_PHASE_ID:?}"; D="$(dirname "$0")/../reports/$P"; N=0\n'
        'bad(){ echo "[$P FAIL] $*" >&2; N=$((N+1)); }\n'
        'PF="$D/proof.txt"\n'
        'kv(){ sed -n "s/^$1=//p" "$PF" 2>/dev/null | tail -1; }\n'
        'if [ ! -s "$PF" ]; then\n'
        '  bad "proof.txt absent ou vide."\n'
        'else\n'
        f'{corps}\n'
        'fi\n'
        '[ "$N" = 0 ] || { echo "[$P FAIL] $N constat(s)" >&2; exit 1; }\n'
        'echo "[$P ok] proof_attempt_id=$(kv proof_attempt_id)"\n')
    cible = sb / ".autoport" / "validators" / "faux-juge.sh"
    cible.write_text(script, encoding="utf-8")
    cible.chmod(0o755)
    return cible


# ====================================================================== UNE JAMBE ==============
def jambe(nom: str, bras: str = "apres", *, preuve: str | None = None,
          timeout_item: int = 30,
          vieille: bool = False, jeton_autre: bool = False, source_tardive: bool = False,
          rc_run: int = 0, dort: float = 0.0, ecrit: int = 1,
          plafond: tuple[float, float] | None = None,
          course_vivante: bool = False, deux_fois: bool = False,
          panne_couche: bool = False) -> dict:
    """Monter un depot, poser la preuve demandee, faire tourner le bloc, publier ce qu'on voit."""
    prefixe = f"{nom}_"
    sb = monte(nom)
    rapport: dict = {}
    vieux_ap, vieux_root = orch.AUTOPORT_DIR, orch.REPO_ROOT
    vieux_cens, vieux_boot = orch.JUDGE_CENSUS_CEILING_SEC, orch.JUDGE_BOOT_GRACE_SEC
    appels_avant = 0
    try:
        # LE MODULE REGARDE LE DEPOT JETABLE, ET LUI SEUL : c'est ce qui garantit qu'aucune
        # VRAIE course ne peut partir d'ici.
        orch.AUTOPORT_DIR = sb / ".autoport"
        orch.REPO_ROOT = sb
        if plafond:
            orch.JUDGE_CENSUS_CEILING_SEC, orch.JUDGE_BOOT_GRACE_SEC = plafond
        item = {"id": ITEM, "device": False, "proof_timeout": timeout_item}
        depart = time.time()
        jeton = f"{ITEM}@7#{int(depart)}"
        rep = sb / ".autoport" / "reports" / ITEM
        faux_run(sb, rc=rc_run, dort=dort, ecrit=ecrit, sha=sha_du_gk(sb))

        # ---- la preuve que le worker a (ou n'a pas) laissee -------------------------------
        if preuve is not None:
            porte = f"{ITEM}@6#{int(depart) - 900}" if jeton_autre else jeton
            (rep / "proof.txt").write_text(
                "source=x86\nbinary=build/game/gk\n"
                f"sha={sha_du_gk(sb)}\ncrash=0\nframes=1800\n"
                f"proof_attempt_id={porte}\n", encoding="utf-8")
            if vieille:
                vieux = depart - 600
                os.utime(rep / "proof.txt", (vieux, vieux))
            if source_tardive:
                time.sleep(0.3)   # l'horloge d'inode avance par tics : sans ca, `-nt` est faux
                (sb / "game" / "sonde_tardive.cpp").write_text("// editee APRES la preuve\n")
        # LE HANDOFF DU WORKER, SEME AVANT LE BLOC. Le contrat exige qu'une mesure lancee par
        # le juge ne l'ecrase pas : on le relit octet a octet apres le passage du bloc.
        handoff = rep / "handoff.md"
        handoff.write_text("ce que le worker a laisse pour l'essai suivant\n", encoding="utf-8")
        handoff_avant = handoff.read_bytes()
        appels = rep / "faux-run-appels.txt"
        appels_avant = len(appels.read_text().splitlines()) if appels.exists() else 0

        # ---- une course DEJA vivante, que le juge ne doit pas doubler ---------------------
        vivant = None
        if course_vivante:
            faux_run(sb, rc=0, dort=25, ecrit=1, sha=sha_du_gk(sb))
            vivant = subprocess.Popen(
                ["bash", str(sb / ".autoport" / "lib" / "proof_run.sh"), ITEM, "x86"],
                cwd=sb, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True)
            for _ in range(60):          # attendre qu'elle ait PRIS son verrou
                if (rep / "proof-writer.lock").exists():
                    break
                time.sleep(0.05)
            appels_avant = len(appels.read_text().splitlines()) if appels.exists() else 0

        # ---- le contexte du bloc ---------------------------------------------------------
        etat: dict = {"retries": {ITEM: 3}}
        sauvegardes = [0]
        log_dir = sb / ".autoport" / "logs" / ITEM
        ctx = {
            "iid": ITEM, "item": item, "state": etat, "seq": 7, "rc": 0,
            "started_at": depart, "attempt_token": jeton,
            "log": lambda m, *a, **k: JOURNAL.append(str(m)),
            "save_state": lambda *a, **k: sauvegardes.__setitem__(0, sauvegardes[0] + 1),
            "BACKEND": "claude",
            "validator_log": log_dir / "validator-007.txt",
            "attempt_log": log_dir / "attempt-007.jsonl",
            "log_dir": log_dir,
            "GENERIC_VALIDATOR": faux_juge(sb),
            "REPO_ROOT": sb,
            # L'ATTENTE D'UNE COURSE EN VOL EST LE PERIMETRE DE L'ITEM PRECEDENT, et son banc la
            # mesure deja. Ici elle est neutralisee pour que la jambe mesure LA MESURE, pas
            # l'attente : on le DIT plutot que de le laisser croire.
            "wait_for_proof_writer": lambda *a, **k: (0, 0),
            "proof_freshness": (lambda i, t, s: orch.proof_freshness(
                i, t, s, reports_dir=str(sb / ".autoport" / "reports"), root=str(sb))),
            "judge_measure": (lambda it, i, t, c, journal=None: orch.judge_measure(
                it, i, t, c, journal=journal,
                reports_dir=str(sb / ".autoport" / "reports"), root=str(sb))),
            "_aborted_record": orch._aborted_record,
        }
        if panne_couche:
            # LA COUCHE TOMBE. `run_attempt` n'est protege que contre `StateConflict` : si une
            # exception d'ici remontait, le pilote entier mourrait. La jambe verifie qu'on
            # retombe sur le comportement d'AVANT, et que l'essai est juge quand meme.
            def _tombe(*_a, **_k):
                raise RuntimeError("panne fabriquee par le banc")
            ctx["proof_freshness"] = _tombe
        t0 = time.monotonic()
        BRAS[bras][0](ctx)
        rapport["mur_s"] = round(time.monotonic() - t0, 1)

        if deux_fois:                      # UNE SEULE COURSE, JAMAIS EN BOUCLE
            orch.judge_measure(item, ITEM, jeton, ctx["judge"],
                               reports_dir=str(sb / ".autoport" / "reports"), root=str(sb))

        # ---- ce qu'on a vu ---------------------------------------------------------------
        j = ctx.get("judge") or {}
        for cle in ("trigger", "why", "launched", "rc", "duration_s", "arm", "ceiling_s",
                    "expired", "refused", "measured_by", "named", "precheck_rc",
                    "live_pid", "live_seen_by", "live_cmd"):
            rapport[cle] = j.get(cle, "-")
        rapport["verdict_rc"] = ctx["v"].returncode if ctx.get("v") is not None else -1
        rapport["retries"] = etat["retries"][ITEM]
        rapport["preuve_presente"] = int((rep / "proof.txt").exists()
                                         and (rep / "proof.txt").stat().st_size > 0)
        champs = orch.impossible_state.parse((rep / "proof.txt").read_text(errors="replace")) \
            if rapport["preuve_presente"] else {}
        rapport["preuve_est_de_cet_essai"] = int(champs.get("proof_attempt_id", "") == jeton)
        apres_n = len(appels.read_text().splitlines()) if appels.exists() else 0
        rapport["courses_lancees"] = apres_n - appels_avant
        etat_imp = orch.impossible_state.read(str(sb / ".autoport" / "reports"), ITEM, since=0.0)
        rapport["impossible_ecrit"] = int(bool(etat_imp))
        # LE CHAINON QUI CLASSE L'ESSAI A PART. `close_gate` lit l'etat par CE lecteur, avec le
        # `since` du depart de l'essai (orchestrator.py, GATE -1). Un etat ecrit que ce
        # lecteur-la ne verrait pas ne ferait rien classer du tout : on l'interroge lui.
        rapport["impossible_vu_par_la_porte"] = int(bool(orch.impossible_state.read(
            str(sb / ".autoport" / "reports"), ITEM, since=depart)))
        rapport["impossible_cause"] = (orch.impossible_state.cause(etat_imp)[:60]
                                       if etat_imp else "-")
        if j.get("pid") and j.get("expired"):
            time.sleep(0.5)
            rapport["course_bornee_morte"] = int(
                not orch.impossible_state.pid_alive(int(j["pid"])))
        rapport["handoff_intact"] = int(handoff.exists()
                                        and handoff.read_bytes() == handoff_avant)
        rapport["journal_dit_qui"] = 0
        journal_juge = log_dir / "judge-007.jsonl"
        # ET L'ESSAI GARDE SA FORME : son dernier enregistrement reste son `attempt_end`.
        if ctx["attempt_log"].exists():
            recs = [l for l in ctx["attempt_log"].read_text(errors="replace").splitlines()
                    if l.strip()]
            rapport["essai_journal_lignes"] = len(recs)
        else:
            rapport["essai_journal_lignes"] = 0
        if journal_juge.exists():
            for ligne in journal_juge.read_text(errors="replace").splitlines():
                try:
                    ev = json.loads(ligne)
                except Exception:          # noqa: BLE001
                    continue
                if ev.get("event") == "judge_run":
                    rapport["journal_dit_qui"] = 1
                    rapport["journal_mesure_par"] = ev.get("measured_by", "-")
                    rapport["journal_declencheur"] = ev.get("trigger", "-")
        if vivant is not None:
            rapport["course_vivante_survit"] = int(vivant.poll() is None)
            try:
                os.killpg(vivant.pid, signal.SIGKILL)     # PID exact, cree par nous
            except (ProcessLookupError, PermissionError):
                pass
            vivant.wait(timeout=30)
    except Exception as e:                 # noqa: BLE001
        rapport["panne"] = f"{type(e).__name__}:{e}"
    finally:
        orch.AUTOPORT_DIR, orch.REPO_ROOT = vieux_ap, vieux_root
        orch.JUDGE_CENSUS_CEILING_SEC, orch.JUDGE_BOOT_GRACE_SEC = vieux_cens, vieux_boot
        shutil.rmtree(sb, ignore_errors=True)
    for cle, val in rapport.items():
        pub(prefixe + cle, val)
    return rapport


# ================================================== LE SITE D'APPEL, DANS LE VRAI FICHIER ====
def audit_site() -> None:
    """Le bloc leve est-il VRAIMENT celui que la production execute ?

    On compte le noeud d'APPEL dans l'AST — un `grep` compterait aussi la docstring — et on
    verifie que la mesure est appelee APRES la lecture de fraicheur et AVANT le validateur."""
    arbre = ast.parse(SRC)
    def appels(nom):
        return [n for n in ast.walk(arbre) if isinstance(n, ast.Call)
                and isinstance(n.func, ast.Name) and n.func.id == nom]
    def defs(nom):
        return [n for n in ast.walk(arbre) if isinstance(n, ast.FunctionDef) and n.name == nom]
    for nom in ("proof_freshness", "judge_measure", "judge_run_ceiling_s",
                "judge_name_the_impossible"):
        pub(f"site_appels_{nom}", len(appels(nom)))
        pub(f"site_definitions_{nom}", len(defs(nom)))
    l_fresh = min((n.lineno for n in appels("proof_freshness")), default=10 ** 9)
    l_mes = min((n.lineno for n in appels("judge_measure")), default=10 ** 9)
    # LE JUGE, DANS LA REGION ET NULLE PART AILLEURS. `GENERIC_VALIDATOR` est aussi NOMME par
    # la garde de demarrage (`if not GENERIC_VALIDATOR.exists()`), mille lignes plus haut : la
    # prendre pour le juge faisait lire « la mesure passe APRES le juge » sur un site correct.
    deb, fin = BORNES
    l_val = min((n.lineno for n in ast.walk(arbre) if isinstance(n, ast.Call)
                 and deb <= n.lineno <= fin
                 and any(isinstance(a, ast.Name) and a.id == "GENERIC_VALIDATOR"
                         for a in ast.walk(n))), default=0)
    pub("site_region_debut", deb)
    pub("site_region_fin", fin)
    pub("site_juge_dans_la_region", int(l_val > 0))
    pub("site_fraicheur_dans_la_region", int(deb <= l_fresh <= fin))
    pub("site_mesure_dans_la_region", int(deb <= l_mes <= fin))
    pub("site_fraicheur_avant_mesure", int(l_fresh < l_mes))
    pub("site_mesure_avant_le_juge", int(0 < l_mes < l_val))
    # LA MESURE EST APPELEE SOUS LE DECLENCHEUR, pas a chaque essai.
    sous_garde = 0
    for noeud in ast.walk(arbre):
        if not isinstance(noeud, ast.If):
            continue
        # `ast.unparse` rend les chaines en apostrophes : comparer au litteral ecrit avec des
        # guillemets rendait toujours faux, et la garde se lisait « absente ».
        if "judge['trigger']" not in ast.unparse(noeud.test).replace('"', "'"):
            continue
        if "judge_measure" in ast.unparse(noeud):
            sous_garde += 1
    pub("site_mesure_sous_le_declencheur", sous_garde)


def audit_plafond() -> None:
    """Les bornes REELLES, lues sur la fonction de production — pas celles du bac a sable."""
    pub("plafond_item_reel", orch.judge_run_ceiling_s({"proof_timeout": 420}))
    pub("plafond_defaut_x86", orch.judge_run_ceiling_s({}))
    pub("plafond_defaut_appareil", orch.judge_run_ceiling_s({"device": True}))
    pub("plafond_recensement", orch.JUDGE_CENSUS_CEILING_SEC)
    pub("plafond_amorcage", orch.JUDGE_BOOT_GRACE_SEC)
    pub("plafond_dur", orch.JUDGE_RUN_HARD_CEILING_SEC)
    pub("plafond_sur_valeur_illisible", orch.judge_run_ceiling_s({"proof_timeout": "bientot"}))
    pub("plafond_borne_par_le_dur", orch.judge_run_ceiling_s({"proof_timeout": 99999}))
    # UNE BORNE AU `proof_timeout` SEUL TUERAIT UNE COURSE NORMALE : la preuve de l'item
    # precedent a dure 502 s pour un `proof_timeout` de 420. On publie l'ecart.
    pub("plafond_couvre_502s", int(orch.judge_run_ceiling_s({"proof_timeout": 420}) > 502))
    pub("plafond_bras_x86", orch.judge_proof_arm({"device": False}))
    pub("plafond_bras_appareil", orch.judge_proof_arm({"device": True}))


def audit_litteraux() -> None:
    """LES CHEMINS DE BINAIRE EPINGLES SONT-ILS ENCORE CEUX DU JUGE ?

    `validators/generic.sh` derive le binaire de `source=` et ne l'expose pas ; DIRECTIVES 5
    interdit de le modifier pour qu'il le publie. On EPINGLE donc ses deux litteraux et on
    verifie, a chaque course, qu'ils sont encore dans son texte. Garde d'egalite, pas refactor :
    le jour ou il change de chemin, cette porte ROUGIT au lieu de devenir aveugle."""
    trouves = sum(1 for chemin in orch.JUDGE_BINARY_OF_SOURCE.values() if chemin in GEN)
    pub("litteraux_epingles", len(orch.JUDGE_BINARY_OF_SOURCE))
    pub("litteraux_dans_le_juge", trouves)
    pub("litteraux_source_device", int('[ "$src" = device ]' in GEN))


def audit_compte() -> None:
    """UN ESSAI DONT LA PREUVE ETAIT IMPOSSIBLE N'EST PAS DEBITE — la fonction de production,
    appelee sur un etat, et le compte relu avant/apres."""
    etat = {"retries": {ITEM: 5}, "proof_impossible": {}}
    verdict, dit = orch.requalify_impossible_attempt(
        etat, ITEM, {"reason": "juge-course-sans-mesure", "detail": "rc 6",
                     "arm": "livre", "since_s": 12})
    pub("compte_verdict", verdict)
    pub("compte_retries_apres", etat["retries"][ITEM])
    pub("compte_rendu_a_l_identique", int(etat["retries"][ITEM] == 4))
    pub("compte_dit_non_compte", int("NON COMPT" in dit.upper()))


def audit_ablation_ancre() -> None:
    """LE BRAS D'AVANT EST-IL LE CODE QUI TOURNAIT LE 16/09 ? Confronte, ligne a ligne, au blob
    que `lib/ablation_anchor.sh` designe — le dernier commit du chemin sans le marqueur."""
    sortie = subprocess.run(
        ["bash", str(AP / "lib" / "ablation_anchor.sh"), str(ROOT),
         ".autoport/orchestrator.py", "# MESURE-DU-JUGE/debut", "kv"],
        cwd=ROOT, capture_output=True, text=True)
    champs = dict(l.split("=", 1) for l in sortie.stdout.splitlines() if "=" in l)
    commit = champs.get("anchor_commit", "-")
    pub("ancre_commit", commit[:12])
    pub("ancre_methode", champs.get("anchor_method", "-"))
    pub("ancre_profondeur", champs.get("anchor_depth", "-1"))
    blob = subprocess.run(["git", "show", f"{commit}:.autoport/orchestrator.py"],
                          cwd=ROOT, capture_output=True, text=True).stdout if commit != "-" else ""
    pub("ancre_blob_octets", len(blob))
    pub("ancre_blob_porte_le_marqueur", int("# MESURE-DU-JUGE/debut" in blob))
    if not blob:
        pub("ancre_avant_egale_le_blob", 0)
        pub("ancre_blob_lignes", -1)
        return
    try:
        _, _, bloc_blob = region("JUGEMENT", blob)
        pub("ancre_blob_lignes", len(bloc_blob))
        pub("ancre_avant_egale_le_blob", int(code_nu(bloc_blob) == code_nu(BLOC_AVANT)))
    except BancCasse:
        # LE MARQUEUR `JUGEMENT` EST NE AVEC LA COUCHE : le blob d'avant ne le porte pas. On
        # compare alors le bras d'AVANT a la sequence qui y tenait lieu de jugement, reperee
        # par sa premiere et sa derniere ligne de code — celles que l'ablation preserve.
        lignes = blob.splitlines()
        nu = code_nu(BLOC_AVANT)
        pub("ancre_blob_lignes", len(lignes))
        debut = next((n for n, l in enumerate(lignes) if l.strip() == nu[0]), -1)
        if debut < 0:
            pub("ancre_avant_egale_le_blob", 0)
            return
        fenetre = code_nu(lignes[debut:debut + len(BLOC_AVANT) + 40])[:len(nu)]
        pub("ancre_avant_egale_le_blob", int(fenetre == nu))


# ============================================================================== LE BANC ======
def main() -> int:
    pub("banc_ran", 0)
    pub("banc_panne", "")
    try:
        decoupe()
        BRAS["apres"] = compile_bloc(BLOC_APRES)
        BRAS["avant"] = compile_bloc(BLOC_AVANT)
        audit_site()
        audit_plafond()
        audit_litteraux()
        audit_compte()
        audit_ablation_ancre()

        # LE TEMOIN QUI INTERDIT LA VRAIE COURSE : le journal d'effacement du vrai
        # `lib/proof_run.sh` ne doit pas avoir bouge d'une ligne pendant tout le banc.
        vrai = AP / "logs" / "proof-erase.tsv"
        avant_n = len(vrai.read_text(errors="replace").splitlines()) if vrai.exists() else -1

        # 1. LE CONTROLE : la preuve EST celle de l'essai. Le juge ne mesure pas.
        jambe("neuve", preuve="a-jour")
        # 2/3/4/5. LES QUATRE DECLENCHEURS QUE LE CONTRAT NOMME.
        jambe("absent")
        jambe("identite", preuve="autre", jeton_autre=True)
        jambe("vieille", preuve="a-jour", vieille=True)
        jambe("sources", preuve="a-jour", source_tardive=True)
        # 6. ON NE DOUBLE JAMAIS UNE COURSE VIVANTE (hors perimetre de cet item).
        jambe("vivante", course_vivante=True)
        # 7. UNE SEULE COURSE PAR ESSAI, MEME APPELEE DEUX FOIS.
        jambe("uneseule", deux_fois=True)
        # 8. LA COURSE QUI NE MESURE PAS : rc 6, aucun etat ecrit par proof_run.sh.
        jambe("impossible", rc_run=6, ecrit=0)
        # 9. LA BORNE TRANCHE, ET ELLE NE RELANCE RIEN.
        # La borne vaut proof_timeout + recensement + amorcage = 2+1+1 = 4 s, et la course en
        # dort 20 : c'est la BORNE qui tranche, et on verifie qu'elle a bien tue la course.
        jambe("plafond", dort=20, timeout_item=2, plafond=(1.0, 1.0))
        # 10. LE BRAS D'AVANT, SUR LA MEME ABSENCE DE PREUVE QUE LA JAMBE 2.
        jambe("avant", bras="avant")
        # 11. LA COUCHE TOMBE : l'essai est juge quand meme, comme avant elle.
        jambe("panne", panne_couche=True)

        apres_n = len(vrai.read_text(errors="replace").splitlines()) if vrai.exists() else -1
        pub("banc_vraie_course_lancee", int(avant_n != apres_n))
        pub("banc_journal_lignes", len(JOURNAL))
        for cle, motif in (("journal_dit_mesure", "LE JUGE MESURE"),
                           ("journal_dit_rien_a_mesurer", "n'a rien a mesurer"),
                           ("journal_dit_vivante", "VIT encore"),
                           ("journal_dit_classe_a_part", "CLASSE A PART")):
            pub(cle, sum(1 for l in JOURNAL if motif in l))
        pub("banc_ran", 1)
    except BancCasse as e:
        pub("banc_panne", str(e)[:200])
    except Exception as e:                 # noqa: BLE001
        pub("banc_panne", f"{type(e).__name__}:{e}"[:200])
    for cle, val in SORTIE.items():
        texte = re.sub(r"\s+", "_", str(val))
        print(f"{cle}={texte or '-'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
