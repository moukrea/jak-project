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
