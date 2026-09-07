#include "game/graphics/refset.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

#include "common/util/FileUtil.h"

#include "game/graphics/fixed_tick.h"
#include "game/graphics/origin_ablate.h"
#include "game/graphics/opengl_renderer/lighting_census.h"
#include "game/graphics/render_pace.h"
#include "game/system/autoport_proof.h"
#include "game/system/pad_replay.h"

#include "third-party/fpng/fpng.h"

#if defined(__ANDROID__)
#include <dlfcn.h>
#include <sys/system_properties.h>
#endif

namespace refset {
namespace {

// ── le plan ─────────────────────────────────────────────────────────────────────────────────
// TROIS jeux x huit creneaux horaires. Les huit heures sont les huit creneaux de
// `mood-lights-table` (SPEC §3.1) espaces de trois heures : c'est la grille sur laquelle la
// donnee de Naughty Dog est art-dirigee.
constexpr int kHours[8] = {0, 3, 6, 9, 12, 15, 18, 21};

struct Step {
  // 1 = ORIGINE-TOTAL (master OFF) ; 2 = RECHARGED (master ON + eclairage ON, prereglage fige) ;
  // 3 = ORIGINE-LUMIERE (master ON, eclairage OFF) — la configuration que le joueur LANCE.
  int phase;
  int hour;
};

// Frames de LOGIQUE. Elles ne dependent pas de la cadence : `pad_replay` force un pas de
// 1/60 s par image des l'ancre.
constexpr int64_t kAnchorSettle = 300;  // 5 s apres le premier warp : le niveau est charge et lie
// Frames de logique entre le TELEPORT d'une etape et sa photo. Reglable par
// `OG_REFSET_SETTLE` : c'est le seul curseur du compromis « la camera n'a pas encore diverge »
// contre « l'heure et le lissage de la lumiere sont poses ». Le regler ne demande pas de rebatir.
int64_t g_step_settle = 180;
// L'INSTANT ABSOLU DU PREMIER TELEPORT (frames de LOGIQUE). Voir `warp_at_frame` dans refset.h :
// le delai apres readiness de `level_warp_maybe` depend du disque, et son ecart d'UNE frame
// entre la capture et le rejeu du 2026-09-06 a suffi a rendre `refpix_maxdiff_origine=232`.
// LA VALEUR N'EST PAS LIBRE VERS LE HAUT. Essayee a 900, la course MEURT avant le teleport :
// mesure du 2026-09-06 sur eae4df44, `signal 4` a la frame 782 avec `A36-TREE at-crash
// viol-total=0` — donc PAS la corruption d'arbre du teleport repete, un autre defaut, atteint
// en restant 300 images de plus sur l'ecran-titre. On ne repousse donc pas l'instant : on le
// FIXE la ou il tombait deja. Mesure des deux courses precedentes : `warp1 lf=600` puis
// `lf=599`, c'est-a-dire readiness atteinte des la premiere image et 600 ticks de delai. 600 en
// frames de LOGIQUE reproduit cet instant sans heriter de la vitesse du disque.
int64_t g_warp_at = 600;

constexpr int kShotW = 320;
constexpr int kShotH = 180;

std::mutex g_mutex;

int g_mode = 0;  // 0 = eteint, 1 = capture, 2 = replay
// lighting-hdr : le dossier par defaut DIFFERE par plateforme, et ce n'est pas une precaution
// de style. Les references x86 sont re-rendues en 320x180 en resolution interne ; celles de
// l'appareil sont un sous-echantillonnage d'un tampon 4:3. Comparer les unes aux autres est faux
// PAR CONSTRUCTION. On rend donc le melange impossible au point de PRODUCTION plutot que
// detectable au point de controle : les deux familles ne portent pas le meme nom.
std::string g_dir = ".autoport/refset";  // Android : rendu ABSOLU a l'init, voir `enabled()`

std::vector<int> g_phases;  // lighting-hdr : les phases que CE plan execute
std::vector<Step> g_steps;
size_t g_cur = 0;  // etape en cours
bool g_finished = false;

int g_tod_x100 = -1;

// lighting-hdr essai 7 — LE FEU DE LA HUTTE A UNE SECONDE HORLOGE, ET ELLE BAT PAR IMAGE
// DESSINEE. `update-mood-flames` (mood.gc:366) incremente un compteur prive de `flames-state`
// une fois par appel, et son appelant `update-time-of-day` pend a `real-main-draw-hook`
// (drawable.gc:839), DEHORS de la boucle de rattrapage : il tourne donc une fois par image
// DESSINEE, pas par frame de logique. Le poids qu'il produit (`times[5].w`) part dans
// `interp_time_of_day` et repeint tfrag, tie, shrub, hfrag et l'herbe autour du foyer — une
// region large, douce, de signe alterne. C'est EXACTEMENT la classe de defaut deja fermee pour
// les particules, le vent et l'herbe, et elle etait restee ouverte pour le mood.
// Au passage : le rebouclage de l'etat consomme trois tirages de `rand-vu` (mood.gc:357-361),
// donc un decalage d'images dessinees decale aussi le flux d'alea de TOUS les autres
// consommateurs.
// LE GESTE : sous refset, l'etat de flamme est repose a une valeur FIXE a chaque appel — meme
// phase, meme hauteur, meme longueur pour les 24 photos. Le feu reste dessine et reste la haute
// lumiere dominante ; on retire son scintillement de la comparaison, pas l'objet mesure. Hors
// refset, `mood_flame_pin()` rend -1 et le chemin d'origine est intact.
constexpr int kMoodPinTime = 3;  // 3/12 de periode : sin(45 deg) = 0,707, ni zero ni sommet
uint64_t g_mood_calls = 0;       // appels a `mood_flame_pin()` depuis le debut de la course
uint64_t g_mood_pins = 0;        // ... dont ceux qui ont reellement repose l'etat
uint64_t g_mood_last_photo = 0;  // valeur de `g_mood_calls` a la photo precedente
uint64_t g_mood_span_min = ~0ull;  // images DESSINEES entre deux photos : le minimum
uint64_t g_mood_span_max = 0;      // ... et le maximum. min != max => la fuite etait vivante.
// L'INVITE 2D DU MAIRE. Contrat et mesure : refset.h. `g_text_last_lf` est la derniere frame
// de LOGIQUE ou `print-game-text` a ete appele ; comparee a celle de la photo, elle dit si le
// texte etait a l'ecran a cet instant precis, sans supposer quoi que ce soit de sa cadence.
uint64_t g_text_calls = 0;          // appels a `text_mute()` depuis le debut de la course
uint64_t g_text_muted = 0;          // ... dont ceux qui ont reellement force le mode no-draw
int64_t g_text_last_lf = -1;        // frame de logique du dernier appel
uint64_t g_text_steps_with = 0;     // photos ou le texte AURAIT ete dessine
uint64_t g_text_steps_without = 0;  // ... et celles ou non

// ── demande de capture, du fil GOAL vers le fil graphique ───────────────────────────────────
// UN SEUL automate, et pas trois booleens. Avec trois booleens le fil graphique pouvait
// re-armer la meme demande entre la fin d'une capture et le passage du fil GOAL a l'etape
// suivante : mesure du 2026-09-06, 16 captures annoncees pour 10 fichiers ecrits, les heures
// 03, 15 et 21 SAUTEES dans les deux jeux. Une etape sautee est une reference manquante, et
// une reference manquante rend la porte inoperante sur ce creneau.
enum CapState { kCapIdle = 0, kCapWaitWarp, kCapArmed, kCapInFlight, kCapDone };
int g_cap = kCapIdle;
int64_t g_capture_frame = -1;      // la chaine attendue porte cette frame de logique
std::string g_capture_name;        // <jeu>/h<hh>

// ── horloge de logique ──────────────────────────────────────────────────────────────────────
// Chaque instant du plan est ancre sur un EVENEMENT (un teleport), jamais sur « l'image ou j'ai
// remarque que... » : une image de logique non rendue ne decale donc rien.
int64_t (*g_logic_fn)() = nullptr;
// UN TELEPORT PAR ETAPE. Le point de repos de la camera depend du chemin : deux courses
// identiques le trouvent a ~0,02 m l'une de l'autre, ce qui suffit a rendre la moitie des pixels
// differents. Un `(start 'play <continue>)` juste avant chaque photo remet la camera a une pose
// TELEPORTEE, et la photo est prise assez tot pour que la derive n'ait pas eu le temps de
// s'installer.
// lighting-hdr essai 6 : le re-ancrage des lanceurs de particules et le gel de leur temps.
// Contrat, chiffres et raison : refset.h, section « LES DEUX GESTES ».
bool g_repin_done = false;
uint64_t g_repins = 0;
int64_t g_repin_lf = -1;
uint64_t g_frozen_frames = 0;
int64_t g_frozen_first_lf = -1;
int64_t g_part_step_lf = -1;
uint64_t g_part_steps = 0;
uint64_t g_part_extra = 0;
int64_t g_warp1 = -1;             // premier warp : sert seulement a savoir que le niveau est la
bool g_rewarp_asked = false;      // une demande de teleport est en vol
int64_t g_rewarp_asked_lf = -1;   // depuis quand : une demande perdue doit se re-poser
int64_t g_step_anchor = -1;       // frame de logique du teleport de l'etape courante
uint64_t g_rewarps = 0;
// UN TELEPORT PAR ETAPE, OU UN SEUL POUR TOUT LE PLAN ? Sur arm64 le plan MEURT au troisieme
// `(start 'play <continue>)` : mesure du 2026-09-06 sur eae4df44, les etapes 0 et 1 capturent
// (`REFSET cap origine/h00`, `h03`) puis
//     GK-DIAG A36-TREE VIOLATION frame=755 tree-self a=0x1dcbd8 b=0x2189d4
//     Process exited due to signal 4
// — une corruption de l'arbre de processus ANTERIEURE a cet item (le scanner d'integrite
// nomme le premier maillon rompu ; il ne fait que LIRE). x86 encaisse les 24 teleports, arm64
// non. Le defaut appartient au redemarrage repete de niveau, pas au jeu de references : on ne
// le corrige pas ici, on cesse de le declencher 24 fois.
// CE QUE LE TELEPORT ACHETAIT reste acquis : le premier re-teleport (etape 0) a toujours lieu,
// et c'est LUI qui rend la pose de la camera independante du chemin de chargement (voir le
// bloc `wants_rewarp` dans refset.h). Les 23 suivants ne faisaient que la re-poser a
// l'identique. Ce qui reste a la charge du determinisme entre deux courses : le pas de temps
// fixe et les graines de `pad_replay`, l'heure du jeu reposee a chaque image, et la
// neutralisation de `render_pace` — tous deja mesures et publies.
// Defaut : 1 sur bureau (le registre de `refset-replay-stable` a ete etabli comme ca, on ne
// change pas la definition de l'instrument sous ses cinq rejeux), 0 sur appareil.
int g_warp_per_step = 1;
// L'ANCRE DU PLAN : la frame de logique du re-teleport de l'etape 0. Quand il n'y a pas de
// teleport par etape, l'instant de chaque photo est CALCULE depuis elle
// (`base + (k+1) * settle`) et jamais lu sur l'horloge au moment ou l'etape s'arme. La
// difference n'est pas cosmetique : l'etape k+1 ne s'arme qu'apres que le fil GRAPHIQUE a
// consomme la photo de l'etape k, donc une lecture d'horloge la ferait dependre de
// l'entrelacement des deux fils — une frame de logique d'ecart, c'est une autre pose de Jak,
// et `refset.h` chiffre deja ce que ca coute (27000 pixels sur 57600).
int64_t g_plan_base = -1;
uint64_t g_late_arms = 0;  // etapes armees APRES leur instant theorique : le plan a pris du retard
// LA CADENCE DU PLAN, ET SON DE-DOUBLONNAGE. Voir `begin_logic_frame` dans refset.h : le plan
// s'avance une fois par frame de LOGIQUE, depuis la lecture de la manette 0, et l'appel depuis
// l'image RENDUE n'est plus qu'un repli. Les deux compteurs disent lequel a reellement cadence.
int64_t g_pumped_lf = -2;
uint64_t g_pump_logic = 0;
uint64_t g_pump_render = 0;
// L'ORDRE DES ETAPES. Voir `enabled()` : par CRENEAU sur appareil (les trois configurations d'une
// meme heure se suivent), par JEU sur bureau (l'instrument de `refset-replay-stable` ne se
// redefinit pas sous ses cinq rejeux).
int g_order_by_hour = 0;
uint64_t g_slip_nonzero = 0;  // captures dont la chaine ne portait PAS la frame demandee
// La frame de logique que porte la chaine EN VOL. Posee par `capture_for_chain` (fil
// GRAPHIQUE, sous le verrou) : `consume_capture` tourne sur ce meme fil et ne peut donc pas
// appeler `current_logic_frame()`, qui lit la memoire GOAL et n'est licite que du fil GOAL.
int64_t g_inflight_lf = -1;

// ── mesures ─────────────────────────────────────────────────────────────────────────────────
uint64_t g_captured = 0;
// L'alpha BRUT du retimeur de rendu, echantillonne une fois par image dessinee. Voir
// `publish_state` : c'est la mesure de ce que la course de reference supprime.
int64_t g_raw_alpha_min = 1 << 30;
int64_t g_raw_alpha_max = -1;
uint64_t g_raw_alpha_n = 0;
uint64_t g_compared = 0;
uint64_t g_missing = 0;
uint64_t g_size_bad = 0;
uint64_t g_decode_bad = 0;
uint64_t g_roundtrip_bad = 0;
uint64_t g_maxdiff = 0;
uint64_t g_diffpx = 0;
// Le maximum PAR JEU. `refset_replay_maxdiff` melange les deux : une regression du seul jeu
// RECHARGED et une derive de la camera qui touche les deux rendent le meme nombre. Les items
// de la refonte doivent pouvoir citer les deux separement (SPEC §7.2, item 1 :
// `refpix_maxdiff_origine` et `refpix_maxdiff_recharged` sont sa condition de sortie).
// lighting-hdr : TROIS jeux desormais (SPEC §7.3). Indices 1..3, la case 0 n'est pas utilisee.
uint64_t g_maxdiff_phase[4] = {0, 0, 0, 0};
uint64_t g_compared_phase[4] = {0, 0, 0, 0};
int64_t g_frame_slip_max = 0;
int64_t g_frame_slip_min = 1 << 20;
// LE REGISTRE DE REJEUX. `refset_replay_flaky` compare des COURSES, pas des images : il ne peut
// donc pas se calculer dans une seule course. Le moteur tient un registre sur disque et publie
// le verdict qu'il en lit. Tant qu'il n'a pas ete ecrit, `publish_state` publie la sentinelle.
bool g_flaky_done = false;

// lighting-hdr : le TROISIEME jeu, ORIGINE-LUMIERE (SPEC §0.2, §7.3). Il existe parce que ni
// ORIGINE-TOTAL ni RECHARGED n'exercaient la configuration que le joueur LANCE : master ON,
// eclairage de la refonte OFF. Deux bras verts, la condition absente — c'est exactement la ou
// l'owner a trouve les blancs brules le 2026-09-06.
const char* set_name(int phase) {
  if (phase == 1) {
    return "origine";
  }
  return phase == 2 ? "recharged" : "origine-lumiere";
}

// `setenv` n'existe pas sur MSVC ; le seul appelant est ce module.
void put_env(const char* key, const char* value) {
#if defined(_WIN32)
  _putenv_s(key, value);
#else
  setenv(key, value, 1);
#endif
}

bool read_knob(const char* env, const char* prop, char* out, size_t cap) {
  if (const char* e = std::getenv(env)) {
    if (e[0]) {
      std::snprintf(out, cap, "%s", e);
      return true;
    }
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    std::snprintf(out, cap, "%s", buf);
    return true;
  }
#else
  (void)prop;
#endif
  return false;
}

// ── lighting-hdr : les grandeurs des verdicts 1, 2 et 5 ─────────────────────────────────────
// Elles se mesurent SUR CE QUI EST DESSINE (le tampon relu), jamais sur une table source, et
// elles sont ENTIERES de bout en bout : un arrondi flottant dont le mode depend du compilateur
// rendrait deux courses du meme binaire non comparables, et c'est exactement la classe de
// defaut que refset-replay-stable vient de fermer.
// Le jeu de REFERENCE de ces trois verdicts est ORIGINE-LUMIERE (phase 3) : la configuration
// que l'owner joue. Comparer RECHARGED a ORIGINE-TOTAL melangerait l'eclairage avec les
// modeles HD, l'herbe et les textures.
struct StepStats {
  bool measured = false;
  uint64_t px = 0;           // pixels examines
  uint64_t sat_px = 0;       // au moins un canal a 255 — la part qui a perdu toute gradation
  uint64_t sat_white_px = 0; // les TROIS canaux a 255 — le « blanc brule » que l'owner decrit
  uint64_t contrast_x1000 = 0;  // contraste local moyen du decile le plus lumineux
  uint64_t decile_px = 0;    // combien de pixels ce decile contenait
  // LE DENOMINATEUR DES VERDICTS 1 ET 2 : la frame de LOGIQUE de la photo. Les deux verdicts
  // apparient RECHARGED et ORIGINE-LUMIERE au meme creneau ; l'ecart de frames entre les deux
  // photos est ce qui melange l'effet de la courbe et celui du temps qui passe. Sans lui,
  // `hdr_hlc_pct_h21=92` ne dit pas si la courbe a ecrase le detail ou si 1440 images de logique
  // ont deplace ce qui bouge dans le decor.
  int64_t cap_lf = -1;
};
StepStats g_stats[4][8];  // [phase 1..3][index de creneau 0..7]

int hour_index(int hour) {
  for (int i = 0; i < 8; i++) {
    if (kHours[i] == hour) {
      return i;
    }
  }
  return -1;
}

// Luminance entiere en 0..255, ponderation Rec.601 en virgule fixe.
inline uint32_t luma(const uint8_t* p) {
  return (uint32_t)((77u * p[0] + 150u * p[1] + 29u * p[2]) >> 8);
}

void measure_step(int phase, int hour, int64_t cap_lf, const uint8_t* px, int w, int h) {
  const int hi = hour_index(hour);
  if (phase < 1 || phase > 3 || hi < 0 || w < 3 || h < 3) {
    return;
  }
  StepStats st;
  const int64_t n = (int64_t)w * h;
  st.px = (uint64_t)n;

  // Saturation, et histogramme de luminance pour trouver le decile.
  uint64_t hist[256] = {0};
  for (int64_t i = 0; i < n; i++) {
    const uint8_t* p = px + i * 4;
    if (p[0] == 255 || p[1] == 255 || p[2] == 255) {
      st.sat_px++;
      if (p[0] == 255 && p[1] == 255 && p[2] == 255) {
        st.sat_white_px++;
      }
    }
    hist[luma(p)]++;
  }

  // Le seuil du decile le plus lumineux : le plus petit T tel que #{L >= T} <= n/10. On garde
  // le T juste EN DESSOUS, pour que le decile contienne au moins n/10 pixels.
  const uint64_t want = (uint64_t)(n / 10);
  uint64_t acc = 0;
  int thr = 255;
  for (int v = 255; v >= 0; v--) {
    acc += hist[v];
    if (acc >= want) {
      thr = v;
      break;
    }
  }

  // Contraste local : gradient de Manhattan sur le voisin droit et le voisin bas, moyenne sur
  // les seuls pixels du decile. Une zone ecrasee a blanc plat rend zero — c'est precisement le
  // detail que la courbe doit preserver.
  uint64_t gsum = 0, gn = 0;
  for (int y = 0; y + 1 < h; y++) {
    for (int x = 0; x + 1 < w; x++) {
      const uint8_t* p = px + ((int64_t)y * w + x) * 4;
      const uint32_t l = luma(p);
      if ((int)l < thr) {
        continue;
      }
      const uint32_t lr = luma(px + ((int64_t)y * w + (x + 1)) * 4);
      const uint32_t lb = luma(px + ((int64_t)(y + 1) * w + x) * 4);
      gsum += (uint64_t)(l > lr ? l - lr : lr - l);
      gsum += (uint64_t)(l > lb ? l - lb : lb - l);
      gn++;
    }
  }
  st.decile_px = gn;
  st.contrast_x1000 = gn ? (gsum * 1000ull) / gn : 0ull;
  st.measured = true;
  st.cap_lf = cap_lf;
  g_stats[phase][hi] = st;
  // Les images DESSINEES depuis la photo precedente. C'est la grandeur qui variait sous le plan
  // et que rien ne publiait : le plan compte des frames de LOGIQUE, le mood et la passe de
  // textures comptent des images dessinees.
  {
    const uint64_t span = g_mood_calls - g_mood_last_photo;
    g_mood_last_photo = g_mood_calls;
    if (span < g_mood_span_min) {
      g_mood_span_min = span;
    }
    if (span > g_mood_span_max) {
      g_mood_span_max = span;
    }
  }
  // LE RECENSEMENT DE L'INVITE, ETAPE PAR ETAPE. `print-game-text` est appele a chaque image de
  // logique ou le texte est visible : si le dernier appel porte la frame de la photo (ou celle
  // d'avant, l'appel precedant l'incrementation du compteur), le texte etait a l'ecran. C'est ce
  // partage — dix photos contre quatorze — qui rend la neutralisation non vacue.
  if (cap_lf >= 0 && g_text_last_lf >= 0 && g_text_last_lf + 1 >= cap_lf) {
    g_text_steps_with++;
  } else {
    g_text_steps_without++;
  }
}

uint64_t read_capture_witness(int phase);  // defini plus bas, avec le temoin de capture

// Le temoin de capture est ecrit et relu plus bas (section « LE TEMOIN DE CAPTURE ») ;
// `publish_state` le publie, d'ou cette declaration avant usage.
std::string read_capture_flavour(int phase);

// La SAVEUR du binaire courant : `ablate` = la couche Recharged n'est pas compilee dedans
// (game/graphics/origin_ablate.h), `normal` = le binaire de l'owner.
const char* build_flavour() {
#if AUTOPORT_ORIGIN_ABLATE
  return "ablate";
#else
  return "normal";
#endif
}

void publish_state() {
  autoport_proof::publish_text("refset_mode", g_mode == 1 ? "capture" : "replay");
  // QUEL BINAIRE A PRODUIT CETTE COURSE. `ablate` = la couche Recharged n'est pas compilee
  // dedans ; il ne sert qu'a CAPTURER la reference ORIGINE-TOTAL et il ne peut pas passer la
  // porte (voir `verdict_master_off_bitexact`). Publie hors du bras `g_mode == 2` : une course
  // de capture doit dire elle aussi de quel binaire elle sort.
  autoport_proof::publish_text("origin_build_flavour", build_flavour());
#if defined(__ANDROID__)
  autoport_proof::publish_text("refset_platform", "device");
#else
  autoport_proof::publish_text("refset_platform", "x86");
#endif
  autoport_proof::publish("refset_steps", g_steps.size());
  autoport_proof::publish("refset_step_done", g_cur);
  autoport_proof::publish("refset_step_anchor_set", g_step_anchor >= 0 ? 1 : 0);
  autoport_proof::publish("refset_rewarps", g_rewarps);
  autoport_proof::publish("refset_parts_repins", g_repins);
  autoport_proof::publish("refset_parts_repin_lf", (uint64_t)(g_repin_lf < 0 ? 0 : g_repin_lf));
  autoport_proof::publish("refset_parts_frozen_frames", g_frozen_frames);
  autoport_proof::publish("refset_parts_steps", g_part_steps);
  autoport_proof::publish("refset_parts_extra_calls", g_part_extra);
  autoport_proof::publish("refset_parts_frozen_first_lf",
                          (uint64_t)(g_frozen_first_lf < 0 ? 0 : g_frozen_first_lf));
  autoport_proof::publish("refset_settle", (uint64_t)g_step_settle);
  // L'HORLOGE DU FEU, ET LE CONTROLE DE NON-VACUITE DE SA NEUTRALISATION. `refset_mood_pins`
  // dit que le geste a bien eu lieu ; `refset_mood_span_min/max` disent combien d'images ont
  // ete DESSINEES entre deux photos consecutives. Si ces deux bornes sont egales, la cadence
  // d'affichage etait deja constante et epingler la flamme n'expliquerait rien : c'est la
  // mesure qui tranche, pas ce commentaire.
  autoport_proof::publish("refset_mood_pins", g_mood_pins);
  autoport_proof::publish("refset_mood_calls", g_mood_calls);
  autoport_proof::publish("refset_mood_span_min",
                          g_mood_span_min == ~0ull ? 0 : g_mood_span_min);
  autoport_proof::publish("refset_mood_span_max", g_mood_span_max);
  // L'INVITE 2D, ET LE CONTROLE DE NON-VACUITE DE SA NEUTRALISATION. `refset_text_muted` dit que
  // le geste a eu lieu ; `refset_text_steps_with/_without` disent que le texte etait bien present
  // dans une partie seulement des photos. Un `_with` a 0 ou a 24 rendrait la clause vide.
  autoport_proof::publish("refset_text_calls", g_text_calls);
  autoport_proof::publish("refset_text_muted", g_text_muted);
  autoport_proof::publish("refset_text_steps_with", g_text_steps_with);
  autoport_proof::publish("refset_text_steps_without", g_text_steps_without);
  // La POLITIQUE DE TELEPORT est publiee : deux courses qui ne l'ont pas la meme ne
  // photographient pas les memes poses, et rien d'autre dans la preuve ne le dirait.
  autoport_proof::publish("refset_warp_per_step", (uint64_t)g_warp_per_step);
  autoport_proof::publish("refset_late_arms", g_late_arms);
  // L'instant DEMANDE et l'instant OBTENU pour le premier teleport. Publier le seul demande
  // ne dirait pas si la readiness est arrivee apres : `warp1 != warp_at` = la course a rate
  // son ancre, et tout ce qui suit est incomparable.
  autoport_proof::publish("refset_warp_at", (uint64_t)g_warp_at);
  autoport_proof::publish("refset_warp1_lf", (uint64_t)(g_warp1 < 0 ? 0 : g_warp1));
  autoport_proof::publish("refset_plan_base_lf", (uint64_t)(g_plan_base < 0 ? 0 : g_plan_base));
  autoport_proof::publish("refset_captured", g_captured);
  autoport_proof::publish("refset_slip_max", (uint64_t)(g_frame_slip_max < 0 ? 0
                                                                             : g_frame_slip_max));
  autoport_proof::publish("refset_slip_min",
                          (uint64_t)(g_frame_slip_min > (1 << 19) ? 0 : g_frame_slip_min));
  autoport_proof::publish("refset_roundtrip_bad", g_roundtrip_bad);
  // QUI CADENCE LE PLAN, et combien de photos ont rate leur frame. Sans ces trois lignes,
  // « le plan est cadence sur la frame de logique » est une affirmation que la preuve ne
  // contredit pas : `refset_pump_logic` doit dominer, et `refset_slip_nonzero` doit valoir 0
  // pour qu'une comparaison bit-a-bit ait un sens.
  autoport_proof::publish("refset_pump_logic", g_pump_logic);
  autoport_proof::publish("refset_pump_render", g_pump_render);
  autoport_proof::publish("refset_slip_nonzero", g_slip_nonzero);
  autoport_proof::publish("refset_order_by_hour", (uint64_t)g_order_by_hour);
  // LE RETIMEUR DE RENDU, LU SUR SON ETAT REELLEMENT LATCHE — pas sur notre intention.
  // `render_pace` est la seule entree de montre murale du chemin de dessin : son alpha
  // reecrit la pose DESSINEE de la camera (cam-update.gc:246) et celle des articulations
  // (drawable.gc:1107). Tant qu'il est arme, deux courses identiques ne peuvent pas rendre
  // la meme image, et `refset_replay_maxdiff` le dirait sans dire pourquoi. Ces deux lignes
  // nomment la cause dans la preuve elle-meme : une reference n'est rejouable que capturee
  // et rejouee avec `refset_pace_armed=0`.
  autoport_proof::publish("refset_pace_armed", render_pace::armed() ? 1 : 0);
  autoport_proof::publish("refset_fixed_tick_armed", fixed_tick::enabled() ? 1 : 0);
  // CE QUE LA NEUTRALISATION SUPPRIME, MESURE. `refset_pace_alpha` est ce que GOAL lit
  // vraiment (1000000 = identite). `refset_raw_alpha_min/max` est ce que `render_pace` a
  // calcule depuis la cadence d'affichage REELLE pendant la meme course : min != max prouve
  // que la grandeur supprimee variait, donc que la neutralisation n'est pas une clause vide.
  autoport_proof::publish("refset_pace_alpha", (uint64_t)(int64_t)render_pace::alpha_micro());
  autoport_proof::publish("refset_pace_skip", render_pace::skip() ? 1 : 0);
  if (g_raw_alpha_n) {
    autoport_proof::publish("refset_raw_alpha_min", (uint64_t)g_raw_alpha_min);
    autoport_proof::publish("refset_raw_alpha_max", (uint64_t)g_raw_alpha_max);
    autoport_proof::publish("refset_raw_alpha_n", g_raw_alpha_n);
  }
  if (g_mode == 2) {
    autoport_proof::publish("refset_compared", g_compared);
    autoport_proof::publish("refset_missing", g_missing);
    autoport_proof::publish("refset_size_bad", g_size_bad);
    autoport_proof::publish("refset_decode_bad", g_decode_bad);
    autoport_proof::publish("refset_replay_diffpx", g_diffpx);
    // 254 = le plan n'est pas alle au bout ; 255 = une reference manque ou ne se decode pas.
    // La vraie mesure ne remplace ces deux valeurs QUE lorsque tout a ete compare.
    uint64_t gate;
    if (g_missing || g_size_bad || g_decode_bad) {
      gate = 255;
    } else if (!g_finished) {
      gate = 254;
    } else {
      gate = g_maxdiff;
    }
    autoport_proof::publish("refset_replay_maxdiff", gate);
    // La grandeur de PORTE de cet item porte sur plusieurs COURSES (voir `publish_flaky`). Tant
    // que le registre n'a pas parle, la preuve porte la sentinelle : une course interrompue est
    // rouge, jamais muette — un `proof.txt` sans la cle se lit « le moteur ne l'emet pas ».
    if (!g_flaky_done) {
      autoport_proof::publish("refset_replay_flaky", 254);
    }
    // Les deux jeux, separement, avec la MEME regle de sentinelle : une course qui n'est pas
    // allee au bout ne peut pas rendre un zero.
    for (int ph = 1; ph <= 3; ph++) {
      static const char* const kMax[4] = {"", "refpix_maxdiff_origine", "refpix_maxdiff_recharged",
                                          "refpix_maxdiff_origine_lumiere"};
      static const char* const kImg[4] = {"", "refpix_images_origine", "refpix_images_recharged",
                                          "refpix_images_origine_lumiere"};
      const char* key = kMax[ph];
      const char* nkey = kImg[ph];
      autoport_proof::publish(key, gate >= 254 ? gate : g_maxdiff_phase[ph]);
      autoport_proof::publish(nkey, g_compared_phase[ph]);
    }
    // lighting-hdr : les grandeurs BRUTES des verdicts 1 et 2, publiees a cote du verdict pour
    // qu'un zero soit lisible. Un verdict sans son denominateur est une fausse constante.
    uint64_t sat_r = 0, sat_o = 0, px_o = 0, worst_ratio = 1u << 30, meas = 0;
    for (int i = 0; i < 8; i++) {
      const StepStats& r = g_stats[2][i];
      const StepStats& o = g_stats[3][i];
      if (!r.measured || !o.measured) {
        continue;
      }
      meas++;
      sat_r += r.sat_px;
      sat_o += o.sat_px;
      px_o += o.px;
      const uint64_t ratio = o.contrast_x1000
                                 ? (r.contrast_x1000 * 100ull) / o.contrast_x1000
                                 : (r.contrast_x1000 ? 1000ull : 100ull);
      if (ratio < worst_ratio) {
        worst_ratio = ratio;
      }
      // PAR CRENEAU, et pas seulement le pire. Les verdicts 1 et 2 echouent DES QU'UN creneau
      // echoue : un chiffre agrege dit qu'il y a un probleme, il ne dit pas ou corriger. Ces
      // seize lignes nomment le creneau fautif — sans elles l'essai suivant recommence a
      // l'aveugle, et c'est exactement ce que la revue reproche a un verdict sans denominateur.
      char k[64];
      std::snprintf(k, sizeof(k), "hdr_sat_excess_h%02d", kHours[i]);
      autoport_proof::publish(k, r.sat_px > o.sat_px ? r.sat_px - o.sat_px : 0ull);
      std::snprintf(k, sizeof(k), "hdr_hlc_pct_h%02d", kHours[i]);
      autoport_proof::publish(k, ratio);
    }
    // L'ECART D'APPARIEMENT DES VERDICTS 1 ET 2, EN FRAMES DE LOGIQUE. Le pire des huit
    // creneaux. C'est le denominateur de `hdr_hlc_pct_h*` : a 1440 il melange la courbe et le
    // temps, a 180 il ne reste que le settle d'une etape. 0 = pas mesurable (une des deux
    // photos manque), ce qui se lit sur `hdr_refset_hours_paired`.
    uint64_t gap_max = 0;
    for (int i = 0; i < 8; i++) {
      const StepStats& r = g_stats[2][i];
      const StepStats& o = g_stats[3][i];
      if (!r.measured || !o.measured || r.cap_lf < 0 || o.cap_lf < 0) {
        continue;
      }
      const uint64_t gap = (uint64_t)(r.cap_lf > o.cap_lf ? r.cap_lf - o.cap_lf
                                                          : o.cap_lf - r.cap_lf);
      if (gap > gap_max) {
        gap_max = gap;
      }
    }
    autoport_proof::publish("refset_pair_gap_lf", gap_max);
    autoport_proof::publish("hdr_refset_hours_paired", meas);
    autoport_proof::publish("hdr_sat_px_recharged", sat_r);
    autoport_proof::publish("hdr_sat_px_origine_lumiere", sat_o);
    autoport_proof::publish("hdr_sat_denom_px", px_o);
    // LA CLASSE DE DEFAUT QUE L'OWNER NOMME, PUBLIEE. `sat_white_px` (les TROIS canaux a 255 —
    // le blanc entierement brule) etait compte par `measure_step` et lu par AUCUNE ligne. Il est
    // publie pour les TROIS configurations, avec le total d'ORIGINE-TOTAL a cote de celui des
    // deux autres : sans ces trois nombres, « est-ce que le master ON brule plus que le jeu
    // d'origine ? » n'a pas de reponse machine, et c'est litteralement la question posee le
    // 2026-09-06. Aucun verdict n'en depend — c'est une mesure, pas une porte.
    {
      uint64_t sw[4] = {0, 0, 0, 0}, sp[4] = {0, 0, 0, 0};
      for (int ph = 1; ph <= 3; ph++) {
        for (int i = 0; i < 8; i++) {
          if (g_stats[ph][i].measured) {
            sw[ph] += g_stats[ph][i].sat_white_px;
            sp[ph] += g_stats[ph][i].sat_px;
          }
        }
      }
      autoport_proof::publish("hdr_sat_px_origine_total", sp[1]);
      autoport_proof::publish("hdr_sat_white_px_origine_total", sw[1]);
      autoport_proof::publish("hdr_sat_white_px_recharged", sw[2]);
      autoport_proof::publish("hdr_sat_white_px_origine_lumiere", sw[3]);
    }
    autoport_proof::publish("hdr_hl_contrast_worst_pct", meas ? worst_ratio : 0);
    // Le temoin de capture d'ORIGINE-TOTAL, publie pour que le verdict 4 soit LISIBLE : s'il
    // egale `refset_bin_fp`, la reference a ete capturee par ce binaire meme et le verdict est
    // rouge par construction, quel que soit le maxdiff.
    char wt[32];
    std::snprintf(wt, sizeof(wt), "%016llx", (unsigned long long)read_capture_witness(1));
    autoport_proof::publish_text("refset_witness_origine", wt);
    // La saveur du binaire qui a capture, et celle du binaire qui rejoue. Sans ces deux lignes,
    // « la reference vient d'un build sans la couche » est une affirmation que la preuve ne
    // contredit pas : la porte les EXIGE, le proof.txt doit donc les MONTRER.
    {
      const std::string wf = read_capture_flavour(1);
      autoport_proof::publish_text("refset_witness_origine_flavour",
                                   wf.empty() ? "absente" : wf.c_str());
    }
  }
  // En mode capture on ne publie AUCUNE valeur de porte : une course qui fabrique ses propres
  // references ne doit pas pouvoir la franchir.
}

std::string image_path(const std::string& name) {
  return g_dir + "/" + name + ".png";
}

void apply_step_config(const Step& s) {
  // Le master et la lumiere temps reel se pilotent par les surcharges d'environnement qui
  // EXISTENT (gfx.h:554 `OG_RECHARGED`, background_common.cpp:2635 `OG_RT_LIGHT`). Ecrire
  // directement dans `g_global_settings` ne tiendrait pas : GOAL repousse `recharged-master?`
  // a chaque image (hud-classes-pc.gc:1747). Les deux variables sont posees a leur longueur
  // definitive des l'initialisation, donc chaque bascule n'est qu'un `strcpy` en place.
  // lighting-hdr : `OG_LIGHTING` epingle le maitre de la refonte lumiere (gfx.h
  // `recharged_lighting_active`). C'est LUI qui separe RECHARGED d'ORIGINE-LUMIERE ; le master
  // les separe toutes les deux d'ORIGINE-TOTAL. `OG_RT_LIGHT` ne choisissait qu'un composite.
  if (s.phase == 1) {
    put_env("OG_RECHARGED", "0");  // ORIGINE-TOTAL : le jeu de Naughty Dog entier
    put_env("OG_LIGHTING", "0");
    put_env("OG_RT_LIGHT", "0");
  } else if (s.phase == 2) {
    put_env("OG_RECHARGED", "1");  // RECHARGED : master ON + refonte lumiere ON
    put_env("OG_LIGHTING", "1");
    put_env("OG_RT_LIGHT", "1");
  } else {
    // ORIGINE-LUMIERE : tout le Recharged SAUF l'eclairage. La config que l'owner joue.
    put_env("OG_RECHARGED", "1");
    put_env("OG_LIGHTING", "0");
    put_env("OG_RT_LIGHT", "0");
  }
  g_tod_x100 = s.hour * 100;
  lighting_census::set_phase(s.phase);
}

// Compare deux tampons RGBA de meme taille. L'alpha est ignore : `finish_screenshot` le force a
// 0xff, il ne porte donc aucune information.
void compare(const uint8_t* a, const uint8_t* b, int n_px, uint64_t* maxd, uint64_t* npx) {
  uint64_t md = 0, np = 0;
  for (int i = 0; i < n_px; i++) {
    int d = 0;
    for (int c = 0; c < 3; c++) {
      int t = (int)a[i * 4 + c] - (int)b[i * 4 + c];
      if (t < 0) {
        t = -t;
      }
      if (t > d) {
        d = t;
      }
    }
    if (d > 0) {
      np++;
      if ((uint64_t)d > md) {
        md = (uint64_t)d;
      }
    }
  }
  *maxd = md;
  *npx = np;
}


// ── le registre de rejeux ───────────────────────────────────────────────────────────────────
// `refset_replay_flaky` est le NOMBRE DE PAIRES DE REJEUX CONSECUTIFS, meme binaire et memes
// references, dont le `maxdiff` differe. C'est une grandeur qui porte sur des COURSES : aucune
// course seule ne peut la calculer, et un chiffre recopie a la main ne prouverait rien. Le
// moteur tient donc un registre sur disque, `<dir>/replay-ledger.txt`, une ligne par rejeu
// COMPLET :
//     bin=<empreinte du binaire> refs=<empreinte des 16 references> maxdiff=<n> diffpx=<n>
// et ne compare QUE les lignes dont les deux empreintes valent celles de la course en cours.
// Un binaire rebati ou une reference recapturee change l'empreinte : le registre se perime tout
// seul, il n'y a rien a effacer — et effacer un registre pour se debloquer serait exactement le
// geste que la non-destruction interdit.
//
// SENTINELLES, memes regles que `refset_replay_maxdiff` : 255 = la course n'a pas pu se mesurer
// (reference manquante, illisible, plan incomplet) ; 254 = moins de CINQ rejeux au registre,
// donc la question n'a pas encore de reponse. Ni l'une ni l'autre ne vaut zero : une porte
// verte demande cinq rejeux qui se sont mis d'accord.
uint64_t hash_file(const std::string& path) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) {
    return 0;
  }
  uint64_t h = 1469598103934665603ull;  // FNV-1a 64
  unsigned char buf[1 << 16];
  size_t n;
  while ((n = std::fread(buf, 1, sizeof(buf), f)) > 0) {
    for (size_t i = 0; i < n; i++) {
      h ^= buf[i];
      h *= 1099511628211ull;
    }
  }
  std::fclose(f);
  return h ? h : 1;  // 0 est reserve a « pas lisible »
}

