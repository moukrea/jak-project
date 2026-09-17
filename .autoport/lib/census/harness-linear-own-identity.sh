#!/usr/bin/env bash
# census/harness-linear-own-identity.sh — LE VERDICT DE L'ITEM `harness-linear-own-identity`.
#
# Lance par `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`) apres la course.
# Il ne peut ecrire aucun champ que la machine produit (`sha`, `frames`, `crash`).
#
# CE QU'IL MESURE — quatre termes, un par point du livrable :
#   1. l'AUTEUR d'un commentaire du harnais differe de l'owner   -> lid_author_distinct
#   2. la detection d'un retour owner lit l'AUTEUR, pas le marqueur -> lid_detection_by_author
#   3. rien n'est casse : une passe `--check` sans erreur, 0 ecart  -> lid_sync_check
#   4. un jeton d'APPLICATION est effectivement en main            -> lid_app_token
#
# INCONNU = DEFAUT. Un terme qu'on n'a pas su mesurer compte pour un, jamais pour zero : une
# porte `== 0` sur une identite serait sinon verte par INACTION (reseau coupe = aucun defaut vu).
# `linear_identity_terms_measured` dit combien de termes ont VRAIMENT ete mesures : le lire
# AVANT la somme, une somme basse sur des termes aveugles ne vaut rien.
#
# Le terme 2 est mesure sur DEUX BRAS dans la meme population : la regle LIVREE (auteur) et la
# regle CONDAMNEE (marqueur seul). Si le bras condamne ne se trompe sur RIEN, le test ne separe
# rien et le terme est compte comme un defaut : deux bras au vert = la condition est absente.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "linear_identity_defects=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import json, os, subprocess, sys, time
sys.path.insert(0, '.autoport')

OUT = {}
def pub(k, v): OUT[k] = v

defects = 0
measured = 0

# ============================================================ T2 : LA DETECTION (hors reseau) ==
# Mesure en premier : c'est le seul terme qui ne depend d'aucun secret ni d'aucun reseau, donc
# le seul qui reste parlant quand tout le reste est hors d'atteinte.
try:
    import linear_sync as S
    OWNER = "owner-uuid-temoin"
    APP = "app-uuid-temoin"
    # Population SEMEE : des cas a traiter ET des cas a laisser. Le cas decisif est le 3e —
    # un commentaire du harnais poste APRES la bascule, donc SANS marqueur : la regle condamnee
    # le prend pour un retour de l'owner et le deverse dans owner_feedback.
    CASES = [
        ("owner nu",                 {"body": "ca marche pas", "user": {"id": OWNER}, "botActor": None}, True,  False),
        ("harnais avant bascule",    {"body": S.MARK + "verdict", "user": {"id": OWNER}, "botActor": None}, False, True),
        ("app OAuth, sans marqueur", {"body": "verdict", "user": {"id": APP, "app": True}, "botActor": None}, False, True),
        ("app OAuth, avec marqueur",  {"body": S.MARK + "verdict", "user": {"id": APP, "app": True}, "botActor": None}, False, True),
        ("integration botActor",      {"body": "build", "user": None, "botActor": {"id": "int-1"}}, False, True),
        ("tiers du workspace",       {"body": "salut", "user": {"id": "un-tiers"}, "botActor": None}, False, False),
        ("auteur inconnu",           {"body": "?", "user": None, "botActor": None}, True,  False),
    ]
    wrong_now = 0
    for _n, c, exp_owner, exp_ours in CASES:
        if S.is_owner_comment(c, OWNER) != exp_owner or S.is_harness_comment(c) != exp_ours:
            wrong_now += 1

    # LE BRAS CONDAMNE, rejoue sur la MEME population : « sans marqueur = l'owner ».
    def marker_only_owner(c): return not (c.get("body") or "").startswith(S.MARK)
    def marker_only_ours(c):  return (c.get("body") or "").startswith(S.MARK)
    wrong_marker = 0
    for _n, c, exp_owner, exp_ours in CASES:
        if marker_only_owner(c) != exp_owner or marker_only_ours(c) != exp_ours:
            wrong_marker += 1

    pub("linear_detect_cases", len(CASES))
    pub("linear_detect_wrong_now", wrong_now)
    pub("linear_detect_wrong_marker_only", wrong_marker)
    measured += 1
    # vacuite : si la regle condamnee ne rate rien, la population ne separe pas les deux regles
    bad = 1 if (wrong_now != 0 or wrong_marker == 0) else 0
    pub("lid_detection_by_author", bad)
    defects += bad
except Exception as e:  # noqa: BLE001
    pub("linear_detect_error", str(e)[:120].replace(" ", "_"))
    pub("lid_detection_by_author", 1)
    defects += 1

