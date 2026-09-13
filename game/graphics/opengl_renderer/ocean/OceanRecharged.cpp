#include "OceanRecharged.h"
#include "game/system/recharged_gating.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>
#include <vector>

#include "common/goal_constants.h"
#include "common/log/log.h"
#include "fmt/core.h"

#include "game/graphics/gfx.h"
#include "game/graphics/gl_query_census.h"
#include "game/graphics/opengl_renderer/Shader.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/runtime.h"
#include "game/system/autoport_proof.h"
#include "game/system/overlap_census.h"

namespace {

constexpr const char* kItemId = "water-ocean-mesh";
AUTOPORT_FEATURE_SITE(kItemId);

// 1 metre = 4096 unites GOAL. La cellule de houle vaut 12288 unites (3 m) ; on la reprend telle
// quelle plutot que de refabriquer 3.0f * 4096.0f, pour que le pas des anneaux soit un diviseur
// EXACT de la periode et que la grille snappee ne derive jamais du modulo 32.
constexpr float kWaveCell = 12288.f;  // 3 m ; 1 m = 4096 unites GOAL
constexpr int kMaskSide = 48;             // 6 tuiles x 8 sous-cellules

// La transcription CPU de `ocean-get-height` (ocean.gc:16-35), moins le `+ start-corner.y`.
// Elle est le REFERENT de la porte : le GPU rend la meme grandeur par
// `shaders/ocean_layer_a.glsl`, apres le vrai aller-retour de texture. Les deux cotes doivent
// donner le meme chiffre au millimetre pres, et c'est la seule chose que la porte affirme.
float layer_a_cpu(const float* h, float origin_x, float origin_z, float wx, float wz) {
  const float u = (wx - origin_x) * 0.00008138021f;
  const float w = (wz - origin_z) * 0.00008138021f;
  const int iu = (int)u;
  const int iw = (int)w;
  const float fx = u - (float)iu;
  const float fz = w - (float)iw;
  const int ix0 = iu & 31;
  const int iz0 = iw & 31;
  const int ix1 = (ix0 + 1) & 31;
  const int iz1 = (iz0 + 1) & 31;
  const float h00 = h[iz0 * 32 + ix0];
  const float h10 = h[iz0 * 32 + ix1];
  const float h01 = h[iz1 * 32 + ix0];
  const float h11 = h[iz1 * 32 + ix1];
  const float row0 = h10 * fx + h00 * (1.f - fx);
  const float row1 = h11 * fx + h01 * (1.f - fx);
  return row1 * fz + row0 * (1.f - fz);
}

// Le symbole `*ocean-map*` est un `define-extern` de ocean.gc : il existe des que le noyau GOAL a
// charge ENGINE.CGO. On le resout UNE fois et on garde l'adresse du symbole ; sa VALEUR (l'adresse
// de la carte, ou 0) est relue a chaque image, parce que `update-ocean` la repose selon les
// niveaux actifs. Les objets `ocean-map` sont des donnees STATIQUES : leur adresse ne bouge
// jamais, donc rien de ce qu'on lit ne peut etre a moitie ecrit — sauf `start-corner.y`, que
// `draw-ocean` reecrit chaque image entre trois valeurs. Cet offset est commun aux DEUX cotes de
// la porte et s'y annule ; il ne decide que de la hauteur a l'ecran.
u32 read_ocean_map_ptr() {
  static bool s_tried = false;
  static u32 s_symbol = 0;
  static u32 s_type = 0;
  if (!s_tried) {
    s_tried = true;
    // Ne rien interner tant que le tas GOAL n'est pas la : `intern_from_c` CREE le symbole s'il
    // manque, et fabriquer un symbole depuis le fil de rendu serait un effet de bord.
    if (g_ee_main_mem) {
      s_symbol = jak1::intern_from_c("*ocean-map*").offset;
      s_type = jak1::intern_from_c("ocean-map").offset;
    }
  }
  if (!s_symbol || !s_type || !g_ee_main_mem) {
    return 0;
  }
  u32 v = 0;
  std::memcpy(&v, g_ee_main_mem + s_symbol, sizeof(v));
  if (v < 0x10000 || (u64)v + 128 >= EE_MAIN_MEM_SIZE) {
    return 0;
  }
  // `#f` EST LE SYMBOLE s7, PAS ZERO. Une carte absente rend donc une valeur qui RESSEMBLE a un
  // pointeur et passe n'importe quel test de plage : la course du 2026-09-10 a lu, une image sur
  // deux, un `start-corner` de denormaux a 2.2e-39. On valide donc par le TAG DE TYPE, qui est
  // l'invariant reel d'un `basic` : les quatre octets qui precedent l'objet portent l'adresse de
  // son type. Un mot exact, pas une heuristique de plage.
  u32 tag = 0;
  std::memcpy(&tag, g_ee_main_mem + v - 4, sizeof(tag));
  u32 type_value = 0;
  std::memcpy(&type_value, g_ee_main_mem + s_type, sizeof(type_value));
  if (!type_value || tag != type_value) {
    return 0;
  }
  // perf-goal-gl-overlap : `*ocean-map*` n'est PAS double-bufferise et `ocean.gc:527` reecrit
  // `start-corner y` a chaque image. C'est le seul site du recensement dont l'ecrivain GOAL
  // tourne par image : ce temoin-la peut monter, et s'il monte il nomme la course.
  overlap_census::note_read(overlap_census::kOcean, v, 80);
  return v;
}

// LES OFFSETS DE `ocean-map`, MESURES ET NON DEDUITS. `decompiler/config/jak1/all-types.gc`
// annonce start-corner a 16, far-color a 32, les six pointeurs de 48 a 68 — en comptant le mot de
// type comme l'offset 0. En memoire, le pointeur d'un `basic` designe le PREMIER CHAMP et le type
// vit a -4 : tous les offsets valent donc `declare - 4`. La course du 2026-09-10 l'a montre sans
// ambiguite — lu a +16/+20/+24, `start-corner` rendait (0, -9437184, 1), c'est-a-dire y, z, w.
// C'est aussi ce qui explique `draw-ocean-mid` (ocean-mid.gc:846), qui lit les index a
// `objet + tuile * 2` : le champ `data`, declare a 4, est bien a 0.
constexpr u32 kOffStartCorner = 12;   // declare 16
constexpr u32 kOffFarColor = 28;      // declare 32
constexpr u32 kOffMidIndices = 52;    // declare 56
constexpr u32 kOffMidMasks = 64;      // declare 68
constexpr u32 kOffBasicData = 0;      // le champ `data` d'un basic, declare a 4

const u8* ee(u32 addr) {
  return g_ee_main_mem + addr;
}

u32 ee_u32(u32 addr) {
  u32 v = 0;
  std::memcpy(&v, ee(addr), sizeof(v));
  return v;
}

}  // namespace

