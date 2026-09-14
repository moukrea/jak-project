#!/usr/bin/env python3
"""lib/inherited_red_selftest.py — LE BANC DE `harness-close-gate-separates-inherited-reds`.

CE QU'IL FAIT. Il joue le VRAI juge de la suite — `lib/suite_gate.py` — sur des depots git
JETABLES ou l'histoire est SEMEE : un commit de base, puis un commit de l'item. Selon le semis,
le test rouge l'est DEJA au commit de base (herite) ou seulement apres le commit de l'item
(neuf). C'est la seule facon de montrer que la porte distingue : sur l'arbre livre la suite est
verte, il n'y a donc AUCUN rouge a classer, et « les deux bras au vert » ne prouverait rien.

LES QUATRE SEMIS, chacun dans son propre depot :

  vert              rien de rouge                        -> les DEUX bras ferment (le CONTROLE
                                                            A LAISSER : une porte qui refuse un
                                                            vert ne vaut rien)
  herite_signale    rouge a la base ET apres, nomme dans -> APRES ferme, `unwaived_known=1`,
                    le rapport et trie dans FINDINGS        `unwaived_new=0`
  herite_muet       le meme rouge, rapport et FINDINGS   -> APRES REFUSE, mais pour le
                    MUETS                                   SIGNALEMENT, pas pour le rouge :
                                                            l'herite ne meurt pas en silence
  neuf              vert a la base, casse par le commit  -> APRES REFUSE et NOMME le test
                    de l'item

LE BRAS D'AVANT EST ANCRE PAR MARQUEUR, jamais lu a `HEAD:` : des le commit de ce chantier,
`HEAD` porte la reparation et le temoin s'accuserait lui-meme. On remonte l'histoire de
`lib/suite_gate.py` jusqu'au dernier blob qui ne porte PAS le marqueur, et le commit retenu est
PUBLIE. Sur `herite_signale`, ce bras doit REFUSER : c'est le defaut qu'on repare, et sans
cette jambe l'ablation serait vide — « la porte distingue » serait vrai aussi le jour ou plus
aucun rouge ne peut etre herite.

CE QU'IL NE FAIT PAS. Il ne juge rien et n'ecrit aucun champ de `proof.txt` : il rend des
lignes `cle=valeur` sur stdout, et `lib/census/harness-close-gate-separates-inherited-reds.sh`
en fait la somme.

LE COUT. Quatre semis par bras, une suite miniature de trois tests, un arbre de travail jetable
par semis rouge : environ vingt secondes en tout. La duree de la VRAIE suite est mesuree
ailleurs, sur l'arbre livre.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parent.parent
REPO = AP.parent

# Le marqueur qui separe l'avant de l'apres. Il vit dans le docstring ET dans le code de
# `lib/suite_gate.py` : le bras d'avant est le dernier blob qui ne le porte pas.
MARQUEUR = "HERITE OU NEUF : ON LE MESURE A LA BASE DE L'ESSAI"

CLE_NEUVE = "hdr_stretch_top_const"
CLE_VIEILLE = "hdr_stretch_top"

NODE_CASSE = ".autoport/tests/harness/test_petit.py::test_cle_publiee"

TEST_PETIT = '''"""Suite MINIATURE du banc : elle cite une cle publiee, comme les 44 tests du 12/09."""
from pathlib import Path

DONNEE = Path(__file__).resolve().parents[2] / "donnee.txt"


def test_cle_publiee():
    assert "%s=" % "{cle}" in DONNEE.read_text(encoding="utf-8")


def test_donnee_existe():
    assert DONNEE.exists()


def test_toujours_vert():
    assert 1 + 1 == 2
'''.replace("{cle}", CLE_NEUVE)

GIT_ENV = {**os.environ, "GIT_AUTHOR_NAME": "banc", "GIT_AUTHOR_EMAIL": "banc@local",
           "GIT_COMMITTER_NAME": "banc", "GIT_COMMITTER_EMAIL": "banc@local"}


def kv(key, value):
    print("%s=%s" % (key, str(value).replace("\n", " ").replace(" ", "_")[:400] or "-"))


def charger(src: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def before_blob(rel: str, marker: str) -> tuple[str, str]:
    """Le premier commit, en remontant, dont `rel` ne porte PAS `marker`."""
    try:
        hist = subprocess.run(["git", "-C", str(REPO), "log", "--format=%H", "-n", "200",
                               "--", rel], capture_output=True, text=True,
                              timeout=60).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return "", ""
    for commit in hist:
        try:
            blob = subprocess.run(["git", "-C", str(REPO), "show", "%s:%s" % (commit, rel)],
                                  capture_output=True, text=True, timeout=60).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        if blob and marker not in blob:
            return commit, blob
    return "", ""


# ======================================================= les depots jetables, avec une HISTOIRE =
def _git(root: Path, *args: str, quand: int = 0) -> subprocess.CompletedProcess:
    """`quand` DATE le commit. `git` n'ecrit qu'une seconde entiere : sans date explicite, la
    base et le commit de l'essai peuvent porter la MEME seconde, et `ct >= since` devient un
    tirage au sort. On les separe donc a la main plutot qu'en dormant."""
    env = dict(GIT_ENV)
    if quand:
        env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = "@%d +0000" % quand
    return subprocess.run(["git", *args], cwd=root, env=env, capture_output=True,
                          text=True, timeout=120)


