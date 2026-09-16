#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""lib/inflight_selftest.py — LE BANC DE `harness-judge-waits-for-the-proof-a-worker-left-in-flight`.

CE QU'IL MESURE. Le 16/09, `ao-prepass-tie-alpha` essai 15 a lance sa course de preuve en
arriere-plan (`run_in_background` de la CLI), emis son resultat, et s'est tu. Quarante-cinq
secondes plus tard `_kill('post-result')` a envoye SIGTERM au GROUPE du worker : la course est
partie avec lui, `proof-engine.log` s'arrete net a l'instant du signal, et `proof.txt` n'a
jamais existe. Le juge a lu « proof.txt absent ou vide » et l'essai a ete COMPTE.

HUIT JAMBES, DE VRAIS PROCESSUS, DE VRAIS `killpg`. Un faux worker (bash) lance un faux
`proof_run.sh` qui dort puis ECRIT, emet `{"type":"result"}` et se tait pour toujours — le
comportement exact du 16/09. La boucle de lecture du banc porte, TEL QUEL, le bloc de decision
leve de `orchestrator.py` entre `# POST-RESULT/debut` et `# POST-RESULT/fin` :

  * bras d'APRES  = ce bloc entier ;
  * bras d'AVANT  = le MEME bloc prive de sa region `# EN-VOL/...`, c'est-a-dire le code qui
                    tournait le 16/09. La couche n'est pas desarmee : elle est ABSENTE.

Le banc REFUSE de tourner si un marqueur manque ou si la region d'avant nomme encore la couche :
un bras d'ablation qui contient ce qu'il ablate mesure zero et ne le dit pas.

CE QU'IL NE MESURE PAS. Il ne lance aucune vraie course, n'installe rien, ne touche ni a
`reports/` ni a `state.json` : chaque jambe vit dans son propre dossier jetable, sous son propre
id d'item, et ne tue que des PID qu'elle a elle-meme crees (DIRECTIVES : PID exacts, jamais de
motif).

SORTIE : des lignes `cle=valeur` sans espace, lues par
`lib/census/harness-judge-waits-for-the-proof-a-worker-left-in-flight.sh`. Une cle absente vaut
-1 cote recensement, jamais 0 : un zero passerait une porte `== 0`.
"""
from __future__ import annotations

import ast
import os
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

AP = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(AP))
import orchestrator as orch              # noqa: E402 — le chemin doit precede l'import

SRC = (AP / "orchestrator.py").read_text(encoding="utf-8")
SORTIE: dict[str, object] = {}

# LE JOURNAL QUE L'ORCHESTRATEUR TIENT, CAPTE. Deux raisons : sa sortie riche polluerait les
# lignes `cle=valeur` du banc, et surtout le contrat demande de PUBLIER l'attente — la publier,
# c'est prouver que la ligne existe et qu'elle nomme le PID, pas jurer qu'on l'a ecrite.
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
    """(premiere ligne, derniere ligne, contenu) de la region `# <marque>/debut .. /fin`.

    ANCRE SUR UN MARQUEUR, JAMAIS SUR `HEAD:`. Un temoin d'AVANT lu a `git show HEAD:` s'accuse
    lui-meme des le commit : il devient le code d'apres sans que rien ne le dise."""
    lignes = texte.splitlines()
    d = [n for n, l in enumerate(lignes) if l.strip() == f"# {marque}/debut"]
    f = [n for n, l in enumerate(lignes) if l.strip() == f"# {marque}/fin"]
    if len(d) != 1 or len(f) != 1 or f[0] <= d[0] + 1:
        raise BancCasse(f"marqueur {marque} : {len(d)} debut, {len(f)} fin — region introuvable")
    return d[0], f[0], lignes[d[0] + 1:f[0]]


def reindente(lignes: list[str], vers: int) -> list[str]:
    marge = min((len(l) - len(l.lstrip()) for l in lignes if l.strip()), default=0)
    return [(" " * vers + l[marge:]) if l.strip() else "" for l in lignes]


def code_nu(lignes: list[str]) -> list[str]:
    """Le code, sans les commentaires ni l'indentation : deux blocs identiques doivent l'etre
    meme si l'un est indente de vingt colonnes et l'autre de douze."""
    nu = []
    for l in lignes:
        t = l.strip()
        if t and not t.startswith("#"):
            nu.append(t)
    return nu


