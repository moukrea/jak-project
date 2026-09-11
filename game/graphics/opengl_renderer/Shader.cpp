#include "Shader.h"

#include <regex>

#include "common/log/log.h"
#include "common/util/Assert.h"
#include "common/util/FileUtil.h"
#include "common/util/rss_census.h"

#include "game/graphics/pipelines/opengl.h"
#include "game/graphics/opengl_renderer/shade_proof.h"
#include "game/graphics/opengl_renderer/frame_ubo.h"
#include "game/graphics/opengl_renderer/gl_uniform_cache.h"
#include "game/graphics/opengl_renderer/hdr.h"
#include "game/system/asset_manifest.h"

#ifdef __ANDROID__
// Phase A35 (autoport): on Android the shader sources are the GLES 3.20
// variants generated at build time by shaders/preprocess.py (version
// header, precision qualifiers, sampler1D and noperspective transforms,
// jak1 template tokens already substituted). Embedded as string_views so
// no shader files need to ship in the APK.
#include "shaders_android_blob.h"
#endif

// lighting-legacy-purge (2026-09-11) : `gl_context_supports_tessellation`,
// `gl_tfrag3_tess_program_ok` et `gl_max_tess_gen_level` sont SUPPRIMES avec le programme
// TFRAG3_TESS, leur unique client.

