"""relay — les mots de l'owner dits au superviseur HORS Linear (terminal), recopies ETIQUETES.

Depuis 76594a90bc (2026-09-23 01:23:33 +0200, harness-owner-sla-matches-every-owner-comment),
la synchro garde a la recopie l'identifiant du commentaire Linear (`via: {comment, ticket, at}`).
Un `owner_feedback` SANS `via` ecrit apres cette bascule n'a donc pas ete recopie par la synchro :
c'est un relais du superviseur ecrit a la main, et `owner_sla` le compte NON APPARIE — le
compteur « sans reponse » rougit sur un relais legitime.

Le seul ecrivain d'un relais est `relay()`, derriere `./.autoport/autoport feedback <id> "<mots>"` :
mots verbatim, date du jour, `via: {source: supervisor, at, by}`, consigne refabriquee si
c'est la notre (jamais une consigne ecrite a la main). `census()` compte ce qui a echappe a
la commande ; `backfill()` etiquette une fois les relais existants, seulement si c'est PROUVE.

    python3 .autoport/lib/relay.py --census          # cle=valeur, sans rien ecrire
    python3 .autoport/lib/relay.py --backfill [--apply]
"""

import copy
import datetime
import os
import subprocess
import sys

try:
    from . import backlog as B  # `autoport` importe `lib.backlog` : UNE seule BacklogError
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import backlog as B  # noqa: E402

BASCULE_COMMIT = "76594a90bc"
# Le `date:` du backlog est au JOUR : la fenetre commence le jour de la bascule. Les retours de
# ce jour ecrits AVANT 01:23 ont ete repris par la reprise du meme commit (ils portent un `via`).
BASCULE_DAY = "2026-09-23"
BY = "autoport feedback"
SUPERVISOR_COMMIT_PREFIX = "[autoport/supervisor]"


