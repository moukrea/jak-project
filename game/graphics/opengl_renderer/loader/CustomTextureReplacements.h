#pragma once

// Runtime PNG texture replacements from TWO sources.
//
// Textures uploaded by the loader are looked up against two PNG indexes and, on a
// hit, the PNG is uploaded in place of the baked fr3 texture:
//   1. the USER drop dir (get_custom_assets_replacements_dir), gated by
//      Gfx::g_global_settings.load_custom_assets, and
//   2. the package-BUNDLED first-party set under
//      custom_assets/<game>/recharged_textures (get_bundled_recharged_textures_dir):
//      base swaps gated by Gfx::g_global_settings.recharged_textures, the bundle's
//      _height/_normal/_roughness PBR maps gated by the PBR path instead.
// Precedence is user > bundled > stock, and every gate is composed with the Recharged
// master via Gfx::recharged_active().

#include <optional>
#include <string>
#include <vector>

#include "common/common_types.h"

#include "game/graphics/opengl_renderer/loader/ManagedAssets.h"

namespace custom_tex {

struct ReplacementImage {
  std::vector<u8> rgba;
  int w = 0;
  int h = 0;
  const char* src = "";  // which index the file came from: "user"/"bundled"
};

// Which source won the base texture (deterministic mirror of lookup()).
enum class BaseSource { Stock, User, Bundled };

// Look up a replacement for a given texture. Returns nullopt when custom
// assets are disabled or no matching PNG exists.
std::optional<ReplacementImage> lookup(const std::string& tpage_name, const std::string& tex_name);

// Report which source would win the BASE texture for this key, without loading pixels.
BaseSource base_source(const std::string& tpage_name, const std::string& tex_name);

// ===== Gfont-regression (owner 2026-09-02) — LA POLICE N'EST PAS UNE « TEXTURE RECHARGED » =====
// « t'as complètement niqué la font (Urbanist) ça utilise des glyphs chinois de la font par
// défaut du jeu ». Mesure : les deux atlas Urbanist (gamefontnew/ascii.12lo, ascii.24lo)
// voyagent comme des remplacements de textures LIVRES, donc derriere les MEMES portes que les
// textures HD : `recharged-master?`, `recharged-textures?`, et la precedence joueur > telecharge
// > livre > stock de add_texture. Or le TEXTE, lui, est converti en casse mixte SANS porte
// (banques de texte, cycle Gfont-urbanist). Une seule de ces portes fermee — ou un PNG
// `gamefontnew` pose par le joueur, ou un pack telecharge qui porterait cette page — et le jeu
// dessine des minuscules avec l'atlas D'ORIGINE, dont les cellules a-z de la GRANDE police
// sont 26 KANJI (mesure cellule par cellule, project_jak1_two_font_code_pages). C'est mot pour
// mot ce qu'il decrit, et le Redmi ne le montrait pas : toutes ses portes sont a #t.
// Le texte et l'atlas sont UNE unite : l'un ne se livre pas sans l'autre. La page de police se
// resout donc SANS AUCUNE porte, depuis le paquet livre uniquement, et rien ne peut la masquer.
bool is_font_atlas(const std::string& tpage_name);  // tpage_name == "gamefontnew"

// Registre des atlas de police REELLEMENT TELEVERSES (add_texture) et REELLEMENT LIES au dessin
// (DirectRenderer::update_gl_texture) — la preuve se prend au point de LECTURE, pas au chargement.
struct FontAtlasRec {
  std::string key;     // "gamefontnew/ascii.24lo"
  std::string source;  // "bundled-police" (Urbanist) | "stock" (atlas d'origine = kanji)
  int w = 0;
  int h = 0;
  u32 gl = 0;
  u64 binds = 0;  // fois ou le dessin direct a lie cette texture
};
void note_font_atlas_upload(const std::string& key, const char* source, u32 gl_id, int w, int h);
// nullptr si ce GL id n'est pas un atlas de police connu.
FontAtlasRec* font_atlas_by_gl(u32 gl_id);
// Lignes `FONTATLAS ...` pour le fichier de diag natif (files/font_atlas.txt sur Android, ou
// logcat est muet sur le Honor de l'owner).
std::string font_atlas_section();

// ===== Gshield-load-and-crash: the PRE-BAKED tier ==============================================
// Grecharged / Gshield-load-and-crash : niveau PRE-CUIT (baked). Les memes images
// que le niveau PNG, mais deja compressees GPU (ASTC) et deja mipmappees hors ligne.
// Aucun stbi_load, aucun glGenerateMipmap, aucune passe de mesure CPU : les
// statistiques PBR viennent du sidecar produit par la cuisson.
//
// Measured cause this tier exists for (SHIELD, 2026-08-26): one `add_texture` on a PBR
// material costs `stage texture took 1799 ms` on the PNG path — a 2048x2048 stbi_load per
// map (151-330 ms), each map decoded TWICE (probe pass + re-fetch), then glGenerateMipmap
// (68-235 ms). The already-proven KTX2 path serves the same material in 87 ms.
//
// Source ranking is UNCHANGED apart from the new rung:
//   user PNG > managed KTX2 > BAKED KTX2 > bundled PNG > stock.
// The baked tier replaces the BUNDLED PNG tier and therefore carries the bundled tier's
// gates: the base swap follows `recharged_textures`, the companion maps follow the master
// (exactly like lookup()/resolve_suffixed()). It is INERT unless the GPU's PREFERRED PROFILE is
// the ASTC one — not merely unless the GPU can read ASTC, which a desktop GL 4.6 driver also
// advertises (measured 2026-08-26: 28 `custom texture BAKED` lines in an x86 run, against what
// this comment used to claim). With the profile gate the desktop path is what it was.
std::optional<managed_assets::CompressedTex> lookup_baked_base(const std::string& tpage_name,
                                                               const std::string& tex_name);
// `map_kind` is the managed-pack spelling ("normal", "roughness", "height", ...); the file on
// disk carries it as a suffix ("<material>_normal.ktx2"). SAME-SOURCE rule: only call this when
// the BASE came from the baked tier.
std::optional<managed_assets::CompressedTex> lookup_baked_map(const std::string& tpage_name,
                                                              const std::string& tex_name,
                                                              const char* map_kind);
// At least one baked material indexed AND a GPU that reads ASTC.
bool baked_available();

#ifdef OG_FEAT_PBR
// Grecharged-pbr-materials: look up a replacement PNG whose NAME part carries a
// suffix (e.g. "_normal"), reusing the same index/scan as lookup(). The returned
// pointer is backed by a per-call thread-local buffer; it is valid only until the
// next lookup_suffixed() call on this thread (add_texture consumes it immediately).
const ReplacementImage* lookup_suffixed(const std::string& tpage_name,
                                        const std::string& tex_name,
                                        const char* suffix,
                                        BaseSource base_src);

// Existence-only probe for a suffixed map. Same key construction, same source gating and
// same-source pairing rule as lookup_suffixed(), but it stops at the index: no file read, no
// PNG decode. Used by the pre-subdivision pass to bound itself to surfaces that actually have
// a displacement source.
bool has_suffixed(const std::string& tpage_name,
                  const std::string& tex_name,
                  const char* suffix,
                  BaseSource base_src);

// Grecharged-pbr-materials: registry mapping a texture debug-name to its extra
// PBR material GL textures. GL ids, 0 = absent.
struct PbrMaterialMaps {
  u32 normal_tex = 0;
  u32 rough_tex = 0;
  u32 metal_tex = 0;
  u32 ao_tex = 0;
  u32 height_tex = 0;  // <tex>_height.png — drives parallax occlusion mapping
  // Grecharged-pbr-realtime-fusion (owner: "faut câbler specular et emissive aussi"):
  u32 specular_tex = 0;  // <tex>_specular.png — F0 / specular color (specular workflow)
  u32 emissive_tex = 0;  // <tex>_emissive.png — unlit self-illumination, added on top
  // MEAN tangent-space surface gradient (n.xy / n.z, per-texel clamp +-4) of <tex>_normal.png,
  // measured over every texel when the map is decoded. Non-zero means the map carries a constant
  // TILT rather than pure relief; the shader subtracts it so the perturbation is zero-mean (see
  // tfrag3.frag u_pbr_normal_dc — a non-zero DC was the owner's hard brightness-plate defect).
  float normal_dc_x = 0.f;
  float normal_dc_y = 0.f;
  // HEIGHT-MAP STATISTICS of <tex>_height.png's red channel, measured over every texel when the
  // map is decoded. The shipped height maps are NEITHER normalised NOR mean-centred: measured on
  // the 7 bundled maps, vil1-jng-leafyground spans 0.0627..0.4627 (mean 0.3225), vil-wallplaster
  // means 0.8068, vil1-sages-strawroof-01 spans only 0.298..0.478. So the naive (h - 0.5) both
  // OFFSETS the whole material (net-inward for a dark map, net-outward for a bright one) and
  // wastes most of the nominal amplitude (only 18-75% of it is ever used). These two numbers let
  // the shader recentre and rescale per material: (h - height_mean) * height_norm + 0.5 refills
  // 0..1 around the material's own mid. The defaults (0.5, 1.0) are the IDENTITY transform.
  float height_mean = 0.5f;  // mean of <tex>_height.png's red channel, 0..1
  float height_norm = 1.0f;  // 0.5 / robust half-range; (h-mean)*norm+0.5 refills 0..1
  // ROUND 20: characteristic feature WAVELENGTH of the height field, in TILES (1 tile = the whole
  // texture). Measured at load from the map's own mip-energy spectrum. x the material's world tile
  // size = the feature's world size, which is what the tessellation amplitude is scaled by.
  float height_lambda_tiles = 0.25f;

