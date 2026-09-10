// water_bake — L'INVENTAIRE DE L'EAU DE JAK 1 (SPEC-refonte-eau.md §5.8, item `water-census`).
//
// POURQUOI CET OUTIL EXISTE.
// -------------------------
// La refonte de l'eau touche onze items. Le premier ne change pas un pixel : il NOMME. Tant que
// personne ne peut dire « voici les N surfaces d'eau du jeu, et voici ce que chacune est », un
// item aval qui repeint « l'eau » repeint en realite ce qu'il a sous les yeux au moment ou il
// regarde, et le reste du jeu part en silence.
//
// La nappe des cascades est de la GEOMETRIE DE NIVEAU : aucune classe GOAL ne la dessine
// (SPEC §2.4). Elle n'est donc atteignable que par les donnees — les `.fr3` — et c'est
// exactement ce que cet outil lit.
//
// CE QUE CET OUTIL N'EST PAS. Il n'ecrit AUCUN compagnon `.waterbake` : le SDF de rivage, la
// direction et la profondeur appartiennent a l'item `water-shore`. Ici, inventaire SEUL.
//
// LE DENOMINATEUR NE SE RETRECIT PAS EN SILENCE.
// ---------------------------------------------
// Le lexique de vegetation (`recharged_assets/foliage_wind_protos.txt`) a appris a ce depot
// qu'un critere geometrique rend 93 faux positifs sur 108, et que le NOM est la seule grandeur
// qui separe une plante d'un mur. L'eau a la meme forme de probleme, mais l'asymetrie est
// INVERSE : ici, un candidat de trop coute une ligne `EXCLU` a ecrire, tandis qu'un candidat
// manquant retire une surface du denominateur SANS QUE RIEN NE LE DISE — et la porte
// `water_proto_unassigned == 0` devient verte par inaction.
//
// La detection est donc DELIBEREMENT LARGE, et elle a deux etages :
//
//   (1) SIGNAL DE DONNEE, infalsifiable : tout arbre tfrag de `TFragmentTreeKind::WATER`.
//       C'est Naughty Dog qui a range ces surfaces la, pas nous. Toute texture consommee par un
//       tel arbre entre dans le lexique d'eau AUTOMATIQUEMENT, sans qu'on ait a deviner son nom.
//   (2) SIGNAL DE NOM, large : un motif de `kNameHints`. Il rattrape les surfaces que ND a
//       rangees ailleurs (les nappes de cascade sont du tfrag ORDINAIRE ou du TIE).
//
// L'UNITE RECENSEE. Le TIE et le shrub ont des prototypes nommes (`proto_names`, qui voyagent
// dans le fr3 depuis `extract_tie.cpp`). Le tfrag n'en a pas : une surface tfrag n'est
// identifiable que par sa TEXTURE. L'unite du recensement est donc un NOM :
//   - `tie`   : le nom du prototype
//   - `shrub` : le nom du prototype
//   - `tfrag` : le nom de la texture
// Chaque nom doit porter un verdict explicite dans `recharged_assets/water_falls.txt`. Un nom
// sans verdict est compte dans `unassigned` : c'est la grandeur que la porte de l'item lit.

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "common/custom_data/Tfrag3Data.h"
#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"
#include "common/util/json_util.h"

#include "fmt/format.h"

