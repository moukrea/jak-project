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
import sys
sys.path.insert(0, str(AUTOPORT / "lib"))
# L'AUTORITE DE NOMMAGE des fichiers d'une course. Une preuve semee sous un nom reecrit ici
# serait invisible au juge : il refuserait pour « preuve absente » et le test passerait au vert
# sans avoir jamais exerce le critere qu'il croit mesurer.
import impossible as NOMS  # noqa: E402

VALIDATOR = AUTOPORT / "validators" / "generic.sh"
NAMER = AUTOPORT / "lib" / "verdict_sources.sh"
ROOT = AUTOPORT.parent
ITEM = "test-item-preuve"
# Les familles de fichiers que le nommeur du verdict peut nommer : c'est sur elles, et sur elles
# seules, que l'ecart entre « ce que le bac a sable contient » et « ce que la porte epingle » a
# un sens. Le reste du bac a sable (backlog.yaml, reports/, build/) n'est pas une source.
# Les gardes locales peuvent aussi dependre de fichiers sous .autoport/tests/.
FAMILLES = (".autoport/lib/", ".autoport/validators/", ".autoport/acquis/", ".autoport/tests/")


def sources_du_verdict():
    """LA LISTE DE LA PORTE REELLE, pas celle du bac a sable.

    harness-verdict-sources-are-incomplete, 2026-09-12. Ce fichier copiait DEUX fichiers, cites
    a la main. Le jour ou la porte a gagne un appel a `lib/verdict_sources.sh`, les douze jambes
    ci-dessous ont rougi pour la meme raison — nommeur absent — et le controle positif est tombe :
    une suite ou tout est rouge ne distingue plus un defaut d'un decor incomplet. Un bac a sable
    monte a la main diverge du depot a chaque dependance que la porte gagne. Celui-ci ne le peut
    plus : sa liste EST celle du nommeur.
    """
    r = subprocess.run(["bash", ".autoport/lib/verdict_sources.sh", ITEM, "list"],
                       cwd=ROOT, capture_output=True, text=True)
    return [l for l in r.stdout.splitlines() if l.strip()]


def _repo(tmp_path):
    """Un dépôt jetable qui ressemble à jak-project sur les seuls points que la porte lit."""
    root = tmp_path / "repo"
    (root / ".autoport" / "validators").mkdir(parents=True)
    (root / ".autoport" / "lib").mkdir(parents=True)
    (root / ".autoport" / "reports" / ITEM).mkdir(parents=True)
    (root / "build" / "game").mkdir(parents=True)
    for d in ("game", "common", "android", "goal_src"):
        (root / d).mkdir(parents=True)
    VALIDATOR.exists() or pytest.skip("generic.sh absent")
    liste = sources_du_verdict()
    liste or pytest.skip("le nommeur des sources du verdict ne rend rien")
    for rel in liste:
        dst = root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes((ROOT / rel).read_bytes())
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
        # LE TEMOIN D'ARMEMENT EST ATTRIBUE DEPUIS LE 12/09 (proof-feature-hits-is-vacuous) : le
        # `hits=` de la ligne FEATURE est le compteur GLOBAL du binaire, et la porte lit le compte
        # PROPRE a l'item. Une preuve produite par la machine porte donc ces cles ; un fixture qui
        # ne les porte pas decrit un producteur perime, pas une course saine.
        "proof_feature_id": ITEM,
        "proof_feature_state": "hit",
        "proof_feature_declared": "1",
        "proof_feature_own_hits": "37",
        "proof_feature_global_hits": "4419755",
        "proof_census_present": "0",
        "proof_census_rc": "-1",
        "proof_census_keys": "0",
    }
    champs.update({k: str(v) for k, v in over.items()
                   if k not in ("feature", "gate", "sans_epingle")})
    lignes = [f"{k}={v}" for k, v in champs.items()]
    # L'EMPREINTE DES SOURCES DU VERDICT SORT DU NOMMEUR, elle n'est pas tapée ici : une valeur
    # écrite à la main ne prouverait que la frappe, et c'est exactement ce que `lib/proof_run.sh`
    # fait au moment de produire la preuve. `sans_epingle=True` reproduit une preuve venue d'un
    # producteur qui n'épinglait pas — le cas que la porte doit refuser.
    if not over.get("sans_epingle"):
        kv = subprocess.run(["bash", ".autoport/lib/verdict_sources.sh", ITEM, "kv"],
                            cwd=root, capture_output=True, text=True)
        lignes += [l for l in kv.stdout.splitlines() if l]
    lignes.append(over.get("feature", f"FEATURE {ITEM} armed=1 hits=37"))
    lignes.append(over.get("gate", "episodes=0"))
    p = root / ".autoport" / "reports" / ITEM / NOMS.arm_name("proof", "")
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


