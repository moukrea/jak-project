#include "Tie3.h"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <unordered_map>

#include "common/global_profiler/GlobalProfiler.h"
#include "common/log/log.h"
#include "common/util/Assert.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/background/MeshBrowserGizmos.h"
#include "game/graphics/opengl_renderer/loader/PbrTestPattern.h"
#include "game/mips2c/spart_prof.h"

#include "third-party/imgui/imgui.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace {
// Grecharged-foliage-wind: live-tunable TIE (palm/foliage) wind-shear multiplier applied on top of the
// stock per-instance wind when the toggle is ON. Mirrors GrassRenderer.cpp's grass_droop_len() dual
// mechanism EXACTLY (cached + throttled with (s_throttle++ & 63) so it isn't re-read every frame):
// Android prop debug.opengoal.foliage.tie_mult / desktop env FOLIAGE_WIND_TIE_MULT. Default 3.0
// (device-tuned at the village1-hut vantage: palms/trees roughly double their motion-energy vs
// stock, gentle not stormy; 8.0 bends palms comically), clamped [1.0, 8.0] (1.0 == neutral ==
// stock arithmetic).
// ROUND 2 MEASUREMENT — this default goes back to 1.0 (neutral), and the reason is the whole
// post-mortem of round 1. The device shear audit says the stock jak1 TIE wind is NOT small:
// bend_rms 0.057-0.077, i.e. a palm crown already displaced ~1.0-1.35 m. What it is, is GLACIAL —
// differencing the applied shear frame to frame gives motion_rms 0.0011, so the shear traverses
// its own magnitude in ~50 frames: an oscillation of 0.04-0.06 Hz, a SEVENTEEN-TO-TWENTY-FIVE
// SECOND period. The palms were never static; they were bent and drifting too slowly to read as
// movement, which is exactly "on voit aucune feuille qui bouge".
// Multiplying that term is therefore the wrong lever twice over: it scales bend and motion
// together, so the frequency — the thing that was broken — is unchanged, and at x3 it bent the
// crown 3.27 m RMS (a storm) while still moving at 0.11 Hz. Per unit of bend, the procedural
// breeze below buys 8.2x more motion than this multiplier does. So: leave the game's own wind
// alone (x1 == stock arithmetic) and get the movement from the term that actually oscillates.
// The knob survives for experiments; it is simply no longer the default answer.
constexpr float FOLIAGE_WIND_TIE_MULT_DEFAULT = 1.0f;
static float foliage_wind_tie_mult() {
  static float s_cached = FOLIAGE_WIND_TIE_MULT_DEFAULT;
  static int s_throttle = 0;
  if ((s_throttle++ & 63) != 0) {
    return s_cached;
  }
  char buf[16] = {0};
  bool have = false;
#ifdef __ANDROID__
  if (__system_property_get("debug.opengoal.foliage.tie_mult", buf) > 0 && buf[0]) {
    have = true;
  }
#else
  const char* e = std::getenv("FOLIAGE_WIND_TIE_MULT");
  if (e && e[0]) {
    std::strncpy(buf, e, sizeof(buf) - 1);
    have = true;
  }
#endif
  float v = have ? (float)std::atof(buf) : FOLIAGE_WIND_TIE_MULT_DEFAULT;
  if (v < 1.0f) v = FOLIAGE_WIND_TIE_MULT_DEFAULT;  // unparsable/zero -> default, never < neutral
  if (v > 8.0f) v = 8.0f;
  s_cached = v;
  return v;
}

// ---------------------------------------------------------------------------------------------
// Grecharged-foliage-wind2 (ROUND 2). Owner verdict on round 1: "on voit aucune feuille qui bouge,
// aucun palmier, nada". Round 1's only lever was MULTIPLYING the stock shear, and the stock shear on
// jak1 foliage is tiny: do_wind_math integrates a spring whose restoring term is cy = 100, so the
// steady-state oscillator settles at |vf17| ~= |drive| / 100 before it is even multiplied by the
// per-prototype `stiffness`. 3x of almost-nothing is still almost-nothing (+9% measured crown
// motion). Round 2 therefore stops scaling the stock term and ADDS two guaranteed-amplitude terms
// whose size does not depend on the level's authored stiffness at all:
//
//   (1) TIE_AMP   - a procedural breeze SHEAR added to the instance matrix (CPU, here). Because the
//                   shear is applied as `row.x += s.x * row.y`, the world displacement of a point is
//                   s * (its height above the instance origin): the base stays planted and the crown
//                   swings. s is DIMENSIONLESS, so 0.055 moves a 10 m palm crown +-0.55 m at the
//                   waveform peak (~+-0.25 m RMS) — a light breeze, not a storm.
//   (2) FROND     - a per-vertex flutter in tie_wind.vert (GPU). The shear above moves a palm
//                   rigidly; leaves only look ALIVE when they deform. The flutter displaces each
//                   vertex by a FRACTION OF ITS OWN HORIZONTAL REACH from the trunk axis, so it is
//                   exactly zero on the trunk, largest at the frond tips, and needs no per-prototype
//                   size data (unit- and scale-invariant). 0.10 moves a 3.5 m frond tip +-0.35 m.
//
// Both are 0 when the toggle is OFF, which leaves the stock arithmetic untouched (the CPU term is
// not added at all and the shader takes the `u_fw_amp > 0.0` branch never).
// Live-tunable with NO rebuild: Android props debug.opengoal.foliage.{tie_amp,frond} / desktop envs
// FOLIAGE_WIND_{TIE_AMP,FROND}.
// ROUND 2 FINAL DEFAULTS, chosen from the device shear audit rather than from taste. Both levers
// are DIMENSIONLESS (a fraction of the object's own size), so they mean the same thing on every
// prototype. Predicted effect on beach's palm-02.mb (17.52 m tall, census-measured), against the
// stock numbers this build measured on the device:
//   TIE_AMP 0.12 -> the breeze contributes bend_rms 0.052 at ~0.52 Hz. Summed with the stock wind
//                   the crown sits at bend_rms 0.081 = 1.42 m, i.e. 8% of the palm's height, which
//                   a palm does in a breeze; and the aggregate oscillation lands at 0.35 Hz (a
//                   ~3 s cycle) against stock's 0.05 Hz. Frame-to-frame motion goes 0.00136 ->
//                   0.0098, SEVEN TIMES the stock wind, while total bend DROPS from round 1's
//                   x3-boosted 0.187 (3.27 m, a storm) to 0.081. More movement, less bending —
//                   which is the actual definition of "légère brise" and the opposite of what
//                   raising a multiplier does.
//   FROND   0.14 -> each crown vertex flutters +-14% of its own lever arm (capped at 4 m and
//                   ramped in with height, see tie_wind.vert), so a frond tip sweeps <= +-0.56 m
//                   at ~0.37/0.59 Hz while the trunk holds still. This is the term that makes
//                   LEAVES read as alive rather than the whole tree read as leaning.
// Both remain live-tunable via props/env with no rebuild, and both are 0 when the toggle is OFF.
// Grecharged-foliage-wind3 (owner 2026-08-31, defaut D3) — « ils bougent comme s'il y avait une
// tempête c'est ridicule ». MESURE avant de toucher au chiffre, sur deux courses du meme binaire :
// la brise AJOUTEE (difference en quadrature de `applied_rms` et `stock_rms` de la meme ligne
// d'audit) valait **0,05362** de cisaillement, soit **1,282 m** de couronne RMS sur `palm-01.mb`
// (23,91 m, la plus haute plante de jak1, hauteur du recensement) — et son mouvement par image
// pesait 4,3 a 12,6 fois celui du jeu lui-meme. C'est la tempete, chiffree.
// CIBLE POSEE AVANT LA COURSE DE VERIFICATION : la brise ajoutee ne deplace pas la couronne de la
// plus haute plante de plus de 0,50 m RMS, soit un cisaillement de 0,0209.
// LIVRE : 0,035 -> **0,01560** mesure, soit **0,373 m**. Les deux niveaux (beach, village1)
// s'accordent a 0,4 % sur 25 fenetres. Facteur 3,44 de reduction.
// `frond` suit la meme division : la pointe d'une fronde balaie au plus 4 m x 0,055 = 0,22 m au
// lieu de 0,56 m (le bras de levier est plafonne a 4 m dans tie_wind.vert, donc la conversion ne
// depend d'aucune donnee de niveau).
constexpr float FOLIAGE_WIND_TIE_AMP_DEFAULT = 0.035f;
constexpr float FOLIAGE_WIND_FROND_DEFAULT = 0.055f;

// Shared reader for the round-2 knobs (same cached + (throttle & 63) discipline as the mult above).
static float foliage_wind_knob(const char* prop, const char* env, float def, float hi, float* cache) {
  char buf[16] = {0};
  bool have = false;
#ifdef __ANDROID__
  (void)env;
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    have = true;
  }
#else
  (void)prop;
  const char* e = std::getenv(env);
  if (e && e[0]) {
    std::strncpy(buf, e, sizeof(buf) - 1);
    have = true;
  }
#endif
  float v = have ? (float)std::atof(buf) : def;
  if (!(v >= 0.0f) || v > hi) {
    v = def;  // unparsable / NaN / out of range -> default
  }
  *cache = v;
  return v;
}

static float foliage_wind_tie_amp() {
  static float s_cached = FOLIAGE_WIND_TIE_AMP_DEFAULT;
  static int s_throttle = 0;
  if ((s_throttle++ & 63) != 0) {
    return s_cached;
  }
  return foliage_wind_knob("debug.opengoal.foliage.tie_amp", "FOLIAGE_WIND_TIE_AMP",
                           FOLIAGE_WIND_TIE_AMP_DEFAULT, 0.30f, &s_cached);
}

static float foliage_wind_frond() {
  static float s_cached = FOLIAGE_WIND_FROND_DEFAULT;
  static int s_throttle = 0;
  if ((s_throttle++ & 63) != 0) {
    return s_cached;
  }
  return foliage_wind_knob("debug.opengoal.foliage.frond", "FOLIAGE_WIND_FROND",
                           FOLIAGE_WIND_FROND_DEFAULT, 0.40f, &s_cached);
}

// ---------------------------------------------------------------------------------------------
// Grecharged-foliage-wind3 (owner 2026-08-31, defaut D2 : « tous les arbres ne sont pas
// impactés ») — L'AMPLITUDE DU BALANCEMENT DU TIE **STATIQUE**, en METRES a la couronne.
//
// Les deux boutons ci-dessus ne touchent QUE le chemin VENT, c'est-a-dire les seules instances que
// l'extracteur a basculees en `instanced_wind_draws` parce que leur prototype porte une raideur
// non nulle. Tout le reste de la vegetation TIE est de la geometrie STATIQUE, sans matrice
// d'instance a l'execution : aucun reglage de ce fichier ne pouvait la faire bouger, et c'est
// exactement « tous les arbres ne sont pas impactés ». Ce bouton-ci pilote le chemin neuf.
//
// HIERARCHIE, ET ELLE EST L'ORDRE DE L'OWNER (« ceux qui n'en ont pas doivent en recevoir une,
// PLUS LEGERE »). Le chemin VENT applique un cisaillement SANS DIMENSION (`tie_amp`, 0,12 par
// defaut) multiplie par la HAUTEUR du sommet au-dessus de l'origine de son instance : sur le
// palmier `palm-02.mb` de la plage (17,52 m, mesure au recensement) cela vaut 0,12 x 17,52 =
// 2,10 m a la crete de la forme d'onde. Ici, 0,10 m, quelle que soit la taille de la plante :
// vingt-et-une fois moins sur ce palmier, et STRICTEMENT MOINS sur toute plante de plus de
// 0,84 m. La comparaison est publiee sur la ligne de preuve, pas seulement affirmee ici.
// Le bouton vit sur le meme patron que `foliage_wind_tie_amp` : prop Android
// debug.opengoal.foliage.tie_sway / env FOLIAGE_WIND_TIE_SWAY, cache + (s_throttle++ & 63), et la
// meme semantique de bornes que le lecteur partage — une valeur illisible, negative ou AU-DESSUS
// de 0,40 m retombe sur le DEFAUT (0,10 m), elle n'est pas rabotee a 0,40. Un doigt qui glisse sur
// le clavier rend donc la brise nominale, jamais une tempete.
// Renvoie des UNITES MONDE (metres x 4096), comme `foliage_wind_shrub_amp`.
constexpr float FOLIAGE_WIND_TIE_SWAY_DEFAULT_M = 0.10f;
constexpr float FOLIAGE_WIND_TIE_SWAY_MAX_M = 0.40f;
static float foliage_wind_tie_sway() {
  static float s_cached_m = FOLIAGE_WIND_TIE_SWAY_DEFAULT_M;
  static int s_throttle = 0;
  if ((s_throttle++ & 63) == 0) {
    foliage_wind_knob("debug.opengoal.foliage.tie_sway", "FOLIAGE_WIND_TIE_SWAY",
                      FOLIAGE_WIND_TIE_SWAY_DEFAULT_M, FOLIAGE_WIND_TIE_SWAY_MAX_M, &s_cached_m);
  }
  return s_cached_m * 4096.0f;  // metres -> unites monde
}

// Breeze clock, in seconds. Deliberately NOT the game's wind_time frame counter: that advances once
// per rendered frame, so on the Redmi (variable fps, often ~30) the whole breeze would run at half
// speed and lose exactly the per-frame motion the eye keys on. A monotonic clock keeps the sway at
// the authored frequency on any device. It is advanced ONCE per frame (render_tree_wind is called
// per tree) and frozen while the game's own wind is paused, so pausing still freezes the foliage.
static float foliage_wind_clock(u64 frame_idx, bool paused) {
  static float s_t = 0.f;
  static u64 s_last_frame = (u64)-1;
  static std::chrono::steady_clock::time_point s_last = std::chrono::steady_clock::now();
  if (frame_idx != s_last_frame) {
    s_last_frame = frame_idx;
    auto now = std::chrono::steady_clock::now();
    float dt = std::chrono::duration<float>(now - s_last).count();
    s_last = now;
    if (dt < 0.f) dt = 0.f;
    if (dt > 0.1f) dt = 0.1f;  // hitch/loading guard: never jump the breeze
    if (!paused) {
      s_t += dt;
    }
  }
  return s_t;
}

// ---------------------------------------------------------------------------------------------
// Grecharged-foliage-wind3 (owner 2026-08-31, defaut D1) — LA BRISE NATIVE, OPTION ETEINTE.
//
// Verbatim : « les arbres qui sont sensés être animés par défaut font de légers twitchs sans
// animations ». Ce n'est pas une amplitude, c'est une CADENCE, et le defaut a deux moities qui se
// tiennent :
//
//   (a) COTE PRODUCTEUR (GOAL). `update-wind` remplit un anneau de 64 vecteurs, un slot par
//       appel. La version « high fps » multipliait l'INDEX D'ECRITURE et l'amplitude par
//       `time-adjust-ratio` en gardant UN appel par image dessinee, alors que l'index de LECTURE
//       est le compteur BRUT chez tous les consommateurs. A 15 images/s le ratio vaut 4, le pas
//       d'ecriture vaut 4 slots, et `64 - 64/pgcd(4,64)` = 48 slots ne sont JAMAIS ecrits : le
//       ressort lit du vide trois fois sur quatre puis un coup multiplie par 4. Corrige a la
//       source dans goal_src/jak1/engine/gfx/background/wind.gc : l'arithmetique de ND est
//       restauree et c'est le NOMBRE D'APPELS qui porte la cadence.
//
//   (b) COTE RESSORT (ici). `do_wind_math` integre avec un pas CODE EN DUR de 1/60 s (`cz`, et
//       `wind-const.z` dans goal_src/jak1/engine/gfx/tie/tie-work.gc:15) et tournait UNE fois par
//       image DESSINEE. A 15 images/s la brise de ND avancait donc a un quart de sa vitesse.
//
// LE NOMBRE DE PAS SE LIT SUR `wind-time`, PAS SUR UNE HORLOGE A NOUS. Le compteur avance
// d'exactement un cran par appel a `update-wind`, et `update-wind` est desormais appelee une fois
// par pas de 1/60 s. `wind_time - m_wind_last_time` EST donc le nombre de pas que cette image
// porte — exact, partage avec le producteur, et sans second generateur aleatoire. Le round 3
// avait construit une COPIE du vent avancee a l'horloge murale ; elle est supprimee, parce que
// deux horloges peuvent diverger et que celle-ci ne le peut pas. A 60 images/s le delta vaut 1 et
// tout ce fichier fait exactement ce qu'il faisait avant : la correction n'agit que la ou le
// defaut existe.
//
// CE N'EST PAS UNE OPTION « RECHARGED ». L'owner demande que la brise native marche « par défaut
// sans notre modification » : le correctif vit donc HORS du basculement, et son ablation est
// `*wind-native-rate*` (OG_WIND_NATIVE_RATE / debug.opengoal.wind.native_rate), qui remet GOAL
// sur son ancien chemin — le delta retombe alors a 1 tout seul et cette moitie-ci se desarme avec
// lui, sans qu'aucun drapeau ait a etre lu deux fois.
//
// NON corrige, et deliberement : le ressort persiste sa sortie DEJA MULTIPLIEE PAR `stiffness`
// dans le slot de position (`my_vector[0] = vf27.x()` apres `vf27 *= stiffness`). Le listing EE
// brut (docs/progress-notes/jak1/scratch/tie_ee.asm:486-522), la transcription mips2c
// (game/mips2c/jak1_functions/tie_methods.cpp:633,647) et le programme VU SHRUB INDEPENDANT
// (docs/progress-notes/jak1/scratch/shrub_asm.md:1028-1054) font tous le meme choix. Le vent TIE
// de ND est donc un appui lent, pas un balancement ; « restituer l'intention ND » veut dire
// restituer sa CADENCE, pas inventer l'oscillateur qu'il n'a jamais eu.
//
// Combien de pas de 1/60 s cette image porte. Borne haute a 8 pour qu'un a-coup de chargement ne
// fasse pas defiler la brise d'un huitieme de seconde d'un coup ; 0 est autorise et signifie
// « aucun tick de logique sur cette image » (pas fixe arme, image de rendu seul) — dans ce cas le
// cisaillement DEJA calcule est reapplique tel quel, sans integrer.
static int fw_wind_ticks(u32 now, u32& last, bool& seeded, bool paused) {
  if (!seeded) {
    seeded = true;
    last = now;
    return 1;  // premiere image apres un chargement : on ne rattrape pas l'historique du monde
  }
  if (paused) {
    last = now;
    return 0;  // en pause GOAL n'avance plus `wind-time` ; on n'integre pas non plus
  }
  const u32 d = now - last;  // arithmetique non signee : robuste au repliement de l'uint32
  last = now;
  if (d > 8) {
    return 8;
  }
  return (int)d;
}

