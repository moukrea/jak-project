#!/usr/bin/env python3
"""
Recensement des essais du harnais : qui a tourne, avec quel modele, a quel effort,
pour combien de jetons, et avec quelle issue.

CE FICHIER NE JUGE RIEN. Il MESURE et ecrit un digest JSON. Le jugement
(`model_mix_defects`) est fait par `gate.py`, qui relit ce digest.

Sources de verite, dans l'ordre de preference :

  1. `logs/<item>/attempt-NNN.jsonl[.gz]` — PREMIERE LIGNE : `attempt_start` (backend
     claude|codex) ou `phase_start` (ancien format). Elle porte le modele, l'effort et le
     modele des sous-agents. C'est l'identite du profil POUR CET ESSAI, ecrite par le
     lanceur au moment du lancement : elle ne peut pas deriver comme une banniere de
     `orchestrator.log`, qui est reecrite a chaque bascule de profil.
  2. Les lignes `assistant` du meme fichier : `message.usage` (jetons) + `message.model`
     (le modele REELLEMENT facture) + `parent_tool_use_id`/`subagent_type` (l'ETAGE).
  3. `logs/<item>/validator-NNN.txt` — l'issue de l'essai.

DEUX COMPTABILITES DE JETONS, QU'ON NE PEUT PAS ADDITIONNER TELLES QUELLES :
  Anthropic : `input_tokens` EXCLUT le cache ; le cache est a part (creation/lecture).
  OpenAI    : `input_tokens` INCLUT `cached_input_tokens`.
On normalise tout vers quatre seaux disjoints — inp (entree fraiche), cread (cache lu),
cwrite (cache ecrit), out (sortie) — et c'est CETTE normalisation que le rapport publie.
Sans elle, Codex parait 2x plus cher qu'il n'est : ses jetons de cache sont comptes deux
fois, une fois dans `input_tokens` et une fois dans `cached_input_tokens`.

TROIS PIEGES DE CE FLUX, MESURES SUR UN TEMOIN AVANT D'ETRE CONTOURNES
(temoin = un essai SANS AUCUN sous-agent, ou le total de l'etage principal DOIT egaler
le total de la session ; `logs/00-harness/attempt-02.jsonl` et 3 autres) :

  1. UN MEME MESSAGE REVIENT 3 A 5 FOIS dans le flux, avec la MEME `usage`. Les sommer
     multiplie le cache par ~3. On deduplique donc par `message.id`. Controle : apres
     deduplication, le cache lu de l'etage principal tombe EXACTEMENT sur le total de la
     session (1 455 508 = 1 455 508 sur le temoin) — au jeton pres, sur les quatre temoins.
  2. `usage.output_tokens` DES LIGNES `assistant` EST UN ACOMPTE, pas le total : 7 541
     contre 32 646 reellement factures sur le meme temoin sans sous-agent (facteur 4 a 9).
     La sortie ne se lit donc QUE sur l'evenement `result`, qui est de SESSION : elle
     n'est PAS attribuable a un etage. Le rapport publie cette cecite au lieu de la
     combler par une regle de trois.
  3. `attempt_end.tokens_*`, que l'orchestrateur ecrit, ADDITIONNAIT les doublons du point 1
     PUIS y rajoutait le total de `result` : il comptait tout deux a quatre fois. CORRIGE le
     2026-09-19 (item harness-usage-double-counted) — `_note_assistant_usage` deduplique par
     `(etage, message.id)` et `_adopt_result_totals` REMPLACE au lieu d'additionner, si bien
     que `attempt_end` porte desormais le dernier `result.modelUsage` au jeton pres, avec
     `usage_source`, `usage_results` et `usage_dup_msgs` pour le dire. Ce fichier continue
     neanmoins de mesurer lui-meme : il a besoin du detail PAR ETAGE, qu'`attempt_end` n'a
     jamais porte.

L'AUTORITE POUR LES TOTAUX EST `result.modelUsage` : Claude Code y publie, par modele,
les jetons factures et `costUSD` (base `list`, le tarif public). C'est une grandeur
produite par l'outil, pas une estimation de notre part.
"""

import gzip
import io
import json
import os
import re
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

VERSION = "model-mix/collect.py v3"

AUTOPORT = Path(__file__).resolve().parents[3]
LOGS = AUTOPORT / "logs"
SUPERVISOR_DIR = Path.home() / ".claude" / "projects" / "-home-emeric-code-jak-project"

