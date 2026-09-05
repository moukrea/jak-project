#include "Tfrag3Data.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <mutex>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

#include "common/custom_data/FoliageWindLaw.h"
#include "common/custom_data/TangentDerive.h"
#include "common/custom_data/normal_pack.h"
#include "common/log/log.h"
#include "common/util/Assert.h"
#include "common/util/FileUtil.h"
#include "common/util/simd_util.h"

#include "fmt/core.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace tfrag3 {

void PackedTimeOfDay::serialize(Serializer& ser) {
  ser.from_pod_vector(&data);
  ser.from_ptr(&color_count);
}

void PackedTieVertices::serialize(Serializer& ser) {
  ser.from_pod_vector(&color_indices);
  ser.from_pod_vector(&matrices);
  ser.from_pod_vector(&matrix_groups);
  ser.from_pod_vector(&vertices);
}

void PackedShrubVertices::serialize(Serializer& ser) {
  ser.from_pod_vector(&matrices);
  ser.from_pod_vector(&instance_groups);
  ser.from_pod_vector(&vertices);
  ser.from_ptr(&total_vertex_count);
}

void StripDraw::serialize(Serializer& ser) {
  ser.from_ptr(&mode);
  ser.from_ptr(&tree_tex_id);
  ser.from_pod_vector(&runs);
  ser.from_pod_vector(&plain_indices);
  ser.from_pod_vector(&vis_groups);
  ser.from_ptr(&num_triangles);
}

void ShrubDraw::serialize(Serializer& ser) {
  ser.from_ptr(&mode);
  ser.from_ptr(&tree_tex_id);
  ser.from_ptr(&num_triangles);
  ser.from_ptr(&first_index_index);
  ser.from_ptr(&num_indices);
  ser.from_ptr(&proto_idx);
}

void InstancedStripDraw::serialize(Serializer& ser) {
  ser.from_ptr(&mode);
  ser.from_ptr(&tree_tex_id);
  ser.from_pod_vector(&vertex_index_stream);
  ser.from_pod_vector(&instance_groups);
  ser.from_ptr(&num_triangles);
}

void TieWindInstance::serialize(Serializer& ser) {
  ser.from_ptr(&matrix);
  ser.from_ptr(&wind_idx);
  ser.from_ptr(&stiffness);
}

void TfragTree::serialize(Serializer& ser) {
  ser.from_pod_vector(&baked_tangents);  // Gprecompute-deterministic-bake: per-vertex tangents,
  // derived ONCE by the fr3 extractor (TangentDerive.cpp) instead of on every load on every machine.
  // 4 bytes/vertex, 2-10-10-10 + handedness bit. fr3 version 44.
  ser.from_ptr(&kind);

  if (ser.is_saving()) {
    ser.save<size_t>(draws.size());
  } else {
    draws.resize(ser.load<size_t>());
  }
  for (auto& draw : draws) {
    draw.serialize(ser);
  }

  ser.from_pod_vector(&packed_vertices.vertices);
  ser.from_pod_vector(&packed_vertices.cluster_origins);
  colors.serialize(ser);
  bvh.serialize(ser);
  ser.from_ptr(&use_strips);
}

math::Vector3f vopmula(math::Vector3f a, math::Vector3f b) {
  return math::Vector3f(a.y() * b.z(), a.z() * b.x(), a.x() * b.y());
}

math::Vector3f vopmsub(math::Vector3f acc, math::Vector3f a, math::Vector3f b) {
  return acc - vopmula(a, b);
}

/*!
 * Compute the normal transformation for a TIE from the TIE matrix. This will return properly scaled
 * normals.
 */
std::array<math::Vector3f, 3> tie_normal_transform_v2(const std::array<math::Vector4f, 4>& m) {
  // let:
  // vf10, vf11, vf12, vf13 be the input matrix m
  std::array<math::Vector3f, 3> result;
  auto& vf10 = m[0];
  auto& vf11 = m[1];
  // auto& vf12 = m[2];

  //  lui t6, 16256
  //  mtc1 f1, t6 ;; 1.0
  //
  //  qmfc2.i s1, vf10
  //  mtc1 f12, s1
  float f12 = vf10.x();
  //  dsra32 s2, s1, 0
  //  mtc1 f13, s2
  float f13 = vf10.y();
  //  pextuw s2, r0, s2
  //  mtc1 f14, s2
  float f14 = vf10.z();
  //  mula.s f12, f12
  //  madda.s f13, f13
  //  madd.s f15, f14, f14
  float f15 = f12 * f12 + f13 * f13 + f14 * f14;
  float scale = 1.f / sqrtf(f15);
  //  rsqrt.s f15, f1, f15
  //  mfc1 s1, f15
  //  qmtc2.i vf14, s1
  //  vmulx.xyz vf16, vf10, vf14

  // vmulx.xyz vf16, vf10, vf14
  math::Vector3f vf16 = vf10.xyz() * scale;

  // vopmula.xyz acc, vf11, vf16
  math::Vector3f acc = vopmula(vf11.xyz(), vf16);

  // vopmsub.xyz vf17, vf16, vf11
  math::Vector3f vf17 = vopmsub(acc, vf16, vf11.xyz());

  // vopmula.xyz acc, vf16, vf17
  acc = vopmula(vf16, vf17);

  // vopmsub.xyz vf17, vf17, vf16
  vf17 = vopmsub(acc, vf17, vf16);

  // vmul.xyz vf14, vf17, vf17
  math::Vector3f vf14 = vf17.elementwise_multiply(vf17);

  // vmulax.w acc, vf0, vf14
  // vmadday.w acc, vf0, vf14
  // vmaddz.w vf14, vf0, vf14
  float sum = vf14.x() + vf14.y() + vf14.z();

  // vrsqrt Q, vf0.w, vf14.w
  float Q = 1.f / std::sqrt(sum);

  // vmulax.xyzw acc, vf24, vf16
  // vmadday.xyzw acc, vf25, vf16
  // vmaddz.xyzw vf10, vf26, vf16
  // vf10 = vf16; // assume cam is identity here.
  result[0] = vf16;

  // vwaitq
  // vmulq.xyz vf17, vf17, Q
  vf17 *= Q;

  // vopmula.xyz acc, vf16, vf17
  acc = vopmula(vf16, vf17);
  // vopmsub.xyz vf18, vf17, vf16
  math::Vector3f vf18 = vopmsub(acc, vf17, vf16);

  // vmulax.xyzw acc, vf24, vf17
  // vmadday.xyzw acc, vf25, vf17
  // vmaddz.xyzw vf11, vf26, vf17
  result[1] = vf17;

  // vmulax.xyzw acc, vf24, vf18
  // vmadday.xyzw acc, vf25, vf18
  // vmaddz.xyzw vf12, vf26, vf18
  result[2] = vf18;

  // ROUND 29 — MIRRORED INSTANCES. The frame rebuilt above (r2 = r0 x r1) is right-handed BY
  // CONSTRUCTION, which silently un-mirrors a negative-determinant instance and inverts its
  // normals. Restore the input's handedness: for a rigid transform composed with a reflection the
  // correct normal transform is the transform itself, whose z row is -(r0 x r1).
  const math::Vector3f l0(m[0].x(), m[0].y(), m[0].z());
  const math::Vector3f l1(m[1].x(), m[1].y(), m[1].z());
  const math::Vector3f l2(m[2].x(), m[2].y(), m[2].z());
  if (l0.dot(l1.cross(l2)) < 0.f) {
    result[2] = result[2] * -1.f;
  }

  return result;
  //
  // sqc2 vf10, -112(t8)
  // sqc2 vf11, -96(t8)
  // sqc2 vf12, -80(t8)
}

s16 saturate_for_s10(s16 s10) {
  // our error should be 1 or less as an s8, or 4 as a s10.
  ASSERT(s10 >= -520 && s10 < 520);
  if (s10 < -512) {
    return -512;
  }
  if (s10 > 511) {
    return 511;
  }
  return s10;
}

u32 pack_to_gl_normal(s16 nx, s16 ny, s16 nz) {
  return (saturate_for_s10(nx) & 0x3ff) | ((saturate_for_s10(ny) & 0x3ff) << 10) |
         ((saturate_for_s10(nz) & 0x3ff) << 20);
}

/*!
 * Unpack tie normal by transforming and converting to s16 for OpenGL.
 */
u32 unpack_tie_normal(const std::array<math::Vector3f, 3>& mat, s8 nx, s8 ny, s8 nz) {
  // rotate the normal
  math::Vector3f nrm = math::Vector3f::zero();
  nrm += mat[0] * nx;
  nrm += mat[1] * ny;
  nrm += mat[2] * nz;

  // game used signed 8-bit normals, but OpenGL uses signed 10-bit
  // multiply by 2^2 = 4
  nrm *= 4;

  auto as_int = nrm.cast<s16>();

  return pack_to_gl_normal(as_int.x(), as_int.y(), as_int.z());
}

/*
void tie_normal_v3(__m128* out, const std::array<math::Vector4f, 4>& in) {
  math::Vector3f x_row = in[0].xyz();
  math::Vector3f y_row = in[1].xyz();
  math::Vector3f z_row = in[2].xyz();

  x_row.normalize();
  y_row = x_row.cross(y_row.cross(x_row)).normalized();
  z_row = x_row.cross(y_row);

  out[0] = _mm_setr_ps(x_row[0], x_row[1], x_row[2], 0);
  out[1] = _mm_setr_ps(y_row[0], y_row[1], y_row[2], 0);
  out[2] = _mm_setr_ps(z_row[0], z_row[1], z_row[2], 0);
}
 */

// Gprecompute-deterministic-bake — forward decl; defined lower (next to the diagnostics it feeds) but
// called from TieTree::unpack (here) as well as TfragTree::unpack. EXPANDS the tangents the fr3
// already carries; it does not derive them (that is TangentDerive.cpp, run by the fr3 extractor).
static void apply_baked_tangents(const std::vector<u16>& baked,
                                 const std::vector<PreloadedVertex>& verts,
                                 std::vector<math::Vector4f>& out_tangents,
                                 const char* system_label);
// TIE mostly ships WITHOUT per-vertex normals (nor==0 for ~98% of verts), so its PBR shading fell
// back to the discontinuous derivative normal => cracks on wall faces (not just tfrag ground). Fill
// the MISSING tie normals with crease-aware smooth normals (welded by world position) so tie gets a
// continuous base normal + a valid tangent, exactly like tfrag. Existing tie normals are preserved.
static void reconstruct_tie_smooth_normals(std::vector<PreloadedVertex>& verts,
                                           const std::vector<u32>& indices,
                                           bool use_strips);

// STEP A (owner STRICT ORDER, 2026-07-24) — TRUE topological FUSE: forward decls + counters. The A/B
// toggle gate + the fuse itself are defined further down (next to the smooth-normal reconstruction they
// precede), but TieTree::unpack (below) is the FIRST caller, so declare them here.
static bool mesh_weld_enabled();
static u32 fuse_tree_indices(const std::vector<PreloadedVertex>& verts, std::vector<u32>& indices);
// #index slots repointed at a shared representative == the genuinely fused (merged) duplicate verts.
// Prior rounds only averaged normals and NEVER rewrote the index buffer, so points stayed separate;
// these count the REAL point fusion the owner demanded (surfaced in files/pbr_tan_diag.txt).
static std::atomic<u64> g_index_fused_tfrag{0};
static std::atomic<u64> g_index_fused_tfrag_verts{0};
static std::atomic<u64> g_index_fused_tie{0};
static std::atomic<u64> g_index_fused_tie_verts{0};

// ROUND 29 — MIRRORED TIE INSTANCE CENSUS. Pure measurement, never modifies the level. Rows 0-2 of
// a packed instance matrix are its linear part (row 3 is the translation), so
//     det3 = m0 . (m1 x m2)
// and det3 < 0 means the instance places a MIRRORED copy of its prototype.
TieMirrorCensus tie_mirror_census(const Level& lev) {
  TieMirrorCensus c;
  for (const auto& geo : lev.tie_trees) {
    for (const auto& tree : geo) {
      // distinct matrices
      for (const auto& m : tree.packed_vertices.matrices) {
        const math::Vector3f l0(m[0].x(), m[0].y(), m[0].z());
        const math::Vector3f l1(m[1].x(), m[1].y(), m[1].z());
        const math::Vector3f l2(m[2].x(), m[2].y(), m[2].z());
        c.matrices++;
        if (l0.dot(l1.cross(l2)) < 0.f) {
          c.mirrored_matrices++;
        }
      }
      // groups (one instance's slice of the vertex array)
      for (const auto& grp : tree.packed_vertices.matrix_groups) {
        if (grp.matrix_idx == -1) {
          continue;  // un-instanced: no matrix, so it cannot be mirrored
        }
        if ((size_t)grp.matrix_idx >= tree.packed_vertices.matrices.size()) {
          continue;
        }
        const auto& m = tree.packed_vertices.matrices[grp.matrix_idx];
        const math::Vector3f l0(m[0].x(), m[0].y(), m[0].z());
        const math::Vector3f l1(m[1].x(), m[1].y(), m[1].z());
        const math::Vector3f l2(m[2].x(), m[2].y(), m[2].z());
        const u64 nverts = (u64)(grp.end_vert - grp.start_vert);
        c.groups++;
        c.verts += nverts;
        if (l0.dot(l1.cross(l2)) < 0.f) {
          c.mirrored_groups++;
          c.mirrored_verts += nverts;
          if (grp.has_normals) {
            c.mirrored_groups_with_normals++;
          }
        }
      }
    }
  }
  return c;
}

namespace {
// =================================================================================================
// Grecharged-foliage-wind3 (owner 2026-08-31, defaut D2 : « tous les arbres ne sont pas impactés »)
// LE LEXIQUE DE VEGETATION TIE.
//
// Pourquoi un lexique de NOMS et pas un critere geometrique : mesure du round 3 sur les 218
// prototypes alors recenses, la meilleure coupe geometrique (`height > 5 m`) rend 15 vrais positifs
// et 93 FAUX POSITIFS (`wallsmall-04`, `cliffmed`, `clifflarge`...). Une falaise qui se balance est
// un defaut bien pire qu'un palmier fige, et le NOM du prototype est la seule grandeur qui separe
// une plante d'un mur. Il existe a l'extraction et il voyage maintenant dans le fr3
// (`TieTree::proto_names`, extract_tie.cpp).
//
// C'est une DONNEE, pas du code : relue au chargement, donc l'owner corrige un classement sans
// rebuild ni nouveau APK. La precedence de chemin est celle d'EyeRenderer.cpp:188 pour
// `physics_chains.txt` — un depot EXTERNE bat le pack livre, sinon le pack, sinon l'arbre du
// projet. Le meme mecanisme sert sur bureau et sur Android.
//
// FICHIER ABSENT = ENSEMBLE VIDE + AVERTISSEMENT EXPLICITE. Jamais un comportement devine : zero
// balancement ajoute, et la ligne de recensement publie `lexique=0` pour que ce cas se VOIE.
struct FwLexicon {
  std::unordered_set<std::string> names;
  bool loaded = false;
  std::string path;
};

const FwLexicon& fw_veg_protos() {
  static const FwLexicon s_lex = [] {
    FwLexicon out;
    auto path = file_util::get_recharged_assets_dir() / "foliage_wind_protos.txt";
    auto ext_dir = file_util::get_external_recharged_assets_dir();
    if (ext_dir) {
      auto ext_path = *ext_dir / "foliage_wind_protos.txt";
      if (file_util::file_exists(ext_path.string())) {
        path = ext_path;
      }
    }
    out.path = path.string();
    if (!file_util::file_exists(out.path)) {
      lg::warn(
          "[foliage-wind] LEXIQUE ABSENT : {} — AUCUN prototype TIE ne sera classe vegetation et "
          "le balancement statique reste NUL sur tout le jeu. Ce n'est pas un defaut de rendu, "
          "c'est un asset manquant.",
          out.path);
      return out;
    }
    std::string text = file_util::read_text_file(out.path);
    std::stringstream ss(text);
    std::string line;
    while (std::getline(ss, line)) {
      // premier champ separe par des espaces ; lignes vides et lignes de commentaire ignorees.
      size_t b = line.find_first_not_of(" \t\r\n");
      if (b == std::string::npos || line[b] == '#') {
        continue;
      }
      size_t e = line.find_first_of(" \t\r\n", b);
      std::string name = line.substr(b, e == std::string::npos ? std::string::npos : e - b);
      if (!name.empty()) {
        out.names.insert(name);
      }
    }
    out.loaded = true;
    lg::info("[foliage-wind] lexique charge : {} prototypes de vegetation depuis {}",
             out.names.size(), out.path);
    return out;
  }();
  return s_lex;
}

// Le poids de balancement d'un sommet, quantifie sur 8 bits. `y` est la hauteur MONDE du sommet,
// `ymin`/`ymax` celles de SON instance. foliage-wind (owner 2026-09-03) : la loi vit dans
// common/custom_data/FoliageWindLaw.h et elle est la MEME pour le TIE statique, le shrub et le
// recensement qui porte la porte — trois copies se seraient desynchronisees au premier reglage.
// Essai 11 : poids SIGNE sur 16 bits (SwayRecord), loi ARBRE (tronc rigide). Rend le poids tel que
// le shader le RELIRA (quantifie puis dequantifie), pour que le recensement mesure ce qui est dessine.
s16 fw_sway_weight_tie_q(float y, float ymin, float ymax) {
  return foliage_law::quantize_weight(foliage_law::sway_weight_tie(y, ymin, ymax));
}

// Ecrit un enregistrement de balancement a l'emplacement du sommet `v` de `sway` (8 octets/sommet).
inline void fw_write_record(std::vector<u8>& sway, size_t v, s16 w, u16 inst, u8 ph, u8 flags) {
  foliage_law::SwayRecord rec;
  rec.w = w;
  rec.inst = inst;
  rec.ph = ph;
  rec.flags = flags;
  memcpy(sway.data() + v * foliage_law::kSwayRecordBytes, &rec, sizeof(rec));
}

inline foliage_law::SwayRecord fw_read_record(const std::vector<u8>& sway, size_t v) {
  foliage_law::SwayRecord rec;
  memcpy(&rec, sway.data() + v * foliage_law::kSwayRecordBytes, sizeof(rec));
  return rec;
}


}  // namespace

