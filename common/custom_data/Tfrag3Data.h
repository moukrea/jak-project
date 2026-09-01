#pragma once

// Data format for the tfrag3 renderer.
#include <array>

#include "common/common_types.h"
#include "common/dma/gs.h"
#include "common/math/Vector.h"
#include "common/util/Assert.h"
#include "common/util/Serializer.h"

namespace tfrag3 {

// NOTE:
// when updating any data structures in this file:
// - change the TFRAG3_VERSION
// - make sure to update the serialize function
// - if changing any large things (vertices, vis, bvh, colors, textures) update get_memory_usage
// - if adding a new category to the memory usage, update extract_level to print it.

constexpr int TFRAG3_VERSION = 44;  // 44: Gprecompute-deterministic-bake — baked per-vertex tangents

enum MemoryUsageCategory {
  TEXTURE,

  SPECIAL_TEXTURE,

  TIE_DEINST_VIS,
  TIE_DEINST_INDEX,
  TIE_INST_VIS,
  TIE_INST_INDEX,
  TIE_BVH,
  TIE_VERTS,
  TIE_TIME_OF_DAY,
  TIE_WIND_INSTANCE_INFO,

  TIE_CIDX,
  TIE_MATRICES,
  TIE_GRPS,

  // Gprecompute-deterministic-bake: the per-vertex tangents the fr3 now carries (4 bytes/vertex).
  // They REPLACE a full per-triangle derivation that ran on every load on every machine; the fr3
  // grows by a quarter of what the runtime used to allocate for the same data.
  TIE_TANGENT,

  TFRAG_VIS,
  TFRAG_INDEX,
  TFRAG_VERTS,
  TFRAG_TANGENT,
  TFRAG_CLUSTER,
  TFRAG_TIME_OF_DAY,
  TFRAG_BVH,

  SHRUB_TIME_OF_DAY,
  SHRUB_VERT,
  SHRUB_IND,
  SHRUB_DRAW,

  MERC_VERT,
  MERC_INDEX,
  MERC_DRAW,

  MERC_MOD_DRAW_1,
  MERC_MOD_DRAW_2,
  MERC_MOD_VERT,
  MERC_MOD_IND,
  MERC_MOD_TABLE,
  BLERC,

  HFRAG_VERTS,
  HFRAG_INDEX,
  HFRAG_TIME_OF_DAY,
  HFRAG_CORNERS,

  COLLISION,

  NUM_CATEGORIES
};

struct MemoryUsageTracker {
  u32 data[MemoryUsageCategory::NUM_CATEGORIES];

  MemoryUsageTracker() {
    for (auto& x : data) {
      x = 0;
    }
  }

  void add(MemoryUsageCategory category, u32 size_bytes) { data[category] += size_bytes; }
};

// These vertices should be uploaded to the GPU at load time and don't change
struct PreloadedVertex {
  // the vertex position
  float x = 0, y = 0, z = 0;
  // envmap tint color, not used in == or hash.
  u8 r = 0, g = 0, b = 0, a = 0;
  // texture coordinates
  float s = 0, t = 0;

  // not used in == or hash!!
  // note that this is a 10-bit 3-element field packed into 32-bits.
  u32 nor = 0;

  // color table index
  u16 color_index = 0;

  // Grecharged-mesh-consolidation: SEAM WEIGHT, occupying the 2 bytes this struct already wasted on
  // padding (sizeof stays 32 — see the static_assert below). 65535 = displace normally, 0 = do not
  // displace at all. mesh_consolidate() zeroes it on every vertex that sits on a boundary where the
  // two sides CANNOT displace identically (a material boundary where only one side has a height map,
  // a tfrag<->tie junction where the other side is never tessellated, a genuine open boundary, or a
  // hard crease where the two sides carry different normals). Barycentric interpolation then makes the
  // displacement exactly zero ALONG the shared edge on both sides, which is what closes the owner's
  // see-through tessellation slits. Interior vertices keep 65535 so the relief is untouched.
  // Runtime-only (unpacked.vertices is rebuilt from the packed data on every load) => no fr3 version
  // bump, no asset rebuild. NOT part of == / hash (like `nor`), so index fusion is unaffected.
  u16 seam_w = 0xffff;

  struct hash {
    std::size_t operator()(const PreloadedVertex& x) const;
  };

  bool operator==(const PreloadedVertex& other) const {
    return x == other.x && y == other.y && z == other.z && s == other.s && t == other.t &&
           color_index == other.color_index;
  }
};
static_assert(sizeof(PreloadedVertex) == 32, "PreloadedVertex size");

struct PackedTieVertices {
  struct Vertex {
    float x, y, z;
    float s, t;
    s8 nx, ny, nz;
    u8 r, g, b, a;

