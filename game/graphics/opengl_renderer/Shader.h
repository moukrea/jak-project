#pragma once

#include <string>

#include "common/common_types.h"
#include "common/versions/versions.h"

class Shader {
 public:
  static constexpr char shader_folder[] = "game/graphics/opengl_renderer/shaders/";
  Shader(const std::string& shader_name, GameVersion version);
  // REOPEN #3 TESSELLATION: a shader with tessellation-control + tessellation-evaluation
  // stages. vert_name/frag_name may differ from tesc_name/tese_name (the tess program reuses
  // the plain tfrag3 fragment source). If the current GL context has no tessellation support,
  // construction fails SOFT (m_is_okay stays false, one log line) — it never crashes; the
  // caller must gate program selection on okay().
  Shader(const std::string& vert_name,
         const std::string& tesc_name,
         const std::string& tese_name,
         const std::string& frag_name,
         GameVersion version);
  Shader() = default;
  void activate() const;
  bool okay() const { return m_is_okay; }
  u64 id() const { return m_program; }

 private:
  // Shared build of the linked program from already-substituted stage sources. tesc_src/tese_src
  // empty => a plain 2-stage vert+frag program (the legacy path). Returns via members.
  void build(const std::string& shader_name,
             const std::string& vert_src,
             const std::string& tesc_src,
             const std::string& tese_src,
             const std::string& frag_src,
             GameVersion version);
  std::string m_name;
  u64 m_frag_shader = 0;
  u64 m_vert_shader = 0;
  u64 m_tesc_shader = 0;
  u64 m_tese_shader = 0;
  u64 m_program = 0;
  bool m_is_okay = false;
};

// REOPEN #3 TESSELLATION: true when the live GL/GLES context exposes the tessellation stages
// (desktop GL >= 4.0, or GLES >= 3.2). Cached after the first query. A Shader with tess stages
// must never be selected/activated when this is false.
bool gl_context_supports_tessellation();

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
  // Grecharged-ambient-occlusion: screen-space AO passes (estimator + blur + composite)
  AO_SSAO = 45,
  AO_HBAO = 46,
  AO_GTAO = 47,
  AO_BLUR = 48,
  AO_COMPOSITE = 49,
#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials round-4 mandate B: depth-only sun shadow-map pass.
  PBR_DEPTH = 50,
  // REOPEN #3 TESSELLATION displacement: TFRAG3 with a tess control+eval stage that
  // displaces the surface by the PBR height map (u_pbr_displacement == 2). vert =
  // tfrag3_tess.vert (pass-through), tesc = tfrag3.tesc, tese = tfrag3.tese, frag =
  // tfrag3.frag (reused unchanged). Only compiled/selected on a tess-capable context.
  TFRAG3_TESS = 51,
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