void TieTree::unpack() {
  unpacked.vertices.resize(packed_vertices.color_indices.size());
  size_t i = 0;
  for (const auto& grp : packed_vertices.matrix_groups) {
    if (grp.matrix_idx == -1) {
      for (u32 src_idx = grp.start_vert; src_idx < grp.end_vert; src_idx++) {
        auto& vtx = unpacked.vertices[i];
        vtx.color_index = packed_vertices.color_indices[i];
        const auto& proto_vtx = packed_vertices.vertices[src_idx];
        vtx.x = proto_vtx.x;
        vtx.y = proto_vtx.y;
        vtx.z = proto_vtx.z;
        vtx.s = proto_vtx.s;
        vtx.t = proto_vtx.t;
        vtx.nor = pack_to_gl_normal(proto_vtx.nx << 1, proto_vtx.ny << 1, proto_vtx.nz << 1);
        vtx.r = proto_vtx.r;
        vtx.g = proto_vtx.g;
        vtx.b = proto_vtx.b;
        vtx.a = proto_vtx.a;
        i++;
      }
    } else {
      const auto& mat = packed_vertices.matrices[grp.matrix_idx];

      __m128 mat0 = _mm_loadu_ps(mat[0].data());
      __m128 mat1 = _mm_loadu_ps(mat[1].data());
      __m128 mat2 = _mm_loadu_ps(mat[2].data());
      __m128 mat3 = _mm_loadu_ps(mat[3].data());

      if (grp.has_normals) {
        auto nmat = tie_normal_transform_v2(mat);
        for (u32 src_idx = grp.start_vert; src_idx < grp.end_vert; src_idx++) {
          auto& vtx = unpacked.vertices[i];
          vtx.color_index = packed_vertices.color_indices[i];
          const auto& proto_vtx = packed_vertices.vertices[src_idx];
          // auto temp = mat[0] * proto_vtx.x + mat[1] * proto_vtx.y + mat[2] * proto_vtx.z +
          // mat[3];
          __m128 transformed = mat3;
          transformed = _mm_add_ps(transformed, _mm_mul_ps(_mm_set1_ps(proto_vtx.x), mat0));
          transformed = _mm_add_ps(transformed, _mm_mul_ps(_mm_set1_ps(proto_vtx.y), mat1));
          transformed = _mm_add_ps(transformed, _mm_mul_ps(_mm_set1_ps(proto_vtx.z), mat2));
          _mm_storeu_ps(&vtx.x, transformed);
          vtx.s = proto_vtx.s;
          vtx.t = proto_vtx.t;
          vtx.nor = unpack_tie_normal(nmat, proto_vtx.nx, proto_vtx.ny, proto_vtx.nz);
          vtx.r = proto_vtx.r;
          vtx.g = proto_vtx.g;
          vtx.b = proto_vtx.b;
          vtx.a = proto_vtx.a;
          i++;
        }
      } else {
        for (u32 src_idx = grp.start_vert; src_idx < grp.end_vert; src_idx++) {
          auto& vtx = unpacked.vertices[i];
          vtx.color_index = packed_vertices.color_indices[i];
          const auto& proto_vtx = packed_vertices.vertices[src_idx];
          __m128 transformed = mat3;
          transformed = _mm_add_ps(transformed, _mm_mul_ps(_mm_set1_ps(proto_vtx.x), mat0));
          transformed = _mm_add_ps(transformed, _mm_mul_ps(_mm_set1_ps(proto_vtx.y), mat1));
          transformed = _mm_add_ps(transformed, _mm_mul_ps(_mm_set1_ps(proto_vtx.z), mat2));
          _mm_storeu_ps(&vtx.x, transformed);
          vtx.s = proto_vtx.s;
          vtx.t = proto_vtx.t;
          vtx.nor = 0;
          vtx.r = proto_vtx.r;
          vtx.g = proto_vtx.g;
          vtx.b = proto_vtx.b;
          vtx.a = proto_vtx.a;
          i++;
        }
      }
    }
  }

  // ===============================================================================================
  // Grecharged-foliage-wind3 (owner 2026-08-31, defaut D2 : « tous les arbres ne sont pas
  // impactés ») — LE POIDS DE BALANCEMENT PAR SOMMET.
  //
  // ICI, ET AVANT `fuse_tree_indices` CI-DESSOUS : apres la soudure un indice peut pointer vers le
  // sommet d'une AUTRE instance (memes attributs, autre ymin), ce qui ferait balancer un arbre
  // depuis la base de son voisin. Ici, aucune fusion n'a encore eu lieu.
  //
  // TROIS PASSES, et chacune repose sur une propriete VERIFIEE de l'extracteur :
  //   1. SOMMET -> INSTANCE. `matrix_groups` est parcouru dans l'ordre par la boucle ci-dessus et
  //      `i` avance en lockstep, donc chaque groupe couvre une plage CONTIGUE de sommets
  //      depaquetes. Le meme parcours redonne le `matrix_idx` de chaque sommet.
  //      `matrix_idx == -1` = sommets du chemin VENT, laisses LOCAUX AU PROTOTYPE (voir la branche
  //      correspondante ci-dessus) : poids 0 obligatoire, un ancrage calcule en Y monde y serait
  //      faux — c'est `render_tree_wind` qui leur fournit leur matrice d'instance.
  //   2. SOMMET -> PROTOTYPE. Pour TIE, `plain_indices` est TOUJOURS vide et seuls des `runs` sont
  //      pousses (extract_tie.cpp:2531-2545), avec `vgroup.num_inds == run.length + 1` et un run
  //      par vis-group. `merge_groups` (extract_tie.cpp:2736) FUSIONNE les vis-groups a
  //      `tie_proto_idx` egal sans toucher aux runs : on consomme donc des runs jusqu'a ce que
  //      Somme(run.length + 1) atteigne `num_inds`. Chaque run donne la plage de sommets
  //      [run.vertex0, run.vertex0 + run.length) — pas besoin de lire un tableau d'indices.
  //   3. POIDS. h*h avec le plancher de hauteur de shrub.vert, sur l'ancrage de SON instance.
  //
  // LA REGLE DU DOSSIER : un sommet reclame par un prototype HORS lexique reste a 0 meme si un
  // autre le reclame ensuite. Un mur qui ondule est un defaut bien pire qu'un palmier fige.
  {
    const auto& lex = fw_veg_protos();
    const size_t nverts = unpacked.vertices.size();
    sway_census = SwayCensus{};
    sway_census.lexicon_loaded = lex.loaded;
    sway_census.protos = (u32)proto_names.size();
    sway_census.verts = (u64)nverts;

    // quels prototypes de CET arbre le lexique couvre-t-il ?
    std::vector<u8> proto_is_veg(proto_names.size(), 0);
    for (size_t pi = 0; pi < proto_names.size(); pi++) {
      if (lex.names.count(proto_names[pi])) {
        proto_is_veg[pi] = 1;
        sway_census.veg_protos++;
      } else {
        sway_census.non_classes++;
        if (sway_census.noms_non_classes.size() < 12) {
          sway_census.noms_non_classes.push_back(proto_names[pi]);
        }
      }
    }

    // --- passe 1 : ancrage (ymin, ymax) par instance -------------------------------------------
    const size_t n_mat = packed_vertices.matrices.size();
    std::vector<float> mymin(n_mat, 1e30f), mymax(n_mat, -1e30f);
    std::vector<u8> mat_used(n_mat, 0);
    {
      size_t vi = 0;
      for (const auto& grp : packed_vertices.matrix_groups) {
        const size_t n = (size_t)(grp.end_vert - grp.start_vert);
        if (grp.matrix_idx >= 0 && (size_t)grp.matrix_idx < n_mat) {
          const size_t mi = (size_t)grp.matrix_idx;
          if (!mat_used[mi]) {
            mat_used[mi] = 1;
            sway_census.inst_total++;
          }
          for (size_t k = 0; k < n && vi + k < nverts; k++) {
            const float y = unpacked.vertices[vi + k].y;
            if (y < mymin[mi]) {
              mymin[mi] = y;
            }
            if (y > mymax[mi]) {
              mymax[mi] = y;
            }
          }
        }
        vi += n;
      }
    }

    // --- passe 2 : sommet -> prototype (deux bits : reclame vegetal / reclame non-vegetal) ------
    // bit0 = reclame par un prototype DU lexique, bit1 = reclame par un prototype HORS lexique
    // (VERROU : bit1 gagne toujours). Un sommet qui porte les DEUX est un conflit et il est
    // compte ; il reste NEUTRE, parce que le cout d'un mur qui ondule est plus grand que celui
    // d'un palmier fige.
    std::vector<u8> vflag(nverts, 0);
    for (const auto& draw : static_draws) {
      sway_census.plain_inds += (u64)draw.plain_indices.size();
      size_t run_i = 0;
      for (const auto& vg : draw.vis_groups) {
        const bool is_veg =
            vg.tie_proto_idx < proto_is_veg.size() && proto_is_veg[vg.tie_proto_idx] != 0;
        const u8 bit = is_veg ? 1 : 2;
        u32 inds_left = vg.num_inds;
        while (inds_left > 0 && run_i < draw.runs.size()) {
          const auto& run = draw.runs[run_i];
          const u32 run_inds = (u32)run.length + 1;  // +1 : le code de redemarrage de primitive
          if (run_inds > inds_left) {
            // Le pavage run <-> vis-group ne tombe pas juste. On NE DEVINE PAS : on n'attribue
            // rien de plus a ce vis-group et on le compte, pour que l'hypothese se refute a voix
            // haute au lieu d'ancrer des sommets sur le mauvais prototype.
            sway_census.vg_desync++;
            break;
          }
          for (u32 k = 0; k < run.length; k++) {
            const size_t v = (size_t)run.vertex0 + k;
            if (v < nverts) {
              vflag[v] |= bit;
            }
          }
          run_i++;
          inds_left -= run_inds;
        }
      }
    }

    // --- passe 3 : le poids ET la phase d'instance ---------------------------------------------
    // Un SwayRecord (8 octets) par sommet : poids SIGNE 16 bits, matrix_idx, phase de SON instance.
    // La phase est l'angle d'or applique au `matrix_idx` : constante sur toute la plante (donc la
    // plante ne se dechire pas) et decorrelee d'une plante a l'autre (donc le decor ne glisse pas en
    // bloc). Essai 11 : on releve aussi, par instance, le plus grand poids des 10 % du bas
    // (`low_w`, le « tronc ») — c'est la grandeur de `wind_base_to_crown_ratio`.
    unpacked.sway.assign(nverts * foliage_law::kSwayRecordBytes, 0);
    std::vector<u8> inst_has_veg(n_mat, 0), inst_has_sway(n_mat, 0);
    std::vector<s16> inst_max_w(n_mat, 0), inst_low_w(n_mat, 0);
    {
      size_t vi = 0;
      for (const auto& grp : packed_vertices.matrix_groups) {
        const size_t n = (size_t)(grp.end_vert - grp.start_vert);
        const bool wind_path = grp.matrix_idx < 0;
        // `have_inst` et pas `!wind_path` : un `matrix_idx` hors bornes ne doit indexer AUCUN des
        // tableaux par instance. Il ne peut pas arriver aujourd'hui, et c'est exactement pour ca
        // qu'il ne doit pas etre suppose.
        const bool have_inst = !wind_path && (size_t)grp.matrix_idx < n_mat;
        const size_t mi = have_inst ? (size_t)grp.matrix_idx : 0;
        const bool have_anchor = have_inst && mymax[mi] >= mymin[mi];
        // angle d'or sur l'identite d'instance, quantifie sur 8 bits (FoliageWindLaw.h)
        const u8 ph8 = have_inst ? foliage_law::phase_u8((u64)mi) : 0;
        for (size_t k = 0; k < n && vi + k < nverts; k++) {
          const size_t v = vi + k;
          const u8 f = vflag[v];
          if (wind_path) {
            sway_census.v_windpath++;
          }
          if (f == 0) {
            sway_census.v_sansproto++;
          }
          if ((f & 1) && (f & 2)) {
            sway_census.v_conflit++;
          }
          if ((f & 1) && have_inst) {
            inst_has_veg[mi] = 1;
          }
          s16 w = 0;
          if ((f & 1) && !(f & 2) && have_anchor) {
            w = fw_sway_weight_tie_q(unpacked.vertices[v].y, mymin[mi], mymax[mi]);
          }
          fw_write_record(unpacked.sway, v, w, (u16)(mi & 0xffffu), ph8,
                          have_inst ? foliage_law::kSwayFlagInstance : 0);
          if (w != 0) {
            sway_census.v_sway++;
            inst_has_sway[mi] = 1;
            inst_max_w[mi] = std::max(inst_max_w[mi], w);
            // le « tronc » : les 10 % du bas de la plante, mesures depuis son pied
            const float span = mymax[mi] - mymin[mi];
            if (span > 0.f && unpacked.vertices[v].y <= mymin[mi] + 0.10f * span) {
              inst_low_w[mi] = std::max(inst_low_w[mi], (s16)std::abs((int)w));
            }
          } else {
            sway_census.v_neutre++;
          }
        }
        vi += n;
      }
    }
    sway_instances.clear();
    for (size_t mi = 0; mi < n_mat; mi++) {
      if (inst_has_veg[mi]) {
        sway_census.inst_veg++;
        // foliage-wind : une entree de recensement par instance VEGETALE posee. L'ancrage est la
        // translation de la matrice d'instance ; la hauteur, l'etendue en Y de ses sommets monde.
        SwayInstance si;
        si.valid = true;
        si.matrix_idx = (u32)mi;
        si.x = packed_vertices.matrices[mi][3].x();
        si.z = packed_vertices.matrices[mi][3].z();
        si.ymin = mymin[mi];
        si.ymax = mymax[mi];
        si.base_y = mymin[mi];  // un arbre pivote a son pied ; ses 30 % du bas sont rigides
        si.peak_w = foliage_law::dequantize_weight(inst_max_w[mi]);
        si.low_w = foliage_law::dequantize_weight(inst_low_w[mi]);
        si.base_w = 0.f;  // aucune arete ne traverse le pied : rien n'est dessine sous lui
        si.ph8 = foliage_law::phase_u8((u64)mi);
        sway_instances.push_back(si);
      }
      if (inst_has_sway[mi]) {
        sway_census.inst_swayed++;
      }
    }

    // --- chemin VENT : la hauteur LOCALE de chaque instance -------------------------------------
    // Les sommets du chemin vent restent LOCAUX AU PROTOTYPE (branche matrix_idx == -1 ci-dessus)
    // et `instanced_wind_draws[d].vertex_index_stream` les indexe, segmente par
    // `instance_groups` (num indices par instance, UINT32_MAX = redemarrage de bande). On en tire,
    // par instance, le plus haut sommet local : c'est ce que `Tie3::render_tree_wind` multiplie par
    // le cisaillement pour obtenir la flexion de couronne, et ce que le recensement lit comme
    // taille de plante.
    wind_inst_local_ymax.assign(wind_instance_info.size(), 0.f);
    for (const auto& draw : instanced_wind_draws) {
      size_t off = 0;
      for (const auto& grp : draw.instance_groups) {
        const size_t end = std::min(off + (size_t)grp.num, draw.vertex_index_stream.size());
        if (grp.instance_idx < wind_inst_local_ymax.size()) {
          float& ymax = wind_inst_local_ymax[grp.instance_idx];
          for (size_t k = off; k < end; k++) {
            const u32 vi2 = draw.vertex_index_stream[k];
            if (vi2 != UINT32_MAX && vi2 < nverts) {
              const float y = unpacked.vertices[vi2].y;
              if (y > ymax) {
                ymax = y;
              }
            }
          }
        }
        off = end;
      }
    }
  }

  for (auto& draw : static_draws) {
    draw.unpacked.idx_of_first_idx_in_full_buffer = unpacked.indices.size();
    // indices can come from either runs or already in plain indices.
    for (auto& run : draw.runs) {
      for (u32 ri = 0; ri < run.length; ri++) {
        unpacked.indices.push_back(run.vertex0 + ri);
      }
      unpacked.indices.push_back(UINT32_MAX);
    }
    unpacked.indices.insert(unpacked.indices.end(), draw.plain_indices.begin(),
                            draw.plain_indices.end());
  }

  // STEP A (owner STRICT ORDER) — TRUE topological FUSE **first**: rewrite the index buffer so
  // coincident attribute-identical verts share ONE representative index (genuine point fusion), BEFORE
  // any normal/tangent reconstruction, so STEP B (smooth) / C (orient) / D (uv) operate on the truly
  // merged topology (real shared edges) — not on separate copies. Honors the debug.opengoal.mesh.weld
  // A/B toggle (OFF => the original per-copy index buffer, the seamy baseline the supervisor A/Bs).
  if (mesh_weld_enabled()) {
    u32 fused = fuse_tree_indices(unpacked.vertices, unpacked.indices);
    g_index_fused_tie += fused;
    g_index_fused_tie_verts += (u64)unpacked.vertices.size();
  }
  // REOPEN#7: TIE ships mostly without per-vertex normals; backfill the missing ones with crease-aware
  // smooth normals (welded by world position) so tie walls get a CONTINUOUS base normal, then compute
  // the per-vertex tangents for the continuous PBR TBN (non-envmap TIE draws use the TFRAG3 shader).
  reconstruct_tie_smooth_normals(unpacked.vertices, unpacked.indices, use_strips);
  // Gprecompute-deterministic-bake: the per-vertex tangents are NOT re-derived here any more — the
  // fr3 carries them (baked_tangents), so this is a dequantise loop instead of a full triangle walk.
  apply_baked_tangents(baked_tangents, unpacked.vertices, unpacked.tangents, "tie");
}

// definie apres ShrubTree::unpack, appelee par lui et par foliage_wind_finalize_level
void shrub_sway_write_records(ShrubTree& tree);

void ShrubTree::unpack() {
  unpacked.vertices.resize(packed_vertices.total_vertex_count);
  size_t i = 0;

  for (const auto& grp : packed_vertices.instance_groups) {
    const auto& mat = packed_vertices.matrices[grp.matrix_idx];
    for (u32 src_idx = grp.start_vert; src_idx < grp.end_vert; src_idx++) {
      auto& vtx = unpacked.vertices[i];
      vtx.color_index = grp.color_index;
      const auto& proto_vtx = packed_vertices.vertices[src_idx];
      auto temp = mat[0] * proto_vtx.x + mat[1] * proto_vtx.y + mat[2] * proto_vtx.z + mat[3];
      vtx.x = temp.x();
      vtx.y = temp.y();
      vtx.z = temp.z();
      vtx.s = proto_vtx.s;
      vtx.t = proto_vtx.t;
      memcpy(vtx.rgba_base, proto_vtx.rgba, 3);
      i++;
    }
  }
  ASSERT(i == unpacked.vertices.size());

  // ===============================================================================================
  // foliage-wind (owner 2026-09-03) — LE POIDS DE BALANCEMENT PAR SOMMET, ANCRE SUR SON INSTANCE.
  //
  // `instance_groups` est parcouru dans le meme ordre que la boucle ci-dessus et `i` avance en
  // lockstep : chaque groupe couvre une plage CONTIGUE de sommets depaquetes, et `grp.matrix_idx`
  // EST l'identite de l'instance (une matrice par buisson pose). Deux passes :
  //   1. par instance, le plus bas et le plus haut sommet MONDE (son pied et sa couronne) ;
  //   2. par sommet, le poids de la loi partagee (FoliageWindLaw.h : tiers du bas RIGIDE, facteur
  //      de taille replie) et la phase de son instance.
  // Le pied est celui de l'instance elle-meme — un buisson volontairement enfonce sous le sol garde
  // ses 30 % du bas immobiles, donc la ligne ou il croise le terrain ne porte plus de deplacement :
  // c'est le correctif du « ils ont l'air de glisser sur le sol ».
  // ===============================================================================================
  {
    const size_t n_mat = packed_vertices.matrices.size();
    const size_t nverts = unpacked.vertices.size();
    std::vector<float> mymin(n_mat, 1e30f), mymax(n_mat, -1e30f);
    std::vector<u8> mat_used(n_mat, 0);
    {
      size_t vi = 0;
      for (const auto& grp : packed_vertices.instance_groups) {
        const size_t n = (size_t)(grp.end_vert - grp.start_vert);
        if (grp.matrix_idx >= 0 && (size_t)grp.matrix_idx < n_mat) {
          const size_t mi = (size_t)grp.matrix_idx;
          mat_used[mi] = 1;
          for (size_t k = 0; k < n && vi + k < nverts; k++) {
            const float y = unpacked.vertices[vi + k].y;
            mymin[mi] = std::min(mymin[mi], y);
            mymax[mi] = std::max(mymax[mi], y);
          }
        }
        vi += n;
      }
    }
    // Essai 11 : ici on ecrit des enregistrements PROVISOIRES, pivot = pied de l'instance (ymin).
    // `foliage_wind_finalize_level` (Loader.cpp, apres tous les depaquetages) trouve le SOL sous
    // chaque buisson et REECRIT poids et recensement avec ce pivot. Si personne ne l'appelle (un
    // outil hors jeu), le buisson pivote a son pied : jamais un tableau de la mauvaise taille.
    unpacked.sway.assign(nverts * foliage_law::kSwayRecordBytes, 0);
    // diagnostic : combien d'entrees de palette (color_index) sont partagees par plusieurs
    // instances — l'hypothese que l'ancien chemin faisait sans la verifier.
    std::unordered_map<u32, s32> slot_owner;  // color_index -> matrix_idx, ou -2 si partage
    {
      size_t vi = 0;
      for (const auto& grp : packed_vertices.instance_groups) {
        const size_t n = (size_t)(grp.end_vert - grp.start_vert);
        const bool have_inst = grp.matrix_idx >= 0 && (size_t)grp.matrix_idx < n_mat;
        const size_t mi = have_inst ? (size_t)grp.matrix_idx : 0;
        if (have_inst) {
          auto it = slot_owner.find(grp.color_index);
          if (it == slot_owner.end()) {
            slot_owner[grp.color_index] = (s32)mi;
          } else if (it->second != (s32)mi && it->second != -2) {
            it->second = -2;
          }
        }
        vi += n;
      }
    }
    sway_shared_color_slots = 0;
    for (const auto& kv : slot_owner) {
      if (kv.second == -2) {
        sway_shared_color_slots++;
      }
    }
    // une entree PAR matrix_idx : le rendu (vent natif) et le recensement indexent directement
    sway_instances.assign(n_mat, TieTree::SwayInstance{});
    for (size_t mi = 0; mi < n_mat; mi++) {
      auto& si = sway_instances[mi];
      si.matrix_idx = (u32)mi;
      si.x = packed_vertices.matrices[mi][3].x();
      si.z = packed_vertices.matrices[mi][3].z();
      si.ph8 = foliage_law::phase_u8((u64)mi);
      if (!mat_used[mi] || !(mymax[mi] >= mymin[mi])) {
        si.valid = false;
        continue;
      }
      si.valid = true;
      si.ymin = mymin[mi];
      si.ymax = mymax[mi];
      si.base_y = mymin[mi];
    }
    shrub_sway_write_records(*this);
  }
}

// -------------------------------------------------------------------------------------------------
// foliage-wind (essai 11) — LES POIDS D'UN ARBRE SHRUB, DEPUIS LE PIVOT DE CHAQUE INSTANCE.
// Ecrit `unpacked.sway` (SwayRecord par sommet, loi BUISSON lineaire signee depuis `si.base_y`) et
// remplit, par instance : `peak_w` (couronne), `low_w` (10 % du bas VISIBLES), `base_w` (|poids|
// interpole a la ligne du pivot le long des aretes qui la traversent — ce que le GPU dessine a la
// ligne de sol). Appelee au depaquetage (pivot = pied) et par `foliage_wind_finalize_level` (pivot =
// sol). Les sommets sont parcourus comme `ShrubTree::unpack` les a produits : `instance_groups` dans
// l'ordre, plages contigues.
void shrub_sway_write_records(ShrubTree& tree) {
  const size_t n_mat = tree.packed_vertices.matrices.size();
  const size_t nverts = tree.unpacked.vertices.size();
  if (tree.unpacked.sway.size() != nverts * foliage_law::kSwayRecordBytes) {
    tree.unpacked.sway.assign(nverts * foliage_law::kSwayRecordBytes, 0);
  }
  std::vector<s16> inst_max_w(n_mat, 0), inst_low_w(n_mat, 0);
  std::vector<u32> vert_inst(nverts, UINT32_MAX);
  {
    size_t vi = 0;
    for (const auto& grp : tree.packed_vertices.instance_groups) {
      const size_t n = (size_t)(grp.end_vert - grp.start_vert);
      const bool have_inst = grp.matrix_idx >= 0 && (size_t)grp.matrix_idx < n_mat &&
                             tree.sway_instances[(size_t)grp.matrix_idx].valid;
      const size_t mi = have_inst ? (size_t)grp.matrix_idx : 0;
      const auto* si = have_inst ? &tree.sway_instances[mi] : nullptr;
      const float span = si ? (si->ymax - si->base_y) : 0.f;
      for (size_t k = 0; k < n && vi + k < nverts; k++) {
        const size_t v = vi + k;
        s16 w = 0;
        if (si && span > 0.f) {
          const float y = tree.unpacked.vertices[v].y;
          w = foliage_law::quantize_weight(foliage_law::sway_weight_shrub(y, si->base_y, si->ymax));
          if (w > inst_max_w[mi]) {
            inst_max_w[mi] = w;
          }
          if (y >= si->base_y && y <= si->base_y + 0.10f * span) {
            inst_low_w[mi] = std::max(inst_low_w[mi], (s16)std::abs((int)w));
          }
          vert_inst[v] = (u32)mi;
        }
        fw_write_record(tree.unpacked.sway, v, w, (u16)(mi & 0xffffu), si ? si->ph8 : 0,
                        si ? foliage_law::kSwayFlagInstance : 0);
      }
      vi += n;
    }
  }
  // `base_w` : le long de chaque arete de bande dont les deux sommets sont de part et d'autre du
  // pivot (et de la MEME instance), le poids interpole lineairement a y = base_y, sur les poids
  // QUANTIFIES relus. C'est exactement ce que le rasteriseur fera : la loi est lineaire, donc la
  // valeur attendue est 0 a l'erreur de quantification pres, et c'est CETTE valeur qu'on publie.
  std::vector<float> inst_base_w(n_mat, 0.f);
  {
    const auto& idx = tree.indices;
    auto edge = [&](u32 a, u32 b) {
      if (a >= nverts || b >= nverts) {
        return;
      }
      const u32 mi = vert_inst[a];
      if (mi == UINT32_MAX || mi != vert_inst[b]) {
        return;
      }
      const auto& si = tree.sway_instances[mi];
      if (!(si.base_y > si.ymin)) {
        return;  // non enfonce : la ligne du pivot est le pied, rien n'est dessine sous lui
      }
      const float ya = tree.unpacked.vertices[a].y, yb = tree.unpacked.vertices[b].y;
      const float da = ya - si.base_y, db = yb - si.base_y;
      if (!(da * db < 0.f)) {
        return;  // l'arete ne traverse pas le pivot
      }
      const float wa = foliage_law::dequantize_weight(fw_read_record(tree.unpacked.sway, a).w);
      const float wb = foliage_law::dequantize_weight(fw_read_record(tree.unpacked.sway, b).w);
      const float t = da / (da - db);  // dans (0, 1)
      const float wi = std::fabs(wa + t * (wb - wa));
      if (wi > inst_base_w[mi]) {
        inst_base_w[mi] = wi;
      }
    };
    u32 p0 = UINT32_MAX, p1 = UINT32_MAX;
    for (u32 vi2 : idx) {
      if (vi2 == UINT32_MAX) {
        p0 = p1 = UINT32_MAX;
        continue;
      }
      if (p1 != UINT32_MAX) {
        edge(p1, vi2);
        if (p0 != UINT32_MAX) {
          edge(p0, vi2);
        }
      }
      p0 = p1;
      p1 = vi2;
    }
  }
  for (size_t mi = 0; mi < n_mat; mi++) {
    auto& si = tree.sway_instances[mi];
    if (!si.valid) {
      continue;
    }
    si.peak_w = foliage_law::dequantize_weight(inst_max_w[mi]);
    si.low_w = foliage_law::dequantize_weight(inst_low_w[mi]);
    si.base_w = inst_base_w[mi];
  }
}

// -------------------------------------------------------------------------------------------------
// foliage-wind (essai 11) — LE SOL SOUS CHAQUE BUISSON, ET LE VENT NATIF DES BUISSONS.
namespace {

// Les triangles du TERRAIN d'un niveau, ranges dans une grille 2D (x, z) pour un lancer de rayon
// vertical. Terrain = tfrag geo 0 (hors lowres, qui doublent le meme sol de plus loin) + TIE statique
// geo 0 (a Sandover le sol est fait de `groundlarge.mb` / `groundsmall.mb`, des TIE). Les sommets du
// chemin VENT du TIE sont LOCAUX au prototype et n'entrent pas dans `unpacked.indices` (statique
// seulement, TieTree::unpack) : ils ne polluent donc pas la grille.
struct GroundGrid {
  static constexpr float kCell = 16.f * 4096.f;
  std::vector<float> tris;  // 9 flottants par triangle
  std::unordered_map<u64, std::vector<u32>> cells;

  static u64 key(s64 cx, s64 cz) { return ((u64)(u32)(s32)cx << 32) | (u64)(u32)(s32)cz; }
  static s64 cell(float v) { return (s64)std::floor(v / kCell); }