    struct hash {
      std::size_t operator()(const Vertex& x) const;
    };

    bool operator==(const Vertex& other) const {
      return x == other.x && y == other.y && z == other.z && s == other.s && t == other.t &&
             nx == other.nx && ny == other.ny && nz == other.nz && r == other.r && g == other.g &&
             b == other.b && a == other.a;
    }
  };

  struct MatrixGroup {
    s32 matrix_idx;
    u32 start_vert;
    u32 end_vert;
    bool has_normals = false;
  };

  std::vector<u16> color_indices;
  std::vector<std::array<math::Vector4f, 4>> matrices;
  std::vector<MatrixGroup> matrix_groups;  // todo pack
  std::vector<Vertex> vertices;
  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
};

struct PackedTfragVertices {
  struct Vertex {
    u16 xoff, yoff, zoff;
    u16 cluster_idx;
    s16 s, t;
    u16 color_index;
  };
  void memory_usage(MemoryUsageTracker* tracker) const;
  std::vector<Vertex> vertices;
  std::vector<math::Vector<u16, 3>> cluster_origins;
};

struct ShrubGpuVertex {
  float x, y, z;
  float s, t;
  // Grecharged-mesh-consolidation: shrub shipped with NO per-vertex normal (shrub.frag synthesized one
  // from screen-space derivatives), so shrub was the one renderable system every weld/normal pass had
  // to skip — an omission by construction. These two fields reuse the struct's existing padding
  // (sizeof stays 32) and are runtime-only, so shrub now carries the same 2-10-10-10 packed smooth
  // normal and seam weight as tfrag/tie and is covered by the audit and the weld.
  u32 nor;  // was pad0
  u16 color_index;
  u16 seam_w;  // was pad1
  u8 rgba_base[3];
  u8 pad2;
};
static_assert(sizeof(ShrubGpuVertex) == 32, "ShrubGpuVertex size");

struct PackedShrubVertices {
  struct Vertex {
    float x, y, z;
    float s, t;
    u8 rgba[3];
  };

  struct InstanceGroup {
    s32 matrix_idx;
    u32 start_vert;
    u32 end_vert;
    u16 color_index;
  };
  std::vector<std::array<math::Vector4f, 4>> matrices;
  std::vector<InstanceGroup> instance_groups;  // todo pack
  std::vector<Vertex> vertices;
  u32 total_vertex_count = 0;
  void memory_usage(MemoryUsageTracker* tracker) const;
  void serialize(Serializer& ser);
};

// Settings for drawing a group of triangle strips.
// This refers to a group of PreloadedVertices that are already uploaded.
// All triangles here are drawn in the same "mode" (blending, texture, etc)
// The vertex index list is chunked by visibility group.
// You can just memcpy the entire list to draw everything, or iterate through visgroups and
// check visibility.
struct StripDraw {
  DrawMode mode;        // the OpenGL draw settings.
  s32 tree_tex_id = 0;  // the texture that should be bound for the draw (negative for anim slot)

  struct {
    u32 idx_of_first_idx_in_full_buffer = 0;
  } unpacked;

  // indices can be specified as lists of runs and plain indices.
  // the runs are still drawn with indexed opengl calls, it just uses less space in the file.
  struct VertexRun {
    u32 vertex0;
    u16 length;
  };
  std::vector<VertexRun> runs;
  std::vector<u32> plain_indices;

  // to do culling, the above vertex stream is grouped.
  // by following the visgroups and checking the visibility, you can leave out invisible vertices.
  struct VisGroup {
    u32 num_inds = 0;           // number of vertex indices in this group
    u32 num_tris = 0;           // number of triangles
    u16 vis_idx_in_pc_bvh = 0;  // the visibility group they belong to (in BVH)
    u16 tie_proto_idx = 0;      // index of tie proto (tie only)
  };
  std::vector<VisGroup> vis_groups;

  // for debug counting.
  u32 num_triangles = 0;
  void serialize(Serializer& ser);
};

struct ShrubDraw {
  DrawMode mode;        // the OpenGL draw settings.
  u32 tree_tex_id = 0;  // the texture that should be bound for the draw

  u32 first_index_index = 0;
  u32 num_indices = 0;

  // for debug counting.
  u32 num_triangles = 0;

  u16 proto_idx = 0;
  void serialize(Serializer& ser);
};

struct InstancedStripDraw {
  DrawMode mode;        // the OpenGL draw settings.
  s32 tree_tex_id = 0;  // the texture that should be bound for the draw

