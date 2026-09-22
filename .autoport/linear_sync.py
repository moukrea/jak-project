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


def ensure_ticket(L, mp, team, iid, title, payload, st, h):
    """LE seul chemin qui cree un ticket. Rend (rec, cree). Linear d'abord : une carte qui a recule (git)
    ou lue depuis un worktree ne sait pas que le ticket existe. Une recherche qui echoue LEVE : jamais de
    creation a l'aveugle. La carte est sauvee AVANT toute autre requete."""
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    found = find_issue_for(L, team, iid, title, {v["issue_id"] for k, v in mp.items() if not k.startswith("_")})
    if found:
        print("TICKET EXISTANT RELIE : %s -> %s (aucune creation)" % (found["identifier"], iid))
        mp[iid] = {"issue_id": found["id"], "identifier": found["identifier"], "url": found["url"],
                   "last_state": found["state"]["name"], "hash": "", "pulled_at": now}
        save_map(mp)
        return mp[iid], False
    r = L.q('mutation($i:IssueCreateInput!){ issueCreate(input:$i){ issue { id identifier url } } }', i=dict(payload, teamId=team))
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
            return d["data"]
        raise RuntimeError("Linear indisponible apres 4 essais : %s" % last)


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


def ensure_projects(L, team_id):
    d = L.q('query($t:String!){ team(id:$t){ projects { nodes { id name } } } }', t=team_id)
    have = {p["name"]: p["id"] for p in d["team"]["projects"]["nodes"]}
    for name in sorted(set(PROJECTS.values()) | {"Divers"}):
        if name not in have:
            r = L.q('mutation($i:ProjectCreateInput!){ projectCreate(input:$i){ project { id } } }',
                    i={"name": name, "teamIds": [team_id]})
            have[name] = r["projectCreate"]["project"]["id"]
    return have


LABEL_READ = "À lire : réponse du harnais"
LABEL_TODO = "À traiter : retour de l'owner"
LABEL_TALK = "En discussion"
LABEL_OK = "Sans revue (machine)"  # owner 17/09 : marquer ceux que la machine passe Done seule, pas l'inverse


def ensure_label(L, team_id, name=LABEL_READ, color="#f2994a"):
    d = L.q('query($t:String!){ team(id:$t){ labels { nodes { id name } } } }', t=team_id)
    for l in d["team"]["labels"]["nodes"]:
        if l["name"] == name:
            return l["id"]
    r = L.q('mutation($i:IssueLabelCreateInput!){ issueLabelCreate(input:$i){ issueLabel { id } } }',
            i={"teamId": team_id, "name": name, "color": color})
    return r["issueLabelCreate"]["issueLabel"]["id"]


def ensure_view(L, team_id, label_id, name="À lire", icon="Inbox", color="#f2994a",
                desc="Tickets où le harnais t'a répondu et que tu n'as pas encore relus. L'étiquette tombe dès que tu commentes."):
    d = L.q('{ customViews { nodes { id name } } }')
    for v in d["customViews"]["nodes"]:
        if v["name"] == name:
            return v["id"]
    r = L.q('mutation($i:CustomViewCreateInput!){ customViewCreate(input:$i){ customView { id } } }',
            i={"name": name, "teamId": team_id, "icon": icon, "color": color, "description": desc,
               "filterData": {"labels": {"some": {"id": {"eq": label_id}}}}})
    return r["customViewCreate"]["customView"]["id"]


def swap_labels(L, issue_id, add=None, remove=None):
    """Pose `add`, retire `remove` (ids d'etiquettes), en une ecriture."""
    d = L.q('query($id:String!){ issue(id:$id){ labels { nodes { id } } } }', id=issue_id)
    ids = [l["id"] for l in d["issue"]["labels"]["nodes"]]
    want = [i for i in ids if i != remove]
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


