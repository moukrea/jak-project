#!/usr/bin/env python3
"""Banc de harness-dead-dependency-is-named-never-silent — la VRAIE classe `Backlog` sur des
backlogs JETABLES (`lib/census/fake_backlog.Sandbox`), jamais sur le vrai.

Chaque scenario publie `cle=valeur`. Le recensement (`lib/census/<id>.sh`) les juge.

  positif   : un item fabrique depend d'un ARCHIVE -> compte, lint NOMME l'item et la dependance,
              `status` le dit, la descendance est comptee gelee.
  absent    : dependance vers un id inexistant -> comptee, nommee.
  bloque    : dependance vers un `blocked` -> nommee par le lint (pas comptee morte).
  supplante : archiver avec `superseded_by` redirige les dependants DANS la meme ecriture,
              chaine de successeurs suivie ; par `set_status` ET par `update`.
  negatif   : dependance vers un `validated`, et un `validated` qui dependait d'un archive
              -> rien de compte, lint muet sur les dependances, `status` muet.
  avant     : le MEME scenario positif rejoue sur le `lib/backlog.py` d'AVANT le correctif
              (ancre par marqueur, pas `HEAD:`) : il doit etre MUET — sinon le banc est aveugle.
"""
import os
import subprocess
import sys
import types

AP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, AP)
from lib import backlog as B  # noqa: E402
from lib.census.fake_backlog import Sandbox  # noqa: E402

MARQUEUR = "DEPENDANCES-MORTES/"


def pub(k, v):
    print("%s=%s" % (k, v))


def it(iid, status="open", **kw):
    d = {"id": iid, "feature": "chantier %s" % iid, "status": status, "priority": 50,
         "code_scope": "jeu"}
    if status == "validated":
        d["owner_ok"] = {"date": "2026-09-24", "text": "ok"}
    d.update(kw)
    return d


def dep_lint(problems):
    return [p for p in problems if "DEPENDANCE MORTE" in p or "BLOQUE" in p
            or "n'existe pas" in p]


def positif():
    items = [it("vieux", "archived"), it("enfant", depends_on=["vieux"]),
             it("petit", depends_on=["enfant"]), it("socle", "validated"),
             it("libre", depends_on=["socle"])]
    with Sandbox(items) as sb:
        b = sb.load()
        h = b.dependency_health()
        lint = dep_lint(b.lint())
        st = b.status_report()
        pub("positif_dead", len(h["dead"]))
        pub("positif_lint_named", int(any("enfant" in p and "vieux" in p and "ARCHIVE" in p
                                          for p in lint)))
        pub("positif_status_named", int("## En attente d'un chantier abandonne" in st
                                        and "enfant attend vieux" in st))
        pub("positif_descendance", int("petit" in h["game_stuck"]))
        pub("positif_game_takeable", h["game_takeable"])
        pub("positif_game_open", h["game_open"])
        pub("positif_next_open", (b.next_open() or {}).get("id", "-"))
        sig_mort = b.signature_digest()
    # La meme file, dependance reparee : la signature du digest doit CHANGER (le superviseur
    # est reveille par une file gelee).
    items[1] = it("enfant", depends_on=["socle"])
    with Sandbox(items) as sb:
        pub("positif_digest_wakes", int(sb.load().signature_digest() != sig_mort))


def absent():
    with Sandbox([it("enfant", depends_on=["fantome"])]) as sb:
        b = sb.load()
        h = b.dependency_health()
        pub("absent_dead", len([d for d in h["dead"] if d[2] == "absent"]))
        pub("absent_lint_named", int(any("enfant" in p and "fantome" in p for p in b.lint())))


def bloque():
    with Sandbox([it("mur", "blocked", block_reason="parque"),
                  it("enfant", depends_on=["mur"])]) as sb:
        b = sb.load()
        h = b.dependency_health()
        pub("bloque_dead", len(h["dead"]))
        pub("bloque_lint_named", int(any("enfant" in p and "mur" in p and "BLOQUE" in p
                                         for p in b.lint())))
        pub("bloque_stuck", int("enfant" in h["game_stuck"]))