// ---------------------------------------------------------------------------------------------
// Grecharged-foliage-wind2 SHEAR AUDIT. The permanent renderer-side counter that replaces round
// 1's capture-derived motion statistic (owner banned that class of proof, 2026-07-26/2026-08-04).
// Every wind instance reports the stock shear and the shear this build actually applied; once per
// window we print peak + RMS of both and their ratio.
//
// How to read the numbers: the shear is dimensionless and displaces a vertex by
// `shear * (its height above the instance origin)`, so
//     crown sway in metres = shear * prototype height in metres
// with the heights coming from the offline census in tie-census.txt. ratio_peak == 1.000000 with
// the toggle OFF is a RUNTIME proof that OFF is the untouched stock arithmetic.
struct FwAudit {
  std::string level;
  double stock_sq = 0.0, appl_sq = 0.0;
  float stock_peak = 0.f, appl_peak = 0.f;
  // MOTION, i.e. how far the shear travels from one frame to the next. This is the field the owner
  // is actually complaining about; the peak/RMS above only say how far the palm is BENT.
  double dstock_sq = 0.0, dappl_sq = 0.0;
  float dstock_peak = 0.f, dappl_peak = 0.f;
  // Grecharged-foliage-wind3 : l'ETAT BRUT du ressort, AVANT la multiplication par `stiffness`,
  // et sa part de temps passee sur la butee +/-1 (`vector_min_in_place` / `vector_max` dans
  // do_wind_math). `stock_rms` ne pouvait pas repondre a la question « le ressort est-il sature ? »
  // parce qu'il porte deja `stiffness`, qui vaut 0,1 a la plage et 0,25 sur le poisson de
  // Sandover : deux denominateurs dans une meme moyenne. `raw` a le meme sens partout.
  double raw_sq = 0.0;
  float raw_peak = 0.f;
  u64 sat_hits = 0;
  u64 dsamples = 0;
  u64 samples = 0;
  u64 frames = 0;
  u64 last_frame = (u64)-1;
  u64 draws = 0;
  std::chrono::steady_clock::time_point t0 = std::chrono::steady_clock::now();
};

// Grecharged-foliage-wind3 — UN ACCUMULATEUR PAR NIVEAU, ET C'EST UN CORRECTIF D'INSTRUMENT.
// L'accumulateur etait un GLOBAL UNIQUE partage par tous les `Tie3` residents, et son champ
// `level` prenait le nom du DERNIER appelant : a la plage, ou `beach` (stiffness 0,1) et
// `village1` (0,1 ET 0,25) sont residents en meme temps, les lignes `lev=beach` melangeaient les
// deux niveaux. La preuve arithmetique que c'etait faux etait deja dans les journaux du round 3 :
// `stock_peak = 0,152` et `0,177` depassent `sqrt(2) x 0,1 = 0,1414`, ce qui est IMPOSSIBLE pour
// une instance de stiffness 0,1 sous la butee. Toute conversion « shear -> metres » faite sur ces
// lignes portait donc deux hauteurs et deux raideurs a la fois.
static std::unordered_map<std::string, FwAudit>& fw_audits() {
  static std::unordered_map<std::string, FwAudit> s;
  return s;
}

static void fw_audit_accum(const std::string& level,
                           float stock,
                           float applied,
                           bool have_delta,
                           float dstock,
                           float dappl,
                           float raw,
                           bool saturated) {
  FwAudit& a = fw_audits()[level];
  a.level = level;
  a.stock_peak = std::max(a.stock_peak, stock);
  a.appl_peak = std::max(a.appl_peak, applied);
  a.stock_sq += (double)stock * stock;
  a.appl_sq += (double)applied * applied;
  a.raw_peak = std::max(a.raw_peak, raw);
  a.raw_sq += (double)raw * raw;
  if (saturated) {
    a.sat_hits++;
  }
  a.samples++;
  if (have_delta) {
    a.dstock_peak = std::max(a.dstock_peak, dstock);
    a.dappl_peak = std::max(a.dappl_peak, dappl);
    a.dstock_sq += (double)dstock * dstock;
    a.dappl_sq += (double)dappl * dappl;
    a.dsamples++;
  }
}

static void fw_audit_tick(const std::string& level,
                          u64 frame_idx,
                          bool on,
                          float frond,
                          size_t wind_draws,
                          u32 paused,
                          u32 wind_time,
                          // Grecharged-foliage-wind3 : pas de 1/60 s portes par cette image.
                          // 1 == ce que rend un affichage a 60 images/s, donc la correction de
                          // cadence y est un no-op par construction ; 4 a 15 images/s, et c'est
                          // le facteur par lequel le port faisait tourner la brise de ND LENTE.
                          int rate_ticks) {
  FwAudit& a = fw_audits()[level];
  if (frame_idx != a.last_frame) {
    a.last_frame = frame_idx;
    a.frames++;
  }
  a.draws += wind_draws;
  if (a.frames < 300 || !a.samples) {
    return;
  }
  const double n = (double)a.samples;
  const double dn = (double)std::max<u64>(a.dsamples, 1);
  const double s_rms = std::sqrt(a.stock_sq / n);
  const double a_rms = std::sqrt(a.appl_sq / n);
  const double ds_rms = std::sqrt(a.dstock_sq / dn);
  const double da_rms = std::sqrt(a.dappl_sq / dn);
  const double raw_rms = std::sqrt(a.raw_sq / n);
  const double sat = (double)a.sat_hits / n;
  const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - a.t0).count();
  const double fps = secs > 0.0 ? (double)a.frames / secs : 0.0;
  // BEND (peak/rms) says how far the palm is pushed over. MOTION (dpeak/drms) says how far the
  // shear travels between consecutive frames — a frozen lean scores high on the first and ~0 on
  // the second, and only the second is what an eye can see.
  // Grecharged-foliage-wind3 ajoute les trois grandeurs qui repondent a D1, et elles sont
  // INDEPENDANTES de `stiffness` (donc comparables d'un niveau a l'autre) :
  //   raw_rms  : |vf17| AVANT la multiplication par stiffness. Une brise saine reste bien sous 1.
  //   satfrac  : part des echantillons colles a la butee +/-1. Un arbre fige sur un plein appui.
  //   fps      : la cadence de la fenetre, mesuree ici et pas deduite des horodatages du journal.
  // `dmotion_per_s = dstock_rms * fps` est la grandeur qui doit etre INDEPENDANTE de la cadence
  // quand la brise est une fonction du TEMPS et non des IMAGES : c'est le verdict de D1.
  lg::info(
      "[foliage-wind] shear-audit lev={} on={} rate_ticks={} paused={} wind_time={} frames={} "
      "fps={:.2f} samples={} "
      "wind_draws_submitted={} frond={:.4f} raw_rms={:.4f} raw_peak={:.4f} satfrac={:.4f} "
      "stock_peak={:.6f} stock_rms={:.6f} "
      "applied_peak={:.6f} applied_rms={:.6f} ratio_peak={:.3f} ratio_rms={:.3f} "
      "dstock_peak={:.6f} dstock_rms={:.6f} dapplied_peak={:.6f} dapplied_rms={:.6f} "
      "dratio_peak={:.3f} dratio_rms={:.3f} dmotion_per_s={:.6f}",
      a.level, on ? 1 : 0, rate_ticks, paused, wind_time, a.frames, fps, a.samples,
      a.draws, frond, raw_rms, a.raw_peak, sat, a.stock_peak, s_rms, a.appl_peak, a_rms,
      a.stock_peak > 0.f ? a.appl_peak / a.stock_peak : -1.f,
      s_rms > 0.0 ? a_rms / s_rms : -1.0, a.dstock_peak, ds_rms, a.dappl_peak,
      da_rms, a.dstock_peak > 0.f ? a.dappl_peak / a.dstock_peak : -1.f,
      ds_rms > 0.0 ? da_rms / ds_rms : -1.0, ds_rms * fps);
  a = FwAudit{};
  a.level = level;
}
}  // namespace

Tie3::Tie3(const std::string& name,
           int my_id,
           int level_id,
           const std::vector<GLuint>* anim_slot_array,
           tfrag3::TieCategory category)
    : BucketRenderer(name, my_id),
      m_level_id(level_id),
      m_default_category(category),
      m_anim_slot_array(anim_slot_array) {
  // regardless of how many we use some fixed max
  // we won't actually interp or upload to gpu the unused ones, but we need a fixed maximum so
  // indexing works properly.
  m_color_result.resize(TIME_OF_DAY_COLOR_COUNT);

  m_wind_data.paused = 0;
  math::Vector4f ones(1, 1, 1, 1);
  m_wind_data.wind_normal = ones;
  m_wind_data.wind_temp = ones;
  for (auto& wv : m_wind_data.wind_array) {
    wv = ones;
  }
  for (auto& wf : m_wind_data.wind_force) {
    wf = 1.f;
  }
}

Tie3::~Tie3() {
  discard_tree_cache();
}

void Tie3::init_shaders(ShaderLibrary& shaders) {
  m_uniforms.decal = glGetUniformLocation(shaders[ShaderId::TFRAG3].id(), "decal");

  m_etie_uniforms.persp0 = glGetUniformLocation(shaders[ShaderId::ETIE].id(), "persp0");
  m_etie_uniforms.persp1 = glGetUniformLocation(shaders[ShaderId::ETIE].id(), "persp1");
  m_etie_uniforms.cam_no_persp = glGetUniformLocation(shaders[ShaderId::ETIE].id(), "cam_no_persp");
  m_etie_uniforms.envmap_tod_tint =
      glGetUniformLocation(shaders[ShaderId::ETIE].id(), "envmap_tod_tint");

  m_etie_base_uniforms.decal = glGetUniformLocation(shaders[ShaderId::ETIE_BASE].id(), "decal");
  m_etie_base_uniforms.persp0 = glGetUniformLocation(shaders[ShaderId::ETIE_BASE].id(), "persp0");
  m_etie_base_uniforms.persp1 = glGetUniformLocation(shaders[ShaderId::ETIE_BASE].id(), "persp1");
  m_etie_base_uniforms.cam_no_persp =
      glGetUniformLocation(shaders[ShaderId::ETIE_BASE].id(), "cam_no_persp");
}

/*!
 * Load a TIE tree from FR3 data.
 * This often causes stutters, so as much as possible, we move stuff to the loader,
 * and this function just updates things to reference loader data.
 */