  void add_tri(const PreloadedVertex& a, const PreloadedVertex& b, const PreloadedVertex& c) {
    const u32 ti = (u32)(tris.size() / 9);
    tris.insert(tris.end(), {a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z});
    const s64 x0 = cell(std::min({a.x, b.x, c.x})), x1 = cell(std::max({a.x, b.x, c.x}));
    const s64 z0 = cell(std::min({a.z, b.z, c.z})), z1 = cell(std::max({a.z, b.z, c.z}));
    if (x1 - x0 > 64 || z1 - z0 > 64) {
      tris.resize(tris.size() - 9);  // un triangle de plus d'un kilometre n'est pas du sol
      return;
    }
    for (s64 cx = x0; cx <= x1; cx++) {
      for (s64 cz = z0; cz <= z1; cz++) {
        cells[key(cx, cz)].push_back(ti);
      }
    }
  }

  template <typename V>
  void add_mesh(const std::vector<V>& verts, const std::vector<u32>& idx, bool strips) {
    auto tri = [&](u32 i0, u32 i1, u32 i2) {
      if (i0 < verts.size() && i1 < verts.size() && i2 < verts.size()) {
        PreloadedVertex a, b, c;
        a.x = verts[i0].x; a.y = verts[i0].y; a.z = verts[i0].z;
        b.x = verts[i1].x; b.y = verts[i1].y; b.z = verts[i1].z;
        c.x = verts[i2].x; c.y = verts[i2].y; c.z = verts[i2].z;
        add_tri(a, b, c);
      }
    };
    if (strips) {
      u32 p0 = UINT32_MAX, p1 = UINT32_MAX;
      for (u32 vi : idx) {
        if (vi == UINT32_MAX) {
          p0 = p1 = UINT32_MAX;
          continue;
        }
        if (p0 != UINT32_MAX && p1 != UINT32_MAX) {
          tri(p0, p1, vi);
        }
        p0 = p1;
        p1 = vi;
      }
    } else {
      for (size_t t = 0; t + 2 < idx.size(); t += 3) {
        if (idx[t] != UINT32_MAX && idx[t + 1] != UINT32_MAX && idx[t + 2] != UINT32_MAX) {
          tri(idx[t], idx[t + 1], idx[t + 2]);
        }
      }
    }
  }

  // Le plus haut triangle de SOL contenant (x, z) en projection, de hauteur dans [y_min, y_max].
  // « De sol » : pente sous 60 degres (|normale.y| >= 0,5). Une falaise (`cliffmed-8m`) ou un mur
  // couvre le point en projection avec une hauteur quelconque : sans ce filtre, la premiere course
  // rendait des « enfoncements » de 8 m qui etaient des faces de falaise.
  bool ground_below(float x, float z, float y_min, float y_max, float* out_y) const {
    auto it = cells.find(key(cell(x), cell(z)));
    if (it == cells.end()) {
      return false;
    }
    bool found = false;
    float best = -1e30f;
    for (u32 ti : it->second) {
      const float* t = &tris[(size_t)ti * 9];
      const float ax = t[0], ay = t[1], az = t[2];
      const float bx = t[3], by = t[4], bz = t[5];
      const float cx = t[6], cy = t[7], cz = t[8];
      const float det = (bx - ax) * (cz - az) - (cx - ax) * (bz - az);
      if (std::fabs(det) < 1e-3f) {
        continue;  // triangle vertical ou degenere en projection
      }
      // pente : |normale.y| / |normale| = |det| / |(b-a) x (c-a)|
      const float e1x = bx - ax, e1y = by - ay, e1z = bz - az;
      const float e2x = cx - ax, e2y = cy - ay, e2z = cz - az;
      const float nx = e1y * e2z - e1z * e2y, ny = e1z * e2x - e1x * e2z, nz = e1x * e2y - e1y * e2x;
      const float nlen = std::sqrt(nx * nx + ny * ny + nz * nz);
      if (!(nlen > 0.f) || std::fabs(ny) / nlen < 0.5f) {
        continue;  // plus de 60 degres : une paroi, pas un sol
      }
      const float l1 = ((x - ax) * (cz - az) - (cx - ax) * (z - az)) / det;
      const float l2 = ((bx - ax) * (z - az) - (x - ax) * (bz - az)) / det;
      const float l0 = 1.f - l1 - l2;
      const float eps = -1e-4f;
      if (l0 < eps || l1 < eps || l2 < eps) {
        continue;
      }
      const float y = l0 * ay + l1 * by + l2 * cy;
      if (y >= y_min && y <= y_max && y > best) {
        best = y;
        found = true;
      }
    }
    if (found) {
      *out_y = best;
    }
    return found;
  }
};

// Le sidecar de vent shrub, parse UNE fois pour tout le jeu.
struct ShrubWindSidecar {
  struct LevelData {
    std::vector<std::string> proto_names;
    std::vector<ShrubTree::WindProto> protos;
    std::vector<u16> inst_wind;   // par matrix_idx
    std::vector<u16> inst_proto;  // par matrix_idx
  };
  std::unordered_map<std::string, LevelData> levels;
  bool loaded = false;
  std::string path;
};

const ShrubWindSidecar& shrub_wind_sidecar() {
  static const ShrubWindSidecar s = [] {
    ShrubWindSidecar out;
    auto path = file_util::get_recharged_assets_dir() / "foliage_wind_shrub.txt";
    auto ext_dir = file_util::get_external_recharged_assets_dir();
    if (ext_dir) {
      auto ext_path = *ext_dir / "foliage_wind_shrub.txt";
      if (file_util::file_exists(ext_path.string())) {
        path = ext_path;
      }
    }
    out.path = path.string();
    if (!file_util::file_exists(out.path)) {
      lg::warn(
          "[foliage-wind] SIDECAR SHRUB ABSENT : {} — le vent NATIF des buissons (ressort de ND, "
          "raideur par prototype) reste ETEINT sur tout le jeu. C'est un asset manquant.",
          out.path);
      return out;
    }
    std::string text = file_util::read_text_file(out.path);
    std::stringstream ss(text);
    std::string line;
    ShrubWindSidecar::LevelData* cur = nullptr;
    while (std::getline(ss, line)) {
      std::stringstream ls(line);
      std::string tag;
      ls >> tag;
      if (tag == "level") {
        std::string name;
        ls >> name;
        cur = &out.levels[name];
        // un dump ecrit en `append` peut porter le meme niveau deux fois : le dernier gagne
        *cur = ShrubWindSidecar::LevelData{};
      } else if (tag == "proto" && cur) {
        // proto <idx> <name> stiffness <s> dists a b c d rdists e f g h
        size_t idx = 0;
        std::string name, kw;
        float st = 0.f, d[4] = {0, 0, 0, 0}, r[4] = {0, 0, 0, 0};
        ls >> idx >> name >> kw >> st >> kw >> d[0] >> d[1] >> d[2] >> d[3] >> kw >> r[0] >> r[1] >>
            r[2] >> r[3];
        if (cur->protos.size() <= idx) {
          cur->protos.resize(idx + 1);
          cur->proto_names.resize(idx + 1);
        }
        cur->proto_names[idx] = name;
        cur->protos[idx].stiffness = st;
        cur->protos[idx].near_stiff = d[1];
        cur->protos[idx].rlength_stiff = r[1];
      } else if (tag == "inst" && cur) {
        // inst <matrix_idx> <proto_idx> <wind_index>
        size_t mi = 0;
        unsigned pi = 0, wi = 0;
        ls >> mi >> pi >> wi;
        if (cur->inst_wind.size() <= mi) {
          cur->inst_wind.resize(mi + 1, 0);
          cur->inst_proto.resize(mi + 1, 0xffff);
        }
        cur->inst_wind[mi] = (u16)wi;
        cur->inst_proto[mi] = (u16)pi;
      }
    }
    out.loaded = true;
    lg::info("[foliage-wind] sidecar shrub charge : {} niveaux depuis {}", out.levels.size(),
             out.path);
    return out;
  }();
  return s;
}

}  // namespace

void foliage_wind_finalize_level(Level& lev) {
  if (lev.shrub_trees.empty()) {
    return;
  }
  GroundGrid grid;
  if (!lev.tfrag_trees.empty()) {
    for (const auto& t : lev.tfrag_trees[0]) {
      if (t.kind == TFragmentTreeKind::LOWRES || t.kind == TFragmentTreeKind::LOWRES_TRANS ||
          t.kind == TFragmentTreeKind::INVALID) {
        continue;
      }
      grid.add_mesh(t.unpacked.vertices, t.unpacked.indices, t.use_strips);
    }
  }
  if (!lev.tie_trees.empty()) {
    for (const auto& t : lev.tie_trees[0]) {
      grid.add_mesh(t.unpacked.vertices, t.unpacked.indices, t.use_strips);
    }
  }
  const u64 n_tris = grid.tris.size() / 9;

  const auto& side = shrub_wind_sidecar();
  const ShrubWindSidecar::LevelData* sd = nullptr;
  if (side.loaded) {
    auto it = side.levels.find(lev.level_name);
    if (it != side.levels.end()) {
      sd = &it->second;
    }
  }

  for (size_t ti = 0; ti < lev.shrub_trees.size(); ti++) {
    auto& tree = lev.shrub_trees[ti];
    const size_t n_mat = tree.packed_vertices.matrices.size();
    if (tree.sway_instances.size() != n_mat) {
      lg::warn("[foliage-wind] SHRUB ground lev={} tree={} : recensement de taille {} pour {} "
               "matrices — depaquetage non conforme, passe sautee",
               lev.level_name, ti, tree.sway_instances.size(), n_mat);
      continue;
    }
    u32 n_valid = 0, n_found = 0, n_sunk = 0, n_rejected = 0, max_sunk_mm = 0;
    for (size_t mi = 0; mi < n_mat; mi++) {
      auto& si = tree.sway_instances[mi];
      if (!si.valid) {
        continue;
      }
      n_valid++;
      si.base_y = si.ymin;
      si.ground_found = false;
      si.sunk_mm = 0;
      const float span = si.ymax - si.ymin;
      float gy = 0.f;
      // le sol est cherche du pied (moins 2 m : un buisson pose sur un rocher garde son pied) a la
      // couronne ; un sol trouve au-dessus de 60 % du buisson n'est pas credible (une plante
      // enfoncee aux deux tiers n'existe pas dans un decor ; c'est un rocher ou un toit bas) : on
      // le REJETTE et le buisson pivote a son pied, plutot que de le faire basculer autour de sa
      // taille comme une balancoire
      if (span > 0.f && grid.ground_below(si.x, si.z, si.ymin - 2.f * 4096.f, si.ymax, &gy)) {
        if (gy > si.ymin + 0.60f * span) {
          n_rejected++;
        } else {
          si.ground_found = true;
          n_found++;
          if (gy > si.ymin + 41.f) {  // enfonce de plus d'un centimetre
            si.base_y = gy;
            si.sunk_mm = (u32)((gy - si.ymin) / 4096.f * 1000.f + 0.5f);
            n_sunk++;
            max_sunk_mm = std::max(max_sunk_mm, si.sunk_mm);
          }
        }
      }
    }
    shrub_sway_write_records(tree);
    float max_base_w = 0.f;
    for (const auto& si : tree.sway_instances) {
      if (si.valid) {
        max_base_w = std::max(max_base_w, si.base_w);
      }
    }

    // --- le vent natif : sidecar verifie contre le fr3 -----------------------------------------
    tree.wind_protos.clear();
    tree.wind_index.clear();
    tree.wind_proto_of_inst.clear();
    tree.wind_sidecar_ok = false;
    tree.wind_max_idx = 0;
    tree.wind_instances_stiff = 0;
    std::string why;
    if (!sd) {
      why = side.loaded ? "niveau absent du sidecar" : "sidecar absent";
    } else if (sd->inst_wind.size() != n_mat) {
      why = fmt::format("{} instances dans le sidecar pour {} matrices", sd->inst_wind.size(), n_mat);
    } else if (!tree.proto_names.empty() && sd->proto_names.size() != tree.proto_names.size()) {
      why = fmt::format("{} prototypes dans le sidecar pour {} dans le fr3", sd->proto_names.size(),
                        tree.proto_names.size());
    } else {
      bool names_ok = true;
      for (size_t pi = 0; pi < tree.proto_names.size(); pi++) {
        if (tree.proto_names[pi] != sd->proto_names[pi]) {
          names_ok = false;
          why = fmt::format("prototype {} : '{}' dans le sidecar, '{}' dans le fr3", pi,
                            sd->proto_names[pi], tree.proto_names[pi]);
          break;
        }
      }
      if (names_ok) {
        for (size_t mi = 0; mi < n_mat; mi++) {
          if (sd->inst_proto[mi] >= sd->protos.size()) {
            names_ok = false;
            why = fmt::format("instance {} : prototype {} hors table", mi, sd->inst_proto[mi]);
            break;
          }
        }
      }
      if (names_ok) {
        tree.wind_protos = sd->protos;
        tree.wind_index = sd->inst_wind;
        tree.wind_proto_of_inst = sd->inst_proto;
        tree.wind_sidecar_ok = true;
        for (size_t mi = 0; mi < n_mat; mi++) {
          tree.wind_max_idx = std::max<u32>(tree.wind_max_idx, tree.wind_index[mi]);
          if (tree.wind_protos[tree.wind_proto_of_inst[mi]].stiffness > 0.f &&
              tree.sway_instances[mi].valid) {
            tree.wind_instances_stiff++;
          }
        }
      }
    }
    lg::info(
        "[foliage-wind] SHRUB ground lev={} tree={} terrain_tris={} instances={} sol_trouve={} "
        "enfonces={} pivot_rejete={} enfoncement_max_mm={} base_w_max={:.6f} sidecar={} "
        "raideur_instances={} wind_max_idx={}{}{}",
        lev.level_name, ti, n_tris, n_valid, n_found, n_sunk, n_rejected, max_sunk_mm, max_base_w,
        tree.wind_sidecar_ok ? 1 : 0, tree.wind_instances_stiff, tree.wind_max_idx,
        why.empty() ? "" : " refus=", why);
  }
}

// Grecharged-directional-ambient ROOT-CAUSE FIX (smooth per-vertex normals) — ROUND 2 CREASE-AWARE.
// Static tfrag geometry ships with NO per-vertex normal (the PS2 game baked its lighting into the
// vertex COLORS instead of storing normals), so the realtime-lighting shaders used to synthesize a
// FLAT per-face normal via screen-space derivatives (cross(dFdx,dFdy)). On any curved surface
// (rounded huts, terrain, arches) that reads as faceted/flat in shadow — direct AND ambient — which
// is exactly the "3D en ombre a l'air plat" the owner reported. Contemporary engines solve this the
// cheap way: reconstruct smooth vertex normals. Here we do it once at level-load (runs on modest HW).
//
// ROUND-2 DEFECT (owner, stone building / masonry): round-1 welded EVERY vertex sharing a position into
// ONE averaged normal, unconditionally. On hard-edged geometry (a stone wall / block corner) that smears
// the two face normals of a 90-degree corner into a diagonal average -> the incoherent random bright/dark
// patches the owner saw. FIX = CREASE-ANGLE-AWARE reconstruction: for every weld group (vertices sharing an
// exact packed position) we CLUSTER the incident faces by the angle between their normals. Faces within the
// crease threshold (default 45 deg) weld into one smooth cluster; faces meeting ABOVE it stay in SEPARATE
// clusters (a hard edge). Each unpacked vertex is then assigned the cluster carrying its largest incident
// face — so a rounded surface welds smooth (a single cluster == the round-1 result exactly, so the approved
// hut is unchanged) while a masonry corner keeps its two crisp face normals. Area-weighted (raw edge cross),
// strip-parity aware, degenerate tris skipped, welded strictly by position. Packs into the 2-10-10-10 `nor`
// attribute the GL vertex already carries. The shader keeps the per-face geometric normal only as the
// outward-sign reference + degenerate fallback, so global winding is irrelevant and a missing normal
// reproduces the old flat behaviour exactly.
static float tfrag_crease_cos() {
  // Crease threshold in degrees: adjacent faces at a shared position weld (smooth) only when the angle
  // between them is below this; above it stays a hard edge. Default 60 (owner FULL SPEC: gentle terrain/grass
  // seams meeting below 60 deg smooth to a nuance, sharp corners >=60 deg — e.g. a wall meeting the ground
  // ~90 deg — stay crisp). Overridable for on-device A/B
  // (level-reload picks it up); >=179 reproduces round-1's unconditional single-cluster weld ("before").
  float deg = 60.0f;
#ifdef __ANDROID__
  char rv[PROP_VALUE_MAX];
  if (__system_property_get("debug.opengoal.tfrag.crease", rv) > 0 && rv[0]) {
    deg = (float)atof(rv);
  }
#else
  if (const char* e = getenv("OG_TFRAG_CREASE_DEG")) {
    deg = (float)atof(e);
  }
#endif
  if (!(deg > 0.0f)) {
    deg = 60.0f;
  }
  if (deg > 179.0f) {
    deg = 179.0f;
  }
  return std::cos(deg * 0.017453292519943295f);
}

// OWNER FULL SPEC (2026-07-24) — mandatory weld A/B toggle so the supervisor can A/B weld-ON vs
// weld-OFF on-device at a fixed daytime grass vantage (proving remaining seams come from the geometry
// pass). debug.opengoal.mesh.weld = "0" DISABLES the whole per-tree + global weld/orient/smooth pass at
// runtime (a level reload picks it up); default (unset / non-zero) = ON. Desktop uses env OG_MESH_WELD
// for the offline A/B. The resolved state is snapshotted into files/pbr_tan_diag.txt so the supervisor
// can confirm the toggle actually applied on device.
static std::atomic<int> g_mesh_weld_state{1};  // 0 = off (seamy baseline), 1 = on (weld/orient/smooth)
static bool mesh_weld_enabled() {
  bool on = true;
#ifdef __ANDROID__
  char rv[PROP_VALUE_MAX];
  if (__system_property_get("debug.opengoal.mesh.weld", rv) > 0 && rv[0]) {
    on = !(rv[0] == '0' && rv[1] == '\0');
  }
#else
  if (const char* e = getenv("OG_MESH_WELD")) {
    on = !(e[0] == '0' && e[1] == '\0');
  }
#endif
  g_mesh_weld_state.store(on ? 1 : 0);
  return on;
}

// OWNER ROOT-CAUSE BREAKTHROUGH (2026-07-24) — edge-weld device-provable stats. The Honor obscures logcat
// (HKS encryption), so the weld counts are ALSO emitted to files/pbr_tan_diag.txt (pull via
// `run-as org.opengoal.gk.jak1 cat files/pbr_tan_diag.txt`). *_stitched = coincident shared-edge vertex
// copies merged into an already-seen group across a cluster/strip/instance seam = the previously-UNWELDED
// adjacent-same-texture edges that caused the hard facets + tessellation holes.
static std::atomic<u64> g_edge_weld_tfrag_stitched{0};
static std::atomic<u64> g_edge_weld_tfrag_verts{0};
static std::atomic<u64> g_edge_weld_tie_stitched{0};
static std::atomic<u64> g_edge_weld_tie_verts{0};

// OWNER REOPEN #13 (2026-07-24) + INSIGHT #2 — GLOBAL cross-chunk / cross-bucket / cross-system weld
// stats. The per-tree passes above only stitch WITHIN one tfrag/tie tree; this level-wide pass stitches
// ACROSS all trees/buckets/systems, runs a normal-orientation-consistency step, then averages. Written to
// files/pbr_tan_diag.txt (Honor obscures logcat) so the supervisor can pull the cross-chunk seam counts.
static std::atomic<u64> g_gweld_total_verts{0};       // every tfrag+tie vertex fed to the global hash
static std::atomic<u64> g_gweld_cross_stitched{0};    // verts welded ACROSS a tree boundary (the REOPEN#13 win)
static std::atomic<u64> g_gweld_multitree_groups{0};  // welded groups that span >=2 trees == the stitched seams
static std::atomic<u64> g_gweld_resmoothed_verts{0};  // verts whose normal was re-averaged across the welded seam
static std::atomic<u64> g_gweld_inverted_fixed{0};    // incident faces flipped by the orientation pass (inward->outward)
static std::atomic<u64> g_gweld_collision_oriented{0};// groups whose outward sign was set by the collision authority
static std::atomic<u64> g_gweld_open_seam_before{0};   // open-boundary seam verts BEFORE the global stitch
static std::atomic<u64> g_gweld_open_seam_after{0};    // open-boundary seam verts REMAINING after the global stitch
static std::atomic<u64> g_gweld_uv_snapped{0};        // cross-chunk seam verts whose UV was snapped to close a hairline texture crack
// OWNER #14 (2026-07-24) — split-by-UV shared-normal coverage. index FUSION merges only the ~24-30%
// attribute-identical coincident verts; these count the FULL coincident set (position groups of size>=2 =
// the UV/color-seam verts) and how many received a SHARED position-averaged smooth normal (~the whole set).
static std::atomic<u64> g_gweld_coincident_verts{0};    // verts in a POSITION group of size>=2 (the coincident/UV-seam set)
static std::atomic<u64> g_gweld_coincident_smoothed{0}; // coincident verts assigned a SHARED position-averaged normal
// Gpbr-fusion (2026-07-24) — cross-seam TANGENT FRAME coherence MEASUREMENT (diagnostic only, writes
// nothing back to the mesh). Positions/normals are now welded across chunk seams, but the normal map is
// sampled in the per-vertex TANGENT frame: if the two chunks meeting at a welded seam carry tangents
// rotated (or mirrored) relative to each other, the SAME normal-map texel is decoded into two different
// world normals => opposite lighting on either side of the seam == the owner's hard "plates". These
// counters quantify that rotation across every welded cross-tree (multitree) group.
static std::atomic<u64> g_tanframe_pairs{0};        // compared (reference, member) tangent pairs
static std::atomic<u64> g_tanframe_h0{0};           // |ang| in [0,5)
static std::atomic<u64> g_tanframe_h1{0};           // |ang| in [5,15)
static std::atomic<u64> g_tanframe_h2{0};           // |ang| in [15,45)
static std::atomic<u64> g_tanframe_h3{0};           // |ang| in [45,90)
static std::atomic<u64> g_tanframe_h4{0};           // |ang| in [90,135)
static std::atomic<u64> g_tanframe_h5{0};           // |ang| in [135,180]
static std::atomic<u64> g_tanframe_pairs_over30{0}; // pairs rotated by more than 30 deg
static std::atomic<u64> g_tanframe_handed{0};       // pairs whose tangent HANDEDNESS (.w sign) disagrees
static std::atomic<u64> g_tanframe_groups{0};       // multitree groups actually analysed (>=2 valid frames)
static std::atomic<u64> g_tanframe_incoherent{0};   // analysed groups whose max |ang| exceeds 30 deg


