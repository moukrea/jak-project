#pragma once

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "common/dma/gs.h"
#include "common/math/Vector.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/BucketRenderer.h"

// Gjak2-visuals probe: one-shot per background (tie/tfrag) anim-slot bind —
// diffable our-x86 (env GJ2VIS_SKY) vs device (always) to see which title
// surfaces depend on TextureAnimator output slots.
inline void gj2vis_probe_bg_slot(int slot, unsigned tex) {
#ifdef __ANDROID__
  static const bool s_on = true;
#else
  static const bool s_on = getenv("GJ2VIS_SKY") != nullptr;
#endif
  if (s_on) {
    static bool s_seen[128] = {};
    if (slot >= 0 && slot < 128 && !s_seen[slot]) {
      s_seen[slot] = true;
      fprintf(stderr, "GJ2VIS-BGSLOT slot=%d tex=%u\n", slot, tex);
    }
  }
}

struct GoalBackgroundCameraData {
  math::Vector4f planes[4];
  math::Vector<s32, 4> itimes[4];
  math::Vector4f camera[4];
  math::Vector4f hvdf_off;
  math::Vector4f fog;
  math::Vector4f trans;
  math::Vector4f rot[4];
  math::Vector4f perspective[4];
};

// data passed from game to PC renderers
// the GOAL code assumes this memory layout.
struct TfragPcPortData {
  GoalBackgroundCameraData camera;
  char level_name[32];
};
static_assert(sizeof(TfragPcPortData) == 16 * 25);

// inputs to background renderers.
struct TfragRenderSettings {
  GoalBackgroundCameraData camera;
  int tree_idx;
  bool debug_culling = false;
  const u8* occlusion_culling = nullptr;
};

enum class DoubleDrawKind { NONE, AFAIL_NO_DEPTH_WRITE };

struct DoubleDraw {
  DoubleDrawKind kind = DoubleDrawKind::NONE;
  float aref_first = 0.;
  float aref_second = 0.;
  float color_mult = 1.;
};

// cached alpha_min/alpha_max uniform locations for a linked program (hot path:
// looked up once per program instead of per draw)
struct TfragAlphaUniforms {
  s32 alpha_min = -1;
  s32 alpha_max = -1;
};
const TfragAlphaUniforms& tfrag_alpha_uniforms(u64 program);

// Grecharged-grass-overhang2: near-fade params for the painted grass-fringe alpha strips (the 3D
// droop covers them near; far keeps the stock texture). x=enable, distances in METERS to match the
// tfrag3 shader's meter-scaled varying. Returns on=false unless BOTH recharged grass toggles are ON.
struct GrassFringeFade {
  bool on = false;
  float start_m = 0.f;
  float end_m = 0.f;
  // Grecharged-grass-overhang7 ROUND 10 forensics (painted strip still visible at the owner's close
  // judging distance): debug.opengoal.grass.fringe_dbg (Android) / GRASS_FRINGE_DBG (desktop).
  // 0 = stock (default). 1 = ignore the steepness gate (fade EVERY texel of the two fringe textures
  // near). 2 = don't fade; paint the gate state instead (magenta = would-fade steep face, cyan =
  // gate-blocked flat-ish face) — one close capture then names WHY a tuft survived the fade.
  float dbg = 0.f;
};
GrassFringeFade grass_fringe_fade_params();

