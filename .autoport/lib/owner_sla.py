#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""« Retour owner sans reponse » : le delai se MESURE, et son depassement est une ALERTE.

Le 22/09 l'owner a demande « Pourquoi tu réagis plus a mes feedbacks sur Linear ». Rien
n'etait casse dans la chaine de transport : les commentaires arrivaient dans `owner_feedback`,
le bloc « RETOURS DE L'OWNER SANS REPONSE » etait bien insere en tete de chaque reveil, la
synchro criait « À TRAITER » a chaque passage. Le LECTEUR etait mort. Une file servie a un
lecteur qui n'existe plus est une file silencieuse : elle ne rougit jamais.

Ce module transforme ce silence en grandeur, puis en alerte :

  * `collect()`   date chaque retour de l'owner par son horodatage LINEAR (le `date:` du
                  backlog est au JOUR : il ne peut pas porter un SLA de 2 h) et lui attache
                  le premier commentaire du harnais poste APRES lui sur le MEME ticket.
                  Sans reponse, le delai reste OUVERT (mesure jusqu'a maintenant).
  * `evaluate()`  decide. Deux conditions, toutes les deux necessaires : un retour depasse
                  `AUTOPORT_OWNER_SLA_S`, ET aucun superviseur VIVANT ne l'a lu. Un
                  superviseur vivant qui prend son temps n'est pas une panne ; un superviseur
                  mort l'est, meme sans retour en attente — mais alors il n'y a rien a crier.
  * `run()`       ecrit l'alerte la ou quelqu'un regarde, UNE SEULE FOIS par retour.

TOUT EST INJECTE — l'horloge, le releve du superviseur, la lecture des commentaires, le
posteur, le fichier d'etat. Sans cela la porte de l'item ne pourrait mesurer que le bras
qu'elle a sous la main : elle doit pouvoir SEMER un superviseur mort et un retour de 3 h, et
verifier que le bras oppose (superviseur vivant) ne crie RIEN. Deux bras au vert ne separent
rien (feedback_ablation_vacuous_when_condition_absent).
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import time

AP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SLA_DEFAULT_S = 7200  # 2 h — le chiffre du contrat
# ABSOLU, jamais relatif : `autoport status` est lance depuis n'importe ou, et un chemin
# relatif ferait repartir le compteur « deja crie » a zero selon le repertoire courant —
# donc un commentaire de plus sur le ticket de l'owner a chaque appel depuis ailleurs.
STATE_FILE = os.path.join(AP, ".owner_sla_alerted.json")
RUBRIQUE = "RETOURS DE L'OWNER SANS LECTEUR VIVANT"


def sla_seconds(env=None):
    env = os.environ if env is None else env
    try:
        v = int(env.get("AUTOPORT_OWNER_SLA_S", "") or SLA_DEFAULT_S)
    except (TypeError, ValueError):
        return SLA_DEFAULT_S
    return v if v > 0 else SLA_DEFAULT_S


def feedback_key(item, text):
    """Identifiant STABLE d'un retour, pour ne le crier qu'une fois.

    Il ne peut pas etre l'index dans la liste : l'owner en ajoute, le harnais en archive, et
    les index glissent — on reposterait sur d'anciens retours. Il ne peut pas etre
    l'horodatage seul : deux retours de la meme minute se confondraient. C'est donc l'item
    plus l'empreinte du TEXTE, qui, lui, ne bouge plus une fois recopie.
    """
    h = hashlib.sha1(("%s\n%s" % (item, text or "")).encode("utf-8", "replace"))
    return "%s:%s" % (item, h.hexdigest()[:12])


def collect(rows, fetch_comments, is_owner, is_harness, now=None, ts_of=None):
    """Date chaque retour et lui attache la premiere reponse du harnais qui le SUIT.

    `rows`            [{item, ticket, text, date}] — ce que le backlog a recopie.
    `fetch_comments`  ticket -> [commentaire brut], le plus ancien d'abord ou non.
    `is_owner`/`is_harness`  les regles d'AUTEUR de linear_sync (jamais le marqueur seul :
                      feedback_reference... l'auteur est la seule grandeur qui ne ment pas).
    `ts_of`           commentaire -> epoch. Par defaut `createdAt` ISO-8601.

    Un retour qu'on ne retrouve PAS sur le ticket sort avec `ts=0` et `dated=0` : il est
    compte dans `undated`, jamais silencieusement jete. Un delai qu'on ne sait pas mesurer
    n'est pas un delai nul.
    """
    now = time.time() if now is None else now
    ts_of = _created_at if ts_of is None else ts_of
    par_ticket = {}
    out = []
    for row in rows:
        ticket = row.get("ticket") or ""
        if ticket not in par_ticket:
            try:
                par_ticket[ticket] = list(fetch_comments(ticket) or [])
            except Exception as exc:  # noqa: BLE001
                par_ticket[ticket] = None
                row.setdefault("error", str(exc)[:80])
        comments = par_ticket.get(ticket)
        rec = {
            "item": row.get("item") or "",
            "ticket": ticket,
            "text": row.get("text") or "",
            "date": row.get("date") or "",
            "key": feedback_key(row.get("item") or "", row.get("text") or ""),
            "ts": 0,
            "dated": 0,
            "answered_ts": 0,
            "answered": 0,
            "delay_s": -1,
            "open": 0,
            "excluded": "",
        }
        via = row.get("via") or {}
        rec["origin"] = _origin(via)
        rec["match"] = ""
        if rec["origin"] in EXCLUDED_SOURCES:
            # PAS un commentaire Linear : un deplacement de ticket, un relais du terminal, un
            # commentaire retire. Il reste dans la population, NOMME, jamais compte « apparie ».
            rec["excluded"] = rec["origin"]
        elif comments:
            if via.get("comment"):
                mine = _find_by_id(comments, via["comment"], is_owner)
                how = "id"
            else:
                mine = _match_owner_comment(comments, rec["text"], is_owner, rec["date"])
                how = "text"
            if mine is not None:
                rec["ts"] = ts_of(mine)
                rec["dated"] = 1 if rec["ts"] else 0
                rec["match"] = how if rec["dated"] else ""
        if rec["dated"]:
            suivantes = sorted(
                (c for c in comments if is_harness(c) and ts_of(c) > rec["ts"]),
                key=ts_of,
            )
            if suivantes:
                rec["answered_ts"] = ts_of(suivantes[0])
                rec["answered"] = 1
                rec["delay_s"] = int(rec["answered_ts"] - rec["ts"])
            else:
                # SANS REPONSE = DELAI OUVERT. C'est le cas que l'owner a vecu : le mesurer
                # a zero rendrait la moyenne d'autant plus verte que la panne est grave.
                rec["open"] = 1
                rec["delay_s"] = int(now - rec["ts"])
        out.append(rec)
    return out


def _created_at(comment):
    v = (comment or {}).get("createdAt") or ""
    return iso_to_epoch(v)


def iso_to_epoch(value):
    if not value:
        return 0
    txt = str(value).strip().replace("Z", "+00:00")
    try:
        import datetime
        return int(datetime.datetime.fromisoformat(txt).timestamp())
    except (ValueError, ImportError):
        return 0


def _normalise(text):
    return " ".join((text or "").split()).strip().lower()


# Ce que `linear_sync.save_owner_images` AJOUTE en fin de retour a la recopie. Le texte de
# l'owner n'est pas reecrit : on lui colle une ligne. Elle se retire avant toute comparaison.
RECOPY_SUFFIX_RX = re.compile(r"\s*\[images enregistrees : [^\n]*\]\s*$")
PREFIXE_MIN = 40

# D'ou vient un retour. Ecrit AU MOMENT DE LA RECOPIE dans `owner_feedback[].via` :
#   {comment, ticket, at}   un commentaire Linear, par son identifiant (linear_sync.pull_owner)
#   {source: move}          un deplacement de ticket, recopie en phrase par la synchro
#   {source: supervisor}    les mots de l'owner relayes a la main (terminal), absents de Linear
#   {source: deleted}       recopie de Linear puis retire du ticket (secret, 17/09)
# Rien d'ecrit = un retour d'AVANT la correction, retrouve par son texte, sinon NON APPARIE.
EXCLUDED_SOURCES = ("move", "supervisor", "deleted")


def _origin(via):
    via = via or {}
    if via.get("comment"):
        return "linear"
    return str(via.get("source") or "") or "legacy"


def strip_recopy(text):
    return RECOPY_SUFFIX_RX.sub("", text or "")


def _find_by_id(comments, cid, is_owner):
    """Le commentaire par son IDENTIFIANT — et seulement s'il est de l'owner : un identifiant
    qui designerait un commentaire du harnais ne date rien."""
    for c in comments:
        if c.get("id") == cid:
            return c if is_owner(c) else None
    return None


def text_matches(body, text):
    """Le corps d'un commentaire est-il le retour recopie ? Egalite apres normalisation ; un
    prefixe seulement au-dela de PREFIXE_MIN caracteres — sinon un « oui » de l'owner daterait
    tous les retours qui commencent par « oui »."""
    cible = _normalise(strip_recopy(text))
    corps = _normalise(body)
    if not cible or not corps:
        return False
    if corps == cible:
        return True
    if len(cible) >= PREFIXE_MIN and corps.startswith(cible):
        return True
    return len(corps) >= PREFIXE_MIN and cible.startswith(corps)


def _match_owner_comment(comments, text, is_owner, date=""):
    """Retrouve sur le ticket le commentaire de l'owner que le backlog a recopie, PAR SON TEXTE.

    Repli pour les retours recopies AVANT que la recopie garde l'identifiant. Seuls les
    commentaires dont l'AUTEUR est l'owner concourent : un commentaire du harnais qui CITE
    l'owner ne doit pas se faire prendre pour lui (feedback_detector_on_worker_output...).
    Plusieurs candidats : celui du jour du retour, sinon le plus ancien.
    """
    cands = [c for c in comments if is_owner(c) and text_matches(c.get("body"), text)]
    if not cands:
        return None
    cands.sort(key=lambda c: (str(c.get("createdAt") or "")[:10] != (date or ""),
                              str(c.get("createdAt") or "")))
    return cands[0]


def cost_summary(records, sla_s, now=None):
    """Le COUT D'AVANT, chiffre. Termes publies separement, jamais une moyenne.

    Une moyenne sur une population ou la moitie des delais sont courts NOIE le cas grave
    (feedback_mean_over_a_low_threshold_set_is_self_defeating) : on publie un COMPTE au-dela
    du seuil et le MAXIMUM, qui est exactement ce que l'owner a subi.
    """
    now = time.time() if now is None else now
    dated = [r for r in records if r["dated"]]
    over = [r for r in dated if r["delay_s"] > sla_s]
    worst = max((r["delay_s"] for r in dated), default=-1)
    exclus = {}
    for r in records:
        if r.get("excluded"):
            exclus[r["excluded"]] = exclus.get(r["excluded"], 0) + 1
    return {
        "population": len(records),
        "dated": len(dated),
        "undated": len(records) - len(dated),
        # NON APPARIE = ni date ni exclu par une source NOMMEE a la recopie.
        "unmatched": sum(1 for r in records if not r["dated"] and not r.get("excluded")),
        "excluded": exclus,
        "by_id": sum(1 for r in dated if r.get("match") == "id"),
        "by_text": sum(1 for r in dated if r.get("match") == "text"),
        "answered": sum(1 for r in dated if r["answered"]),
        "open": sum(1 for r in dated if r["open"]),
        "over_sla": len(over),
        "max_delay_s": worst,
        "worst_item": (max(dated, key=lambda r: r["delay_s"])["item"] if dated else "-"),
    }


def evaluate(records, supervisor, now=None, sla_s=None, already=None):
    """Faut-il crier ? Les deux conditions du contrat, et rien d'autre."""
    now = time.time() if now is None else now
    sla_s = sla_seconds() if sla_s is None else sla_s
    already = set(already or ())
    en_retard = [
        r for r in records
        if r["dated"] and not r["answered"] and (now - r["ts"]) > sla_s
    ]
    en_retard.sort(key=lambda r: r["ts"])
    lecteur_mort = not bool(supervisor.get("alive"))
    declenche = bool(en_retard) and lecteur_mort
    return {
        "raise": declenche,
        "overdue": en_retard,
        "overdue_n": len(en_retard),
        "oldest_age_s": int(now - en_retard[0]["ts"]) if en_retard else -1,
        "oldest_item": en_retard[0]["item"] if en_retard else "-",
        "reader_dead": 1 if lecteur_mort else 0,
        "reader_why": supervisor.get("why", "-"),
        "reader_state": _etat_lecteur(supervisor),
        # Ce qui reste A CRIER : ce qui a deja ete crie ne l'est pas deux fois.
        "to_post": [r for r in en_retard if r["key"] not in already] if declenche else [],
    }


def _etat_lecteur(supervisor):
    """`vivant` / `non-inscrit` / `mort` — ABSENT DU REGISTRE N'EST PAS MORT (22/09)."""
    if supervisor.get("alive"):
        return "vivant"
    return "non-inscrit" if supervisor.get("why") == "absent-du-registre" else "mort"


def status_lines(alert, supervisor):
    """La rubrique, en tete de `autoport status`. Vide quand il n'y a rien a dire."""
    if not alert.get("raise"):
        return []
    age_h = alert["oldest_age_s"] / 3600.0
    lignes = [
        "!! %s !!" % RUBRIQUE,
        "   %d retour(s) de l'owner sans reponse ; le plus vieux attend %.1f h (%s)."
        % (alert["overdue_n"], age_h, alert["oldest_item"]),
        ("   Aucun superviseur inscrit ni aucune session declaree ne les lit : %s "
         "(ce n'est pas une mort constatee, c'est une absence de lecteur connu)."
         % supervisor.get("why", "-"))
        if _etat_lecteur(supervisor) == "non-inscrit" else
        "   Aucun superviseur vivant ne peut les lire : %s (pid declare %s, tty %s tenu par %s)."
        % (supervisor.get("why", "-"), supervisor.get("pid", 0) or supervisor.get("self_pid", 0),
           supervisor.get("tty", "-"), supervisor.get("tty_holder", "-")),
        "   Relance le superviseur (./run-supervisor.sh) : la file ne se videra pas seule.",
    ]
    for r in alert["overdue"][:5]:
        lignes.append("   - %s : « %s »" % (r["item"], (r["text"] or "")[:90]))
    return lignes


def comment_body(record, alert, supervisor, now=None):
    now = time.time() if now is None else now
    age_h = (now - record["ts"]) / 3600.0
    if _etat_lecteur(supervisor) == "non-inscrit":
        cause = "aucune session ne s'est signalee comme lisant tes retours"
    else:
        cause = "la session qui traite tes retours s'est arretee ou ne repond plus"
    return (
        "Ton retour attend depuis %.1f h et personne ne l'a lu : %s. Ce message est "
        "automatique — il part justement parce qu'aucun humain ni aucune session n'etait la "
        "pour te repondre. Je reprends ce point des qu'une session redemarre." % (age_h, cause)
    )


def state_path():
    return os.environ.get("AUTOPORT_OWNER_SLA_STATE") or STATE_FILE


def cache_path():
    return os.environ.get("AUTOPORT_OWNER_SLA_CACHE") or CACHE_FILE


def load_state(path=None):
    path = state_path() if path is None else path
    try:
        with open(path, "r") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def save_state(state, path=None):
    path = state_path() if path is None else path
    tmp = "%s.tmp.%d" % (path, os.getpid())
    d = os.path.dirname(path)
    if d and not os.path.isdir(d):
        os.makedirs(d, exist_ok=True)
    with open(tmp, "w") as fh:
        json.dump(state, fh, ensure_ascii=False, indent=1, sort_keys=True)
    os.replace(tmp, path)


def run(records, supervisor, poster, now=None, sla_s=None, state_path=None, state=None):
    """Ecrit l'alerte la ou quelqu'un regarde. Rend ce qui a ete fait, chiffre.

    `poster(item, ticket, body) -> bool`. Un post qui ECHOUE ne marque pas le retour comme
    crie : sinon une coupure reseau ferait taire l'alerte pour toujours — exactement la panne
    silencieuse qu'on est en train de supprimer.
    """
    now = time.time() if now is None else now
    etat = load_state(state_path) if state is None else state
    alert = evaluate(records, supervisor, now=now, sla_s=sla_s, already=etat.keys())
    poste, rate, deja = 0, 0, 0
    if alert["raise"]:
        deja = alert["overdue_n"] - len(alert["to_post"])
        for r in alert["to_post"]:
            try:
                ok = poster(r["item"], r["ticket"], comment_body(r, alert, supervisor, now=now))
            except Exception:  # noqa: BLE001
                ok = False
            if ok:
                etat[r["key"]] = {"ts": int(now), "item": r["item"]}
                poste += 1
            else:
                rate += 1
    if state is None and poste:
        save_state(etat, state_path)
    alert.update({"posted": poste, "post_failed": rate, "already_posted": deja,
                  "lines": status_lines(alert, supervisor)})
    return alert


# ===================================================================== LES SOURCES REELLES ==
# Tout ce qui precede est pur : injectable, rejouable, mesurable hors reseau. Ce qui suit est
# le branchement sur le vrai backlog et le vrai Linear, et rien d'autre ne doit s'y ajouter :
# la porte de l'item doit pouvoir tout exercer SANS toucher au reseau.

def rows_from_backlog(items, linear_map, since_date=None):
    """Les retours de l'owner recopies dans le backlog, aplatis, avec leur ticket.

    `since_date` borne la fenetre (`AAAA-MM-JJ`). Le `date:` du backlog est au JOUR : il sert
    a BORNER la population, jamais a mesurer un SLA de 2 h. L'heure vient de Linear.
    """
    rows = []
    for it in items:
        iid = it.get("id") or ""
        rec = (linear_map or {}).get(iid) or {}
        for fb in (it.get("owner_feedback") or []):
            date = str(fb.get("date") or "")
            if since_date and date < since_date:
                continue
            via = fb.get("via") if isinstance(fb.get("via"), dict) else {}
            # Le ticket ou l'owner a PARLE : celui de l'item, sauf si la recopie en nomme un
            # autre (retour recopie d'un ticket parent, d'un doublon archive...).
            rows.append({"item": iid, "date": date, "text": fb.get("text") or "",
                         "ticket": via.get("ticket") or rec.get("issue_id") or "",
                         "item_ticket": rec.get("issue_id") or "",
                         "via": via,
                         "identifier": rec.get("identifier") or "-"})
    return rows


COMMENT_FIELDS = "id body createdAt user { id app } botActor { id }"


def _rest(L, ticket, page):
    """La SUITE des commentaires d'un ticket. `comments(first:100)` s'arretait au centieme :
    JAK-176 en porte 139, et ses retours les plus anciens n'etaient jamais retrouves (23/09)."""
    out = []
    while page and page.get("hasNextPage"):
        d = L.q('query($id:String!,$a:String){ issue(id:$id){ comments(first:100, after:$a){ '
                'pageInfo { hasNextPage endCursor } nodes { ' + COMMENT_FIELDS + ' } } } }',
                id=ticket, a=page.get("endCursor"))
        conn = ((d.get("issue") or {}).get("comments")) or {}
        out += conn.get("nodes") or []
        page = conn.get("pageInfo") or {}
    return out


def linear_sources(L, owner_id, tickets=()):
    """Rend (fetch_comments, is_owner, is_harness) branches sur le vrai Linear.

    LES TICKETS SE TIRENT PAR PAQUETS DE 40, comme `pull_owner` ; leurs commentaires EN ENTIER. La population de 7 jours
    tient sur une cinquantaine de tickets : une requete par RETOUR ferait 145 allers-retours,
    et ce code tourne dans un demon qui repasse toutes les 30 s. Deux requetes suffisent.
    """
    try:
        from . import linear_sync as S  # pragma: no cover
    except ImportError:
        import sys
        sys.path.insert(0, AP)
        import linear_sync as S
    cache = {}
    uniq = [t for t in dict.fromkeys(tickets) if t]
    for i in range(0, len(uniq), 40):
        lot = uniq[i:i + 40]
        d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:40, includeArchived:true){ '
                'nodes { id comments(first:100){ pageInfo { hasNextPage endCursor } '
                'nodes { ' + COMMENT_FIELDS + ' } } } } }', ids=lot)
        for iss in (d.get("issues") or {}).get("nodes") or []:
            conn = iss.get("comments") or {}
            cache[iss["id"]] = (conn.get("nodes") or []) + _rest(L, iss["id"], conn.get("pageInfo"))

    def fetch(ticket):
        if not ticket:
            return []
        if ticket not in cache:
            cache[ticket] = _rest(L, ticket, {"hasNextPage": True, "endCursor": None})
        return cache[ticket]

    return fetch, (lambda c: S.is_owner_comment(c, owner_id)), S.is_harness_comment


