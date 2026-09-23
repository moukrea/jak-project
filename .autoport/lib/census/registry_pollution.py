#!/usr/bin/env python3
"""registry_pollution — le VRAI registre des commentaires Linear ne porte que des commentaires reels.

harness-tests-never-write-real-registries, 23/09. Le registre `logs/linear_comments.jsonl` de l'arbre
principal (lu par CLOSE-GATE/capture et INVISIBLE-CAPTURE) portait 134 lignes fictives sur 231, ecrites
par les tests et les recensements (tickets `t-d`, `t-b`, `t0`, `t2`, `T9`, `verdict`), et 26 lignes
sans item. Ce recensement publie :

  REGISTRE  le vrai registre, ligne par ligne, juge par `owner_capture.polluted` (MEME predicat que le
            refus au point de production) + item inconnu du backlog et de la carte. Denominateur publie.
  BANC      les six recensements qui ecrivaient les lignes fictives + `tests/harness/test_loop.py`,
            `test_attempt.py`, `test_owner_capture_gate.py` relances : aucune ligne polluee ajoutee.
  CONTROLES semes dans un faux arbre principal : refus (C+) et passage (C-) de `record` et de
            `linear_sync.post_comment`, et le compteur applique a un registre fabrique.

registry_pollution = lignes polluees du vrai registre + lignes ajoutees par le banc + controles rates.
"""
from __future__ import annotations

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
AP = ROOT / ".autoport"
sys.path[:0] = [str(AP), str(AP / "lib")]

OUT = {}
PENALTY = 0
UUID = "0f0e0d0c-0b0a-4908-8706-050403020100"
UUID2 = "1f1e1d1c-1b1a-4918-8716-151413121110"


def pub(k, v):
    OUT[k] = str(v).replace(" ", "_") if v != "" else "-"


def read(p):
    out = []
    try:
        lines = Path(p).read_text(errors="replace").splitlines()
    except OSError:
        return out
    for ln in lines:
        try:
            out.append(json.loads(ln))
        except ValueError:
            out.append({"item": "", "issue_id": "<json-illisible>"})
    return out


def judge(recs, known, OC):
    """(fictives, sans_item, item_inconnu) — une ligne n'est comptee qu'une fois."""
    fict = none = unknown = 0
    for r in recs:
        why = OC.polluted(r)
        if why == "sans-item":
            none += 1
        elif why:
            fict += 1
        elif r.get("item") not in known:
            unknown += 1
    return fict, none, unknown


class FakeL:
    def __init__(self):
        self.calls = 0

    def q(self, query, **v):
        self.calls += 1
        return {"commentCreate": {"success": True, "comment": {"id": "cmt-%d" % self.calls}}}


def controls(OC, LS):
    res = {}
    saved_main, saved_env = dict(OC._MAIN), os.environ.pop(OC.REGISTRY_ENV, None)
    saved_ls = {k: getattr(LS, k) for k in ("HOME", "MAP_PATH", "SHADOW_PATH", "on_ticket")}
    saved_ctx = dict(LS._CTX)
    try:
        with tempfile.TemporaryDirectory(prefix="registry-pollution-") as tmp:
            main, other, bench = Path(tmp) / "main", Path(tmp) / "sandbox", Path(tmp) / "bench"
            for d in (main, other, bench):
                d.mkdir()
            OC._MAIN["p"] = main.resolve()
            led = main / OC.LEDGER
            q = contextlib.redirect_stdout(io.StringIO())
            with q:
                r = OC.record(main, "item-d", "x", issue_id="t-d")
            res["pos_record_refuses_fictitious_ticket"] = r.get("refused") == "ticket-fictif" and not led.exists()
            with contextlib.redirect_stdout(io.StringIO()):
                r = OC.record(main, "", "x", issue_id=UUID)
            res["pos_record_refuses_empty_item"] = r.get("refused") == "sans-item" and not led.exists()
            OC.record(main, "harness-reel", "x", issue_id=UUID)
            res["neg_record_keeps_a_real_comment"] = len(read(led)) == 1
            OC.record(other, "item-d", "x", issue_id="t-d")
            res["neg_sandbox_ap_dir_still_written"] = len(read(other / OC.LEDGER)) == 1
            os.environ[OC.REGISTRY_ENV] = str(bench)
            OC.record(main, "item-d", "x", issue_id="t-d")
            res["pos_env_redirects_the_main_registry"] = (len(read(bench / OC.LEDGER.name)) == 1
                                                          and len(read(led)) == 1
                                                          and OC.entries(main, "item-d", 0)[0]["issue_id"] == "t-d")
            os.environ.pop(OC.REGISTRY_ENV, None)

            # post_comment : un ticket hors carte ne part pas ; un ticket de la carte part meme sans main()
            (main / "map.json").write_text(json.dumps({"harness-reel": {"issue_id": UUID2, "identifier": "JAK-0"}}))
            LS.HOME, LS.MAP_PATH, LS.SHADOW_PATH = main, main / "map.json", main / "absent.json"
            LS.on_ticket = lambda L, _i, fn, revive=True: fn()
            LS._CTX.update(bl={"harness-reel": {"id": "harness-reel", "owner_test": False}}, mp=None)
            fl = FakeL()
            n0 = len(read(led))
            with contextlib.redirect_stdout(io.StringIO()):
                r = LS.post_comment(fl, "T9", "Porte tenue.")
            res["pos_post_without_item_is_not_sent"] = r is None and fl.calls == 0 and len(read(led)) == n0
            with contextlib.redirect_stdout(io.StringIO()):
                r = LS.post_comment(fl, UUID2, "Porte tenue.")
            rows = read(led)
            res["neg_post_mapped_ticket_is_sent_and_attached"] = (fl.calls == 1 and len(rows) == n0 + 1
                                                                  and rows[-1].get("item") == "harness-reel")

            # le compteur sur un registre FABRIQUE : 3 bons, 2 fictifs, 1 sans item, 1 inconnu
            fab = [{"item": "a", "issue_id": UUID}] * 3 + [{"item": "item-d", "issue_id": "t-d"},
                                                           {"item": "harness-un", "issue_id": "t0"},
                                                           {"item": "", "issue_id": UUID},
                                                           {"item": "fantome", "issue_id": UUID}]
            res["pos_counter_on_a_fabricated_registry"] = judge(fab, {"a"}, OC) == (2, 1, 1)
            res["neg_counter_on_a_clean_registry"] = judge(fab[:3], {"a"}, OC) == (0, 0, 0)
    finally:
        OC._MAIN.clear()
        OC._MAIN.update(saved_main)
        if saved_env is not None:
            os.environ[OC.REGISTRY_ENV] = saved_env
        for k, v in saved_ls.items():
            setattr(LS, k, v)
        LS._CTX.update(saved_ctx)
    return res


