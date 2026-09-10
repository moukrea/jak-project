#pragma once

// recharged_gating — LA HIERARCHIE DES OPTIONS RECHARGED, ET LE SEUL ENDROIT QUI L'APPLIQUE.
//
// LE DEFAUT DE L'OWNER (2026-09-10)
// ---------------------------------
// « passer a off une option dans les reglages recharges qui desactive d'autres options qui en
//   dependent... Ne desactive pas les options qui en dependent reellement, elles restent actives
//   dans l'etat ou elles etaient quand elles ont ete grisees. On devrait avoir tout un sous menu
//   "Recharged Lighting" avec un toggle global (qui passe vraiment tous les elements a OFF
//   derriere le rideau, et grise les options liees avec en valeur la valeur qu'elles avaient au
//   moment du switch off de la feature complete, mais vraiment desactive) »
//
// POURQUOI LE DEFAUT EXISTAIT, MESURE ET PAS SUPPOSE
// -------------------------------------------------
// La dependance etait ECRITE DEUX FOIS, dans deux langages, sans que rien ne les compare :
//
//   * cote GOAL, le grisage : `option-disabled-func`, une lambda par rangee de menu
//     (progress-pc.gc). Elle ne fait QUE deux choses — la couleur `menu-invalid` et une sortie
//     anticipee du bouton de confirmation. Elle ne touche AUCUNE valeur, et `update-to-os`
//     (hud-classes-pc.gc:1777) repousse la valeur brute vers le C++ A CHAQUE IMAGE, grisee ou non.
//   * cote C++, la porte : `Gfx::recharged_active()` / `lighting_active()` / `water_active()`,
//     recopiee a la main dans ~92 sites. Le recensement du 2026-09-10 en a trouve 6 qui composent
//     un drapeau d'ECLAIRAGE a travers le MAUVAIS maitre (`recharged_active` au lieu de
//     `lighting_active`, donc en ignorant « Recharged Lighting ») : Loader.cpp:759, :760, :776,
//     :777, :823, refset.cpp:2333, CustomTextureReplacements.cpp:1055 ; plus un site sans aucune
//     porte qui televerse des textures au chargement (PbrTestPattern.cpp:277) ; plus, cote GOAL,
//     jak-hd.gc:3396 qui lit `recharged-enhanced-models?` sans consulter le master.
//
// Deux ecritures d'une meme regle divergent ; ici elles avaient diverge. Une porte oubliee ne
// produit aucune erreur : elle produit une option grisee qui continue de couter.
//
// CE QUE CE MODULE CHANGE, ET POURQUOI C'EST AU POINT DE PRODUCTION
// ----------------------------------------------------------------
// On ne rattrape pas la porte manquante au point de CONTROLE (« ajouter le composeur oublie a ces
// 8 sites »), parce que le 9e site s'ecrira demain et personne ne le verra. On la rend IMPOSSIBLE
// au point de PRODUCTION :
//
//     ce que le moteur LIT dans `Gfx::g_global_settings` est desormais la valeur EFFECTIVE.
//     ce que le MENU affiche et ce que `settings.ini` persiste reste la valeur MEMORISEE.
//
// Le module tient les valeurs VOULUES par le joueur (`set()`, alimente par les ponts `pc-set-*`),
// calcule pour chacune la valeur EFFECTIVE en remontant la chaine de parents, et ECRIT cette
// valeur effective dans le champ de `GfxGlobalSettings`. Un lecteur — compose, nu, present ou
// futur — voit donc la valeur STOCK des qu'un ancetre est eteint. « OFF egale l'ABSENCE » cesse
// d'etre une regle a respecter et devient une propriete du champ lui-meme.
//
// La valeur voulue, elle, n'est jamais ecrasee : c'est la « valeur qu'elles avaient au moment du
// switch off » que l'owner demande de retrouver. Le menu GOAL continue de lire `*pc-settings*`,
// que ce module ne touche pas ; la persistance passe par `handle-output-settings` (pckernel.gc:626)
// et n'est pas concernee.
//
// LA HIERARCHIE EST UNE TABLE, ET C'EST LA MEME DES DEUX COTES
// -----------------------------------------------------------
// `kOptions` ci-dessous est LA source de verite : un parent par option. Le grisage GOAL ne porte
// plus sa propre copie de la regle, il DEMANDE au module (`__pc-gating-disabled?`). Le grisage que
// l'owner voit et la porte que le moteur applique sont donc, par construction, la meme relation.
// C'est ce qui rend le recensement `gating_menu_parent` autre chose qu'un miroir : GOAL rapporte
// les rangees qu'il DESSINE, le C++ publie le parent que la table leur donne, et les deux moities
// ne peuvent pas deriver sans que le compte le dise.
//
// CE QUE CE MODULE NE FAIT PAS
// ----------------------------
// Il ne juge rien et ne mesure aucune performance. Il ne change le CONTENU d'aucune feature : une
// option allumee sous des parents allumes rend exactement ce qu'elle rendait. Il ne touche pas aux
// valeurs persistees. Le verdict reste au validateur, qui lit `gating_defects` dans proof.txt.

#include <cstdint>