// Grecharged-grass-overhang7: levels the recharged grass system covers. Round-7 root cause: the
// whole system (placement + fringe fade) was hardcoded to "training" while the owner plays and
// judges at Sentinel Beach — every lip there kept the stock painted overhang no matter the toggle.
// The GBK7 texture set (tra-grass / bch-grassfringe / bch-leafyground-hang-2x1) matches ONLY these
// two levels (16-level census 2026-07-14); other levels use differently-named grass textures and
// stay stock until they get their own curated set + bake.
// Ggrass-density-presets (owner 2026-08-30) : « sur la plage peut-etre que il y a de l'herbe en
// calcul mais ca n'a jamais ete visible, tu peux completement dismiss ». MESURE AVANT RETRAIT, course
// x86 du 2026-08-31 (3 chargements de `beach-start`, herbe armee, pre-calcul actif) :
//     PLACE-TIME mode=precomputed bake=out/jak1/fr3/beach.grassbake total=423ms
//                (source=142ms expand+logs=259ms upload+light=22ms) instances=176350
// La plage n'etait donc PAS vide — elle placait 176 350 brins pour 423 ms de chargement, plus une
// mise a jour de lumiere par image tant qu'elle est chargee. Ce qu'on retire est du GACHIS paye a
// chaque premiere entree sur le niveau le plus parcouru du jeu, pas un reste inoffensif : la
// premisse « la plage ne place jamais un brin » est REFUTEE, c'est le verdict de l'owner sur la
// VISIBILITE qui tranche, pas l'absence de calcul.
inline constexpr const char* kGrassLevels[] = {"training"};
inline bool grass_level_enabled(const std::string& name) {
  for (const char* n : kGrassLevels) {
    if (name == n) {
      return true;
    }
  }
  return false;
}

DoubleDraw setup_tfrag_shader(SharedRenderState* render_state, DrawMode mode, ShaderId shader);
DoubleDraw setup_opengl_from_draw_mode(DrawMode mode, u32 tex_unit, bool mipmap);

// Pure computation of DoubleDraw settings from a DrawMode (no GL calls) — used
// by the tfrag-family state cache to pick the alpha uniform without re-issuing
// GL state.
DoubleDraw compute_double_draw(DrawMode mode);

// lighting-ao-indirect : le `alpha_min` que `compute_double_draw` donnerait a ce mode, sans
// construire un DoubleDraw. C'est le seuil que la passe principale applique a `color.a`
// (tfrag3.frag:130, shrub.frag:84). 0 = ce draw ne jette rien, la prepasse n'a pas a le texturer.
float prepass_alpha_min(const DrawMode& mode);

// lighting-ao-indirect (refus owner (c)/(g) du 2026-09-12) : VRAI si ce draw ecrit la
// profondeur dans la passe principale. Miroir EXACT de la condition de `glDepthMask` de
// `setup_opengl_from_draw_mode` (background_common.cpp:336). Un draw qui rend FAUX ne doit
// pas entrer dans la prepasse de profondeur : son quad y deviendrait un occluder d'AO que
// l'image ne dessine pas.
bool prepass_writes_depth(const DrawMode& mode);

// lighting-ao-indirect (terme 3) : L'ETAT D'ECHANTILLONNAGE, DEFINI UNE SEULE FOIS.
// `setup_opengl_from_draw_mode` pose QUATRE `glTexParameteri` — et un `glTexParameteri` ecrit sur
// l'OBJET TEXTURE LIE, pas sur l'unite : l'etat survit donc au draw qui l'a pose. La prepasse de
// profondeur lie les MEMES objets (PrePass.cpp, `draw_depth_range`) et n'en posait AUCUN. Tirant au
// bucket 6, AVANT tout draw couleur de l'image, elle heritait de ce que le DERNIER consommateur de
// l'image PRECEDENTE y avait laisse — TIE, Shrub, Hfrag, DirectRenderer, Generic2 et
// TextureAnimator posent tous CLAMP ou REPEAT selon LEUR propre mode sur des objets du meme pool.
// Un `GL_REPEAT` la ou le draw veut `GL_CLAMP_TO_EDGE`, ou un `GL_LINEAR` la ou il veut
// `GL_LINEAR_MIPMAP_LINEAR`, fait lire un AUTRE texel : l'alpha-test de la prepasse jette alors un
// fragment que la passe couleur garde, et l'AO se calcule sur un trou.
// Ces deux fonctions sont la SEULE definition de la regle. Les trois sites l'appellent
// (`setup_opengl_from_draw_mode`, `apply_tex_params_from_draw_mode`, la prepasse) ; aucun ne la
// recopie, sinon le prochain changement de regle ne toucherait que deux sites sur trois.
// `prepass_tex_mode` : bit 0 = clamp_s, bit 1 = clamp_t, bit 2 = filt. 0xff = INCONNU, et la
// prepasse ne pose alors RIEN — un contributeur qui ne renseigne pas son mode n'a pas le droit de
// fabriquer un etat par defaut.
uint8_t prepass_tex_mode(const DrawMode& mode);
// Rend, dans l'ordre, les valeurs de GL_TEXTURE_WRAP_S, GL_TEXTURE_WRAP_T, GL_TEXTURE_MIN_FILTER
// et GL_TEXTURE_MAG_FILTER. `tex_mode == 0xff` rend quatre zeros (aucune valeur GL valide).
void prepass_tex_params(uint8_t tex_mode, bool mipmap, int out4[4]);

