#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Le superviseur est-il un LECTEUR VIVANT ? Une grandeur, pas une croyance.

Pourquoi ce fichier existe (owner, 22/09 : « Pourquoi tu réagis plus a mes feedbacks sur
Linear »). Toute la chaine marchait : linear_sync recopiait ses commentaires dans
`owner_feedback`, wake_gate inserait le bloc « RETOURS DE L'OWNER SANS REPONSE » en tete de
chaque reveil, la synchro criait « À TRAITER » 7 585 fois. Le seul maillon casse etait le
LECTEUR, et personne ne le regardait : `grep -i linear .autoport/autoport` ne rend rien.

DEUX MORTS, PAS UNE. Le releve du 22/09 les porte toutes les deux :

  * LA MORT FRANCHE. `.supervisor-terminal.json` designait encore le pid 68980, mort, et le
    tty qu'il nomme (/dev/pts/3) faisait tourner un `codex --yolo resume` depuis quatre jours.
  * LE GEL. La session a rendu sa derniere reponse a 09:50:56 ; le reveil de 10:20:48 est
    reste EN FILE sans jamais etre traite ; le processus n'est mort qu'a 11:07:54. Pendant ces
    77 minutes, le pid etait VIVANT et la file n'avancait pas. Un controle qui ne regarde que
    le pid serait reste MUET tout ce temps — c'est exactement
    `feedback_live_oracle_can_be_frozen_anchor_on_its_own_ran_timestamp` : on ancre sur
    l'horodatage que l'oracle pose QUAND IL TOURNE, jamais sur son existence.

CE QUE CE MODULE REFUSE DE FAIRE

1. `kill -0` (feedback_kill_0_succeeds_on_a_zombie) : il REUSSIT sur un zombie. On lit l'etat
   au champ 3 de /proc/<pid>/stat, et `Z` vaut mort.
2. Croire un pid nu (feedback_ppid_is_read_after_exec...) : les pids se recyclent. Le fichier
   note le `start` (champ 22 de /proc/<pid>/stat) : un pid vivant dont le starttime differe
   n'est pas notre superviseur, c'est un inconnu qui a herite du numero.
3. Croire un processus vivant : voir LE GEL ci-dessus.

