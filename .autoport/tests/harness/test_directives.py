#!/usr/bin/env python3
"""Unit tests for .autoport/lib/directives.py — the contract handed to a worker.

They run against a THROWAWAY tree (tmp_path), never the real .autoport, so a
failing test cannot bump the serial or append to .directives_issued.

    python3 -m pytest .autoport/tests/harness/test_directives.py -q
    python3 .autoport/tests/harness/test_directives.py        # pytest absent
"""
import contextlib
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / ".autoport" / "lib"))

import directives  # noqa: E402

STANDING = "# DIRECTIVES — ordres permanents\n\nRègle 1 : un commentaire n'est pas une preuve.\n"


@contextlib.contextmanager
def fake_tree(standing=STANDING, scopes=None, serial="7"):
    """Point the module at a temp .autoport and restore it afterwards."""
    saved = {k: getattr(directives, k)
             for k in ("AUTOPORT", "DIRECTIVES", "SERIAL_FILE", "ISSUED")}
    with tempfile.TemporaryDirectory() as td:
        ap = Path(td) / ".autoport"
        (ap / "prompts").mkdir(parents=True)
        (ap / "DIRECTIVES.md").write_text(standing, encoding="utf-8")
        (ap / "SCOPE-SERIAL").write_text(serial + "\n", encoding="utf-8")
        for name, body in (scopes or {}).items():
            (ap / "prompts" / name).write_text(body, encoding="utf-8")
        directives.AUTOPORT = ap
        directives.DIRECTIVES = ap / "DIRECTIVES.md"
        directives.SERIAL_FILE = ap / "SCOPE-SERIAL"
        directives.ISSUED = ap / ".directives_issued"
        try:
            yield ap
        finally:
            for k, v in saved.items():
                setattr(directives, k, v)


def test_block_without_scope_is_the_standing_orders_only():
    with fake_tree():
        b = directives.block("item-sans-scope")
        assert "un commentaire n'est pas une preuve" in b
        assert "PÉRIMÈTRE DE CETTE TÂCHE" not in b
        assert len(b.encode()) < directives.MAX_BLOCK_BYTES


def test_block_with_scope_inlines_that_scope():
    with fake_tree(scopes={"SCOPE-flicker.md": "Les PNJ clignotent en cinématique."}):
        b = directives.block("flicker")
        assert "Les PNJ clignotent en cinématique." in b
        assert "SCOPE-flicker.md" in b
        # ... and only its own scope
        assert "SCOPE-autre.md" not in b


def test_a_spec_named_in_the_directives_is_never_inlined():
    """The 2026-09-03 defect: _spec_path() pulled SPEC-keira-physique.md into
    every phase because DIRECTIVES.md happened to backtick its path."""
    named = STANDING + "\nContrat : `.autoport/prompts/SPEC-keira-physique.md`\n"
    spec_body = "SECTION 22 — apex displacement <= 0.50 B0"
    with fake_tree(standing=named) as ap:
        (ap / "prompts" / "SPEC-keira-physique.md").write_text(spec_body, encoding="utf-8")
        b = directives.block("cutscene-npc-flicker")
        assert spec_body not in b
        assert not hasattr(directives, "_spec_path")


def test_version_is_per_item_and_stable():
    with fake_tree(scopes={"SCOPE-a.md": "périmètre A", "SCOPE-b.md": "périmètre B"}):
        va, vb = directives.version("a"), directives.version("b")
        assert va != vb, "deux items ne peuvent pas partager une version"
        assert va == directives.version("a"), "la version doit être stable"
        assert directives.version("a") != directives.version(None)


def test_version_moves_when_the_scope_or_the_serial_moves():
    with fake_tree(scopes={"SCOPE-a.md": "périmètre A"}) as ap:
        before = directives.version("a")
        (ap / "prompts" / "SCOPE-a.md").write_text("périmètre A, corrigé", encoding="utf-8")
        assert directives.version("a") != before
        after_scope = directives.version("a")
        (ap / "SCOPE-SERIAL").write_text("8\n", encoding="utf-8")
        assert directives.serial() == 8
        assert directives.version("a") != after_scope


def test_oversized_scope_raises_instead_of_truncating():
    big = "x" * (directives.MAX_BLOCK_BYTES + 1)
    with fake_tree(scopes={"SCOPE-enorme.md": big}):
        try:
            directives.block("enorme")
        except directives.DirectivesTooLarge as exc:
            msg = str(exc)
            assert "SCOPE-enorme.md" in msg and str(directives.MAX_BLOCK_BYTES) in msg
        else:
            raise AssertionError("un contrat au-dessus du plafond doit lever")


def test_issued_records_one_line_per_version_under_the_serial():
    with fake_tree(scopes={"SCOPE-a.md": "périmètre A"}) as ap:
        directives.block("a")
        directives.block("a")           # même version : pas de doublon
        directives.block(None)
        lines = (ap / ".directives_issued").read_text(encoding="utf-8").splitlines()
        assert len(lines) == len(set(lines)) == 2
        assert all(ln.startswith("7 ") for ln in lines)
        assert directives.version("a") in directives.issued_for_current_serial()
        (ap / "SCOPE-SERIAL").write_text("8\n", encoding="utf-8")
        assert directives.version("a") not in directives.issued_for_current_serial()


def test_the_real_contract_fits_under_the_cap():
    """No fake tree: the contract actually shipped today must fit."""
    for item in ("cutscene-npc-flicker", "font-regression", None):
        size = len(directives.block(item, record=False).encode())
        assert size <= directives.MAX_BLOCK_BYTES, f"{item}: {size} o"


