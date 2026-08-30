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
  u64 ticks = 0;
  u64 render_frames = 0;
  u64 armed_frames = 0;
  PublishFn publisher = nullptr;
  // Moyenne glissante de la duree reelle d'une image. Sert UNIQUEMENT a decider si
  // l'affichage tourne plus vite que 60 Hz (perimetre de l'etape 1). Une decision
  // prise sur une frame isolee ferait clignoter l'armement a chaque hoquet.
  double dt_ema = kFixedTickSeconds;
};

State& state() {
  static State s;
  return s;
}

bool read_enable_flag() {
  // DEFAUT DESARME depuis le 2026-08-30. Ce chantier (Gfixed-tick-interpolation) n'a PAS
  // passe sa porte de sortie : ses deux tentatives ont echoue. Il etait pourtant actif par
  // defaut dans le build publie a 17h32 et installe par l'owner, qui a vu le jeu planter.
  // Une reecriture non validee du pas de simulation — ce qui gouverne les sauts, la camera
  // et les seuils d'etat — ne doit JAMAIS etre armee dans un binaire qui part chez lui.
  // `OG_FIXED_TICK=1` (ou la propriete a "1") l'arme pour nos propres mesures ; c'est
  // l'ablation sur LE MEME BINAIRE qu'exigent les directives pour un avant/apres honnete.
  // A rebasculer sur ON le jour ou le chantier passe son validateur, pas avant.
  const char* e = std::getenv("OG_FIXED_TICK");
  if (e && e[0] == '1') {
    return true;
  }
#ifdef __ANDROID__
  char pv[8] = {0};
  if (__system_property_get("debug.opengoal.fixed_tick", pv) > 0 && pv[0] == '1') {
    return true;
  }
#endif
  return false;
}

}  // namespace

bool enabled() {
  static const bool s_enabled = read_enable_flag();
  return s_enabled;
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
  if (k >= 1) {
    s.armed_frames++;
  }
  if (s.publisher) {
    s.publisher(k >= 1 ? 1 : 0, k >= 1 ? (k - 1) : 0, s.alpha_micro);
  }
}

int begin_render_frame() {
  if (!enabled()) {
    return 0;
  }
  State& s = state();
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

  // Cadence d'affichage plus rapide que le pas fixe : hors perimetre de l'etape 1
  // (il faudrait des images SANS tick). On desarme, le moteur garde son calcul.
  s.dt_ema = 0.85 * s.dt_ema + 0.15 * dt;
  if (s.dt_ema < kFixedTickSeconds * kDisarmFasterThan) {
    s.disarmed_fast_display = true;
    s.accumulator = 0.0;
    s.alpha_micro = 1000000;
    return 0;
  }
  s.disarmed_fast_display = false;

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
    // Peut arriver ponctuellement (une image plus courte qu'un tick alors que la
    // moyenne dit le contraire). On rend 0 : le moteur garde son calcul pour CETTE
    // image et l'accumulateur conserve le reste, donc rien n'est perdu.
    s.alpha_micro = 1000000;
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
