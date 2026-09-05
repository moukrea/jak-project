#include "game/system/settings_case_l10n.h"

#include <algorithm>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "common/util/FileUtil.h"
#include "common/versions/versions.h"

#include "game/system/autoport_proof.h"

#include "fmt/core.h"

namespace settings_case_l10n {
namespace {

// ── LE BANC LIVRE ───────────────────────────────────────────────────────────────────────────
// `<n>COMMON.TXT` est un objet GOAL lie en V2, ecrit par `compile_text`
// (goalc/data_compiler/game_text_common.cpp:53-79) via `DataObjectGenerator::generate_v2`
// (goalc/data_compiler/DataObjectGenerator.cpp:121-148). On le relit ici SANS le lieur : les
// mots de pointeur portent deja leur cible en octets, `generate_link_table` les y ecrit
// (`m_words.at(entry.source_word) = entry.target_byte`, DataObjectGenerator.cpp:203).
//
//   [0..12)  LinkHeaderV2 { u32 type_tag=0xffffffff ; u32 length ; u32 version=2 }
//            `length` = 12 + taille de la table de liens = L'OFFSET DU CORPS. (common/link_types.h:43)
//   corps    +0 type-tag, +4 nombre d'entrees, +8 language-id, +12 renvoi vers `group-name`,
//            puis N couples { u32 id ; u32 renvoi vers la chaine }, tries par id.
//   chaine   a l'offset o du corps : u32 `allocated-length`, puis les octets, termines par 0.
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

// ── LES MOTS D'UNE CHAINE DE BANC ───────────────────────────────────────────────────────────
// Les octets d'un banc ne sont PAS de l'UTF-8 : c'est l'encodage de la police jak1, ou un `e`
// accentue s'ecrit `~Y~-14H~-1V<glyphe>~Z` (groupe de composition). Le decoupage reproduit celui
// du convertisseur de casse qui a deja traite tout le reste du menu — `Caser.convert`,
// recharged_assets/font/gen_mixed_case.py:186-205 : sur `~`, on saute un signe optionnel, les
// chiffres, puis UNE lettre de commande ; sur `<`, on saute la balise `<PAD_X>` ; le reste se
// decoupe en mots de lettres et de chiffres.
// Sans ce decoupage, les lettres de commande (`H`, `V`, `Y`, `Z`) compteraient comme des
// majuscules et « Reglages recharges » en francais sortirait « tout en majuscules ».
std::vector<std::string> words_of(const std::string& s) {
  std::vector<std::string> out;
  size_t i = 0;
  const size_t n = s.size();
  while (i < n) {
    const char c = s[i];
    if (c == '<') {
      const size_t j = s.find('>', i);
      if (j != std::string::npos && j - i <= 20) {
        i = j + 1;
        continue;
      }
    }
    if (c == '~') {
      size_t j = i + 1;
      if (j < n && (s[j] == '+' || s[j] == '-')) {
        j++;
      }
      while (j < n && s[j] >= '0' && s[j] <= '9') {
        j++;
      }
      if (j < n) {
        j++;  // la lettre de commande
      }
      i = j;
      continue;
    }
    const auto is_word_byte = [](char x) {
      return (x >= 'A' && x <= 'Z') || (x >= 'a' && x <= 'z') || (x >= '0' && x <= '9') ||
             x == '\'';
    };
    if (is_word_byte(c)) {
      size_t j = i;
      while (j < n && is_word_byte(s[j])) {
        j++;
      }
      out.push_back(s.substr(i, j - i));
      i = j;
      continue;
    }
    i++;
  }
  return out;
}

// Les sigles qui restent legitimement en majuscules. RECOPIE de la liste `acronyms` de
// `recharged_assets/font/case_rules.json` — la meme donnee qui a decide la casse de tout le
// reste du menu. Une derive de cette liste ne peut que rendre l'instrument PLUS severe (un
// sigle inconnu compte comme un defaut), jamais plus laxiste : le sens de l'erreur est choisi.
const std::set<std::string>& acronyms() {
  static const std::set<std::string> s = {
      "2D",  "3D",   "AI",   "AO",   "CD",   "CPU",  "DVD",  "FPS",  "GB",   "GPU",  "GTAO",
      "HBAO", "HD",  "HDR",  "HUD",  "IBL",  "ID",   "II",   "III",  "IO",   "IV",   "KB",
      "L1",  "L2",   "L3",   "LED",  "LOD",  "LTD",  "MB",   "MSAA", "NTSC", "OK",   "PAL",
      "PBR", "PS",   "PS2",  "PS3",  "PS4",  "PS5",  "QA",   "R1",   "R2",   "R3",   "RAM",
      "SCEA", "SCEE", "SCEI", "SD",  "SFX",  "SSAO", "SSD",  "TRC",  "TV",   "UI",   "UK",
      "USA", "USB",  "VR",   "XP",   "SH"};
  return s;
}

// Les NOMS PROPRES, meme source : la liste `proper` de `recharged_assets/font/case_rules.json`.
// Ils ne servent QU'A l'exemption d'identite : « Jak II » est « Jak II » dans les 23 langues, le
// compter « non traduit » fabriquerait un defaut qu'aucune traduction ne peut lever. Ils restent
// en revanche soumis au test de casse : « JAK » crie autant que « MASTER ».
const std::set<std::string>& proper_nouns() {
  static const std::set<std::string> s = {
      "ANDROID", "BOSANSKI", "CATALA",  "CESTINA",  "DAXTER",     "DEUTSCH",  "DISCORD",
      "ENGLISH", "ESPANOL",  "FLUT",    "FRANCAIS", "GALEGO",     "GOL",      "GOOGLE",
      "GORDY",   "HRVATSKI", "ISLANDSKA", "ITALIANO", "JAK",      "KEIRA",    "KLAWW",
      "LIETUVIU", "LINUX",   "LURKER",  "LURKERS",  "MAC",        "MAGYAR",   "MAIA",
      "NEDERLANDS", "NORSK", "OPENGOAL", "POLSKI",  "PORTUGUES",  "PRECURSOR", "PRECURSORS",
      "RECHARGED", "SAGE",   "SAMOS",   "SANDOVER", "SLOVENCINA", "SONY",     "STEAM",
      "SUOMI",   "SVENSKA",  "WILLARD", "WINDOWS",  "YAKOW",      "YAKOWS",   "ZOOMER",
      "ZOOMERS"};
  return s;
}

std::string upper(const std::string& w) {
  std::string u = w;
  for (char& c : u) {
    if (c >= 'a' && c <= 'z') {
      c = (char)(c - 'a' + 'A');
    }
  }
  return u;
}

bool has_digit(const std::string& w) {
  for (char c : w) {
    if (c >= '0' && c <= '9') {
      return true;
    }
  }
  return false;
}

int letters(const std::string& w) {
  int n = 0;
  for (char c : w) {
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
      n++;
    }
  }
  return n;
}

// Un mot « ordinaire » : ni sigle, ni jeton numerique, ni initiale isolee. C'est le seul type de
// mot dont la casse et la traduction veulent dire quelque chose.
bool is_plain_word(const std::string& w) {
  if (has_digit(w) || letters(w) < 2) {
    return false;
  }
  return acronyms().count(upper(w)) == 0;
}

// TOUT-MAJUSCULES : au moins un mot ordinaire ecrit entierement en capitales.
bool is_shouting(const std::string& s) {
  for (const auto& w : words_of(s)) {
    if (!is_plain_word(w)) {
      continue;
    }
    bool lower_seen = false;
    for (char c : w) {
      if (c >= 'a' && c <= 'z') {
        lower_seen = true;
        break;
      }
    }
    if (!lower_seen) {
      return true;
    }
  }
  return false;
}

// Un libelle qui ne contient QUE des sigles, des chiffres et des noms propres (`SSAO`, `IBL`,
// `HD`, `Jak II`, `Jak 3`) est le meme mot dans toutes les langues : le compter « identique a
// l'anglais » fabriquerait un defaut qu'aucune traduction ne peut lever. Un seul mot ordinaire
// suffit a rendre le libelle traduisible — « Jak 3 Masked » l'est par `Masked`.
bool is_language_neutral(const std::string& s) {
  for (const auto& w : words_of(s)) {
    if (is_plain_word(w) && proper_nouns().count(upper(w)) == 0) {
      return false;
    }
  }
  return true;
}

// ── L'ETAT DU RECENSEMENT ───────────────────────────────────────────────────────────────────
struct Row {
  int id = 0;
  std::string shown;
};

bool g_open = false;
bool g_done = false;
int g_current_language = -1;
std::vector<Row> g_rows;
uint64_t g_uncovered = 0;
std::vector<std::string> g_uncovered_names;

constexpr uint64_t kVacuous = 9999;

}  // namespace