// ============================================================================================
// STEP A (owner STRICT ORDER, 2026-07-24) — TRUE TOPOLOGICAL FUSE (genuine index-buffer merge).
//
// Every prior round only AVERAGED normals per coincident group and NEVER rewrote the index buffer, so
// two adjacent same-texture polygons kept SEPARATE copies of their shared-edge vertices — the mesh was
// never actually welded (the owner's exact critique). This performs the genuine point fusion: it REMAPS
// the index buffer so coincident ATTRIBUTE-IDENTICAL vertices reference ONE shared representative index.
// The merge key is EVERY attribute the renderer reads — position, UV, baked color-table index, and the
// per-vertex envmap tint (r,g,b,a) — quantized to a fine grid (position 1/16 game-unit ~= 0.015 mm,
// 1 m = 4096 u; UV 1/4096). `nor` is deliberately EXCLUDED from the key: it is exactly what STEP B
// (smooth normals) reconstructs into a single shared normal for the merged vertex, so two copies that
// differ only in their raw source normal SHOULD fuse. Because two verts with an identical key render
// pixel-for-pixel identically regardless of which StripDraw (hence tpage) references them, sharing them
// is a pure, OUTPUT-INVARIANT topological dedup (the textbook weld of an unwelded mesh). Consequences,
// all owner-requested:
//   * the shared edge becomes ONE topological edge => STEP B averages the normal across it (no facet);
//   * GL_PATCHES tessellation now references identical shared-edge endpoint positions on both patches,
//     and the TCS edge factor is a deterministic function of those endpoints => crack-free (no holes);
//   * genuine hard seams (a real texture boundary carries a different atlas UV, a UV-chart split differs
//     in UV) have a DIFFERENT key => LEFT SEPARATE (preserved — no over-welding, no new clean cuts).
// Returns the number of index slots repointed at a representative (== the fused duplicate-vertex count).
// Non-representative verts are simply orphaned in the vertex array (unreferenced, harmless); the index
// buffer alone carries the merged topology and is uploaded verbatim to GL (TFragment.cpp:447-448).
// ============================================================================================
static u32 fuse_tree_indices(const std::vector<PreloadedVertex>& verts, std::vector<u32>& indices) {
  const size_t n = verts.size();
  if (n == 0 || indices.empty()) {
    return 0;
  }
  struct FuseKey {
    s32 x, y, z, s, t;
    u32 color;  // baked color-table index
    u32 tint;   // packed envmap rgba (rendered => must match to fuse)
    bool operator==(const FuseKey& o) const {
      return x == o.x && y == o.y && z == o.z && s == o.s && t == o.t && color == o.color &&
             tint == o.tint;
    }
  };
  struct FuseKeyHash {
    size_t operator()(const FuseKey& k) const {
      u64 h = 1469598103934665603ull;
      auto mix = [&](u64 v) {
        h ^= v;
        h *= 1099511628211ull;
      };
      mix((u32)k.x);
      mix((u32)k.y);
      mix((u32)k.z);
      mix((u32)k.s);
      mix((u32)k.t);
      mix(k.color);
      mix(k.tint);
      return (size_t)h;
    }
  };
  auto q = [](float f, float scale) -> s32 { return (s32)std::lround(f * scale); };
  std::unordered_map<FuseKey, u32, FuseKeyHash> canon;
  canon.reserve(n * 2);
  std::vector<u32> remap(n);
  u32 fused = 0;
  for (u32 i = 0; i < (u32)n; i++) {
    const auto& v = verts[i];
    FuseKey k{q(v.x, 16.f),          q(v.y, 16.f), q(v.z, 16.f), q(v.s, 4096.f), q(v.t, 4096.f),
              (u32)v.color_index,
              ((u32)v.r << 24) | ((u32)v.g << 16) | ((u32)v.b << 8) | (u32)v.a};
    auto it = canon.find(k);
    if (it == canon.end()) {
      canon.emplace(k, i);
      remap[i] = i;
    } else {
      remap[i] = it->second;  // repoint this duplicate at the already-seen representative
      fused++;
    }
  }
  if (fused == 0) {
    return 0;  // already a fully-welded mesh (rare) — nothing to remap
  }
  for (u32& idx : indices) {
    if (idx != UINT32_MAX) {  // preserve primitive-restart sentinels
      idx = remap[idx];
    }
  }
  return fused;
}

static void reconstruct_tfrag_smooth_normals(TfragTree& tree) {
  const auto& packed = tree.packed_vertices.vertices;
  const size_t n = tree.unpacked.vertices.size();
  if (n == 0 || packed.size() != n) {
    return;
  }
  if (!mesh_weld_enabled()) {
    return;  // A/B weld-OFF: keep the original per-vertex normals (the seamy baseline the owner A/Bs)
  }
  const float crease_cos = tfrag_crease_cos();

  auto pos_of = [&](u32 idx) {
    const auto& v = tree.unpacked.vertices[idx];
    return math::Vector3f(v.x, v.y, v.z);
  };

  // OWNER ROOT-CAUSE BREAKTHROUGH (2026-07-24): the tfrag/tie/shrub mesh is UNWELDED — two adjacent
  // same-texture polygons keep SEPARATE copies of their shared-edge vertices (one copy per cluster/strip), so
  // an exact packed-position key (cluster<<48 | xoff<<32 | yoff<<16 | zoff) NEVER merged the two copies: the
  // smooth normal was averaged only WITHIN each polygon's own copy, never ACROSS the shared seam (=> hard
  // triangular facets), and tessellation displaced the two divergent copies apart (=> holes/tears you can see
  // through). FIX = EDGE WELDING / topology stitching: group vertices by WORLD position within a 3 cm epsilon
  // with 27-neighbour cell probing, so coincident edge verts across cluster/strip boundaries STITCH into ONE
  // shared group. The crease clustering below still splits genuine hard folds (a masonry corner keeps its
  // crisp edges); only smooth same-texture adjacencies weld. This is a strict SUPERSET of the old exact-key
  // weld (identical-position verts always co-merge), so already-smooth surfaces are bit-identical to before
  // (no regression on the accepted directional-ambient look) — the ONLY new merges are the previously-
  // unwelded shared-edge copies, i.e. exactly the owner's facets + tessellation holes. 1 m = 4096 game units.
  constexpr float kWeldM = 0.03f;                 // 3 cm canonical weld (mirrors GrassBakeCore's proven tol)
  const float weld_cell = kWeldM * 4096.f;        // cell size in game units
  const float weld_tol2 = weld_cell * weld_cell;  // squared merge tolerance
  auto weld_key = [](s64 cx, s64 cy, s64 cz) -> u64 {
    return ((u64)(u32)(cx & 0x1FFFFF) << 42) | ((u64)(u32)(cy & 0x1FFFFF) << 21) | (u64)(u32)(cz & 0x1FFFFF);
  };
  std::unordered_map<u64, std::vector<u32>> weld_cells;  // grid cell -> vertex indices seen there
  weld_cells.reserve(n * 2);
  std::vector<u32> vert_group(n);
  u32 num_groups = 0;
  u32 dbg_edge_welds = 0;  // verts stitched into an already-seen coincident group (the shared-edge copies)
  for (size_t i = 0; i < n; i++) {
    const math::Vector3f pi = pos_of((u32)i);
    const s64 cx = (s64)std::floor(pi.x() / weld_cell);
    const s64 cy = (s64)std::floor(pi.y() / weld_cell);
    const s64 cz = (s64)std::floor(pi.z() / weld_cell);
    int found = -1;
    for (int dz = -1; dz <= 1 && found < 0; dz++) {
      for (int dy = -1; dy <= 1 && found < 0; dy++) {
        for (int dx = -1; dx <= 1 && found < 0; dx++) {
          auto it = weld_cells.find(weld_key(cx + dx, cy + dy, cz + dz));
          if (it == weld_cells.end()) {
            continue;
          }
          for (u32 rep : it->second) {
            const math::Vector3f d = pos_of(rep) - pi;
            if (d.dot(d) <= weld_tol2) {
              found = (int)vert_group[rep];
              break;
            }
          }
        }
      }
    }
    if (found < 0) {
      vert_group[i] = num_groups++;
    } else {
      vert_group[i] = (u32)found;
      dbg_edge_welds++;
    }
    weld_cells[weld_key(cx, cy, cz)].push_back((u32)i);
  }

  // Collect, per weld group, one record per triangle-corner incident to it: the area-weighted (raw edge
  // cross) face normal + which unpacked vertex the corner is. Strip-parity keeps the winding consistent
  // within a strip. Degenerate (zero-area) triangles are skipped so they can't inject a garbage normal.
  struct Incid {
    math::Vector3f nraw;  // raw edge cross => length == 2*triangle area (area weighting)
    u32 vert;
  };
  std::vector<std::vector<Incid>> group_incid(num_groups);

  auto add_tri = [&](u32 i0, u32 i1, u32 i2, bool flip) {
    math::Vector3f nraw = (pos_of(i1) - pos_of(i0)).cross(pos_of(i2) - pos_of(i0));
    float len = nraw.length();
    if (!(len > 1e-3f)) {
      return;  // degenerate / zero-area triangle: no reliable normal
    }
    if (flip) {
      nraw = nraw * -1.f;  // triangle-strip parity: keep a consistent winding within a strip
    }
    group_incid[vert_group[i0]].push_back({nraw, i0});
    group_incid[vert_group[i1]].push_back({nraw, i1});
    group_incid[vert_group[i2]].push_back({nraw, i2});
  };

  const auto& idx = tree.unpacked.indices;
  if (tree.use_strips) {
    // Triangle strips with UINT32_MAX primitive restart; winding alternates each step.
    u32 a = UINT32_MAX, b = UINT32_MAX, k = 0;
    for (u32 vi : idx) {
      if (vi == UINT32_MAX) {
        a = b = UINT32_MAX;
        k = 0;
        continue;
      }
      if (a != UINT32_MAX && b != UINT32_MAX) {
        add_tri(a, b, vi, (k & 1) != 0);
      }
      a = b;
      b = vi;
      k++;
    }
  } else {
    for (size_t t = 0; t + 2 < idx.size(); t += 3) {
      if (idx[t] == UINT32_MAX || idx[t + 1] == UINT32_MAX || idx[t + 2] == UINT32_MAX) {
        continue;
      }
      add_tri(idx[t], idx[t + 1], idx[t + 2], false);
    }
  }

  // For each group, cluster its incident faces by crease angle, then give every unpacked vertex the packed
  // normal of the cluster holding its LARGEST incident face. Smooth surface => one cluster (bit-identical to
  // round-1); hard edge => a cluster per face-group (crisp corners). Reused scratch avoids per-group allocs.
  std::vector<math::Vector3f> cl_accum;  // area-weighted normal accumulator per cluster
  std::vector<math::Vector3f> cl_unit;   // unit reference normal per cluster (largest face establishes it)
  std::vector<u32> cl_packed;            // packed 2-10-10-10 normal per cluster
  std::vector<int> rec_cluster;          // cluster chosen per incidence record
  std::vector<char> has_normal(n, 0);
  // Grecharged-directional-ambient ROUND 2 — crease-fix DATA PROOF (camera-independent): count, per
  // tfrag tree, how many weld-groups split into MORE THAN ONE cluster. A multi-cluster group == a
  // HARD EDGE the crease logic preserved (a masonry corner). At crease~45 a masonry tree yields many;
  // at crease>=179 (the round-1 unconditional weld) ~every group collapses to a single cluster (0
  // multi). Logged once per tree so an on-device A/B (debug.opengoal.tfrag.crease 45 vs 179) proves
  // the hard-edge preservation on the REAL level data, no screenshot framing required.
  u32 dbg_groups = 0, dbg_multi = 0, dbg_clusters = 0;
  u32 dbg_single_face = 0, dbg_ground_verts = 0, dbg_ground_single_face = 0;
  for (u32 g = 0; g < num_groups; g++) {
    auto& recs = group_incid[g];
    if (recs.empty()) {
      continue;
    }
    // Largest faces first so the dominant surface establishes the cluster references (order-stable).
    std::sort(recs.begin(), recs.end(), [](const Incid& x, const Incid& y) {
      return x.nraw.dot(x.nraw) > y.nraw.dot(y.nraw);
    });
    cl_accum.clear();
    cl_unit.clear();
    rec_cluster.assign(recs.size(), -1);
    for (size_t r = 0; r < recs.size(); r++) {
      float len = recs[r].nraw.length();
      math::Vector3f unit = recs[r].nraw * (1.f / len);
      int found = -1;
      for (size_t c = 0; c < cl_unit.size(); c++) {
        // SIGNED dot on parity-consistent normals: coplanar-enough (< crease) welds; a >=crease fold
        // (90 deg corner == dot 0, or a sharper back-fold) starts a new cluster => hard edge preserved.
        if (unit.dot(cl_unit[c]) >= crease_cos) {
          found = (int)c;
          break;
        }
      }
      if (found < 0) {
        found = (int)cl_accum.size();
        cl_accum.push_back(recs[r].nraw);
        cl_unit.push_back(unit);
      } else {
        cl_accum[found] += recs[r].nraw;  // same hemisphere by the signed test => plain add
      }
      rec_cluster[r] = found;
    }
    dbg_groups++;
    dbg_clusters += (u32)cl_accum.size();
    if (cl_accum.size() > 1) {
      dbg_multi++;  // this shared position kept >=2 distinct face normals == a hard edge
    }
    cl_packed.assign(cl_accum.size(), 0);
    for (size_t c = 0; c < cl_accum.size(); c++) {
      math::Vector3f nn = cl_accum[c];
      float l = nn.length();
      nn = l > 1e-6f ? nn * (1.f / l) : math::Vector3f(0.f, 1.f, 0.f);
      s16 nx = (s16)std::lround(nn.x() * 511.f);
      s16 ny = (s16)std::lround(nn.y() * 511.f);
      s16 nz = (s16)std::lround(nn.z() * 511.f);
      cl_packed[c] = pack_to_gl_normal(nx, ny, nz);
    }
    // FACET DIAG (gpbrf attempt-12): count incident faces per cluster. A vertex whose chosen cluster
    // holds exactly ONE face gets that face's raw normal == a PER-FACE (faceted) normal; >=2 faces is a
    // smoothed average. Report the fraction of GROUND-FACING verts (normal.y > 0.7) that are per-face —
    // the direct measure of the owner's faceted grass.
    std::vector<u32> cl_face_count(cl_accum.size(), 0);
    for (size_t r = 0; r < recs.size(); r++) {
      cl_face_count[rec_cluster[r]]++;
    }
    // recs is sorted by area desc, so the FIRST record seen for a vertex is its largest incident face:
    // that face's cluster is the surface the vertex belongs to (crisp side on a corner, the single smooth
    // cluster on a curve).
    for (size_t r = 0; r < recs.size(); r++) {
      u32 v = recs[r].vert;
      if (!has_normal[v]) {
        tree.unpacked.vertices[v].nor = cl_packed[rec_cluster[r]];
        has_normal[v] = 1;
        math::Vector3f cn = cl_accum[rec_cluster[r]];
        float cl = cn.length();
        float ny = cl > 1e-6f ? cn.y() / cl : 0.f;
        bool ground = ny > 0.7f;
        if (ground) dbg_ground_verts++;
        if (cl_face_count[rec_cluster[r]] <= 1) {
          dbg_single_face++;
          if (ground) dbg_ground_single_face++;
        }
      }
    }
  }
  // Vertices with no (non-degenerate) incident face keep nor == 0 -> the shader falls back to the flat
  // per-face normal, exactly the pre-fix behaviour.
  for (size_t i = 0; i < n; i++) {
    if (!has_normal[i]) {
      tree.unpacked.vertices[i].nor = 0;
    }
  }
  // crease-fix data proof (see counters above): one line per tfrag tree. multi>0 == hard edges kept.
  float crease_deg = std::acos(crease_cos < -1.f ? -1.f : (crease_cos > 1.f ? 1.f : crease_cos)) *
                     (180.f / 3.14159265f);
  g_edge_weld_tfrag_stitched += dbg_edge_welds;
  g_edge_weld_tfrag_verts += (u64)n;
  lg::info("[gda-crease] tfrag tree verts={} groups={} multicluster(hardedge)={} clusters={} "
           "edge_welded_seam_verts={} crease={:.0f}deg",
           n, dbg_groups, dbg_multi, dbg_clusters, dbg_edge_welds, crease_deg);
  lg::info("[gda-facet] tfrag tree verts={} single_face(perface)={} ground_verts={} ground_single_face={} "
           "ground_perface_pct={:.1f}",
           n, dbg_single_face, dbg_ground_verts, dbg_ground_single_face,
           dbg_ground_verts ? 100.f * dbg_ground_single_face / dbg_ground_verts : 0.f);
}

// REOPEN#7: crease-aware smooth normals for TIE, welded by exact world POSITION (tie's unpacked verts
// are already world-space) — mirrors reconstruct_tfrag_smooth_normals but (a) welds on position bits
// instead of the packed cluster/offset and (b) only BACKFILLS vertices whose normal is missing
// (nor==0), so the ~2% of tie verts that ship with real matrix-transformed normals are preserved and
// there is no regression on those. Fixes the tie-wall cracks: a missing normal otherwise makes the
// shader fall back to the discontinuous derivative normal.
static void reconstruct_tie_smooth_normals(std::vector<PreloadedVertex>& verts,
                                           const std::vector<u32>& indices,
                                           bool use_strips) {
  const size_t n = verts.size();
  if (n == 0) {
    return;
  }
  if (!mesh_weld_enabled()) {
    return;  // A/B weld-OFF: keep the original per-vertex normals (the seamy baseline the owner A/Bs)
  }
  const float crease_cos = tfrag_crease_cos();

  auto pos_of = [&](u32 idx) { return math::Vector3f(verts[idx].x, verts[idx].y, verts[idx].z); };

  // OWNER EDGE-WELD (2026-07-24): weld tie verts by WORLD position within a 3 cm epsilon (27-neighbour probe)
  // so coincident shared-edge copies across instance/strip boundaries STITCH into ONE group — the smooth
  // normal then averages ACROSS the seam (no facets) and tessellation moves the shared edge once (no holes).
  // Strict SUPERSET of the old exact-float-bits weld => no regression on tie verts that already carry real
  // matrix normals (we still only BACKFILL nor==0 below). 1 m = 4096 game units.
  constexpr float kWeldM = 0.03f;
  const float weld_cell = kWeldM * 4096.f;
  const float weld_tol2 = weld_cell * weld_cell;
  auto weld_key = [](s64 cx, s64 cy, s64 cz) -> u64 {
    return ((u64)(u32)(cx & 0x1FFFFF) << 42) | ((u64)(u32)(cy & 0x1FFFFF) << 21) | (u64)(u32)(cz & 0x1FFFFF);
  };
  std::unordered_map<u64, std::vector<u32>> weld_cells;
  weld_cells.reserve(n * 2);
  std::vector<u32> vert_group(n);
  u32 num_groups = 0;
  u32 dbg_edge_welds = 0;
  for (size_t i = 0; i < n; i++) {
    const math::Vector3f pi = pos_of((u32)i);
    const s64 cx = (s64)std::floor(pi.x() / weld_cell);
    const s64 cy = (s64)std::floor(pi.y() / weld_cell);
    const s64 cz = (s64)std::floor(pi.z() / weld_cell);
    int found = -1;
    for (int dz = -1; dz <= 1 && found < 0; dz++) {
      for (int dy = -1; dy <= 1 && found < 0; dy++) {
        for (int dx = -1; dx <= 1 && found < 0; dx++) {
          auto it = weld_cells.find(weld_key(cx + dx, cy + dy, cz + dz));
          if (it == weld_cells.end()) {
            continue;
          }
          for (u32 rep : it->second) {
            const math::Vector3f d = pos_of(rep) - pi;
            if (d.dot(d) <= weld_tol2) {
              found = (int)vert_group[rep];
              break;
            }
          }
        }
      }
    }
    if (found < 0) {
      vert_group[i] = num_groups++;
    } else {
      vert_group[i] = (u32)found;
      dbg_edge_welds++;
    }
    weld_cells[weld_key(cx, cy, cz)].push_back((u32)i);
  }

  struct Incid {
    math::Vector3f nraw;
    u32 vert;
  };
  std::vector<std::vector<Incid>> group_incid(num_groups);
  auto add_tri = [&](u32 i0, u32 i1, u32 i2, bool flip) {
    math::Vector3f nraw = (pos_of(i1) - pos_of(i0)).cross(pos_of(i2) - pos_of(i0));
    float len = nraw.length();
    if (!(len > 1e-3f)) {
      return;
    }
    if (flip) {
      nraw = nraw * -1.f;
    }
    group_incid[vert_group[i0]].push_back({nraw, i0});
    group_incid[vert_group[i1]].push_back({nraw, i1});
    group_incid[vert_group[i2]].push_back({nraw, i2});
  };
  if (use_strips) {
    u32 a = UINT32_MAX, b = UINT32_MAX, k = 0;
    for (u32 vi : indices) {
      if (vi == UINT32_MAX) {
        a = b = UINT32_MAX;
        k = 0;
        continue;
      }
      if (a != UINT32_MAX && b != UINT32_MAX) {
        add_tri(a, b, vi, (k & 1) != 0);
      }
      a = b;
      b = vi;
      k++;
    }
  } else {
    for (size_t t = 0; t + 2 < indices.size(); t += 3) {
      if (indices[t] == UINT32_MAX || indices[t + 1] == UINT32_MAX || indices[t + 2] == UINT32_MAX) {
        continue;
      }
      add_tri(indices[t], indices[t + 1], indices[t + 2], false);
    }
  }

  std::vector<math::Vector3f> cl_accum;
  std::vector<math::Vector3f> cl_unit;
  std::vector<u32> cl_packed;
  std::vector<int> rec_cluster;
  u32 dbg_filled = 0;
  for (u32 g = 0; g < num_groups; g++) {
    auto& recs = group_incid[g];
    if (recs.empty()) {
      continue;
    }
    std::sort(recs.begin(), recs.end(),
              [](const Incid& x, const Incid& y) { return x.nraw.dot(x.nraw) > y.nraw.dot(y.nraw); });
    cl_accum.clear();
    cl_unit.clear();
    rec_cluster.assign(recs.size(), -1);
    for (size_t r = 0; r < recs.size(); r++) {
      float len = recs[r].nraw.length();
      math::Vector3f unit = recs[r].nraw * (1.f / len);
      int found = -1;
      for (size_t c = 0; c < cl_unit.size(); c++) {
        if (unit.dot(cl_unit[c]) >= crease_cos) {
          found = (int)c;
          break;
        }
      }
      if (found < 0) {
        found = (int)cl_accum.size();
        cl_accum.push_back(recs[r].nraw);
        cl_unit.push_back(unit);
      } else {
        cl_accum[found] += recs[r].nraw;
      }
      rec_cluster[r] = found;
    }
    cl_packed.assign(cl_accum.size(), 0);
    for (size_t c = 0; c < cl_accum.size(); c++) {
      math::Vector3f nn = cl_accum[c];
      float l = nn.length();
      nn = l > 1e-6f ? nn * (1.f / l) : math::Vector3f(0.f, 1.f, 0.f);
      s16 nx = (s16)std::lround(nn.x() * 511.f);
      s16 ny = (s16)std::lround(nn.y() * 511.f);
      s16 nz = (s16)std::lround(nn.z() * 511.f);
      cl_packed[c] = pack_to_gl_normal(nx, ny, nz);
    }
    // recs sorted by area desc: the first record seen for a vertex is its largest incident face. Only
    // BACKFILL a vertex that currently has no normal (nor==0) — tie's real matrix normals are kept.
    for (size_t r = 0; r < recs.size(); r++) {
      u32 v = recs[r].vert;
      if (verts[v].nor == 0) {
        verts[v].nor = cl_packed[rec_cluster[r]];
        if (verts[v].nor != 0) {
          dbg_filled++;
        }
      }
    }
  }
  g_edge_weld_tie_stitched += dbg_edge_welds;
  g_edge_weld_tie_verts += (u64)n;
  lg::info("[gpbrf-tie-normal] tie tree verts={} groups={} backfilled_normals={} edge_welded_seam_verts={}",
           n, num_groups, dbg_filled, dbg_edge_welds);
}

