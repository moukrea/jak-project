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

API = "https://api.linear.app/graphql"
MAP_PATH = AP / "linear_map.json"
STATE_JSON = AP / "state.json"
TEAM_KEY = "JAK"
TEAM_NAME = "Jak and Daxter: Recharged Collection"
MARK = "🤖 "
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


def load_key():
    env = Path.home() / ".config/autoport/linear.env"
    for line in env.read_text().splitlines():
        if line.startswith("LINEAR_API_KEY="):
            return line.split("=", 1)[1].strip()
    raise SystemExit("LINEAR_API_KEY absent de %s" % env)


class Linear:
    def __init__(self, key):
        self.n = 0
        self.s = requests.Session()
        self.s.headers.update({"Authorization": key, "Content-Type": "application/json"})

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
    lines += ["", "---", "Identifiant harnais : `%s` — rang %s — spec : %s" % (it["id"], it.get("priority"), ("[%s](%s)" % (os.path.basename(spec), doc)) if doc else (spec or "—"))]
    return "\n".join(lines)


def plain_state_comment(bl, it, st):
    """Commentaire de changement de colonne en francais courant. Owner 17/09, devant « OK : source=device
    sha=… frames=… ; ao_tie_prepass_defects == 0 tenu » : « Genre je suis sensé comprendre ce que je dois
    vérifier avec ce commentaire ? »."""
    where = (it.get("where") or "").strip()
    lv = last_verdict(it["id"])
    frames = ""
    mfr = re.search(r"frames=(\d+)", lv or "")
    if mfr:
        frames = " (mesure machine tenue sur %s images, sans plantage)" % mfr.group(1)
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


def _say(L, rec, text):
    L.q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', i={"issueId": rec["issue_id"], "body": MARK + text})


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
    d = L.q('query($t:String!){ team(id:$t){ issues(first:250){ nodes { id identifier title description state { name type } } } } }', t=team)
    n = 0
    for iss in d["team"]["issues"]["nodes"]:
        if iss["id"] in known or iss["state"]["type"] in ("completed", "canceled"):
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


def adopt_owner_order(L, bl, mp, states, dry):
    """Le pendant natif du rang = l'ordre manuel de la colonne Todo (sortOrder). Si l'owner reordonne
    a la main, le backlog adopte cet ordre : les rangs des eligibles sont permutes, rien d'autre ne bouge
    (owner 17/09, JAK-174 : « si ça pouvait être adapté programmatiquement ce serait encore mieux »)."""
    el = [i for i in bl.items if i["status"] == "open" and isinstance(i.get("priority"), int) and eligible(bl, i) and i["id"] in mp]
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
    OK_EMOJI = ("+1", "thumbsup", "👍", "white_check_mark", "heavy_check_mark", "ballot_box_with_check", "✅", "☑", "✔")
    n = 0
    for lab in (read, todo, talk):
        d = L.q('query($id:String!){ issueLabel(id:$id){ issues { nodes { id identifier labels { nodes { id } } comments { nodes { body createdAt reactions { emoji } } } } } } }', id=lab)
        for iss in d["issueLabel"]["issues"]["nodes"]:
            if iss["id"] in known:
                continue
            have = {l["id"] for l in iss["labels"]["nodes"]}
            cs = sorted(iss["comments"]["nodes"], key=lambda c: c["createdAt"])
            ours = [c for c in cs if c["body"].startswith(MARK)]
            last_owner = [c for c in cs if not c["body"].startswith(MARK)]
            if read in have and ours and any(any(k in str(r["emoji"]) for k in OK_EMOJI) for r in (ours[-1].get("reactions") or [])):
                print("  reaction owner sur la derniere reponse de %s (hors backlog) : lu" % iss["identifier"])
                if not dry:
                    swap_labels(L, iss["id"], remove=read); swap_labels(L, iss["id"], remove=talk)
                n += 1
            elif cs and not cs[-1]["body"].startswith(MARK) and todo not in have:
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


