#!/usr/bin/env python3
"""Gcutscene-npc-flicker — BRAS 4 DE LA GARDE : un niveau qui DESSINE ne doit pas vieillir.

LE DEFAUT QUE CE BRAS EMPECHE DE REVENIR (mesure du 2026-09-05, Honor de l'owner,
.autoport/reports/cutscene-npc-flicker/owner-honor/npc_flicker-honor-2026-09-05.txt) :

    NPCFLICK scene=mayor-introduction pnj=mayor-lod0 cycles=4 modele_absent=8 trou_max=317
             images=3564 dessine=1624
    NPCCULL  scene=mayor-introduction pnj=mayor-lod0 npc=1 noir_dans_frustum=1823
             images_dans_frustum=3448 images=3564

Le maire est dans le champ 3448 images sur 3564 et n'est dessine que 1624 fois, en 8 episodes
de 3577 a 4127 ms. La chaine, chaque maillon mesure :

  1. `mayor-lod0` n'a QU'UN fournisseur dans tout l'arbre : `out/jak1/fr3/beach.fr3`
     (`goal_src/jak1/dgos/bea.gd:41`). Il n'existe pas de `enhanced/beach.fr3`.
  2. `mayor-introduction` execute `(0 display-level beach special)`
     (`goal_src/jak1/levels/beach/mayor.gc:147`). `drawable-tree.gc:15-22` : le cas `'special`
     est une branche VIDE — aucun paquet de fond n'est emis pour `beach`.
  3. Les seuls sites qui remettent `frames_since_last_used` a zero sont `get_tfrag3_level`,
     appelee par les renderers de FOND, et la liste `m_active_levels` — qui reste vide toute la
     partie pour jak1 (`__pc-set-active-levels` n'existe que dans kernel/jak2, jak3, jakx).
  4. `beach` vieillit donc d'une image par image PENDANT QUE LE MAIRE EST A L'ECRAN, franchit
     les 180 images de `get_most_unloadable_level` et se fait evincer par sa SECONDE boucle,
     celle qui ignore `m_desired_levels`.
  5. L'eviction efface les modeles merc du niveau de `m_all_merc_models` ; `get_merc_model`
     rend `nullopt` ; `Merc2.cpp` sort sans rien dessiner. Le maire disparait le temps du
     rechargement de beach (12,5 Mo compresses, ~3,8 s sur l'appareil), puis revient.

DISCRIMINANT, MESURE SUR LES SEPT ACTEURS DE LA SCENE, SANS EXCEPTION (2026-09-05, essai 14).
Quel fr3 fournit chaque acteur — les fr3 sont zstd apres 8 octets d'en-tete, donc :

    for f in out/jak1/fr3/*.fr3; do tail -c +9 "$f" | zstd -dc | grep -aq -- "$nom" && echo "$f"; done

    mayor-lod0           -> beach                                    modele_absent=8, noir_dans_frustum=1823
    hutlamp-lod0         -> village1                                 modele_absent=0
    mayorgears-geo       -> village1                                 modele_absent=0
    medres-jungle2-lod0  -> village1                                 modele_absent=0
    eichar-lod0          -> GAME                                     modele_absent=0
    crate-iron-lod0      -> GAME                                     modele_absent=0
    sidekick-lod0        -> GAME (+ beach, misty, swamp, ...)        modele_absent=0

Correspondance EXACTE, sept acteurs sur sept : le seul touche est le seul dont l'unique
fournisseur est un niveau A LA FOIS evincable ET jamais dessine en fond. `village1` est affiche,
son age retombe a chaque image par `get_tfrag3_level`. `GAME.fr3` vit dans `m_common_level`, un
membre SEPARE de `m_loaded_tfrag3_levels` que la boucle d'eviction n'itere jamais. `beach` n'est
ni l'un ni l'autre. Ce n'est pas une correlation choisie apres coup : les six temoins sont tous
les autres acteurs que le recensement a suivis dans cette scene.

EMPREINTE TEMPORELLE, sur la meme capture, DEUX FOIS INDEPENDAMMENT :
  * la premiere image noire du maire tombe a `image=184` dans les TROIS occurrences de la scene ;
  * `dessine=1624` pour `modele_absent=8` episodes, donc 9 plages dessinees :
    **1624 / 9 = 180,4 images par plage**.
`kUnloadAgeFrames` vaut 180. Aucune autre constante du moteur ne vaut 180 images. La duree des
plages OU LE MAIRE EST VISIBLE est donc le seuil d'age lui-meme : l'age court PENDANT que le
niveau dessine, ce qui est exactement ce que le correctif supprime. Les plages noires, elles,
valent 202 a 317 images — c'est le rechargement de beach.fr3, une autre grandeur, non bornee
par 180 : les deux ne se confondent pas.

CE BRAS ECHOUE SI l'un des quatre maillons du correctif disparait du code. C'est exactement la
forme de regression qui s'est produite ici : le geste correct etait deja dans l'arbre, EN
COMMENTAIRE, dans `Loader::get_merc_model` —

    // it->second.front().parent_level->frames_since_last_used = 0;

— et quatre correctifs successifs ont cherche la cause dans Merc2, au point de CONSTAT.

Comme les trois autres bras, ce fichier porte son PROPRE controle positif : il s'applique
d'abord a un motif qui reproduit l'etat d'avant le correctif et echoue s'il ne le detecte pas.
"""
import re
import sys