def post_comment(L, issue_id, body):
    """LE SEUL endroit d'ou le harnais poste un commentaire.

    Il y en avait CINQ, chacun portant sa copie de la mutation. Une bascule d'identite aurait
    tenu dans quatre et laisse le cinquieme parler sous l'owner sans que rien ne rougisse.
    L'identite elle-meme ne se pose pas ici : elle est portee par le JETON (`Linear.__init__`),
    donc par toutes les ecritures a la fois, commentaires compris."""
    return L.q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }',
               i={"issueId": issue_id, "body": body})


def _say(L, rec, text):
    post_comment(L, rec["issue_id"], mark(L) + text)


def apply_owner_move(L, bl, iid, rec, here):
    """Un deplacement de ticket fait par l'owner est une DECISION : le backlog suit, et on le dit.
    Owner 17/09 : « si je change un status de ticket moi même […] ça serait con que ce soit systématiquement écrasé »."""
    it = bl.get(iid)
    if it is None:
        return bl
    today = dt.date.today().isoformat()
    s = it["status"]
    def top_priority():
        opens = [x.get("priority") for x in bl.items if x["status"] == "open" and isinstance(x.get("priority"), int)]
        return (min(opens) - 1) if opens else 0
    if here == "Done":
        if not it.get("owner_ok"):
            bl.validate(iid, "Déplacé en « Done » dans Linear par l'owner", date=today)
            _say(L, rec, "Passé Done par ton déplacement : c'est ton feu vert, enregistré tel quel.")
            if _TALK.get("ok"):
                swap_labels(L, rec["issue_id"], remove=_TALK["ok"])
    elif here == "Canceled":
        if s != "archived":
            bl.set_status(iid, "archived", notes=((it.get("notes") or "").rstrip() + "\n%s : archivé par l'owner dans Linear." % today).strip())
            _say(L, rec, "Archivé sur ton déplacement : le harnais ne le reprendra plus.")
    elif here == "À arbitrer":
        if s == "in-progress":
            bl.add_owner_feedback(iid, today, "[Linear] déplacé en « À arbitrer » pendant un essai : sera mis de côté à la fin de l'essai en cours")
            _say(L, rec, "Un essai est en cours dessus ; je le bloque dès qu'il se termine, pas au milieu.")
        elif s != "blocked":
            bl.set_status(iid, "blocked", block_reason="Bloqué par l'owner dans Linear le %s" % today)
            _say(L, rec, "Bloqué sur ton déplacement : le harnais ne le prendra pas tant que tu ne le remets pas dans À faire ou Backlog.")
    elif here in ("Backlog", "Todo", "In Progress"):
        fields = {}
        if s in ("blocked", "to-test", "validated", "archived"):
            fields["status"] = "open"
            if s == "validated":
                fields["owner_ok"] = None
            if _TALK.get("ok"):
                swap_labels(L, rec["issue_id"], remove=_TALK["ok"])
        if here in ("Todo", "In Progress"):
            fields["priority"] = top_priority()
        if fields:
            status = fields.pop("status", s if s != "archived" else "open")
            if s in ("blocked", "to-test", "validated", "archived"):
                status = "open"
            bl.set_status(iid, status, **fields)
            msg = "Rouvert sur ton déplacement." if s != "open" else "Noté."
            if here in ("Todo", "In Progress"):
                msg += " Passé en tête de file : il démarre dès que l'essai en cours se termine (le harnais fait un chantier à la fois)."
            _say(L, rec, msg)
    elif here == "In Review":
        _say(L, rec, "In Review est posé par la machine quand une porte mesurée tient. Je le remets où le backlog le place ; si tu veux forcer, commente ce que tu attends.")
        rec["hash"] = ""  # recalage par la synchro
    bl = B.load()
    it = bl.get(iid)
    if it and it["status"] != "archived":
        try:
            refresh_prompt(it)
        except Exception as e:  # noqa: BLE001
            print("  prompt non refabrique pour %s : %s" % (iid, e))
    return bl


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
                mp[what] = {"issue_id": iss["id"], "identifier": iss["identifier"], "url": "https://linear.app/moukrea/issue/" + iss["identifier"],
                            "last_state": iss["state"]["name"], "hash": "", "pulled_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")}
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
        item = {"id": iid, "status": "open", "game": "jak1", "priority": 999, "feature": iss["title"].strip()[:200],
                "gate": None, "depends_on": [], "device": False, "owner_test": True, "owner_ok": None, "code_scope": "jeu",
                "max_turns": 600, "max_retries": 6, "proof_timeout": 420, "no_code": True,
                "known_cause": "Ticket cree par l'owner dans Linear le %s. Son texte : %s" % (dt.date.today().isoformat(), (iss.get("description") or "").strip()),
                "notes": "A CADRER : porte, livrable et perimetre a ecrire par le superviseur avant tout essai.",
                "where": "", "deliverable": "", "out_of_scope": "", "spec": None}
        path = bl.path
        with B._Lock(path):
            fresh = B._read(path)
            fresh["items"].append(item)
            B._atomic_write(path, B._dump(fresh))
        mp[iid] = {"issue_id": iss["id"], "identifier": iss["identifier"], "url": "https://linear.app/moukrea/issue/" + iss["identifier"],
                   "last_state": iss["state"]["name"], "hash": "", "pulled_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")}
        _say(L, {"issue_id": iss["id"]}, "Ticket adopté par le harnais (item « %s »). Il n'a pas encore de porte de mesure : le superviseur le cadre, puis il entrera dans la file. Ta description est conservée dans l'item." % iid)
        swap_labels(L, iss["id"], add=todo_id)
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
    d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:100){ nodes { id sortOrder } } }', ids=list(ids))
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
        it = bl.get(iid)
        if it["priority"] != rank:
            bl.set_status(iid, it["status"], priority=rank); bl = B.load(); refresh_prompt(bl.get(iid))
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