def announce_builds(L, bl, mp, read, dry):
    """Quand le build publie sur jak-builds contient le dernier commit d'un chantier « a tester », le dire sur le ticket
    (owner 17/09 : « la revue manuelle se fait sur mon HONOR, à partir d'un build sur jak-builds […] c'est bien dispo ? »)."""
    import subprocess
    info = AP / ".published_build_info.txt"
    if not info.exists():
        return 0
    txt = info.read_text(errors="replace")
    mc = re.search(r"commit: ([0-9a-f]{7,40})", txt); mt = re.search(r"TAG: (\S+)", txt); md = re.search(r"date: (\S+)", txt)
    if not mc:
        return 0
    pub, tag = mc.group(1), (mt.group(1) if mt else mc.group(1)[:6])
    when = (md.group(1)[11:16] if md else "?")
    n = 0
    for it in bl.items:
        if it["status"] != "to-test":
            continue
        rec = mp.get(it["id"])
        if not rec or rec.get("build_announced") == pub:
            continue
        try:
            # -F : sans lui, « [autoport/x] » est une classe de caracteres et matche n'importe quel commit
            last = subprocess.run(["git", "log", "-1", "--format=%H", "-F", "--grep=[autoport/%s]" % it["id"]], cwd=ROOT, capture_output=True, text=True).stdout.strip()
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


def viewer_id(L):
    return L.q("{ viewer { id } }")["viewer"]["id"]


