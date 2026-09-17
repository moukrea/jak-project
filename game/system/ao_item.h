#pragma once

// ao_item — L'IDENTIFIANT DE L'ITEM D'AO, ECRIT UNE SEULE FOIS.
//
// POURQUOI CE FICHIER EXISTE. Le 2026-09-17 le ticket d'AO a change de nom :
// `lighting-ao-indirect` (14 essais, un livrable devenu illisible) est remplace par
// `ao-indirect-clean`, meme porte et meme mesures. Or tout l'instrument d'AO — la prepasse,
// la sonde, le recensement de motif, la campagne de cout, la ligne d'AO du menu — demandait
// `autoport_proof::feature_is("lighting-ao-indirect")` a SIX endroits differents, chacun avec
// son litteral. Sous le nouvel identifiant, ces six conditions rendent FAUX : l'instrument se
// tait ENTIEREMENT, `ao_owner_defects` n'est jamais publie, et le validateur refuse pour
// « le proof ne porte pas 'ao_owner_defects=' » — un symptome qui ne ressemble pas a sa cause.
//
// LE NOM EST DONC ICI, ET NULLE PART AILLEURS. Le prochain renommage touche une ligne.
//
// DEUX NOMS, DEUX ROLES DISTINCTS :
//   `kId`     — le ticket COURANT. C'est lui, et lui seul, que recoivent `note_hit_for`,
//               `AUTOPORT_FEATURE_SITE` et `armed_for` : c'est le nom que `validators/generic.sh`
//               cherche dans `FEATURE <id> armed=1 hits=<n>` et dans `proof_feature_own_hits`.
//   `kPrevId` — le ticket REMPLACE. Il ne recoit plus ni prise ni site — s'en prevaloir
//               fabriquerait des hits pour un item qui ne tourne plus. Il continue en revanche
//               d'ARMER la MESURE (`measured()`), pour qu'une course relancee par erreur sur
//               l'ancien nom mesure encore quelque chose au lieu de rendre une preuve muette.
//
// CE QUE `measured()` N'EST PAS. Ce n'est pas `armed()`. `feature_is` dit « le harnais mesure
// cet item » et ne doit jamais changer le comportement du jeu ; l'ablation se demande a
// `armed_for(kId)`. Les deux questions ne se confondent pas (autoport_proof.h).

#include "game/system/autoport_proof.h"

namespace ao_item {

inline constexpr const char* kId = "ao-indirect-clean";
inline constexpr const char* kPrevId = "lighting-ao-indirect";

// « Le harnais mesure l'AO » — la seule question que l'instrument pose.
inline bool measured() {
  return autoport_proof::feature_is(kId) || autoport_proof::feature_is(kPrevId);
}

}  // namespace ao_item
