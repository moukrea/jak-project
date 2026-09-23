"""LE BANC PART D'UN ENVIRONNEMENT MAITRISE ; IL NE L'HERITE PAS.

POURQUOI (harness-test-bench-does-not-inherit-the-worker-env, 2026-09-14). Signalement du
worker de `hdr-shadow-range` (essai 3, 13/09, FINDINGS.txt). `tests/harness/test_proof.py`
construisait l'environnement du juge par `dict(os.environ, AUTOPORT_PHASE_ID=ITEM)` : le banc
heritait TOUT l'environnement de qui le lance. Depuis une session de worker, `AUTOPORT_ATTEMPT_ID`
est pose ; `validators/generic.sh` exige alors `proof_attempt_id=` dans la preuve, que le fixture
`_proof` n'ecrit pas, et `test_une_preuve_produite_par_la_machine_passe` — LE CONTROLE POSITIF du
banc — rougit. Un test qui change de verdict selon qui le lance ne mesure plus son sujet : il
mesure son lanceur, et le seul test qui dit « la porte sait dire OUI » tombe en silence.

MESURE DU 14/09, LA SUITE ENTIERE, DEUX LANCEMENTS : depuis un shell sans variable `AUTOPORT_*`,
595 tests collectes, 595 verts ; depuis la session de worker, memes 595 tests, UN rouge — le
controle positif, et lui seul.

LE POINT DE PRODUCTION, PAS LE POINT DE CONTROLE (DIRECTIVES/non-destruction). Vingt sites du
banc fabriquent un environnement de sous-processus a partir de `os.environ`. Les corriger un par
un laisse naitre le vingt-et-unieme demain, et il faudrait alors relire vingt fichiers pour
savoir ce que le banc voit. On assainit donc `os.environ` LUI-MEME, UNE fois, dans `conftest.py`,
avant que le moindre module de test soit importe : tout site en aval est propre sans le savoir,
et il n'y a qu'UN endroit a lire. C'est aussi ce qui rend l'ablation honnete — `OFF` ne peut pas
laisser un site non gate derriere lui, puisqu'il n'y a qu'un site.

CE QUI PASSE, ET RIEN D'AUTRE. `TRANSMISES` est la liste blanche, et elle est mesuree, pas
supposee : la suite entiere passe avec `env -i PATH HOME LANG`. `TMPDIR` et `LC_ALL` s'y
ajoutent pour une raison nommee, pas par prudence — voir leurs commentaires.

`EXPLICITES` est la seule porte par laquelle un `AUTOPORT_*` du parent entre : un canal
d'instrument, nomme ici, publie dans la preuve. Tout le reste de l'environnement du parent est
RETIRE, et ce qui a ete retire reste lisible (`retirees`) pour qu'un test sonde puisse compter
ce qui a survecu — un compteur qui ne connait pas son denominateur ne prouve rien.

MARQUEUR: banc-env-maitrise-2026-09-14
"""
import os

# Le marqueur qui ancre le bras d'AVANT. `lib/ablation_anchor.sh` remonte a la revision qui l'a
# introduit : un « avant » lu a `HEAD:` serait faux des le commit de ce chantier.
MARQUEUR = "banc-env-maitrise-2026-09-14"

# LA LISTE BLANCHE. Chaque nom a sa raison ; un nom sans raison est une fuite qu'on a rendue
# legale.
TRANSMISES = (
    "PATH",    # sans lui, ni python3 ni git ni bash ne se resolvent : le banc ne collecte rien
    "HOME",    # `git init` des bacs a sable lit ~/.gitconfig ; pytest y pose ses caches
    "LANG",    # l'encodage des sorties comparees par les tests
    "LC_ALL",  # meme raison, et il PRIME sur LANG : le laisser au parent ferait deux locales
    # POURQUOI TMPDIR EST TRANSMIS, et pas juste tolere : le 14/09 la mesure a d'abord rendu
    # 78 rouges et un junit tronque sur `OSError: [Errno 122] Disk quota exceeded`, /tmp etant
    # a son quota (6311M/6311M). Un lanceur qui redirige TMPDIR ailleurs le fait pour une
    # raison ; le retirer renverrait le banc sur le /tmp sature sans rien dire.
    "TMPDIR",
)