// Les SEIZE references, dans l'ordre du plan. Une reference qui bouge d'un octet change
// l'empreinte, donc coupe le registre : on ne compare jamais deux courses jugees sur des
// references differentes.
uint64_t refs_fingerprint() {
  uint64_t h = 1469598103934665603ull;
  for (int phase : g_phases) {
    for (int hr : kHours) {
      char nm[64];
      std::snprintf(nm, sizeof(nm), "%s/h%02d", set_name(phase), hr);
      const uint64_t fh = hash_file(g_dir + "/" + nm + ".png");
      if (!fh) {
        return 0;
      }
      for (int b = 0; b < 8; b++) {
        h ^= (unsigned char)((fh >> (8 * b)) & 0xff);
        h *= 1099511628211ull;
      }
    }
  }
  return h ? h : 1;
}

// LE JEU DE DONNEES EST UNE ENTREE AU MEME TITRE QUE LE BINAIRE (item `refset-replay-stable`).
// Le registre ne comparait que `bin` et `refs`. Or `out/jak1/iso` est REECRIT par le
// constructeur, et pas rarement : mesure du 2026-09-06, les 28 `.CGO`/`.DGO` portent 15:58,
// c'est-a-dire APRES le rejeu de 15:52 dont la ligne est deja au registre. Deux rejeux qui
// encadrent une reconstruction n'ont pas lu la meme donnee : leur `maxdiff` a toutes les raisons
// de differer, et le registre l'aurait compte comme une intermittence de l'INSTRUMENT. C'est
// exactement le faux rouge que cet item doit supprimer. On ferme donc la porte au POINT DE
// PRODUCTION — les donnees entrent dans la CLE du registre — au lieu de le detecter apres coup.
// L'empreinte est le CONTENU, jamais une date : un `.CGO` rebati a l'identique ne coupe rien, et
// une donnee qui bouge d'un octet perime les lignes d'avant sans qu'on ait rien a effacer.
// Zero = un des repertoires est absent ou illisible ; `publish_flaky` en fait la sentinelle 255,
// jamais un zero de porte.
uint64_t data_fingerprint() {
  std::vector<fs::path> files;
  auto scan = [&files](const fs::path& dir, const char* ext) {
    std::error_code ec;
    for (const auto& e : fs::directory_iterator(dir, ec)) {
      std::error_code ec2;
      if (!e.is_regular_file(ec2)) {
        continue;
      }
      const std::string name = e.path().filename().string();
      const size_t n = std::strlen(ext);
      if (name.size() > n && name.compare(name.size() - n, n, ext) == 0) {
        files.push_back(e.path());
      }
    }
  };
  const fs::path iso = file_util::get_iso_out_dir(GameVersion::Jak1);
  const fs::path fr3 = file_util::get_fr3_dir(GameVersion::Jak1);
  scan(iso, ".CGO");
  scan(iso, ".DGO");
  scan(fr3, ".fr3");
  scan(fr3 / "enhanced", ".fr3");
  if (files.empty()) {
    return 0;
  }
  // Trie sur le NOM : l'ordre de `directory_iterator` est celui du systeme de fichiers, il n'est
  // pas stable d'une course a l'autre.
  std::sort(files.begin(), files.end());
  uint64_t h = 1469598103934665603ull;
  for (const auto& f : files) {
    const uint64_t fh = hash_file(f.string());
    if (!fh) {
      return 0;
    }
    // Le nom entre dans l'empreinte : deux fichiers qui echangent leur contenu ne doivent pas
    // rendre la meme valeur.
    for (unsigned char c : f.filename().string()) {
      h ^= c;
      h *= 1099511628211ull;
    }
    for (int b = 0; b < 8; b++) {
      h ^= (unsigned char)((fh >> (8 * b)) & 0xff);
      h *= 1099511628211ull;
    }
  }
  return h ? h : 1;
}