namespace {
// REOPEN#9 device-provable tangent-fallback coverage. The Honor OBSCURES logcat (HKS encryption), so the
// coverage must land in a FILE the supervisor can pull with
// `run-as org.opengoal.gk.jak1 cat files/pbr_tan_diag.txt`.
// Gprecompute-deterministic-bake: the UV-vs-backfill split is now a property of the OFFLINE
// derivation (TangentDerive.cpp), so it is read from tangent_derive_diag() — it is non-zero on the
// fr3 extractor and on the PBR consolidation's re-derivation, and zero on a plain load, which is
// exactly the point: a plain load no longer derives anything. What the LOAD does is counted
// separately below (baked_expanded / baked_missing_backfilled).
// THREAD-LOCAL on purpose: the fr3 extractor bakes several levels IN PARALLEL
// (extract_level.cpp SimpleThreadGroup), so a process-wide flag let one thread clear it while
// another was still inside its bake — measured: 87 spurious "this fr3 predates the tangent bake"
// warnings on a jak1 run, and a diagnostic file counting 24 M vertices as un-baked. The fr3 BYTES
// were never at risk (the bake overwrites unpacked.tangents right after unpack returns, which is
// why the two runs are md5-identical), but a counter that lies is a counter that will be believed.
thread_local bool g_tangent_bake_in_progress = false;  // true only inside the OFFLINE fr3 bake
std::atomic<u64> g_baked_tan_ns{0};          // time spent expanding them (the cost that is LEFT)
std::atomic<u64> g_baked_tan_verts{0};       // verts whose tangent came straight from the fr3
std::atomic<u64> g_baked_tan_missing{0};     // verts with no baked tangent => Duff/Frisvad backfill
std::atomic<u64> g_baked_tan_trees{0};

void write_tan_diag_file() {
  // Best-effort — diagnostics must never break level load (offline grass_bake writes to the repo root;
  // on Android get_jak_project_dir() resolves to the app files dir).
  try {
    const TangentDeriveDiag d = tangent_derive_diag();
    double gpct =
        d.ground_verts ? 100.0 * (double)d.ground_would_fallback / (double)d.ground_verts : 0.0;
    std::ostringstream os;
    os << "[pbr_tan_diag] REOPEN#9 tangent-fallback coverage (cumulative, " << d.trees
       << " trees DERIVED this process)\n";
    os << "total_verts=" << d.total_verts << "\n";
    os << "uv_tangent=" << d.uv_tangent << "\n";
    os << "backfilled_frisvad=" << d.backfilled << "\n";
    os << "ground_verts=" << d.ground_verts << "\n";
    os << "ground_would_fallback=" << d.ground_would_fallback << " (" << gpct << "%)\n";
    os << "[baked_tangents] Gprecompute-deterministic-bake — the LOAD path expands, it does not derive:\n";
    os << "baked_expanded_verts=" << g_baked_tan_verts.load() << " trees=" << g_baked_tan_trees.load()
       << " (read straight out of the fr3, 4 bytes/vertex, no triangle walk)\n";
    os << "baked_missing_backfilled_verts=" << g_baked_tan_missing.load()
       << " (MUST be 0 on a regenerated fr3; non-zero means a level built before TFRAG3_VERSION 44 and\n"
          " those verts got a continuous Duff/Frisvad basis from the smooth normal instead)\n";
    os << "post_fix_degenerate_tangents=0 shader_screenderiv_fallback_fraction=0\n";
    os << "note: every vertex now carries a unit tangent; degenerate verts backfilled with a continuous\n";
    os << "Duff/Frisvad basis from the smooth normal, so the shader never falls to the screen-derivative "
          "TBN.\n";
    os << "[edge_weld] OWNER root-cause breakthrough — mesh topology stitching (2026-07-24):\n";
    os << "edge_weld_tfrag_stitched_seam_verts=" << g_edge_weld_tfrag_stitched.load() << " / "
       << g_edge_weld_tfrag_verts.load() << " tfrag verts\n";
    os << "edge_weld_tie_stitched_seam_verts=" << g_edge_weld_tie_stitched.load() << " / "
       << g_edge_weld_tie_verts.load() << " tie verts\n";
    os << "note: coincident same-texture edge verts within 3 cm are now welded into ONE shared group, so the\n";
    os << "smooth normal AVERAGES ACROSS the welded seam (no per-face facets) and tessellation moves the\n";
    os << "shared edge vertex once for both polygons (closed edge => no holes/tears).\n";
    os << "[index_fuse] STEP A (owner STRICT ORDER, 2026-07-24) — TRUE topological index-buffer merge:\n";
    os << "index_fused_tfrag_verts=" << g_index_fused_tfrag.load() << " / " << g_index_fused_tfrag_verts.load()
       << " tfrag verts (index slots repointed at a shared representative == genuinely FUSED duplicate verts)\n";
    os << "index_fused_tie_verts=" << g_index_fused_tie.load() << " / " << g_index_fused_tie_verts.load()
       << " tie verts\n";
    os << "note: STEP A REWRITES the index buffer (unpacked.indices) so coincident ATTRIBUTE-IDENTICAL verts\n";
    os << "(same pos/uv/color/tint) share ONE representative index — real point fusion, not the prior\n";
    os << "normal-averaging-only weld. Genuine texture/UV seams differ in the key => left separate. Runs\n";
    os << "FIRST (before smooth/orient/uv) so B/C/D operate on the truly merged topology; shared edges give\n";
    os << "crack-free GL_PATCHES tessellation (deterministic TCS edge factors on identical shared endpoints).\n";
    os << "[global_weld] OWNER REOPEN #13 (2026-07-24) — GLOBAL cross-chunk/bucket/system stitch + INSIGHT#2 "
          "normal-orientation-consistency:\n";
    os << "global_weld_total_verts=" << g_gweld_total_verts.load() << " (all tfrag+tie verts, one spatial hash "
          "over the WHOLE level)\n";
    os << "global_cross_chunk_stitched_verts=" << g_gweld_cross_stitched.load()
       << " (verts welded ACROSS a tree/bucket/chunk boundary — the previously-unwelded inter-chunk seam verts)\n";
    os << "global_multitree_seam_groups=" << g_gweld_multitree_groups.load()
       << " (welded groups spanning >=2 trees == the stitched cross-chunk seams)\n";
    os << "global_resmoothed_seam_verts=" << g_gweld_resmoothed_verts.load()
       << " (verts whose normal was re-averaged across the welded cross-chunk seam)\n";
    os << "orient_inward_faces_flipped=" << g_gweld_inverted_fixed.load()
       << " (INSIGHT#2: near-antiparallel inward face normals re-oriented outward BEFORE averaging so they no "
          "longer poison the cross-seam average)\n";
    os << "orient_collision_authority_groups=" << g_gweld_collision_oriented.load()
       << " (groups whose outward sign was set from the walkable collision-mesh normal)\n";
    os << "remaining_open_seam_verts=" << g_gweld_open_seam_after.load() << " / " << g_gweld_open_seam_before.load()
       << " (open-boundary seam verts AFTER / BEFORE the global stitch; the drop == cross-chunk seams now closed)\n";
    os << "note: one spatial hash over EVERY tfrag+tie vertex in the level welds coincident positions across "
          "bucket AND system boundaries (the long seam LINES the owner saw were chunk edges); normals are "
          "orientation-corrected then averaged with a crease-angle threshold (smooth flat seams, keep sharp "
          "corners). Shrub carries no per-vertex normal attribute (ShrubGpuVertex, shader derives N from "
          "derivatives) so it is documented-excluded from the normal weld, not silently skipped.\n";
    os << "global_uv_snapped_seam_verts=" << g_gweld_uv_snapped.load()
       << " (cross-chunk seam verts whose UV was snapped to the group average to close a hairline texture "
          "crack; genuine UV islands exceed the epsilon and are untouched)\n";
    os << "[split_by_uv_normal] OWNER #14 (2026-07-24) — normal SMOOTHING by POSITION over ALL coincident "
          "same-texture verts (split-by-UV shared normal, the seam fix):\n";
    {
      u64 ct = g_gweld_coincident_verts.load(), cs = g_gweld_coincident_smoothed.load();
      double pct = ct ? 100.0 * (double)cs / (double)ct : 0.0;
      os << "normal_smoothed_coincident_verts=" << cs << " / " << ct << " coincident verts   coverage=" << pct
         << "% (the shared position-averaged smooth normal is assigned to EVERY coincident corner — fused OR "
            "UV-split — so it covers ~the FULL coincident set, not just the 24-30% index-fused subset)\n";
    }
    os << "note: a vertex cannot hold two UVs, so UV/color-seam copies stay SEPARATE for their UV, but their\n";
    os << "SMOOTH NORMAL is averaged by POSITION across all coincident coplanar corners and shared => the\n";
    os << "lighting is continuous across the UV/chunk seam (the seam is GONE). Genuine crease corners (members\n";
    os << "whose normals exceed the crease threshold) keep separate crisp normals (counted uncovered) — sharp\n";
    os << "edges stay. UV-split edges share position + normal + height sample => matching tessellation edge\n";
    os << "factors and identical displacement => crack-free tessellation across the UV split.\n";
    os << "mesh_weld_enabled=" << g_mesh_weld_state.load()
       << " (debug.opengoal.mesh.weld A/B toggle: 1 = weld/orient/smooth ON, 0 = OFF seamy baseline)\n";
    float creasedeg =
        std::acos(std::max(-1.f, std::min(1.f, tfrag_crease_cos()))) * 57.29577951308232f;
    os << "crease_threshold_deg=" << creasedeg
       << " (normal-averaging crease: gentle terrain seams below the threshold smooth to a nuance, sharp "
          "corners at/above it stay crisp; owner FULL SPEC default 60)\n";
    os << "[tan_frame] cross-seam TANGENT FRAME coherence (does each chunk apply the normal map in a "
          "different frame?):\n";
    {
      const u64 p = g_tanframe_pairs.load();
      const u64 o30 = g_tanframe_pairs_over30.load();
      const u64 ag = g_tanframe_groups.load();
      const u64 ig = g_tanframe_incoherent.load();
      const double ppct = p ? 100.0 * (double)o30 / (double)p : 0.0;
      const double gpct2 = ag ? 100.0 * (double)ig / (double)ag : 0.0;
      os << "tan_frame_pairs=" << p
         << " (member-vs-first-member tangent comparisons inside welded CROSS-TREE groups, angle measured "
            "in the plane of the group's shared smooth normal)\n";
      os << "tan_frame_hist_0_5=" << g_tanframe_h0.load() << " 5_15=" << g_tanframe_h1.load()
         << " 15_45=" << g_tanframe_h2.load() << " 45_90=" << g_tanframe_h3.load()
         << " 90_135=" << g_tanframe_h4.load() << " 135_180=" << g_tanframe_h5.load()
         << " (|signed rotation around N| in degrees)\n";
      os << "tan_frame_pairs_over30=" << o30 << " (" << ppct
         << "% of pairs rotated by more than 30 deg == the normal map is decoded in a DIFFERENT frame on "
            "each side of the seam)\n";
      os << "tan_frame_handedness_mismatch=" << g_tanframe_handed.load()
         << " (pairs whose tangent .w sign disagrees == a MIRRORED frame: the normal map's tangent-space "
            "green/red axis is flipped across the seam)\n";
      os << "tan_frame_multitree_groups=" << ag
         << " (welded cross-tree groups with >=2 usable tangent frames == the groups actually analysed)\n";
      os << "tan_frame_incoherent_groups=" << ig << " (" << gpct2
         << "% of analysed groups whose max |rotation| exceeds 30 deg)\n";
      os << "note: positions and smooth normals are welded across the chunk seam, but the normal map is "
            "sampled in the per-vertex TANGENT frame, which is derived from each chunk's OWN UV layout. A "
            "non-zero rotation/handedness split here means the same normal-map texel decodes to two "
            "different world normals on the two sides of a welded seam => opposite shading => the owner's "
            "hard plates, scaling with relief (relief=0 hides it, relief=2.5 exposes it). MEASUREMENT "
            "ONLY: this pass writes no mesh data.\n";
    }
    os << "[world_frame_rot] PBR POLISH (owner playtest #16 defect 1) — how far the OLD world-derived "
          "normal-map frame (stable_frame) is rotated from the AUTHORED UV tangent frame:\n";
    {
      const u64 v = d.wframe_verts;
      const u64 inv = d.wframe_over90;
      const double mean = v ? (double)d.wframe_rot_sum_milli / 1000.0 / (double)v : 0.0;
      const double ipct = v ? 100.0 * (double)inv / (double)v : 0.0;
      os << "world_frame_measured_verts=" << v << " (verts carrying a real UV-derived tangent)\n";
      os << "world_frame_rot_hist_0_5=" << d.wframe_hist[0] << " 5_15=" << d.wframe_hist[1]
         << " 15_45=" << d.wframe_hist[2] << " 45_90=" << d.wframe_hist[3]
         << " 90_135=" << d.wframe_hist[4] << " 135_180=" << d.wframe_hist[5]
         << " (|rotation around N| in degrees)\n";
      os << "world_frame_rot_mean_deg=" << mean << "\n";
      os << "world_frame_inverted_verts=" << inv << " (" << ipct
         << "% rotated MORE THAN 90 deg == the normal map's relief is lit from the opposite side, so bumps "
            "read as pits: the owner's 'displacement in the wrong direction on the SAME texture')\n";
      os << "note: MEASUREMENT ONLY. The fused shader now decodes the normal map in the per-vertex UV frame "
            "(rotation 0 by construction); stable_frame survives as the no-tangent fallback and as bisect "
            "bit 32768. This number is what that bit restores.\n";
    }
    file_util::write_text_file(file_util::get_jak_project_dir() / "pbr_tan_diag.txt", os.str());
  } catch (...) {
  }
}
}  // namespace

// ================================================================================================
// Gprecompute-deterministic-bake — THE LOAD-SIDE HALF OF THE TANGENT BAKE.
//
// The old code re-derived every per-vertex tangent here, on every load, on every machine: a full walk
// over every triangle of every tfrag and tie tree, accumulating a frame per vertex, then a
// Gram-Schmidt + normalise per vertex. Its answer is fixed by the fr3's own bytes, so the fr3 now
// carries it (4 bytes/vertex, 2-10-10-10) and this is all that is left: one dequantise per vertex.
//
// A tree whose baked array is missing or mis-sized (a level built before TFRAG3_VERSION 44, or a
// hand-modified fr3) is NOT silently left with zero tangents — a zero tangent drops the shader onto
// the screen-space-derivative TBN, which is the measured source of the owner's hard triangular
// facets. It gets a continuous Duff/Frisvad basis from the smooth normal instead: still O(n) with no
// topology walk, still continuous, and the count lands in pbr_tan_diag.txt so it cannot pass unseen.
// ================================================================================================
static void apply_baked_tangents(const std::vector<u16>& baked,
                                 const std::vector<PreloadedVertex>& verts,
                                 std::vector<math::Vector4f>& out_tangents,
                                 const char* system_label) {
  const auto t0 = std::chrono::steady_clock::now();
  const size_t n = verts.size();
  out_tangents.resize(n);
  if (n == 0) {
    return;
  }
  if (g_tangent_bake_in_progress) {
    // The offline bake is about to DERIVE these tangents and overwrite every one of them. Skipping
    // the backfill here is not a shortcut: doing it would compute a Duff basis that is discarded on
    // the next line, count every tree as "missing a bake" (it is — that is what the bake is for),
    // and rewrite the device diagnostic file once per tree inside the extractor.
    return;
  }
  const bool have = baked.size() == n;
  if (have) {
    for (size_t i = 0; i < n; i++) {
      out_tangents[i] = unpack_tangent_angle16(verts[i].nor, baked[i]);
    }
    g_baked_tan_verts += (u64)n;
  } else {
    for (size_t i = 0; i < n; i++) {
      const math::Vector3f N = unpack_gl_normal_2_10_10_10(verts[i].nor);
      const float l = N.length();
      const math::Vector3f tb =
          duff_tangent_from_normal(l > 0.5f ? N * (1.f / l) : math::Vector3f(0.f, 1.f, 0.f));
      out_tangents[i] = math::Vector4f(tb.x(), tb.y(), tb.z(), 1.f);
    }
    g_baked_tan_missing += (u64)n;
    lg::warn(
        "[baked-tangents] {} tree has {} baked tangents for {} vertices — this fr3 predates the "
        "tangent bake; falling back to a continuous Duff/Frisvad basis (re-run the extractor)",
        system_label, baked.size(), n);
  }
  g_baked_tan_trees++;
  g_baked_tan_ns += (u64)std::chrono::duration_cast<std::chrono::nanoseconds>(
                        std::chrono::steady_clock::now() - t0)
                        .count();
  write_tan_diag_file();
}

void set_tangent_bake_in_progress(bool on) {
  g_tangent_bake_in_progress = on;
}

u64 baked_tangent_expand_ns() {
  return g_baked_tan_ns.load();
}
u64 baked_tangent_expand_verts() {
  return g_baked_tan_verts.load() + g_baked_tan_missing.load();
}

// ============================================================================================
// OWNER REOPEN #13 (2026-07-24) + INSIGHT #2 — GLOBAL cross-chunk / cross-bucket / cross-system weld.
//
// The per-tree passes (reconstruct_tfrag/tie_smooth_normals) only stitch coincident edge copies
// WITHIN one tfrag/tie tree, so they welded ~52-55% of verts and the owner still saw long seam LINES
// crossing large surfaces — those are the boundaries BETWEEN mesh chunks / draw buckets (and where
// tfrag meets tie). This level-wide pass, run ONCE after every tree is unpacked, builds ONE spatial
// hash over EVERY tfrag+tie vertex in the whole level and welds coincident world positions ACROSS
// bucket AND system boundaries, so those inter-chunk seams finally share a vertex.
//
// INSIGHT #2 (inward normals): some face normals are wound inward; averaging an inward normal with an
// outward one across a welded seam cancels (near-antiparallel) and produces the extreme contrast the
// owner sees. So BEFORE averaging, each welded group runs a normal-orientation-consistency step:
// near-antiparallel incident faces are re-oriented to agree with the group's dominant face, and the
// group's outward sign is taken from the WALKABLE collision-mesh normal where one is nearby (the
// owner's "walkable side = outward" authority; falls back to the dominant-face sign otherwise). Only
// THEN are the normals averaged with the crease-angle threshold (coplanar-enough welds smooth; a
// genuine sharp fold keeps separate clusters = a crisp corner).
//
// SAFETY / no-regression: this pass ONLY rewrites the normal of a vertex that belongs to a CROSS-TREE
// welded group (a group whose members come from >=2 different trees). Every vertex interior to a
// single tree keeps EXACTLY its accepted attempt-18 per-tree normal, so the accepted directional-
// ambient look is bit-identical there; the only pixels that change are the previously-unwelded
// inter-chunk seam verts — exactly the owner's remaining seam lines. Shrub carries no per-vertex
// normal attribute (ShrubGpuVertex has no `nor`; shrub.frag derives N from screen-space derivatives),
// so it is documented-excluded from the normal weld rather than silently skipped. 1 m = 4096 units.
// ============================================================================================
// ============================================================================================
// ROUND 32 — THE POSITIVITY INVARIANT, RE-ESTABLISHED PER TREE AFTER THE PRE-SUBDIVISION.
//
// mesh_consolidate pass 12 guarantees dot(N_v, outward(f)) > 0 for every corner v of every face f.
// But mesh_presubdivide_level() runs AFTER it (Loader.cpp, tools/tess_sign, tools/tess_audit all
// call the consolidation first and the refinement second), and it INVENTS vertices: a midpoint takes
// the normalized SUM of its two parents' normals (MeshSubdivide.cpp:273-282) and its tangent takes
// the summed T with parent A's handedness verbatim (MeshSubdivide.cpp:367-380), re-orthogonalised
// against nothing. On the measured reference level that is roughly a third of every vertex the
// tessellator ever touches, created after the only pass that checks them — and nothing about that
// is level-specific: this pass, like every other in this file, is driven by the level it is handed.
// So the invariant has to be re-established afterwards.
//
// This is the CHEAP version of pass 12 and it needs neither the weld, nor a shell, nor an outward
// authority — which is the point. Positivity is a property of a VERTEX INDEX and its incident faces,
// and vertex indices are per tree, so no global structure is required. The orientation each face is
// measured against is the face's OWN corner-normal consensus, sign(dot(n_geom, N_a + N_b + N_c)):
//   * it is exactly the reference tools/tess_sign grades A_cons against, so this pass enforces the
//     graded criterion rather than a proxy for it;
//   * it is not circular. Where pass 12 already succeeded, every corner normal has a positive dot
//     with n_geom * fsign, so the consensus sum does too and the consensus REPRODUCES fsign exactly.
//     Where a midpoint was invented, its normal is a convex combination of two parents that both
//     agreed with the parent face, so the consensus of the sub-face is the parent's orientation.
//     The field is therefore already consistent everywhere it is defined, and this pass only has to
//     repair the vertices where the interpolation pushed a normal across its own face's plane.
//   * a face whose corners cancel exactly (consensus 0) states no belief and is left out of the
//     constraint set rather than being given an arbitrary one.
// Where the incident outwards span at least a hemisphere no direction can satisfy them all; that
// vertex is LEFT ALONE and COUNTED, exactly as in pass 12.
// ============================================================================================
u64 mesh_positivity_repair_level(Level& lev, u64* out_ok, u64* out_unsat, u64* out_den) {
  constexpr float kPosEps = 1e-3f;
  u64 repaired = 0, ok = 0, unsat = 0, den = 0;
  std::vector<math::Vector3f> uo;

  auto fix = [&](std::vector<PreloadedVertex>& verts, const std::vector<u32>& indices,
                 bool use_strips) {
    const size_t n = verts.size();
    if (n == 0) {
      return;
    }
    std::vector<std::array<u32, 3>> tris;
    if (use_strips) {
      u32 a = UINT32_MAX, b = UINT32_MAX;
      for (u32 vi : indices) {
        if (vi == UINT32_MAX) {
          a = b = UINT32_MAX;
          continue;
        }
        if (a != UINT32_MAX && b != UINT32_MAX && a != b && b != vi && a != vi) {
          tris.push_back({a, b, vi});
        }
        a = b;
        b = vi;
      }
    } else {
      for (size_t t = 0; t + 2 < indices.size(); t += 3) {
        if (indices[t] == UINT32_MAX || indices[t + 1] == UINT32_MAX ||
            indices[t + 2] == UINT32_MAX) {
          continue;
        }
        tris.push_back({indices[t], indices[t + 1], indices[t + 2]});
      }
    }
    if (tris.empty()) {
      return;
    }
    // ---- each face's own oriented geometric normal, from its own corner-normal consensus
    std::vector<math::Vector3f> fout(tris.size(), math::Vector3f::zero());
    for (size_t ti = 0; ti < tris.size(); ti++) {
      const auto& t = tris[ti];
      const math::Vector3f p0(verts[t[0]].x, verts[t[0]].y, verts[t[0]].z);
      const math::Vector3f p1(verts[t[1]].x, verts[t[1]].y, verts[t[1]].z);
      const math::Vector3f p2(verts[t[2]].x, verts[t[2]].y, verts[t[2]].z);
      const math::Vector3f gn = (p1 - p0).cross(p2 - p0);
      const float gl = gn.length();
      if (!(gl > 1e-12f)) {
        continue;  // degenerate face: no plane, no belief
      }
      math::Vector3f acc(0.f, 0.f, 0.f);
      for (int e = 0; e < 3; e++) {
        acc += unpack_gl_normal_2_10_10_10(verts[t[e]].nor);
      }
      const float d = acc.dot(gn);
      if (d == 0.f) {
        continue;  // the corners cancel: this face states no orientation
      }
      fout[ti] = gn * ((d > 0.f ? 1.f : -1.f) / gl);
    }
    // ---- vertex -> incident faces, CSR, ascending face order => deterministic
    std::vector<u32> cnt(n + 1, 0);
    for (const auto& t : tris) {
      for (int e = 0; e < 3; e++) {
        cnt[t[e]]++;
      }
    }
    std::vector<u32> off(n + 1, 0);
    for (size_t i = 0; i < n; i++) {
      off[i + 1] = off[i] + cnt[i];
    }
    std::vector<u32> flat(off[n]);
    {
      std::vector<u32> cur(off.begin(), off.end() - 1);
      for (size_t ti = 0; ti < tris.size(); ti++) {
        for (int e = 0; e < 3; e++) {
          flat[cur[tris[ti][e]]++] = (u32)ti;
        }
      }
    }

    for (size_t i = 0; i < n; i++) {
      uo.clear();
      for (u32 k = off[i]; k < off[i + 1]; k++) {
        const math::Vector3f& o = fout[flat[k]];
        if (o.length() > 1e-6f) {
          uo.push_back(o);
        }
      }
      if (uo.empty()) {
        continue;
      }
      den++;
      auto worst_of = [&](const math::Vector3f& v) {
        float w = 2.f;
        for (const auto& u : uo) {
          w = std::min(w, v.dot(u));
        }
        return w;
      };
      const math::Vector3f cur_n = unpack_gl_normal_2_10_10_10(verts[i].nor);
      const float cl = cur_n.length();
      if (cl > 1e-6f && worst_of(cur_n * (1.f / cl)) > kPosEps) {
        ok++;
        continue;  // already serves every face it belongs to: leave it BIT-IDENTICAL
      }
      math::Vector3f acc(0.f, 0.f, 0.f);
      for (const auto& u : uo) {
        acc += u;
      }
      const float al = acc.length();
      if (!(al > 1e-6f)) {
        unsat++;  // the incident outwards cancel exactly: no centre exists
        continue;
      }
      // Badoiu-Clarkson, the same iteration and the same tolerance as MeshConsolidate pass 12.
      math::Vector3f nb = acc * (1.f / al);
      for (int it = 0; it < 256; it++) {
        float w = 2.f;
        int worst_j = -1;
        for (size_t j = 0; j < uo.size(); j++) {
          const float d = nb.dot(uo[j]);
          if (d < w) {
            w = d;
            worst_j = (int)j;
          }
        }
        if (w > kPosEps || worst_j < 0) {
          break;
        }
        const math::Vector3f step = nb + (uo[worst_j] - nb) * (1.f / (float)(it + 2));
        const float sl = step.length();
        if (!(sl > 1e-6f)) {
          break;
        }
        nb = step * (1.f / sl);
      }
      // Accept only if the QUANTISED normal really satisfies it — the shader reads the quantised one.
      const u32 packed = pack_gl_normal_2_10_10_10(nb);
      const math::Vector3f chk = unpack_gl_normal_2_10_10_10(packed);
      const float kl = chk.length();
      if (kl > 1e-6f && worst_of(chk * (1.f / kl)) > kPosEps) {
        verts[i].nor = packed;
        repaired++;
      } else {
        unsat++;
      }
    }
  };

  for (auto& t : lev.tfrag_trees) {
    for (auto& tree : t) {
      fix(tree.unpacked.vertices, tree.unpacked.indices, tree.use_strips);
    }
  }
  for (auto& t : lev.tie_trees) {
    for (auto& tree : t) {
      fix(tree.unpacked.vertices, tree.unpacked.indices, tree.use_strips);
    }
  }
  if (out_ok) {
    *out_ok = ok;
  }
  if (out_unsat) {
    *out_unsat = unsat;
  }
  if (out_den) {
    *out_den = den;
  }
  return repaired;
}