def main():
    global PENALTY
    import owner_capture as OC
    from lib import backlog as B
    import linear_sync as LS

    real = OC.main_autoport()
    ledger = real / OC.LEDGER
    pub("registry_path", ledger.relative_to(ROOT) if ledger.is_relative_to(ROOT) else ledger)
    known = {it["id"] for it in B.load().items}
    try:
        known |= {k for k in json.loads((real / "linear_map.json").read_text()) if not k.startswith("_")}
    except (OSError, ValueError):
        pass

    # ------------------------------------------------------------ le banc ne touche plus au vrai registre
    # Les ecrivains du 23/09 : les recensements qui importent `linear_sync` avec le VRAI `HOME` (item-d/item-b,
    # harness-un/trois, T9, verdict), et les deux fichiers de tests cites par l'item. `harness-linear-own-identity`
    # n'est pas relance : il poste un VRAI commentaire sur son ticket.
    writers = ["harness-linear-pull-reads-archived-tickets", "harness-linear-relinks-closed-tickets",
               "harness-linear-relink-keeps-owner-comments", "harness-linear-owner-moves-never-lost",
               "harness-linear-auto-archive-when-space-runs-out", "harness-owner-sla-answer-must-address-the-owner"]
    tests = ["tests/harness/test_loop.py", "tests/harness/test_attempt.py", "tests/harness/test_owner_capture_gate.py"]
    before = read(ledger)
    env = {k: v for k, v in os.environ.items() if k != OC.REGISTRY_ENV}   # le banc pose SA variable lui-meme
    r = subprocess.run([sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider"] + tests, cwd=str(AP),
                       env=env, capture_output=True, text=True, timeout=600)
    pub("bench_rc", r.returncode)
    pub("bench_summary", (r.stdout.strip().splitlines() or ["-"])[-1][:120])
    bad_rc = int(r.returncode != 0)
    ran = 0
    for w in writers:
        c = subprocess.run(["bash", str(AP / "lib" / "census" / (w + ".sh"))], cwd=str(ROOT), env=env,
                           capture_output=True, text=True, timeout=300)
        ran += c.returncode == 0
    pub("writers_census_run", len(writers))
    pub("writers_census_rc0", ran)
    after = read(ledger)
    added = after[len(before):]
    bench_polluted = sum(1 for x in added if OC.polluted(x) or x.get("item") not in known)
    pub("bench_registry_lines_added", len(added))
    pub("bench_registry_polluted_added", bench_polluted)
    # AVANT le correctif, la meme relance ajoutait 102 (item-d/b) + 12 (harness-un/trois) + 18 (T9/verdict)
    # lignes par passage complet des recensements : notes/purged.jsonl garde les 134 lignes retirees.

    # ------------------------------------------------------------ le vrai registre
    recs = read(ledger)
    fict, none, unknown = judge(recs, known, OC)
    pub("registry_records", len(recs))
    pub("registry_fictitious", fict)
    pub("registry_without_item", none)
    pub("registry_unknown_item", unknown)
    pub("registry_known_items", len(known))

    # ------------------------------------------------------------ controles semes
    res = controls(OC, LS)
    for k, ok in res.items():
        pub("control_" + k, int(bool(ok)))
    failed = sum(1 for ok in res.values() if not ok)
    pub("registry_controls", len(res))
    pub("registry_controls_positive", sum(1 for k in res if k.startswith("pos_")))
    pub("registry_controls_negative", sum(1 for k in res if k.startswith("neg_")))
    pub("registry_controls_failed", failed)
    PENALTY += failed + bad_rc + (len(writers) - ran)
    pub("registry_pollution", fict + none + unknown + bench_polluted + PENALTY)


if __name__ == "__main__":
    rc = 0
    try:
        main()
    except Exception as e:  # noqa: BLE001
        pub("registry_pollution_error", "%s:%s" % (type(e).__name__, str(e)[:120]))
        OUT["registry_pollution"] = str(1000 + PENALTY)
        rc = 1
    for k, v in OUT.items():
        print("%s=%s" % (k, v))
    sys.exit(rc)