void Tie3::load_from_fr3_data(const LevelData* loader_data) {
  auto ul = scoped_prof("update-load");
  const tfrag3::Level* lev_data = loader_data->level.get();
  // Grecharged-grass-overhang2: resolve the fringe alpha textures the near droop replaces.
  // Grecharged-grass-overhang7: gate widened from "training" to the grass allowlist — the owner
  // plays at Sentinel Beach, which uses the same bch-* textures and now gets the droop/fall tail.
  m_fringe_tex_a = m_fringe_tex_b = -1;
  if (grass_level_enabled(lev_data->level_name)) {
    for (size_t ti = 0; ti < lev_data->textures.size(); ++ti) {
      const auto& tn = lev_data->textures[ti].debug_name;
      if (tn == "bch-grassfringe") {
        m_fringe_tex_a = (s32)ti;
      } else if (tn == "bch-leafyground-hang-2x1") {
        m_fringe_tex_b = (s32)ti;
      }
    }
  }
#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials round-4: resolve every texture in this level that has a
  // registered PBR material set (no level-name gating). Mirrors TFragment::update_load.
  m_pbr_draws.clear();
  for (size_t ti = 0; ti < lev_data->textures.size(); ++ti) {
    if (const auto* maps = custom_tex::find_pbr_material(custom_tex::pbr_material_key(lev_data->textures[ti].debug_tpage_name, lev_data->textures[ti].debug_name))) {
      const auto mat_key = custom_tex::pbr_material_key(lev_data->textures[ti].debug_tpage_name,
                                                        lev_data->textures[ti].debug_name);
      // Gpbr-props-reach-draw : une matiere AUTHOREE SANS AUCUNE CARTE n'a rien qui lise la densite
      // UV — elle pilote l'amplitude POM/tessellation, qui exigent toutes deux une carte de hauteur.
      // Sauter la marche de geometrie garde les nouvelles entrees gratuites au chargement.
      const bool has_any_map = maps->normal_tex || maps->rough_tex || maps->metal_tex ||
                               maps->ao_tex || maps->height_tex || maps->specular_tex ||
                               maps->emissive_tex;
      // Grecharged-pbr-realtime-fusion ROUND 20: same measured authored UV density as TFragment,
      // walked over the TIE geo-0 static draws (same StripDraw / PreloadedVertex types).
      u32 nsamp = 0;
      float dens = 0.5f;
      if (has_any_map) {
        dens = measure_uv_density_tie(*lev_data, (s32)ti, &nsamp);
        if (dens <= 0.f) {
          dens = 0.5f;
        }
      }
      m_pbr_draws.push_back({(s32)ti, *maps, dens, mat_key});
      if (has_any_map) {
        // [pom] device diagnostic: same hand-off as TFragment — TIE materials are exactly the draws
        // the per-PROGRAM tess gate now keeps the POM on, so they must appear in the dump too.
        custom_tex::pbr_pom_diag_note(lev_data->textures[ti].debug_name, *maps, dens);
        lg::info(
            "pbr uv density (tie): {} tiles/m={:.3f} tile={:.1f}cm (shader assumed 0.5 => 200.0cm, "
            "ratio {:.2f}x) samples={}",
            lev_data->textures[ti].debug_name, dens, 100.f / dens, dens / 0.5f, nsamp);
      } else {
        lg::info(
            "pbr authored-only material (tie): {} (aucune carte compagnon ; u_pbr_mode bit 256, "
            "les constantes authorees de surfaces.json remplacent les cartes absentes)",
            lev_data->textures[ti].debug_name);
      }
    }
  }
  if (!m_pbr_draws.empty()) {
    lg::info("Grecharged-pbr-materials: Tie3 level {} has {} PBR material(s)", lev_data->level_name,
             m_pbr_draws.size());
  }
#endif
  m_wind_vectors.clear();

  // We changed level! free opengl resources allocated for the previous
  discard_tree_cache();

  // resize for the number of trees in this level.
  for (int geo = 0; geo < 4; ++geo) {
    m_trees[geo].resize(lev_data->tie_trees[geo].size());
  }

  u16 max_wind_idx = 0;
  // loop over all "geos" (level of details)
  for (u32 l_geo = 0; l_geo < tfrag3::TIE_GEOS; l_geo++) {
    // loop over all trees
    for (u32 l_tree = 0; l_tree < lev_data->tie_trees[l_geo].size(); l_tree++) {
      auto ul = scoped_prof("load-tree");
      size_t wind_idx_buffer_len = 0;
      size_t num_grps = 0;
      const auto& tree = lev_data->tie_trees[l_geo][l_tree];

      // compute maximum number of vis groups (leaf in the bvh)
      for (auto& draw : tree.static_draws) {
        num_grps += draw.vis_groups.size();
      }

      // compute wind buffer sizes
      for (auto& draw : tree.instanced_wind_draws) {
        wind_idx_buffer_len += draw.vertex_index_stream.size();
      }
      for (auto& inst : tree.wind_instance_info) {
        max_wind_idx = std::max(max_wind_idx, inst.wind_idx);
      }

      // vertex buffer max
      auto& lod_tree = m_trees.at(l_geo);

      // set up resources: create a VAO
      glGenVertexArrays(1, &lod_tree[l_tree].vao);
      glBindVertexArray(lod_tree[l_tree].vao);
      // openGL vertex buffer from loader
      lod_tree[l_tree].vertex_buffer = loader_data->tie_data[l_geo][l_tree].vertex_buffer;
      // draw array from FR3 data
      lod_tree[l_tree].draws = &tree.static_draws;
      // base TOD colors from FR3
      lod_tree[l_tree].colors = &tree.colors;
      // visibility BVH from FR3
      lod_tree[l_tree].vis = &tree.bvh;
      // indices from FR3 (needed on CPU for culling)
      lod_tree[l_tree].index_data = tree.unpacked.indices.data();
      // wind metadata
      lod_tree[l_tree].instance_info = &tree.wind_instance_info;
      lod_tree[l_tree].wind_draws = &tree.instanced_wind_draws;
      // Grecharged-foliage-wind: one-shot census so a device log can PROVE whether this level's
      // TIE protos are wind-enabled (stiffness != 0 => instances here). If instances == 0 the
      // wind pass early-returns and the sway boost is a silent no-op — this line makes that
      // failure mode visible instead of invisible.
      if (l_geo == 0) {
        // Grecharged-foliage-wind2: the census now also reports the authored STIFFNESS spread and
        // the static-draw count. That is the whole round-1 post-mortem in one line: the stock shear
        // is stiffness * (drive/100), so a tiny max stiffness proves arithmetically why multiplying
        // it could never be visible — and static_draws vs wind_draws shows how much of the level's
        // TIE geometry is baked static (no per-instance matrix at all => unreachable from here).
        float st_min = 0.f, st_max = 0.f, st_sum = 0.f;
        bool st_first = true;
        for (const auto& wi : tree.wind_instance_info) {
          if (st_first) {
            st_min = st_max = wi.stiffness;
            st_first = false;
          } else {
            st_min = std::min(st_min, wi.stiffness);
            st_max = std::max(st_max, wi.stiffness);
          }
          st_sum += wi.stiffness;
        }
        const float st_mean =
            tree.wind_instance_info.empty() ? 0.f : st_sum / (float)tree.wind_instance_info.size();
        lg::info(
            "[foliage-wind] TIE census lev={} tree={} wind_draws={} wind_instances={} "
            "static_draws={} stiffness_min={} stiffness_max={} stiffness_mean={}",
            lev_data->level_name, l_tree, tree.instanced_wind_draws.size(),
            tree.wind_instance_info.size(), tree.static_draws.size(), st_min, st_max, st_mean);
      }
      // ----------------------------------------------------------------------------------------
      // Grecharged-foliage-wind3 (owner 2026-08-31, defaut D2 : « tous les arbres ne sont pas
      // impactés ») — LA LIGNE QUI PORTE LE VERDICT DE D2, une par arbre TIE et par LOD.
      //
      // Elle est imprimee ICI et pas dans `TieTree::unpack()` parce que c'est le seul endroit ou
      // le NOM DU NIVEAU existe ; les compteurs, eux, ne peuvent etre calcules que dans `unpack()`
      // (apres, les sommets CPU sont rendus — Loader.cpp:1550-1553) et ils y survivent parce que
      // ce ne sont que des entiers.
      //
      // POURQUOI `proto_names_size` EST SUR CETTE LIGNE : les fr3 « enhanced » HD
      // (out/jak1/fr3/enhanced/, dont village1) sortent d'une chaine SEPAREE
      // (scripts/shell/build_enhanced_models.sh). S'ils ne sont pas regeneres, Loader.cpp:358-371
      // les fait GAGNER quand le basculement HD est actif, et le niveau chargerait un fr3 SANS
      // `proto_names` : zero balancement, en silence, exactement le symptome que l'owner decrit.
      // `proto_names_size=0` rend ce cas VISIBLE au lieu de le laisser passer pour un defaut de
      // rendu.
      //
      // POURQUOI LES NOMS NON CLASSES SONT PUBLIES : sans eux, retirer une ligne du lexique
      // retrecirait le denominateur en silence et la couverture monterait toute seule.
      {
        const auto& c = tree.sway_census;
        std::string noms;
        for (size_t ni = 0; ni < c.noms_non_classes.size(); ni++) {
          if (ni) {
            noms += ",";
          }
          noms += c.noms_non_classes[ni];
        }
        if (c.non_classes > c.noms_non_classes.size()) {
          noms += fmt::format(",+{}", c.non_classes - c.noms_non_classes.size());
        }
        lg::info(
            "[foliage-wind] TIE sway-cover lev={} tree={} geo={} lexique={} proto_names_size={} "
            "protos={} veg_protos={} non_classes={} inst_total={} inst_veg={} inst_swayed={} "
            "verts={} v_sway={} v_neutre={} v_windpath={} v_sansproto={} vconflit={} "
            "vg_desync={} plain_inds={} noms_non_classes={}",
            lev_data->level_name, l_tree, l_geo, c.lexicon_loaded ? 1 : 0, tree.proto_names.size(),
            c.protos, c.veg_protos, c.non_classes, c.inst_total, c.inst_veg, c.inst_swayed,
            c.verts, c.v_sway, c.v_neutre, c.v_windpath, c.v_sansproto, c.v_conflit, c.vg_desync,
            c.plain_inds, noms.empty() ? "-" : noms);
      }
      // OpenGL index buffer (fixed index buffer for multidraw system)
      lod_tree[l_tree].index_buffer = loader_data->tie_data[l_geo][l_tree].index_buffer;
      lod_tree[l_tree].category_draw_indices = tree.category_draw_indices;
      lod_tree[l_tree].draw_mode = tree.use_strips ? GL_TRIANGLE_STRIP : GL_TRIANGLES;
#ifdef OG_FEAT_PBR
      // New level data invalidates the cached full-caster ranges (round-5 shadow fix).
      lod_tree[l_tree].pbr_full_ranges.clear();
      lod_tree[l_tree].pbr_full_ranges_built = false;
#endif

      // set up vertex attributes
      glBindBuffer(GL_ARRAY_BUFFER, lod_tree[l_tree].vertex_buffer);
      glEnableVertexAttribArray(0);
      glEnableVertexAttribArray(1);
      glEnableVertexAttribArray(2);
      glEnableVertexAttribArray(3);
      glEnableVertexAttribArray(4);

      glVertexAttribPointer(0,                                           // location 0 in the shader
                            3,                                           // 3 values per vert
                            GL_FLOAT,                                    // floats
                            GL_FALSE,                                    // normalized
                            sizeof(tfrag3::PreloadedVertex),             // stride
                            (void*)offsetof(tfrag3::PreloadedVertex, x)  // offset (0)
      );

      glVertexAttribPointer(1,                                           // location 1 in the shader
                            3,                                           // 3 values per vert
                            GL_FLOAT,                                    // floats
                            GL_FALSE,                                    // normalized
                            sizeof(tfrag3::PreloadedVertex),             // stride
                            (void*)offsetof(tfrag3::PreloadedVertex, s)  // offset (0)
      );

      glVertexAttribIPointer(2,                                // location 2 in the shader
                             2,                                // 1 values per vert
                             GL_UNSIGNED_SHORT,                // u16
                             sizeof(tfrag3::PreloadedVertex),  // stride
                             (void*)offsetof(tfrag3::PreloadedVertex, color_index)  // offset (0)
      );

      glVertexAttribPointer(3,                                // location 1 in the shader
                            4,                                // 3 values per vert
                            GL_INT_2_10_10_10_REV,            // floats
                            GL_TRUE,                          // normalized
                            sizeof(tfrag3::PreloadedVertex),  // stride
                            (void*)offsetof(tfrag3::PreloadedVertex, nor)  // offset (0)
      );

      glVertexAttribPointer(4,                                           // location 1 in the shader
                            4,                                           // 3 values per vert
                            GL_UNSIGNED_BYTE,                            // floats
                            GL_TRUE,                                     // normalized
                            sizeof(tfrag3::PreloadedVertex),             // stride
                            (void*)offsetof(tfrag3::PreloadedVertex, r)  // offset (0)
      );

      // Grecharged-mesh-consolidation: per-vertex SEAM WEIGHT (1 = displace normally, 0 = do not
      // displace). mesh_consolidate() zeroes it at boundaries whose two sides cannot displace
      // identically, so the tessellation evaluation shader can fade displacement to exactly zero
      // along a shared edge on BOTH sides — that is what closes the see-through slits. Bound here
      // (before the tangent VBO swaps GL_ARRAY_BUFFER below) so it reads the vertex buffer.
      glEnableVertexAttribArray(6);
      glVertexAttribPointer(6, 1, GL_UNSIGNED_SHORT, GL_TRUE, sizeof(tfrag3::PreloadedVertex),
                            (void*)offsetof(tfrag3::PreloadedVertex, seam_w));

      // REOPEN#7: per-vertex tangent at location 5 (loc 4 = envmap tint). Non-envmap TIE draws use
      // the TFRAG3 shader which reads location 5 as the tangent for the continuous PBR TBN.
      glBindBuffer(GL_ARRAY_BUFFER, loader_data->tie_data[l_geo][l_tree].tangent_buffer);
      glEnableVertexAttribArray(5);
      glVertexAttribPointer(5, 4, GL_FLOAT, GL_FALSE, sizeof(float) * 4, (void*)0);

      // Grecharged-foliage-wind3 (defaut D2) : poids + phase de balancement, DEUX octets par
      // sommet, sur la LOCATION 7. Elle est libre et c'est verifie et non suppose : les shaders de
      // cet arbre declarent 0,1,2,3,4,5 (`grep "location = 7" shaders/*.vert` rendait ZERO avant
      // ce chunk), le VAO TIE ci-dessus active 0..6, et le VAO TFRAG (TFragment.cpp:443-494)
      // n'active ni 4 ni 7. Normalise : l'octet 0..255 arrive dans le shader en 0..1.
      glBindBuffer(GL_ARRAY_BUFFER, loader_data->tie_data[l_geo][l_tree].sway_buffer);
      glEnableVertexAttribArray(7);
      glVertexAttribPointer(7, 2, GL_UNSIGNED_BYTE, GL_TRUE, 2 * sizeof(u8), (void*)0);

      // allocate dynamic index buffer for the fallback "not multidraw" mode.
      glGenBuffers(1, &lod_tree[l_tree].single_draw_index_buffer);

      // set up wind
      if (wind_idx_buffer_len > 0) {
        lod_tree[l_tree].wind_matrix_cache.resize(tree.wind_instance_info.size());
        // Grecharged-foliage-wind2: 4 floats per instance for the motion half of the shear audit.
        lod_tree[l_tree].fw_prev_shear.assign(tree.wind_instance_info.size() * 4, 0.f);
        lod_tree[l_tree].fw_prev_valid = false;
        lod_tree[l_tree].wind_vertex_index_buffer =
            loader_data->tie_data[l_geo][l_tree].wind_indices;
        u32 off = 0;
        for (auto& draw : tree.instanced_wind_draws) {
          lod_tree[l_tree].wind_vertex_index_offsets.push_back(off);
          off += draw.vertex_index_stream.size();
        }
      }

      // set up per-proto visibility. Jak 2 needs to enable/disable individual protos.
      lod_tree[l_tree].has_proto_visibility = tree.has_per_proto_visibility_toggle;
      if (tree.has_per_proto_visibility_toggle) {
        lod_tree[l_tree].proto_visibility.init(tree.proto_names);
      }

      // set up time of day texture.
      // A36: Wx1 2D LUT instead of 1D. The non-envmap TIE draws share the
      // TFRAG3 shader (see draw_matching_draws_for_tree), and tfrag3.vert was
      // converted to `sampler2D tex_T10` with texelFetch(ivec2(i,0)). Sampling
      // a sampler2D from a unit that only has a 1D texture bound returns black,
      // which made every non-envmap TIE structure render as a black silhouette.
      // Match TFragment.cpp's Wx1 GL_TEXTURE_2D upload so the shared shader
      // reads real colors. (Also unblocks GLES, which has no glTexImage1D.)
      glActiveTexture(GL_TEXTURE10);
      glGenTextures(1, &lod_tree[l_tree].time_of_day_texture);
      glBindTexture(GL_TEXTURE_2D, lod_tree[l_tree].time_of_day_texture);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, TIME_OF_DAY_COLOR_COUNT, 1, 0, GL_RGBA,
                   GL_UNSIGNED_BYTE, nullptr);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

      // Gperf-particles round 3: second (ping-pong) TOD texture, identical.
      glGenTextures(1, &lod_tree[l_tree].time_of_day_texture_pp);
      glBindTexture(GL_TEXTURE_2D, lod_tree[l_tree].time_of_day_texture_pp);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, TIME_OF_DAY_COLOR_COUNT, 1, 0, GL_RGBA,
                   GL_UNSIGNED_BYTE, nullptr);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      lod_tree[l_tree].tod_flip = 0;
      lod_tree[l_tree].tod_current = lod_tree[l_tree].time_of_day_texture;
      lod_tree[l_tree].tod_cache_valid = false;  // Gperf-particles: fresh level re-interpolates

      glBindVertexArray(0);

      lod_tree[l_tree].vis_temp.resize(tree.bvh.vis_nodes.size());

      lod_tree[l_tree].draw_idx_temp.resize(tree.static_draws.size());
      lod_tree[l_tree].index_temp.resize(tree.unpacked.indices.size());
      lod_tree[l_tree].multidraw_offset_per_stripdraw.resize(tree.static_draws.size());
      lod_tree[l_tree].multidraw_count_buffer.resize(num_grps);
      lod_tree[l_tree].multidraw_index_offset_buffer.resize(num_grps);
    }
  }

  // set up temporary caches. These are just temporary, so they don't need per-tree versions.

  m_wind_vectors.resize(4 * max_wind_idx + 4);  // 4x u32's per wind.

  // ASSERT(time_of_day_count <= TIME_OF_DAY_COLOR_COUNT);
}

/*!
 * Try loading a level. Hopefully it has been preloaded and this is fast.
 */
bool Tie3::try_loading_level(const std::string& level, SharedRenderState* render_state) {
  // make sure we have the level data.
  Timer tfrag3_setup_timer;
  auto lev_data = render_state->loader->get_tfrag3_level(level);

  if (!lev_data) {
    // not loaded
    m_has_level = false;
    m_textures = nullptr;
    m_level_name = "";
    discard_tree_cache();
    return false;
  }

  if (m_has_level && lev_data->load_id != m_load_id) {
    m_has_level = false;
    m_textures = nullptr;
    m_level_name = "";
    discard_tree_cache();
    return try_loading_level(level, render_state);
  }

  // loading was successful. Link textures/load ID.
  m_textures = &lev_data->textures;
  m_load_id = lev_data->load_id;

  // see if this is the first time we've gotten the level
  if (m_level_name != level) {
    // it is! do the one time load.
    load_from_fr3_data(lev_data);
    m_has_level = true;
    m_level_name = level;
  } else {
    m_has_level = true;
  }

  if (tfrag3_setup_timer.getMs() > 5) {
    lg::info("TIE setup: {:.1f}ms", tfrag3_setup_timer.getMs());
  }

  return m_has_level;
}

void Tie3::discard_tree_cache() {
  for (int geo = 0; geo < 4; ++geo) {
    for (auto& tree : m_trees[geo]) {
      glBindTexture(GL_TEXTURE_2D, tree.time_of_day_texture);
#ifdef __ANDROID__
      fprintf(stderr, "F1E-DELTEX site=tie-tod tex=%u\n", (unsigned)tree.time_of_day_texture);
#endif
      glDeleteTextures(1, &tree.time_of_day_texture);
      // Gperf-particles round 3: delete the ping-pong TOD texture too.
      glDeleteTextures(1, &tree.time_of_day_texture_pp);
      // glDeleteBuffers(1, &tree.index_buffer);
      glDeleteBuffers(1, &tree.single_draw_index_buffer);
      glDeleteVertexArrays(1, &tree.vao);
    }

    m_trees[geo].clear();
  }
}