Toutes les valeurs de sortie sont des jetons SANS ESPACE : `proof.txt` jette toute valeur qui
en contient (feedback_proof_txt_drops_any_value_containing_a_space), et ce releve y va tel quel.
"""

from __future__ import annotations

import json
import os
import time

AP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(AP)

# Ecrit par `supervisor_terminal.py` a l'ouverture de `run-supervisor.sh` : {pid, start, tty}.
DEFAULT_STATE_FILE = os.path.join(AP, ".supervisor-terminal.json")
# Pose par `wake_gate.py` QUAND la session du superviseur traite reellement un reveil.
SEEN_FILE = os.path.join(AP, ".supervisor-seen.json")
LAUNCHES = os.path.join(AP, "logs", "supervisor-launches.jsonl")

# Au-dela de ce silence, un processus vivant n'est plus un LECTEUR. Le superviseur est reveille
# toutes les 15 a 30 minutes (wake_gate) : une heure sans un seul reveil traite ne s'explique
# pas par la charge.
STALE_DEFAULT_S = 3600

VIVANT = "vivant"
# ABSENT DU REGISTRE N'EST PAS MORT (superviseur, releve de terrain du 22/09) : la veille rendait
# `lecteur=MORT (fichier-absent)` pendant que la session superviseur TOURNAIT et lisait les
# retours — elle n'avait simplement pas ete ouverte par `run-supervisor.sh`, donc personne ne
# l'avait inscrite. « Personne d'inscrit » et « l'inscrit est mort » sont deux etats, et le
# releve les nomme separement.
ABSENT_REGISTRE = "absent-du-registre"
ABSENT_FICHIER = ABSENT_REGISTRE          # ancien nom, garde pour les appelants
# Un lecteur qui REPOND se fait reconnaitre par ce qu'il fait, pas par son lanceur : le crochet
# de prompt de SA session pose le tampon avec le pid + starttime de la session (`self_declare`).
VIVANT_HORS_REGISTRE = "vivant-hors-registre"
HORS_REGISTRE_MORT = "hors-registre-mort"
HORS_REGISTRE_GELE = "hors-registre-gele"
HORS_REGISTRE_SANS_PREUVE = "hors-registre-sans-preuve"
ILLISIBLE = "json-illisible"
SANS_PID = "pid-absent-du-fichier"
PID_MORT = "pid-mort"
ZOMBIE = "zombie"
PID_RECYCLE = "starttime-different"
GELE = "gele-sans-reponse"

_TICKS = float(os.sysconf("SC_CLK_TCK")) if hasattr(os, "sysconf") else 100.0


# LES CHEMINS SE SURCHARGENT PAR L'ENVIRONNEMENT. La porte de l'item doit pouvoir SEMER un
# superviseur mort et un superviseur vivant sans ecrire dans l'etat du harnais qui tourne :
# poser un faux `.supervisor-terminal.json` le temps d'une mesure ferait refuser le prochain
# `run-supervisor.sh`. On ne mesure jamais en deplacant ce qu'on mesure.
def _chemin(cle, defaut):
    return os.environ.get(cle) or defaut


def state_file_path():
    return _chemin("AUTOPORT_SUPERVISOR_TERMINAL", DEFAULT_STATE_FILE)


def seen_file_path():
    return _chemin("AUTOPORT_SUPERVISOR_SEEN", SEEN_FILE)


def stale_seconds(env=None):
    env = os.environ if env is None else env
    try:
        v = int(env.get("AUTOPORT_SUPERVISOR_STALE_S", "") or STALE_DEFAULT_S)
    except (TypeError, ValueError):
        return STALE_DEFAULT_S
    return v if v > 0 else STALE_DEFAULT_S


def boot_epoch(proc_root="/proc"):
    try:
        with open("%s/stat" % proc_root, "r") as fh:
            for line in fh:
                if line.startswith("btime "):
                    return int(line.split()[1])
    except (OSError, ValueError, IndexError):
        pass
    return 0


def read_proc_stat(pid, proc_root="/proc"):
    """Champs utiles de /proc/<pid>/stat, ou None si le pid n'existe pas.

    Le champ 2 (`comm`) est entre parentheses et peut contenir espaces ET parentheses : on
    coupe au DERNIER ')' , jamais par un `split()` sur toute la ligne.
    """
    try:
        with open("%s/%d/stat" % (proc_root, int(pid)), "r") as fh:
            raw = fh.read()
    except (OSError, ValueError):
        return None
    cut = raw.rfind(")")
    if cut < 0:
        return None
    rest = raw[cut + 2:].split()
    if len(rest) < 20:
        return None
    try:
        tty_nr = int(rest[3])        # champ 7
        starttime = int(rest[19])    # champ 22
    except (ValueError, IndexError):
        return None
    # rest[0] = champ 3 (state), donc champ N = rest[N-3].
    return {"pid": int(pid), "comm": raw[raw.find("(") + 1:cut], "state": rest[0],
            "ppid": rest[1], "tty_nr": tty_nr, "starttime": starttime}


def tty_name(tty_nr):
    if not tty_nr:
        return "-"
    major, minor = (tty_nr >> 8) & 0xFF, (tty_nr & 0xFF) | ((tty_nr >> 20) << 8)
    return "/dev/pts/%d" % minor if major == 136 else "tty-%d-%d" % (major, minor)


def cmdline_of(pid, proc_root="/proc"):
    try:
        with open("%s/%d/cmdline" % (proc_root, int(pid)), "rb") as fh:
            parts = [p for p in fh.read().split(b"\0") if p]
    except (OSError, ValueError):
        return "-"
    if not parts:
        return "-"
    return os.path.basename(parts[0].decode("utf-8", "replace")).replace(" ", "_") or "-"


def who_holds_tty(tty, proc_root="/proc"):
    """Qui tourne sur ce terminal AUJOURD'HUI ? Sert a NOMMER le cas du 22/09 (pts/3 = codex)."""
    if not tty or not tty.startswith("/dev/pts/"):
        return "-"
    try:
        want = "/dev/pts/%d" % int(tty.rsplit("/", 1)[1])
    except ValueError:
        return "-"
    try:
        pids = sorted(int(d) for d in os.listdir(proc_root) if d.isdigit())
    except OSError:
        return "-"
    for pid in pids:
        st = read_proc_stat(pid, proc_root=proc_root)
        if st and st["tty_nr"] and tty_name(st["tty_nr"]) == want:
            return cmdline_of(pid, proc_root=proc_root)
    return "-"


