"""LE MANIFESTE DU PACK EST UN PRODUIT DU BUILD — la garde de non-regression.

Elle echoue si le symptome revient : un manifeste de pack RE-SUIVI par git, ou une regle
`.gitignore` ecrite en quatre litteraux qui laisserait passer le cinquieme.

CE QUI EST MESURE ICI, ET CE QUI NE L'EST PAS. Ces tests ne touchent JAMAIS le depot livre :
le symptome est FABRIQUE dans des depots jetables semes par `pack_manifest_check.semer()`, et
seule la lecture (`defauts`, `ignore`) porte sur le vrai arbre. La sonde de reecriture — celle
qui rejoue ce que fait `android/build_cgo_pack.sh` et regarde si l'arbre se salit — ne tourne
ici que sur les jetables ; sur le depot livre, c'est le recensement de l'item qui la lance,
avec restitution des octets verifiee.

DEUX BRAS, TOUJOURS. Un test qui n'affirme que « le depot livre est propre » passerait aussi
avec une garde qui ne regarde rien. Le bras d'AVANT (`suivi=True`) reproduit l'etat du 19/09 et
doit ROUGIR ; sans lui, le vert du bras d'APRES ne vaut rien.
"""
import sys
from pathlib import Path

LIB = Path(__file__).resolve().parents[2] / "lib"
if str(LIB) not in sys.path:
    sys.path.insert(0, str(LIB))

import pack_manifest_check as G                                       # noqa: E402

RACINE = Path(__file__).resolve().parents[3]


def test_le_depot_livre_ne_suit_aucun_manifeste_de_pack():
    """`git ls-files` n'en liste plus un seul, et aucun dossier de pack n'est sale."""
    assert G.defauts(RACINE) == []


def test_la_regle_couvre_un_manifeste_qui_n_existe_pas_encore():
    """Le jour ou un jak3 arrive, son manifeste naitra ignore sans que personne y pense."""
    futur = "android/app/src/jak3/assets-slim/bundle/jak3_cgo.manifest.properties"
    assert G.ignore(RACINE, futur), f"{futur} n'est couvert par aucune regle"


def test_les_quatre_manifestes_livres_sont_bien_sur_le_disque():
    """Dé-suivre n'est pas SUPPRIMER : les fichiers que le build a produits restent la, et
    c'est eux que gradle empaquette."""
    trouves = [p for d in G.dossiers_bundle(RACINE)
               for p in sorted((RACINE / d).glob("*.manifest.properties"))]
    assert len(trouves) >= 2, trouves


def test_la_garde_mord_quand_le_manifeste_est_re_suivi(tmp_path):
    """LE BRAS D'AVANT. Sans ce rouge, le vert d'a cote ne prouve rien."""
    d = G.semer(tmp_path / "avant", suivi=True)
    mauvais = G.defauts(d)
    assert any(m.startswith("suivi:") for m in mauvais), mauvais
    assert any(m.startswith("regle-non-generique:") for m in mauvais), mauvais


def test_la_garde_laisse_passer_le_regime_cible(tmp_path):
    d = G.semer(tmp_path / "apres", suivi=False)
    assert G.defauts(d) == []


def test_une_reecriture_par_le_build_ne_salit_plus_l_arbre(tmp_path):
    """LE SYMPTOME LUI-MEME, rejoue sur les deux regimes.

    Ce n'est pas « le manifeste est ignore » qui a coute l'essai 5 de hud-eco-gauge, c'est
    « gradle le reecrit et l'arbre devient sale ». On reecrit donc, et on regarde."""
    avant = G.sonde_reecriture(G.semer(tmp_path / "s-avant", suivi=True))
    apres = G.sonde_reecriture(G.semer(tmp_path / "s-apres", suivi=False))
    assert avant["reecrits"] == 1 and apres["reecrits"] == 1
    assert avant["sale"], "le bras d'AVANT ne salit rien : la sonde est aveugle"
    assert apres["sale"] == [], apres["sale"]
    # NON-DESTRUCTION : la sonde rend les octets qu'elle a empruntes, des deux cotes.
    assert avant["intacts"] == 1 and apres["intacts"] == 1
