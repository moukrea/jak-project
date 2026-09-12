#!/usr/bin/env python3
"""lib/impossible.py — LE SEUL LECTEUR de l'etat nomme « preuve impossible ».

POURQUOI CE FICHIER EXISTE. `lib/proof_impossible.sh` ECRIT depuis le 12/09 un etat nomme a
cote de proof.txt quand aucune preuve n'etait possible : binaire absent, appareil absent,
verrou de deploiement tenu au-dela de la borne. Il etait lu par UN recensement, celui de
l'item qui l'avait cree. Ni la porte de fermeture, ni `autoport status`, ni le digest de
l'owner ne le regardaient. Le constructeur a tenu `.autoport/.deploy-in-progress` 6 h 38 le
12/09 : l'etat etait sur le disque, personne ne l'a lu. Un etat nomme que personne ne lit vaut
exactement le silence qu'il remplace.

CE QU'IL FAIT, ET CE QU'IL NE FAIT PAS. Il LIT, il NOMME, il PURGE ; il ne juge pas et il
n'ecrit jamais dans proof.txt ni dans l'etat lui-meme. Les deux lecteurs — `orchestrator.close_gate` (GATE -1) et
`backlog.status_report` — passent par ici, de sorte qu'il n'existe qu'UNE definition de ce
qu'est une preuve impossible, comme il n'existe qu'une definition du territoire moteur.

L'ETAT PERIME NE COMPTE PAS. Un etat « impossible » qu'une course ULTERIEURE a rendu caduc —
`proof.txt` ecrit APRES lui — n'est plus debout. Sans cette regle, un bras d'ablation
impossible en debut d'essai bloquerait pour toujours un item dont la course armee a ensuite
abouti.

L'AGE EST UNE GRANDEUR, PAS UN DETAIL. Une impossibilite de 30 secondes et une de six heures
ne se lisent pas pareil. On publie donc DEUX durees separement :
  * `since_s`     depuis quand le harnais ne peut plus mesurer cet item ;
  * `lock_held_s` depuis quand le verrou de deploiement est tenu, quand son pid REPOND encore
                  au moment de la lecture. `-1` quand la cause n'est pas un verrou vivant :
                  on ne fabrique jamais une duree qu'on n'a pas mesuree.
"""
from __future__ import annotations

import os
import sys
import time

# Les deux bras d'une preuve : l'etat livre et son ablation. Chacun porte son propre etat
# nomme, et chacun est rendu caduc par SON propre proof.txt, jamais par celui de l'autre.
SUFFIXES = ("", "-off")

# Les douze cles que `lib/proof_impossible.sh` ecrit. Un etat qui n'en porte pas douze est
# degenere : on le dit, on ne le repare pas.
KEYS = (
    "proof_impossible",
    "proof_impossible_id",
    "proof_impossible_reason",
    "proof_impossible_detail",
    "proof_impossible_wait_s",
    "proof_impossible_wait_max_s",
    "proof_impossible_busy_why",
    "proof_impossible_lock_pid",
    "proof_impossible_lock_alive",
    "proof_impossible_lock_age_s",
    "proof_impossible_at",
    "proof_impossible_exit",
)


def parse(text):
    """Les `cle=valeur` d'un etat nomme, derniere valeur gagnante."""
    out = {}
    for line in (text or "").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def _num(d, key, default=-1):
    try:
        return int(str(d.get(key, "")).strip())
    except (TypeError, ValueError):
        return default


def pid_alive(pid):
    """Le pid REPOND-il, maintenant. Un verrou dont le pid est mort ne tient rien."""
    try:
        n = int(str(pid).strip())
    except (TypeError, ValueError):
        return False
    if n <= 0:
        return False
    try:
        os.kill(n, 0)
    except ProcessLookupError:
        return False
    except PermissionError:                     # vivant, mais pas a nous
        return True
    except OSError:
        return False
    return True


# ====================================================== LE SEUL ENDROIT QUI NOMME UN BRAS ===
# NOMMAGE/un-seul-endroit
# NOM DE FICHIER DIVERGENT, MESURE LE 12/09 : `lib/proof_run.sh` ecrit `proof$SUF-wait.txt` —
# donc `proof-off-wait.txt` pour l'ablation — et DEUX recensements lisaient un `proof-wait.txt`
# code EN DUR. L'attente du bras d'ablation n'etait donc lue par personne, dans une porte qui
# venait de passer au vert. Un nom fabrique a deux endroits diverge en silence : il n'y en a
# plus qu'un. Les lecteurs passent par ici ; l'ecrivain VERIFIE a chaque course que le fichier
# qu'il vient d'ecrire porte bien le nom que ce module derive, et refuse de continuer sinon.
KINDS = {
    "proof": ".txt",                 # la preuve elle-meme
    "wait": "-wait.txt",             # l'attente de CETTE course (verrou, build en cours)
    "impossible": "-impossible.txt",  # l'etat nomme « preuve impossible »
    "engine": "-engine.log",         # le journal brut du moteur
    "census": "-census.log",         # le journal du recensement de harnais
    "env": "-env.txt",               # l'environnement RELU du processus mesure (bras x86)
    "teardown": "-teardown-fin.txt",  # ce que le teardown de FIN de course a efface (appareil)
}


