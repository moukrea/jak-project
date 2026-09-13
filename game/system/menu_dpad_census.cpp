// menu_dpad_census — CE QUE COMPTE `menu_step_overshoots`.
//
// Une pression qui ne bouge rien compte comme un depassement : le livrable exige un rapport de 1,
// pas un rapport <= 1. Toute pression dont le nombre de crans DIFFERE DE 1 — zero cran ignore
// comme deux crans sautes — entre donc dans `menu_step_overshoots`. Les pressions a zero cran
// sont AUSSI publiees a part sous `menu_step_misses`, pour dire lequel des deux defauts on
// regarde.
//
// LA PORTE LIT UNE CHAINE : « une pression du doigt = un front = un cran », et elle rougit des
// qu'un des deux maillons se dedouble. `menu_step_overshoots` est donc la somme des pressions
// dont le nombre de crans differe de 1 (par jambe) ET des gestes dont le nombre de fronts differe
// de 1 (`menu_step_gesture_multi`).

#include "game/system/menu_dpad_census.h"

#include <algorithm>
#include <cstdio>
#include <map>
#include <mutex>
#include <set>
#include <string>

#include "game/system/autoport_proof.h"

// CE BINAIRE PORTE UN SITE DE `menu-dpad-steps`. Au niveau NAMESPACE : l'enregistrement doit
// avoir lieu au CHARGEMENT, sinon la porte ne peut pas separer « instrument absent » de
// « instrument jamais atteint ».
AUTOPORT_FEATURE_SITE("menu-dpad-steps");

namespace menu_dpad_census {
namespace {

constexpr int kLegCount = 4;   // 0 repos, 1 manette, 2 tactile-franc, 3 tactile-seme
constexpr int kLegPad = 1;
constexpr int kLegTouch = 2;
constexpr int kLegSeed = 3;

// Sans nouvelle passe de respond-common pendant ce nombre d'images RENDUES, le menu est
// considere ferme : toute pression encore ouverte est cloturee comme si la touche etait
// retombee. Sans cela, une pression restee ouverte a la fermeture du menu ne serait jamais
// comptee — ni en cran, ni en depassement.
constexpr uint64_t kIdleFramesToClose = 30;

constexpr uint64_t kPublishEveryFrames = 300;

struct Dir {
  bool prev_held = false;
  bool open = false;
  uint64_t steps_in_press = 0;
  uint64_t hold_frames = 0;
  int press_screen = -1;
  int press_leg = 0;
};

struct State {
  std::mutex mu;

  Dir dir[2];  // 0 = haut, 1 = bas

  int leg = 0;
  int last_screen = -1;
  uint64_t frames_noted = 0;          // appels a note_frame
  uint64_t frames_since_note = kIdleFramesToClose + 1;

  // TEMOIN DU REGIME (correction du 13/09). `note_frame` tourne une fois par passe de
  // `respond-common`, `publish_tick` une fois par image RENDUE : leur rapport dit si l'horloge a
  // pas fixe a fait repasser l'arbre des processus plusieurs fois pour UNE lecture du pad. Sans
  // lui, un zero de depassement se lirait aussi bien sur une course ou la condition du defaut
  // etait ABSENTE.
  uint64_t passes_this_frame = 0;
  uint64_t passes_per_frame_max = 0;
  uint64_t passes_per_frame_multi = 0;

  uint64_t presses = 0;
  uint64_t steps_total = 0;
  uint64_t misses = 0;
  uint64_t tap_steps = 0;
  uint64_t orphan_steps = 0;
  uint64_t overshoots = 0;

  uint64_t presses_by_leg[kLegCount] = {0, 0, 0, 0};
  uint64_t steps_by_leg[kLegCount] = {0, 0, 0, 0};
  uint64_t overshoots_by_leg[kLegCount] = {0, 0, 0, 0};

  std::set<int> pages_seen;

