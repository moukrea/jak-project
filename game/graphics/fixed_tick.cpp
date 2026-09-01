// Gfixed-tick-interpolation — voir fixed_tick.h pour le raisonnement complet.

#include "fixed_tick.h"

#include <cmath>
#include <cstdlib>

#include "common/util/Timer.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace fixed_tick {

namespace {

// Etat de l'horloge. Tout ceci ne vit QUE sur le fil GOAL/EE : `begin_render_frame`
// est appelee depuis la soumission de la chaine DMA, sur le fil GOAL/EE. Aucune synchronisation necessaire, et
// surtout aucune lecture depuis le fil graphique (ce serait une course).
struct State {
  Timer timer;
  bool have_last = false;
  double accumulator = 0.0;
  s32 alpha_micro = 1000000;  // 1.0 == pose courante == pas d'interpolation
  bool deterministic = false;
  bool disarmed_fast_display = false;
  // Gfixed-tick-anim-interp : « l'horloge gouverne cette image » n'est PLUS la meme
  // chose que « cette image porte un tick ». Au-dessus de 60 Hz elle gouverne des
  // images de RENDU SEUL, qui portent zero tick.
  bool clock_governs = false;
  u64 ticks = 0;
  u64 render_frames = 0;
  u64 armed_frames = 0;
  PublishFn publisher = nullptr;
  // Armement. `forced` vaut -1 quand l'environnement ne dit rien (le reglage du joueur
  // decide alors), 0 ou 1 quand il FORCE l'etat pour une course d'ablation.
  int forced = -2;  // -2 == pas encore lu
  bool armed_setting = false;
  // Moyenne glissante de la duree reelle d'une image. Sert UNIQUEMENT a decider si
  // l'affichage tourne plus vite que 60 Hz (perimetre de l'etape 1). Une decision
  // prise sur une frame isolee ferait clignoter l'armement a chaque hoquet.
  double dt_ema = kFixedTickSeconds;
};

State& state() {
  static State s;
  return s;
}

// Lit la CONSIGNE D'ENVIRONNEMENT. Rend -1 quand elle est absente : dans ce cas le
// reglage du joueur (menu Recharged Settings) decide, et son defaut est DESARME.
//
// DEFAUT DESARME depuis le 2026-08-30 (superviseur). Ce chantier reecrit le pas de
// simulation — sauts, camera, seuils d'etat. Il etait actif par defaut dans le build
// publie a 17h32 et installe par l'owner, qui a vu le jeu planter. Une telle reecriture
// ne part pas armee chez lui sans qu'il l'ait demandee. `OG_FIXED_TICK=1` (ou la
// propriete Android a "1") l'arme pour nos propres mesures ; `...=0` la desarme meme si
// le joueur l'a activee. C'est l'ablation sur LE MEME BINAIRE qu'exigent les directives
// pour un avant/apres honnete, et c'est pour ca que l'environnement PRIME sur le menu.
int read_force_flag() {
  const char* e = std::getenv("OG_FIXED_TICK");
  if (e && (e[0] == '0' || e[0] == '1')) {
    return e[0] - '0';
  }
#ifdef __ANDROID__
  char pv[8] = {0};
  if (__system_property_get("debug.opengoal.fixed_tick", pv) > 0 &&
      (pv[0] == '0' || pv[0] == '1')) {
    return pv[0] - '0';
  }
#endif
  return -1;
}

// Sonde de cadence, une ligne par image dessinee. Gate a part, parce qu'une sonde
// par-image livree ARMEE est un defaut deja paye (40 Mo de sortie en 220 s sur
// l'appareil). Sur Android stdout/stderr sont routes vers logcat
// (android/gk_android_main.cpp), donc la meme sonde sert aux deux plateformes — mais
// l'environnement n'y est pas reglable, d'ou la propriete.
bool read_probe_flag() {
  if (std::getenv("OG_FIXED_TICK_PROBE") != nullptr) {
    return true;
  }
#ifdef __ANDROID__
  char pv[8] = {0};
  if (__system_property_get("debug.opengoal.fixed_tick_probe", pv) > 0 && pv[0] == '1') {
    return true;
  }
#endif
  return false;
}

// Gfixed-tick-anim-interp — lecture d'un interrupteur 0/1 avec un DEFAUT declare.
// L'environnement (bureau) prime, puis la propriete Android, sinon le defaut. C'est
// le meme patron que `read_force_flag`, et c'est ce qui permet l'ablation SUR LE MEME
// BINAIRE que les directives exigent : une course avec, une course sans, meme .so.
bool read_bool_flag(const char* env_name, const char* prop_name, bool dflt) {
  const char* e = std::getenv(env_name);
  if (e && (e[0] == '0' || e[0] == '1')) {
    return e[0] == '1';
  }
#ifdef __ANDROID__
  char pv[8] = {0};
  if (__system_property_get(prop_name, pv) > 0 && (pv[0] == '0' || pv[0] == '1')) {
    return pv[0] == '1';
  }
#else
  (void)prop_name;
#endif
  return dflt;
}

}  // namespace

