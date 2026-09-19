#pragma once

// water-ocean-mesh (SPEC-refonte-eau §5.3, §8) — LA CLIPMAP QUI REMPLACE LE MICROCODE VU1.
//
// CE QUE FAIT CE MODULE. Sous `recharged_water`, les buckets 4 (OCEAN_MID_AND_FAR) et 63
// (OCEAN_NEAR) consomment leur DMA exactement comme avant mais n'emettent plus un seul
// `glDrawElements` : les renderers de Naughty Dog restent VIVANTS, ils avancent le flux, tiennent
// l'ASSERT de fin de bucket et posent le meme etat GL. A leur place, a la position du bucket 63
// (la passe W2a de la SPEC — apres tous les opaques et tous les alphas, la ou la profondeur de
// scene est enfin lisible), ce module dessine une clipmap de trois anneaux deplacee en vertex par
// la houle cuite de Naughty Dog.
//
// CE QU'IL NE FAIT PAS. Aucun modele de lumiere, aucun rivage, aucune ride, aucune physique.
// « Shading provisoire = l'actuel » : le fragment echantillonne la texture d'ocean que ND produit
// deja et la fond vers `far-color`. Les items 2 a 10 de la SPEC prennent la suite.
//
// L'INTERRUPTEUR. Une seule porte, `ocean_recharged_enabled()`, consultee par les trois sites.
// Elle compose `recharged_gating::on(kWater)` (master > eau) avec l'armement du harnais : desarme, le
// binaire redevient celui de Naughty Dog dans la MEME scene, ce qui est exactement ce que
// `proof_run.sh --off` doit pouvoir montrer.

#include <array>
#include <vector>

#include "common/common_types.h"

#include "game/graphics/opengl_renderer/BucketRenderer.h"

// La porte unique. Vraie quand la clipmap doit remplacer l'ocean d'origine.
bool ocean_recharged_enabled();

class OceanRecharged {
 public:
  static OceanRecharged& get();

  // Appele au debut du bucket 63 Jak1, meme desactive ou vide.
  void begin_near_frame(bool active);

  // Appele par OceanNear apres le decodage VIF du bucket 63 : `ocean-near-add-heights` y a pousse
  // les 4096 octets de `*ocean-heights*` (2 x 2048), les 1024 flottants MEMES que
  // `ocean-get-height` lit. C'est la capture de la couche A.
  void note_layer_a(const void* heights_4096_bytes);

  // Appele par OceanTexture quand elle vient de produire la texture d'ocean de cette image.
  void note_ocean_texture(u32 gl_texture);

  // Appele a la fin du bucket 63, apres que le renderer ND a fini de consommer son DMA.
  void draw(SharedRenderState* render_state, ScopedProfilerNode& prof);

  // --- LE COMPARATEUR RASTER ND/CLIPMAP (defaut 4 de l'arbitrage owner du 16/09) -------------
  // « Mesurer par niveau et par cellule l'emprise de l'eau DESSINEE contre celle de l'origine :
  // aucun pixel d'eau la ou l'origine n'en dessine pas. » L'oracle n'est pas une seconde lecture
  // des masques — ce serait un miroir de la decoupe qu'il juge — mais les SOMMETS que l'emulation
  // du microcode VU1 de Naughty Dog produit deja chaque image aux buckets 4 et 63. Sous
  // `recharged_water` leur `glDrawElements` est supprime, mais tout le calcul tourne : la
  // hierarchie mid/trans/near, les triangles ADC et l'attenuation de houle sont dedans, et aucun
  // n'est calcule par notre code.
  //
  // DEUX MOITIES DANS LA MEME IMAGE : le mid arrive au bucket 4, le near et la clipmap au 63.
  // L'armement se decide donc au 4, avant que quoi que ce soit ne soit rasterise.
  void census_begin_frame(SharedRenderState* render_state);
  void census_capture_nd(SharedRenderState* render_state, const u32* indices, u32 index_count);