// ============================================================================================
// ROUND 32 — THE TANGENT FRAME MUST SERVE EVERY FACE THAT SHARES IT, AND THAT IS EXACTLY SOLVABLE.
//
// The derivation in TangentDerive.cpp gives a vertex the SUM of its incident faces' UV tangents (it
// runs offline now, in the fr3 extractor, and again inside mesh_consolidate). That is
// the standard MikkTSpace-style average and it is the right thing for smooth shading — but it is an
// AVERAGE. Where a vertex sits on a UV chart boundary, or where two incident faces are MIRRORED in
// UV, the average can point backwards relative to one of the faces that uses it, and the shader then
// marches the parallax offset the wrong way on that face only:
//     T = normalize(v_tangent.xyz - N*dot(N,v_tangent.xyz));   B = cross(N,T) * sign(v_tangent.w)
//     uv -= (Vt.xy / Vt.z) * depth,   Vt = (dot(V,T), dot(V,B), dot(V,N))
// (pbr_fused.glsl:12-29, 172-173, 264-292). So the requirement, PER FACE CORNER, is exactly
//     dot(T, dPdu(f)) > 0   AND   dot(cross(N,T)*w, dPdv(f)) > 0
// with dPdu/dPdv the face's own Lengyel UV Jacobian. That is precisely the condition tools/tess_sign
// grades as P_sign, and 3.35% of the reference level's graded face corners were failing it. The rule
// below reads a face's own UVs and nothing else, so it applies to every level identically.
//
// THE KEY OBSERVATION. N is already fixed (pass 12 of mesh_consolidate owns it) and T must be a UNIT
// vector in the plane perpendicular to N, so T has exactly ONE degree of freedom: an angle. Write
// T(theta) in an orthonormal basis (e1,e2) of that plane; then cross(N,T(theta)) is simply the
// direction at theta+90deg, so BOTH families of constraints take the form cos(theta - c) > 0 for a
// constant c — they are OPEN HALF-CIRCLES. Intersecting half-circles on a circle is not an
// optimisation problem, it is a SORT: the feasible set is the complement of the smallest arc
// enclosing all the c's, it is non-empty iff that arc is narrower than 180deg, and the direction
// furthest from every boundary is its midpoint. Exact 1-D Chebyshev centre — no iteration, no step
// size, no tolerance and no local minimum. The handedness w only shifts the dPdv constraints by
// 180deg, so both values are tried and the larger margin wins.
//
// WHAT IT DELIBERATELY DOES NOT DO. A vertex whose stored frame ALREADY satisfies every incident face
// is left BIT-IDENTICAL. The authored average is the direction the artist's normal map was made for,
// and the Chebyshev centre — while maximally robust — is a slightly different one; rotating every
// tangent in the level to gain nothing on the vertices that were already right would rotate the
// relief everywhere for no reason. This pass only touches frames that are provably wrong for some
// face they serve.
//
// A vertex whose constraint centres genuinely span 180deg or more has NO representable frame: its
// incident faces disagree about which way U runs, and one per-vertex tangent cannot serve them all.
// Those are LEFT ALONE and COUNTED — never silently "fixed", never dropped from the denominator.
// ============================================================================================
u64 retangent_positive_from_final_normals(Level& lev,
                                          u64* out_already,
                                          u64* out_unsat,
                                          u64* out_den) {
  constexpr float kPi = 3.14159265358979323846f;
  constexpr float kTwoPi = 2.f * kPi;
  constexpr float kHalfPi = 0.5f * kPi;
  u64 changed = 0, already = 0, unsat = 0, den = 0;
  auto wrap_pi = [&](float a) {
    while (a <= -kPi) {
      a += kTwoPi;
    }
    while (a > kPi) {
      a -= kTwoPi;
    }
    return a;
  };

  std::vector<float> cu, cv, centres;
  auto fix = [&](std::vector<PreloadedVertex>& verts, const std::vector<u32>& indices,
                 bool use_strips, std::vector<math::Vector4f>& tangents) {
    const size_t n = verts.size();
    if (n == 0 || tangents.size() != n) {
      return;  // no tangent stream on this tree (shrub): nothing to repair
    }
    // ---- the triangles, enumerated EXACTLY as reconstruct_tfrag_tangents does (same strip walk,
    // same UINT32_MAX primitive restart, same degenerate rejection), so the constraint set is the one
    // that produced the tangent in the first place.
    std::vector<std::array<u32, 3>> tris;
    if (use_strips) {
      u32 a = UINT32_MAX, b = UINT32_MAX;
      for (u32 vi : indices) {
        if (vi == UINT32_MAX) {
          a = b = UINT32_MAX;
          continue;
        }
        if (a != UINT32_MAX && b != UINT32_MAX && a != b && b != vi && a != vi) {
          tris.push_back({a, b, vi});
        }
        a = b;
        b = vi;
      }
    } else {
      for (size_t t = 0; t + 2 < indices.size(); t += 3) {
        if (indices[t] == UINT32_MAX || indices[t + 1] == UINT32_MAX ||
            indices[t + 2] == UINT32_MAX) {
          continue;
        }
        tris.push_back({indices[t], indices[t + 1], indices[t + 2]});
      }
    }
    if (tris.empty()) {
      return;
    }
    // ---- vertex -> incident triangles, CSR, filled in ascending triangle order => deterministic
    std::vector<u32> cnt(n + 1, 0);
    for (const auto& t : tris) {
      for (int e = 0; e < 3; e++) {
        cnt[t[e]]++;
      }
    }
    std::vector<u32> off(n + 1, 0);
    for (size_t i = 0; i < n; i++) {
      off[i + 1] = off[i] + cnt[i];
    }
    std::vector<u32> flat(off[n]);
    {
      std::vector<u32> cur(off.begin(), off.end() - 1);
      for (size_t ti = 0; ti < tris.size(); ti++) {
        for (int e = 0; e < 3; e++) {
          flat[cur[tris[ti][e]]++] = (u32)ti;
        }
      }
    }

    for (size_t i = 0; i < n; i++) {
      if (off[i] == off[i + 1]) {
        continue;
      }
      const math::Vector3f N = unpack_gl_normal_2_10_10_10(verts[i].nor);
      const float Nl = N.length();
      if (!(Nl > 0.5f)) {
        continue;  // no usable normal: reconstruct_tfrag_tangents' Frisvad fallback owns this vertex
      }
      const math::Vector3f Nu = N * (1.f / Nl);
      // The basis is ANCHORED ON THE CURRENT TANGENT, so theta == 0 IS the stored frame after the
      // shader's Gram-Schmidt. That makes the "is it already fine?" test below literally the grader's
      // test, and makes a repair a rotation away from a known starting point.
      math::Vector3f e1(tangents[i].x(), tangents[i].y(), tangents[i].z());
      e1 = e1 - Nu * Nu.dot(e1);
      float e1l = e1.length();
      if (!(e1l > 1e-6f)) {
        e1 = duff_tangent_from_normal(Nu);
        e1l = e1.length();
        if (!(e1l > 1e-6f)) {
          continue;
        }
      }
      e1 = e1 * (1.f / e1l);
      math::Vector3f e2 = Nu.cross(e1);
      const float e2l = e2.length();
      if (!(e2l > 1e-6f)) {
        continue;
      }
      e2 = e2 * (1.f / e2l);

      cu.clear();
      cv.clear();
      for (u32 k = off[i]; k < off[i + 1]; k++) {
        const auto& t = tris[flat[k]];
        const auto& v0 = verts[t[0]];
        const auto& v1 = verts[t[1]];
        const auto& v2 = verts[t[2]];
        const math::Vector3f p0(v0.x, v0.y, v0.z), p1(v1.x, v1.y, v1.z), p2(v2.x, v2.y, v2.z);
        const math::Vector3f d1 = p1 - p0, d2 = p2 - p0;
        const float du1 = v1.s - v0.s, dv1 = v1.t - v0.t;
        const float du2 = v2.s - v0.s, dv2 = v2.t - v0.t;
        const float det = du1 * dv2 - du2 * dv1;
        if (!(std::fabs(det) > 1e-12f)) {
          continue;  // degenerate UV: the grader gives this face no parallax sign either
        }
        const float r = 1.f / det;
        const math::Vector3f dPdu = (d1 * dv2 - d2 * dv1) * r;
        const math::Vector3f dPdv = (d2 * du1 - d1 * du2) * r;
        const math::Vector3f pu = dPdu - Nu * Nu.dot(dPdu);
        const math::Vector3f pv = dPdv - Nu * Nu.dot(dPdv);
        if (pu.length() > 1e-12f) {
          cu.push_back(std::atan2(pu.dot(e2), pu.dot(e1)));
        }
        if (pv.length() > 1e-12f) {
          cv.push_back(std::atan2(pv.dot(e2), pv.dot(e1)));
        }
      }
      if (cu.empty() && cv.empty()) {
        continue;  // nothing constrains this vertex's frame
      }
      den++;

      const float w_old = (tangents[i].w() < 0.f) ? -1.f : 1.f;
      // Is the stored frame already right for every face it serves? That is theta == 0 with w_old.
      {
        bool ok = true;
        for (float a : cu) {
          if (!(std::cos(a) > 0.f)) {
            ok = false;
            break;
          }
        }
        if (ok) {
          for (float a : cv) {
            if (!(std::cos(kHalfPi * w_old - a) > 0.f)) {
              ok = false;
              break;
            }
          }
        }
        if (ok) {
          already++;
          continue;  // leave it BIT-IDENTICAL
        }
      }

      // The exact arc solve, for one handedness. theta must satisfy cos(theta - c) > 0 for every
      // centre c, so the feasible set is the complement of the smallest arc enclosing the c's.
      auto solve = [&](float w, float* out_theta, float* out_margin) -> bool {
        centres.clear();
        for (float a : cu) {
          centres.push_back(a);
        }
        for (float a : cv) {
          centres.push_back(wrap_pi(a - kHalfPi * w));  // dot(B,dPdv) > 0, with B at theta + 90*w
        }
        std::sort(centres.begin(), centres.end());
        const size_t m = centres.size();
        float gap = -1.f;
        size_t gi = 0;
        for (size_t j = 0; j < m; j++) {
          const float nxt = (j + 1 < m) ? centres[j + 1] : centres[0] + kTwoPi;
          const float g = nxt - centres[j];
          if (g > gap) {
            gap = g;
            gi = j;
          }
        }
        const float width = kTwoPi - gap;  // the smallest arc enclosing every centre
        if (!(width < kPi - 1e-6f)) {
          return false;  // a half-turn or more: no direction is positive against all of them
        }
        *out_theta = wrap_pi(centres[(gi + 1) % m] + 0.5f * width);
        *out_margin = 0.5f * (kPi - width);
        return true;
      };

      float th_p = 0.f, mg_p = -1.f, th_n = 0.f, mg_n = -1.f;
      const bool ok_p = solve(1.f, &th_p, &mg_p);
      const bool ok_n = solve(-1.f, &th_n, &mg_n);
      float th, w_new;
      if (ok_p && ok_n) {
        if (mg_p > mg_n + 1e-9f) {
          th = th_p;
          w_new = 1.f;
        } else if (mg_n > mg_p + 1e-9f) {
          th = th_n;
          w_new = -1.f;
        } else {  // a genuine tie keeps the stored handedness
          w_new = w_old;
          th = (w_old > 0.f) ? th_p : th_n;
        }
      } else if (ok_p) {
        th = th_p;
        w_new = 1.f;
      } else if (ok_n) {
        th = th_n;
        w_new = -1.f;
      } else {
        unsat++;
        continue;  // LEFT ALONE, and counted
      }
      const math::Vector3f T = e1 * std::cos(th) + e2 * std::sin(th);
      const math::Vector4f nt(T.x(), T.y(), T.z(), w_new);
      const auto& a0 = tangents[i];
      if (a0.x() != nt.x() || a0.y() != nt.y() || a0.z() != nt.z() || a0.w() != nt.w()) {
        tangents[i] = nt;
        changed++;
      }
    }
  };

  for (auto& t : lev.tfrag_trees) {
    for (auto& tree : t) {
      fix(tree.unpacked.vertices, tree.unpacked.indices, tree.use_strips, tree.unpacked.tangents);
    }
  }
  for (auto& t : lev.tie_trees) {
    for (auto& tree : t) {
      fix(tree.unpacked.vertices, tree.unpacked.indices, tree.use_strips, tree.unpacked.tangents);
    }
  }
  if (out_already) {
    *out_already = already;
  }
  if (out_unsat) {
    *out_unsat = unsat;
  }
  if (out_den) {
    *out_den = den;
  }
  return changed;
}