# ==================================================================== T4 : LE JETON D'APP ======
ident = None
try:
    import linear_identity as LI
    ident = LI.resolve()
    pub("linear_identity_mode", ident["mode"])
    pub("linear_identity_blocked_by", ident.get("blocked_by") or "-")
    pub("linear_identity_why", (ident.get("why") or "-")[:160].replace(" ", "_"))
    measured += 1
    bad = 0 if ident["mode"] == "app" else 1
    pub("lid_app_token", bad)
    defects += bad
except Exception as e:  # noqa: BLE001
    pub("linear_identity_mode", "erreur")
    pub("linear_identity_why", str(e)[:160].replace(" ", "_"))
    pub("lid_app_token", 1)
    defects += 1

# ============================================== T1 : L'AUTEUR, MESURE SUR UN VRAI COMMENTAIRE ==
# On POSTE, on relit l'auteur que le SERVEUR attache, on supprime. Aucune supposition : c'est la
# seule grandeur qui dit sous quel nom l'owner verra le message.
# Le corps porte le marqueur exprès : sans lui, le veilleur (30 s) relirait la sonde comme un
# retour de l'owner et l'ecrirait dans backlog.yaml. La sonde ne doit rien laisser derriere elle.
ISSUE_TITLE = "Le harnais parle sur Linear sous sa propre identite"
try:
    import linear_sync as S
    import linear_identity as LI
    env = LI.load_env()
    owner_id = ""
    if env.get("LINEAR_API_KEY"):
        owner_id = LI.gql(env["LINEAR_API_KEY"], "{ viewer { id } }")["viewer"]["id"]
    pub("linear_owner_id", owner_id or "-")

    L = S.Linear(ident or LI.resolve())
    d = L.q('query($t:String!){ issues(filter:{title:{containsIgnoreCase:$t}}, first:1){ nodes { id identifier } } }',
            t="sous sa propre identit")
    nodes = d["issues"]["nodes"]
    if not nodes:
        raise RuntimeError("ticket de l'item introuvable")
    iid = nodes[0]["id"]
    pub("linear_probe_issue", nodes[0]["identifier"])

    body = S.MARK + "sonde d'identite du recensement (supprimee dans la seconde) %d" % int(time.time())
    S.post_comment(L, iid, body)
    got = L.q('query($id:String!){ issue(id:$id){ comments(last:20){ nodes { id body createdAt user { id app name } botActor { id name } } } } }',
              id=iid)["issue"]["comments"]["nodes"]
    mine = [c for c in got if c["body"] == body]
    if not mine:
        raise RuntimeError("sonde postee mais introuvable a la relecture")
    c = mine[-1]
    kind, who = S.comment_author(c)
    pub("linear_author_kind", kind)
    pub("linear_author_id", who or "-")
    pub("linear_author_name", (((c.get("botActor") or {}).get("name")
                               or (c.get("user") or {}).get("name") or "-")).replace(" ", "_"))
    pub("linear_author_is_app", 1 if ((c.get("user") or {}).get("app") or (c.get("botActor") or {}).get("id")) else 0)
    L.q('mutation($id:String!){ commentDelete(id:$id){ success } }', id=c["id"])
    pub("linear_probe_deleted", 1)
    measured += 1
    bad = 0 if (kind == "app" and who and who != owner_id) else 1
    pub("lid_author_distinct", bad)
    defects += bad
except Exception as e:  # noqa: BLE001
    pub("linear_author_kind", "erreur")
    pub("linear_author_error", str(e)[:160].replace(" ", "_"))
    pub("lid_author_distinct", 1)
    defects += 1

# ============================================================ T3 : RIEN N'EST CASSE (--check) ==
try:
    r = subprocess.run([sys.executable, ".autoport/linear_sync.py", "--check"],
                       capture_output=True, text=True, timeout=180)
    tail = (r.stdout or "").strip().splitlines()
    line = tail[-1] if tail else ""
    pub("linear_check_rc", r.returncode)
    pub("linear_check_line", (line or "-")[:200].replace(" ", "_"))
    import re
    m = re.search(r"(\d+) tickets, (\d+) ecarts d'etat, (\d+) orphelins, (\d+) items actifs sans ticket", line)
    if m:
        pub("linear_check_tickets", m.group(1))
        pub("linear_check_drift", m.group(2))
        pub("linear_check_orphans", m.group(3))
        measured += 1
        bad = 0 if (r.returncode == 0 and m.group(2) == "0" and m.group(3) == "0") else 1
    else:
        pub("linear_check_drift", -1); pub("linear_check_orphans", -1)
        bad = 1
    pub("lid_sync_check", bad)
    defects += bad
except Exception as e:  # noqa: BLE001
    pub("linear_check_rc", -1)
    pub("linear_check_line", str(e)[:160].replace(" ", "_"))
    pub("lid_sync_check", 1)
    defects += 1

pub("linear_identity_terms_measured", measured)
pub("linear_identity_terms_total", 4)
pub("linear_identity_defects", defects)

for k, v in OUT.items():
    print("%s=%s" % (k, v))
PY
