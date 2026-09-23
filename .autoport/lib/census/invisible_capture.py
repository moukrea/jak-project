#!/usr/bin/env python3
"""Recensement de `harness-invisible-item-comment-has-no-capture-boilerplate` (INVISIBLE-CAPTURE/).

Owner 23/09, sur JAK-240 : « c'est le genre de chantier qui nécessite pas de capture, donc c'est
attendu qu'il n'y ait pas de capture, gaspillage d'énergie là ! ». Un chantier hors champ
(`owner_capture.is_visible` faux : owner_test/owner_verify faux, ou `where` « rien a regarder »)
ne parle ni de capture ni de build a tester dans ses commentaires.

Publie (cle=valeur, sans espace) :
  AVANT   le registre `logs/linear_comments.jsonl` sur 7 jours, jusqu'au correctif : messages
          d'items hors champ portant une image, un `--no-capture` ou un build a tester.
  APRES   les memes messages depuis le commit du correctif (ancre = premier commit de
          linear_sync.py portant le marqueur), plus ce que le filet de `post_comment` a retire.
  PROMPT  le contrat DIRECTIVES rendu a chaque item VIVANT : zero consigne capture pour un hors
          champ, la consigne pour un visible.
  CONTROLES le VRAI `linear_sync.main()` (`--comment`) et le VRAI `post_comment`, reseau remplace
          par un faux qui compte : items fabriques hors champ (refus / retrait) et visibles (capture
          toujours exigee, ligne « Build a tester » toujours composee, `judge` -> defaut).

`invisible_item_capture_mentions` = APRES + PROMPT + controles en echec. Jamais un zero par silence :
une etape qui tombe publie son echec et ajoute 1000.
"""
from __future__ import annotations

import contextlib
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

AP = Path(__file__).resolve().parents[2]
ROOT = AP.parent
sys.path.insert(0, str(AP))
sys.path.insert(0, str(AP / "lib"))
from lib.census import fake_backlog as FB

MARKER = "INVISIBLE-CAPTURE/"
PROMPT_RX = re.compile(r"--no-capture|close-gate/capture|joins une capture|build a tester|--attach capture")
LIVE = ("open", "in-progress", "blocked", "to-test")
WEEK = 7 * 86400

OUT: dict[str, object] = {}
PENALTY = 0


def pub(k, v):
    OUT[k] = str(v).replace(" ", "_") if v != "" else "-"


# ------------------------------------------------------------------ l'ancre : le commit du correctif
def anchor():
    r = subprocess.run(["git", "-C", str(ROOT), "log", "--reverse", "--format=%h %ct", "-S" + MARKER,
                        "--", ".autoport/linear_sync.py"], capture_output=True, text=True, timeout=60)
    first = (r.stdout.strip().splitlines() or [""])[0].split()
    if len(first) == 2:
        return first[0], float(first[1])
    return "non-commite", time.time()


# ------------------------------------------------------------------ les controles semes
class FakeL:
    mode = "app"

    def __init__(self, log):
        self.log = log

    def q(self, query, **kw):
        if "commentCreate" in query:
            self.log["posted"].append(kw["i"]["body"])
            return {"commentCreate": {"success": True, "comment": {"id": "fake-%d" % len(self.log["posted"])}}}
        self.log["net"] += 1
        return {}