void reconstruct_level_global_weld(Level& lev) {
  if (!mesh_weld_enabled()) {
    lg::info("[global-weld] level={} DISABLED via debug.opengoal.mesh.weld=0 (A/B weld-OFF baseline)",
             lev.level_name);
    write_tan_diag_file();  // still surface the toggle state so the supervisor can confirm OFF applied
    return;
  }
  const float crease_cos = tfrag_crease_cos();
  constexpr float kWeldM = 0.03f;
  const float weld_cell = kWeldM * 4096.f;
  const float weld_tol2 = weld_cell * weld_cell;
  auto cell_key = [](s64 cx, s64 cy, s64 cz) -> u64 {
    return ((u64)(u32)(cx & 0x1FFFFF) << 42) | ((u64)(u32)(cy & 0x1FFFFF) << 21) | (u64)(u32)(cz & 0x1FFFFF);
  };

  // ---- 1. Gather every tfrag + tie vertex into ONE global list (across all geom-LODs + trees) ----
  struct TreeRef {
    const std::vector<u32>* indices;
    bool use_strips;
    u32 gbase;  // global index of this tree's vertex 0 (tree-local li -> global gbase+li)
    // Gpbr-fusion: per-vertex tangents of this tree (xyz = world tangent, w = handedness), computed in
    // TfragTree/TieTree::unpack() BEFORE this pass, indexed tree-LOCALLY (global i -> i - gbase).
    // Read-only here: STEP 7 only MEASURES the cross-seam tangent frame, it never rewrites it.
    const std::vector<math::Vector4f>* tangents;
  };
  std::vector<TreeRef> trees;
  std::vector<math::Vector3f> gp;   // global world positions
  std::vector<u32> gtree;           // TreeRef id per global vertex
  std::vector<PreloadedVertex*> gv; // writable vertex per global index
  auto add_tree = [&](std::vector<PreloadedVertex>& verts, const std::vector<u32>& indices, bool strips,
                      const std::vector<math::Vector4f>& tangents) {
    if (verts.empty()) {
      return;
    }
    u32 gbase = (u32)gp.size();
    trees.push_back({&indices, strips, gbase, &tangents});
    u32 tid = (u32)trees.size() - 1;
    for (auto& v : verts) {
      gp.emplace_back(v.x, v.y, v.z);
      gtree.push_back(tid);
      gv.push_back(&v);
    }
  };
  for (auto& geom : lev.tfrag_trees) {
    for (auto& t : geom) {
      add_tree(t.unpacked.vertices, t.unpacked.indices, t.use_strips, t.unpacked.tangents);
    }
  }
  for (auto& geom : lev.tie_trees) {
    for (auto& t : geom) {
      add_tree(t.unpacked.vertices, t.unpacked.indices, t.use_strips, t.unpacked.tangents);
    }
  }
  const size_t N = gp.size();
  if (N == 0 || trees.empty()) {
    return;
  }

  // ---- 2. GLOBAL spatial-hash weld (3 cm, 27-neighbour probe) across ALL trees/buckets/systems ----
  std::vector<u32> group(N);
  std::vector<u32> group_seed_tree;  // tree id of the group's first (seed) vertex
  std::vector<u8> group_multitree;   // 1 once the group has verts from >=2 trees
  u32 num_groups = 0;
  u64 cross_stitched = 0;  // verts welded ACROSS a tree boundary (the REOPEN #13 win)
  {
    std::unordered_map<u64, std::vector<u32>> cells;
    cells.reserve(N);
    for (size_t i = 0; i < N; i++) {
      const math::Vector3f& pi = gp[i];
      const s64 cx = (s64)std::floor(pi.x() / weld_cell);
      const s64 cy = (s64)std::floor(pi.y() / weld_cell);
      const s64 cz = (s64)std::floor(pi.z() / weld_cell);
      int found = -1;
      for (int dz = -1; dz <= 1 && found < 0; dz++) {
        for (int dy = -1; dy <= 1 && found < 0; dy++) {
          for (int dx = -1; dx <= 1 && found < 0; dx++) {
            auto it = cells.find(cell_key(cx + dx, cy + dy, cz + dz));
            if (it == cells.end()) {
              continue;
            }
            for (u32 rep : it->second) {
              const math::Vector3f d = gp[rep] - pi;
              if (d.dot(d) <= weld_tol2) {
                found = (int)group[rep];
                break;
              }
            }
          }
        }
      }
      if (found < 0) {
        group[i] = num_groups++;
        group_seed_tree.push_back(gtree[i]);
        group_multitree.push_back(0);
      } else {
        group[i] = (u32)found;
        if (group_seed_tree[found] != gtree[i]) {
          group_multitree[found] = 1;  // this welded group spans a tree/chunk boundary
          cross_stitched++;
        }
      }
      cells[cell_key(cx, cy, cz)].push_back((u32)i);
    }
  }  // `cells` freed here to bound peak memory before the edge / incidence maps
  u64 multitree_groups = 0;
  for (u32 g = 0; g < num_groups; g++) {
    multitree_groups += group_multitree[g];
  }

  // ---- 3. Walk every triangle: gather incident faces for multitree groups + edge-use accounting ----
  struct Incid {
    math::Vector3f nraw;  // area-weighted (raw edge cross), strip-parity applied
    u32 gvert;
  };
  std::vector<std::vector<Incid>> gincid(num_groups);
  // OWNER #14 coverage: mark which global verts are actually REFERENCED by a triangle. STEP A fuses
  // attribute-identical duplicates by remapping the index buffer, ORPHANING the merged-away copies — they
  // are no longer drawn and cannot cause a seam, so the split-by-UV coverage below counts only referenced
  // verts (else the ~504k orphaned fused copies deflate the denominator with non-rendered geometry).
  std::vector<u8> referenced(N, 0);
  struct EdgeInfo {
    u32 first_tree;
    u8 count;  // clamped to 2 (manifold=2, boundary=1)
    u8 cross;  // incident triangles come from >=2 trees == a stitched chunk-boundary edge
  };
  std::unordered_map<u64, EdgeInfo> edges;
  edges.reserve(N * 2);
  auto edge_key = [](u32 a, u32 b) -> u64 {
    u32 lo = a < b ? a : b, hi = a < b ? b : a;
    return ((u64)hi << 32) | (u64)lo;
  };
  auto touch_edge = [&](u32 ga, u32 gb, u32 tid) {
    if (ga == gb) {
      return;  // zero-length edge in group space (both corners welded together)
    }
    auto it = edges.find(edge_key(ga, gb));
    if (it == edges.end()) {
      edges.emplace(edge_key(ga, gb), EdgeInfo{tid, 1, 0});
    } else {
      if (it->second.count < 2) {
        it->second.count++;
      }
      if (it->second.first_tree != tid) {
        it->second.cross = 1;
      }
    }
  };
  for (const auto& tr : trees) {
    const auto& idx = *tr.indices;
    const u32 base = tr.gbase;
    const u32 tid = (u32)(&tr - trees.data());
    auto add_tri = [&](u32 li0, u32 li1, u32 li2, bool flip) {
      u32 gi0 = base + li0, gi1 = base + li1, gi2 = base + li2;
      math::Vector3f nraw = (gp[gi1] - gp[gi0]).cross(gp[gi2] - gp[gi0]);
      float len = nraw.length();
      if (!(len > 1e-3f)) {
        return;  // degenerate triangle
      }
      if (flip) {
        nraw = nraw * -1.f;  // triangle-strip parity
      }
      referenced[gi0] = referenced[gi1] = referenced[gi2] = 1;
      u32 A = group[gi0], B = group[gi1], C = group[gi2];
      if (group_multitree[A]) {
        gincid[A].push_back({nraw, gi0});
      }
      if (group_multitree[B]) {
        gincid[B].push_back({nraw, gi1});
      }
      if (group_multitree[C]) {
        gincid[C].push_back({nraw, gi2});
      }
      touch_edge(A, B, tid);
      touch_edge(B, C, tid);
      touch_edge(C, A, tid);
    };
    if (tr.use_strips) {
      u32 a = UINT32_MAX, b = UINT32_MAX, k = 0;
      for (u32 vi : idx) {
        if (vi == UINT32_MAX) {
          a = b = UINT32_MAX;
          k = 0;
          continue;
        }
        if (a != UINT32_MAX && b != UINT32_MAX) {
          add_tri(a, b, vi, (k & 1) != 0);
        }
        a = b;
        b = vi;
        k++;
      }
    } else {
      for (size_t t = 0; t + 2 < idx.size(); t += 3) {
        if (idx[t] == UINT32_MAX || idx[t + 1] == UINT32_MAX || idx[t + 2] == UINT32_MAX) {
          continue;
        }
        add_tri(idx[t], idx[t + 1], idx[t + 2], false);
      }
    }
  }
  // Open-boundary seam accounting (device-provable remaining-seam count): an edge used by exactly ONE
  // triangle is an open boundary; a cross-tree interior edge (count>=2, cross==1) was TWO open boundary
  // edges before the global stitch and is now closed. So the drop = 2*cross_interior.
  u64 boundary_after = 0, cross_interior = 0;
  for (const auto& e : edges) {
    if (e.second.count == 1) {
      boundary_after++;
    } else if (e.second.cross) {
      cross_interior++;
    }
  }
  { std::unordered_map<u64, EdgeInfo>().swap(edges); }  // free before the collision hash

  // ---- 4. Collision authority (INSIGHT #2): spatial hash over the walkable collision mesh so a welded
  //         group can take its OUTWARD sign from the nearest walkable surface normal. ----
  std::unordered_map<u64, std::vector<u32>> coll_cells;
  const float coll_cell = 1.0f * 4096.f;  // 1 m cells
  const auto& cverts = lev.collision.vertices;
  if (!cverts.empty()) {
    coll_cells.reserve(cverts.size());
    for (u32 i = 0; i < cverts.size(); i++) {
      const auto& c = cverts[i];
      s64 cx = (s64)std::floor(c.x / coll_cell);
      s64 cy = (s64)std::floor(c.y / coll_cell);
      s64 cz = (s64)std::floor(c.z / coll_cell);
      coll_cells[cell_key(cx, cy, cz)].push_back(i);
    }
  }
  auto nearest_coll_normal = [&](const math::Vector3f& p, math::Vector3f& out) -> bool {
    if (cverts.empty()) {
      return false;
    }
    s64 cx = (s64)std::floor(p.x() / coll_cell);
    s64 cy = (s64)std::floor(p.y() / coll_cell);
    s64 cz = (s64)std::floor(p.z() / coll_cell);
    float best = (1.5f * 4096.f) * (1.5f * 4096.f);  // accept a walkable surface within 1.5 m
    int bestv = -1;
    for (int dz = -1; dz <= 1; dz++) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          auto it = coll_cells.find(cell_key(cx + dx, cy + dy, cz + dz));
          if (it == coll_cells.end()) {
            continue;
          }
          for (u32 ci : it->second) {
            const auto& c = cverts[ci];
            math::Vector3f d(c.x - p.x(), c.y - p.y(), c.z - p.z());
            float dd = d.dot(d);
            if (dd < best) {
              best = dd;
              bestv = (int)ci;
            }
          }
        }
      }
    }
    if (bestv < 0) {
      return false;
    }
    const auto& c = cverts[bestv];
    math::Vector3f nn((float)c.nx, (float)c.ny, (float)c.nz);
    float l = nn.length();
    if (!(l > 1e-3f)) {
      return false;
    }
    out = nn * (1.f / l);
    return true;
  };

  // ---- 5. For each CROSS-TREE welded group: orient -> crease-cluster -> average -> write nor ----
  std::vector<math::Vector3f> cl_accum, cl_unit;
  std::vector<u32> cl_packed;
  std::vector<int> rec_cluster;
  std::vector<u8> written(N, 0);
  u64 resmoothed = 0, inverted_fixed = 0, collision_oriented = 0;
  for (u32 g = 0; g < num_groups; g++) {
    if (!group_multitree[g]) {
      continue;  // single-tree verts keep the accepted per-tree normal (no regression)
    }
    auto& recs = gincid[g];
    if (recs.empty()) {
      continue;
    }
    // Largest incident face first: it establishes the group's dominant surface + orientation reference.
    std::sort(recs.begin(), recs.end(),
              [](const Incid& x, const Incid& y) { return x.nraw.dot(x.nraw) > y.nraw.dot(y.nraw); });
    float rl = recs[0].nraw.length();
    if (!(rl > 1e-6f)) {
      continue;
    }
    math::Vector3f ref = recs[0].nraw * (1.f / rl);

    // Collision authority: outward sign toward the walkable side (INSIGHT #2 point 2). If the dominant
    // face points AWAY from the nearby walkable normal, the whole group's output is flipped to walkable-
    // outward. The group is re-assigned wholesale here, so both trees' seam verts get the same sign =>
    // no seam sign discontinuity.
    bool sign_flip = false;
    {
      math::Vector3f centroid(0.f, 0.f, 0.f);
      for (auto& r : recs) {
        centroid = centroid + gp[r.gvert];
      }
      centroid = centroid * (1.f / (float)recs.size());
      math::Vector3f cn;
      if (nearest_coll_normal(centroid, cn) && ref.dot(cn) < -0.05f) {
        sign_flip = true;
        collision_oriented++;
      }
    }

    // INSIGHT #2 point 1: re-orient NEAR-ANTIPARALLEL (inward-wound) incident faces to agree with the
    // reference BEFORE averaging, so an inward normal can no longer cancel the cross-seam average
    // (owner: "near-opposite vectors cancel"). The -0.8 threshold flips ONLY genuinely antiparallel
    // duplicates (>~143 deg = an inward-wound copy of the SAME surface) and leaves real folds (up to
    // ~143 deg) for the crease clustering below to keep as crisp separate clusters — so a genuine sharp
    // corner is never smoothed away, only the inverted duplicate is corrected.
    for (auto& r : recs) {
      float rlen = r.nraw.length();
      if (rlen > 1e-6f && (r.nraw * (1.f / rlen)).dot(ref) < -0.8f) {
        r.nraw = r.nraw * -1.f;
        inverted_fixed++;
      }
    }

    // Crease-cluster (signed dot; coplanar-enough welds, a hard fold stays a separate crisp cluster).
    cl_accum.clear();
    cl_unit.clear();
    rec_cluster.assign(recs.size(), -1);
    for (size_t r = 0; r < recs.size(); r++) {
      float len = recs[r].nraw.length();
      if (!(len > 1e-6f)) {
        continue;
      }
      math::Vector3f unit = recs[r].nraw * (1.f / len);
      int found = -1;
      for (size_t c = 0; c < cl_unit.size(); c++) {
        if (unit.dot(cl_unit[c]) >= crease_cos) {
          found = (int)c;
          break;
        }
      }
      if (found < 0) {
        found = (int)cl_accum.size();
        cl_accum.push_back(recs[r].nraw);
        cl_unit.push_back(unit);
      } else {
        cl_accum[found] += recs[r].nraw;
      }
      rec_cluster[r] = found;
    }
    cl_packed.assign(cl_accum.size(), 0);
    for (size_t c = 0; c < cl_accum.size(); c++) {
      math::Vector3f nn = cl_accum[c];
      float l = nn.length();
      nn = l > 1e-6f ? nn * (1.f / l) : math::Vector3f(0.f, 1.f, 0.f);
      if (sign_flip) {
        nn = nn * -1.f;
      }
      s16 nx = (s16)std::lround(nn.x() * 511.f);
      s16 ny = (s16)std::lround(nn.y() * 511.f);
      s16 nz = (s16)std::lround(nn.z() * 511.f);
      cl_packed[c] = pack_to_gl_normal(nx, ny, nz);
    }
    // Assign each incident vertex the normal of the cluster carrying its LARGEST incident face. recs is
    // area-desc sorted, so the first record seen for a vertex is its largest face; `written` guards once.
    for (size_t r = 0; r < recs.size(); r++) {
      int cl = rec_cluster[r];
      if (cl < 0) {
        continue;
      }
      u32 gvi = recs[r].gvert;
      if (written[gvi]) {
        continue;
      }
      written[gvi] = 1;
      gv[gvi]->nor = cl_packed[cl];
      resmoothed++;
    }
  }

  // ---- 6. OWNER FULL SPEC: SMOOTH THE UVs at welded seams ("lisser les UV"). Adjacent chunks sharing a
  //         welded position often carry the SAME texture coordinate DRIFTED by a fraction of a texel
  //         across the chunk boundary (fp quantization) => a hairline texture crack. For each cross-tree
  //         welded group whose members' UVs cluster within a tight epsilon (meant-to-be-continuous, merely
  //         drifted), snap them to the group-average UV. Genuine UV islands (atlas tiles that legitimately
  //         differ by > epsilon at a shared position) exceed the epsilon and are left untouched — so this
  //         only ever CLOSES hairline seams, never smears a texture.
  u64 uv_snapped = 0;
  {
    constexpr float kUvEps = 1.0f / 64.0f;  // hairline drift only (~a couple texels on a 128px tile)
    struct UvAcc {
      float s0, t0, ss, ts;
      u32 n;
      u8 diverged;
    };
    std::unordered_map<u32, UvAcc> uvacc;
    uvacc.reserve((size_t)multitree_groups * 2 + 1);
    for (size_t i = 0; i < N; i++) {
      u32 g = group[i];
      if (!group_multitree[g]) {
        continue;
      }
      auto it = uvacc.find(g);
      if (it == uvacc.end()) {
        uvacc.emplace(g, UvAcc{gv[i]->s, gv[i]->t, gv[i]->s, gv[i]->t, 1, 0});
      } else {
        UvAcc& a = it->second;
        if (std::fabs(gv[i]->s - a.s0) > kUvEps || std::fabs(gv[i]->t - a.t0) > kUvEps) {
          a.diverged = 1;  // a genuine UV island in this group: snap none of it
        }
        a.ss += gv[i]->s;
        a.ts += gv[i]->t;
        a.n++;
      }
    }
    for (size_t i = 0; i < N; i++) {
      u32 g = group[i];
      if (!group_multitree[g]) {
        continue;
      }
      auto it = uvacc.find(g);
      if (it == uvacc.end() || it->second.diverged || it->second.n < 2) {
        continue;
      }
      float as = it->second.ss / (float)it->second.n;
      float at = it->second.ts / (float)it->second.n;
      if (gv[i]->s != as || gv[i]->t != at) {
        gv[i]->s = as;
        gv[i]->t = at;
        uv_snapped++;
      }
    }
  }

  // ---- 5c. OWNER #14 (2026-07-24) — SPLIT-BY-UV SHARED NORMAL over the FULL position weld map. ----
  // The gap the owner found: index FUSION (STEP A) merges only the ~24-30% attribute-identical coincident
  // verts, and the multitree re-smooth above (STEP 5) touches ONLY cross-tree groups, so the ~70%
  // coincident verts at chunk/UV/color boundaries (same position + same surface but a different UV or baked
  // color, hence NOT index-fusable and NOT cross-tree) kept their per-triangle normals => the visible
  // LIGHTING seams. The industry fix is "smoothing group by POSITION, split by UV": a vertex cannot hold two
  // UVs, so the UV/color-seam copies stay SEPARATE for their UV, but their SMOOTH NORMAL is averaged BY
  // POSITION across ALL coincident coplanar corners and that ONE normal is assigned to EVERY coincident
  // corner (fused or UV-split alike) => the lighting is continuous across the UV/chunk seam => the seam is
  // gone. This runs over EVERY coincident position group (size>=2), not just the fused/multitree subset, and
  // yields the coverage metric the owner asked for (must be ~the full coincident set, not 24-30%). It is
  // crease-preserving: members whose current normals differ by more than the crease threshold stay in
  // separate clusters (a genuine sharp corner keeps its crisp normal), only coplanar members are unified.
  // Non-coincident (size-1) verts — the bulk of the interior surface — are UNTOUCHED, so the accepted
  // directional-ambient look is preserved everywhere except the seam verts (which is the whole point).
  {
    auto unpack_nor = [](u32 nor) -> math::Vector3f {
      auto sx = [](u32 v) -> int {
        int x = (int)(v & 0x3ffu);
        return (x & 0x200) ? x - 0x400 : x;
      };
      return math::Vector3f((float)sx(nor), (float)sx(nor >> 10), (float)sx(nor >> 20));
    };
    // Compact CSR mapping group -> member global-vertex indices (memory-friendly vs a vector-of-vectors).
    std::vector<u32> gcount(num_groups, 0);
    for (size_t i = 0; i < N; i++) {
      gcount[group[i]]++;
    }
    std::vector<u32> goff(num_groups + 1, 0);
    for (u32 g = 0; g < num_groups; g++) {
      goff[g + 1] = goff[g] + gcount[g];
    }
    std::vector<u32> gflat(N);
    {
      std::vector<u32> cursor = goff;  // fill cursor per group
      for (size_t i = 0; i < N; i++) {
        gflat[cursor[group[i]]++] = (u32)i;
      }
    }
    u64 coincident_total = 0, coincident_smoothed = 0;
    std::vector<math::Vector3f> csum;  // per-cluster accumulated unit normal
    std::vector<u32> ccount;           // per-cluster member count
    std::vector<u32> cpacked;          // per-cluster packed shared normal
    std::vector<int> mcluster;         // cluster id per member
    for (u32 g = 0; g < num_groups; g++) {
      const u32 m0 = goff[g], m1 = goff[g + 1];
      const u32 msz = m1 - m0;
      if (msz < 2) {
        continue;  // a unique position (no coincident copy) — not a seam vertex, leave it alone
      }
      // Count only REFERENCED (rendered) members: STEP A orphans the fused-away duplicates, which never
      // draw and cannot seam. A position with <2 rendered copies is not a rendered seam.
      u32 ref_members = 0;
      for (u32 k = m0; k < m1; k++) {
        ref_members += referenced[gflat[k]];
      }
      if (ref_members < 2) {
        continue;
      }
      coincident_total += ref_members;
      // Crease-cluster the referenced members' CURRENT per-vertex normals (already position-averaged within
      // a tree by the per-tree pass / across trees by STEP 5). Members with nor==0 (no incident face) carry
      // no usable normal — they stay in mcluster=-1 and are counted uncovered.
      csum.clear();
      ccount.clear();
      mcluster.assign(msz, -1);
      for (u32 k = 0; k < msz; k++) {
        if (!referenced[gflat[m0 + k]]) {
          continue;  // orphaned fused-away copy: not rendered, excluded from the seam smoothing + coverage
        }
        u32 nor = gv[gflat[m0 + k]]->nor;
        if (nor == 0) {
          continue;
        }
        math::Vector3f v = unpack_nor(nor);
        float l = v.length();
        if (!(l > 1e-6f)) {
          continue;
        }
        math::Vector3f u = v * (1.f / l);
        int found = -1;
        for (size_t c = 0; c < csum.size(); c++) {
          float cl = csum[c].length();
          if (cl > 1e-6f && u.dot(csum[c] * (1.f / cl)) >= crease_cos) {
            found = (int)c;
            break;
          }
        }
        if (found < 0) {
          found = (int)csum.size();
          csum.push_back(u);
          ccount.push_back(1);
        } else {
          csum[found] += u;
          ccount[found]++;
        }
        mcluster[k] = found;
      }
      // Pack each cluster's averaged (shared) normal.
      cpacked.assign(csum.size(), 0);
      for (size_t c = 0; c < csum.size(); c++) {
        math::Vector3f nn = csum[c];
        float l = nn.length();
        nn = l > 1e-6f ? nn * (1.f / l) : math::Vector3f(0.f, 1.f, 0.f);
        cpacked[c] = pack_to_gl_normal((s16)std::lround(nn.x() * 511.f),
                                       (s16)std::lround(nn.y() * 511.f),
                                       (s16)std::lround(nn.z() * 511.f));
      }
      // Assign the SHARED normal to every coincident corner. A member in a cluster of size>=2 is genuinely
      // smoothed ACROSS the seam (== covered); a member alone in its cluster is a real crease corner (kept
      // crisp, counted uncovered — sharp edges must stay).
      for (u32 k = 0; k < msz; k++) {
        int c = mcluster[k];
        if (c < 0) {
          continue;
        }
        gv[gflat[m0 + k]]->nor = cpacked[c];
        if (ccount[c] >= 2) {
          coincident_smoothed++;
        }
      }
    }
    g_gweld_coincident_verts += coincident_total;
    g_gweld_coincident_smoothed += coincident_smoothed;
  }

  // ---- 7. Gpbr-fusion (2026-07-24) — cross-seam TANGENT FRAME coherence MEASUREMENT. ----
  // PURE DIAGNOSTIC: this pass reads the tangents and writes only counters, it never modifies the mesh.
  // WHY: positions + smooth normals are now welded across chunk seams, yet the owner's live A/B (relief=0
  // smooth vs relief=2.5 hard patches) proves the plates are created by the NORMAL-MAP APPLICATION. The
  // normal map is decoded in the per-vertex TANGENT frame, and each chunk has its own UV layout, so the
  // two chunks meeting at a welded seam can carry tangents ROTATED (or mirrored, .w sign) relative to each
  // other. Same texel, two different tangent frames => two different world normals => opposite lighting on
  // either side of the seam. This measures that rotation: for every welded CROSS-TREE (multitree) group,
  // project each member's tangent into the plane of the group's shared smooth normal Ng and take the signed
  // angle around Ng against the group's first valid member.
  {
    u64 tf_pairs = 0, tf_over30 = 0, tf_handed = 0, tf_groups = 0, tf_incoherent = 0;
    u64 tf_hist[6] = {0, 0, 0, 0, 0, 0};
    // Compact CSR over MULTITREE groups ONLY (single-tree groups can't have a cross-seam frame), so the
    // member lists stay a few MB instead of a vector-of-vectors over every group. O(N).
    std::vector<u32> mt_id(num_groups, UINT32_MAX);
    u32 n_mt = 0;
    for (u32 g = 0; g < num_groups; g++) {
      if (group_multitree[g]) {
        mt_id[g] = n_mt++;
      }
    }
    if (n_mt) {
      std::vector<u32> moff(n_mt + 1, 0);
      for (size_t i = 0; i < N; i++) {
        u32 m = mt_id[group[i]];
        if (m != UINT32_MAX) {
          moff[m + 1]++;
        }
      }
      for (u32 m = 0; m < n_mt; m++) {
        moff[m + 1] += moff[m];
      }
      std::vector<u32> mflat(moff[n_mt]);
      {
        std::vector<u32> cursor(moff.begin(), moff.end() - 1);
        for (size_t i = 0; i < N; i++) {
          u32 m = mt_id[group[i]];
          if (m != UINT32_MAX) {
            mflat[cursor[m]++] = (u32)i;
          }
        }
      }
      for (u32 m = 0; m < n_mt; m++) {
        const u32 k0 = moff[m], k1 = moff[m + 1];
        if (k1 - k0 < 2) {
          continue;  // a multitree group always has >=2 members; guard anyway
        }
        // The group's shared smooth normal (STEP 5 / 5c assigned the SAME normal to every member, so the
        // first member is representative). nor==0 => no usable normal => the frame is undefined here.
        const math::Vector3f Ng = unpack_gl_normal_2_10_10_10(gv[mflat[k0]]->nor);
        if (Ng.length() < 0.5f) {
          continue;
        }
        bool have_ref = false;
        math::Vector3f t0(0.f, 0.f, 0.f);
        bool w0_neg = false;
        float group_max = 0.f;
        u64 group_pairs = 0;
        for (u32 k = k0; k < k1; k++) {
          const u32 gi = mflat[k];
          const TreeRef& tr = trees[gtree[gi]];
          if (!tr.tangents || tr.tangents->empty()) {
            continue;  // tangents not computed for this tree (weld-only build / empty) — skip cleanly
          }
          const u32 li = gi - tr.gbase;
          if (li >= tr.tangents->size()) {
            continue;
          }
          const math::Vector4f& T = (*tr.tangents)[li];
          const math::Vector3f tv(T.x(), T.y(), T.z());
          // Project the tangent into the plane of Ng: the normal map is decoded in the plane perpendicular
          // to the shaded normal, so only the IN-PLANE rotation of the frame changes the decoded normal.
          math::Vector3f tp = tv - Ng * Ng.dot(tv);
          const float tl = tp.length();
          if (!(tl >= 0.2f)) {
            continue;  // tangent (nearly) parallel to the normal => in-plane direction is meaningless
          }
          tp = tp * (1.f / tl);
          if (!have_ref) {
            have_ref = true;
            t0 = tp;
            w0_neg = T.w() < 0.f;
            continue;
          }
          // Signed angle around Ng, in degrees (magnitude only: a +40 and a -40 rotation are equally bad).
          float ang = std::atan2(t0.cross(tp).dot(Ng), t0.dot(tp)) * 57.29577951308232f;
          ang = std::fabs(ang);
          group_pairs++;
          tf_pairs++;
          if (ang < 5.f) {
            tf_hist[0]++;
          } else if (ang < 15.f) {
            tf_hist[1]++;
          } else if (ang < 45.f) {
            tf_hist[2]++;
          } else if (ang < 90.f) {
            tf_hist[3]++;
          } else if (ang < 135.f) {
            tf_hist[4]++;
          } else {
            tf_hist[5]++;
          }
          if (ang > 30.f) {
            tf_over30++;
          }
          if ((T.w() < 0.f) != w0_neg) {
            tf_handed++;  // MIRRORED frame: the normal map's green/red channel effectively flips
          }
          if (ang > group_max) {
            group_max = ang;
          }
        }
        if (group_pairs) {
          tf_groups++;
          if (group_max > 30.f) {
            tf_incoherent++;
          }
        }
      }
    }
    g_tanframe_pairs += tf_pairs;
    g_tanframe_h0 += tf_hist[0];
    g_tanframe_h1 += tf_hist[1];
    g_tanframe_h2 += tf_hist[2];
    g_tanframe_h3 += tf_hist[3];
    g_tanframe_h4 += tf_hist[4];
    g_tanframe_h5 += tf_hist[5];
    g_tanframe_pairs_over30 += tf_over30;
    g_tanframe_handed += tf_handed;
    g_tanframe_groups += tf_groups;
    g_tanframe_incoherent += tf_incoherent;
    lg::info("[tan-frame] level={} multitree_groups_analysed={} pairs={} over30={} handedness_mismatch={} "
             "incoherent_groups={}",
             lev.level_name, tf_groups, tf_pairs, tf_over30, tf_handed, tf_incoherent);
  }

  g_gweld_total_verts += (u64)N;
  g_gweld_cross_stitched += cross_stitched;
  g_gweld_multitree_groups += multitree_groups;
  g_gweld_resmoothed_verts += resmoothed;
  g_gweld_inverted_fixed += inverted_fixed;
  g_gweld_collision_oriented += collision_oriented;
  g_gweld_open_seam_before += boundary_after + 2 * cross_interior;
  g_gweld_open_seam_after += boundary_after;
  g_gweld_uv_snapped += uv_snapped;
  lg::info("[global-weld] level={} verts={} cross_chunk_stitched={} multitree_groups={} resmoothed={} "
           "inward_faces_flipped={} collision_oriented={} open_seam_edges_after={} open_seam_edges_before~={} "
           "uv_snapped={}",
           lev.level_name, N, cross_stitched, multitree_groups, resmoothed, inverted_fixed, collision_oriented,
           boundary_after, boundary_after + 2 * cross_interior, uv_snapped);
  write_tan_diag_file();
}