void begin_census(int current_language) {
  if (g_done) {
    return;
  }
  g_open = true;
  g_current_language = current_language;
  g_rows.clear();
  g_uncovered = 0;
  g_uncovered_names.clear();
}

void note_label(int text_id, const char* shown) {
  if (!g_open || g_done) {
    return;
  }
  Row r;
  r.id = text_id;
  r.shown = shown ? shown : "";
  g_rows.push_back(r);
}

void note_uncovered_row(const char* who) {
  if (!g_open || g_done) {
    return;
  }
  g_uncovered++;
  if (g_uncovered_names.size() < 24) {
    g_uncovered_names.push_back(who ? who : "?");
  }
}

void end_census() {
  if (!g_open || g_done) {
    return;
  }
  g_open = false;
  g_done = true;

  // Les bancs REELLEMENT LIVRES, lus la ou le jeu les charge.
  //
  // `get_iso_out_dir` — PAS `get_iso_dir_for_game`. Le second nomme le dossier des donnees
  // EXTRAITES de l'ISO de l'owner (`iso_data/jak1`) ; le premier nomme `out/jak1/iso`, ou
  // `compile_text` ecrit les `<n>COMMON.TXT` (goalc/data_compiler/game_text_common.cpp:74-77) et
  // ou le chargeur GOAL va les chercher. Course du 2026-09-05 13:53 avec le mauvais : `langs=0`,
  // et le module a publie sa sentinelle 9999 au lieu d'un zero qui n'aurait rien mesure. C'est
  // exactement ce que la sentinelle est la pour faire.
  // Le second chemin reste en repli : sur l'appareil, `get_iso_out_dir` passe par
  // `g_external_game_root`, et si rien n'y est monte on tente encore le dossier de donnees.
  std::map<int, Bank> banks;
  std::vector<fs::path> dirs = {file_util::get_iso_out_dir(GameVersion::Jak1),
                                file_util::get_iso_dir_for_game(GameVersion::Jak1)};
  for (const auto& dir : dirs) {
    if (dir.empty()) {
      continue;
    }
    for (int lang = 0; lang <= 32; lang++) {
      if (banks.count(lang)) {
        continue;
      }
      Bank b;
      const auto path = (dir / fmt::format("{}COMMON.TXT", lang)).string();
      if (read_bank(path, &b) && b.language == lang && !b.lines.empty()) {
        banks[lang] = std::move(b);
      }
    }
    if (!banks.empty()) {
      break;
    }
  }

  // « Langue traduite » : mesuree sur les entrees STOCK, jamais decretee. Voir l'en-tete.
  std::set<int> translated;
  const auto en = banks.find(0);
  if (en != banks.end()) {
    for (const auto& [lang, b] : banks) {
      if (lang == 0) {
        continue;
      }
      int common = 0, diff = 0;
      for (const auto& [id, line] : b.lines) {
        if (id >= 0x1700) {
          continue;
        }
        const auto it = en->second.lines.find(id);
        if (it == en->second.lines.end() || it->second.empty() || line.empty()) {
          continue;
        }
        common++;
        if (line != it->second) {
          diff++;
        }
      }
      if (common >= 50 && diff * 2 > common) {
        translated.insert(lang);
      }
    }
  }

  // LES CHAINES STOCK NE SONT PAS JUGEES ICI, ET C'EST DIT. `On` (#x111), `Off` (#x112) et
  // `Back` (#x13e) sont partagees par TOUT le menu, pas propres au menu Recharged : elles sont
  // deja redigees a la main dans onze bancs, avec des choix qui varient par langue (fr
  // « Oui/Non », de « AN/AUS », pl « Wl./Wyl. »), et elles manquent dans douze bancs pour le
  // menu ENTIER. Les compter ici ferait porter a cet item un defaut qui n'est pas le sien, et les
  // reecrire serait une regression hors perimetre. Le compte des lignes ecartees est PUBLIE :
  // une frontiere de perimetre qu'on ne voit pas est un de-scope silencieux.
  uint64_t stock_skipped = 0;
  uint64_t caps = 0, missing = 0, same_as_en = 0, mismatch = 0;
  std::vector<std::string> first_offenders;
  const auto note_offender = [&](const std::string& s) {
    if (first_offenders.size() < 12) {
      first_offenders.push_back(s);
    }
  };

  for (const auto& row : g_rows) {
    if (row.id < 0x1700) {
      stock_skipped++;
      continue;
    }
    // Le pont GOAL <-> banc, verifie et non suppose : la chaine que le menu DESSINE doit etre
    // celle du banc de la langue courante pour l'identifiant annonce.
    const auto cur = banks.find(g_current_language);
    if (cur != banks.end()) {
      const auto it = cur->second.lines.find(row.id);
      const std::string expect =
          it != cur->second.lines.end()
              ? it->second
              : (en != banks.end() && en->second.lines.count(row.id) ? en->second.lines.at(row.id)
                                                                    : std::string());
      if (!expect.empty() && expect != row.shown) {
        mismatch++;
        note_offender(fmt::format("mismatch:{:x}", row.id));
      }
    }

    std::string en_line;
    if (en != banks.end()) {
      const auto en_it = en->second.lines.find(row.id);
      if (en_it != en->second.lines.end()) {
        en_line = en_it->second;
      }
    }

    for (const auto& [lang, b] : banks) {
      const auto it = b.lines.find(row.id);
      if (it == b.lines.end()) {
        if (translated.count(lang)) {
          missing++;
          note_offender(fmt::format("missing:{:x}@{}", row.id, lang));
        }
        continue;
      }
      if (is_shouting(it->second)) {
        caps++;
        note_offender(fmt::format("caps:{:x}@{}", row.id, lang));
      }
      if (translated.count(lang) && !en_line.empty() && it->second == en_line &&
          !is_language_neutral(en_line)) {
        same_as_en++;
        note_offender(fmt::format("same:{:x}@{}", row.id, lang));
      }
    }
  }

  const uint64_t rows = (uint64_t)g_rows.size() - stock_skipped;
  const uint64_t langs = (uint64_t)banks.size();
  uint64_t defects = g_uncovered + caps + missing + same_as_en + mismatch;

  // Un instrument qui n'a rien regarde ne dit pas « zero ». Voir l'en-tete.
  const bool vacuous = rows == 0 || langs < 2 || translated.size() < 2;
  if (vacuous) {
    defects = kVacuous;
  }

  autoport_proof::note_hit(rows * langs + 1);
  autoport_proof::publish("settings_case_l10n_defects", defects);
  autoport_proof::publish("settings_case_l10n_rows", rows);
  autoport_proof::publish("settings_case_l10n_langs", langs);
  autoport_proof::publish("settings_case_l10n_langs_translated", (uint64_t)translated.size());
  autoport_proof::publish("settings_case_l10n_uncovered", g_uncovered);
  autoport_proof::publish("settings_case_l10n_stock_skipped", stock_skipped);
  autoport_proof::publish("settings_case_l10n_caps", caps);
  autoport_proof::publish("settings_case_l10n_missing", missing);
  autoport_proof::publish("settings_case_l10n_same_as_en", same_as_en);
  autoport_proof::publish("settings_case_l10n_mismatch", mismatch);
  autoport_proof::publish("settings_case_l10n_current_language", (uint64_t)g_current_language);

  // Le detail va dans le journal du moteur (pas dans proof.txt) : c'est ce qui rend un rouge
  // reparable sans relancer une course pour savoir QUELLE ligne pechait.
  for (const auto& s : first_offenders) {
    fmt::print("[SCL10N] {}\n", s);
  }
  for (const auto& s : g_uncovered_names) {
    fmt::print("[SCL10N] uncovered {}\n", s);
  }
  fmt::print("[SCL10N] rows={} langs={} translated={} uncovered={} caps={} missing={} same={} mismatch={}\n",
             rows, langs, translated.size(), g_uncovered, caps, missing, same_as_en, mismatch);
  autoport_proof::flush();
}

}  // namespace settings_case_l10n
