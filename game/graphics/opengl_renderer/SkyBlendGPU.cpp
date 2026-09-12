#include "SkyBlendGPU.h"

#include <cstdio>

#include "common/log/log.h"

#include "game/graphics/opengl_renderer/AdgifHandler.h"
#include "game/graphics/opengl_renderer/hdr.h"

#include "fmt/format.h"

SkyBlendGPU::SkyBlendGPU() {
  // generate textures for sky blending
  glGenFramebuffers(2, m_framebuffers);
  glGenTextures(2, m_textures);

  GLint old_framebuffer;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &old_framebuffer);

  // setup the framebuffers
  for (int i = 0; i < 2; i++) {
    glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffers[i]);
    glBindTexture(GL_TEXTURE_2D, m_textures[i]);
#ifdef __ANDROID__
    // GLES rejects GL_UNSIGNED_INT_8_8_8_8_REV — the attachment gets no
    // storage and the status check below fails ("SkyTextureHandler setup
    // failed.", every A35-A40 boot log). Byte-identical on little-endian —
    // see LoaderStages.cpp (A41).
    const GLenum legacy_type = GL_UNSIGNED_BYTE;
#else
    const GLenum legacy_type = GL_UNSIGNED_INT_8_8_8_8_REV;
#endif
    // hdr-source-range (chantier A) : le ciel est ACCUMULE (`glBlendFunc(GL_ONE, GL_ONE)` plus
    // bas) ; sur une cible normalisee la somme de ses couches sature a 1,0 et la richesse que
    // l'owner reclame n'existe jamais. On demande le flottant, on RELIT ce que le pilote a
    // accepte, et c'est ce format-la — pas celui qu'on voulait — qui entre au recensement.
    hdr::StageFormat sf = hdr::source_stage_format(GL_RGBA8, GL_RGBA, legacy_type);
    glTexImage2D(GL_TEXTURE_2D, 0, sf.internal_fmt, m_sizes[i], m_sizes[i], 0, sf.ext_fmt, sf.type,
                 0);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glFramebufferTexture(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, m_textures[i], 0);
    GLenum draw_buffers[1] = {GL_COLOR_ATTACHMENT0};
    glDrawBuffers(1, draw_buffers);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
      if (sf.is_float) {
        // Le pilote a REFUSE le flottant : on retombe sur le format historique au lieu de
        // laisser une cible incomplete, et le repli est COMPTE. Un ecran noir se lirait comme
        // un defaut du chantier ; un repli compte se lit pour ce qu'il est.
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, m_sizes[i], m_sizes[i], 0, GL_RGBA, legacy_type,
                     0);
        glFramebufferTexture(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, m_textures[i], 0);
        sf.internal_fmt = GL_RGBA8;
        sf.is_float = false;
        hdr::note_stage_fallback(fmt::format("sky-blend-gpu-{}", i).c_str());
      }
      if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        lg::error("SkyTextureHandler setup failed.");
      }
    }
    // hdr-plan/hdr-source-range : recensement pris au SITE DE CREATION, avec le format
    // EFFECTIF. Une liste ecrite a la main mentirait des le premier repli.
    hdr::note_scene_stage_indexed("sky-blend-gpu", i, sf.internal_fmt, m_sizes[i], m_sizes[i]);
    // hdr-sky-gpu-alpha : le format EFFECTIF de l'etage, celui qu'on vient de faire accepter.
    // Les tampons `prev` et le temoin doivent etre BATIS DANS CE FORMAT-LA, pas dans celui
    // qu'on avait demande : un blit entre deux formats differents n'est pas une copie.
    m_stage[i].internal_fmt = sf.internal_fmt;
    m_stage[i].ext_fmt = sf.ext_fmt;
    m_stage[i].type = sf.is_float ? GL_HALF_FLOAT : legacy_type;
    m_stage[i].is_float = sf.is_float;
  }
  // L'OPERANDE DE L'ADDITION. Depuis hdr-sky-gpu-alpha l'accumulation des couches n'est plus
  // faite par le melange a fonction fixe mais par `sky_blend.frag`, qui a besoin de l'etat de la
  // cible AVANT le tirage. Ce tampon fait donc partie de l'ETAT LIVRE, pas de l'instrument.
  for (int i = 0; i < 2; i++) {
    if (!make_target(i, &m_prev[i])) {
      lg::error("SkyBlendGPU: tampon `prev` {} incomplet.", i);
    }
  }
  glBindFramebuffer(GL_FRAMEBUFFER, 0);

  glGenBuffers(1, &m_gl_vertex_buffer);
  glBindBuffer(GL_ARRAY_BUFFER, m_gl_vertex_buffer);
  glBufferData(GL_ARRAY_BUFFER, sizeof(Vertex) * 6, nullptr, GL_DYNAMIC_DRAW);
  glBindBuffer(GL_ARRAY_BUFFER, old_framebuffer);

  // we only draw squares
  m_vertex_data[0].x = 0;
  m_vertex_data[0].y = 0;

  m_vertex_data[1].x = 1;
  m_vertex_data[1].y = 0;

  m_vertex_data[2].x = 0;
  m_vertex_data[2].y = 1;

  m_vertex_data[3].x = 1;
  m_vertex_data[3].y = 0;

  m_vertex_data[4].x = 0;
  m_vertex_data[4].y = 1;

  m_vertex_data[5].x = 1;
  m_vertex_data[5].y = 1;
}

