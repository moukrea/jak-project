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
ABSENT_FICHIER = "fichier-absent"
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


def stamp_seen(path=None, now=None, pid=None):
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
            json.dump({"ts": now, "pid": int(pid or os.getpid())}, fh)
        os.replace(tmp, path)
        return True
    except OSError:
        return False


def read_seen(path=None):
    path = seen_file_path() if path is None else path
    try:
        with open(path, "r") as fh:
            data = json.load(fh)
        return int(data.get("ts") or 0), "wake-gate"
    except (OSError, ValueError, TypeError, AttributeError):
        return 0, "-"


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
    rel = probe(state_file=state_file, record=record, proc_root=proc_root, freeze=False)
    return rel["alive"], rel


def one_line(rel):
    return ("superviseur=%s pid=%s why=%s derniere_reponse=%s depuis=%ss"
            % ("vivant" if rel["alive"] else "mort", rel["pid"], rel["why"],
               rel["last_response_ts"], rel["since_last_response_s"]))


if __name__ == "__main__":
    import sys
    r = probe()
    json.dump(r, sys.stdout, indent=1, sort_keys=True)
    sys.stdout.write("\n")