// lighting-hdr : l'empreinte du binaire COURANT. Extraite de `publish_flaky` pour que le
// verdict 4 puisse s'en servir aussi.
//
// SUR ANDROID, `/proc/self/exe` N'EST PAS NOTRE BINAIRE. Le processus est forke depuis zygote :
// son executable est `/system/bin/app_process64`, IDENTIQUE pour tous nos builds (mesure du
// 2026-09-06 sur eae4df44 : le lien pointe hors de l'APK). Le temoin de capture du verdict 4
// valait donc la meme chose pour le binaire qui capture et pour celui qui rejoue, et
// `verdict_master_off_bitexact()` rendait 1 QUOI QU'IL ARRIVE. Notre code vit dans `libgk.so` :
// on l'atteint par `dladdr` sur une adresse de CE module — jamais par un chemin ecrit en dur,
// qui changerait au premier renommage d'APK.
//
// Le resultat est CALCULE UNE FOIS. `verdict_master_off_bitexact()` est appele toutes les 30
// images depuis `hdr::frame_end` ; relire et hacher 134 Mo a chaque appel arreterait le jeu.
uint64_t self_fingerprint() {
  static uint64_t s_fp = 0;
  static bool s_done = false;
  if (s_done) {
    return s_fp;
  }
  s_done = true;
#if defined(__ANDROID__)
  Dl_info info;
  std::memset(&info, 0, sizeof(info));
  if (dladdr((const void*)&refs_fingerprint, &info) && info.dli_fname && info.dli_fname[0]) {
    s_fp = hash_file(info.dli_fname);
  }
#elif defined(__linux__)
  s_fp = hash_file("/proc/self/exe");
#endif
  return s_fp;
}

