"""La SORTIE vers l'owner d'un chantier VISIBLE exige une capture sur son ticket.

Owner 18/09 02:50 : « t'aurais pu joindre un screen ça aurait accéléré les choses… ». DIRECTIVES
l'a demandé en consigne ; trois agents sur trois l'ont ignorée (hud-eco-gauge essai 11 le 21/09
00:46, grass-blade-variants, grass-interaction-direction). Une consigne ignorée partout n'est pas
une règle : c'est une porte qui manque. La voici, lue par `close_gate` juste avant GATE 4.

La capture n'est PAS une preuve (règle 2) : la porte de mesure ne change pas, seule la sortie vers
l'owner est conditionnée. Amendement de l'owner du 22/09 : une capture impossible ne devient
JAMAIS un essai rouge ni une mesure de substitution. Trois issues, et trois seulement :

  (a) `capture`  un commentaire du harnais posté PENDANT l'essai porte une image      -> passe
  (b) `livre`    capture impossible DÉCLARÉE (`--no-capture`) ET un build publié
                 PENDANT l'essai (`.published_build_info.txt`)                        -> passe
  (c) `defaut`   ni l'un ni l'autre                                                    -> refus

Un item hors champ (`owner_test: false`, `owner_verify: false`, ou `where` qui dit « rien à
installer / rien à regarder ») n'est pas concerné : `hors-champ`.

LE REGISTRE est écrit au POINT DE PRODUCTION — `linear_sync.post_comment`, le seul endroit d'où le
harnais poste — et non reconstitué à la fermeture : `logs/linear_comments.jsonl`, une ligne par
commentaire posté, avec l'identifiant que Linear a rendu.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
import unicodedata
from datetime import datetime
from pathlib import Path

LEDGER = Path("logs") / "linear_comments.jsonl"
PUBLISHED = ".published_build_info.txt"
IMAGE_RX = re.compile(r"!\[[^\]]*\]\([^)]+\)")
NOTHING_TO_SEE_RX = re.compile(r"rien a (installer|regarder)")
DATE_RX = re.compile(r"^date: (\S+)", re.M)
TAG_RX = re.compile(r"^TAG: (\S+)", re.M)

HORS_CHAMP, CAPTURE, LIVRE, DEFAUT = "hors-champ", "capture", "livre", "defaut"

# LE VRAI REGISTRE N'ACCUEILLE QUE DE VRAIS COMMENTAIRES (harness-tests-never-write-real-registries, 23/09).
# Le 23/09, 134 lignes sur 231 du registre de l'arbre principal venaient des tests et des recensements
# (tickets `t-d`, `t-b`, `t0`, `T9`, `verdict`, items `item-d`, `harness-un`...) et 26 n'avaient pas d'item :
# CLOSE-GATE/capture et INVISIBLE-CAPTURE lisaient ce melange. Deux verrous, ici, au point de production :
#   * REGISTRY_ENV : un banc qui la pose (tests/harness/bench_env.py) ecrit et lit le registre de l'arbre
#     principal dans ce dossier jetable, jamais dans `.autoport/logs`. Un `ap_dir` de bac a sable n'est
#     pas concerne : il est deja jetable.
#   * `polluted` : ce qui n'est pas un commentaire Linear rattache a un chantier (ticket qui n'est pas un
#     identifiant Linear, item vide) n'entre JAMAIS dans le registre de l'arbre principal. Meme predicat
#     que la grandeur `registry_pollution` (lib/census/harness-tests-never-write-real-registries.py).
REGISTRY_ENV = "AUTOPORT_REGISTRY_DIR"
LINEAR_ID_RX = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_MAIN = {}


def main_autoport() -> Path:
    """Le `.autoport` de l'arbre PRINCIPAL (meme regle que `linear_sync._home`), celui du vrai registre."""
    if "p" not in _MAIN:
        here = Path(__file__).resolve().parents[1]
        try:
            common = subprocess.run(["git", "-C", str(here), "rev-parse", "--path-format=absolute",
                                     "--git-common-dir"], capture_output=True, text=True, timeout=10).stdout.strip()
        except Exception:  # noqa: BLE001 — pas de git : l'arbre courant
            common = ""
        main = Path(common).parent / ".autoport" if common else None
        _MAIN["p"] = (main if main and (main / "linear_sync.py").exists() else here).resolve()
    return _MAIN["p"]


def is_main(ap_dir) -> bool:
    try:
        return Path(ap_dir).resolve() == main_autoport()
    except OSError:
        return False


def ledger_path(ap_dir) -> Path:
    """Ou le registre de `ap_dir` s'ecrit ET se lit : le dossier jetable du banc pour l'arbre principal."""
    env = os.environ.get(REGISTRY_ENV, "").strip()
    if env and is_main(ap_dir):
        return Path(env) / LEDGER.name
    return Path(ap_dir) / LEDGER