bool ocean_recharged_enabled() {
  // `armed_for` et non `armed()` : le bras d'ablation d'un AUTRE item ne doit pas desarmer
  // celui-ci. `recharged_gating::on(kWater)` compose master > eau ; aucune porte ne lit le
  // drapeau en direct.
  return recharged_gating::on(recharged_gating::kWater) && autoport_proof::armed_for(kItemId);
}

OceanRecharged& OceanRecharged::get() {
  static OceanRecharged s_instance;
  return s_instance;
}

void OceanRecharged::note_layer_a(const void* heights_4096_bytes) {
  std::memcpy(m_layer_a.data(), heights_4096_bytes, sizeof(float) * m_layer_a.size());
  m_have_layer_a = true;
  m_layer_a_fresh = true;
}

void OceanRecharged::note_ocean_texture(u32 gl_texture) {
  if (gl_texture) {
    m_ocean_texture = gl_texture;
  }
}

bool OceanRecharged::ensure_gl() {
  if (m_gl_ready) {
    return true;
  }
  if (m_gl_failed) {
    return false;
  }
  m_gl_failed = true;  // remis a false a la toute fin : un echec ne se retente pas chaque image

  // ---- sommets : une seule grille 129 x 129, coordonnees entieres -64 .. +64 ----------------
  std::vector<float> verts;
  verts.reserve(kGridVerts * kGridVerts * 2);
  for (int z = 0; z < kGridVerts; z++) {
    for (int x = 0; x < kGridVerts; x++) {
      verts.push_back((float)(x - kGridCells / 2));
      verts.push_back((float)(z - kGridCells / 2));
    }
  }

  // ---- anneaux (SPEC §5.3). Les trous se RECOUVRENT volontairement -------------------------
  // La SPEC prescrit un morphing de bord ; on obtient le meme resultat — aucune fente — par un
  // recouvrement franc, et c'est plus sur : chaque anneau se snappe a SON pas, donc les centres
  // de deux anneaux voisins peuvent s'ecarter de la moitie du plus gros pas. Un trou pile a la
  // taille de l'anneau interieur ouvrirait une fente de cette largeur des que la camera bouge.
  // Le recouvrement est dimensionne sur ce pire cas :
  //   anneau 1 : trou +-42 m, anneau 0 couvre +-48 m, ecart de snap max 0,375 + 1,5 = 1,875 m.
  //   anneau 2 : trou +-144 m, anneau 1 couvre +-192 m, ecart de snap max 1,5 + 18 = 19,5 m.
  m_rings[0] = {kWaveCell / 4.f, 0, 0, 0, {0.f, 0.f}};        // 0,75 m -> +-48 m
  m_rings[1] = {kWaveCell, 14, 0, 0, {0.f, 0.f}};             // 3 m    -> +-192 m, trou +-42 m
  m_rings[2] = {kWaveCell * 12.f, 4, 0, 0, {0.f, 0.f}};       // 36 m   -> +-2304 m, trou +-144 m

  std::vector<u32> indices;
  indices.reserve(kGridCells * kGridCells * 6 * kNumRings);
  for (int r = 0; r < kNumRings; r++) {
    m_rings[r].index_offset = (u32)indices.size();
    const int hole = m_rings[r].hole_half;
    for (int cz = 0; cz < kGridCells; cz++) {
      const int gz = cz - kGridCells / 2;
      for (int cx = 0; cx < kGridCells; cx++) {
        const int gx = cx - kGridCells / 2;
        if (hole > 0 && gx >= -hole && gx < hole && gz >= -hole && gz < hole) {
          continue;
        }
        const u32 v00 = (u32)(cz * kGridVerts + cx);
        const u32 v10 = v00 + 1;
        const u32 v01 = v00 + kGridVerts;
        const u32 v11 = v01 + 1;
        indices.push_back(v00);
        indices.push_back(v10);
        indices.push_back(v01);
        indices.push_back(v10);
        indices.push_back(v11);
        indices.push_back(v01);
      }
    }
    m_rings[r].index_count = (u32)indices.size() - m_rings[r].index_offset;
  }

  glGenVertexArrays(1, &m_vao);
  glGenBuffers(1, &m_vbo);
  glGenBuffers(1, &m_ibo);
  glBindVertexArray(m_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
  glBufferData(GL_ARRAY_BUFFER, verts.size() * sizeof(float), verts.data(), GL_STATIC_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), nullptr);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_ibo);
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.size() * sizeof(u32), indices.data(),
               GL_STATIC_DRAW);
  glBindVertexArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

  // ---- couche A : R32F. Un R8 (256 crans sur +-1,33 m) coute 5,9 mm de quantification, et la
  // porte de cet item est `== 0` mm : le format 8 bits la rendrait INATTEIGNABLE. R32F est un
  // format de texture EXIGE par GLES 3.0 ; il n'est pas filtrable sans extension, d'ou le
  // bilerp a la main dans `ocean_layer_a.glsl` — qui est de toute facon obligatoire pour
  // reproduire l'ordre d'operations de `ocean-get-height`.
  glGenTextures(1, &m_tex_layer_a);
  glBindTexture(GL_TEXTURE_2D, m_tex_layer_a);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R32F, 32, 32, 0, GL_RED, GL_FLOAT, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

  glGenTextures(1, &m_tex_mask);
  glBindTexture(GL_TEXTURE_2D, m_tex_mask);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, kMaskSide, kMaskSide, 0, GL_RED, GL_UNSIGNED_BYTE,
               nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

  // ---- la cible de la sonde : RGBA8 8x8. C'est le SEUL format dont `glReadPixels` est garanti
  // sur GLES 3.2 ; un R32F relu directement ne l'est pas.
  glGenTextures(1, &m_probe_tex);
  glBindTexture(GL_TEXTURE_2D, m_probe_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, kProbeSide, kProbeSide, 0, GL_RGBA, GL_UNSIGNED_BYTE,
               nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glGenFramebuffers(1, &m_probe_fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, m_probe_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_probe_tex, 0);
  const GLenum fb_status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glBindTexture(GL_TEXTURE_2D, 0);
  if (fb_status != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("[water-ocean-mesh] probe FBO incomplete (0x{:x}) — la porte ne pourra pas etre mesuree",
              (u32)fb_status);
  }

  lg::info("[water-ocean-mesh] clipmap prete : {} sommets, {} indices sur 3 anneaux",
           kGridVerts * kGridVerts,
           m_rings[0].index_count + m_rings[1].index_count + m_rings[2].index_count);
  m_gl_failed = false;
  m_gl_ready = true;
  return true;
}

