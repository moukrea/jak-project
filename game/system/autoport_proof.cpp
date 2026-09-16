#include "game/system/autoport_proof.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <set>
#include <string>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include "fmt/core.h"

namespace autoport_proof {
namespace {

std::mutex g_mutex;

// Env sur bureau, PROPRIETE sur Android : l'application ne recoit pas l'environnement du shell
// qui l'a lancee, donc sans le second chemin le harnais ne pourrait rien armer sur l'appareil —
// et une course appareil sans ligne FEATURE serait indistinguable d'une feature qui ne tire pas.
bool read_knob(const char* env, const char* prop, char* out, size_t out_sz) {
  if (const char* e = std::getenv(env)) {
    if (e[0]) {
      std::snprintf(out, out_sz, "%s", e);
      return true;
    }
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    std::snprintf(out, out_sz, "%s", buf);
    return true;
  }
#else
  (void)prop;
#endif
  return false;
}

const std::string& feature_str() {
  static std::string s_id;
  static bool s_read = false;
  if (!s_read) {
    s_read = true;
    char v[128] = {0};
    if (read_knob("AUTOPORT_FEATURE", "debug.opengoal.feature", v, sizeof(v))) {
      s_id = v;
    }
  }
  return s_id;
}

uint64_t g_hits = 0;
uint64_t g_frames = 0;

// ============================================================ L'ATTRIBUTION PAR ITEM ==========
// proof-feature-hits-is-vacuous, 2026-09-12. `g_hits` ci-dessus est un compteur PARTAGE par tout
// le binaire : `dead_probe_census()` le remplit une fois par passe, le recensement d'eclairage une
// fois par draw. La ligne `FEATURE <id> armed=1 hits=N` que `validators/generic.sh` exigeait de
// chaque preuve etait donc VRAIE POUR N'IMPORTE QUEL ITEM, y compris ceux dont tout le travail
// vit dans `lib/census/<id>.sh` et qui ne touchent pas une ligne du moteur. Un temoin que rien ne
// peut faire tomber ne temoigne de rien.
//
// Ce qui suit compte SEPAREMENT, par identifiant d'item, et publie les deux comptes cote a cote
// avec leur ecart. Deux items qui tirent sur la MEME course rendent deux comptes differents.
//
// STATIQUES LOCALES, PAS DE PORTEE FICHIER. `register_site()` est appele depuis l'initialisation
// STATIQUE d'autres unites de traduction, dont l'ordre n'est pas defini : un `std::set` de portee
// fichier pourrait n'etre pas encore construit. Une statique locale l'est au premier appel, quel
// qu'il soit. (`g_mutex` est initialise a la COMPILATION — `std::mutex` a un constructeur
// constexpr — donc le verrouiller a ce moment-la est sur.)
std::set<std::string>& sites_ref() {
  static std::set<std::string> s;
  return s;
}
std::map<std::string, uint64_t>& site_hits_ref() {
  static std::map<std::string, uint64_t> m;
  return m;
}

// Le seau des prises qui ne nomment aucun item (`note_hit` nu). Il est PUBLIE, et aucun item ne
// peut s'en prevaloir : c'est la vacuite rendue visible plutot que repartie sur tout le monde.
constexpr const char* kUnattributed = "__unattributed";
// L'item dont le travail EST cette attribution. Son chemin de code est `feature_census_locked()`.
constexpr const char* kOwnItem = "proof-feature-hits-is-vacuous";

// Une valeur de proof.txt ne peut porter AUCUN espace : le moissonneur (`^cle=[^[:space:]]+$`)
// jetterait la ligne entiere. Les identifiants d'items n'en portent pas. La troncature se dit par
// sa propre cle : une liste coupee en silence se lirait « il n'y en a que trois ».
constexpr size_t kListCap = 3000;

// hd-stretch-flag-in-game-logic : le recensement des consultations de l'armement par du code de
// JEU, une table d'identifiants par polarite (voir l'en-tete). On garde les IDENTIFIANTS et pas
// un simple compte : `proof_flag_game_sites` doit nommer ce qu'il compte, sinon un 1 n'apprend
// rien sur QUEL site est revenu.
std::map<std::string, uint64_t> g_flag_ids[2];
uint64_t g_flag_calls[2] = {0, 0};
uint64_t g_flag_census_passes = 0;
std::map<std::string, uint64_t> g_keys;
std::map<std::string, std::string> g_text_keys;

// Cadence de publication. Assez souvent pour qu'une course coupee en plein vol porte quand meme
// ses chiffres, assez rare pour ne pas noyer la trace : 60 images, c'est une seconde sur bureau
// et trois sur le telephone.
constexpr uint64_t kEmitEveryFrames = 60;

bool valid_key(const char* key) {
  if (!key || !key[0]) {
    return false;
  }
  if (!((key[0] >= 'A' && key[0] <= 'Z') || (key[0] >= 'a' && key[0] <= 'z') || key[0] == '_')) {
    return false;
  }
  for (const char* p = key + 1; *p; p++) {
    const char c = *p;
    if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')) {
      return false;
    }
  }
  return true;
}

// Une prise, deja sous le verrou. C'est le SEUL endroit qui touche aux trois compteurs a la
// fois : global, seau de l'item, et presence du site (un site qui TIRE est evidemment compile).
void note_hit_locked(const std::string& id, uint64_t n) {
  g_hits += n;
  site_hits_ref()[id] += n;
  if (id != kUnattributed) {
    sites_ref().insert(id);
  }
}

std::string join_capped(const std::string& s, bool* truncated) {
  if (s.size() <= kListCap) {
    *truncated = false;
    return s.empty() ? std::string("-") : s;
  }
  *truncated = true;
  return s.substr(0, kListCap);
}

// LE RECENSEMENT DE L'ATTRIBUTION, appele a chaque emission, sous le verrou.
void feature_census_locked() {
  // LE SITE DE `proof-feature-hits-is-vacuous`. Cette fonction EST le chemin de code de l'item ;
  // elle se compte sous la meme regle que tous les autres, armement compris.
  if (armed()) {
    note_hit_locked(kOwnItem, 1);
  }
  const auto& sites = sites_ref();
  const auto& hits = site_hits_ref();
  const std::string& id = feature_str();

  uint64_t own = 0;
  uint64_t unattributed = 0;
  uint64_t attributed = 0;
  std::string table;
  for (const auto& kv : hits) {
    if (kv.first == kUnattributed) {
      unattributed = kv.second;
    } else {
      attributed += kv.second;
    }
    if (table.size() < kListCap) {
      if (!table.empty()) {
        table += ',';
      }
      table += fmt::format("{}:{}", kv.first, kv.second);
    }
    if (!id.empty() && kv.first == id) {
      own = kv.second;
    }
  }
  std::string list;
  for (const auto& s : sites) {
    if (list.size() < kListCap) {
      if (!list.empty()) {
        list += ',';
      }
      list += s;
    }
  }
  const bool declared = !id.empty() && sites.count(id) != 0;
  // TROIS ETATS NOMMES, PAS UN SEUL ZERO. `absent` et `declared_unreached` rendent tous les deux
  // un compte nul et ne veulent pas dire la meme chose : le premier est normal pour un item de
  // harnais, le second est un instrument qui n'a pas ete atteint.
  const char* state = "sans_item";
  if (!id.empty()) {
    state = own > 0 ? "hit" : (declared ? "declared_unreached" : "absent");
  }
  bool t_list = false, t_table = false;
  const std::string list_pub = join_capped(list, &t_list);
  const std::string table_pub = join_capped(table, &t_table);

  fmt::print("proof_feature_id={}\n", id.empty() ? "-" : id.c_str());
  fmt::print("proof_feature_state={}\n", state);
  fmt::print("proof_feature_declared={}\n", declared ? 1 : 0);
  fmt::print("proof_feature_own_hits={}\n", own);
  fmt::print("proof_feature_global_hits={}\n", g_hits);
  fmt::print("proof_feature_hits_gap={}\n", g_hits - own);
  fmt::print("proof_feature_hits_attributed={}\n", attributed);
  fmt::print("proof_feature_hits_unattributed={}\n", unattributed);
  fmt::print("proof_feature_sites_total={}\n", (uint64_t)sites.size());
  fmt::print("proof_feature_hits_items={}\n", (uint64_t)hits.size());
  fmt::print("proof_feature_sites_list={}\n", list_pub);
  fmt::print("proof_feature_sites_list_truncated={}\n", t_list ? 1 : 0);
  fmt::print("proof_feature_hits_table={}\n", table_pub);
  fmt::print("proof_feature_hits_table_truncated={}\n", t_table ? 1 : 0);
}

// Ecrit sur stdout, la seule sortie que `proof_run.sh` moissonne des deux cotes : sur bureau elle
// part dans le journal du process, sur Android le lanceur la redirige vers logcat (tag
// GK_STDOUT). `norm()` de proof_run.sh retire les prefixes des deux formats avant d'ancrer sur ^.
void emit_locked() {
  fmt::print("AUTOPORT-FRAMES n={}\n", g_frames);
  const std::string& id = feature_str();
  feature_census_locked();
  if (!id.empty()) {
    // These contracts count their own fragments, vertices, or baseline quantities.
    // `grass-baseline-cost` compte ses RELEVES DE CADENCE, pas les prises du binaire entier : son
    // contrat exige `hits=<releves de cadence effectivement pris>`, et le compteur global monte
    // pour tout le monde.
    uint64_t hits = (id == "ao-prepass-tie-alpha" || id == "shrub-trunk-contact" ||
                     id == "soft-baseline" || id == "grass-baseline-cost")
                        ? site_hits_ref()[id]
                        : g_hits;
    if (id == "water-ocean-mesh") {
      // Cumulative valid observations of the 64 probe vertices, not all submitted vertices.
      const auto it = g_keys.find("water_clipmap_verts_moved");
      hits = armed() && it != g_keys.end() ? it->second : uint64_t{0};
    }
    fmt::print("FEATURE {} armed={} hits={}\n", id, armed() ? 1 : 0, hits);
  }
  for (const auto& kv : g_keys) {
    fmt::print("{}={}\n", kv.first, kv.second);
  }
  for (const auto& kv : g_text_keys) {
    fmt::print("{}={}\n", kv.first, kv.second);
  }
  std::fflush(stdout);
}

}  // namespace

