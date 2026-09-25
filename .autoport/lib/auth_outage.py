"""lib/auth_outage.py — PANNE-D-AUTH/ : UN REFUS D'AUTHENTIFICATION N'EST PAS UN ECHEC DU CHANTIER.

25/09 vers 14h55 : le jeton OAuth de la CLI a ete revoque (renouvele a 15:16). Chaque essai a
rendu « API Error: 401 » ; l'orchestrateur a range le 401 avec les erreurs de CONFIGURATION
(`fatal_config_reason`, 401/403/404 confondus) et BLOQUE 25 items l'un apres l'autre, puis
s'est arrete sur « rien d'ouvert ». L'essai qui travaillait deja (lighting-local-lights,
essai 2, 123 outils) n'a meme pas pris ce chemin : il a ete COMPTE comme un echec.

Ce module ne decide rien : il LIT ce que la CLI a elle-meme ecrit (jamais la sortie d'un outil ni
la prose du worker, qui citent ces mots des qu'on travaille sur ce sujet), et il publie l'etat
« en pause » pour `autoport status` et le reveil du superviseur.

Les marqueurs, releves sur les 28 journaux reels du 24-25/09 :
  {"type":"system","subtype":"api_retry","error_status":401,"error":"authentication_failed"}
  {"type":"assistant","message":{"model":"<synthetic>",...,"text":"Failed to authenticate. API
   Error: 401 OAuth access token has been revoked."}, "error":"authentication_failed"}
  {"type":"result","is_error":true,"subtype":"success","terminal_reason":"api_error",
   "api_error_status":401,"result":"Failed to authenticate. ..."}
"""
from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path

AUTH_STATUSES = (401, 403)
AUTH_ERRORS = ("authentication_failed", "authentication_error", "permission_error",
               "invalid_api_key", "oauth_token_expired", "oauth_token_revoked")
# Seulement sur un texte que la CLI a produit ELLE-MEME (resultat en erreur, message synthetique).
AUTH_TEXT = re.compile(r"(?i)failed to authenticate|oauth (access )?token (has )?(expired|been "
                       r"revoked)|invalid api key|please run /login|invalid bearer token|"
                       r"api error: 40[13]\b")
# Codex : ses erreurs sont des messages ; 404 / modele absent reste une erreur de CONFIGURATION.
CODEX_AUTH = re.compile(r"(?i)\b40[13]\b|not authenticated|unauthori[sz]ed|invalid.*key|"
                        r"authentication|login")
CODEX_NOT_AUTH = re.compile(r"(?i)\b404\b|model.*(not found|not supported|does not exist)")


def event_marker(ev: dict) -> str:
    """Le refus d'authentification que CET evenement porte, '' sinon.

    Terminal seulement : un `api_retry` en 401 n'est pas un refus (la CLI reessaie et peut
    passer) ; il ne compte que s'il est le dernier mot (voir `refusal`)."""
    if not isinstance(ev, dict):
        return ""
    t = ev.get("type")
    if t == "result":
        st = str(ev.get("api_error_status") or "")
        if st.isdigit() and int(st) in AUTH_STATUSES:
            return "API %s : %s" % (st, str(ev.get("result") or "")[:160])
        if ev.get("is_error") and AUTH_TEXT.search(str(ev.get("result") or "")):
            return "refus d'authentification : %s" % str(ev.get("result"))[:160]
        return ""
    if t == "assistant":
        msg = ev.get("message") or {}
        if not isinstance(msg, dict) or msg.get("model") != "<synthetic>":
            return ""
        texts = " ".join(str(c.get("text") or "") for c in (msg.get("content") or [])
                         if isinstance(c, dict))
        if str(ev.get("error") or "") in AUTH_ERRORS or AUTH_TEXT.search(texts):
            return "refus d'authentification : %s" % (texts or str(ev.get("error")))[:160]
        return ""
    if t in ("error", "turn.failed"):                       # CLI Codex (cli_backend.codex_error)
        err = ev.get("error", ev)
        text = str(err.get("message", "")) if isinstance(err, dict) else str(err)
        if CODEX_AUTH.search(text) and not CODEX_NOT_AUTH.search(text):
            return "refus d'authentification Codex : %s" % text[:160]
    return ""


