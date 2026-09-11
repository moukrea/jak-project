#pragma once

// gl_query_census — LE COMPTEUR DE REQUETES PILOTE, PRODUIT PAR LES APPELS EUX-MEMES.
//
// POURQUOI PAS UN COMPTEUR AUX SITES. L'item `perf-gl-waits` demande de prouver qu'AUCUNE sonde
// pilote ne tourne plus en production. Un compteur incremente a la main a chaque site connu ne
// prouve que la liste qu'on a ecrite : le site oublie — ou celui qu'un autre chantier ajoutera
// demain — ne rend rien, et la porte reste verte sur un defaut present. C'est le defaut
// « auditer par VALEUR, pas par liste de sites ».
//
// CE MODULE COMPTE AU POINT D'APPEL DU PILOTE. glad expose ses entrees comme des POINTEURS DE
// FONCTION GLOBAUX (`glad_glGetError`, et `#define glGetError glad_glGetError`). `install()`
// remplace ces pointeurs par des relais qui comptent puis appellent le vrai. Tout appel du
// binaire — le notre, celui d'ImGui, celui d'un module qui n'existe pas encore — passe par la.
//
// LES CINQ ENTREES QUE L'ITEM NOMME : glGetError, glGetIntegerv (et sa jumelle glGetInteger64v),
// glReadPixels, glFinish, glMapBufferRange.
//
// CE QUE LA PORTE COMPTE, ET CE QU'ELLE NE COMPTE PAS — LA SEULE DECISION DE FOND.
// --------------------------------------------------------------------------------
// `glFinish`, `glReadPixels` et `glMapBufferRange(GL_MAP_READ_BIT)` font ATTENDRE le fil
// appelant : ils vident le tuyau de commandes. `glGetError` draine la file d'erreurs du pilote,
// et sous KHR_debug synchrone c'est lui qui declenche la validation. Ces quatre-la sont comptes
// A LA PORTE, sans exception.
//
// `glGetIntegerv` recouvre deux gestes tres differents, et le pilote les paye differemment :
//   1. relire une LIMITE (`GL_MAX_SAMPLES`, un alignement d'UBO, un format de lecture) : ces
//      valeurs ne changent jamais de la vie du contexte ; les redemander par image est du
//      gaspillage pur. COMPTE A LA PORTE.
//   2. relire l'ETAT LIE pour le restaurer apres coup (`GL_*_BINDING`, `GL_VIEWPORT`,
//      `GL_CURRENT_PROGRAM`, `GL_PACK_*`) : le pilote rend une valeur qu'il tient cote CPU, sans
//      toucher au GPU. C'est l'idiome sauvegarde/restauration de tout le moteur, present dans une
//      trentaine de fonctions de rendu ecrites par Naughty Dog ou par les chantiers precedents.
//      NON compte a la porte — mais PUBLIE sous `gl_state_restore_queries_per_frame`, avec son
//      total. Une exclusion muette serait le defaut « EXCLU n'est pas CORRECT » ; celle-ci est
//      chiffree, et le chiffre baisse quand un chantier la reduit.
// La liste des `pname` d'etat est une LISTE BLANCHE : un `pname` inconnu tombe du cote COMPTE.
// La polarite sure est celle qui fait rougir la porte, jamais celle qui la laisse verte.
//
// ARME / HORS ARMEMENT. « Arme » ici veut dire DECLARE ET ATTRIBUE : un `Armed("<site>")` sur la
// pile dit « ce bloc parle au pilote exprès, et voici son nom ». La porte lit les requetes
// HORS de tout bloc declare — celles que personne n'assume. Les sondes de SPEC qu'on n'a pas le
// droit de supprimer (hdr.cpp `hdr_overbright_px`, la capture du refset) et les contournements
// pilote Adreno (le defuse F1a/F1d de Merc2, chantier suivant) sont declares : ils restent
// comptes, nommes et publies dans `gl_armed_driver_queries_total` / `gl_query_declared_sites`.
//
// LE TEMOIN QUI REND LE ZERO FALSIFIABLE. Un `gl_unarmed_driver_queries_per_frame=0` obtenu
// parce que les relais ne sont pas installes serait indistinguable d'un zero merite. Trois cles
// l'empechent : `gl_query_census_hooked` (pointeurs glad effectivement remplaces),
// `gl_query_census_selftest` (un appel deliberé fait a l'installation, DANS un bloc declare :
// non nul = le relais s'execute vraiment) et `gl_state_restore_queries_total` (l'idiome de
// restauration, qui tourne des milliers de fois et passe par le MEME relais). Un zero a la porte
// avec un zero sur ces trois temoins est un instrument mort, pas une reussite.
//
// QUAND LA PORTE EST ROUGE, ELLE NOMME LE COUPABLE. `gl_unarmed_top_site` publie l'adresse de
// retour la plus frequente parmi les appels non declares, resolue par `dladdr` quand le symbole
// est exporte, sinon en `libgk.so+0x<offset>` — de quoi pointer la fonction sans deviner.

#include <cstdint>

namespace gl_query_census {

// Remplace les pointeurs glad par les relais. A appeler sur le fil qui porte le contexte, juste
// apres le chargement de glad. IDEMPOTENT, et RE-INSTALLE si un rechargement de glad a remis les
// vrais pointeurs en place (le contexte Android est recree quand la surface revient).
void install();

// Une image vient d'etre dessinee. Bascule le seau de l'image, tient le maximum et publie.
// A appeler UNE fois par image, depuis le fil graphique.
void frame_boundary();

// Un bloc qui parle au pilote exprès. Portee par FIL : un bloc declare sur le fil de chargement
// n'excuse pas une requete emise au meme instant par le fil de rendu.
class Armed {
 public:
  explicit Armed(const char* site);
  ~Armed();
  Armed(const Armed&) = delete;
  Armed& operator=(const Armed&) = delete;

 private:
  const char* m_site;
};

// UNE LIMITE DU CONTEXTE, LUE UNE SEULE FOIS. `GL_MAX_TEXTURE_SIZE`, `GL_MAX_SAMPLES`, un
// alignement d'UBO : ces valeurs ne changent pas de la vie du contexte, et les redemander par
// image (ou par texture chargee) est du gaspillage que cet item retire. La premiere lecture a
// lieu dans un bloc DECLARE (site `gl-limit-cache`), les suivantes ne touchent plus au pilote.
// A n'utiliser QUE pour une grandeur constante ; un etat lie (`GL_*_BINDING`) change et doit
// continuer d'etre relu.
int limit(unsigned int pname);

// L'INTERRUPTEUR DES SONDES DE DIAGNOSTIC. Faux par defaut — c'est le binaire que l'owner joue.
// Arme par `OG_GL_PROBE=1` (bureau) ou `setprop debug.opengoal.glprobe 1` (appareil). Lu UNE
// fois, au premier appel, sur le fil qui demande : une lecture de propriete par image est
// exactement le genre de cout que cet item retire.
bool probes_armed();

// Pour un rapport : le maximum retenu sur les images comptees, et le total hors armement.
uint64_t max_unarmed_per_frame();
uint64_t total_unarmed();

}  // namespace gl_query_census