const char* feature_id() {
  return feature_str().c_str();
}

bool feature_is(const char* id) {
  return id && id[0] && feature_str() == id;
}

bool armed() {
  static bool s_armed = true;
  static bool s_read = false;
  if (!s_read) {
    s_read = true;
    // Sans item nomme, il n'y a pas d'ablation possible : le binaire est celui de l'owner, donc
    // ARME. C'est la regle « pas d'acquis sous drapeau optionnel ».
    if (feature_str().empty()) {
      s_armed = true;
    } else {
      char v[32] = {0};
      if (read_knob("AUTOPORT_FEATURE_ARMED", "debug.opengoal.feature.armed", v, sizeof(v))) {
        s_armed = !(v[0] == '0' && v[1] == 0);
      }
    }
  }
  return s_armed;
}

bool armed_for(const char* id) {
  // Sans item nomme : rien n'est sous ablation, tout est arme (le binaire de l'owner).
  // Item nomme mais different du notre : ce n'est pas notre bras d'ablation, on reste arme.
  if (feature_str().empty() || !id || !id[0] || feature_str() != id) {
    return true;
  }
  return armed();
}

void note_hit(uint64_t n) {
  if (!armed()) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  // Sans item nomme, la prise va dans le seau `__unattributed` : elle continue de remplir le
  // total global (la ligne FEATURE ne change pas de sens) mais AUCUN item ne la compte pour lui.
  note_hit_locked(kUnattributed, n);
}

