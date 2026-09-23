#!/usr/bin/env python3
"""Miroir Linear du backlog autoport — lisible par l'owner depuis son telephone.

Owner, 17/09/2026 : « ce serait mieux si on passait par un vrai systeme genre Linear ? Tu pourrais
setup le MCP […] tu sera le seul (enfin toi, le harnais) a utiliser ce compte ». Le fichier
backlog.yaml RESTE la source de verite de la machine (portes, livrables, ecritures atomiques) ;
Linear en est le miroir en francais courant, ET un canal de decision : un ticket que l'owner deplace fait suivre le backlog (voir apply_owner_move) : un ticket par chantier, un etat, un rang, ce que
l'owner doit regarder, le dernier verdict, et les retours de l'owner en commentaires.

Sens des ecritures :
  backlog -> Linear : titre, description, etat, projet, priorite (a chaque passage) ; un commentaire
                      marque « 🤖 » quand l'etat change.
  Linear -> backlog : les commentaires SANS le marqueur sont ceux de l'owner (meme compte) :
                      recopies mot pour mot dans owner_feedback ; un ticket qu'il deplace lui-meme
                      en « Validé » pose son feu vert (c'est son geste, pas le notre).

Jeton : ~/.config/autoport/linear.env (LINEAR_API_KEY), jamais dans le depot.
Correspondance id -> ticket : .autoport/linear_map.json (versionne).
"""
import argparse
import fcntl
import re
import datetime as dt
import hashlib
import json
import os
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parent.parent
AP = ROOT / ".autoport"
sys.path.insert(0, str(AP))
from lib import backlog as B  # noqa: E402
import linear_identity as LI  # noqa: E402
from lib import secret_mask as SM  # noqa: E402
from lib import owner_sla as OSLA  # noqa: E402
from lib import owner_capture as OCAP  # noqa: E402

API = "https://api.linear.app/graphql"