  // LA REPRISE DU GRAPHE D'ORIGINE, DECIDEE UNE SEULE FOIS PAR IMAGE (defaut B du 17/09).
  //
  // « sur le title screen l'eau est noire (c'est bon une fois en jeu) ». Le survol du titre
  // affiche village1 (title-obs.gc:696) depuis une camera haute ; au-dela de 48 m d'altitude
  // `draw-ocean` n'insere plus le bucket 63 (ocean.gc:550), donc aucune houle n'est captee,
  // donc `draw()` sort sans poser un pixel. La suppression de l'ocean d'origine, elle, ne lisait
  // que le drapeau (`OceanMidAndFar.cpp:67`) : le quad `far-color` qui remplit l'horizon etait
  // efface sans remplacant, et le niveau `title` n'a pas de ciel (`level-info.gc:2318`) — il
  // reste la couleur d'effacement, c'est-a-dire le noir.
  //
  // Le graphe d'origine n'est donc plus efface QUE si la clipmap va vraiment dessiner a sa
  // place. La decision se prend au bucket 4, le premier des deux, pour que le mid, le quad far
  // et le near soient d'accord dans la MEME image ; `close_frame` est passe par le bucket 63,
  // qui la referme. Un bucket 4 vide (tag CALL, OceanMidAndFar.cpp:53) la laisse prendre au 63.
  bool takeover_decision(bool close_frame);

 private:
  OceanRecharged() = default;

  struct Ring {
    float step;         // unites GOAL par cellule
    int hole_half;      // demi-trou central, en cellules (0 = pas de trou)
    u32 index_offset;   // en indices, dans l'IBO commun
    u32 index_count;
    float center[2];    // centre monde xz, snappe au pas
  };

  bool ensure_gl();
  void census_draw_alpha(u32 program);
  bool refresh_ocean_map();
  void rebuild_mask_texture();
  void run_probe(SharedRenderState* render_state);
  bool wave_readback(SharedRenderState* render_state,
                     float ox,
                     float oz,
                     float step,
                     int side,
                     std::vector<float>* out);
  void run_wave_probe(SharedRenderState* render_state);
  void run_band_probe(SharedRenderState* render_state);
  float shore_cells_cpu(float wx, float wz) const;
  bool ensure_census_gl();
  void census_draw_rings(SharedRenderState* render_state, u32 program, int target, int regime);
  void census_read_and_count();
  void publish();

  // --- geometrie ---------------------------------------------------------------------------
  // 129 x 129 coordonnees de grille entieres partagees par les TROIS anneaux : seuls le pas et le
  // centre changent, par uniforme. Trois plages d'indices decoupent le trou central de chacun.
  static constexpr int kGridCells = 128;
  static constexpr int kGridVerts = kGridCells + 1;
  static constexpr int kNumRings = 3;

  bool m_gl_ready = false;
  bool m_gl_failed = false;
  u32 m_vao = 0;
  u32 m_vbo = 0;
  u32 m_ibo = 0;
  std::vector<u32> m_soft_indices;
  Ring m_rings[kNumRings] = {};

  // --- couche A ----------------------------------------------------------------------------
  std::array<float, 1024> m_layer_a = {};
  bool m_accept_layer_a = false;
  bool m_have_layer_a = false;
  bool m_layer_a_fresh = false;
  u32 m_layer_a_map_ptr = 0;  // carte associee a la derniere capture au draw
  u32 m_tex_layer_a = 0;

  // --- carte ND ----------------------------------------------------------------------------
  u32 m_map_ptr = 0;           // adresse GOAL de l'`ocean-map` courante
  u32 m_mask_map_ptr = 0;      // celle dont la texture de masque a ete construite
  u32 m_tex_mask = 0;

  // --- LA RAMPE DE RIVAGE (reprise du 19/09) ------------------------------------------------
  // La transformee en distance du masque near : pour chaque cellule de 3 m, la distance a la
  // cellule de terre la plus proche, en 1/32 de cellule, saturee a 255 (7,97 cellules). Elle
  // remplace l'extinction a 24 m de la camera comme borne de la houle VISUELLE : une riviere est
  // etroite, donc plate ; la mer est large, donc elle garde son relief a toute distance de
  // l'oeil. La copie CPU sert aux sondes — elle dit aussi, par `> 0`, quelles cellules portent de
  // l'eau, ce que les sondes ne consultaient pas jusqu'ici.
  static constexpr float kShoreCells = 5.f;  // LA MEME valeur que `OCEAN_SHORE_CELLS` du chunk
  u32 m_tex_shore = 0;
  std::vector<u8> m_shore;  // 1536 x 1536, 1/32 de cellule
  u64 m_shore_land_cells = 0;
  u64 m_shore_open_cells = 0;  // cellules d'eau a plus de kShoreCells du rivage
  float m_time_s = 0.f;        // l'horloge de la couche B, secondes
  float m_start_corner[4] = {0, 0, 0, 0};
  float m_far_color[4] = {0, 0, 0, 0};
  u32 m_ocean_texture = 0;