CACHE_FILE = os.path.join(AP, ".owner_sla.json")


def save_cache(records, path=None, now=None):
    """Le releve DATE des retours, pose par la synchro (30 s) pour que `status` soit offline.

    `autoport status` ne doit appeler NI Linear NI le reseau : il est lu des dizaines de fois
    par jour, et une rubrique qui coute une requete HTTP finirait par etre retiree. Le cache
    porte la partie chere (les horodatages Linear) ; la partie DECISIVE — le lecteur est-il
    vivant MAINTENANT — est remesuree a chaque `status`, sur /proc, sans reseau.
    """
    now = int(time.time() if now is None else now)
    path = cache_path() if path is None else path
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as fh:
        json.dump({"at": now, "records": records}, fh, ensure_ascii=False)
    os.replace(tmp, path)


def load_cache(path=None):
    path = cache_path() if path is None else path
    try:
        with open(path, "r") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return [], 0
    if not isinstance(data, dict):
        return [], 0
    return list(data.get("records") or []), int(data.get("at") or 0)


FENETRE_JOURS = 7
PERIODE_DEFAUT_S = 600


def periode_s(env=None):
    env = os.environ if env is None else env
    try:
        v = int(env.get("AUTOPORT_OWNER_SLA_PERIOD_S", "") or PERIODE_DEFAUT_S)
    except (TypeError, ValueError):
        return PERIODE_DEFAUT_S
    return max(v, 0)


