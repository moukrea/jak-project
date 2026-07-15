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

  // Per-game template tokens, substituted at runtime on both desktop and
  // Android (the Android GLES blob keeps them verbatim — jak2 is a 416-line
  // frame, jak1 448; baking jak1 values stretched jak2 geometry vertically).
  const std::string height_scale = version == GameVersion::Jak1 ? "1.0" : "0.5";
  const std::string scissor_height = version == GameVersion::Jak1 ? "448.0" : "416.0";
  const std::string scissor_adjust = "512.0 / " + scissor_height;

  vert_src = std::regex_replace(vert_src, std::regex("HEIGHT_SCALE"), height_scale);
  vert_src = std::regex_replace(vert_src, std::regex("SCISSOR_HEIGHT"), scissor_height);
  frag_src = std::regex_replace(frag_src, std::regex("SCISSOR_HEIGHT"), scissor_height);
  vert_src = std::regex_replace(vert_src, std::regex("SCISSOR_ADJUST"), "(" + scissor_adjust + ")");

  m_vert_shader = glCreateShader(GL_VERTEX_SHADER);
  const char* src = vert_src.c_str();
  glShaderSource(m_vert_shader, 1, &src, nullptr);
  glCompileShader(m_vert_shader);

  constexpr int len = 1024;
  int compile_ok;
  char err[len];

  glGetShaderiv(m_vert_shader, GL_COMPILE_STATUS, &compile_ok);
  if (!compile_ok) {
    glGetShaderInfoLog(m_vert_shader, len, nullptr, err);
    lg::error("Failed to compile vertex shader {}:\n{}", shader_name.c_str(), err);
    m_is_okay = false;
    return;
  }

  m_frag_shader = glCreateShader(GL_FRAGMENT_SHADER);
  src = frag_src.c_str();
  glShaderSource(m_frag_shader, 1, &src, nullptr);
  glCompileShader(m_frag_shader);

  glGetShaderiv(m_frag_shader, GL_COMPILE_STATUS, &compile_ok);
  if (!compile_ok) {
    glGetShaderInfoLog(m_frag_shader, len, nullptr, err);
    lg::error("Failed to compile fragment shader {}:\n{}", shader_name.c_str(), err);
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

#ifdef __ANDROID__
  // A35: name every failing shader instead of dying on the first one — a
  // device-side compile failure needs the full list to be fixable in one
  // cycle. Renderers whose shaders failed will still loudly assert at
  // activate() if they are ever used.
  int failed = 0;
  for (auto& shader : m_shaders) {
    if (!shader.okay()) {
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
  for (auto& shader : m_shaders) {
    ASSERT_MSG(shader.okay(), "error compiling shader");
  }
#endif
}
