#include "game/system/naming_census.h"

#include <algorithm>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "common/util/FileUtil.h"
#include "common/versions/versions.h"

#include "game/runtime.h"
#include "game/system/autoport_proof.h"

#include "fmt/core.h"
AUTOPORT_FEATURE_SITE("recharged-naming");

namespace naming_census {
namespace {

// ── LES JETONS ──────────────────────────────────────────────────────────────────────────────
// Voir l'en-tete pour le choix de « Precursor Legacy » plutot que « Precursor », et de la casse
// exacte pour « OpenGOAL ».
constexpr const char* kLegacyTokens[] = {"precursor legacy", "jak-pot"};
constexpr const char* kOpenGoal = "OpenGOAL";

// Les emplois d'« OpenGOAL » qui ne nomment pas le produit, reconnus par leur CONTEXTE et non
// par le fichier ou ils tombent : une exemption par fichier laisserait passer un vrai site de
// nommage qui atterrirait dans le meme conteneur.
constexpr const char* kToolingContexts[] = {"Created by OpenGOAL build", "not supported in OpenGOAL"};

std::string lower(std::string s) {
  for (char& c : s) {
    if (c >= 'A' && c <= 'Z') {
      c = (char)(c - 'A' + 'a');
    }
  }
  return s;
}

// ── LE BANC LIVRE ───────────────────────────────────────────────────────────────────────────
// Meme format que celui que `settings_case_l10n` relit deja (voir son en-tete pour le detail
// des offsets) : LinkHeaderV2 de 12 octets dont `length` donne l'offset du corps, puis
// { type-tag, nombre d'entrees, language-id, group-name }, puis N couples { id, renvoi }.
struct Bank {
  int language = -1;
  std::map<int, std::string> lines;
};

bool read_u32(const std::vector<uint8_t>& d, size_t off, uint32_t* out) {
  if (off + 4 > d.size()) {
    return false;
  }
  std::memcpy(out, d.data() + off, 4);
  return true;
}

bool read_bank(const std::string& path, Bank* out) {
  std::vector<uint8_t> d;
  try {
    d = file_util::read_binary_file(path);
  } catch (...) {
    return false;
  }
  uint32_t tag = 0, len = 0, ver = 0;
  if (!read_u32(d, 0, &tag) || !read_u32(d, 4, &len) || !read_u32(d, 8, &ver)) {
    return false;
  }
  if (ver != 2 || len < 12 || len >= d.size()) {
    return false;
  }
  const size_t body = len;
  uint32_t count = 0, lang = 0, dummy = 0;
  if (!read_u32(d, body + 4, &count) || !read_u32(d, body + 8, &lang)) {
    return false;
  }
  if (count > 100000) {
    return false;
  }
  out->language = (int)lang;
  for (uint32_t i = 0; i < count; i++) {
    uint32_t id = 0, ref = 0;
    if (!read_u32(d, body + 16 + 8 * i, &id) || !read_u32(d, body + 20 + 8 * i, &ref)) {
      return false;
    }
    if (ref == 0 || !read_u32(d, body + ref, &dummy)) {
      continue;
    }
    const size_t start = body + ref + 4;
    size_t end = start;
    while (end < d.size() && d[end] != 0) {
      end++;
    }
    out->lines[(int)id] = std::string((const char*)d.data() + start, end - start);
  }
  return true;
}

// ── L'ETAT ──────────────────────────────────────────────────────────────────────────────────
bool g_done = false;
uint32_t g_frames = 0;
constexpr uint64_t kVacuous = 9999;

// Les deux identifiants que `draw-title-credits` dessine cote a cote pendant la sequence
// d'ouverture (goal_src/jak1/engine/ui/credits.gc:47, base 3840 = #xf00, groupe 6) : c'est LA
// ou le jeu s'annonce par son nom complet.
constexpr int kTitleLine1 = 0xf06;
constexpr int kTitleLine2 = 0xf07;

std::vector<std::string> g_offenders;
void note_offender(const std::string& s) {
  if (g_offenders.size() < 16) {
    g_offenders.push_back(s);
  }
}

// Combien de fois `needle` apparait dans `hay`, et ou.
std::vector<size_t> find_all(const std::string& hay, const std::string& needle) {
  std::vector<size_t> out;
  if (needle.empty()) {
    return out;
  }
  for (size_t p = hay.find(needle); p != std::string::npos; p = hay.find(needle, p + 1)) {
    out.push_back(p);
  }
  return out;
}

bool has_legacy_token(const std::string& s) {
  const std::string low = lower(s);
  for (const char* tok : kLegacyTokens) {
    if (low.find(tok) != std::string::npos) {
      return true;
    }
  }
  return false;
}

// Toutes les chaines entre guillemets doubles d'un texte source, ligne par ligne.
std::vector<std::string> quoted_literals(const std::string& text) {
  std::vector<std::string> out;
  size_t i = 0;
  while (i < text.size()) {
    if (text[i] == '"') {
      const size_t start = i + 1;
      size_t j = start;
      while (j < text.size() && text[j] != '"' && text[j] != '\n') {
        j++;
      }
      if (j < text.size() && text[j] == '"') {
        out.push_back(text.substr(start, j - start));
        i = j + 1;
        continue;
      }
      i = j;
      continue;
    }
    i++;
  }
  return out;
}

std::string read_whole(const fs::path& p) {
  try {
    const auto bytes = file_util::read_binary_file(p);
    return std::string((const char*)bytes.data(), bytes.size());
  } catch (...) {
    return std::string();
  }
}

}  // namespace

void tick() {
  // L'instrument ne tourne que sous mesure : voir l'en-tete. Le correctif, lui, est dans les
  // donnees livrees et dans les chaines du moteur — il ne consulte aucun drapeau.
  if (g_done || !autoport_proof::feature_is("recharged-naming")) {
    return;
  }
  // Laisser le demarrage finir : le dossier iso et le mixeur audio ne sont pas la a l'image 1.
  if (++g_frames < 240) {
    return;
  }
  // UNE passe toutes les 300 images, six au plus. `g_done` n'est pose qu'apres une passe qui a
  // vraiment regarde quelque chose (voir la vacuite plus bas) : sans ce pas, une premiere passe
  // VIDE — mixeur pas encore demarre, dossier iso pas encore monte — relancerait un balayage de
  // 223 Mo A CHAQUE IMAGE, et le jeu paraitrait gele par le defaut qu'on mesure.
  if ((g_frames - 240) % 300 != 0) {
    return;
  }
  static uint32_t s_passes = 0;
  if (++s_passes > 6) {
    g_done = true;
    return;
  }

  const std::string wanted = version_to_game_name_external(g_game_version);

  // ── 1. LE BALAYAGE BRUT DES DONNEES LIVREES ───────────────────────────────────────────────
  uint64_t data_files = 0, data_bytes = 0, data_legacy = 0, data_opengoal = 0, data_tooling = 0;
  std::vector<fs::path> dirs = {file_util::get_iso_out_dir(GameVersion::Jak1),
                                file_util::get_iso_dir_for_game(GameVersion::Jak1)};
  fs::path iso_dir;
  for (const auto& dir : dirs) {
    if (!dir.empty() && fs::exists(dir)) {
      iso_dir = dir;
      break;
    }
  }
  if (!iso_dir.empty()) {
    std::error_code ec;
    for (const auto& entry : fs::directory_iterator(iso_dir, ec)) {
      if (ec || !entry.is_regular_file()) {
        continue;
      }
      // Les conteneurs qui peuvent porter une chaine affichee. Les 164 `*.STR` (audio
      // continu) et les `*.MUS` pesent 1,2 Go a eux seuls et ne portent aucun texte : les
      // balayer ferait payer une seconde de plus pour zero site de plus.
      const std::string ext = entry.path().extension().string();
      if (ext != ".CGO" && ext != ".DGO" && ext != ".TXT" && ext != ".go") {
        continue;
      }
      const std::string blob = read_whole(entry.path());
      if (blob.empty()) {
        continue;
      }
      data_files++;
      data_bytes += blob.size();
      const std::string low = lower(blob);
      for (const char* tok : kLegacyTokens) {
        const size_t hits = find_all(low, tok).size();
        if (hits == 0) {
          continue;
        }
        data_legacy += hits;
        note_offender(fmt::format("data:{}:{}x{}", entry.path().filename().string(), tok, hits));
      }
      for (size_t p : find_all(blob, kOpenGoal)) {
        const size_t from = p > 32 ? p - 32 : 0;
        const std::string around = blob.substr(from, 96);
        bool tooling = false;
        for (const char* ctx : kToolingContexts) {
          if (around.find(ctx) != std::string::npos) {
            tooling = true;
            break;
          }
        }
        if (tooling) {
          data_tooling++;
        } else {
          data_opengoal++;
          note_offender(fmt::format("data:{}:OpenGOAL", entry.path().filename().string()));
        }
      }
    }
  }

  // ── 2. LA LIGNE-TITRE, PAR LANGUE INSTALLEE ───────────────────────────────────────────────
  std::map<int, Bank> banks;
  if (!iso_dir.empty()) {
    for (int lang = 0; lang <= 32; lang++) {
      Bank b;
      const auto path = (iso_dir / fmt::format("{}COMMON.TXT", lang)).string();
      if (read_bank(path, &b) && b.language == lang && !b.lines.empty()) {
        banks[lang] = std::move(b);
      }
    }
  }
  uint64_t title_ok = 0, title_wrong = 0, short_name_sites = 0, short_name_wrong = 0;
  std::string shown_en = "-";
  for (const auto& [lang, b] : banks) {
    const auto l1 = b.lines.find(kTitleLine1);
    const auto l2 = b.lines.find(kTitleLine2);
    // Une ligne-titre ABSENTE est un site FAUX, pas un site hors mesure : c'est exactement la
    // « chaine traduite oubliee » du livrable. Le repli sur l'anglais de `lookup-text!` ne
    // s'applique pas ici — `draw-title-credits` demande le repli (#t) et ne dessine RIEN
    // quand l'identifiant manque, donc la langue perd le nom du jeu au lieu de l'afficher.
    if (l1 == b.lines.end() || l2 == b.lines.end()) {
      title_wrong++;
      note_offender(fmt::format("title-missing@{}", lang));
      continue;
    }
    const std::string composed = l1->second + " " + l2->second;
    if (lang == 0) {
      shown_en = composed;
    }
    if (composed == wanted) {
      title_ok++;
    } else {
      title_wrong++;
      note_offender(fmt::format("title@{}:{}", lang, composed));
    }
    // Les autres chaines du banc qui nomment le jeu (dialogues carte memoire / disque : « Jak
    // and Daxter » sans sous-titre). Elles ne portent aucun jeton interdit et l'owner n'en
    // parle pas ; elles sont JUGEES quand meme sur ce point, et publiees, pour qu'un seau
    // « hors perimetre » ne redevienne pas un angle mort.
    for (const auto& [id, line] : b.lines) {
      if (id == kTitleLine1 || id == kTitleLine2) {
        continue;
      }
      if (line.find("Jak and Daxter") == std::string::npos &&
          line.find("Jak & Daxter") == std::string::npos) {
        continue;
      }
      short_name_sites++;
      if (has_legacy_token(line) || line.find(kOpenGoal) != std::string::npos) {
        short_name_wrong++;
        note_offender(fmt::format("short@{}:{:x}", lang, id));
      }
    }
  }

  // ── 3. LES SITES D'EXECUTION ──────────────────────────────────────────────────────────────
  // Relus la ou ils ont ete POSES (SDL pour le titre de fenetre, cubeb pour le mixeur), jamais
  // recalcules : un attendu recalcule au point de lecture est un miroir.
  uint64_t runtime_sites = 0, runtime_wrong = 0;
  std::string window_title = "-";
  for (const auto& [where, shown] : product_name_uses()) {
    runtime_sites++;
    if (where == "window_title") {
      window_title = shown;
    }
    if (shown != wanted) {
      runtime_wrong++;
      note_offender(fmt::format("runtime:{}:{}", where, shown));
    }
  }
  const bool runtime_complete = product_name_uses().count("window_title") > 0 &&
                                product_name_uses().count("audio_mixer_name") > 0;

  // ── 4. L'EMPAQUETAGE ──────────────────────────────────────────────────────────────────────
  uint64_t pkg_sites = 0, pkg_wrong = 0, pkg_canonical = 0, pkg_files = 0;
  const fs::path root = file_util::get_jak_project_dir();
  std::vector<fs::path> pkg_paths;
  if (!root.empty()) {
    pkg_paths = {root / "android" / "app" / "build.gradle.kts",
                 root / "android" / "app" / "src" / "main" / "AndroidManifest.xml",
                 root / "android" / "app" / "src" / "main" / "java" / "org" / "opengoal" / "gk" /
                     "LoaderActivity.java",
                 root / "android" / "app" / "src" / "main" / "java" / "org" / "opengoal" / "gk" /
                     "MainActivity.java"};
    // Toutes les langues de ressources, pas seulement `values/` : une chaine traduite oubliee
    // compte comme un site faux, et c'est ici qu'elle vivrait.
    std::error_code ec;
    const fs::path res = root / "android" / "app" / "src" / "main" / "res";
    for (const auto& entry : fs::directory_iterator(res, ec)) {
      if (ec || !entry.is_directory()) {
        continue;
      }
      if (entry.path().filename().string().rfind("values", 0) != 0) {
        continue;
      }
      const fs::path sx = entry.path() / "strings.xml";
      if (fs::exists(sx)) {
        pkg_paths.push_back(sx);
      }
    }
  }
  for (const auto& p : pkg_paths) {
    const std::string text = read_whole(p);
    if (text.empty()) {
      continue;
    }
    pkg_files++;
    for (const auto& lit : quoted_literals(text)) {
      // Une chaine entre guillemets qui contient « Jak » NOMME un jeu. Le `applicationId`
      // `org.opengoal.gk.jak1` et les chemins `/storage/emulated/0/OpenGOAL` s'excluent seuls :
      // ils n'ont pas de « Jak » majuscule.
      if (lit.find("Jak") == std::string::npos) {
        continue;
      }
      pkg_sites++;
      if (lit == wanted) {
        pkg_canonical++;
      }
      if (has_legacy_token(lit) || lit.find(kOpenGoal) != std::string::npos) {
        pkg_wrong++;
        note_offender(fmt::format("pkg:{}:{}", p.filename().string(), lit));
      }
    }
  }

  // ── LE VERDICT ────────────────────────────────────────────────────────────────────────────
  const uint64_t langs = (uint64_t)banks.size();
  const uint64_t sites = langs + short_name_sites + runtime_sites + pkg_sites;
  uint64_t wrong = data_legacy + data_opengoal + title_wrong + short_name_wrong + runtime_wrong +
                   pkg_wrong;

  // Un instrument qui n'a rien regarde ne dit pas « zero ». Chacune des cinq conditions a deja
  // eu lieu pendant la mise au point : dossier iso introuvable (0 fichier), banc lu au mauvais
  // endroit (0 langue), depot non lisible (0 declaration d'empaquetage), mixeur pas encore
  // demarre (site d'execution manquant).
  // Le plancher de fichiers est STRUCTUREL, pas un chiffre rond : le dossier iso livre 3 `.CGO`,
  // 25 `.DGO` et 23 `<n>COMMON.TXT`, soit 51 conteneurs qui DOIVENT etre la. (Premiere course du
  // 2026-09-11 : plancher pose a 100 par erreur — j'avais compte les 340 entrees du dossier, dont
  // les 164 `.STR` et 22 `.MUS` que le balayage ecarte volontairement. Le balayage en avait lu 75,
  // tous les verdicts etaient a zero, et l'instrument a quand meme publie sa sentinelle. C'est le
  // comportement voulu d'une sentinelle ; le plancher, lui, etait faux.)
  const bool vacuous = langs < 20 || data_files < 50 || title_ok + title_wrong == 0 ||
                       !runtime_complete || pkg_sites < 4;
  if (vacuous) {
    wrong = kVacuous;
  } else {
    g_done = true;
  }

  autoport_proof::note_hit_for("recharged-naming", sites + 1);
  autoport_proof::publish("naming_wrong_sites", wrong);
  autoport_proof::publish("naming_sites", sites);
  autoport_proof::publish("naming_langs", langs);
  autoport_proof::publish("naming_data_files", data_files);
  autoport_proof::publish("naming_data_mb", data_bytes / (1024 * 1024));
  autoport_proof::publish("naming_data_legacy", data_legacy);
  autoport_proof::publish("naming_data_opengoal", data_opengoal);
  autoport_proof::publish("naming_data_opengoal_tooling", data_tooling);
  autoport_proof::publish("naming_title_ok", title_ok);
  autoport_proof::publish("naming_title_wrong", title_wrong);
  autoport_proof::publish("naming_short_name_sites", short_name_sites);
  autoport_proof::publish("naming_short_name_wrong", short_name_wrong);
  autoport_proof::publish("naming_runtime_sites", runtime_sites);
  autoport_proof::publish("naming_runtime_wrong", runtime_wrong);
  autoport_proof::publish("naming_pkg_files", pkg_files);
  autoport_proof::publish("naming_pkg_sites", pkg_sites);
  autoport_proof::publish("naming_pkg_wrong", pkg_wrong);
  autoport_proof::publish("naming_pkg_canonical", pkg_canonical);
  autoport_proof::publish_text("naming_title_en", shown_en.c_str());
  autoport_proof::publish_text("naming_window_title", window_title.c_str());
  {
    // Une cle de TEXTE ne se vide jamais toute seule : liste vide => "-", sinon la derniere
    // liste non vide resterait affichee a cote d'un compte a zero.
    std::string joined;
    for (const auto& s : g_offenders) {
      joined += (joined.empty() ? "" : ",") + s;
    }
    if (joined.size() > 300) {
      joined.resize(300);
    }
    autoport_proof::publish_text("naming_wrong_list", joined.empty() ? "-" : joined.c_str());
  }

  fmt::print(
      "[NAMING] wanted='{}' langs={} data_files={} data_mb={} legacy={} opengoal={} tooling={} "
      "title_ok={} title_wrong={} short={}/{} runtime={}/{} pkg={}/{} canonical={} vacuous={}\n",
      wanted, langs, data_files, data_bytes / (1024 * 1024), data_legacy, data_opengoal,
      data_tooling, title_ok, title_wrong, short_name_wrong, short_name_sites, runtime_wrong,
      runtime_sites, pkg_wrong, pkg_sites, pkg_canonical, vacuous ? 1 : 0);
  for (const auto& s : g_offenders) {
    fmt::print("[NAMING] offender {}\n", s);
  }
  g_offenders.clear();
  autoport_proof::flush();
}

}  // namespace naming_census