def _home():
    """Le `.autoport` de l'arbre PRINCIPAL, meme lance depuis un worktree. Un worktree porte sa propre
    copie VERSIONNEE (donc perimee) de la carte et son propre verrou : une synchro lancee de la creait un
    second ticket pour tout item ne apres la coupe de l'arbre, sans jamais attendre la veille."""
    try:
        import subprocess  # noqa: PLC0415
        common = subprocess.run(["git", "-C", str(AP), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:  # noqa: BLE001 — pas de git : l'arbre courant
        return AP
    main = Path(common).parent / ".autoport" if common else None
    return main if main and (main / "linear_sync.py").exists() else AP


HOME = _home()
MAP_PATH = HOME / "linear_map.json"
# Cliche HORS git de la carte (gitignore). 23/09 00:19 : un `git revert` + `git reset HEAD~1` a remis la
# carte suivie a son dernier commit ; la correspondance de JAK-195 (creee 7 min plus tot) a disparu, la
# veille a cree JAK-196 pour le meme item 22 s plus tard, puis a pris JAK-195 pour un ticket de l'owner.
SHADOW_PATH = HOME / ".linear_map.shadow.json"
LOCK_PATH = HOME / ".linear_sync.lock"
KEY_FMT = "Identifiant harnais : `%s`"   # ecrit par description() : la cle de l'item DANS le ticket
KEY_RE = re.compile(r"Identifiant harnais : `([^`]+)`")


def _write_atomic(path, mp):
    tmp = path.with_name(path.name + ".tmp.%d" % os.getpid())
    tmp.write_text(json.dumps(mp, indent=1, ensure_ascii=False, sort_keys=True))
    os.replace(tmp, path)


def _gen(mp):
    try:
        return int((mp or {}).get("_gen") or 0)
    except (TypeError, ValueError):
        return 0


def load_map():
    """La carte item -> ticket. Si le fichier suivi a RECULE sous le cliche (git reset/checkout/stash/
    revert), le cliche gagne et la perte est NOMMEE. Egalite = le fichier suivi gagne (retouche a la main)."""
    def rd(p):
        try:
            return json.loads(p.read_text())
        except (OSError, ValueError):
            return None
    mp, sh = rd(MAP_PATH), rd(SHADOW_PATH)
    if sh is None and mp is not None:
        _write_atomic(SHADOW_PATH, mp)   # premier passage, ou cliche efface (git clean) : on le pose
    elif sh is not None and _gen(sh) > _gen(mp):
        lost = sorted(k for k in sh if not k.startswith("_") and k not in (mp or {}))
        print("CARTE LINEAR RECULEE : %s est a la generation %d, le cliche hors git a la %d ; cliche restaure, "
              "%d correspondance(s) sauvee(s)%s" % (MAP_PATH.name, _gen(mp), _gen(sh), len(lost),
                                                    (" : " + ", ".join(lost[:8])) if lost else ""))
        mp = sh
        _write_atomic(MAP_PATH, mp)
    _SAVED["body"] = _body(mp or {})
    return mp or {}


_SAVED = {"body": None}


def _body(mp):
    return json.dumps({k: v for k, v in mp.items() if k != "_gen"}, sort_keys=True, ensure_ascii=False)


def save_map(mp):
    """Ecriture atomique, cliche d'abord : un lecteur ne voit jamais une carte a moitie ecrite. Rien de
    change = rien d'ecrit : la generation ne monte pas a chaque passage de la veille (30 s)."""
    body = _body(mp)
    if body == _SAVED["body"]:
        return
    _SAVED["body"] = body
    mp["_gen"] = _gen(mp) + 1
    _write_atomic(SHADOW_PATH, mp)
    _write_atomic(MAP_PATH, mp)


def map_lock():
    """LE verrou de la synchro, pris par TOUTES les voies d'entree (veille, --comment, --only, --check),
    dans l'arbre principal quel que soit l'arbre d'ou l'on part."""
    fh = open(LOCK_PATH, "a+")
    fcntl.flock(fh, fcntl.LOCK_EX)
    return fh


def issue_key(iss):
    m = KEY_RE.search((iss or {}).get("description") or "")
    return m.group(1) if m else None


def item_title(it):
    return (it.get("feature") or it["id"]).strip()[:250]


def find_issue_for(L, team, iid, title, taken):
    """Le ticket de `iid` existe-t-il DEJA dans Linear ? Linear est la seule memoire que ni git ni un
    worktree ne peuvent faire reculer : on le lui demande avant toute creation. Un ticket qui porte la
    cle d'un AUTRE item, ou deja relie ailleurs (`taken`), n'est jamais repris."""
    d = L.q('query($t:ID!,$k:String!,$ti:String!){ issues(first:20, includeArchived:true, filter:{team:{id:{eq:$t}}, '
            'or:[{description:{contains:$k}},{title:{eq:$ti}}]}){ nodes { id identifier url title description '
            'createdAt state { name type } } } }', t=team, k=KEY_FMT % iid, ti=title)
    c = [n for n in d["issues"]["nodes"] if n["id"] not in taken
         and (issue_key(n) == iid or (issue_key(n) is None and (n.get("title") or "").strip() == title))]
    c.sort(key=lambda n: (issue_key(n) != iid, n["state"]["type"] == "canceled", n.get("createdAt") or ""))
    return c[0] if c else None


def relinked_rec(iss):
    """LA fiche d'un ticket RETROUVE apres perte de la carte (`ensure_ticket`, `adopt_owner_issues`) : le curseur repart
    d'avant la creation du ticket, jamais de maintenant — un retour de l'owner poste pendant la perte serait saute a
    jamais. `pull_owner` saute ceux deja recopies (par identifiant) : rien n'est recopie deux fois."""
    return {"issue_id": iss["id"], "identifier": iss["identifier"],
            "url": iss.get("url") or "https://linear.app/moukrea/issue/" + iss["identifier"],
            "last_state": iss["state"]["name"], "hash": "", "pulled_at": PULL_FROM_START}


def ensure_ticket(L, mp, team, iid, title, payload, st, h):
    """LE seul chemin qui cree un ticket. Rend (rec, cree). Linear d'abord : une carte qui a recule (git)
    ou lue depuis un worktree ne sait pas que le ticket existe. Une recherche qui echoue LEVE : jamais de
    creation a l'aveugle. La carte est sauvee AVANT toute autre requete."""
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    found = find_issue_for(L, team, iid, title, {v["issue_id"] for k, v in mp.items() if not k.startswith("_")})
    if found:
        print("TICKET EXISTANT RELIE : %s -> %s (aucune creation)" % (found["identifier"], iid))
        mp[iid] = relinked_rec(found)
        save_map(mp)
        return mp[iid], False
    r = with_room(L, lambda: L.q('mutation($i:IssueCreateInput!){ issueCreate(input:$i){ issue { id identifier url } } }',
                                 i=dict(payload, teamId=team)), "creation du ticket de %s" % iid)
    iss = r["issueCreate"]["issue"]
    mp[iid] = {"issue_id": iss["id"], "identifier": iss["identifier"], "url": iss["url"],
               "last_state": st, "hash": h, "pulled_at": now}
    save_map(mp)
    return mp[iid], True


def classify_unmapped(iss, bl, mp):
    """Un ticket hors carte : ("owner", None) s'il vient de l'owner, ("relink", iid) si c'est le ticket
    PERDU d'un item sans ticket, ("harness", pourquoi) s'il vient de nous. Un ticket du harnais n'est
    JAMAIS adopte comme ticket de l'owner : ni par sa cle, ni par son auteur, ni par son titre."""
    k = issue_key(iss)
    if k:
        return ("relink", k) if bl.get(k) and k not in mp else ("harness", "porte la cle de %s" % k)
    t = (iss.get("title") or "").strip()
    twin = next((it["id"] for it in bl.items if not it["id"].startswith("owner-") and item_title(it) == t), None)
    if twin:
        return ("relink", twin) if twin not in mp else ("harness", "titre de %s" % twin)
    if (iss.get("creator") or {}).get("app"):
        return ("harness", "cree par l'application")
    return ("owner", None)
STATE_JSON = AP / "state.json"
TEAM_KEY = "JAK"
TEAM_NAME = "Jak and Daxter: Recharged Collection"
MARK = "🤖 "


def mark(L):
    """Prefixe ECRIT devant nos messages. Owner 17/09 21:35, une fois l'identite d'application en
    place : « tu peux virer l'emoji bot de tes réponses ». Sous l'application, l'auteur est rendu
    par le serveur et le marqueur ne sert plus qu'a relire l'AVANT-bascule (is_harness_comment) ;
    en repli sur la cle personnelle, il reste le seul moyen de nous distinguer de l'owner."""
    return "" if getattr(L, "mode", "owner") == "app" else MARK
MAP_DOCS = {}
SINCE_DAYS = 7  # validés/archivés plus vieux que ça ne sont pas miroités

STATES = [  # (nom Linear, type Linear) — colonnes NATIVES de Linear quand elles existent (owner 17/09), custom sinon
    ("Backlog", "backlog"), ("Todo", "unstarted"), ("In Progress", "started"),
    ("In Review", "started"), ("À arbitrer", "started"),
    ("Done", "completed"), ("Canceled", "canceled"),
]
PROJECTS = {  # prefixe d'id -> projet
    "grass": "Herbe", "water": "Eau", "lighting": "Lumière", "hdr": "Lumière", "ao": "Lumière",
    "soft": "Surfaces meubles", "perf": "Performances", "harness": "Harnais", "acquis": "Harnais",
    "res": "Écran et menus", "menu": "Écran et menus", "firstperson": "Personnages",
    "shrub": "Végétation", "mesh": "Végétation", "hud": "Écran et menus",
}
STATUS_FR = {"open": "à faire", "in-progress": "en cours", "to-test": "à tester par toi",
             "blocked": "bloqué", "validated": "validé", "archived": "archivé"}


class Linear:
    def __init__(self, ident):
        """`ident` vient de `linear_identity.resolve()`. Le jeton et L'IDENTITE SOUS LAQUELLE IL
        PARLE voyagent ensemble, volontairement : tant qu'on ne passait qu'une chaine, aucun code
        du fichier ne pouvait savoir qu'il postait sous le compte de l'owner — c'est exactement la
        panne du 17/09 (JAK-180)."""
        self.n = 0
        self.ident = ident
        self.mode = ident["mode"]          # "app" = l'application Autoport ; "owner" = repli
        self.s = requests.Session()
        auth = ("Bearer " + ident["key"]) if ident.get("bearer") else ident["key"]
        self.s.headers.update({"Authorization": auth, "Content-Type": "application/json"})

    def q(self, query, **vars):
        last = None
        for attempt in range(4):
            self.n += 1
            try:
                r = self.s.post(API, json={"query": query, "variables": vars}, timeout=60)
            except requests.RequestException as e:  # reseau : transitoire
                last = "reseau : %s" % e; time.sleep(3 * (attempt + 1)); continue
            if r.status_code == 429 or r.status_code >= 500:
                last = "HTTP %d" % r.status_code; time.sleep(5 * (attempt + 1)); continue
            try:
                d = r.json()
            except ValueError:  # reponse non JSON (page d'erreur) : transitoire
                last = "reponse non JSON (HTTP %d)" % r.status_code; time.sleep(3 * (attempt + 1)); continue
            if "errors" in d:
                raise RuntimeError(json.dumps(d["errors"])[:600])
            # 23/09 (harness-owner-secret-never-copied-in-clear) : le Client Secret colle par l'owner le 17/09 a
            # ete recopie en clair dans le journal, le backlog, .owner_sla.json, un prompt et 18 commits. Le masque
            # s'applique ICI, a la reception : aucun appelant ne voit jamais le texte de Linear en clair.
            SM.mask_tree(d["data"])
            return d["data"]
        raise RuntimeError("Linear indisponible apres 4 essais : %s" % last)


# ------------------------------------------------------------------------------------------ ESPACE ----
# 23/09 00:3x : le plan gratuit de Linear refuse toute creation au-dela de 250 tickets ACTIFS (erreur
# USAGE_LIMIT_EXCEEDED, metrique `activeIssueCount` = tout ticket NON ARCHIVE, clos compris). 275 actifs :
# chaque passage mourait sur la premiere creation. Le superviseur en a archive 169 a la main ; la synchro
# mourait alors sur le premier commentaire adresse a un ticket archive (« Entity not found: Issue ») et
# JAK-176, 191, 192, 193 ont du etre desarchives a la main. Owner 23/09 : « Archive les tickets terminés,
# ça devrait se faire automatiquement quand on a un soucis de place. »
SPACE_LIMIT = int(os.environ.get("LINEAR_ISSUE_LIMIT") or 250)  # plan gratuit ; un refus de Linear l'abaisse
SPACE_HIGH = 0.85     # au-dela : archivage des tickets clos les plus anciens...
SPACE_LOW = 0.75      # ...jusqu'ici : l'ecart evite de rearchiver a chaque passage
SPACE_EVERY_S = 300   # un recensement de l'espace au plus toutes les 5 min (la veille passe toutes les 30 s)
SPACE_PATH = HOME / ".linear_space.json"  # hors git : le dernier recensement, lu par la preuve
# Une limite APPRISE sur un refus ne remontait jamais seule : l'owner qui change de plan gardait un archivage calcule sur
# l'ancienne limite jusqu'a l'effacement du fichier. Elle tombe des que Linear accepte plus de tickets actifs qu'elle
# (creation, desarchivage, recensement), et au plus tard apres LEARNED_TTL_S : le prochain refus la reapprend (un essai).
LEARNED_TTL_S = 6 * 3600
CODE_FP = hashlib.sha1(Path(__file__).read_bytes()).hexdigest()[:12]  # quel code a tourne, dans le journal
_CTX = {"bl": None, "mp": None, "todo": None, "team": None}  # ce que l'archivage doit epargner, pose par main()
FAILED = []           # les echecs NOMMES du passage : un ticket qui refuse ne fait plus tomber les autres
LEFT_ARCHIVED = object()
# Curseur d'un ticket RELIE ou ADOPTE : depuis le debut. Le 17/09, JAK-173 adopte a 10:08 avec `pulled_at` = maintenant a perdu
# les trois commentaires que l'owner y avait poses avant (09:37, 10:04, 10:06) ; `pull_owner` saute ceux deja recopies.
PULL_FROM_START = "1970-01-01T00:00:00Z"
UNARCHIVE = 'mutation($id:String!){ issueUnarchive(id:$id){ success } }'
LIVE = ("open", "in-progress", "blocked", "to-test")  # un chantier que l'archivage d'un ticket peut encore decider
# Jusqu'au 17/09 au soir (harness-linear-own-identity), le harnais parlait sous la cle de l'owner : un changement d'etat
# signe de son identifiant AVANT cette date ne prouve pas que l'owner a deplace le ticket (marge : minuit UTC du 18).
OWNER_KEY_UNTIL = "2026-09-18T00:00:00.000Z"
MOVES = []  # les ecarts d'etat du passage et ce qu'on en a fait (applique ou non, pourquoi) : lu par le recensement
# 23/09 (harness-linear-owner-moves-never-lost) : ce que l'ENVOI a fait devant un deplacement de l'owner (etat non pose,
# deplacement rattrape apres coup) ; et le motif, ecrit UNE fois, du deplacement qu'on ne peut pas attribuer sous la cle
# de l'owner. `owner_moves` d'un item garde les MOVES_KEPT derniers deplacements traites, par id d'historique Linear.
PUSH_GUARD = []
AMBIGUOUS = "repli sous la cle de l'owner sans dernier passage"
MOVES_KEPT = 20


def is_usage_limit(e):
    return "USAGE_LIMIT_EXCEEDED" in str(e)


def is_missing_issue(e):
    return "Entity not found" in str(e)


def _rec_of(issue_id):
    for k, v in (_CTX["mp"] or {}).items():
        if not k.startswith("_") and isinstance(v, dict) and v.get("issue_id") == issue_id:
            return k, v
    return None, None


def _name(issue_id):
    k, v = _rec_of(issue_id)
    return "%s (%s)" % (v.get("identifier"), k) if v else issue_id


def fail(what, e):
    """Un appel Linear qui echoue sur UN ticket ou UNE etape est compte et NOMME ; le passage continue."""
    FAILED.append("%s : %s" % (what, str(e)[:160]))
    print("ECHEC LINEAR NOMME : %s : %s ; la synchro continue" % (what, str(e)[:300]))


def guard(what, fn, default=None):
    try:
        return fn()
    except Exception as e:  # noqa: BLE001 — une etape qui tombe ne fait plus tomber tout le passage
        fail(what, e)
        return default


def with_room(L, fn, what):
    """Un appel que la limite d'espace peut refuser : on fait de la place (archivage) puis UNE nouvelle
    tentative. Un second refus remonte a l'appelant, qui le nomme."""
    try:
        r = fn()
    except RuntimeError as e:
        if not is_usage_limit(e):
            raise
        print("LIMITE D'ESPACE LINEAR atteinte sur %s : archivage puis une nouvelle tentative" % what)
        make_room(L, force=True, refused=True)
        r = fn()
    note_accepted(L, what)
    return r


def relax_learned(st, seen, why, now):
    """`seen` tickets actifs que Linear a laisses exister (None : aucun compte). Au-dela de la limite apprise, elle est
    fausse (l'owner a change de plan) ; passe LEARNED_TTL_S, elle est re-sondee. Rend True si elle est tombee."""
    ll = int(st.get("learned_limit") or 0)
    if not ll:
        return False
    if seen is not None:
        st["accepted_max"] = max(int(st.get("accepted_max") or 0), seen)
    age = now - float(st.get("learned_at") or 0)   # une limite sans date (d'avant ce code) est d'age inconnu : re-sondee
    if seen is not None and seen > ll:
        why = "Linear a laisse exister %d tickets actifs (%s), au-dela de la limite apprise de %d" % (seen, why, ll)
    elif age >= LEARNED_TTL_S:
        why = "limite apprise de %d vieille de %d h : re-sondee" % (ll, age // 3600)
    else:
        return False
    print("LIMITE LINEAR RELEVEE : %s ; retour a %d, le prochain refus la reapprendra" % (why, SPACE_LIMIT))
    for k in ("learned_limit", "learned_at", "accepted_max"):
        st.pop(k, None)
    st.update(learned_dropped_at=now, learned_dropped_from=ll, learned_dropped_why=why)
    return True


def note_accepted(L, what):
    """Apres une creation ou un desarchivage ACCEPTE, si une limite apprise est en place : Linear vient d'accepter le
    compte d'aujourd'hui, une limite apprise plus basse tombe. Ne leve jamais : le ticket est cree, la carte attend."""
    try:
        st = _space_state()
        if not st.get("learned_limit"):
            return
        n = count_active(L)
        print("ACCEPTE PAR LINEAR : %s, %d tickets actifs (limite apprise %d)" % (what, n, int(st["learned_limit"])))
        relax_learned(st, n, what, time.time())
        _write_atomic(SPACE_PATH, st)
    except Exception as e:  # noqa: BLE001
        print("LIMITE APPRISE NON RELUE apres %s : %s" % (what, str(e)[:160]))


def on_ticket(L, issue_id, fn, revive=True):
    """UN appel sur UN ticket. Linear repond « Entity not found: Issue » sur un ticket ARCHIVE : on le ressort
    (`revive`) puis on rejoue l'appel une fois ; sinon on le laisse archive, on le NOMME et on rend LEFT_ARCHIVED."""
    try:
        return fn()
    except RuntimeError as e:
        if not is_missing_issue(e):
            raise
        if not revive:
            print("TICKET ARCHIVE LAISSE ARCHIVE : %s (rien a lui dire)" % _name(issue_id))
            return LEFT_ARCHIVED
        with_room(L, lambda: L.q(UNARCHIVE, id=issue_id), "desarchivage de %s" % _name(issue_id))
        (_rec_of(issue_id)[1] or {}).pop("harness_archived_at", None)
        print("TICKET ARCHIVE RESSORTI : %s (un message ou une mise a jour lui etait destine)" % _name(issue_id))
        return fn()


def _space_state():
    try:
        return json.loads(SPACE_PATH.read_text())
    except (OSError, ValueError):
        return {}


def _pages(L, query, **v):
    """Tous les noeuds de la connexion `issues`, page par page."""
    out, after = [], None
    while True:
        pg = L.q(query, a=after, **v)["issues"]
        out += pg["nodes"]
        if not pg["pageInfo"]["hasNextPage"]:
            return out
        after = pg["pageInfo"]["endCursor"]


def count_active(L):
    """Ce que Linear compte contre la limite : tous les tickets NON archives de l'espace, clos compris."""
    return len(_pages(L, 'query($a:String){ issues(first:250, after:$a){ pageInfo { hasNextPage endCursor } nodes { id } } }'))


def kept_ids():
    """Tickets jamais archives par la synchro : celui d'un chantier dont l'etat cible n'est pas clos."""
    bl, mp = _CTX["bl"], _CTX["mp"] or {}
    if bl is None:
        return set()
    return {mp[it["id"]]["issue_id"] for it in bl.items
            if it["id"] in mp and target_state(bl, it) not in ("Done", "Canceled")}


def archivable(L, keep):
    """Tickets clos (termines, annules) non archives : ceux de NOTRE equipe d'abord, puis ceux des autres equipes de
    l'espace (la limite est celle de l'espace : le 23/09 il y avait aussi des JAU-*), chaque groupe du plus ANCIEN au
    plus recent. Jamais : le ticket d'un chantier encore ouvert du backlog, ni un ticket qui porte « A traiter »."""
    todo = _CTX.get("todo")
    nodes = _pages(L, 'query($a:String){ issues(first:250, after:$a, filter:{state:{type:{in:["completed","canceled"]}}}){ '
                      'pageInfo { hasNextPage endCursor } nodes { id identifier completedAt canceledAt updatedAt '
                      'team { id } labels { nodes { id } } } } }')
    c = [n for n in nodes if n["id"] not in keep
         and not (todo and todo in [l["id"] for l in ((n.get("labels") or {}).get("nodes") or [])])]
    c.sort(key=lambda n: (bool(_CTX.get("team")) and ((n.get("team") or {}).get("id") != _CTX["team"]),
                          n.get("completedAt") or n.get("canceledAt") or n.get("updatedAt") or ""))
    return c


def make_room(L, force=False, refused=False, dry=False):
    """Recense l'espace (au plus toutes les SPACE_EVERY_S, sauf `force`) ; au-dela de SPACE_HIGH de la limite,
    archive les tickets clos les plus anciens jusqu'a SPACE_LOW, un par un, chacun journalise. `refused` :
    Linear vient de refuser (USAGE_LIMIT_EXCEEDED), la limite reelle est donc au plus le compte d'aujourd'hui."""
    st = _space_state()
    now = time.time()
    if not force and now - float(st.get("checked") or 0) < SPACE_EVERY_S:
        return None
    active = count_active(L)
    relax_learned(st, active, "recensement", now)
    limit = min(SPACE_LIMIT, int(st.get("learned_limit") or SPACE_LIMIT))
    if refused and active < limit:
        print("LIMITE LINEAR APPRISE : refus a %d tickets actifs, sous la limite supposee de %d" % (active, limit))
        limit = st["learned_limit"] = max(active, 1)
        st.update(learned_at=now, accepted_max=active)
    high, low = int(limit * SPACE_HIGH), int(limit * SPACE_LOW)
    before, done, left = active, [], None
    if active >= high:
        cand = archivable(L, kept_ids())
        print("ESPACE LINEAR : %d tickets actifs sur %d (seuil %d) : archivage des tickets clos les plus anciens "
              "jusqu'a %d%s" % (active, limit, high, low, " (simulation)" if dry else ""))
        for n in cand:
            if active < low:
                break
            if not dry:
                try:
                    L.q('mutation($id:String!){ issueArchive(id:$id){ success } }', id=n["id"])
                except RuntimeError as e:
                    fail("archivage de %s" % n["identifier"], e)
                    continue
                # Sous la cle de l'owner (repli), l'historique Linear attribue CET archivage a l'owner : la marque dit
                # qu'il est du harnais, et `pull_owner` ne le prend pas pour une decision.
                rec = _rec_of(n["id"])[1]
                if rec is not None:
                    rec["harness_archived_at"] = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
            active -= 1
            done.append(n["identifier"])
            print("  %s %s (clos le %s)" % ("ARCHIVERAIT" if dry else "ARCHIVE AUTO :", n["identifier"],
                                           (n.get("completedAt") or n.get("canceledAt") or "?")[:10]))
        left = len(cand) - len(done)
        if active >= high:
            print("ESPACE LINEAR SATURE : %d actifs sur %d apres archivage, plus aucun ticket clos a archiver" % (active, limit))
    st.update({"checked": now, "active_before": before, "active": active, "limit": limit, "high": high, "low": low,
               "archived": len(done), "archived_list": done[:60], "archivable_left": left, "code": CODE_FP,
               "learned_ttl_s": LEARNED_TTL_S})
    if not dry:
        _write_atomic(SPACE_PATH, st)
    print("ESPACE LINEAR : %d/%d tickets actifs (seuil %d, cible %d) ; %d archive(s) ce passage"
          % (active, limit, high, low, len(done)))
    return st


def refresh_prompt(it):
    """Refabrique la consigne SEULEMENT si c'est la notre et qu'elle est perimee. Une consigne ecrite a la main
    (prompt_state 'a-la-main') ne s'ecrase jamais : le 17/09 neuf consignes manuelles ont ete ecrasees par erreur."""
    st = B.prompt_state(it)
    if st in ("perime", "absent"):
        B.write_prompt(it)
    elif st == "a-la-main":
        print("  consigne ECRITE A LA MAIN pour %s : non touchee (l'item a bouge, a relire par le superviseur)" % it["id"])


def project_for(item_id):
    return PROJECTS.get(item_id.split("-")[0], "Divers")


def last_verdict(item_id):
    d = AP / "logs" / item_id
    if not d.is_dir():
        return ""
    files = sorted(d.glob("validator-*.txt"), key=lambda p: p.stat().st_mtime)
    if not files:
        return ""
    for line in files[-1].read_text(errors="replace").splitlines():
        line = line.strip()
        if line and "constat(s) ci-dessus" not in line:
            t = dt.datetime.fromtimestamp(files[-1].stat().st_mtime).strftime("%d/%m %H:%M")
            line = line.replace("[%s FAIL]" % item_id, "ÉCHEC :").replace("[%s ok]" % item_id, "OK :")
            return "%s — %s" % (t, line[:300])
    return ""


def eligible(bl, it):
    return all((bl.get(d) or {}).get("status") == "validated" for d in (it.get("depends_on") or []))


def target_state(bl, it):
    s = it["status"]
    if s == "open":
        return "Todo" if eligible(bl, it) else "Backlog"
    if s == "in-progress":
        return "In Progress"
    if s == "to-test":
        return "In Review"
    if s == "blocked":
        return "À arbitrer"
    if s == "validated":
        return "Done"  # owner 17/09 : Validé et Done c'est redondant ; l'accord de l'owner est une etiquette
    return "Canceled"


def priority_for(bl, it):
    s = it["status"]
    if s in ("in-progress", "to-test"):
        return 1
    if s == "blocked":
        return 2
    if s == "open":
        return 2 if eligible(bl, it) else 3
    return 0


def last_activity(it):
    dates = []
    for h in it.get("history") or []:
        if isinstance(h, dict) and h.get("date"):
            dates.append(str(h["date"])[:10])
    gv = it.get("gate_verdict") or {}
    if isinstance(gv, dict) and gv.get("date"):
        dates.append(str(gv["date"])[:10])
    for f in it.get("owner_feedback") or []:
        if isinstance(f, dict) and f.get("date"):
            dates.append(str(f["date"])[:10])
    return max(dates) if dates else ""


def wanted(it, today):
    if it["status"] in ("open", "in-progress", "to-test", "blocked"):
        return True
    la = last_activity(it)
    if not la:
        return False
    try:
        return (today - dt.date.fromisoformat(la)).days <= SINCE_DAYS
    except ValueError:
        return False


def description(bl, it, retries):
    s = it["status"]
    lines = []
    where = (it.get("where") or "").strip()
    if where and s != "archived":
        lines += ["**Où regarder / à tester**", where, ""]
    n = retries.get(it["id"])
    essais = "%s/%s essais" % (n if n is not None else 0, it.get("max_retries", 6)) if s in ("open", "in-progress", "blocked") else ""
    lines += ["**État** : %s%s" % (STATUS_FR.get(s, s), (" — " + essais) if essais else "")]
    if s == "blocked" and it.get("block_reason"):
        lines += ["**À arbitrer parce que** : " + str(it["block_reason"]).strip()[:600]]
    lv = last_verdict(it["id"])
    if lv:
        lines += ["**Dernier verdict machine** : " + lv]
    deps = [d for d in (it.get("depends_on") or []) if (bl.get(d) or {}).get("status") != "validated"]
    if deps:
        lines += ["**Attend d'abord** : " + ", ".join((bl.get(d) or {}).get("feature", d) for d in deps)]
    if it.get("known_cause") and s in ("open", "in-progress", "blocked"):
        lines += ["", "**Ce qu'on sait** : " + str(it["known_cause"]).strip().split("\n\n")[0][:900]]
    fb = it.get("owner_feedback") or []
    if fb:
        lines += ["", "**Tes retours**"]
        for f in fb[-6:]:
            if isinstance(f, dict):
                lines += ["- %s : « %s »" % (f.get("date", "?"), str(f.get("text", "")).strip()[:700])]
    spec = it.get("spec") or ""
    doc = (MAP_DOCS.get(os.path.basename(spec)) or {}).get("url") if spec else None
    lines += ["", "---", (KEY_FMT + " — rang %s — spec : %s") % (it["id"], it.get("priority"), ("[%s](%s)" % (os.path.basename(spec), doc)) if doc else (spec or "—"))]
    return "\n".join(lines)


def needs_build(it):
    """Un chantier se teste-t-il sur un build du jeu ? Non pour un chantier du harnais : sa preuve
    est un crochet `lib/census/<id>.sh` (ou son id commence par harness-), rien n'est a installer."""
    iid = it.get("id") or ""
    if it.get("code_scope") == "harness" or iid.startswith("harness-"):
        return False
    if "rien a installer" in (it.get("where") or "").lower().replace("à", "a"):
        return False
    # 19/09 20:15 : un crochet lib/census/<id>.sh ne dit PAS « pas de build » — les items de JEU en ont
    # un aussi (grass-blade-variants). Le test sur le crochet a fait taire l'annonce d'un vrai build.
    return True


def plain_state_comment(bl, it, st):
    """Commentaire de changement de colonne en francais courant. Owner 17/09, devant « OK : source=device
    sha=… frames=… ; ao_tie_prepass_defects == 0 tenu » : « Genre je suis sensé comprendre ce que je dois
    vérifier avec ce commentaire ? »."""
    where = (it.get("where") or "").strip()
    lv = last_verdict(it["id"])
    frames = ""  # owner 17/09 : les comptes d'images n'aident personne
    if st == "In Review" and not needs_build(it):
        # Owner 17/09 21:50, sur un chantier du harnais : « je vois pas pourquoi on devrait attendre
        # qu'un build soit publié pour ça ». Un chantier qui ne touche pas le jeu se teste tout de suite.
        return "→ **À tester par toi, tout de suite** : ce chantier ne touche pas le jeu, il n'y a rien à installer.\n\n**Où regarder** : %s" % (where or "voir la description du ticket")
    if st == "In Review":
        return "→ **À tester par toi**%s. Attends le commentaire « build publié » ci-dessous : il dit quel build de jak-builds porte ce chantier (jak-builds ne garde que le dernier).\n\n**Où regarder** : %s" % (frames, where or "voir la description du ticket")
    if st == "Done":
        return "→ **Terminé**%s. %s" % (frames, "Rien à te montrer : c'est une mesure ou une fondation." if not it.get("owner_test") else "")
    if st == "In Progress":
        try:
            backend = json.loads((AP / ".backend.json").read_text()).get("backend", "claude")
        except Exception:  # noqa: BLE001
            backend = "claude"
        who = {"claude": "Claude", "codex": "Codex"}.get(backend, backend)
        n = None
        try:
            n = (json.loads(STATE_JSON.read_text()).get("retries") or {}).get(it["id"])
        except Exception:  # noqa: BLE001
            pass
        essai = " — essai %d sur %s" % (int(n) + 1, it.get("max_retries", 6)) if isinstance(n, int) else " — essai 1 sur %s" % it.get("max_retries", 6)
        return "→ **En cours** : le harnais (agent %s) y travaille%s." % (who, essai)
    if st == "Todo":
        return "→ **Prêt à démarrer** : plus rien ne le bloque, il attend son tour (rang %s)." % it.get("priority")
    if st == "Backlog":
        deps = [d for d in (it.get("depends_on") or []) if (bl.get(d) or {}).get("status") != "validated"]
        return "→ **En attente** de : %s." % ", ".join((bl.get(d) or {}).get("feature", d) for d in deps) if deps else "→ **En attente**."
    if st == "À arbitrer":
        why = str(it.get("block_reason") or "").strip()
        if why.startswith("max_retries"):
            why = "tous les essais accordés sont consommés sans passer la mesure"
        return "→ **À arbitrer** : %s. Une décision est attendue : rouvrir avec une nouvelle piste, redécouper, ou archiver." % (why[:300] or "la machine s'est arrêtée dessus")
    if st == "Canceled":
        return "→ **Archivé** : abandonné ou supplanté, il ne sera pas fait."
    return "→ **%s**" % st


def ensure_team(L):
    d = L.q("{ teams { nodes { id key name } } }")
    for t in d["teams"]["nodes"]:
        if t["key"] == TEAM_KEY:
            return t["id"]
    d = L.q('mutation($n:String!,$k:String!){ teamCreate(input:{name:$n,key:$k}) { team { id } } }', n=TEAM_NAME, k=TEAM_KEY)
    return d["teamCreate"]["team"]["id"]


def ensure_states(L, team_id):
    d = L.q('query($t:String!){ team(id:$t){ states { nodes { id name type } } } }', t=team_id)
    have = {s["name"]: s for s in d["team"]["states"]["nodes"]}
    out = {}
    pos = 0
    for name, typ in STATES:
        pos += 1
        if name in have:
            out[name] = have[name]["id"]; continue
        r = L.q('mutation($i:WorkflowStateCreateInput!){ workflowStateCreate(input:$i){ workflowState { id } } }',
                i={"teamId": team_id, "name": name, "type": typ, "position": pos, "color": "#95a2b3"})
        out[name] = r["workflowStateCreate"]["workflowState"]["id"]
    return out


# 23/09 (harness-linear-archived-structures-not-recreated) : une COLLECTION Linear (`team{projects}`,
# `team{labels}`, `customViews`) ecarte en silence ce qui est archive sans `includeArchived:true`. Un projet,
# une etiquette ou une vue que l'owner a archive etait donc INVISIBLE et aurait ete RECREE au premier passage
# sans cache (`_ids` absent de la carte : poste neuf, `git reset` de linear_map.json). Regle commune aux trois :
# le nom existe, actif -> on le reprend ; archive (ou a la corbeille) -> c'est le choix de l'owner, on ne le
# recree pas et on rend None (la fonction qui s'en sert se tait).
def _archived(n):
    return bool(n.get("archivedAt") or n.get("trashed"))


def ensure_projects(L, team_id):
    d = L.q('query($t:String!){ team(id:$t){ projects(first:250, includeArchived:true) { nodes { id name archivedAt trashed } } } }', t=team_id)
    nodes = d["team"]["projects"]["nodes"]
    have = {p["name"]: p["id"] for p in nodes if not _archived(p)}
    gone = {p["name"] for p in nodes if _archived(p)} - set(have)
    for name in sorted(set(PROJECTS.values()) | {"Divers"}):
        if name not in have and name not in gone:
            r = L.q('mutation($i:ProjectCreateInput!){ projectCreate(input:$i){ project { id } } }',
                    i={"name": name, "teamIds": [team_id]})
            have[name] = r["projectCreate"]["project"]["id"]
    return have


LABEL_READ = "À lire : réponse du harnais"
LABEL_TODO = "À traiter : retour de l'owner"
LABEL_TALK = "En discussion"
LABEL_OK = "Sans revue (machine)"  # owner 17/09 : marquer ceux que la machine passe Done seule, pas l'inverse


def ensure_label(L, team_id, name=LABEL_READ, color="#f2994a"):
    d = L.q('query($t:String!){ team(id:$t){ labels(first:250, includeArchived:true) { nodes { id name archivedAt } } } }', t=team_id)
    same = [l for l in d["team"]["labels"]["nodes"] if l["name"] == name]
    for l in same:
        if not _archived(l):
            return l["id"]
    if same:
        return None   # archivee par l'owner : pas de recreation
    r = L.q('mutation($i:IssueLabelCreateInput!){ issueLabelCreate(input:$i){ issueLabel { id } } }',
            i={"teamId": team_id, "name": name, "color": color})
    return r["issueLabelCreate"]["issueLabel"]["id"]


def ensure_view(L, team_id, label_id, name="À lire", icon="Inbox", color="#f2994a",
                desc="Tickets où le harnais t'a répondu et que tu n'as pas encore relus. L'étiquette tombe dès que tu commentes."):
    """Une vue PRIVEE n'est lue que par son createur. Les trois vues de l'owner ont ete creees sous sa cle le
    17/09 (07:36-07:48, `shared:false`) ; a la bascule vers l'identite d'application (19:17:56), `customViews` ne
    les rendait plus et l'application en a cree trois copies privees, que PERSONNE ne voit. On lit donc aussi
    sous la cle personnelle (comme `owner_user_id`) ; si elle manque ou echoue, l'absence n'est pas prouvee et
    on ne cree rien. Une vue creee l'est partagee (`shared`) : sous l'application, une vue privee est perdue.
    Le filtre d'equipe compte aussi : « En discussion » existe dans l'equipe JAU."""
    q = '{ customViews(first:250, includeArchived:true) { nodes { id name archivedAt team { id } } } }'
    views = list(L.q(q)["customViews"]["nodes"])
    if getattr(L, "mode", "owner") == "app":
        key = LI.load_env().get("LINEAR_API_KEY")
        try:
            views += LI.gql(key, q)["customViews"]["nodes"]
        except Exception:  # noqa: BLE001  (cle absente comprise)
            return None   # vues de l'owner illisibles : on ne sait pas si la sienne existe
    same = [v for v in views if v["name"] == name and (v.get("team") or {}).get("id") == team_id]
    for v in same:
        if not _archived(v):
            return v["id"]
    if same or not label_id:
        return None   # archivee par l'owner, ou son etiquette l'est : pas de recreation
    r = L.q('mutation($i:CustomViewCreateInput!){ customViewCreate(input:$i){ customView { id } } }',
            i={"name": name, "teamId": team_id, "icon": icon, "color": color, "description": desc, "shared": True,
               "filterData": {"labels": {"some": {"id": {"eq": label_id}}}}})
    return r["customViewCreate"]["customView"]["id"]


def swap_labels(L, issue_id, add=None, remove=None):
    """Pose `add`, retire `remove` (un id d'etiquette ou une liste d'ids), en une ecriture. Sur un ticket archive, la lecture passe
    mais l'ecriture rend « Entity not found » : `on_ticket` le ressort et rejoue le tout."""
    on_ticket(L, issue_id, lambda: _swap_labels(L, issue_id, add, remove))


def _swap_labels(L, issue_id, add, remove):
    iss = L.q('query($id:String!){ issue(id:$id){ labels { nodes { id } } } }', id=issue_id).get("issue")
    if iss is None:
        raise RuntimeError("Entity not found: Issue (lecture nulle)")
    ids = [l["id"] for l in iss["labels"]["nodes"]]
    rm = set(remove) if isinstance(remove, (list, tuple, set)) else {remove}
    want = [i for i in ids if i not in rm]
    if add and add not in want:
        want.append(add)
    talk = _TALK.get("id")
    if add and talk and talk not in want and add in (_TALK.get("read"), _TALK.get("todo")):
        want.append(talk)
    if sorted(want) != sorted(ids):
        L.q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }', id=issue_id, i={"labelIds": want})


def set_read_label(L, issue_id, label_id, on):
    swap_labels(L, issue_id, add=label_id if on else None, remove=None if on else label_id)


_TALK = {}


def labels(L, team):
    read = ensure_label(L, team, LABEL_READ, "#f2994a")
    todo = ensure_label(L, team, LABEL_TODO, "#eb5757")
    talk = ensure_label(L, team, LABEL_TALK, "#5e6ad2")
    _TALK["id"] = talk; _TALK["read"] = read; _TALK["todo"] = todo
    _TALK["ok"] = ensure_label(L, team, LABEL_OK, "#95a2b3")
    ensure_view(L, team, read)
    ensure_view(L, team, todo, name="À traiter", icon="Inbox", color="#eb5757",
                desc="Tes retours que le harnais n'a pas encore traités. L'étiquette tombe quand il te répond.")
    ensure_view(L, team, talk, name="En discussion", icon="Inbox", color="#5e6ad2",
                desc="Tous les tickets où l'un de nous deux a parlé en dernier. Pour clore sans répondre : retire « À lire » du ticket, « En discussion » tombe à la synchro suivante (5 min).")
    return read, todo


# ====================================================== QUI PARLE, ET COMMENT ON LE SAIT ======
# Le harnais et l'owner ont longtemps ete le MEME compte Linear : la seule facon de les
# distinguer etait le prefixe « 🤖 » du CORPS du message. Un marqueur de texte n'est pas une
# identite. Il se colle a la main, il disparait a la copie, et surtout il ne produit aucune
# notification : l'owner recevait ses propres messages (JAK-180, 17/09).
#
# Sous l'identite d'application (voir `linear_identity.py`), Linear attache a chaque commentaire
# un `botActor` : un AUTEUR, produit par le serveur, que rien dans un corps de message ne peut
# imiter. C'est lui qui tranche desormais.
#
# LE MARQUEUR RESTE ECRIT, ET IL RESTE LU — pas par nostalgie, pour deux raisons :
#   1. il n'est plus ECRIT sous l'application (owner 17/09 21:35 : « vire l'emoji bot ») ;
#   2. NON-DESTRUCTION : les centaines de commentaires postes AVANT la bascule portent
#      `botActor: null` et l'identifiant de l'owner. Sans le repli sur le marqueur, la premiere
#      synchro apres la bascule les relirait TOUS comme des retours de l'owner et les deverserait
#      dans `owner_feedback`. On rend la perte impossible au point de production.

def comment_author(c):
    """('app', id) | ('user', id) | ('inconnu', None) — l'auteur tel que le SERVEUR le rend.

    DEUX formes d'auteur non-humain, et il a fallu les mesurer pour le savoir (17/09) :
      - `botActor` : les integrations (Slack, GitHub) ;
      - `user { app: true }` : une application OAuth qui parle en son nom. C'est NOTRE cas —
        l'application apparait comme un utilisateur du workspace dont l'adresse finit par
        « @oauthapp.linear.app ». Attendre un `botActor` ici, c'est ne rien voir."""
    bot = c.get("botActor") or {}
    if bot.get("id"):
        return "app", bot["id"]
    u = c.get("user") or {}
    if u.get("id"):
        return ("app" if u.get("app") else "user"), u["id"]
    return "inconnu", None


def is_harness_comment(c):
    """Nous. D'abord l'auteur ; le marqueur seulement pour l'avant-bascule."""
    kind, _ = comment_author(c)
    if kind == "app":
        return True
    return (c.get("body") or "").startswith(MARK)


def is_owner_comment(c, owner_id=None):
    """Un retour de l'OWNER : un humain, et CET humain-la.

    Quand on sait qui est l'owner, un commentaire d'un tiers invite dans le workspace n'est pas
    un retour de l'owner et n'a rien a faire dans `owner_feedback`. Un auteur INCONNU qui n'est
    pas nous reste compte comme owner : perdre un retour coute plus cher qu'en lire un de trop."""
    if is_harness_comment(c):
        return False
    kind, who = comment_author(c)
    if owner_id and kind == "user":
        return who == owner_id
    return True


def owner_user_id(L, mp):
    """L'identifiant de l'owner, releve UNE fois et garde dans `linear_map.json`.

    Il FAUT le relever tant qu'on tient encore la cle personnelle : sous l'identite
    d'application, `viewer` ne designe plus un humain et l'information serait hors d'atteinte."""
    rec = mp.get("_owner") or {}
    if rec.get("user_id"):
        return rec["user_id"]
    if getattr(L, "mode", "owner") != "app":
        d = L.q("{ viewer { id name email } }")["viewer"]
    else:
        # Sous l'identite d'application, `viewer` est l'APPLICATION : il ne dira jamais qui est
        # l'owner. On le releve alors avec la cle personnelle, qui reste dans linear.env pour
        # exactement cet usage. Sans ce repli, un poste neuf (carte vide) partirait avec un
        # owner INCONNU et perdrait la distinction « l'owner » / « un tiers ».
        key = LI.load_env().get("LINEAR_API_KEY")
        if not key:
            return None
        try:
            d = LI.gql(key, "{ viewer { id name email } }")["viewer"]
        except Exception:  # noqa: BLE001
            return None
    mp["_owner"] = {"user_id": d["id"], "name": d.get("name"), "email": d.get("email")}
    return d["id"]


def post_comment(L, issue_id, body, parent=None, capture_failed=""):
    """LE SEUL endroit d'ou le harnais poste un commentaire.

    Il y en avait CINQ, chacun portant sa copie de la mutation. Une bascule d'identite aurait
    tenu dans quatre et laisse le cinquieme parler sous l'owner sans que rien ne rougisse.
    L'identite elle-meme ne se pose pas ici : elle est portee par le JETON (`Linear.__init__`),
    donc par toutes les ecritures a la fois, commentaires compris.

    `parent` : le fil ou le message REPOND a l'owner. Seul `--comment` le passe (`--reply-to`, ou par
    defaut le dernier retour ouvert : `default_reply_target`) ; c'est
    ce fil, et lui seul, qui compte comme reponse a son retour (`lib/owner_sla.answer_how`)."""
    # INVISIBLE-CAPTURE/ filet du point de production (23/09) : un chantier hors champ ne parle ni de
    # capture ni de build a tester, quel que soit l'appelant (annonce de verdict qui relaie le rapport
    # et joint les images de notes/, relances...). `--comment` a deja REFUSE ce que le worker a ecrit.
    _iid = _rec_of(issue_id)[0] or ""
    try:
        _it = ((_CTX.get("bl") or B.load()).get(_iid) or {}) if _iid else {}
    except Exception:  # noqa: BLE001 — backlog illisible : l'item est traite comme visible (rien retire)
        _it = {}
    _vis = OCAP.is_visible(_it)[0] if _it else None
    body, _stripped = OCAP.scrub_invisible(_it, body)
    if _stripped:
        print("INVISIBLE-CAPTURE : %d passage(s) parlant de capture/build a tester retire(s) du message sur %s "
              "(chantier hors champ)" % (_stripped, _iid))
    if not body.strip():
        print("INVISIBLE-CAPTURE : message vide apres retrait, rien n'est poste sur %s" % _iid)
        return None
    i = {"issueId": issue_id, "body": body}
    if parent:
        i["parentId"] = parent
    r = on_ticket(L, issue_id, lambda: L.q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success comment { id } } }',
                                           i=i))
    # LE REGISTRE DES COMMENTAIRES, ecrit ICI parce que c'est le seul point de production : la porte
    # de fermeture (`lib/owner_capture`) y lit si l'essai a joint une capture a son ticket.
    # Un registre qui tombe ne fait pas tomber le message deja poste : il est NOMME.
    if r is LEFT_ARCHIVED:
        return r   # rien n'est parti : rien a inscrire
    try:
        cid = (((r or {}).get("commentCreate") or {}).get("comment") or {}).get("id", "") if isinstance(r, dict) else ""
        OCAP.record(HOME, _iid, body, issue_id=issue_id, comment_id=cid, capture_failed=capture_failed,
                    visible=_vis, talk=OCAP.capture_talk(_it, body) if _it else [], stripped=_stripped)
    except Exception as e:  # noqa: BLE001
        print("REGISTRE DES COMMENTAIRES NON ECRIT : %s" % str(e)[:200])
    return r