namespace {

// ------------------------------------------------------------------ le lexique de nom ------
// LARGE PAR CONSTRUCTION (voir l'en-tete). Chaque motif est une sous-chaine, comparee en
// minuscules au nom de la texture ET au nom de sa tpage. Un faux positif se solde par une ligne
// `EXCLU <nom> <raison>` dans `water_falls.txt` — c'est le prix voulu.
// `darkeco`, `sulfur`, `tar` et `bubble` sont la parce que le recensement des 26 fr3 a montre
// des surfaces qu'aucun motif « aquatique » evident n'attrape : `cv-darkecofringe`,
// `environment-darkeco`, `vil3-sulfurpool-*`, `swp-mud-floor-tar`, `effects/surfacebubble`.
// Sans eux, six surfaces sortaient du denominateur sans que rien ne le dise.
const char* const kNameHints[] = {
    "water",  "wat-",   "wass",   "fall",   "cascad", "river",  "riv-",   "ocean",
    "sea-",   "lava",   "mud",    "sludg",  "pool",   "pond",   "fount",  "geyser",
    "splash", "foam",   "wave",   "liquid", "swamp",  "drip",   "stream", "darkeco",
    "eco-",   "-eco",   "whirl",  "ripple", "sulfur", "tar",    "bubble", "caustic",
};

std::string lower(std::string s) {
  for (auto& c : s) {
    c = (char)std::tolower((unsigned char)c);
  }
  return s;
}

bool name_hints_water(const std::string& tex_name, const std::string& tpage) {
  const std::string a = lower(tex_name);
  const std::string b = lower(tpage);
  for (const char* hint : kNameHints) {
    if (a.find(hint) != std::string::npos || b.find(hint) != std::string::npos) {
      return true;
    }
  }
  return false;
}

// ------------------------------------------------------------------------ l'inventaire -----
struct Entry {
  std::string name;              // le nom recense (proto TIE/shrub, ou texture tfrag)
  std::string kind;              // "tie" | "shrub" | "tfrag"
  std::set<std::string> levels;  // les niveaux ou il apparait
  std::set<std::string> textures;
  std::set<std::string> tfrag_kinds;  // pour le tfrag : normal / trans / water / ...
  bool hard_signal = false;           // vu dans un arbre tfrag de kind WATER
  u64 draws = 0;
  u64 tris = 0;
};

struct LevelStat {
  std::string name;
  u64 fr3_bytes = 0;
  u64 textures = 0;
  u64 water_textures = 0;
  u64 tfrag_water_trees = 0;
  u64 tie_protos = 0;
  u64 shrub_protos = 0;
  // `tree_tex_id < 0` designe un SLOT de texture animee, pas un index dans `textures`. Jak 1
  // n'a pas de `TextureAnimator` (SPEC §1.4), donc ce compte doit rester nul ; s'il ne l'est
  // pas, des draws echappent au recensement et il faut que ca se VOIE plutot que de les
  // laisser tomber en silence.
  u64 anim_slot_draws = 0;
};

void load_level_fr3(const fs::path& fr3_path, tfrag3::Level& lev) {
  // Meme sequence que `tools/mesh_audit/main.cpp:65` et que `Loader.cpp` : le fr3 est zstd, et
  // les sommets restent packes tant que `unpack()` n'a pas tourne. Le recensement ne lit QUE les
  // draws, les textures et les noms de prototype : aucun `unpack()` n'est necessaire ici, et s'en
  // passer economise plusieurs Go de RAM sur les 26 niveaux.
  auto data = file_util::read_binary_file(fr3_path);
  auto decomp = compression::decompress_zstd(data.data(), data.size());
  Serializer ser(decomp.data(), decomp.size());
  lev.serialize(ser);
}

std::string tex_label(const tfrag3::Level& lev, s32 tex_id) {
  if (tex_id < 0 || (size_t)tex_id >= lev.textures.size()) {
    return fmt::format("<tex#{}>", tex_id);
  }
  const auto& t = lev.textures[(size_t)tex_id];
  if (!t.debug_name.empty()) {
    return t.debug_name;
  }
  return fmt::format("<tex#{}>", tex_id);
}


// ------------------------------------------------------------------ les entites ------------
// Les surfaces d'eau POSEES ne sont pas dans le fr3 : ce sont des entites du bsp, et le look
// qu'elles portent est un entier du res-lump (`water-anim.gc:606`). Le decompilateur les exporte
// deja en JSON (`extract_level.cpp:576`), et c'est la seule source ou le LOOK POSE est lisible.
// Sans cette passe, `water_entities` serait un nombre recopie a la main : un echo, pas une mesure.
struct EntityCensus {
  u64 anim = 0;         // entites d'un sous-type de water-anim
  u64 vol = 0;          // water-vol nus
  u64 files = 0;
  std::map<int, u64> looks_posed;  // look -> nombre de fois pose
  bool loaded = false;
};

// Les 14 sous-types de `water-anim` de jak 1. `helix-water` est un `process-drawable` qui RELAIE
// son entite a un enfant `helix-dark-eco` (levels/sunken/helix-water.gc:448) : il porte le look 40
// et un recensement qui ne filtrerait que sur les sous-types de water-anim le MANQUERAIT.
const char* const kWaterAnimTypes[] = {
    "water-anim",   "dark-eco-pool", "jungle-water",   "mud",           "lavatube-lava",
    "cave-water",   "ogre-lava",     "rolling-water",  "sunken-water",  "training-water",
    "villagea-water", "villageb-water", "villagec-lava", "helix-water"};
const char* const kWaterVolTypes[] = {"water-vol", "water-vol-deadly"};

EntityCensus census_entities(const fs::path& dir) {
  EntityCensus out;
  if (!fs::exists(dir)) {
    return out;
  }
  std::set<std::string> anim_types(std::begin(kWaterAnimTypes), std::end(kWaterAnimTypes));
  std::set<std::string> vol_types(std::begin(kWaterVolTypes), std::end(kWaterVolTypes));
  std::vector<fs::path> files;
  for (const auto& de : fs::directory_iterator(dir)) {
    const auto fn = de.path().filename().string();
    if (de.is_regular_file() && fn.size() > 12 &&
        fn.compare(fn.size() - 12, 12, "-actors.json") == 0) {
      files.push_back(de.path());
    }
  }
  std::sort(files.begin(), files.end());
  for (const auto& f : files) {
    out.files++;
    json j;
    try {
      j = json::parse(file_util::read_text_file(f.string()));
    } catch (const std::exception& e) {
      fmt::print(stderr, "[water_bake] {} illisible : {}\n", f.string(), e.what());
      continue;
    }
    if (!j.is_array()) {
      continue;
    }
    for (const auto& a : j) {
      // `demo-actors.json` porte des entrees nulles : les sauter, pas s'y arreter.
      if (!a.is_object() || !a.contains("etype") || !a["etype"].is_string()) {
        continue;
      }
      const std::string etype = a["etype"].get<std::string>();
      if (anim_types.count(etype)) {
        out.anim++;
        if (a.contains("lump") && a["lump"].is_object() && a["lump"].contains("look") &&
            a["lump"]["look"].is_number_integer()) {
          out.looks_posed[a["lump"]["look"].get<int>()]++;
        }
      } else if (vol_types.count(etype)) {
        out.vol++;
      }
    }
  }
  out.loaded = true;
  return out;
}

void usage() {
  fmt::print(
      "water_bake — inventaire de l'eau (item water-census, SPEC-refonte-eau.md §5.8)\n"
      "\n"
      "Usage: water_bake [--fr3-dir DIR] [--verdicts PATH] [--inventory PATH]\n"
      "                  [--report PATH] [--dump-textures]\n"
      "\n"
      "  --fr3-dir DIR     dossier des .fr3 (defaut: <repo>/out/jak1/fr3)\n"
      "  --verdicts PATH   water_falls.txt (defaut: <repo>/recharged_assets/water_falls.txt)\n"
      "  --inventory PATH  inventaire machine a ecrire (lu par le moteur)\n"
      "  --report PATH     rapport lisible a ecrire (notes de labo, aucune porte ne le lit)\n"
      "  --dump-textures   n'ecrit rien : imprime CHAQUE texture de CHAQUE niveau, avec le kind\n"
      "                    des arbres qui la consomment. C'est la vue depuis laquelle le lexique\n"
      "                    de verdicts s'ecrit.\n");
}

}  // namespace