bool OceanRecharged::refresh_ocean_map() {
  m_map_ptr = read_ocean_map_ptr();
  if (!m_map_ptr) {
    return false;
  }
  std::memcpy(m_start_corner, ee(m_map_ptr + kOffStartCorner), sizeof(m_start_corner));
  std::memcpy(m_far_color, ee(m_map_ptr + kOffFarColor), sizeof(m_far_color));
  // UNE fois par carte : ce qu'on a VRAIMENT lu. `start-corner` doit valoir (-9437184, *, -9437184)
  // pour les trois cartes de jak1 (ocean-tables.gc:11211) ; si ce n'est pas le cas, la lecture du
  // symbole est fausse et tout ce qui suit l'est aussi. On l'ecrit plutot que de le supposer.
  static u32 s_logged = 0;
  if (s_logged != m_map_ptr) {
    s_logged = m_map_ptr;
    lg::info("[water-ocean-mesh] ocean-map @0x{:x} start-corner=({}, {}, {}) far-color=({}, {}, {})",
             m_map_ptr, m_start_corner[0], m_start_corner[1], m_start_corner[2], m_far_color[0],
             m_far_color[1], m_far_color[2]);
  }
  return true;
}

void OceanRecharged::rebuild_mask_texture() {
  // « using 0 will draw, using 1 will skip » (ocean-mid.gc:442-444). Les 36 tuiles de 768 m
  // portent chacune 8 octets = 8 x 8 bits, soit une grille de 48 x 48 sous-cellules de 96 m.
  // L'indexation est celle de `ocean-mid-mask-ptrs-bit?` (ocean-mid.gc:485-496), lue a la lettre :
  //   tuile = 6 * (z / 8) + (x / 8) ; octet = z & 7 ; bit = x & 7.
  // (Le sens des deux axes vient de `ocean-mid-add-upload` : gp.x suit arg2 = la seconde boucle,
  //  gp.z suit arg1 = la premiere ; la tuile vaut 6 * arg1 + arg2, donc arg1 est bien z.)
  u8 mask[kMaskSide * kMaskSide];
  std::memset(mask, 0, sizeof(mask));
  m_mask_skip_cells = 0;
  m_mask_draw_cells = 0;
  m_mask_fallback = 0;

  const u32 indices_obj = ee_u32(m_map_ptr + kOffMidIndices);
  const u32 masks_obj = ee_u32(m_map_ptr + kOffMidMasks);
  if (!indices_obj || !masks_obj) {
    m_mask_fallback = 1;
  }

  u32 masks_data = 0;
  if (!m_mask_fallback) {
    masks_data = ee_u32(masks_obj + kOffBasicData);  // champ `data`, un (inline-array ocean-mid-mask)
    if (!masks_data || (u64)masks_data + 8 >= EE_MAIN_MEM_SIZE) {
      m_mask_fallback = 1;
    }
  }

  // L'ACCES AUX INDICES, MESURE ET NON SUPPOSE. `draw-ocean-mid` lit
  // `(pointer int16)` a `objet + tuile * 2` — c'est-a-dire, si le champ `data` est bien a
  // l'offset 4, deux crans avant le premier element. Plutot que de trancher sur une lecture de
  // `deftype`, on compte pour les DEUX offsets combien des 36 tuiles rendent un index plausible,
  // on publie les deux chiffres, et on prend le meilleur. Un desaccord se lit dans la preuve.
  auto count_valid = [&](u32 off) {
    u32 n = 0;
    for (int t = 0; t < 36; t++) {
      s16 v = 0;
      std::memcpy(&v, ee(indices_obj + off + t * 2), sizeof(v));
      if (v >= -1 && v < 4096) {
        n++;
      }
    }
    return n;
  };
  if (!m_mask_fallback) {
    m_mask_valid_off0 = count_valid(0);
    m_mask_valid_off4 = count_valid(4);
    {
      std::string dump0, dump4;
      for (int t = 0; t < 36; t++) {
        s16 a = 0, b = 0;
        std::memcpy(&a, ee(indices_obj + t * 2), sizeof(a));
        std::memcpy(&b, ee(indices_obj + 4 + t * 2), sizeof(b));
        dump0 += fmt::format("{} ", a);
        dump4 += fmt::format("{} ", b);
      }
      lg::info("[water-ocean-mesh] mid-indices off0: {}", dump0);
      lg::info("[water-ocean-mesh] mid-indices off4: {}", dump4);
    }
    m_mask_index_offset = (m_mask_valid_off4 > m_mask_valid_off0) ? 4 : 0;
    if (std::max(m_mask_valid_off0, m_mask_valid_off4) < 36) {
      m_mask_fallback = 1;
    }
  }

  if (!m_mask_fallback) {
    for (int t = 0; t < 36; t++) {
      s16 idx = 0;
      std::memcpy(&idx, ee(indices_obj + m_mask_index_offset + t * 2), sizeof(idx));
      const int z_tile = t / 6;
      const int x_tile = t % 6;
      if (idx < 0) {
        // `(< s0-0 0)` : la tuile entiere est sautee par l'original.
        for (int bz = 0; bz < 8; bz++) {
          for (int bx = 0; bx < 8; bx++) {
            mask[(z_tile * 8 + bz) * kMaskSide + (x_tile * 8 + bx)] = 255;
          }
        }
        continue;
      }
      const u32 mask_addr = masks_data + (u32)idx * 8;
      if ((u64)mask_addr + 8 >= EE_MAIN_MEM_SIZE) {
        m_mask_fallback = 1;
        break;
      }
      u8 bytes[8];
      std::memcpy(bytes, ee(mask_addr), 8);
      for (int bz = 0; bz < 8; bz++) {
        for (int bx = 0; bx < 8; bx++) {
          const bool skip = (bytes[bz] & (1u << bx)) != 0;
          mask[(z_tile * 8 + bz) * kMaskSide + (x_tile * 8 + bx)] = skip ? 255 : 0;
        }
      }
    }
  }

  for (int i = 0; i < kMaskSide * kMaskSide; i++) {
    if (mask[i]) {
      m_mask_skip_cells++;
    } else {
      m_mask_draw_cells++;
    }
  }

  // SOUPAPE. Un masque qui saute presque tout n'est pas une carte, c'est une lecture ratee — et
  // une mer entierement decoupee est un defaut que l'owner verrait avant nous. Dans ce cas on
  // dessine partout : le test de profondeur (on est au bucket 63, apres le monde) suffit deja a
  // laisser la terre recouvrir l'eau. Le repli est PUBLIE, jamais silencieux.
  if (m_mask_draw_cells * 20 < (u32)(kMaskSide * kMaskSide)) {
    m_mask_fallback = 1;
  }
  if (m_mask_fallback) {
    std::memset(mask, 0, sizeof(mask));
    m_mask_skip_cells = 0;
    m_mask_draw_cells = kMaskSide * kMaskSide;
  }

  glBindTexture(GL_TEXTURE_2D, m_tex_mask);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, kMaskSide, kMaskSide, GL_RED, GL_UNSIGNED_BYTE, mask);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  m_mask_map_ptr = m_map_ptr;
}