# LE SEUL CHEMIN PAR LEQUEL UN `AUTOPORT_*` DU PARENT ENTRE. Ce sont des canaux d'instrument :
# un fichier ou une jambe du banc ECRIT ce qu'elle a mesure, pour qu'un recensement le relise.
# Ils ne changent le verdict d'aucun test — seulement s'il publie ou non.
EXPLICITES = (
    "AUTOPORT_SANDBOX_MANIFEST",    # lib/verdict_sources_selftest.sh -> test_proof.py
    "AUTOPORT_BENCH_ENV_MANIFEST",  # lib/census/harness-test-bench-... -> test_bench_env.py
    "AUTOPORT_REGISTRY_DIR",        # le registre de commentaires du banc (lib/owner_capture.REGISTRY_ENV)
)

# LE REGISTRE DU BANC EST JETABLE (harness-tests-never-write-real-registries, 23/09). test_loop.py et
# test_attempt.py poussaient leurs commentaires fictifs (`item-d`, `item-b`...) dans le VRAI
# `.autoport/logs/linear_comments.jsonl`, lu par CLOSE-GATE/capture : 102 lignes en un jour. Pose ici, au
# point de production de l'environnement du banc, la variable suit tous les sous-processus.
REGISTRY = "AUTOPORT_REGISTRY_DIR"

# LE BRAS D'ABLATION. `=1` rend au banc l'etat d'AVANT : il herite tout. C'est le seul commutateur,
# et il est lu AVANT l'assainissement — il disparait ensuite avec le reste.
INHERIT = "AUTOPORT_BENCH_ENV_INHERIT"

_ETAT = {
    "installe": 0,
    "mode": "-",
    "parent": 0,
    "gardees": (),
    "retirees": (),
}
# Les VALEURS du parent qui ont ete retirees. Une fuite, c'est un nom du parent dont la VALEUR
# du parent est encore lisible : pytest repose `PYTEST_CURRENT_TEST` a chaque test, et comparer
# les seuls noms accuserait le banc de fuir ce qu'il vient d'ecrire lui-meme.
_RETIREES = {}


def etat():
    """Ce que l'assainissement a fait, recopiable dans une preuve."""
    return dict(_ETAT)


def install(environ=None, force=False):
    """Assainit `os.environ` EN PLACE. Appele par `conftest.py`, avant toute collecte."""
    env = os.environ if environ is None else environ
    if _ETAT["installe"] and not force:
        return etat()
    parent = dict(env)
    if parent.get(INHERIT, "0") == "1":
        # L'ETAT D'AVANT, TEL QUEL : on ne touche a rien. `OFF` doit EGALER l'absence de ce
        # fichier, et il n'y a aucun autre site a desarmer.
        _RETIREES.clear()
        _ETAT.update(installe=1, mode="herite", parent=len(parent),
                     gardees=tuple(sorted(parent)), retirees=())
        return etat()
    garde = {k: parent[k] for k in TRANSMISES + EXPLICITES if k in parent}
    _RETIREES.clear()
    _RETIREES.update({k: v for k, v in parent.items() if k not in garde})
    env.clear()
    env.update(garde)
    if not env.get(REGISTRY):
        import tempfile  # noqa: PLC0415
        env[REGISTRY] = tempfile.mkdtemp(prefix="autoport-bench-registry-")
    _ETAT.update(installe=1, mode="maitrise", parent=len(parent),
                 gardees=tuple(sorted(garde)), retirees=tuple(sorted(_RETIREES)))
    return etat()


def fuites(environ=None):
    """Les variables du PARENT encore lisibles malgre le retrait. Doit etre vide."""
    env = os.environ if environ is None else environ
    return tuple(n for n, v in sorted(_RETIREES.items()) if env.get(n) == v)


def hors_liste():
    """Ce que le banc a garde et que la liste blanche n'annonce pas. Doit etre vide."""
    permis = set(TRANSMISES) | set(EXPLICITES)
    return tuple(n for n in _ETAT["gardees"] if n not in permis)


def autoport_du_parent():
    """Les `AUTOPORT_*` que le parent posait, qu'ils aient survecu ou non."""
    noms = set(_RETIREES) | set(_ETAT["gardees"])
    return tuple(sorted(n for n in noms if n.startswith("AUTOPORT_")))