def veille(L, items, linear_map, owner_id, poster, dry=False, now=None, force=False):
    """UN passage de veille, appele par la synchro Linear. Rend un compte rendu chiffre.

    IL EST BRIDE. La synchro repasse toutes les 30 s ; redater 145 retours a chaque fois
    ferait 5 800 requetes par heure pour une grandeur qui bouge a l'echelle de l'heure. On ne
    redate que toutes les `AUTOPORT_OWNER_SLA_PERIOD_S` (10 min par defaut) — mais la DECISION,
    elle, est reprise a chaque passage sur le cache, parce que c'est l'etat du LECTEUR qui
    bascule vite, pas les horodatages.
    """
    import datetime
    now = time.time() if now is None else now
    try:
        from . import supervisor_alive as SA
    except ImportError:
        import sys
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import supervisor_alive as SA

    records, at = load_cache()
    frais = bool(records) and (now - at) < periode_s()
    if force or not frais:
        depuis = (datetime.date.fromtimestamp(now)
                  - datetime.timedelta(days=FENETRE_JOURS)).isoformat()
        rows = rows_from_backlog(items, linear_map, since_date=depuis)
        fetch, is_owner, is_harness = linear_sources(L, owner_id,
                                                     tickets=[r["ticket"] for r in rows])
        records = collect(rows, fetch, is_owner, is_harness, now=now)
        save_cache(records, now=now)
        at = now

    rel = SA.probe(now=now)
    resume = cost_summary(records, sla_seconds(), now=now)
    if dry:
        alerte = evaluate(records, rel, now=now, already=load_state().keys())
        alerte.update({"posted": 0, "post_failed": 0,
                       "lines": status_lines(alerte, rel)})
    else:
        alerte = run(records, rel, poster, now=now)
    return {"releve": rel, "cout": resume, "alerte": alerte, "redate": at == now}


