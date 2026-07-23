#include "Shader.h"

#include <regex>

#include "common/log/log.h"
#include "common/util/Assert.h"
#include "common/util/FileUtil.h"

#include "game/graphics/pipelines/opengl.h"

#ifdef __ANDROID__
// Phase A35 (autoport): on Android the shader sources are the GLES 3.20
// variants generated at build time by shaders/preprocess.py (version
// header, precision qualifiers, sampler1D and noperspective transforms,
// jak1 template tokens already substituted). Embedded as string_views so
// no shader files need to ship in the APK.
#include "shaders_android_blob.h"
#endif

// REOPEN #3 TESSELLATION: the live context's tessellation capability. Desktop GL exposes
// the tess stages from core 4.0 (glad fills GLVersion); GLES exposes them from core 3.2.
// Queried once, lazily, so it is safe to call from any renderer path after context creation.
// REOPEN #3 TESSELLATION driver-defensive: the FINAL usability of the tess program. Set true
// only when the TFRAG3_TESS program was actually built AND linked okay() on the live context.
// Distinct from gl_context_supports_tessellation() (which only reflects capability), because a
// context that advertises tessellation can still fail to build/link the tess program.
static bool s_tfrag3_tess_program_ok = false;
bool gl_tfrag3_tess_program_ok() {
  return s_tfrag3_tess_program_ok;
}

bool gl_context_supports_tessellation() {
  static int cached = -1;
  if (cached != -1) {
    return cached != 0;
  }
  bool ok = false;
#ifdef __ANDROID__
  // GLES: tessellation is CORE from GLES 3.2. Parse the major.minor from GL_VERSION
  // ("OpenGL ES 3.2 ...") rather than trusting a build-time constant.
  const char* ver = (const char*)glGetString(GL_VERSION);
  if (ver) {
    // find the first "<major>.<minor>" run.
    int major = 0, minor = 0;
    for (const char* p = ver; *p; ++p) {
      if (*p >= '0' && *p <= '9' && p[1] == '.') {
        major = *p - '0';
        minor = (p[2] >= '0' && p[2] <= '9') ? p[2] - '0' : 0;
        break;
      }
    }
    ok = (major > 3) || (major == 3 && minor >= 2);
  }
#else
  // Desktop GL: glad's GLVersion is populated at load; tess is core from 4.0.
  ok = (GLVersion.major > 4) || (GLVersion.major == 4 && GLVersion.minor >= 0);
#endif
  // Driver-defensive: the version report is not enough. glPatchParameteri is a loaded
  // function pointer (glad's macro expands to glad_glPatchParameteri) that can be NULL on a
  // driver even when GL_VERSION advertises tessellation. Calling a NULL fn-ptr crashes, so
  // require the entry point to be actually resolved before declaring tessellation usable.
  if (ok && glPatchParameteri == nullptr) {
    ok = false;
    lg::warn(
        "[recharged] GL reports 3.2 but glPatchParameteri is unresolved — tessellation "
        "disabled (driver-defensive)");
  }
  cached = ok ? 1 : 0;
  if (!ok) {
    lg::warn("REOPEN#3 TESS: GL context has no tessellation stages — tess programs disabled");
  }
  return ok;
}

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
  build(shader_name, vert_src, "", "", frag_src, version);
}