def pull_labeled_unmapped(L, mp, read, todo, talk, dry):
    """Tickets HORS backlog (questions closes, tickets de l'owner non adoptes) qui portent nos etiquettes :
    memes regles que les autres — 👍/✅ sur la derniere reponse robot = lu ; commentaire owner = « A traiter ».
    17/09 : JAK-173 (question, passee Done sans etre dans la carte) a garde « A lire » 21 min malgre son pouce."""
    known = {v["issue_id"] for k, v in mp.items() if not k.startswith("_")}
    owner_id = owner_user_id(L, mp)
    OK_EMOJI = ("+1", "thumbsup", "👍", "white_check_mark", "heavy_check_mark", "ballot_box_with_check", "✅", "☑", "✔")
    n = 0
    for lab in (read, todo, talk):
        d = L.q('query($id:String!){ issueLabel(id:$id){ issues { nodes { id identifier labels { nodes { id } } comments { nodes { body createdAt user { id app } botActor { id } reactions { emoji } } } } } } }', id=lab)
        for iss in d["issueLabel"]["issues"]["nodes"]:
            if iss["id"] in known:
                continue
            have = {l["id"] for l in iss["labels"]["nodes"]}
            cs = sorted(iss["comments"]["nodes"], key=lambda c: c["createdAt"])
            ours = [c for c in cs if is_harness_comment(c)]
            if read in have and ours and any(any(k in str(r["emoji"]) for k in OK_EMOJI) for r in (ours[-1].get("reactions") or [])):
                print("  reaction owner sur la derniere reponse de %s (hors backlog) : lu" % iss["identifier"])
                if not dry:
                    swap_labels(L, iss["id"], remove=read); swap_labels(L, iss["id"], remove=talk)
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
        if notes.is_dir():
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
            post_comment(L, rec["issue_id"], body)
            swap_labels(L, rec["issue_id"], add=read)
            rec["last_verdict_announced"] = v.name
        n += 1
    return n