def polluted(rec: dict) -> str:
    """Pourquoi cette ligne n'a pas sa place dans le vrai registre ('' = elle l'a)."""
    if not str(rec.get("item") or "").strip():
        return "sans-item"
    if not LINEAR_ID_RX.match(str(rec.get("issue_id") or "")):
        return "ticket-fictif"
    return ""


def plain(text) -> str:
    """Minuscules sans accents : « Rien à regarder » et « rien a regarder » se lisent pareil."""
    t = unicodedata.normalize("NFKD", str(text or ""))
    return "".join(c for c in t if not unicodedata.combining(c)).lower()


def is_visible(item: dict) -> tuple[bool, str]:
    """(concerné ?, pourquoi). Mêmes drapeaux que GATE 4 : ce qui ne va pas au test n'a rien à joindre."""
    if not item.get("owner_test", True):
        return False, "owner_test: false"
    if not item.get("owner_verify", True):
        return False, "owner_verify: false"
    if NOTHING_TO_SEE_RX.search(plain(item.get("where"))):
        return False, "where : rien a installer / rien a regarder"
    return True, "chantier visible"


def has_image(body: str) -> bool:
    return bool(IMAGE_RX.search(body or ""))


# INVISIBLE-CAPTURE/ (harness-invisible-item-comment-has-no-capture-boilerplate, 23/09). Owner, sur
# JAK-240 : « c'est le genre de chantier qui nécessite pas de capture, donc c'est attendu qu'il n'y
# ait pas de capture, gaspillage d'énergie là ! ». Le worker d'un item `owner_test: false` avait
# ecrit « Capture impossible : ... Build a tester : ... » par habitude (paragraphe capture de
# DIRECTIVES, alors rendu a TOUS les items). Un chantier hors champ ne parle ni de capture ni de
# build a tester : `--comment` le REFUSE (le worker l'apprend), `post_comment` le RETIRE (filet du
# point de production, pour les messages que le harnais compose lui-meme).
TALK_RX = re.compile(r"\bcaptures?\b|build a tester|screenshot|screencap|--no-capture")
IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp")


def _flat(text) -> str:
    return " ".join(plain(text).split())


def capture_talk(item: dict, body: str) -> list[str]:
    """Ce qui, dans `body`, parle de capture ou de build a tester — hors le TITRE et l'id de l'item,
    que le harnais cite (« Critère : « ... » ») sans que personne n'en parle. Une image jointe compte."""
    t = _flat(body)
    for s in (item.get("feature"), item.get("id")):
        s = _flat(s)
        if s:
            t = t.replace(s, " ")
    hits = [m.group(0) for m in TALK_RX.finditer(t)]
    if has_image(body):
        hits.append("image")
    return hits


def invisible_comment_refusal(item: dict, body="", attach=(), no_capture="") -> str:
    """Motif du refus d'un `--comment` sur un chantier hors champ, ou "" s'il peut partir.
    Un item visible n'est jamais refuse ici : sa capture reste exigee (`judge`)."""
    vis, why = is_visible(item or {})
    if vis:
        return ""
    bad = []
    if (no_capture or "").strip():
        bad.append("--no-capture")
    imgs = [Path(str(f)).name for f in (attach or ()) if Path(str(f)).suffix.lower() in IMAGE_SUFFIXES]
    if imgs:
        bad.append("image jointe (%s)" % ", ".join(imgs))
    talk = sorted(set(capture_talk(item, body)))
    if talk:
        bad.append("le message parle de : %s" % ", ".join(talk))
    if not bad:
        return ""
    return ("REFUS INVISIBLE-CAPTURE : %s est un chantier hors champ (%s) : l'owner n'a rien a regarder, "
            "donc ni capture ni build a tester (owner 23/09 : « gaspillage d'énergie »). En cause : %s. "
            "Poste le verdict sans en parler." % (item.get("id", "?"), why, " ; ".join(bad)))


def scrub_invisible(item: dict, body: str) -> tuple[str, int]:
    """Filet de `post_comment` : sur un chantier hors champ, retire les images et les LIGNES qui parlent
    de capture ou de build a tester. -> (corps, nombre de passages retires). Visible : inchange."""
    if not item or is_visible(item)[0]:
        return body, 0
    out, n = [], 0
    for ln in (body or "").split("\n"):
        bare = IMAGE_RX.sub("", ln)
        if bare != ln:
            n += 1
            if not bare.strip():
                continue
        if capture_talk(item, bare):
            # par PHRASE : l'annonce de verdict relaie le rapport de l'agent sur UNE ligne
            keep = [x for x in re.split(r"(?<=[.!?;])\s+", bare) if not capture_talk(item, x)]
            n += 1
            if not "".join(keep).strip():
                continue
            bare = " ".join(keep)
        out.append(bare)
    return "\n".join(out).strip("\n"), n