def arm_suffix(armed):
    """Le suffixe du bras, derive de l'unique chose que le recensement recoit : `armed`."""
    try:
        a = int(str(armed).strip())
    except (TypeError, ValueError):
        a = 1
    return "" if a else "-off"


def arm_name(kind, suffix=""):
    """`proof<suffixe><extension>` — le nom, et rien que le nom."""
    try:
        ext = KINDS[kind]
    except KeyError:
        raise KeyError("genre de fichier inconnu : %r (connus : %s)"
                       % (kind, ",".join(sorted(KINDS))))
    suf = suffix or ""
    if suf not in SUFFIXES:
        raise ValueError("bras inconnu : %r (connus : %s)"
                         % (suf, ",".join(x or "''" for x in SUFFIXES)))
    return "proof%s%s" % (suf, ext)


def arm_path(reports_dir, item_id, kind, suffix=""):
    return os.path.join(reports_dir, item_id, arm_name(kind, suffix))


def state_path(reports_dir, item_id, suffix=""):
    return arm_path(reports_dir, item_id, "impossible", suffix)


def proof_path(reports_dir, item_id, suffix=""):
    return arm_path(reports_dir, item_id, "proof", suffix)


def wait_path(reports_dir, item_id, suffix=""):
    """L'attente de la course de CE bras. Le bras d'ablation est inclus : c'est LUI qui etait
    lu par personne."""
    return arm_path(reports_dir, item_id, "wait", suffix)


def _mtime(path):
    try:
        return os.path.getmtime(path)
    except OSError:
        return -1.0


def _superseded(reports_dir, item_id, suffix, stamp):
    """Une course ULTERIEURE a-t-elle produit la preuve que cet etat disait impossible."""
    pf = proof_path(reports_dir, item_id, suffix)
    try:
        if os.path.getsize(pf) <= 0:
            return False
    except OSError:
        return False
    return _mtime(pf) >= stamp


def read(reports_dir, item_id, now=None, since=0.0):
    """L'etat nomme DEBOUT de cet item, ou `None`.

    `since` : ne rendre que les etats ecrits a partir de cet instant (epoch). La porte de
    fermeture s'en sert pour n'accepter que l'impossibilite de l'essai EN COURS — un etat
    laisse par un essai precedent ne doit pas requalifier indefiniment les suivants.
    """
    now = time.time() if now is None else now
    best = None
    for suf in SUFFIXES:
        p = state_path(reports_dir, item_id, suf)
        stamp = _mtime(p)
        if stamp < 0:
            continue
        if stamp + 1.0 < since:
            continue
        if _superseded(reports_dir, item_id, suf, stamp):
            continue
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                raw = fh.read()
        except OSError:
            continue
        d = parse(raw)
        st = {
            "item": item_id,
            "arm": "ablation" if suf else "livre",
            "suffix": suf,
            "file": os.path.relpath(p, reports_dir),
            "mtime": stamp,
            "keys": sum(1 for k in KEYS if k in d),
            "reason": d.get("proof_impossible_reason") or "inconnue",
            "detail": d.get("proof_impossible_detail") or "-",
            "at": d.get("proof_impossible_at") or "-",
            "busy_why": d.get("proof_impossible_busy_why") or "-",
            "wait_s": _num(d, "proof_impossible_wait_s"),
            "wait_max_s": _num(d, "proof_impossible_wait_max_s"),
            "lock_pid": (d.get("proof_impossible_lock_pid") or "-").strip(),
            "lock_age_s": _num(d, "proof_impossible_lock_age_s"),
            "exit": _num(d, "proof_impossible_exit"),
        }
        # DEPUIS QUAND LE HARNAIS NE PEUT PLUS MESURER. Mesure sur l'horloge du fichier, pas
        # sur la date qu'il porte : une date de texte peut etre fausse, un mtime non.
        st["since_s"] = max(0, int(now - stamp))
        # DEPUIS QUAND LE VERROU EST TENU — seulement si son pid REPOND ENCORE, maintenant.
        # Sinon `-1` : la cause a peut-etre disparu, et inventer sa duree serait la meme faute
        # que le compteur publie sans site d'ecriture.
        st["lock_alive_now"] = 1 if pid_alive(st["lock_pid"]) else 0
        st["lock_held_s"] = (st["lock_age_s"] + st["since_s"]
                             if st["lock_alive_now"] and st["lock_age_s"] >= 0 else -1)
        if best is None or st["mtime"] > best["mtime"]:
            best = st
    return best


