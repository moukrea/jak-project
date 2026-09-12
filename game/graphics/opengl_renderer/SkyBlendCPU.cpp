#include "SkyBlendCPU.h"

#include <cmath>
#include <cstdio>

#include "common/util/os.h"
#include "common/util/simd_util.h"

#include "game/graphics/opengl_renderer/AdgifHandler.h"
#include "game/graphics/opengl_renderer/hdr.h"

#include "fmt/format.h"

#ifdef __ANDROID__
// GLES rejects GL_UNSIGNED_INT_8_8_8_8_REV (incomplete texture → samples
// black). Byte-identical on little-endian — see LoaderStages.cpp (A41).
constexpr GLenum kSkyRgbaTexType = GL_UNSIGNED_BYTE;
#else
constexpr GLenum kSkyRgbaTexType = GL_UNSIGNED_INT_8_8_8_8_REV;
#endif

SkyBlendCPU::SkyBlendCPU() {
  for (int i = 0; i < 2; i++) {
    glGenTextures(1, &m_textures[i].gl);
    glBindTexture(GL_TEXTURE_2D, m_textures[i].gl);
    // hdr-source-range (chantier A). La cible du ciel CPU est un TELEVERSEMENT, pas une cible de
    // rendu : c'est le format du conteneur qui decide si la somme des couches a le droit de
    // depasser 1,0. On le demande flottant et on recense le format EFFECTIF.
    const hdr::StageFormat sf = hdr::source_stage_format(GL_RGBA8, GL_RGBA, kSkyRgbaTexType);
    m_float_target[i] = sf.is_float;
    glTexImage2D(GL_TEXTURE_2D, 0, sf.internal_fmt, m_sizes[i], m_sizes[i], 0, sf.ext_fmt,
                 sf.is_float ? GL_FLOAT : sf.type, 0);
    if (sf.is_float && glGetError() != GL_NO_ERROR) {
      // Le pilote a refuse : on retombe sur le format historique, et le repli est COMPTE.
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, m_sizes[i], m_sizes[i], 0, GL_RGBA, kSkyRgbaTexType,
                   0);
      m_float_target[i] = false;
      hdr::note_stage_fallback(fmt::format("sky-blend-cpu-{}", i).c_str());
    }
    hdr::note_scene_stage_indexed("sky-blend-cpu", i,
                                  m_float_target[i] ? GL_RGBA16F : GL_RGBA8, m_sizes[i],
                                  m_sizes[i]);
    m_texture_data[i].resize(4 * m_sizes[i] * m_sizes[i]);
    m_float_data[i].assign(4 * m_sizes[i] * m_sizes[i], 0.f);
  }
}

SkyBlendCPU::~SkyBlendCPU() {
  for (auto& tex : m_textures) {
#ifdef __ANDROID__
    fprintf(stderr, "F1E-DELTEX site=skycpu tex=%u\n", (unsigned)tex.gl);
#endif
    glDeleteTextures(1, &tex.gl);
  }
}

void blend_sky_initial_fast(u8 intensity, u8* out, const u8* in, u32 size) {
#ifndef __arm64__
  if (get_cpu_info().has_avx2) {
#ifdef __AVX2__
    __m256i intensity_vec = _mm256_set1_epi16(intensity);
    for (u32 i = 0; i < size / 16; i++) {
      __m128i tex_data8 = _mm_loadu_si128((const __m128i*)(in + (i * 16)));
      __m256i tex_data16 = _mm256_cvtepu8_epi16(tex_data8);
      tex_data16 = _mm256_mullo_epi16(tex_data16, intensity_vec);
      tex_data16 = _mm256_srli_epi16(tex_data16, 7);
      auto hi = _mm256_extracti128_si256(tex_data16, 1);
      auto result = _mm_packus_epi16(_mm256_castsi256_si128(tex_data16), hi);
      _mm_storeu_si128((__m128i*)(out + (i * 16)), result);
    }
#else
    ASSERT(false);
#endif
  } else {
    __m128i intensity_vec = _mm_set1_epi16(intensity);
    for (u32 i = 0; i < size / 8; i++) {
      __m128i tex_data8 = _mm_loadu_si64((const __m128i*)(in + (i * 8)));
      __m128i tex_data16 = _mm_cvtepu8_epi16(tex_data8);
      tex_data16 = _mm_mullo_epi16(tex_data16, intensity_vec);
      tex_data16 = _mm_srli_epi16(tex_data16, 7);
      auto result = _mm_packus_epi16(tex_data16, tex_data16);
      _mm_storel_epi64((__m128i*)(out + (i * 8)), result);
    }
  }
#endif
}