  // ===== Grecharged-materials-modern-parity — THE MODERN MATERIAL STACK ============================
  // Everything below is per-material and OPT-IN. `mm_flags == 0` (the default) means this material
  // is untouched by the modern layer no matter what the menu says, which is how "OFF == stock"
  // stays true per material and not just globally.
  //
  // The eight fields above are all MEASURED from the PNGs at load. These are AUTHORED: they are
  // read from `surfaces.json` (see mm_params_reload), because a scattering colour or a coat weight
  // is an artistic decision about the surface, not a statistic of its texture. That file is
  // authored in the ASSET repository and installed under managed_assets/<game>/, never shipped in
  // the APK (owner, 2026-08-29), with an external-dir copy taking precedence so re-tuning costs a
  // kilobyte push instead of a 581 MB APK.
  u32 thickness_tex = 0;  // <tex>_thickness.png — 1 = thin/translucent, 0 = optically thick
  // TRUE when this material's occlusion/roughness/metallic were unpacked from one _orm.png. Kept as
  // its own field rather than as a bit inside mm_flags because mm_flags is REBUILT from scratch on
  // every re-stamp (and cleared to 0 whenever the master is off), so a bit living only there would
  // be lost the first time the owner toggled the row off and on again. Anything derived from the
  // TEXTURES has to be recoverable from the textures.
  bool orm_packed = false;
  u32 mm_flags = 0;  // capability bits, see pbr_modern_uniforms.glsl (1 sss, 2 coat, 4 aniso,
                     // 8 energy, 16 spec-occlusion, 32 thickness map, 64 filmic, 128 ORM).
                     // Derived, never authored directly: mm_apply_params() rebuilds it from the
                     // surfaces.json record ORed with the texture-derived bits it recomputes from
                     // thickness_tex / orm_packed.
  float sss_color[3] = {1.f, 1.f, 1.f};  // scattering colour, LINEAR
  float sss_strength = 0.f;
  float sss_thickness = 0.5f;  // fallback when no _thickness.png
  float sss_power = 6.f;       // transmission falloff
  float sss_distort = 0.2f;    // normal distortion of the transmission vector
  float sss_wrap = 0.f;        // terminator wrap
  float sss_ambient = 0.25f;   // share of skylight that also transmits
  float coat_weight = 0.f;
  float coat_rough = 0.10f;
  float aniso = 0.f;        // [-0.95, 0.95]
  float aniso_angle = 0.f;  // radians