bool Tie3::set_up_common_data_from_dma(DmaFollower& dma, SharedRenderState* render_state) {
  auto data0 = dma.read_and_advance();
  ASSERT(data0.vif1() == 0 || data0.vifcode1().kind == VifCode::Kind::NOP);
  ASSERT(data0.vif0() == 0 || data0.vifcode0().kind == VifCode::Kind::NOP ||
         data0.vifcode0().kind == VifCode::Kind::MARK);
  ASSERT(data0.size_bytes == 0);

  if (dma.current_tag().kind == DmaTag::Kind::CALL) {
    // renderer didn't run, let's just get out of here.
    for (int i = 0; i < 4; i++) {
      dma.read_and_advance();
    }
    ASSERT(dma.current_tag_offset() == render_state->next_bucket);
    return false;
  }

  if (dma.current_tag_offset() == render_state->next_bucket) {
    return false;
  }

  auto gs_test = dma.read_and_advance();
  if (gs_test.size_bytes == 160) {
  } else {
    ASSERT(gs_test.size_bytes == 32);

    auto tie_consts = dma.read_and_advance();
    ASSERT(tie_consts.size_bytes == 9 * 16);
  }

  auto mscalf = dma.read_and_advance();
  ASSERT(mscalf.size_bytes == 0);

  auto row = dma.read_and_advance();
  ASSERT(row.size_bytes == 32);

  auto next = dma.read_and_advance();
  if (next.size_bytes == 32) {
    next = dma.read_and_advance();
  }
  ASSERT(next.size_bytes == 0);

  auto pc_port_data = dma.read_and_advance();
  ASSERT(pc_port_data.size_bytes == sizeof(TfragPcPortData));
  memcpy(&m_pc_port_data, pc_port_data.data, sizeof(TfragPcPortData));
  m_pc_port_data.level_name[11] = '\0';

  if (render_state->version == GameVersion::Jak1) {
    auto wind_data = dma.read_and_advance();
    ASSERT(wind_data.size_bytes == sizeof(WindWork));
    memcpy(&m_wind_data, wind_data.data, sizeof(WindWork));
  }

  if (render_state->version >= GameVersion::Jak2) {
    // jak 2 proto visibility
    auto proto_mask_data = dma.read_and_advance();
    m_common_data.proto_vis_data = proto_mask_data.data;
    m_common_data.proto_vis_data_size = proto_mask_data.size_bytes;
  }

  // envmap color
  auto envmap_color = dma.read_and_advance();
  ASSERT(envmap_color.size_bytes == 16);
  memcpy(m_common_data.envmap_color.data(), envmap_color.data, 16);
  m_common_data.envmap_color /= 128.f;
  if (render_state->version == GameVersion::Jak1) {
    m_common_data.envmap_color *= 2;
  }
  m_common_data.envmap_color *= m_envmap_strength;

  m_common_data.frame_idx = render_state->frame_idx;

  while (dma.current_tag_offset() != render_state->next_bucket) {
    dma.read_and_advance();
  }

  m_common_data.settings.camera = m_pc_port_data.camera;

  m_common_data.settings.tree_idx = 0;

  if (render_state->occlusion_vis[m_level_id].valid) {
    m_common_data.settings.occlusion_culling = render_state->occlusion_vis[m_level_id].data;
  } else {
    m_common_data.settings.occlusion_culling = 0;
  }

  update_render_state_from_pc_settings(render_state, m_pc_port_data);

  m_has_level = try_loading_level(m_pc_port_data.level_name, render_state);
  return true;
}
/*!
 * Render method called from bucket render system.
 * Does common setup for all category, but only renderers default_category.
 */
void Tie3::render(DmaFollower& dma, SharedRenderState* render_state, ScopedProfilerNode& prof) {
  if (!m_enabled) {
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
    }
    return;
  }

  if (set_up_common_data_from_dma(dma, render_state)) {
    // Gperf-particles: attribute per-tree TOD/cull/index-build setup vs draw
    // submission separately so A35-PERF can steer the batching work (mirrors
    // TFragment's "t3" child idiom).
    {
      auto setup_prof = prof.make_scoped_child("setup");
      setup_all_trees(lod(), m_common_data.settings, m_common_data.proto_vis_data,
                      m_common_data.proto_vis_data_size, !render_state->no_multidraw,
                      render_state->perf_tod_pingpong, render_state->perf_tod_skip, setup_prof);
    }

    {
      auto draws_prof = prof.make_scoped_child("draws");
      draw_matching_draws_for_all_trees(lod(), m_common_data.settings, render_state, draws_prof,
                                        m_default_category);
    }

    // Grecharged-mesh-browser V2: freecam NORMAL GIZMOS overlay for a targeted TIE mesh.
    // One compare (mb_target_active) when the browser is idle — the loader lookup and the
    // module's own filtering only run while the gizmo toggle is armed.
    if (Gfx::g_global_settings.mb_target_active && Gfx::g_global_settings.mb_gizmos_target &&
        m_has_level) {
      const auto* mb_lev = render_state->loader->get_tfrag3_level(m_level_name);
      if (mb_lev) {
        mb_gizmos::render(mb_lev->level.get(), 1, m_level_name.c_str(), render_state, prof);
      }
    }
    // Grecharged-mesh-browser V2.4: persistent MARKED-polygon highlight — independent of the
    // gizmo toggle, once per frame (the module stamps the frame), only while the browser
    // session is open and marks exist. Two relaxed loads when idle.
    if (Gfx::g_global_settings.mb_pbr_override &&
        Gfx::g_global_settings.mb_marks_active.load(std::memory_order_relaxed) > 0) {
      mb_gizmos::render_marks(render_state, prof);
    }
    // Grecharged-mesh-browser V2.1: pending reticle pick — contribute this level's TIE
    // triangle hits (two relaxed loads when idle; see gfx.h mb_pick_*).
    if (mb_pick::pending() && m_has_level) {
      const auto* mb_lev = render_state->loader->get_tfrag3_level(m_level_name);
      if (mb_lev) {
        mb_pick::raytest(mb_lev->level.get(), 1, m_level_name.c_str());
      }
    }
  }
}

void Tie3::render_from_another(SharedRenderState* render_state,
                               ScopedProfilerNode& prof,
                               tfrag3::TieCategory category) {
  if (render_state->frame_idx != m_common_data.frame_idx) {
    return;
  }
  draw_matching_draws_for_all_trees(lod(), m_common_data.settings, render_state, prof, category);
}

void Tie3::draw_matching_draws_for_all_trees(int geom,
                                             const TfragRenderSettings& settings,
                                             SharedRenderState* render_state,
                                             ScopedProfilerNode& prof,
                                             tfrag3::TieCategory category) {
  for (u32 i = 0; i < m_trees[geom].size(); i++) {
    draw_matching_draws_for_tree(i, geom, settings, render_state, prof, category);
  }
}

void Tie3::setup_all_trees(int geom,
                           const TfragRenderSettings& settings,
                           const u8* proto_vis_data,
                           size_t proto_vis_data_size,
                           bool use_multidraw,
                           bool tod_pingpong,
                           bool tod_skip,
                           ScopedProfilerNode& prof) {
  for (u32 i = 0; i < m_trees[geom].size(); i++) {
    setup_tree(i, geom, settings, proto_vis_data, proto_vis_data_size, use_multidraw, tod_pingpong,
               tod_skip, prof);
  }
}

void Tie3::setup_tree(int idx,
                      int geom,
                      const TfragRenderSettings& settings,
                      const u8* proto_vis_data,
                      size_t proto_vis_data_size,
                      bool use_multidraw,
                      bool tod_pingpong,
                      bool tod_skip,
                      ScopedProfilerNode& prof) {
  // reset perf
  auto& tree = m_trees.at(geom).at(idx);
  // don't render if we haven't loaded
  if (!m_has_level) {
    return;
  }

  // update time of day
  if (m_color_result.size() < tree.colors->color_count) {
    m_color_result.resize(tree.colors->color_count);
  }

  {
    // Gperf-particles: memoize the TOD interp+upload — when itimes is unchanged
    // vs the last cached value, tod_current already holds the correct palette,
    // so skip both the interpolation and the glTexSubImage2D upload (night
    // hot-path). Behind the perf_tod_skip kill switch; result is byte-identical.
    bool tod_same = tree.tod_cache_valid &&
        memcmp(tree.tod_cache_itimes, settings.camera.itimes, 16 * sizeof(s32)) == 0;
    if (tod_skip && tod_same) {
      // Gperf-particles: itimes unchanged -> skip interp + palette upload;
      // tod_current retains last frame's palette (byte-identical result).
    } else {
      {
        // Gperf-particles: time-of-day color interpolation (per-tree, accumulate).
        SpartScopedNs _interp(g_spart_prof.tie_interp);
        interp_time_of_day(settings.camera.itimes, *tree.colors, m_color_result.data());
      }

      {
        // Gperf-particles: time-of-day texture upload (bind pair + sub-image).
        // Round 3: ping-pong the target texture (flag ON) so the upload does not
        // touch the texture last frame's draws are still sampling on Adreno, then
        // publish it via tod_current so every later bind uses the same texture.
        // Flag OFF => tod_current == time_of_day_texture (byte-identical old path).
        SpartScopedNs _texsub(g_spart_prof.tie_texsub);
        if (tod_pingpong) {
          tree.tod_flip ^= 1;
          tree.tod_current = tree.tod_flip ? tree.time_of_day_texture_pp : tree.time_of_day_texture;
        } else {
          tree.tod_current = tree.time_of_day_texture;
        }
        glActiveTexture(GL_TEXTURE10);
        glBindTexture(GL_TEXTURE_2D, tree.tod_current);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, tree.colors->color_count, 1, GL_RGBA,
                        GL_UNSIGNED_BYTE, m_color_result.data());
      }
      memcpy(tree.tod_cache_itimes, settings.camera.itimes, 16 * sizeof(s32));
      tree.tod_cache_valid = true;
    }
  }

  // update proto vis mask
  if (proto_vis_data) {
    tree.proto_visibility.update(proto_vis_data, proto_vis_data_size);
  }

  if (!m_debug_all_visible) {
    // Gperf-particles: slow (per-node) frustum/occlusion cull check.
    SpartScopedNs _cull(g_spart_prof.tie_cull);
    // need culling data
    cull_check_all_slow(settings.camera.planes, tree.vis->vis_nodes, settings.occlusion_culling,
                        tree.vis_temp.data());
  }

  // Gperf-particles: index-list build + index-buffer upload (per-tree).
  SpartScopedNs _index(g_spart_prof.tie_index);
  u32 num_tris = 0;
  if (use_multidraw) {
    if (m_debug_all_visible) {
      num_tris = make_all_visible_multidraws(
          tree.multidraw_offset_per_stripdraw.data(), tree.multidraw_count_buffer.data(),
          tree.multidraw_index_offset_buffer.data(), *tree.draws);
    } else {
      Timer index_timer;
      if (tree.has_proto_visibility) {
        num_tris = make_multidraws_from_vis_and_proto_string(
            tree.multidraw_offset_per_stripdraw.data(), tree.multidraw_count_buffer.data(),
            tree.multidraw_index_offset_buffer.data(), *tree.draws, tree.vis_temp,
            tree.proto_visibility.vis_flags);
      } else {
        num_tris = make_multidraws_from_vis_string(
            tree.multidraw_offset_per_stripdraw.data(), tree.multidraw_count_buffer.data(),
            tree.multidraw_index_offset_buffer.data(), *tree.draws, tree.vis_temp);
      }
    }
  } else {
    u32 idx_buffer_size;
    if (m_debug_all_visible) {
      idx_buffer_size =
          make_all_visible_index_list(tree.draw_idx_temp.data(), tree.index_temp.data(),
                                      *tree.draws, tree.index_data, &num_tris);
    } else {
      if (tree.has_proto_visibility) {
        idx_buffer_size = make_index_list_from_vis_and_proto_string(
            tree.draw_idx_temp.data(), tree.index_temp.data(), *tree.draws, tree.vis_temp,
            tree.proto_visibility.vis_flags, tree.index_data, &num_tris);
      } else {
        idx_buffer_size =
            make_index_list_from_vis_string(tree.draw_idx_temp.data(), tree.index_temp.data(),
                                            *tree.draws, tree.vis_temp, tree.index_data, &num_tris);
      }
    }

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree.single_draw_index_buffer);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx_buffer_size * sizeof(u32), tree.index_temp.data(),
                 GL_STREAM_DRAW);
  }

  prof.add_tri(num_tris);
}

namespace {
void set_uniform(GLuint uniform, const math::Vector4f& val) {
  glUniform4f(uniform, val.x(), val.y(), val.z(), val.w());
}
}  // namespace

void init_etie_cam_uniforms(const EtieUniforms& uniforms, const GoalBackgroundCameraData& data) {
  glUniformMatrix4fv(uniforms.cam_no_persp, 1, GL_FALSE, data.rot[0].data());

  math::Vector4f perspective[2];
  float inv_fog = 1.f / data.fog[0];
  auto& hvdf_off = data.hvdf_off;
  float pxx = data.perspective[0].x();
  float pyy = data.perspective[1].y();
  float pzz = data.perspective[2].z();
  float pzw = data.perspective[2].w();
  float pwz = data.perspective[3].z();
  float scale = pzw * inv_fog;
  perspective[0].x() = scale * hvdf_off.x();
  perspective[0].y() = scale * hvdf_off.y();
  perspective[0].z() = scale * hvdf_off.z() + pzz;
  perspective[0].w() = scale;

  perspective[1].x() = pxx;
  perspective[1].y() = pyy;
  perspective[1].z() = pwz;
  perspective[1].w() = 0;

  set_uniform(uniforms.persp0, perspective[0]);
  set_uniform(uniforms.persp1, perspective[1]);
}

// =================================================================================================
// Grecharged-foliage-wind3 (owner 2026-08-31, defaut D2 : « tous les arbres ne sont pas impactés »)
// LE BALANCEMENT DU TIE **STATIQUE** — pose des uniformes.
//
// Le chemin VENT (`render_tree_wind`) ne touche QUE les instances que l'extracteur a basculees en
// `instanced_wind_draws`, c'est-a-dire celles dont le prototype porte une raideur non nulle. Tout
// le reste de la vegetation TIE est de la geometrie STATIQUE fondue dans un seul maillage, sans
// matrice d'instance a l'execution : aucun bouton de ce fichier ne pouvait la faire bouger. C'est
// ca, « tous les arbres ne sont pas impactés », et c'est ce chemin-ci qui le ferme.
//
// OFF == STOCK, ET C'EST LA SEULE CHOSE QUE CETTE FONCTION GARANTIT : quand l'option est eteinte
// elle ecrit 0, le `if` du chunk saute le bloc et le sommet ressort a l'identique. Elle n'ecrit
// RIEN d'autre sur le chemin statique.
void Tie3::push_tie_sway_uniforms(GLuint program, u64 frame_idx, const char* pass) {
  float amp = 0.f;
  if (Gfx::recharged_active(Gfx::g_global_settings.recharged_foliage_wind)) {
    amp = foliage_wind_tie_sway();  // unites monde (metres x 4096)
  }
  // Horloge MURALE, la meme que le chemin vent (helper partage en haut de ce fichier) : elle
  // n'avance qu'une fois par image et se fige avec la pause du jeu, donc le balancement garde sa
  // frequence quel que soit le nombre d'images par seconde de l'appareil.
  const float t = foliage_wind_clock(frame_idx, m_wind_data.paused != 0);
  // Cap du vent : celui du jeu, comme le fait deja `render_tree_wind`, pour que le statique et le
  // chemin vent penchent du meme cote. Repli sur une diagonale fixe si le niveau ne le remplit pas.
  float dx = m_wind_data.wind_normal.x();
  float dz = m_wind_data.wind_normal.z();
  const float dlen = std::sqrt(dx * dx + dz * dz);
  if (dlen > 1e-3f) {
    dx /= dlen;
    dz /= dlen;
  } else {
    dx = 0.7071f;
    dz = 0.7071f;
  }
  const GLint amp_loc = glGetUniformLocation(program, "u_tie_sway_amp");
  const GLint time_loc = glGetUniformLocation(program, "u_tie_sway_time");
  const GLint dir_loc = glGetUniformLocation(program, "u_tie_sway_dir");
  if (amp_loc >= 0) {
    glUniform1f(amp_loc, amp);
  }
  if (time_loc >= 0) {
    glUniform1f(time_loc, t);
  }
  if (dir_loc >= 0) {
    glUniform2f(dir_loc, dx, dz);
  }
  if (amp > 0.f) {
    // Ligne de preuve one-shot PAR PASSE. Elle publie les trois modes de defaillance SILENCIEUX de
    // ce chemin, parce qu'aucun d'eux ne produit d'erreur GL :
    //   * un `loc` a -1 = l'uniforme n'existe pas dans le programme lie (chunk absent du blob
    //     GLES, bloc optimise) : on ecrirait dans le vide ;
    //   * `attr7_on=0` = l'attribut 7 n'est pas active sur le VAO courant, donc le poids arrive a
    //     0 partout et RIEN ne bouge, sans le moindre message ;
    //   * la comparaison au chemin VENT, qui est l'ordre de l'owner : la brise ajoutee doit rester
    //     STRICTEMENT SOUS celle des arbres qui en ont deja une.
    static std::unordered_map<std::string, bool> s_logged;
    if (!s_logged[pass]) {
      s_logged[pass] = true;
      GLint attr_on = 0, attr_size = 0;
      glGetVertexAttribiv(7, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &attr_on);
      glGetVertexAttribiv(7, GL_VERTEX_ATTRIB_ARRAY_SIZE, &attr_size);
      const float amp_m = amp / 4096.f;
      const float wind_shear = foliage_wind_tie_amp();
      const float wind_m_palm = wind_shear * 17.52f;  // palm-02.mb, hauteur du recensement
      lg::info(
          "[foliage-wind] TIE static sway ACTIVE pass={} amp={:.1f}u ({:.3f} m a la couronne) "
          "amp_loc={} time_loc={} dir_loc={} attr7_on={} attr7_size={} dir=({:.3f},{:.3f}) "
          "vent_shear={:.3f} (soit {:.2f} m sur palm-02.mb, 17,52 m) "
          "rapport_statique_sur_vent={:.4f}",
          pass, amp, amp_m, amp_loc, time_loc, dir_loc, attr_on, attr_size, dx, dz, wind_shear,
          wind_m_palm, wind_m_palm > 0.f ? amp_m / wind_m_palm : -1.f);
    }
  }
}