def _as_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def in_supervisor_tree(pid=None, state_file=None, proc_root="/proc", record=None):
    """Ce processus-ci descend-il du superviseur DECLARE ? (pid + starttime, jamais le pid nu)

    C'est ce qui permet de dater « la derniere reponse effective » sans se tromper de session.
    Gater le tampon sur la FORME du prompt (un reveil automatique fait plus de 400 caracteres)
    marcherait tant que le superviseur est pilote par le cron — et declarerait GELE, au bout
    d'une heure, un superviseur que l'owner pilote a la main par messages courts. L'alarme
    partirait alors sur le ticket de l'owner pendant qu'il est en train d'y ecrire.
    L'ascendance, elle, ne depend d'aucune heuristique de texte.

    PLUS UTILISE POUR LE TAMPON depuis le 23/09 (`stamp_reader`) : un juge lance depuis le
    terminal du superviseur DESCEND de lui, et l'ascendance seule le prenait pour lui. Garde pour
    les temoins d'ascendance de harness-supervisor-death-is-an-alarm.
    """
    state_file = state_file_path() if state_file is None else state_file
    data = record
    if data is None:
        try:
            with open(state_file, "r") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            return False
    if not isinstance(data, dict):
        return False
    cible = _as_int(data.get("pid"))
    if not cible:
        return False
    attendu = _as_int(data.get("start"))
    if attendu is None:
        attendu = _as_int(data.get("starttime"))
    st_cible = read_proc_stat(cible, proc_root=proc_root)
    if st_cible is None or st_cible["state"] == "Z":
        return False
    if attendu is not None and attendu >= 0 and attendu != st_cible["starttime"]:
        return False
    cur = os.getpid() if pid is None else int(pid)
    for _ in range(64):                      # borne : une ascendance ne boucle pas, un /proc si
        if cur == cible:
            return True
        if cur <= 1:
            return False
        st = read_proc_stat(cur, proc_root=proc_root)
        if st is None:
            return False
        cur = _as_int(st["ppid"]) or 0
    return False


def is_worker(env=None):
    """Une session d'ESSAI (worker) n'est pas un lecteur des retours de l'owner. L'orchestrateur
    pose `AUTOPORT_ATTEMPT_ID` / `AUTOPORT_PHASE_ID` sur chaque worker ; `AUTOPORT_ROLE` ne
    separe RIEN (un worker en herite `supervisor` de celui qui a lance l'orchestrateur)."""
    env = os.environ if env is None else env
    return bool(env.get("AUTOPORT_ATTEMPT_ID") or env.get("AUTOPORT_PHASE_ID"))


SESSION_COMMS = ("claude", "codex")


