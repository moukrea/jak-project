#pragma once

// gl_query_census — LE COMPTEUR DE REQUETES PILOTE, PRODUIT PAR LES APPELS EUX-MEMES.
//
// POURQUOI PAS UN COMPTEUR AUX SITES. L'item `perf-gl-waits` demande de prouver qu'AUCUNE sonde
// pilote ne tourne plus en production. Un compteur incremente a la main a chaque site connu ne
// prouve que la liste qu'on a ecrite : le site qu'on a oublie — ou celui qu'un autre chantier
// ajoutera demain — ne rend rien, et la porte reste verte sur un defaut present. C'est le defaut
// « auditer par VALEUR, pas par liste de sites ».
//
// CE MODULE COMPTE AU POINT D'APPEL DU PILOTE. glad expose ses entrees comme des POINTEURS DE
// FONCTION GLOBAUX (`glad_glGetError`, et `#define glGetError glad_glGetError`). `install()`
// remplace ces pointeurs par des relais qui comptent puis appellent le vrai. Tout appel du
// binaire — le notre, celui d'ImGui, celui d'un module qui n'existe pas encore — passe par la.
// Il n'y a pas de liste a tenir a jour.
//
// LES CINQ ENTREES QUE L'ITEM NOMME : glGetError, glGetIntegerv (et sa jumelle glGetInteger64v),
// glReadPixels, glFinish, glMapBufferRange. Ce sont les appels qui font ATTENDRE le fil appelant :
// les quatre premiers vident le tuyau de commandes, le cinquieme rend un pointeur que le pilote
// ne peut fournir qu'une fois le tampon libre.
//
// ARME / HORS ARMEMENT. « Arme » ici veut dire DECLARE ET ATTRIBUE : un `Armed("<site>")` sur la
// pile dit « ce bloc parle au pilote exprès, et voici son nom ». La porte lit les requetes
// HORS de tout bloc declare — celles que personne n'assume. Les sondes de SPEC qu'on n'a pas le
// droit de supprimer (hdr_overbright_px, la capture du refset) et le contournement F1a/F1d de
// Merc2 (chantier suivant) sont declares : ils restent comptes, nommes et publies dans
// `gl_armed_driver_queries_total` / `gl_query_declared_sites`, mais ils ne sont plus anonymes.
//
// LE TEMOIN QUI REND LE ZERO FALSIFIABLE. Un `gl_unarmed_driver_queries_per_frame=0` obtenu
// parce que les relais ne sont pas installes serait indistinguable d'un zero merite. Trois cles
// l'empechent : `gl_query_census_hooked` (nombre de pointeurs glad effectivement remplaces),
// `gl_query_census_selftest` (un appel deliberé fait a l'installation, DANS un bloc declare :
// non nul = le relais s'execute vraiment) et `gl_armed_driver_queries_total` (les sondes
// declarees qui tournent encore). Un zero a la porte avec un zero sur ces temoins est un
// instrument mort, pas une reussite.

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

// Pour un rapport : le maximum retenu sur les images comptees, et le total hors armement.
uint64_t max_unarmed_per_frame();
uint64_t total_unarmed();

}  // namespace gl_query_census