void note_hit_for(const char* id, uint64_t n) {
  if (!armed()) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  note_hit_locked((id && id[0]) ? std::string(id) : std::string(kUnattributed), n);
}

void register_site(const char* id) {
  if (!id || !id[0]) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  sites_ref().insert(id);
}

void publish(const char* key, uint64_t value) {
  if (!valid_key(key)) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_text_keys.erase(key);
  g_keys[key] = value;
}

void publish_text(const char* key, const char* value) {
  if (!valid_key(key) || !value || !value[0]) {
    return;
  }
  std::string v(value);
  for (char& c : v) {
    if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
      c = '_';
    }
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_keys.erase(key);
  g_text_keys[key] = v;
}

bool has_key(const char* key) {
  if (!valid_key(key)) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_keys.count(key) != 0 || g_text_keys.count(key) != 0;
}

bool read_uint(const char* key, uint64_t& value) {
  if (!valid_key(key)) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  const auto it = g_keys.find(key);
  if (it == g_keys.end()) {
    return false;
  }
  value = it->second;
  return true;
}

void note_flag_consult(int polarity, const char* id) {
  const int p = (polarity == kFlagSafe) ? 1 : 0;
  const char* key = (id && id[0]) ? id : "__unnamed";
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_flag_calls[p]++;
    g_flag_ids[p][key]++;
  }
}

