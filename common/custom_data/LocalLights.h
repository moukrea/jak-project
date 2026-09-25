#pragma once

// lighting-local-lights (SPEC-refonte-lumiere §4.9, §5.3.8, §5.7.1) : les lumieres locales.
//
// Partage par l'outil hors ligne (tools/light_bake : extraction -> section LIGHTS du compagnon
// <niveau>.lightbake, recensement des candidats -> light_candidates.txt) et par le moteur (relit
// le lexique et les candidats pour publier le residu `lights_unjudged`, relit LIGHTS au
// chargement du niveau, remplit la grille de clusters sur le fil de rendu).

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace tfrag3 {
struct Level;
}

namespace local_lights {

enum class Type : uint8_t { Point = 0, Spot = 1, Area = 2 };
constexpr uint8_t kNoFlicker = 0xff;

// Une ligne LUMIERE du lexique.
struct Rule {
  std::string proto;
  Type type = Type::Point;
  bool rgb_auto = false;         // rgb=auto : moyenne des textures ponderee par la surface
  float rgb[3] = {1, 1, 1};      // 0..1 (le fichier porte 0..255)
  float cd = 1.f;                // intensite
  float r = 1.f;                 // rayon de coupure, metres
  bool has_off = false;          // off= : depuis le CENTRE DU BAS de la boite de l'instance
  float off[3] = {0, 0, 0};      // metres, axes du monde
  float cone_inner_deg = 0.f;    // type=spot seulement
  float cone_outer_deg = 0.f;
  uint8_t flicker = kNoFlicker;  // creneau de mood suivi, 0..7
};

struct Lexicon {
  std::unordered_map<std::string, Rule> lights;           // LUMIERE
  std::unordered_map<std::string, std::string> excluded;  // EXCLU -> raison
  int bad_lines = 0;  // lignes ni vides, ni commentaire, ni LUMIERE/EXCLU bien formees
  bool loaded = false;
  std::string path;
  bool judged(const std::string& proto) const {
    return lights.count(proto) != 0 || excluded.count(proto) != 0;
  }
};

// recharged_assets/light_emitters.txt, ou le depot externe s'il en porte un (meme regle que
// foliage_wind_protos.txt, common/custom_data/TFrag3Data.cpp fw_veg_protos()).
std::string default_lexicon_path();
Lexicon load_lexicon(const std::string& path);

// Le prototype porte-t-il un jeton d'emetteur (§5.3.8) : light, lite, lamp, lant, torch, glow,
// flame, candle, brazier, spotlight, neon. Sous-chaine, insensible a la casse.
bool is_candidate(const std::string& proto);

// Un emetteur extrait, espace MONDE, METRES.
struct Light {
  float pos[3] = {0, 0, 0};
  float radius = 1.f;
  float rgb[3] = {1, 1, 1};
  float intensity = 1.f;
  float dir[3] = {0, -1, 0};
  float cos_inner = 1.f;
  float cos_outer = 1.f;
  Type type = Type::Point;
  uint8_t flicker = kNoFlicker;
  uint8_t source = 1;  // 1 lexique, 2 jumeau -glow (rgb=auto), 3 source basse (lave)
  uint32_t proto_hash = 0;  // fnv1a 32 du nom de prototype
};

// Enregistrement serialise : 16 mots de 32 bits = 64 octets, petit-boutiste :
//   f32 pos[3], f32 radius, f32 rgb[3], f32 intensity, f32 dir[3], f32 cos_inner, f32 cos_outer,
//   u32 packed = type | flicker<<8 | source<<16, u32 proto_hash, u32 reserve(0)
// Corps de la section kSecLights : u32 count, puis count enregistrements. count = 0 est le corps
// qu'ecrivait lighting-bake (version 1) : il reste valide, aucune montee de version.
constexpr size_t kRecordBytes = 64;
void serialize(const std::vector<Light>& lights, std::vector<uint8_t>& out);
bool deserialize(const uint8_t* data, size_t size, std::vector<Light>& out);

struct ExtractStats {
  int instances_seen = 0;      // instances TIE parcourues
  int instances_lit = 0;       // instances d'un prototype LUMIERE
  int lights = 0;              // lumieres emises
  int protos_candidate = 0;    // prototypes distincts du niveau portant un jeton
  int protos_unjudged = 0;     // dont ni LUMIERE ni EXCLU
  std::vector<std::string> unjudged_names;
};

// §5.3.8 sources 1 et 2 sur un niveau fr3 charge : une lumiere par instance TIE d'un prototype
// LUMIERE du lexique.
std::vector<Light> extract(const tfrag3::Level& lev, const Lexicon& lex, ExtractStats* st);

// light_candidates.txt (ecrit par tools/light_bake --emitter-census, a cote des fr3) :
//   <proto> <instances> <NIV,NIV,...>      une ligne par prototype candidat, '#' = commentaire
struct Candidate {
  std::string proto;
  int instances = 0;
  std::string levels;
};
std::vector<Candidate> load_candidates(const std::string& path, bool* ok);

uint32_t fnv1a32(const std::string& s);

}  // namespace local_lights
