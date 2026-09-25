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
  // lighting-shadows (SPEC-refonte-lumiere §1.2 decision 2) : « Ombres d'acteurs » (vraies /
  // aplat PS2 / aucune) et sa distance, sous le meme sous-menu que l'AO.
  kActorShadows,
  kActorShadowDist,
  // lighting-shadows partie B (SPEC-refonte-lumiere §6.2, paliers §4.8) : les cinq reglages de
  // l'atlas d'ombres portees PBR, tous enfants de `kLighting` comme `ao-mode`. Lus uniquement par
  // le code de l'atlas PBR, donc sans effet hors eclairage recharge (regle du parent).
  kShadowAtlas,
  kShadowCascades,
  kShadowDist,
  kShadowStrength,
  kShadowSecond,
  kHdr,
  kHdrKnee,
  kHdrCurve,
  kHdrExposure,
  kHdrOutput,
  // lighting-legacy-purge (2026-09-11) : les quatorze options de l'ancien monde sont RETIREES de
  // la table, pas mises a zero. Le rendu PBR n'est plus une option : il est INCONDITIONNEL sous
  // « lighting ». Ce que portaient les autres est fige dans RechargedFixed (gfx.h).
  kPbrExposure,

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
// `page` vaut la page reelle de la rangee, ou l'une des deux ABSENCES DECLAREES : `"hidden"` pour
// une rangee que ce build ne livre pas (HDR OUTPUT sans ecran HDR), `"masked"` pour une rangee que
// la page connait mais qui a QUITTE la liste dessinee parce qu'un ancetre est eteint. Les deux ne
// se confondent pas : `hidden` sort l'option du jugement de couverture, `masked` l'y laisse — une
// option masquee reste une option que la course doit avoir exercee.
void menu_row(const char* page, const char* opt_id);
void menu_end();

// ─── LE LIBELLE PORTEUR ET SA PRESELECTION (l'exigence 8 de l'owner) ─────────────────────────
// Une rangee doit AFFICHER sa valeur courante, et l'ouvrir doit PRESELECTIONNER cette valeur. Ni
// l'un ni l'autre ne se verifie en regardant le menu : ce qu'on mesure ici est l'indice que GOAL
// a effectivement calcule (`shown`), celui sur lequel il a pose le curseur (`presel`), le nombre
// de lignes de la page de choix (`rows`, < 2 = ce n'est pas un sous-menu) et le texte non vide.
// `shown` est compare a la valeur VOULUE que porte la table : c'est ce qui empeche la mesure
// d'etre un miroir de GOAL.
void menu_value(const char* opt_id,
                int shown_index,
                int presel_index,
                int page_rows,
                const char* value_text);

// Ce que GOAL a compte sur la page qu'il vient de dessiner : des rangees encore PRESENTES alors
// qu'un ancetre les verrouille (doit rester zero — c'est le defaut « grise au lieu de masque »),
// et le total de rangees masquees (temoin informatif, a comparer au compte du C++).
void menu_mask_counts(int shown_locked, int masked_total);

// LE C++ RECLAME-T-IL UN RECENSEMENT MAINTENANT ? Le balayage eteint un parent different a chaque
// fenetre ; un recensement unique ne verrait donc qu'UN SEUL regime, et le masquage ne serait
// jamais exerce. Le module pose ce drapeau a l'interieur de chaque fenetre, GOAL le consomme
// quand il peut (menu ouvrable) et recense. La lecture CONSOMME le drapeau : deux lecteurs ne
// peuvent pas se declencher sur la meme demande.
bool census_due();

// Le harnais mesure-t-il CET item ? Le recensement du menu a besoin de `init-game-options`, que
// le jeu n'appelle qu'a l'OUVERTURE du menu — au demarrage, aucune rangee ne porte encore son
// libelle ni son identifiant. Sous mesure, GOAL le force une fois au boot pour que la course
// puisse recenser sans qu'un humain ouvre le menu ; hors mesure, on ne touche a rien. C'est
// l'INSTRUMENT qui est sous drapeau, jamais le correctif (meme patron que
// `settings_case_l10n::pc_scl10n_wanted`).
bool census_wanted();

// LA PAGE OU CETTE OPTION DOIT VIVRE, DEDUITE DE SON PARENT : 0 = « Recharged Settings »,
// 1 = « Grass Settings », 2 = « Recharged Lighting », -1 = option inconnue.
//
// POURQUOI LE MENU DEMANDE SA STRUCTURE A LA TABLE DES PORTES. L'owner veut un sous-menu
// « Recharged Lighting » qui contienne « tout ce qui viendra en lien a la refonte de
// l'eclairage ». Ecrire cette liste a la main dans le menu la ferait deriver de la hierarchie des
// portes des le premier ajout — c'est-a-dire refaire, sur la PLACE des options, exactement la
// faute qu'on vient de corriger sur leur EXTINCTION. GOAL construit donc ses pages en demandant
// ici, et une option ajoutee sous `kLighting` atterrit dans le sous-menu sans que personne n'y
// pense.
int page_of(int opt);

}  // namespace recharged_gating