void Tie3::draw_matching_draws_for_tree(int idx,
                                        int geom,
                                        const TfragRenderSettings& settings,
                                        SharedRenderState* render_state,
                                        ScopedProfilerNode& prof,
                                        tfrag3::TieCategory category) {
  auto& tree = m_trees.at(geom).at(idx);

  // don't render if we haven't loaded
  if (!m_has_level) {
    return;
  }
  bool use_envmap = tfrag3::is_envmap_first_draw_category(category);
  auto shader_id = use_envmap ? ShaderId::ETIE_BASE : ShaderId::TFRAG3;

  // setup OpenGL shader
  first_tfrag_draw_setup(settings.camera, render_state, shader_id);

  if (use_envmap) {
    // if we use envmap, use the envmap-style math for the base draw to avoid rounding issue.
    init_etie_cam_uniforms(m_etie_base_uniforms, m_common_data.settings.camera);
  }

  glBindVertexArray(tree.vao);
  glBindBuffer(GL_ARRAY_BUFFER, tree.vertex_buffer);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,
               render_state->no_multidraw ? tree.single_draw_index_buffer : tree.index_buffer);

  // Grecharged-foliage-wind3 (defaut D2) : APRES `first_tfrag_draw_setup`, qui vient d'ecrire 0
  // pour tout le monde (le terrain TFRAG partage ce vertex shader), et APRES le bind du VAO pour
  // que la ligne de preuve puisse interroger l'etat REEL de l'attribut 7.
  push_tie_sway_uniforms(render_state->shaders[shader_id].id(), render_state->frame_idx,
                         use_envmap ? "etie_base" : "tfrag3");

  glActiveTexture(GL_TEXTURE10);
  // Gperf-particles round 3: bind the TOD texture selected at update time (the
  // ping-pong current, or the single texture when the flag is off).
  glBindTexture(GL_TEXTURE_2D, tree.tod_current);

  glActiveTexture(GL_TEXTURE0);
#ifdef __ANDROID__
  // GLES has no settable restart index (glPrimitiveRestartIndex is NULL in the
  // arm64 loader — calling it is BLR-to-0 / sig=11 fault=0x0, the same class as
  // the A36 tfrag/shrub crashes). The fixed-index mode restarts on the all-ones
  // index, which IS UINT32_MAX for our u32 index buffers — identical semantics.
  glEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX);
#else
  glEnable(GL_PRIMITIVE_RESTART);
  glPrimitiveRestartIndex(UINT32_MAX);
#endif

#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials round-4, owner clarification 2026-07-18 (WORLD-scale
  // shadows): TIE geometry — the sage hut, bridges, buildings — must CAST into the sun
  // shadow map, else the owner's acceptance image (hut shadow on the ground) is
  // impossible. Depth-only pass over this tree's NORMAL-category draws into the
  // double-buffered write map; receivers sample last frame's completed map, so bucket
  // order (tfrag before tie) does not matter. Same GL-state dance as the TFragment
  // caster pass. Vertex layout is compatible: TIE draws with the TFRAG3 program, so
  // attribute 0 is the world position pbr_depth.vert consumes.
  // Round-5 addendum 2 (mandate F): world-wide — no m_pbr_draws gate (see TFragment).
  // ROUND 2 (owner defect #3): the envmap TIE geometry (shiny huts, metal props, bridges)
  // must ALSO cast — its opaque base draw is the NORMAL_ENVMAP category. Cast for both the
  // plain NORMAL and the NORMAL_ENVMAP base draws (never the TRANS/WATER or *_SECOND_DRAW
  // shiny-overlay categories, which would double-cast the same geometry).
  if (((!use_envmap && category == tfrag3::TieCategory::NORMAL) ||
       (use_envmap && category == tfrag3::TieCategory::NORMAL_ENVMAP)) &&
      (Gfx::recharged_active(Gfx::g_global_settings.recharged_pbr_enable) ||
       Gfx::recharged_active(Gfx::g_global_settings.recharged_rt_light_enable)) &&
      (pbr_shadow_caster_mask(render_state->frame_idx) & 2) &&
      pbr_shadow_begin_frame(render_state->frame_idx, settings.camera.trans.data())) {
    auto& sh_st = pbr_shadow_state();
    GLint prev_program = 0, prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0}, prev_depth_func = GL_LEQUAL;
    GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
    GLboolean prev_cull = glIsEnabled(GL_CULL_FACE);
    GLboolean prev_poly_off = glIsEnabled(GL_POLYGON_OFFSET_FILL);
    // DEPTH_TEST is per-DrawMode state — force it on for the depth-only pass (depth
    // writes only happen when the test is enabled; the device chain reaches here with
    // it off → empty map). Same fix as the TFragment caster pass.
    GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
    GLboolean prev_depth_mask = GL_TRUE;
    glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);
    glGetIntegerv(GL_VIEWPORT, prev_vp);
    glGetIntegerv(GL_DEPTH_FUNC, &prev_depth_func);
    glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);

    glBindFramebuffer(GL_FRAMEBUFFER, sh_st.fbo[sh_st.write]);
    glViewport(0, 0, sh_st.size, sh_st.size);
    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_CULL_FACE);
    glEnable(GL_DEPTH_TEST);
    glDepthMask(GL_TRUE);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_POLYGON_OFFSET_FILL);
    glPolygonOffset(2.0f, 4.0f);

    const auto& depth_sh = render_state->shaders[ShaderId::PBR_DEPTH];
    depth_sh.activate();
    GLuint depth_id = depth_sh.id();
    glUniformMatrix4fv(glGetUniformLocation(depth_id, "u_smvp"), 1, GL_FALSE, sh_st.mvp);
    const auto& ct = settings.camera.trans;
    glUniform4f(glGetUniformLocation(depth_id, "cam_trans"), ct[0], ct[1], ct[2], ct[3]);

    // Grecharged-mesh-browser V2: a HIDDEN targeted TIE mesh must not cast into the sun shadow
    // map either (unlike the TFragment caster pass, which is whole-tree-in-one-call and keeps
    // casting — documented there). When the hide target lives in this renderer's system+level,
    // the coalesced-range fast path below can't skip per draw, so fall back to per-draw
    // full-range submission for exactly as long as the hide is armed (the cached ranges are
    // left untouched for the normal path). V2.6-bis isolation needs the same per-draw fallback:
    // NON-target draws must not cast while only the target renders (isolation is level/system
    // agnostic — a target elsewhere still silences every caster in this tree).
    const auto& mb_st = Gfx::g_global_settings;
    const bool mb_shadow_hide =
        mb_st.mb_target_active && mb_st.mb_hide_target && mb_st.mb_target_system == 1 &&
        std::strncmp(m_level_name.c_str(), mb_st.mb_target_level,
                     sizeof(mb_st.mb_target_level)) == 0;
    const bool mb_shadow_iso = mb_st.mb_isolation_on();
    if (sh_st.cast_full && (mb_shadow_hide || mb_shadow_iso)) {
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree.index_buffer);
      for (size_t di = tree.category_draw_indices[(int)category];
           di < tree.category_draw_indices[(int)category + 1]; di++) {
        const auto& draw = (*tree.draws)[di];
        u32 count = 0;
        for (const auto& vg : draw.vis_groups) {
          count += vg.num_inds;
        }
        if (count == 0) {
          continue;
        }
        const bool mb_caster_tgt = mb_draw_targeted(1, draw.tree_tex_id, m_level_name.c_str());
        if (mb_shadow_iso && !mb_caster_tgt) {
          Gfx::g_global_settings.mb_cur_isolated_skips++;  // color-draw counter stays untouched
          continue;
        }
        if (mb_shadow_hide && mb_caster_tgt) {
          Gfx::g_global_settings.mb_ctr_hidden_draws++;
          continue;
        }
        glDrawElements(tree.draw_mode, count, GL_UNSIGNED_INT,
                       (void*)((size_t)draw.unpacked.idx_of_first_idx_in_full_buffer * sizeof(u32)));
        sh_st.cast_indices += (u64)count;
      }
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, render_state->no_multidraw
                                                ? tree.single_draw_index_buffer
                                                : tree.index_buffer);
    } else if (sh_st.cast_full) {
      // Round-5 owner bug fix (same as TFragment): the caster set must IGNORE camera
      // visibility — an off-screen hut must keep casting its on-screen shadow, else
      // shadows pop in/out on camera rotation. Draw the current category's FULL static
      // index ranges from tree.index_buffer (already the bound EBO in multidraw mode;
      // rebind for no_multidraw and restore after). Ranges are built lazily per tree:
      // each StripDraw's vis_groups tile its span in the full buffer, so the draw's
      // total index count is the sum of its groups' num_inds. ROUND 2: keyed by category
      // so NORMAL and NORMAL_ENVMAP each get their own cached ranges (no clobber, no
      // double-cast — the two categories occupy distinct index spans in the same buffer).
      const int cast_cat = (int)category;
      const bool env_cat = (category == tfrag3::TieCategory::NORMAL_ENVMAP);
      auto& ranges = env_cat ? tree.pbr_full_ranges_env : tree.pbr_full_ranges;
      bool& ranges_built = env_cat ? tree.pbr_full_ranges_env_built : tree.pbr_full_ranges_built;
      if (!ranges_built) {
        ranges.clear();
        for (size_t di = tree.category_draw_indices[cast_cat];
             di < tree.category_draw_indices[cast_cat + 1]; di++) {
          const auto& draw = (*tree.draws)[di];
          u32 count = 0;
          for (const auto& vg : draw.vis_groups) {
            count += vg.num_inds;
          }
          if (count == 0) {
            continue;
          }
          u32 first = draw.unpacked.idx_of_first_idx_in_full_buffer;
          if (!ranges.empty() &&
              ranges.back().first + ranges.back().second == first) {
            ranges.back().second += count;  // coalesce adjacent draws
          } else {
            ranges.emplace_back(first, count);
          }
        }
        ranges_built = true;
      }
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree.index_buffer);
      for (const auto& r : ranges) {
        glDrawElements(tree.draw_mode, r.second, GL_UNSIGNED_INT,
                       (void*)((size_t)r.first * sizeof(u32)));
        sh_st.cast_indices += (u64)r.second;
      }
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, render_state->no_multidraw
                                                ? tree.single_draw_index_buffer
                                                : tree.index_buffer);
    } else {
      // Old camera-vis-culled caster set (prop castfull=0), kept as the perf/repro A/B.
      for (size_t di = tree.category_draw_indices[(int)category];
           di < tree.category_draw_indices[(int)category + 1]; di++) {
        // Grecharged-mesh-browser V2: hidden targeted TIE draws don't cast (see above); under
        // V2.6-bis isolation, NON-target draws don't cast either.
        if (mb_shadow_hide || mb_shadow_iso) {
          const bool mb_caster_tgt =
              mb_draw_targeted(1, (*tree.draws)[di].tree_tex_id, m_level_name.c_str());
          if (mb_shadow_iso && !mb_caster_tgt) {
            Gfx::g_global_settings.mb_cur_isolated_skips++;  // color-draw counter stays untouched
            continue;
          }
          if (mb_shadow_hide && mb_caster_tgt) {
            Gfx::g_global_settings.mb_ctr_hidden_draws++;
            continue;
          }
        }
        if (render_state->no_multidraw) {
          const auto& sd = tree.draw_idx_temp[di];
          if (sd.second == 0) {
            continue;
          }
          glDrawElements(tree.draw_mode, sd.second, GL_UNSIGNED_INT,
                         (void*)(sd.first * sizeof(u32)));
          sh_st.cast_indices += (u64)sd.second;
        } else {
          const auto& md = tree.multidraw_offset_per_stripdraw[di];
          if (md.second == 0) {
            continue;
          }
          glMultiDrawElements(tree.draw_mode, &tree.multidraw_count_buffer[md.first],
                              GL_UNSIGNED_INT, &tree.multidraw_index_offset_buffer[md.first],
                              md.second);
          for (int mdi = 0; mdi < md.second; mdi++) {
            sh_st.cast_indices += (u64)tree.multidraw_count_buffer[md.first + mdi];
          }
        }
      }
    }
    if (sh_st.debug) {
      GLenum dbg_err = glGetError();
      if (dbg_err != GL_NO_ERROR) {
        lg::warn("PBR-SHADOW-DBG tie depth pass glerr=0x{:x}", (u32)dbg_err);
      }
    }

    glUseProgram((GLuint)prev_program);
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
    glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
    if (prev_scissor) {
      glEnable(GL_SCISSOR_TEST);
    } else {
      glDisable(GL_SCISSOR_TEST);
    }
    if (prev_cull) {
      glEnable(GL_CULL_FACE);
    } else {
      glDisable(GL_CULL_FACE);
    }
    if (prev_poly_off) {
      glEnable(GL_POLYGON_OFFSET_FILL);
    } else {
      glDisable(GL_POLYGON_OFFSET_FILL);
    }
    glPolygonOffset(0.0f, 0.0f);
    if (!prev_depth_test) {
      glDisable(GL_DEPTH_TEST);
    }
    glDepthMask(prev_depth_mask);
    glDepthFunc(prev_depth_func);
  }
#endif

  // Gperf-particles: per-draw GL state cache (flag-off = identical old path).
  BgDrawStateCache draw_state_cache;
  GLuint bound_tex = 0;

  // Grecharged-grass-overhang2: per-draw fringe near-fade uniform. Non-envmap TFRAG3 only (the
  // painted fringe strips are not envmapped); the envmap paths use ETIE_BASE and are left untouched.
  // ALWAYS left at 0 so other TFRAG3 users are unaffected; 0 = stock shader path.
  const GrassFringeFade fringe_fade = grass_fringe_fade_params();
  const bool fringe_active = fringe_fade.on && !use_envmap;
  GLint fringe_loc = -2;  // -2 = not queried yet
  bool fringe_on_state = false;
  auto set_fringe = [&](bool want) {
    if (want == fringe_on_state) {
      return;
    }
    if (fringe_loc == -2) {
      fringe_loc = glGetUniformLocation(render_state->shaders[shader_id].id(), "u_fringe_fade");
    }
    if (fringe_loc >= 0) {
      glUniform4f(fringe_loc, want ? 1.f : 0.f, fringe_fade.start_m, fringe_fade.end_m,
                  fringe_fade.dbg);
    }
    fringe_on_state = want;
  };

#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials round-4 coverage unification: bind PBR material maps per draw via
  // the shared PbrDrawBinder; u_pbr_mode restored to 0 + neutrals parked in finish() below.
  // ★ ROUND 22 (owner defect A, "la plupart des endroits n'ont toujours pas de displacement du
  // tout"): the binder used to run on the NON-envmap TFRAG3 path ONLY — the envmap branch drew
  // through ETIE_BASE, which had no PBR uniforms and no material bind, so EVERY envmapped TIE
  // object was structurally incapable of showing relief at any slider value. etie_base.frag now
  // carries the same shared fused chunk tfrag3.frag does, so the binder runs on both branches;
  // the only difference is WHICH program the uniforms land on.
  PbrDrawBinder pbr_binder;
  const ShaderId pbr_program = use_envmap ? ShaderId::ETIE_BASE : ShaderId::TFRAG3;
  pbr_binder.begin(render_state->shaders[pbr_program].id(), &m_pbr_draws);
  // [cover] ROUND 21 DISPLACEMENT COVERAGE: TIE's PBR draws are NEVER on the tess program (that
  // one is tfrag-only), so tess_program = false — every TIE draw with a height map must land in
  // disp_pom, never in disp_none. The two branches report under distinct renderer labels so the
  // coverage census can tell the envmap half from the plain half. No tree kind here.
  pbr_binder.set_coverage_context(use_envmap ? "tie_envmap" : "tie", nullptr, false,
                                  render_state->frame_idx);
  // Round-4 mandate B: bind the sun shadow matrix + sampler on the program that is actually
  // active so a replaced TIE surface receives the same shadowed direct term as tfrag. The depth
  // pass itself is driven by TFragment (tfrag NORMAL casters); Tie3 is receiver-only.
  // (Round-3 defect A/B: the envmap base needs this too, and always did.)
  if ((Gfx::recharged_active(Gfx::g_global_settings.recharged_pbr_enable) ||
       Gfx::recharged_active(Gfx::g_global_settings.recharged_rt_light_enable)) &&
      pbr_shadow_state().valid) {
    pbr_shadow_bind_receiver(render_state->shaders[pbr_program].id(),
                             settings.camera.trans.data());
  }