  // ===== Gpbr-per-texture-materials — LES BOUTONS DE MATIERE DU CHEMIN PBR LUI-MEME ==============
  // Contrairement au bloc mm_* ci-dessus, ceux-ci ne sont PAS derriere la ligne de menu MODERN
  // MATERIALS : relief, rugosite, metallicite, reflectance et le signe du canal vert de la normal
  // map sont les parametres du chemin PBR, qui est actif par defaut. Les mettre derriere une ligne
  // eteinte par defaut rendrait tout preset INERTE — le defaut « unite feature-gatee ».
  // CHAQUE DEFAUT CI-DESSOUS EST L'IDENTITE : un materiau sans enregistrement dans surfaces.json
  // rend exactement ce qu'il rendait avant cette phase (les multiplicateurs valent 1, et les
  // valeurs absolues reproduisent au bit pres les constantes que le shader portait en dur).
  float pm_relief = 1.f;          // multiplie la force de la normal map (globale x celui-ci)
  float pm_relief_depth = 1.f;    // multiplie la profondeur parallaxe/displacement
  float pm_relief_lambda = 0.f;   // > 0 remplace la longueur d'onde MESUREE height_lambda_tiles
  float pm_spec = 1.f;            // multiplie l'intensite speculaire
  float pm_rough_nomap = 0.9f;    // rugosite quand AUCUNE _roughness n'est liee (constante shader)
  float pm_rough_scale = 1.f;     // multiplie la _roughness liee
  float pm_metal_nomap = 0.f;     // metallicite quand AUCUNE _metallic n'est liee
  float pm_metal_scale = 1.f;     // multiplie la _metallic liee
  float pm_reflectance = 0.04f;   // F0 dielectrique (la constante 0.04 du shader)
  float pm_normal_y = 1.f;        // +1 = normal maps vert-en-haut (OpenGL), -1 = vert-en-bas (DX)
  bool pm_authored = false;       // un enregistrement de surfaces.json a nomme ce materiau