BLOC_APRES: list[str] = []
BLOC_AVANT: list[str] = []


def decoupe() -> None:
    """Les deux bras, leves du fichier de production. UN COMMENTAIRE N'EST PAS DU CODE : la
    prose du bloc NOMME la couche et le banc — c'est meme son role — et la juger reviendrait a
    refuser l'ablation a cause de sa propre explication. On ne regarde que les lignes de code."""
    global BLOC_APRES, BLOC_AVANT
    d_post, f_post, BLOC_APRES = region("POST-RESULT")
    d_vol, f_vol, _ = region("EN-VOL")
    if not (d_post < d_vol and f_vol < f_post):
        raise BancCasse("la region EN-VOL n'est pas DANS la region POST-RESULT")
    # LE BRAS D'AVANT : le meme bloc, prive de la region de la couche et de ses deux marqueurs.
    BLOC_AVANT = BLOC_APRES[:d_vol - (d_post + 1)] + BLOC_APRES[f_vol - (d_post + 1) + 1:]

    avant = "\n".join(code_nu(BLOC_AVANT))
    apres = "\n".join(code_nu(BLOC_APRES))
    pub("bloc_apres_lignes", len(BLOC_APRES))
    pub("bloc_avant_lignes", len(BLOC_AVANT))
    pub("bloc_apres_nomme_la_couche", int("post_result_verdict" in apres))
    pub("bloc_avant_nomme_la_couche",
        int("post_result_verdict" in avant or "inflight" in avant))
    pub("bloc_avant_tue", int('_kill("post-result")' in avant))
    pub("bloc_avant_contient_continue", int("continue" in avant))
    if SORTIE["bloc_avant_nomme_la_couche"]:
        raise BancCasse("le bras d-AVANT nomme encore la couche : l-ablation serait vide")
    if not SORTIE["bloc_apres_nomme_la_couche"]:
        raise BancCasse("le bras d-APRES ne nomme pas la couche : marqueur pose au mauvais endroit")

GABARIT = r'''
def boucle(ctx):
    proc = ctx["proc"]; pstate = ctx["pstate"]; iid = ctx["iid"]; inflight = ctx["inflight"]
    log = ctx["log"]; _kill = ctx["_kill"]; _maybe_emit_tick = ctx["_maybe_emit_tick"]
    BACKEND = ctx["BACKEND"]; post_result_verdict = ctx["post_result_verdict"]
    STALL_POST_RESULT_SEC = ctx["STALL_POST_RESULT_SEC"]
    last_event_at = time.monotonic()
    while True:
        try:
            ready, _, _ = select.select([proc.stdout], [], [], ctx["poll_s"])
        except (OSError, ValueError):
            break
        if not ready:
            idle = time.monotonic() - last_event_at
            if proc.poll() is not None:
                break
{BLOC}
            if idle >= ctx["garde_s"]:
                ctx["garde_du_banc"] = 1
                _kill("garde-du-banc")
                break
            continue
        # ON LIT LE DESCRIPTEUR, PAS UN TAMPON. `select` regarde le fd ; un `readline()`
        # bufferise aspire DEUX lignes d'un coup, en rend une, et garde l'autre dans un tampon
        # que `select` ne voit pas — le fd redevient muet et la ligne restee dedans n'est
        # JAMAIS lue. Mesure du banc : cinq jambes sur huit n'ont jamais vu le `result` de leur
        # faux worker, qui l'avait pourtant ecrit. Signale dans FINDINGS : la production lit
        # comme ca.
        brut = os.read(proc.stdout.fileno(), 65536)
        if not brut:
            break
        last_event_at = time.monotonic()
        ctx["tampon"] += brut
        while b"\n" in ctx["tampon"]:
            ligne, _, ctx["tampon"] = ctx["tampon"].partition(b"\n")
            if b'"type":"result"' in ligne.replace(b" ", b""):
                pstate.result_seen = True
                ctx["result_at"] = time.monotonic()
'''


def compile_boucle(bloc: list[str]):
    source = GABARIT.replace("{BLOC}", "\n".join(reindente(bloc, 12)))
    espace: dict = {"time": time, "select": select, "os": os}
    exec(compile(source, "<boucle-du-banc>", "exec"), espace)   # noqa: S102 — c'est le sujet
    return espace["boucle"], source


BOUCLES: dict = {}