// Gperf-particles: per-draw GL state cache for the tfrag-family loops. A local
// cache lives at the top of each tree-render function (per-render reset). When
// render_state->perf_state_cache is off, setup_tfrag_shader_cached is exactly
// setup_tfrag_shader.
struct BgDrawStateCache {
  u32 last_mode;
  GLuint last_tex;
  bool valid = false;
};
DoubleDraw setup_tfrag_shader_cached(SharedRenderState* rs,
                                     DrawMode mode,
                                     ShaderId shader,
                                     GLuint bound_tex,
                                     BgDrawStateCache& cache);

void first_tfrag_draw_setup(const GoalBackgroundCameraData& settings,
                            SharedRenderState* render_state,
                            ShaderId shader);

// lighting-regimes (SPEC §4.10) : la capture du ciel est-elle voulue cette image ? (item arme,
// eclairage recharge actif, un niveau actif a un ciel). Faux sans OG_FEAT_PBR.
bool regime_sky_capture_wanted();

#ifdef OG_FEAT_PBR
// lighting-shadows (SPEC-refonte-lumiere §4.8) : ATLAS D'OMBRE TUILE, deux astres, acteurs.
// Remplace l'ancienne carte unique. UN atlas carre par cote du double-buffer, decoupe en 2x2
// tuiles : les tuiles 0..cascades-1 portent les CASCADES de l'astre DOMINANT (le plus haut ET
// le plus pesant), la derniere tuile porte l'unique tuile du SECOND astre quand il est haut ET
// pese plus de 5% du total direct. Deux astres, deux ombres, aucune attribution ni fondu
// (SPEC §3.4/§4.8) : contrairement a l'ancienne carte unique, il n'y a plus de bascule a fondre
// entre les deux — chaque astre a sa propre geometrie d'atlas, active ou non selon sa hauteur.
//
// DOUBLE-BUFFERE comme avant : les casters STATIQUES (tfrag/tie/shrub) sont rejoues au premier
// passage camera de l'image (`pbr_shadow_first_camera`, via la prepasse d'AO) dans l'atlas
// D'ECRITURE ; les acteurs (merc) y ajoutent leurs propres draws pendant la passe couleur
// (implementeur B). Les receveurs echantillonnent l'atlas de LECTURE = celui complete l'image
// precedente, avec sa matrice.
struct PbrShadowState {
  GLuint fbo[2] = {0, 0};
  GLuint depth_tex[2] = {0, 0};
  int size = 4096;      // cote de l'atlas (desktop 4096, Android 2048)
  int tile_px = 2048;   // cote d'une tuile = size/2
  int cascades = 3;      // nombre de cascades de l'astre dominant (desktop 3, Android 2)
  float half[4] = {8.f, 32.f, 150.f, 150.f};  // demi-etendue (m) par tuile
  u64 frame = ~0ull;   // frame_idx that last cleared the write map
  bool valid = false;  // resources created OK
  int write = 0;          // buffer index this frame's depth pass renders into
  bool have_mvp = false;  // write-side matrices computed for the current frame
  bool tile_on[4] = {false, false, false, false};       // write-side : tuile active cette image
  bool read_tile_on[4] = {false, false, false, false};  // promue au flip
  float tile_mvp[4][16];       // write-side, par tuile (metres camera-relatifs -> clip tuile)
  float read_tile_mvp[4][16];  // promue au flip
  float texel_world[4] = {0.f, 0.f, 0.f, 0.f};       // metres/texel, par tuile (write)
  float read_texel_world[4] = {0.f, 0.f, 0.f, 0.f};  // promu au flip
  int key_light = 0;       // 0 = le soleil porte les cascades, 1 = la lune verte
  int read_key_light = 0;  // promu au flip
  float w_sun = 0.f;   // poids direct du soleil (image precedente)
  float w_moon = 0.f;  // poids direct de la lune verte (image precedente)
  float cam_rot[16] = {1.f, 0.f, 0.f, 0.f, 0.f, 1.f, 0.f, 0.f,
                       0.f, 0.f, 1.f, 0.f, 0.f, 0.f, 0.f, 1.f};  // vue GL, colonne-major
  float merc_mvp[4][16];  // "vue merc (metres GOAL) -> clip tuile", par tuile
  bool merc_mvp_valid[4] = {false, false, false, false};
  u32 class_mask_frame = 0;  // classes ayant projete >0 indices cette image (bits ci-dessous)
  u32 read_class_mask = 0;   // promu au flip
  u32 class_mask_run = 0;    // union depuis le debut (publication)
  u64 class_idx[4] = {0, 0, 0, 0};  // indices ce cadre : tfrag, tie, shrub, merc
  bool cast_full = true;  // hors du chemin livre desormais (le caster statique est TOUJOURS complet)
  bool debug = false;    // telemetrie (env OG_PBR_SHADOW_DEBUG / prop ...pbr.shadowdbg)
  float write_cam[3] = {0.f, 0.f, 0.f};
  float read_cam[3] = {0.f, 0.f, 0.f};
};
PbrShadowState& pbr_shadow_state();
void pbr_shadow_ensure_resources();  // lazy FBO/tex creation
// lighting-shadows : classes de projecteurs (bitmask).
constexpr u32 kShadowCastTfrag = 1, kShadowCastTie = 2, kShadowCastShrub = 4, kShadowCastMerc = 8;
constexpr int kShadowTiles = 4;
// Point d'entree UNIQUE de l'image, appele au premier passage camera (avant
// `prepass::on_first_camera`) : bascule/promotion, calcul des matrices des 4 tuiles, effacement
// de l'atlas d'ECRITURE, et dessin des casters STATIQUES (tfrag/tie/shrub) dans chaque tuile
// active, via la prepasse d'AO.
void pbr_shadow_first_camera(SharedRenderState* rs, const GoalBackgroundCameraData& cam);
// Vrai si l'atlas d'ECRITURE de CETTE image est pret (first_camera a tourne pour frame_idx).
bool pbr_shadow_write_ready(u64 frame_idx);
// Lie le FBO d'ECRITURE de l'atlas, viewport + scissor OFF sur la tuile `tile` ; rend faux si la
// tuile est eteinte cette image. Ne sauve rien : l'appelant sauve/restaure son etat.
bool pbr_shadow_bind_write_tile(int tile);
// Matrice "espace camera merc (vue, unites GOAL) -> clip de la tuile", valide cette image.
const float* pbr_shadow_merc_mvp(int tile);  // nullptr si tuile eteinte ou matrice invalide
// Espace vue (unites GOAL) -> monde (unites GOAL), par l'inverse de camera-rot de l'image
// d'ecriture.
bool pbr_shadow_view_to_world(const float view[3], float out_world[3]);
void pbr_shadow_note_cast(u32 cls, u64 indices);
// Acteurs dans l'atlas cette image ? (mode "vraies", item arme, eclairage recharge, atlas pret)
bool pbr_shadow_merc_cast_enabled(u64 frame_idx);
// Distance max (m) d'un acteur qui projette (reglage "distance des ombres d'acteurs").
float pbr_shadow_actor_dist_m();
// La carte LUE cette image contient-elle des acteurs ? (sert au saut de l'aplat PS2, bucket 47)
bool pbr_shadow_read_has_actors();
// Portee (m) couverte par l'atlas lu : demi-etendue de la derniere cascade (150).
float pbr_shadow_read_range_m();
// Frontiere partagee atlas/aplat (m) : min(distance reglee, 0.9 * portee de l'atlas). 0 si
// l'atlas lu ne porte pas d'acteur. Thread de rendu seulement.
float pbr_shadow_actor_cutoff_m();
// Meme frontiere, lisible depuis le thread GOAL (0.f si mode != "vraies").
float pbr_shadow_actor_blob_cutoff_m_threadsafe();
// Nombre de draws merc projetes dans l'atlas a l'image precedente complete (alimente aussi
// la cle de preuve "shadow_merc_draws_cast", definie dans Merc2.cpp).
u64 pbr_shadow_atlas_draws_cast();
// lighting-shadows, partie A : verdict par acteur (thread GOAL) et fin d'image (thread rendu)
// pour le saut de l'aplat PS2 quand l'ombre reelle couvre deja l'acteur.
void pbr_actor_blob_note(bool skipped);
void pbr_actor_blob_frame_end(u64 frame_idx, u64 blob_tris);
// Preuve : l'image courante est-elle l'image de PREPARATION (les merc ecrivent AUSSI l'atlas
// acteur) ?
bool pbr_shadow_actor_prep_frame(u64 frame_idx);
// Lie le FBO de l'atlas ACTEUR (preuve), viewport sur la tuile ; faux si non prep ou tuile eteinte.
bool pbr_shadow_bind_actor_tile(int tile);
// Preuve : avant/apres un bucket (voir background_common.cpp, section preuve).
void pbr_shadow_proof_frame_begin(u64 frame_idx);
void pbr_shadow_proof_before_bucket(int bucket_id);
void pbr_shadow_proof_post_opaque(SharedRenderState* rs);
// Phantom-lines bisect tool: bitmask gating which STATIC renderers cast into the atlas
// (bit0 tfrag, bit1 tie, bit2 shrub). Default 7 (all). Debug-only override via env
// OG_PBR_CASTER_MASK / prop debug.opengoal.pbr.castermask; cached once per frame.
int pbr_shadow_caster_mask(u64 frame_idx);
// Bind matrix+sampler(+cam-delta re-anchor) on a TFRAG3-family program. cam_trans = the
// CURRENT frame's camera translation in game units (same vector the program's cam_trans
// uniform gets) so the 1-frame-stale read map is sampled in its own camera anchor.
void pbr_shadow_bind_receiver(GLuint program, const float* cam_trans);