  // the list of vertices in the draw. This includes the restart code of UINT32_MAX that OpenGL
  // will use to start a new strip.
  std::vector<u32> vertex_index_stream;

  // the vertex stream above is segmented by instance.
  struct InstanceGroup {
    u32 num = 0;           // number of vertex indices in this group
    u32 instance_idx = 0;  // the instance they belong to
    u32 vis_idx = 0;
  };
  std::vector<InstanceGroup> instance_groups;

  // for debug counting.
  u32 num_triangles = 0;
  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
};

// node in the BVH.
struct VisNode {
  math::Vector<float, 4> bsphere;  // the bounding sphere, in meters (4096 = 1 game meter). w = rad
  u16 child_id = 0xffff;           // the ID of our first child.
  u16 my_id = 0xffff;
  u8 num_kids = 0xff;  // number of children. The children are consecutive in memory
  u8 flags = 0;        // flags.  If 1, we have a DrawVisNode child, otherwise a leaf.
};

// The leaf nodes don't actually exist in the vector of VisNodes, but instead they are ID's used
// by the actual geometry.  Currently we do not include the bspheres of these, but this might be
// worth it if we have a more performant culling algorithm.
struct BVH {
  std::vector<VisNode> vis_nodes;  // bvh for frustum culling
  // additional information about the BVH
  u16 first_leaf_node = 0;
  u16 last_leaf_node = 0;
  u16 first_root = 0;
  u16 num_roots = 0;
  bool only_children = false;
  void serialize(Serializer& ser);
};

// This is split into groups of 4 colors.
// The data in these groups is stored first by palette, then color, then channel.
struct PackedTimeOfDay {
  std::vector<u8> data;
  u32 color_count = 0;
  void serialize(Serializer& ser);

  u8 read(int color, int palette, int channel) const {
    const int color_quad = color / 4;
    const int color_in_quad = color % 4;
    return data[color_quad * 4 * 4 * 8 + palette * 4 * 4 + color_in_quad * 4 + channel];
  }

  u8& read(int color, int palette, int channel) {
    const int color_quad = color / 4;
    const int color_in_quad = color % 4;
    return data[color_quad * 4 * 4 * 8 + palette * 4 * 4 + color_in_quad * 4 + channel];
  }
};

// A single texture. Stored as RGBA8888.
struct Texture {
  u16 w = 0, h = 0;
  u32 combo_id = 0;
  std::vector<u32> data;
  std::string debug_name;
  std::string debug_tpage_name;
  bool load_to_pool = false;
  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
};

struct IndexTexture {
  u16 w = 0, h = 0;
  u32 combo_id = 0;
  std::vector<u8> index_data;
  std::vector<std::string> level_names;
  std::string name;
  std::string tpage_name;
  std::array<math::Vector4<u8>, 256> color_table;
  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
};

// Tfrag trees have several kinds:
enum class TFragmentTreeKind { NORMAL, TRANS, DIRT, ICE, LOWRES, LOWRES_TRANS, WATER, INVALID };

constexpr const char* tfrag_tree_names[] = {"normal", "trans",        "dirt",  "ice",
                                            "lowres", "lowres-trans", "water", "invalid"};

// A tfrag model
struct TfragTree {
  TFragmentTreeKind kind = TFragmentTreeKind::INVALID;        // our tfrag kind
  std::vector<StripDraw> draws;  // the actual topology and settings
  PackedTfragVertices packed_vertices;
  PackedTimeOfDay colors;  // vertex colors (pre-interpolation)
  BVH bvh;                 // the bvh for frustum culling
  bool use_strips = true;

  // ------------------------------------------------------------------------------------------
  // Gprecompute-deterministic-bake (owner 2026-08-26: « tout ce qu'on peut pre-computer devrait
  // l'etre au lieu de prendre du temps CPU/GPU »). THE PER-VERTEX TANGENT FRAME, BAKED OFFLINE.
  //
  // The tangent of a vertex is a pure function of this tree's PACKED bytes: the positions and UVs
  // come from packed_vertices, the triangle topology from draws + use_strips, and the accumulation
  // is index-ordered, so the fr3 fully determines the answer. It used to be re-derived on EVERY
  // load on EVERY machine (reconstruct_tfrag_tangents, ~26.3 MB of output for village1 alone).
  // It is now derived ONCE, by the fr3 extractor, and only expanded here.
  //
  // ONE u16 PER VERTEX: 15 bits of angle in the plane perpendicular to the vertex normal, plus the
  // handedness sign in bit 15 (see normal_pack.h). The derivation Gram-Schmidts T against N, so the
  // direction N already fixes is not stored twice — which is why 2 bytes buy 0.011 deg here where a
  // packed 10-10-10 vector would have spent 4 bytes to get 0.11 deg. On village1 the whole bake is
  // 6.6 MB rather than 13.2, and TIE is 91% of it (TIE tangents are per-INSTANCE because the
  // derivation runs on world-space vertices, while TIE positions are per-PROTOTYPE).
  // Empty, or a size other than the vertex count, means a level built before this bake: unpack()
  // then backfills a continuous Duff/Frisvad basis from the smooth normal (O(n), no topology walk)
  // and says so, rather than silently handing the shader a zero tangent.
  std::vector<u16> baked_tangents;

