#pragma once

#include "game/graphics/texture/TexturePool.h"

// Gloading-screen — les deux images de l'ecran de chargement, montees dans des fentes VRAM fixes
// du pool PC pour que GOAL puisse les designer par TBP dans un adgif TEX0 :
//   8311 loading_jak        (silhouette Jak + Daxter)
//   8312 loading_precursor  (atlas des glyphes precurseurs A-Z)
// Elles doivent correspondre a RHUD_TBP_LOADING_* dans goal_src/jak1/pc/loading-screen-pc.gc.
//
// POURQUOI CE FICHIER EXISTE AU LIEU D'UNE ENTREE DE PLUS DANS RechargedHudTextures.cpp.
// Cette derniere unite de compilation est FEATURE-GATEE : android/CMakeLists.txt et
// game/CMakeLists.txt ne l'ajoutent que sous `if(OG_FEAT_RECHARGED_HUD)`, et le build ANDROID
// LIVRE est bati avec `hud=0` (marqueur ogflags:435df2141670:android-arm64). Mesure sur le
// libgk.so publie le 2026-08-29 05:41 : ZERO occurrence de « jak_heart_100 », « recharged-hud »
// ou « loading_jak ». Les fentes 8311/8312 n'y etaient donc JAMAIS remplies, et
// DirectRenderer.cpp:425 lie alors la texture de remplacement -- un damier gris de 16x16.
// L'ecran de chargement aurait affiche un DAMIER a la place de la silhouette et de chaque glyphe.
// L'ecran de chargement n'est pas le HUD « recharged » : il ne doit dependre d'aucun de ses
// drapeaux. Cette unite est donc compilee SANS CONDITION des deux cotes.
void load_loading_screen_textures(TexturePool& pool, GameVersion version);