// lighting-shadows : l'herbe recharged recoit l'atlas avec sa PROPRE modulation (pas de N.L de
// brin stable), donc elle n'appelle pas `rt_key_vis`/`rt_sec_vis` du C++ — elle a besoin des DEUX
// poids directs de l'image LUE pour doser sa propre attenuation cote shader. `read_key_light`
// dit quel astre (0 soleil, 1 lune) porte les cascades cote LECTURE ; ces deux fonctions donnent
// le poids direct (0..1) de l'astre CASCADES et de l'astre SECOND (tuile 3, 0 si absent),
// mesures a l'image precedente (memes `w_sun`/`w_moon` que `shade.glsl` pese).
float pbr_shadow_read_key_weight();
float pbr_shadow_read_second_weight();

// ROUND 22 PER-PIXEL SCREEN-COVERAGE INSTRUMENTATION (owner defect A step 1: "la plupart des
// endroits n'ont aucun displacement" — measure the truth before porting anything).
// The active PBR debug visualisation mode (android prop debug.opengoal.pbr.debug, desktop env
// OG_PBR_DEBUG; 0 = normal render). Hoisted out of first_tfrag_draw_setup so the renderers that do
// NOT go through that setup (merc2, generic, emerc) can be told the same mode. Not cached — same
// per-call prop read the inline code always did.
int pbr_debug_mode();
// Push u_pbr_debug onto the currently-active program. Programs without the uniform get location -1
// and glUniform1i(-1, ...) is a documented no-op, so this is safe to call on any program.
void pbr_push_debug_tag(GLuint program);
#endif