# ================================================== LE SITE D'APPEL, DANS LE VRAI FICHIER ====
def audit_site() -> None:
    """Le bloc leve est-il VRAIMENT celui que la production execute ?

    Un banc qui leve une region morte serait vert sur du code que personne n'appelle. On
    compte le noeud d'APPEL dans l'AST — un `grep` compterait aussi la docstring — et on
    verifie qu'il est DANS le test post-result et AVANT le `_kill`."""
    arbre = ast.parse(SRC)
    appels = [n for n in ast.walk(arbre)
              if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
              and n.func.id == "post_result_verdict"]
    pub("site_appels", len(appels))
    defs = [n for n in ast.walk(arbre)
            if isinstance(n, ast.FunctionDef) and n.name == "post_result_verdict"]
    pub("site_definitions", len(defs))
    dedans = 0
    avant_le_kill = 0
    for noeud in ast.walk(arbre):
        if not isinstance(noeud, ast.If):
            continue
        test = ast.unparse(noeud.test)
        if "result_seen" not in test or "STALL_POST_RESULT_SEC" not in test:
            continue
        corps = ast.unparse(noeud)
        if "post_result_verdict" not in corps:
            continue
        dedans += 1
        # La ligne de l'appel doit preceder celle de tout `_kill` de cette branche.
        l_appel = min((n.lineno for n in ast.walk(noeud) if isinstance(n, ast.Call)
                       and isinstance(n.func, ast.Name) and n.func.id == "post_result_verdict"),
                      default=10 ** 9)
        l_kill = min((n.lineno for n in ast.walk(noeud) if isinstance(n, ast.Call)
                      and isinstance(n.func, ast.Name) and n.func.id == "_kill"), default=0)
        avant_le_kill += int(l_kill > l_appel)
    pub("site_dans_le_test_post_result", dedans)
    pub("site_appel_avant_le_kill", avant_le_kill)
    pub("site_stall_s", orch.STALL_POST_RESULT_SEC)


# ================================================================== LES BORNES DE L'ATTENTE ==
def audit_plafond() -> None:
    pub("plafond_item_reel", orch.inflight_ceiling_s({"proof_timeout": 420}))
    pub("plafond_defaut_x86", orch.inflight_ceiling_s({}))
    pub("plafond_defaut_appareil", orch.inflight_ceiling_s({"device": True}))
    pub("plafond_marge", orch.INFLIGHT_GRACE_SEC)
    pub("plafond_sur_valeur_illisible", orch.inflight_ceiling_s({"proof_timeout": "bientot"}))


# ======================================================= LA DETECTION NE SE MATCHE PAS ELLE ==
def motif_de_ligne(item_id: str) -> int:
    """Ce qu'un matcher sur la ligne ENTIERE — un `pkill -f` — aurait pris. Publie pour
    CHIFFRER l'ecart avec la comparaison argument par argument, pas pour l'utiliser."""
    n = 0
    for e in os.scandir("/proc"):
        if not e.name.isdigit() or int(e.name) == os.getpid():
            continue
        try:
            brut = (Path(e.path) / "cmdline").read_bytes()
        except OSError:
            continue
        ligne = brut.replace(b"\0", b" ").decode("utf-8", "replace")
        if "proof_run.sh" in ligne and item_id in ligne:
            n += 1
    return n


def audit_self_match(base: Path) -> None:
    """Un processus dont UN SEUL argument porte a la fois le nom du script et l'id de l'item.
    C'est ce que fabrique n'importe quel `bash -c` qui NOMME la commande sans la lancer."""
    iid = "banc-envol-self"
    faux = base / "proof_run.sh"
    # DEUX COMMANDES, ET C'EST INDISPENSABLE. `bash -c 'sleep 8 # ...'` remplace bash par
    # `sleep` (optimisation d'exec du dernier commande) : la ligne de commande DISPARAIT, et le
    # temoin mesurait zero des deux cotes — un faux vert. Le `true` empeche l'exec.
    cmd = f"sleep 8  # bash {faux} {iid} x86\ntrue"
    p = subprocess.Popen(["bash", "-c", cmd])
    try:
        time.sleep(1.0)
        pub("selfmatch_par_argument", len(orch.proof_run_processes(iid)))
        pub("selfmatch_par_motif_de_ligne", motif_de_ligne(iid))
        pub("selfmatch_cible_vivante", int(orch.impossible_state.pid_alive(p.pid)))
    finally:
        try:
            os.kill(p.pid, signal.SIGKILL)      # PID exact, jamais un motif
        except ProcessLookupError:
            pass
        p.wait()