def reply_target(L, bl, iid, ref):
    """(ticket, fil) ou poster la reponse au retour `ref` de l'owner sur l'item `iid`.

    `ref` = l'identifiant du commentaire Linear de l'owner (`owner_feedback[].via.comment`), ou
    `last` = son dernier retour recopie avec un identifiant. Refuse un commentaire qui n'est pas de
    l'owner : repondre « dans le fil » d'un message du harnais n'adresse rien a personne."""
    if ref == "last":
        fb = [f for f in ((bl.get(iid) or {}).get("owner_feedback") or [])
              if isinstance(f, dict) and isinstance(f.get("via"), dict) and f["via"].get("comment")]
        if not fb:
            raise SystemExit("--reply-to last : aucun retour de l'owner recopie de Linear sur %s" % iid)
        ref = fb[-1]["via"]["comment"]
    d = L.q('query($c:String!){ comment(id:$c){ id parentId issue { id } user { id app } botActor { id } body } }', c=ref)
    c = d.get("comment") or {}
    if not c.get("id") or is_harness_comment(c):
        raise SystemExit("--reply-to %s : ce n'est pas un commentaire de l'owner" % ref)
    # Linear n'a qu'un niveau de fil : un retour poste en reponse a un message y reste.
    return (c.get("issue") or {}).get("id"), (c.get("parentId") or c["id"])