# On importe l'empreinte d'echec DU HARNAIS LUI-MEME plutot que d'en reecrire une :
# c'est `orchestrator.py` qui decide, en vol, si deux essais ont echoue PAREIL
# (`check_stuck`, seuil 3). Une deuxieme definition ici mesurerait une autre notion de
# « boucle » que celle que le harnais applique, et le chiffre publie ne vaudrait rien.
sys.path.insert(0, str(AUTOPORT))
from orchestrator import fingerprint_validator_output, STUCK_REPEAT_THRESHOLD  # noqa: E402


# ---------------------------------------------------------------- lecture fichiers

def open_text(path: Path):
    if path.name.endswith(".gz"):
        return io.TextIOWrapper(gzip.open(path, "rb"), errors="replace")
    return open(path, "r", errors="replace")


def open_bytes(path: Path):
    if path.name.endswith(".gz"):
        return gzip.open(path, "rb")
    return open(path, "rb")


ATTEMPT_RE = re.compile(r"^attempt-(\d+)\.jsonl(\.gz)?$")
VALIDATOR_RE = re.compile(r"^validator-(\d+)\.txt$")


def discover_attempts():
    """(item, numero) -> chemin. Le .jsonl non compresse l'emporte sur son .gz."""
    found = {}
    for item_dir in sorted(LOGS.iterdir()):
        if not item_dir.is_dir():
            continue
        for f in item_dir.iterdir():
            m = ATTEMPT_RE.match(f.name)
            if not m:
                continue
            key = (item_dir.name, int(m.group(1)))
            if key in found and found[key].name.endswith(".gz"):
                found[key] = f          # le clair remplace le compresse
            elif key not in found:
                found[key] = f
    return found


def discover_validators():
    found = {}
    for item_dir in sorted(LOGS.iterdir()):
        if not item_dir.is_dir():
            continue
        for f in item_dir.iterdir():
            m = VALIDATOR_RE.match(f.name)
            if m:
                found[(item_dir.name, int(m.group(1)))] = f
    return found


# ---------------------------------------------------------------- verdicts

# Trois dialectes de verdict se sont succede dans ce depot. Aucun n'a ete reecrit, donc
# le classement doit tenir les trois, et TOUT CE QU'IL NE RECONNAIT PAS EST PUBLIE comme
# `inconnu` — jamais reparti au hasard dans vert ou rouge.
_GREEN = re.compile(r"(?:^|\s)\[[^\]]*\bok\]|\bPASSED\b|\bPASS\b(?!ED)", re.M)
_RED = re.compile(r"\bFAIL\b|\bFAILED\b|\bECHEC\b|\bECHOUE\b", re.I)


def classify_validator(text: str) -> str:
    lines = [l for l in text.splitlines() if l.strip()]
    if not lines:
        return "inconnu"
    tail = "\n".join(lines[-6:])
    red = bool(_RED.search(tail))
    green = bool(_GREEN.search(tail))
    if red and not green:
        return "rouge"
    if green and not red:
        return "vert"
    if red and green:
        # « [id FAIL] ... » + une ligne « ok » plus haut : le FAIL final tranche.
        return "rouge" if _RED.search(lines[-1]) else "vert"
    return "inconnu"


# La plomberie de preuve n'est pas un echec du MODELE (releve du 16/09 : 4 echecs sur 5
# etaient de la plomberie). On separe donc les causes AVANT toute comparaison de modeles.
# C'est une heuristique par mots-cles sur les lignes d'erreur retenues par l'empreinte :
# elle est declaree comme telle dans le rapport, et sa couverture est publiee.
_PLUMBING = re.compile(
    r"proof\.txt absent|proof\.txt vide|preuve absente|proof_attempt_id|"
    r"perime|perimee|stale|obsolete|"
    r"course de preuve|proof_run|en vol|in-flight|orphelin|"
    r"verrou|deploy-in-progress|lock|"
    r"adb|device|appareil|no devices|unauthorized|offline|"
    r"gradle|ninja|cmake|undefined symbol|undefined reference|link|"
    r"timeout|timed out|delai depasse|"
    r"No space left|disk|quota|rate.?limit|529|overloaded|"
    r"freshness|fraicheur|md5|empreinte de binaire",
    re.I,
)