# ================================ LE BRAS D'AVANT, CONFRONTE AU CODE QUI TOURNAIT VRAIMENT ====
ROOT = AP.parent


def branche_post_result(texte: str) -> list[str]:
    """La branche `if pstate.result_seen and idle >= STALL...:` jusqu'a son `break`."""
    lignes = texte.splitlines()
    for n, l in enumerate(lignes):
        if l.strip().startswith("if pstate.result_seen and idle >= STALL_POST_RESULT_SEC:"):
            bloc = [l]
            for m in range(n + 1, min(n + 40, len(lignes))):
                bloc.append(lignes[m])
                if lignes[m].strip() == "break":
                    return bloc
            return bloc
    return []


def audit_bras_avant() -> None:
    """LE BRAS D'AVANT EST-IL VRAIMENT LE CODE DU 16/09 ?

    Le banc le fabrique en retirant la region `EN-VOL/` du bloc de production. C'est une
    DERIVATION : elle pourrait diverger de ce qui tournait ce jour-la sans que rien ne le dise.
    On la confronte donc au blob que `lib/ablation_anchor.sh` designe — le dernier commit ou
    `orchestrator.py` ne portait pas encore le marqueur. Ancre sur le MARQUEUR, jamais sur
    `HEAD:` : un temoin d'avant lu a `HEAD:` devient le code d'apres des le commit, et
    s'accuse lui-meme."""
    commit, methode = "-", "-"
    try:
        r = subprocess.run(["bash", str(AP / "lib/ablation_anchor.sh"), str(ROOT),
                            ".autoport/orchestrator.py", "POST-RESULT/debut", "kv"],
                           capture_output=True, text=True, timeout=300)
        champs = dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)
        commit = champs.get("anchor_commit", "-") or "-"
        methode = champs.get("anchor_method", "-") or "-"
    except (OSError, subprocess.SubprocessError, ValueError):
        pass
    pub("avant_ancre_commit", commit[:12])
    pub("avant_ancre_methode", methode)
    blob = ""
    if commit not in ("", "-"):
        try:
            blob = subprocess.run(["git", "-C", str(ROOT), "show",
                                   f"{commit}:.autoport/orchestrator.py"],
                                  capture_output=True, text=True, timeout=120).stdout
        except (OSError, subprocess.SubprocessError):
            blob = ""
    pub("avant_blob_octets", len(blob))
    pub("avant_blob_porte_le_marqueur", int("POST-RESULT/debut" in blob))
    du_blob = code_nu(branche_post_result(blob))
    derive = code_nu(BLOC_AVANT)
    pub("avant_blob_lignes", len(du_blob))
    pub("avant_derive_lignes", len(derive))
    pub("avant_derive_egale_le_blob", int(bool(du_blob) and du_blob == derive))
    apres = code_nu(BLOC_APRES)
    pub("apres_lignes_de_code", len(apres))
    pub("apres_egale_le_blob", int(bool(du_blob) and du_blob == apres))


# ============================================ LE MEME PID, NOMME PUIS MUET (cout : 1 seconde) ==
def audit_verrou_vivant_puis_mort(base: Path) -> None:
    """Un verrou ne vaut que par la vie de son PID. Le meme numero doit etre NOMME tant qu'il
    respire et MUET des qu'il est mort : un verrou qui nomme un cadavre retiendrait le juge
    jusqu'a la borne, a chaque essai, sans qu'aucune course n'ecrive."""
    d = base / "verrouvif"
    (d / "reports").mkdir(parents=True, exist_ok=True)
    iid = "banc-envol-verrouvif"
    chemin = Path(orch.impossible_state.arm_path(str(d / "reports"), iid, "writer", ""))
    chemin.parent.mkdir(parents=True, exist_ok=True)
    dormeur = subprocess.Popen(["sleep", "60"])
    try:
        chemin.write_text(f"pid={dormeur.pid}\nat=banc\nattempt=banc\n", encoding="utf-8")
        pid, vu = orch.inflight_proof_run(iid, str(d / "reports"))
        pub("verrouvif_pid_vu", pid)
        pub("verrouvif_vu_par", vu or "-")
        pub("verrouvif_est_le_dormeur", int(pid == dormeur.pid))
    finally:
        try:
            os.kill(dormeur.pid, signal.SIGKILL)       # PID exact, jamais un motif
        except ProcessLookupError:
            pass
        dormeur.wait()
    pid, vu = orch.inflight_proof_run(iid, str(d / "reports"))
    pub("verroumort_pid_vu", pid)
    pub("verroumort_vu_par", vu or "-")
    pub("verroumort_fichier_toujours_la", int(chemin.exists()))