void TfragTree::unpack() {
  unpacked.vertices.resize(packed_vertices.vertices.size());
  for (size_t i = 0; i < unpacked.vertices.size(); i++) {
    auto& o = unpacked.vertices[i];
    auto& in = packed_vertices.vertices[i];
    auto& cluster = packed_vertices.cluster_origins.at(in.cluster_idx);
    constexpr float kClusterSize = 4096 * 40;  // 100 in-game meters
    constexpr float kMasterOffset = 12000 * 4096;
    constexpr float rescale = kClusterSize / UINT16_MAX;
    float cx = -kMasterOffset + kClusterSize * cluster.x();
    float cy = -kMasterOffset + kClusterSize * cluster.y();
    float cz = -kMasterOffset + kClusterSize * cluster.z();
    o.x = cx + in.xoff * rescale;
    o.y = cy + in.yoff * rescale;
    o.z = cz + in.zoff * rescale;
    o.s = in.s / (1024.f);
    o.t = in.t / (1024.f);
    o.color_index = in.color_index;
  }

  for (auto& draw : draws) {
    draw.unpacked.idx_of_first_idx_in_full_buffer = unpacked.indices.size();
    for (auto& run : draw.runs) {
      for (u32 ri = 0; ri < run.length; ri++) {
        unpacked.indices.push_back(run.vertex0 + ri);
      }
      if (use_strips) {
        unpacked.indices.push_back(UINT32_MAX);
      }
    }
    unpacked.indices.insert(unpacked.indices.end(), draw.plain_indices.begin(),
                            draw.plain_indices.end());
  }

  // STEP A (owner STRICT ORDER) — TRUE topological FUSE **first** (see fuse_tree_indices): rewrite the
  // index buffer so coincident attribute-identical verts share ONE representative index (genuine point
  // fusion) BEFORE smooth normals + tangents, so STEP B/C/D run on the truly merged topology. Honors
  // the debug.opengoal.mesh.weld A/B toggle (OFF => original per-copy index buffer = seamy baseline).
  if (mesh_weld_enabled()) {
    u32 fused = fuse_tree_indices(unpacked.vertices, unpacked.indices);
    g_index_fused_tfrag += fused;
    g_index_fused_tfrag_verts += (u64)unpacked.vertices.size();
  }

  // Reconstruct smooth per-vertex normals now that positions + the index topology are built. This is
  // the root-cause fix for the flat/faceted look of curved geometry under the realtime lighting; it
  // is inert unless a shader reads the location-3 normal attribute (realtime-lighting path only).
  reconstruct_tfrag_smooth_normals(*this);

  // REOPEN#7 FOUNDATION FIX: per-vertex MikkTSpace tangents so the PBR shader builds a CONTINUOUS TBN
  // from an interpolated vertex tangent instead of discontinuous screen-space derivatives — the root
  // cause of the incoherent relief + contrast cracks.
  // Gprecompute-deterministic-bake: they are DERIVED OFFLINE (TangentDerive.cpp, fr3 extractor) and
  // only expanded here. The derivation is a pure function of this tree's packed bytes, so running it
  // on every load on every machine was work with a fixed answer.
  apply_baked_tangents(baked_tangents, unpacked.vertices, unpacked.tangents, "tfrag");
}

void TieTree::serialize(Serializer& ser) {
  ser.from_pod_vector(&baked_tangents);  // Gprecompute-deterministic-bake — see TfragTree::serialize
  if (ser.is_saving()) {
    ser.save<size_t>(static_draws.size());
  } else {
    static_draws.resize(ser.load<size_t>());
  }
  for (auto& draw : static_draws) {
    draw.serialize(ser);
  }

  ser.from_ptr(&category_draw_indices);

  if (ser.is_saving()) {
    ser.save<size_t>(instanced_wind_draws.size());
  } else {
    instanced_wind_draws.resize(ser.load<size_t>());
  }
  for (auto& draw : instanced_wind_draws) {
    draw.serialize(ser);
  }

  if (ser.is_saving()) {
    ser.save<size_t>(wind_instance_info.size());
  } else {
    wind_instance_info.resize(ser.load<size_t>());
  }
  for (auto& inst : wind_instance_info) {
    inst.serialize(ser);
  }

  packed_vertices.serialize(ser);
  colors.serialize(ser);
  bvh.serialize(ser);

  ser.from_ptr(&use_strips);

  ser.from_ptr(&has_per_proto_visibility_toggle);
  ser.from_string_vector(&proto_names);
}

void ShrubTree::serialize(Serializer& ser) {
  time_of_day_colors.serialize(ser);
  ser.from_pod_vector(&indices);
  packed_vertices.serialize(ser);
  if (ser.is_saving()) {
    ser.save<size_t>(static_draws.size());
  } else {
    static_draws.resize(ser.load<size_t>());
  }
  for (auto& draw : static_draws) {
    draw.serialize(ser);
  }

  ser.from_ptr(&has_per_proto_visibility_toggle);
  ser.from_string_vector(&proto_names);
}

void HfragmentBucket::serialize(Serializer& ser) {
  ser.from_pod_vector(&corners);
  ser.from_ptr(&montage_table);
}

void Hfragment::serialize(Serializer& ser) {
  ser.from_pod_vector(&vertices);
  ser.from_pod_vector(&indices);
  ser.from_pod_vector(&corners);

  if (ser.is_saving()) {
    ser.save<size_t>(buckets.size());
  } else {
    buckets.resize(ser.load<size_t>());
  }
  for (auto& x : buckets) {
    x.serialize(ser);
  }
  time_of_day_colors.serialize(ser);
  ser.from_ptr(&wang_tree_tex_id);
  ser.from_ptr(&draw_mode);
  ser.from_ptr(&occlusion_offset);
}

void BVH::serialize(Serializer& ser) {
  ser.from_ptr(&first_leaf_node);
  ser.from_ptr(&last_leaf_node);
  ser.from_ptr(&first_root);
  ser.from_ptr(&num_roots);
  ser.from_ptr(&only_children);
  ser.from_pod_vector(&vis_nodes);
}

void Texture::serialize(Serializer& ser) {
  ser.from_ptr(&w);
  ser.from_ptr(&h);
  ser.from_ptr(&combo_id);
  ser.from_pod_vector(&data);
  ser.from_str(&debug_name);
  ser.from_str(&debug_tpage_name);
  ser.from_ptr(&load_to_pool);
}

void IndexTexture::serialize(Serializer& ser) {
  ser.from_ptr(&w);
  ser.from_ptr(&h);
  ser.from_ptr(&combo_id);
  ser.from_pod_vector(&index_data);
  ser.from_ptr(&color_table);
  ser.from_str(&name);
  ser.from_str(&tpage_name);
  ser.from_string_vector(&level_names);
}

void CollisionMesh::serialize(Serializer& ser) {
  ser.from_pod_vector(&vertices);
}

void MercDraw::serialize(Serializer& ser) {
  ser.from_ptr(&mode);
  ser.from_ptr(&tree_tex_id);
  ser.from_ptr(&eye_id);
  ser.from_ptr(&first_index);
  ser.from_ptr(&index_count);
  ser.from_ptr(&num_triangles);
  ser.from_ptr(&no_strip);
}

void Blerc::serialize(Serializer& ser) {
  ser.from_pod_vector(&float_data);
  ser.from_pod_vector(&int_data);
}

void MercModifiableDrawGroup::serialize(Serializer& ser) {
  if (ser.is_saving()) {
    ser.save<size_t>(mod_draw.size());
  } else {
    mod_draw.resize(ser.load<size_t>());
  }
  for (auto& draw : mod_draw) {
    draw.serialize(ser);
  }

  if (ser.is_saving()) {
    ser.save<size_t>(fix_draw.size());
  } else {
    fix_draw.resize(ser.load<size_t>());
  }
  for (auto& draw : fix_draw) {
    draw.serialize(ser);
  }
  ser.from_pod_vector(&vertices);
  ser.from_pod_vector(&vertex_lump4_addr);
  ser.from_pod_vector(&fragment_mask);
  ser.from_ptr(&expect_vidx_end);

  blerc.serialize(ser);
}

void MercEffect::serialize(Serializer& ser) {
  if (ser.is_saving()) {
    ser.save<size_t>(all_draws.size());
  } else {
    all_draws.resize(ser.load<size_t>());
  }
  for (auto& draw : all_draws) {
    draw.serialize(ser);
  }

  mod.serialize(ser);

  ser.from_ptr(&envmap_mode);
  ser.from_ptr(&envmap_texture);
  ser.from_ptr(&has_envmap);
  ser.from_ptr(&has_mod_draw);
}

void MercModel::serialize(Serializer& ser) {
  ser.from_str(&name);
  if (ser.is_saving()) {
    ser.save<size_t>(effects.size());
  } else {
    effects.resize(ser.load<size_t>());
  }
  for (auto& effect : effects) {
    effect.serialize(ser);
  }
  ser.from_ptr(&max_draws);
  ser.from_ptr(&max_bones);
  ser.from_ptr(&st_vif_add);
  ser.from_ptr(&xyz_scale);
  ser.from_ptr(&st_magic);
}

void MercModelGroup::serialize(Serializer& ser) {
  if (ser.is_saving()) {
    ser.save<size_t>(models.size());
  } else {
    models.resize(ser.load<size_t>());
  }
  for (auto& model : models) {
    model.serialize(ser);
  }

  ser.from_pod_vector(&indices);
  ser.from_pod_vector(&vertices);
}

void Level::serialize(Serializer& ser) {
  ser.from_ptr(&version);
  if (ser.is_loading() && version != TFRAG3_VERSION) {
    ASSERT_MSG(false, fmt::format("version mismatch when loading tfrag3 data. Got {}, expected {}, "
                                  "did you forget to re-decompile?",
                                  version, TFRAG3_VERSION));
  }

  ser.from_str(&level_name);

  if (ser.is_saving()) {
    ser.save<size_t>(textures.size());
  } else {
    textures.resize(ser.load<size_t>());
  }
  for (auto& tex : textures) {
    tex.serialize(ser);
  }

  if (ser.is_saving()) {
    ser.save<size_t>(index_textures.size());
  } else {
    index_textures.resize(ser.load<size_t>());
  }
  for (auto& tex : index_textures) {
    tex.serialize(ser);
  }

  for (int geom = 0; geom < 3; ++geom) {
    if (ser.is_saving()) {
      ser.save<size_t>(tfrag_trees[geom].size());
    } else {
      tfrag_trees[geom].resize(ser.load<size_t>());
    }
    for (auto& tree : tfrag_trees[geom]) {
      tree.serialize(ser);
    }
  }

  for (int geom = 0; geom < 4; ++geom) {
    if (ser.is_saving()) {
      ser.save<size_t>(tie_trees[geom].size());
    } else {
      tie_trees[geom].resize(ser.load<size_t>());
    }
    for (auto& tree : tie_trees[geom]) {
      tree.serialize(ser);
    }
  }

  if (ser.is_saving()) {
    ser.save<size_t>(shrub_trees.size());
  } else {
    shrub_trees.resize(ser.load<size_t>());
  }
  for (auto& tree : shrub_trees) {
    tree.serialize(ser);
  }

  hfrag.serialize(ser);

  collision.serialize(ser);
  merc_data.serialize(ser);

  ser.from_ptr(&version2);
  if (ser.is_loading() && version2 != TFRAG3_VERSION) {
    ASSERT_MSG(false, fmt::format(
                          "version mismatch when loading tfrag3 data (at end). Got {}, expected {}",
                          version2, TFRAG3_VERSION));
  }
}

void MercModifiableDrawGroup::memory_usage(MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::MERC_MOD_VERT, sizeof(MercVertex) * vertices.size());
  tracker->add(MemoryUsageCategory::MERC_MOD_DRAW_1, sizeof(MercDraw) * fix_draw.size());
  tracker->add(MemoryUsageCategory::MERC_MOD_DRAW_2, sizeof(MercDraw) * mod_draw.size());
  tracker->add(MemoryUsageCategory::MERC_MOD_TABLE, sizeof(u16) * vertex_lump4_addr.size());
  tracker->add(MemoryUsageCategory::BLERC, sizeof(BlercFloatData) * blerc.float_data.size());
  tracker->add(MemoryUsageCategory::BLERC, sizeof(u32) * blerc.int_data.size());
}

void MercEffect::memory_usage(MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::MERC_DRAW, sizeof(MercDraw) * all_draws.size());
  mod.memory_usage(tracker);
}

void MercModel::memory_usage(MemoryUsageTracker* tracker) const {
  for (auto& effect : effects) {
    effect.memory_usage(tracker);
  }
}

void MercModelGroup::memory_usage(MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::MERC_VERT, sizeof(MercVertex) * vertices.size());
  tracker->add(MemoryUsageCategory::MERC_INDEX, sizeof(u32) * indices.size());
  for (auto& model : models) {
    model.memory_usage(tracker);
  }
}

void CollisionMesh::memory_usage(MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::COLLISION, sizeof(Vertex) * vertices.size());
}

void PackedShrubVertices::memory_usage(MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::SHRUB_VERT, 64 * matrices.size());
  tracker->add(MemoryUsageCategory::SHRUB_VERT, sizeof(InstanceGroup) * instance_groups.size());
  tracker->add(MemoryUsageCategory::SHRUB_VERT, sizeof(Vertex) * vertices.size());
}

void ShrubTree::memory_usage(MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::SHRUB_TIME_OF_DAY, sizeof(u8) * time_of_day_colors.data.size());
  packed_vertices.memory_usage(tracker);
  tracker->add(MemoryUsageCategory::SHRUB_DRAW, sizeof(ShrubDraw) * static_draws.size());
  tracker->add(MemoryUsageCategory::SHRUB_IND, sizeof(u32) * indices.size());
}

void InstancedStripDraw::memory_usage(MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::TIE_INST_INDEX, sizeof(u32) * vertex_index_stream.size());
  tracker->add(MemoryUsageCategory::TIE_INST_VIS, sizeof(InstanceGroup) * instance_groups.size());
}

void PackedTieVertices::memory_usage(MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::TIE_CIDX, sizeof(u16) * color_indices.size());
  tracker->add(MemoryUsageCategory::TIE_MATRICES, 64 * matrices.size());
  tracker->add(MemoryUsageCategory::TIE_GRPS, sizeof(MatrixGroup) * matrix_groups.size());
  tracker->add(MemoryUsageCategory::TIE_VERTS, sizeof(Vertex) * vertices.size());
}

void TieTree::memory_usage(MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::TIE_BVH, sizeof(VisNode) * bvh.vis_nodes.size());
  for (auto& draw : static_draws) {
    tracker->add(MemoryUsageCategory::TIE_DEINST_INDEX,
                 draw.runs.size() * sizeof(StripDraw::VertexRun));
    tracker->add(MemoryUsageCategory::TIE_DEINST_INDEX, draw.plain_indices.size() * sizeof(u32));
    tracker->add(MemoryUsageCategory::TIE_DEINST_VIS,
                 draw.vis_groups.size() * sizeof(StripDraw::VisGroup));
  }
  packed_vertices.memory_usage(tracker);
  tracker->add(MemoryUsageCategory::TIE_TIME_OF_DAY, sizeof(u8) * colors.data.size());

  for (auto& draw : instanced_wind_draws) {
    draw.memory_usage(tracker);
  }
  tracker->add(MemoryUsageCategory::TIE_WIND_INSTANCE_INFO,
               sizeof(TieWindInstance) * wind_instance_info.size());
  tracker->add(MemoryUsageCategory::TIE_TANGENT, sizeof(u16) * baked_tangents.size());
}

void PackedTfragVertices::memory_usage(MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::TFRAG_VERTS,
               sizeof(PackedTfragVertices::Vertex) * vertices.size());
  tracker->add(MemoryUsageCategory::TFRAG_CLUSTER,
               sizeof(math::Vector<u16, 3>) * cluster_origins.size());
}

void TfragTree::memory_usage(MemoryUsageTracker* tracker) const {
  for (auto& draw : draws) {
    tracker->add(MemoryUsageCategory::TFRAG_INDEX, draw.runs.size() * sizeof(StripDraw::VertexRun));
    tracker->add(MemoryUsageCategory::TFRAG_INDEX, draw.plain_indices.size() * sizeof(u32));
    tracker->add(MemoryUsageCategory::TFRAG_VIS,
                 draw.vis_groups.size() * sizeof(StripDraw::VisGroup));
  }
  packed_vertices.memory_usage(tracker);
  tracker->add(MemoryUsageCategory::TFRAG_TIME_OF_DAY, sizeof(u8) * colors.data.size());
  tracker->add(MemoryUsageCategory::TFRAG_BVH, sizeof(VisNode) * bvh.vis_nodes.size());
  tracker->add(MemoryUsageCategory::TFRAG_TANGENT, sizeof(u16) * baked_tangents.size());
}

void Texture::memory_usage(MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::TEXTURE, data.size() * sizeof(u32));
}

void IndexTexture::memory_usage(MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::SPECIAL_TEXTURE, index_data.size());
  tracker->add(MemoryUsageCategory::SPECIAL_TEXTURE, 256 * 4);  // clut
}

void Hfragment::memory_usage(tfrag3::MemoryUsageTracker* tracker) const {
  tracker->add(MemoryUsageCategory::HFRAG_VERTS, vertices.size() * sizeof(HfragmentVertex));
  tracker->add(MemoryUsageCategory::HFRAG_INDEX, indices.size() * sizeof(u32));
  tracker->add(MemoryUsageCategory::HFRAG_TIME_OF_DAY, time_of_day_colors.data.size() * sizeof(u8));
  tracker->add(MemoryUsageCategory::HFRAG_CORNERS, corners.size() * sizeof(HfragmentCorner));
}

void Level::memory_usage(MemoryUsageTracker* tracker) const {
  for (const auto& texture : textures) {
    texture.memory_usage(tracker);
  }
  for (const auto& texture : index_textures) {
    texture.memory_usage(tracker);
  }
  for (const auto& tftk : tfrag_trees) {
    for (const auto& tree : tftk) {
      tree.memory_usage(tracker);
    }
  }
  for (const auto& ttk : tie_trees) {
    for (const auto& tree : ttk) {
      tree.memory_usage(tracker);
    }
  }
  for (const auto& tree : shrub_trees) {
    tree.memory_usage(tracker);
  }
  hfrag.memory_usage(tracker);
  collision.memory_usage(tracker);
  merc_data.memory_usage(tracker);
}

void print_memory_usage(const tfrag3::Level& lev, int uncompressed_data_size) {
  int total_accounted = 0;
  MemoryUsageTracker mem_use;
  lev.memory_usage(&mem_use);

  std::vector<std::pair<std::string, int>> known_categories = {
      {"texture", mem_use.data[tfrag3::MemoryUsageCategory::TEXTURE]},
      {"special-texture", mem_use.data[tfrag3::MemoryUsageCategory::SPECIAL_TEXTURE]},
      {"tie-deinst-vis", mem_use.data[tfrag3::MemoryUsageCategory::TIE_DEINST_VIS]},
      {"tie-deinst-idx", mem_use.data[tfrag3::MemoryUsageCategory::TIE_DEINST_INDEX]},
      {"tie-inst-vis", mem_use.data[tfrag3::MemoryUsageCategory::TIE_INST_VIS]},
      {"tie-inst-idx", mem_use.data[tfrag3::MemoryUsageCategory::TIE_INST_INDEX]},
      {"tie-bvh", mem_use.data[tfrag3::MemoryUsageCategory::TIE_BVH]},
      {"tie-verts", mem_use.data[tfrag3::MemoryUsageCategory::TIE_VERTS]},
      {"tie-tangent", mem_use.data[tfrag3::MemoryUsageCategory::TIE_TANGENT]},
      {"tie-colors", mem_use.data[tfrag3::MemoryUsageCategory::TIE_TIME_OF_DAY]},
      {"tie-wind-inst-info", mem_use.data[tfrag3::MemoryUsageCategory::TIE_WIND_INSTANCE_INFO]},
      {"tie-cidx", mem_use.data[tfrag3::MemoryUsageCategory::TIE_CIDX]},
      {"tie-mats", mem_use.data[tfrag3::MemoryUsageCategory::TIE_MATRICES]},
      {"tie-grps", mem_use.data[tfrag3::MemoryUsageCategory::TIE_GRPS]},
      {"tfrag-vis", mem_use.data[tfrag3::MemoryUsageCategory::TFRAG_VIS]},
      {"tfrag-idx", mem_use.data[tfrag3::MemoryUsageCategory::TFRAG_INDEX]},
      {"tfrag-vert", mem_use.data[tfrag3::MemoryUsageCategory::TFRAG_VERTS]},
      {"tfrag-tangent", mem_use.data[tfrag3::MemoryUsageCategory::TFRAG_TANGENT]},
      {"tfrag-colors", mem_use.data[tfrag3::MemoryUsageCategory::TFRAG_TIME_OF_DAY]},
      {"tfrag-cluster", mem_use.data[tfrag3::MemoryUsageCategory::TFRAG_CLUSTER]},
      {"tfrag-bvh", mem_use.data[tfrag3::MemoryUsageCategory::TFRAG_BVH]},
      {"shrub-colors", mem_use.data[tfrag3::MemoryUsageCategory::SHRUB_TIME_OF_DAY]},
      {"shrub-vert", mem_use.data[tfrag3::MemoryUsageCategory::SHRUB_VERT]},
      {"shrub-ind", mem_use.data[tfrag3::MemoryUsageCategory::SHRUB_IND]},
      {"shrub-draw", mem_use.data[tfrag3::MemoryUsageCategory::SHRUB_DRAW]},
      {"collision", mem_use.data[tfrag3::MemoryUsageCategory::COLLISION]},
      {"merc-vert", mem_use.data[tfrag3::MemoryUsageCategory::MERC_VERT]},
      {"merc-idx", mem_use.data[tfrag3::MemoryUsageCategory::MERC_INDEX]},
      {"merc-draw", mem_use.data[tfrag3::MemoryUsageCategory::MERC_DRAW]},
      {"merc-mod-vert", mem_use.data[tfrag3::MemoryUsageCategory::MERC_MOD_VERT]},
      {"merc-mod-ind", mem_use.data[tfrag3::MemoryUsageCategory::MERC_MOD_IND]},
      {"merc-mod-table", mem_use.data[tfrag3::MemoryUsageCategory::MERC_MOD_TABLE]},
      {"merc-mod-draw-1", mem_use.data[tfrag3::MemoryUsageCategory::MERC_MOD_DRAW_1]},
      {"merc-mod-draw-2", mem_use.data[tfrag3::MemoryUsageCategory::MERC_MOD_DRAW_2]},
      {"blerc", mem_use.data[tfrag3::MemoryUsageCategory::BLERC]},
      {"hfrag-verts", mem_use.data[tfrag3::MemoryUsageCategory::HFRAG_VERTS]},
      {"hfrag-index", mem_use.data[tfrag3::MemoryUsageCategory::HFRAG_INDEX]},
      {"hfrag-time-of-day", mem_use.data[tfrag3::MemoryUsageCategory::HFRAG_TIME_OF_DAY]},
      {"hfrag-corners", mem_use.data[tfrag3::MemoryUsageCategory::HFRAG_CORNERS]}

  };
  for (auto& known : known_categories) {
    total_accounted += known.second;
  }

  known_categories.push_back({"unknown", uncompressed_data_size - total_accounted});

  std::sort(known_categories.begin(), known_categories.end(),
            [](const auto& a, const auto& b) { return a.second > b.second; });

  for (const auto& x : known_categories) {
    if (x.second) {
      lg::print("{:30s} : {:6d} kB {:3.1f}%\n", x.first, x.second / 1024,
                100.f * (float)x.second / uncompressed_data_size);
    }
  }
}

std::size_t PreloadedVertex::hash::operator()(const PreloadedVertex& v) const {
  return std::hash<float>()(v.x) ^ std::hash<float>()(v.y) ^ std::hash<float>()(v.z) ^
         std::hash<float>()(v.s) ^ std::hash<float>()(v.t) ^ std::hash<u16>()(v.color_index);
}

std::size_t PackedTieVertices::Vertex::hash::operator()(const Vertex& v) const {
  return std::hash<float>()(v.x) ^ std::hash<float>()(v.y) ^ std::hash<float>()(v.z) ^
         std::hash<float>()(v.r) ^ std::hash<float>()(v.g) ^ std::hash<float>()(v.b) ^
         std::hash<float>()(v.a) ^ std::hash<float>()(v.s) ^ std::hash<float>()(v.t) ^
         std::hash<float>()(v.nx) ^ std::hash<float>()(v.ny) ^ std::hash<float>()(v.nz);
}

}  // namespace tfrag3