// REOPEN #3 TESSELLATION: a 4-stage program (vert + tesc + tese + frag). Stage source names
// may differ (the tess program reuses tfrag3.frag as its fragment source). Fails SOFT on a
// context without tessellation support.
Shader::Shader(const std::string& vert_name,
               const std::string& tesc_name,
               const std::string& tese_name,
               const std::string& frag_name,
               GameVersion version)
    : m_name(vert_name) {
  if (!gl_context_supports_tessellation()) {
    // Soft-fail: no crash, no program. The caller must gate on okay().
    m_is_okay = false;
    return;
  }
#ifdef __ANDROID__
  std::string vert_src, tesc_src, tese_src, frag_src;
  auto lookup = [](const std::string& name, std::string& vert, std::string& tesc,
                   std::string& tese, std::string& frag) -> bool {
    for (const auto& s : gk_android_shaders::kShaders) {
      if (s.name == name) {
        vert = std::string(s.vert_src);
        frag = std::string(s.frag_src);
        tesc = std::string(s.tesc_src);
        tese = std::string(s.tese_src);
        return true;
      }
    }
    return false;
  };
  {
    std::string dummy_tesc, dummy_tese, dummy_frag, dummy_vert;
    // vert + tesc + tese all come from the vert_name entry (the tess set is authored as one
    // named group: tfrag3_tess.{vert,tesc,tese}); the fragment source comes from frag_name.
    if (!lookup(vert_name, vert_src, tesc_src, tese_src, dummy_frag)) {
      lg::error("REOPEN#3 TESS shader group '{}' missing from the GLES blob", vert_name);
      m_is_okay = false;
      return;
    }
    if (!lookup(frag_name, dummy_vert, dummy_tesc, dummy_tese, frag_src)) {
      lg::error("REOPEN#3 TESS frag source '{}' missing from the GLES blob", frag_name);
      m_is_okay = false;
      return;
    }
  }
#else
  auto vert_src =
      file_util::read_text_file(file_util::get_file_path({shader_folder, vert_name + ".vert"}));
  auto tesc_src =
      file_util::read_text_file(file_util::get_file_path({shader_folder, tesc_name + ".tesc"}));
  auto tese_src =
      file_util::read_text_file(file_util::get_file_path({shader_folder, tese_name + ".tese"}));
  auto frag_src =
      file_util::read_text_file(file_util::get_file_path({shader_folder, frag_name + ".frag"}));
#endif
  build(vert_name, vert_src, tesc_src, tese_src, frag_src, version);
}