# ============================================================================ LES SCRIPTS ====
FAUX_PROOF_RUN = r'''#!/usr/bin/env bash
# Le faux proof_run du banc. Il ne mesure rien : il OCCUPE la place d'une course, il pose son
# PID, et il n'ECRIT qu'a la fin — comme une vraie course, dont proof.txt n'existe pas tant
# qu'elle n'a pas fini. Tue, il n'ecrit rien : c'est tout le defaut du 16/09.
ID="$1"; DUREE="$2"; CIBLE="$3"; VERROU="$4"; PIDF="$5"
printf '%s\n' "$$" > "$PIDF"
if [ -n "$VERROU" ]; then
  mkdir -p "$(dirname "$VERROU")"
  printf 'pid=%s\nat=%s\nattempt=banc\n' "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$VERROU"
fi
sleep "$DUREE"
printf 'proof=%s\npid=%s\nfini_a=%s\n' "$ID" "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$CIBLE"
[ -z "$VERROU" ] || rm -f "$VERROU"
'''

FAUX_WORKER = r'''#!/usr/bin/env bash
# Le faux worker. Il lance sa course, il emet son resultat, et il SE TAIT — mot pour mot ce
# qu'a fait ao-prepass-tie-alpha 15 le 16/09 a 16:17. Il ne sort jamais de lui-meme : c'est la
# CLI en mode -p qui reste ouverte, et c'est pour ca que la fermeture forcee existe.
set -u
if [ "${BANC_COURSE:-0}" = 1 ]; then
  if [ "${BANC_SETSID:-0}" = 1 ]; then
    setsid bash "$BANC_SCRIPT" "$BANC_ITEM" "$BANC_DUREE" "$BANC_CIBLE" "$BANC_VERROU" \
        "$BANC_PIDF" >/dev/null 2>&1 &
  else
    bash "$BANC_SCRIPT" "$BANC_ITEM" "$BANC_DUREE" "$BANC_CIBLE" "$BANC_VERROU" \
        "$BANC_PIDF" >/dev/null 2>&1 &
  fi
  printf '{"type":"assistant","dit":"course lancee, j attends la notification"}\n'
fi
printf '{"type":"result","subtype":"success"}\n'
exec sleep 900
'''


class Etat:
    def __init__(self) -> None:
        self.result_seen = False