bool enabled() {
  State& s = state();
  if (s.forced == -2) {
    s.forced = read_force_flag();
  }
  if (s.forced >= 0) {
    return s.forced == 1;
  }
  return s.armed_setting;
}

void set_enabled(bool on) {
  State& s = state();
  if (s.forced == -2) {
    s.forced = read_force_flag();
  }
  if (s.forced >= 0) {
    return;  // une course d'ablation est en cours : le menu ne la contredit pas
  }
  if (on == s.armed_setting) {
    return;
  }
  s.armed_setting = on;
  // Rebase a chaque transition. Sans ca, la premiere image apres l'armement lirait une
  // montre arretee depuis la derniere image ARMEE (potentiellement des minutes) et
  // fabriquerait un rattrapage de 4 ticks pour rien.
  s.have_last = false;
  s.accumulator = 0.0;
  s.dt_ema = kFixedTickSeconds;
  s.alpha_micro = 1000000;
}

bool probe_enabled() {
  static const bool s_probe = read_probe_flag();
  return s_probe;
}

bool anim_interp_enabled() {
  static const bool s_on = read_bool_flag("OG_ANIM_INTERP", "debug.opengoal.animinterp", true);
  return s_on;
}

bool anim_probe_enabled() {
  static const bool s_on = read_bool_flag("OG_ANIM_PROBE", "debug.opengoal.animprobe", false);
  return s_on;
}

bool armed_last_frame() {
  return state().clock_governs;
}

bool fast_display() {
  return state().disarmed_fast_display;
}

void set_deterministic(bool on) {
  state().deterministic = on;
}

s32 render_alpha_micro() {
  return state().alpha_micro;
}

u64 total_ticks() {
  return state().ticks;
}

u64 total_render_frames() {
  return state().render_frames;
}

u64 total_armed_frames() {
  return state().armed_frames;
}

void set_publisher(PublishFn fn) {
  state().publisher = fn;
}

// Une image vient d'etre produite : on fait avancer l'accumulateur puis on publie le
// resultat vers GOAL. Publier MEME quand l'horloge n'est pas armee est deliberé — sinon
// `*fixed-tick-armed*` garderait la valeur de la derniere image armee et le moteur
// resterait sur le chemin a pas fixe apres un desarmement.
void on_render_frame() {
  State& s = state();
  const int k = begin_render_frame();
  if (s.clock_governs) {
    s.armed_frames++;
  }
  if (s.publisher) {
    // `armed` suit desormais l'horloge, pas le nombre de ticks : une image de RENDU
    // SEUL est ARMEE et porte `skip=1`. Publier `armed=0` pour elle rendrait la main
    // au calcul d'origine, qui deduit le pas de la duree de la frame — c'est-a-dire
    // exactement le pas variable que ce module existe pour supprimer.
    s.publisher(s.clock_governs ? 1 : 0, k >= 1 ? (k - 1) : 0, s.alpha_micro,
                (s.clock_governs && k == 0) ? 1 : 0);
  }
}