def supplante():
    items = [it("ancien"), it("relais", "archived", superseded_by=["neuf"]), it("neuf"),
             it("enfant", depends_on=["ancien", "autre"]), it("autre", "validated"),
             it("fini", "validated", depends_on=["ancien"])]
    with Sandbox(items) as sb:
        b = sb.load()
        b.set_status("ancien", "archived", superseded_by=["relais"])
        e = sb.item("enfant")
        pub("supplante_set_status_deps", ",".join(e.get("depends_on") or []) or "-")
        pub("supplante_set_status_trace", int(bool(e.get("dependency_redirects"))))
        pub("supplante_valide_intact", ",".join(sb.item("fini").get("depends_on") or []))
        pub("supplante_dead_after", len(sb.load().dependency_health()["dead"]))
    with Sandbox([it("ancien"), it("neuf"), it("enfant", depends_on=["ancien"])]) as sb:
        def archive(t, _items):
            t["status"] = "archived"
            t["superseded_by"] = ["neuf"]
            return True
        sb.load().update("ancien", archive)
        pub("supplante_update_deps", ",".join(sb.item("enfant").get("depends_on") or []) or "-")
    # Archive SANS successeur : pas de redirection, le lint l'exige.
    with Sandbox([it("ancien"), it("enfant", depends_on=["ancien"])]) as sb:
        b = sb.load()
        b.set_status("ancien", "archived")
        b = sb.load()
        pub("sans_successeur_deps", ",".join(sb.item("enfant").get("depends_on") or []))
        pub("sans_successeur_lint_named", int(any("enfant" in p and "sans successeur" in p
                                                  for p in b.lint())))


def negatif():
    items = [it("socle", "validated"), it("enfant", depends_on=["socle"]),
             it("vieux", "archived"), it("fini", "validated", depends_on=["vieux"])]
    with Sandbox(items) as sb:
        b = sb.load()
        h = b.dependency_health()
        st = b.status_report()
        pub("negatif_dead", len(h["dead"]))
        pub("negatif_lint_dep", len(dep_lint(b.lint())))
        pub("negatif_status_block", int("chantier abandonne" in st))
        pub("negatif_game_takeable", h["game_takeable"])


def avant():
    """Le code d'AVANT : le dernier commit de lib/backlog.py qui ne porte PAS le marqueur."""
    root = subprocess.run(["git", "-C", AP, "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True).stdout.strip()
    intro = subprocess.run(["git", "-C", root, "log", "--format=%H", "-S", MARQUEUR, "--",
                            ".autoport/lib/backlog.py"], capture_output=True, text=True).stdout.split()
    base = (intro[-1] + "^") if intro else "HEAD"
    src = subprocess.run(["git", "-C", root, "show", "%s:.autoport/lib/backlog.py" % base],
                         capture_output=True, text=True).stdout
    if not src or MARQUEUR in src:
        pub("avant_commit", "-")
        return
    pub("avant_commit", subprocess.run(["git", "-C", root, "rev-parse", "--short", base],
                                       capture_output=True, text=True).stdout.strip())
    # Le module d'avant cherche ses voisins par `__file__` : il s'execute sous le chemin de
    # `lib/backlog.py`, depuis la SOURCE du commit d'avant (rien n'est ecrit dans lib/).
    old = types.ModuleType("backlog_avant")
    old.__file__ = os.path.join(AP, "lib", "backlog.py")
    old.__package__ = "lib"
    sys.modules["backlog_avant"] = old
    exec(compile(src, old.__file__ + "@avant", "exec"), old.__dict__)
    if True:
        items = [it("vieux", "archived"), it("enfant", depends_on=["vieux"])]
        with Sandbox(items) as sb:
            b = old.load(sb.path)
            pub("avant_lint_named", int(any("enfant" in p and "vieux" in p for p in b.lint())))
            pub("avant_status_named", int("vieux" in b.status_report()))
            pub("avant_next_open", (b.next_open() or {}).get("id", "-"))


def reel():
    b = B.load()
    h = b.dependency_health()
    pub("reel_dead", len(h["dead"]))
    pub("reel_dead_list", ",".join("%s>%s:%s" % d[:3] for d in h["dead"]) or "-")
    pub("reel_blocked_deps", len(h["blocked"]))
    pub("reel_game_stuck", len(h["game_stuck"]))
    pub("reel_game_takeable", h["game_takeable"])
    pub("reel_game_open", h["game_open"])
    pub("reel_lint_dep", len([p for p in dep_lint(b.lint()) if "n'existe pas" not in p]))
    pub("reel_lint_absent", len([p for p in b.lint() if "n'existe pas" in p]))


for f in (positif, absent, bloque, supplante, negatif, avant, reel):
    try:
        f()
        pub("%s_ran" % f.__name__, 1)
    except Exception as exc:  # noqa: BLE001 — un bras qui leve est un bras ABSENT, publie
        pub("%s_ran" % f.__name__, 0)
        pub("%s_error" % f.__name__, repr(exc)[:120].replace(" ", "_"))