def semer(racine: Path, iid: str, *, casse_a_la_base: bool, casse_par_l_item: bool,
          rapport: str, findings: str) -> float:
    """Un depot git jetable avec DEUX commits, et l'instant qui separe l'essai de sa base.

    Commit 1  la base : la suite miniature, le registre vide, le backlog. `donnee.txt` y porte
              la vieille cle si le rouge doit y etre DEJA.
    (pause)   l'instant rendu : tout commit pose apres lui appartient a l'essai.
    Commit 2  `[autoport/<iid>]` : le geste de l'essai. Il casse `donnee.txt` si le rouge doit
              naitre ICI, sinon il ne touche qu'un fichier de notes.

    C'est l'histoire qui fait la difference entre les semis, pas un reglage : le juge remonte
    a la base par `git`, exactement comme sur l'arbre livre.
    """
    ap = racine / ".autoport"
    (ap / "tests" / "harness").mkdir(parents=True, exist_ok=True)
    (ap / "logs").mkdir(parents=True, exist_ok=True)
    (ap / "reports" / iid).mkdir(parents=True, exist_ok=True)
    (ap / "tests" / "harness" / "test_petit.py").write_text(TEST_PETIT, encoding="utf-8")
    (ap / "tests" / "harness" / "ECHECS-ATTENDUS.yaml").write_text("attendus: []\n",
                                                                   encoding="utf-8")
    (ap / "donnee.txt").write_text(
        "%s=1\n" % (CLE_VIEILLE if casse_a_la_base else CLE_NEUVE), encoding="utf-8")
    import yaml
    (ap / "backlog.yaml").write_text(yaml.safe_dump(
        {"version": 1, "items": [{"id": iid, "status": "in-progress", "priority": 1,
                                  "game": "jak1", "device": False, "owner_test": False,
                                  "owner_verify": False, "no_code": True,
                                  "feature": "banc du rouge herite"}]},
        allow_unicode=True, sort_keys=False), encoding="utf-8")
    t0 = int(time.time()) - 600
    _git(racine, "init", "-q", ".")
    _git(racine, "add", "-A")
    _git(racine, "commit", "-q", "-m", "base du banc", quand=t0)

    # L'INSTANT QUI SEPARE : tout commit pose apres lui appartient a l'essai.
    depart = float(t0 + 30)

    if casse_par_l_item:
        (ap / "donnee.txt").write_text("%s=1\n" % CLE_VIEILLE, encoding="utf-8")
    (ap / "notes.txt").write_text("le geste de l'essai\n", encoding="utf-8")
    _git(racine, "add", "-A")
    _git(racine, "commit", "-q", "-m", "[autoport/%s] le geste de l'essai" % iid, quand=t0 + 60)

    # Le rapport et les signalements sont HORS commit : ils vivent comme sur l'arbre livre.
    (ap / "reports" / iid / "report.txt").write_text(rapport, encoding="utf-8")
    (ap / "reports" / iid / "FINDINGS.txt").write_text(findings, encoding="utf-8")
    return depart


SIGNALEMENT = (NODE_CASSE + " | rouge deja present a la base de cet essai, ne vient pas de lui "
               "| l'essai suivant le repaierait -> item:build-and-harness-leftovers\n")

