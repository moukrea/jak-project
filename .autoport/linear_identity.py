#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""linear_identity.py — SOUS QUELLE IDENTITE le harnais parle sur Linear.

Owner 17/09 (JAK-180) : « Le harnais poste sur les issues en tant que Emeric Commenge
(moukrea) parce que c'est un token personnel… c'est penible car dur a dissocier, et
surtout on beneficie pas des notifs Linear du coup parce que tous les messages sont
envoyes par… moi-meme ». Puis, sur la proposition d'un second compte : « C'est un peu
degueu non de creer un compte fake pour ca ? Il n'y a pas un moyen natif propre ? »

L'identite NATIVE de Linear pour un outil n'est pas un compte : c'est une APPLICATION
OAuth qui parle en mode acteur=application. C'est ce que font les integrations
officielles et les agents Linear. Aucun compte fantome n'est cree.

CE QUI SUIT EST MESURE CONTRE L'API DE PRODUCTION, PAS SUPPOSE (17/09) :

  commentCreate(input:{createAsUser:"Autoport", ...}) avec la cle personnelle
      -> « `createAsUser` used without OAuth `actor=app` mode »   (INPUT_ERROR 400)
  oauthApplicationCreate(...) avec la cle personnelle
      -> « Invalid scope: `oauth:create` required »               (FORBIDDEN 403)

Deux consequences, et elles commandent tout ce fichier :

  1. IL N'EXISTE AUCUN RACCOURCI. Renommer l'auteur d'un commentaire est refuse par
     Linear lui-meme tant que le jeton n'est pas un jeton d'application. On ne peut donc
     pas « habiller » la cle personnelle : il faut un vrai jeton d'application.
  2. AUCUN CLIC DE NAVIGATEUR N'EST NECESSAIRE. Le schema de Linear expose
     `OAuthApplicationGrantType.client_credentials` : une application peut retirer son
     propre jeton sans page d'autorisation. Le seul geste humain qui reste est de
     fournir UNE cle portant le scope `oauth:create` — apres quoi ce module cree
     l'application « Autoport » et s'en sert tout seul, indefiniment.

Reglages, tous dans ~/.config/autoport/linear.env (jamais dans le depot) :

  LINEAR_API_KEY         cle personnelle de l'owner. Reste la voie de repli, et sert a
                         relever l'identite de l'owner tant qu'on l'a sous la main.
  LINEAR_BOOTSTRAP_KEY   cle portant le scope `oauth:create`. Lue UNE fois : ce module
                         cree l'application et ecrit les deux lignes suivantes.
  LINEAR_CLIENT_ID       \\ ecrits par l'amorcage, ou colles a la main si l'application
  LINEAR_CLIENT_SECRET   / a ete creee depuis les reglages Linear. Les noms
                         LINEAR_OAUTH_CLIENT_ID / _SECRET sont acceptes aussi : c'est
                         sous ceux-la que l'owner a depose les siens le 17/09, et on ne
                         reecrit pas le fichier de quelqu'un pour une question de nom.
  LINEAR_APP_SCOPES      facultatif ; defaut ci-dessous.

Le jeton d'application est garde dans ~/.config/autoport/linear_app_token.json (mode
600) et renouvele tout seul avant son echeance.
"""
from __future__ import annotations

import json
import os
import stat
import time
from pathlib import Path

import requests

API = "https://api.linear.app/graphql"
OAUTH_TOKEN_URL = "https://api.linear.app/oauth/token"
ENV_PATH = Path.home() / ".config/autoport/linear.env"
TOKEN_PATH = Path.home() / ".config/autoport/linear_app_token.json"

APP_NAME = "Autoport"
APP_REDIRECT = "http://127.0.0.1:8765/callback"
APP_DEV_URL = "https://github.com/open-goal/jak-project"
APP_DESC = "Le harnais autoport : miroir du backlog et voix des essais."
DEFAULT_SCOPES = "read,write,issues:create,comments:create"

# Marge de renouvellement : on ne rend jamais un jeton qui expire dans la minute.
RENEW_MARGIN_S = 120


# ------------------------------------------------------------------ le fichier de reglages ---
def load_env(path: Path = ENV_PATH) -> dict:
    out = {}
    try:
        txt = path.read_text(encoding="utf-8")
    except OSError:
        return out
    for line in txt.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def save_env(updates: dict, path: Path = ENV_PATH) -> dict:
    """Ajoute/remplace des cles sans toucher aux autres, et sans jamais elargir le mode 600.

    NON-DESTRUCTION : ecriture par fichier temporaire puis `replace` atomique. Un secret
    a moitie ecrit, c'est une identite perdue et un amorcage a refaire a la main."""
    cur = load_env(path)
    cur.update({k: v for k, v in updates.items() if v is not None})
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text("".join("%s=%s\n" % (k, v) for k, v in cur.items()), encoding="utf-8")
    os.chmod(tmp, stat.S_IRUSR | stat.S_IWUSR)
    tmp.replace(path)
    return cur


# ------------------------------------------------------------------------------ transport ---
def gql(key: str, query: str, variables: dict | None = None, bearer: bool = False) -> dict:
    """Un aller simple. Pas de reessai : l'appelant (linear_sync.Linear.q) a le sien."""
    head = {"Content-Type": "application/json",
            "Authorization": ("Bearer " + key) if bearer else key}
    r = requests.post(API, json={"query": query, "variables": variables or {}},
                      headers=head, timeout=60)
    try:
        d = r.json()
    except ValueError:
        raise RuntimeError("reponse non JSON (HTTP %d)" % r.status_code)
    if d.get("errors"):
        raise RuntimeError(json.dumps(d["errors"])[:600])
    return d["data"]


