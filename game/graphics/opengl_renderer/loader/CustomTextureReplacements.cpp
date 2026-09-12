#include "CustomTextureReplacements.h"
#include "game/system/recharged_gating.h"
#include "game/graphics/origin_ablate.h"

#include <atomic>
#include <cctype>
#include <cstring>
#include <fstream>
#include <map>
#include <mutex>
#include <set>
#include <vector>

#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/util/Ktx2Subset.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/GpuCaps.h"
#include "game/graphics/opengl_renderer/loader/ManagedAssets.h"
#include "game/runtime.h"
#include "game/system/autoport_proof.h"

#include "third-party/json.hpp"
#include "third-party/stb_image/stb_image.h"


namespace custom_tex {

namespace {
// Lazily-built index of replacement PNGs. Two keys map to each file: the
// relative path without extension (e.g. "village1-tpage-2/sand-01") and the
// bare filename without extension ("sand-01").
struct ScanState {
  bool scanned = false;
  bool last_user_enable = false;
  bool last_bundled_enable = false;
  // USER drop dir (get_custom_assets_replacements_dir) — always wins over bundled.
  std::map<std::string, fs::path> user_index;
  // Package-BUNDLED first-party set (get_bundled_recharged_textures_dir).
  std::map<std::string, fs::path> bundled_index;
} g_state;


std::string normalize_key(std::string key) {
  // filesystem separators may differ across platforms; the debug tpage/name
  // keys use forward slashes.
  for (auto& c : key) {
    if (c == '\\') {
      c = '/';
    }
  }
  return key;
}

// Scan one replacements root into an index. Keys per file: the relative path without
// extension ("village1-tpage-2/sand-01"), the bare stem ("sand-01"), and — for nested
// per-texture layouts like <tpage>/<tex>/<tex>.png (the committed first-party set) —
// "<top-level-dir>/<stem>" so the exact tpage/name lookup still hits without relying on
// the bare-name fallback. A leading "texture_replacements/" wrapper (how internet packs
// ship: texture_replacements/<tpage>/<name>.png) is stripped before key derivation, so
// wrapped and unwrapped layouts produce the same keys on both the user and bundled sides.
// Gshield-load-and-crash: `ext` (lowercase, with the dot) selects the tier's file type. The
// PNG tiers pass the default and are therefore untouched: ".png"/".PNG" are exactly the two
// spellings accepted before. The PRE-BAKED tier passes ".ktx2" and gets the SAME key
// derivation — which is the point, since it indexes the same tree under different extensions.
int scan_dir(const fs::path& dir,
             std::map<std::string, fs::path>& index,
             const char* ext = ".png") {
  if (!fs::exists(dir)) {
    return 0;
  }
  std::string ext_upper(ext);
  for (auto& c : ext_upper) {
    c = (char)std::toupper((unsigned char)c);
  }
  int file_count = 0;
  for (const auto& entry : fs::recursive_directory_iterator(dir)) {
    if (!entry.is_regular_file()) {
      continue;
    }
    const auto& p = entry.path();
    if (p.extension() != ext && p.extension() != ext_upper) {
      continue;
    }
    file_count++;
    auto rel = fs::relative(p, dir);
    rel.replace_extension();
    std::string rel_key = normalize_key(rel.string());
    index[rel_key] = p;
    // Internet texture packs ship wrapped as texture_replacements/<tpage>/... (the upstream
    // OpenGOAL convention). Strip the wrapper so the same <tpage>/<name> keys come out as for
    // an unwrapped layout — the user and bundled sides share this exact derivation.
    std::string sub_key = rel_key;
    constexpr const char* kWrapper = "texture_replacements/";
    if (sub_key.rfind(kWrapper, 0) == 0) {
      sub_key = sub_key.substr(std::string(kWrapper).size());
      if (!sub_key.empty() && index.find(sub_key) == index.end()) {
        index[sub_key] = p;
      }
    }
    std::string bare_key = p.stem().string();
    // "<tpage>/<stem>" for nested layouts (first path component + stem).
    auto slash = sub_key.find('/');
    if (slash != std::string::npos) {
      std::string tpage_key = sub_key.substr(0, slash) + "/" + bare_key;
      if (tpage_key != sub_key && index.find(tpage_key) == index.end()) {
        index[tpage_key] = p;
      }
    }
    // don't clobber a more-specific relative key with a bare-name collision
    if (index.find(bare_key) == index.end()) {
      index[bare_key] = p;
    }
  }
  return file_count;
}

// Exact tpage/name key first, then the bare-name fallback. Returns nullptr on miss.
const fs::path* find_key(const std::map<std::string, fs::path>& index,
                         const std::string& exact_key,
                         const std::string& bare_key) {
  auto it = index.find(exact_key);
  if (it == index.end()) {
    it = index.find(bare_key);
    if (it == index.end()) {
      return nullptr;
    }
  }
  return &it->second;
}

void ensure_scanned() {
  const bool user_on = recharged_gating::on(recharged_gating::kLoadCustomAssets);
  // Le jeu bundle sert les substitutions de base (porte `recharged_textures`) — on le balaye
  // des que le maitre est leve ; les portes par lookup choisissent les sources.
  const bool bundled_on = Gfx::recharged_master_active();
  // Rescan on any gate transition so a freshly-dropped directory is picked up.
  if (g_state.scanned && g_state.last_user_enable == user_on &&
      g_state.last_bundled_enable == bundled_on) {
    return;
  }
  g_state.last_user_enable = user_on;
  g_state.last_bundled_enable = bundled_on;
  g_state.scanned = true;
  g_state.user_index.clear();
  g_state.bundled_index.clear();

  const auto user_dir = file_util::get_custom_assets_replacements_dir(g_game_version);
  const int user_count = scan_dir(user_dir, g_state.user_index);
  const auto bundled_dir = file_util::get_bundled_recharged_textures_dir(g_game_version);
  const int bundled_count = scan_dir(bundled_dir, g_state.bundled_index);

  lg::info("custom texture replacements: {} user files in {}, {} bundled files in {}",
           user_count, user_dir.string(), bundled_count, bundled_dir.string());
}
}  // namespace

// lighting-origin-bitexact : COMBIEN DE FOIS LA PAGE DE POLICE EST SORTIE DE LA PORTE, MAITRE
// ETEINT. Publie par `hdr.cpp` sous `origin_font_master_bypass`, a cote de
// `origin_bitexact_defects`. Ce compteur n'est pas decoratif : il est la SEULE trace machine que
// la porte bit-a-bit ne couvre pas la police. Le jour ou on croira que « maitre eteint = le jeu
// d'origine » sans reserve, il sera non nul et dira le contraire.
static std::atomic<uint64_t> g_font_master_bypass{0};

uint64_t font_master_bypass_count() {
  return g_font_master_bypass.load(std::memory_order_relaxed);
}

bool is_font_atlas(const std::string& tpage_name) {
  if (tpage_name != "gamefontnew") {
    return false;
  }
  // CE PREDICAT N'EST PAS ABLATE DANS LE BINAIRE-TEMOIN, ET C'EST UNE DECISION MESUREE.
  //
  // L'essai 1 de `lighting-origin-bitexact` l'ablatait (le temoin rendait l'atlas de Naughty
  // Dog) et mesurait 994 px d'ecart au creneau h12. Le raisonnement etait « la page sort de la
  // porte du maitre, donc c'est une fuite de la couche Recharged ». Trois mesures du 2026-09-07
  // le refutent :
  //
  //  1. LE BANC DE TEXTE EST DANS LA DONNEE PARTAGEE. `goalc/data_compiler/game_text_common.cpp`
  //     ecrit UN seul `<lang>COMMON.TXT` dans `out/jak1/iso`, empile depuis les trois couches de
  //     `game/assets/jak1/game_text.gp` (dont nos JSON de casse mixte). `text.gc:157` le charge
  //     par ce nom unique et `fake_iso.cpp:60-64` ne scanne que `get_iso_out_dir()` : les bancs
  //     purs de ND (`iso_data/jak1/TEXT/`) ne sont JAMAIS atteignables. Les deux binaires lisent
  //     donc le meme banc, et aucun drapeau ne peut en choisir un autre.
  //  2. LES CHASSES SONT DANS LA DONNEE PARTAGEE. `*font12-table*` / `*font24-table*`
  //     (`goal_src/jak1/engine/gfx/font.gc`) portent les avances Urbanist ecrites par
  //     `recharged_assets/font/patch_font_tables.py` (a=13,5756 en 12 et 14,5671 en 24 contre
  //     14,25 et 24,0 en stock) ; `font.o` est liste dans `game.gd:179` et `engine.gd:183`, et
  //     ces flottants se retrouvent dans `GAME.CGO` et `ENGINE.CGO`. `grep -ci recharged
  //     font.gc` rend 0 : aucune garde, aucun selecteur.
  //  3. DONC LE TEMOIN ABLATE NE DESSINAIT PAS LE JEU DE NAUGHTY DOG. Il dessinait les glyphes
  //     ND positionnes par des chasses Urbanist, sur nos chaines : une chimere qu'aucun binaire
  //     livrable ne peut egaler. Mesure de la bande y=128..141 du creneau h12 (seuil d'Otsu sur
  //     un chapeau haut-de-forme, pas un reglage a la main) : encre 776 px cote temoin contre
  //     530 cote juge, 29 composantes contre 26, Jaccard des masques d'encre 0,38. Ce ne sont
  //     pas les memes formes.
  //
  // Et surtout : gater cette page REOUVRE UN DEFAUT DEJA RAPPORTE PAR L'OWNER le 2026-09-02
  // (« t'as completement nique la font (Urbanist) ca utilise des glyphs chinois de la font par
  // defaut du jeu », voir l'en-tete de CustomTextureReplacements.h). La reponse a ce retour
  // fut precisement de retirer toute porte de cette page, parce que le texte et l'atlas sont
  // UNE unite dont les deux autres tiers ne sont pas gatables. Un vert obtenu en la gatant
  // serait un faux vert au sens des DIRECTIVES regle 3.
  //
  // Ce qui est donc VRAI et ce qui ne l'est pas : la porte `origin_bitexact_defects` mesure la
  // couche que le MAITRE gouverne. La police/texte n'en fait pas partie — par decision de
  // l'owner et par construction de la donnee. Elle est declaree non couverte dans
  // `origin_ablate.h`, et `origin_font_master_bypass` la compte a chaque course.
  if (!Gfx::recharged_master_active()) {
    g_font_master_bypass.fetch_add(1, std::memory_order_relaxed);
  }
  return true;
}

std::optional<ReplacementImage> lookup(const std::string& tpage_name, const std::string& tex_name) {
  const bool user_on = recharged_gating::on(recharged_gating::kLoadCustomAssets);
  const bool bundled_on = recharged_gating::on(recharged_gating::kTextures);
  const bool font = is_font_atlas(tpage_name);
  if (!font && !user_on && !bundled_on) {
    return std::nullopt;
  }
  ensure_scanned();

  const std::string exact_key = normalize_key(tpage_name + "/" + tex_name);
  const fs::path* path = nullptr;
  const char* src = "user";
  if (font) {
    // Gfont-regression : la page de police se resout SANS porte et depuis le paquet livre
    // UNIQUEMENT (voir le header). Un PNG joueur n'est pas honore : le texte du jeu est encode
    // pour CET atlas (minuscules dans les cellules qui portent des kanji dans l'original), un
    // autre atlas ne peut que le casser. On le dit au lieu de l'avaler.
    if (find_key(g_state.user_index, exact_key, tex_name)) {
      lg::warn("FONTTEX user-override IGNORE pour {} : la police du jeu n'est pas remplacable",
               exact_key);
    }
    path = find_key(g_state.bundled_index, exact_key, tex_name);
    src = "bundled-police";
    if (!path) {
      // Les pages `hi` (mt4hh : icones de boutons) restent d'origine par construction, seules
      // `12lo`/`24lo` portent les lettres. Pour celles-la, l'absence est le seul cas ou l'atlas
      // d'origine peut encore etre dessine : un defaut de LIVRAISON, jamais un choix — nomme.
      if (tex_name.size() >= 2 && tex_name.compare(tex_name.size() - 2, 2, "lo") == 0) {
        lg::warn("FONTTEX atlas Urbanist ABSENT du paquet livre pour {} -> atlas d'origine (les "
                 "minuscules de la grande police y sont des kanji)",
                 exact_key);
      }
      return std::nullopt;
    }
  } else {
    // PRECEDENCE (owner): user custom_assets > bundled recharged > stock.
    path = user_on ? find_key(g_state.user_index, exact_key, tex_name) : nullptr;
    if (!path && bundled_on) {
      path = find_key(g_state.bundled_index, exact_key, tex_name);
      src = "bundled";
    }
  }
  if (!path) {
    return std::nullopt;
  }

  int w = 0, h = 0;
  auto* data = stbi_load(path->string().c_str(), &w, &h, nullptr, STBI_rgb_alpha);
  if (!data) {
    lg::warn("custom texture replacement: failed to load {}", path->string());
    return std::nullopt;
  }

  ReplacementImage out;
  out.w = w;
  out.h = h;
  out.src = src;
  out.rgba.resize((size_t)w * (size_t)h * 4);
  memcpy(out.rgba.data(), data, out.rgba.size());
  stbi_image_free(data);

  lg::info("custom texture replacement ({}): {} <- {}", src, exact_key, path->string());
  return out;
}

// Deterministic mirror of lookup()'s winning source — no pixel load.
BaseSource base_source(const std::string& tpage_name, const std::string& tex_name) {
  const bool user_on = recharged_gating::on(recharged_gating::kLoadCustomAssets);
  const bool bundled_on = recharged_gating::on(recharged_gating::kTextures);
  const bool font = is_font_atlas(tpage_name);
  if (!font && !user_on && !bundled_on) {
    return BaseSource::Stock;
  }
  ensure_scanned();
  const std::string exact_key = normalize_key(tpage_name + "/" + tex_name);
  if (font) {
    // Gfont-regression : miroir exact de lookup() — la police vient du paquet livre, sans porte,
    // et jamais du dossier joueur. add_texture s'en sert pour NE PAS consulter les niveaux
    // telecharge/pre-cuit sur cette page.
    return find_key(g_state.bundled_index, exact_key, tex_name) ? BaseSource::Bundled
                                                                : BaseSource::Stock;
  }
  if (user_on && find_key(g_state.user_index, exact_key, tex_name)) {
    return BaseSource::User;
  }
  if (bundled_on && find_key(g_state.bundled_index, exact_key, tex_name)) {
    return BaseSource::Bundled;
  }
  return BaseSource::Stock;
}

// ===== Gfont-regression — registre des atlas de police televerses / lies =======================
// Ecrit par le chargeur (add_texture, thread de chargement) a raison de QUATRE entrees par boot
// (ascii.12lo/12hi/24lo/24hi) ; lu et compte par le dessin direct (thread GL). Les deux threads
// n'ecrivent jamais le meme champ : le chargeur pose l'entree, le dessin incremente `binds`.
namespace {
std::mutex g_font_atlas_mutex;
std::vector<FontAtlasRec> g_font_atlas;  // petit et stable : jamais plus de quelques entrees
}  // namespace

void note_font_atlas_upload(const std::string& key, const char* source, u32 gl_id, int w, int h) {
  std::lock_guard<std::mutex> lock(g_font_atlas_mutex);
  for (auto& r : g_font_atlas) {
    if (r.key == key) {
      r.source = source;
      r.gl = gl_id;
      r.w = w;
      r.h = h;
      r.binds = 0;
      return;
    }
  }
  FontAtlasRec r;
  r.key = key;
  r.source = source;
  r.gl = gl_id;
  r.w = w;
  r.h = h;
  g_font_atlas.push_back(std::move(r));
}

FontAtlasRec* font_atlas_by_gl(u32 gl_id) {
  std::lock_guard<std::mutex> lock(g_font_atlas_mutex);
  for (auto& r : g_font_atlas) {
    if (r.gl == gl_id) {
      return &r;  // les entrees ne sont jamais retirees, le pointeur reste valide
    }
  }
  return nullptr;
}

std::string font_atlas_section() {
  std::lock_guard<std::mutex> lock(g_font_atlas_mutex);
  std::string out;
  for (const auto& r : g_font_atlas) {
    out += fmt::format("FONTATLAS name={} source={} gl={} w={} h={} binds={}\n", r.key, r.source,
                       r.gl, r.w, r.h, r.binds);
  }
  return out;
}

// ===============================================================================================
// Gshield-load-and-crash — THE PRE-BAKED (ASTC KTX2) TIER
//
// Same images as the bundled PNG tier, already GPU-compressed and already mipmapped offline by
// tools/bake_recharged_textures.py. Nothing here decodes: no stbi_load, no glGenerateMipmap, and
// no CPU measurement pass — the statistics the PNG path used to compute from decoded pixels are
// read from the <material>.stats.json the bake wrote next to the textures.
//
// MEASURED reason (SHIELD, 2026-08-26): `stage texture took 1799 ms` is ONE add_texture. The mass
// is inside the atom — a 2048x2048 PNG decode per map (151-330 ms), each map decoded TWICE (probe
// pass + re-fetch), then glGenerateMipmap (68-235 ms). The KTX2 path already in this build serves
// the same material in 87 ms, and keeps a compressed image on the GPU instead of 16 MiB of RGBA8.
// ===============================================================================================
namespace {

// One subdirectory per GPU profile under <...>_baked/. Only "astc" is produced today; the name
// is also what the two hit lines print, so a logcat can be counted per profile.
constexpr const char* kBakedProfile = "astc";

struct BakedState {
  // The PNG scan above is lock-free because it predates the managed tier; this one is not.
  // add_texture runs on whichever thread owns the GL context at the time (main thread at boot,
  // loader thread during streaming), which is exactly the race ManagedAssets.cpp locks for.
  std::mutex mutex;
  bool scanned = false;
  bool last_enable = false;
  std::map<std::string, fs::path> index;  // same key shapes as scan_dir()
  // Parsed <material>.stats.json documents, keyed by absolute sidecar path. A null value is a
  // NEGATIVE cache entry (missing or unreadable), so the warning is printed once per material
  // instead of once per map.
  std::map<std::string, nlohmann::json> sidecars;
} g_baked;

// The capability this tier hangs on. gpu_caps::detect() queries the live context ONCE (the
// renderer's init does it: opengl.cpp / android_gfx.cpp, which is where the
// "gpu caps: GLES 3.2 ... astc=true -> asset profile 'android-astc'" line comes from) and caches
// the result, so this is a struct field read, not a GL call.
bool baked_gpu_reads_astc() {
  // MESURE, 2026-08-26 (Gmemory-ceiling-and-crash), course de non-regression x86 : le pilote
  // de bureau annonce `astc=true` (GL 4.6), donc ce niveau pre-cuit N'ETAIT PAS inerte sur le
  // bureau — 28 lignes `custom texture BAKED` dans une course x86, alors que le commentaire de
  // ce fichier ET celui de LoaderStages.cpp affirmaient le contraire. Un commentaire n'est pas
  // une preuve : c'est la course qui a tranche.
  //
  // La capacite ne suffit donc pas comme garde, il faut le PROFIL. `preferred_profile()`
  // (GpuCaps.cpp:72-92) applique deja exactement cette regle a l'ETC2, avec la meme raison
  // ecrite : « Deliberately NOT android-etc2 on desktop: that would be software decompression
  // on most desktop drivers ». Un bureau qui a du BC doit lire du BC ; le seul niveau pre-cuit
  // qui existe est en ASTC, donc il ne s'applique qu'aux GPU dont le profil EST l'ASTC.
  // Effet : le chemin PNG du bureau redevient ce que la conception disait qu'il etait.
  return gpu_caps::detect().astc_ldr && gpu_caps::preferred_profile() == "android-astc";
}

// Scan gate: the MASTER, exactly like the bundled PNG index (ensure_scanned's `bundled_on`).
// The per-lookup gates below are the finer ones (base = recharged_textures, maps = master).
void ensure_baked_scanned_locked() {
  const bool on = Gfx::recharged_master_active() && baked_gpu_reads_astc();
  if (g_baked.scanned && g_baked.last_enable == on) {
    return;
  }
  g_baked.scanned = true;
  g_baked.last_enable = on;
  g_baked.index.clear();
  g_baked.sidecars.clear();
  if (!on) {
    return;
  }
  const auto dir = file_util::get_bundled_recharged_textures_baked_dir(g_game_version,
                                                                       kBakedProfile);
  const int count = scan_dir(dir, g_baked.index, ".ktx2");
  lg::info("baked recharged textures ({}): {} files ({} keys) in {}", kBakedProfile, count,
           (int)g_baked.index.size(), dir.string());
}

// The sidecar of a baked map is <its own directory>/<that directory's name>.stats.json — the
// layout the bake tool writes (<tpage>/<material>/<material>.stats.json). Returns nullptr when
// it is missing or unreadable; the caller then declines the whole material.
const nlohmann::json* baked_sidecar_locked(const fs::path& ktx2_path) {
  const auto dir = ktx2_path.parent_path();
  const auto sidecar = dir / (dir.filename().string() + ".stats.json");
  const auto key = sidecar.string();
  auto it = g_baked.sidecars.find(key);
  if (it == g_baked.sidecars.end()) {
    nlohmann::json doc;  // null on any failure => negative cache entry
    if (!fs::exists(sidecar)) {
      lg::warn(
          "baked recharged textures: no sidecar {} — les statistiques n'ont nulle part ou "
          "from without a decode, so this material falls back to PNG",
          sidecar.string());
    } else {
      try {
        doc = nlohmann::json::parse(file_util::read_text_file(sidecar));
      } catch (const std::exception& e) {
        doc = nlohmann::json();
        lg::warn("baked recharged textures: unreadable sidecar {}: {} — falling back to PNG",
                 sidecar.string(), e.what());
      }
    }
    it = g_baked.sidecars.emplace(key, std::move(doc)).first;
  }
  return it->second.is_null() ? nullptr : &it->second;
}

// What the shader must be told about the payload's channels. NEVER "rg": the bake stores full
// RGB normals, and "rg" would make the shader reconstruct Z and change the render.
const char* baked_channels(const std::string& suffix) {
  if (suffix.empty()) {
    return "rgba";  // base colour
  }
  if (suffix == "_normal" || suffix == "_specular" || suffix == "_emissive") {
    return "rgb";
  }
  return "r";  // _roughness / _height / _metallic / _ao — sampled as .r and nothing else
}

// Load one baked file. `suffix` is "" for the base and "_<kind>" for a companion map; it is also
// the key the sidecar files its entry under ("base" for the empty one).
std::optional<managed_assets::CompressedTex> baked_load(const std::string& tpage_name,
                                                        const std::string& tex_name,
                                                        const std::string& suffix,
                                                        const char* log_what) {
  if (!baked_gpu_reads_astc()) {
    return std::nullopt;
  }
  const std::string name = tex_name + suffix;
  const std::string exact_key = normalize_key(tpage_name + "/" + name);

  std::lock_guard<std::mutex> lock(g_baked.mutex);
  ensure_baked_scanned_locked();
  const fs::path* found = find_key(g_baked.index, exact_key, name);
  if (!found) {
    return std::nullopt;
  }
  const fs::path path = *found;

  // STATISTICS FIRST. Without the sidecar the POM relief would be silently wrong and nobody
  // would see it, so a material with no readable sidecar is declined outright — PNG, which
  // measures them, is the better answer.
  const nlohmann::json* doc = baked_sidecar_locked(path);
  if (!doc) {
    return std::nullopt;
  }
  const auto maps_it = doc->find("maps");
  if (maps_it == doc->end() || !maps_it->is_object()) {
    lg::warn("baked recharged textures: sidecar for {} has no \"maps\" object — falling back",
             path.string());
    return std::nullopt;
  }
  const auto entry_it = maps_it->find(suffix.empty() ? std::string("base") : suffix);
  if (entry_it == maps_it->end() || !entry_it->is_object()) {
    // The file exists but the bake never described it: treat it as a MISS, not as a texture
    // with default statistics.
    lg::warn("baked recharged textures: {} is not described by its sidecar — falling back",
             path.string());
    return std::nullopt;
  }

  managed_assets::CompressedTex out;
  {
    std::ifstream f(path, std::ios::binary);
    if (!f) {
      lg::warn("baked recharged textures: cannot open {} — falling back to PNG", path.string());
      return std::nullopt;
    }
    f.seekg(0, std::ios::end);
    const std::streamoff len = f.tellg();
    f.seekg(0, std::ios::beg);
    if (len <= 0) {
      lg::warn("baked recharged textures: empty file {} — falling back to PNG", path.string());
      return std::nullopt;
    }
    out.payload.resize((size_t)len);
    f.read((char*)out.payload.data(), len);
    if (!f) {
      lg::warn("baked recharged textures: short read on {} — falling back to PNG", path.string());
      return std::nullopt;
    }
  }
  std::string err;
  if (!ktx2::parse(out.payload.data(), out.payload.size(), &out.info, &err)) {
    // A broken baked file must never produce a black texture: decline and let the PNG tier win.
    lg::error("baked recharged textures: bad ktx2 {}: {} — falling back to PNG", path.string(),
              err);
    return std::nullopt;
  }
  out.wrap_mode = "repeat";
  out.channels = baked_channels(suffix);

  const auto& e = *entry_it;
  if (e.contains("normal_dc_x") && e.contains("normal_dc_y")) {
    out.stats.has_normal_dc = true;
    out.stats.normal_dc_x = e.value("normal_dc_x", 0.f);
    out.stats.normal_dc_y = e.value("normal_dc_y", 0.f);
  }
  if (e.contains("height_mean") && e.contains("height_norm") &&
      e.contains("height_lambda_tiles")) {
    out.stats.has_height = true;
    out.stats.height_mean = e.value("height_mean", 0.5f);
    out.stats.height_norm = e.value("height_norm", 1.0f);
    out.stats.height_lambda_tiles = e.value("height_lambda_tiles", 0.25f);
  }

  lg::info("{} ({}): {} <- {}", log_what, kBakedProfile, exact_key, path.string());
  return out;
}

}  // namespace

std::optional<managed_assets::CompressedTex> lookup_baked_base(const std::string& tpage_name,
                                                               const std::string& tex_name) {
  // Same gate as the BUNDLED PNG base swap (lookup()): this tier replaces it.
  if (!recharged_gating::on(recharged_gating::kTextures)) {
    return std::nullopt;
  }
  return baked_load(tpage_name, tex_name, "", "custom texture BAKED");
}

bool baked_available() {
  if (!Gfx::recharged_master_active() || !baked_gpu_reads_astc()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_baked.mutex);
  ensure_baked_scanned_locked();
  return !g_baked.index.empty();
}


// ===== Grecharged-texture-hotreload ===========================================================
u32 hotreload_regime() {
  u32 r = 0;
  if (recharged_gating::on(recharged_gating::kLoadCustomAssets)) {
    r |= 1;
  }
  if (recharged_gating::on(recharged_gating::kTextures)) {
    r |= 2;
  }
  if (Gfx::recharged_master_active()) {
    r |= 4;
  }
  return r;
}

namespace {
// Nombre d'appels au SEUL ecrivain de `recharged_textures`, donc d'images GOAL depuis l'amorcage
// du pousseur `update-to-os`. Ces deux bornes ne sont pas des gouts : la premiere laisse le boot
// (chargement de GAME.fr3 + du premier niveau) se terminer sous le reglage REEL, la seconde
// laisse la passe de re-resolution declenchee par le premier basculement finir avant le second.
// A 19-30 images/s sur le Redmi, elles tombent vers 30-47 s et 80-126 s d'une course de 300 s ;
// a 60 images/s sur x86, vers 15 s et 40 s. DEUX transitions, pas une : la premiere peut tomber
// avant que le niveau vise soit resident (il serait alors televerse sous le nouveau regime, donc
// rien a re-resoudre), la seconde le trouve a coup sur.
constexpr uint64_t kHotreloadStimOff = 900;
constexpr uint64_t kHotreloadStimOn = 2400;
uint64_t g_htr_stim_calls = 0;
}  // namespace

bool hotreload_stimulus(bool on) {
  if (!autoport_proof::feature_is("recharged-texture-hotreload") || !autoport_proof::armed()) {
    return on;
  }
  const uint64_t n = ++g_htr_stim_calls;
  const bool forced = (n >= kHotreloadStimOff && n < kHotreloadStimOn);
  autoport_proof::publish("hotreload_stim_frames", n);
  autoport_proof::publish("hotreload_stim_forced", forced ? 1 : 0);
  return forced ? !on : on;
}

void invalidate() {
  g_state.scanned = false;
  g_state.user_index.clear();
  g_state.bundled_index.clear();
}

void dump_key(const std::string& tpage_name, const std::string& tex_name) {
  static std::set<std::string> s_seen;
  const auto dir = file_util::get_custom_assets_replacements_dir(g_game_version);
  const auto marker = dir.parent_path() / "dump_keys";
  if (!fs::exists(marker)) {
    return;
  }
  const std::string key = tpage_name + "/" + tex_name;
  if (!s_seen.insert(key).second) {
    return;
  }
  const auto out_path = dir.parent_path() / "texture_keys_dump.txt";
  std::ofstream ofs(out_path.string(), std::ios::app);
  if (ofs) {
    ofs << key << "\n";
  }
}

}  // namespace custom_tex