def sweep_talk(L, read, todo, talk, dry):
    """« En discussion » ne vit qu'avec « A lire » ou « A traiter ». Owner 17/09 : « si j'ai rien à ajouter à ta
    réponse ça reste en discussion indéfiniment » -> retirer « A lire » soi-meme (= lu) suffit, le balayage
    fait tomber « En discussion » au passage suivant."""
    d = L.q('query($id:String!){ issueLabel(id:$id){ issues { nodes { id identifier labels { nodes { id } } } } } }', id=talk)
    n = 0
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
                L.q('mutation($i:IssueRelationCreateInput!){ issueRelationCreate(input:$i){ success } }',
                    i={"issueId": drec["issue_id"], "relatedIssueId": rec["issue_id"], "type": "blocks"})
            except RuntimeError as e:
                if "already" not in str(e).lower() and "exist" not in str(e).lower():
                    raise
            have.add(dep); rec["relations"] = sorted(have); made += 1
    return made


def pull_owner(L, bl, mp, states_by_id, dry, label_id=None, todo_id=None):
    """Commentaires sans marqueur et deplacements faits a la main -> backlog."""
    pulled = 0
    owner_id = owner_user_id(L, mp)
    ids = [v["issue_id"] for k, v in mp.items() if not k.startswith("_")]
    for i in range(0, len(ids), 40):
        chunk = ids[i:i + 40]
        d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:40){ nodes { id state { name } labels { nodes { id } } comments { nodes { id body createdAt user { id app } botActor { id } reactions { emoji } } } } } }', ids=chunk)
        for iss in d["issues"]["nodes"]:
            iid = next((k for k, v in mp.items() if not k.startswith("_") and v["issue_id"] == iss["id"]), None)
            if not iid:
                continue
            rec = mp[iid]
            since = rec.get("pulled_at", "1970-01-01T00:00:00Z")
            newest = since
            for c in iss["comments"]["nodes"]:
                if not is_owner_comment(c, owner_id) or c["createdAt"] <= since:
                    continue
                date = c["createdAt"][:10]
                print("  retour owner sur %s (%s) : %s" % (iid, date, c["body"][:80].replace("\n", " ")))
                if not dry:
                    bl.add_owner_feedback(iid, date, save_owner_images(L, iid, c["body"].strip(), c["createdAt"])); bl = B.load()
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
            if newest != since and label_id and not dry:
                swap_labels(L, iss["id"], add=todo_id, remove=label_id)
            # Owner 17/09 : « un thumbs up / checkbox en réaction sur ton dernier message » = lu, comme retirer « A lire ».
            have = {l["id"] for l in iss["labels"]["nodes"]}
            # l'API rend les commentaires du plus recent au plus ancien : trier, sinon « dernier » = le premier
            ours = sorted([c for c in iss["comments"]["nodes"] if is_harness_comment(c)], key=lambda c: c["createdAt"])
            OK_EMOJI = ("+1", "thumbsup", "👍", "white_check_mark", "heavy_check_mark", "ballot_box_with_check", "✅", "☑", "✔")
            reacts = [r["emoji"] for r in (ours[-1].get("reactions") or [])] if ours else []
            if label_id in have and ours and any(any(k in str(e) for k in OK_EMOJI) for e in reacts) and newest == since:
                print("  reaction owner sur la derniere reponse de %s (%s) : lu" % (iid, ",".join(reacts)))
                if not dry:
                    swap_labels(L, iss["id"], remove=label_id)
            rec["pulled_at"] = newest
            here = iss["state"]["name"]
            if here != rec.get("last_state") and rec.get("last_state"):
                print("  owner a déplacé %s : %s -> %s" % (iid, rec.get("last_state"), here))
                if not dry:
                    bl = apply_owner_move(L, bl, iid, rec, here)
                    rec["last_state"] = here
    return pulled