  struct {
    std::vector<PreloadedVertex> vertices;  // mesh vertices
    std::vector<u32> indices;
    // Grecharged-pbr-realtime-fusion REOPEN#7 FOUNDATION FIX: per-vertex MikkTSpace tangent
    // (xyz = orthonormalized tangent in world space, w = +/-1 handedness for the bitangent).
    // EXPANDED at load from `baked_tangents` above (no longer re-derived) so the PBR shader builds
    // a CONTINUOUS TBN from an interpolated vertex tangent instead of screen-space derivatives
    // (dFdx/dFdy) — the derivative TBN is discontinuous at triangle edges/UV seams, which caused
    // the owner's incoherent relief + hard contrast CRACKS at relief>0. Runtime-only working copy;
    // uploaded as vertex attribute location 5 and then released (see release_uploaded_tangents).
    std::vector<math::Vector4f> tangents;
  } unpacked;
  void unpack();
  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
};

struct TieWindInstance {
  std::array<math::Vector4f, 4> matrix = {};
  u16 wind_idx = 0;
  float stiffness = 0;
  void serialize(Serializer& ser);
};

// Tie draws are split into categories.
enum class TieCategory {
  // normal tie buckets
  NORMAL,
  TRANS,  // also called alpha
  WATER,

  // first draw (normal base draw) for envmapped stuff
  NORMAL_ENVMAP,
  TRANS_ENVMAP,
  WATER_ENVMAP,

  // second draw (shiny) for envmapped ties.
  NORMAL_ENVMAP_SECOND_DRAW,
  TRANS_ENVMAP_SECOND_DRAW,
  WATER_ENVMAP_SECOND_DRAW,
};
constexpr int kNumTieCategories = 9;

constexpr bool is_envmap_first_draw_category(tfrag3::TieCategory category) {
  switch (category) {
    case tfrag3::TieCategory::NORMAL_ENVMAP:
    case tfrag3::TieCategory::WATER_ENVMAP:
    case tfrag3::TieCategory::TRANS_ENVMAP:
      return true;
    default:
      return false;
  }
}

constexpr bool is_envmap_second_draw_category(tfrag3::TieCategory category) {
  switch (category) {
    case tfrag3::TieCategory::NORMAL_ENVMAP_SECOND_DRAW:
    case tfrag3::TieCategory::WATER_ENVMAP_SECOND_DRAW:
    case tfrag3::TieCategory::TRANS_ENVMAP_SECOND_DRAW:
      return true;
    default:
      return false;
  }
}

constexpr TieCategory get_second_draw_category(tfrag3::TieCategory category) {
  switch (category) {
    case TieCategory::NORMAL_ENVMAP:
      return TieCategory::NORMAL_ENVMAP_SECOND_DRAW;
    case TieCategory::TRANS_ENVMAP:
      return TieCategory::TRANS_ENVMAP_SECOND_DRAW;
    case TieCategory::WATER_ENVMAP:
      return TieCategory::WATER_ENVMAP_SECOND_DRAW;
    default:
      return TieCategory::NORMAL_ENVMAP;
  }
}

// A tie model
struct TieTree {
  BVH bvh;
  std::vector<StripDraw> static_draws;
  // Category n uses draws: static_draws[cdi[n]] to static_draws[cdi[n + 1]]
  std::array<u32, kNumTieCategories + 1> category_draw_indices = {};

  PackedTieVertices packed_vertices;
  PackedTimeOfDay colors;  // vertex colors (pre-interpolation)

  std::vector<InstancedStripDraw> instanced_wind_draws;
  std::vector<TieWindInstance> wind_instance_info;

  // jak 2 and later can toggle on and off visibility per proto by name
  bool has_per_proto_visibility_toggle = false;
  std::vector<std::string> proto_names;