// ── LE TEMOIN DE CAPTURE, ET POURQUOI IL EXISTE ─────────────────────────────────────────────
// Le verdict 4 affirme « master eteint, sortie identique au bit a ORIGINE-TOTAL ». Si la
// reference a ete capturee par LE MEME binaire que le rejeu, cette affirmation se compare a
// elle-meme : elle mesure la stabilite, pas l'identite avec le jeu d'origine, et elle rendrait
// zero meme si le changement avait tout casse. C'est la faute « porte calculee sur ses propres
// variables », et elle ne doit pas dependre de la discipline de celui qui lance la course.
// On ecrit donc l'empreinte du binaire qui capture, a cote des images, et le verdict REFUSE de
// passer au vert quand elle est celle du binaire qui rejoue.
std::string witness_path(int phase) {
  return g_dir + "/" + set_name(phase) + "/captured-by.txt";
}

void write_capture_witness(int phase) {
  if (FILE* f = std::fopen(witness_path(phase).c_str(), "w")) {
    // Deux lignes, et les deux comptent. L'empreinte dit « pas le meme binaire » ; la saveur
    // dit « et ce n'etait pas un binaire qui contient la couche qu'on juge ». Sans la seconde,
    // n'importe quel binaire legerement different ferait une reference — la porte serait une
    // mesure de stabilite deguisee, exactement ce que le temoin existe pour empecher.
    std::fprintf(f, "%016llx\nflavour=%s\n", (unsigned long long)self_fingerprint(),
                 build_flavour());
    std::fclose(f);
  }
}

