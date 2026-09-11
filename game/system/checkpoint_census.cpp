#include "game/system/checkpoint_census.h"

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <string>
#include <vector>

#include "common/util/FileUtil.h"

#include "game/system/autoport_proof.h"

namespace checkpoint_census {
namespace {

constexpr const char* kItem = "builder-checkpoint-steals-work";
constexpr const char* kCensus = ".autoport/lib/checkpoint_census.py";
constexpr const char* kSelftest = ".autoport/lib/checkpoint_selftest.sh";
constexpr const char* kGuard = ".autoport/lib/checkpoint_snapshot.sh";
constexpr const char* kBuilder = ".autoport/auto_build_apk.sh";

bool g_done = false;
uint32_t g_frames = 0;

// Sortie standard d'une commande. `ok` distingue « rien a dire » de « n'a pas tourne » : un
// echec silencieux devient un zero, et un zero passe une porte `== 0`.
std::string capture(const std::string& cmd, bool* ok) {
  *ok = false;
  FILE* p = popen(cmd.c_str(), "r");
  if (!p) {
    return {};
  }
  std::string out;
  char buf[4096];
  while (fgets(buf, sizeof(buf), p)) {
    out += buf;
  }
  *ok = (pclose(p) == 0);
  return out;
}

// Les `cle=valeur` seules sur leur ligne, derniere valeur gagnante — la meme regle que
// `proof_run.sh` applique a la sortie du moteur.
std::map<std::string, std::string> parse_kv(const std::string& text) {
  std::map<std::string, std::string> kv;
  size_t start = 0;
  while (start <= text.size()) {
    size_t end = text.find('\n', start);
    if (end == std::string::npos) {
      end = text.size();
    }
    const std::string line = text.substr(start, end - start);
    const size_t eq = line.find('=');
    if (eq != std::string::npos && eq > 0) {
      std::string key = line.substr(0, eq);
      bool key_ok = !key.empty() && (isalpha((unsigned char)key[0]) || key[0] == '_');
      for (char c : key) {
        if (!isalnum((unsigned char)c) && c != '_') {
          key_ok = false;
        }
      }
      if (key_ok) {
        kv[key] = line.substr(eq + 1);
      }
    }
    if (end == text.size()) {
      break;
    }
    start = end + 1;
  }
  return kv;
}

// -1 = la cle manque. Jamais 0 : voir « inconnu = defaut » dans l'en-tete.
long num(const std::map<std::string, std::string>& kv, const char* key) {
  auto it = kv.find(key);
  if (it == kv.end() || it->second.empty()) {
    return -1;
  }
  char* endp = nullptr;
  const long v = std::strtol(it->second.c_str(), &endp, 10);
  if (!endp || *endp != '\0') {
    return -1;
  }
  return v;
}

void publish_sha(const std::string& repo, const char* key, const char* relative) {
  bool ok = false;
  const std::string out = capture("sha256sum '" + repo + "/" + relative + "' 2>/dev/null", &ok);
  autoport_proof::publish_text(key, (ok && out.size() >= 16) ? out.substr(0, 16).c_str() : "-");
}

void run_once() {
  const std::string repo = file_util::get_jak_project_dir().string();
  // Ni depot ni recolte : on le DIT, et la porte reste rouge. Une passe muette qui publierait
  // zero se lirait « rien n'a ete vole » alors qu'elle veut dire « personne n'a regarde ».
  if (repo.empty() || !fs::exists(fs::path(repo) / ".git") ||
      !fs::exists(fs::path(repo) / kCensus)) {
    autoport_proof::publish("checkpoint_census_ran", 0);
    autoport_proof::publish("checkpoint_stolen_files", 1);
    autoport_proof::publish_text("checkpoint_stolen_files_terms", "recensement=absent");
    autoport_proof::note_hit(1);
    return;
  }

  bool ok = false;
  const std::string raw = capture("python3 '" + repo + "/" + kCensus + "' 2>/dev/null", &ok);
  const auto kv = parse_kv(raw);

  // ── LES TROIS TERMES MESURES ────────────────────────────────────────────────────────────────
  // Chacun sur sa propre cle : une porte qui ne publie que sa somme ne dit pas ce qui a cede.
  long history_after = num(kv, "history_stolen_after");
  long sandbox_stolen = num(kv, "selftest_stolen");
  long unsafe_sites = num(kv, "audit_unsafe_sites");
  if (history_after < 0) {
    history_after = 1;
  }
  if (sandbox_stolen < 0) {
    sandbox_stolen = 1;
  }
  if (unsafe_sites < 0) {
    unsafe_sites = 1;
  }

  // ── LES TEMOINS, ET LA PENALITE QU'UN TEMOIN MUET COUTE ─────────────────────────────────────
  // `history_stolen_before` n'est PAS dans cette liste, a dessein : il vaut 89 aujourd'hui et
  // tombera legitimement a 0 quand les commits fautifs sortiront de la fenetre de 50. Le penaliser
  // rendrait la porte rouge pour toujours a une date arbitraire. Ce qui rend le zero falsifiable
  // ne depend donc pas de lui : c'est le bac a sable (il FABRIQUE la condition) et
  // `audit_before_sites` (ancre sur un sha fige, donc stable).
  long penalty = 0;
  std::string why;
  auto require = [&](const char* label, bool good) {
    if (!good) {
      penalty++;
      why += (why.empty() ? "" : "+");
      why += label;
    }
  };
  require("recolte", ok && !kv.empty());
  require("histoire", num(kv, "history_ran") == 1);
  require("audit", num(kv, "audit_ran") == 1);
  require("bac-a-sable", num(kv, "selftest_ran") == 1);
  require("garde-absente", num(kv, "guard_present") == 1);
  require("rien-a-voler", num(kv, "selftest_planted") >= 4);
  require("controle-positif-muet", num(kv, "selftest_ablation_stolen") >= 1);
  require("instantane-incomplet",
          num(kv, "selftest_snapshot_files") == num(kv, "selftest_planted"));
  require("index-abime", num(kv, "selftest_index_kept") == 1);
  require("arbre-abime", num(kv, "selftest_worktree_kept") == 1);
  require("head-bouge", num(kv, "selftest_head_moved") == 0);
  require("audit-aveugle", num(kv, "audit_before_sites") >= 2);

  const long total = history_after + sandbox_stolen + unsafe_sites + penalty;
  autoport_proof::publish("checkpoint_stolen_files", (uint64_t)total);
  autoport_proof::publish("checkpoint_census_ran", (ok && !kv.empty()) ? 1 : 0);
  autoport_proof::publish("checkpoint_history_after_guard", (uint64_t)history_after);
  autoport_proof::publish("checkpoint_sandbox_stolen", (uint64_t)sandbox_stolen);
  autoport_proof::publish("checkpoint_unsafe_commit_sites", (uint64_t)unsafe_sites);
  autoport_proof::publish("checkpoint_witness_penalty", (uint64_t)penalty);
  autoport_proof::publish_text(
      "checkpoint_stolen_files_terms",
      ("histoire" + std::to_string(history_after) + "+bac" + std::to_string(sandbox_stolen) +
       "+scripts" + std::to_string(unsafe_sites) + "+penalite" + std::to_string(penalty) +
       (why.empty() ? "" : ":" + why))
          .c_str());

  // Les grandeurs de la recolte, recopiees telles quelles : ce sont elles qui rendent la somme
  // lisible, et une valeur manquante sort en 0 seulement ici, jamais dans le verdict.
  static const char* const kRelay[] = {"history_commits_scanned",
                                       "history_checkpoint_commits",
                                       "history_stolen_before",
                                       "audit_files_scanned",
                                       "audit_sites",
                                       "audit_exempt_sites",
                                       "audit_before_sites",
                                       "selftest_planted",
                                       "selftest_ablation_stolen",
                                       "selftest_snapshot_files",
                                       "selftest_index_kept",
                                       "selftest_worktree_kept",
                                       "selftest_head_moved",
                                       "guard_present"};
  for (const char* key : kRelay) {
    const long v = num(kv, key);
    autoport_proof::publish(("checkpoint_" + std::string(key)).c_str(), (uint64_t)(v < 0 ? 0 : v));
  }
  {
    auto it = kv.find("audit_unsafe_list");
    const std::string list = (it == kv.end() || it->second.empty()) ? "-" : it->second;
    autoport_proof::publish_text("checkpoint_unsafe_list", list.c_str());
  }

  // LES OCTETS JUGES. Un chemin n'est pas une provenance : la preuve porte l'empreinte de chaque
  // script que cette passe a lu ou lance.
  publish_sha(repo, "checkpoint_census_sha", kCensus);
  publish_sha(repo, "checkpoint_selftest_sha", kSelftest);
  publish_sha(repo, "checkpoint_guard_sha", kGuard);
  publish_sha(repo, "checkpoint_builder_sha", kBuilder);

  autoport_proof::note_hit(1);
}

}  // namespace

void tick() {
  // L'instrument ne tourne que sous mesure, et une seule fois : l'objet mesure est le depot, il
  // ne change pas d'une image a l'autre. La passe coute ~0,25 s, elle est faite une fois pour
  // toutes a l'image 240 — le temps que la course soit franchement demarree.
  if (g_done || !autoport_proof::feature_is(kItem)) {
    return;
  }
  if (++g_frames < 240) {
    return;
  }
  g_done = true;
  run_once();
}

}  // namespace checkpoint_census