def default_reply_target(L, bl, mp, iid):
    """(ticket, fil, retour) : le dernier retour de l'owner encore OUVERT sur `iid`, ou None.

    Les workers postent leur fin d'essai par `--comment` sans `--reply-to` : hors fil, leur reponse
    n'eteignait aucun retour (`owner_sla.answer_how`, 23/09). Le fil est donc choisi ICI, au point de
    production, par la definition du compteur (`owner_sla.open_records`), relue EN DIRECT sur le
    ticket : le releve de la veille a jusqu'a 10 min de retard. Linear illisible -> ce releve."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from lib import owner_sla as O                             # noqa: PLC0415
    it = bl.get(iid)
    if it is None:
        return None
    try:
        rows = O.rows_from_backlog([it], mp)
        if not rows:
            return None
        fetch, is_own, is_har = O.linear_sources(L, owner_user_id(L, mp), tickets=[r["ticket"] for r in rows])
        records = O.collect(rows, fetch, is_own, is_har)
    except Exception as e:  # noqa: BLE001
        print("fil de reponse non relu en direct (%s) : releve de la veille" % str(e)[:160])
        records = O.load_cache()[0]
    return O.default_reply(records, iid)


def _say(L, rec, text):
    post_comment(L, rec["issue_id"], mark(L) + text)


def apply_owner_move(L, bl, iid, rec, here, ev=None):
    """Un deplacement de ticket fait par l'owner est une DECISION : le backlog suit, et on le dit.
    Owner 17/09 : « si je change un status de ticket moi même […] ça serait con que ce soit systématiquement écrasé ».

    23/09 : la decision se prend SOUS LE VERROU, sur l'item RELU du disque (`Backlog.update`), jamais sur la copie
    chargee en debut de passe : un statut pose par l'orchestrateur ou une note ajoutee par le superviseur entre-temps
    etaient ecrases (notes recomposees depuis la memoire, statut ramene en arriere). Les messages suivent la decision
    RELUE. Voir `lib/census/harness-linear-owner-move-reads-fresh-item.sh`.

    `ev` (l'evenement d'historique Linear) : son id est ECRIT dans l'item (`owner_moves`) sous le meme verrou que la
    decision, et un id deja present n'est jamais re-applique. La trace vit avec l'effet : une carte (et son cliche)
    reculee sous `state_at` ne refait plus le deplacement (priorite remise en tete, « Noté. » repete) ; un backlog
    recule efface l'effet ET la trace, et le deplacement se refait, ce qui est juste."""
    if bl.get(iid) is None:
        return bl
    today = dt.date.today().isoformat()
    via = {"source": "move", "ticket": rec["issue_id"]}
    sha = B.build_sha() if here == "Done" else None   # hors verrou : git n'a rien a faire sous lui

    ev_id = (ev or {}).get("id")

    def decide(t, items):
        s = t.get("status")
        if here == "Done":
            if t.get("owner_ok"):
                return None
            e, champs = B.validation_fields("Déplacé en « Done » dans Linear par l'owner", today, sha, via)
            B.fb_append(t, e, skip_same_text=True)
            t.update(champs)
            return ("done", s)
        if here == "Canceled":
            if s == "archived":
                return None
            t["status"] = "archived"
            t["notes"] = ((t.get("notes") or "").rstrip() + "\n%s : archivé par l'owner dans Linear." % today).strip()
            return ("archived", s)
        if here == "À arbitrer":
            if s == "in-progress":
                B.fb_append(t, {"date": today, "text": "[Linear] déplacé en « À arbitrer » pendant un essai : sera mis de côté à la fin de l'essai en cours",
                                "via": dict(via)})
                return ("arbitrate-running", s)
            if s == "blocked":
                return None
            t["status"] = "blocked"
            t["block_reason"] = "Bloqué par l'owner dans Linear le %s" % today
            return ("blocked", s)
        if here in ("Backlog", "Todo", "In Progress"):
            reopen = s in ("blocked", "to-test", "validated", "archived")
            if reopen:
                t["status"] = "open"
                if s == "validated":
                    t["owner_ok"] = None
            if here in ("Todo", "In Progress"):
                opens = [x.get("priority") for x in items if x.get("status") == "open" and isinstance(x.get("priority"), int)]
                t["priority"] = (min(opens) - 1) if opens else 0
            elif not reopen:
                return None
            return ("reopen" if reopen else "priority", s)
        return None

    def once(t, items):
        if ev_id in moves_traced(t):
            return ("already", t.get("status"))
        r = decide(t, items)
        _trace(t, ev, here, r[0] if r else "noop")
        return r or ("noop", t.get("status"))

    decision = None
    if ev_id:
        decision = bl.update(iid, once)
    elif here in ("Done", "Canceled", "À arbitrer", "Backlog", "Todo", "In Progress"):
        decision = bl.update(iid, decide)
    act, s = decision or (None, None)
    if act == "already":
        print("  deplacement deja applique sur %s (evenement %s) : rien n'est refait" % (iid, ev_id))
        return B.load(bl.path)
    if act == "done":
        _say(L, rec, "Passé Done par ton déplacement : c'est ton feu vert, enregistré tel quel.")
        if _TALK.get("ok"):
            swap_labels(L, rec["issue_id"], remove=_TALK["ok"])
    elif act == "archived":
        _say(L, rec, "Archivé sur ton déplacement : le harnais ne le reprendra plus.")
    elif act == "arbitrate-running":
        _say(L, rec, "Un essai est en cours dessus ; je le bloque dès qu'il se termine, pas au milieu.")
    elif act == "blocked":
        _say(L, rec, "Bloqué sur ton déplacement : le harnais ne le prendra pas tant que tu ne le remets pas dans À faire ou Backlog.")
    elif act in ("reopen", "priority"):
        if act == "reopen" and _TALK.get("ok"):
            swap_labels(L, rec["issue_id"], remove=_TALK["ok"])
        msg = "Rouvert sur ton déplacement." if s != "open" else "Noté."
        if here in ("Todo", "In Progress"):
            msg += " Passé en tête de file : il démarre dès que l'essai en cours se termine (le harnais fait un chantier à la fois)."
        _say(L, rec, msg)
    elif here == "In Review":
        _say(L, rec, "In Review est posé par la machine quand une porte mesurée tient. Je le remets où le backlog le place ; si tu veux forcer, commente ce que tu attends.")
        rec["hash"] = ""  # recalage par la synchro
    bl = B.load(bl.path)
    it = bl.get(iid)
    if it and it["status"] != "archived":
        try:
            refresh_prompt(it)
        except Exception as e:  # noqa: BLE001
            print("  prompt non refabrique pour %s : %s" % (iid, e))
    return bl


def moves_traced(it):
    """Les ids d'historique des deplacements de l'owner deja TRAITES sur cet item (appliques ou nommes)."""
    return {m.get("event") for m in ((it or {}).get("owner_moves") or []) if isinstance(m, dict) and m.get("event")}


def _trace(t, ev, here, act):
    t["owner_moves"] = ([m for m in (t.get("owner_moves") or []) if isinstance(m, dict)]
                        + [{"event": ev["id"], "to": here, "at": ev.get("createdAt"), "act": act}])[-MOVES_KEPT:]


def name_ambiguous_move(L, bl, iid, rec, here, ev):
    """Sous le repli d'identite (cle de l'owner), un changement d'etat signe de son nom sans passage de reference
    (`state_at`) peut etre le sien comme le notre : il n'est pas applique, mais il lui est DIT, une fois par evenement
    (trace `owner_moves`, act « named »). Avant (23/09), il etait perdu sans un mot. -> (backlog, nomme ?)"""
    ev_id = (ev or {}).get("id")
    if not ev_id or bl.get(iid) is None:
        return bl, False

    def once(t, _items):
        if ev_id in moves_traced(t):
            return None
        _trace(t, ev, here, "named")
        return True
    if not bl.update(iid, once):
        return B.load(bl.path), False
    w = ev.get("createdAt") or "????-??-??T??:??"
    _say(L, rec, "Ce ticket est passé en « %s » le %s/%s à %s (heure UTC), mais à ce moment-là je parlais sous ton nom : "
                 "je ne peux pas savoir si c'est toi qui l'as déplacé. Je ne change rien au chantier et le ticket revient où "
                 "il en est. Si c'était bien ton choix, dis-le en commentaire ou redéplace-le : un nouveau déplacement sera suivi."
         % (here, w[8:10], w[5:7], w[11:16]))
    print("  deplacement NOMME a l'owner sur %s (%s, evenement %s) : auteur indistinguable sous sa cle" % (iid, here, ev_id))
    return B.load(bl.path), True


def ticket_state(L, issue_id):
    """L'etat du ticket RELU sur Linear (archives compris) ; None s'il est introuvable."""
    d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:1, includeArchived:true){ nodes { id state { name } } } }',
            ids=[issue_id])
    n = d["issues"]["nodes"]
    return n[0]["state"]["name"] if n else None


def catch_overwritten(L, bl, iid, rec, st, seen):
    """APRES avoir pose `st` : un deplacement de l'owner tombe entre la relecture et l'ecriture a ete ECRASE. Il est
    reconnu dans l'historique (evenements absents de `seen`, anterieurs a NOTRE changement), applique sur-le-champ et
    nomme. -> (date de NOTRE changement d'etat ou None, evenement rattrape ou None)."""
    hist = issue_history(L, rec["issue_id"])
    owner_id = owner_user_id(L, _CTX.get("mp") or {})
    app = getattr(L, "mode", "owner") == "app"
    new = [e for e in hist if e.get("toState") and e.get("id") not in seen]
    ours = next((e for e in new if e["toState"]["name"] == st and (not app or history_author(e, owner_id) == "app")), None)
    if ours is None:
        old = next((e for e in hist if e.get("toState") and e.get("id") in seen), None)
        return (old or {}).get("createdAt"), None
    beaten = [e for e in new if e is not ours and e["createdAt"] <= ours["createdAt"]
              and owner_id and history_author(e, owner_id) == "owner"]
    if not beaten:
        return ours["createdAt"], None
    mv = beaten[0]   # le plus recent : la derniere intention de l'owner
    to = mv["toState"]["name"]
    PUSH_GUARD.append({"iid": iid, "kind": "caught", "event": mv.get("id"), "to": to, "overwritten_by": st})
    print("DEPLACEMENT DE L'OWNER RATTRAPE : %s %s deplace en « %s » (%s) pendant l'envoi de « %s » ; applique"
          % (rec.get("identifier"), iid, to, mv["createdAt"], st))
    apply_owner_move(L, bl, iid, rec, to, ev=mv)
    return ours["createdAt"], mv


def adopted_item(iid, iss):
    """L'item que devient un ticket de l'owner adopte. `code_scope: a-cadrer` (23/09) : il recevait
    `jeu` en dur, et JAK-265 — les profils de modeles, un sujet de HARNAIS — est entre classe « jeu ».
    Le superviseur pose le vrai perimetre en le cadrant (`set_scope`) ; d'ici la, `next_open` le saute."""
    return {"id": iid, "status": "open", "game": "jak1", "priority": 999, "feature": iss["title"].strip()[:200],
            "gate": None, "depends_on": [], "device": False, "owner_test": True, "owner_ok": None,
            "code_scope": B.SCOPE_A_CADRER,
            "max_turns": 600, "max_retries": 6, "proof_timeout": 420, "no_code": True,
            "known_cause": "Ticket cree par l'owner dans Linear le %s. Son texte : %s" % (dt.date.today().isoformat(), (iss.get("description") or "").strip()),
            "notes": B.AWAITING_FRAMING_NOTE,
            "where": "", "deliverable": "", "out_of_scope": "", "spec": None}


def adopt_owner_issues(L, bl, mp, team, todo_id, dry):
    """Un ticket cree par l'owner directement dans Linear devient un item du backlog (owner 17/09 :
    « j'ai ajouté une nouvelle issue et t'en a rien fait c'est pas normal ! »). Il arrive en bas de la pile,
    sans porte : le superviseur est reveille (ligne NOUVEAU TICKET) et le cadre."""
    known = {v["issue_id"] for k, v in mp.items() if not k.startswith("_")}
    nodes, after = [], None
    while True:  # pagine : `first:250` sans suite aurait perdu les tickets au-dela (205 le 23/09)
        d = L.q('query($t:String!,$a:String){ team(id:$t){ issues(first:100, after:$a, filter:{state:{type:{nin:["completed","canceled"]}}}){ '
                'pageInfo { hasNextPage endCursor } nodes { id identifier title description createdAt creator { id app } state { name type } } } } }',
                t=team, a=after)
        page = d["team"]["issues"]
        nodes += page["nodes"]
        if not page["pageInfo"]["hasNextPage"]:
            break
        after = page["pageInfo"]["endCursor"]
    n = 0
    for iss in nodes:
        if iss["id"] in known or iss["state"]["type"] in ("completed", "canceled"):
            continue
        kind, what = classify_unmapped(iss, bl, mp)
        if kind == "relink":
            print("TICKET DU HARNAIS RELIE : %s -> item %s (sa correspondance avait ete perdue ; rien n'est cree)" % (iss["identifier"], what))
            if not dry:
                mp[what] = relinked_rec(iss)
                known.add(iss["id"]); save_map(mp)
            continue
        if kind == "harness":
            print("TICKET DU HARNAIS NON RELIE : %s (%s) — jamais adopte comme ticket de l'owner" % (iss["identifier"], what))
            continue
        base = re.sub(r"[^a-z0-9]+", "-", iss["title"].lower().encode("ascii", "ignore").decode()).strip("-")[:48] or "ticket"
        iid = "owner-" + base
        k = 2
        while bl.get(iid):
            iid = "owner-%s-%d" % (base, k); k += 1
        print("NOUVEAU TICKET OWNER : %s « %s » -> item %s (a cadrer par le superviseur)" % (iss["identifier"], iss["title"][:60], iid))
        if dry:
            continue
        item = adopted_item(iid, iss)
        path = bl.path
        with B._Lock(path):
            fresh = B._read(path)
            fresh["items"].append(item)
            B._atomic_write(path, B._dump(fresh))
            # UN GESTE DE L'OWNER, quel que soit le processus qui l'a tire : `suite_gate` ne l'impute
            # pas a l'essai qui tourne (JAK-265 a coute l'essai 2 d'un chantier innocent le 23/09).
            B.record_gesture(path, "linear_sync", "adopt_owner_issues", [(iid, None, item)])
        mp[iid] = {"issue_id": iss["id"], "identifier": iss["identifier"], "url": "https://linear.app/moukrea/issue/" + iss["identifier"],
                   "last_state": iss["state"]["name"], "hash": "", "pulled_at": PULL_FROM_START}
        _say(L, {"issue_id": iss["id"]}, "Ticket adopté par le harnais (item « %s »). Il n'a pas encore de porte de mesure : le superviseur le cadre, puis il entrera dans la file. Ta description est conservée dans l'item." % iid)
        swap_labels(L, iss["id"], add=todo_id)
        n += 1
    return n