# ============================================================ REPRISE DES RETOURS D'AVANT ==
# Les retours recopies AVANT que la recopie garde l'identifiant n'ont pas de `via`. On les
# reprend UNE FOIS, et la regle est ecrite ici, pas dans une session : elle n'etiquette jamais
# un retour « hors Linear » parce qu'on ne le trouve pas. Il faut DEUX absences independantes —
# aucun commentaire de l'espace Linear entier (archives comprises), ET aucune recopie dans le
# journal de la synchro, le seul code qui recopie un commentaire. Une seule absence ne suffit
# pas : le retour reste sans `via` et compte NON APPARIE.

MOVE_TEXTS = ("Déplacé en « Done » dans Linear par l'owner",
              "[Linear] déplacé en « À arbitrer » pendant un essai : sera mis de côté à la fin de "
              "l'essai en cours")
PULL_LOG_RX = re.compile(r"^  retour owner sur (\S+) \((\d{4}-\d\d-\d\d)\) : (.*)$")


def pull_log_entries(lines):
    """Ce que `pull_owner` a DIT avoir recopie : (item, jour, 80 premiers caracteres)."""
    out = []
    for ln in lines:
        m = PULL_LOG_RX.match(ln.rstrip("\n"))
        if m:
            out.append((m.group(1), m.group(2), m.group(3)))
    return out