// ===========================================================================================
// Grecharged-pbr-realtime-fusion ROUND 22 — SHADER `#include` (shared GLSL chunks).
//
// Owner defect A ("la plupart des endroits n'ont toujours pas de displacement du tout") was
// STRUCTURAL: only tfrag3 carried the fused rt+pbr path, so TIE-envmap (etie_base), wind-animated
// TIE (tie_wind) and every shrub was incapable of showing relief at ANY slider value. Porting that
// ~1000-line path by copy-paste into three more shaders would guarantee permanent divergence — and
// the owner's mandate is that both displacement tiers show the same depth BY CONSTRUCTION. So the
// path lives ONCE, in shaders/pbr_uniforms.glsl + pbr_helpers.glsl + pbr_fused.glsl, and every
// consumer pulls it in with a `#include "<name>.glsl"` line.
//
// The chunks are NOT standalone shaders (no `#version`). On Android they ride the generated GLES
// blob as a second array (gk_android_shaders::kChunks, see shaders/preprocess.py); on desktop they
// are read from the shader folder. ONE expander serves both, and it runs BEFORE subst_tokens and
// BEFORE inject_pbr_define so the template tokens and the OG_PBR define apply to the expanded text
// exactly as they did when the code was inline.
//
// A chunk's text is emitted VERBATIM — that is what makes the extraction provably a no-op for
// tfrag3.frag (.autoport/gpbrf_r22_include_expand.py re-expands it and diffs against the
// pre-extraction file; the diff is empty). For the same reason a chunk carries no doc header of
// its own: the "names that must be in scope" contract is documented at each consumer's adapter
// preamble (grep "PBR FUSED CHUNK CONTRACT").
// ===========================================================================================
namespace {
constexpr int kMaxIncludeDepth = 4;

// lighting-legacy-purge (2026-09-11) : la TABLE DES CHUNKS COMPAGNONS est VIDE. Elle ne portait
// que les trois fichiers de la pile « Materiaux avances » (pbr_modern_uniforms.glsl,
// pbr_modern_helpers.glsl, pbr_modern.glsl), supprimes avec elle : un compagnon qui nomme un
// fichier ABSENT fait echouer la construction du shader a l'execution, sans erreur de compilation.
// La structure et la boucle de raccordement restent — c'est le mecanisme, pas la pile.
struct ChunkCompanion {
  const char* base;
  const char* extension;
};
constexpr ChunkCompanion kChunkCompanions[] = {
    {nullptr, nullptr},  // sentinelle : un tableau de longueur nulle n'est pas du C++ valide
};

// Resolve one chunk by file name (e.g. "pbr_fused.glsl"). Returns false when it does not exist.
bool find_shader_chunk(const std::string& name, std::string* out) {
#ifdef __ANDROID__
  for (const auto& c : gk_android_shaders::kChunks) {
    if (c.name == name) {
      *out = std::string(c.src);
      return true;
    }
  }
  return false;
#else
  const auto path = file_util::get_file_path({Shader::shader_folder, name});
  if (!file_util::file_exists(path)) {
    return false;
  }
  *out = file_util::read_text_file(path);
  return true;
#endif
}

// Replace every line of the form   [whitespace] #include "NAME.glsl" [whitespace]
// with that chunk's text, recursively (max kMaxIncludeDepth). A MISSING chunk is NEVER silent:
// it logs an error and the source is returned UNCHANGED, so the raw `#include` directive reaches
// the GLSL compiler and the stage fails loudly instead of quietly losing the PBR path.
std::string expand_includes(const std::string& src, int depth = 0) {
  if (src.find("#include") == std::string::npos) {
    return src;
  }
  if (depth > kMaxIncludeDepth) {
    lg::error(
        "[recharged] SHADER INCLUDE: nesting deeper than {} — refusing to expand further. The "
        "shader will fail to compile; fix the chunk cycle.",
        kMaxIncludeDepth);
    return src;
  }
  std::string out;
  out.reserve(src.size() * 2);
  bool missing = false;
  size_t pos = 0;
  while (pos < src.size()) {
    const size_t nl = src.find('\n', pos);
    const size_t line_end = (nl == std::string::npos) ? src.size() : nl + 1;
    const std::string line = src.substr(pos, line_end - pos);
    pos = line_end;

    // ---- match  ^[ \t]*#include[ \t]*"NAME"[ \t]*$  ----
    size_t i = 0;
    while (i < line.size() && (line[i] == ' ' || line[i] == '\t')) {
      i++;
    }
    static const std::string kDirective = "#include";
    if (line.compare(i, kDirective.size(), kDirective) != 0) {
      out += line;
      continue;
    }
    i += kDirective.size();
    while (i < line.size() && (line[i] == ' ' || line[i] == '\t')) {
      i++;
    }
    if (i >= line.size() || line[i] != '"') {
      out += line;
      continue;
    }
    const size_t name_start = ++i;
    const size_t name_end = line.find('"', name_start);
    if (name_end == std::string::npos) {
      out += line;
      continue;
    }
    size_t tail = name_end + 1;
    while (tail < line.size() &&
           (line[tail] == ' ' || line[tail] == '\t' || line[tail] == '\r' || line[tail] == '\n')) {
      tail++;
    }
    if (tail != line.size()) {
      out += line;  // trailing junk: not an include we own
      continue;
    }
    const std::string name = line.substr(name_start, name_end - name_start);
    std::string chunk;
    if (!find_shader_chunk(name, &chunk)) {
      lg::error(
          "[recharged] SHADER INCLUDE: chunk '{}' NOT FOUND (desktop: {}{}; android: not in the "
          "GLES blob's kChunks). The shader source is left UNCHANGED so this fails loudly at "
          "compile time instead of silently dropping the PBR path.",
          name, Shader::shader_folder, name);
      missing = true;
      out += line;
      continue;
    }
    out += expand_includes(chunk, depth + 1);
    // ---- Grecharged-materials-modern-parity: COMPANION CHUNKS ---------------------------------
    // A companion is spliced in immediately after its base chunk, at the base chunk's own
    // injection point, so it lands in the same scope with the same locals visible. It is how the
    // MODERN MATERIAL STACK (subsurface scattering, clearcoat, anisotropy, energy compensation,
    // specular/horizon occlusion) is added to all four world programs WITHOUT editing one byte of
    // pbr_uniforms / pbr_helpers / pbr_fused / tfrag3.frag / tfrag3_tess.*.
    //
    // WHY NOT JUST EDIT THOSE FILES: they carry the look the owner ACCEPTED. Round 27 of the
    // fusion phase edited them, the owner's verdict was "beaucoup, beaucoup moins bien qu'avant",
    // and 4b736aab03 reverted them to fc7b815e34, where they still sit bit-pristine. Extending by
    // composition instead of by edit buys three things at once: the accepted tree cannot regress,
    // "modern OFF == stock" is structural rather than measured (with the layer off the companion's
    // uniform gate is false and nothing it contains writes anything), and the fusion phase can
    // resume on an untouched tree whenever the owner wants it.
    //
    // A missing companion is NOT an error — the table is a static list of optional extensions, and
    // find_shader_chunk() already logs loudly for a missing REQUIRED include above.
    for (const auto& comp : kChunkCompanions) {
      if (comp.base && name == comp.base) {
        std::string ext;
        if (find_shader_chunk(comp.extension, &ext)) {
          out += expand_includes(ext, depth + 1);
        }
      }
    }
  }
  if (missing) {
    return src;
  }
  return out;
}
}  // namespace

