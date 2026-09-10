#include "water_census.h"

#include <cstdlib>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <vector>

#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/versions/versions.h"

#include "game/system/autoport_proof.h"

#include "fmt/format.h"

namespace water_census {
namespace {

// Sentinelle : « la porte n'a PAS pu etre mesuree ». Jamais 0, jamais un nombre plausible.
constexpr u64 kNoCensus = 999999;

std::once_flag g_once;

struct Line {
  std::string verdict;  // CHUTE | JET | NAPPE | EXCLU
  std::string material;
};

// Lecture ligne a ligne, commentaires `#` et lignes vides ignores. Meme convention que
// `recharged_assets/foliage_wind_protos.txt`.
std::vector<std::vector<std::string>> read_fields(const std::string& path, bool* loaded) {
  std::vector<std::vector<std::string>> rows;
  *loaded = false;
  if (!file_util::file_exists(path)) {
    return rows;
  }
  const std::string text = file_util::read_text_file(path);
  size_t pos = 0;
  while (pos <= text.size()) {
    const size_t end = text.find('\n', pos);
    std::string line = text.substr(pos, end == std::string::npos ? std::string::npos : end - pos);
    pos = (end == std::string::npos) ? text.size() + 1 : end + 1;
    // Une ligne de verdict peut porter un commentaire de queue introduit par ` ; `.
    const size_t semi = line.find(" ; ");
    if (semi != std::string::npos) {
      line = line.substr(0, semi);
    }
    std::vector<std::string> f;
    size_t i = 0;
    while (i < line.size()) {
      while (i < line.size() && (line[i] == ' ' || line[i] == '\t' || line[i] == '\r')) {
        i++;
      }
      const size_t b = i;
      while (i < line.size() && line[i] != ' ' && line[i] != '\t' && line[i] != '\r') {
        i++;
      }
      if (i > b) {
        f.push_back(line.substr(b, i - b));
      }
    }
    if (f.empty() || f[0][0] == '#') {
      continue;
    }
    rows.push_back(std::move(f));
  }
  *loaded = true;
  return rows;
}

// `cle=valeur` dans un champ ; rend "" si la cle n'y est pas.
std::string field_value(const std::vector<std::string>& f, const std::string& key) {
  for (const auto& s : f) {
    if (s.size() > key.size() + 1 && s.compare(0, key.size(), key) == 0 && s[key.size()] == '=') {
      return s.substr(key.size() + 1);
    }
  }
  return "";
}

// Le chemin d'un asset « recharge » : le depot EXTERNE bat le pack livre, sinon le pack, sinon
// l'arbre du projet. Exactement la precedence de `fw_veg_protos()` (TFrag3Data.cpp) et de
// `physics_chains.txt` (kmachine.cpp).
std::string recharged_path(const char* name) {
  auto path = file_util::get_recharged_assets_dir() / name;
  auto ext = file_util::get_external_recharged_assets_dir();
  if (ext) {
    auto ext_path = *ext / name;
    if (file_util::file_exists(ext_path.string())) {
      return ext_path.string();
    }
  }
  return path.string();
}

void census() {
  // `armed_for`, jamais `armed()` : `armed()` est global et desarmerait du meme coup toute
  // feature livree que le harnais n'a pas nommee.
  if (!autoport_proof::armed_for("water-census")) {
    return;
  }

  // ---------------------------------------------------------------- l'enumeration (donnees) --
  const std::string inv_path =
      (file_util::get_water_census_dir(GameVersion::Jak1) / "water_inventory.txt").string();
  bool inv_loaded = false;
  const auto inv = read_fields(inv_path, &inv_loaded);

  struct LevelRow {
    std::string name;
    u64 fr3_bytes = 0;
  };
  std::vector<LevelRow> levels;
  std::vector<std::string> proto_names;
  u64 ent_anim = 0, ent_vol = 0, ent_total = 0, ent_looks_posed = 0, ent_looks_dup = 0;
  bool ent_loaded = false;
  u64 tfrag_water_trees = 0, anim_slot_draws = 0;

  for (const auto& f : inv) {
    if (f[0] == "level" && f.size() >= 2) {
      LevelRow r;
      r.name = f[1];
      r.fr3_bytes = std::strtoull(field_value(f, "fr3_bytes").c_str(), nullptr, 10);
      tfrag_water_trees += std::strtoull(field_value(f, "tfrag_water_trees").c_str(), nullptr, 10);
      anim_slot_draws += std::strtoull(field_value(f, "anim_slot_draws").c_str(), nullptr, 10);
      levels.push_back(std::move(r));
    } else if (f[0] == "proto" && f.size() >= 2) {
      proto_names.push_back(f[1]);
    } else if (f[0] == "entities") {
      ent_loaded = field_value(f, "loaded") == "1";
      ent_anim = std::strtoull(field_value(f, "water_anim").c_str(), nullptr, 10);
      ent_vol = std::strtoull(field_value(f, "water_vol").c_str(), nullptr, 10);
      ent_total = std::strtoull(field_value(f, "total").c_str(), nullptr, 10);
      ent_looks_posed = std::strtoull(field_value(f, "looks_posed").c_str(), nullptr, 10);
      ent_looks_dup = std::strtoull(field_value(f, "looks_dup").c_str(), nullptr, 10);
    }
  }

  // ------------------------------------------------------------------- les verdicts (nous) --
  bool falls_loaded = false, over_loaded = false, mat_loaded = false, ocean_loaded = false;
  const auto falls = read_fields(recharged_path("water_falls.txt"), &falls_loaded);
  const auto over = read_fields(recharged_path("water_overrides.txt"), &over_loaded);
  const auto mats = read_fields(recharged_path("water_materials.txt"), &mat_loaded);
  const auto ocean = read_fields(
      (file_util::get_water_census_dir(GameVersion::Jak1) / "water_ocean_maps.txt").string(),
      &ocean_loaded);

  std::map<std::string, Line> verdict;
  u64 v_nappe = 0, v_chute = 0, v_jet = 0, v_exclu = 0;
  for (const auto& f : falls) {
    if (f.size() < 2) {
      continue;
    }
    const std::string& v = f[0];
    if (v != "CHUTE" && v != "JET" && v != "NAPPE" && v != "EXCLU") {
      continue;
    }
    Line l;
    l.verdict = v;
    l.material = field_value(f, "matiere");
    verdict[f[1]] = l;
    if (v == "NAPPE") {
      v_nappe++;
    } else if (v == "CHUTE") {
      v_chute++;
    } else if (v == "JET") {
      v_jet++;
    } else {
      v_exclu++;
    }
  }

  // les 48 looks -> une matiere
  std::map<int, std::string> look_material;
  for (const auto& f : over) {
    if (f.size() >= 3 && f[0] == "look") {
      look_material[std::atoi(f[1].c_str())] = f[2];
    }
  }

  std::set<std::string> declared_materials;
  for (const auto& f : mats) {
    if (f.size() >= 2 && f[0] == "matiere") {
      declared_materials.insert(f[1]);
    }
  }

  u64 ocean_levels = 0, ocean_maps = 0, ocean_spheres = 0;
  for (const auto& f : ocean) {
    if (f[0] == "niveau") {
      ocean_levels++;
    } else if (f[0] == "carte") {
      ocean_maps++;
    } else if (f[0] == "sphere") {
      ocean_spheres++;
    }
  }

  // ------------------------------------------------------------------------ la jointure -----
  u64 assigned = 0, unassigned = 0;
  std::set<std::string> seen;
  for (const auto& n : proto_names) {
    seen.insert(n);
    if (verdict.count(n)) {
      assigned++;
      autoport_proof::note_hit();
    } else {
      unassigned++;
    }
  }
  u64 orphan = 0;
  for (const auto& kv : verdict) {
    if (!seen.count(kv.first)) {
      orphan++;
    }
  }

  // Les 48 looks : `water-anim.gc:7-56` en declare 48, 0..47 sans trou. Un look sans matiere est
  // compte, jamais suppose.
  constexpr int kLookCount = 48;
  u64 looks_mapped = 0, looks_unmapped = 0;
  for (int i = 0; i < kLookCount; i++) {
    auto it = look_material.find(i);
    if (it == look_material.end() || it->second.empty()) {
      looks_unmapped++;
    } else {
      looks_mapped++;
      autoport_proof::note_hit();
    }
  }

  // Une matiere citee par un verdict ou par un look mais jamais DECLAREE est un verdict qui
  // pointe dans le vide.
  u64 material_undeclared = 0;
  std::set<std::string> cited;
  for (const auto& kv : verdict) {
    if (!kv.second.material.empty()) {
      cited.insert(kv.second.material);
    }
  }
  for (const auto& kv : look_material) {
    cited.insert(kv.second);
  }
  for (const auto& m : cited) {
    if (!declared_materials.count(m)) {
      material_undeclared++;
    }
  }

  // ----------------------------------------------------- l'inventaire est-il encore vrai ? --
  // Le `.fr3` est resolu par le RESOLVEUR (pack custom > pack de base), jamais par un chemin
  // construit a la main : sur l'appareil le fichier ne vit pas dans l'arbre du projet.
  u64 stale = 0, unresolved = 0;
  for (const auto& l : levels) {
    const auto route = file_util::resolve_fr3_asset(GameVersion::Jak1, l.name + ".fr3");
    if (route.path.empty() || !file_util::file_exists(route.path.string())) {
      unresolved++;
      continue;
    }
    std::error_code ec;
    const auto sz = fs::file_size(route.path, ec);
    if (ec || (u64)sz != l.fr3_bytes) {
      stale++;
    }
  }

  // ------------------------------------------------------------------------ publication -----
  const bool measurable = inv_loaded && falls_loaded && !proto_names.empty();
  if (!measurable) {
    // Une porte qui n'a pas pu etre mesuree est ROUGE. Voir l'en-tete, garde-fou 2.
    lg::warn(
        "[water-census] RECENSEMENT IMPOSSIBLE : inventaire={} ({}), verdicts={}, protos={}. "
        "`water_proto_unassigned` prend la sentinelle {} — ce n'est pas un zero.",
        inv_loaded ? 1 : 0, inv_path, falls_loaded ? 1 : 0, proto_names.size(), kNoCensus);
    autoport_proof::publish("water_proto_unassigned", kNoCensus);
  } else {
    autoport_proof::publish("water_proto_unassigned", unassigned);
  }
  autoport_proof::publish("water_proto_total", (u64)proto_names.size());
  autoport_proof::publish("water_proto_assigned", assigned);
  autoport_proof::publish("water_proto_orphan", orphan);
  autoport_proof::publish("water_proto_nappe", v_nappe);
  autoport_proof::publish("water_proto_chute", v_chute);
  autoport_proof::publish("water_proto_jet", v_jet);
  autoport_proof::publish("water_proto_exclu", v_exclu);

  // MESURE, pas constante : le nombre de lignes `look` REELLEMENT lues. `looks_mapped +
  // looks_unmapped` vaudrait 48 meme fichier absent — une fausse constante. Ici, fichier absent
  // rend 0, et `water_look_unmapped` rend 48 : les deux disent la meme panne.
  autoport_proof::publish("water_looks_total", (u64)look_material.size());
  autoport_proof::publish("water_looks_mapped", looks_mapped);
  autoport_proof::publish("water_look_unmapped", looks_unmapped);
  autoport_proof::publish("water_materials_declared", (u64)declared_materials.size());
  autoport_proof::publish("water_material_undeclared", material_undeclared);

  autoport_proof::publish("water_entities", ent_total);
  autoport_proof::publish("water_entities_anim", ent_anim);
  autoport_proof::publish("water_entities_vol", ent_vol);
  autoport_proof::publish("water_entity_census_loaded", ent_loaded ? 1 : 0);
  autoport_proof::publish("water_looks_posed", ent_looks_posed);
  autoport_proof::publish("water_looks_posed_twice", ent_looks_dup);

  autoport_proof::publish("water_levels_indexed", (u64)levels.size());
  autoport_proof::publish("water_inventory_loaded", inv_loaded ? 1 : 0);
  autoport_proof::publish("water_inventory_stale_levels", stale);
  autoport_proof::publish("water_inventory_unresolved_levels", unresolved);
  autoport_proof::publish("water_falls_loaded", falls_loaded ? 1 : 0);
  autoport_proof::publish("water_overrides_loaded", over_loaded ? 1 : 0);
  autoport_proof::publish("water_materials_loaded", mat_loaded ? 1 : 0);

  autoport_proof::publish("water_ocean_levels", ocean_levels);
  autoport_proof::publish("water_ocean_maps", ocean_maps);
  autoport_proof::publish("water_ocean_spheres", ocean_spheres);

  // `tfrag_water_trees` est nul sur les 26 niveaux : le seau `TFragmentTreeKind::WATER` du format
  // fr3 est VIDE en jak 1. C'est la raison pour laquelle le recensement repose sur un lexique de
  // noms et sur 196 verdicts explicites, et non sur un drapeau de donnee. Publie pour que ce
  // fait se lise dans la preuve au lieu de rester dans un commentaire.
  autoport_proof::publish("water_tfrag_water_trees", tfrag_water_trees);
  autoport_proof::publish("water_anim_slot_draws", anim_slot_draws);

  lg::info(
      "[water-census] {} noms, {} classes, {} sans verdict, {} orphelins ; {} looks sur 48 avec "
      "matiere ; {} entites ; {} niveaux indexes ({} perimes)",
      proto_names.size(), assigned, unassigned, orphan, looks_mapped, ent_total, levels.size(),
      stale);
}

}  // namespace

void run_once() {
  std::call_once(g_once, census);
}

}  // namespace water_census