# ============================================================= PURGE/etat-perime ============
# RIEN NE PURGEAIT UN ETAT DEBOUT (signalement du 12/09). `lib/proof_run.sh` n'efface l'etat
# qu'a sa PROPRE relance, sur le MEME item et le MEME bras. Un item abandonne en cours de route
# — la file passe au suivant, le superviseur change d'avis, la machine revient — gardait donc
# son etat pour toujours, et `autoport status` continuait d'annoncer a l'owner une impossibilite
# perimee dont l'age grandissait tout seul.
#
# UN ETAT SE PURGE DES QU'IL NE DECRIT PLUS LE PRESENT, et pour une raison NOMMEE :
#   course-aboutie      une course ULTERIEURE a produit le proof.txt que cet etat disait
#                       impossible — le lecteur l'ignorait deja, le disque le perd enfin ;
#   changement-d-item   le harnais mesure un AUTRE item : plus personne n'essaie celui-la ;
#   changement-de-bras  le bras que cet etat decrit est en train d'etre RE-MESURE ;
#   essai-precedent     l'etat est anterieur a l'essai en cours (la meme borne `since` que la
#                       porte de fermeture applique deja pour ne pas requalifier a l'infini).
#
# CE QUI N'EST JAMAIS PURGE : l'AUTRE bras de l'item en cours. Une ablation impossible pendant
# qu'on mesure le bras livre reste debout — sinon un essai brulerait pour une machine
# indisponible que plus rien ne nommerait, exactement le defaut du 12/09.
#
# LA PURGE LAISSE UNE TRACE. Un etat efface sans journal, c'est une information qui disparait
# une deuxieme fois : chaque purge ecrit une ligne dans `logs/impossible-purges.log`, avec sa
# raison et l'age de ce qu'elle a retire. C'est ce journal qui permet de publier le compte de
# purges A COTE du compte d'etats encore debout — un zero d'etats debout se lit « rien en
# cours », jamais « rien verifie ».
PURGE_REASONS = ("course-aboutie", "changement-d-item", "changement-de-bras", "essai-precedent")


def purge_journal_path(reports_dir):
    """Le journal des purges. A cote des rapports, jamais dedans : `reports/<id>/` appartient
    aux items, et un fichier de plus y serait lu comme un item par `read_all`."""
    return os.path.join(os.path.dirname(os.path.abspath(reports_dir)), "logs",
                        "impossible-purges.log")


def scan(reports_dir):
    """Tous les etats nommes PRESENTS sur le disque, purgeables ou non : (item, bras, chemin,
    mtime). C'est le denominateur — sans lui, « 0 purge » et « rien a purger » se confondent."""
    out = []
    try:
        entries = sorted(os.listdir(reports_dir))
    except OSError:
        return out
    for iid in entries:
        for suf in SUFFIXES:
            p = state_path(reports_dir, iid, suf)
            stamp = _mtime(p)
            if stamp >= 0:
                out.append((iid, suf, p, stamp))
    return out


def purge_reason(reports_dir, item_id, suffix, stamp, current_item=None,
                 current_suffix=None, since=0.0):
    """Pourquoi cet etat ne decrit plus le present, ou `""` s'il le decrit encore."""
    if _superseded(reports_dir, item_id, suffix, stamp):
        return "course-aboutie"
    if current_item is not None and item_id != current_item:
        return "changement-d-item"
    if (current_item is not None and current_suffix is not None
            and suffix != current_suffix):
        return ""                      # l'AUTRE bras de l'item en cours : jamais purge
    if (current_item is not None and current_suffix is not None
            and suffix == current_suffix):
        return "changement-de-bras"
    if since and stamp + 1.0 < since:
        return "essai-precedent"
    return ""