  bool use_strips = true;

  // ------------------------------------------------------------------------------------------
  // Gprecompute-deterministic-bake (owner 2026-08-26: « tout ce qu'on peut pre-computer devrait
  // l'etre au lieu de prendre du temps CPU/GPU »). THE PER-VERTEX TANGENT FRAME, BAKED OFFLINE.
  //
  // The tangent of a vertex is a pure function of this tree's PACKED bytes: the positions and UVs
  // come from packed_vertices, the triangle topology from draws + use_strips, and the accumulation
  // is index-ordered, so the fr3 fully determines the answer. It used to be re-derived on EVERY
  // load on EVERY machine (reconstruct_tfrag_tangents, ~26.3 MB of output for village1 alone).
  // It is now derived ONCE, by the fr3 extractor, and only expanded here.
  //
  // ONE u16 PER VERTEX: 15 bits of angle in the plane perpendicular to the vertex normal, plus the
  // handedness sign in bit 15 (see normal_pack.h). The derivation Gram-Schmidts T against N, so the
  // direction N already fixes is not stored twice — which is why 2 bytes buy 0.011 deg here where a
  // packed 10-10-10 vector would have spent 4 bytes to get 0.11 deg. On village1 the whole bake is
  // 6.6 MB rather than 13.2, and TIE is 91% of it (TIE tangents are per-INSTANCE because the
  // derivation runs on world-space vertices, while TIE positions are per-PROTOTYPE).
  // Empty, or a size other than the vertex count, means a level built before this bake: unpack()
  // then backfills a continuous Duff/Frisvad basis from the smooth normal (O(n), no topology walk)
  // and says so, rather than silently handing the shader a zero tangent.
  std::vector<u16> baked_tangents;

  struct {
    std::vector<PreloadedVertex> vertices;  // mesh vertices
    std::vector<u32> indices;
    // Grecharged-pbr-realtime-fusion REOPEN#7: per-vertex MikkTSpace tangent (see TfragTree). TIE
    // non-envmap draws use the TFRAG3 shader, so they need the same continuous TBN. Attribute loc 5.
    // EXPANDED at load from `baked_tangents` above.
    std::vector<math::Vector4f> tangents;
    // ------------------------------------------------------------------------------------------
    // Grecharged-foliage-wind3 (owner 2026-08-31, defaut D2 : « tous les arbres ne sont pas
    // impactés ») — LE BALANCEMENT, DEUX OCTETS PAR SOMMET. Parallele a `vertices`, uploade sur
    // l'attribut 7 du VAO TIE (meme patron que `tangents`, attribut 5), rendu ensuite comme eux.
    //   [2*v + 0] = POIDS   : 0 = ce sommet ne bouge JAMAIS, 255 = pleine couronne.
    //   [2*v + 1] = PHASE   : la phase de balancement de SON INSTANCE, sur 8 bits de [0, 2 pi).
    //
    // POURQUOI LA PHASE EST UNE DONNEE ET PAS UN CALCUL DE SHADER. Il faut qu'elle soit constante
    // sur toute la plante (sinon la plante se DECHIRE au lieu de se balancer) et differente d'une
    // plante a l'autre (sinon tout le decor glisse en bloc). Les deux seules grandeurs qu'un
    // sommet TIE porte deja sont sa POSITION — qui varie a l'interieur de la plante — et son
    // `color_index`, qui sur TIE identifie le PROTOTYPE et non l'instance (voir plus bas) : tous
    // les palmiers du niveau bougeraient alors en parfait synchronisme. L'identite d'instance
    // n'existe qu'ici, dans `matrix_groups` ; c'est donc ici que la phase se derive (angle d'or
    // sur le `matrix_idx`).
    //
    // POURQUOI PAR SOMMET ET PAS UNE LUT PAR `color_index` (la route refutee). Sur SHRUB,
    // extract_shrub ecrit une entree de palette PAR INSTANCE, donc `color_index` identifie la
    // plante et une LUT (ymin, hauteur) indexee dessus ancre chaque buisson (Shrub.cpp:192-244).
    // Sur TIE c'est FAUX : `make_big_palette` (extract_tie.cpp:2106-2124) attribue
    // `color_index_offset_in_big_palette` PAR PROTOTYPE, partage par toutes ses instances. Une LUT
    // par `color_index` rendrait donc le ymin du PROTOTYPE, faux pour toute instance posee a une
    // autre altitude — un palmier ancre sur la base de son voisin. L'ancrage doit donc etre
    // resolu par INSTANCE (`matrix_groups`), et le seul endroit ou l'instance d'un sommet est
    // encore connue est `unpack()`.
    //
    // ET C'EST AUSSI POURQUOI CE N'EST PAS CALCULE DANS `Tie3::load_from_fr3_data` : les sommets
    // CPU du TIE sont RENDUS avant que cette fonction ne tourne (Loader.cpp:1550-1553 libere des
    // la fin de l'etape `texture` ; le commentaire Loader.cpp:1588-1591 dit que les lectures
    // tardives, `Tie3::load_from_fr3_data` comprise, sont appelees par le RENDU apres ce point
    // malgre leur nom). Une LUT construite la lirait un vecteur VIDE.
    //
    // Rendu par `release_uploaded_vertices` en meme temps que `vertices` et `tangents`.
    std::vector<u8> sway;
  } unpacked;