void publish_flag_census(const char* hit_item_id) {
  uint64_t sites[2];
  uint64_t calls[2];
  uint64_t passes;
  std::string list[2];
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    passes = ++g_flag_census_passes;
    for (int p = 0; p < 2; p++) {
      sites[p] = (uint64_t)g_flag_ids[p].size();
      calls[p] = g_flag_calls[p];
      for (const auto& kv : g_flag_ids[p]) {
        if (list[p].size() >= 160) {
          break;
        }
        if (!list[p].empty()) {
          list[p] += ',';
        }
        list[p] += kv.first;
      }
    }
  }
  // LA PORTE. Le nombre d'identifiants distincts consultes en polarite DANGEREUSE par du code de
  // jeu pendant CETTE course. Zero = aucun site ; un site reintroduit demain le fait remonter.
  publish("proof_flag_game_sites", sites[kFlagDangerous]);
  publish("proof_flag_game_calls", calls[kFlagDangerous]);
  // LE TEMOIN. La polarite SURE passe par les ponts voisins, enregistres dans le MEME bloc
  // `InitMachine_PCPort` que le pont dangereux. Non nul = le pont GOAL->C de cette famille est
  // bien relie sur CETTE machine, donc le zero ci-dessus vient d'une absence de SITE et non
  // d'une absence de pont. Un zero ici rendrait la porte muette, pas verte.
  publish("proof_flag_ablation_sites", sites[kFlagSafe]);
  publish("proof_flag_ablation_calls", calls[kFlagSafe]);
  // Le denominateur de ce recensement a lui : `hits` est partage par tout le binaire.
  publish("proof_flag_census_passes", passes);
  // Une cle de TEXTE ne se vide jamais toute seule : liste vide => "-", sinon la derniere liste
  // non vide resterait a cote d'un compte a zero.
  publish_text("proof_flag_game_list", list[kFlagDangerous].empty() ? "-" : list[kFlagDangerous].c_str());
  publish_text("proof_flag_ablation_list", list[kFlagSafe].empty() ? "-" : list[kFlagSafe].c_str());
  if (feature_is(hit_item_id)) {
    note_hit(1);
  }
}

void frame_tick() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_frames++;
  if (g_frames % kEmitEveryFrames == 0) {
    emit_locked();
  }
}

void flush() {
  std::lock_guard<std::mutex> lock(g_mutex);
  emit_locked();
}

// Le site de l'item est DECLARE au chargement comme tous les autres : sans cette ligne, une
// course ou l'emission n'aurait jamais lieu le dirait « absent » au lieu de « jamais atteint ».
AUTOPORT_FEATURE_SITE("proof-feature-hits-is-vacuous");

}  // namespace autoport_proof