def classify_failure_cause(key_lines) -> str:
    blob = "\n".join(key_lines)
    return "plomberie" if _PLUMBING.search(blob) else "substance"


# ---------------------------------------------------------------- un essai

def norm_anthropic(u):
    """Anthropic : input_tokens EXCLUT deja le cache."""
    return (
        int(u.get("input_tokens") or 0),
        int(u.get("cache_read_input_tokens") or 0),
        int(u.get("cache_creation_input_tokens") or 0),
        int(u.get("output_tokens") or 0),
    )


def norm_openai(u):
    """OpenAI : input_tokens INCLUT cached_input_tokens — on le retranche."""
    total_in = int(u.get("input_tokens") or 0)
    cached = int(u.get("cached_input_tokens") or 0)
    cwrite = int(u.get("cache_write_input_tokens") or 0)
    return (
        max(0, total_in - cached),
        cached,
        cwrite,
        int(u.get("output_tokens") or 0),
    )


def blank_stage():
    # cw5/cw1h : l'ecriture de cache n'a PAS un tarif unique (5 min = 1,25x l'entree,
    # 1 h = 2x). Sans ce partage, le cout recalcule depuis les tarifs publics rate le
    # `costUSD` de l'outil de ~2,3 % ; avec lui, il tombe dessus.
    return {"inp": 0, "cread": 0, "cwrite": 0, "cw5": 0, "cw1h": 0,
            "out": 0, "msgs": 0, "models": {}}


