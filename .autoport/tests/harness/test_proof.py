"""Le validateur générique ne doit JAMAIS pouvoir être satisfait par du texte.

C'est LA propriété qu'on achète avec toute la remise d'équerre du 2026-09-03. Avant elle,
les 19 derniers validateurs lisaient `reports/<phase>/report.txt`, écrit par le worker
lui-même : 116 vérifications sur 116 portaient sur ce texte, zéro sur un binaire ou sur
l'appareil. Le chemin le plus court vers le vert était donc d'écrire la ligne manquante, et
le hook Stop — qui refusait de laisser le worker s'arrêter tant que la porte était rouge —
entraînait précisément ce réflexe.

Chaque test ci-dessous fabrique un `proof.txt` PARFAIT dans son texte et vérifie que la
porte le refuse quand même, parce qu'elle mesure le disque et non le récit.
"""
import hashlib
import os
import subprocess
import textwrap

import pytest

from conftest import AUTOPORT

VALIDATOR = AUTOPORT / "validators" / "generic.sh"
ITEM = "test-item-preuve"


def _repo(tmp_path):
    """Un dépôt jetable qui ressemble à jak-project sur les seuls points que la porte lit."""
    root = tmp_path / "repo"
    (root / ".autoport" / "validators").mkdir(parents=True)
    (root / ".autoport" / "lib").mkdir(parents=True)
    (root / ".autoport" / "reports" / ITEM).mkdir(parents=True)
    (root / "build" / "game").mkdir(parents=True)
    for d in ("game", "common", "android", "goal_src"):
        (root / d).mkdir(parents=True)
    (VALIDATOR.parent / "generic.sh").exists() or pytest.skip("generic.sh absent")
    (root / ".autoport" / "validators" / "generic.sh").write_bytes(VALIDATOR.read_bytes())
    subprocess.run(["git", "init", "-q"], cwd=root, check=True)

    # Le binaire jugé. Son empreinte réelle est la seule chose que le worker ne peut pas taper.
    gk = root / "build" / "game" / "gk"
    gk.write_bytes(b"binaire x86 de test, contenu arbitraire mais REEL\n")
    sha = hashlib.sha256(gk.read_bytes()).hexdigest()[:16]

    (root / ".autoport" / "backlog.yaml").write_text(textwrap.dedent(f"""\
        version: 1
        items:
          - id: {ITEM}
            feature: "Un défaut de test"
            status: open
            device: false
            gate: {{key: episodes, op: "==", value: 0}}
        """), encoding="utf-8")
    return root, gk, sha


def _proof(root, **over):
    champs = {
        "source": "x86",
        "binary": "build/game/gk",
        "sha": over.pop("sha_reel"),
        "started_at": "2026-09-03T09:00:00Z",
        "duration_s": "62",
        "crash": "0",
        "frames": "1800",
    }
    champs.update({k: str(v) for k, v in over.items() if k not in ("feature", "gate")})
    lignes = [f"{k}={v}" for k, v in champs.items()]
    lignes.append(over.get("feature", f"FEATURE {ITEM} armed=1 hits=37"))
    lignes.append(over.get("gate", "episodes=0"))
    p = root / ".autoport" / "reports" / ITEM / "proof.txt"
    p.write_text("\n".join(lignes) + "\n", encoding="utf-8")
    return p


def _juge(root):
    env = dict(os.environ, AUTOPORT_PHASE_ID=ITEM)
    r = subprocess.run(["bash", ".autoport/validators/generic.sh"], cwd=root, env=env,
                       capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr)


def test_une_preuve_produite_par_la_machine_passe(tmp_path):
    """Le contrôle positif : sans lui, un test qui échoue toujours ne prouve rien."""
    root, gk, sha = _repo(tmp_path)
    _proof(root, sha_reel=sha)
    code, out = _juge(root)
    assert code == 0, out


def test_une_preuve_ecrite_a_la_main_ne_passe_pas(tmp_path):
    """LE test. Tout est vert dans le texte ; l'empreinte du binaire ne l'est pas."""
    root, gk, sha = _repo(tmp_path)
    _proof(root, sha_reel="deadbeefdeadbeef")
    code, out = _juge(root)
    assert code == 1
    assert "sha=deadbeefdeadbeef" in out