Shader::Shader(const std::string& shader_name, GameVersion version) : m_name(shader_name) {
#ifdef __ANDROID__
  std::string vert_src;
  std::string frag_src;
  {
    bool found = false;
    for (const auto& s : gk_android_shaders::kShaders) {
      if (s.name == shader_name) {
        vert_src = std::string(s.vert_src);
        frag_src = std::string(s.frag_src);
        found = true;
        break;
      }
    }
    if (!found) {
      lg::error("A35-RENDER shader '{}' missing from the GLES blob", shader_name);
      m_is_okay = false;
      return;
    }
  }
#else
  // read the shader source
  auto vert_src =
      file_util::read_text_file(file_util::get_file_path({shader_folder, shader_name + ".vert"}));
  auto frag_src =
      file_util::read_text_file(file_util::get_file_path({shader_folder, shader_name + ".frag"}));
#endif
  build(shader_name, vert_src, frag_src, version);
}

// lighting-legacy-purge (2026-09-11) : le constructeur a QUATRE ETAGES (vert+tesc+tese+frag) est
// SUPPRIME avec le programme TFRAG3_TESS, son unique client.

void Shader::build(const std::string& shader_name,
                   const std::string& vert_src_in,
                   const std::string& frag_src_in,
                   GameVersion version) {
  // ROUND 22: shared GLSL chunks. Expand `#include "<name>.glsl"` FIRST — before the per-game
  // template substitution and before the OG_PBR define is injected — so both apply to the
  // expanded text exactly as they did when the code was inline in tfrag3.frag.
  std::string vert_src = expand_includes(vert_src_in);
  std::string frag_src = expand_includes(frag_src_in);

  // Per-game template tokens, substituted at runtime on both desktop and
  // Android (the Android GLES blob keeps them verbatim — jak2 is a 416-line
  // frame, jak1 448; baking jak1 values stretched jak2 geometry vertically).
  const std::string height_scale = version == GameVersion::Jak1 ? "1.0" : "0.5";
  const std::string scissor_height = version == GameVersion::Jak1 ? "448.0" : "416.0";
  const std::string scissor_adjust = "512.0 / " + scissor_height;

  auto subst_tokens = [&](std::string& src, bool vert_like) {
    if (vert_like) {
      src = std::regex_replace(src, std::regex("HEIGHT_SCALE"), height_scale);
      src = std::regex_replace(src, std::regex("SCISSOR_ADJUST"), "(" + scissor_adjust + ")");
    }
    src = std::regex_replace(src, std::regex("SCISSOR_HEIGHT"), scissor_height);
  };
  subst_tokens(vert_src, true);
  subst_tokens(frag_src, false);

#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials: inject the shader-side feature define right after the
  // #version directive (which is NOT the first line on desktop — the source files
  // open with comments; GLSL requires #version to stay first-in-effect, so the
  // define must land after it). Guards the OG_PBR preprocessor block in tfrag3.frag.
  auto inject_pbr_define = [](std::string& src) {
    if (src.empty()) {
      return;
    }
    auto v = src.find("#version");
    auto nl = v == std::string::npos ? std::string::npos : src.find('\n', v);
    if (nl != std::string::npos) {
      src.insert(nl + 1, "#define OG_PBR 1\n");
    } else {
      src += "\n#define OG_PBR 1\n";
    }
  };
  inject_pbr_define(vert_src);
  inject_pbr_define(frag_src);
#endif

  constexpr int len = 1024;
  int compile_ok;
  char err[len];

  auto compile_stage = [&](GLenum type, const std::string& src, const char* label) -> u64 {
    u64 sh = glCreateShader(type);
    const char* csrc = src.c_str();
    if (asset_manifest::enabled()) {
      asset_manifest::record("shader", shader_name + "/" + label, 0, csrc, src.size());
    }
    glShaderSource(sh, 1, &csrc, nullptr);
    glCompileShader(sh);
    glGetShaderiv(sh, GL_COMPILE_STATUS, &compile_ok);
    if (!compile_ok) {
      glGetShaderInfoLog(sh, len, nullptr, err);
      lg::error("Failed to compile {} shader {}:\n{}", label, shader_name.c_str(), err);
      glDeleteShader(sh);
      return 0;
    }
    return sh;
  };

  m_vert_shader = compile_stage(GL_VERTEX_SHADER, vert_src, "vertex");
  if (!m_vert_shader) {
    m_is_okay = false;
    return;
  }
  // lighting-unify : releve du texte fragment TEL QUE LE PILOTE LE RECOIT — apres
  // `expand_includes`, apres `subst_tokens`, apres l'injection de `OG_PBR`. Mesurer plus tot
  // decrirait un texte qui n'est pas celui qui est compile.
  shade_proof::note_fragment_source(shader_name, frag_src);
  hdr::note_fragment_source(shader_name, frag_src);
  m_frag_shader = compile_stage(GL_FRAGMENT_SHADER, frag_src, "fragment");
  if (!m_frag_shader) {
    m_is_okay = false;
    return;
  }

  m_program = glCreateProgram();
  glAttachShader(m_program, m_vert_shader);
  glAttachShader(m_program, m_frag_shader);
  glLinkProgram(m_program);

  glGetProgramiv(m_program, GL_LINK_STATUS, &compile_ok);
  if (!compile_ok) {
    glGetProgramInfoLog(m_program, len, nullptr, err);
    lg::error("Failed to link shader {}:\n{}", shader_name.c_str(), err);
    m_is_okay = false;
    return;
  }
  shade_proof::note_program_linked(shader_name, (unsigned)m_program);

  // uniform samplers must be named matching the texture unit
  glUseProgram(m_program);
  for (int i = 1; i < 30; ++i) {
    std::string uniformName = "tex_T" + std::to_string(i);
    GLint texLoc = glGetUniformLocation(m_program, uniformName.c_str());
    if (texLoc != -1) {
      glUniform1i(texLoc, i);
    }
  }
  // assuming that the bones uniform block is always using binding point 1
  GLint bonesLoc = glGetUniformBlockIndex(m_program, "ub_bones");
  if (bonesLoc != -1) {
    glUniformBlockBinding(m_program, bonesLoc, 1);
  }
  // lighting-ao-indirect (amendement §4.3) : le bloc d'image ub_frame est au point 2, et les
  // emplacements caches pour cet identifiant de programme sont oublies (un id GL reutilise
  // apres suppression ne doit jamais servir un emplacement perime).
  frame_ubo::bind_program(m_program);
  glu::invalidate(m_program);

  glDeleteShader(m_vert_shader);
  glDeleteShader(m_frag_shader);
  m_is_okay = true;
}