int main(int argc, char** argv) {
  fs::path fr3_dir;
  fs::path verdicts_path;
  fs::path inventory_path;
  fs::path report_path;
  fs::path entities_dir;
  bool dump_textures = false;

  for (int i = 1; i < argc; i++) {
    const std::string a = argv[i];
    auto next = [&]() -> std::string {
      if (i + 1 >= argc) {
        fmt::print(stderr, "water_bake: '{}' attend une valeur\n", a);
        std::exit(2);
      }
      return argv[++i];
    };
    if (a == "--fr3-dir") {
      fr3_dir = next();
    } else if (a == "--verdicts") {
      verdicts_path = next();
    } else if (a == "--inventory") {
      inventory_path = next();
    } else if (a == "--report") {
      report_path = next();
    } else if (a == "--entities-dir") {
      entities_dir = next();
    } else if (a == "--dump-textures") {
      dump_textures = true;
    } else if (a == "-h" || a == "--help") {
      usage();
      return 0;
    } else {
      fmt::print(stderr, "water_bake: option inconnue '{}'\n", a);
      usage();
      return 2;
    }
  }

  file_util::setup_project_path({});
  if (fr3_dir.empty()) {
    fr3_dir = file_util::get_jak_project_dir() / "out" / "jak1" / "fr3";
  }
  if (entities_dir.empty()) {
    entities_dir = file_util::get_jak_project_dir() / "decompiler_out" / "jak1" / "entities";
  }
  if (verdicts_path.empty()) {
    verdicts_path = file_util::get_jak_project_dir() / "recharged_assets" / "water_falls.txt";
  }

  std::vector<fs::path> fr3_files;
  for (const auto& de : fs::directory_iterator(fr3_dir)) {
    if (de.is_regular_file() && de.path().extension() == ".fr3") {
      fr3_files.push_back(de.path());
    }
  }
  std::sort(fr3_files.begin(), fr3_files.end());
  if (fr3_files.empty()) {
    fmt::print(stderr, "water_bake: aucun .fr3 dans {}\n", fr3_dir.string());
    return 3;
  }

  std::map<std::string, Entry> entries;  // cle : kind + '\t' + nom
  std::vector<LevelStat> level_stats;

  auto entry_for = [&](const std::string& kind, const std::string& name) -> Entry& {
    auto& e = entries[kind + "\t" + name];
    if (e.name.empty()) {
      e.name = name;
      e.kind = kind;
    }
    return e;
  };

  for (const auto& path : fr3_files) {
    const std::string level_name = path.stem().string();
    tfrag3::Level lev;
    load_level_fr3(path, lev);

    LevelStat st;
    st.name = level_name;
    st.fr3_bytes = (u64)fs::file_size(path);
    st.textures = lev.textures.size();

    // --- etage (1) : le signal de DONNEE. Les textures que ND a rangees sous un arbre WATER.
    std::set<s32> hard_water_tex;
    for (int geo = 0; geo < tfrag3::TFRAG_GEOS; geo++) {
      for (const auto& tree : lev.tfrag_trees[geo]) {
        if (tree.kind != tfrag3::TFragmentTreeKind::WATER) {
          continue;
        }
        st.tfrag_water_trees++;
        for (const auto& draw : tree.draws) {
          hard_water_tex.insert(draw.tree_tex_id);
        }
      }
    }

    // --- les draws qui ne pointent aucune texture indexee (slot anime) : comptes, jamais tus.
    for (int geo = 0; geo < tfrag3::TFRAG_GEOS; geo++) {
      for (const auto& tree : lev.tfrag_trees[geo]) {
        for (const auto& draw : tree.draws) {
          st.anim_slot_draws += draw.tree_tex_id < 0 ? 1 : 0;
        }
      }
    }
    for (int geo = 0; geo < tfrag3::TIE_GEOS; geo++) {
      for (const auto& tree : lev.tie_trees[geo]) {
        for (const auto& draw : tree.static_draws) {
          st.anim_slot_draws += draw.tree_tex_id < 0 ? 1 : 0;
        }
        for (const auto& draw : tree.instanced_wind_draws) {
          st.anim_slot_draws += draw.tree_tex_id < 0 ? 1 : 0;
        }
      }
    }

    // --- le lexique d'eau EFFECTIF de ce niveau : signal de donnee OU signal de nom.
    std::set<s32> water_tex;
    for (size_t ti = 0; ti < lev.textures.size(); ti++) {
      const auto& t = lev.textures[ti];
      if (hard_water_tex.count((s32)ti) || name_hints_water(t.debug_name, t.debug_tpage_name)) {
        water_tex.insert((s32)ti);
      }
    }
    st.water_textures = water_tex.size();

    if (dump_textures) {
      // Vue brute : ce que le lexique de verdicts doit couvrir, avant toute decision.
      std::map<s32, std::set<std::string>> consumed_by;
      for (int geo = 0; geo < tfrag3::TFRAG_GEOS; geo++) {
        for (const auto& tree : lev.tfrag_trees[geo]) {
          const char* kn = tfrag3::tfrag_tree_names[(int)tree.kind];
          for (const auto& draw : tree.draws) {
            consumed_by[draw.tree_tex_id].insert(std::string("tfrag/") + kn);
          }
        }
      }
      for (int geo = 0; geo < tfrag3::TIE_GEOS; geo++) {
        for (const auto& tree : lev.tie_trees[geo]) {
          for (const auto& draw : tree.static_draws) {
            consumed_by[draw.tree_tex_id].insert("tie");
          }
          for (const auto& draw : tree.instanced_wind_draws) {
            consumed_by[draw.tree_tex_id].insert("tie-wind");
          }
        }
      }
      for (const auto& tree : lev.shrub_trees) {
        for (const auto& draw : tree.static_draws) {
          consumed_by[(s32)draw.tree_tex_id].insert("shrub");
        }
      }
      for (size_t ti = 0; ti < lev.textures.size(); ti++) {
        const auto& t = lev.textures[ti];
        auto it = consumed_by.find((s32)ti);
        if (it == consumed_by.end()) {
          continue;  // texture presente mais jamais liee par un draw de decor
        }
        std::string users;
        for (const auto& u : it->second) {
          users += (users.empty() ? "" : ",") + u;
        }
        const bool hard = hard_water_tex.count((s32)ti) != 0;
        const bool hinted = name_hints_water(t.debug_name, t.debug_tpage_name);
        fmt::print("TEX {} {} tpage={} name={} users={} hard={} hint={}\n", level_name, ti,
                   t.debug_tpage_name.empty() ? "-" : t.debug_tpage_name,
                   t.debug_name.empty() ? "-" : t.debug_name, users, hard ? 1 : 0, hinted ? 1 : 0);
      }
      level_stats.push_back(st);
      continue;
    }

    // --- etage (2) : remonter de la texture au NOM qui portera le verdict.
    // tfrag : l'unite est la texture elle-meme (le tfrag n'a pas de prototypes).
    for (int geo = 0; geo < tfrag3::TFRAG_GEOS; geo++) {
      for (const auto& tree : lev.tfrag_trees[geo]) {
        const char* kn = tfrag3::tfrag_tree_names[(int)tree.kind];
        for (const auto& draw : tree.draws) {
          if (!water_tex.count(draw.tree_tex_id)) {
            continue;
          }
          auto& e = entry_for("tfrag", tex_label(lev, draw.tree_tex_id));
          e.levels.insert(level_name);
          e.textures.insert(tex_label(lev, draw.tree_tex_id));
          e.tfrag_kinds.insert(kn);
          e.hard_signal = e.hard_signal || hard_water_tex.count(draw.tree_tex_id) != 0;
          e.draws++;
          e.tris += draw.num_triangles;
        }
      }
    }

    // tie : l'unite est le prototype. Un draw porte une texture ; ses vis-groups disent quel
    // prototype il habille (`tie_proto_idx`).
    for (int geo = 0; geo < tfrag3::TIE_GEOS; geo++) {
      for (const auto& tree : lev.tie_trees[geo]) {
        st.tie_protos += tree.proto_names.size();
        for (const auto& draw : tree.static_draws) {
          if (!water_tex.count(draw.tree_tex_id)) {
            continue;
          }
          std::set<u16> protos;
          for (const auto& vg : draw.vis_groups) {
            protos.insert(vg.tie_proto_idx);
          }
          for (u16 pi : protos) {
            const std::string pname = pi < tree.proto_names.size()
                                          ? tree.proto_names[pi]
                                          : fmt::format("<tie-proto#{}>", pi);
            auto& e = entry_for("tie", pname);
            e.levels.insert(level_name);
            e.textures.insert(tex_label(lev, draw.tree_tex_id));
            e.hard_signal = e.hard_signal || hard_water_tex.count(draw.tree_tex_id) != 0;
            e.draws++;
            e.tris += draw.num_triangles;
          }
        }
        // Les draws instancies (vent) ne portent pas de `tie_proto_idx` : leur groupe designe une
        // INSTANCE. Ils sont recenses sous un nom de texture pour ne pas disparaitre du
        // denominateur — un seau non classe n'est pas un seau vide.
        for (const auto& draw : tree.instanced_wind_draws) {
          if (!water_tex.count(draw.tree_tex_id)) {
            continue;
          }
          auto& e = entry_for("tie", fmt::format("tie-wind:{}", tex_label(lev, draw.tree_tex_id)));
          e.levels.insert(level_name);
          e.textures.insert(tex_label(lev, draw.tree_tex_id));
          e.draws++;
          e.tris += draw.num_triangles;
        }
      }
    }

    // shrub : l'unite est le prototype, donne directement par le draw.
    for (const auto& tree : lev.shrub_trees) {
      st.shrub_protos += tree.proto_names.size();
      for (const auto& draw : tree.static_draws) {
        if (!water_tex.count((s32)draw.tree_tex_id)) {
          continue;
        }
        const std::string pname = draw.proto_idx < tree.proto_names.size()
                                      ? tree.proto_names[draw.proto_idx]
                                      : fmt::format("<shrub-proto#{}>", draw.proto_idx);
        auto& e = entry_for("shrub", pname);
        e.levels.insert(level_name);
        e.textures.insert(tex_label(lev, (s32)draw.tree_tex_id));
        e.draws++;
        e.tris += draw.num_triangles;
      }
    }

    level_stats.push_back(st);
    fmt::print("[water_bake] {:<12} textures={:<5} eau={:<4} arbres-tfrag-WATER={}\n", level_name,
               st.textures, st.water_textures, st.tfrag_water_trees);
  }

  if (dump_textures) {
    return 0;
  }

  // ------------------------------------------------------------------ le verdict ------------
  // `water_falls.txt` : un verdict par nom. Le format est celui de SPEC §5.7 ; seul le PREMIER
  // champ (le verdict) et le SECOND (le nom) sont lus ici — le reste est la charge utile des
  // items aval.
  std::map<std::string, std::string> verdict;  // nom -> CHUTE|JET|NAPPE|EXCLU
  bool verdicts_loaded = false;
  if (file_util::file_exists(verdicts_path.string())) {
    verdicts_loaded = true;
    const std::string text = file_util::read_text_file(verdicts_path.string());
    size_t pos = 0;
    while (pos <= text.size()) {
      size_t end = text.find('\n', pos);
      std::string line = text.substr(pos, end == std::string::npos ? std::string::npos : end - pos);
      pos = (end == std::string::npos) ? text.size() + 1 : end + 1;
      size_t b = line.find_first_not_of(" \t\r");
      if (b == std::string::npos || line[b] == '#') {
        continue;
      }
      size_t e = line.find_first_of(" \t\r", b);
      if (e == std::string::npos) {
        continue;
      }
      const std::string v = line.substr(b, e - b);
      if (v != "CHUTE" && v != "JET" && v != "NAPPE" && v != "EXCLU") {
        continue;
      }
      size_t nb = line.find_first_not_of(" \t\r", e);
      if (nb == std::string::npos) {
        continue;
      }
      size_t ne = line.find_first_of(" \t\r", nb);
      verdict[line.substr(nb, ne == std::string::npos ? std::string::npos : ne - nb)] = v;
    }
  }

  u64 assigned = 0, unassigned = 0, orphan = 0;
  std::map<std::string, u64> by_verdict;
  std::set<std::string> seen_names;
  for (const auto& kv : entries) {
    seen_names.insert(kv.second.name);
    auto it = verdict.find(kv.second.name);
    if (it == verdict.end()) {
      unassigned++;
    } else {
      assigned++;
      by_verdict[it->second]++;
    }
  }
  for (const auto& kv : verdict) {
    if (!seen_names.count(kv.first)) {
      orphan++;
    }
  }

  // ------------------------------------------------------------------ les sorties -----------
  const EntityCensus ents = census_entities(entities_dir);
  u64 looks_dup = 0;
  for (const auto& kv : ents.looks_posed) {
    looks_dup += kv.second > 1 ? kv.second - 1 : 0;
  }
  fmt::print("[water_bake] entites : water-anim={} water-vol={} total={} looks poses={} (fichiers={})\n",
             ents.anim, ents.vol, ents.anim + ents.vol, ents.looks_posed.size(), ents.files);

  if (!inventory_path.empty()) {
    std::string out;
    out += "# water_inventory.txt — GENERE par tools/water_bake. NE PAS EDITER A LA MAIN.\n";
    out += "# L'enumeration vient des .fr3 (donnee produite par l'utilisateur, famille ISO) ;\n";
    out += "# les verdicts vivent a cote, dans recharged_assets/water_falls.txt. Le moteur JOINT\n";
    out += "# les deux et publie le residu : c'est la porte `water_proto_unassigned`.\n";
    out += "version 1\n";
    out += fmt::format("entities loaded={} files={} water_anim={} water_vol={} total={} "
                       "looks_posed={} looks_dup={}\n",
                       ents.loaded ? 1 : 0, ents.files, ents.anim, ents.vol, ents.anim + ents.vol,
                       ents.looks_posed.size(), looks_dup);
    for (const auto& st : level_stats) {
      out += fmt::format(
          "level {} fr3_bytes={} textures={} water_textures={} tfrag_water_trees={} "
          "anim_slot_draws={}\n",
          st.name, st.fr3_bytes, st.textures, st.water_textures, st.tfrag_water_trees,
          st.anim_slot_draws);
    }
    for (const auto& kv : entries) {
      const auto& e = kv.second;
      std::string levels, textures;
      for (const auto& l : e.levels) {
        levels += (levels.empty() ? "" : ",") + l;
      }
      for (const auto& t : e.textures) {
        textures += (textures.empty() ? "" : ",") + t;
      }
      out += fmt::format("proto {} kind={} hard={} draws={} tris={} levels={} tex={}\n", e.name,
                         e.kind, e.hard_signal ? 1 : 0, e.draws, e.tris, levels, textures);
    }
    file_util::write_text_file(inventory_path.string(), out);
    fmt::print("[water_bake] inventaire ecrit : {}\n", inventory_path.string());
  }

  if (!report_path.empty()) {
    std::string out;
    out += "water_bake — rapport lisible (notes de labo ; aucune porte ne lit ce fichier)\n\n";
    out += fmt::format("niveaux lus         : {}\n", level_stats.size());
    out += fmt::format("noms recenses       : {}\n", entries.size());
    out += fmt::format("verdicts charges    : {} ({})\n", verdict.size(),
                       verdicts_loaded ? verdicts_path.string() : "FICHIER ABSENT");
    out += fmt::format("classes             : {}\n", assigned);
    out += fmt::format("SANS VERDICT        : {}\n", unassigned);
    out += fmt::format("verdicts orphelins  : {}\n\n", orphan);
    for (const auto& kv : by_verdict) {
      out += fmt::format("  {:<6} {}\n", kv.first, kv.second);
    }
    out += "\n-- noms SANS VERDICT (a classer) --\n";
    for (const auto& kv : entries) {
      if (!verdict.count(kv.second.name)) {
        std::string levels;
        for (const auto& l : kv.second.levels) {
          levels += (levels.empty() ? "" : ",") + l;
        }
        out += fmt::format("  {:<6} {:<40} hard={} draws={:<5} levels={}\n", kv.second.kind,
                           kv.second.name, kv.second.hard_signal ? 1 : 0, kv.second.draws, levels);
      }
    }
    out += "\n-- verdicts ORPHELINS (nom absent des donnees) --\n";
    for (const auto& kv : verdict) {
      if (!seen_names.count(kv.first)) {
        out += fmt::format("  {:<6} {}\n", kv.second, kv.first);
      }
    }
    file_util::write_text_file(report_path.string(), out);
    fmt::print("[water_bake] rapport ecrit : {}\n", report_path.string());
  }

  fmt::print("[water_bake] noms={} classes={} sans-verdict={} orphelins={}\n", entries.size(),
             assigned, unassigned, orphan);
  return 0;
}