# -------------------------------------------------------------------------------- amorcage ---
def create_app(bootstrap_key: str) -> tuple:
    """Cree l'application « Autoport » dans le workspace. Rend (client_id, client_secret).

    `clientSecret` est porte par le PAYLOAD, pas par l'application : il n'est lisible qu'ICI,
    a la creation. Il n'est plus jamais rendu ensuite (il faudrait `oauthApplicationRotateSecret`).
    On l'ecrit donc dans linear.env avant toute autre chose."""
    d = gql(bootstrap_key, """mutation($i:OAuthApplicationCreateInput!){
      oauthApplicationCreate(input:$i){ success clientSecret application { id clientId name } } }""",
            {"i": {"name": APP_NAME,
                   "developer": APP_NAME,
                   "developerUrl": APP_DEV_URL,
                   "description": APP_DESC,
                   "redirectUris": [APP_REDIRECT],
                   "grantTypes": "client_credentials"}})
    p = d["oauthApplicationCreate"]
    if not p.get("success"):
        raise RuntimeError("oauthApplicationCreate n'a pas abouti : %s" % json.dumps(p)[:300])
    cid = p["application"]["clientId"]
    secret = p.get("clientSecret")
    if not cid or not secret:
        raise RuntimeError("application creee sans clientId/clientSecret lisible : %s" % json.dumps(p)[:300])
    save_env({"LINEAR_CLIENT_ID": cid, "LINEAR_CLIENT_SECRET": secret})
    return cid, secret


def fetch_app_token(client_id: str, client_secret: str, scopes: str | None = None) -> dict:
    """Retire un jeton d'APPLICATION (acteur=application), sans page d'autorisation."""
    data = {"grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
            "scope": scopes or DEFAULT_SCOPES,
            "actor": "app"}
    r = requests.post(OAUTH_TOKEN_URL, data=data, timeout=60)
    try:
        d = r.json()
    except ValueError:
        raise RuntimeError("jeton : reponse non JSON (HTTP %d) %s" % (r.status_code, r.text[:200]))
    if r.status_code >= 400 or "access_token" not in d:
        raise RuntimeError("jeton refuse (HTTP %d) : %s" % (r.status_code, json.dumps(d)[:300]))
    tok = {"access_token": d["access_token"],
           "expires_at": time.time() + float(d.get("expires_in") or 3600),
           "scope": d.get("scope") or (scopes or DEFAULT_SCOPES),
           "client_id": client_id}
    TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = TOKEN_PATH.with_name(TOKEN_PATH.name + ".tmp")
    tmp.write_text(json.dumps(tok), encoding="utf-8")
    os.chmod(tmp, stat.S_IRUSR | stat.S_IWUSR)
    tmp.replace(TOKEN_PATH)
    return tok


def cached_token() -> dict | None:
    try:
        tok = json.loads(TOKEN_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not tok.get("access_token"):
        return None
    if float(tok.get("expires_at") or 0) <= time.time() + RENEW_MARGIN_S:
        return None
    return tok


# --------------------------------------------------------------------------- l'identite ---
def resolve(env: dict | None = None, allow_bootstrap: bool = True) -> dict:
    """Rend l'identite sous laquelle le harnais va parler.

    {"mode": "app"|"owner", "key": <jeton>, "bearer": bool, "why": <phrase>, "blocked_by": <mot|None>}

    « owner » n'est pas une erreur : c'est le repli, et il FAUT qu'il marche, sinon une
    absence de secret couperait le miroir entier. Mais il est NOMME, pour qu'une porte
    puisse le compter comme un defaut au lieu de le confondre avec un succes."""
    env = load_env() if env is None else env

    tok = cached_token()
    if tok:
        return {"mode": "app", "key": tok["access_token"], "bearer": True,
                "why": "jeton d'application en cache", "blocked_by": None}

    cid = env.get("LINEAR_CLIENT_ID") or env.get("LINEAR_OAUTH_CLIENT_ID")
    secret = env.get("LINEAR_CLIENT_SECRET") or env.get("LINEAR_OAUTH_CLIENT_SECRET")
    scopes = env.get("LINEAR_APP_SCOPES") or DEFAULT_SCOPES

    if not (cid and secret) and allow_bootstrap and env.get("LINEAR_BOOTSTRAP_KEY"):
        try:
            cid, secret = create_app(env["LINEAR_BOOTSTRAP_KEY"])
        except Exception as e:  # noqa: BLE001
            return _owner_fallback(env, "amorcage refuse : %s" % str(e)[:200], "bootstrap")

    if cid and secret:
        try:
            tok = fetch_app_token(cid, secret, scopes)
            return {"mode": "app", "key": tok["access_token"], "bearer": True,
                    "why": "jeton d'application retire par client_credentials", "blocked_by": None}
        except Exception as e:  # noqa: BLE001
            return _owner_fallback(env, "jeton d'application refuse : %s" % str(e)[:200], "token")

    return _owner_fallback(
        env,
        "aucune application : ni LINEAR_CLIENT_ID/SECRET, ni LINEAR_BOOTSTRAP_KEY dans %s" % ENV_PATH,
        "no_app")


def _owner_fallback(env: dict, why: str, blocked_by: str) -> dict:
    key = env.get("LINEAR_API_KEY")
    if not key:
        raise SystemExit("ni jeton d'application ni LINEAR_API_KEY dans %s" % ENV_PATH)
    return {"mode": "owner", "key": key, "bearer": False, "why": why, "blocked_by": blocked_by}