def relink_closed_tickets(L, bl, mp, team, dry):
    """Le ticket PERDU d'un item, quel que soit son etat : Done, Canceled, archive. `adopt_owner_issues` ne lit que les
    ouverts et `ensure_ticket` ne repasse plus sur un item clos (il n'est plus miroite) : un ticket clos sorti de la carte
    n'etait jamais relie, et un « ca marche toujours pas » de l'owner dessus jamais tire (23/09). Ne demande que les
    tickets a cle ABSENTS de la carte : en regime normal, une page vide. Appele AVANT `pull_owner` : le retour de l'owner
    est lu dans le meme passage."""
    known = [v["issue_id"] for k, v in mp.items() if not k.startswith("_") and isinstance(v, dict) and v.get("issue_id")]
    nodes, after = [], None
    while True:
        d = L.q('query($t:ID!,$k:String!,$n:[ID!],$a:String){ issues(first:100, after:$a, includeArchived:true, filter:{team:{id:{eq:$t}}, '
                'description:{contains:$k}, id:{nin:$n}}){ pageInfo { hasNextPage endCursor } nodes { id identifier url title '
                'description createdAt archivedAt creator { id app } state { name type } } } }',
                t=team, k=KEY_FMT.split("`")[0], n=known, a=after)
        page = d["issues"]
        nodes += page["nodes"]
        if not page["pageInfo"]["hasNextPage"]:
            break
        after = page["pageInfo"]["endCursor"]
    n = 0
    for iss in nodes:
        if not issue_key(iss) or iss["id"] in {v.get("issue_id") for k, v in mp.items() if not k.startswith("_") and isinstance(v, dict)}:
            continue
        how = "%s%s" % (iss["state"]["name"], ", archive" if iss.get("archivedAt") else "")
        kind, what = classify_unmapped(iss, bl, mp)
        if kind != "relink":
            print("TICKET PERDU NON RELIE : %s (%s) — %s" % (iss["identifier"], how, what))
            continue
        print("TICKET PERDU RELIE : %s (%s) -> item %s (ses retours de l'owner seront lus)" % (iss["identifier"], how, what))
        if not dry:
            mp[what] = relinked_rec(iss); save_map(mp)
        n += 1
    return n


def adopt_owner_order(L, bl, mp, states, dry, skip=()):
    """Le pendant natif du rang = l'ordre manuel de la colonne Todo (sortOrder). Si l'owner reordonne
    a la main, le backlog adopte cet ordre : les rangs des eligibles sont permutes, rien d'autre ne bouge
    (owner 17/09, JAK-174 : « si ça pouvait être adapté programmatiquement ce serait encore mieux »)."""
    # 18/09 07:30 : un ticket CREE dans ce tour est place en tete de colonne par Linear lui-meme
    # (le `sortOrder` passe a la creation ne survit pas au reglage d'equipe). Sans l'exclusion, la
    # synchro lisait sa propre creation comme un geste de l'owner, ecrivait « owner a reordonne » et
    # permutait les rangs : la regression de la jauge est passee DERRIERE le ticket qui venait de
    # naitre. On n'adopte que l'ordre des tickets qui existaient AVANT ce tour.
    el = [i for i in bl.items if i["status"] == "open" and isinstance(i.get("priority"), int)
          and eligible(bl, i) and i["id"] in mp and i["id"] not in skip]
    if len(el) < 2:
        return 0
    ids = {mp[i["id"]]["issue_id"]: i for i in el}
    # 23/09 : sans `includeArchived`, un ticket archive manquait a la reponse et prenait le rang 0 (tete de
    # colonne) : un faux « owner a reordonne ». On le LIT, puis on l'ecarte : il n'est plus dans la colonne.
    d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:100, includeArchived:true){ nodes { id sortOrder archivedAt } } }', ids=list(ids))
    gone = {n["id"] for n in d["issues"]["nodes"] if n.get("archivedAt")}
    ids = {k: v for k, v in ids.items() if k not in gone}
    el = [i for i in el if mp[i["id"]]["issue_id"] not in gone]
    if len(el) < 2:
        return 0
    so = {n["id"]: n["sortOrder"] for n in d["issues"]["nodes"]}
    linear_order = [ids[k]["id"] for k in sorted(ids, key=lambda k: (so.get(k, 0), ids[k]["id"]))]
    backlog_order = [i["id"] for i in sorted(el, key=lambda i: (i["priority"], i["id"]))]
    if linear_order == backlog_order:
        return 0
    ranks = sorted(i["priority"] for i in el)
    print("  owner a reordonne la colonne Todo : le backlog adopte cet ordre : " + " > ".join(linear_order))
    if dry:
        return 1
    for iid, rank in zip(linear_order, ranks):
        # Le rang seul, sur l'item RELU sous le verrou : `set_status(iid, it["status"], ...)` reposait le statut
        # lu en debut de passe et ramenait en arriere un essai lance entre-temps (23/09).
        def rerank(t, _items, rank=rank):
            if t.get("priority") == rank:
                return False
            t["priority"] = rank
            return True
        if bl.update(iid, rerank):
            refresh_prompt(bl.get(iid))
    return 1


IMG_RX = re.compile(r"!\[[^\]]*\]\((https://uploads\.linear\.app/[^)\s]+)\)")


def save_owner_images(L, iid, body, when):
    """Owner 17/09 : « je sais pas si tu sais récupérer les images de Linear (tu devrais, c'est un bon endroit
    pour avoir des feedbacks visuels !) ». Les images d'un commentaire owner sont enregistrees sous
    .autoport/owner-feedback/<item>/ et leur chemin est ajoute au retour, pour que le worker et le superviseur les voient."""
    urls = IMG_RX.findall(body or "")
    if not urls:
        return body
    d = AP / "owner-feedback" / iid
    d.mkdir(parents=True, exist_ok=True)
    stamp = when.replace("-", "").replace(":", "")[:13]
    saved = []
    for n, u in enumerate(urls, 1):
        try:
            r = L.s.get(u, timeout=60)
            if r.status_code != 200:
                saved.append("%s (HTTP %d)" % (u, r.status_code)); continue
            ext = {"image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp"}.get(r.headers.get("content-type", "").split(";")[0], "bin")
            path = d / ("%s-%d.%s" % (stamp, n, ext))
            path.write_bytes(r.content)
            saved.append(str(path.relative_to(ROOT)))
        except requests.RequestException as e:
            saved.append("%s (erreur %s)" % (u, e))
    return body + "\n[images enregistrees : " + " ; ".join(saved) + "]"


def upload_file(L, path):
    """Televerse un fichier local dans Linear (fileUpload -> PUT signe) et rend son URL d'asset."""
    path = Path(path)
    ctype = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
             "txt": "text/plain", "md": "text/markdown", "json": "application/json", "log": "text/plain"}.get(path.suffix.lower().lstrip("."), "application/octet-stream")
    data = path.read_bytes()
    r = L.q('mutation($ct:String!,$fn:String!,$sz:Int!){ fileUpload(contentType:$ct, filename:$fn, size:$sz){ success uploadFile { uploadUrl assetUrl headers { key value } } } }',
            ct=ctype, fn=path.name, sz=len(data))
    up = r["fileUpload"]["uploadFile"]
    headers = {h["key"]: h["value"] for h in up["headers"]}
    headers["Content-Type"] = ctype
    put = requests.put(up["uploadUrl"], data=data, headers=headers, timeout=120)
    if put.status_code not in (200, 201, 204):
        raise RuntimeError("televersement refuse : HTTP %d" % put.status_code)
    return up["assetUrl"], ctype


def push_existing(L, bl, it, rec, payload, st, h, label, todo):
    """Pose l'etat du backlog sur le ticket EXISTANT d'un chantier. Rend 1 si un changement d'etat a ete commente.

    23/09 (harness-linear-owner-moves-never-lost) : un deplacement fait par l'owner entre le tirage et cet envoi etait
    ECRASE (l'etat partait a chaque mise a jour, meme de simple description). Desormais l'etat ne part que s'il CHANGE ;
    avant de le changer, l'historique puis l'etat du ticket sont RELUS : un ticket qui n'est plus ou la carte le dit
    n'est pas touche (le tirage suivant dit qui l'a deplace). Apres l'ecriture, un deplacement de l'owner tombe entre la
    relecture et l'ecriture est reconnu dans l'historique et applique (`catch_overwritten`)."""
    moved = 0
    seen = None
    if rec.get("last_state") == st:
        payload = {k: v for k, v in payload.items() if k != "stateId"}
    elif rec.get("last_state"):
        seen = {e.get("id") for e in issue_history(L, rec["issue_id"])}   # AVANT l'etat : rien ne passe entre les deux
        now_state = ticket_state(L, rec["issue_id"])
        if now_state is not None and now_state != rec["last_state"]:
            PUSH_GUARD.append({"iid": it["id"], "kind": "deferred", "ticket": now_state, "map": rec["last_state"], "target": st})
            print("ETAT NON ECRASE : %s %s est en « %s » (la carte dit « %s ») ; « %s » n'est pas pose, le prochain tirage "
                  "dit qui l'a deplace" % (rec.get("identifier"), it["id"], now_state, rec["last_state"], st))
            return 0
    # Un ticket clos et archive le reste : on ne le ressort pas pour une retouche de description.
    upd = on_ticket(L, rec["issue_id"], lambda: L.q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }',
                                                    id=rec["issue_id"], i=payload),
                    revive=st not in ("Done", "Canceled"))
    if upd is not LEFT_ARCHIVED:
        if rec.get("last_state") != st:
            body = mark(L) + plain_state_comment(bl, it, st)
            post_comment(L, rec["issue_id"], body)
            if st == "In Review":
                set_read_label(L, rec["issue_id"], label, True)
            elif st in ("Done", "Canceled"):
                for lab in (label, todo, _TALK.get("id")):
                    if lab:
                        swap_labels(L, rec["issue_id"], remove=lab)
            moved = 1
        if _TALK.get("ok") and it["status"] == "validated":
            swap_labels(L, rec["issue_id"], add=None if it.get("owner_ok") else _TALK["ok"], remove=_TALK["ok"] if it.get("owner_ok") else None)
    ours_at = caught = None
    if upd is not LEFT_ARCHIVED and seen is not None:
        ours_at, caught = catch_overwritten(L, bl, it["id"], rec, st, seen)
    if st != "In Review":
        rec.pop("build_announced", None)   # un nouveau passage en test aura droit a UNE annonce
    if upd is LEFT_ARCHIVED:
        # L'etat n'a PAS ete pose : `last_state` garde celui du ticket, sinon le tirage suivant lirait l'ecart
        # comme un deplacement de l'owner (un archive « Done » revalide, un archive « Todo » rouvert).
        rec.update({"hash": h, "stale_archived": True})
    else:
        # `state_at` : le dernier passage qui a POSE l'etat ; un changement anterieur n'est jamais pris pour un
        # deplacement de l'owner (`owner_move`), meme sous la cle de l'owner ou le harnais signe comme lui. C'est la date
        # que LINEAR donne a notre changement (pas l'horloge locale), et elle ne bouge pas quand l'etat n'est pas pose :
        # un deplacement de l'owner fait pendant une simple retouche de description reste posterieur, donc applique.
        rec.update({"last_state": st, "hash": "" if caught else h})
        if "stateId" in payload:
            rec["state_at"] = ours_at or rec.get("state_at") or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    return moved


REACTION_FIELDS = "reactions { emoji createdAt user { id app } }"


def close_on_owner_thumb(L, iss, owner_id, read, todo, talk, dry, name):
    """LA regle du pouce, pour les tickets du backlog ET hors backlog (23/09, JAK-176 : « Pourquoi les labels
    subsistent, j'ai mis le pouce sur le dernier message »). Un pouce (ou ✅) de l'owner sur le DERNIER message du
    harnais, sans commentaire de l'owner apres lui, clot la discussion : « A lire », « A traiter » et « En
    discussion » tombent ensemble. Avant, seul « A lire » tombait, et « A traiter » restait des qu'un retour
    precedait un message automatique. Ses retours anterieurs comptent repondus dans owner_sla (meme fonction,
    `owner_sla.thread_closed`). Un ticket archive n'est dans aucune vue : on ne le ressort pas pour ca.
    -> True si le fil est clos par un pouce (etiquettes retirees ou deja absentes)."""
    if iss.get("archivedAt"):
        return False
    cs = iss["comments"]["nodes"]
    t = OSLA.thread_closed(cs, lambda c: is_owner_comment(c, owner_id), is_harness_comment)
    if not t:
        return False
    have = {l["id"] for l in iss["labels"]["nodes"]}
    drop = [x for x in (read, todo, talk) if x and x in have]
    if drop:
        print("  pouce de l'owner sur la derniere reponse de %s : discussion close (%d etiquette(s) retiree(s))"
              % (name, len(drop)))
        if not dry:
            swap_labels(L, iss["id"], remove=drop)
    return True


def pull_labeled_unmapped(L, mp, read, todo, talk, dry):
    """Tickets HORS backlog (questions closes, tickets de l'owner non adoptes) qui portent nos etiquettes :
    memes regles que les autres — 👍/✅ sur la derniere reponse robot = lu ; commentaire owner = « A traiter ».
    17/09 : JAK-173 (question, passee Done sans etre dans la carte) a garde « A lire » 21 min malgre son pouce."""
    known = {v["issue_id"] for k, v in mp.items() if not k.startswith("_")}
    owner_id = owner_user_id(L, mp)
    n = 0
    seen = set()
    for lab in (read, todo, talk):
        if not lab:
            continue   # etiquette archivee par l'owner (ensure_label)
        d = L.q('query($id:String!){ issueLabel(id:$id){ issues { nodes { id identifier archivedAt labels { nodes { id } } comments { nodes { body createdAt user { id app } botActor { id } ' + REACTION_FIELDS + ' } } } } } }', id=lab)
        for iss in d["issueLabel"]["issues"]["nodes"]:
            if iss["id"] in known or iss["id"] in seen:
                continue
            seen.add(iss["id"])
            have = {l["id"] for l in iss["labels"]["nodes"]}
            cs = sorted(iss["comments"]["nodes"], key=lambda c: c["createdAt"])
            if close_on_owner_thumb(L, iss, owner_id, read, todo, talk, dry, "%s (hors backlog)" % iss["identifier"]):
                n += 1
            elif cs and is_owner_comment(cs[-1], owner_id) and todo not in have:
                print("  retour owner sur %s (hors backlog) : %s" % (iss["identifier"], cs[-1]["body"][:80].replace("\n", " ")))
                if not dry:
                    swap_labels(L, iss["id"], add=todo, remove=read)
                n += 1
    return n


SPEC_PROJECT = {"SPEC-refonte-eau.md": "Eau", "SPEC-refonte-herbe.md": "Herbe", "SPEC-refonte-lumiere.md": "Lumière",
                "SPEC-surfaces-meubles.md": "Surfaces meubles", "SPEC-refonte-hud.md": "Écran et menus",
                "SPEC-keira-physique.md": "Personnages", "SPEC-c20-code-changes.md": "Divers"}


def sync_docs(L, mp, projects, dry):
    """Les SPEC deviennent des documents Linear rattaches au projet de leur campagne (owner 17/09 :
    « Les specs… Linear il peut pas les avoir ? […] voir que la spec existe sans pouvoir la lire… »)."""
    docs = mp.setdefault("_docs", {})
    n = 0
    for name, proj in SPEC_PROJECT.items():
        path = AP / "prompts" / name
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        h = hashlib.sha1(text.encode()).hexdigest()
        rec = docs.get(name)
        if rec and rec.get("hash") == h:
            continue
        title = text.splitlines()[0].lstrip("# ").strip()[:120] or name
        body = text + "\n\n---\n_Copie du fichier `.autoport/prompts/%s` du dépôt, mise à jour automatiquement ; la version du dépôt fait foi._" % name
        if dry:
            print("  document %s (%s)" % (name, "maj" if rec else "creation")); continue
        if rec:
            L.q('mutation($id:String!,$i:DocumentUpdateInput!){ documentUpdate(id:$id,input:$i){ success } }', id=rec["id"], i={"title": title, "content": body})
        else:
            r = L.q('mutation($i:DocumentCreateInput!){ documentCreate(input:$i){ document { id slugId } } }', i={"title": title, "content": body, "projectId": projects.get(proj) or projects.get("Divers")})
            d = r["documentCreate"]["document"]
            rec = {"id": d["id"], "url": "https://linear.app/moukrea/document/" + d["slugId"]}
        rec["hash"] = h; docs[name] = rec; n += 1
    return n