// La saveur inscrite a cote de la reference. "" = absente (temoin d'avant ce champ, ou fichier
// manquant) — et une saveur absente n'est jamais traitee comme `ablate`.
std::string read_capture_flavour(int phase) {
  std::string v;
  if (FILE* f = std::fopen(witness_path(phase).c_str(), "r")) {
    char line[128];
    while (std::fgets(line, sizeof(line), f)) {
      const char* p = std::strstr(line, "flavour=");
      if (p) {
        v = p + 8;
        while (!v.empty() && (v.back() == '\n' || v.back() == '\r')) {
          v.pop_back();
        }
        break;
      }
    }
    std::fclose(f);
  }
  return v;
}

uint64_t read_capture_witness(int phase) {
  uint64_t v = 0;
  if (FILE* f = std::fopen(witness_path(phase).c_str(), "r")) {
    if (std::fscanf(f, "%llx", (unsigned long long*)&v) != 1) {
      v = 0;
    }
    std::fclose(f);
  }
  return v;
}

void publish_flaky() {
  g_flaky_done = true;
  const uint64_t bin = self_fingerprint();
  const uint64_t refs = refs_fingerprint();
  const uint64_t data = data_fingerprint();
  char t[32];
  std::snprintf(t, sizeof(t), "%016llx", (unsigned long long)bin);
  autoport_proof::publish_text("refset_bin_fp", t);
  std::snprintf(t, sizeof(t), "%016llx", (unsigned long long)refs);
  autoport_proof::publish_text("refset_refs_fp", t);
  std::snprintf(t, sizeof(t), "%016llx", (unsigned long long)data);
  autoport_proof::publish_text("refset_data_fp", t);
  if (!bin || !refs || !data || g_missing || g_size_bad || g_decode_bad ||
      g_compared != g_steps.size()) {
    autoport_proof::publish("refset_replay_runs", 0);
    autoport_proof::publish("refset_replay_flaky", 255);
    return;
  }
  const std::string path = g_dir + "/replay-ledger.txt";
  // On ECRIT d'abord, on RELIT ensuite : le verdict porte sur ce qui est sur le disque, pas sur
  // ce que cette course croit avoir ajoute.
  if (FILE* f = std::fopen(path.c_str(), "a")) {
    std::fprintf(f, "bin=%016llx refs=%016llx data=%016llx maxdiff=%llu diffpx=%llu\n",
                 (unsigned long long)bin, (unsigned long long)refs, (unsigned long long)data,
                 (unsigned long long)g_maxdiff, (unsigned long long)g_diffpx);
    std::fclose(f);
  }
  // LA COMPARAISON PORTE SUR LE COUPLE (maxdiff, diffpx), PAS SUR `maxdiff` SEUL.
  // Mesure du 2026-09-07 qui force ce changement : six rejeux a cle IDENTIQUE ont rendu
  // 1242, 1242, 100238, 1242, 1242, 1242 px — et `refset_replay_flaky` a publie 0, parce que
  // l'atlas de police fixait `maxdiff=242` sur les six. Un instrument aveugle a un facteur 80
  // sur le NOMBRE de pixels ne certifie rien. Le nombre de pixels est la grandeur qui bouge ;
  // le maximum est celle qui sature.
  std::vector<std::pair<uint64_t, uint64_t>> md;
  if (FILE* f = std::fopen(path.c_str(), "r")) {
    char line[256];
    while (std::fgets(line, sizeof(line), f)) {
      unsigned long long b = 0, r = 0, dt = 0, m = 0, d = 0;
      if (std::sscanf(line, "bin=%llx refs=%llx data=%llx maxdiff=%llu diffpx=%llu", &b, &r, &dt,
                      &m, &d) == 5 &&
          b == bin && r == refs && dt == data) {
        md.emplace_back((uint64_t)m, (uint64_t)d);
      }
    }
    std::fclose(f);
  }
  uint64_t flaky = 0;
  for (size_t i = 1; i < md.size(); i++) {
    if (md[i] != md[i - 1]) {
      flaky++;
    }
  }
  autoport_proof::publish("refset_replay_runs", md.size());
  autoport_proof::publish("refset_replay_flaky", md.size() >= 5 ? flaky : 254);
  // LA LIGNE `FEATURE` DE CET ITEM, ET SON PROPRE DENOMINATEUR. `note_hit` alimente un compteur
  // GLOBAL que le recensement d'eclairage domine de plusieurs millions : `hits` prouve que la
  // course a tire, il ne dit pas combien de fois CE code a tire. La grandeur de cet item est
  // `refset_replay_runs` — le nombre de rejeux sur lesquels le verdict est calcule — et elle est
  // publiee juste au-dessus. Un seul hit par rejeu COMPLET : une course interrompue avant la
  // derniere etape n'atteint jamais cette ligne, donc ne peut pas se compter.
  autoport_proof::note_hit();
  std::printf("REFSET ledger runs=%d flaky=%llu (bin=%016llx refs=%016llx data=%016llx "
              "maxdiff=%llu)\n",
              (int)md.size(), (unsigned long long)flaky, (unsigned long long)bin,
              (unsigned long long)refs, (unsigned long long)data,
              (unsigned long long)g_maxdiff);
  std::fflush(stdout);
}

}  // namespace