void OceanRecharged::run_probe(SharedRenderState* render_state) {
  gl_query_census::Armed _ap("ocean-probe");
  if (!m_probe_fbo) {
    return;
  }
  auto& shader = render_state->shaders[ShaderId::OCEAN_PROBE];
  if (!shader.okay()) {
    return;
  }

  // Les 64 points de mesure SONT 64 sommets de l'anneau 0, pris sur une grille reguliere de la
  // meme grille de sommets : la porte compare donc bien « la hauteur de jeu aux memes (x, z) que
  // 64 sommets de la clipmap » (SPEC §8, controle causal 1), pas 64 points inventes.
  for (int j = 0; j < kProbeSide; j++) {
    for (int i = 0; i < kProbeSide; i++) {
      const int k = j * kProbeSide + i;
      const float gx = (float)(-56 + i * 16);
      const float gz = (float)(-56 + j * 16);
      m_probe_xz[k][0] = m_rings[0].center[0] + gx * m_rings[0].step;
      m_probe_xz[k][1] = m_rings[0].center[1] + gz * m_rings[0].step;
      m_probe_xz[k][2] = 0.f;
      m_probe_xz[k][3] = 0.f;
    }
  }

  glBindFramebuffer(GL_FRAMEBUFFER, m_probe_fbo);
  glViewport(0, 0, kProbeSide, kProbeSide);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);
  glDepthMask(GL_FALSE);
  glClearColor(0.f, 0.f, 0.f, 0.f);
  glClear(GL_COLOR_BUFFER_BIT);

  shader.activate();
  const GLuint id = shader.id();
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, m_tex_layer_a);
  glUniform1i(glGetUniformLocation(id, "tex_layer_a"), 0);
  glUniform4f(glGetUniformLocation(id, "u_ocean_origin"), m_start_corner[0], m_start_corner[1],
              m_start_corner[2], m_start_corner[3]);
  glUniform4fv(glGetUniformLocation(id, "u_probe_xz"), kProbeCount, &m_probe_xz[0][0]);
  glBindVertexArray(m_vao);
  glDrawArrays(GL_TRIANGLES, 0, 3);

  u8 pixels[kProbeCount * 4];
  glReadPixels(0, 0, kProbeSide, kProbeSide, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

  glBindFramebuffer(GL_FRAMEBUFFER, render_state->render_fb);
  glViewport(render_state->render_fb_x, render_state->render_fb_y, render_state->render_fb_w,
             render_state->render_fb_h);
  // La sonde a eteint le test et l'ecriture de profondeur pour son quad de 8x8. Rien ne les
  // repose entre ici et le bucket suivant : une image sur trente sortirait avec un etat de
  // profondeur different des vingt-neuf autres, et l'ecart ne ressemblerait pas a sa cause. On
  // rend exactement l'etat que la clipmap venait de poser.
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_GEQUAL);
  glDepthMask(GL_TRUE);

  m_probe_runs++;
  s64 span_min = 0, span_max = 0;
  bool first = true;
  for (int k = 0; k < kProbeCount; k++) {
    if (pixels[k * 4 + 3] < 128) {
      // Alpha nul = AUCUN fragment n'a tourne pour ce texel. Une cible restee noire vaudrait
      // « hauteur zero » et rendrait la porte verte par inaction : on la compte, on ne la lit pas.
      m_probe_alpha_missing++;
      continue;
    }
    const s64 gpu_q = (s64)pixels[k * 4 + 0] + ((s64)pixels[k * 4 + 1] << 8) +
                      ((s64)pixels[k * 4 + 2] << 16) - 8388608;
    const float cpu_a = layer_a_cpu(m_layer_a.data(), m_start_corner[0], m_start_corner[2],
                                    m_probe_xz[k][0], m_probe_xz[k][1]);
    const s64 cpu_q = (s64)std::llround(cpu_a * 256.0);
    const s64 d = std::llabs(gpu_q - cpu_q);
    if (d > m_maxdelta_q256) {
      m_maxdelta_q256 = d;
    }
    if (first || cpu_q < span_min) {
      span_min = cpu_q;
    }
    if (first || cpu_q > span_max) {
      span_max = cpu_q;
    }
    first = false;
  }
  if (!first && (span_max - span_min) > m_probe_span_q256) {
    m_probe_span_q256 = span_max - span_min;
  }
}