SkyBlendGPU::~SkyBlendGPU() {
  for (int i = 0; i < 2; i++) {
    destroy_target(&m_prev[i]);
    destroy_target(&m_witness[i]);
    destroy_target(&m_witness_prev[i]);
    destroy_target(&m_seed[i]);
    destroy_target(&m_seed_prev[i]);
  }
  glDeleteFramebuffers(2, m_framebuffers);
  glDeleteBuffers(1, &m_gl_vertex_buffer);
#ifdef __ANDROID__
  fprintf(stderr, "F1E-DELTEX site=skygpu tex=%u %u\n", (unsigned)m_textures[0],
          (unsigned)m_textures[1]);
#endif
  glDeleteTextures(2, m_textures);
}

void SkyBlendGPU::init_textures(TexturePool& tex_pool, GameVersion version) {
  for (int i = 0; i < 2; i++) {
    TextureInput in;
    in.gpu_texture = m_textures[i];
    in.w = m_sizes[i];
    in.h = in.w;
    in.debug_name = fmt::format("PC-SKY-GPU-{}", i);
    in.id = tex_pool.allocate_pc_port_texture(version);
    u32 tbp = SKY_TEXTURE_VRAM_ADDRS[i];
    m_tex_info[i] = {tex_pool.give_texture_and_load_to_vram(in, tbp), tbp};
  }
}

// ============================ hdr-sky-gpu-alpha — les tampons ================================
// Une cible de la taille d'un etage, dans le format que le pilote a ACCEPTE pour cet etage.
// Le blit qui alimente `prev` est une copie : deux formats differents en feraient une
// conversion, et l'accumulation ne serait plus celle qu'on croit mesurer.
bool SkyBlendGPU::make_target(int idx, Target* out) {
  GLint old_framebuffer;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &old_framebuffer);
  glGenFramebuffers(1, &out->fbo);
  glGenTextures(1, &out->tex);
  glBindFramebuffer(GL_FRAMEBUFFER, out->fbo);
  glBindTexture(GL_TEXTURE_2D, out->tex);
  glTexImage2D(GL_TEXTURE_2D, 0, m_stage[idx].internal_fmt, m_sizes[idx], m_sizes[idx], 0,
               m_stage[idx].ext_fmt, m_stage[idx].type, 0);
  // GL_NEAREST, obligatoire : `sky_blend.frag` relit ce tampon TEXEL POUR TEXEL (le quad couvre
  // la cible exactement une fois). Un filtrage lineaire melangerait les voisins a chaque couche.
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glFramebufferTexture(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, out->tex, 0);
  GLenum draw_buffers[1] = {GL_COLOR_ATTACHMENT0};
  glDrawBuffers(1, draw_buffers);
  const bool ok = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
  if (ok) {
    float clear[4] = {0, 0, 0, 0};
    glClearBufferfv(GL_COLOR, 0, clear);
  }
  glBindFramebuffer(GL_FRAMEBUFFER, old_framebuffer);
  return ok;
}