def test_une_preuve_qui_n_epingle_pas_les_sources_du_verdict_ne_passe_pas(tmp_path):
    """Le verdict d'un item de harnais vit dans des SCRIPTS, éditables après la course.
    Une preuve qui ne porte pas l'empreinte de ses propres juges est refusée."""
    root, gk, sha = _repo(tmp_path)
    _proof(root, sha_reel=sha, sans_epingle=True)
    code, out = _juge(root)
    assert code == 1
    assert "verdict_sources_sha" in out


def test_une_source_du_verdict_editee_apres_la_preuve_ne_passe_pas(tmp_path):
    """Le pendant, côté `.autoport/` : la porte relit le disque, pas la ligne recopiée."""
    root, gk, sha = _repo(tmp_path)
    _proof(root, sha_reel=sha)
    juge = root / ".autoport" / "validators" / "generic.sh"
    juge.write_bytes(juge.read_bytes() + b"\n# edite APRES la course\n")
    code, out = _juge(root)
    assert code == 1
    assert "a change depuis la course" in out


def test_une_preuve_absente_ne_passe_pas(tmp_path):
    root, gk, sha = _repo(tmp_path)
    code, out = _juge(root)
    assert code == 1
    # NOM-LITTERAL-ATTENDU: message-du-juge-pas-un-chemin
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
    """`hits=0` : le code est là, il n'a jamais été atteint. C'est l'angle mort historique.

    Depuis le 12/09 la situation se dit dans l'état : un site DÉCLARÉ dans le binaire dont le
    compte propre reste à zéro. Le `hits=` global, lui, monte pour tout le monde — c'est
    précisément pour ça qu'il ne pouvait plus servir de témoin.
    """
    root, gk, sha = _repo(tmp_path)
    _proof(root, sha_reel=sha, feature=f"FEATURE {ITEM} armed=1 hits=0",
           proof_feature_state="declared_unreached", proof_feature_own_hits="0")
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
    (root / ".autoport" / "reports" / ITEM / NOMS.arm_name("proof", "-off")).write_text(
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


def test_le_bac_a_sable_contient_exactement_ce_que_la_porte_epingle(tmp_path):
    """Un bac a sable incomplet fabrique un rouge qui ne decrit AUCUN defaut.

    Mesure du 12/09 : `1 failed, 556 passed`, ECHECS-ATTENDUS.yaml vide, douze jambes tombees
    ensemble parce que la porte venait de gagner une dependance que ce fichier ne copiait pas.
    L'ecart entre les deux listes est donc une grandeur, pas une intention : il se mesure, et il
    vaut zero. `AUTOPORT_SANDBOX_MANIFEST` le rend lisible depuis
    `lib/census/harness-verdict-sources-are-incomplete.sh`.
    """
    root, gk, sha = _repo(tmp_path)
    attendu = set(sources_du_verdict())
    trouve = set()
    for chemin in (root / ".autoport").rglob("*"):
        if not chemin.is_file():
            continue
        rel = chemin.relative_to(root).as_posix()
        if rel.startswith(FAMILLES):
            trouve.add(rel)
    manque = sorted(attendu - trouve)
    en_trop = sorted(trouve - attendu)
    cible = os.environ.get("AUTOPORT_SANDBOX_MANIFEST")
    if cible:
        with open(cible, "w", encoding="utf-8") as f:
            f.write("sandbox=test_proof.py\n")
            f.write("attendu=%d\ntrouve=%d\n" % (len(attendu), len(trouve)))
            f.write("manque=%d\nen_trop=%d\n" % (len(manque), len(en_trop)))
            f.write("manque_liste=%s\n" % (",".join(manque) or "-"))
            f.write("en_trop_liste=%s\n" % (",".join(en_trop) or "-"))
    assert attendu, "la porte n'epingle rien : l'ecart serait vide de sens"
    assert not manque, "le bac a sable ne copie pas %s" % manque
    assert not en_trop, "le bac a sable porte des fichiers que la porte n'epingle pas : %s" % en_trop