def delivery_state():
    """LA seule source de verite sur « le build est-il sur jak-builds ? » (17/09 : deux commentaires faux ecrits sur une fin de
    journal perimee). Verifie : la ligne PUSHED du publieur, l'empreinte locale == publiee, et l'asset APK en ligne (etat uploaded)."""
    import subprocess, hashlib as hl
    info = AP / ".published_build_info.txt"
    out = {"ok": False, "why": ""}
    if not info.exists():
        out["why"] = "aucune publication enregistree"; return out
    txt = info.read_text(errors="replace")
    mc = re.search(r"commit: ([0-9a-f]{7,40})", txt); mt = re.search(r"TAG: (\S+)", txt); md = re.search(r"date: (\S+)", txt)
    out.update({"commit": mc.group(1) if mc else "?", "tag": mt.group(1) if mt else "?", "when": (md.group(1)[11:16] if md else "?")})
    try:
        pub = (AP / ".last_published_apk_md5").read_text().strip()
        dist = AP / "dist" / "app-jak1-HD-recharged.apk"
        loc = hl.md5(dist.read_bytes()).hexdigest() if dist.exists() else ""
        if not pub or pub != loc:
            out["why"] = "empreinte publiee (%s) != APK local (%s)" % (pub[:8], loc[:8]); return out
        r = subprocess.run(["gh", "release", "view", "--repo", "moukrea/jak-builds", "jak1-rtlight-wip", "--json", "assets",
                            "--jq", '.assets[] | select(.name|test("apk")) | "\\(.size) \\(.state)"'], capture_output=True, text=True, timeout=60)
        line = r.stdout.strip().splitlines()[0] if r.stdout.strip() else ""
        size, state = (line.split() + ["", ""])[:2]
        if state != "uploaded" or (dist.exists() and str(dist.stat().st_size) != size):
            out["why"] = "asset en ligne : %s %s (local %s)" % (size, state, dist.stat().st_size if dist.exists() else "?"); return out
    except Exception as e:  # noqa: BLE001
        out["why"] = "verification impossible : %s" % str(e)[:80]; return out
    out["ok"] = True; return out


def announce_builds(L, bl, mp, read, dry):
    """Quand le build publie sur jak-builds contient le dernier commit d'un chantier « a tester », le dire sur le ticket
    (owner 17/09 : « la revue manuelle se fait sur mon HONOR, à partir d'un build sur jak-builds […] c'est bien dispo ? »)."""
    import subprocess
    ds = delivery_state()
    if not ds["ok"]:
        return 0
    pub, tag, when = ds["commit"], ds["tag"], ds["when"]
    n = 0
    for it in bl.items:
        if it["status"] != "to-test":
            continue
        # 19/09, owner : « messages auto de build publiés sur des tickets ne nécessitant pas de tests » :
        # un chantier du harnais ou une etude n'a rien a installer, on ne lui annonce aucun build.
        if not needs_build(it):
            continue
        rec = mp.get(it["id"])
        # 19/09 22:50 : UNE annonce par passage en test, pas une par build. Trois « build publié » en
        # quarante minutes sur l'herbe (chaque nouveau build re-annoncait) : « comment tu peux être
        # autant à côté de la plaque ? ». Le champ est remis a zero quand l'item quitte « a tester ».
        if not rec or rec.get("build_announced"):
            continue
        try:
            # -F : sans lui, « [autoport/x] » est une classe de caracteres et matche n'importe quel commit
            # 18/09 : on cherche le dernier commit de l'item qui touche le CODE DU JEU, pas le dernier
            # commit tout court. Le commit de cloture d'un essai ne porte souvent que de la comptabilite
            # de harnais (info de build, carte Linear, manifeste d'assets) et arrive APRES le build ; le
            # comparer au build publie disait « pas encore livre » d'un chantier entierement livre — vu
            # deux fois dans la nuit du 17 au 18/09, avec l'owner qui demandait « j'ai teste un build pas fini ? ».
            # `assets-slim` est EXCLU : le manifeste de paquet d'assets change a chaque build et vit
            # sous android/. Sans l'exclusion, le commit de cloture d'un essai — qui ne porte que ce
            # manifeste — passe pour du code de jeu et rend l'ancrage inutile (mesure du 18/09 04:20).
            GAME = ["game", "goalc", "goal_src", "common", "android", "shaders", "decompiler",
                    ":(exclude)android/app/src/*/assets-slim/**"]
            last = subprocess.run(["git", "log", "-1", "--format=%H", "-F", "--grep=[autoport/%s]" % it["id"],
                                   "--"] + GAME, cwd=ROOT, capture_output=True, text=True).stdout.strip()
            if not last:
                last = subprocess.run(["git", "log", "-1", "--format=%H", "-F", "--grep=[autoport/%s]" % it["id"]],
                                      cwd=ROOT, capture_output=True, text=True).stdout.strip()
            if not last:
                continue
            ok = subprocess.run(["git", "merge-base", "--is-ancestor", last, pub], cwd=ROOT).returncode == 0
        except Exception:  # noqa: BLE001
            continue
        if not ok:
            continue
        print("  build %s porte %s : annonce sur le ticket" % (tag, it["id"]))
        if not dry:
            _say(L, rec, "**Build publié** : le build %s (jak-builds, %s) porte ce chantier. C'est celui-là à regarder." % (tag, when))
            swap_labels(L, rec["issue_id"], add=read)
            rec["build_announced"] = pub
        n += 1
    return n


def _proof_for(item_id, vpath):
    """La preuve qui correspond a ce verdict : proof.txt si elle n'a pas ete reecrite depuis, sinon proof-prev.txt."""
    d = AP / "reports" / item_id
    vt = vpath.stat().st_mtime
    for name in ("proof.txt", "proof-prev.txt"):
        f = d / name
        if f.exists() and abs(f.stat().st_mtime - vt) < 180:
            return f
    return None


def _key_numbers(text, gate_key):
    """Les chiffres qui expliquent un verdict : la porte, ses termes non nuls, les comptes d'images."""
    vals = {}
    for line in text.splitlines():
        if "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            vals[k.strip()] = v.strip()
    out = []
    if gate_key in vals:
        out.append("%s = %s" % (gate_key, vals[gate_key]))
    for k in ("frames", "crash", "duration_s", "source"):
        if k in vals:
            out.append("%s = %s" % (k, vals[k]))
    prefix = gate_key.split("_")[0] + "_"
    bad = []
    for k, v in vals.items():
        if k == gate_key or not k.startswith(prefix):
            continue
        if re.search(r"(_defects|_px|_x1000|_leak|_gap|_delta|_over_|_not_)", k) and re.fullmatch(r"-?\d+(\.\d+)?", v) and float(v) != 0:
            bad.append("%s = %s" % (k, v))
    out += sorted(bad)[:10]
    return out


def _fmt(k, v):
    try:
        x = float(v)
    except ValueError:
        return v
    if k.endswith("_x1000"):
        return "%.1f %%" % (x / 10.0)
    if k.endswith("_px"):
        return "%d px" % x
    if k.endswith("_ms"):
        return "%.2f ms" % x
    if k.endswith("_us"):
        return "%d µs" % x
    return ("%d" % x) if x == int(x) else ("%.3f" % x)


def explain_numbers(it, proof_text):
    """Owner 17/09 : « Tu penses vraiment que c'est le genre de truc que je peux intelligiblement comprendre ? ».
    SEULES les grandeurs que le livrable nomme explicitement (entre accents graves) sont montrees, chacune avec la
    phrase du livrable qui lui donne son sens ; la porte et le compte d'images en tete ; jamais une cle brute."""
    vals = {}
    for line in proof_text.splitlines():
        if "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            vals[k.strip()] = v.strip()
    gate = (it.get("gate") or {}).get("key", "")
    deliv = it.get("deliverable") or ""
    out = []
    # Owner 17/09 (JAK-177) : « source=device… frames=15720… Tu crois vraiment que ça m'aide ? » — ni compte d'images,
    # ni duree, ni valeur brute de la porte : seulement les points nommes par le ticket, en clair, et ce qui est en defaut.
    try:
        gate_val = float(vals.get(gate, "nan"))
    except ValueError:
        gate_val = float("nan")
    if gate_val == gate_val and gate_val > 0:
        out.append("**%d point(s) en défaut** sur la mesure." % gate_val)
    named = []
    for key, rest in re.findall(r"`([a-z][a-z0-9_]+)([^`]*)`", deliv):
        if key == gate or key.startswith("FEATURE") or key in named:
            continue
        expected_zero = ("= 0" in rest or "== 0" in rest) or re.search(r"(_defects|_leak_px|_gap_px|_delta_px|_band_px|_over_ceiling|_not_fullres|_excess_x1000)$", key)
        witness = re.search(r"(_moved_px|_excluded_px|_pop_px|_pop$|_measured|_frames|_witness|_cover|_sites|_compiled|_selftest|_queried|_readers|_hit_px)$", key)
        if expected_zero and not witness:
            named.append(key)
    paras = [pg.strip() for pg in re.split(r"\n\s*\n", deliv) if pg.strip()]
    paras = sorted(paras, key=lambda pg: 0 if re.match(r"^\(?[A-Z0-9]{1,2}[.)]\s", pg) else 1)  # verdicts lettres d'abord
    shown = 0
    ok_points = []
    for key in named:
        family = [kk for kk in vals if kk == key or (kk.startswith(key) and re.fullmatch(r"_(gtao|hbao|ssao)?(_q[0-9])?(_x1000)?", kk[len(key):]))]
        nums = []
        for kk in family:
            try:
                nums.append(float(vals[kk]))
            except ValueError:
                pass
        if not nums:
            continue
        worst = max(nums)
        pg = next((pg for pg in paras if re.search(r"`%s\b" % re.escape(key), pg)), "")
        body = re.sub(r"^\s*\(?[0-9A-Za-z]{1,2}[.)]\s*", "", re.sub(r"`[^`]*`", "", pg))  # sans le « E. » de tete
        head = body.split(":", 1)[0].strip(" .-")
        if len(head) < 12:
            head = re.split(r"(?<=[.;])\s", body, 1)[0].strip(" .-")
        sent = (head[:1].upper() + head[1:].lower())[:100] if head else key.replace("_", " ")
        if worst == 0:
            ok_points.append(sent)
            continue
        line = "- %s : %s" % (sent, _fmt(family[0], worst))
        if len(family) > 1:
            line += " au pire, sur %d modes/qualités" % len(family)
        out.append(line + " — en défaut"); shown += 1
        if shown >= 8:
            break
    if ok_points:
        out.append("Tenu : " + " ; ".join(ok_points[:6]) + ".")
    return out


def announce_verdicts(L, bl, mp, read, dry):
    """Owner 17/09 : « on pourrait au moins avoir une raison des échecs et possiblement des preuves à l'appui ! Et pareil
    pour les succès ». A chaque verdict (validator-NNN.txt nouveau), un commentaire : essai, resultat, pourquoi, chiffres,
    resume de l'agent, pieces jointes (rapport, mesures, captures recentes)."""
    n = 0
    for it in bl.items:
        rec = mp.get(it["id"])
        if not rec or it["status"] == "archived":
            continue
        d = AP / "logs" / it["id"]
        if not d.is_dir():
            continue
        files = sorted(d.glob("validator-*.txt"), key=lambda p: p.stat().st_mtime)
        if not files:
            continue
        v = files[-1]
        if rec.get("last_verdict_announced") == v.name:
            continue
        if "last_verdict_announced" not in rec:  # premier passage : on n'annonce pas l'histoire, seulement ce qui vient
            rec["last_verdict_announced"] = v.name; continue
        if time.time() - v.stat().st_mtime > 3 * 86400:
            rec["last_verdict_announced"] = v.name; continue  # vieux verdict d'avant le miroir : on ne rejoue pas l'histoire
        text = v.read_text(errors="replace")
        fails = [l.strip() for l in text.splitlines() if "FAIL]" in l and "constat(s)" not in l]
        ok = " ok]" in text and not fails
        impossible = "PREUVE IMPOSSIBLE" in text
        num = int(v.stem.split("-")[-1])
        gate = (it.get("gate") or {}).get("key", "")
        lines = []
        if impossible:
            lines.append("**Essai %d : pas de mesure possible** (non compté)." % num)
            lines.append(text.splitlines()[0][:400])
        elif ok:
            lines.append("**Essai %d : porte tenue.**" % num)
        else:
            lines.append("**Essai %d : échec.**" % num)
            # Owner 17/09 : « c'est quoi le critère et pourquoi ça le viole ? » — le critere est la premiere phrase du
            # livrable (en francais), le pourquoi = les points du ticket en defaut (explain_numbers) ; la ligne brute du
            # juge n'est montree que si elle dit autre chose qu'un chiffre (preuve perimee, site jamais tire…).
            crit = (it.get("feature") or "").strip()
            if crit:
                lines.append("Critère : « %s », chaque point du ticket mesuré à zéro défaut." % crit)
            other = [f for f in fails if "viole le critere" not in f]
            for f in other[:6]:
                lines.append("- " + re.sub(r"^\[%s FAIL\]\s*" % re.escape(it["id"]), "", f)[:300])
        attach = []
        pf = _proof_for(it["id"], v)
        if pf:
            expl = explain_numbers(it, pf.read_text(errors="replace"))
            if expl:
                lines.append("")
                lines += expl
        rep = AP / "reports" / it["id"] / "report.txt"
        hand = AP / "reports" / it["id"] / "handoff.md"
        if rep.exists() and abs(rep.stat().st_mtime - v.stat().st_mtime) < 1800:
            body_lines = [l for l in rep.read_text(errors="replace").splitlines() if l.strip() and not l.startswith("DIRECTIVES")]
            lines.append("\n**Ce que dit l'agent** : " + " ".join(body_lines[:6])[:900])
            attach.append(rep)
        elif hand.exists() and abs(hand.stat().st_mtime - v.stat().st_mtime) < 1800:
            ht = hand.read_text(errors="replace")
            reste = re.search(r"## RESTE\s*(.+?)(?:\n## |\Z)", ht, re.S)
            etabli = re.search(r"## ÉTABLI\s*(.+?)(?:\n## |\Z)", ht, re.S)
            if etabli and etabli.group(1).strip() and "inconnu" not in etabli.group(1):
                lines.append("\n**Ce que l'agent a établi** : " + " ".join(l.strip() for l in etabli.group(1).splitlines() if l.strip())[:600])
            if reste and reste.group(1).strip() and "inconnu" not in reste.group(1) and "remplir" not in reste.group(1):
                lines.append("\n**Ce qui reste, selon l'agent** : " + " ".join(l.strip() for l in reste.group(1).splitlines() if l.strip())[:700])
            else:
                lines.append("\nL'agent n'a pas laissé de rapport pour cet essai.")
        else:
            lines.append("\nL'agent n'a pas laissé de rapport pour cet essai.")
        notes = AP / "reports" / it["id"] / "notes"
        if notes.is_dir() and OCAP.is_visible(it)[0]:   # INVISIBLE-CAPTURE/ : hors champ, aucune image a televerser
            prev_t = files[-2].stat().st_mtime if len(files) > 1 else 0
            imgs = sorted([p for p in notes.iterdir() if p.suffix.lower() in (".png", ".jpg", ".jpeg") and p.stat().st_mtime > prev_t and p.stat().st_size < 8_000_000], key=lambda p: p.stat().st_mtime)[-3:]
            attach += imgs
        print("  verdict essai %d de %s annonce (%s)" % (num, it["id"], "ok" if ok else "impossible" if impossible else "echec"))
        if not dry:
            body = mark(L) + "\n".join(lines)
            for f in attach:
                try:
                    url, ctype = upload_file(L, f)
                    body += ("\n\n![%s](%s)" if ctype.startswith("image/") else "\n\n[%s](%s)") % (f.name, url)
                except Exception as e:  # noqa: BLE001
                    body += "\n\n(piece jointe %s non televersee : %s)" % (f.name, str(e)[:80])
            try:   # 23/09 : un ticket qui refuse ici faisait tomber tout le passage, pull compris
                post_comment(L, rec["issue_id"], body)
                swap_labels(L, rec["issue_id"], add=read)
            except Exception as e:  # noqa: BLE001
                fail("verdict essai %d de %s sur %s" % (num, it["id"], rec.get("identifier")), e)
                continue
            rec["last_verdict_announced"] = v.name
        n += 1
    return n


def sweep_talk(L, read, todo, talk, dry):
    """« En discussion » ne vit qu'avec « A lire » ou « A traiter ». Owner 17/09 : « si j'ai rien à ajouter à ta
    réponse ça reste en discussion indéfiniment » -> retirer « A lire » soi-meme (= lu) suffit, le balayage
    fait tomber « En discussion » au passage suivant."""
    n = 0
    if not talk:
        return n   # « En discussion » archivee par l'owner : plus rien a tenir coherent
    d = L.q('query($id:String!){ issueLabel(id:$id){ issues { nodes { id identifier labels { nodes { id } } } } } }', id=talk)
    for iss in d["issueLabel"]["issues"]["nodes"]:
        ids = {l["id"] for l in iss["labels"]["nodes"]}
        if read not in ids and todo not in ids:
            if not dry:
                swap_labels(L, iss["id"], remove=talk)
            n += 1
    # 20/09 : l'invariant vaut dans les DEUX sens. Un ticket qui porte « A lire » ou « A traiter » SANS
    # « En discussion » (etiquette retiree a la main, ou posee par un chemin qui ne passe pas par
    # swap_labels) etait invisible dans la vue « En discussion » : l'owner ne le trouvait pas.
    for lab in (read, todo):
        if not lab:
            continue
        d2 = L.q('query($id:String!){ issueLabel(id:$id){ issues { nodes { id labels { nodes { id } } } } } }', id=lab)
        for iss in d2["issueLabel"]["issues"]["nodes"]:
            if talk not in {l["id"] for l in iss["labels"]["nodes"]}:
                if not dry:
                    swap_labels(L, iss["id"], add=lab)   # add=read|todo fait suivre « En discussion »
                n += 1
    return n