#endif

  int last_texture = -1;
  if (render_state->no_multidraw && render_state->batch_singledraw) {
    // Gperf-batching: merge consecutive draws sharing texture+mode into one
    // glDrawElements (see TFragment.cpp — same contiguity + trailing-restart
    // guarantees; TieTree::unpack ends every run with UINT32_MAX). Tie base
    // draws never double-draw (the AFAIL arm below is ASSERT(false)).
    const auto shader_id2 = use_envmap ? ShaderId::ETIE_BASE : ShaderId::TFRAG3;
    size_t draw_idx = tree.category_draw_indices[(int)category];
    const size_t end_idx = tree.category_draw_indices[(int)category + 1];
    while (draw_idx < end_idx) {
      const auto& draw = tree.draws->operator[](draw_idx);
      const auto& singledraw_indices = tree.draw_idx_temp[draw_idx];
      if (singledraw_indices.second == 0) {
        draw_idx++;
        continue;
      }

      // Grecharged-mesh-browser V2: freecam target — hide skips the draw, checker swaps the base.
      const bool mb_targeted = mb_draw_targeted(1, draw.tree_tex_id, m_level_name.c_str());
      if (mb_targeted && Gfx::g_global_settings.mb_hide_target) {
        Gfx::g_global_settings.mb_ctr_hidden_draws++;
        draw_idx++;
        continue;
      }
      if (!mb_targeted && Gfx::g_global_settings.mb_target_active) {
        if (Gfx::g_global_settings.mb_isolate) {
          Gfx::g_global_settings.mb_cur_isolated_skips++;
          draw_idx++;
          continue;  // isolation: only the targeted mesh renders
        }
        Gfx::g_global_settings.mb_cur_nontarget_draws++;  // per-frame proof: non-target draws submitted
      }
      if (mb_targeted) {
        Gfx::g_global_settings.mb_cur_target_draws++;  // V2.1 per-frame proof: submitted, not hidden
      }

      if (draw.tree_tex_id != last_texture) {
        if (draw.tree_tex_id >= 0) {
          bound_tex = m_textures->at(draw.tree_tex_id);
        } else {
          bound_tex = ((size_t)(-(draw.tree_tex_id + 1)) < m_anim_slot_array->size() ? m_anim_slot_array->at(-(draw.tree_tex_id + 1)) : 0);
          gj2vis_probe_bg_slot(-(draw.tree_tex_id + 1), bound_tex);
        }
        glBindTexture(GL_TEXTURE_2D, bound_tex);
        last_texture = draw.tree_tex_id;
      }

      auto double_draw =
          setup_tfrag_shader_cached(render_state, draw.mode, shader_id2, bound_tex, draw_state_cache);
      glUniform1i(use_envmap ? m_etie_base_uniforms.decal : m_uniforms.decal,
                  draw.mode.get_decal() ? 1 : 0);
      set_fringe(fringe_active && draw.tree_tex_id >= 0 &&
                 (draw.tree_tex_id == m_fringe_tex_a || draw.tree_tex_id == m_fringe_tex_b));
      const bool mb_checker = mb_targeted && Gfx::g_global_settings.mb_checker_target;
#ifdef OG_FEAT_PBR
      // ROUND 22: unconditional — the binder targets ETIE_BASE on the envmap branch and TFRAG3
      // on the plain one, so both now get the material maps + u_pbr_mode.
      pbr_binder.set(draw.tree_tex_id, draw.mode, mb_checker);
#endif
      if (mb_checker) {
        // Bind AFTER the cached setup so the draw-mode glTexParameteri calls landed on the draw's
        // own texture, not the shared checker (which keeps its REPEAT/mipmap params). This loop
        // caches its binding in last_texture — poison it so the NEXT draw rebinds its own texture
        // instead of inheriting the checker.
        glBindTexture(GL_TEXTURE_2D, pbr_testpattern::checker_base_gl());
        last_texture = INT32_MIN;
        Gfx::g_global_settings.mb_ctr_checker_draws++;
        Gfx::g_global_settings.mb_cur_checker_binds++;  // V2.1 per-frame proof
      }

      int first = singledraw_indices.first;
      int count = singledraw_indices.second;
      size_t next = draw_idx + 1;
      // Grecharged-mesh-browser V2: a TARGETED draw must never merge (in either role) — a merged
      // range would carry the targeted indices along and hide/checker would silently stop working.
      if (double_draw.kind == DoubleDrawKind::NONE) {
        while (next < end_idx && !mb_targeted) {
          const auto& d2 = tree.draws->operator[](next);
          const auto& sd2 = tree.draw_idx_temp[next];
          if (sd2.second == 0) {
            next++;
            continue;
          }
          if (d2.tree_tex_id != draw.tree_tex_id || d2.mode.as_int() != draw.mode.as_int() ||
              sd2.first != first + count ||
              mb_draw_targeted(1, d2.tree_tex_id, m_level_name.c_str())) {
            break;
          }
          count += sd2.second;
          next++;
        }
      } else {
        ASSERT(false);
      }

      prof.add_draw_call();
      glDrawElements(tree.draw_mode, count, GL_UNSIGNED_INT, (void*)(first * sizeof(u32)));
      draw_idx = next;
    }
  } else {
  for (size_t draw_idx = tree.category_draw_indices[(int)category];
       draw_idx < tree.category_draw_indices[(int)category + 1]; draw_idx++) {
    const auto& draw = tree.draws->operator[](draw_idx);
    const auto& multidraw_indices = tree.multidraw_offset_per_stripdraw[draw_idx];
    const auto& singledraw_indices = tree.draw_idx_temp[draw_idx];

    if (render_state->no_multidraw) {
      if (singledraw_indices.second == 0) {
        continue;
      }
    } else {
      if (multidraw_indices.second == 0) {
        continue;
      }
    }

    // Grecharged-mesh-browser V2: freecam target — hide skips the draw, checker swaps the base.
    const bool mb_targeted = mb_draw_targeted(1, draw.tree_tex_id, m_level_name.c_str());
    if (mb_targeted && Gfx::g_global_settings.mb_hide_target) {
      Gfx::g_global_settings.mb_ctr_hidden_draws++;
      continue;
    }
    if (!mb_targeted && Gfx::g_global_settings.mb_target_active) {
      if (Gfx::g_global_settings.mb_isolate) {
        Gfx::g_global_settings.mb_cur_isolated_skips++;
        continue;  // isolation: only the targeted mesh renders
      }
      Gfx::g_global_settings.mb_cur_nontarget_draws++;  // per-frame proof: non-target draws submitted
    }
    if (mb_targeted) {
      Gfx::g_global_settings.mb_cur_target_draws++;  // V2.1 per-frame proof: submitted, not hidden
    }

    if (draw.tree_tex_id != last_texture) {
      if (draw.tree_tex_id >= 0) {
        bound_tex = m_textures->at(draw.tree_tex_id);
      } else {
        bound_tex = ((size_t)(-(draw.tree_tex_id + 1)) < m_anim_slot_array->size() ? m_anim_slot_array->at(-(draw.tree_tex_id + 1)) : 0);
        gj2vis_probe_bg_slot(-(draw.tree_tex_id + 1), bound_tex);
      }
      glBindTexture(GL_TEXTURE_2D, bound_tex);
      last_texture = draw.tree_tex_id;
    }

    auto double_draw = setup_tfrag_shader_cached(
        render_state, draw.mode, use_envmap ? ShaderId::ETIE_BASE : ShaderId::TFRAG3, bound_tex,
        draw_state_cache);

    glUniform1i(use_envmap ? m_etie_base_uniforms.decal : m_uniforms.decal,
                draw.mode.get_decal() ? 1 : 0);
    set_fringe(fringe_active && draw.tree_tex_id >= 0 &&
               (draw.tree_tex_id == m_fringe_tex_a || draw.tree_tex_id == m_fringe_tex_b));
    const bool mb_checker = mb_targeted && Gfx::g_global_settings.mb_checker_target;
#ifdef OG_FEAT_PBR
    // ROUND 22: unconditional — see the merged-draw loop above.
    pbr_binder.set(draw.tree_tex_id, draw.mode, mb_checker);
#endif
    if (mb_checker) {
      // Bind AFTER the cached setup (see the merged-draw loop above); poison last_texture so the
      // NEXT draw rebinds its own texture instead of inheriting the checker.
      glBindTexture(GL_TEXTURE_2D, pbr_testpattern::checker_base_gl());
      last_texture = INT32_MIN;
      Gfx::g_global_settings.mb_ctr_checker_draws++;
      Gfx::g_global_settings.mb_cur_checker_binds++;  // V2.1 per-frame proof
    }

    prof.add_draw_call();

    if (render_state->no_multidraw) {
      glDrawElements(tree.draw_mode, singledraw_indices.second, GL_UNSIGNED_INT,
                     (void*)(singledraw_indices.first * sizeof(u32)));
    } else {
      glMultiDrawElements(
          tree.draw_mode, &tree.multidraw_count_buffer[multidraw_indices.first], GL_UNSIGNED_INT,
          &tree.multidraw_index_offset_buffer[multidraw_indices.first], multidraw_indices.second);
    }

    switch (double_draw.kind) {
      case DoubleDrawKind::NONE:
        break;
      case DoubleDrawKind::AFAIL_NO_DEPTH_WRITE: {
        ASSERT(false);
        prof.add_draw_call();
        const auto& afail_u = tfrag_alpha_uniforms(render_state->shaders[ShaderId::TFRAG3].id());
        if (afail_u.alpha_min != -1) {
          glUniform1f(afail_u.alpha_min, -10.f);
        }
        if (afail_u.alpha_max != -1) {
          glUniform1f(afail_u.alpha_max, double_draw.aref_second);
        }
        glDepthMask(GL_FALSE);
        // depth-mask toggled: cached mode's depth state is now stale.
        draw_state_cache.valid = false;
        if (render_state->no_multidraw) {
          glDrawElements(tree.draw_mode, singledraw_indices.second, GL_UNSIGNED_INT,
                         (void*)(singledraw_indices.first * sizeof(u32)));
        } else {
          glMultiDrawElements(tree.draw_mode, &tree.multidraw_count_buffer[multidraw_indices.first],
                              GL_UNSIGNED_INT,
                              &tree.multidraw_index_offset_buffer[multidraw_indices.first],
                              multidraw_indices.second);
        }
        break;
      } // AFAIL_NO_DEPTH_WRITE
      default:
        ASSERT(false);
    }
  }
  }
  // Grecharged-grass-overhang2: leave the fringe fade off for any subsequent TFRAG3 user.
  set_fringe(false);
#ifdef OG_FEAT_PBR
  // Reset u_pbr_mode to 0 + park neutral maps so no material leaks into later users of this
  // program (TFRAG3 is shared with tfrag/shrub; ETIE_BASE with the other envmap categories).
  pbr_binder.finish();
#endif

  if (!m_hide_wind && category == tfrag3::TieCategory::NORMAL) {
    auto wind_prof = prof.make_scoped_child("wind");
    render_tree_wind(idx, geom, settings, render_state, wind_prof);
  }

  glBindVertexArray(0);

  if (use_envmap && m_draw_envmap_second_draw) {
    envmap_second_pass_draw(tree, settings, render_state, prof,
                            tfrag3::get_second_draw_category(category));
  }
}

// Grecharged-mesh-browser V2: the *_ENVMAP_SECOND_DRAW categories drawn here are the additive
// sheen layer of envmapped TIEs, and their draws carry the ENVMAP texture id, not the base
// texture id the mesh-index target uses — pairing a base draw with its second draw is not
// attempted. So the envmap sheen layer of an envmapped TIE is NOT hidden/checkered (base pass
// only) — accepted debug-tool tolerance.
void Tie3::envmap_second_pass_draw(const Tree& tree,
                                   const TfragRenderSettings& settings,
                                   SharedRenderState* render_state,
                                   ScopedProfilerNode& prof,
                                   tfrag3::TieCategory category) {
  first_tfrag_draw_setup(settings.camera, render_state, ShaderId::ETIE);
  glBindVertexArray(tree.vao);
  glBindBuffer(GL_ARRAY_BUFFER, tree.vertex_buffer);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,
               render_state->no_multidraw ? tree.single_draw_index_buffer : tree.index_buffer);
  // Grecharged-foliage-wind3 : la passe ADDITIVE de reflet dessine la MEME geometrie que la passe
  // de base. Si elle ne recevait pas exactement les memes uniformes, le reflet se decollerait de
  // l'objet des que le balancement s'allume.
  push_tie_sway_uniforms(render_state->shaders[ShaderId::ETIE].id(), render_state->frame_idx,
                         "etie");

  init_etie_cam_uniforms(m_etie_uniforms, m_common_data.settings.camera);
  set_uniform(m_etie_uniforms.envmap_tod_tint, m_common_data.envmap_color);

  // Gjak2-visuals probe: the etie additive-coat tint, the one unmeasured input
  // of the white-wash hypothesis — diffable our-x86 (env GJ2VIS_TFTREE) vs
  // device (always, ~5 s cadence).
  {
#ifdef __ANDROID__
    static const bool s_tint_dump = true;
#else
    static const bool s_tint_dump = getenv("GJ2VIS_TFTREE") != nullptr;
#endif
    if (s_tint_dump) {
      static int s_tint_ctr = 0;
      if ((s_tint_ctr++ % 300) == 0) {
        const auto& ec = m_common_data.envmap_color;
        fprintf(stderr, "GJ2VIS-ETIETINT lvl=%s cat=%d tint=(%.4f %.4f %.4f %.4f) strength=%.3f\n",
                m_level_name.c_str(), (int)category, ec.x(), ec.y(), ec.z(), ec.w(),
                m_envmap_strength);
      }
    }
  }

  // Gperf-particles: per-draw GL state cache (flag-off = identical old path).
  BgDrawStateCache draw_state_cache;
  GLuint bound_tex = 0;

  int last_texture = -1;
  if (render_state->no_multidraw && render_state->batch_singledraw) {
    // Gperf-batching: merged-draw variant (see render_tree above). Envmap
    // second-pass draws never double-draw (non-NONE asserts below).
    size_t draw_idx = tree.category_draw_indices[(int)category];
    const size_t end_idx = tree.category_draw_indices[(int)category + 1];
    while (draw_idx < end_idx) {
      const auto& draw = tree.draws->operator[](draw_idx);
      const auto& singledraw_indices = tree.draw_idx_temp[draw_idx];
      if (singledraw_indices.second == 0) {
        draw_idx++;
        continue;
      }

      if (draw.tree_tex_id != last_texture) {
        if (draw.tree_tex_id >= 0) {
          bound_tex = m_textures->at(draw.tree_tex_id);
        } else {
          bound_tex = ((size_t)(-(draw.tree_tex_id + 1)) < m_anim_slot_array->size() ? m_anim_slot_array->at(-(draw.tree_tex_id + 1)) : 0);
          gj2vis_probe_bg_slot(-(draw.tree_tex_id + 1), bound_tex);
        }
        glBindTexture(GL_TEXTURE_2D, bound_tex);
        last_texture = draw.tree_tex_id;
      }

      auto double_draw =
          setup_tfrag_shader_cached(render_state, draw.mode, ShaderId::ETIE, bound_tex,
                                    draw_state_cache);
      ASSERT(double_draw.kind == DoubleDrawKind::NONE);

      int first = singledraw_indices.first;
      int count = singledraw_indices.second;
      size_t next = draw_idx + 1;
      while (next < end_idx) {
        const auto& d2 = tree.draws->operator[](next);
        const auto& sd2 = tree.draw_idx_temp[next];
        if (sd2.second == 0) {
          next++;
          continue;
        }
        if (d2.tree_tex_id != draw.tree_tex_id || d2.mode.as_int() != draw.mode.as_int() ||
            sd2.first != first + count) {
          break;
        }
        count += sd2.second;
        next++;
      }

      prof.add_draw_call();
      glDrawElements(tree.draw_mode, count, GL_UNSIGNED_INT, (void*)(first * sizeof(u32)));
      draw_idx = next;
    }
    return;
  }

  for (size_t draw_idx = tree.category_draw_indices[(int)category];
       draw_idx < tree.category_draw_indices[(int)category + 1]; draw_idx++) {
    const auto& draw = tree.draws->operator[](draw_idx);
    const auto& multidraw_indices = tree.multidraw_offset_per_stripdraw[draw_idx];
    const auto& singledraw_indices = tree.draw_idx_temp[draw_idx];

    if (render_state->no_multidraw) {
      if (singledraw_indices.second == 0) {
        continue;
      }
    } else {
      if (multidraw_indices.second == 0) {
        continue;
      }
    }

    if (draw.tree_tex_id != last_texture) {
      if (draw.tree_tex_id >= 0) {
        bound_tex = m_textures->at(draw.tree_tex_id);
      } else {
        bound_tex = ((size_t)(-(draw.tree_tex_id + 1)) < m_anim_slot_array->size() ? m_anim_slot_array->at(-(draw.tree_tex_id + 1)) : 0);
        gj2vis_probe_bg_slot(-(draw.tree_tex_id + 1), bound_tex);
      }
      glBindTexture(GL_TEXTURE_2D, bound_tex);

      last_texture = draw.tree_tex_id;
    }

    auto double_draw =
        setup_tfrag_shader_cached(render_state, draw.mode, ShaderId::ETIE, bound_tex,
                                  draw_state_cache);

    prof.add_draw_call();

    if (render_state->no_multidraw) {
      glDrawElements(tree.draw_mode, singledraw_indices.second, GL_UNSIGNED_INT,
                     (void*)(singledraw_indices.first * sizeof(u32)));
    } else {
      glMultiDrawElements(
          tree.draw_mode, &tree.multidraw_count_buffer[multidraw_indices.first], GL_UNSIGNED_INT,
          &tree.multidraw_index_offset_buffer[multidraw_indices.first], multidraw_indices.second);
    }

    switch (double_draw.kind) {
      case DoubleDrawKind::NONE:
        break;
      default:
        ASSERT(false);
    }
  }
}

void Tie3::draw_debug_window() {
  ImGui::Checkbox("envmap 2nd draw", &m_draw_envmap_second_draw);
  ImGui::SliderFloat("envmap str", &m_envmap_strength, 0, 2);
  ImGui::SameLine();
  ImGui::Checkbox("All Visible", &m_debug_all_visible);
  ImGui::Checkbox("Hide Wind", &m_hide_wind);
  ImGui::SliderFloat("Wind Multiplier", &m_wind_multiplier, 0., 40.f);
  ImGui::Separator();
}