  // --- sonde de controle -------------------------------------------------------------------
  static constexpr int kProbeSide = 8;
  static constexpr int kProbeCount = kProbeSide * kProbeSide;
  static constexpr int kProbeEveryFrames = 30;
  u32 m_probe_fbo = 0;
  u32 m_probe_tex = 0;
  float m_probe_xz[kProbeCount][4] = {};

  // --- verdict C du 17/09 : « LES VAGUES RESTENT DES VAGUES » -------------------------------
  //
  // CE QUI EST COMPARE, ET A QUOI. L'owner : « avant cette reprise les vagues ressemblaient plus
  // a des vagues ». Le contrat nomme la reference : le binaire d'AVANT water-ocean-mesh, dont
  // l'eau est celle de Naughty Dog. La grandeur de reference est donc la houle de ND — la table
  // `*ocean-heights*` captee au DMA du bucket 63 — lue a SA PROPRE resolution (ses noeuds, tous
  // les 3 m) et attenuee par SA PROPRE loi. La grandeur mesuree est le deplacement que NOTRE
  // surface produit vraiment, relu du GPU au pas de l'anneau 0 (0,75 m) par `ocean_wave.frag`.
  //
  // CE QUE CETTE PORTE NE JUGE PAS : la loi d'attenuation elle-meme, qui est le contrat de
  // l'item (« la houle reste celle de Naughty Dog ») et qui est commune aux deux cotes. Ce
  // qu'elle juge : que le maillage livre RESOLVE le relief que la donnee de ND porte. Un pas
  // trop grossier, un masque trop large, une attenuation appliquee deux fois, une couche A
  // perdue : tout cela fait tomber le rapport, et c'est exactement ce que « plus plate » veut
  // dire. Les deux cotes n'echantillonnent PAS les memes points — les noeuds de ND sont ceux de
  // sa table, les notres ceux de l'anneau snappe a la camera — donc un rapport de 1,000 exact
  // serait la signature d'un miroir, pas d'un accord.
  static constexpr int kWaveSide = 61;        // 60 cellules de l'anneau 0 : 45 m autour de la
  static constexpr int kWaveCount = kWaveSide * kWaveSide;   // camera, dans la portee de 24 m ou
  static constexpr int kWaveCmpSide = 16;     // l'attenuation ND laisse encore de la houle.
  static constexpr int kWaveCmpStride = 4;    // 16 noeuds tous les 4 x 0,75 m = 3 m : la MEME
                                              // fenetre de 45 m que la reference, au MEME pas
  static constexpr int kWaveCtrlSide = 6;     // temoin d'echelle : la MEME surface, relue
  static constexpr int kWaveCtrlStride = 12;  // tous les 9 m
  u32 m_wave_fbo = 0;
  u32 m_wave_tex = 0;
  u64 m_wave_runs = 0;            // passes de sonde de houle
  u64 m_wave_runs_compared = 0;   // passes ou la houle de ND n'etait pas plate
  u64 m_wave_texels_missing = 0;  // texels sans fragment : une cible partielle ne se compare pas
  u64 m_wave_flat_runs = 0;       // passes ou NOTRE relief tombe sous 90 % du sien
  u64 m_wave_ratio_amp_min_x1000 = 0;   // LA PORTE : notre surface TELLE QU'ELLE EST DESSINEE
  u64 m_wave_ratio_nvar_min_x1000 = 0;  // (0,75 m) contre celle de ND telle qu'elle l'est (3 m)
  u64 m_wave_ratio_amp_sub_min_x1000 = 0;   // publie, PAS juge : notre surface RAMENEE a 3 m.
  u64 m_wave_ratio_nvar_sub_min_x1000 = 0;  // Biais connu, voir `water_waves_scope`.
  s64 m_wave_amp_sub_q256 = 0;
  u64 m_wave_nvar_sub_x1e6 = 0;
  u64 m_wave_slope_sub_x1e6 = 0;
  s64 m_wave_amp_ours_q256 = 0;   // derniere passe comparee, valeurs absolues
  s64 m_wave_amp_nd_q256 = 0;
  u64 m_wave_nvar_ours_x1e6 = 0;
  u64 m_wave_nvar_nd_x1e6 = 0;
  u64 m_wave_slope_ours_x1e6 = 0;
  u64 m_wave_slope_nd_x1e6 = 0;
  u32 m_wave_nodes_ours = 0;
  u32 m_wave_nodes_nd = 0;
  s64 m_wave_amp_full_q256 = 0;   // notre surface a SON pas (0,75 m) : le cote JUGE
  u64 m_wave_nvar_full_x1e6 = 0;
  u64 m_wave_slope_full_x1e6 = 0;
  u32 m_wave_nodes_full = 0;
  s64 m_wave_amp_ctrl_q256 = 0;   // la meme, relue tous les 12 m
  u64 m_wave_nvar_ctrl_x1e6 = 0;