def sync_relations(L, bl, mp, dry):
    """depends_on -> relation Linear « bloque » (la dependance BLOQUE l'item). Owner 17/09 :
    « ils devraient être clairement liés, avec des blocked by, depends on […] sinon on s'y retrouvera jamais »."""
    made = 0
    for it in bl.items:
        rec = mp.get(it["id"])
        if not rec or it["id"].startswith("_"):
            continue
        have = set(rec.get("relations") or [])
        for dep in it.get("depends_on") or []:
            drec = mp.get(dep)
            if not drec or dep in have:
                continue
            if dry:
                print("  relation %s bloque %s" % (dep, it["id"])); continue
            try:
                # Un ticket archive refuse la relation : elle est NOMMEE (on_ticket) et jamais retentee ; on ne ressort pas
                # un ticket clos pour un lien.
                on_ticket(L, rec["issue_id"], lambda: L.q('mutation($i:IssueRelationCreateInput!){ issueRelationCreate(input:$i){ success } }',
                                                          i={"issueId": drec["issue_id"], "relatedIssueId": rec["issue_id"], "type": "blocks"}),
                          revive=False)
            except RuntimeError as e:
                if "already" not in str(e).lower() and "exist" not in str(e).lower():
                    raise
            have.add(dep); rec["relations"] = sorted(have); made += 1
    return made


def issue_history(L, issue_id):
    """L'historique Linear d'un ticket, en entier, du plus RECENT au plus ancien. C'est la seule source qui dise QUI a
    archive un ticket : `archivedAt` ne porte qu'une date."""
    out, after = [], None
    while True:
        d = L.q('query($id:String!,$a:String){ issue(id:$id){ history(first:100, after:$a){ pageInfo { hasNextPage endCursor } '
                'nodes { id createdAt archived autoArchived toState { name } actor { id app } botActor { id } } } } }',
                id=issue_id, a=after)
        h = d["issue"]["history"]
        out += h["nodes"]
        if not h["pageInfo"]["hasNextPage"]:
            break
        after = h["pageInfo"]["endCursor"]
    return sorted(out, key=lambda e: e["createdAt"], reverse=True)


def history_author(e, owner_id):
    """'owner' | 'app' | 'auto' | 'autre' | 'inconnu' — l'auteur d'un evenement d'historique."""
    if e.get("autoArchived"):
        return "auto"
    if (e.get("botActor") or {}).get("id") or (e.get("actor") or {}).get("app"):
        return "app"
    who = (e.get("actor") or {}).get("id")
    if not who:
        return "inconnu"
    return "owner" if (not owner_id or who == owner_id) else "autre"


def last_archive(hist, owner_id):
    """(evenement, auteur) du DERNIER archivage (`archived: true`) ; (None, 'inconnu') s'il n'y en a aucun."""
    ev = next((e for e in hist if e.get("archived") is True), None)
    return (ev, history_author(ev, owner_id)) if ev else (None, "inconnu")


def owner_archived(L, hist, owner_id, rec):
    """L'evenement d'archivage si c'est une DECISION de l'owner, sinon None. Sous l'identite d'application, l'auteur suffit ;
    sous la cle de l'owner (repli), le harnais archive AUSSI sous son nom : sa marque `harness_archived_at` l'exclut."""
    ev, who = last_archive(hist, owner_id)
    if who != "owner":
        return None
    if getattr(L, "mode", "owner") != "app" and rec.get("harness_archived_at"):
        return None
    return ev


def worker_comment_refused(bl, iid, env=None):
    """ARCHIVE-OWNER/ (harness-owner-archive-of-running-item-is-safe, 23/09) : un ESSAI n'ecrit rien au
    nom d'un item que l'owner a archive — son commentaire ressortirait le ticket des archives (`on_ticket`
    `revive=True`) et defairait le geste. Un essai = `AUTOPORT_PHASE_ID` pose par l'orchestrateur ; le
    superviseur (sans lui) garde la main. -> motif du refus, ou "" si le message peut partir."""
    env = os.environ if env is None else env
    if not env.get("AUTOPORT_PHASE_ID"):
        return ""
    if ((bl.get(iid) or {}).get("status")) != "archived":
        return ""
    return ("REFUS : %s est ARCHIVE par l'owner ; un essai ne poste rien en son nom (le message "
            "ressortirait le ticket des archives)" % iid)


def apply_owner_archive(bl, iid, rec, ev):
    """Owner 23/09 (« oui ouvre ») : un ticket de chantier VIVANT que l'owner archive lui-meme est sa DECISION, comme un
    deplacement en « Canceled ». On ne lui ecrit rien : tout message ressortirait le ticket des archives et defairait son
    geste. La synchro qui suit l'envoie en « Canceled » sans le ressortir (`revive` faux pour un etat clos).
    Notes prolongees sur l'item RELU sous le verrou, jamais sur la copie de debut de passe (23/09)."""
    today = dt.date.today().isoformat()

    def archive(t, _items):
        avant = t.get("status")
        if avant not in LIVE:   # l'appelant a lu « vivant » en debut de passe ; le disque peut dire autre chose
            return None
        t["status"] = "archived"
        t["notes"] = ((t.get("notes") or "").rstrip()
                      + "\n%s : ticket archivé par l'owner dans Linear (%s) : chantier archivé." % (today, ev["createdAt"])).strip()
        return avant or "?"
    avant = bl.update(iid, archive)
    if not avant:
        print("ARCHIVAGE PAR L'OWNER NON APPLIQUE : %s %s n'est plus vivant sur le disque (%s)"
              % (rec.get("identifier"), iid, (bl.get(iid) or {}).get("status")))
        return B.load(bl.path)
    rec["owner_archived_at"] = ev["createdAt"]
    print("ARCHIVAGE PAR L'OWNER APPLIQUE : %s %s (archive le %s) : %s -> archived ; aucun message (il ressortirait le ticket)"
          % (rec.get("identifier"), iid, ev["createdAt"], avant))
    return B.load(bl.path)


def owner_move(L, hist, owner_id, here, rec):
    """(evenement, motif) : le changement d'etat vers `here` que LINEAR attribue a l'owner, sinon (None, pourquoi).
    23/09 00:19:47 : une carte reculee (git reset) rendait un `last_state` perime, et l'ecart avec le ticket etait pris
    pour un deplacement de l'owner (deux appliques ce soir-la). La carte ne prouve rien : seul l'historique du ticket dit
    QUI l'a deplace, et le deplacement doit etre posterieur au dernier passage qui a pose ou constate l'etat (`state_at`)."""
    mv = next((e for e in hist if e.get("toState")), None)  # le DERNIER changement d'etat, par qui que ce soit
    if not mv:
        return None, "aucun changement d'etat dans l'historique"
    if mv["toState"]["name"] != here:
        return None, "dernier changement vers %s, pas %s" % (mv["toState"]["name"], here)
    if not owner_id:
        return None, "owner inconnu"
    who = history_author(mv, owner_id)
    if who != "owner":
        return None, "auteur %s" % who
    if mv["createdAt"] <= OWNER_KEY_UNTIL:
        return None, "signe sous la cle de l'owner avant l'identite d'application (%s)" % mv["createdAt"]
    since = rec.get("state_at")
    if since and mv["createdAt"] <= since:
        return None, "anterieur au dernier passage (%s <= %s)" % (mv["createdAt"], since)
    if getattr(L, "mode", "owner") != "app" and not since:
        return None, AMBIGUOUS + " : l'auteur ne se distingue pas du harnais"
    return mv, "owner"