void blend_sky_fast(u8 intensity, u8* out, const u8* in, u32 size) {
#ifndef __arm64__
  if (get_cpu_info().has_avx2) {
#ifdef __AVX2__
    __m256i intensity_vec = _mm256_set1_epi16(intensity);
    __m256i max_intensity = _mm256_set1_epi16(255);
    for (u32 i = 0; i < size / 16; i++) {
      __m128i tex_data8 = _mm_loadu_si128((const __m128i*)(in + (i * 16)));
      __m128i out_val = _mm_loadu_si128((const __m128i*)(out + (i * 16)));
      __m256i tex_data16 = _mm256_cvtepu8_epi16(tex_data8);
      tex_data16 = _mm256_mullo_epi16(tex_data16, intensity_vec);
      tex_data16 = _mm256_srli_epi16(tex_data16, 7);
      tex_data16 = _mm256_min_epi16(max_intensity, tex_data16);
      auto hi = _mm256_extracti128_si256(tex_data16, 1);
      auto result = _mm_packus_epi16(_mm256_castsi256_si128(tex_data16), hi);
      out_val = _mm_adds_epu8(out_val, result);
      _mm_storeu_si128((__m128i*)(out + (i * 16)), out_val);
    }
#else
    ASSERT(false);
#endif
  } else {
    __m128i intensity_vec = _mm_set1_epi16(intensity);
    __m128i max_intensity = _mm_set1_epi16(255);
    for (u32 i = 0; i < size / 8; i++) {
      __m128i tex_data8 = _mm_loadu_si64((const __m128i*)(in + (i * 8)));
      __m128i out_val = _mm_loadu_si64((const __m128i*)(out + (i * 8)));
      __m128i tex_data16 = _mm_cvtepu8_epi16(tex_data8);
      tex_data16 = _mm_mullo_epi16(tex_data16, intensity_vec);
      tex_data16 = _mm_srli_epi16(tex_data16, 7);
      tex_data16 = _mm_min_epi16(max_intensity, tex_data16);
      auto result = _mm_packus_epi16(tex_data16, tex_data16);
      out_val = _mm_adds_epu8(out_val, result);
      _mm_storel_epi64((__m128i*)(out + (i * 8)), out_val);
    }
  }
#endif
}

// ======================== hdr-source-range : le melange SANS BORNE ===========================
// Miroir scalaire EXACT de `blend_sky_fast`, a trois differences pres, et chacune est le
// chantier :
//   * l'accumulateur est flottant en unites de blanc (1,0 = l'ancien 255) ;
//   * la borne a 255 de CHAQUE couche (`_mm_min_epi16`) et la saturation de la SOMME
//     (`_mm_adds_epu8`) disparaissent : c'est exactement la plage que le 8 bits detruisait ;
//   * le decalage entier `>> 7` devient une division, donc la troncature par couche disparait
//     aussi — c'est du lisse en plus, pas de la plage.
// L'ALPHA, lui, reste borne a 1,0 : c'est un POIDS DE MELANGE consomme par le DirectRenderer du
// ciel, pas une couleur. Le laisser filer changerait la composition, pas sa richesse.
// La valeur de retour est le nombre de COMPOSANTES DE COULEUR dont la somme depasse 1,0 : la
// mesure est prise LA OU L'ECRETAGE ETAIT, pas relue plus tard sur une image deja composee.
struct SkyWideStats {
  uint64_t over = 0;      // composantes dont la somme NON BORNEE depasse 1,0
  uint64_t differs = 0;   // ... que le u8 ne pouvait pas representer (arrondi different)
  float max_v = 0.f;      // la plus grande somme vue
  float max_diff = 0.f;   // le plus grand ecart au u8, en pas de 1/255
};