LOADER = "game/graphics/opengl_renderer/loader/Loader.cpp"
COMMON = "game/graphics/opengl_renderer/loader/common.h"


def strip_comments(src):
    """Le geste manquant existait EN COMMENTAIRE. Un controle qui lit les commentaires aurait
    donc ete vert sur le code casse : on les retire avant toute recherche."""
    src = re.sub(r'/\*.*?\*/', ' ', src, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', src)


def body_of(src, signature):
    """Le corps de la fonction dont la ligne de definition contient `signature`, accolades
    equilibrees. Chercher un identifiant « quelque part dans le fichier » ne prouverait pas
    qu'il est dans la fonction qui doit le porter."""
    i = src.find(signature)
    if i < 0:
        return None
    i = src.find('{', i)
    if i < 0:
        return None
    depth, j = 0, i
    while j < len(src):
        if src[j] == '{':
            depth += 1
        elif src[j] == '}':
            depth -= 1
            if depth == 0:
                return src[i:j + 1]
        j += 1
    return None


def audit(loader_src, common_src):
    """[(nom du maillon, tenu, detail)] — accumule, ne sort pas au premier echec."""
    loader = strip_comments(loader_src)
    common = strip_comments(common_src)
    out = []

    out.append((
        "le niveau porte une marque de derniere utilisation merc",
        bool(re.search(r'\blast_merc_use_frame\b', common)),
        "LevelData::last_merc_use_frame absent de common.h"))

    get_merc = body_of(loader, "Loader::get_merc_model")
    out.append((
        "get_merc_model MARQUE le niveau qu'il vient de servir",
        bool(get_merc) and bool(re.search(r'last_merc_use_frame\s*\.\s*store', get_merc)),
        "aucune ecriture de last_merc_use_frame dans le corps de get_merc_model"
        " (c'est exactement l'etat d'avant le correctif : le geste y etait en COMMENTAIRE)"))

    update = body_of(loader, "Loader::update(TexturePool&")
    out.append((
        "la boucle d'age de Loader::update LIT cette marque",
        bool(update) and bool(re.search(r'last_merc_use_frame\s*\.\s*load', update))
        and bool(re.search(r'frames_since_last_used\s*=\s*0', update)),
        "la boucle qui vieillit les niveaux ne consulte pas la marque merc :"
        " un niveau qui dessine un acteur peut redevenir evincable"))

    unload = body_of(loader, "Loader::get_most_unloadable_level")
    out.append((
        "le seuil d'eviction est UNE constante nommee, pas un litteral",
        bool(unload) and 'kUnloadAgeFrames' in unload
        and not re.search(r'frames_since_last_used\s*>\s*\d', unload),
        "get_most_unloadable_level compare a un nombre ecrit en clair :"
        " la garde et le moteur peuvent diverger sans que rien ne le dise"))

    out.append((
        "l'eviction compte ce qu'elle emporte (numerateur ET denominateur)",
        bool(re.search(r's_npcf_evictions\s*\+\+', loader))
        and bool(re.search(r's_npcf_evict_with_live_merc\s*\+\+', loader)),
        "une eviction qui emporte un modele dessine doit etre COMPTEE ;"
        " sans denominateur, un zero ne dit pas si la situation s'est presentee"))

    # ------------------------------------------------------------------ ESSAI 14 : L'OCCASION
    # `s_npcf_evictions` et `s_npcf_evict_with_live_merc` ne sont PAS le denominateur qu'ils
    # pretendaient etre : ils ne comptent que ce qui arrive une fois la branche d'eviction
    # atteinte. Or cette branche demande `m_loaded_tfrag3_levels.size() >= m_max_levels` (3 en
    # jak1) et les courses du harnais n'ont jamais tenu que DEUX niveaux residents. Les deux
    # compteurs valaient donc zero parce que le mecanisme n'avait pas tourne, pas parce qu'il
    # etait repare — et treize verdicts verts sont sortis sur un defaut que l'owner voyait.
    # C'est la meme faute que `[hd-flicker] blackouts=0` (BRAS 2), sous une autre forme : une
    # clause qu'aucun chemin de code ne pouvait violer.
    out.append((
        "la branche d'eviction compte les images ou elle est ATTEINTE",
        bool(update) and bool(re.search(r's_npcf_evict_pressure_frames\s*\+\+', update)),
        "rien ne compte les images ou `size() >= m_max_levels` : un zero sur les evictions"
        " redevient muet, on ne peut plus distinguer « repare » de « jamais exerce »"))

    out.append((
        "l'occasion est PUBLIEE a cote du verdict",
        all(f'publish("{k}"' in loader for k in
            ("npc_evict_pressure_frames", "npc_loaded_levels_max", "npc_level_age_max")),
        "npc_evict_pressure_frames / npc_loaded_levels_max / npc_level_age_max doivent sortir"
        " dans proof.txt : sans eux le lecteur du rapport ne peut pas voir que la course"
        " n'a rien exerce"))

    out.append((
        "l'echec de get_merc_model separe CLE ABSENTE et VECTEUR VIDE",
        bool(get_merc) and bool(re.search(r's_npcf_merc_key_missing\s*\+\+', get_merc))
        and bool(re.search(r's_npcf_merc_vec_empty\s*\+\+', get_merc)),
        "les deux echecs n'ont pas la meme cause : la cle absente = modele jamais charge,"
        " le vecteur vide = niveau EVINCE (l'eviction fait `mercs.erase` et laisse la cle)."
        " Les confondre a envoye les essais precedents chercher dans le chargement"))

    return out


# Controle positif : l'arbre TEL QU'IL ETAIT avant le correctif. Le geste est present, mais en
# commentaire — la forme exacte qui a survecu a quatre correctifs.
FIXTURE_LOADER = """
std::optional<MercRef> Loader::get_merc_model(const char* model_name) {
  const auto& it = m_all_merc_models.find(model_name);
  if (it != m_all_merc_models.end() && !it->second.empty()) {
    // it->second.front().parent_level->frames_since_last_used = 0;
    return it->second.front();
  } else {
    return std::nullopt;
  }
}
void Loader::update(TexturePool& texture_pool) {
  for (auto& [name, lev] : m_loaded_tfrag3_levels) {
    if (std::find(m_active_levels.begin(), m_active_levels.end(), name) ==
        m_active_levels.end()) {
      lev->frames_since_last_used++;
    } else {
      lev->frames_since_last_used = 0;
    }
  }
}
const std::string* Loader::get_most_unloadable_level() {
  for (auto& [name, lev] : m_loaded_tfrag3_levels) {
    if (lev->frames_since_last_used > 180) { return &name; }
  }
  return nullptr;
}
"""
FIXTURE_COMMON = "struct LevelData { int frames_since_last_used = 0; };"


def main():
    fx = audit(FIXTURE_LOADER, FIXTURE_COMMON)
    held = [n for n, ok, _ in fx if ok]
    if held:
        print("  [GARDE FAIL] controle positif : l'etat d'AVANT le correctif est juge tenu sur "
              + repr(held), file=sys.stderr)
        return 1
    print(f"  [ok]   controle positif : les {len(fx)} maillons tombent sur le code d'avant")

    try:
        loader_src = open(LOADER, encoding='utf-8').read()
        common_src = open(COMMON, encoding='utf-8').read()
    except OSError as e:
        print(f"  [GARDE FAIL] source illisible : {e}", file=sys.stderr)
        return 1

    bad = 0
    for name, ok, detail in audit(loader_src, common_src):
        if ok:
            print(f"  [ok]   {name}")
        else:
            bad += 1
            print(f"  [GARDE FAIL] {name}\n               {detail}", file=sys.stderr)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