void SkyBlendGPU::destroy_target(Target* t) {
  if (t->fbo) {
    glDeleteFramebuffers(1, &t->fbo);
    t->fbo = 0;
  }
  if (t->tex) {
    glDeleteTextures(1, &t->tex);
    t->tex = 0;
  }
}

void SkyBlendGPU::accumulate(GLuint dst_fbo,
                             const Target& prev,
                             int size,
                             GLint loc_limit,
                             float limit) {
  glBindFramebuffer(GL_READ_FRAMEBUFFER, dst_fbo);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, prev.fbo);
  glBlitFramebuffer(0, 0, size, size, 0, 0, size, size, GL_COLOR_BUFFER_BIT, GL_NEAREST);
  glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
  glViewport(0, 0, size, size);
  if (loc_limit >= 0) {
    glUniform1f(loc_limit, limit);
  }
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, prev.tex);
  glActiveTexture(GL_TEXTURE0);
  glDrawArrays(GL_TRIANGLES, 0, 6);
}

// LA MESURE EST PRISE SUR CE QUI EST DESSINE, jamais sur les couches d'entree recomposees a
// cote : on relit la cible. `components` compte les composantes alpha RELUES — c'est le
// denominateur sans lequel un maximum ne se lit pas.
void SkyBlendGPU::readback_into(const Target& t, int size, AlphaScan* st) {
  if (!t.fbo) {
    return;
  }
  const size_t n = (size_t)size * (size_t)size * 4u;
  if (m_readback.size() < n) {
    m_readback.resize(n);
  }
  glBindFramebuffer(GL_READ_FRAMEBUFFER, t.fbo);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  glReadPixels(0, 0, size, size, GL_RGBA, GL_FLOAT, m_readback.data());
  for (size_t i = 0; i < n; i += 4) {
    for (int c = 0; c < 3; c++) {
      if (m_readback[i + c] > st->rgb_max) {
        st->rgb_max = m_readback[i + c];
      }
    }
    const float a = m_readback[i + 3];
    st->components++;
    if (a > 1.f) {
      st->alpha_over++;
    }
    if (a > st->alpha_max) {
      st->alpha_max = a;
    }
  }
}

namespace {
constexpr int kSeedLayers = 8;
uint64_t x1000(float v) {
  return v <= 0.f ? 0u : (uint64_t)(v * 1000.f + 0.5f);
}
// La borne du temoin : FINIE (un uniforme infini n'est pas portable) et hors de portee du
// demi-flottant, dont le maximum est 65504. `min(x, kNoLimit)` ne borne donc rien.
constexpr float kNoLimit = 1.0e30f;
}  // namespace

