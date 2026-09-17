#!/usr/bin/env python3
"""Miroir Linear du backlog autoport — lisible par l'owner depuis son telephone.

Owner, 17/09/2026 : « ce serait mieux si on passait par un vrai systeme genre Linear ? Tu pourrais
setup le MCP […] tu sera le seul (enfin toi, le harnais) a utiliser ce compte ». Le fichier
backlog.yaml RESTE la source de verite de la machine (portes, livrables, ecritures atomiques) ;
Linear en est le miroir en francais courant : un ticket par chantier, un etat, un rang, ce que
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
SINCE_DAYS = 7  # validés/archivés plus vieux que ça ne sont pas miroités

STATES = [  # (nom Linear, type Linear)
    ("Backlog", "backlog"), ("À faire", "unstarted"), ("En cours", "started"),
    ("À tester", "started"), ("Bloqué", "started"), ("Validé", "completed"),
    ("Terminé (machine)", "completed"), ("Archivé", "canceled"),
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
        self.s = requests.Session()
        self.s.headers.update({"Authorization": key, "Content-Type": "application/json"})

    def q(self, query, **vars):
        for attempt in range(4):
            r = self.s.post(API, json={"query": query, "variables": vars}, timeout=60)
            if r.status_code == 429:
                time.sleep(5 * (attempt + 1)); continue
            d = r.json()
            if "errors" in d:
                raise RuntimeError(json.dumps(d["errors"])[:600])
            return d["data"]
        raise RuntimeError("Linear : 429 persistant")


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
        return "À faire" if eligible(bl, it) else "Backlog"
    if s == "in-progress":
        return "En cours"
    if s == "to-test":
        return "À tester"
    if s == "blocked":
        return "Bloqué"
    if s == "validated":
        return "Validé" if it.get("owner_ok") else "Terminé (machine)"
    return "Archivé"


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
        lines += ["**Bloqué parce que** : " + str(it["block_reason"]).strip()[:600]]
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
    lines += ["", "---", "Identifiant harnais : `%s` — rang %s — spec : %s" % (it["id"], it.get("priority"), it.get("spec") or "—")]
    return "\n".join(lines)


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
    if sorted(want) != sorted(ids):
        L.q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }', id=issue_id, i={"labelIds": want})


def set_read_label(L, issue_id, label_id, on):
    swap_labels(L, issue_id, add=label_id if on else None, remove=None if on else label_id)


def labels(L, team):
    read = ensure_label(L, team, LABEL_READ, "#f2994a")
    todo = ensure_label(L, team, LABEL_TODO, "#eb5757")
    ensure_view(L, team, read)
    ensure_view(L, team, todo, name="À traiter", icon="Inbox", color="#eb5757",
                desc="Tes retours que le harnais n'a pas encore traités. L'étiquette tombe quand il te répond.")
    return read, todo


def viewer_id(L):
    return L.q("{ viewer { id } }")["viewer"]["id"]


def pull_owner(L, bl, mp, states_by_id, dry, label_id=None, todo_id=None):
    """Commentaires sans marqueur et deplacements faits a la main -> backlog."""
    pulled = 0
    ids = [v["issue_id"] for v in mp.values()]
    for i in range(0, len(ids), 40):
        chunk = ids[i:i + 40]
        d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:40){ nodes { id state { name } comments { nodes { id body createdAt user { id } } } } } }', ids=chunk)
        for iss in d["issues"]["nodes"]:
            iid = next((k for k, v in mp.items() if v["issue_id"] == iss["id"]), None)
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
                    bl.add_owner_feedback(iid, date, c["body"].strip()); bl = B.load()
                pulled += 1
                newest = max(newest, c["createdAt"])
            if newest != since and label_id and not dry:
                swap_labels(L, iss["id"], add=todo_id, remove=label_id)
            rec["pulled_at"] = newest
            here = iss["state"]["name"]
            if here != rec.get("last_state") and rec.get("last_state"):
                print("  owner a déplacé %s : %s -> %s" % (iid, rec.get("last_state"), here))
                if here == "Validé" and not dry:
                    it = bl.get(iid)
                    if it and not it.get("owner_ok"):
                        bl.validate(iid, "Déplacé en « Validé » dans Linear par l'owner", date=dt.date.today().isoformat()); bl = B.load()
                elif not dry:
                    bl.add_owner_feedback(iid, dt.date.today().isoformat(), "[Linear] l'owner a déplacé le ticket vers « %s »" % here); bl = B.load()
    return pulled


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-pull", action="store_true")
    ap.add_argument("--only", default=None, help="un seul id")
    ap.add_argument("--comment", default=None, help="id d'item : poster --body comme commentaire du harnais (marque 🤖)")
    ap.add_argument("--body", default=None)
    a = ap.parse_args()
    L = Linear(load_key())
    if a.comment:
        mp = json.loads(MAP_PATH.read_text()) if MAP_PATH.exists() else {}
        rec = mp.get(a.comment)
        if not rec:
            raise SystemExit("aucun ticket Linear pour %s (lance d'abord la synchro)" % a.comment)
        L.q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', i={"issueId": rec["issue_id"], "body": MARK + (a.body or "").strip()})
        team = ensure_team(L); read, todo = labels(L, team)
        swap_labels(L, rec["issue_id"], add=read, remove=todo)
        print("commentaire poste sur", rec["identifier"], "+ « A lire », - « A traiter »"); return
    bl = B.load()
    retries = {}
    if STATE_JSON.exists():
        retries = (json.loads(STATE_JSON.read_text()).get("retries") or {})
    mp = json.loads(MAP_PATH.read_text()) if MAP_PATH.exists() else {}
    team = ensure_team(L)
    states = ensure_states(L, team)
    projects = ensure_projects(L, team)
    today = dt.date.today()
    label, todo = labels(L, team)
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
        h = hashlib.sha1((title + "|" + st + "|" + desc + "|" + str(priority_for(bl, it))).encode()).hexdigest()
        rec = mp.get(iid)
        if rec and rec.get("hash") == h:
            continue
        payload = {"title": title, "description": desc, "stateId": states[st],
                   "projectId": projects[project_for(iid)], "priority": priority_for(bl, it)}
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
                lv = last_verdict(iid)
                body = MARK + "→ **%s**" % st + (("\n" + lv) if lv else "") + (("\nBloqué : " + str(it.get("block_reason"))[:300]) if it["status"] == "blocked" else "")
                L.q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', i={"issueId": rec["issue_id"], "body": body})
                if st == "À tester":
                    set_read_label(L, rec["issue_id"], label, True)
                moved += 1
            rec.update({"last_state": st, "hash": h})
            updated += 1
        MAP_PATH.write_text(json.dumps(mp, indent=1, ensure_ascii=False, sort_keys=True))
    if not a.dry_run:
        MAP_PATH.write_text(json.dumps(mp, indent=1, ensure_ascii=False, sort_keys=True))
    print("Linear : %d créés, %d mis à jour, %d changements d'état commentés, %d tickets suivis" % (created, updated, moved, len(mp)))


if __name__ == "__main__":
    main()