  // --- LE RELIEF PAR BANDE DE DISTANCE (reprise du 19/09) -----------------------------------
  // « publier l'EXCEDENT VISUEL : amplitude et variance de normales de la surface rendue a
  // 30-90 m de la camera, qui doivent etre du MEME ORDRE que celles a 0-24 m (l'original tombe a
  // 0 la-bas : c'est le temoin gratuit) ».
  //
  // UNE SEULE GRILLE POUR LES DEUX BANDES. 121 x 121 au pas de 1,5 m couvre 180 m ; la bande
  // proche est l'anneau r <= 24 m, la bande lointaine 30 m <= r <= 90 m. Les deux sont
  // echantillonnees au MEME pas, sur la MEME image : sans cela le rapport mesurerait la
  // difference de pas d'echantillonnage et non celle de relief — c'est le biais deja nomme par
  // le releve `-sub-` du verdict C.
  //
  // SEULE L'EAU COMPTE. Les deux bandes ne retiennent que les cellules ou le masque near dessine
  // (distance de rivage > 0) : un carre de 180 m dans la jungle est surtout de la terre, et une
  // amplitude relevee sur de la terre ne decrit rien de ce que l'owner voit.
  static constexpr int kBandSide = 121;
  static constexpr float kBandStep = 6144.f;  // 1,5 m
  static constexpr int kBandCount = kBandSide * kBandSide;
  u64 m_band_runs = 0;
  u64 m_band_near_samples = 0;
  u64 m_band_far_samples = 0;
  s64 m_band_near_amp_q256 = 0;
  s64 m_band_far_amp_q256 = 0;
  s64 m_band_near_amp_nd_q256 = 0;
  s64 m_band_far_amp_nd_q256 = 0;
  u64 m_band_near_nvar_x1e6 = 0;
  u64 m_band_far_nvar_x1e6 = 0;
  u64 m_band_near_nvar_nd_x1e6 = 0;
  u64 m_band_far_nvar_nd_x1e6 = 0;
  u64 m_band_far_over_near_amp_x1000 = 0;
  u64 m_band_far_over_near_nvar_x1000 = 0;
  // LA BANDE LOINTAINE AU LARGE : les points de 30-90 m dont la rampe de rivage est SATUREE.
  // C'est la population que le verdict du 19/09 vise vraiment — la mer, pas la riviere — et
  // c'est la seule ou « ce qu'on livre » et « ce que la table de ND contient » se comparent sans
  // que la rampe s'en mele. `gap` est le manque PAR POINT : de combien, au plus, notre surface
  // reste sous la houle que la donnee porte. Le regime de l'essai 9 (extinction ND) y rendait
  // toute l'amplitude ; le regime livre ne peut en perdre que la couche B, 237 mm.
  u64 m_band_far_open_samples = 0;
  s64 m_band_far_open_amp_q256 = 0;
  s64 m_band_far_open_amp_full_q256 = 0;
  s64 m_band_far_open_amp_nd_q256 = 0;
  u64 m_band_far_open_nvar_x1e6 = 0;
  s64 m_band_far_open_gap_max_q256 = 0;
  s64 m_visual_excess_q256 = 0;   // max |livre - ND| sur la bande lointaine
  // La couche B, MESUREE et non declaree : sur les points ou la rampe de rivage est saturee des
  // deux cotes (voisinage 3 x 3 au-dela de kShoreCells + 1), `livre - A` EST la couche B, sans
  // qu'aucune interpolation de texture ne s'y melange.
  u64 m_band_open_samples = 0;
  s64 m_layer_b_measured_q256 = 0;
  // L'EAU RESTE DANS SON LIT : le profil de l'excedent par distance au rivage, en cellules de
  // 3 m. `_before` est le regime du 10/09 (houle entiere, sans rampe) calcule aux MEMES points :
  // c'est le controle positif, sans lequel un zero d'excedent ne se distinguerait pas d'une
  // course sans berge en vue.
  static constexpr int kShoreBuckets = 6;  // d<=1, <=2, <=3, <=4, <=5, >5 cellules
  u64 m_shore_bucket_samples[kShoreBuckets] = {};
  s64 m_shore_bucket_excess_q256[kShoreBuckets] = {};
  s64 m_shore_bucket_excess_before_q256[kShoreBuckets] = {};

