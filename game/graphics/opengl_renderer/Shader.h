#pragma once

#include <string>

#include "common/common_types.h"
#include "common/versions/versions.h"

class Shader {
 public:
  static constexpr char shader_folder[] = "game/graphics/opengl_renderer/shaders/";
  Shader(const std::string& shader_name, GameVersion version);
  Shader() = default;
  void activate() const;
  bool okay() const { return m_is_okay; }
  u64 id() const { return m_program; }

 private:
  // Shared build of the linked program from already-substituted stage sources (vert + frag).
  // Returns via members.
  void build(const std::string& shader_name,
             const std::string& vert_src,
             const std::string& frag_src,
             GameVersion version);
  std::string m_name;
  u64 m_frag_shader = 0;
  u64 m_vert_shader = 0;
  u64 m_program = 0;
  bool m_is_okay = false;
};

// lighting-legacy-purge (2026-09-11) : les trois indicateurs de capacite de TESSELLATION
// sont SUPPRIMES avec le programme tesselle, jamais livre.

// note: update the constructor in Shader.cpp
enum class ShaderId {
  SOLID_COLOR = 0,
  DIRECT_BASIC = 1,
  DIRECT_BASIC_TEXTURED = 2,
  DEBUG_RED = 3,
  SKY = 4,
  SKY_BLEND = 5,
  TFRAG3 = 6,
  TFRAG3_NO_TEX = 7,
  SPRITE = 8,
  SPRITE3 = 9,
  DIRECT2 = 10,
  EYE = 11,
  GENERIC = 12,
  OCEAN_TEXTURE = 13,
  OCEAN_TEXTURE_MIPMAP = 14,
  OCEAN_COMMON = 15,
  SHADOW = 16,
  SHRUB = 17,
  COLLISION = 18,
  MERC2 = 19,
  SPRITE_DISTORT = 20,
  SPRITE_DISTORT_INSTANCED = 21,
  POST_PROCESSING = 22,
  DEPTH_CUE = 23,
  EMERC = 24,
  GLOW_PROBE = 25,
  GLOW_PROBE_READ = 26,
  GLOW_PROBE_READ_DEBUG = 27,
  GLOW_PROBE_DOWNSAMPLE = 28,
  GLOW_DRAW = 29,
  ETIE_BASE = 30,
  ETIE = 31,
  SHADOW2 = 32,
  DIRECT_BASIC_TEXTURED_MULTI_UNIT = 33,
  TEX_ANIM = 34,
  GLOW_DEPTH_COPY = 35,
  GLOW_PROBE_ON_GRID = 36,
  HFRAG = 37,
  HFRAG_MONTAGE = 38,
  PLAIN_TEXTURE = 39,
  TIE_WIND = 40,
  SIMPLE_TEXTURE = 41,
  SLOW_TIME = 42,
  SPRITE3_INSTANCED = 43,
  GRASS = 44,  // Grecharged-grass-poc: procedural 3D grass (jak1 training)
  // L'occlusion ambiante : estimateur + flou bilateral. PAS de composite — le programme
  // `ao_composite` de l'ancien chemin est supprime (lighting-ao-indirect, SPEC §4.7).
  AO_SSAO = 45,
  AO_HBAO = 46,
  AO_GTAO = 47,
  AO_BLUR = 48,
  PREPASS_WORLD = 49,  // lighting-ao-indirect : prepasse de profondeur vue camera (PrePass.cpp)
  // lighting-hdr : le site UNIQUE de tone map (SPEC-refonte-lumiere §4.5, passe P9). Ce
  // programme est le seul de la chaine d'affichage autorise a compresser la plage ; le
  // recensement de hdr.cpp le reconnait par le marqueur `@tonemap-site` de son texte.
  TONEMAP = 50,
  // water-ocean-mesh (SPEC-refonte-eau §5.3, §8) : la clipmap d'ocean et sa sonde de controle.
  // Les deux partagent le chunk `ocean_layer_a.glsl` — une seule transcription de
  // `ocean-get-height`, sinon la porte comparerait deux copies qui derivent.
  OCEAN_RECHARGED = 51,
  OCEAN_PROBE = 52,
#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials round-4 mandate B: depth-only sun shadow-map pass.
  PBR_DEPTH = 53,
  // lighting-legacy-purge (2026-09-11) : `TFRAG3_TESS` (l'ancien 54, DERNIER enumerateur) est
  // SUPPRIME : le mode DISPLACEMENT = TESSELLATION n'a jamais ete livre. Etant le dernier, son
  // retrait ne renumerote AUCUN autre identifiant.
#endif
  // lighting-ao-indirect (essai 9) : la sonde portable — empaquetage d'une profondeur 24 bits
  // dans un RGBA8, et resolution des drapeaux de shade() par test de STENCIL. GLES 3.2 ne relit
  // ni GL_DEPTH_COMPONENT ni GL_STENCIL_INDEX ; il relit un RGBA8.
  AO_PROBE = 54,
  // water-ocean-mesh (defaut 4 de l'arbitrage du 16/09) : l'oracle du recensement d'emprise —
  // l'ocean de Naughty Dog, rasterise depuis les sommets que son microcode VU1 emule produit
  // deja, dans une cible de recensement et non a l'ecran.
  OCEAN_FOOTPRINT_ND = 55,
  // water-ocean-mesh (verdict C du 17/09) : la sonde de houle — ce que la surface LIVREE deplace
  // vraiment, relu du GPU au pas de l'anneau 0. Elle partage `ocean_layer_a.glsl` ET
  // `ocean_atten.glsl` avec la clipmap : une seule transcription de chaque loi, deux lecteurs.
  OCEAN_WAVE = 56,
#ifdef OG_FEAT_PBR
  // lighting-shadows (SPEC §4.8) : depth-only merc (acteur) dans une tuile de l'atlas d'ombre.
  MERC_SHADOW = 57,
  // lighting-shadows : sonde de preuve — triangle plein ecran qui noircit tout pixel monde non
  // marque au stencil, pour isoler la population que la relecture couleur classe.
  SHADOW_PROBE = 58,
#endif
  MAX_SHADERS
};

class ShaderLibrary {
 public:
  ShaderLibrary(GameVersion version);
  Shader& operator[](ShaderId id) { return m_shaders[(int)id]; }
  Shader& at(ShaderId id) { return m_shaders[(int)id]; }

 private:
  Shader m_shaders[(int)ShaderId::MAX_SHADERS];
};