def session_process(pid=None, env=None, proc_root="/proc"):
    """Le processus de la SESSION qui a declenche ce crochet : le plus PROCHE ascendant dont le
    `comm` est celui d'une CLI d'agent ; a defaut, `CLAUDE_PID` s'il est vivant ET ascendant.
    Le pid du crochet lui-meme ne vaut rien : il meurt dans la seconde. Rend le releve /proc,
    ou None.

    L'ORDRE COMPTE (harness-supervisor-reader-must-be-the-supervisor, 23/09). `CLAUDE_PID` s'HERITE :
    l'orchestrateur du 23/09 portait encore celui du superviseur du 22 (3057237). Une session
    lancee depuis le terminal du superviseur (un juge `claude -p`, un codex) qui croirait la
    variable d'abord se ferait passer pour le superviseur lui-meme. L'ascendant le plus proche,
    lui, ne s'herite pas."""
    env = os.environ if env is None else env
    cur = os.getpid() if pid is None else int(pid)
    chaine = []
    for _ in range(64):
        if cur <= 1:
            break
        st = read_proc_stat(cur, proc_root=proc_root)
        if st is None:
            break
        if st["comm"] in SESSION_COMMS and st["state"] != "Z":
            return st
        chaine.append(cur)
        cur = _as_int(st["ppid"]) or 0
    dit = _as_int(env.get("CLAUDE_PID"))
    if dit and dit > 1 and dit in chaine:
        st = read_proc_stat(dit, proc_root=proc_root)
        if st is not None and st["state"] != "Z":
            return st
    return None


# LA PREUVE POSITIVE D'ETRE LE SUPERVISEUR (harness-supervisor-reader-must-be-the-supervisor).
# Jusqu'au 23/09, « pas de variable de worker » valait « superviseur » : toute session Claude du
# depot — l'owner a la main, un juge lance sans AUTOPORT_ATTEMPT_ID — tamponnait et eteignait
# l'alarme « superviseur mort » sans avoir lu un seul retour. Quatre preuves, et rien d'autre :
#   registre  la session EST le pid inscrit par `supervisor_terminal.py` (ou la premiere session
#             sous lui, sans autre session entre les deux) ;
#   lanceur   son (pid, starttime) a ete declare par `supervisor.sh` / `codex/supervisor.py`
#             juste avant leur `exec` ;
#   session   son identifiant de conversation a deja ete prouve (un `--resume` a la main du
#             superviseur reste le superviseur) ;
#   reveil    elle traite un reveil de supervision (`wake_gate.est_un_reveil`).
PREUVES = ("registre", "lanceur", "session", "reveil")
NON_DECLARE = "non-declare"
DECLARED_FILE = os.path.join(AP, ".supervisor-declared.json")
SEEN_LOG = os.path.join(AP, "logs", "supervisor-seen.jsonl")
DECLARED_MAX = 64


def declared_file_path():
    return _chemin("AUTOPORT_SUPERVISOR_DECLARED", DECLARED_FILE)


def seen_log_path():
    return _chemin("AUTOPORT_SUPERVISOR_SEEN_LOG", SEEN_LOG)


def read_declared(path=None):
    path = declared_file_path() if path is None else path
    try:
        with open(path, "r") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return []
    return [d for d in data if isinstance(d, dict)] if isinstance(data, list) else []


def declare(pid=None, start=None, session="-", via="lanceur", path=None, now=None,
            proc_root="/proc"):
    """Inscrit une identite de superviseur. `start` absent = lu dans /proc (le starttime survit
    a `exec` : le shell du lanceur et la CLI qu'il remplace sont le MEME processus)."""
    path = declared_file_path() if path is None else path
    pid = int(os.getpid() if pid is None else pid)
    if start is None:
        st = read_proc_stat(pid, proc_root=proc_root)
        start = -1 if st is None else st["starttime"]
    session = str(session or "-").replace(" ", "_") or "-"
    rec = {"ts": int(time.time() if now is None else now), "pid": pid, "start": int(start),
           "session": session, "via": str(via)}
    garde = [d for d in read_declared(path)
             if not (d.get("pid") == pid and d.get("start") == int(start))
             and not (session != "-" and d.get("session") == session)]
    garde.append(rec)
    try:
        tmp = "%s.tmp.%d" % (path, os.getpid())
        with open(tmp, "w") as fh:
            json.dump(garde[-DECLARED_MAX:], fh)
        os.replace(tmp, path)
        return True
    except OSError:
        return False