def scan_attempt(path: Path):
    """Un essai -> son profil, ses jetons par etage, sa fin. None si illisible."""
    rec = {
        "backend": None, "model": None, "effort": None, "subagent_model": None,
        "started_at": None, "ended_at": None, "exit_code": None, "tool_calls": None,
        "abort_reason": "", "halted": False,
        "stages": defaultdict(blank_stage),
        "billed_models": Counter(),
        "sessions": set(),
        "agent_calls": Counter(),
        "header": None,
        "result_seen": False,
        "model_usage": {},          # AUTORITE des totaux (par modele)
        "total_cost_usd": None,
    }
    header_seen = False
    seen_msg = set()                # (etage, message.id) — cf. piege 1 de l'en-tete
    with open_bytes(path) as fh:
        for raw in fh:
            # Pre-filtre : 9 lignes sur 10 sont du progres d'outil sans jetons.
            if (b'"usage"' not in raw and b'"event"' not in raw
                    and b'"session_id"' not in raw and b'"tool_use"' not in raw):
                continue
            try:
                d = json.loads(raw)
            except Exception:
                continue

            ev = d.get("event")
            if ev in ("attempt_start", "phase_start"):
                rec["backend"] = d.get("backend") or "claude"
                rec["model"] = d.get("model") or ""
                rec["effort"] = d.get("effort") or ""
                rec["subagent_model"] = d.get("subagent_model")
                rec["started_at"] = d.get("started_at")
                rec["header"] = ev
                header_seen = True
                continue
            if ev in ("attempt_end", "phase_end"):
                rec["ended_at"] = d.get("ended_at")
                rec["exit_code"] = d.get("exit_code")
                rec["tool_calls"] = d.get("tool_calls")
                rec["abort_reason"] = d.get("abort_reason") or ""
                rec["halted"] = bool(d.get("halted"))
                continue

            sid = d.get("session_id") or d.get("sessionId")
            if sid:
                rec["sessions"].add(sid)

            t = d.get("type")
            if t == "result":
                # UN ESSAI PEUT PORTER PLUSIEURS `result` : l'orchestrateur relance la
                # session, et CHAQUE `result` republie un `modelUsage` CUMULE depuis le
                # debut (18,8 M -> 19,0 M -> 19,3 M de cache lu sur ao-indirect-clean/1,
                # 40 evenements). Les additionner gonflait le cout de 25 % — et c'est
                # l'ecart qui trahissait le defaut : 192 essais a un seul `result`
                # tombaient au jeton pres sur la somme par etage, les 59 autres non.
                # On garde donc le DERNIER instantane, jamais la somme.
                rec["result_seen"] = True
                rec["n_results"] = rec.get("n_results", 0) + 1
                rec["total_cost_usd"] = d.get("total_cost_usd")
                snap = {}
                for mname, mu in (d.get("modelUsage") or {}).items():
                    canon = mu.get("canonicalModel") or mname
                    acc = snap.setdefault(
                        canon, {"inp": 0, "cread": 0, "cwrite": 0, "out": 0,
                                "thinking": 0, "cost_usd": 0.0, "basis": mu.get("costBasis")})
                    acc["inp"] += int(mu.get("inputTokens") or 0)
                    acc["cread"] += int(mu.get("cacheReadInputTokens") or 0)
                    acc["cwrite"] += int(mu.get("cacheCreationInputTokens") or 0)
                    acc["out"] += int(mu.get("outputTokens") or 0)
                    acc["thinking"] += int(mu.get("thinkingTokens") or 0)
                    acc["cost_usd"] += float(mu.get("costUSD") or 0.0)
                rec["model_usage"] = snap
                continue

            if t == "assistant":
                msg = d.get("message") or {}
                parent = d.get("parent_tool_use_id")
                stage = "principal" if not parent else (d.get("subagent_type") or "sous-agent-inconnu")
                for c in msg.get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") in ("Agent", "Task"):
                        sub = (c.get("input") or {}).get("subagent_type") or "?"
                        rec["agent_calls"][sub] += 1
                u = msg.get("usage")
                mid = msg.get("id")
                if not u or not mid:
                    continue
                key = (stage, mid)
                if key in seen_msg:
                    continue
                seen_msg.add(key)
                inp, cread, cwrite, _out = norm_anthropic(u)
                s = rec["stages"][stage]
                s["inp"] += inp
                s["cread"] += cread
                s["cwrite"] += cwrite
                cc = u.get("cache_creation") or {}
                s["cw5"] += int(cc.get("ephemeral_5m_input_tokens") or 0)
                s["cw1h"] += int(cc.get("ephemeral_1h_input_tokens") or 0)
                # `out` reste a 0 : acompte non fiable (piege 2). La sortie est de session.
                s["msgs"] += 1
                if msg.get("model"):
                    rec["billed_models"][msg["model"]] += 1
                    # Le modele REELLEMENT facture A CET ETAGE. C'est ce qui permet de
                    # verifier, sur nos propres traces, qu'un `subagent_model` configure
                    # prend effet au lieu d'etre ignore en silence.
                    s["models"][msg["model"]] = s["models"].get(msg["model"], 0) + 1
            elif t == "turn.completed":
                u = d.get("usage") or {}
                inp, cread, cwrite, out = norm_openai(u)
                # Codex ne distingue pas l'etage dans ce flux : tout est agrege.
                s = rec["stages"]["codex-agrege"]
                s["inp"] += inp
                s["cread"] += cread
                s["cwrite"] += cwrite
                s["out"] += out
                s["msgs"] += 1
                acc = rec["model_usage"].setdefault(
                    "gpt-6-astra", {"inp": 0, "cread": 0, "cwrite": 0, "out": 0,
                                    "thinking": 0, "cost_usd": 0.0, "basis": "codex-turn"})
                acc["inp"] += inp
                acc["cread"] += cread
                acc["cwrite"] += cwrite
                acc["out"] += out
                acc["thinking"] += int(u.get("reasoning_output_tokens") or 0)
                rec["result_seen"] = True

    if not header_seen:
        return None
    rec["stages"] = {k: v for k, v in rec["stages"].items()}
    rec["sessions"] = sorted(rec["sessions"])
    rec["billed_models"] = dict(rec["billed_models"])
    rec["agent_calls"] = dict(rec["agent_calls"])
    return rec


# ---------------------------------------------------------------- superviseur