int begin_render_frame() {
  if (!enabled()) {
    state().clock_governs = false;
    return 0;
  }
  State& s = state();
  s.clock_governs = true;
  s.render_frames++;

  // Mode deterministe (harnais de rejeu) : exactement un tick par image, sans lire la
  // montre. Le pas vaut 1/60 s a TOUS les framerates cibles, ce qui isole la taille du
  // pas comme seule variable de la mesure.
  if (s.deterministic) {
    s.accumulator = 0.0;
    s.alpha_micro = 1000000;
    s.have_last = false;  // la premiere frame apres le mode reel rebase la montre
    s.ticks++;
    return 1;
  }

  double dt;
  if (!s.have_last) {
    // Premiere image : aucune duree a mesurer. On pose exactement un tick plutot que
    // d'inventer une valeur — c'est le defaut sur lequel le moteur demarre deja.
    dt = kFixedTickSeconds;
    s.have_last = true;
  } else {
    dt = s.timer.getSeconds();
  }
  s.timer.start();

  // Gfixed-tick-anim-interp — CE BLOC DESARMAIT, IL NE FAIT PLUS QUE CONSTATER.
  // Jusqu'ici, des que la moyenne glissante de la duree d'image passait sous 0,95 tick
  // (~63 img/s), l'horloge rendait la main au calcul d'origine. Deux consequences
  // mesurees : la simulation reprenait la cadence de l'AFFICHAGE sur tout panneau
  // 90/120 Hz, et l'ablation de cette phase publiait `armed=0` DES DEUX COTES au-dessus
  // de 60 img/s — donc deux lignes identiques et une comparaison vide.
  // L'horloge reste desormais armee et rend k = 0 pour les images qui ne meritent pas
  // de tick ; `time-ratio` vaut alors 0 cote GOAL et la logique n'avance pas.
  s.dt_ema = 0.85 * s.dt_ema + 0.15 * dt;
  s.disarmed_fast_display = (s.dt_ema < kFixedTickSeconds * kDisarmFasterThan);

  // Un hoquet (chargement, changement de niveau) ne doit pas fabriquer un
  // fast-forward : on borne l'apport a ce que le rattrapage peut absorber.
  const double dt_ceiling = kMaxCatchupTicks * kFixedTickSeconds;
  if (dt > dt_ceiling) {
    dt = dt_ceiling;
  }

  // Accrochage a un nombre entier de ticks. C'est ce qui rend la sortie a 60 fps
  // identique : sur un panneau verrouille, dt vaut 1 tick a la milliseconde pres,
  // donc exactement 1 tick, et le reste accumule reste NUL.
  bool snapped = false;
  const double ticks_f = dt / kFixedTickSeconds;
  const double nearest = std::floor(ticks_f + 0.5);
  if (nearest >= 1.0 && std::fabs(ticks_f - nearest) <= kSnapTolerance) {
    dt = nearest * kFixedTickSeconds;
    snapped = true;
    // Gfixed-tick-anim-interp — L'ACCROCHAGE PORTE AUSSI SUR L'ACCUMULATEUR, ET C'EST
    // CE QUI MANQUAIT. Mesure : a 60,0 img/s verrouilles, l'alpha publie restait FIGE a
    // 0,738171 sur 800 images sur 800, jamais 1,0. Cause : l'accrochage ne corrigeait
    // que `dt` ; le reste fractionnaire herite du chargement (cadence irreguliere) etait
    // ensuite ajoute puis retire a l'identique a chaque image, donc il ne se resorbait
    // JAMAIS. Tant que rien ne lisait l'alpha en dehors de la camera -- ou un alpha
    // CONSTANT ne produit qu'une latence constante -- ca ne se voyait pas.
    // Ici il se voit : la reference « 60 images/s identique au bit » exige alpha == 1,0.
    // Accrocher, c'est declarer que cette image vaut EXACTEMENT N ticks : il n'y a donc
    // pas de reste sous-tick, et le porter serait se contredire. Le temps jete vaut au
    // plus une fraction de tick, UNE FOIS, au moment ou la cadence se verrouille.
    s.accumulator = 0.0;
  }

  s.accumulator += dt;

  int k = 0;
  while (s.accumulator >= kFixedTickSeconds && k < kMaxCatchupTicks) {
    s.accumulator -= kFixedTickSeconds;
    k++;
  }
  if (s.accumulator >= kFixedTickSeconds) {
    // Le plafond de rattrapage a mordu : on jette le retard au lieu de le porter,
    // sinon la frame suivante hériterait d'un backlog qui ne se resorbe jamais.
    s.accumulator = kFixedTickSeconds * 0.999;
  }
  if (k < 1) {
    // IMAGE DE RENDU SEUL : le temps reel n'a pas encore paye un tick entier. On garde
    // l'horloge armee et on publie l'alpha, de sorte que la pose DESSINEE avance quand
    // meme — c'est tout l'objet de cette phase. Le reste accumule est conserve, donc
    // rien n'est perdu ni invente.
    double a0 = s.accumulator / kFixedTickSeconds;
    if (a0 < 0.0) {
      a0 = 0.0;
    }
    if (a0 > 1.0) {
      a0 = 1.0;
    }
    s.alpha_micro = (s32)(a0 * 1000000.0 + 0.5);
    return 0;
  }

  s.ticks += (u64)k;

  // Alpha de rendu. Cadence verrouillee (accroche ET reste nul) => 1.0, donc aucune
  // interpolation et aucune latence ajoutee : c'est la reference 60 fps.
  if (snapped && s.accumulator < 1e-9) {
    s.alpha_micro = 1000000;
  } else {
    double a = s.accumulator / kFixedTickSeconds;
    if (a < 0.0) {
      a = 0.0;
    }
    if (a > 1.0) {
      a = 1.0;
    }
    s.alpha_micro = (s32)(a * 1000000.0 + 0.5);
  }
  return k;
}

}  // namespace fixed_tick