def _common_prefix(a, b):
    n = 0
    for x, y in zip(a, b):
        if x != y:
            break
        n += 1
    return n


def _in_pull_log(item, text, entries):
    """La synchro a-t-elle recopie ce retour dans CET item ? Le journal garde 80 caracteres ;
    le retour, lui, a pu etre expurge a la recopie (secret retire le 17/09) : un prefixe commun
    de PREFIXE_MIN caracteres suffit, le texte entier s'il est plus court."""
    cible = _normalise(strip_recopy(text))
    for iid, _day, head in entries:
        h = _normalise(head)
        if iid == item and h and _common_prefix(cible, h) >= min(PREFIXE_MIN, len(h), len(cible)):
            return True
    return False


def classify_legacy(item, date, text, item_ticket, workspace, is_owner, pull_entries,
                    pull_first_day):
    """Rend (`via` a poser ou None, cause). `workspace` = tous les commentaires de l'espace,
    chacun portant `issue` (son ticket). Cause : move | own-ticket | other-ticket | deleted |
    supervisor | unknown."""
    if text in MOVE_TEXTS:
        return {"source": "move", "backfill": "texte-du-deplacement"}, "move"
    own = [c for c in workspace if c.get("issue") == item_ticket]
    mine = _match_owner_comment(own, text, is_owner, date)
    where = "own-ticket"
    if mine is None and len(_normalise(strip_recopy(text))) >= PREFIXE_MIN:
        # Hors de son ticket, un texte court ne prouve rien : « Validé » est ecrit partout.
        mine = _match_owner_comment(workspace, text, is_owner, date)
        where = "other-ticket"
    if mine is not None:
        return ({"comment": mine["id"], "ticket": mine["issue"], "at": mine.get("createdAt"),
                 "backfill": where}, where)
    if not pull_first_day or str(date) < pull_first_day:
        # Le journal ne couvre pas ce jour : ni sa presence ni son absence ne temoignent.
        return None, "unknown"
    if _in_pull_log(item, text, pull_entries):
        return ({"source": "deleted", "backfill": "recopie-par-la-synchro-absent-de-linear"},
                "deleted")
    return ({"source": "supervisor",
             "backfill": "absent-de-linear-et-du-journal-de-synchro-depuis-" + pull_first_day},
            "supervisor")