// LE CONTROLE SEME (voir SkyBlendGPU.h). Le jeu partage 128 d'intensite entre les couches du
// ciel : leur somme d'alpha vaut au plus l'alpha d'UNE couche, et la borne posee par cet item
// n'est jamais touchee par les donnees reelles. Un `alpha_max <= 1,0` serait donc vert quoi
// qu'on ait ecrit dans le shader. On empile ici huit fois la MEME couche a pleine intensite dans
// deux cibles jetables — l'une bornee a 1,0, l'autre libre — et on relit les deux. Le bras LIBRE
// dit que la population est atteignable ; le bras BORNE dit que la borne borne. Aucune cible du
// jeu n'est touchee, et rien de tout ceci n'existe hors de la mesure de cet item.
void SkyBlendGPU::run_seed_control(SharedRenderState* render_state, GLuint src_tex) {
  const int size = m_sizes[0];
  render_state->shaders[ShaderId::SKY_BLEND].activate();
  const GLuint prog = (GLuint)render_state->shaders[ShaderId::SKY_BLEND].id();
  const GLint loc_prev = glGetUniformLocation(prog, "tex_prev");
  const GLint loc_limit = glGetUniformLocation(prog, "alpha_limit");
  if (loc_prev < 0 || loc_limit < 0) {
    return;  // les localisations manquent : `m_uniform_ok` le dit deja, on n'invente rien
  }
  glUniform1i(loc_prev, 1);

  // pleine intensite sur chaque couche : c'est le point du controle.
  for (auto& vert : m_vertex_data) {
    vert.intensity = 1.f;
  }
  glBindBuffer(GL_ARRAY_BUFFER, m_gl_vertex_buffer);
  glBufferData(GL_ARRAY_BUFFER, sizeof(Vertex) * 6, m_vertex_data, GL_STREAM_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 3, GL_FLOAT, GL_TRUE, 0, 0);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);

  float clear[4] = {0, 0, 0, 0};
  for (int arm = 0; arm < 2; arm++) {
    glBindFramebuffer(GL_FRAMEBUFFER, m_seed[arm].fbo);
    glClearBufferfv(GL_COLOR, 0, clear);
  }
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, src_tex);
  for (int k = 0; k < kSeedLayers; k++) {
    accumulate(m_seed[0].fbo, m_seed_prev[0], size, loc_limit, 1.f);
    accumulate(m_seed[1].fbo, m_seed_prev[1], size, loc_limit, kNoLimit);
  }
  AlphaScan clamped, free_arm;
  readback_into(m_seed[0], size, &clamped);
  readback_into(m_seed[1], size, &free_arm);
  m_seed_clamped_x1000 = x1000(clamped.alpha_max);
  m_seed_free_x1000 = x1000(free_arm.alpha_max);
}