void interp_time_of_day(const math::Vector<s32, 4> itimes[4],
                        const tfrag3::PackedTimeOfDay& packed_colors,
                        math::Vector<u8, 4>* out);

void cull_check_all_slow(const math::Vector4f* planes,
                         const std::vector<tfrag3::VisNode>& nodes,
                         const u8* level_occlusion_string,
                         u8* out);
bool sphere_in_view_ref(const math::Vector4f& sphere, const math::Vector4f* planes);

void update_render_state_from_pc_settings(SharedRenderState* state, const TfragPcPortData& data);

void make_all_visible_multidraws(std::pair<int, int>* draw_ptrs_out,
                                 GLsizei* counts_out,
                                 void** index_offsets_out,
                                 const std::vector<tfrag3::ShrubDraw>& draws);

u32 make_all_visible_multidraws(std::pair<int, int>* draw_ptrs_out,
                                GLsizei* counts_out,
                                void** index_offsets_out,
                                const std::vector<tfrag3::StripDraw>& draws);

u32 make_multidraws_from_vis_string(std::pair<int, int>* draw_ptrs_out,
                                    GLsizei* counts_out,
                                    void** index_offsets_out,
                                    const std::vector<tfrag3::StripDraw>& draws,
                                    const std::vector<u8>& vis_data);