def relay_via(now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    return {"source": "supervisor", "at": now.isoformat(timespec="seconds"), "by": BY}


def _refresh_prompt(it, ap_dir):
    """La regle de `linear_sync.refresh_prompt` : refabriquer SEULEMENT notre consigne perimee
    (ou absente) ; une consigne ecrite a la main ne s'ecrase jamais (17/09)."""
    st = B.prompt_state(it, ap_dir)
    if st in ("perime", "absent"):
        B.write_prompt(it, ap_dir)
        return "refabriquee"
    return st


def relay(b, item_id, text, date=None, now=None):
    """Ajoute les mots de l'owner, verbatim, a `item_id`. Rend (etat, statut de la consigne).
    etat : 'ajoute' | 'deja-recopie' (meme item, meme jour, meme texte : rien n'est ecrit)."""
    if not (text or "").strip():
        raise B.BacklogError("mots vides : rien a relayer")
    date = date or datetime.date.today().isoformat()
    # Sous le verrou et sur le disque RELU (comme `set_feedback_via`) : `add_owner_feedback`
    # reecrit la liste lue en memoire et perdrait un retour que la synchro aurait ajoute entre-temps.
    with B._Lock(b.path):
        fresh = B._read(b.path)
        it = next((x for x in fresh["items"] if x.get("id") == item_id), None)
        if it is None:
            raise B.BacklogError("item inconnu : %s" % item_id)
        fbs = it.get("owner_feedback") or []
        if any(isinstance(fb, dict) and str(fb.get("date")) == date and fb.get("text") == text
               for fb in fbs):
            b.items = fresh["items"]
            return "deja-recopie", "-"
        avant = copy.deepcopy(it)
        it["owner_feedback"] = list(fbs) + [{"date": date, "text": text, "via": relay_via(now)}]
        B._atomic_write(b.path, B._dump(fresh))
        B.record_gesture(b.path, getattr(b, "author", None), "relay", [(item_id, avant, it)])
    b.items = fresh["items"]
    return "ajoute", _refresh_prompt(b.get(item_id), os.path.dirname(os.path.abspath(b.path)))


def origin(fb):
    via = fb.get("via") if isinstance(fb.get("via"), dict) else None
    if not via:
        return "unlabeled"
    if via.get("comment"):
        return "linear"
    return str(via.get("source") or "") or "malformed"


def census(items, since_day=BASCULE_DAY):
    """Les retours dates depuis la bascule, par origine ; les non etiquetes, NOMMES."""
    out = {"total": 0, "population": 0, "origins": {}, "unlabeled": [], "by_command": 0}
    for it in items:
        for fb in it.get("owner_feedback") or []:
            if not isinstance(fb, dict):
                continue
            out["total"] += 1
            if str(fb.get("date") or "") < since_day:
                continue
            out["population"] += 1
            o = origin(fb)
            out["origins"][o] = out["origins"].get(o, 0) + 1
            if o in ("unlabeled", "malformed"):
                out["unlabeled"].append((it.get("id") or "", str(fb.get("date")), fb.get("text") or ""))
            elif o == "supervisor" and (fb.get("via") or {}).get("by") == BY:
                out["by_command"] += 1
    return out


def name(entry):
    """Un nom sans espace : proof.txt jette toute valeur qui en porte."""
    iid, date, text = entry
    head = " ".join((text or "").split())[:40]
    return "%s@%s:%s" % (iid, date, head.replace(" ", "_").replace(",", ";"))


def _introducing_commit(text, root, backlog_rel=".autoport/backlog.yaml"):
    """Le commit qui a fait entrer ce texte dans le backlog (le plus ancien), ou None."""
    needle = " ".join((text or "").split())[:40]
    if len(needle) < 12:
        return None
    try:
        r = subprocess.run(["git", "log", "--reverse", "--format=%h %s", "-S", needle, "--",
                            backlog_rel], cwd=root, capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.SubprocessError):
        return None
    lines = [ln for ln in r.stdout.splitlines() if ln.strip()]
    return lines[0] if lines else None


def classify(items, entry, root=None):
    """Rend (`via` a poser ou None, cause). Deux preuves seulement :
    copie   le MEME texte, le MEME jour, deja etiquete sur un autre item : le superviseur a
            recopie un commentaire Linear en ouvrant un chantier -> on reprend son `via`.
    commit  le texte est entre dans le backlog par un commit du superviseur et n'est nulle part
            ailleurs -> relais du terminal.
    Rien d'autre n'etiquette : un retour non prouve reste sans `via`, NOMME."""
    iid, date, text = entry
    copies = []
    for it in items:
        if it.get("id") == iid:
            continue
        for fb in it.get("owner_feedback") or []:
            if (isinstance(fb, dict) and isinstance(fb.get("via"), dict) and fb["via"]
                    and str(fb.get("date")) == date and fb.get("text") == text):
                copies.append((str(fb["via"].get("at") or ""), it.get("id") or "?", fb["via"]))
    if copies:
        # La meme phrase postee sur PLUSIEURS tickets (23/09 : deux) : le plus ancien commentaire,
        # et le nombre de candidats ecrit dans l'etiquette plutot qu'un choix muet.
        copies.sort(key=lambda c: (c[0], c[1]))
        _at, src, v = copies[0]
        via = {k: x for k, x in v.items() if k not in ("backfill", "candidates")}
        via["backfill"] = "copie-de-" + src
        if len(copies) > 1:
            via["candidates"] = len(copies)
        return via, "copie"
    c = _introducing_commit(text, root or os.path.dirname(B.AP))
    if c and c.split(" ", 1)[1:2] and c.split(" ", 1)[1].startswith(SUPERVISOR_COMMIT_PREFIX):
        return {"source": "supervisor", "backfill": "commit-" + c.split(" ", 1)[0]}, "commit"
    return None, "non-prouve"


def backfill(b, apply=False, since_day=BASCULE_DAY, root=None):
    c = census(b.items, since_day)
    res = []
    for entry in c["unlabeled"]:
        via, cause = classify(b.items, entry, root)
        n = b.set_feedback_via(entry[0], entry[1], entry[2], via) if (via and apply) else 0
        res.append((entry, cause, via, n))
    return res


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--file", default=None)
    ap.add_argument("--census", action="store_true")
    ap.add_argument("--backfill", action="store_true")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args(argv)
    b = B.load(a.file)
    if a.backfill:
        res = backfill(b, apply=a.apply)
        for entry, cause, via, n in res:
            print("%-10s %s pose=%d via=%s" % (cause, name(entry), n, via))
        print("relay_backfill_candidates=%d" % len(res))
        print("relay_backfill_applied=%d" % sum(r[3] for r in res))
        return 0
    if a.census:
        c = census(b.items)
        print("unlabeled_relays=%d" % len(c["unlabeled"]))
        print("relay_population=%d relay_feedback_total=%d" % (c["population"], c["total"]))
        return 0
    ap.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
