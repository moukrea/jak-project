#pragma once
// prop_cache — LECTURE THROTTLEE DES PROPRIETES SYSTEME ET DE L'ENVIRONNEMENT (item
// `lighting-ao-indirect`, amendement perf du 2026-09-09, SPEC-refonte-lumiere §4.3).
//
// LE DEFAUT. `first_tfrag_draw_setup` lisait ~42 proprietes systeme (Android,
// `__system_property_get`) ou ~33 variables d'environnement (bureau, `getenv`) a CHAQUE appel,
// soit ~1 000 lectures par image sur l'appareil, chacune une marche dans l'arbre partage des
// proprietes. Modele `AoOverride` (AmbientOcclusion.cpp) : la valeur est relue toutes les 0,25 s
// et servie depuis le cache entre deux relectures. La SEMANTIQUE des appels est conservee au
// caractere pres (meme signature, meme valeur de retour, meme tampon) : seule la latence d'un
// changement de propriete passe de « l'image suivante » a « au plus 0,25 s ».
//
// LA CLE est l'adresse du litteral de nom, verifiee par son contenu (tous les appelants passent
// des litteraux).
#include <cstddef>
#include <cstdint>

namespace prop_cache {

// Meme contrat que `__system_property_get(name, value)` : copie la valeur dans `value`
// (PROP_VALUE_MAX octets) et rend sa longueur ; 0 si absente. Bureau : rend toujours 0.
int property_get(const char* name, char* value);

// Meme contrat que `getenv(name)` : le pointeur rendu reste valide jusqu'a la prochaine
// relecture de CE nom (au plus tot 0,25 s plus tard) — les appelants font `atof`/`atoi`
// immediatement, comme avant.
const char* env_get(const char* name);

// Une fois par image : bascule et publie `prop_reads_per_frame` (lectures REELLES de l'image
// precedente) et `prop_reads_served_per_frame` (lectures servies depuis le cache).
void frame_begin();

}  // namespace prop_cache