def published_build(ap_dir) -> dict:
    """Le build publié tel que `.published_build_info.txt` le décrit : {tag, date, epoch} ou {}."""
    try:
        txt = (Path(ap_dir) / PUBLISHED).read_text(errors="replace")
    except OSError:
        return {}
    md, mt = DATE_RX.search(txt), TAG_RX.search(txt)
    if not md:
        return {}
    try:
        epoch = datetime.fromisoformat(md.group(1)).timestamp()
    except ValueError:
        return {}
    return {"tag": mt.group(1) if mt else "?", "date": md.group(1), "epoch": epoch}


def record(ap_dir, item_id, body, *, issue_id="", comment_id="", capture_failed="",
           when=None, visible=None, talk=None, stripped=0) -> dict:
    """Une ligne du registre. Appelée par `linear_sync.post_comment` APRÈS le succès de Linear."""
    build = published_build(ap_dir) if capture_failed else {}
    rec = {
        "at": float(when if when is not None else time.time()),
        "item": item_id or "",
        "issue_id": issue_id or "",
        "comment_id": comment_id or "",
        "image": has_image(body),
        "capture_failed": (capture_failed or "").strip(),
        "build_tag": build.get("tag", ""),
        "build_epoch": build.get("epoch", 0.0),
    }
    if visible is not None:   # INVISIBLE-CAPTURE/ : lu par le recensement de l'item, apres le correctif
        rec.update(visible=bool(visible), talk=list(talk or []), stripped=int(stripped or 0))
    p = ledger_path(ap_dir)
    why = polluted(rec) if p == Path(ap_dir) / LEDGER and is_main(ap_dir) else ""
    if why:
        print("REGISTRE DES COMMENTAIRES : ligne refusee (%s : item=%r ticket=%r) — le vrai registre ne "
              "prend que des commentaires Linear rattaches a un chantier" % (why, rec["item"], rec["issue_id"]))
        rec["refused"] = why
        return rec
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    return rec


def entries(ap_dir, item_id, since: float) -> list[dict]:
    """Les commentaires du harnais postés sur l'item depuis `since` (début de l'essai)."""
    out = []
    try:
        lines = ledger_path(ap_dir).read_text(errors="replace").splitlines()
    except OSError:
        return out
    for ln in lines:
        try:
            r = json.loads(ln)
        except ValueError:
            continue
        if r.get("item") == item_id and float(r.get("at") or 0) >= since:
            out.append(r)
    return out


def judge(item: dict, since: float, ap_dir) -> dict:
    """{verdict, why, comments, images, declared, build}. `verdict` ∈ HORS_CHAMP/CAPTURE/LIVRE/DEFAUT."""
    iid = item.get("id", "?")
    vis, why = is_visible(item)
    res = {"verdict": HORS_CHAMP, "why": why, "comments": 0, "images": 0, "declared": 0,
           "build": ""}
    if not vis:
        return res
    got = entries(ap_dir, iid, since)
    res["comments"] = len(got)
    res["images"] = sum(1 for r in got if r.get("image"))
    declared = [r for r in got if r.get("capture_failed")]
    res["declared"] = len(declared)
    if res["images"]:
        res["verdict"], res["why"] = CAPTURE, "capture jointe au ticket pendant l'essai"
        return res
    # (b) : le build publié compte s'il date de CET essai — relu au moment du commentaire OU
    # maintenant (le publieur peut passer entre le commentaire et la fermeture).
    now = published_build(ap_dir)
    fresh = [r.get("build_tag") for r in declared if float(r.get("build_epoch") or 0) >= since]
    if declared and not fresh and now.get("epoch", 0) >= since:
        fresh = [now.get("tag", "?")]
    if declared and fresh:
        res["verdict"], res["build"] = LIVRE, fresh[0]
        res["why"] = ("capture impossible declaree (%s), build %s publie pendant l'essai"
                      % (declared[-1]["capture_failed"][:80], fresh[0]))
        return res
    res["verdict"] = DEFAUT
    if declared:
        res["why"] = ("capture impossible declaree, mais AUCUN build publie depuis le debut de "
                      "l'essai (.published_build_info.txt : %s)" % (now.get("date") or "absent"))
    else:
        res["why"] = ("%d commentaire(s) du harnais sur le ticket pendant l'essai, AUCUNE image, "
                      "aucune capture impossible declaree" % len(got))
    return res


def refusal(item: dict, res: dict) -> str:
    """Le texte du refus : la raison, puis les DEUX seules sorties, commande comprise."""
    iid = item.get("id", "?")
    return (f"CLOSE-GATE/capture: {iid} est un chantier VISIBLE et part au test de l'owner sans "
            f"capture — {res['why']}. La mesure a tenu ; seule la sortie vers l'owner est "
            f"refusee (owner 18/09 : « t'aurais pu joindre un screen »). Deux sorties : "
            f"(a) python3 .autoport/linear_sync.py --comment {iid} --body \"ce qu'il verra\" "
            f"--attach capture.png ; (b) si la capture est IMPOSSIBLE, livre un build a tester "
            f"(APK publie, .published_build_info.txt) et poste --comment {iid} --no-capture "
            f"\"pourquoi\" --body \"quoi regarder\". Aucune mesure visuelle ne remplace la "
            f"capture.")