def pull_owner(L, bl, mp, states_by_id, dry, label_id=None, todo_id=None):
    """Commentaires sans marqueur et deplacements faits a la main -> backlog."""
    pulled = 0
    ids = [v["issue_id"] for k, v in mp.items() if not k.startswith("_")]
    for i in range(0, len(ids), 40):
        chunk = ids[i:i + 40]
        d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:40){ nodes { id state { name } labels { nodes { id } } comments { nodes { id body createdAt user { id } reactions { emoji } } } } } }', ids=chunk)
        for iss in d["issues"]["nodes"]:
            iid = next((k for k, v in mp.items() if not k.startswith("_") and v["issue_id"] == iss["id"]), None)
            if not iid:
                continue
            rec = mp[iid]
            since = rec.get("pulled_at", "1970-01-01T00:00:00Z")
            newest = since
            for c in iss["comments"]["nodes"]:
                if c["body"].startswith(MARK) or c["createdAt"] <= since:
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
            ours = sorted([c for c in iss["comments"]["nodes"] if c["body"].startswith(MARK)], key=lambda c: c["createdAt"])
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
    lock = open(AP / ".linear_sync.lock", "a+")
    fcntl.flock(lock, fcntl.LOCK_EX)
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-pull", action="store_true")
    ap.add_argument("--only", default=None, help="un seul id")
    ap.add_argument("--check", action="store_true", help="verifier la coherence Linear <-> backlog, archiver les tickets orphelins")
    ap.add_argument("--comment", default=None, help="id d'item : poster --body comme commentaire du harnais (marque 🤖)")
    ap.add_argument("--body", default=None)
    ap.add_argument("--attach", nargs="*", default=[], help="fichiers a joindre au commentaire (images, journaux) : illustration, jamais une preuve")
    a = ap.parse_args()
    L = Linear(load_key())
    if a.check:
        bl = B.load(); mp = json.loads(MAP_PATH.read_text()) if MAP_PATH.exists() else {}
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
                    L.q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', i={"issueId": rec["issue_id"], "body": MARK + "Ce chantier n'existe plus dans le backlog du harnais : ticket archivé."})
                    print("  orphelin archive :", rec["identifier"], iid)
                continue
            want = target_state(bl, it)
            if iss and iss["state"]["name"] != want:
                drift += 1
                print("  ecart %s : Linear=%s backlog=%s (recale au prochain passage)" % (rec["identifier"], iss["state"]["name"], want))
                rec["hash"] = ""  # force la mise a jour
        MAP_PATH.write_text(json.dumps(mp, indent=1, ensure_ascii=False, sort_keys=True))
        missing = [it["id"] for it in bl.items if it["status"] in ("open", "in-progress", "to-test", "blocked") and it["id"] not in mp]
        print("coherence : %d tickets, %d ecarts d'etat, %d orphelins, %d items actifs sans ticket%s" % (len([k for k in mp if not k.startswith("_")]), drift, orphans, len(missing), (" : " + ", ".join(missing)) if missing else ""))
        return
    if a.comment:
        mp = json.loads(MAP_PATH.read_text()) if MAP_PATH.exists() else {}
        rec = mp.get(a.comment)
        if not rec:
            raise SystemExit("aucun ticket Linear pour %s (lance d'abord la synchro)" % a.comment)
        body = MARK + (a.body or "").strip()
        for f in a.attach:
            url, ctype = upload_file(L, f)
            body += ("\n\n![%s](%s)" if ctype.startswith("image/") else "\n\n[%s](%s)") % (Path(f).name, url)
        L.q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', i={"issueId": rec["issue_id"], "body": body})
        team = ensure_team(L); read, todo = labels(L, team)
        # Owner 17/09 : « si tu commentes, ça a une valeur de le mettre à lire » — toujours, ticket clos ou non.
        swap_labels(L, rec["issue_id"], add=read, remove=todo)
        print("commentaire poste sur", rec["identifier"], "+ « A lire », - « A traiter »"); return
    bl = B.load()
    retries = {}
    if STATE_JSON.exists():
        retries = (json.loads(STATE_JSON.read_text()).get("retries") or {})
    mp = json.loads(MAP_PATH.read_text()) if MAP_PATH.exists() else {}
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
    created = updated = moved = 0
    for it in bl.items:
        iid = it["id"]
        if a.only and iid != a.only:
            continue
        if not wanted(it, today) and iid not in mp:
            continue
        st = target_state(bl, it)
        desc = description(bl, it, retries)
        title = (it.get("feature") or iid).strip()[:250]
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
        if not rec:
            payload["teamId"] = team
            r = L.q('mutation($i:IssueCreateInput!){ issueCreate(input:$i){ issue { id identifier url } } }', i=payload)
            iss = r["issueCreate"]["issue"]
            mp[iid] = {"issue_id": iss["id"], "identifier": iss["identifier"], "url": iss["url"],
                       "last_state": st, "hash": h, "pulled_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")}
            created += 1
        else:
            L.q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }', id=rec["issue_id"], i=payload)
            if rec.get("last_state") != st:
                body = MARK + plain_state_comment(bl, it, st)
                L.q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', i={"issueId": rec["issue_id"], "body": body})
                if st == "In Review":
                    set_read_label(L, rec["issue_id"], label, True)
                elif st in ("Done", "Canceled"):
                    for lab in (label, todo, _TALK.get("id")):
                        if lab:
                            swap_labels(L, rec["issue_id"], remove=lab)
                moved += 1
            if _TALK.get("ok") and it["status"] == "validated":
                swap_labels(L, rec["issue_id"], add=None if it.get("owner_ok") else _TALK["ok"], remove=_TALK["ok"] if it.get("owner_ok") else None)
            rec.update({"last_state": st, "hash": h})
            updated += 1
        MAP_PATH.write_text(json.dumps(mp, indent=1, ensure_ascii=False, sort_keys=True))
    adopted = adopt_owner_issues(L, bl, mp, team, todo, a.dry_run)
    if adopted or adopt_owner_order(L, bl, mp, states, a.dry_run):
        bl = B.load()
    rel = sync_relations(L, bl, mp, a.dry_run)
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
        MAP_PATH.write_text(json.dumps(mp, indent=1, ensure_ascii=False, sort_keys=True))
    print("Linear : %d créés, %d mis à jour, %d changements d'état commentés, %d relations posées, %d discussions closes, %d tickets suivis, %d requêtes" % (created, updated, moved, rel, swept, len([k for k in mp if not k.startswith("_")]), L.n))


if __name__ == "__main__":
    main()