def registry_proves(st, state_file=None, proc_root="/proc"):
    """La session `st` est-elle LE superviseur inscrit ? Egalite (pid + starttime) avec le pid
    inscrit, ou premiere session sous lui : entre elle et lui, aucun processus — lui compris —
    ne doit etre une session. Un juge `claude -p` lance depuis le terminal du superviseur
    DESCEND du superviseur : c'est exactement ce que l'ascendance seule laissait passer."""
    state_file = state_file_path() if state_file is None else state_file
    try:
        with open(state_file, "r") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return False
    if not isinstance(data, dict):
        return False
    cible = _as_int(data.get("pid"))
    attendu = _as_int(data.get("start"))
    if attendu is None:
        attendu = _as_int(data.get("starttime"))
    if not cible:
        return False
    st_cible = read_proc_stat(cible, proc_root=proc_root)
    if st_cible is None or st_cible["state"] == "Z":
        return False
    if attendu is not None and attendu >= 0 and attendu != st_cible["starttime"]:
        return False
    if st["pid"] == cible:
        return True
    cur = _as_int(st["ppid"]) or 0
    for _ in range(64):
        if cur <= 1:
            return False
        up = read_proc_stat(cur, proc_root=proc_root)
        if up is None or up["comm"] in SESSION_COMMS:
            return False
        if cur == cible:
            return True
        cur = _as_int(up["ppid"]) or 0
    return False


def supervisor_proof(env=None, reveil=False, session_id="-", proc_root="/proc",
                     state_file=None, declared=None):
    """Rend (jeton, releve de session). Jeton dans PREUVES = superviseur prouve ; sinon le
    REFUS nomme : `worker`, `sans-session`, `non-declare`."""
    env = os.environ if env is None else env
    if is_worker(env):
        return "worker", None
    st = session_process(env=env, proc_root=proc_root)
    if st is None:
        return "sans-session", None
    if registry_proves(st, state_file=state_file, proc_root=proc_root):
        return "registre", st
    sid = str(session_id or "-").replace(" ", "_") or "-"
    liste = read_declared() if declared is None else declared
    for d in liste:
        if d.get("pid") == st["pid"] and d.get("start") == st["starttime"]:
            return "lanceur", st
    if sid != "-" and any(d.get("session") == sid for d in liste):
        return "session", st
    if reveil:
        return "reveil", st
    return NON_DECLARE, st


def _journal_seen(rec, path=None):
    path = seen_log_path() if path is None else path
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a") as fh:
            fh.write(json.dumps(rec, sort_keys=True) + "\n")
    except OSError:
        pass


def stamp_reader(env=None, reveil=False, session_id="-", now=None, proc_root="/proc"):
    """Appele par `wake_gate.py` a CHAQUE prompt de CHAQUE session du depot. Tamponne seulement
    sur preuve positive ; journalise la decision (tampon ou refus) dans `logs/supervisor-seen.jsonl`
    pour que la porte compte une population, pas une croyance. Rend le jeton de `supervisor_proof`.
    """
    env = os.environ if env is None else env
    now = int(time.time() if now is None else now)
    preuve, st = supervisor_proof(env=env, reveil=reveil, session_id=session_id,
                                  proc_root=proc_root)
    sid = str(session_id or "-").replace(" ", "_") or "-"
    rec = {"ts": now, "proof": preuve, "session": sid,
           "pid": st["pid"] if st else 0, "start": st["starttime"] if st else -1,
           "comm": st["comm"] if st else "-", "decision": "refus"}
    if preuve in PREUVES:
        ok = stamp_seen(now=now, pid=st["pid"], start=st["starttime"],
                        via="registre" if preuve == "registre" else "hors-registre",
                        session=sid, comm=st["comm"], proof=preuve)
        # Une preuve acquise se RETIENT : le prochain prompt court de l'owner dans cette session,
        # ou un `--resume` de cette conversation, reste le superviseur sans attendre un reveil.
        if preuve != "lanceur" or sid != "-":
            declare(pid=st["pid"], start=st["starttime"], session=sid, via=preuve, now=now)
        rec["decision"] = "tampon" if ok else "echec-ecriture"
    _journal_seen(rec)
    return preuve