def purge(reports_dir, current_item=None, current_suffix=None, since=0.0, now=None,
          journal=True):
    """Retire les etats qui ne decrivent plus le present. Rend `{"purged": [...],
    "standing": [...]}` — les DEUX comptes, separement, jamais leur difference."""
    now = time.time() if now is None else now
    purged, standing = [], []
    for iid, suf, p, stamp in scan(reports_dir):
        why = purge_reason(reports_dir, iid, suf, stamp, current_item=current_item,
                           current_suffix=current_suffix, since=since)
        rec = {"item": iid, "arm": "ablation" if suf else "livre", "suffix": suf,
               "file": os.path.relpath(p, reports_dir), "age_s": max(0, int(now - stamp)),
               "reason": why or "-"}
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                rec["cause"] = parse(fh.read()).get("proof_impossible_reason") or "inconnue"
        except OSError:
            rec["cause"] = "inconnue"
        if not why:
            standing.append(rec)
            continue
        try:
            os.remove(p)
        except OSError as exc:                                  # noqa: BLE001
            rec["reason"] = "echec-de-purge"
            rec["cause"] = "%s: %s" % (type(exc).__name__, exc)
            standing.append(rec)
            continue
        purged.append(rec)
    if journal and purged:
        _write_journal(reports_dir, purged, now)
    return {"purged": purged, "standing": standing}


def _write_journal(reports_dir, purged, now):
    """Une ligne par etat retire, en ajout seul. Ce qu'on efface se raconte."""
    path = purge_journal_path(reports_dir)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now))
        with open(path, "a", encoding="utf-8") as fh:
            for rec in purged:
                fh.write("%s item=%s arm=%s file=%s reason=%s age_s=%d cause=%s\n"
                         % (stamp, rec["item"], rec["arm"], rec["file"], rec["reason"],
                            rec["age_s"], str(rec["cause"]).replace(" ", "_")[:120]))
    except OSError:
        pass                          # un journal illisible ne doit pas empecher la purge