def main():
    # Une seule synchro a la fois : le veilleur (30 s) et les appels du superviseur s'entrelacaient
    # (17/09, JAK-173 : trois etiquettes a la fois, un deplacement du superviseur lu comme celui de l'owner).
    lock = map_lock()  # noqa: F841 — tenu jusqu'a la sortie du processus
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-pull", action="store_true")
    ap.add_argument("--only", default=None, help="un seul id")
    ap.add_argument("--check", action="store_true", help="verifier la coherence Linear <-> backlog, archiver les tickets orphelins")
    ap.add_argument("--delivery", action="store_true", help="dire, verifie, quel build est sur jak-builds (a lire AVANT d'ecrire sur une livraison)")
    ap.add_argument("--comment", default=None, help="id d'item : poster --body comme commentaire du harnais (marque 🤖)")
    ap.add_argument("--body", default=None)
    ap.add_argument("--identity", action="store_true", help="dire sous QUELLE identite le harnais parle, et amorcer l'application si la cle le permet")
    ap.add_argument("--attach", nargs="*", default=[], help="fichiers a joindre au commentaire (images, journaux) : illustration, jamais une preuve")
    a = ap.parse_args()
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
        ids = [v["issue_id"] for k, v in mp.items() if not k.startswith("_")]
        live = {}
        for i in range(0, len(ids), 50):
            d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:50){ nodes { id state { name } title } } }', ids=ids[i:i + 50])
            for iss in d["issues"]["nodes"]:
                live[iss["id"]] = iss
        for iid, rec in mp.items():
            if iid.startswith("_"):
                continue
            iss = live.get(rec["issue_id"])
            it = bl.get(iid)
            if it is None:
                orphans += 1
                if iss and iss["state"]["name"] != "Canceled":
                    L.q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }', id=rec["issue_id"], i={"stateId": states["Canceled"]})
                    post_comment(L, rec["issue_id"], mark(L) + "Ce chantier n'existe plus dans le backlog du harnais : ticket archivé.")
                    print("  orphelin archive :", rec["identifier"], iid)
                continue
            want = target_state(bl, it)
            if iss and iss["state"]["name"] != want:
                drift += 1
                print("  ecart %s : Linear=%s backlog=%s (recale au prochain passage)" % (rec["identifier"], iss["state"]["name"], want))
                rec["hash"] = ""  # force la mise a jour
        save_map(mp)
        missing = [it["id"] for it in bl.items if it["status"] in ("open", "in-progress", "to-test", "blocked") and it["id"] not in mp]
        print("coherence : %d tickets, %d ecarts d'etat, %d orphelins, %d items actifs sans ticket%s" % (len([k for k in mp if not k.startswith("_")]), drift, orphans, len(missing), (" : " + ", ".join(missing)) if missing else ""))
        return
    if a.comment:
        mp = load_map()
        rec = mp.get(a.comment)
        if not rec:
            raise SystemExit("aucun ticket Linear pour %s (lance d'abord la synchro)" % a.comment)
        body = mark(L) + (a.body or "").strip()
        for f in a.attach:
            url, ctype = upload_file(L, f)
            body += ("\n\n![%s](%s)" if ctype.startswith("image/") else "\n\n[%s](%s)") % (Path(f).name, url)
        post_comment(L, rec["issue_id"], body)
        team = ensure_team(L); read, todo = labels(L, team)
        # Owner 17/09 : « si tu commentes, ça a une valeur de le mettre à lire » — toujours, ticket clos ou non.
        swap_labels(L, rec["issue_id"], add=read, remove=todo)
        print("commentaire poste sur", rec["identifier"], "+ « A lire », - « A traiter »"); return
    bl = B.load()
    retries = {}
    if STATE_JSON.exists():
        retries = (json.loads(STATE_JSON.read_text()).get("retries") or {})
    mp = load_map()
    ids = mp.get("_ids") or {}
    if ids.get("team") and ids.get("states") and ids.get("projects") and ids.get("labels") and ids["labels"].get("ok") and ids["labels"].get("v2") and "Validé" not in ids["states"]:
        team, states, projects = ids["team"], ids["states"], ids["projects"]
        label, todo = ids["labels"]["read"], ids["labels"]["todo"]; _TALK["id"] = ids["labels"]["talk"]; _TALK["ok"] = ids["labels"].get("ok"); _TALK["read"] = label; _TALK["todo"] = todo
    else:
        team = ensure_team(L); states = ensure_states(L, team); projects = ensure_projects(L, team)
        label, todo = labels(L, team)
        mp["_ids"] = {"team": team, "states": states, "projects": projects, "labels": {"read": label, "todo": todo, "talk": _TALK["id"], "ok": _TALK["ok"], "v2": True}}
    today = dt.date.today()
    MAP_DOCS.update(mp.get("_docs") or {})
    if sync_docs(L, mp, projects, a.dry_run):
        MAP_DOCS.update(mp.get("_docs") or {})
    if mp and not a.no_pull:
        pull_owner(L, bl, mp, {v: k for k, v in states.items()}, a.dry_run, label, todo)
        bl = B.load()
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
                   "projectId": projects[project_for(iid)], "priority": priority_for(bl, it)}
        if isinstance(it.get("priority"), int):
            payload["sortOrder"] = float(it["priority"])  # l'ordre des colonnes = l'ordre reel de la file (owner 17/09, JAK-174)
        if a.dry_run:
            print(("CRÉER " if not rec else "MAJ   ") + "%-40s %-18s %s" % (iid, st, title[:60]))
            continue
        if not rec and create_refused:
            continue
        made = False
        if not rec:
            try:
                rec, made = ensure_ticket(L, mp, team, iid, title, payload, st, h)
            except RuntimeError as e:
                # Un refus (quota, reseau) ne tue plus le passage : les retours de l'owner, les verdicts et la
                # file « A traiter » passent apres cette boucle. Plus aucune creation jusqu'au passage suivant.
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
            L.q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }', id=rec["issue_id"], i=payload)
            if rec.get("last_state") != st:
                body = mark(L) + plain_state_comment(bl, it, st)
                post_comment(L, rec["issue_id"], body)
                if st == "In Review":
                    set_read_label(L, rec["issue_id"], label, True)
                elif st in ("Done", "Canceled"):
                    for lab in (label, todo, _TALK.get("id")):
                        if lab:
                            swap_labels(L, rec["issue_id"], remove=lab)
                moved += 1
            if _TALK.get("ok") and it["status"] == "validated":
                swap_labels(L, rec["issue_id"], add=None if it.get("owner_ok") else _TALK["ok"], remove=_TALK["ok"] if it.get("owner_ok") else None)
            if st != "In Review":
                rec.pop("build_announced", None)   # un nouveau passage en test aura droit a UNE annonce
            rec.update({"last_state": st, "hash": h})
            updated += 1
        save_map(mp)
    adopted = adopt_owner_issues(L, bl, mp, team, todo, a.dry_run)
    if adopted or adopt_owner_order(L, bl, mp, states, a.dry_run, skip=created_ids):
        bl = B.load()
    rel = sync_relations(L, bl, mp, a.dry_run)
    announce_verdicts(L, bl, mp, label, a.dry_run)
    announce_builds(L, bl, mp, label, a.dry_run)
    pull_labeled_unmapped(L, mp, label, todo, _TALK["id"], a.dry_run)
    swept = sweep_talk(L, label, todo, _TALK["id"], a.dry_run)
    # Owner 17/09 : « tu peux te plug sur "À traiter : retour de l'owner" » — la file est LA, et elle se crie a chaque passage
    # tant qu'un ticket la porte : le guetteur du superviseur lit ces lignes.
    d = L.q('query($id:String!){ issueLabel(id:$id){ issues { nodes { id identifier } } } }', id=todo)
    by_issue = {v["issue_id"]: k for k, v in mp.items() if not k.startswith("_")}
    for iss in d["issueLabel"]["issues"]["nodes"]:
        print("À TRAITER : %s %s (retour owner sans réponse)" % (iss["identifier"], by_issue.get(iss["id"], "hors-backlog")))
    if not a.dry_run:
        save_map(mp)
    if create_refused:
        print("CREATIONS SUSPENDUES : %d item(s) actif(s) sans ticket ; Linear refuse : %s"
              % (len([i for i in bl.items if wanted(i, today) and i["id"] not in mp]), create_refused))
    print("Linear : %d créés, %d mis à jour, %d changements d'état commentés, %d relations posées, %d discussions closes, %d tickets suivis, %d requêtes" % (created, updated, moved, rel, swept, len([k for k in mp if not k.startswith("_")]), L.n))


if __name__ == "__main__":
    main()
