#pragma once

// water_census — LA JOINTURE QUI PORTE LA PORTE DE L'ITEM `water-census`.
//
// POURQUOI CE MODULE EXISTE.
// -------------------------
// Le recensement de l'eau a deux moities de PROVENANCE DIFFERENTE, et c'est la tout l'interet :
//
//   - l'ENUMERATION vient des donnees. `tools/water_bake` lit les 26 `.fr3` (famille ISO,
//     produite par l'utilisateur) et les JSON d'entites du decompilateur, et ecrit
//     `custom_assets/jak1/water_census/water_inventory.txt`. Personne ne la tape a la main.
//   - les VERDICTS viennent de nous. `recharged_assets/water_falls.txt` (un verdict par
//     prototype), `water_overrides.txt` (une matiere par look), `water_materials.txt` (les huit
//     matieres). Ce sont des DONNEES, relues au demarrage : un classement se corrige sans
//     rebuild, sur le patron de `recharged_assets/foliage_wind_protos.txt`.
//
// Ce module JOINT les deux et publie le residu. `water_proto_unassigned` — la porte — est le
// nombre de noms enumeres depuis les donnees qu'aucune ligne de verdict ne couvre. Il ne se
// calcule pas depuis nos propres variables : un cote est mesure, l'autre est ecrit, et l'ecart
// est la grandeur.
//
// LA PORTE NE DOIT PAS POUVOIR ETRE VERTE PAR INACTION.
// ----------------------------------------------------
// `water_proto_unassigned == 0` est satisfait trivialement par un module qui ne tourne pas, par
// un inventaire absent, ou par un inventaire vide. Trois garde-fous, tous publies :
//
//   1. `water_proto_total` est publie a cote : zero denominateur se VOIT.
//   2. inventaire absent, illisible ou vide  =>  `water_proto_unassigned` prend la valeur
//      SENTINELLE `kNoCensus`, jamais 0. Une porte qui ne peut pas etre mesuree est ROUGE, pas
//      verte. C'est la regle « non-destruction au point de production » : on rend la panne
//      impossible a confondre avec un succes, au lieu de la detecter en aval.
//   3. `note_hit()` ne compte que des noms REELLEMENT classes ; le bras desarme publie
//      `hits=0`, et le validateur refuse deja `hits=0` du cote arme.
//
// ET L'INVENTAIRE PERIME ? Il est genere depuis les `.fr3`. Si les niveaux sont re-extraits sans
// que `water_bake` soit relance, l'inventaire decrit des donnees qui n'existent plus. Le module
// compare donc, pour chaque niveau, la TAILLE du `.fr3` sur le disque a celle inscrite dans
// l'inventaire, et publie `water_inventory_stale_levels`. Le chemin passe par
// `file_util::resolve_fr3_asset` — le RESOLVEUR, jamais un chemin brut : sur l'appareil le fr3
// vient du pack, et une garde posee sur un chemin construit a la main ne verrait rien.
//
// CE MODULE NE DESSINE RIEN ET NE PUBLIE PAS `gpu_ms_ocean`. Cette cle appartient a
// `lighting_census` (le chronometre GPU par passe) et la derniere ecriture gagne : en publier
// une seconde ici ecraserait une mesure par un chiffre invente.

namespace water_census {

// Le recensement complet : lit les fichiers, joint, publie. Idempotent — seul le premier appel
// travaille. Appelee depuis le chargeur de niveau, le seul site garanti d'etre atteint sur les
// deux plateformes une fois que les chemins d'assets sont resolus.
void run_once();

}  // namespace water_census