void Shader::activate() const {
  ASSERT(m_is_okay);
  glUseProgram(m_program);
  shade_proof::note_program_bound((unsigned)m_program);
}

ShaderLibrary::ShaderLibrary(GameVersion version) {
  at(ShaderId::SOLID_COLOR) = {"solid_color", version};
  at(ShaderId::DIRECT_BASIC) = {"direct_basic", version};
  at(ShaderId::DIRECT_BASIC_TEXTURED) = {"direct_basic_textured", version};
  at(ShaderId::DIRECT_BASIC_TEXTURED_MULTI_UNIT) = {"direct_basic_textured_multi_unit", version};
  at(ShaderId::DEBUG_RED) = {"debug_red", version};
  at(ShaderId::SPRITE) = {"sprite_3d", version};
  at(ShaderId::SKY) = {"sky", version};
  at(ShaderId::SKY_BLEND) = {"sky_blend", version};
  at(ShaderId::TFRAG3) = {"tfrag3", version};
  at(ShaderId::TFRAG3_NO_TEX) = {"tfrag3_no_tex", version};
  at(ShaderId::SPRITE3) = {"sprite3_3d", version};
  at(ShaderId::DIRECT2) = {"direct2", version};
  at(ShaderId::EYE) = {"eye", version};
  at(ShaderId::GENERIC) = {"generic", version};
  at(ShaderId::OCEAN_TEXTURE) = {"ocean_texture", version};
  at(ShaderId::OCEAN_TEXTURE_MIPMAP) = {"ocean_texture_mipmap", version};
  at(ShaderId::OCEAN_COMMON) = {"ocean_common", version};
  at(ShaderId::SHRUB) = {"shrub", version};
  at(ShaderId::SHADOW) = {"shadow", version};
  at(ShaderId::COLLISION) = {"collision", version};
  at(ShaderId::MERC2) = {"merc2", version};
  at(ShaderId::SPRITE_DISTORT) = {"sprite_distort", version};
  at(ShaderId::SPRITE_DISTORT_INSTANCED) = {"sprite_distort_instanced", version};
  at(ShaderId::POST_PROCESSING) = {"post_processing", version};
  at(ShaderId::TONEMAP) = {"tonemap", version};
  at(ShaderId::DEPTH_CUE) = {"depth_cue", version};
  at(ShaderId::EMERC) = {"emerc", version};
  at(ShaderId::GLOW_PROBE) = {"glow_probe", version};
  at(ShaderId::GLOW_PROBE_READ) = {"glow_probe_read", version};
  at(ShaderId::GLOW_PROBE_READ_DEBUG) = {"glow_probe_read_debug", version};
  at(ShaderId::GLOW_PROBE_DOWNSAMPLE) = {"glow_probe_downsample", version};
  at(ShaderId::GLOW_DRAW) = {"glow_draw", version};
  at(ShaderId::ETIE_BASE) = {"etie_base", version};
  at(ShaderId::ETIE) = {"etie", version};
  at(ShaderId::SHADOW2) = {"shadow2", version};
  at(ShaderId::TEX_ANIM) = {"tex_anim", version};
  at(ShaderId::GLOW_DEPTH_COPY) = {"glow_depth_copy", version};
  at(ShaderId::GLOW_PROBE_ON_GRID) = {"glow_probe_on_grid", version};
  at(ShaderId::HFRAG) = {"hfrag", version};
  at(ShaderId::HFRAG_MONTAGE) = {"hfrag_montage", version};
  at(ShaderId::PLAIN_TEXTURE) = {"plain_texture", version};
  at(ShaderId::TIE_WIND) = {"tie_wind", version};
  at(ShaderId::SIMPLE_TEXTURE) = {"simple_texture", version};
  at(ShaderId::SLOW_TIME) = {"slow_time", version};
  at(ShaderId::SPRITE3_INSTANCED) = {"sprite3_3d_inst", version};
  at(ShaderId::GRASS) = {"grass", version};  // Grecharged-grass-poc
  // L'occlusion ambiante : estimateurs SSAO/HBAO/GTAO + flou bilateral. Le programme de
  // composite sur l'image finale est supprime (lighting-ao-indirect, SPEC §4.7).
  at(ShaderId::AO_SSAO) = {"ao_ssao", version};
  at(ShaderId::AO_HBAO) = {"ao_hbao", version};
  at(ShaderId::AO_GTAO) = {"ao_gtao", version};
  at(ShaderId::AO_BLUR) = {"ao_blur", version};
  at(ShaderId::PREPASS_WORLD) = {"prepass_world", version};
  // water-ocean-mesh : clipmap d'ocean + sonde de controle de la couche A.
  at(ShaderId::OCEAN_RECHARGED) = {"ocean_recharged", version};
  at(ShaderId::OCEAN_PROBE) = {"ocean_probe", version};
#ifdef OG_FEAT_PBR
  at(ShaderId::PBR_DEPTH) = {"pbr_depth", version};
  // lighting-legacy-purge (2026-09-11) : le programme TFRAG3_TESS n'est plus construit — il
  // n'existe plus. Le mode DISPLACEMENT = TESSELLATION qui l'aurait selectionne n'a jamais ete
  // livre.
#endif

#ifdef __ANDROID__
  // A35: name every failing shader instead of dying on the first one — a
  // device-side compile failure needs the full list to be fixable in one
  // cycle. Renderers whose shaders failed will still loudly assert at
  // activate() if they are ever used.
  int failed = 0;
  for (int i = 0; i < (int)ShaderId::MAX_SHADERS; ++i) {
    if (!m_shaders[i].okay()) {
      failed++;
    }
  }
  if (failed > 0) {
    lg::error("A35-RENDER {} of {} shaders FAILED to compile under GLES 3.20 (see "
              "'Failed to compile' lines above)",
              failed, (int)ShaderId::MAX_SHADERS);
  } else {
    lg::info("A35-RENDER all {} shaders compiled under GLES 3.20", (int)ShaderId::MAX_SHADERS);
  }
#else
  for (int i = 0; i < (int)ShaderId::MAX_SHADERS; ++i) {
    ASSERT_MSG(m_shaders[i].okay(), "error compiling shader");
  }
#endif
  // A55-RSS: pose juste apres la ligne `A35-RENDER all {} shaders compiled` ci-dessus
  // (hors du #ifdef pour que le meme marqueur existe aussi sur la cible x86 de reference).
  rss_census::mark("shaders");
}