def purge_counts(reports_dir):
    """(purges journalisees depuis toujours, par raison). Le journal est la seule memoire d'un
    etat retire : sans lui on ne saurait pas distinguer « rien a purger » de « jamais purge »."""
    total, par_raison = 0, {}
    try:
        with open(purge_journal_path(reports_dir), encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if " reason=" not in line:
                    continue
                total += 1
                why = line.split(" reason=", 1)[1].split(" ", 1)[0].strip()
                par_raison[why] = par_raison.get(why, 0) + 1
    except OSError:
        pass
    return total, par_raison


def standing(reports_dir, now=None):
    """Les etats encore DEBOUT, tous items confondus — le compte que le livrable demande de
    publier A COTE de celui des purges."""
    now = time.time() if now is None else now
    out = []
    for iid, suf, p, stamp in scan(reports_dir):
        if _superseded(reports_dir, iid, suf, stamp):
            continue
        out.append({"item": iid, "arm": "ablation" if suf else "livre",
                    "file": os.path.relpath(p, reports_dir),
                    "age_s": max(0, int(now - stamp))})
    return out


def read_all(reports_dir, item_ids=None, now=None, since=0.0):
    """Tous les etats debout, par id d'item, du plus ancien au plus recent."""
    now = time.time() if now is None else now
    if item_ids is None:
        try:
            item_ids = sorted(os.listdir(reports_dir))
        except OSError:
            item_ids = []
    out = {}
    for iid in item_ids:
        st = read(reports_dir, iid, now=now, since=since)
        if st is not None:
            out[iid] = st
    return dict(sorted(out.items(), key=lambda kv: -kv[1]["since_s"]))


def human(seconds):
    """Une duree dans les mots de l'owner. `-1` n'est pas une duree : on le dit."""
    try:
        s = int(seconds)
    except (TypeError, ValueError):
        return "inconnu"
    if s < 0:
        return "inconnu"
    if s < 90:
        return "%d s" % s
    if s < 5400:
        return "%d min" % (s // 60)
    return "%d h %02d" % (s // 3600, (s % 3600) // 60)


# Les paliers du digest. Le digest de l'owner se reveille quand quelque chose a BOUGE ; sans
# palier, une duree qui avance d'une seconde le reveillerait a chaque appel et il n'y aurait
# plus de digest du tout. Avec eux il se reveille a l'apparition, puis quand l'impossibilite
# DURE vraiment — ce qui est precisement l'information de six heures qu'on a ratee le 12/09.
PALIERS = ((300, "moins de 5 min"), (1800, "moins de 30 min"),
           (7200, "moins de 2 h"), (None, "plus de 2 h"))


def bucket(seconds):
    try:
        s = int(seconds)
    except (TypeError, ValueError):
        return "inconnu"
    if s < 0:
        return "inconnu"
    for borne, nom in PALIERS:
        if borne is None or s < borne:
            return nom
    return "plus de 2 h"


def cause(st):
    """La cause, NOMMEE, avec son age. Jamais « pas de preuve »."""
    if not st:
        return "-"
    bout = "%s (%s)" % (st["reason"], st["detail"]) if st["detail"] != "-" else st["reason"]
    return bout[:300]


def lines(st, feature=None):
    """Le texte rendu a l'owner : la cause, depuis quand, et le verrou s'il tient encore.

    L'AGE Y EST UN PALIER, PAS UNE SECONDE, et c'est deliberé. Ce texte est RELU EN BOUCLE :
    `watch.py` le rend toutes les quelques secondes et reveille le superviseur des qu'il
    change, `auto_push_builds.sh` en tire le digest de l'owner. Une duree a la seconde le
    ferait changer a chaque tour — un signal qui crie en permanence ne se lit plus, et on
    aurait remplace le silence du 12/09 par du bruit. Le palier ne bouge que quand
    l'impossibilite DURE vraiment.

    LA DUREE EXACTE N'EST PAS PERDUE POUR AUTANT : l'INSTANT ou l'etat a ete ecrit est
    imprime tel quel, immuable, et la porte de fermeture — ecrite UNE FOIS par essai, jamais
    relue en boucle — publie elle la duree au format « 6 h 38 ».
    """
    if not st:
        return []
    out = ["- %s" % (feature or st["item"]),
           "  Cause : %s" % cause(st),
           "  Impossible depuis : %s (etat ecrit le %s, bras %s)"
           % (bucket(st["since_s"]), st["at"], st["arm"])]
    if st["lock_held_s"] >= 0:
        out.append("  Verrou de deploiement : pid %s, VIVANT, tenu depuis %s"
                   % (st["lock_pid"], bucket(st["lock_held_s"])))
    elif st["lock_pid"] not in ("-", ""):
        out.append("  Verrou de deploiement : pid %s, ne repond plus" % st["lock_pid"])
    if st["wait_s"] > 0:
        out.append("  Attendu : %s (borne %s)"
                   % (human(st["wait_s"]), human(st["wait_max_s"])))
    return out


def digest_lines(st, feature=None):
    """La MEME chose, l'age remplace par son palier : ce qui entre dans le hash du digest."""
    if not st:
        return []
    return ["- %s" % (feature or st["item"]),
            "  Cause : %s" % cause(st),
            "  Impossible depuis : %s" % bucket(st["since_s"]),
            "  Verrou tenu depuis : %s" % (bucket(st["lock_held_s"])
                                           if st["lock_held_s"] >= 0 else "-")]

# ==================================================================== appelable depuis bash ==
# `lib/proof_run.sh` est en bash et doit nommer les memes fichiers que les lecteurs python.
# Plutot que de recopier la regle dans un deuxieme langage — c'est cette recopie qui a rendu
# l'attente du bras d'ablation illisible — il APPELLE ce module :
#     python3 lib/impossible.py name wait -off        -> proof-off-wait.txt
#     python3 lib/impossible.py purge --reports D --item ID --arm -off
def _cli(argv):
    """Ecrit a la main, sans argparse : un suffixe de bras COMMENCE par un tiret (`-off`) et
    argparse le lit comme une option. Un outil qui ne sait pas nommer le bras d'ablation est
    exactement le defaut que ce module corrige."""
    def opt(name, defaut=None):
        return argv[argv.index(name) + 1] if name in argv[:-1] else defaut
    cmd = argv[0] if argv else ""
    if cmd == "name" and len(argv) >= 2:
        print(arm_name(argv[1], argv[2] if len(argv) > 2 else ""))
        return 0
    if cmd == "purge":
        r = purge(opt("--reports", ".autoport/reports"), current_item=opt("--item"),
                  current_suffix=opt("--arm"), since=float(opt("--since", 0.0) or 0.0))
        for rec in r["purged"]:
            print("purge %s/%s (%s, %ds) : %s"
                  % (rec["item"], rec["file"], rec["reason"], rec["age_s"], rec["cause"]),
                  file=sys.stderr)
        print("purged=%d standing=%d" % (len(r["purged"]), len(r["standing"])))
        return 0
    if cmd == "standing":
        deb = standing(opt("--reports", ".autoport/reports"))
        print("standing=%d" % len(deb))
        for rec in deb:
            print("%s %s %ss" % (rec["item"], rec["file"], rec["age_s"]))
        return 0
    print("usage: impossible.py name <%s> [bras] | purge [--reports D] [--item ID] "
          "[--arm BRAS] [--since T] | standing [--reports D]" % "|".join(sorted(KINDS)),
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(_cli(sys.argv[1:]))