def _retry_status(ev: dict) -> int:
    if ev.get("type") == "system" and ev.get("subtype") == "api_retry":
        st = str(ev.get("error_status") or "")
        if st.isdigit():
            return int(st)
    return 0


def refusal(events) -> str:
    """Le refus d'authentification qui a TERMINE la session, '' sinon.

    Le dernier marqueur terminal gagne ; a defaut, une session coupee sans `result` dont le
    dernier evenement de l'API est un `api_retry` en 401/403."""
    found, last_retry, saw_result = "", 0, False
    for ev in events:
        m = event_marker(ev)
        if m:
            found = m
        if isinstance(ev, dict):
            if ev.get("type") == "result":
                saw_result = True
                if not m:
                    found = ""                   # une session qui a fini autrement l'emporte
            st = _retry_status(ev)
            if st:
                last_retry = st
    if found:
        return found
    if not saw_result and last_retry in AUTH_STATUSES:
        return "API %d : la CLI a reessaye puis s'est arretee sans resultat" % last_retry
    return ""


def refusal_in_file(path) -> str:
    def _events():
        try:
            with Path(path).open(errors="replace") as fh:
                for line in fh:
                    line = line.strip()
                    if not line.startswith("{"):
                        continue
                    try:
                        yield json.loads(line)
                    except ValueError:
                        continue
        except OSError:
            return
    return refusal(_events())


# ---- LA PUBLICATION, lue par `autoport status` et la signature du digest -------------------

def _alive(pid: int) -> bool:
    if not pid or pid <= 0:
        return False
    try:
        raw = Path("/proc/%d/stat" % pid).read_text()
    except OSError:
        return False
    return raw[raw.rfind(")") + 2:][:1] != "Z"          # `kill -0` reussit sur un zombie


def publish(path, rec: dict) -> None:
    path = Path(path)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(path.name + ".tmp.%d" % os.getpid())
        tmp.write_text(json.dumps(rec, ensure_ascii=False) + "\n", encoding="utf-8")
        os.replace(tmp, path)
    except OSError:
        pass


def unpublish(path) -> None:
    path = Path(path)
    try:
        rec = json.loads(path.read_text())
        if int(rec.get("orchestrator_pid", 0) or 0) != os.getpid():
            return                                   # l'etat d'un autre orchestrateur
        path.unlink()
    except (OSError, ValueError):
        pass


def current(path) -> dict | None:
    """La pause publiee, si elle est VRAIE maintenant (l'orchestrateur qui l'a ecrite vit)."""
    try:
        rec = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(rec, dict) or not _alive(int(rec.get("orchestrator_pid", 0) or 0)):
        return None
    return rec


def human_since(epoch: float) -> str:
    """Un repere FIXE (« 14:05 », « le 23/09 14:05 »), jamais un age : watch.py reveille le
    superviseur des que le texte de statut change."""
    lt = time.localtime(epoch)
    if time.strftime("%Y%m%d", lt) == time.strftime("%Y%m%d"):
        return time.strftime("%H:%M", lt)
    return time.strftime("le %d/%m %H:%M", lt)


def status_line(path) -> str:
    rec = current(path)
    if not rec:
        return ""
    every = int(rec.get("probe_every_s") or 0) // 60
    line = ("En pause : authentification API refusee depuis %s (aucun item n'est pris ni "
            "compte ; l'API est re-sondee toutes les %d min, reprise automatique)"
            % (human_since(float(rec.get("since_epoch") or 0)), every))
    if rec.get("alerted"):
        line += ("\nALERTE : la panne dure depuis plus de %d min — renouveler l'identifiant "
                 "de la CLI (`claude` en interactif, /login)"
                 % (int(rec.get("alert_after_s") or 0) // 60))
    return line


def digest_token(path) -> str:
    """Ce que la pause met dans la signature du digest : RIEN avant l'alerte (une pause courte
    ne reveille personne), puis un jeton FIXE par episode — le superviseur est reveille UNE fois."""
    rec = current(path)
    if not rec or not rec.get("alerted"):
        return ""
    return "auth-pause:%s" % rec.get("since_epoch")


def journal(path, event: str, **fields) -> None:
    """Une ligne par evenement de la pause (pause, sonde, alerte, reprise, arret)."""
    rec = {"event": event, "at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "pid": os.getpid()}
    rec.update(fields)
    try:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with Path(path).open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except OSError:
        pass