  // PAR PAGE. Le livrable exige le nombre de pressions ET de crans « par page (menu principal
  // ET sous-menus) », pas seulement la liste des pages visitees : une page ou le rapport ne
  // vaut pas 1 doit se lire SANS relire le journal. La cle est `display-state`, la valeur
  // {pressions, crans, depassements}. Les trois sont alimentes au meme endroit que le total
  // (`close_press`), donc la somme des pages EGALE le total par construction.
  struct PageStat {
    uint64_t presses = 0;
    uint64_t steps = 0;
    uint64_t overshoots = 0;
  };
  std::map<int, PageStat> page_stat;

  uint64_t hold_frames_max = 0;
  uint64_t hold_steps_at_max = 0;

  uint64_t gestures = 0;
  uint64_t gesture_edges = 0;
  uint64_t gesture_legacy_edges = 0;
  uint64_t seed_gestures = 0;
  uint64_t gesture_multi = 0;
  uint64_t seed_legacy_edges = 0;

  int dead_x100 = 0;
  int arm_inner_x100 = 0;
  int seed_dip_x100 = 0;
  bool geometry_seen = false;

  int legs_done = 0;

  // Publication : une empreinte qui bouge a chaque ecriture, pour ne republier que sur
  // changement (ou toutes les kPublishEveryFrames images).
  uint64_t revision = 1;
  uint64_t published_revision = 0;
  uint64_t frames_since_publish = kPublishEveryFrames + 1;
  bool published_once = false;
};

State& s() {
  static State state;
  return state;
}

// Cloture une pression. A appeler sous le mutex.
void close_press(State& st, int d) {
  Dir& dd = st.dir[d];
  if (!dd.open) {
    return;
  }
  int leg = dd.press_leg;
  if (leg < 0 || leg >= kLegCount) {
    leg = 0;
  }
  st.steps_total += dd.steps_in_press;
  st.steps_by_leg[leg] += dd.steps_in_press;
  if (dd.steps_in_press != 1) {
    // Zero cran ou deux crans : les deux sont un defaut au meme titre. Le livrable exige un
    // rapport de 1, pas un rapport <= 1.
    st.overshoots++;
    st.overshoots_by_leg[leg]++;
  }
  if (dd.steps_in_press == 0) {
    // Publie a part (`menu_step_misses`) pour nommer LEQUEL des deux defauts on regarde.
    st.misses++;
  }
  if (dd.hold_frames > st.hold_frames_max) {
    st.hold_frames_max = dd.hold_frames;
    st.hold_steps_at_max = dd.steps_in_press;
  }
  st.pages_seen.insert(dd.press_screen);
  {
    State::PageStat& ps = st.page_stat[dd.press_screen];
    ps.presses++;
    ps.steps += dd.steps_in_press;
    if (dd.steps_in_press != 1) {
      ps.overshoots++;
    }
  }
  dd.open = false;
  dd.steps_in_press = 0;
  dd.hold_frames = 0;
  st.revision++;
}

}  // namespace

void note_frame(int mask, int steps, int screen) {
  // Le temoin que l'instrument de CET item a tourne.
  autoport_proof::note_hit_for("menu-dpad-steps", 1);

  State& st = s();
  std::lock_guard<std::mutex> lk(st.mu);

  st.frames_noted++;
  st.passes_this_frame++;
  st.frames_since_note = 0;
  st.last_screen = screen;

  int leg = st.leg;
  if (leg < 0 || leg >= kLegCount) {
    leg = 0;
  }

  const bool held[2] = {(mask & 1) != 0, (mask & 2) != 0};
  const bool edge[2] = {(mask & 4) != 0, (mask & 8) != 0};

  // 1. fronts montants : ouverture de pression.
  for (int d = 0; d < 2; d++) {
    if (held[d] && !st.dir[d].prev_held) {
      st.presses++;
      st.presses_by_leg[leg]++;
      Dir& dd = st.dir[d];
      dd.open = true;
      dd.steps_in_press = 0;
      dd.hold_frames = 0;
      dd.press_screen = screen;
      dd.press_leg = leg;
      st.revision++;
    }
  }

  // 2. attribution des crans de CETTE image, une seule fois.
  if (steps > 0) {
    const uint64_t n = (uint64_t)steps;
    int target = -1;
    if (edge[0]) {
      target = 0;
    } else if (edge[1]) {
      target = 1;
    } else if (held[0] && !held[1]) {
      target = 0;
    } else if (held[1] && !held[0]) {
      target = 1;
    }
    if (target >= 0 && st.dir[target].open) {
      st.dir[target].steps_in_press += n;
    } else if (!held[0] && !held[1]) {
      // canal tap du menu (bits 16/32) : ni cran de pression, ni depassement.
      st.tap_steps += n;
    } else {
      st.orphan_steps += n;
    }
    st.revision++;
  }

  // 3. duree de maintien.
  for (int d = 0; d < 2; d++) {
    if (held[d] && st.dir[d].open) {
      st.dir[d].hold_frames++;
    }
  }

  // 4. fronts descendants : cloture.
  for (int d = 0; d < 2; d++) {
    if (!held[d] && st.dir[d].prev_held) {
      close_press(st, d);
    }
    st.dir[d].prev_held = held[d];
  }
}

void set_leg(int leg) {
  State& st = s();
  std::lock_guard<std::mutex> lk(st.mu);
  if (leg < 0 || leg >= kLegCount) {
    leg = 0;
  }
  if (st.leg != leg) {
    st.leg = leg;
    st.revision++;
  }
}

void note_gesture(int edges, int legacy_edges) {
  State& st = s();
  std::lock_guard<std::mutex> lk(st.mu);
  st.gestures++;
  if (edges > 0) {
    st.gesture_edges += (uint64_t)edges;
  }
  if (legacy_edges > 0) {
    st.gesture_legacy_edges += (uint64_t)legacy_edges;
  }
  if (edges != 1) {
    // Un geste qui emet deux fronts se lit, plus bas, comme deux pressions propres d'un cran
    // chacune : `presses` compte les fronts du bit TENU tels que GOAL les voit, et un rebond
    // tactile au milieu d'un seul appui du doigt en fabrique deux. Sans ce compte la porte serait
    // verte sur le rebond que cet item existe pour supprimer.
    // Seul `edges` entre ici : `legacy_edges` ne juge rien, il ne sert qu'au code de vacuite 8.
    st.overshoots++;
    st.gesture_multi++;
  }
  if (st.leg == kLegSeed) {
    st.seed_gestures++;
    if (legacy_edges > 0) {
      st.seed_legacy_edges += (uint64_t)legacy_edges;
    }
  }
  st.revision++;
}

void note_geometry(int dead_x100, int arm_inner_x100, int seed_dip_x100) {
  State& st = s();
  std::lock_guard<std::mutex> lk(st.mu);
  st.dead_x100 = dead_x100;
  st.arm_inner_x100 = arm_inner_x100;
  st.seed_dip_x100 = seed_dip_x100;
  st.geometry_seen = true;
  st.revision++;
}

void note_campaign_done(int legs_done) {
  State& st = s();
  std::lock_guard<std::mutex> lk(st.mu);
  st.legs_done = legs_done;
  st.revision++;
}

int current_screen() {
  State& st = s();
  std::lock_guard<std::mutex> lk(st.mu);
  return st.last_screen;
}

bool menu_live() {
  State& st = s();
  std::lock_guard<std::mutex> lk(st.mu);
  return st.frames_since_note < kIdleFramesToClose;
}

void publish_tick() {
  State& st = s();
  std::lock_guard<std::mutex> lk(st.mu);

  if (st.passes_this_frame > 0) {
    if (st.passes_this_frame > st.passes_per_frame_max) {
      st.passes_per_frame_max = st.passes_this_frame;
      st.revision++;
    }
    if (st.passes_this_frame >= 2) {
      st.passes_per_frame_multi++;
      st.revision++;
    }
    st.passes_this_frame = 0;
  }

  if (st.frames_since_note <= kIdleFramesToClose) {
    st.frames_since_note++;
    if (st.frames_since_note > kIdleFramesToClose) {
      // Menu ferme : toute pression en cours est cloturee comme si la touche etait retombee.
      for (int d = 0; d < 2; d++) {
        close_press(st, d);
        st.dir[d].prev_held = false;
      }
    }
  }

  st.frames_since_publish++;
  if (st.published_once && st.revision == st.published_revision &&
      st.frames_since_publish < kPublishEveryFrames) {
    return;
  }
  st.published_revision = st.revision;
  st.frames_since_publish = 0;
  st.published_once = true;

  autoport_proof::publish("menu_step_presses", st.presses);
  autoport_proof::publish("menu_step_steps", st.steps_total);
  autoport_proof::publish("menu_step_misses", st.misses);
  autoport_proof::publish("menu_step_tap_steps", st.tap_steps);
  // Un cran qu'on n'a pas su attribuer a une direction : s'il est non nul, la comptabilite par
  // direction est fausse et le zero de depassement ne vaut rien.
  autoport_proof::publish("menu_step_orphan_steps", st.orphan_steps);

  // La jambe « repos » : ce qui a ete presse hors campagne. Non nul, c'est une entree que le
  // pilote n'a pas produite — il faut le voir, pas le deviner.
  autoport_proof::publish("menu_step_presses_idle", st.presses_by_leg[0]);
  autoport_proof::publish("menu_step_overshoots_idle", st.overshoots_by_leg[0]);

  autoport_proof::publish("menu_step_presses_pad", st.presses_by_leg[kLegPad]);
  autoport_proof::publish("menu_step_steps_pad", st.steps_by_leg[kLegPad]);
  autoport_proof::publish("menu_step_overshoots_pad", st.overshoots_by_leg[kLegPad]);

  autoport_proof::publish("menu_step_presses_touch", st.presses_by_leg[kLegTouch]);
  autoport_proof::publish("menu_step_steps_touch", st.steps_by_leg[kLegTouch]);
  autoport_proof::publish("menu_step_overshoots_touch", st.overshoots_by_leg[kLegTouch]);

  autoport_proof::publish("menu_step_presses_seed", st.presses_by_leg[kLegSeed]);
  autoport_proof::publish("menu_step_steps_seed", st.steps_by_leg[kLegSeed]);
  autoport_proof::publish("menu_step_overshoots_seed", st.overshoots_by_leg[kLegSeed]);

  autoport_proof::publish("menu_step_pages", (uint64_t)st.pages_seen.size());
  {
    std::string list;
    for (int page : st.pages_seen) {
      if (!list.empty()) {
        list += ",";
      }
      char buf[24];
      snprintf(buf, sizeof(buf), "%d", page);
      list += buf;
    }
    autoport_proof::publish_text("menu_step_pages_list", list.empty() ? "-" : list.c_str());
  }
  {
    // `<page>:<pressions>/<crans>/<depassements>`, pages separees par une virgule. AUCUN ESPACE :
    // `proof.txt` jette toute valeur qui en contient, et la ligne serait publiee pour personne.
    std::string table;
    uint64_t pages_bad = 0;
    for (const auto& kv : st.page_stat) {
      if (!table.empty()) {
        table += ",";
      }
      char buf[80];
      snprintf(buf, sizeof(buf), "%d:%llu/%llu/%llu", kv.first,
               (unsigned long long)kv.second.presses, (unsigned long long)kv.second.steps,
               (unsigned long long)kv.second.overshoots);
      table += buf;
      if (kv.second.steps != kv.second.presses) {
        pages_bad++;
      }
    }
    autoport_proof::publish_text("menu_step_pages_table", table.empty() ? "-" : table.c_str());
    // Le scalaire qui dit, sans lire la table, si UNE page a un rapport different de 1.
    autoport_proof::publish("menu_step_pages_ratio_bad", pages_bad);
  }

  autoport_proof::publish("menu_step_hold_frames_max", st.hold_frames_max);
  autoport_proof::publish("menu_step_hold_steps_at_max", st.hold_steps_at_max);

  autoport_proof::publish("menu_step_gestures", st.gestures);
  autoport_proof::publish("menu_step_gesture_edges", st.gesture_edges);
  autoport_proof::publish("menu_step_gesture_legacy_edges", st.gesture_legacy_edges);
  autoport_proof::publish("menu_step_gesture_multi", st.gesture_multi);
  autoport_proof::publish("menu_step_seed_gestures", st.seed_gestures);
  autoport_proof::publish("menu_step_seed_legacy_edges", st.seed_legacy_edges);

  autoport_proof::publish("menu_step_dead_x100", (uint64_t)(st.dead_x100 < 0 ? 0 : st.dead_x100));
  autoport_proof::publish("menu_step_arm_inner_x100",
                          (uint64_t)(st.arm_inner_x100 < 0 ? 0 : st.arm_inner_x100));
  autoport_proof::publish(
      "menu_step_seed_dip_x100",
      (uint64_t)(st.geometry_seen && st.seed_dip_x100 > 0 ? st.seed_dip_x100 : 0));
  {
    int margin = st.geometry_seen ? (st.arm_inner_x100 - st.dead_x100) : 0;
    autoport_proof::publish("menu_step_margin_x100", (uint64_t)(margin < 0 ? 0 : margin));
  }

  autoport_proof::publish("menu_step_legs_done", (uint64_t)(st.legs_done < 0 ? 0 : st.legs_done));
  autoport_proof::publish("menu_step_frames", st.frames_noted);
  autoport_proof::publish("menu_step_passes_per_frame_max", st.passes_per_frame_max);
  autoport_proof::publish("menu_step_passes_per_frame_multi", st.passes_per_frame_multi);

  // POLARITE : tout inconnu vaut DEFAUT. Le premier code qui echoue gagne.
  int code = 0;
  const char* reason = "-";
  if (st.frames_noted == 0) {
    code = 1;
    reason = "aucun_menu_observe";
  } else if (st.legs_done != 7) {
    code = 2;
    reason = "campagne_incomplete_les_trois_jambes_non_finies";
  } else if (st.presses_by_leg[kLegPad] < 12) {
    code = 3;
    reason = "pressions_manette_insuffisantes";
  } else if (st.presses_by_leg[kLegTouch] < 6) {
    code = 4;
    reason = "pressions_tactile_franc_insuffisantes";
  } else if (st.presses_by_leg[kLegSeed] < 4) {
    code = 5;
    reason = "pressions_tactile_seme_insuffisantes";
  } else if (st.pages_seen.size() < 2) {
    code = 6;
    reason = "moins_de_deux_pages_visitees";
  } else if (st.gestures == 0) {
    code = 7;
    reason = "aucun_geste_pilote";
  } else if (st.seed_legacy_edges <= st.seed_gestures) {
    // Le controle seme n'a pas produit, sous l'ANCIENNE regle, plus d'un front par geste : il ne
    // semait rien, et un zero de depassement ne voudrait rien dire.
    code = 8;
    reason = "controle_seme_ne_semait_rien_sous_la_regle_d_origine";
  }

  autoport_proof::publish("menu_step_vacuity", (uint64_t)code);
  autoport_proof::publish_text("menu_step_vacuity_reason", reason);
  if (code != 0) {
    autoport_proof::publish("menu_step_overshoots", (uint64_t)(9000 + code));
  } else {
    // Les deux maillons de la chaine : pressions a nombre de crans != 1, et gestes a nombre de
    // fronts != 1. On publie le TOTAL tenu par `st.overshoots`, pas la somme des trois jambes
    // pilotees : une pression survenue hors campagne (jambe 0, « repos ») compte pour l'owner
    // comme n'importe quelle autre, et l'additionner a la main la laisserait dehors en silence.
    // `menu_step_overshoots` = pad + touch + seed + repos + gesture_multi.
    autoport_proof::publish("menu_step_overshoots", st.overshoots);
  }
}

}  // namespace menu_dpad_census