void OceanRecharged::publish() {
  using autoport_proof::publish;
  // LA PORTE. 1/1024 d'unite GOAL vaut 1/4194,304 de millimetre : convertir puis arrondir, c'est
  // dire « au millimetre pres », l'unite meme de la regle 2. Le chiffre BRUT est publie a cote —
  // un seuil qui censure fabrique une fausse constante, et personne ne pourrait distinguer un
  // vrai zero d'un ecart de 0,4 mm.
  if (m_maxdelta_q256 >= 0) {
    const double mm = (double)m_maxdelta_q256 / 1048.576;  // 256 * 4096 / 1000
    publish("water_gameplay_height_maxdelta_mm", (u64)std::llround(mm));
    publish("water_gameplay_height_maxdelta_q256", (u64)m_maxdelta_q256);
    // Les couches B et C n'existent pas encore (items 2 et 4) : la hauteur VISUELLE vaut
    // exactement la couche A, donc l'excedent visuel est la MEME grandeur. C'est un zero par
    // absence de couche, pas par bornage, et le rapport le dit.
    publish("water_visual_excess_mm", (u64)std::llround(mm));
  }
  publish("water_probe_runs", m_probe_runs);
  publish("water_probe_alpha_missing", m_probe_alpha_missing);
  publish("water_probe_span_q256", (u64)m_probe_span_q256);
  publish("water_layerA_absmax_q256", (u64)m_layer_a_absmax_q256);
  publish("water_layerA_nonzero_texels", (u64)m_layer_a_nonzero);
  publish("water_clipmap_frames", m_frames_drawn);
  publish("water_clipmap_verts_moved", m_verts_moved);
  publish("water_layerA_fresh_frames", m_frames_layer_a_fresh);
  publish("water_layerA_stale_frames", m_frames_layer_a_stale);
  publish("water_mask_skip_cells", m_mask_skip_cells);
  publish("water_mask_draw_cells", m_mask_draw_cells);
  publish("water_mask_valid_off0", m_mask_valid_off0);
  publish("water_mask_valid_off4", m_mask_valid_off4);
  publish("water_mask_index_offset", m_mask_index_offset);
  publish("water_mask_fallback", m_mask_fallback);
}