void Shader::build(const std::string& shader_name,
                   const std::string& vert_src_in,
                   const std::string& tesc_src_in,
                   const std::string& tese_src_in,
                   const std::string& frag_src_in,
                   GameVersion version) {
  std::string vert_src = vert_src_in;
  std::string tesc_src = tesc_src_in;
  std::string tese_src = tese_src_in;
  std::string frag_src = frag_src_in;
  const bool has_tess = !tesc_src.empty() && !tese_src.empty();

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
  // The tessellation-evaluation stage applies the SAME camera transform + SCISSOR_ADJUST *
  // HEIGHT_SCALE the vert normally does (it produces gl_Position), so it needs the vert-like
  // token substitution too. tesc/frag only need SCISSOR_HEIGHT (harmless if absent).
  subst_tokens(vert_src, true);
  subst_tokens(frag_src, false);
  if (has_tess) {
    subst_tokens(tesc_src, false);
    subst_tokens(tese_src, true);
  }

#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials: inject the shader-side feature define right after the
  // #version directive (which is NOT the first line on desktop — the source files
  // open with comments; GLSL requires #version to stay first-in-effect, so the
  // define must land after it). Guards the OG_PBR preprocessor block in tfrag3.frag —
  // and the height-displacement OG_PBR block in the tess stages.
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
  if (has_tess) {
    inject_pbr_define(tesc_src);
    inject_pbr_define(tese_src);
  }
#endif

  constexpr int len = 1024;
  int compile_ok;
  char err[len];

  auto compile_stage = [&](GLenum type, const std::string& src, const char* label) -> u64 {
    u64 sh = glCreateShader(type);
    const char* csrc = src.c_str();
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
  m_frag_shader = compile_stage(GL_FRAGMENT_SHADER, frag_src, "fragment");
  if (!m_frag_shader) {
    m_is_okay = false;
    return;
  }
  if (has_tess) {
    m_tesc_shader = compile_stage(GL_TESS_CONTROL_SHADER, tesc_src, "tess-control");
    if (!m_tesc_shader) {
      m_is_okay = false;
      return;
    }
    m_tese_shader = compile_stage(GL_TESS_EVALUATION_SHADER, tese_src, "tess-eval");
    if (!m_tese_shader) {
      m_is_okay = false;
      return;
    }
  }

  m_program = glCreateProgram();
  glAttachShader(m_program, m_vert_shader);
  if (has_tess) {
    glAttachShader(m_program, m_tesc_shader);
    glAttachShader(m_program, m_tese_shader);
  }
  glAttachShader(m_program, m_frag_shader);
  glLinkProgram(m_program);

  glGetProgramiv(m_program, GL_LINK_STATUS, &compile_ok);
  if (!compile_ok) {
    glGetProgramInfoLog(m_program, len, nullptr, err);
    lg::error("Failed to link shader {}:\n{}", shader_name.c_str(), err);
    m_is_okay = false;
    return;
  }

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

  glDeleteShader(m_vert_shader);
  glDeleteShader(m_frag_shader);
  if (has_tess) {
    glDeleteShader(m_tesc_shader);
    glDeleteShader(m_tese_shader);
  }
  m_is_okay = true;
}

void Shader::activate() const {
  ASSERT(m_is_okay);
  glUseProgram(m_program);
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
  // Grecharged-ambient-occlusion: SSAO/HBAO/GTAO estimators + bilateral blur + composite.
  at(ShaderId::AO_SSAO) = {"ao_ssao", version};
  at(ShaderId::AO_HBAO) = {"ao_hbao", version};
  at(ShaderId::AO_GTAO) = {"ao_gtao", version};
  at(ShaderId::AO_BLUR) = {"ao_blur", version};
  at(ShaderId::AO_COMPOSITE) = {"ao_composite", version};
#ifdef OG_FEAT_PBR
  at(ShaderId::PBR_DEPTH) = {"pbr_depth", version};
  // REOPEN #3 TESSELLATION: only build the tess program on a tess-capable context; on a
  // context without the stages the 4-arg ctor fails soft (m_is_okay == false) and the
  // routing in TFragment never selects it. vert/tesc/tese share the tfrag3_tess group;
  // the fragment source is the plain tfrag3.frag (reused unchanged).
  at(ShaderId::TFRAG3_TESS) = {"tfrag3_tess", "tfrag3_tess", "tfrag3_tess", "tfrag3", version};
  // Record the FINAL usability: the tess program is only usable when the context advertises
  // tessellation AND the program actually built+linked. Last build wins if this runs per-Display.
  s_tfrag3_tess_program_ok =
      gl_context_supports_tessellation() && at(ShaderId::TFRAG3_TESS).okay();
#endif

#ifdef __ANDROID__
  // A35: name every failing shader instead of dying on the first one — a
  // device-side compile failure needs the full list to be fixable in one
  // cycle. Renderers whose shaders failed will still loudly assert at
  // activate() if they are ever used.
  int failed = 0;
  for (int i = 0; i < (int)ShaderId::MAX_SHADERS; ++i) {
#ifdef OG_FEAT_PBR
    // REOPEN #3: the tess program may legitimately be soft-disabled on a GLES < 3.2 context.
    if (i == (int)ShaderId::TFRAG3_TESS && !gl_context_supports_tessellation()) {
      continue;
    }
#endif
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
#ifdef OG_FEAT_PBR
    // REOPEN #3 TESSELLATION: the tess program is allowed to fail soft on a context without
    // tessellation support (e.g. GL < 4.0). It is only ever selected when
    // gl_context_supports_tessellation() is true, so a soft-failed tess program is benign.
    if (i == (int)ShaderId::TFRAG3_TESS) {
      continue;
    }
#endif
    ASSERT_MSG(m_shaders[i].okay(), "error compiling shader");
  }
#endif
}