bool enabled() {
  static int s_init = 0;
  if (s_init) {
    return g_mode != 0;
  }
  s_init = 1;
  char v[32] = {0};
  if (!read_knob("OG_REFSET", "debug.opengoal.refset", v, sizeof(v))) {
    return false;
  }
  if (std::strcmp(v, "capture") == 0) {
    g_mode = 1;
  } else if (std::strcmp(v, "replay") == 0) {
    g_mode = 2;
  } else {
    return false;
  }
  // lighting-hdr : SUR ANDROID, LE DEFAUT DOIT ETRE ABSOLU, et ce n'est pas une preference.
  // `g_dir` est relatif au CWD du processus, et ce CWD n'est jamais change sur Android : il est
  // en LECTURE SEULE (gk_android_main.cpp:9429-9433 le documente deja pour les sauvegardes,
  // d'ou son `setenv("HOME", files_dir)`). Avec le defaut relatif, la premiere chose que fait
  // refset est `create_directories`, qui LANCE sur un systeme de fichiers en lecture seule —
  // exception non rattrapee, donc `std::terminate` sur le fil GOAL, a l'init. Ce n'etait pas un
  // rouge propre, c'etait un SIGABRT dont la cause ne ressemble pas a son symptome.
  // Le nom differe aussi de celui du x86 : les deux familles d'images ne sont pas comparables
  // (re-rendu 320x180 en resolution interne d'un cote, sous-echantillonnage 4:3 de l'autre), et
  // on rend le melange impossible au point de PRODUCTION plutot que detectable plus tard.
  // La valeur reste ecrasable, mais attention : le canal Android est une propriete systeme,
  // donc plafonnee a PROP_VALUE_MAX (92 octets) — un chemin plus long serait tronque en silence.
#if defined(__ANDROID__)
  if (const char* home = std::getenv("HOME")) {
    if (home[0]) {
      g_dir = std::string(home) + "/.autoport/refset-device";
    }
  }
#endif
  char d[512] = {0};
  if (read_knob("OG_REFSET_DIR", "debug.opengoal.refset.dir", d, sizeof(d))) {
    g_dir = d;
  }
  // UN TELEPORT PAR ETAPE : voir `g_warp_per_step`. Sur appareil le defaut est 0 parce que le
  // troisieme `(start 'play <continue>)` tue la course en SIGILL (mesure du 2026-09-06).
#if defined(__ANDROID__)
  g_warp_per_step = 0;
#endif
  {
    char wv[32] = {0};
    if (read_knob("OG_REFSET_WARP_PER_STEP", "debug.opengoal.refset.warpstep", wv, sizeof(wv))) {
      g_warp_per_step = (std::atoi(wv) != 0) ? 1 : 0;
    }
  }
  {
    char av[32] = {0};
    if (read_knob("OG_REFSET_WARP_AT", "debug.opengoal.refset.warpat", av, sizeof(av))) {
      const long v = std::strtol(av, nullptr, 10);
      if (v >= 60 && v <= 100000) {
        g_warp_at = v;
      }
    }
  }
  {
    char sv[32] = {0};
    if (read_knob("OG_REFSET_SETTLE", "debug.opengoal.refset.settle", sv, sizeof(sv))) {
      const long v = std::strtol(sv, nullptr, 10);
      if (v >= 2 && v <= 3600) {
        g_step_settle = v;
      }
    }
  }
  fpng::fpng_init();
  // lighting-hdr : quelles phases ce plan execute. `OG_REFSET_PHASES=1,2` ou `=3`, defaut les
  // trois. Ca existe pour une raison precise : la reference ORIGINE-TOTAL du verdict 4 doit
  // etre capturee par un binaire d'AVANT le changement d'eclairage, sinon le verdict se compare
  // a lui-meme. Les phases se capturent donc separement, puis se rejouent ensemble.
  {
    char pv[64] = {0};
    if (read_knob("OG_REFSET_PHASES", "debug.opengoal.refset.phases", pv, sizeof(pv))) {
      for (const char* c = pv; *c; c++) {
        if (*c >= '1' && *c <= '3') {
          const int ph = *c - '0';
          if (std::find(g_phases.begin(), g_phases.end(), ph) == g_phases.end()) {
            g_phases.push_back(ph);
          }
        }
      }
    }
    if (g_phases.empty()) {
      g_phases = {1, 2, 3};
    }
    std::sort(g_phases.begin(), g_phases.end());
  }
  // L'ORDRE DES ETAPES, ET CE QU'IL CHANGE POUR LES VERDICTS 1 ET 2.
  // Par JEU (huit heures d'ORIGINE, puis huit de RECHARGED, puis huit d'ORIGINE-LUMIERE), les
  // deux photos qu'apparient les verdicts 1 et 2 — RECHARGED et ORIGINE-LUMIERE au MEME creneau
  // — sont separees de huit etapes, soit 1440 frames de logique. Ce que ces verdicts mesurent
  // alors est la somme de l'effet de la courbe et de 24 s de decor qui bouge : mesure du
  // 2026-09-06, `hdr_hlc_pct_h21=92` pour un seuil a 95 et `hdr_sat_excess_h06=62` sur 460800
  // pixels — des ecarts du meme ordre que le bruit temporel, donc un verdict qu'on ne peut pas
  // attribuer. Par CRENEAU, les trois configurations d'une meme heure se suivent : l'ecart tombe
  // a UN settle (180 frames), et `refset_pair_gap_lf` le publie au lieu de le supposer.
  // Pourquoi pas partout : sur bureau chaque etape est re-teleportee (`g_warp_per_step=1`), donc
  // l'ordre n'a aucun effet sur les poses — et l'instrument de `refset-replay-stable` ne se
  // redefinit pas sous les cinq rejeux qui l'ont valide (registre keye sur le binaire).
  g_order_by_hour = g_warp_per_step ? 0 : 1;
  {
    char ov[32] = {0};
    if (read_knob("OG_REFSET_ORDER_HOUR", "debug.opengoal.refset.orderhour", ov, sizeof(ov))) {
      g_order_by_hour = (std::atoi(ov) != 0) ? 1 : 0;
    }
  }
  if (g_order_by_hour) {
    for (int h : kHours) {
      for (int phase : g_phases) {
        g_steps.push_back(Step{phase, h});
      }
    }
  } else {
    for (int phase : g_phases) {
      for (int h : kHours) {
        g_steps.push_back(Step{phase, h});
      }
    }
  }
  // Poser les deux variables a leur longueur definitive AVANT que le fil graphique ne les lise
  // pour la premiere fois : ainsi chaque bascule ulterieure reecrit un unique octet en place.
  put_env("OG_RECHARGED", "0");
  put_env("OG_RT_LIGHT", "0");
  put_env("OG_LIGHTING", "0");
  file_util::create_dir_if_needed(g_dir + "/origine");
  file_util::create_dir_if_needed(g_dir + "/recharged");
  file_util::create_dir_if_needed(g_dir + "/origine-lumiere");
  std::printf("REFSET mode=%s dir=%s steps=%d res=%dx%d\n", g_mode == 1 ? "capture" : "replay",
              g_dir.c_str(), (int)g_steps.size(), kShotW, kShotH);
  std::fflush(stdout);
  return true;
}

int tod_override_x100() {
  return g_tod_x100;
}

int64_t warp_at_frame() {
  return g_warp_at;
}

void set_logic_frame_provider(int64_t (*fn)()) {
  g_logic_fn = fn;
}

int64_t current_logic_frame() {
  return g_logic_fn ? g_logic_fn() : -1;
}