  // Grecharged-managed-assets: the normal map came from a GPU-compressed pack and stores only
  // X/Y (BC5 / EAC RG11 / ASTC two-channel). Sets u_pbr_mode bit 128 so the shader rebuilds Z.
  // PNG-sourced maps are 3-channel and leave this false.
  bool normal_is_rg = false;
};

// ===== Gpbr-material-props — surfaces.json =========================================================
// Per-material AUTHORED parameters. The table is authored in the ASSET repository and published as
// a release extra, so the GAME repo (and therefore the APK) carries none of it. Two sources, first
// hit wins: <external recharged assets dir>/surfaces.json (the owner's kilobyte-push override) then
// managed_assets/<game>/surfaces.json (what the asset manager installed). Shape:
//
//     { "schema_version": 1, "game": "jak1",
//       "families": { ... },            // authoring/tooling only, the engine ignores it
//       "defaults": { ... },            // optional, same shape as a material record
//       "materials": {
//         "village1-vis-tfrag/vil-beach-01": {
//            "family": "sand", "relief_depth": 0.8, "roughness": 0.95, ... } } }
//
// Keys are the engine replacement key "<tpage>/<name>". EVERY property key is optional and an
// absent one leaves the field at its struct default, which is the identity — so an empty record and
// no record at all behave the same. `defaults` applies to every material that carries PBR maps and
// is not named. A schema_version other than 1 loads NOTHING; unknown keys are reported and skipped.
//
// mm_params_reload() re-reads the file and bumps the generation counter; it is called at first use
// and whenever the MODERN MATERIALS menu row is toggled (kmachine's pc_set_modern_materials).
// Materials already registered are re-stamped in place, so a toggle applies edits without a level
// reload.
// True when the MODERN MATERIAL STACK is live: the menu row ANDed with the Recharged master,
// overridable by debug.opengoal.mm.on / OG_MM_ON for the headless harness (which has no menu to
// navigate). Every consumer must ask THIS, never the gfx field directly, or the override splits.
bool mm_master_active();
// ASK for a re-read. Callable from ANY thread (kmachine's pc_set_modern_materials runs on the GOAL
// kernel thread when the menu row is toggled) because all it does is set an atomic flag. The actual
// re-read — which mutates the material registry the renderers walk — is serviced on the GL thread by
// mm_service_reload(). Doing the parse where the request comes from would race a level load:
// register_pbr_material() is a GL-thread writer into the same map.
void mm_request_params_reload();
// GL THREAD ONLY. Performs a pending re-read, if one was requested. Called once per frame from
// PbrDrawBinder::begin(), which is already the GL-thread entry point for everything PBR.
void mm_service_reload();
// GL THREAD ONLY. Re-read surfaces.json and re-stamp every registered material now.
void mm_params_reload();
// Stamp the authored parameters (and the "defaults" fallback) onto a freshly-built material. Called
// by the loader right before register_pbr_material(). No-op when the modern master is off, which is
// what keeps an un-toggled build bit-identical.
void mm_apply_params(const std::string& tex_debug_name, PbrMaterialMaps* maps);
// Gpbr-per-texture-materials. Stamp the PBR-path material knobs (pm_* above) from the SAME
// surfaces.json records. Called from the same two sites as mm_apply_params — but with NO gate: the
// PBR path is on by default, so gating these on the MODERN MATERIALS menu row would make every
// preset inert. Parses the file on first use if nobody has yet. A material the file does not name
// keeps the pm_* defaults, which ARE the pre-phase behaviour.
void pbrmat_apply_params(const std::string& tex_debug_name, PbrMaterialMaps* maps);

// ===== Gpbr-props-reach-draw ====================================================================
// VRAI quand surfaces.json NOMME ce materiau exactement, ou via l'index de noms nus uniques
// (surf_resolve_key). Le bloc optionnel `defaults` est DELIBEREMENT ignore ici : `defaults` est un
// repli pour des matieres qui portent deja des cartes, et le laisser repondre VRAI ferait de CHAQUE
// texture du jeu une matiere authoree — des milliers d'entrees vides inscrites au registre.
bool pbrmat_has_record(const std::string& tex_debug_name);

// ===== Gpbr-props-reach-draw — LE RECENSEMENT « LA PROPRIETE ATTEINT-ELLE UN DRAW » ==============
// Owner 2026-08-31 : « ça applique le PBR uniquement aux 7 textures PBR qui étaient dans le projet
// depuis un bail et ça ignore les autres ». Le defaut est INVISIBLE par construction : chaque defaut
// de la table EST l'identite, donc une matiere dont les proprietes ne sont jamais deposees rend
// exactement ce que rend une matiere correctement authoree par defaut. Il n'existe aucun message
// « aucune correspondance » a chercher. La seule reponse est de publier la resolution de CHAQUE
// matiere rencontree, absences comprises.
//
// TROIS temps, et ils sont separes exprès :
//   note_seen()   : appele AVANT la sortie anticipee du binder, des que le registre a rendu une
//                   entree pour la texture de ce draw. Une matiere resolue puis ignoree est donc
//                   comptee comme RENCONTREE avec params_deposes = 0 — la forme exacte du defaut.
//   note_pushed() : appele APRES glUniform, et il ne stocke PAS ce qu'on a voulu ecrire : il stocke
//                   ce que `glGetUniformfv` RELIT DANS L'OBJET PROGRAMME. Une valeur relue du
//                   programme que le draw suivant utilise n'est pas une variable a nous.
//   note_draw()   : un bind portant une matiere poussee, immediatement avant que l'appelant emette
//                   son draw. COMPTE CPU : il ne prouve pas qu'un fragment a tourne, et la ligne
//                   NOTE de la section le dit.
// `needs_probe()` borne le cout : `glGetUniformfv` est une requete SYNCHRONE qui draine le pipeline
// du pilote (cf. le commentaire glGetFloatv de LoaderStages.cpp:270 — 8 blocages de 1,2 a 2,1 s
// quand il tournait par texture). Il ne tourne donc qu'UNE FOIS par materiau, jamais par draw.
bool pbr_reach_needs_probe(const std::string& key);
void pbr_reach_note_seen(const std::string& key, const PbrMaterialMaps& maps);
void pbr_reach_note_pushed(const std::string& key,
                           const float* mat_readback,   // 4 floats relus de u_pbr_mat, ou nullptr
                           const float* mat2_readback,  // 2 floats relus de u_pbr_mat2, ou nullptr
                           int mode);
// Meme contrat que note_pushed, pour la MOITIE MODERNE : clearcoat et aniso ne voyagent pas dans
// u_pbr_mat mais dans u_mm_coat / u_mm_aniso, poussees par un bloc separe. Sans cette relecture
// leurs valeurs publiees seraient recopiees de nos variables, c'est-a-dire mesurees par leur
// EFFET SUPPOSE — et quand l'effet est absent « le modele est faux » et « rien n'a ete pousse »
// deviennent indistinguables. Appelee HORS de la garde de changement d'etat du binder : la garde
// evite de RE-pousser, elle ne change pas ce que l'objet programme contient, donc la relecture est
// valide meme pour un draw qui n'a rien repousse.
void pbr_reach_note_mm(const std::string& key,
                       const float* coat_readback,   // 4 floats de u_mm_coat, ou nullptr
                       const float* aniso_readback,  // 2 floats de u_mm_aniso, ou nullptr
                       int mm_flags);
void pbr_reach_note_draw();
// Avance quand une matiere NOUVELLE apparait ou qu'une matiere passe a « poussee », pour que
// l'ecrivain de diag re-emette le fichier. Jamais par draw.
u32 pbr_reach_generation();
// Les lignes PBRREACH / PBRVAL. Vide tant qu'aucune matiere n'a ete rencontree.
std::string pbr_reach_section();
// STATE-PUSH COUNTER. NOT a draw counter, and NOT evidence that the modern chunk executed.
// It is called from INSIDE PbrDrawBinder::set()'s state-change guard
// (`if (mm_want != m_cur_mm_flags || mm_key != m_cur_mm_maps)`), so it ticks once per MATERIAL
// TRANSITION: 50 consecutive draws sharing one material count 1, not 50. It also fires on the CPU
// at uniform-bind time, before any fragment runs — a bind whose draw is later scissored or
// depth-killed, or whose modern chunk is skipped by the `u_pbr_debug == 0` gate of
// pbr_modern.glsl:40, still increments it. Read it as "how many times the modern uniform block was
// re-pushed", never as "how many draws entered the modern chunk". Per channel because SSS and
// clearcoat opt in independently.
void mm_note_active_draw(int flags);
// BIND COUNTER. Called on EVERY PbrDrawBinder::set() bind, OUTSIDE the state-change guard, so it
// counts the real PBR binds: `total` for all of them, `flagged` for those carrying a non-zero
// mm_flags. The gap between `flagged` here and mm_note_active_draw's total IS the state-reuse rate
// (equal = every bind changed material; flagged >> pushes = the binder is coalescing). Like the
// counter above it fires on the CPU, so it proves a bind happened, never that a fragment ran.
void mm_note_bind(int flags);
// One line per material with a non-zero mm_flags, then the counts line, then a NOTE line spelling
// out what those counts do NOT prove. Emitted UNCONDITIONALLY: an OFF leg publishes explicit zeros
// instead of going silent, because a missing line is indistinguishable from an uncompiled block or
// a stale file.
std::string mm_params_diag_section();

// Registry key for a texture's PBR maps. Keyed on "<tpage>/<name>", NOT the
// bare debug name: two textures can share a name across tpages (the base
// lookup has always used the full key), and a bare-name registry let the
// second registration delete the first material's maps out from under it.
inline std::string pbr_material_key(const std::string& tpage_name, const std::string& tex_name) {
  return tpage_name + "/" + tex_name;
}

// Register (overwrite) the PBR maps for a texture. Returns the PREVIOUS entry by
// value (all-zero if none) so the caller can glDeleteTextures the old GL ids on a
// level-reload path.
PbrMaterialMaps register_pbr_material(const std::string& tex_key, const PbrMaterialMaps& maps);

// Look up the registered PBR maps for a texture, or nullptr if none.
const PbrMaterialMaps* find_pbr_material(const std::string& tex_key);

// Remove a texture's entry and return its maps so the caller can free the GL
// ids (level unload). All-zero when nothing was registered. Without this the
// companion maps of an evicted level stayed resident for the whole session.
PbrMaterialMaps release_pbr_material(const std::string& tex_key);

// Grecharged-pbr-realtime-fusion 2026-07-26, [pom] DEVICE DIAGNOSTIC. The owner and the
// supervisor both asked the same question about the flat parallax — "is the POM branch even
// executed on this draw, and what is the FINAL offset after every cap, in UV and in world cm?".
// The shader cannot answer it (no printf on GLES), so the CPU mirrors the exact same amplitude law
// per material and dumps it into the pullable pbr_tan_diag.txt. The renderers call
// pbr_pom_diag_note() as they resolve a level's materials (they own the measured UV density,
// which is geometry-derived and therefore not part of PbrMaterialMaps); the kernel's diag writer
// calls pbr_pom_diag_section() to render the block. This is diagnostics only — nothing here is
// read by the render path.
void pbr_pom_diag_note(const std::string& tex_debug_name,
                       const PbrMaterialMaps& maps,
                       float uv_per_m);
// Bumped every time a note() actually changes the recorded set, so the diag writer can tell that
// a level load brought new materials in and re-emit the file (it is otherwise only written when
// the isolate carousel moves, which happens before any level is loaded).
u32 pbr_pom_diag_generation();
// The rendered "[pom]" block, one line per PBR-bound material plus a summary line. Empty string
// when nothing has been noted yet.
std::string pbr_pom_diag_section();

// Grecharged-pbr-realtime-fusion ROUND 21, [cover] DISPLACEMENT COVERAGE counters. The owner's
// bug B is "des chunks entiers (LA PLUPART) sont juste PLATS": the question is not whether the POM
// law is right, it is WHICH PBR-bound draws receive ANY displacement at all. These counters answer
// it with numbers instead of eyeballs: every draw that binds a PBR material is classified, once,
// at the bind site (PbrDrawBinder::set) into exactly one displacement bucket. Counted per frame and
// snapshotted at the frame boundary, so the dump always reports one complete frame.
//   frame_idx  : SharedRenderState::frame_idx — used to detect the frame boundary.
//   renderer   : the renderer that owns the draw, a STRING LITERAL ("tfrag"/"tie"); the pointer is
//                stored, so it must have static storage duration.
//   tree_kind  : optional sub-label with the same lifetime rule (tfrag3::tfrag_tree_names[kind]);
//                nullptr when the caller has no cheap tree kind.
//   has_height : this draw has a height map bound (u_pbr_mode bit 16).
//   disp_tess  : the draw is rendered by the TFRAG3_TESS program AND the tess-eval displacement
//                gate is open (real vertex displacement).
//   disp_pom   : the draw is rendered by a non-tess program AND the fragment POM gate is open.
// Both false with has_height = the "flat chunk" bucket. Callers own the gate mirroring (the
// effective height scale / bisect / debug values live on the GL side).
void pbr_coverage_note_draw(u64 frame_idx,
                            const char* renderer,
                            const char* tree_kind,
                            bool has_height,
                            bool disp_tess,
                            bool disp_pom);
// Advances every ~300 completed frames once counting has started, so the diag writer re-emits the
// file with live coverage numbers without doing per-frame disk I/O.
u32 pbr_coverage_generation();
// The rendered "[cover]" block. Empty string until one full frame has been counted.
std::string pbr_coverage_section();
#endif

// Force a rescan of the replacements directory on the next lookup().
void invalidate();

// Key-dump helper: when the marker file <root>/custom_assets/dump_keys exists,
// append the "tpage/name" key for every texture seen to texture_keys_dump.txt
// (deduped). No-op otherwise.
void dump_key(const std::string& tpage_name, const std::string& tex_name);

}  // namespace custom_tex