def stamp_seen(path=None, now=None, pid=None, start=None, via="registre", session="-",
               comm="-", proof="-"):
    """« Le superviseur a REELLEMENT traite un reveil a cet instant. »

    Appele par `wake_gate.py` depuis le processus de la session elle-meme, au moment ou elle
    traite le prompt. C'est la seule grandeur qui separe une session qui tourne d'une session
    qui a le prompt EN FILE : le 22/09, le reveil de 10:20:48 n'a jamais ete traite et ce
    fichier serait reste a 09:50.
    Il n'echoue jamais bruyamment : un crochet casse ne doit pas faire taire le superviseur.
    """
    now = int(time.time() if now is None else now)
    path = seen_file_path() if path is None else path
    try:
        tmp = "%s.tmp.%d" % (path, os.getpid())
        with open(tmp, "w") as fh:
            json.dump({"ts": now, "pid": int(pid or os.getpid()),
                       "start": -1 if start is None else int(start), "via": str(via),
                       "session": str(session).replace(" ", "_") or "-",
                       "comm": str(comm).replace(" ", "_") or "-",
                       "proof": str(proof)}, fh)
        os.replace(tmp, path)
        return True
    except OSError:
        return False


def read_seen_record(path=None):
    path = seen_file_path() if path is None else path
    try:
        with open(path, "r") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def read_seen(path=None):
    data = read_seen_record(path)
    try:
        return int(data.get("ts") or 0), ("wake-gate" if data.get("ts") else "-")
    except (TypeError, ValueError):
        return 0, "-"


def _self_declared_verdict(seen, now, stale_s, proc_root="/proc"):
    """Le lecteur HORS REGISTRE : celui dont le tampon porte `via=hors-registre`. Rend
    (why, pid) ; why vaut '-' s'il n'y a pas de tel tampon."""
    if not seen or seen.get("via") != "hors-registre":
        return "-", 0
    if seen.get("proof") not in PREUVES:
        # Tampon d'AVANT le 23/09 (ou d'une session qui n'a rien prouve) : il ne rallume rien.
        return HORS_REGISTRE_SANS_PREUVE, _as_int(seen.get("pid")) or 0
    pid = _as_int(seen.get("pid")) or 0
    start = _as_int(seen.get("start"))
    ts = _as_int(seen.get("ts")) or 0
    st = read_proc_stat(pid, proc_root=proc_root) if pid > 1 else None
    if st is None or st["state"] == "Z":
        return HORS_REGISTRE_MORT, pid
    if start is not None and start >= 0 and start != st["starttime"]:
        return HORS_REGISTRE_MORT, pid          # pid recycle : la session tamponnee est partie
    if not ts or (now - ts) > stale_s:
        return HORS_REGISTRE_GELE, pid
    return VIVANT_HORS_REGISTRE, pid


def last_launch_ts(path=LAUNCHES):
    """Repli : l'heure du dernier LANCEMENT. Ce n'est pas une reponse, et on le dit."""
    ts = 0
    try:
        with open(path, "r") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                v = rec.get("ts")
                if isinstance(v, str):
                    from datetime import datetime
                    try:
                        ts = max(ts, int(datetime.fromisoformat(v).timestamp()))
                    except ValueError:
                        pass
                elif isinstance(v, (int, float)):
                    ts = max(ts, int(v))
    except OSError:
        return 0
    return ts