# ================================================================================ UNE JAMBE ==
def jambe(nom: str, *, bras: str, course: bool, duree: int, detache: bool,
          script_proof_run: bool, item_argument: bool, verrou: bool, plafond: float,
          verrou_perime: bool = False, base: Path) -> None:
    """Une jambe = un faux worker, sa course, et la VRAIE decision. Rien n'est simule."""
    d = base / nom
    (d / "reports").mkdir(parents=True, exist_ok=True)
    iid = f"banc-envol-{nom}"
    script = d / ("proof_run.sh" if script_proof_run else "ecrivain.sh")
    script.write_text(FAUX_PROOF_RUN, encoding="utf-8")
    cible = d / "proof.txt"
    pidf = d / "run.pid"
    chemin_verrou = Path(orch.impossible_state.arm_path(str(d / "reports"), iid, "writer", ""))

    if verrou_perime:
        mort = subprocess.Popen(["bash", "-c", "exit 0"])
        mort.wait()
        chemin_verrou.parent.mkdir(parents=True, exist_ok=True)
        chemin_verrou.write_text(f"pid={mort.pid}\nat=banc\nattempt=banc\n", encoding="utf-8")
        pub(f"{nom}_verrou_perime_pid_vivant",
            int(orch.impossible_state.pid_alive(mort.pid)))

    env = dict(os.environ)
    env.update({
        "BANC_COURSE": "1" if course else "0",
        "BANC_SETSID": "1" if detache else "0",
        "BANC_SCRIPT": str(script),
        # DEUX LEVIERS SEPARES, PARCE QUE LA DETECTION A DEUX TERMES. Le NOM du script
        # (`proof_run.sh`) et l'ARGUMENT (l'id de l'item) sont compares independamment : une
        # jambe porte un VRAI proof_run.sh lance sur un AUTRE item — il ne doit pas retenir le
        # juge de celui-ci — et une autre porte un ecrivain qui ne nomme rien, que seul le
        # verrou revele.
        "BANC_ITEM": iid if item_argument else f"{iid}-AUTRE",
        "BANC_DUREE": str(duree),
        "BANC_CIBLE": str(cible),
        "BANC_VERROU": str(chemin_verrou) if verrou else "",
        "BANC_PIDF": str(pidf),
    })
    worker = d / "worker.sh"
    worker.write_text(FAUX_WORKER, encoding="utf-8")

    inflight = {"ceiling_s": plafond, "pid": 0, "how": "", "waited_s": 0.0, "holds": 0,
                "expired": 0, "ended": 0, "reports_dir": str(d / "reports")}
    ctx: dict = {
        "pstate": Etat(), "iid": iid, "inflight": inflight, "BACKEND": "banc",
        "post_result_verdict": orch.post_result_verdict,
        "STALL_POST_RESULT_SEC": orch.STALL_POST_RESULT_SEC,
        "poll_s": 2.0, "garde_s": 60.0 + duree, "garde_du_banc": 0, "tampon": b"",
        "result_at": 0.0, "kill_at": 0.0, "kill_raison": "",
        "log": lambda *a, **k: None, "_maybe_emit_tick": lambda *a, **k: None,
    }
    proc = subprocess.Popen(["bash", str(worker)], cwd=str(d), env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            bufsize=0, start_new_session=True)
    ctx["proc"] = proc

    def _kill(raison: str) -> None:
        ctx["kill_raison"] = raison
        ctx["kill_at"] = time.monotonic()
        # LE MEME APPEL QUE LA PRODUCTION : le GROUPE du worker, jamais un motif.
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    ctx["_kill"] = _kill

    t0 = time.monotonic()
    try:
        BOUCLES[bras](ctx)
    finally:
        course_pid = 0
        try:
            course_pid = int(pidf.read_text().strip())
        except (OSError, ValueError):
            pass
        # LA SURVIE, LUE JUSTE APRES LE SIGNAL : c'est la que `setsid` se voit ou pas.
        time.sleep(1.0)
        vivante = int(bool(course_pid) and orch.impossible_state.pid_alive(course_pid))
        pub(f"{nom}_course_pid", course_pid)
        pub(f"{nom}_course_vivante_apres_kill", vivante)
        # On laisse la course finir SI elle a survecu — c'est le point du contrat : la preuve
        # arrive apres la fermeture. Borne, et on ne relance rien.
        limite = time.monotonic() + duree + 15
        while vivante and time.monotonic() < limite and not cible.exists():
            time.sleep(1.0)
            vivante = orch.impossible_state.pid_alive(course_pid)
        for pid in (proc.pid, course_pid):
            # ON NE TIRE QUE SUR CE QUI VIT ENCORE, ET QU'ON A SOI-MEME SEME : un numero recycle
            # appartient deja a quelqu'un d'autre.
            if not pid or not orch.impossible_state.pid_alive(pid):
                continue
            try:
                os.killpg(pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                try:
                    os.kill(pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass

    result_at = ctx["result_at"] or t0
    pub(f"{nom}_tue", int(bool(ctx["kill_raison"])))
    pub(f"{nom}_raison", ctx["kill_raison"] or "-")
    pub(f"{nom}_tue_a_s", (ctx["kill_at"] - result_at) if ctx["kill_at"] else -1)
    pub(f"{nom}_garde_du_banc", ctx["garde_du_banc"])
    pub(f"{nom}_pid_vu", inflight["pid"])
    pub(f"{nom}_vu_par", inflight["how"] or "-")
    pub(f"{nom}_attendu_s", inflight["waited_s"])
    pub(f"{nom}_holds", inflight["holds"])
    pub(f"{nom}_plafond_atteint", inflight["expired"])
    pub(f"{nom}_course_finie_vue", inflight["ended"])
    pub(f"{nom}_preuve_presente", int(cible.exists()))
    pub(f"{nom}_preuve_octets", cible.stat().st_size if cible.exists() else 0)


JAMBES = [
    # 1. LA COURSE EST VUE ET ATTENDUE : aucun signal tant qu'elle ecrit. (livrable 2)
    dict(nom="attend", bras="apres", course=True, duree=75, detache=False,
         script_proof_run=True, item_argument=True, verrou=False, plafond=540.0),
    # 2. LE DEFAUT DU 16/09, REJOUE : meme course, couche ABSENTE. (livrable 4, bras --off)
    dict(nom="avant", bras="avant", course=True, duree=75, detache=False,
         script_proof_run=True, item_argument=True, verrou=False, plafond=540.0),
    # 3. AUCUNE COURSE : la fermeture a 45 s ne bouge pas. (livrable 4b)
    dict(nom="sanscourse", bras="apres", course=False, duree=5, detache=False,
         script_proof_run=True, item_argument=True, verrou=False, plafond=540.0),
    # 4. MEME FERMETURE QUE 2, MAIS `setsid` : la course survit et sa preuve arrive. (livrable 3)
    dict(nom="setsid", bras="avant", course=True, duree=75, detache=True,
         script_proof_run=True, item_argument=True, verrou=False, plafond=540.0),
    # 5. UN VRAI `proof_run.sh` D'UN AUTRE ITEM ne retient pas ce juge-ci : c'est l'ARGUMENT
    #    qui identifie la course, pas le nom du script. Population de controle.
    dict(nom="autreitem", bras="apres", course=True, duree=75, detache=False,
         script_proof_run=True, item_argument=False, verrou=False, plafond=540.0),
    # 6. L'ATTENTE EST BORNEE : plafond a 10 s sur une course de 75 s.
    dict(nom="plafond", bras="apres", course=True, duree=75, detache=True,
         script_proof_run=True, item_argument=True, verrou=False, plafond=10.0),
    # 7. LE VERROU VOIT CE QUE LE PROCESSUS NE VOIT PAS : ni le nom, ni l'argument.
    dict(nom="verrou", bras="apres", course=True, duree=70, detache=False,
         script_proof_run=False, item_argument=False, verrou=True, plafond=540.0),
    # 8. UN VERROU PERIME NE RETIENT PERSONNE : son PID est mort, la fermeture a lieu.
    dict(nom="verrouperime", bras="apres", course=False, duree=5, detache=False,
         script_proof_run=True, item_argument=True, verrou=False, plafond=540.0,
         verrou_perime=True),
]


def main() -> int:
    decoupe()
    BOUCLES["apres"], _ = compile_boucle(BLOC_APRES)
    BOUCLES["avant"], _ = compile_boucle(BLOC_AVANT)
    audit_site()
    audit_plafond()
    audit_bras_avant()
    base = Path(tempfile.mkdtemp(prefix="banc-envol-"))
    pub("bac", str(base).replace(" ", "_"))
    try:
        audit_self_match(base)
        audit_verrou_vivant_puis_mort(base)
        with ThreadPoolExecutor(max_workers=len(JAMBES)) as pool:
            futurs = {j["nom"]: pool.submit(jambe, base=base, **j) for j in JAMBES}
            for nom, fut in futurs.items():
                try:
                    fut.result()
                except Exception as e:                       # noqa: BLE001
                    pub(f"{nom}_panne", type(e).__name__)
    finally:
        shutil.rmtree(base, ignore_errors=True)
    # CE QUE LE JOURNAL A DIT, COMPTE. Trois phrases, trois etats : on attend, la course a
    # fini, la borne a tranche. Un journal muet pendant qu'on attend serait une attente que
    # personne ne pourrait expliquer a l'owner.
    pub("journal_lignes", len(JOURNAL))
    pub("journal_dit_attend", sum(1 for l in JOURNAL if "ÉCRIT encore" in l))
    pub("journal_dit_finie", sum(1 for l in JOURNAL if "est terminée après" in l))
    pub("journal_dit_borne", sum(1 for l in JOURNAL if "dépasse la borne" in l))
    pub("journal_nomme_un_pid", sum(1 for l in JOURNAL if "pid=" in l))
    pub("banc_ran", 1)
    for cle in sorted(SORTIE):
        val = str(SORTIE[cle])
        print(f"{cle}={re.sub(r'\s+', '_', val) or '-'}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BancCasse as e:
        print(f"banc_ran=0\nbanc_panne={re.sub(r'[^A-Za-z0-9_.:-]+', '_', str(e))}")
        sys.exit(2)