SkyBlendStats SkyBlendGPU::do_sky_blends(DmaFollower& dma,
                                         SharedRenderState* render_state,
                                         ScopedProfilerNode& prof) {
  SkyBlendStats stats;
  // hdr-sky-gpu-alpha : le temoin est bati au premier appel MESURE, jamais dans le constructeur.
  // Hors mesure il n'existe pas : il ne coute rien a l'owner, et un echec de sa construction ne
  // peut pas empecher le ciel de se dessiner (`m_witness_failed` le dit et la preuve le publie).
  const bool measuring = hdr::sky_gpu_alpha_measuring();
  if (measuring && !m_witness_ready && !m_witness_failed) {
    m_witness_ready = true;
    for (int i = 0; i < 2; i++) {
      if (!make_target(i, &m_witness[i]) || !make_target(i, &m_witness_prev[i]) ||
          !make_target(0, &m_seed[i]) || !make_target(0, &m_seed_prev[i])) {
        m_witness_ready = false;
        m_witness_failed = true;
      }
    }
  }
  bool touched[2] = {false, false};
  GLuint seed_src = 0;  // la derniere couche vue : la matiere du controle seme

  GLuint vao;
  glGenVertexArrays(1, &vao);
  glBindVertexArray(vao);

  GLint old_viewport[4];
  glGetIntegerv(GL_VIEWPORT, old_viewport);

  GLint old_framebuffer;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &old_framebuffer);

  while (dma.current_tag().qwc == 6) {
    // assuming that the vif and gif-tag is correct
    auto setup_data = dma.read_and_advance();

    // first is an adgif
    AdgifHelper adgif(setup_data.data + 16);
    ASSERT(adgif.is_normal_adgif());
    ASSERT(adgif.alpha().data == 0x8000000068);  // Cs + Cd

    // next is the actual draw
    auto draw_data = dma.read_and_advance();
    ASSERT(draw_data.size_bytes == 6 * 16);

    GifTag draw_or_blend_tag(draw_data.data);

    // the first draw overwrites the previous frame's draw by disabling alpha blend (ABE = 0)
    bool is_first_draw = !GsPrim(draw_or_blend_tag.prim()).abe();

    // here's we're relying on the format of the drawing to get the alpha/offset.
    u32 coord;
    u32 intensity;
    memcpy(&coord, draw_data.data + (5 * 16), 4);
    memcpy(&intensity, draw_data.data + 16, 4);

    // we didn't parse the render-to-texture setup earlier, so we need a way to tell sky from
    // clouds. we can look at the drawing coordinates to tell - the sky is smaller than the clouds.
    int buffer_idx = 0;
    if (coord == 0x200) {
      // sky
      buffer_idx = 0;
    } else if (coord == 0x400) {
      buffer_idx = 1;
    } else {
      ASSERT(false);  // bad data
    }

    // look up the source texture
    auto tex = render_state->texture_pool->lookup(adgif.tex0().tbp0());
    ASSERT(tex);

    // setup for rendering!
    const int size = m_sizes[buffer_idx];
    touched[buffer_idx] = true;
    glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffers[buffer_idx]);
    glViewport(0, 0, size, size);
    glFramebufferTexture(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, m_textures[buffer_idx], 0);
    render_state->shaders[ShaderId::SKY_BLEND].activate();

    // hdr-sky-gpu-alpha : LES DEUX LOCALISATIONS, TESTEES. Un uniforme que le programme lie ne
    // LIT pas est retire par le compilateur GLSL et rend -1 ; un `glUniform1i` sur -1 est ignore
    // en silence et l'echantillonneur `tex_prev` resterait sur l'unite 0 — donc sur la texture
    // SOURCE. Le resultat serait faux sans une seule erreur GL. On le teste, et on le publie.
    const GLuint prog = (GLuint)render_state->shaders[ShaderId::SKY_BLEND].id();
    const GLint loc_prev = glGetUniformLocation(prog, "tex_prev");
    const GLint loc_limit = glGetUniformLocation(prog, "alpha_limit");
    m_uniform_ok = (loc_prev >= 0 && loc_limit >= 0) ? 1 : 0;
    if (m_uniform_ok) {
      glUniform1i(loc_prev, 1);
    }

    // if the first is set, it disables alpha. we can just clear here, so it's easier to find
    // in renderdoc.
    if (is_first_draw) {
      float clear[4] = {0, 0, 0, 0};
      glClearBufferfv(GL_COLOR, 0, clear);
      if (m_witness_ready) {
        glBindFramebuffer(GL_FRAMEBUFFER, m_witness[buffer_idx].fbo);
        glClearBufferfv(GL_COLOR, 0, clear);
        glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffers[buffer_idx]);
      }
    }

    // intensities should be 0-128 (maybe higher is okay, but I don't see how this could be
    // generated with the GOAL code.)
    ASSERT(intensity <= 128);

    // todo - could do this on the GPU, but probably not worth it for <20 triangles...
    float intensity_float = intensity / 128.f;
    for (auto& vert : m_vertex_data) {
      vert.intensity = intensity_float;
    }

    glDisable(GL_DEPTH_TEST);

    // hdr-sky-gpu-alpha : LE MELANGE A FONCTION FIXE EST ETEINT.
    // Il etait `glBlendFunc(GL_ONE, GL_ONE)`. Sur la cible 8 bits il saturait tout a 1,0 ;
    // depuis que `hdr-source-range` l'a ouverte en flottant, le RGB a le droit de depasser — et
    // l'ALPHA l'a pris aussi, alors qu'il est un POIDS DE MELANGE consomme par le DirectRenderer
    // du ciel. Aucun facteur a fonction fixe ne borne une SOMME sans changer sa valeur la ou elle
    // ne saturait pas (`GL_SRC_ALPHA_SATURATE` rend 1 sur le canal alpha : il ne borne rien).
    // L'addition passe donc dans `sky_blend.frag`, qui lit l'etat d'AVANT dans `tex_prev` et
    // borne le POIDS LUI-MEME a `alpha_limit`. Le RGB reste sans borne : la plage ouverte par le
    // chantier A n'est pas reprise, et la relecture des deux cotes le montre.
    glDisable(GL_BLEND);

    // setup draw data
    glBindBuffer(GL_ARRAY_BUFFER, m_gl_vertex_buffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(Vertex) * 6, m_vertex_data, GL_STREAM_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0,         // location 0 in the shader
                          3,         // 3 floats per vert
                          GL_FLOAT,  // floats
                          GL_TRUE,   // normalized, ignored,
                          0,         // tightly packed
                          0

    );
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, *tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    // L'ETAT LIVRE : le poids de melange est borne a 1,0 A SA SOURCE.
    accumulate(m_framebuffers[buffer_idx], m_prev[buffer_idx], size, loc_limit, 1.f);
    // LE TEMOIN (instrument seul) : la MEME accumulation, sans borne — la valeur d'AVANT, tiree
    // sur les MEMES couches, dans la MEME course. Sans lui, un `alpha_max <= 1,0` ne dirait pas
    // si le depassement existait.
    if (m_witness_ready) {
      accumulate(m_witness[buffer_idx].fbo, m_witness_prev[buffer_idx], size, loc_limit, kNoLimit);
      glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffers[buffer_idx]);
    }
    seed_src = *tex;

    // 1 draw, 2 triangles
    prof.add_draw_call(1);
    prof.add_tri(2);

    render_state->texture_pool->move_existing_to_vram(m_tex_info[buffer_idx].tex,
                                                      m_tex_info[buffer_idx].tbp);

    if (buffer_idx == 0) {
      if (is_first_draw) {
        stats.sky_draws++;
      } else {
        stats.sky_blends++;
      }
    } else {
      if (is_first_draw) {
        stats.cloud_draws++;
      } else {
        stats.cloud_blends++;
      }
    }
  }

  // ---- hdr-sky-gpu-alpha : LE CONTROLE SEME, puis la relecture. Une fois sur quatre — la relecture synchronise le
  // pilote, et le ciel evolue a la vitesse du cycle jour/nuit, pas a celle d'une image.
  if (measuring && (touched[0] || touched[1])) {
    m_calls++;
    if ((m_calls % 4) == 1) {
      AlphaScan now, before;
      for (int i = 0; i < 2; i++) {
        if (!touched[i]) {
          continue;
        }
        const Target live{m_framebuffers[i], m_textures[i]};
        readback_into(live, m_sizes[i], &now);
        if (m_witness_ready) {
          readback_into(m_witness[i], m_sizes[i], &before);
        }
      }
      if (m_witness_ready && seed_src) {
        run_seed_control(render_state, seed_src);
      }
      if (now.components) {
        hdr::note_sky_gpu_alpha(now.components, now.alpha_over, x1000(now.alpha_max),
                                x1000(now.rgb_max), before.alpha_over, x1000(before.alpha_max),
                                x1000(before.rgb_max), m_stage[0].is_float && m_stage[1].is_float,
                                m_uniform_ok, m_witness_ready, m_seed_clamped_x1000,
                                m_seed_free_x1000, kSeedLayers);
      }
    }
  }

  glViewport(old_viewport[0], old_viewport[1], old_viewport[2], old_viewport[3]);
  glBindFramebuffer(GL_FRAMEBUFFER, old_framebuffer);
  glBindVertexArray(0);
  glDeleteVertexArrays(1, &vao);

  return stats;
}