def probe(state_file=None, now=None, proc_root="/proc", record=None,
          seen_file=None, launches=LAUNCHES, stale_s=None, freeze=True, self_declared=True):
    """Le releve : le superviseur INSCRIT d'abord, puis le lecteur HORS REGISTRE.

    `registry_why` garde toujours le verdict du registre seul ; `self_why` celui du tampon
    hors registre. `why` est le verdict retenu. `self_declared=False` ne regarde que le
    registre (c'est ce que veut `supervisor_terminal.py` pour refuser un second lanceur).
    """
    now = time.time() if now is None else now
    stale_s = stale_seconds() if stale_s is None else stale_s
    seen_file = seen_file_path() if seen_file is None else seen_file
    out = _probe_registry(state_file=state_file, now=now, proc_root=proc_root, record=record,
                          seen_file=seen_file, launches=launches, stale_s=stale_s,
                          freeze=freeze)
    out["registry_why"] = out["why"]
    out["self_why"], out["self_pid"] = "-", 0
    if not self_declared:
        return out
    seen = read_seen_record(seen_file)
    out["self_why"], out["self_pid"] = _self_declared_verdict(seen, now, stale_s,
                                                              proc_root=proc_root)
    if out["alive"]:
        return out
    if out["self_why"] == VIVANT_HORS_REGISTRE:
        out["alive"] = True
        out["why"] = VIVANT_HORS_REGISTRE
    elif out["why"] == ABSENT_REGISTRE and out["self_why"] != "-":
        # Personne d'inscrit, mais une session s'etait declaree : c'est ELLE qu'on juge.
        out["why"] = out["self_why"]
    return out


def reader_state(rel):
    """Trois etats, jamais deux : `vivant`, `non-inscrit` (personne d'inscrit ni de declare :
    on ne SAIT PAS s'il y a un lecteur), `mort` (un lecteur connu a disparu ou s'est gele)."""
    if rel.get("alive"):
        return "vivant"
    if rel.get("why") == ABSENT_REGISTRE:
        return "non-inscrit"
    return "mort"