def test_une_preuve_absente_ne_passe_pas(tmp_path):
    root, gk, sha = _repo(tmp_path)
    code, out = _juge(root)
    assert code == 1
    assert "proof.txt absent" in out
    assert "proof_run.sh" in out, "le message doit dire COMMENT produire la preuve"


def test_une_source_moteur_editee_apres_la_preuve_ne_passe_pas(tmp_path):
    """La preuve décrit un binaire ; si le code a bougé depuis, elle décrit le passé."""
    root, gk, sha = _repo(tmp_path)
    p = _proof(root, sha_reel=sha)
    tard = p.stat().st_mtime + 10
    src = root / "game" / "corrige-apres-coup.cpp"
    src.write_text("// edite APRES la mesure\n", encoding="utf-8")
    os.utime(src, (tard, tard))
    code, out = _juge(root)
    assert code == 1
    assert "APRES la preuve" in out


def test_une_feature_qui_na_pas_tire_ne_passe_pas(tmp_path):
    """`hits=0` : le code est là, il n'a jamais été atteint. C'est l'angle mort historique."""
    root, gk, sha = _repo(tmp_path)
    _proof(root, sha_reel=sha, feature=f"FEATURE {ITEM} armed=1 hits=0")
    code, out = _juge(root)
    assert code == 1
    assert "hits" in out


def test_un_critere_viole_ne_passe_pas(tmp_path):
    root, gk, sha = _repo(tmp_path)
    _proof(root, sha_reel=sha, gate="episodes=479")
    code, out = _juge(root)
    assert code == 1
    assert "episodes=479" in out


def test_un_critere_absent_du_proof_ne_passe_pas(tmp_path):
    """Ne pas mesurer n'est pas réussir : la grandeur manquante est un échec, pas un silence."""
    root, gk, sha = _repo(tmp_path)
    _proof(root, sha_reel=sha, gate="autre_chose=0")
    code, out = _juge(root)
    assert code == 1
    assert "episodes" in out


def test_un_plantage_ne_passe_pas(tmp_path):
    root, gk, sha = _repo(tmp_path)
    _proof(root, sha_reel=sha, crash=1)
    code, out = _juge(root)
    assert code == 1
    assert "crash=1" in out


def test_trop_peu_d_images_ne_passe_pas(tmp_path):
    """Un jeu qui n'a rien dessiné n'a rien prouvé, même sans planter."""
    root, gk, sha = _repo(tmp_path)
    _proof(root, sha_reel=sha, frames=3)
    code, out = _juge(root)
    assert code == 1
    assert "frames" in out


def test_l_ablation_qui_tire_encore_ne_passe_pas(tmp_path):
    """Feature désarmée mais compteur non nul : la porte mesure autre chose que la feature."""
    root, gk, sha = _repo(tmp_path)
    _proof(root, sha_reel=sha)
    (root / ".autoport" / "reports" / ITEM / "proof-off.txt").write_text(
        f"source=x86\nFEATURE {ITEM} armed=0 hits=12\n", encoding="utf-8")
    code, out = _juge(root)
    assert code == 1
    assert "ablation" in out


def test_les_constats_s_accumulent_sans_se_masquer(tmp_path):
    """Une porte qui sort à la première erreur cache les suivantes — ça a caché des
    régressions pendant des jours. Trois défauts doivent produire trois lignes."""
    root, gk, sha = _repo(tmp_path)
    _proof(root, sha_reel="0000000000000000", crash=1, gate="episodes=9")
    code, out = _juge(root)
    assert code == 1
    for attendu in ("sha=", "crash=1", "episodes=9"):
        assert attendu in out, f"constat masqué : {attendu}\n{out}"


def test_le_validateur_ne_lit_jamais_le_rapport_du_worker(tmp_path):
    """Un report.txt parfait ne rachète pas une preuve absente."""
    root, gk, sha = _repo(tmp_path)
    (root / ".autoport" / "reports" / ITEM / "report.txt").write_text(
        f"RESULT: OK\nFEATURE {ITEM} armed=1 hits=999\nepisodes=0\nplateforme=redmi\n",
        encoding="utf-8")
    code, out = _juge(root)
    assert code == 1, "le rapport du worker ne doit jamais suffire"