def controls(LS, OC, DV, tmp):
    import owner_capture as oc_mod  # noqa: F401
    inv = {"id": "zz-invisible-control", "feature": "reglage interne", "status": "in-progress",
           "owner_test": False}
    vis = {"id": "zz-visible-control", "feature": "herbe plus verte", "status": "in-progress",
           "owner_test": True, "where": "Sandover, l'herbe du village"}
    log = {"posted": [], "net": 0}
    fakel = FakeL(log)

    def boom(*_a, **_k):
        log["net"] += 1
        raise RuntimeError("reseau interdit dans le controle")

    LS.map_lock = lambda: None
    LS.SM.install_hooks = lambda **_k: None
    LS.LI.resolve = lambda: {"mode": "app", "why": "controle"}
    LS.Linear = lambda _ident: fakel
    LS.load_map = lambda: {i["id"]: {"issue_id": "ISS-" + i["id"], "identifier": "FAKE-" + i["id"]} for i in (inv, vis)}
    LS.on_ticket = lambda L, _issue, fn, revive=True: fn()
    LS.default_reply_target = lambda *_a, **_k: None
    LS.upload_file = lambda L, f: ("https://fake/" + Path(f).name,
                                   "image/png" if Path(f).suffix == ".png" else "text/plain")
    LS.ensure_team = lambda L: None
    LS.labels = lambda L, team: (None, None)
    LS.swap_labels = lambda *_a, **_k: None
    LS.requests.post = LS.requests.get = LS.requests.put = boom
    LS.LI.gql = boom
    LS.HOME = Path(tmp)
    ctl_sb = FB.Sandbox([inv, vis])
    FB.install(LS, ctl_sb)
    LS._CTX.update(bl=None, mp=None)

    def run(args):
        n0, net0 = len(log["posted"]), log["net"]
        sys.argv = ["linear_sync.py"] + args
        code, err = 0, ""
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                LS.main()
        except SystemExit as e:
            code, err = 1, str(e.code or "")
        except Exception as e:  # noqa: BLE001
            code, err = 2, "%s: %s" % (type(e).__name__, e)
        return {"code": code, "err": err, "posted": log["posted"][n0:], "net": log["net"] - net0}

    res = {}
    # C+ : chantier hors champ -> refuse avant tout reseau, rien de poste
    for k, extra in (("no_capture", ["--no-capture", "rien a l'ecran"]),
                     ("attach_image", ["--attach", str(Path(tmp) / "shot.png")]),
                     ("body_boilerplate", [])):
        body = "Porte tenue." if k != "body_boilerplate" else \
            "Porte tenue. Capture impossible : reglage interne. Build a tester : 2971e3-c666da"
        r = run(["--comment", inv["id"], "--body", body] + extra)
        res["pos_" + k] = r["code"] == 1 and "INVISIBLE-CAPTURE" in r["err"] and not r["posted"] and r["net"] == 0
    # C+ : un message propre d'un chantier hors champ PART (le garde ne muselle pas)
    r = run(["--comment", inv["id"], "--body", "Porte tenue, rien a regarder dans le jeu."])
    res["pos_clean_passes"] = r["code"] == 0 and len(r["posted"]) == 1 and "Porte tenue" in r["posted"][0]
    # C+ : filet de post_comment (message compose par le harnais) -> image et ligne capture retirees
    LS._CTX["mp"] = LS.load_map()
    n0 = len(log["posted"])
    with contextlib.redirect_stdout(io.StringIO()):
        LS.post_comment(fakel, "ISS-" + inv["id"], "Essai 3 : porte tenue.\nCapture impossible : x. Build a tester : y\n\n![shot.png](https://fake/shot.png)")
    posted = log["posted"][n0:]
    led = [json.loads(ln) for ln in (Path(tmp) / "logs" / "linear_comments.jsonl").read_text().splitlines()]
    last = led[-1] if led else {}
    res["pos_net_strips"] = (len(posted) == 1 and "Essai 3" in posted[0] and not OC.capture_talk(inv, posted[0])
                             and last.get("stripped", 0) >= 2 and last.get("visible") is False
                             and not last.get("image") and not last.get("talk"))
    # C- : chantier visible -> --no-capture accepte, la ligne « Build a tester » est composee
    r = run(["--comment", vis["id"], "--body", "Herbe livree.", "--no-capture", "ecran eteint"])
    res["neg_no_capture_kept"] = r["code"] == 0 and len(r["posted"]) == 1 and "Build a tester" in r["posted"][0]
    r = run(["--comment", vis["id"], "--body", "Herbe livree.", "--attach", str(Path(tmp) / "shot.png")])
    res["neg_attach_kept"] = r["code"] == 0 and len(r["posted"]) == 1 and "![shot.png]" in r["posted"][0]
    # C- : la porte de fermeture exige toujours la capture d'un visible (registre vide -> defaut)
    empty = Path(tmp) / "empty"
    empty.mkdir()
    res["neg_judge_requires_capture"] = OC.judge(vis, time.time() - 60, empty)["verdict"] == OC.DEFAUT
    res["pos_judge_invisible_out_of_scope"] = OC.judge(inv, time.time() - 60, empty)["verdict"] == OC.HORS_CHAMP
    # C+/C- : le contrat rendu
    res["pos_prompt_invisible_no_rule"] = not PROMPT_RX.search(OC.plain(DV.block(inv["id"], record=False, item=inv)))
    res["neg_prompt_visible_has_rule"] = len(PROMPT_RX.findall(OC.plain(DV.block(vis["id"], record=False, item=vis)))) >= 2
    ctl_sb.close()
    return res