  // --- comparateur raster d'emprise --------------------------------------------------------
  // 320 x 180 : la cible est rasterisee en CLIP SPACE par les memes shaders que l'ecran, donc
  // c'est l'ecran, reduit. Une cellule vaut 1/57600 de l'image. Une image sur 120 seulement : le
  // relevé coute deux `glReadPixels` de 230 Ko et il n'a rien a gagner a etre pris plus souvent
  // qu'une fois toutes les cinq secondes.
  static constexpr int kCensusW = 320;
  static constexpr int kCensusH = 180;
  static constexpr int kCensusCells = kCensusW * kCensusH;
  static constexpr int kCensusEveryFrames = 120;
  bool m_census_gl_ready = false;
  bool m_census_gl_failed = false;
  bool m_census_armed = false;
  u32 m_census_fbo[2] = {0, 0};
  u32 m_census_tex[2] = {0, 0};
  u32 m_census_ibo = 0;
  u64 m_census_nd_draws = 0;        // rasterisations d'oracle de l'image en cours
  u64 m_fp_runs = 0;
  u64 m_fp_nd_draws = 0;
  u64 m_fp_cells = 0;
  u64 m_fp_nd = 0;
  u64 m_fp_ours = 0;
  u64 m_fp_before = 0;
  u64 m_fp_excess = 0;
  u64 m_fp_deficit = 0;
  u64 m_fp_excess_before = 0;
  u64 m_fp_excess_ring[kNumRings] = {0, 0, 0};
  u64 m_fp_ours_ring[kNumRings] = {0, 0, 0};
  u64 m_fp_excess_before_ring[kNumRings] = {0, 0, 0};

  // --- defaut A du 17/09 : LA TRANSPARENCE, RELEVEE SUR LA SURFACE VISIBLE ------------------
  // Le fragment encode dans le canal A de la cible 1 l'alpha QU'IL VIENT DE CALCULER pour le
  // rendu livre (`ocean_recharged.frag`, u_footprint == 2) : une seule expression, deux lecteurs.
  // 0 = pas d'eau sur la cellule ; 1..255 = alpha, relu a = (v - 1) / 254.
  u64 m_alpha_cells = 0;
  u64 m_alpha_transparent_cells = 0;  // cellules dont l'alpha est sous 0,99
  u32 m_alpha_min_v = 0;              // 0 tant que rien n'a ete mesure
  u32 m_alpha_max_v = 0;

  // --- defaut B du 17/09 : LA REPRISE, ET LE TROU QU'ELLE OUVRAIT --------------------------
  bool m_takeover = false;          // l'ocean d'origine est-il efface pour CETTE image ?
  bool m_takeover_decided = false;  // la decision de l'image a-t-elle deja ete prise ?
  bool m_takeover_blocked = false;  // `draw()` a renonce pour une cause durable : on rend la
                                    // main a l'ocean d'origine au lieu de laisser un trou
  u64 m_takeover_frames = 0;           // images ou la clipmap a pris la place de l'origine
  u64 m_takeover_declined_frames = 0;  // images ou l'origine a ete LAISSEE dessiner
  u64 m_blackout_frames = 0;           // images ou l'origine etait effacee et ou NOUS n'avons
                                       // rien dessine : le trou noir, qui doit rester a zero
  u64 m_tex_ocean_zero_frames = 0;     // images dessinees sans texture d'ocean liee