void note_anchor() {
  if (!enabled()) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  const int64_t lf = current_logic_frame();
  if (g_warp1 < 0) {
    g_warp1 = lf;
    std::printf("REFSET warp1 lf=%lld (le plan demarre dans %lld images)\n", (long long)lf,
                (long long)kAnchorSettle);
    std::fflush(stdout);
    return;
  }
  g_rewarps++;
  g_rewarp_asked = false;
  if (g_cap == kCapWaitWarp) {
    g_step_anchor = lf;
    g_capture_frame = lf + g_step_settle;
    if (g_plan_base < 0) {
      g_plan_base = lf;
    }
    g_cap = kCapArmed;
  }
}

// LE RE-ANCRAGE DES LANCEURS DE PARTICULES. Rend vrai UNE seule fois, a la premiere frame de
// logique ou l'ancre du plan existe — donc a un instant FIXE, le meme dans la course qui capture
// et dans celle qui rejoue. C'est ce qui retire au feu sa dependance a la vitesse du chargement.
bool wants_particle_repin() {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_repin_done || g_plan_base < 0) {
    return false;
  }
  g_repin_done = true;
  g_repins++;
  g_repin_lf = current_logic_frame();
  std::printf("REFSET repin-particules lf=%lld (ancre=%lld)\n", (long long)g_repin_lf,
              (long long)g_plan_base);
  std::fflush(stdout);
  return true;
}

// LE PAS DES PARTICULES. Contrat et mesure : refset.h. Deux choses en une fonction, parce que
// ce sont deux faces du meme geste — le temps des particules ne doit avancer qu'a la cadence du
// PLAN, puis plus du tout des la premiere photo.
int particle_step_mode() {
  if (!enabled()) {
    return 2;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_plan_base < 0) {
    return 2;  // avant l'ancre : le moteur garde son chemin normal
  }
  const int64_t lf = current_logic_frame();
  if (lf < 0) {
    return 2;
  }
  if (lf >= g_plan_base + g_step_settle) {
    if (g_frozen_first_lf < 0) {
      g_frozen_first_lf = lf;
    }
    g_frozen_frames++;
    return 0;  // gel : les 24 photos voient le meme feu
  }
  if (lf == g_part_step_lf) {
    g_part_extra++;
    return 0;  // deja avance dans cette frame de logique : un deuxieme pas serait du hasard
  }
  g_part_step_lf = lf;
  g_part_steps++;
  return 1;
}

// L'ETAT DE FLAMME, EPINGLE. Contrat et mesure : la declaration d'etat en haut de ce fichier.
// Rend -1 hors du mode refset : le joueur ne rencontre jamais ce chemin, et `update-mood-flames`
// garde son increment d'origine.
int mood_flame_pin() {
  if (!enabled()) {
    return -1;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_mood_calls++;
  if (g_plan_base < 0) {
    return -1;  // avant l'ancre : le moteur garde son chemin normal
  }
  g_mood_pins++;
  return kMoodPinTime;
}

// LE SILENCE DES INCRUSTATIONS DE TEXTE. Contrat et mesure : refset.h. Rend 0 hors du mode
// refset — le joueur ne rencontre jamais ce chemin — et 1 pendant une course, ou
// `print-game-text` bascule alors en mode NO-DRAW : la mise en page est calculee a l'identique et
// la valeur de retour ne change pas, seule l'emission des glyphes disparait.
int text_mute() {
  if (!enabled()) {
    return 0;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_text_calls++;
  g_text_last_lf = current_logic_frame();
  // LA PHASE 1 GARDE SON TEXTE, ET CE N'EST PAS UN DETAIL DE CONFORT.
  // `lighting-origin-bitexact` mesure « maitre eteint => identique au bit au jeu d'origine ».
  // L'invite du maire est le SEUL objet du plan qui dessine l'atlas de police et qui exerce la
  // mise en page de `font.gc`. La muter retirerait de la comparaison tout un sous-systeme, et la
  // porte passerait au vert sur une scene ou la question ne se pose plus — « les DEUX bras au
  // vert parce que la condition est absente ». Depuis l'essai 2 la police n'est plus ablatee
  // dans le binaire-temoin (voir `origin_ablate.h` : banc de texte et chasses vivent dans la
  // donnee partagee), donc ces pixels DOIVENT etre identiques des deux cotes : ce creneau est
  // devenu le controle que le chemin de texte, lui, ne fuit pas ailleurs.
  // On ne mute donc que les phases 2 et 3, celles qu'apparient les verdicts de `lighting-hdr` ;
  // leur instrument est inchange, ligne pour ligne.
  if (g_cur < g_steps.size() && g_steps[g_cur].phase == 1) {
    return 0;
  }
  g_text_muted++;
  return 1;
}

bool wants_rewarp() {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_cap != kCapWaitWarp || g_warp1 < 0) {
    return false;
  }
  const int64_t lf = current_logic_frame();
  if (g_rewarp_asked) {
    // Le slot `*listener-function*` est partage : une demande peut etre ecrasee avant que le
    // noyau ne la lance. Sans ce re-armement l'etape resterait bloquee pour toujours, et la
    // porte rendrait 254 sans dire pourquoi.
    if (lf < g_rewarp_asked_lf + 300) {
      return false;
    }
  }
  g_rewarp_asked = true;
  g_rewarp_asked_lf = lf;
  return true;
}

// LA CADENCE DU PLAN. Contrat et mesure : voir `begin_logic_frame` dans refset.h. Le
// de-doublonnage porte sur la frame de LOGIQUE, pas sur un compteur maison : deux appels dans la
// meme image simulee (manette lue deux fois, ou image rendue qui suit l'image simulee) rendent
// faux au second, et une frame de logique qu'AUCUNE image rendue ne porte est quand meme
// cadencee — c'est tout l'objet du changement.
bool begin_logic_frame(bool from_logic) {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  const int64_t lf = current_logic_frame();
  if (lf == g_pumped_lf) {
    return false;
  }
  g_pumped_lf = lf;
  if (from_logic) {
    g_pump_logic++;
  } else {
    g_pump_render++;
  }
  return true;
}

void tick() {
  if (!enabled()) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  // AVANT tout retour anticipe : l'alpha brut s'echantillonne sur TOUTE la course, y compris
  // le chargement. Le poser apres les gardes ci-dessous ne mesurerait que les images du plan.
  {
    const int64_t raw = (int64_t)render_pace::raw_alpha_micro();
    if (raw < g_raw_alpha_min) {
      g_raw_alpha_min = raw;
    }
    if (raw > g_raw_alpha_max) {
      g_raw_alpha_max = raw;
    }
    g_raw_alpha_n++;
  }
  if (g_warp1 < 0 || g_finished) {
    return;
  }
  const int64_t lf = current_logic_frame();
  if (lf < 0 || lf < g_warp1 + kAnchorSettle) {
    return;
  }

  if (g_cap == kCapDone) {
    g_cap = kCapIdle;
    g_cur++;
    if (g_cur >= g_steps.size()) {
      g_finished = true;
      lighting_census::set_phase(0);
      g_tod_x100 = -1;
      if (g_mode == 2) {
        publish_flaky();
      }
      publish_state();
      std::printf("REFSET done steps=%d captured=%llu compared=%llu maxdiff=%llu diffpx=%llu "
                  "missing=%llu slip=%lld..%lld rewarps=%llu settle=%lld\n",
                  (int)g_steps.size(), (unsigned long long)g_captured,
                  (unsigned long long)g_compared, (unsigned long long)g_maxdiff,
                  (unsigned long long)g_diffpx, (unsigned long long)g_missing,
                  (long long)g_frame_slip_min, (long long)g_frame_slip_max,
                  (unsigned long long)g_rewarps, (long long)g_step_settle);
      std::fflush(stdout);
      return;
    }
  }

  if (g_cap == kCapIdle) {
    // La configuration est posee AVANT le teleport : l'heure et le master sont donc deja ceux de
    // l'etape quand la camera se repose.
    const Step& st = g_steps[g_cur];
    apply_step_config(st);
    char nm[64];
    std::snprintf(nm, sizeof(nm), "%s/h%02d", set_name(st.phase), st.hour);
    g_capture_name = nm;
    if (g_warp_per_step || g_cur == 0 || g_plan_base < 0) {
      g_cap = kCapWaitWarp;
    } else {
      // Pas de teleport pour cette etape : l'instant de la photo se DEDUIT de l'ancre du plan.
      // Voir `g_plan_base`. Un retard reel (le plan n'a pas tenu la cadence) n'est pas absorbe
      // en silence : il se compte, et le repli qui suit rend la course non comparable — c'est
      // exactement ce que `refset_late_arms` doit rendre visible.
      g_step_anchor = g_plan_base;
      g_capture_frame = g_plan_base + (int64_t)(g_cur + 1) * g_step_settle;
      if (g_capture_frame <= lf) {
        g_late_arms++;
        g_capture_frame = lf + g_step_settle;
      }
      g_cap = kCapArmed;
    }
    if (g_cur == 0) {
      std::printf("REFSET start lf=%lld warp1=%lld settle=%lld\n", (long long)lf,
                  (long long)g_warp1, (long long)g_step_settle);
      std::fflush(stdout);
    }
  }
  publish_state();
}

bool capture_for_chain(int64_t lf, char* name_out, int name_cap, int* w, int* h) {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_cap != kCapArmed || lf < g_capture_frame) {
    return false;
  }
  // `lf > g_capture_frame` veut dire qu'une chaine a saute : on le MESURE au lieu de l'ignorer,
  // parce qu'un decalage d'une frame de logique suffit a faire mentir la comparaison.
  // Le decalage entre la frame de logique DEMANDEE et celle que porte la chaine rendue. Il est
  // constant par construction (l'ordre des appels dans une image de GOAL est fixe) ; ce qui
  // serait dangereux, c'est qu'il VARIE. On publie donc le min ET le max : `slip_min ==
  // slip_max` est la preuve que l'appariement est stable, un intervalle ouvert dit que non.
  const int64_t slip = lf - g_capture_frame;
  if (slip > g_frame_slip_max) {
    g_frame_slip_max = slip;
  }
  if (slip < g_frame_slip_min) {
    g_frame_slip_min = slip;
  }
  if (slip != 0) {
    // Un slip non nul veut dire que la chaine portant la frame DEMANDEE n'a jamais ete rendue :
    // la photo decrit une autre image de logique que celle du plan. On le COMPTE, parce que
    // `slip_min..slip_max` ne dit pas combien de photos sont concernees, et c'est ce nombre qui
    // rend une comparaison bit-a-bit impossible.
    g_slip_nonzero++;
  }
  g_inflight_lf = lf;
  // Desarmer ICI, pas a la fin de la capture : entre les deux, le fil graphique dessine une ou
  // deux images de plus et re-prendrait la meme demande.
  g_cap = kCapInFlight;
  std::snprintf(name_out, name_cap, "%s", g_capture_name.c_str());
  *w = kShotW;
  *h = kShotH;
  return true;
}