// Le chemin 8 bits, refait SCALAIREMENT a cote du flottant, dans la meme boucle. Ce n'est pas
// une redondance : c'est le TEMOIN D'EFFET. Sans lui, un `overbright=0` se lirait « rien n'a
// change » alors que ce que le u8 detruisait ici n'est pas de la plage mais de la PRECISION —
// `>> 7` tronque chaque couche, et l'accumulateur n'a que 256 paliers. `differs` compte les
// composantes ou le flottant et le u8 ne tombent pas sur le meme palier : c'est exactement
// l'information que le conteneur 8 bits perdait, et elle se compte, elle ne se raconte pas.
static void blend_sky_initial_wide(u8 intensity,
                                   float* out,
                                   u8* legacy,
                                   const u8* in,
                                   u32 size,
                                   SkyWideStats* st) {
  const float k = (float)intensity / (128.f * 255.f);
  for (u32 i = 0; i < size; i++) {
    const u32 lv = ((u32)in[i] * (u32)intensity) >> 7;
    const u8 lu8 = (u8)(lv > 255u ? 255u : lv);
    legacy[i] = lu8;
    float v = (float)in[i] * k;
    if ((i & 3u) == 3u) {
      if (v > 1.f) {
        v = 1.f;
      }
    } else {
      if (v > 1.f) {
        st->over++;
      }
      if (v > st->max_v) {
        st->max_v = v;
      }
      const float d = std::fabs(v * 255.f - (float)lu8);
      if ((int)std::lround(v * 255.f) != (int)lu8) {
        st->differs++;
      }
      if (d > st->max_diff) {
        st->max_diff = d;
      }
    }
    out[i] = v;
  }
}

static void blend_sky_wide(u8 intensity,
                           float* out,
                           u8* legacy,
                           const u8* in,
                           u32 size,
                           SkyWideStats* st) {
  const float k = (float)intensity / (128.f * 255.f);
  for (u32 i = 0; i < size; i++) {
    const u32 lv = ((u32)in[i] * (u32)intensity) >> 7;
    const u32 layer = lv > 255u ? 255u : lv;          // `_mm_min_epi16(255, ...)`
    const u32 sum = (u32)legacy[i] + layer;
    const u8 lu8 = (u8)(sum > 255u ? 255u : sum);     // `_mm_adds_epu8`
    legacy[i] = lu8;
    float v = out[i] + (float)in[i] * k;
    if ((i & 3u) == 3u) {
      if (v > 1.f) {
        v = 1.f;
      }
    } else {
      if (v > 1.f) {
        st->over++;
      }
      if (v > st->max_v) {
        st->max_v = v;
      }
      const float d = std::fabs(v * 255.f - (float)lu8);
      if ((int)std::lround(v * 255.f) != (int)lu8) {
        st->differs++;
      }
      if (d > st->max_diff) {
        st->max_diff = d;
      }
    }
    out[i] = v;
  }
}