if __name__ == "__main__":
    fails = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print("ok   ", name)
            except Exception as exc:
                fails += 1
                print("ECHEC", name, "->", type(exc).__name__, exc)
    print(("%d échec(s)" % fails) if fails else "tous les tests passent")
    sys.exit(1 if fails else 0)


def test_capture_paragraph_is_rendered_only_for_a_visible_item():
    """INVISIBLE-CAPTURE/ : le paragraphe capture ne va qu'a un chantier que l'owner regardera."""
    inv = {"id": "h", "owner_test": False}
    vis = {"id": "g", "owner_test": True, "where": "Sandover"}
    bi = directives.block("h", record=False, item=inv)
    bv = directives.block("g", record=False, item=vis)
    assert "--no-capture" not in bi and "CLOSE-GATE/capture" not in bi
    assert "--no-capture" in bv and "CLOSE-GATE/capture" in bv
    assert "<!--" not in bi and "<!--" not in bv
    assert directives.version("h", inv) != directives.version("h", vis)


def test_report_verdict_accepte_la_version_courante():
    item = {"id": "x-item", "owner_test": False}
    with fake_tree() as ap:
        rp = ap / "report.txt"
        rp.write_text(f"Verdict.\nDIRECTIVES {directives.version('x-item', item)}\n", encoding="utf-8")
        ok, why = directives.report_verdict("x-item", rp, item=item)
        assert ok, why


def test_report_verdict_refuse_une_version_de_la_serie_precedente():
    item = {"id": "x-item", "owner_test": False}
    with fake_tree() as ap:
        directives.ISSUED.write_text("6 v6666666666 x-item\n", encoding="utf-8")
        rp = ap / "report.txt"
        rp.write_text("DIRECTIVES v6666666666\n", encoding="utf-8")
        ok, why = directives.report_verdict("x-item", rp, item=item)
        assert not ok and "v6666666666" in why


def test_report_verdict_refuse_un_rapport_sans_ligne():
    item = {"id": "x-item", "owner_test": False}
    with fake_tree() as ap:
        rp = ap / "report.txt"
        rp.write_text("Verdict sans contrat.\n", encoding="utf-8")
        ok, why = directives.report_verdict("x-item", rp, item=item)
        assert not ok and "aucune ligne" in why


# harness-directives-gate-reads-any-report-name (25/09) : la porte lit le DOSSIER du rapport.
def test_dir_verdict_lit_report_md_quand_report_txt_manque():
    item = {"id": "x-item", "owner_test": False}
    with fake_tree() as ap:
        d = ap / "reports" / "x-item"
        d.mkdir(parents=True)
        (d / "report.md").write_text(f"DIRECTIVES {directives.version('x-item', item)}\n",
                                     encoding="utf-8")
        ok, why, cause = directives.dir_verdict("x-item", d, item=item)
        assert ok and cause == "" and why.startswith("report.md"), why


def test_dir_verdict_sans_ligne_nulle_part_est_un_refus_de_forme():
    item = {"id": "x-item", "owner_test": False}
    with fake_tree() as ap:
        d = ap / "reports" / "x-item"
        d.mkdir(parents=True)
        (d / "report.md").write_text("rien\n", encoding="utf-8")
        (d / "proof.txt").write_text("k=DIRECTIVES v0123456789\n", encoding="utf-8")
        ok, why, cause = directives.dir_verdict("x-item", d, item=item)
        assert not ok and cause == directives.FORM and "report.txt" in why


def test_dir_verdict_version_perimee_ecrite_pendant_l_essai_reste_un_refus_de_fond():
    item = {"id": "x-item", "owner_test": False}
    with fake_tree() as ap:
        d = ap / "reports" / "x-item"
        d.mkdir(parents=True)
        (d / "report.txt").write_text("DIRECTIVES v6666666666\n", encoding="utf-8")
        (d / "report.md").write_text(f"DIRECTIVES {directives.version('x-item', item)}\n",
                                     encoding="utf-8")
        ok, _why, cause = directives.dir_verdict("x-item", d, item=item)
        assert not ok and cause == directives.STALE


def test_dir_verdict_prefere_le_rapport_de_l_essai_a_un_reste_perime():
    import os
    item = {"id": "x-item", "owner_test": False}
    with fake_tree() as ap:
        d = ap / "reports" / "x-item"
        d.mkdir(parents=True)
        old = d / "report.txt"
        old.write_text("DIRECTIVES v6666666666\n", encoding="utf-8")
        os.utime(old, (1000, 1000))
        (d / "handoff.md").write_text(f"DIRECTIVES {directives.version('x-item', item)}\n",
                                      encoding="utf-8")
        ok, why, _ = directives.dir_verdict("x-item", d, item=item, since=2000)
        assert ok and why.startswith("handoff.md"), why
        (d / "handoff.md").unlink()
        ok, _why, cause = directives.dir_verdict("x-item", d, item=item, since=2000)
        assert not ok and cause == directives.FORM


def test_block_nomme_le_fichier_du_rapport():
    with fake_tree():
        b = directives.block("x-item", record=False, item={"id": "x-item"})
        assert ".autoport/reports/x-item/report.txt" in b


def test_le_motif_de_refus_ne_se_fait_pas_passer_pour_la_ligne():
    item = {"id": "x-item", "owner_test": False}
    with fake_tree() as ap:
        d = ap / "reports" / "x-item"
        d.mkdir(parents=True)
        _ok, why, _ = directives.dir_verdict("x-item", d, item=item)
        (d / "handoff.md").write_text("## Porte\n" + why + "\n", encoding="utf-8")
        ok, _why, cause = directives.dir_verdict("x-item", d, item=item)
        assert not ok and cause == directives.FORM