void TieProtoVisibility::init(const std::vector<std::string>& names) {
  vis_flags.resize(names.size());
  for (auto& x : vis_flags) {
    x = 1;
  }
  all_visible = true;
  name_to_idx.clear();
  size_t i = 0;
  for (auto& name : names) {
    name_to_idx[name].push_back(i++);
  }
}

void TieProtoVisibility::update(const u8* data, size_t size) {
  char name_buffer[256];  // ??

  if (!all_visible) {
    for (auto& x : vis_flags) {
      x = 1;
    }
    all_visible = true;
  }

  const u8* end = data + size;

  while (true) {
    int name_idx = 0;
    while (*data) {
      name_buffer[name_idx++] = *data;
      data++;
    }
    if (name_idx) {
      ASSERT(name_idx < 254);
      name_buffer[name_idx] = '\0';
      const auto& it = name_to_idx.find(name_buffer);
      if (it != name_to_idx.end()) {
        all_visible = false;
        for (auto x : name_to_idx.at(name_buffer)) {
          vis_flags[x] = 0;
        }
      }
    }

    while (*data == 0) {
      if (data >= end) {
        return;
      }
      data++;
    }
  }
}

void vector_min_in_place(math::Vector4f& v, float val) {
  for (int i = 0; i < 4; i++) {
    if (v[i] > val) {
      v[i] = val;
    }
  }
}

math::Vector4f vector_max(const math::Vector4f& v, float val) {
  math::Vector4f result;
  for (int i = 0; i < 4; i++) {
    result[i] = std::max(val, v[i]);
  }
  return result;
}

void do_wind_math(u16 wind_idx,
                  float* wind_vector_data,
                  const Tie3::WindWork& wind_work,
                  float stiffness,
                  float shear_boost,
                  // Grecharged-foliage-wind2: additive procedural breeze shear {x, z}, computed per
                  // instance in render_tree_wind. nullptr when the toggle is OFF (stock path).
                  const float* shear_add,
                  // Grecharged-foliage-wind2 ROUND 3: the wind tick to evaluate the drive at. The
                  // stock leg passes wind_work.wind_time (one tick per displayed frame); the
                  // restored 60 Hz leg walks it forward one tick per SUBSTEP, which is what the
                  // game does per frame on a 60 fps console.
                  u32 wind_time_now,
                  std::array<math::Vector4f, 4>& mat,
                  // Grecharged-foliage-wind2 SHEAR AUDIT (round 2). Round 1 shipped an effect the
                  // owner could not see, and the only evidence it had was a capture-derived pixel
                  // statistic — the class of proof he has since banned outright. This is the
                  // replacement, and it is exact: [0] receives |stock shear| (vf27, bit for bit
                  // what the untouched game applies) and [1] |applied shear| (vf27s, what THIS
                  // build applies). The shear is DIMENSIONLESS and, because it lands as
                  // `row.x += s.x * row.y`, it displaces a vertex by  s * (its height above the
                  // instance origin). So these two numbers, multiplied by a prototype's authored
                  // height from tie-census.txt, are the sway in METRES — no pixels involved.
                  // nullptr = no audit. Reading vf27/vf27s cannot change what is rendered.
                  float* audit_out = nullptr) {
  float* my_vector = wind_vector_data + (4 * wind_idx);
  const auto& work_vector = wind_work.wind_array[(wind_time_now + wind_idx) & 63];
  constexpr float cx = 0.5;
  constexpr float cy = 100.0;
  constexpr float cz = 0.0166;
  constexpr float cw = -1.0;

  // ld s1, 8(s5)                    # load wind vector 1
  // pextlw s1, r0, s1               # convert to 2x 64 bits, by shifting left
  // qmtc2.i vf18, s1                # put in vf
  float vf18_x = my_vector[2];
  float vf18_z = my_vector[3];

  // ld s2, 0(s5)                    # load wind vector 0
  // pextlw s3, r0, s2               # convert to 2x 64 bits, by shifting left
  // qmtc2.i vf17, s3                # put in vf
  float vf17_x = my_vector[0];
  float vf17_z = my_vector[1];

  // lqc2 vf16, 12(s3)               # load wind vector
  math::Vector4f vf16 = work_vector;

  // vmula.xyzw acc, vf16, vf1       # acc = vf16
  // vmsubax.xyzw acc, vf18, vf19    # acc = vf16 - vf18 * wind_const.x
  // vmsuby.xyzw vf16, vf17, vf19
  // # vf16 -= (vf18 * wind_const.x) + (vf17 * wind_const.y)
  vf16.x() -= cx * vf18_x + cy * vf17_x;
  vf16.z() -= cx * vf18_z + cy * vf17_z;

  // vmulaz.xyzw acc, vf16, vf19     # acc = vf16 * wind_const.z
  // vmadd.xyzw vf18, vf1, vf18
  // # vf18 += vf16 * wind_const.z
  math::Vector4f vf18(vf18_x, 0.f, vf18_z, 0.f);
  vf18 += vf16 * cz;

  // vmulaz.xyzw acc, vf18, vf19    # acc = vf18 * wind_const.z
  // vmadd.xyzw vf17, vf17, vf1
  // # vf17 += vf18 * wind_const.z
  math::Vector4f vf17(vf17_x, 0.f, vf17_z, 0.f);
  vf17 += vf18 * cz;

  // vitof12.xyzw vf11, vf11 # normal convert
  // vitof12.xyzw vf12, vf12 # normal convert

  // Grecharged-foliage-wind3 : l'etat AVANT la butee, pour que l'audit puisse dire si le ressort
  // est SATURE. `stock_rms` ne le pouvait pas : il porte deja `stiffness`, qui differe par
  // prototype (0,1 pour les palmiers, 0,25 pour le poisson suspendu de Sandover).
  const float rc_pre_x = vf17.x();
  const float rc_pre_z = vf17.z();

  // vminiw.xyzw vf17, vf17, vf0
  vector_min_in_place(vf17, 1.f);

  // qmfc2.i s3, vf18
  // ppacw s3, r0, s3

  // vmaxw.xyzw vf27, vf17, vf19
  auto vf27 = vector_max(vf17, cw);

  // vmulw.xyzw vf27, vf27, vf15
  vf27 *= stiffness;

  // Grecharged-foliage-wind: amplify ONLY the applied matrix shear, never the persisted
  // integrator state (my_vector below keeps the stock vf27). Boosting `stiffness` instead is
  // self-cancelling: vf27 feeds back into next frame's restoring term (cy=100 * vf17), so the
  // spring just stiffens and the visible sway barely changes. shear_boost == 1.0 (toggle OFF)
  // multiplies by the exact literal 1.0f => byte-identical stock arithmetic.
  // Grecharged-foliage-wind2: the additive breeze lands on the SAME applied-shear-only line — the
  // persisted integrator state (my_vector, written below) still stores the stock vf27, so the stock
  // spring keeps running untouched underneath and nothing accumulates or drifts.
  math::Vector4f vf27s = vf27 * shear_boost;
  if (shear_add) {
    vf27s.x() += shear_add[0];
    vf27s.z() += shear_add[1];
  }

  // vmulax.yw acc, vf0, vf0
  // vmulay.xz acc, vf27, vf10
  // vmadd.xyzw vf10, vf1, vf10
  mat[0].x() += vf27s.x() * mat[0].y();
  mat[0].z() += vf27s.z() * mat[0].y();

  // qmfc2.i s2, vf27
  if (!wind_work.paused) {
    my_vector[0] = vf27.x();
    my_vector[1] = vf27.z();
    my_vector[2] = vf18.x();
    my_vector[3] = vf18.z();
  }

  // vmulax.yw acc, vf0, vf0
  // vmulay.xz acc, vf27, vf11
  // vmadd.xyzw vf11, vf1, vf11
  mat[1].x() += vf27s.x() * mat[1].y();
  mat[1].z() += vf27s.z() * mat[1].y();

  // ppacw s2, r0, s2
  // vmulax.yw acc, vf0, vf0
  // vmulay.xz acc, vf27, vf12
  // vmadd.xyzw vf12, vf1, vf12
  mat[2].x() += vf27s.x() * mat[2].y();
  mat[2].z() += vf27s.z() * mat[2].y();

  // Grecharged-foliage-wind2: hand the two shear magnitudes back for the audit (see the parameter
  // comment). With the toggle OFF, shear_boost is the literal 1.0f and shear_add is nullptr, so
  // vf27s IS vf27 and the two values below are bit-identical — which is exactly how the audit line
  // proves OFF == stock at RUNTIME rather than by reading the source.
  if (audit_out) {
    audit_out[0] = std::sqrt(vf27.x() * vf27.x() + vf27.z() * vf27.z());
    audit_out[1] = std::sqrt(vf27s.x() * vf27s.x() + vf27s.z() * vf27s.z());
    audit_out[2] = vf27s.x();
    audit_out[3] = vf27s.z();
    audit_out[4] = vf27.x();
    audit_out[5] = vf27.z();
    // [6] etat brut du ressort AVANT stiffness ; [7] 1.0 si une composante a tape la butee.
    audit_out[6] = std::sqrt(rc_pre_x * rc_pre_x + rc_pre_z * rc_pre_z);
    audit_out[7] = (rc_pre_x > 1.f || rc_pre_x < cw || rc_pre_z > 1.f || rc_pre_z < cw) ? 1.f : 0.f;
  }

  //
  // if not paused
  // sd s3, 8(s5)
  // sd s2, 0(s5)
}

// Grecharged-foliage-wind3 : REAPPLIQUER le cisaillement deja calcule, sans integrer.
// Utilise sur une image qui ne porte AUCUN tick de logique (pas fixe arme, affichage au-dessus de
// 60 Hz : `time-adjust-ratio` vaut alors 0 et `wind-time` n'avance pas). Ne rien appliquer ferait
// revenir l'arbre a sa pose droite pour une image — un clignotement d'une image, pire que le
// defaut qu'on corrige. `my_vector[0..1]` porte EXACTEMENT le `vf27` ecrit par le dernier pas
// (do_wind_math ci-dessus), donc il n'y a rien a recalculer.
static void fw_apply_persisted_shear(u16 wind_idx,
                                     const float* wind_vector_data,
                                     float shear_boost,
                                     const float* shear_add,
                                     std::array<math::Vector4f, 4>& mat,
                                     float* audit_out) {
  const float* my_vector = wind_vector_data + (4 * wind_idx);
  const math::Vector4f vf27(my_vector[0], 0.f, my_vector[1], 0.f);
  math::Vector4f vf27s = vf27 * shear_boost;
  if (shear_add) {
    vf27s.x() += shear_add[0];
    vf27s.z() += shear_add[1];
  }
  for (int r = 0; r < 3; r++) {
    mat[r].x() += vf27s.x() * mat[r].y();
    mat[r].z() += vf27s.z() * mat[r].y();
  }
  if (audit_out) {
    audit_out[0] = std::sqrt(vf27.x() * vf27.x() + vf27.z() * vf27.z());
    audit_out[1] = std::sqrt(vf27s.x() * vf27s.x() + vf27s.z() * vf27s.z());
    audit_out[2] = vf27s.x();
    audit_out[3] = vf27s.z();
    audit_out[4] = vf27.x();
    audit_out[5] = vf27.z();
    // Aucune integration n'a eu lieu : il n'y a pas d'etat brut neuf a publier, et surtout pas de
    // NOUVELLE saturation a compter. Publier 0 ici gonflerait l'echantillon sans rien mesurer, donc
    // on republie l'etat persiste et on declare la butee non touchee.
    audit_out[6] = audit_out[0];
    audit_out[7] = 0.f;
  }
}