CAS = {
    # nom              casse_a_la_base  casse_par_l_item  rapport                    findings
    "vert":            (False, False, "rien a signaler",                         "AUCUN\n"),
    "herite_signale":  (True,  False, "rouge herite : " + NODE_CASSE,            SIGNALEMENT),
    "herite_muet":     (True,  False, "rien a signaler",                         "AUCUN\n"),
    "neuf":            (False, True,  "rien a signaler",                         "AUCUN\n"),
}

# CE QU'ON ATTEND DE LA PORTE LIVREE, semis par semis. La table est ici, en clair, pour que le
# recensement n'ait pas a la reecrire : deux tables divergeraient en silence.
ATTENDU = {
    # nom              verdict   herites  neufs
    "vert":            ("pass",  0, 0),
    "herite_signale":  ("pass",  1, 0),
    "herite_muet":     ("refuse", 1, 0),
    "neuf":            ("refuse", 0, 1),
}


def axe(prefixe: str, racine: Path, SG, iid: str) -> None:
    """Joue le juge `SG` sur les quatre semis et publie ses grandeurs, semis par semis."""
    vieux = not _accepte_since(SG)
    for nom, (base, item, rapport, findings) in CAS.items():
        d = racine / (prefixe + "-" + nom)
        d.mkdir(parents=True, exist_ok=True)
        depart = semer(d, iid, casse_a_la_base=base, casse_par_l_item=item,
                       rapport=rapport, findings=findings)
        t0 = time.time()
        try:
            if vieux:
                v = SG.judge(d, d / ".autoport", iid, record=False)
            else:
                v = SG.judge(d, d / ".autoport", iid, record=False, since=depart)
        except Exception as exc:                                        # noqa: BLE001
            v = {"verdict": "exception:%s" % type(exc).__name__, "reason": str(exc)}
        raison = str(v.get("reason") or "-")
        kv("%s_%s_verdict" % (prefixe, nom), v.get("verdict", "-"))
        kv("%s_%s_unwaived" % (prefixe, nom), v.get("unwaived", "-"))
        kv("%s_%s_herites" % (prefixe, nom), v.get("unwaived_known", "-"))
        kv("%s_%s_neufs" % (prefixe, nom), v.get("unwaived_new", "-"))
        kv("%s_%s_base" % (prefixe, nom), v.get("red_base_ref", "-"))
        kv("%s_%s_base_kind" % (prefixe, nom), v.get("red_base_kind", "-"))
        kv("%s_%s_replay_ran" % (prefixe, nom), v.get("replay_ran", "-"))
        kv("%s_%s_replay_err" % (prefixe, nom), v.get("replay_error", "-"))
        kv("%s_%s_nomme_le_test" % (prefixe, nom), 1 if NODE_CASSE in raison else 0)
        kv("%s_%s_dit_signalement" % (prefixe, nom), 1 if "signalement" in raison else 0)
        kv("%s_%s_dit_ce_travail" % (prefixe, nom), 1 if "ce travail-ci" in raison else 0)
        kv("%s_%s_filed" % (prefixe, nom), v.get("inherited_filed", "-"))
        kv("%s_%s_unfiled" % (prefixe, nom),
           len(v.get("inherited_unfiled") or []) if "inherited_unfiled" in v else -1)
        kv("%s_%s_secondes" % (prefixe, nom), round(time.time() - t0, 1))
        kv("%s_%s_raison" % (prefixe, nom), raison[:220])
        shutil.rmtree(d, ignore_errors=True)
    kv("%s_ran" % prefixe, 1)


def _accepte_since(SG) -> bool:
    try:
        import inspect
        return "since" in inspect.signature(SG.judge).parameters
    except Exception:                                                   # noqa: BLE001
        return False


def conformite(lignes: dict, bras: str, suffixe: str = "") -> int:
    """Le bras tient-il la table ATTENDU, semis par semis ? Publie le detail ET la somme.

    On compte les ECARTS, pas les succes : une porte qui ne rend rien doit peser, pas
    disparaitre. Un semis dont une grandeur manque compte pour un ecart.

    LE DETECTEUR EST CONTROLE, PAS SUPPOSE. La meme table est passee au bras d'AVANT, qui doit
    rendre des ecarts NON NULS : un comparateur qui rendrait zero des deux cotes ne comparerait
    rien, et `conformite_ecarts=0` se lirait comme une reussite sur un instrument mort.
    """
    ecarts, detail = 0, []
    for nom, (verdict, herites, neufs) in ATTENDU.items():
        for cle, attendu in (("verdict", verdict), ("herites", herites), ("neufs", neufs)):
            obtenu = lignes.get("%s_%s_%s" % (bras, nom, cle), "manquant")
            if str(obtenu) != str(attendu):
                ecarts += 1
                detail.append("%s.%s=%s!=%s" % (nom, cle, obtenu, attendu))
    kv("conformite_ecarts" + suffixe, ecarts)
    kv("conformite_detail" + suffixe, ",".join(detail) or "-")
    return ecarts