void OceanRecharged::draw(SharedRenderState* render_state, ScopedProfilerNode& prof) {
  const bool had_fresh = m_layer_a_fresh;
  m_layer_a_fresh = false;

  if (!m_have_layer_a) {
    // Jamais capte la houle : le bucket 63 n'a encore rien porte. On ne dessine pas une mer
    // plate a la place, on ne dessine rien.
    return;
  }
  if (!refresh_ocean_map()) {
    return;
  }
  if (!ensure_gl()) {
    return;
  }
  auto& shader = render_state->shaders[ShaderId::OCEAN_RECHARGED];
  if (!shader.okay()) {
    return;
  }

  if (had_fresh) {
    m_frames_layer_a_fresh++;
    glBindTexture(GL_TEXTURE_2D, m_tex_layer_a);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 32, 32, GL_RED, GL_FLOAT, m_layer_a.data());
  } else {
    // Au-dessus de 48 m, `draw-ocean` n'insere plus le bucket 63 (ocean.gc:543) et la houle ne
    // part plus au DMA. On garde la derniere captee : c'est ce que le joueur voit de toute facon
    // a cette altitude, et la porte, elle, ne se mesure QUE sur une image fraiche.
    m_frames_layer_a_stale++;
  }

  if (m_map_ptr != m_mask_map_ptr) {
    rebuild_mask_texture();
  }

  // Chaque anneau se snappe a SON pas : sans cela la grille glisse sous la houle et le
  // scintillement de bord revient a chaque image.
  const float cam_x = render_state->camera_pos[0];
  const float cam_z = render_state->camera_pos[2];
  for (int r = 0; r < kNumRings; r++) {
    m_rings[r].center[0] = std::floor(cam_x / m_rings[r].step + 0.5f) * m_rings[r].step;
    m_rings[r].center[1] = std::floor(cam_z / m_rings[r].step + 0.5f) * m_rings[r].step;
  }

  shader.activate();
  const GLuint id = shader.id();
  glUniformMatrix4fv(glGetUniformLocation(id, "camera"), 1, GL_FALSE,
                     render_state->camera_matrix[0].data());
  glUniform4f(glGetUniformLocation(id, "hvdf_offset"), render_state->camera_hvdf_off[0],
              render_state->camera_hvdf_off[1], render_state->camera_hvdf_off[2],
              render_state->camera_hvdf_off[3]);
  glUniform4f(glGetUniformLocation(id, "camera_position"), render_state->camera_pos[0],
              render_state->camera_pos[1], render_state->camera_pos[2],
              render_state->camera_pos[3]);
  glUniform1f(glGetUniformLocation(id, "fog_constant"), render_state->camera_fog.x());
  glUniform1f(glGetUniformLocation(id, "u_water_y"), m_start_corner[1]);
  glUniform4f(glGetUniformLocation(id, "u_ocean_origin"), m_start_corner[0], m_start_corner[1],
              m_start_corner[2], m_start_corner[3]);
  glUniform4f(glGetUniformLocation(id, "u_far_color"), m_far_color[0], m_far_color[1],
              m_far_color[2], m_far_color[3]);

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, m_tex_layer_a);
  glUniform1i(glGetUniformLocation(id, "tex_layer_a"), 0);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, m_ocean_texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
  glUniform1i(glGetUniformLocation(id, "tex_ocean"), 1);
  glActiveTexture(GL_TEXTURE2);
  glBindTexture(GL_TEXTURE_2D, m_tex_mask);
  glUniform1i(glGetUniformLocation(id, "tex_mask"), 2);

  // Profondeur INVERSEE dans cet arbre : `flush_near` teste en GL_GEQUAL. On ecrit la profondeur,
  // contrairement au near d'origine, parce qu'on dessine enfin l'eau a sa vraie place dans la
  // scene et non par-dessus tout.
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_GEQUAL);
  glDepthMask(GL_TRUE);
  glDisable(GL_BLEND);
  glDisable(GL_CULL_FACE);

  glBindVertexArray(m_vao);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_ibo);
  u64 verts_this_frame = 0;
  for (int r = 0; r < kNumRings; r++) {
    glUniform2f(glGetUniformLocation(id, "u_ring_center"), m_rings[r].center[0],
                m_rings[r].center[1]);
    glUniform1f(glGetUniformLocation(id, "u_ring_step"), m_rings[r].step);
    glDrawElements(GL_TRIANGLES, m_rings[r].index_count, GL_UNSIGNED_INT,
                   (void*)(intptr_t)(m_rings[r].index_offset * sizeof(u32)));
    prof.add_draw_call();
    prof.add_tri(m_rings[r].index_count / 3);
    verts_this_frame += m_rings[r].index_count;
  }
  glBindVertexArray(0);
  m_frames_drawn++;

  // LES `hits` SONT LUS SUR L'EFFET. Un sommet n'est « deplace » que si la couche A n'est pas
  // plate : on ne compte donc que les images ou la houle captee porte au moins un texel non nul.
  // Un compteur qui monterait meme sur une mer d'huile ne separerait rien.
  bool any_wave = false;
  m_layer_a_nonzero = 0;
  for (float h : m_layer_a) {
    if (h != 0.f) {
      any_wave = true;
      m_layer_a_nonzero++;
      const s64 q = (s64)std::llround(std::fabs((double)h) * 256.0);
      if (q > m_layer_a_absmax_q256) {
        m_layer_a_absmax_q256 = q;
      }
    }
  }
  if (any_wave) {
    m_verts_moved += verts_this_frame;
    autoport_proof::note_hit_for(kItemId, verts_this_frame);
  }

  // La sonde ne tourne que sur une image FRAICHE : comparer la hauteur de jeu de cette image a
  // une couche A d'il y a dix images mesurerait le retard, pas la fidelite.
  if (had_fresh && (m_frames_drawn % kProbeEveryFrames) == 0) {
    run_probe(render_state);
  }
  if ((m_frames_drawn % kProbeEveryFrames) == 0) {
    publish();
  }
}