void Tie3::render_tree_wind(int idx,
                            int geom,
                            const TfragRenderSettings& settings,
                            SharedRenderState* render_state,
                            ScopedProfilerNode& prof) {
  auto& tree = m_trees.at(geom).at(idx);
  if (tree.wind_draws->empty()) {
    return;
  }

  // note: this isn't the most efficient because we might compute wind matrices for invisible
  // instances. TODO: add vis ids to the instance info to avoid this
  memset(tree.wind_matrix_cache.data(), 0, sizeof(float) * 16 * tree.wind_matrix_cache.size());
  // Grecharged-foliage-wind2: belt-and-braces for the audit's per-instance history. update_load
  // sizes this next to wind_matrix_cache; sizing it here too means no ordering assumption between
  // the two can turn an instrumentation array into an out-of-bounds write.
  if (tree.fw_prev_shear.size() < tree.instance_info->size() * 4) {
    tree.fw_prev_shear.assign(tree.instance_info->size() * 4, 0.f);
    tree.fw_prev_valid = false;
  }
  auto& cam_bad = settings.camera.camera;
  std::array<math::Vector4f, 4> cam;
  for (int i = 0; i < 4; i++) {
    cam[i] = cam_bad[i];
  }

  // Grecharged-foliage-wind: when the toggle is ON, amplify the per-instance TIE wind shear so the
  // jak1 palms/foliage react to a stronger-but-still-light breeze. The boost is applied ONLY to the
  // matrix shear inside do_wind_math (the integrator state stays stock — boosting stiffness is
  // self-cancelling via the restoring feedback). OFF => boost 1.0 => byte-identical stock
  // arithmetic. Live-tunable for A/B (prop/env), clamped to a sane range.
  float rc_wind_boost = 1.0f;
  // Grecharged-foliage-wind2: additive procedural breeze (see foliage_wind_tie_amp above). rc_amp
  // stays 0 when the toggle is OFF, and 0 means the additive pointer is never handed to
  // do_wind_math => the stock code path, bit for bit.
  float rc_amp = 0.0f;
  float rc_frond = 0.0f;
  float rc_t = 0.0f;
  // Breeze heading: follow the game's own wandering wind direction so the sway agrees with anything
  // else driven by it; fall back to a fixed diagonal if the level never fills it in.
  float rc_dir_x = 0.7071f, rc_dir_z = 0.7071f;
  // Grecharged-foliage-wind3 (defaut D1) : combien de pas de 1/60 s cette image DESSINEE porte.
  // Lu sur `wind-time`, que GOAL avance d'un cran par pas de 1/60 s depuis cette phase. HORS du
  // basculement Recharged : l'owner demande que la brise NATIVE marche par defaut. A 60 images/s
  // le delta vaut 1 et tout ce qui suit est le chemin d'avant, au bit pres.
  const u32 rc_wt_now = m_wind_data.wind_time;
  if (m_wind_ticks_frame != render_state->frame_idx) {
    m_wind_ticks_frame = render_state->frame_idx;
    m_wind_ticks = fw_wind_ticks(rc_wt_now, m_wind_last_time, m_wind_time_seeded,
                                 m_wind_data.paused != 0);
  }
  const int rc_ticks = m_wind_ticks;
  bool rc_on = false;
  if (Gfx::recharged_active(Gfx::g_global_settings.recharged_foliage_wind)) {
    rc_on = true;
    rc_wind_boost = foliage_wind_tie_mult();  // helper above, default 1.0 (neutral)
    rc_amp = foliage_wind_tie_amp();          // helper above, additive breeze shear
    rc_frond = foliage_wind_frond();          // helper above, per-vertex leaf flutter
    rc_t = foliage_wind_clock(render_state->frame_idx, m_wind_data.paused != 0);
    const float dx = m_wind_data.wind_normal.x();
    const float dz = m_wind_data.wind_normal.z();
    const float dlen = std::sqrt(dx * dx + dz * dz);
    if (dlen > 1e-3f) {
      rc_dir_x = dx / dlen;
      rc_dir_z = dz / dlen;
    }
    static bool s_logged = false;
    if (!s_logged) {
      s_logged = true;
      // Renderer-side proof line (no captures): if this never appears the feature did not run.
      lg::info("[foliage-wind] TIE breeze ACTIVE mult={} tie_amp={} frond={} instances={}",
               rc_wind_boost, rc_amp, rc_frond, tree.instance_info->size());
    }
  }
  {
    // Preuve de cablage de D1, une ligne par course : si `ticks` ne monte jamais au-dessus de 1
    // sur un appareil qui rend a 15 images/s, le correctif n'agit pas.
    static bool s_rate_logged = false;
    if (!s_rate_logged && rc_ticks > 1) {
      s_rate_logged = true;
      lg::info("[foliage-wind] NATIVE RATE actif : cette image porte {} pas de 1/60 s "
               "(wind_time={}) — la brise de ND n'avance plus a la cadence de l'affichage",
               rc_ticks, rc_wt_now);
    }
  }

  for (size_t inst_id = 0; inst_id < tree.instance_info->size(); inst_id++) {
    auto& info = tree.instance_info->operator[](inst_id);
    auto& out = tree.wind_matrix_cache[inst_id];
    // auto& mat = tree.instance_info->operator[](inst_id).matrix;
    auto mat = info.matrix;

    ASSERT(info.wind_idx * 4 <= m_wind_vectors.size());
    // Grecharged-foliage-wind2: three incommensurate sinusoids (slow lean + sway + light rustle)
    // along the wind heading, plus a smaller cross-axis term so crowns trace ellipses instead of
    // sliding on a line. The per-instance golden-angle phase keeps neighbouring palms from moving
    // in lockstep (which reads as the whole level sliding, not as wind).
    float rc_shear_add[2];
    const float* rc_add_ptr = nullptr;
    if (rc_amp > 0.0f) {
      const float p = (float)inst_id * 2.3999632f;  // golden angle
      // Grecharged-foliage-wind2 SPECTRUM REBALANCE. The round-2 weights put 55% of the amplitude
      // budget on the 0.14 Hz term — a SEVEN-SECOND lean. A seven-second oscillation has almost no
      // per-frame velocity, so the eye reads it as a tree that is simply standing at an angle: the
      // amplitude was spent where it cannot be seen. Moving weight to the 0.45 Hz band raises the
      // perceptually salient share from 0.45 to 0.70 (+55% visible motion) at an UNCHANGED peak
      // excursion, which is the opposite trade to "make it bigger" — the palm does not lean any
      // further, it just gets there and back at a speed the eye resolves. Same lesson the shrub
      // path already learned with its 1.1 Hz flutter term (shrub.vert).
      const float sway = 0.30f * std::sin(rc_t * 0.8796f + p)                  // 0.14 Hz slow lean
                         + 0.50f * std::sin(rc_t * 2.8274f + 1.7f * p + 0.9f)  // 0.45 Hz main sway
                         + 0.20f * std::sin(rc_t * 6.5973f + 2.3f * p);        // 1.05 Hz rustle
      const float cross = 0.35f * std::sin(rc_t * 1.8850f + 1.3f * p + 2.1f);  // 0.30 Hz cross-axis
      rc_shear_add[0] = rc_amp * (rc_dir_x * sway - rc_dir_z * cross * 0.4f);
      rc_shear_add[1] = rc_amp * (rc_dir_z * sway + rc_dir_x * cross * 0.4f);
      rc_add_ptr = rc_shear_add;
    }
    // Grecharged-foliage-wind2: [0]/[1] = stock/applied shear magnitude, [2..5] = the signed
    // components, which is what the frame-to-frame difference below needs.
    float rc_audit[8] = {0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f};
    const float rc_stiff = info.stiffness * m_wind_multiplier;
    if (rc_ticks <= 0) {
      // Aucun tick de logique sur cette image : on reapplique, on n'integre pas.
      fw_apply_persisted_shear(info.wind_idx, m_wind_vectors.data(), rc_wind_boost, rc_add_ptr, mat,
                               rc_audit);
    } else {
      // `do_wind_math` ACCUMULE dans la matrice d'instance (`mat[0].x() += ...`), donc seul le
      // DERNIER pas a le droit d'y ecrire : laisser chaque sous-pas ecrire appliquerait le
      // cisaillement rc_ticks fois et publierait une tempete que personne ne voit. Les pas
      // intermediaires avancent l'integrateur contre une matrice jetable.
      for (int k = 0; k < rc_ticks - 1; k++) {
        std::array<math::Vector4f, 4> rc_scratch = mat;
        do_wind_math(info.wind_idx, m_wind_vectors.data(), m_wind_data, rc_stiff, 1.0f, nullptr,
                     rc_wt_now - (u32)(rc_ticks - 1) + (u32)k, rc_scratch, nullptr);
      }
      do_wind_math(info.wind_idx, m_wind_vectors.data(), m_wind_data, rc_stiff, rc_wind_boost,
                   rc_add_ptr, rc_wt_now, mat, rc_audit);
    }
    {
      float* prev = &tree.fw_prev_shear[inst_id * 4];
      const float dax = rc_audit[2] - prev[0], daz = rc_audit[3] - prev[1];
      const float dsx = rc_audit[4] - prev[2], dsz = rc_audit[5] - prev[3];
      fw_audit_accum(m_level_name, rc_audit[0], rc_audit[1], tree.fw_prev_valid,
                     std::sqrt(dsx * dsx + dsz * dsz), std::sqrt(dax * dax + daz * daz),
                     rc_audit[6], rc_audit[7] > 0.5f);
      prev[0] = rc_audit[2];
      prev[1] = rc_audit[3];
      prev[2] = rc_audit[4];
      prev[3] = rc_audit[5];
    }

    // vmulax.xyzw acc, vf20, vf10
    // vmadday.xyzw acc, vf21, vf10
    // vmaddz.xyzw vf10, vf22, vf10
    out[0] = cam[0] * mat[0].x() + cam[1] * mat[0].y() + cam[2] * mat[0].z();

    // vmulax.xyzw acc, vf20, vf11
    // vmadday.xyzw acc, vf21, vf11
    // vmaddz.xyzw vf11, vf22, vf11
    out[1] = cam[0] * mat[1].x() + cam[1] * mat[1].y() + cam[2] * mat[1].z();

    // vmulax.xyzw acc, vf20, vf12
    // vmadday.xyzw acc, vf21, vf12
    // vmaddz.xyzw vf12, vf22, vf12
    out[2] = cam[0] * mat[2].x() + cam[1] * mat[2].y() + cam[2] * mat[2].z();

    // vmulax.xyzw acc, vf20, vf13
    // vmadday.xyzw acc, vf21, vf13
    // vmaddaz.xyzw acc, vf22, vf13
    // vmaddw.xyzw vf13, vf23, vf0
    out[3] = cam[0] * mat[3].x() + cam[1] * mat[3].y() + cam[2] * mat[3].z() + cam[3];
  }

  auto shader_id = ShaderId::TIE_WIND;
  first_tfrag_draw_setup(settings.camera, render_state, shader_id);
  // Grecharged-foliage-wind2: per-vertex FROND FLUTTER uniforms (tie_wind.vert). The matrix shear
  // above swings a palm rigidly; this is what actually makes the leaves move. u_fw_amp == 0 (toggle
  // OFF) makes the shader skip the whole block, so OFF renders the stock vertex path.
  // wind_draws vertices are PROTOTYPE-LOCAL (TieTree::unpack leaves matrix_idx == -1 groups
  // untransformed and this pass supplies the instance matrix as `camera`), which is what lets the
  // shader use distance-from-the-trunk-axis as the flutter weight.
  const GLuint fw_prog = render_state->shaders[shader_id].id();
  const GLint fw_amp_loc = glGetUniformLocation(fw_prog, "u_fw_amp");
  const GLint fw_time_loc = glGetUniformLocation(fw_prog, "u_fw_time");
  const GLint fw_phase_loc = glGetUniformLocation(fw_prog, "u_fw_phase");
  if (fw_amp_loc >= 0) {
    glUniform1f(fw_amp_loc, rc_frond);
  }
  if (fw_time_loc >= 0) {
    glUniform1f(fw_time_loc, rc_t);
  }
  // Grecharged-foliage-wind2: the flutter's one silent-failure mode. If the linked TIE_WIND program
  // does not expose these uniforms (shader blob stale, or the block optimised away), every
  // glUniform1f above is skipped and the leaves simply never deform — with no error anywhere.
  // A location of -1 in this line is that failure, stated out loud.
  {
    static bool s_fw_uni_logged = false;
    if (!s_fw_uni_logged) {
      s_fw_uni_logged = true;
      lg::info("[foliage-wind] TIE flutter uniforms amp_loc={} time_loc={} phase_loc={} (all >= 0 "
               "means the round-2 per-vertex flutter is live in the linked program)",
               fw_amp_loc, fw_time_loc, fw_phase_loc);
    }
  }
  tree.fw_prev_valid = true;  // the previous-frame shears are now populated for every instance
  // Grecharged-foliage-wind3 : `on=` porte l'etat REEL du basculement, pas `frond>0 || amp>0`.
  // Le tour precedent avait NOMME ce defaut d'etiquette dans ses « honest gaps » sans le corriger :
  // une course avec le basculement ALLUME et les amplitudes mises a 0 par les proprietes vivantes
  // s'etiquetait `on=0`, donc une ligne qui n'etait PAS le chemin stock se presentait comme telle.
  fw_audit_tick(m_level_name, render_state->frame_idx, rc_on, rc_frond,
                tree.wind_draws->size(), m_wind_data.paused, m_wind_data.wind_time, rc_ticks);
#ifdef OG_FEAT_PBR
  // Round-3 defect A/B: wind-tie foliage receives the sun N.L in-shader; bind the shadow
  // receiver so it also RECEIVES cast shadows. TIE_WIND is the active program here.
  if ((Gfx::recharged_active(Gfx::g_global_settings.recharged_pbr_enable) ||
       Gfx::recharged_active(Gfx::g_global_settings.recharged_rt_light_enable)) &&
      pbr_shadow_state().valid) {
    pbr_shadow_bind_receiver(render_state->shaders[ShaderId::TIE_WIND].id(),
                             settings.camera.trans.data());
  }
  // ★ ROUND 22 (owner defect A): the wind path never bound PBR material maps, so every
  // wind-animated TIE object was structurally flat. tie_wind.frag now carries the same shared
  // fused chunk tfrag3.frag does, so the material bind runs here too — same PbrDrawList (the
  // wind draws index the SAME level texture table as the static TIE draws), same binder.
  PbrDrawBinder pbr_binder;
  pbr_binder.begin(render_state->shaders[ShaderId::TIE_WIND].id(), &m_pbr_draws);
  // [cover] the wind program is not the tess program, so every height-mapped wind draw must land
  // in disp_pom. Distinct renderer label so the coverage census separates it from static TIE.
  pbr_binder.set_coverage_context("tie_wind", nullptr, false, render_state->frame_idx);
#endif
  glBindVertexArray(tree.vao);
  glBindBuffer(GL_ARRAY_BUFFER, tree.vertex_buffer);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,
               render_state->no_multidraw ? tree.single_draw_index_buffer : tree.index_buffer);

  glActiveTexture(GL_TEXTURE10);
  // Gperf-particles round 3: bind the TOD texture selected at update time (the
  // ping-pong current, or the single texture when the flag is off).
  glBindTexture(GL_TEXTURE_2D, tree.tod_current);

  glActiveTexture(GL_TEXTURE0);
#ifdef __ANDROID__
  // GLES has no settable restart index (see render_tree_category above); the
  // fixed-index mode restarts on all-ones = UINT32_MAX for our u32 buffers.
  glEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX);
#else
  glEnable(GL_PRIMITIVE_RESTART);
  glPrimitiveRestartIndex(UINT32_MAX);
#endif

  // Gperf-particles: per-draw GL state cache (flag-off = identical old path).
  BgDrawStateCache draw_state_cache;
  GLuint bound_tex = 0;

  int last_texture = -1;
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree.wind_vertex_index_buffer);

  for (size_t draw_idx = 0; draw_idx < tree.wind_draws->size(); draw_idx++) {
    const auto& draw = tree.wind_draws->operator[](draw_idx);

    // Grecharged-mesh-browser V2.1: the wind path had NO target hook at all — a targeted
    // wind-animated TIE (palms, foliage) ignored hide AND checker, exactly the owner's "every
    // toggle dead" on those meshes. Same (system 1, tree_tex_id, level) identity as the static
    // TIE draws (the wind draws index the SAME level texture table — see the PBR note above).
    const bool mb_targeted = mb_draw_targeted(1, draw.tree_tex_id, m_level_name.c_str());
    if (mb_targeted && Gfx::g_global_settings.mb_hide_target) {
      // whole-draw skip: per-draw index offsets come from wind_vertex_index_offsets[draw_idx],
      // so skipping one draw shifts nothing for the others.
      Gfx::g_global_settings.mb_ctr_hidden_draws++;
      continue;
    }
    if (!mb_targeted && Gfx::g_global_settings.mb_target_active) {
      if (Gfx::g_global_settings.mb_isolate) {
        Gfx::g_global_settings.mb_cur_isolated_skips++;
        continue;  // isolation: only the targeted mesh renders
      }
      Gfx::g_global_settings.mb_cur_nontarget_draws++;  // per-frame proof: non-target draws submitted
    }
    if (mb_targeted) {
      Gfx::g_global_settings.mb_cur_target_draws++;  // V2.1 per-frame proof: submitted, not hidden
    }

    if (draw.tree_tex_id != last_texture) {
      if (draw.tree_tex_id >= 0) {
        bound_tex = m_textures->at(draw.tree_tex_id);
      } else {
        bound_tex = ((size_t)(-(draw.tree_tex_id + 1)) < m_anim_slot_array->size() ? m_anim_slot_array->at(-(draw.tree_tex_id + 1)) : 0);
        gj2vis_probe_bg_slot(-(draw.tree_tex_id + 1), bound_tex);
      }
      glBindTexture(GL_TEXTURE_2D, bound_tex);
      last_texture = draw.tree_tex_id;
    }
    auto double_draw =
        setup_tfrag_shader_cached(render_state, draw.mode, shader_id, bound_tex, draw_state_cache);
    const bool mb_checker = mb_targeted && Gfx::g_global_settings.mb_checker_target;
#ifdef OG_FEAT_PBR
    // ROUND 22: per-draw PBR material bind for the wind path (see the binder set up above).
    // InstancedStripDraw::tree_tex_id is the same level texture index the static draws use.
    pbr_binder.set(draw.tree_tex_id, draw.mode, mb_checker);
#endif
    if (mb_checker) {
      // Bind AFTER the cached setup so the draw-mode glTexParameteri calls landed on the draw's
      // own texture (see the static-loop notes); poison last_texture so the NEXT draw rebinds
      // its own texture instead of inheriting the checker.
      glBindTexture(GL_TEXTURE_2D, pbr_testpattern::checker_base_gl());
      last_texture = INT32_MIN;
      Gfx::g_global_settings.mb_ctr_checker_draws++;
      Gfx::g_global_settings.mb_cur_checker_binds++;  // V2.1 per-frame proof
    }

    int off = 0;
    for (auto& grp : draw.instance_groups) {
      if (!m_debug_all_visible && !tree.vis_temp.at(grp.vis_idx)) {
        off += grp.num;
        continue;  // invisible, skip.
      }

      glUniformMatrix4fv(glGetUniformLocation(render_state->shaders[shader_id].id(), "camera"), 1,
                         GL_FALSE, tree.wind_matrix_cache.at(grp.instance_idx)[0].data());
      // Grecharged-foliage-wind2: per-instance flutter phase (same golden-angle decorrelation the
      // CPU shear uses), so two palms side by side never rustle in lockstep. Skipped entirely when
      // the flutter is off.
      if (fw_phase_loc >= 0 && rc_frond > 0.0f) {
        glUniform1f(fw_phase_loc, (float)grp.instance_idx * 2.3999632f);
      }

      prof.add_draw_call();
      prof.add_tri(grp.num);

      glDrawElements(tree.draw_mode, grp.num, GL_UNSIGNED_INT,
                     (void*)((off + tree.wind_vertex_index_offsets.at(draw_idx)) * sizeof(u32)));
      off += grp.num;

      switch (double_draw.kind) {
        case DoubleDrawKind::NONE:
          break;
        case DoubleDrawKind::AFAIL_NO_DEPTH_WRITE: {
          prof.add_draw_call();
          prof.add_tri(grp.num);
          const auto& afail_u = tfrag_alpha_uniforms(render_state->shaders[shader_id].id());
          if (afail_u.alpha_min != -1) {
            glUniform1f(afail_u.alpha_min, -10.f);
          }
          if (afail_u.alpha_max != -1) {
            glUniform1f(afail_u.alpha_max, double_draw.aref_second);
          }
          glDepthMask(GL_FALSE);
          // depth-mask toggled: cached mode's depth state is now stale.
          draw_state_cache.valid = false;
          glDrawElements(tree.draw_mode, draw.vertex_index_stream.size(), GL_UNSIGNED_INT,
                         (void*)0);
          break;
        }
        default:
          ASSERT(false);
      }
    }
  }
#ifdef OG_FEAT_PBR
  // ROUND 22: restore u_pbr_mode to 0 + park the neutral maps so the next TIE_WIND user (another
  // tree, another level) never inherits this tree's last material.
  pbr_binder.finish();
#endif
}

Tie3AnotherCategory::Tie3AnotherCategory(const std::string& name,
                                         int my_id,
                                         Tie3* parent,
                                         tfrag3::TieCategory category)
    : BucketRenderer(name, my_id), m_parent(parent), m_category(category) {}

void Tie3AnotherCategory::draw_debug_window() {
  ImGui::Text("Child of this renderer:");
  m_parent->draw_debug_window();
}

void Tie3AnotherCategory::render(DmaFollower& dma,
                                 SharedRenderState* render_state,
                                 ScopedProfilerNode& prof) {
  auto first_tag = dma.current_tag();
  dma.read_and_advance();
  if (first_tag.kind != DmaTag::Kind::CNT || first_tag.qwc != 0) {
    fmt::print("Bucket renderer {} ({}) was supposed to be empty, but wasn't\n", m_my_id, m_name);
    ASSERT(false);
  }
  m_parent->render_from_another(render_state, prof, m_category);
}

Tie3WithEnvmapJak1::Tie3WithEnvmapJak1(const std::string& name, int my_id, int level_id)
    : Tie3(name, my_id, level_id, nullptr, tfrag3::TieCategory::NORMAL) {}

void Tie3WithEnvmapJak1::render(DmaFollower& dma,
                                SharedRenderState* render_state,
                                ScopedProfilerNode& prof) {
  Tie3::render(dma, render_state, prof);
  if (m_enable_envmap) {
    render_from_another(render_state, prof, tfrag3::TieCategory::NORMAL_ENVMAP);
  }
}

void Tie3WithEnvmapJak1::draw_debug_window() {
  ImGui::Checkbox("envmap", &m_enable_envmap);
  Tie3::draw_debug_window();
}