u32 make_all_visible_index_list(std::pair<int, int>* group_out,
                                u32* idx_out,
                                const std::vector<tfrag3::StripDraw>& draws,
                                const u32* idx_in,
                                u32* num_tris_out);

u32 make_index_list_from_vis_string(std::pair<int, int>* group_out,
                                    u32* idx_out,
                                    const std::vector<tfrag3::StripDraw>& draws,
                                    const std::vector<u8>& vis_data,
                                    const u32* idx_in,
                                    u32* num_tris_out);

u32 make_all_visible_index_list(std::pair<int, int>* group_out,
                                u32* idx_out,
                                const std::vector<tfrag3::ShrubDraw>& draws,
                                const u32* idx_in);

u32 make_multidraws_from_vis_and_proto_string(std::pair<int, int>* draw_ptrs_out,
                                              GLsizei* counts_out,
                                              void** index_offsets_out,
                                              const std::vector<tfrag3::StripDraw>& draws,
                                              const std::vector<u8>& vis_data,
                                              const std::vector<u8>& proto_vis_data);

u32 make_index_list_from_vis_and_proto_string(std::pair<int, int>* group_out,
                                              u32* idx_out,
                                              const std::vector<tfrag3::StripDraw>& draws,
                                              const std::vector<u8>& vis_data,
                                              const std::vector<u8>& proto_vis_data,
                                              const u32* idx_in,
                                              u32* num_tris_out);

// mesh-consolidate-without-consumer — LE COMPTE DE LECTEURS, DEMANDE AU PILOTE.
// `probe_bound_attrib` s'appelle AU POINT D'APPEL : le programme qui va dessiner, et la location a
// laquelle CE VAO a branche un attribut qu'on croit sans lecteur. Une seule fois par couple.
// Un attribut qu'aucun etage ne lit est retire par le compilateur GLSL : il n'est pas ACTIF, et
// c'est le pilote qui le dit. Un grep ne le dirait pas.
namespace mesh_unconsumed_census {
void probe_bound_attrib(u64 program, int location);
void probe_library(ShaderLibrary& shaders);
void publish();
}  // namespace mesh_unconsumed_census
