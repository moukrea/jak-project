#include "OceanRecharged.h"
#include "game/system/recharged_gating.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <ctime>
#include <vector>

#include "common/goal_constants.h"
#include "common/log/log.h"

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

// water-ocean-mesh-hit-counter-cost : L'ITEM QUI MESURE L'INSTRUMENT CI-DESSUS.
// Son chemin de code est le chronometre de `draw` ; il declare donc son site ici, dans la meme
// unite de traduction, et prend sa prise UNE FOIS PAR IMAGE MESUREE — la granularite qu'il
// reclame a l'autre.
constexpr const char* kCostId = "water-ocean-mesh-hit-counter-cost";
AUTOPORT_FEATURE_SITE(kCostId);

// L'horloge du TEMPS PROCESSEUR DU FIL QUI DESSINE. Une horloge murale compterait les preemptions
// du telephone dans le cout de l'instrument, et un seul changement de contexte pendant une region
// de 200 ns la ferait mentir d'un facteur mille. Celle-ci ne compte que les cycles reellement
// passes dedans. Un echec d'appel ne rend pas zero en silence : il se compte, et son compteur est
// publie — sinon « l'horloge n'a pas repondu » se lirait « l'instrument est gratuit ».
u64 cpu_ns(u64* fails) {
  timespec t{};
  if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t) != 0) {
    (*fails)++;
    return 0;
  }
  return (u64)t.tv_sec * 1000000000ull + (u64)t.tv_nsec;
}