  // --- temoin de couverture de l'attenuation (defaut 1) ------------------------------------
  // Ce que l'attenuation ND RETIRE aux points de la sonde, en 1/256 d'unite GOAL. Ce n'est PAS
  // une porte de fidelite — la formule est la meme des deux cotes — mais le temoin qu'une course
  // contient bien des points au-dela de 24 m portant une houle non plate : sans lui, un zero
  // d'excedent ne se distinguerait pas d'une course ou l'attenuation n'avait rien a mordre.
  u64 m_atten_points_total = 0;
  u64 m_atten_points_beyond = 0;
  s64 m_atten_removed_max_q256 = 0;

  // --- recensement -------------------------------------------------------------------------
  u64 m_frames_drawn = 0;
  u64 m_frames_layer_a_fresh = 0;
  u64 m_frames_layer_a_stale = 0;
  u64 m_verts_moved = 0;  // indices soumis sur les images a couche A non plate (historique cost)
  u64 m_probe_verts_moved = 0;  // observations de sommets sonde : alpha valide et gpu_q != 0
  u64 m_probe_verts_sampled = 0;  // observations de sommets sonde a alpha valide
  u64 m_probe_runs = 0;
  u64 m_probe_alpha_missing = 0;
  s64 m_maxdelta_q256 = -1;
  s64 m_probe_span_q256 = 0;
  s64 m_layer_a_absmax_q256 = 0;
  u32 m_layer_a_nonzero = 0;
  // Cellules mid (96 m) et near (3 m), pas des pixels rendus.
  u32 m_mask_near_skip_cells = 0;
  u32 m_mask_near_draw_cells = 0;
  u32 m_mask_invalid_reads = 0;
  u32 m_mask_skip_cells = 0;
  u32 m_mask_draw_cells = 0;
  u32 m_mask_valid_off0 = 0;
  u32 m_mask_valid_off4 = 0;
  u32 m_mask_index_offset = 0;
  u32 m_mask_fallback = 0;

  // --- water-ocean-mesh-hit-counter-cost : LE RECENSEMENT DU RECENSEMENT -------------------
  // Le site de prise de `water-ocean-mesh` (OceanRecharged.cpp, fin de `draw`) portait
  // 4 536 325 248 prises sur une course de 318 s, lues comme « quatorze millions
  // d'incrementations par seconde ». Ce compte est une SOMME PONDEREE, pas un compte d'appels :
  // le site appelait `note_hit_for` UNE fois par image avec `n = 289 824`, le nombre d'INDICES
  // dessines. Les trois compteurs ci-dessous separent enfin les trois grandeurs que ce seul
  // chiffre confondait — appels, unites comptees, evenements reels — et le chronometre mesure ce
  // que l'appel coute vraiment. Il ne tourne QUE sous mesure (meme regle que `LgtSetupScope`,
  // background_common.cpp:1419) : le binaire de l'owner ne paie pas l'instrument qui mesure
  // l'instrument.
  u64 m_hit_calls = 0;     // appels de note_hit_for emis par CE site
  u64 m_hit_units = 0;     // unites passees a ces appels, distinctes des sommets sondes
  u64 m_hit_events = 0;    // evenements observes : images dessinees a couche A non plate
  u64 m_cost_call_ns = 0;  // temps PROCESSEUR passe DANS ces appels
  u64 m_cost_call_ns_max = 0;
  u64 m_cost_scan_ns = 0;   // temps processeur du balayage de la couche A (l'autre moitie)
  u64 m_cost_floor_ns = 0;  // paire d'horloge a vide, prise a la MEME image : le plancher
  u64 m_cost_samples = 0;   // images mesurees
  u64 m_cost_clock_fail = 0;
  u64 m_clock_res_ns = 0;
};