def pull_owner(L, bl, mp, states_by_id, dry, label_id=None, todo_id=None):
    """Commentaires sans marqueur, deplacements faits a la main et archivages de l'owner -> backlog.
    Tickets ARCHIVES compris : ils sont lus comme les autres (`includeArchived`)."""
    pulled = 0
    del MOVES[:]  # le releve du passage, pas celui de toute la vie du processus
    owner_id = owner_user_id(L, mp)
    ids = [v["issue_id"] for k, v in mp.items() if not k.startswith("_")]
    for i in range(0, len(ids), 40):
        chunk = ids[i:i + 40]
        # 23/09 : `includeArchived` — sans lui, les 129 tickets archives (sur 209) sortaient du lot et le retour
        # que l'owner y poste n'etait jamais relu.
        d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:40, includeArchived:true){ nodes { id archivedAt state { name } labels { nodes { id } } comments(first:50){ pageInfo { hasNextPage endCursor } nodes { id body createdAt user { id app } botActor { id } ' + REACTION_FIELDS + ' } } } } }', ids=chunk)
        for iss in d["issues"]["nodes"]:
            # 23/09 : sans suite, Linear ne rend que les 50 commentaires les plus RECENTS (JAK-176 en porte 142, JAK-177 89) :
            # un ticket relie repart du debut, et le retour de l'owner enfoui sous 50 messages du harnais etait saute.
            iss["comments"]["nodes"] += OSLA._rest(L, iss["id"], iss["comments"].get("pageInfo"))
            iid = next((k for k, v in mp.items() if not k.startswith("_") and v["issue_id"] == iss["id"]), None)
            if not iid:
                continue
            rec = mp[iid]
            since = rec.get("pulled_at", "1970-01-01T00:00:00Z")
            newest = since
            # Un commentaire deja recopie (par son identifiant) ne l'est jamais deux fois : le curseur `pulled_at` recule
            # avec la carte (git reset, 23/09) et un ticket relie ou adopte repart du debut.
            have_ids = {f["via"]["comment"] for f in ((bl.get(iid) or {}).get("owner_feedback") or [])
                        if isinstance(f, dict) and isinstance(f.get("via"), dict) and f["via"].get("comment")}
            for c in iss["comments"]["nodes"]:
                if not is_owner_comment(c, owner_id) or c["createdAt"] <= since:
                    continue
                if c["id"] in have_ids:
                    newest = max(newest, c["createdAt"])
                    continue
                date = c["createdAt"][:10]
                print("  retour owner sur %s (%s) : %s" % (iid, date, c["body"][:80].replace("\n", " ")))
                if not dry:
                    bl.add_owner_feedback(iid, date, save_owner_images(L, iid, c["body"].strip(), c["createdAt"]),
                                         via={"comment": c["id"], "ticket": iss["id"], "at": c["createdAt"]}); bl = B.load()
                    # le retour entre dans le prompt du worker (render_prompt) ; sans refabrication, l'orchestrateur bloquerait
                    # l'item sur « consigne PERIMEE » au prochain tirage.
                    it2 = bl.get(iid)
                    if it2 and it2["status"] not in ("archived",):
                        try:
                            refresh_prompt(it2)
                        except Exception as e:  # noqa: BLE001
                            print("  prompt non refabrique pour %s : %s" % (iid, e))
                pulled += 1
                newest = max(newest, c["createdAt"])
            # Owner 17/09 : « un thumbs up / checkbox en réaction sur ton dernier message » = lu. 23/09 : il clot TOUT
            # le fil, retour de l'owner compris, s'il est pose apres lui (`close_on_owner_thumb`) ; un retour pose
            # APRES le pouce rouvre normalement (« A traiter »).
            closed = label_id and close_on_owner_thumb(L, iss, owner_id, label_id, todo_id, _TALK.get("id"), dry, iid)
            if newest != since and label_id and not dry and not closed:
                swap_labels(L, iss["id"], add=todo_id, remove=label_id)
            rec["pulled_at"] = newest
            if not iss.get("archivedAt") and rec.pop("stale_archived", None):
                rec["hash"] = ""  # ressorti des archives : l'etat qu'on n'a pas pu lui poser est renvoye
            here = iss["state"]["name"]
            hist = None
            if here != rec.get("last_state") and rec.get("last_state"):
                # Un ecart avec la carte n'est qu'un INDICE (carte reculee, etat refuse sur un archive, passage
                # interrompu) : l'historique du ticket dit qui l'a deplace, et seul l'owner prouve fait suivre le backlog.
                hist = issue_history(L, iss["id"])
                mv, why = owner_move(L, hist, owner_id, here, rec)
                if mv and mv.get("id") and mv["id"] in moves_traced(bl.get(iid)):
                    mv, why = None, "deja applique (evenement %s)" % mv["id"]   # carte reculee : la trace de l'item le dit
                last_mv = next((e for e in hist if e.get("toState")), None)
                MOVES.append({"iid": iid, "ticket": iss["id"], "from": rec.get("last_state"), "to": here, "applied": bool(mv),
                              "why": why, "event_at": (last_mv or {}).get("createdAt"), "dry": bool(dry), "named": False})
                if not mv and why.startswith(AMBIGUOUS) and not dry:
                    bl, MOVES[-1]["named"] = name_ambiguous_move(L, bl, iid, rec, here, last_mv)
                if mv:
                    print("  owner a déplacé %s : %s -> %s (historique : %s)" % (iid, rec.get("last_state"), here, mv["createdAt"]))
                    if not dry:
                        bl = apply_owner_move(L, bl, iid, rec, here, ev=mv)
                        rec.update({"last_state": here, "state_at": mv["createdAt"]})
                else:
                    print("  ecart d'etat sur %s (ticket %s, carte %s) : pas un deplacement de l'owner (%s)"
                          % (iid, here, rec.get("last_state"), why))
                    if not dry:
                        rec.update({"last_state": here, "state_at": (last_mv or {}).get("createdAt")
                                    or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")})
            it = bl.get(iid)
            if iss.get("archivedAt") and it and it["status"] in LIVE:
                hist = hist if hist is not None else issue_history(L, iss["id"])
                ev = owner_archived(L, hist, owner_id, rec)
                if ev and not dry:
                    bl = apply_owner_archive(bl, iid, rec, ev)
                elif ev:
                    print("  ARCHIVERAIT (decision de l'owner) : %s %s" % (rec.get("identifier"), iid))
                else:
                    print("  ticket archive, chantier vivant : %s %s (archive par %s) ; ressorti au prochain envoi"
                          % (rec.get("identifier"), iid, last_archive(hist, owner_id)[1]))
    return pulled


def main():
    # Une seule synchro a la fois : le veilleur (30 s) et les appels du superviseur s'entrelacaient
    # (17/09, JAK-173 : trois etiquettes a la fois, un deplacement du superviseur lu comme celui de l'owner).
    lock = map_lock()  # noqa: F841 — tenu jusqu'a la sortie du processus
    # GESTE ETRANGER (23/09) : ce que la synchro ecrit dans le backlog vient de l'OWNER (ou du
    # superviseur qui la lance), jamais de l'essai qui tourne. Journalise pour `lib/suite_gate.py`.
    # Lancee par un worker (`--comment`), elle ecrit pour l'essai : rien n'est journalise.
    B.DEFAULT_AUTHOR = None if os.environ.get("AUTOPORT_ATTEMPT_ID") else "linear_sync"
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-pull", action="store_true")
    ap.add_argument("--only", default=None, help="un seul id")
    ap.add_argument("--check", action="store_true", help="verifier la coherence Linear <-> backlog, archiver les tickets orphelins")
    ap.add_argument("--delivery", action="store_true", help="dire, verifie, quel build est sur jak-builds (a lire AVANT d'ecrire sur une livraison)")
    ap.add_argument("--comment", default=None, help="id d'item : poster --body comme commentaire du harnais (marque 🤖)")
    ap.add_argument("--body", default=None)
    ap.add_argument("--reply-to", default=None, help="avec --comment : le commentaire Linear de l'owner auquel ce message REPOND (id de `owner_feedback[].via.comment`, ou `last`). Le message part dans son fil : c'est la seule forme qui compte comme reponse a son retour. SANS cette option, le message part dans le fil du dernier retour OUVERT de l'owner sur l'item, s'il y en a un")
    ap.add_argument("--identity", action="store_true", help="dire sous QUELLE identite le harnais parle, et amorcer l'application si la cle le permet")
    ap.add_argument("--attach", nargs="*", default=[], help="fichiers a joindre au commentaire (images, journaux) : illustration, jamais une preuve")
    ap.add_argument("--no-capture", default="", metavar="POURQUOI", help="avec --comment, chantier VISIBLE seulement : la capture de la zone est IMPOSSIBLE, pour cette raison. Le message dit alors quel build tester ; la porte de fermeture l'accepte si un build est publie pendant l'essai. REFUSE sur un chantier hors champ (owner_test: false) : il n'a rien a capturer")
    a = ap.parse_args()
    if a.comment:
        # INVISIBLE-CAPTURE/ : AVANT tout reseau et tout televersement. Un chantier hors champ
        # (owner_test: false...) ne parle ni de capture ni de build a tester (owner 23/09).
        refus = OCAP.invisible_comment_refusal(B.load().get(a.comment) or {}, a.body or "", a.attach, a.no_capture)
        if refus:
            raise SystemExit(refus)
    SM.install_hooks(quiet=True)  # le refus de commit d'un secret connu ne depend d'aucune installation a la main
    ident = LI.resolve()
    if a.identity:
        print("identite : %s" % ident["mode"])
        print("pourquoi : %s" % ident["why"])
        if ident["mode"] != "app":
            print("bloque par: %s" % ident.get("blocked_by"))
            print("")
            print("Pour que le harnais parle sous SON nom, il manque UNE chose : une cle")
            print("Linear portant le scope `oauth:create`. Linear > Settings > Security & access >")
            print("Personal API keys > New key, cocher `oauth:create`, puis :")
            print("  echo 'LINEAR_BOOTSTRAP_KEY=lin_api_...' >> ~/.config/autoport/linear.env")
            print("  python3 .autoport/linear_sync.py --identity")
            print("Le harnais cree alors l'application « Autoport » et retire son jeton tout seul.")
            print("Aucun compte a creer, aucune page d'autorisation a ouvrir.")
        return
    if ident["mode"] != "app":
        # NOMME, jamais silencieux : le miroir continue de tourner sous le compte de l'owner,
        # mais personne ne peut plus le prendre pour un fonctionnement normal.
        print("IDENTITE : le harnais parle sous le compte de l'owner (%s)" % ident["why"])
    L = Linear(ident)
    if a.delivery:
        ds = delivery_state()
        print("LIVRAISON VERIFIEE : build %s (%s) commit %s sur jak-builds" % (ds.get("tag"), ds.get("when"), ds.get("commit", "?")[:12]) if ds["ok"] else "LIVRAISON NON VERIFIEE : %s" % ds["why"])
        return
    if a.check:
        bl = B.load(); mp = load_map()
        team = ensure_team(L); states = ensure_states(L, team); by_id = {v: k for k, v in states.items()}
        drift = orphans = 0
        # 23/09 (harness-linear-check-survives-a-bad-ticket) : chaque ticket dans SA garde. Un orphelin qui
        # refusait son passage en Canceled (ou son commentaire) levait hors de la boucle et arretait tout le
        # passage : orphelins suivants, ecarts d'etat et carte n'etaient plus traites. Un id que Linear refuse
        # faisait de meme tomber la lecture de son lot de 50. Les echecs vont a FAILED, COMPTES et NOMMES.
        _CTX["mp"] = mp
        ids = [v["issue_id"] for k, v in mp.items() if not k.startswith("_")]
        live = {}
        QCHK = 'query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:50, includeArchived:true){ nodes { id archivedAt state { name } title } } }'
        for i in range(0, len(ids), 50):
            try:
                nodes = L.q(QCHK, ids=ids[i:i + 50])["issues"]["nodes"]
            except RuntimeError as e:
                if str(e).startswith("Linear indisponible"):
                    raise  # le reseau, pas un ticket : le passage entier ne peut rien lire
                nodes = []  # un lot refuse : relu ticket par ticket, seul le fautif est perdu
                for one in ids[i:i + 50]:
                    nodes += guard("--check lecture %s" % _name(one), lambda: L.q(QCHK, ids=[one])["issues"]["nodes"], [])
            for iss in nodes:
                live[iss["id"]] = iss
        for iid, rec in mp.items():
            if iid.startswith("_"):
                continue
            iss = live.get(rec["issue_id"])
            it = bl.get(iid)
            if it is None:
                orphans += 1
                if iss and iss["state"]["name"] != "Canceled" and not iss.get("archivedAt"):  # archive = deja range
                    try:
                        L.q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }', id=rec["issue_id"], i={"stateId": states["Canceled"]})
                        post_comment(L, rec["issue_id"], mark(L) + "Ce chantier n'existe plus dans le backlog du harnais : ticket archivé.")
                        print("  orphelin archive :", rec["identifier"], iid)
                    except Exception as e:  # noqa: BLE001 — un orphelin qui refuse ne fait plus tomber le passage
                        fail("--check orphelin %s (%s)" % (rec["identifier"], iid), e)
                continue
            want = target_state(bl, it)
            if iss and iss["state"]["name"] != want:
                drift += 1
                print("  ecart %s : Linear=%s backlog=%s (recale au prochain passage)" % (rec["identifier"], iss["state"]["name"], want))
                rec["hash"] = ""  # force la mise a jour
        save_map(mp)
        missing = [it["id"] for it in bl.items if it["status"] in ("open", "in-progress", "to-test", "blocked") and it["id"] not in mp]
        # AVANT la ligne de coherence : elle reste la DERNIERE (lue par census/harness-linear-own-identity.sh)
        print("tickets en echec : %d sur %d suivis%s" % (len(FAILED), len(ids), (" : " + " ; ".join(FAILED)) if FAILED else ""))
        print("coherence : %d tickets, %d ecarts d'etat, %d orphelins, %d items actifs sans ticket%s" % (len([k for k in mp if not k.startswith("_")]), drift, orphans, len(missing), (" : " + ", ".join(missing)) if missing else ""))
        return
    if a.comment:
        refus = worker_comment_refused(B.load(), a.comment)
        if refus:
            raise SystemExit(refus)
        mp = load_map()
        _CTX["mp"] = mp
        rec = mp.get(a.comment)
        if not rec:
            raise SystemExit("aucun ticket Linear pour %s (lance d'abord la synchro)" % a.comment)
        body = mark(L) + (a.body or "").strip()
        ticket, parent = rec["issue_id"], None
        if a.reply_to:
            ticket, parent = reply_target(L, B.load(), a.comment, a.reply_to)
        else:
            # Sans `--reply-to`, l'OUTIL adresse la reponse (23/09) : au dernier retour OUVERT de l'owner.
            cible = default_reply_target(L, B.load(), mp, a.comment)
            if cible:
                ticket, parent, _r = cible
                print("reponse postee dans le fil du retour de l'owner du %s : « %s »"
                      % (_r.get("date") or "?", " ".join((_r.get("text") or "").split())[:80]))
        for f in a.attach:
            url, ctype = upload_file(L, f)
            body += ("\n\n![%s](%s)" if ctype.startswith("image/") else "\n\n[%s](%s)") % (Path(f).name, url)
        if a.no_capture:
            _b = OCAP.published_build(HOME)
            body += "\n\nCapture impossible : %s. Build a tester : %s (publie le %s)." % (
                a.no_capture.strip(), _b.get("tag", "aucun"), _b.get("date", "jamais"))
        post_comment(L, ticket, body, parent=parent, capture_failed=a.no_capture)
        if not parent:
            # Un message hors fil n'eteint AUCUN retour (23/09) : le dire au moment ou il part.
            try:
                sys.path.insert(0, str(Path(__file__).resolve().parent))
                from lib import owner_sla as _osla             # noqa: PLC0415
                _open = [r for r in _osla.open_records(_osla.load_cache()[0]) if r.get("item") == a.comment]
                if _open:
                    print("ATTENTION : ce message ne repond a aucun des %d retour(s) de l'owner encore ouverts "
                          "sur %s ; pour y repondre : --reply-to last (ou l'id du commentaire)" % (len(_open), a.comment))
            except Exception:  # noqa: BLE001
                pass
        team = ensure_team(L); read, todo = labels(L, team)
        # Owner 17/09 : « si tu commentes, ça a une valeur de le mettre à lire » — toujours, ticket clos ou non.
        swap_labels(L, rec["issue_id"], add=read, remove=todo)
        print("commentaire poste sur", rec["identifier"], "+ « A lire », - « A traiter »"); return
    # Chaque passage dit QUEL code l'a fait : la preuve juge les plantages du code en place, pas ceux d'avant.
    print("SYNCHRO code=%s" % CODE_FP)
    bl = B.load()
    retries = {}
    if STATE_JSON.exists():
        retries = (json.loads(STATE_JSON.read_text()).get("retries") or {})
    mp = load_map()
    ids = mp.get("_ids") or {}
    if ids.get("team") and ids.get("states") and ids.get("projects") and ids.get("labels") and "ok" in ids["labels"] and ids["labels"].get("v2") and "Validé" not in ids["states"]:
        team, states, projects = ids["team"], ids["states"], ids["projects"]
        label, todo = ids["labels"]["read"], ids["labels"]["todo"]; _TALK["id"] = ids["labels"]["talk"]; _TALK["ok"] = ids["labels"].get("ok"); _TALK["read"] = label; _TALK["todo"] = todo
    else:
        team = ensure_team(L); states = ensure_states(L, team); projects = ensure_projects(L, team)
        label, todo = labels(L, team)
        mp["_ids"] = {"team": team, "states": states, "projects": projects, "labels": {"read": label, "todo": todo, "talk": _TALK["id"], "ok": _TALK["ok"], "v2": True}}
    today = dt.date.today()
    _CTX.update(bl=bl, mp=mp, todo=todo, team=team)
    MAP_DOCS.update(mp.get("_docs") or {})
    if guard("documents", lambda: sync_docs(L, mp, projects, a.dry_run)):
        MAP_DOCS.update(mp.get("_docs") or {})
    if mp and not a.no_pull:
        guard("tickets clos perdus", lambda: relink_closed_tickets(L, bl, mp, team, a.dry_run), 0)
        guard("retours de l'owner",lambda: pull_owner(L, bl, mp, {v: k for k, v in states.items()}, a.dry_run, label, todo))
        bl = B.load()
        _CTX["bl"] = bl
        # ------------------------------------------- LA FILE A-T-ELLE ENCORE UN LECTEUR ?
        # Tirer les retours de l'owner et les poser dans `owner_feedback` ne sert a RIEN si
        # personne ne les lit : c'est exactement ce qui s'est passe le 22/09, ou cette boucle
        # a crie « À TRAITER : JAK-176 » 10 766 fois dans le vide pendant que la session
        # superviseur etait morte. La veille date chaque retour par son horodatage Linear,
        # mesure le lecteur, et ALERTE l'owner sur son propre ticket quand il n'y en a plus.
        # Elle ne peut pas faire echouer la synchro : c'est une alarme, pas une dependance.
        try:
            sys.path.insert(0, str(Path(__file__).resolve().parent))
            from lib import owner_sla as _osla             # noqa: PLC0415

            def _poster(_iid, _ticket, _body):
                if not _ticket:
                    return False
                post_comment(L, _ticket, mark(L) + _body)
                swap_labels(L, _ticket, add=label, remove=todo)
                return True

            _v = _osla.veille(L, bl.items, mp, owner_user_id(L, mp), _poster, dry=a.dry_run)
            _c, _al = _v["cout"], _v["alerte"]
            print("veille owner : %d retours sur %d j, %d sans reponse, %d au-dela du SLA, "
                  "pire delai %s s ; lecteur=%s (%s) ; alerte=%s, %d commentaire(s) poste(s)"
                  % (_c["dated"], _osla.FENETRE_JOURS, _c["open"], _c["over_sla"],
                     _c["max_delay_s"], _al.get("reader_state", "?").upper(),
                     _v["releve"]["why"], "OUI" if _al["raise"] else "non", _al["posted"]))
            for _l in _al["lines"]:
                print("  " + _l)
        except Exception as _e:                            # noqa: BLE001 — jamais fatal
            print("veille owner indisponible : %s" % str(_e)[:160])
    # L'espace AVANT les creations : au-dela du seuil, les tickets clos les plus anciens partent aux archives.
    guard("espace", lambda: make_room(L, dry=a.dry_run))
    created = updated = moved = 0
    created_ids = set()
    create_refused = None  # 23/09 00:3x : quota d'equipe atteint, CHAQUE passage mourait sur la 1re creation
    for it in bl.items:
        iid = it["id"]
        if a.only and iid != a.only:
            continue
        if not wanted(it, today) and iid not in mp:
            continue
        st = target_state(bl, it)
        desc = description(bl, it, retries)
        title = item_title(it)
        h = hashlib.sha1((title + "|" + st + "|" + desc + "|" + str(priority_for(bl, it)) + "|ok=" + str(bool(it.get("owner_ok"))) + "|rang=" + str(it.get("priority"))).encode()).hexdigest()
        rec = mp.get(iid)
        if rec and rec.get("hash") == h:
            continue
        payload = {"title": title, "description": desc, "stateId": states[st],
                   "priority": priority_for(bl, it)}
        if projects.get(project_for(iid)):   # projet archive par l'owner : le ticket reste sans projet
            payload["projectId"] = projects[project_for(iid)]
        if isinstance(it.get("priority"), int):
            payload["sortOrder"] = float(it["priority"])  # l'ordre des colonnes = l'ordre reel de la file (owner 17/09, JAK-174)
        if a.dry_run:
            print(("CRÉER " if not rec else "MAJ   ") + "%-40s %-18s %s" % (iid, st, title[:60]))
            continue
        if not rec and create_refused:
            continue
        try:   # 23/09 : un ticket qui refuse (archive, supprime, limite) ne fait plus tomber les suivants
            made = False
            if not rec:
                try:
                    rec, made = ensure_ticket(L, mp, team, iid, title, payload, st, h)
                except RuntimeError as e:
                    # Un refus (quota malgre l'archivage, reseau) ne tue plus le passage : les retours de l'owner, les
                    # verdicts et la file « A traiter » passent apres cette boucle. Plus de creation jusqu'au passage suivant.
                    create_refused = str(e)[:200]
                    print("CREATION REFUSEE PAR LINEAR : %s (%s) ; plus de creation pendant ce passage" % (iid, create_refused))
                    continue
            if made:
                created += 1
                created_ids.add(iid)
                # Le rang du backlog est REIMPOSE apres coup : a la creation, Linear place le ticket ou son
                # reglage d'equipe le veut, pas ou le `sortOrder` demande le met.
                if isinstance(it.get("priority"), int):
                    L.q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }',
                        id=rec["issue_id"], i={"sortOrder": float(it["priority"])})
            else:
                moved += push_existing(L, bl, it, rec, payload, st, h, label, todo)
                updated += 1
        except Exception as e:  # noqa: BLE001
            fail("chantier %s (%s)" % (iid, (rec or {}).get("identifier") or "sans ticket"), e)
        save_map(mp)
    # Chaque etape est gardee : une etape qui tombe est NOMMEE et les suivantes passent quand meme.
    adopted = guard("tickets de l'owner", lambda: adopt_owner_issues(L, bl, mp, team, todo, a.dry_run), 0)
    if adopted or guard("ordre de l'owner", lambda: adopt_owner_order(L, bl, mp, states, a.dry_run, skip=created_ids)):
        bl = B.load()
    rel = guard("relations", lambda: sync_relations(L, bl, mp, a.dry_run), 0)
    guard("verdicts", lambda: announce_verdicts(L, bl, mp, label, a.dry_run))
    guard("builds", lambda: announce_builds(L, bl, mp, label, a.dry_run))
    guard("etiquettes hors carte", lambda: pull_labeled_unmapped(L, mp, label, todo, _TALK["id"], a.dry_run))
    swept = guard("discussions", lambda: sweep_talk(L, label, todo, _TALK["id"], a.dry_run), 0)
    # Owner 17/09 : « tu peux te plug sur "À traiter : retour de l'owner" » — la file est LA, et elle se crie a chaque passage
    # tant qu'un ticket la porte : le guetteur du superviseur lit ces lignes.
    d = guard("file a traiter", lambda: L.q('query($id:String!){ issueLabel(id:$id){ issues { nodes { id identifier } } } }', id=todo),
              {"issueLabel": {"issues": {"nodes": []}}}) if todo else {"issueLabel": {"issues": {"nodes": []}}}
    by_issue = {v["issue_id"]: k for k, v in mp.items() if not k.startswith("_")}
    for iss in d["issueLabel"]["issues"]["nodes"]:
        print("À TRAITER : %s %s (retour owner sans réponse)" % (iss["identifier"], by_issue.get(iss["id"], "hors-backlog")))
    if not a.dry_run:
        save_map(mp)
    if create_refused:
        print("CREATIONS SUSPENDUES : %d item(s) actif(s) sans ticket ; Linear refuse : %s"
              % (len([i for i in bl.items if wanted(i, today) and i["id"] not in mp]), create_refused))
    if FAILED:
        print("ECHECS LINEAR CE PASSAGE : %d, nommes plus haut ; la synchro est allee au bout" % len(FAILED))
    print("Linear : %d créés, %d mis à jour, %d changements d'état commentés, %d relations posées, %d discussions closes, %d tickets suivis, %d requêtes, %d échec(s) nommé(s)" % (created, updated, moved, rel or 0, swept or 0, len([k for k in mp if not k.startswith("_")]), L.n, len(FAILED)))


if __name__ == "__main__":
    main()