def _probe_registry(state_file=None, now=None, proc_root="/proc", record=None,
                    seen_file=None, launches=LAUNCHES, stale_s=None, freeze=True):
    """Le releve complet. `record` permet de REJOUER un releve archive sans toucher au disque.

    `alive` est la seule grandeur de decision ; `why` la nomme. Rien ici ne suppose : chaque
    champ vient d'une lecture, et un champ qu'on n'a pas su lire vaut -1, jamais 0.
    """
    now = time.time() if now is None else now
    stale_s = stale_seconds() if stale_s is None else stale_s
    state_file = state_file_path() if state_file is None else state_file
    seen_file = seen_file_path() if seen_file is None else seen_file
    out = {"alive": False, "why": ABSENT_FICHIER, "declared": 0, "pid": 0,
           "starttime_declared": -1, "starttime_now": -1, "state": "-", "tty": "-",
           "tty_holder": "-", "tty_matches_pid": 0, "proc_start_epoch": 0,
           "last_response_ts": 0, "last_response_src": "-", "since_last_response_s": -1,
           "stale_s": int(stale_s), "kill0_would_say_alive": 0}

    # L'HORODATAGE DE LA DERNIERE REPONSE : il se lit MEME quand il n'y a pas de superviseur.
    # C'est justement la question de l'owner — « depuis quand plus personne ne repond ? ».
    seen_ts, seen_src = read_seen(seen_file)
    if not seen_ts:
        seen_ts, seen_src = last_launch_ts(launches), "lancement"
    if seen_ts:
        out["last_response_ts"] = seen_ts
        out["last_response_src"] = seen_src
        out["since_last_response_s"] = int(now - seen_ts)
    else:
        out["last_response_src"] = "inconnu"

    data = record
    if data is None:
        if not os.path.exists(state_file):
            return out
        try:
            with open(state_file, "r") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            return dict(out, declared=1, why=ILLISIBLE)
    if not isinstance(data, dict):
        return dict(out, why=ILLISIBLE)

    out["declared"] = 1
    pid = _as_int(data.get("pid"))
    if not pid or pid <= 0:
        out["why"] = SANS_PID
        return out
    out["pid"] = pid

    declared_start = _as_int(data.get("start"))
    if declared_start is None:
        declared_start = _as_int(data.get("starttime"))
    out["starttime_declared"] = -1 if declared_start is None else declared_start

    out["tty"] = str(data.get("tty") or "-").replace(" ", "_") or "-"
    out["tty_holder"] = who_holds_tty(out["tty"], proc_root=proc_root)

    st = read_proc_stat(pid, proc_root=proc_root)
    if st is None:
        out["why"] = PID_MORT
        return out
    # LE BRAS CONDAMNE, mesure a cote du bras livre : `kill -0` repond OUI a tout ce qui est
    # dans /proc, zombie compris. On le publie pour que la porte puisse verifier que les deux
    # regles SE SEPARENT quelque part — deux bras toujours d'accord ne prouvent rien.
    out["kill0_would_say_alive"] = 1
    out["starttime_now"] = st["starttime"]
    out["state"] = st["state"]
    out["tty_matches_pid"] = 1 if tty_name(st["tty_nr"]) == out["tty"] else 0
    bt = boot_epoch(proc_root=proc_root)
    if bt:
        out["proc_start_epoch"] = int(bt + st["starttime"] / _TICKS)

    if st["state"] == "Z":
        out["why"] = ZOMBIE
        return out
    # Le starttime NE SE COMPARE QUE S'IL A ETE DECLARE : un fichier ecrit par un lanceur qui
    # ne le note pas ne doit pas faire passer un superviseur vivant pour un pid recycle.
    if declared_start is not None and declared_start >= 0 and declared_start != st["starttime"]:
        out["why"] = PID_RECYCLE
        return out

    # LE GEL. On ne le prononce que si le processus a eu LE TEMPS de repondre : une session qui
    # vient de demarrer n'a encore rien a montrer, et l'accuser serait une alarme par
    # construction. Le plancher est sa propre date de demarrage.
    # `freeze=False` ne garde QUE le verdict structurel (pid + starttime + zombie). C'est ce
    # dont `supervisor_terminal.py` a besoin pour refuser un second superviseur : un lecteur
    # GELE reste un processus qui tient le terminal, et en lancer un deuxieme par-dessus
    # donnerait deux superviseurs sur le meme depot.
    ref = max(out["last_response_ts"], out["proc_start_epoch"])
    if freeze and ref and (now - ref) > stale_s:
        out["why"] = GELE
        out["since_last_response_s"] = int(now - ref)
        return out

    out["alive"] = True
    out["why"] = VIVANT
    return out


def process_alive(state_file=None, record=None, proc_root="/proc"):
    """Le verdict STRUCTUREL seul : ce pid-la tourne-t-il encore ? (zombie exclu, pid recycle
    exclu). Point de production UNIQUE de la regle : `supervisor_terminal.py` en avait sa
    propre copie, sans le zombie — deux regles pour une question, dont une fausse."""
    rel = probe(state_file=state_file, record=record, proc_root=proc_root, freeze=False,
                self_declared=False)
    return rel["alive"], rel


def one_line(rel):
    return ("superviseur=%s pid=%s why=%s derniere_reponse=%s depuis=%ss"
            % (reader_state(rel), rel["pid"] or rel.get("self_pid", 0), rel["why"],
               rel["last_response_ts"], rel["since_last_response_s"]))


if __name__ == "__main__":
    import sys
    if sys.argv[1:2] == ["declare-launcher"]:
        # `supervisor.sh` / `codex/supervisor.py`, juste avant leur `exec` : « ce pid-la sera le
        # superviseur ». Jamais bloquant : un lanceur ne meurt pas d'un fichier illisible.
        declare(pid=int(sys.argv[2]) if len(sys.argv) > 2 else os.getppid(), via="lanceur")
        sys.exit(0)
    r = probe()
    json.dump(r, sys.stdout, indent=1, sort_keys=True)
    sys.stdout.write("\n")