  // Grecharged-foliage-wind3 — LE RECENSEMENT QUI PORTE LE VERDICT DE D2. Rempli par `unpack()`
  // (le seul point ou prototypes, instances et sommets coexistent) et IMPRIME par
  // `Tie3::load_from_fr3_data`, qui est le seul point ou le nom du niveau est connu. Il survit a
  // la liberation des sommets parce qu'il ne contient que des compteurs.
  // `noms_non_classes` porte les noms des prototypes qu'AUCUNE ligne du lexique ne couvre :
  // sans eux, retirer un nom du lexique retrecirait le denominateur en silence.
  struct SwayCensus {
    u32 protos = 0;          // proto_names.size() de cet arbre
    u32 veg_protos = 0;      // ceux que le lexique couvre
    u32 non_classes = 0;     // les autres
    u32 inst_total = 0;      // matrix_idx distincts >= 0 (instances posees)
    u32 inst_veg = 0;        // instances dont au moins un sommet est reclame par un proto vegetal
    u32 inst_swayed = 0;     // instances dont au moins un sommet finit avec un poids > 0
    u64 verts = 0;
    u64 v_sway = 0;          // sommets a poids > 0
    u64 v_neutre = 0;        // sommets a poids 0 (toutes causes confondues)
    u64 v_windpath = 0;      // matrix_idx == -1 : chemin VENT, restes locaux au prototype
    u64 v_sansproto = 0;     // jamais reclames par un vis-group statique
    u64 v_conflit = 0;       // reclames a la fois par un proto DU lexique et un proto HORS lexique
    // Les deux garde-fous de l'hypothese de pavage « un run par vis-group, num_inds == length+1 »
    // (extract_tie.cpp:2531-2545 + merge_groups :2736). Non nuls = l'hypothese est FAUSSE sur ce
    // niveau, et la ligne de recensement le dit au lieu d'ancrer des sommets au hasard.
    u32 vg_desync = 0;
    u64 plain_inds = 0;      // TIE n'en pousse jamais ; non nul = la lecture par runs est partielle
    bool lexicon_loaded = false;
    std::vector<std::string> noms_non_classes;  // tronquee a 12
  } sway_census;

  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
  void unpack();
};

struct ShrubTree {
  // todo some visibility structure
  PackedTimeOfDay time_of_day_colors;  // multiplier colors

  PackedShrubVertices packed_vertices;
  std::vector<ShrubDraw> static_draws;  // the actual topology and settings
  std::vector<u32> indices;

  struct {
    std::vector<ShrubGpuVertex> vertices;  // mesh vertices
  } unpacked;

  // jak 2 and later can toggle on and off visibility per proto by name
  bool has_per_proto_visibility_toggle = false;
  std::vector<std::string> proto_names;

  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
  void unpack();
};

struct HfragmentVertex {
  float height = 0;
  u32 vi = 0;
  u16 color_index = 0;
  u8 u = 0, v = 0;
  u32 pad = 0;
};

struct HfragmentCorner {
  math::Vector<float, 4> bsphere;
  u32 vis_id = 0;
  u32 index_start = 0;
  u32 index_length = 0;
  u32 num_tris = 0;
};

struct HfragmentBucket {
  std::vector<u32> corners;
  std::array<u16, 16> montage_table = {};
  void serialize(Serializer& ser);
};

struct Hfragment {
  std::vector<HfragmentVertex> vertices;
  std::vector<u32> indices;
  std::vector<HfragmentCorner> corners;
  std::vector<HfragmentBucket> buckets;
  PackedTimeOfDay time_of_day_colors;