SkyBlendStats SkyBlendCPU::do_sky_blends(DmaFollower& dma,
                                         SharedRenderState* render_state,
                                         ScopedProfilerNode& /*prof*/) {
  SkyBlendStats stats;

  while (dma.current_tag().qwc == 6) {
    // assuming that the vif and gif-tag is correct
    auto setup_data = dma.read_and_advance();

    // first is an adgif
    AdgifHelper adgif(setup_data.data + 16);
    ASSERT(adgif.is_normal_adgif());

    // next is the actual draw
    auto draw_data = dma.read_and_advance();
    ASSERT(draw_data.size_bytes == 6 * 16);

    // sky-gpu-path-robustness : LE MEME ASSERT NU VIVAIT ICI, sur le chemin de L'APPAREIL — ou
    // un ASSERT est un SIGABRT dont la pile ne nomme pas le ciel. Meme repli, meme recensement,
    // compteur separe : les deux chemins doivent pouvoir se lire l'un sans l'autre.
    if (!hdr::sky_blend_mode_supported(false, adgif.alpha().data)) {
      continue;
    }

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
    auto tex = render_state->texture_pool->lookup_gpu_texture(adgif.tex0().tbp0());
    ASSERT(tex);

    // slow version
    /*
    if (is_first_draw) {
      memset(m_texture_data[buffer_idx].data(), 0, m_texture_data[buffer_idx].size());
    }

    // intensities should be 0-128 (maybe higher is okay, but I don't see how this could be
    // generated with the GOAL code.)
    ASSERT(intensity <= 128);
    ASSERT(m_texture_data[buffer_idx].size() == tex->data.size());
    for (size_t i = 0; i < m_texture_data[buffer_idx].size(); i++) {
      u32 val = tex->data[i] * intensity;
      val >>= 7;
      m_texture_data[buffer_idx][i] += val;
    }
     */
    if (tex->get_data_ptr()) {
      if (m_texture_data[buffer_idx].size() == tex->data_size()) {
        if (m_float_target[buffer_idx]) {
          const u32 n = (u32)m_texture_data[buffer_idx].size();
          SkyWideStats st;
          if (is_first_draw) {
            blend_sky_initial_wide(intensity, m_float_data[buffer_idx].data(),
                                   m_texture_data[buffer_idx].data(), tex->get_data_ptr(), n, &st);
          } else {
            blend_sky_wide(intensity, m_float_data[buffer_idx].data(),
                           m_texture_data[buffer_idx].data(), tex->get_data_ptr(), n, &st);
          }
          // 3 composantes de couleur sur 4 : le denominateur exclut l'alpha, qui reste borne.
          hdr::note_sky_wide(st.over, st.differs, (uint64_t)n * 3u / 4u,
                             (uint64_t)(st.max_v * 1000.f + 0.5f),
                             (uint64_t)(st.max_diff * 1000.f + 0.5f));
        } else if (is_first_draw) {
          blend_sky_initial_fast(intensity, m_texture_data[buffer_idx].data(), tex->get_data_ptr(),
                                 m_texture_data[buffer_idx].size());
        } else {
          blend_sky_fast(intensity, m_texture_data[buffer_idx].data(), tex->get_data_ptr(),
                         m_texture_data[buffer_idx].size());
        }
      }

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
      glBindTexture(GL_TEXTURE_2D, m_textures[buffer_idx].gl);
      if (m_float_target[buffer_idx]) {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, m_sizes[buffer_idx], m_sizes[buffer_idx], 0,
                     GL_RGBA, GL_FLOAT, m_float_data[buffer_idx].data());
      } else {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, m_sizes[buffer_idx], m_sizes[buffer_idx], 0,
                     GL_RGBA, kSkyRgbaTexType, m_texture_data[buffer_idx].data());
      }

      render_state->texture_pool->move_existing_to_vram(m_textures[buffer_idx].tex,
                                                        m_textures[buffer_idx].tbp);
    }
  }

  return stats;
}

void SkyBlendCPU::init_textures(TexturePool& tex_pool, GameVersion version) {
  for (int i = 0; i < 2; i++) {
    // update it
    glBindTexture(GL_TEXTURE_2D, m_textures[i].gl);
    if (m_float_target[i]) {
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, m_sizes[i], m_sizes[i], 0, GL_RGBA, GL_FLOAT,
                   m_float_data[i].data());
    } else {
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, m_sizes[i], m_sizes[i], 0, GL_RGBA, kSkyRgbaTexType,
                   m_texture_data[i].data());
    }
    TextureInput in;

    in.gpu_texture = m_textures[i].gl;
    in.w = m_sizes[i];
    in.h = m_sizes[i];
    in.debug_name = fmt::format("PC-SKY-CPU-{}", i);
    in.id = tex_pool.allocate_pc_port_texture(version);
    u32 tbp = SKY_TEXTURE_VRAM_ADDRS[i];
    m_textures[i].tex = tex_pool.give_texture_and_load_to_vram(in, tbp);
    m_textures[i].tbp = tbp;
  }
}