def main() -> int:
    iid = "zzz-banc-rouge-herite"
    root = Path(tempfile.mkdtemp(prefix="inherited-red-banc-"))
    lignes: dict = {}

    class Echo:
        """Capture les `cle=valeur` pour la table de conformite, sans cesser de les imprimer."""

        def __init__(self, vrai):
            self.vrai = vrai

        def write(self, s):
            for ligne in s.splitlines():
                if "=" in ligne:
                    k, _, v = ligne.partition("=")
                    lignes[k] = v
            return self.vrai.write(s)

        def flush(self):
            self.vrai.flush()

    try:
        commit, blob = before_blob(".autoport/lib/suite_gate.py", MARQUEUR)
        kv("before_commit", commit[:12] or "-")
        kv("before_marqueur_absent", 1 if (blob and MARQUEUR not in blob) else 0)
        vivant = (AP / "lib" / "suite_gate.py").read_text(encoding="utf-8", errors="replace")
        kv("after_marqueur_present", 1 if MARQUEUR in vivant else 0)
        # LA MESURE DU known_cause, REJOUEE SUR LA SOURCE : le module d'avant ne savait pas
        # rejouer un nodeid a une revision, et il n'avait aucune notion de base d'ESSAI.
        kv("src_replay_avant", blob.count("def replay(") if blob else -1)
        kv("src_replay_apres", vivant.count("def replay("))
        kv("src_red_base_avant", blob.count("def red_base(") if blob else -1)
        kv("src_red_base_apres", vivant.count("def red_base("))
        kv("src_since_avant", blob.count("AUTOPORT_ATTEMPT_ID") if blob else -1)
        kv("src_since_apres", vivant.count("AUTOPORT_ATTEMPT_ID"))
        for rel in ("lib/suite_gate.py", "lib/inherited_red_selftest.py",
                    "lib/inherited_red_cost.py", "orchestrator.py"):
            try:
                h = hashlib.sha256((AP / rel).read_bytes()).hexdigest()[:16]
            except OSError:
                h = "-"
            kv("sha_" + rel.replace("/", "_").replace(".", "_").replace("-", "_"), h)

        sys.path.insert(0, str(AP / "lib"))
        vrai_stdout, sys.stdout = sys.stdout, Echo(sys.stdout)
        try:
            SG_neuf = charger(AP / "lib" / "suite_gate.py", "sg_neuf_irs")
            axe("apres", root, SG_neuf, iid)
            if blob:
                vieux = root / "vieux_suite_gate.py"
                vieux.write_text(blob, encoding="utf-8")
                SG_vieux = charger(vieux, "sg_vieux_irs")
                axe("avant", root, SG_vieux, iid)
        finally:
            sys.stdout = vrai_stdout
        conformite(lignes, "apres")
        conformite(lignes, "avant", "_avant")
        # L'ABLATION N'EST PAS VIDE. Le bras d'avant doit REFUSER le semis `herite_signale` :
        # c'est le defaut qu'on repare. S'il le laissait passer, les deux bras seraient au vert
        # et la comparaison ne mesurerait plus rien.
        kv("ablation_avant_refuse_l_herite",
           1 if lignes.get("avant_herite_signale_verdict") == "refuse" else 0)
        kv("ablation_apres_ferme_l_herite",
           1 if lignes.get("apres_herite_signale_verdict") == "pass" else 0)
        kv("ablation_les_deux_refusent_le_neuf",
           1 if (lignes.get("avant_neuf_verdict") == "refuse"
                 and lignes.get("apres_neuf_verdict") == "refuse") else 0)
        kv("ablation_les_deux_ferment_le_vert",
           1 if (lignes.get("avant_vert_verdict") == "pass"
                 and lignes.get("apres_vert_verdict") == "pass") else 0)
        kv("banc_ran", 1)
        return 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