bool consume_capture(int w, int h, const void* rgba) {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_cap != kCapInFlight) {
    return false;
  }
  const std::string path = image_path(g_capture_name);
  const int n_px = w * h;
  const uint8_t* cur = (const uint8_t*)rgba;
  // lighting-hdr : on mesure AVANT de comparer ou d'ecrire, dans les deux modes. Les
  // verdicts 1 et 2 portent sur ce que le moteur vient de dessiner, pas sur la reference.
  measure_step(g_steps[g_cur].phase, g_steps[g_cur].hour, g_inflight_lf, cur, w, h);

  if (g_mode == 1) {
    file_util::write_rgba_png(path, const_cast<void*>(rgba), w, h);
    g_captured++;
    write_capture_witness(g_steps[g_cur].phase);
    std::printf("REFSET cap %s step=%d/%d\n", g_capture_name.c_str(), (int)g_cur,
                (int)g_steps.size());
    std::fflush(stdout);
    // Un chemin n'est pas une preuve : on relit tout de suite ce qu'on vient d'ecrire et on
    // verifie que l'aller-retour PNG est exact. Sinon la reference ne vaut rien et personne ne
    // le saurait avant l'item suivant.
    std::vector<uint8_t> back;
    uint32_t bw = 0, bh = 0, bc = 0;
    if (fpng::fpng_decode_file(path.c_str(), back, bw, bh, bc, 4) != 0 || (int)bw != w ||
        (int)bh != h) {
      g_roundtrip_bad++;
    } else {
      uint64_t md = 0, np = 0;
      compare(cur, back.data(), n_px, &md, &np);
      if (md != 0) {
        g_roundtrip_bad++;
      }
    }
  } else {
    std::vector<uint8_t> ref;
    uint32_t rw = 0, rh = 0, rc = 0;
    const int rc_dec = fpng::fpng_decode_file(path.c_str(), ref, rw, rh, rc, 4);
    if (rc_dec == fpng::FPNG_DECODE_FILE_OPEN_FAILED) {
      g_missing++;
      std::printf("REFSET missing %s\n", path.c_str());
      std::fflush(stdout);
    } else if (rc_dec != 0) {
      g_decode_bad++;
    } else if ((int)rw != w || (int)rh != h) {
      g_size_bad++;
    } else {
      uint64_t md = 0, np = 0;
      compare(cur, ref.data(), n_px, &md, &np);
      g_compared++;
      if (md > g_maxdiff) {
        g_maxdiff = md;
      }
      {
        // Les phases valent 1..3. La borne haute etait `<= 2` : la phase 3 (ORIGINE-LUMIERE)
        // n'entrait donc JAMAIS dans `g_compared_phase`, et `verdict_origine_lumiere_set()`,
        // qui exige `g_compared_phase[3] == 8`, rendait 1 quoi qu'il arrive — le verdict 5
        // etait rouge par construction, comme `refpix_maxdiff_origine_lumiere` etait mort.
        // La case 0 n'existe pas (voir la declaration de g_maxdiff_phase).
        const int ph = g_steps[g_cur].phase;
        if (ph >= 1 && ph <= 3) {
          if (md > g_maxdiff_phase[ph]) {
            g_maxdiff_phase[ph] = md;
          }
          g_compared_phase[ph]++;
        }
      }
      g_diffpx += np;
      // Le validateur exige `FEATURE <id> armed=1 hits=>0` : une comparaison faite EST le chemin
      // de code de cet item qui tire. `hits` est un compteur global du harnais, pas le notre.
      autoport_proof::note_hit();
      char key[96];
      std::snprintf(key, sizeof(key), "refset_d_%s_h%02d",
                    set_name(g_steps[g_cur].phase), g_steps[g_cur].hour);
      autoport_proof::publish(key, md);
      std::printf("REFSET cmp %s maxdiff=%llu diffpx=%llu\n", g_capture_name.c_str(),
                  (unsigned long long)md, (unsigned long long)np);
      std::fflush(stdout);
      if (md != 0) {
        // L'image REELLE d'un ecart est ecrite a cote de la preuve pour que l'ecart soit
        // localisable hors ligne. Elle ne prouve rien : c'est le nombre qui prouve.
        //
        // SUR ANDROID CE CHEMIN DOIT ETRE ABSOLU, et c'est la meme mine que celle deja payee
        // pour `g_dir` : `.autoport/reports/...` est relatif au CWD du processus, ce CWD est en
        // LECTURE SEULE sur l'appareil, et `create_dir_if_needed` appelle
        // `fs::create_directories` SANS `error_code` (FileUtil.cpp:530) — donc il LANCE.
        // L'exception traverse le fil graphique et devient `std::terminate` : un SIGABRT dont la
        // cause ne ressemble pas au symptome. Le declencheur n'est pas theorique : il suffit
        // qu'UNE comparaison rende un ecart non nul, ce qui est le cas nominal des le moment ou
        // la reference d'une phase vient d'un autre binaire.
#if defined(__ANDROID__)
        const std::string out = g_dir + "/actual";
#else
        const char* fid = autoport_proof::feature_id();
        const std::string out = std::string(".autoport/reports/") +
                                ((fid && fid[0]) ? fid : "lighting-census") + "/refset-actual";
#endif
        file_util::create_dir_if_needed(out);
        file_util::write_rgba_png(out + "/" + set_name(g_steps[g_cur].phase) + "-h" +
                                      (g_steps[g_cur].hour < 10 ? "0" : "") +
                                      std::to_string(g_steps[g_cur].hour) + ".png",
                                  const_cast<void*>(rgba), w, h);
      }
    }
  }

  g_cap = kCapDone;
  publish_state();
  return true;
}


// ── lighting-hdr : quatre des six verdicts de `hdr_tonemap_defects` ─────────────────────────
// Convention, la meme partout : 0 = tenu, 1 = defaut. JAMAIS de troisieme valeur « pas
// mesurable » — une grandeur qu'on n'a pas pu mesurer est un defaut, pas un silence. Sans cette
// regle, une course qui n'irait pas au bout rendrait un zero et fermerait la porte pour rien.

// Verdict 4 — master eteint, sortie identique au bit a ORIGINE-TOTAL.
int verdict_master_off_bitexact() {
#if AUTOPORT_ORIGIN_ABLATE
  // UN BINAIRE D'ABLATION NE JUGE RIEN. Il ne contient pas la couche dont on affirme
  // l'innocuite : son zero ne voudrait rien dire, et il ne doit pas pouvoir fermer la porte.
  return 1;
#else
  const bool clean = !g_missing && !g_size_bad && !g_decode_bad;
  if (g_mode != 2 || !clean || g_compared_phase[1] != 8 || g_maxdiff_phase[1] != 0) {
    return 1;
  }
  // La reference doit venir d'un AUTRE binaire que celui-ci — voir le temoin de capture.
  const uint64_t w = read_capture_witness(1);
  if (w == 0 || w == self_fingerprint()) {
    return 1;
  }
  // ... et pas de n'importe quel autre binaire : d'un binaire ou la couche Recharged n'est pas
  // COMPILEE. C'est la definition que la SPEC donne du jeu d'origine (§1.1 regle 1 point 3 :
  // « son OFF est bit-identique a son ABSENCE »). Une reference capturee par un binaire normal
  // avec le drapeau a zero ne verrait aucun site qui remplace le vanilla sans consulter le
  // maitre — le defaut meme que cet item cherche.
  if (read_capture_flavour(1) != "ablate") {
    return 1;
  }
  return 0;
#endif
}

// Verdict 5 — le jeu ORIGINE-LUMIERE existe ET sert de base aux verdicts 1-3. « Exister » ne
// suffit pas : il faut que ses huit creneaux aient ete compares ET mesures, sinon les verdicts
// 1 et 2 s'appuieraient sur un jeu partiel sans que rien ne le dise.
int verdict_origine_lumiere_set() {
  if (g_mode != 2 || g_compared_phase[3] != 8) {
    return 1;
  }
  for (int i = 0; i < 8; i++) {
    if (!g_stats[3][i].measured) {
      return 1;
    }
  }
  return 0;
}

// Verdict 1 — la part de pixels satures de RECHARGED ne depasse celle d'ORIGINE-LUMIERE sur
// AUCUN creneau. Le maximum par creneau, pas la moyenne : une moyenne laisserait un creneau
// brule se faire compenser par sept creneaux sombres.
int verdict_saturation() {
  if (g_mode != 2) {
    return 1;
  }
  int paired = 0;
  for (int i = 0; i < 8; i++) {
    const StepStats& r = g_stats[2][i];
    const StepStats& o = g_stats[3][i];
    if (!r.measured || !o.measured || r.px != o.px) {
      return 1;
    }
    paired++;
    if (r.sat_px > o.sat_px) {
      return 1;
    }
  }
  return paired == 8 ? 0 : 1;
}

// Verdict 2 — le contraste local du decile le plus lumineux vaut au moins 95 % de celui
// d'ORIGINE-LUMIERE, sur CHAQUE creneau. C'est la mesure de « la courbe preserve le detail » :
// une zone ecrasee a blanc plat a un gradient local nul.
int verdict_highlight_contrast() {
  if (g_mode != 2) {
    return 1;
  }
  for (int i = 0; i < 8; i++) {
    const StepStats& r = g_stats[2][i];
    const StepStats& o = g_stats[3][i];
    if (!r.measured || !o.measured) {
      return 1;
    }
    // o == 0 : la reference n'a aucun detail dans son decile ; on ne peut pas en perdre.
    if (o.contrast_x1000 == 0) {
      continue;
    }
    if (r.contrast_x1000 * 100ull < 95ull * o.contrast_x1000) {
      return 1;
    }
  }
  return 0;
}

}  // namespace refset