def workspace_comments(L):
    """TOUS les commentaires de l'espace Linear, archives compris, pagines jusqu'au bout."""
    try:
        from . import linear_sync as S  # pragma: no cover
    except ImportError:
        import sys
        sys.path.insert(0, AP)
        import linear_sync as S
    issues = S._pages(L, 'query($a:String){ issues(first:50, after:$a, includeArchived:true){ '
                         'pageInfo { hasNextPage endCursor } nodes { id comments(first:100){ '
                         'pageInfo { hasNextPage endCursor } nodes { ' + COMMENT_FIELDS
                         + ' } } } } }')
    out = []
    for iss in issues:
        conn = iss.get("comments") or {}
        for c in (conn.get("nodes") or []) + _rest(L, iss["id"], conn.get("pageInfo")):
            c = dict(c)
            c["issue"] = iss["id"]
            out.append(c)
    return out


def main(argv=None):
    import argparse
    import sys
    ap = argparse.ArgumentParser(description="reprise des retours owner sans `via`")
    ap.add_argument("--backfill", action="store_true")
    ap.add_argument("--apply", action="store_true", help="ecrire dans backlog.yaml (sinon : a blanc)")
    a = ap.parse_args(argv)
    if not a.backfill:
        ap.print_help()
        return 2
    sys.path.insert(0, AP)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import linear_sync as S
    import linear_identity as LI
    import backlog as B
    L = S.Linear(LI.resolve())
    mp = S.load_map()
    owner_id = S.owner_user_id(L, mp)
    ws = workspace_comments(L)
    try:
        with open(os.path.join(AP, "logs", "linear_sync.txt"), "r", errors="replace") as fh:
            pulls = pull_log_entries(fh)
    except OSError:
        pulls = []
    first = min((d for _i, d, _h in pulls), default="")
    bl = B.load()
    causes, poses = {}, 0
    for it in bl.items:
        iid = it.get("id") or ""
        tk = ((mp.get(iid) or {}).get("issue_id")) or ""
        for fb in it.get("owner_feedback") or []:
            if not isinstance(fb, dict) or fb.get("via"):
                continue
            via, cause = classify_legacy(iid, str(fb.get("date") or ""), fb.get("text") or "", tk,
                                         ws, lambda c: S.is_owner_comment(c, owner_id), pulls,
                                         first)
            causes[cause] = causes.get(cause, 0) + 1
            print("%-12s %s %s %s" % (cause, fb.get("date"), iid[:48],
                                      (fb.get("text") or "")[:60].replace("\n", " ")))
            if via and a.apply:
                poses += bl.set_feedback_via(iid, fb.get("date"), fb.get("text") or "", via)
    print("backfill_workspace_comments=%d" % len(ws))
    print("backfill_pull_log_entries=%d backfill_pull_log_first_day=%s" % (len(pulls), first or "-"))
    print("backfill_causes=%s" % ",".join("%s:%d" % kv for kv in sorted(causes.items())))
    print("backfill_applied=%d" % poses)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