def scan_supervisor(worker_sessions):
    """
    Les transcriptions sous ~/.claude/projects/ melangent DEUX voix : les workers
    (lances par `claude -p`, qui ecrivent AUSSI leur transcription la) et le superviseur.
    Le discriminant n'est pas une heuristique : un worker a laisse son `session_id` dans
    son propre `attempt-NNN.jsonl`. Tout ce qui n'est pas dans cet ensemble est du
    superviseur (ou une session interactive de l'owner — c'est nomme comme tel).
    """
    out = {"files": 0, "worker_files": 0, "messages": 0,
           "inp": 0, "cread": 0, "cwrite": 0, "cw5": 0, "cw1h": 0, "out": 0,
           "models": {}, "by_time": []}
    if not SUPERVISOR_DIR.is_dir():
        out["missing"] = True
        return out
    for f in sorted(SUPERVISOR_DIR.glob("*.jsonl")):
        sid = f.stem
        if sid in worker_sessions:
            out["worker_files"] += 1
            continue
        out["files"] += 1
        seen = set()
        with open(f, "rb") as fh:
            for raw in fh:
                if b'"usage"' not in raw:
                    continue
                try:
                    d = json.loads(raw)
                except Exception:
                    continue
                if d.get("type") != "assistant":
                    continue
                msg = d.get("message") or {}
                u = msg.get("usage")
                mid = msg.get("id")
                if not u or not mid or mid in seen:
                    continue
                seen.add(mid)
                inp, cread, cwrite, o = norm_anthropic(u)
                cc = u.get("cache_creation") or {}
                out["messages"] += 1
                out["inp"] += inp
                out["cread"] += cread
                out["cwrite"] += cwrite
                out["cw5"] += int(cc.get("ephemeral_5m_input_tokens") or 0)
                out["cw1h"] += int(cc.get("ephemeral_1h_input_tokens") or 0)
                out["out"] += o
                if msg.get("model"):
                    out["models"][msg["model"]] = out["models"].get(msg["model"], 0) + 1
                ts = d.get("timestamp")
                if ts:
                    out["by_time"].append([ts, inp, cread, cwrite, o])
    out["by_time"].sort(key=lambda r: r[0])
    return out


# ---------------------------------------------------------------- assemblage

def main():
    t0 = time.time()
    attempts = discover_attempts()
    validators = discover_validators()

    records = []
    unreadable = 0
    for (item, num), path in sorted(attempts.items()):
        rec = scan_attempt(path)
        if rec is None:
            unreadable += 1
            continue
        rec["item"] = item
        rec["attempt"] = num
        rec["path"] = str(path.relative_to(AUTOPORT))

        v = validators.get((item, num))
        if v is None:
            rec["verdict"] = "sans-verdict"
            rec["fingerprint"] = None
            rec["cause"] = None
        else:
            text = v.read_text(errors="replace")
            rec["verdict"] = classify_validator(text)
            if rec["verdict"] == "rouge":
                fp, key_lines = fingerprint_validator_output(text)
                rec["fingerprint"] = fp
                rec["cause"] = classify_failure_cause(key_lines)
            else:
                rec["fingerprint"] = None
                rec["cause"] = None
        records.append(rec)

    # --- boucles : meme empreinte d'echec, essais CONSECUTIFS, seuil du harnais.
    by_item = defaultdict(list)
    for r in records:
        by_item[r["item"]].append(r)
    for item, rs in by_item.items():
        rs.sort(key=lambda r: r["attempt"])
        for r in rs:
            r["in_loop"] = False
        i = 0
        while i < len(rs):
            fp = rs[i]["fingerprint"]
            if not fp:
                i += 1
                continue
            j = i
            while j + 1 < len(rs) and rs[j + 1]["fingerprint"] == fp:
                j += 1
            if (j - i + 1) >= STUCK_REPEAT_THRESHOLD:
                for k in range(i, j + 1):
                    rs[k]["in_loop"] = True
            i = j + 1

    worker_sessions = set()
    for r in records:
        worker_sessions.update(r["sessions"])
    sup = scan_supervisor(worker_sessions)

    digest = {
        "version": VERSION,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "elapsed_s": round(time.time() - t0, 1),
        "attempt_files_found": len(attempts),
        "attempt_files_unreadable": unreadable,
        "validator_files_found": len(validators),
        "stuck_threshold": STUCK_REPEAT_THRESHOLD,
        "supervisor": {k: v for k, v in sup.items() if k != "by_time"},
        "supervisor_timeline_len": len(sup.get("by_time", [])),
        "attempts": [
            {k: v for k, v in r.items() if k not in ("sessions",)}
            for r in records
        ],
    }
    # La chronologie du superviseur sert a l'attribution par profil ; elle est volumineuse
    # et vit dans un fichier a part pour que le digest reste lisible a l'oeil.
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "supervisor-timeline.json").write_text(
        json.dumps(sup.get("by_time", []), separators=(",", ":")))
    (out_dir / "digest.json").write_text(json.dumps(digest, indent=1, ensure_ascii=False))
    print(f"{len(records)} essais lus, {unreadable} illisibles, "
          f"superviseur {sup['files']} sessions / {sup['worker_files']} ecartees (workers), "
          f"{digest['elapsed_s']}s", file=sys.stderr)


if __name__ == "__main__":
    main()