def main():
    global PENALTY
    import owner_capture as OC
    import directives as DV
    from lib import backlog as B
    real_load = B.load
    sha, t_fix = anchor()
    pub("invisible_capture_anchor", sha)
    pub("invisible_capture_anchor_epoch", int(t_fix))
    now = time.time()

    # ------------------------------------------------------------ registre reel : AVANT / APRES
    bl = real_load()
    by_id = {it["id"]: it for it in bl.items}
    import linear_sync as LS
    ledger = Path(LS.HOME) / OC.LEDGER
    recs = []
    for ln in ledger.read_text(errors="replace").splitlines():
        try:
            recs.append(json.loads(ln))
        except ValueError:
            pass
    pub("ledger_records", len(recs))
    # Le registre est ne le 23/09 : sa profondeur borne le recensement AVANT (les 7 jours sont lus
    # dans Linear une fois, hors preuve : reports/<id>/notes/).
    pub("ledger_depth_h", int((now - min((float(r.get("at") or now) for r in recs), default=now)) / 3600))
    before_n = before_hit = after_n = after_hit = after_strip = after_unflagged = unknown = 0
    before_items, after_items = set(), set()
    for r in recs:
        it = by_id.get(r.get("item") or "")
        if not it:
            unknown += 1
            continue
        if OC.is_visible(it)[0]:
            continue
        at = float(r.get("at") or 0)
        flagged = bool(r.get("image")) or bool((r.get("capture_failed") or "").strip()) or bool(r.get("build_tag"))
        if now - WEEK <= at < t_fix:
            before_n += 1
            if flagged:
                before_hit += 1
                before_items.add(r["item"])
        elif at >= t_fix:
            after_n += 1
            after_strip += int(r.get("stripped") or 0)
            if "visible" not in r:
                after_unflagged += 1
            if flagged or r.get("talk"):
                after_hit += 1
                after_items.add(r["item"])
    pub("invisible_comments_before_7d", before_n)
    pub("invisible_capture_before_7d", before_hit)
    pub("invisible_capture_before_7d_items", ",".join(sorted(before_items)) or "aucun")
    pub("invisible_capture_before_prose_measured", 0)   # le corps n'etait pas consigne avant le correctif
    pub("invisible_comments_after_fix", after_n)
    pub("invisible_capture_after_fix", after_hit)
    pub("invisible_capture_after_fix_items", ",".join(sorted(after_items)) or "aucun")
    pub("invisible_capture_stripped_after_fix", after_strip)
    pub("invisible_comments_after_fix_old_code", after_unflagged)
    pub("ledger_records_unknown_item", unknown)

    # ------------------------------------------------------------ contrat rendu aux items vivants
    inv_items = vis_items = inv_hits = vis_with = errs = 0
    for it in bl.items:
        if it.get("status") not in LIVE:
            continue
        try:
            n = len(PROMPT_RX.findall(OC.plain(DV.block(it["id"], record=False, item=it))))
        except Exception:  # noqa: BLE001
            errs += 1
            continue
        if OC.is_visible(it)[0]:
            vis_items += 1
            vis_with += n >= 2
        else:
            inv_items += 1
            inv_hits += n
    pub("invisible_prompt_items", inv_items)
    pub("invisible_prompt_capture_mentions", inv_hits)
    pub("visible_prompt_items", vis_items)
    pub("visible_prompt_items_with_capture_rule", vis_with)
    pub("prompt_render_errors", errs)
    PENALTY += (vis_items - vis_with) + errs

    # ------------------------------------------------------------ controles semes
    with tempfile.TemporaryDirectory(prefix="invisible-capture-") as tmp:
        (Path(tmp) / "shot.png").write_bytes(b"\x89PNG\r\n")
        res = controls(LS, OC, DV, tmp)
    for k, ok in res.items():
        pub("control_" + k, int(bool(ok)))
    failed = sum(1 for ok in res.values() if not ok)
    pub("invisible_capture_controls", len(res))
    pub("invisible_capture_controls_failed", failed)
    PENALTY += failed
    pub("invisible_item_capture_mentions", after_hit + inv_hits + PENALTY)


if __name__ == "__main__":
    rc = 0
    try:
        main()
    except Exception as e:  # noqa: BLE001
        pub("invisible_capture_error", "%s:%s" % (type(e).__name__, str(e)[:120]))
        OUT["invisible_item_capture_mentions"] = 1000 + PENALTY
        rc = 1
    for k, v in OUT.items():
        print("%s=%s" % (k, v))
    sys.exit(rc)