namespace recharged_gating {

// ─── LES OPTIONS ─────────────────────────────────────────────────────────────────────────────
// L'ordre n'a aucune importance sauf pour `kMaster`, qui doit rester la racine. Toute option
// ajoutee ici doit AUSSI etre ajoutee a `kOptions` dans le .cpp — le tableau est verifie a
// l'initialisation (chaque entree a la bonne place, chaque parent existe, aucun cycle) et le
// module publie une SENTINELLE si la verification echoue : une table incoherente ne doit jamais
// rendre « zero defaut ».
enum Opt : int {
  kMaster = 0,  // la racine : « Recharged » tout entier

  // ── sous le master directement ──
  kWater,
  kLighting,
  kGrass,
  kTextures,
  kLoadCustomAssets,
  kManagedAssets,
  kEnhancedModels,
  kFoliageWind,
  kCrispTitleLogo,
  kMeshBrowserChecker,

  // ── sous l'herbe ──
  kGrassNearDist,
  kGrassCardDist,
  kGrassDensity,
  kGrassPrecomputed,
  kGrassOverhang,

  // ── sous l'eclairage (le sous-menu « Recharged Lighting » de l'owner) ──
  kAoMode,
  kAoQuality,
  kAoStrength,
  kRtLight,
  kRtShadowRes,
  kRtShadowDist,
  kRtShadowStrength,
  kRtAmbient,
  kRtAmbientModel,
  kRtAmbientStrength,
  kRtAmbientContrast,
  kHdr,
  kHdrKnee,
  kHdrCurve,
  kHdrExposure,
  kHdrOutput,
  kPbr,

  // ── sous PBR MATERIALS ──
  kPbrRelief,
  kPbrSpecular,
  kPbrDisplacement,
  kPbrExposure,
  kPbrIsolate,
  kMeshSubdiv,
  kModernMaterials,

  kOptCount
};

// Identifiant textuel stable de l'option (celui que GOAL et proof.txt emploient), "" hors bornes.
const char* name(int opt);

// L'option nommee, ou -1. Sert au pont GOAL, qui parle par nom et non par indice : un menu qui se
// renumerote ne doit pas pouvoir designer une autre option en silence.
int by_name(const char* id);

// Le parent de l'option, -1 pour la racine.
int parent(int opt);

// ─── LA VALEUR VOULUE PAR LE JOUEUR ──────────────────────────────────────────────────────────
// Appele par les ponts `pc-set-*` (game/kernel/jak1/kmachine.cpp) et par l'amorcage du chargeur.
// C'est la SEULE entree : plus personne n'ecrit un champ `recharged_*` de `GfxGlobalSettings` a
// la main. La valeur est memorisee telle quelle, meme si un ancetre est eteint — c'est la memoire
// que l'owner demande.
void set(int opt, double desired);

// La valeur voulue, telle qu'elle a ete posee. C'est ce que le menu doit afficher.
double desired(int opt);

// La valeur EFFECTIVE : `desired` si tous les ancetres sont allumes, la valeur STOCK sinon.
double effective(int opt);

// Vrai si un ancetre (pas l'option elle-meme) est eteint : c'est EXACTEMENT le predicat de
// grisage du menu. GOAL le consulte par `__pc-gating-disabled?` au lieu de porter sa propre copie.
bool disabled_by_ancestor(int opt);

// ─── LA PORTE, AU SITE DU GESTE ──────────────────────────────────────────────────────────────
// `on()` rend la valeur effective vue comme un booleen ET compte le passage. C'est ce compteur
// qui rend la criterion EFFET falsifiable : parent eteint, `exec` d'une dependante doit rester a
// zero SUR UNE COURSE REELLE, et `eval` a cote dit que le site a bien ete atteint (sans quoi le
// zero ne parlerait de rien — une porte verte par inaction).
bool on(int opt);

// La meme chose pour un mode entier (0 == eteint), pour les carrousels type AO.
int mode(int opt);

// ─── APPLICATION ─────────────────────────────────────────────────────────────────────────────
// Ecrit les valeurs effectives dans `Gfx::g_global_settings`. Appele a chaque `set()` et une fois
// par image. Avant d'ecrire, il RELIT ce qu'il avait ecrit : un champ qui a change entre-temps a
// ete pose par quelqu'un d'autre que ce module, et ce quelqu'un contourne la porte. C'est le seul
// terme de `gating_ungated_sites`, et il a une entree qui le fait monter (n'importe quelle
// affectation directe d'un champ `recharged_*`).
void apply();

// Une image. Applique, recense, fait avancer le balayage de mesure, publie.
void tick();

// ─── RECENSEMENT DU MENU (moitie GOAL) ───────────────────────────────────────────────────────
// GOAL seul sait quelles rangees le menu DESSINE et dans quelle page. Il les rapporte ici ; le
// C++ publie le parent que la TABLE donne a chacune. Une rangee que la table ne connait pas, ou
// une rangee dont la page ne correspond pas au parent, est un defaut : c'est ce qui empeche le
// sous-menu « Recharged Lighting » d'etre une decoration.
void menu_begin();
void menu_row(const char* page, const char* opt_id);
void menu_end();

}  // namespace recharged_gating