  std::array<s32, 4> wang_tree_tex_id = {};
  DrawMode draw_mode;
  u32 occlusion_offset = 0;

  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
};

struct CollisionMesh {
  struct Vertex {
    float x, y, z;
    u32 flags;
    s16 nx, ny, nz;
    u16 pad;
    u32 pat;
    u32 pad2;
  };
  static_assert(sizeof(Vertex) == 32);
  std::vector<Vertex> vertices;
  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
};

// MERC

struct MercVertex {
  alignas(32) float pos[3];
  float pad0;

  float normal[3];
  float pad1;

  float weights[3];
  float pad2;

  float st[2];

  u8 rgba[4];
  u8 mats[3];
  u8 pad3;
};
static_assert(sizeof(MercVertex) == 64);

struct MercDraw {
  DrawMode mode;
  s32 tree_tex_id = 0;  // the texture that should be bound for the draw (negative for anim slot)
  u8 eye_id = 0xff;     // 0xff if not eyes, (slot << 1) | (is_r)
  u32 first_index = 0;
  u32 index_count = 0;
  u32 num_triangles = 0;
  // no strip hack for custom models
  bool no_strip = false;
  void serialize(Serializer& ser);
};

struct BlercFloatData {
  // [x, y, z, pad, nx, ny, nz, pad]
  // note that this should match the layout of the merc vertex above
  alignas(32) float v[8];
};

/*!
 * Data to modify vertices based on blend shapes.
 */
struct Blerc {
  std::vector<BlercFloatData> float_data;
  std::vector<u32> int_data;
  static constexpr u32 kTargetIdxTerminator = UINT32_MAX;
  void serialize(Serializer& ser);

  // int data, per vertex:
  // [tgt0_idx, tgt1_idx, ..., terminator, dest]
  // float data, per vertex:
  // [base, tgt0, tgt1, ...]