// 1 metre = 4096 unites GOAL. La cellule de houle vaut 12288 unites (3 m) ; on la reprend telle
// quelle plutot que de refabriquer 3.0f * 4096.0f, pour que le pas des anneaux soit un diviseur
// EXACT de la periode et que la grille snappee ne derive jamais du modulo 32.
constexpr float kWaveCell = 12288.f;  // 3 m ; 1 m = 4096 unites GOAL
constexpr int kMidMaskSide = 48;             // 6 tuiles x 8 cellules de 96 m
constexpr int kMaskSide = kMidMaskSide * 32;  // cellules near de 3 m

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
  if (!s_symbol || !s_type || !g_ee_main_mem ||
      (u64)s_symbol + sizeof(u32) > EE_MAIN_MEM_SIZE ||
      (u64)s_type + sizeof(u32) > EE_MAIN_MEM_SIZE) {
    return 0;
  }
  u32 v = 0;
  std::memcpy(&v, g_ee_main_mem + s_symbol, sizeof(v));
  if (v < 0x10000 || v == s7.offset || (u64)v + 128 > EE_MAIN_MEM_SIZE) {
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
constexpr u32 kOffTransIndices = 56;  // declare 60, inline-array de paires parent/child
constexpr u32 kOffNearIndices = 60;   // declare 64, pointeur vers les blocs de 32 octets
constexpr u32 kOffMidMasks = 64;      // declare 68
constexpr u32 kOffBasicData = 0;      // le champ `data` d'un basic, declare a 4

const u8* ee(u32 addr) {
  return g_ee_main_mem + addr;
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
  // Journaliser l'origine lue lors d'un changement de carte : village1 utilise
  // (-9437184, y, -9437184), village2/sunken (-7892992, y, -15958016).
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
  // Hierarchie ND : 36 masques mid de 8x8 cellules de 96 m, une paire trans
  // parent/child par cellule, puis 16 indices near par child. Chaque indice near
  // designe un masque de 8x8 cellules de 3 m (ocean-near.gc:393-412, 556-570).
  // Parent : 4 octets utiles, 4 bits/ligne, 1 bit/carre de 24 m (2 triangles),
  // ocean-transition.gc:573-579. Near ne teste pas ces bits : parent >= 0 rend child
  // disponible, puis near utilise ses indices/masques (ocean-near.gc:558-570).
  std::vector<u8> mask(kMaskSide * kMaskSide, 255);
  std::array<u8, kMidMaskSide * kMidMaskSide> mid_mask;
  mid_mask.fill(255);
  m_mask_skip_cells = 0;
  m_mask_draw_cells = 0;
  m_mask_near_skip_cells = 0;
  m_mask_near_draw_cells = 0;
  m_mask_valid_off0 = 0;
  m_mask_valid_off4 = 0;
  m_mask_index_offset = 0;
  m_mask_fallback = 0;
  m_mask_invalid_reads = 0;

  // Toute arithmetique d'adresse precede la validation en u64 : aucun wrap u32.
  // #f est s7, pas zero ; objets ET pointeurs data doivent etre presents.
  auto valid_range = [](u64 addr, u64 size) {
    return g_ee_main_mem && addr != 0 && addr != s7.offset &&
           addr < EE_MAIN_MEM_SIZE && size <= (u64)EE_MAIN_MEM_SIZE - addr;
  };
  auto read = [&](u64 addr, void* dest, u64 size) {
    if (!valid_range(addr, size)) {
      ++m_mask_invalid_reads;
      m_mask_fallback = 1;
      return false;
    }
    std::memcpy(dest, g_ee_main_mem + addr, size);
    return true;
  };
  auto pointer = [&](u64 addr, u32& value, u64 size) {
    if (!read(addr, &value, sizeof(value))) {
      return false;
    }
    if (!valid_range(value, size)) {
      ++m_mask_invalid_reads;
      m_mask_fallback = 1;
      return false;
    }
    return true;
  };

  u32 indices_obj = 0, trans_obj = 0, near_obj = 0, masks_obj = 0;
  u32 near_data = 0, masks_data = 0;
  if (!valid_range(m_map_ptr, kOffMidMasks + sizeof(u32))) {
    ++m_mask_invalid_reads;
    m_mask_fallback = 1;
  }
  const bool have_data =
      !m_mask_fallback &&
      pointer((u64)m_map_ptr + kOffMidIndices, indices_obj, 36 * sizeof(s16)) &&
      pointer((u64)m_map_ptr + kOffTransIndices, trans_obj, kMidMaskSide * kMidMaskSide * 4) &&
      pointer((u64)m_map_ptr + kOffNearIndices, near_obj, sizeof(u32)) &&
      pointer((u64)m_map_ptr + kOffMidMasks, masks_obj, sizeof(u32)) &&
      pointer((u64)near_obj + kOffBasicData, near_data, 32) &&
      pointer((u64)masks_obj + kOffBasicData, masks_data, 8);

  if (have_data) {
    // Off4 reste un diagnostic historique sur les 34 entrees encore dans le tableau ;
    // il ne choisit JAMAIS l'adresse et ne lit pas les objets voisins.
    // Un indice signe >= 0 ou la sentinelle -1 est comptabilise, sans seuil invente.
    for (int t = 0; t < 36 && !m_mask_fallback; ++t) {
      s16 idx = -1;
      if (!read((u64)indices_obj + t * 2, &idx, sizeof(idx))) {
        break;
      }
      m_mask_valid_off0 += idx >= -1;
      const u64 off4_addr = (u64)indices_obj + 4 + t * 2;
      if (t < 34 && valid_range(off4_addr, sizeof(s16))) {
        s16 off4;
        std::memcpy(&off4, g_ee_main_mem + off4_addr, sizeof(off4));
        m_mask_valid_off4 += off4 >= -1;
      }
      if (idx < 0) {
        continue;
      }
      u8 bytes[8];
      if (!read((u64)masks_data + (u64)idx * 8, bytes, sizeof(bytes))) {
        break;
      }
      for (int z = 0; z < 8; ++z) {
        for (int x = 0; x < 8; ++x) {
          mid_mask[((t / 6) * 8 + z) * kMidMaskSide + (t % 6) * 8 + x] =
              (bytes[z] & (1u << x)) ? 255 : 0;
        }
      }
    }

    for (int cz = 0; cz < kMidMaskSide && !m_mask_fallback; ++cz) {
      for (int cx = 0; cx < kMidMaskSide && !m_mask_fallback; ++cx) {
        if (mid_mask[cz * kMidMaskSide + cx]) {
          continue;
        }
        s16 trans[2];
        if (!read((u64)trans_obj + 4 * (cz * kMidMaskSide + cx), trans, sizeof(trans))) {
          break;
        }
        if (trans[0] < 0 || trans[1] < 0) {
          continue;
        }
        s16 near_indices[16];
        if (!read((u64)near_data + (u64)trans[1] * 32, near_indices,
                  sizeof(near_indices))) {
          break;
        }
        for (int nz = 0; nz < 4 && !m_mask_fallback; ++nz) {
          for (int nx = 0; nx < 4; ++nx) {
            const s16 idx = near_indices[nz * 4 + nx];
            if (idx < 0) {
              continue;
            }
            u8 bytes[8];
            if (!read((u64)masks_data + (u64)idx * 8, bytes, sizeof(bytes))) {
              break;
            }
            for (int z = 0; z < 8; ++z) {
              for (int x = 0; x < 8; ++x) {
                const int fine_z = cz * 32 + nz * 8 + z;
                const int fine_x = cx * 32 + nx * 8 + x;
                mask[fine_z * kMaskSide + fine_x] = (bytes[z] & (1u << x)) ? 255 : 0;
              }
            }
          }
        }
      }
    }
  }

  if (m_mask_fallback) {
    // Une lecture invalide ferme toute la carte, sans repli tout-dessiner ni seuil 5%.
    std::fill(mask.begin(), mask.end(), 255);
    mid_mask.fill(255);
    lg::error("[water-ocean-mesh] water_mask_fallback=1 map=0x{:x} invalid_reads={} : "
              "masque entierement skip",
              m_map_ptr, m_mask_invalid_reads);
  }
  for (u8 value : mid_mask) {
    if (value) {
      ++m_mask_skip_cells;
    } else {
      ++m_mask_draw_cells;
    }
  }
  for (u8 value : mask) {
    if (value) {
      ++m_mask_near_skip_cells;
    } else {
      ++m_mask_near_draw_cells;
    }
  }

  glBindTexture(GL_TEXTURE_2D, m_tex_mask);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, kMaskSide, kMaskSide, GL_RED, GL_UNSIGNED_BYTE,
                  mask.data());
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
    m_probe_verts_sampled++;
    if (gpu_q != 0) {
      m_probe_verts_moved++;
    }
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
  publish("water_clipmap_verts_moved", m_probe_verts_moved);
  publish("water_clipmap_verts_sampled", m_probe_verts_sampled);
  publish("water_clipmap_indices_submitted", m_verts_moved);
  autoport_proof::publish_text(
      "water_clipmap_verts_scope",
      "cumulative-valid-observations-of-64-probe-vertex-subset-not-total-draw-vertices-or-fragments");
  publish("water_layerA_fresh_frames", m_frames_layer_a_fresh);
  publish("water_layerA_stale_frames", m_frames_layer_a_stale);
  publish("water_mask_skip_cells", m_mask_skip_cells);
  publish("water_mask_draw_cells", m_mask_draw_cells);
  publish("water_mask_valid_off0", m_mask_valid_off0);
  publish("water_mask_valid_off4", m_mask_valid_off4);
  publish("water_mask_index_offset", m_mask_index_offset);
  publish("water_mask_fallback", m_mask_fallback);
  publish("water_mask_near_skip_cells", m_mask_near_skip_cells);
  publish("water_mask_near_draw_cells", m_mask_near_draw_cells);
  publish("water_mask_invalid_reads", m_mask_invalid_reads);

  // ===== water-ocean-mesh-hit-counter-cost ====================================================
  // CE QUE LE SITE FAIT, DIT EN TROIS GRANDEURS QUE `hits=` CONFONDAIT.
  //   `hit_counter_calls`  : le nombre d'APPELS de `note_hit_for` emis par ce site.
  //   `hit_counter_units`  : la somme des `n` passes a ces appels, distincte des sommets sondes.
  //   `hit_counter_events` : les EVENEMENTS observes, images dessinees a couche A non plate.
  // Le 12/09, la table par feature a lu 4 536 325 248 pour `water-ocean-mesh` et cet ecart a ete
  // lu comme quatorze millions d'incrementations par seconde. Il n'y en avait qu'UNE par image :
  // 4 536 325 248 = 289 824 x 15 652, et 289 824 est le nombre d'indices des trois anneaux.
  autoport_proof::publish_text("hit_counter_site",
                               "OceanRecharged.cpp:draw/note_hit_for(water-ocean-mesh)");
  autoport_proof::publish_text("hit_counter_granularity_before",
                               "une-prise-par-INDICE-dessine-et-par-image");
  autoport_proof::publish_text("hit_counter_granularity_after", "une-prise-par-EVENEMENT");
  publish("hit_counter_calls", m_hit_calls);
  publish("hit_counter_units", m_hit_units);
  publish("hit_counter_events", m_hit_events);
  publish("hit_counter_units_per_call", m_hit_calls ? m_hit_units / m_hit_calls : 0);
  // CE QUE LE COMPTEUR PORTAIT AVANT, sur CETTE course : `m_verts_moved` accumule exactement la
  // grandeur qui partait dans `note_hit_for`. Le rapport avant/apres se lit donc sans ressortir
  // une vieille preuve.
  publish("hit_counter_units_before", m_verts_moved);
  publish("hit_counter_units_before_per_call", m_hit_calls ? m_verts_moved / m_hit_calls : 0);

  // LE COUT, MESURE. Temps PROCESSEUR du fil de dessin. `x1000` : des nanosecondes au millieme,
  // parce qu'un cout par image sous la nanoseconde s'ecrirait « 0 » en entier et se lirait
  // « gratuit ».
  publish("hit_counter_cost_samples", m_cost_samples);
  publish("hit_counter_clock_res_ns", m_clock_res_ns);
  publish("hit_counter_clock_fail", m_cost_clock_fail);
  publish("hit_counter_call_ns_total", m_cost_call_ns);
  publish("hit_counter_call_ns_max", m_cost_call_ns_max);
  publish("hit_counter_call_ns_x1000", m_hit_calls ? m_cost_call_ns * 1000 / m_hit_calls : 0);
  publish("hit_counter_floor_ns_total", m_cost_floor_ns);
  publish("hit_counter_floor_ns_x1000",
          m_cost_samples ? m_cost_floor_ns * 1000 / m_cost_samples : 0);
  publish("hit_counter_scan_ns_total", m_cost_scan_ns);
  publish("hit_counter_scan_ns_x1000", m_cost_samples ? m_cost_scan_ns * 1000 / m_cost_samples : 0);
  // L'instrument ENTIER par image : l'appel de prise plus le balayage des 1024 texels qui decide
  // s'il y a un evenement. Le brut, puis le plancher d'horloge retire — une paire de lectures par
  // region chronometree.
  const u64 brut = m_cost_call_ns + m_cost_scan_ns;
  const u64 plancher =
      m_cost_samples ? m_cost_floor_ns * (m_hit_calls + m_cost_samples) / m_cost_samples : 0;
  publish("hit_counter_instrument_ns_total", brut);
  publish("hit_counter_instrument_ns_per_frame_x1000",
          m_cost_samples ? brut * 1000 / m_cost_samples : 0);
  publish("hit_counter_instrument_net_ns_per_frame_x1000",
          (m_cost_samples && brut > plancher) ? (brut - plancher) * 1000 / m_cost_samples : 0);

  // CE QUE L'INSTRUMENT PROUVAIT CONTINUE D'ETRE PROUVE. Les quinze cles inconditionnelles de
  // `water-ocean-mesh` sont relues DANS LA TABLE QUI SERA MOISSONNEE, pas dans nos variables : une
  // cle qu'on croit avoir publiee et qu'un nom invalide a fait refuser en silence se verrait ici,
  // et nulle part ailleurs.
  static const char* const kWaterKeys[] = {"water_probe_runs",
                                           "water_probe_alpha_missing",
                                           "water_probe_span_q256",
                                           "water_layerA_absmax_q256",
                                           "water_layerA_nonzero_texels",
                                           "water_clipmap_frames",
                                           "water_clipmap_verts_moved",
                                           "water_layerA_fresh_frames",
                                           "water_layerA_stale_frames",
                                           "water_mask_skip_cells",
                                           "water_mask_draw_cells",
                                           "water_mask_valid_off0",
                                           "water_mask_valid_off4",
                                           "water_mask_index_offset",
                                           "water_mask_fallback"};
  constexpr u64 kWaterKeyCount = sizeof(kWaterKeys) / sizeof(kWaterKeys[0]);
  u64 keys_present = 0;
  for (const char* k : kWaterKeys) {
    if (autoport_proof::has_key(k)) {
      keys_present++;
    }
  }
  publish("hit_counter_water_keys_present", keys_present);
  publish("hit_counter_water_keys_expected", kWaterKeyCount);

  // LA PORTE, TERME PAR TERME. Chaque terme exige une valeur POSITIVE avant de rendre zero : une
  // porte qui ne sait dire que « rien n'est arrive » est verte par inaction.
  const u64 d_gran = (m_hit_calls > 0 && m_hit_units == m_hit_calls) ? 0 : 1;
  const u64 d_evt = (m_hit_events > 0 && m_hit_units == m_hit_events) ? 0 : 1;
  const u64 d_cost = (m_cost_samples >= 300 && m_cost_call_ns > 0 && m_cost_floor_ns > 0 &&
                      m_clock_res_ns > 0 && m_cost_clock_fail == 0)
                         ? 0
                         : 1;
  const u64 d_keys = (keys_present == kWaterKeyCount) ? 0 : 1;
  const u64 d_qty =
      (m_verts_moved > 0 && autoport_proof::has_key("water_clipmap_verts_moved")) ? 0 : 1;
  publish("hit_counter_defect_granularity", d_gran);
  publish("hit_counter_defect_events", d_evt);
  publish("hit_counter_defect_cost_unmeasured", d_cost);
  publish("hit_counter_defect_keys_lost", d_keys);
  publish("hit_counter_defect_quantity_dropped", d_qty);
  publish("hit_counter_cost_defects", d_gran + d_evt + d_cost + d_keys + d_qty);
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
    m_have_layer_a = false;
    m_layer_a_map_ptr = 0;
    return;
  }
  if (had_fresh) {
    // Association cote rendu uniquement, sans nouvelle synchronisation GOAL.
    m_layer_a_map_ptr = m_map_ptr;
  } else if (m_map_ptr != m_layer_a_map_ptr) {
    m_have_layer_a = false;
    m_layer_a_map_ptr = 0;
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
    // part plus au DMA. On garde la derniere A captee sur la meme carte ; la fraicheur
    // est mesuree separement.
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

  // Le compteur historique recense les indices soumis quand la couche A porte au moins un
  // texel non nul. Il ne mesure pas les sommets deplaces : cette grandeur est echantillonnee
  // par run_probe sur son sous-ensemble de 64 sommets, sans mesurer les fragments masques.
  // water-ocean-mesh-hit-counter-cost : le chronometre ne tourne que sous mesure.
  static const bool s_cost_measured = autoport_proof::feature_is(kCostId);
  u64 fails = 0;
  const u64 t_scan0 = s_cost_measured ? cpu_ns(&fails) : 0;
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
  const u64 t_scan1 = s_cost_measured ? cpu_ns(&fails) : 0;
  if (any_wave) {
    m_verts_moved += verts_this_frame;
    m_hit_events++;
    // LA GRANULARITE CORRIGEE. `note_hit_for` recevait `verts_this_frame`, soit 289 824 — le
    // nombre d'INDICES dessines par les trois anneaux, et non des sommets. Le compteur portait
    // donc 289 824 unites par image pour UN evenement : trois ordres de grandeur au-dessus de ce
    // qu'il observait. L'unite est desormais l'evenement lui-meme, et la grandeur qui s'y cachait
    // reste publiee, entiere, par `water_clipmap_indices_submitted`.
    const u64 t_call0 = s_cost_measured ? cpu_ns(&fails) : 0;
    autoport_proof::note_hit_for(kItemId, 1);
    const u64 t_call1 = s_cost_measured ? cpu_ns(&fails) : 0;
    m_hit_calls++;
    m_hit_units += 1;
    if (s_cost_measured && fails == 0 && t_call1 >= t_call0) {
      const u64 d = t_call1 - t_call0;
      m_cost_call_ns += d;
      if (d > m_cost_call_ns_max) {
        m_cost_call_ns_max = d;
      }
    }
  }
  if (s_cost_measured) {
    // LE PLANCHER, PRIS A LA MEME IMAGE. Deux lectures d'horloge dos a dos, rien entre elles :
    // c'est ce que l'appareil de mesure coute a lui seul. Sans ce terme, un cout de 200 ns mesure
    // avec une horloge qui en coute 150 se lirait comme un cout de l'instrument.
    const u64 f0 = cpu_ns(&fails);
    const u64 f1 = cpu_ns(&fails);
    if (fails == 0) {
      if (f1 >= f0) {
        m_cost_floor_ns += f1 - f0;
      }
      if (t_scan1 >= t_scan0) {
        m_cost_scan_ns += t_scan1 - t_scan0;
      }
      m_cost_samples++;
    }
    m_cost_clock_fail += fails;
    if (m_clock_res_ns == 0) {
      timespec r{};
      if (clock_getres(CLOCK_THREAD_CPUTIME_ID, &r) == 0) {
        m_clock_res_ns = (u64)r.tv_sec * 1000000000ull + (u64)r.tv_nsec;
      }
    }
    // LA PRISE DE CET ITEM-CI, a la granularite qu'il reclame : une par image mesuree.
    autoport_proof::note_hit_for(kCostId, 1);
  }

  // La sonde ne tourne que sur une image FRAICHE : comparer la hauteur de jeu de cette image a
  // une couche A d'il y a dix images mesurerait le retard, pas la fidelite.
  // Compter les captures fraiches : des buckets near intermittents ne doivent pas
  // rater indefiniment la sonde en arrivant entre deux multiples du total d'images.
  if (had_fresh && (m_frames_layer_a_fresh % kProbeEveryFrames) == 0) {
    run_probe(render_state);
  }
  if ((m_frames_drawn % kProbeEveryFrames) == 0) {
    publish();
  }
}