  // final vertex position is:
  // base + sum(tgtn * weights[tgtn_idx])
};

struct MercModifiableDrawGroup {
  std::vector<MercVertex> vertices;
  std::vector<u16> vertex_lump4_addr;
  std::vector<MercDraw> fix_draw, mod_draw;
  std::vector<u8> fragment_mask;
  Blerc blerc;
  u32 expect_vidx_end = 0;

  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
};

struct MercEffect {
  std::vector<MercDraw> all_draws;
  MercModifiableDrawGroup mod;
  DrawMode envmap_mode;
  u32 envmap_texture = 0;
  bool has_envmap = false;
  bool has_mod_draw = false;
  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
};

struct MercModel {
  std::string name;
  std::vector<MercEffect> effects;
  u32 max_draws = 0;
  u32 max_bones = 0;
  u32 st_vif_add = 0;
  float xyz_scale = 0;
  float st_magic = 0;
  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
};

struct MercModelGroup {
  std::vector<MercVertex> vertices;
  std::vector<u32> indices;
  std::vector<MercModel> models;
  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
};

//

constexpr int TFRAG_GEOS = 3;
constexpr int TIE_GEOS = 4;

struct Level {
  u16 version = TFRAG3_VERSION;
  std::string level_name;
  std::vector<Texture> textures;
  std::vector<IndexTexture> index_textures;
  std::array<std::vector<TfragTree>, TFRAG_GEOS> tfrag_trees;
  std::array<std::vector<TieTree>, TIE_GEOS> tie_trees;
  std::vector<ShrubTree> shrub_trees;
  Hfragment hfrag;
  CollisionMesh collision;
  MercModelGroup merc_data;
  u16 version2 = TFRAG3_VERSION;
  void serialize(Serializer& ser);
  void memory_usage(MemoryUsageTracker* tracker) const;
};

void print_memory_usage(const tfrag3::Level& lev, int uncompressed_data_size);

// Gprecompute-deterministic-bake — cumulative nanoseconds this process has spent EXPANDING baked
// tangents at load (the dequantise loop that replaced the per-triangle derivation), and the number
// of vertices it covered. The loader prints the delta per level so the cost that is left can be put
// next to the [tangent-bake] figure the fr3 extractor printed for the same level.
// Gprecompute-deterministic-bake — set by the OFFLINE bake around its unpack() calls. The bake
// overwrites the tangents the moment unpack() returns, so unpack() must not spend an O(n) backfill
// on them, must not count their absence as a defect, and must not write the per-tree device
// diagnostic file (pbr_tan_diag.txt) thousands of times inside the fr3 extractor.
void set_tangent_bake_in_progress(bool on);

u64 baked_tangent_expand_ns();
u64 baked_tangent_expand_verts();

// OWNER REOPEN #13 + INSIGHT #2: GLOBAL cross-chunk/bucket/system vertex weld + normal-orientation-
// consistency pass. Run ONCE after every tfrag/tie/shrub tree is unpacked (Loader.cpp) — one spatial
// hash over the WHOLE level stitches coincident positions across bucket AND system boundaries (closing
// the inter-chunk seam LINES the per-tree weld left open), orients inward normals outward via the
// walkable collision mesh, then averages across the welded seams with a crease-angle threshold.
void reconstruct_level_global_weld(Level& lev);

// ROUND 31 — RE-DERIVE EVERY PER-VERTEX TANGENT FRAME FROM THE VERTEX NORMALS AS THEY STAND NOW.
//
// The tangent .w handedness is not a free parameter: the shader rebuilds the bitangent as
// cross(N, T) * w (pbr_fused.glsl:12-29), so w is only correct RELATIVE TO A PARTICULAR N. Tangents
// are computed at unpack time, and mesh_consolidate() then rewrites essentially every normal
// (global weld + crease-clustered re-smoothing). Its pass 7b patched w only where the new normal was
// fully INVERTED; a normal that was merely ROTATED into another smoothing cluster kept a w that had
// been computed against a different frame. That population is not marginal and it was already being
// counted, as a diagnostic that wrote nothing back: [tan-frame] handedness_mismatch=342860 of
// 1264479 cross-chunk pairs on village1 (27.1%), measured for several rounds without being fixed.
// A wrong w flips B and therefore inverts the parallax march in V ONLY, leaving the tessellation
// tier (which uses N alone) correct — exactly the surfaces the owner reports as inverted in one
// tier and fine in the other.
//
// Rather than patch the sign, recompute the whole frame against the final normals with the SAME
// Lengyel accumulation that produced it in the first place, so w is right by construction.
// Returns the number of vertices whose (T, w) actually changed.
u64 retangent_level_from_final_normals(Level& lev);

// ROUND 32 — make the per-vertex tangent frame VALID FOR EVERY FACE THAT SHARES IT, not merely the
// average of them. With N fixed, T has one degree of freedom (an angle in the plane perpendicular to
// N), which turns "dot(T,dPdu) > 0 and dot(cross(N,T)*w, dPdv) > 0 for every incident face" into an
// intersection of open half-circles — solved exactly by a sort, no iteration. A frame that is already
// valid is left BIT-IDENTICAL (the authored average is what the normal map was made for); a frame
// with no solution at all (incident faces whose UV directions span a half-turn) is left alone and
// counted. Returns the number of vertices rewritten; the three out-params report the already-valid,
// unsatisfiable and constrained-vertex populations. See the comment at the definition.
u64 retangent_positive_from_final_normals(Level& lev,
                                          u64* out_already,
                                          u64* out_unsat,
                                          u64* out_den);

// ROUND 32 — re-establish the displacement-sign invariant AFTER mesh_presubdivide_level().
// mesh_consolidate pass 12 guarantees dot(N_v, outward(f)) > 0 at every corner, but the refinement
// runs after it and INVENTS vertices (a midpoint's normal is the normalized sum of its parents',
// its tangent is the summed T with parent A's handedness verbatim, re-orthogonalised against
// nothing), so on village1 about a third of the vertices the tessellator touches never saw that
// check. This is the cheap per-tree form of pass 12: no weld, no shell and no outward authority are
// needed, because positivity is a property of a VERTEX INDEX and its incident faces, and each face
// is measured against its OWN corner-normal consensus — the same reference tools/tess_sign grades
// A_cons against. Call it, then retangent_positive_from_final_normals(), immediately after the
// subdivision. Returns the number of normals rewritten. See the comment at the definition.
u64 mesh_positivity_repair_level(Level& lev, u64* out_ok, u64* out_unsat, u64* out_den);

// ROUND 29 — MIRRORED TIE INSTANCE CENSUS. A TIE instance matrix with a NEGATIVE 3x3 determinant
// places a MIRRORED copy of its prototype (the standard way to duplicate a building without
// duplicating geometry). Pure measurement: walks the packed instance matrices and counts, it never
// modifies the level.
struct TieMirrorCensus {
  u64 matrices = 0;           // distinct TIE instance matrices
  u64 mirrored_matrices = 0;  // ...of which det3 < 0
  u64 groups = 0;             // matrix groups (a group = one instance's slice of the vertex array)
  u64 mirrored_groups = 0;
  u64 verts = 0;              // verts placed by a matrix
  u64 mirrored_verts = 0;
  u64 mirrored_groups_with_normals = 0;  // groups where the AUTHORED-normal path is also mirrored
};
TieMirrorCensus tie_mirror_census(const Level& lev);

}  // namespace tfrag3
